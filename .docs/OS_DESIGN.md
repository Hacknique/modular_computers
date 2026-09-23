# Design of the computer OS

Programs and their libraries are described in [LUA_API.md](LUA_API.md), and the
API for other mods in [OS_API.md](OS_API.md). This is how it works inside.

## Machines

A running computer tower has a Lua machine (`src/os/machine.lua`). When it
starts, it loads the libraries in `src/os/rom/lib` into a sandboxed global
environment and runs an event loop, the daemon, that calls event listeners and
timers. A program typed on the terminal runs as the foreground process, with the
machine's globals behind its own. Processes are coroutines, which talk to the
machine with system calls: waiting for a signal, reading a typed line, exiting.

A globalstep runs the processes that can run, a few milliseconds of them each
server step, starting with a different machine each time. Machines only exist
while their tower is loaded: they start again when it loads, so programs don't
survive unloading or server restarts, but files do. `/startup.lua` runs at
every start.

## The sandbox

Programs run on the server's Lua state, so `src/os/lua/sandbox.lua` limits what
they can do:

- An instruction count hook stops a program that runs too long, too slowly or
  grows its memory too much without yielding. JIT compilation is off for
  program code, where the hook wouldn't fire.
- Pattern matching is done in Lua (`src/os/lua/patterns.lua`), so the hook can
  stop slow patterns. Library functions written in C are charged instructions
  for the work they do, and those that make strings check that the program has
  the memory for them first.
- The `..` operator makes its string inside the VM, where nothing can check it,
  so program code is rewritten (`src/os/lua/rewrite.lua`) to concatenate
  through a function that does. The rewriter parses Lua 5.1 as LuaJIT reads it,
  and leaves everything else as it was, on the same lines.
- The shared string metatable points at the program's own string library while
  it runs, and at the real one while host code runs.
- `pcall`, `xpcall` and coroutines can't catch the error that stops a program.
- Host functions check their arguments and never run the program's
  metamethods.

A server-wide memory watchdog stops the machine that allocated the most lately
when the server's Lua memory grows past a setting.

## Components

Programs reach the hardware through components (`src/os/components.lua`): the
computer, the hard drive's filesystem, the GPU and screen, the tower's redstone,
and the cards in the tower (`src/cards`). Methods get the machine, the component
and the program's arguments.

## Files

Each hard drive item has a drive id in its meta. Its files are kept in mod
storage: an index per drive (`drive:<id>`) with the directories, file sizes,
times and label, saved every few seconds, and an entry per file
(`drive:<id>:<path>`). The programs and libraries of the ROM show up in `/bin`
and `/lib` and can't be changed.

## Screens

The monitors show the terminal, or what a program drew with the GPU, as one
entity per row of text in front of them (`src/nodes/display.lua`). A row's
texture only depends on what it shows, so clients, which keep every texture
they get, reuse the textures of text that scrolls. Screens are only shown near
players.
