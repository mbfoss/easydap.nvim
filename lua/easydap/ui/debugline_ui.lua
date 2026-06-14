---@brief Singleton that shows the current execution position as a sign + line highlight.
---Tracks the active session; clears/moves the sign on stopped/continued/terminated.

local signs    = require("easydap.ui.signs")
local extmarks = require("easydap.ui.extmarks")
local manager  = require("easydap.manager")
local ui_utils = require("easydap.util.ui_util")
local config   = require("easydap.config")

local M = {}

local _init_done

---@type easydap.ui.signs.Group?
local _group
---@type easydap.ui.extmarks.GroupFunctions?
local _hl_group
local _sign_id = 1   -- fixed id: we only ever show one debugline sign at a time
local _gen     = 0   -- generation counter to guard stale session callbacks

local _LINE_HL = "EasytasksDebugLine"

local function _show_stopped(sess)
    if not _group or not _hl_group then return end
    local frame = sess:current_stack_frame()
    if not frame then return end
    local src = frame.source
    if not src or not src.path or src.path == "" then return end
    local lnum = frame.line or 1
    _group.set_file_sign(_sign_id, src.path, lnum, "debugline", nil)
    _hl_group.set_file_extmark(_sign_id, src.path, lnum, 0, { line_hl_group = _LINE_HL, hl_mode = "blend" }, nil)
    if sess.state_reason ~= "function call" then
        local col = frame.column and (frame.column - 1) or nil
        ui_utils.smart_open_file(src.path, lnum, col)
    end
end

local function _clear()
    if _group then _group.remove_signs() end
    if _hl_group then _hl_group.remove_extmarks() end
end

function M.init()
    if _init_done then return end
    _init_done = true

    vim.api.nvim_set_hl(0, _LINE_HL, { bg = ui_utils.auto_bg(0xD4A017) })

    _group    = signs.define_group("easydap_debugline", { priority = 20 })
    _hl_group = extmarks.define_group("easydap_debugline_hl", { priority = 20 })
    _group.define_sign("debugline", config.signs.debug_frame, "DiagnosticWarn")

    manager.on_active_changed:subscribe(function(_, sess)
        _clear()
        if not sess then return end

        _gen = _gen + 1
        local gen = _gen

        if sess.state == "stopped" then
            _show_stopped(sess)
        end

        sess:on("stopped", function()
            if gen ~= _gen then return end
            _clear()
            _show_stopped(sess)
        end)
        sess:on("continued", function()
            if gen ~= _gen then return end
            _clear()
        end)
        sess:on("terminated", function()
            if gen ~= _gen then return end
            _clear()
        end)
    end)

    manager.on_selection_changed:subscribe(function(_, sess)
        _clear()
        if sess then _show_stopped(sess) end
    end)
end

return M
