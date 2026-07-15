-- lldb-dap — LLVM's native DAP adapter. The launch/attach parameters mirror the
-- LLDB docs (https://lldb.llvm.org/use/lldbdap.html). `type` is always
-- "lldb-dap" and `name` is a required display label. Attaching by process name
-- (rather than pid) is done by supplying `program` and omitting `pid`.
--
-- Beyond the fields exposed as placeholders below, lldb-dap accepts many
-- optional keys — add them to a run file directly:
--   * common (launch & attach): initCommands, preRunCommands, stopCommands,
--     exitCommands, terminateCommands, sourcePath, sourceMap, debuggerRoot,
--     commandEscapePrefix, customFrameFormat, customThreadFormat,
--     displayExtendedBacktrace, enableAutoVariableSummaries,
--     enableSyntheticChildDebugging.
--   * launch: console ("internalConsole"/"integratedTerminal"/
--     "externalTerminal"), stdio, launchCommands.
--   * attach: attachCommands.
-- An attach must specify exactly one target: pid, program, coreFile,
-- attachCommands, or gdb-remote-port.
--
-- lldb-dap's `gdb-remote-*` are plain body fields (this stdio adapter is not
-- task-level TCP), so the gdb_remote configuration has no `connect` block.
---@type easydap.AdapterDef
return {
    command = "lldb-dap",
    configurations = {
        -- One `command` input carries the whole command line; the per-use kind
        -- overrides split it into `program` (the first word) and `args` (the rest).
        launch = {
            description = "debug an executable",
            request = "launch",
            placeholders = {
                command     = { type = "shell_args", required = true },
                cwd         = { type = "cwd" },
                env         = { type = "env" },
                stopOnEntry = { type = "boolean" },
            },
            parameters = {
                name        = "lldb",
                type        = "lldb-dap",
                program     = "{command:shell_program}",
                args        = "{command:shell_rest_args}",
                cwd         = "{cwd}",
                env         = "{env}",
                stopOnEntry = "{stopOnEntry}",
            },
        },
        attach = {
            description = "attach to a running process by pid",
            request = "attach",
            placeholders = {
                pid = { type = "integer", required = true },
            },
            parameters = {
                name = "lldb",
                type = "lldb-dap",
                pid  = "{pid}",
            },
        },
        attach_by_name = {
            description = "attach to a process by executable, optionally waiting for it to launch",
            request = "attach",
            placeholders = {
                program = { type = "file", required = true },
                waitFor = { type = "boolean" },
            },
            parameters = {
                name    = "lldb",
                type    = "lldb-dap",
                program = "{program}",
                waitFor = "{waitFor}",
            },
        },
        core = {
            description = "post-mortem debug from a core file",
            request = "attach",
            placeholders = {
                corefile = { type = "file", required = true },
                program  = { type = "file" },
            },
            parameters = {
                name     = "lldb",
                type     = "lldb-dap",
                program  = "{program}",
                coreFile = "{corefile}",
            },
        },
        gdb_remote = {
            description = "attach over a gdb-remote (gdbserver) connection",
            request = "attach",
            placeholders = {
                port = { type = "port", required = true },
                host = { type = "host" },
            },
            parameters = {
                name                = "lldb",
                type                = "lldb-dap",
                ["gdb-remote-host"] = "{host}",
                ["gdb-remote-port"] = "{port}",
            },
        },
    },
}
