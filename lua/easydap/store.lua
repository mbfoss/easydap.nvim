---@brief Standalone JSON persistence for easydap.nvim.
---Data lives in stdpath('data')/easydap/<namespace>.json.
---Not project-scoped: persisted globally across sessions.

local M = {}

local fsutil = require("easydap.util.fsutil")

local _dir = vim.fn.stdpath("data") .. "/easydap"

---@param namespace string
---@return string
local function _path(namespace)
    return _dir .. "/" .. namespace .. ".json"
end

local function _ensure_dir()
    if not fsutil.dir_exists(_dir) then
        fsutil.make_dir(_dir)
    end
end

---Load a namespace from disk.
---@param namespace string
---@return table|nil
function M.get(namespace)
    local ok, content = fsutil.read_content(_path(namespace))
    if not ok then return nil end
    local decoded_ok, data = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
    if not decoded_ok then return nil end
    return data
end

---Persist a namespace to disk.
---@param namespace string
---@param data table
---@return boolean ok
---@return string? err
function M.set(namespace, data)
    _ensure_dir()
    local ok, json_or_err = pcall(vim.json.encode, data)
    if not ok then
        return false, "json encode failed: " .. tostring(json_or_err)
    end
    return fsutil.write_content(_path(namespace), json_or_err)
end

return M
