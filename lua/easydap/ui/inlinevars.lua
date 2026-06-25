local M            = {}

local str_util     = require("easydap.util.str_util")
local manager      = require("easydap.manager")
local config       = require("easydap.config")
local extmarks     = require("easydap.ui.extmarks")
local ui_util      = require("easydap.util.ui_util")

local _group       = extmarks.define_group("inlinevars", { priority = 100 })
local _seq         = 0
local _max_size    = 30
local _enabled     = true
local _gen         = 0
local _unsub
local _unsub_var
local _mark_id     = 0
local _clear_timer = nil

ui_util.define_themed_hl("EasydapPill", function()
	return { link = "Visual", default = true }
end)

ui_util.define_themed_hl("EasydapPillSep", function()
	vim.api.nvim_set_hl(0, "EasydapPill", { link = "Visual", default = true })
	local hl = vim.api.nvim_get_hl(0, { name = "EasydapPill", link = false })
	return {
		fg = hl.bg or hl.fg,
		bg = "NONE",
	}
end)

local function _cancel_clear_timer()
	if _clear_timer then
		_clear_timer:stop()
		_clear_timer:close()
		_clear_timer = nil
	end
end

local function _clear()
	_cancel_clear_timer()
	_mark_id = 0
	_group.remove_extmarks()
end

local function _deferred_clear(delay_ms)
	_cancel_clear_timer()
	local t = vim.uv.new_timer()
	if not t then return end
	_clear_timer = t
	t:start(delay_ms, 0, vim.schedule_wrap(function()
		_cancel_clear_timer()
		_mark_id = 0
		_group.remove_extmarks()
	end))
end

---@param file string
---@param row number  -- 0-based
---@param col number  -- 0-based
---@param text string
local function _set_extmark(file, row, col, text)
	text = vim.trim(text)
	if text == "" then return end
	_mark_id = _mark_id + 1
	_group.set_file_extmark(_mark_id, file, row + 1, col, {
		virt_text = {
			{ " " },
			{ "\u{E0B6}", "EasydapPillSep" },
			{ text,       "EasydapPill" },
			{ "\u{E0B4}", "EasydapPillSep" },
		},
		virt_text_pos = "inline",
		hl_mode = "combine",
	}, nil)
end

