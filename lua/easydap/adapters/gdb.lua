-- GDB speaks DAP natively via `--interpreter=dap`. Unlike the VS Code C/C++
-- adapters, GDB defines its own launch/attach parameters; these mirror the GDB
-- manual's "Debugger Adapter Protocol" chapter
-- (https://sourceware.org/gdb/current/onlinedocs/gdb.html/Debugger-Adapter-Protocol.html).
-- GDB has no `runInTerminal`/`type`/body-level `request` field, so none are set here.
-- `program` is a parameter common to launch and attach (it maps to GDB's `file`
-- command, so the adapter can find symbols); the niche `adaSourceCharset` common
-- parameter is omitted — add it to a run file directly if debugging Ada.
---@type easydap.AdapterDef
return {
    command = { "gdb", "--interpreter=dap" },
    configurations = {
        launch = {
            description = "debug a native executable",
            request = "launch",
            parameters = {
                program = "{command:shell_program}",
                args    = "{command:shell_rest_args}",
                cwd     = "{cwd:cwd}",
                env     = "{env:env}",
                stopOnEntry = "{stopOnEntry:boolean}",
                stopAtBeginningOfMainSubprogram = "{stopAtMain:boolean}",
            },
            required = { "target" },
        },
        attach = {
            description = "attach to a running process by pid",
            request    = "attach",
            parameters = { pid = "{pid:integer}" },
            required   = { "pid" },
        },
        remote = {
            description = "connect to a gdbserver / remote target",
            request    = "attach",
            parameters = {
                target  = "{connection}",
                program = "{target:file}",
            },
            required = { "connection" },
        },
        core = {
            description = "post-mortem debug from a core file",
            request    = "attach",
            parameters = {
                coreFile = "{corefile:file}",
                program  = "{target:file}",
            },
            required = { "corefile" },
        },
    },
}
