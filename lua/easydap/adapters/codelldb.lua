-- codelldb (vscode-lldb) — its own key set, distinct from lldb-dap. The
-- launch/attach parameters follow the CodeLLDB MANUAL
-- (https://github.com/vadimcn/codelldb/blob/master/MANUAL.md). `type` is always
-- "lldb" and codelldb uses `terminal` ("console"/"integrated"/"external", not
-- lldb-dap's `console`/`runInTerminal`) to pick the debuggee's stdio destination.
--
-- Beyond the fields exposed as placeholders below, codelldb accepts many
-- optional keys — add them to a run file directly:
--   * common (launch & attach): initCommands, preRunCommands, postRunCommands,
--     exitCommands, preTerminateCommands, gracefulShutdown, expressions,
--     sourceMap, relativePathBase, sourceLanguages, breakpointMode,
--     reverseDebugging.
--   * launch: cargo, envFile, stdio.
-- Remote/core scenarios use the custom launch form, driving LLDB directly via
-- targetCreateCommands + processCreateCommands (e.g. `target create -c <core>`,
-- `gdb-remote <host>:<port>`, `platform select`/`platform connect`).
---@type easydap.AdapterDef
return {
    command = "codelldb",
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
                name        = "codelldb",
                type        = "lldb",
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
                name = "codelldb",
                type = "lldb",
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
                name    = "codelldb",
                type    = "lldb",
                program = "{program}",
                waitFor = "{waitFor}",
            },
        },
        core = {
            description = "post-mortem debug from a core file (custom launch)",
            request = "launch",
            placeholders = {
                program  = { type = "file" },
                corefile = { type = "file" },
            },
            parameters = {
                name                  = "codelldb",
                type                  = "lldb",
                targetCreateCommands  = { "target create {program}" },
                processCreateCommands = { "target create -c {corefile}" },
            },
        },
        gdb_remote = {
            description = "attach over a gdb-remote (gdbserver) connection (custom launch)",
            request = "launch",
            placeholders = {
                program = { type = "file" },
                host    = { type = "host" },
                port    = { type = "port" },
            },
            parameters = {
                name                  = "codelldb",
                type                  = "lldb",
                targetCreateCommands  = { "target create {program}" },
                processCreateCommands = { "gdb-remote {host}:{port}" },
            },
        },
    },
}