local function _render_variables(frame, variables)
	if not frame or not frame.source or not frame.source.path then return end

	local path = frame.source.path
	local bufnr = vim.fn.bufnr(path)
	if bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr) then return end

	local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
	if not lang then return end

	local parser_ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
	if not (parser_ok and parser) then return end

	local tree = parser:parse()[1]
	if not tree then return end

	local root = tree:root()

	local dbg = {}
	for _, v in ipairs(variables or {}) do
		if v.name and v.value then
			dbg[v.name] = vim.trim(v.value)
		end
	end

	if vim.tbl_isempty(dbg) then return end

	local target_row = (frame.line or 1) - 1

	-- the locals query defines scope boundaries; without it we cannot tell a
	-- local variable from an unrelated identifier, so skip rather than guess
	local locals_query = vim.treesitter.query.get(lang, "locals")
	if not locals_query then return end

	-- narrow to the innermost scope containing the frame line
	local scope_node = root
	for id, node in locals_query:iter_captures(root, bufnr) do
		if locals_query.captures[id] == "scope" then
			local sr, _, er, _ = node:range()
			if sr <= target_row and target_row <= er then
				local cur_sr, _, cur_er, _ = scope_node:range()
				if (er - sr) < (cur_er - cur_sr) then
					scope_node = node
				end
			end
		end
	end

	-- pre-collect direct child scopes so the walk does not descend into them
	local _child_scopes = {}
	for id, node in locals_query:iter_captures(scope_node, bufnr) do
		if locals_query.captures[id] == "scope" and node ~= scope_node then
			_child_scopes[node:id()] = true
		end
	end

	-- collect every occurrence of each variable name within the current scope only
	---@type table<string, {sr:number, ec:number}[]>
	local occurrences = {}

	local function walk(node)
		if not node then return end
		if _child_scopes[node:id()] then return end

		local node_type = node:type()
		if node_type == "identifier" and node:parent() then
			local name = vim.treesitter.get_node_text(node, bufnr)
			if dbg[name] then
				local sr, _, _, ec = node:range()
				occurrences[name] = occurrences[name] or {}
				occurrences[name][#occurrences[name] + 1] = { sr = sr, ec = ec }
			end
		end

		for child in node:iter_children() do
			walk(child)
		end
	end

	walk(scope_node)

	-- place each annotation on the occurrence closest to the current execution line
	for name, positions in pairs(occurrences) do
		local best, best_dist = nil, math.huge
		for _, pos in ipairs(positions) do
			local dist = math.abs(pos.sr - target_row)
			if dist < best_dist then
				best_dist = dist
				best = pos
			end
		end
		if best then
			local text = str_util.crop_for_ui(tostring(dbg[name]), _max_size)
			_set_extmark(path, best.sr, best.ec, text)
		end
	end
end

-- Inline annotations should reflect what is in lexical scope at the current
-- frame, so restrict to the locals/arguments scopes and skip globals,
-- statics, registers, etc. Prefer the adapter's presentationHint and fall
-- back to the scope name when it is omitted.
---@param scope easydap.dap.proto.Scope
---@return boolean
local function _is_local_scope(scope)
	local hint = scope.presentationHint
	if hint then
		return hint == "locals" or hint == "arguments"
	end
	local name = (scope.name or ""):lower()
	return name:find("local", 1, true) ~= nil or name:find("argument", 1, true) ~= nil
end

---@param session easydap.dap.Session
---@param frame table
---@param cb function
local function _collect_variables(session, frame, cb)
	local scopes = frame.scopes
	if not scopes then
		return session:fetch_scopes(frame, function()
			_collect_variables(session, frame, cb)
		end)
	end

	local vars = {}
	local pending = 0

	for _, scope in ipairs(scopes) do
		if _is_local_scope(scope) and scope.variablesReference and scope.variablesReference ~= 0 then
			pending = pending + 1

			session:fetch_variables(scope, function()
				if scope.variables then
					vim.list_extend(vars, scope.variables)
				end

				pending = pending - 1
				if pending == 0 then
					cb(vars)
				end
			end)
		end
	end

	if pending == 0 then
		cb(vars)
	end
end

local function _update(session, frame)
	if not _enabled then return end
	if not frame or not frame.source or not frame.source.path then return end

	_seq = _seq + 1
	local my_seq = _seq

	_collect_variables(session, frame, function(vars)
		if my_seq ~= _seq then return end

		_cancel_clear_timer()
		_clear()
		_render_variables(frame, vars)
	end)
end

function M.clear()
	_clear()
end

function M.enable(v)
	_enabled = v ~= false
	if not _enabled then
		_clear()
	end
	if _enabled and not _unsub then
		_unsub_var = manager.on_variable_changed:subscribe(function(_, sess)
			vim.schedule(function()
				local frame = sess:current_stack_frame()
				_update(sess, frame)
			end)
		end)

		_unsub = manager.on_active_changed:subscribe(function(_, sess)
			_clear()
			if not sess then return end

			_gen = _gen + 1
			local gen = _gen

			if sess.state == "stopped" then
				local frame = sess:current_stack_frame()
				_update(sess, frame)
			end

			sess:on("stopped", function()
				if gen ~= _gen then return end
				local frame = sess:current_stack_frame()
				_update(sess, frame)
			end)
			sess:on("continued", function()
				if gen ~= _gen then return end
				_deferred_clear(config.antiflicker_delay)
			end)
			sess:on("terminated", function()
				if gen ~= _gen then return end
				_clear()
			end)
		end)
	end

	if not _enabled and _unsub then
		_unsub()
		_unsub = nil
		if _unsub_var then
			_unsub_var(); _unsub_var = nil
		end
	end
end

return M
