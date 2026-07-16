---@brief run_file scaffolding for `:Debug new_run_file`.
---
---Writes a runnable Lua run_file for an adapter + one of its `configurations` by
---splicing that configuration's `template` — Lua source text for a native request
---body, seeded with example values — into a task table. The template is the only
---thing this module reads, and it is source rather than data, so the adapter
---already wrote the comments, key order and computed expressions that belong in
---the generated file; there is nothing to render, only to re-indent. A run file's
---`parameters` goes to the adapter verbatim (see `easydap.task`), so it never
---passes through the configuration's `build`, which serves `quick_run` alone.

local schema = require("easydap.schema")

local M = {}

---@param msg string
local function _warn(msg) vim.notify("[easydap] " .. msg, vim.log.levels.WARN) end

---@param msg string
local function _err(msg) vim.notify("[easydap] " .. msg, vim.log.levels.ERROR) end

---Re-indent a configuration's `template` to sit at `indent` spaces inside the
---generated run file. Surrounding blank lines are dropped and the template's own
---common leading indent is stripped, so an adapter can write its template at
---whatever indentation reads best in the adapter file and still have it land
---correctly nested here. Blank lines within stay blank rather than collecting
---trailing whitespace.
---@param template string
---@param indent integer
---@return string
local function _reindent(template, indent)
    local lines = vim.split(template, "\n", { plain = true })
    while lines[1] and lines[1]:match("^%s*$") do table.remove(lines, 1) end
    while #lines > 0 and lines[#lines]:match("^%s*$") do table.remove(lines) end

    local common = math.huge
    for _, line in ipairs(lines) do
        if not line:match("^%s*$") then
            common = math.min(common, #line:match("^ *"))
        end
    end
    if common == math.huge then common = 0 end

    local pad, out = string.rep(" ", indent), {}
    for i, line in ipairs(lines) do
        out[i] = line:match("^%s*$") and "" or (pad .. line:sub(common + 1))
    end
    return table.concat(out, "\n")
end

---Scaffold a run_file for an `adapter` + one of its `configurations`: write a Lua
---file whose `parameters` is that configuration's `template` source, then open it
---for editing. Run it afterwards with `:Debug run_file`. `assignments` is positional:
---the adapter (required), the configuration name (defaults to the adapter's sole
---configuration), then the destination path (defaulting to `<project
---root or cwd>/<adapter>_<configuration>.lua`). Fails if the destination already
---exists, rather than overwriting or picking a different name. Reports a clear
---error for every failure mode instead of throwing.
---@param assignments string[]  positional adapter, configuration, path, e.g. { "codelldb", "launch", "./foo.lua" }
---@return string? path  the file that was created
function M.new_run_file(assignments)
    -- Every argument is positional: `new_run_file <adapter> [configuration] [path]`.
    local adapter, configuration_name, path
    for _, tok in ipairs(assignments or {}) do
        if not adapter then
            adapter = tok
        elseif not configuration_name then
            configuration_name = tok
        elseif not path then
            path = tok
        else
            _warn("new_run_file: unexpected argument '" .. tok ..
                "' (usage: new_run_file <adapter> [configuration] [path])")
            return
        end
    end

    if not adapter or adapter == "" then
        _warn("new_run_file: usage: new_run_file <adapter> [configuration] [path]")
        return
    end
    local base = require("easydap.adapters")[adapter]
    if not base then
        _err("new_run_file: unknown adapter: " .. adapter ..
            " (available: " .. table.concat(schema.configurable_adapters(), ", ") .. ")")
        return
    end

    -- Resolve the configuration: given, else the adapter's sole configuration — reject an
    -- adapter that declares none, or an ambiguous choice among several.
    local names = schema.configuration_names(adapter)
    if #names == 0 then
        _err("new_run_file: adapter " .. adapter .. " declares no configurations")
        return
    end
    if configuration_name and configuration_name ~= "" then
        if not vim.tbl_contains(names, configuration_name) then
            _err(("new_run_file: adapter %s has no configuration %q (available: %s)")
                :format(adapter, configuration_name, table.concat(names, ", ")))
            return
        end
    elseif #names == 1 then
        configuration_name = names[1]
    else
        _err(("new_run_file: adapter %s has multiple configurations, pick one (available: %s)")
            :format(adapter, table.concat(names, ", ")))
        return
    end
    local configuration = assert(schema.configuration(adapter, configuration_name))

    -- Resolve the destination; fail rather than clobber or rename an existing file.
    local root = require("easydap.store").root() or vim.fn.getcwd()
    local dest = (path and path ~= "") and vim.fn.fnamemodify(vim.fn.expand(path), ":p")
        or vim.fs.joinpath(root, adapter .. "_" .. configuration_name .. ".lua")
    if not dest:match("%.lua$") then dest = dest .. ".lua" end
    if vim.uv.fs_stat(dest) then
        _err("new_run_file: file already exists: " .. dest)
        return
    end

    local params_src = _reindent(configuration.template or "", 8)

    local lines = {
        "-- easydap run file",
        "return {",
        ("    name       = %q,"):format(adapter),
        ("    adapter    = %q,"):format(adapter),
        ("    request    = %q,"):format(configuration.request),
    }
    -- TCP adapters carry host/port at the task level, not in the body; seed them
    -- from the adapter's own def, which is what `build`'s `connect` overrides.
    if base.host ~= nil or base.port ~= nil then
        lines[#lines + 1] = ("    host       = %q,"):format(base.host or "127.0.0.1")
        lines[#lines + 1] = ("    port       = %d,"):format(base.port or 0)
    end
    -- A configuration with nothing to seed (its inputs are all task-level) gets an
    -- empty body rather than a `{` / blank line / `}` sandwich.
    if params_src == "" then
        lines[#lines + 1] = "    parameters = {},"
    else
        vim.list_extend(lines, { "    parameters = {", params_src, "    }," })
    end
    vim.list_extend(lines, { "}", "" })

    local ok, werr = require("easydap.tk.fsutil").write_content(dest, table.concat(lines, "\n"))
    if not ok then
        _err("new_run_file: failed to write " .. dest .. ": " .. tostring(werr))
        return
    end
    require("easydap.util.ui_util").smart_open_file(vim.fn.fnameescape(dest))
    return dest
end

return M
