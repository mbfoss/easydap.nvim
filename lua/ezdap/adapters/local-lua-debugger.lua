-- Lua
local shared = require("ezdap.shared")

local _adapter_js = vim.fs.joinpath(
    vim.fn.stdpath("data"), "mason", "packages",
    "local-lua-debugger-vscode", "extension", "extension", "debugAdapter.js"
)

---@type ezdap.AdapterDef
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
    profiles       = {
        -- One `command` input carries the whole command line; `build` splits it into
        -- the script (`program.file`) and `args` (the rest).
        launch_program = {
            description = "debug a Lua script",
            request = "launch",
            inputs = {
                command = { type = "string", description = "command line to debug" },
                cwd     = { type = "string", format = "cwd", description = "working directory" },
                env     = { type = "table", format = "map", description = "environment variables" },
            },
            build = function(params, _, inputs)
                params.type = "lua-local"
                params.name = "Debug"
                -- The script goes inside `program`, not beside it, so the pair is
                -- split off first rather than assigned straight to the body.
                local file, args = shared.split_command(inputs.command)
                params.program = {
                    lua           = vim.fn.exepath("lua"),
                    communication = "stdio",
                    file          = inputs.command and file,
                }
                if inputs.command then
                    params.args = args
                end
                params.cwd = inputs.cwd
                params.env = inputs.env
            end,
        },
    },
}
