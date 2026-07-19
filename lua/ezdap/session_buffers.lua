---@brief Registry of the buffers a run attached to its sessions.
---
---A run spawns buffers (REPL, Output, Terminal, DAP messages, adapter logs) and
---may produce several sessions; `ezdap.task` registers the run's buffers against
---each of them here, so the debug view can list a session's buffers and open one.
---Entries are held by session id and pruned once their buffer is gone.

local Signal = require("ezdap.tk.Signal")

---One buffer a run attached to a session, as registered via `ezdap.AddBufOpts`.
---@class ezdap.SessionBuffer
---@field bufnr    integer
---@field label    string
---@field priority integer

local M          = {}

---@type table<integer, ezdap.SessionBuffer[]>
local _by_id     = {}

---Fires with the session whose buffer list changed.
M.on_changed     = Signal.new() ---@type ezdap.tk.Signal<fun(session_id:integer)>

---@param entries ezdap.SessionBuffer[]
---@return ezdap.SessionBuffer[]
local function _live(entries)
    local out = {}
    for _, e in ipairs(entries) do
        if vim.api.nvim_buf_is_valid(e.bufnr) then out[#out + 1] = e end
    end
    return out
end

---Attach `entries` to a session, replacing its previous list. The registry keeps
---its own copy, so callers may keep appending to theirs and call `set` again.
---@param session_id integer
---@param entries ezdap.SessionBuffer[]
function M.set(session_id, entries)
    _by_id[session_id] = vim.deepcopy(entries)

    -- Drop sessions whose buffers have all been wiped; nothing signals their end
    -- to us, and a finished run's buffers are deleted together.
    for id, list in pairs(_by_id) do
        if id ~= session_id and #_live(list) == 0 then _by_id[id] = nil end
    end

    M.on_changed:emit(session_id)
end

---The session's buffers, in registration order, minus any that no longer exist.
---@param session_id integer
---@return ezdap.SessionBuffer[]
function M.get(session_id)
    return _live(_by_id[session_id] or {})
end

return M
