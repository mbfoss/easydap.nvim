-- netcoredbg uses `stopAtEntry` instead of the standard stopOnEntry. Field set
-- matches the keys netcoredbg's VS Code protocol handler reads
-- (Samsung/netcoredbg, src/protocols/vscodeprotocol.cpp); `justMyCode` and
-- `enableStepFiltering` default to true there. No runInTerminal/console arg.
---@type easydap.AdapterDef
return {
    command = { "netcoredbg", "--interpreter=vscode" },
    configurations = {
        launch = {
            description = "debug a .NET assembly",
            request = "launch",
            placeholders = {
                target = { type = "file", description = ".NET assembly to run" },
                args   = { type = "shell_args", description = "arguments to the program" },
                cwd    = { type = "cwd", description = "working directory" },
                env    = { type = "env", description = "environment variables" },
            },
            parameters = {
                program = "{target}",
                args    = "{args}",
                cwd     = "{cwd}",
                env     = "{env}",
            },
        },
        attach = {
            description = "attach to a running process by pid",
            request    = "attach",
            placeholders = {
                pid = { type = "integer", description = "process id to attach to" },
            },
            parameters = { processId = "{pid}" },
        },
    },
}
