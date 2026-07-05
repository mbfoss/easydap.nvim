---@brief Task-file scaffolding for `:Debug new_task`.
---
---Writes a runnable Lua run_file for an `adapter` + `request`, pre-populating its
---`parameters` from the adapter's launch/attach schema (fixed values, defaults, and
---type-appropriate placeholders for the rest, each annotated with its description).
---It renders the schema — read via `easydap.schema` — into Lua source; the DAP core
---and body assembly stay in `easydap.schema`.

local schema = require("easydap.schema")

local M = {}

---@param msg string
local function _warn(msg) vim.notify("[easydap] " .. msg, vim.log.levels.WARN) end

---@param msg string
local function _err(msg) vim.notify("[easydap] " .. msg, vim.log.levels.ERROR) end

---A blank value of the shape `spec` expects, used to seed a template entry the
---caller has no default for (so the generated file is valid Lua to edit).
---@param spec easydap.ParamSpec
---@return any
local function _placeholder(spec)
    if spec.role == "args" then return {} end
    local k = spec.kind
    if k == "list" or k == "env" then return {} end
    if k == "enum" then return (spec.enum and spec.enum[1]) or "" end
    if k == "port" then return 0 end
    local t = spec.type
    if t == "boolean" then return false end
    if t == "integer" or t == "number" then return 0 end
    if t == "table" then return {} end
    return "" -- string / file / dir / host + target role
end

---Render an adapter's request schema as the body of a Lua `parameters` table — a
---multi-line source string for a run_file template (see `new_task`). Each leaf
---param is emitted on its own line, seeded with its resolved default or a
---type-appropriate placeholder, with a trailing `-- desc` comment; nested groups
---are rendered inline. `indent` is the column (in spaces) the outermost params sit
---at. Keys are sorted for stable output.
---@param adapter string
---@param request string
---@param indent integer
---@return string? lua, string? err
local function _render_params(adapter, request, indent)
    local sch = schema.schema(adapter, request)
    if not sch then
        return nil, ("adapter %s has no %s schema"):format(tostring(adapter), tostring(request))
    end
    local lines = {}
    local function emit(group, pad)
        local fields = schema.group_fields(group)
        local keys = {}
        for k in pairs(fields) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local node = fields[k]
            -- Bare identifier keys stay unquoted; anything else needs ["..."].
            local lhs = k:match("^[%a_][%w_]*$") and k or ("[%q]"):format(k)
            if schema.is_group(node) then
                lines[#lines + 1] = ("%s%s = {"):format(pad, lhs)
                emit(node, pad .. "    ")
                lines[#lines + 1] = ("%s},"):format(pad)
            else
                local val     = (node.fixed or node.default ~= nil) and schema.resolve_default(node)
                    or _placeholder(node)
                local line    = ("%s%s = %s,"):format(pad, lhs, vim.inspect(val))
                local comment = node.desc
                if node.fixed then comment = comment and (comment .. " (fixed)") or "fixed" end
                if comment then line = line .. "  -- " .. comment end
                lines[#lines + 1] = line
            end
        end
    end
    emit(sch, string.rep(" ", indent))
    return table.concat(lines, "\n")
end

---Scaffold a run_file for `adapter` + `request`: write a Lua file that returns a
---task table whose `parameters` are pre-populated from the adapter's schema (fixed
---values, defaults, and type-appropriate placeholders for the rest, each annotated
---with its description), then open it for editing. Run it afterwards with `:Debug
---run_file`. `path` defaults to `<project root or cwd>/<adapter>_<request>.lua`,
---uniquified so an existing file is never clobbered. Reports a clear error for
---every failure mode instead of throwing.
---@param adapter string
---@param request string?
---@param path string?
---@return string? path  the file that was created
function M.new_task(adapter, request, path)
    if not adapter or adapter == "" then
        _warn("new_task: usage: new_task <adapter> [request] [path]")
        return
    end
    local base = require("easydap.adapters")[adapter]
    if not base then
        _err("new_task: unknown adapter: " .. adapter ..
            " (available: " .. table.concat(schema.adapter_names(), ", ") .. ")")
        return
    end

    -- Resolve the request: given, else the adapter's DAP default, else its sole
    -- schema — then reject anything the adapter has no schema for.
    local supported = schema.requests(adapter)
    if #supported == 0 then
        _err("new_task: adapter " .. adapter .. " declares no launch/attach schema")
        return
    end
    request = (request and request ~= "") and request or (base.request or "launch")
    if not vim.tbl_contains(supported, request) then
        if #supported == 1 then
            request = supported[1]
        else
            _err(("new_task: adapter %s has no %s schema (supports: %s)")
                :format(adapter, request, table.concat(supported, ", ")))
            return
        end
    end

    -- Resolve the destination and uniquify so we never overwrite an existing file.
    local root = require("easydap.store").root() or vim.fn.getcwd()
    local dest = (path and path ~= "") and vim.fn.fnamemodify(vim.fn.expand(path), ":p")
        or vim.fs.joinpath(root, adapter .. "_" .. request .. ".lua")
    if not dest:match("%.lua$") then dest = dest .. ".lua" end
    do
        local stem, n = (dest:gsub("%.lua$", "")), 1
        while vim.uv.fs_stat(dest) do
            dest = ("%s_%d.lua"):format(stem, n)
            n = n + 1
        end
    end

    local params_src, perr = _render_params(adapter, request, 8)
    if not params_src then
        _err("new_task: " .. tostring(perr))
        return
    end

    local lines = {
        ("-- easydap task — %s (%s)"):format(adapter, request),
        "-- Edit the parameters, then run with:  :Debug run_file " .. vim.fn.fnamemodify(dest, ":~:."),
        "return {",
        ("    name       = %q,"):format(adapter),
        ("    adapter    = %q,"):format(adapter),
        ("    request    = %q,"):format(request),
    }
    -- TCP adapters carry host/port at the task level, not in the body; seed them.
    if base.host ~= nil or base.port ~= nil then
        lines[#lines + 1] = ("    host       = %q,"):format(base.host or "127.0.0.1")
        lines[#lines + 1] = ("    port       = %d,"):format(base.port or 0)
    end
    vim.list_extend(lines, { "    parameters = {", params_src, "    },", "}", "" })

    local ok, werr = require("easydap.tk.fsutil").write_content(dest, table.concat(lines, "\n"))
    if not ok then
        _err("new_task: failed to write " .. dest .. ": " .. tostring(werr))
        return
    end
    vim.cmd.edit(vim.fn.fnameescape(dest))
    vim.notify("[easydap] created task file: " .. dest, vim.log.levels.INFO)
    return dest
end

return M
