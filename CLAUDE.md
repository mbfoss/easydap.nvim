# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

No automated test suite. Manual testing is done by loading the plugin inside Neovim with a running easytasks.nvim setup.

## Architecture

**easytasks-debug.nvim** adds a `debug` task type to easytasks.nvim that drives DAP (Debug Adapter Protocol) sessions. `lua/easytasks-debug/init.lua` is the public API — `setup()` registers the task type, wires persistence to project signals, enables UI subsystems, and registers subcommands on the parent `Tasks` user command via `easytasks.util.usercmd`.

### Integration with easytasks.nvim

`init.lua` calls `easytasks.register_task_type("debug", "easytasks-debug.task")` so the `debug` type appears in the TOML schema and runner. `task.lua` implements the `{ start, schema, templates }` contract required by the type system.

Breakpoints and watch expressions are persisted per-project via `easytasks.store_set` / `easytasks.store_get` (namespaces `"debug.breakpoints"` and `"debug.expressions"`). `on_project_leave_pre` and `on_project_enter` signals from easytasks.nvim trigger save and load respectively. A `_loading` flag suppresses write-conflict warnings during restore.

### Adapter registry (`adapters.lua`)

A plain module-level table — each key is an adapter name, each value is a `Config` table. Built-ins: `codelldb`, `lldb`, `lldb-dap`, `gdb`, `delve`, `debugpy`, `debugpy-module`, `debugpy-remote`, `js-debug`, `bash-debug-adapter`, `php-debug-adapter`, `local-lua-debugger`, `netcoredbg`, `remote`, `java-debug-server`. Users extend or override by mutating the table directly after require.

Each config may have:
- `command` / `host` / `port` — how to reach the adapter process
- `setup(config, ctx, callback)` — optional async launcher (starts a subprocess, waits for it to be ready, then calls `callback(err?, state?)`)
- `teardown(config, state)` — optional cleanup called when the session ends
- `derive_launch_args(task)` / `derive_attach_args(task)` — translate task fields to DAP launch/attach bodies

`AdapterSetupCtx` carries `add_bufnr` and `report` from the easytasks runner context so adapter processes can appear in the task status panel.

### DAP layer (`dap/`)

```
dap/transport.lua   Content-Length framing over stdio or TCP sockets
dap/connection.lua  one Connection per adapter: request/response correlation, event dispatch
dap/session.lua     one Session per connection: handshake, thread/frame/scope state
dap/client.lua      session registry; start/stop lifecycle; public signals
dap/breakpoints.lua global breakpoint registry (source, function, exception, exception-name)
dap/proto.lua       type-only meta file (@class/@alias for DAP spec types; never require'd)
```

**Connection** manages one adapter pipe or TCP socket. It encodes/decodes Content-Length frames via `transport.lua`, correlates responses to pending callbacks by sequence number, and dispatches events and reverse-requests to the session.

**Session** owns one Connection and all runtime state (threads, stack frames, scopes, variables, modules). It drives the full DAP handshake on `start()`, syncs breakpoints after `initialized`, and re-emits DAP events to subscribers via `session:on(event, fn)`.

**Client** is the session registry and lifecycle layer. `client.start(config, opts)` resolves an adapter config, runs `config.setup()`, opens the connection, and registers the session. It emits signals: `on_session_added`, `on_session_removed`, `on_session_updated`, `on_session_stopped`, `on_raw_message`, `on_variable_changed`, `on_selection_changed`.

### Manager (`manager.lua`)

The layer between the client and user-facing commands. It adds the "active session" concept: the session most recently added or stopped is auto-promoted to active. `manager.on_active_changed` and `manager.on_selection_changed` are the signals UI and keymaps should subscribe to. All stepping commands (`continue`, `next`, `step_in`, `step_out`, `step_back`, `pause`, `restart`, `stop`) delegate to the client using the current active id.

`manager` also implements the concrete `M.breakpoint.*` and `M.debug.*` command tables that `init.lua` wires to `Tasks breakpoint <sub>` and `Tasks debug <sub>` subcommands.

### UI layer (`ui/`)

```
ui/DebugView.lua      main debug panel: tree of sessions, threads, frames, scopes, variables, expressions, breakpoints
ui/TreeBuffer.lua     reusable collapsible tree renderer
ui/ReplBuffer.lua     interactive REPL buffer with prompt, history, grid completion
ui/expressions.lua    global watch-expression registry; on_change Signal
ui/extmarks.lua       persistent extmark registry; re-applies marks on BufReadPost
ui/signs.lua          thin extmarks.lua wrapper for sign-column marks
ui/breakpoints_ui.lua sign + extmark rendering for source breakpoints; subscribes to breakpoints.on_change
ui/debugline_ui.lua   current-execution-position sign; subscribes to client.on_session_stopped
ui/inlinevars.lua     inline variable value display via virtual text; subscribes to manager.on_selection_changed and client.on_variable_changed
```

**DebugView** is a singleton `TreeBuffer` showing the full debug state tree. Root nodes are sessions; children are threads, stack frames, scopes, and variables fetched lazily on expand. Expression and breakpoint nodes are interleaved. Node formatters produce highlight-chunk arrays per node kind.

**TreeBuffer** is a general-purpose collapsible tree widget backed by a nofile buffer. It stores nodes in `easytasks.util.Tree` and maintains a flat visible-id list for line↔id mapping. Expand/collapse re-renders only the affected subtree range.

**extmarks.lua** maps logical mark ids to `{file, lnum, col, ns, bufnr}`. `BufReadPost` autocmds re-apply marks when files are loaded; `BufUnload` clears cached bufnrs. This lets breakpoint signs survive buffer deletions.

**inlinevars.lua** subscribes to thread/frame selection changes and renders the current frame's variables as extmark virtual text at the line of the stopped position, cleared on resume.

## Styling

Add Lua annotations (`---@param`, `---@return`, `---@class`, etc.) whenever possible.

Class-based modules are named in PascalCase; functional modules are named in snake_case.

Module-scope `local` variables are prefixed with `_`, except:
- a local name bound directly from `require()`
- the conventional `M` module table
- class type names like `MyType`

Inside a class, private members are prefixed with `_`.
