---@brief Standalone run panel for easydap.
---
---A single pinned bottom split that hosts the buffers a run registers (report,
---REPL, output, terminal, DAP messages) and pages between them through a
---clickable winbar. This is a trimmed standalone counterpart to easytasks'
---status panel: easydap has no dependency on easytasks, so it ships its own.
---
---The panel never steals focus. Buffers are owned by their producers; the panel
---only displays them. Newly added buffers auto-surface only when their priority
---is strictly higher than what is currently shown, so a busy view is not yanked
---away from the user. Per-buffer autoscroll keeps append-only logs pinned to the
---bottom while they are the active page.

local M = {}

---@class easydap.ui.PanelEntry
---@field bufnr      integer
---@field label      string
---@field priority   integer
---@field autoscroll boolean

---@class easydap.ui.Panel
---@field private _entries easydap.ui.PanelEntry[]  insertion order
---@field private _win      integer?                the panel window, when open
---@field private _active   integer?                bufnr currently displayed
---@field private _height   integer
---@field private _attached table<integer, boolean> buffers with an autoscroll listener
local Panel = {}
Panel.__index = Panel

local _DEFAULT_HEIGHT = 12

-- Winbar clicks call a global by name; route them to the panel that rendered the
-- bar. Only one run panel is shown at a time, so a single target suffices.
local _click_target ---@type easydap.ui.Panel?

---@param minwid integer  1-based entry index, encoded as the winbar item's minwid
function _G.EasydapPanelClick(minwid)
    if _click_target then _click_target:show_index(minwid) end
end

---@param opts? { height?: integer }
---@return easydap.ui.Panel
function M.new(opts)
    opts = opts or {}
    return setmetatable({
        _entries  = {},
        _win      = nil,
        _active   = nil,
        _height   = opts.height or _DEFAULT_HEIGHT,
        _attached = {},
    }, Panel)
end

-- ── Window ────────────────────────────────────────────────────────────────

---@return boolean
function Panel:is_open()
    return self._win ~= nil and vim.api.nvim_win_is_valid(self._win)
end

---Open the panel as a bottom split without stealing focus. No-op when already
---open. The first registered buffer (or an empty scratch) is shown.
function Panel:open()
    if self:is_open() then return end
    local cur = vim.api.nvim_get_current_win()
    vim.cmd("botright " .. self._height .. "split")
    self._win = vim.api.nvim_get_current_win()

    vim.wo[self._win].number         = false
    vim.wo[self._win].relativenumber = false
    vim.wo[self._win].winfixheight   = true
    vim.wo[self._win].wrap           = false

    local first = self._active or (self._entries[1] and self._entries[1].bufnr)
    if first then
        self:_set_buf(first)
    else
        self:_set_buf(vim.api.nvim_create_buf(false, true))
    end
    _click_target = self
    if vim.api.nvim_win_is_valid(cur) then vim.api.nvim_set_current_win(cur) end
end

---Close the panel window. Hosted buffers persist; reopening restores them.
function Panel:close()
    if self:is_open() then vim.api.nvim_win_close(self._win, false) end
    self._win = nil
    if _click_target == self then _click_target = nil end
end

-- ── Buffer display ────────────────────────────────────────────────────────

---Display `bufnr` in the panel window and refresh the winbar. Pins terminal and
---autoscroll buffers to their last line.
---@param bufnr integer
function Panel:_set_buf(bufnr)
    if not self:is_open() or not vim.api.nvim_buf_is_valid(bufnr) then return end
    vim.api.nvim_win_set_buf(self._win, bufnr)
    self._active = bufnr
    self:_attach(bufnr)
    if vim.bo[bufnr].buftype == "terminal" then
        pcall(vim.api.nvim_win_set_cursor, self._win, { vim.api.nvim_buf_line_count(bufnr), 0 })
    end
    self:_render_winbar()
end

---@param bufnr integer
---@return easydap.ui.PanelEntry?
function Panel:_entry(bufnr)
    for _, e in ipairs(self._entries) do
        if e.bufnr == bufnr then return e end
    end
end

