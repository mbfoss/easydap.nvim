# CLAUDE.md

## Overview

ezdap.nvim is a Neovim Debug Adapter Protocol (DAP) client. It speaks the DAP
wire protocol directly (no `nvim-dap` dependency), manages adapter processes,
tracks debug sessions/breakpoints, and renders a tree-based debug UI. Requires
Neovim >= 0.10 (guarded in [plugin/ezdap.lua](plugin/ezdap.lua)).

Entry point is [lua/ezdap/init.lua](lua/ezdap/init.lua): `setup(opts)` merges
config, wires autocmds/signals, and registers the `:Debug` user command (with a
`breakpoint` subcommand surface).

## Architecture

The code is layered; higher layers depend on lower ones, not the reverse.

**Public API** — [init.lua](lua/ezdap/init.lua)
- `setup`, `run` (task entry point), `debug_view`/`open_debug_view`, user commands.

**Active session** — [manager.lua](lua/ezdap/manager.lua)
- Owns the "which session is active" concept that keymaps and UI subscribe to.
- Wraps the session-id-explicit `dap/client` with active-session helpers and the
  session-control primitives built on them (`continue`/`next`/`step_*`, selection,
  `evaluate`, `with_capability`, …).
- Re-exports client signals so consumers depend only on `manager`, never `client`.

**Command surface** — [command.lua](lua/ezdap/command.lua)
- The user-facing command tables `M.debug.*`, `M.breakpoint.*`, `M.view.*` reached
  through `:Debug …`. Sits on top of `manager` and owns the command-level UI —
  pickers, prompts, notifications, cursor handling.

**DAP core** — [lua/ezdap/dap/](lua/ezdap/dap/)
- `client.lua` — session registry & lifecycle; session spawning and session-level events.
- `session.lua` — one DAP session: owns a Connection, holds all runtime state
  (threads, frames, scopes, variables, modules, sources), drives the protocol
  handshake. Emits events via `session:on(event, fn)`.
- `connection.lua` — a single adapter connection (stdio pipe or TCP socket);
  Content-Length framing, request/response correlation, event/request dispatch.
- `transport.lua` — streaming Content-Length parser.
- `breakpoints.lua` — global, session-independent breakpoint registry (source,
  function, exception-filter, exception-name breakpoints).
- `proto.lua` — `---@meta` file of DAP spec types; never `require()` it.

**Adapters & tasks**
- [adapters/init.lua](lua/ezdap/adapters/init.lua) — built-in adapter
  definitions as a plain `name -> ezdap.AdapterDef` table (one file per adapter
  under `ezdap/adapters/`, assembled here): native DAP process/connection config
  plus an optional `profiles` table (`name -> ezdap.Profile`) of
  launch/attach descriptions. Each `Profile` is self-describing: an `inputs`
  table declaring what it accepts (`name -> ezdap.Input`, each with a `type` and
  `description`, plus an optional `format` and `required`) and a
  `build(params, connect, inputs)` that assembles the native request body — and any
  task-level `host`/`port` — in place. Both `quick_run` and a scaffolded run file
  resolve the same way (`values -> build -> task`), so `inputs` is the single
  description of a profile. Users add/override keys directly. The DAP core
  never reads the profiles — only `ezdap.schema` does.
- [task.lua](lua/ezdap/task.lua) — task runner (`ezdap.TaskTypeDef`); the
  `run` backend for external task runners. Consumes a native task
  (`name`/`adapter`/`request`/`parameters` + optional `host`/`port`) and sends
  `parameters` as the DAP request body verbatim.
