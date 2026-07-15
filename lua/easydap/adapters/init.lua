---@brief Built-in DAP adapter definitions.
---
---The module is a plain table: each key is an adapter name, each value is an
---AdapterDef — native DAP process/connection config (command, host/port,
---setup/teardown, request, …) plus a `configurations` table of named `easydap.Configuration`
---launch/attach templates. Configurations are what `:Debug new_run_file`/`quick_run`
---read (via `easydap.schema`) to scaffold a run file / assemble a
---native request body; the DAP core never touches them.
---
---Each built-in adapter lives in its own file under `easydap/adapters/`, returning
---one AdapterDef; this module assembles them into the `name -> AdapterDef` table.
---Users can add adapters or override existing ones directly:
---  local adapters = require("easydap.adapters")
---  adapters.myAdapter = { command = "...", request = "launch" }

-- ── Type annotations ──────────────────────────────────────────────────────

---Context passed to `config.setup()` so the adapter can report progress and
---register terminal buffers with the task runner.
---@class easydap.AdapterSetupCtx
---@field add_bufnr fun(bufnr: integer, opts?: easydap.AddBufOpts)
---@field report    fun(message: string)

---One declared input of a configuration — the `name=value` tokens `quick_run`
---accepts and the fields `new_run_file` seeds. `type` names the coercion applied
---to the raw CLI string (see `easydap.schema.coerce`); it also drives type-aware
---value completion and the blank a scaffolded run_file is seeded with. Omit it
---for an input taken verbatim as a string — including one whose every use carries
---a `"{name:kind}"` override, since the declared type is then never consulted. A
---placeholder with `required = true` must be supplied — leaving it unset is a
---`quick_run` error; any other unset placeholder is simply omitted from the body.
---@class easydap.Placeholder
---@field type?        "string"|"boolean"|"integer"|"number"|"file"|"dir"|"cwd"|"env"|"host"|"port"|"list"|"shell_args"|"shell_program"|"shell_rest_args"  default `string`
---@field required?    boolean  unset is an error (default false)
---@field description? string   a few words on what the input means

---A named `quick_run`/`new_run_file` configuration for one adapter.
---
---`placeholders` declares the configuration's inputs up front (name →
---`easydap.Placeholder`); `parameters` is a native request body that refers to
---them. A `parameters` leaf may be:
---  * a literal (string/boolean/number/table), for identity fields the
---    adapter pins itself (`type`/`name`) or fixed defaults it wants sent
---    regardless of user input;
---  * a zero-arg function, resolved at fill time (a computed default, e.g.
---    `function() return vim.fn.getcwd() end`);
---  * a `"{name}"` token naming a declared placeholder, coerced by that
---    placeholder's `type`. Tokens may also be embedded in a longer string
---    (`"target create {program}"`), which interpolates.
---The `"{name:kind}"` form overrides the coercion for that one use. It exists for
---the case where a single input feeds two fields differently — a shell command
---line split into `program` (`shell_program`) and `args` (`shell_rest_args`) —
---and is otherwise unnecessary: prefer a bare `"{name}"` and a declared `type`.
---
---`connect` is the same placeholder mechanism for adapters that connect over a
---task-level TCP endpoint (an `AdapterDef` `host`/`port`, e.g. `remote`/
---`java-debug-server`) — its `host`/`port` placeholders set the task's
---connection, not a body field.
---@class easydap.Configuration
---@field description    string
---@field request        "launch"|"attach"
---@field placeholders?  table<string, easydap.Placeholder>  the configuration's declared inputs
---@field parameters     table    native request body; leaves may be a literal, a zero-arg function, or a `"{placeholder}"` token
---@field connect?       {host?: string, port?: string}   task-level connection placeholders

---A static adapter definition — the launch/attach template for one adapter.
---Entries of this module are values of this type. It is NOT the per-run config
---the DAP layer consumes: the task runner resolves an `AdapterDef` + a task into
---an `easydap.dap.Config` (see [dap/client.lua](dap/client.lua)). No
---`request_args` here — that is a per-run value carried by the resolved config.
---`setup`/`teardown` receive that resolved config (setup may mutate host/port).
---`configurations` are consumed only by `easydap.schema` (for
---new_run_file/quick_run), never by the DAP core.
---@class easydap.AdapterDef
---@field command?               string|string[]
---@field cwd?                   string
---@field env?                   table<string,string>
---@field host?                  string
---@field port?                  integer
---@field type?                  string   DAP adapterID override (defaults to the adapter name)
---@field defer_launch_attach?   boolean
---@field request?               string
---@field configurations?               table<string, easydap.Configuration>
---@field setup?                 fun(config: easydap.dap.Config, ctx: easydap.AdapterSetupCtx, callback: fun(err?: string, state?: any))
---@field teardown?              fun(config: easydap.dap.Config, ctx: any)

-- ── Built-in adapters ──────────────────────────────────────────────────────
-- One file per adapter; keys with hyphens are loaded from the matching filename.

---@type table<string, easydap.AdapterDef>
local M = {
    debugpy               = require("easydap.adapters.debugpy"),
    codelldb              = require("easydap.adapters.codelldb"),
    gdb                   = require("easydap.adapters.gdb"),
    netcoredbg            = require("easydap.adapters.netcoredbg"),
    remote                = require("easydap.adapters.remote"),
    ["java-debug-server"] = require("easydap.adapters.java-debug-server"),
    lldb                  = require("easydap.adapters.lldb"),
    delve                 = require("easydap.adapters.delve"),
    ["js-debug"]          = require("easydap.adapters.js-debug"),
    ["bash-debug-adapter"] = require("easydap.adapters.bash-debug-adapter"),
    ["php-debug-adapter"] = require("easydap.adapters.php-debug-adapter"),
    ["local-lua-debugger"] = require("easydap.adapters.local-lua-debugger"),
}

return M
