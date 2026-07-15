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
        -- One `command` input carries the whole command line; the per-use kind
        -- overrides split it into `program` (the first word) and `args` (the rest).
        launch = {
            description = "debug a native executable",
            request = "launch",
            placeholders = {
                command     = { type = "shell_args", required = true },
                cwd         = { type = "cwd" },
                env         = { type = "env" },
                stopOnEntry = { type = "boolean" },
                stopAtMain  = { type = "boolean" },
            },
            parameters = {
                program     = "{command:shell_program}",
                args        = "{command:shell_rest_args}",
                cwd         = "{cwd}",
                env         = "{env}",
                stopOnEntry = "{stopOnEntry}",
                stopAtBeginningOfMainSubprogram = "{stopAtMain}",
            },
        },
        attach = {
            description = "attach to a running process by pid",
            request    = "attach",
            placeholders = {
                pid = { type = "integer", required = true },
            },
            parameters = { pid = "{pid}" },
        },
        -- The body's `target` key takes the remote `connection` string; the
        -- `target` placeholder is the local binary GDB loads symbols from.
        remote = {
            description = "connect to a gdbserver / remote target",
            request    = "attach",
            placeholders = {
                connection = { type = "string", required = true },
                target     = { type = "file" },
            },
            parameters = {
                target  = "{connection}",
                program = "{target}",
            },
        },
        core = {
            description = "post-mortem debug from a core file",
            request    = "attach",
            placeholders = {
                corefile = { type = "file", required = true },
                target   = { type = "file" },
            },
            parameters = {
                coreFile = "{corefile}",
                program  = "{target}",
            },
        },
    },
}