- [inputs.lua](lua/ezdap/inputs.lua) — the input-format registry: one row per
  `ezdap.InputFormat`, each stating every way that format is read — `type` (what
  `build` receives), `item_type` (what one element of a collection becomes),
  `schema` (JSON Schema for the typed authored form), `parse` (the string authored
  form), `seed` (a scaffolded document's starting value) and `complete`
  (command-line value completion). Consumers call the five projections
  (`parse`/`json_schema`/`seed`/`completion`/`item_type`) and **never switch on a format name**;
  an unknown or absent format falls back to `type` alone. Adding a format is one
  row here, and every consumer — in both plugins — picks it up.

  A value space has two authoring forms, which is why `values` is a per-input union
  of string-or-typed: the **string form** (a command line, where everything is text;
  `parse` reads it) and the **typed form** (a structured file that already has
  types; `schema` describes it). They are not rival answers to what is legal — they
  are one value space reached from a CLI or from a typed file, and a single call may
  mix them per input. `map` is the clearest case: `"A=1,B=2"` on a command line, an
  object of the same pairs in a typed file, one table at `build`.

  Both forms must describe the *same* value: a row whose forms disagree about what
  the value is doesn't belong here. Splitting a command line into `program` + `args`
  is such a case — a transformation into a different shape, not a second spelling —
  and it lived here as a `shell_args` format until it moved to the launch `build`s
  that wanted it (`shared.split_command`, which takes a command line or a list).
- [schema.lua](lua/ezdap/schema.lua) — the engine behind `:Debug quick_run`, the
  profile reader for `new_run_file`, and the seam easytasks' `debug` task type
  runs on. `resolve_task(spec, done)` is that seam: it reads a profile's
  declared inputs from `spec.values` (each in either authoring form, parsed via
  `ezdap.inputs`), calls the profile's `build` to assemble the native
  request body and any task-level connection, and delivers a **complete
  `ezdap.Task`** — request kind and host/port included — ready for
  `run`/`start_task`. Callers supply values and get back a task; they never rejoin
  the two themselves. Inputs marked `required` are errors when left unset, other
  unset inputs arrive at `build` as nil (so Lua drops the fields assigned from them)
  unless that `build` answers them another way. `build` runs on a coroutine — it is
  the one thing here allowed to yield, which is how an attach profile can ask
  the user to pick a process for an unset `pid` (`shared.resolve_pid`); a `build`
  that gives up returns an error string. `done` fires **exactly once**, or never if
  the returned `cancel` is called first — so a caller that gives up while a picker is
  still open need not remember that it did. Introspection helpers —
  `profiles`/`profile`/`profile_names`,
  `profile_inputs`/`profile_input_names`/`profile_required`,
  `requests`, `profiled_adapters` — drive completion and scaffolding. Native keys
  throughout — no portable/generic field vocabulary.
- [scaffold.lua](lua/ezdap/scaffold.lua) — run-file creation behind `:Debug
  new_run_file`: writes a runnable Lua run_file that names the `adapter` and
  `profile` and lists its declared inputs under `parameters`, each seeded (via
  `ezdap.inputs`' `seed`) and commented with its `description`, then opens it. The
  scaffolded file is profile-based, exactly like `quick_run`: `:Debug run_file`
  resolves it through `resolve_task`/`build` (`parameters -> build -> task`), so a run
  file and `quick_run` share one description of a profile — its `inputs` — and
  cannot drift. `run_file` accepts two run-file shapes, told apart by whether a
  `profile` or a `configuration` field is present: the profile-based one above
  (`adapter` + `profile` + `parameters`, the answers to the profile's declared
  inputs), and a **raw** one (`adapter` + `configuration`) whose `configuration` is
  an nvim-dap-like table of raw DAP parameters including `request` — `request` is
  lifted out and the rest is forwarded to the adapter verbatim as the DAP body,
  yielding the same `ezdap.Task` shape `run`/`start_task` take. `resolve_task`
  only handles the profile shape; `run_file` builds the task for the raw shape.

**Persistence** — [store.lua](lua/ezdap/store.lua)
- A thin path + read/write helper. The project root is the nearest ancestor of
  the cwd (cwd included) holding a `root_markers` entry (default `.git`); all
  project state lives in a single JSON file at that root (`.ezdap.json` by
  default). `root()` (cached, `invalidate()` after a cwd change), `relativize`/
  `absolutize` (portable project-relative paths), and `read`/`write` (write
  removes the file when the payload is empty). The store knows nothing about
  *what* is stored.
- The lifecycle lives in [init.lua](lua/ezdap/init.lua): it owns the autocmds
  (`DirChangedPre`/`VimLeavePre` save, `DirChanged` re-resolves the root and
  reloads/clears) and the breakpoint/expression payloads, converting source
  paths at the persistence seam.

**UI** — [lua/ezdap/ui/](lua/ezdap/ui/)
- `DebugView.lua` — the main debug panel (tree of sessions/frames/scopes/
  variables/expressions/breakpoints), built on `TreeBuffer`.
- `output_win.lua` — the one bottom split a run's buffers share. `ezdap.runner`
  registers each buffer it spawns with a priority; the window holds the
  highest-priority live one and closes with the run's last buffer.
- `signs.lua`, `breakpoints_ui.lua`, `debugline_ui.lua`, `inlinevars.lua`,
  `extmarks.lua`, `expressions.lua`, `ReplBuffer.lua` — gutter signs, inline
  values, REPL, etc.

**Utilities** — [lua/ezdap/util/](lua/ezdap/util/)
- `Signal.lua` — the pub/sub primitive used throughout: `Signal.new()`,
  `:subscribe(fn)` (returns an unsubscribe fn), `:emit(...)`. This is the main
  decoupling mechanism between layers.
- `Tree.lua`, `select.lua`, `inputwin.lua`, `usercmd.lua` (subcommand
  registration/completion), plus `fsutil`, `str_util`, `table_util`, `term`,
  `throttle`, `timer`, `ui_util`.

### Conventions to keep in mind
- Layers communicate through `Signal`s, not direct back-references. Lower layers
  emit; higher layers subscribe.
- `manager` is the single dependency surface for UI/commands — prefer it over
  importing `dap/client` directly.

## Styling

Add Lua annotations (`---@param`, `---@return`, `---@class`, etc.) whenever possible.

Comment blocks are capped at 3 lines of prose. Annotation lines (`---@param`,
`---|` alias members, …) don't count toward the cap, and a module's file-top doc
block is exempt.

Don't use box-drawing section headers
(`-- ── Title ─────────`); a plain `-- Title` comment is enough.

Class-based modules are named in PascalCase; functional modules are named in snake_case.

Module-scope `local` variables are prefixed with `_`, except:
- a local name bound directly from `require()`
- the conventional `M` module table
- class type names like `MyType`

Inside a class, private members are prefixed with `_`.

Function local variable names should NOT begin with `_`. 