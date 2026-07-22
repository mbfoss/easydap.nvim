---@brief Active session manager.
---Owns the "which session is active" concept that keymaps and UI subscribe to,
---and exposes the session-control primitives built on it. The DAP client
---(dap/client.lua) is session-id-explicit; this module wraps it with the
---active-session notion. The user-facing command surface lives in command.lua.

local client            = require("ezdap.dap.client")
local Signal            = require("ezdap.tk.Signal")

local M                 = {}

-- Re-exported client signals
-- Consumers import only manager; client is an implementation detail.

M.on_session_added      = client
    .on_session_added ---@type ezdap.tk.Signal<fun(id:number, sess:ezdap.dap.Session, info:ezdap.client.SessionInfo)>
M.on_session_removed    = client.on_session_removed ---@type ezdap.tk.Signal<fun(id:number)>
M.on_session_updated    = client
    .on_session_updated ---@type ezdap.tk.Signal<fun(id:number, info:ezdap.client.SessionInfo)>
M.on_session_stopped    = client
    .on_session_stopped ---@type ezdap.tk.Signal<fun(id:number, info:ezdap.client.SessionInfo)>
M.on_raw_message        = client
    .on_raw_message ---@type ezdap.tk.Signal<fun(id:number, direction:"in"|"out", msg:table)>
M.on_variable_changed   = client
    .on_variable_changed ---@type ezdap.tk.Signal<fun(id:number, sess:ezdap.dap.Session)>
M.on_breakpoint_updated = client
    .on_breakpoint_updated ---@type ezdap.tk.Signal<fun(id:number, bp:table, status:ezdap.dap.BpStatus)>

---@param id number
---@return ezdap.dap.Session?
function M.get_session(id) return client.get_session(id) end

---@return table<number, ezdap.dap.Session>
function M.sessions() return client.sessions() end

---@param config ezdap.dap.Config
---@param callbacks? ezdap.client.Callbacks
function M.start(config, callbacks) return client.start(config, callbacks) end

-- Active session

---Fires when the active (stepping) session changes: (id?, sess?)
M.on_active_changed    = Signal.new() ---@type ezdap.tk.Signal<fun(id:number?, sess:ezdap.dap.Session?)>
---Fires when thread or frame selection changes in the active session: (id, sess)
M.on_selection_changed = Signal.new() ---@type ezdap.tk.Signal<fun(id:number, sess:ezdap.dap.Session)>

---@type number?
local _active_id       = nil

---@param id number?
local function _set_active(id)
    if _active_id == id then return end
    _active_id = id
    M.on_active_changed:emit(id, id and client.get_session(id) or nil)
end

-- forward selection changes from the active session only
client.on_selection_changed:subscribe(function(id, sess)
    if id == _active_id then M.on_selection_changed:emit(id, sess) end
end)

-- auto-promote: new session → active
client.on_session_added:subscribe(function(id)
    _set_active(id)
end)

-- auto-promote: a session stopped → bring it into focus
client.on_session_stopped:subscribe(function(id)
    _set_active(id)
end)

-- auto-reassign: active session removed → pick any remaining, or nil
client.on_session_removed:subscribe(function(id)
    if _active_id ~= id then return end
    local new_id
    for k in pairs(client.sessions()) do
        new_id = k; break
    end
    _set_active(new_id)
end)

---@return ezdap.dap.Session?
function M.session()
    return _active_id and client.get_session(_active_id) or nil
end

---Return the active session's adapter-verified status for a breakpoint, or nil if no session.
---@param bp_id integer  internal stable id (bp.internal_id)
---@return ezdap.dap.BpStatus?
function M.bp_status(bp_id)
    local sess = M.session()
    return sess and sess:bp_status(bp_id)
end

---@return number?
function M.active_id()
    return _active_id
end

---Manually promote a session to the active slot.
---@param id number
function M.select_session(id)
    if client.get_session(id) then _set_active(id) end
end

-- Stepping (delegate to client with active id)

---Granularity used for subsequent steps. Derived from the focused buffer:
---instruction while the disassembly pane is current, line everywhere else.
---@return ezdap.dap.proto.SteppingGranularity
function M.granularity()
    if vim.b.ezdap_disasm then return "instruction" end
    return "line"
end

---Run `fn(sess)` on the active session, but only if it advertises `capability`.
---Shows an error when the adapter lacks the capability, a warning when there is
---no active session. Use for any user command gated on a DAP capability.
---@param capability string  e.g. "supportsRestartFrame"
---@param label      string  human-readable command name for the error message
---@param fn         fun(sess: ezdap.dap.Session, id: number)
function M.with_capability(capability, label, fn)
    local id = _active_id
    if not id then return end
    local sess = M.session()
    if not sess then
        vim.notify("[dap] no active session", vim.log.levels.WARN); return
    end
    if not sess:capable(capability) then
        vim.notify("[dap] adapter does not support " .. label, vim.log.levels.ERROR)
        return
    end
    fn(sess, id)
end

function M.continue() if _active_id then client.continue(_active_id) end end

function M.next() if _active_id then client.next(_active_id, M.granularity()) end end

function M.step_in() if _active_id then client.step_in(_active_id, M.granularity()) end end

function M.step_out() if _active_id then client.step_out(_active_id, M.granularity()) end end

function M.step_back()
    M.with_capability("supportsStepBack", "step back", function(_, id)
        client.step_back(id, M.granularity())
    end)
end

function M.reverse_continue()
    M.with_capability("supportsStepBack", "reverse continue", function(_, id)
        client.reverse_continue(id)
    end)
end

function M.pause() if _active_id then client.pause(_active_id) end end

function M.restart()
    M.with_capability("supportsRestartRequest", "restart", function(_, id)
        client.restart(id)
    end)
end

---@param cb fun()?
function M.stop(cb) if _active_id then client.stop(_active_id, cb) end end

---@param cb fun()?
function M.disconnect(cb) if _active_id then client.disconnect(_active_id, cb) end end

---@param thread_id integer
function M.select_thread(thread_id)
    if _active_id then client.select_thread(_active_id, thread_id) end
end

---@param frame_id integer
function M.select_frame(frame_id)
    if _active_id then client.select_frame(_active_id, frame_id) end
end

---@param text   string
---@param column integer
---@param cb     fun(targets: table[])
function M.complete(text, column, cb)
    if not _active_id then
        cb({}); return
    end
    client.complete(_active_id, text, column, cb)
end

---@param expr    string
---@param context string
---@param cb      fun(body: table?, err: string?)
function M.evaluate(expr, context, cb)
    if not _active_id then
        cb(nil, "no active session"); return
    end
    client.evaluate(_active_id, expr, context, cb)
end

return M