---Attach a one-shot autoscroll listener that keeps `bufnr` at its last line
---while it is the active page (only for entries that asked for autoscroll).
---@param bufnr integer
function Panel:_attach(bufnr)
    if self._attached[bufnr] then return end
    local entry = self:_entry(bufnr)
    if not entry or not entry.autoscroll then return end
    self._attached[bufnr] = true
    vim.api.nvim_buf_attach(bufnr, false, {
        on_lines = function()
            if not self:is_open() then return true end
            if vim.api.nvim_win_get_buf(self._win) ~= bufnr then return end
            vim.schedule(function()
                if not self:is_open() then return end
                if vim.api.nvim_win_get_buf(self._win) ~= bufnr then return end
                pcall(vim.api.nvim_win_set_cursor, self._win, { vim.api.nvim_buf_line_count(bufnr), 0 })
            end)
        end,
        on_detach = function() self._attached[bufnr] = nil end,
    })
end

---Render the tab bar: one clickable label per entry, highest priority first,
---with the active page highlighted.
function Panel:_render_winbar()
    if not self:is_open() then return end
    local order = self:_ordered()
    local parts = {}
    for i, e in ipairs(order) do
        local hl = e.bufnr == self._active and "%#TabLineSel#" or "%#TabLine#"
        parts[#parts + 1] = ("%%%d@v:lua.EasydapPanelClick@%s %s %%X"):format(i, hl, e.label)
    end
    vim.wo[self._win].winbar = table.concat(parts) .. "%#TabLineFill#"
end

---Entries ordered for display: highest priority first, ties in insertion order.
---@return easydap.ui.PanelEntry[]
function Panel:_ordered()
    local order = vim.list_extend({}, self._entries)
    table.sort(order, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return false -- stable: equal priorities keep insertion order
    end)
    return order
end

-- ── Public API ─────────────────────────────────────────────────────────────

---Register a buffer with the panel and surface it when warranted. Opens the
---panel on the first buffer. A buffer added with a strictly higher priority than
---the current page is switched to; otherwise it only joins the winbar.
---@param bufnr      integer
---@param label?     string
---@param priority?  integer  higher = surfaced preferentially (default 0)
---@param autoscroll? boolean keep pinned to the last line while active
function Panel:add(bufnr, label, priority, autoscroll)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    local existing = self:_entry(bufnr)
    if existing then
        existing.label, existing.priority = label or existing.label, priority or existing.priority
    else
        self._entries[#self._entries + 1] = {
            bufnr      = bufnr,
            label      = label or vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t"),
            priority   = priority or 0,
            autoscroll = autoscroll or false,
        }
        vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
            buffer = bufnr, once = true,
            callback = function() self:remove(bufnr) end,
        })
    end

    local was_open  = self:is_open()
    self:open()
    -- Surface the new buffer when nothing meaningful is shown yet (fresh panel /
    -- empty scratch) or when it outranks the current page; otherwise just list it.
    local cur_entry = self._active and self:_entry(self._active)
    if not was_open or self._active == bufnr or not cur_entry then
        self:_set_buf(bufnr)
    elseif (priority or 0) > cur_entry.priority then
        self:_set_buf(bufnr)
    else
        self:_render_winbar()
    end
end

---Forget all hosted buffers (they are not deleted) and show an empty page, so a
---new run does not inherit the previous run's pages. Pending BufDelete autocmds
---for the dropped buffers are harmless: remove() simply finds nothing.
function Panel:reset()
    self._entries  = {}
    self._attached = {}
    self._active   = nil
    if self:is_open() then
        self:_set_buf(vim.api.nvim_create_buf(false, true))
    end
end

---Show the i-th entry in display (priority) order. Used by the winbar.
---@param i integer
function Panel:show_index(i)
    local order = self:_ordered()
    local e = order[i]
    if e then self:_set_buf(e.bufnr) end
end

---Drop a buffer from the panel. If it was showing, fall back to the next entry.
---@param bufnr integer
function Panel:remove(bufnr)
    for i, e in ipairs(self._entries) do
        if e.bufnr == bufnr then
            table.remove(self._entries, i)
            break
        end
    end
    self._attached[bufnr] = nil
    if self._active == bufnr then
        self._active = nil
        local nxt = self._entries[1]
        if nxt and self:is_open() then
            self:_set_buf(nxt.bufnr)
        elseif self:is_open() then
            self:_set_buf(vim.api.nvim_create_buf(false, true))
        end
    elseif self:is_open() then
        self:_render_winbar()
    end
end

return M
