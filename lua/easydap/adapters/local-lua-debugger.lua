-- Lua
local _adapter_js = vim.fs.joinpath(
    vim.fn.stdpath("data"), "mason", "packages",
    "local-lua-debugger-vscode", "extension", "extension", "debugAdapter.js"
)

---@type easydap.AdapterDef
return {
    command = { "node", _adapter_js },
    env     = {
        LUA_PATH = vim.fs.joinpath(
            vim.fn.stdpath("data"), "mason", "packages",
            "local-lua-debugger-vscode", "debugger", "?.lua"
        ) .. ";;",
    },
    -- `program` is a nested table the js-based adapter consumes; the target file
    -- is set as `program.file`. Field set follows tomblind/local-lua-debugger-vscode's
    -- launch configuration.
    configurations = {
        launch = {
            description = "debug a Lua script",
            request = "launch",
            placeholders = {
                target = { type = "file", description = "Lua script to run" },
                args   = { type = "shell_args", description = "arguments to the script" },
                cwd    = { type = "cwd", description = "working directory" },
                env    = { type = "env", description = "environment variables" },
            },
            parameters = {
                type = "lua-local",
                name = "Debug",
                program = {
                    lua           = function() return vim.fn.exepath("lua") end,
                    communication = "stdio",
                    file          = "{target}",
                },
                args = "{args}",
                cwd  = "{cwd}",
                env  = "{env}",
            },
        },
    },
}
