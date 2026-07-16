---@brief Schema engine behind `:Debug new_run_file` and `:Debug quick_run`.
---
---Adapters carry no launch/attach schema of their own — each adapter's
---`configurations` (named `easydap.Configuration` templates, in `easydap.adapters`)
---are wholly self-describing. A configuration declares its inputs up front in an
---`inputs` table — `name -> easydap.Input` — and consumers read them along two
---paths that never meet:
---

local inputs_registry = require("easydap.inputs")

local M = {}

-- ── Introspection ──────────────────────────────────────────────────────────

---An adapter's declared `configurations`, or an empty table.
---@param adapter string
---@return table<string, easydap.Configuration>
function M.configurations(adapter)
    local def = require("easydap.adapters")[adapter]
    return (def and def.configurations) or {}
end

---A single named configuration, or nil.
---@param adapter string
---@param name string
---@return easydap.Configuration?
function M.configuration(adapter, name)
    return M.configurations(adapter)[name]
end

---An adapter's configuration names, sorted.
---@param adapter string
---@return string[]
function M.configuration_names(adapter)
    local out = {}
    for name in pairs(M.configurations(adapter)) do out[#out + 1] = name end
    table.sort(out)
    return out
end

---The inputs a configuration declares (`name -> easydap.Input`), or an empty table.
---Hand an entry to `easydap.inputs` to learn how to read, describe, seed or complete
---it; callers that need several inputs should read the table once rather than
---looking entries up name-by-name.
---@param adapter string
---@param configuration_name string
---@return table<string, easydap.Input>
function M.configuration_inputs(adapter, configuration_name)
    local configuration = M.configuration(adapter, configuration_name)
    return (configuration and configuration.inputs) or {}
end

---The input names a configuration declares, sorted. These are the `name=value`
---tokens `quick_run` accepts, and the `parameters` keys a tasks file may set.
---@param adapter string
---@param configuration_name string
---@return string[]
function M.configuration_input_names(adapter, configuration_name)
    local out = {}
    for name in pairs(M.configuration_inputs(adapter, configuration_name)) do
        out[#out + 1] = name
    end
    table.sort(out)
    return out
end

---The input names a configuration marks `required = true`, sorted — the ones
---`resolve_task` errors on when left unset.
---@param adapter string
---@param configuration_name string
---@return string[]
function M.configuration_required(adapter, configuration_name)
    local out = {}
    for name, spec in pairs(M.configuration_inputs(adapter, configuration_name)) do
        if spec.required then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

---Adapter names a configuration-driven front end can offer — those declaring at
---least one configuration — sorted.
---@return string[]
function M.configurable_adapters()
    local out = {}
    for name, def in pairs(require("easydap.adapters")) do
        if def.configurations and next(def.configurations) then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

---The distinct `request` values ("launch"/"attach") an adapter's configurations use,
---sorted.
---@param adapter string
---@return string[]
function M.requests(adapter)
    local seen, out = {}, {}
    for _, configuration in pairs(M.configurations(adapter)) do
        if not seen[configuration.request] then
            seen[configuration.request] = true
            out[#out + 1] = configuration.request
        end
    end
    table.sort(out)
    return out
end

-- ── Resolving ──────────────────────────────────────────────────────────────

---Read every declared input from `values`. A string is that input's string form and
---is parsed by its `type`/`format`; any other Lua value is already the typed form
---and is taken verbatim (see `easydap.inputs` on the two forms). Unset inputs are
---simply absent from the result (recorded in `missing` when `required`), which is
---what lets `build` omit their fields by assigning nil — or source them some other
---way, as an attach configuration does for an unset `pid`.
---@param configuration easydap.Configuration
---@param values table<string, any>  input name → a value in either authoring form
---@return table<string, any> inputs, string[] missing, string[] errs
local function _read_inputs(configuration, values)
    local inputs, missing, errs = {}, {}, {}
    for name, spec in pairs(configuration.inputs or {}) do
        local raw = values[name]
        if raw == nil then
            if spec.required then missing[#missing + 1] = name end
        elseif type(raw) ~= "string" then
            inputs[name] = raw
        else
            local val, cerr = inputs_registry.parse(spec, raw)
            if cerr then
                errs[#errs + 1] = name .. ": " .. cerr
            else
                inputs[name] = val
            end
        end
    end
    -- `pairs` order is arbitrary; sort so the reported set is stable.
    table.sort(missing)
    table.sort(errs)
    return inputs, missing, errs
end

---What to resolve: an adapter's named configuration, the values for its inputs, and
---the name the resulting task should run under.
---@class easydap.ResolveSpec
---@field adapter       string
---@field configuration string
---@field name?         string              run/panel group name for the resolved task
---@field values?       table<string, any>  input name → a value in either authoring form

---Resolve one of an adapter's named configurations, plus values for its inputs,
---into a runnable `easydap.Task` — everything `run`/`start_task` needs, with the
---request kind and any task-level connection already in place. This is the single
---seam between a configuration and a front end: a caller supplies values and gets
---back a task, and never has to rejoin the two itself.
---@param spec easydap.ResolveSpec
---@param done fun(task: easydap.Task?, err: string?)
---@return fun() cancel
function M.resolve_task(spec, done)
    local settled, cancelled = false, false

    ---@param task easydap.Task?
    ---@param err string?
    local function finish(task, err)
        if settled or cancelled then return end
        settled = true
        done(task, err)
    end

    local function cancel() cancelled = true end

    local configuration = M.configuration(spec.adapter, spec.configuration)
    if not configuration then
        finish(nil, ("adapter %s has no configuration %q (available: %s)")
            :format(spec.adapter, tostring(spec.configuration),
                table.concat(M.configuration_names(spec.adapter), ", ")))
        return cancel
    end

    local inputs, missing, errs = _read_inputs(configuration, spec.values or {})
    if #errs > 0 then
        finish(nil, table.concat(errs, "; "))
        return cancel
    end
    if #missing > 0 then
        finish(nil, "missing: " .. table.concat(missing, ", "))
        return cancel
    end

    local body, connect = {}, {}

    ---Package what `build` assembled in place into the task it describes.
    local function deliver()
        -- No spec governs `connect` (it's task-level, not a body field), so an unset
        -- host/port is always optional: a `build` that leaves it empty reports none,
        -- and the resolved AdapterDef's own host/port apply instead.
        local has_connect = next(connect) ~= nil
        finish({
            name       = spec.name,
            adapter    = spec.adapter,
            request    = configuration.request,
            parameters = body,
            host       = has_connect and connect.host or nil,
            port       = has_connect and connect.port or nil,
        })
    end

    if not configuration.build then
        deliver()
        return cancel
    end

    local co = coroutine.create(function()
        local ok, berr = xpcall(configuration.build, debug.traceback, body, connect, inputs)
        if not ok then return finish(nil, berr) end
        -- `build` gave up — a cancelled picker.
        if berr then return finish(nil, berr) end
        deliver()
    end)
    local ok, err = coroutine.resume(co)
    if not ok then finish(nil, tostring(err)) end

    return cancel
end

return M
