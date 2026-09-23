# Programming computers

Computers run Lua programs, with libraries modelled on
[OpenComputers](https://ocdoc.cil.li/), so most OpenComputers programs work with
few changes.

## Getting started

A computer is a **computer tower** with a **monitor** on top of it. Put a
motherboard in the tower, then a CPU, GPU, RAM and a hard drive. Cards go in the
card slots: a motherboard has one card slot for each of its tiers. Right-click
the monitor to open the terminal.

The terminal runs shell commands and programs:

| Command | What it does |
| --- | --- |
| `help` | Lists the commands and programs |
| `ls [dir]`, `cd [dir]`, `pwd` | Show and change directories |
| `cat <file>...` | Shows files |
| `edit <file>` | Opens a file in the editor |
| `mkdir <dir>...` | Makes directories |
| `rm [-r] <path>...` | Removes files, or directories with `-r` |
| `cp [-r] <from> <to>`, `mv <from> <to>` | Copy and move files |
| `df`, `label [name]` | Show the space used on the hard drive, and its label |
| `echo <text>`, `clear` | Print text, clear the screen |
| `redstone [get <side> \| set <side> <on\|off>]` | Show or set redstone signals |
| `reboot`, `shutdown`, `uptime` | Restart, turn off, show how long it has run |
| `lua` | An interactive Lua prompt (`exit` leaves it) |
| `components [type]` | Lists the components of the computer |
| `wget <url> [file]` | Downloads a file with an internet card |

Any other name runs a program: `hello` runs `hello.lua` from a directory in
`PATH` (`/bin` and the working directory), and `./dir/tool.lua` runs that file.
Arguments are separated by spaces. Type `^C`, or press the `^C` button, to stop
the running program. `/startup.lua` runs every time the computer starts.

```lua
-- hello.lua
local name = ... or "world"
print("Hello, " .. name .. "!")
io.write("What's your name? ")
local answer = io.read()
print("Nice to meet you, " .. answer)
```

The programs and libraries that come with the computer are in `/bin` and
`/lib`, and can't be changed. Libraries of your own go in `/lib` and are loaded
with `require`.

## Limits

Programs run on the server, so they are limited. Each time a program runs until
it waits for something (a signal, input or `os.sleep`), it may run a number of
instructions set by the CPU, and grow its memory by an amount set by the RAM:

| Tier | CPU instructions | RAM | GPU resolution and colors | Hard drive |
| --- | --- | --- | --- | --- |
| 1 | 1,000,000 | 4 MiB | 50×16, black and white | 1 MiB |
| 2 | 2,000,000 | 8 MiB | 80×25, 16 colors | 2 MiB |
| 3 | 4,000,000 | 16 MiB | 80×25, 16 million colors | 4 MiB |

A program that goes over a limit is stopped with `too long without yielding` or
`not enough memory`, even inside `pcall`. Programs that compute for long should
call `os.sleep(0)` now and then. Memory that a program no longer uses counts
until the garbage collector frees it, so building a long string piece by piece
with `..` uses up memory fast; collect the pieces in a table and join them with
`table.concat` instead. A hard drive holds up to 4096 files, and code of more
than 256 KiB can't be loaded.

When a computer's area is unloaded, its programs stop, and it starts again when
the area loads.

## The Lua environment

Programs have Lua 5.1 with `table.pack`, `table.unpack`, `rawlen` and `bit32`
from later versions. `load` only loads source code, `string.dump`, `setfenv`,
`debug` (except `debug.traceback`) and the server's globals are not there, and
`os` has `clock`, `date`, `time` and `difftime` besides the functions below.
Changes to the string library only affect the program itself.

### computer

* `computer.address()`: the address of the computer
* `computer.uptime()`: seconds since the computer started
* `computer.freeMemory()`, `computer.totalMemory()`: memory in bytes
* `computer.pushSignal(name, ...)`: queues a signal; its values can be nil,
  booleans, numbers and strings
* `computer.pullSignal([timeout])`: waits for the next signal and returns its
  name and values, or nothing after `timeout` seconds
* `computer.shutdown([reboot])`: turns the computer off, or restarts it
* `computer.getBootAddress()`: the address of the hard drive

### component

* `component.list([type [, exact]])`: a table of `address = type`, which can
  also be called to go through it: `for address, type in component.list() do`
* `component.type(address)`, `component.slot(address)`,
  `component.methods(address)`
* `component.invoke(address, method, ...)`: calls a method of a component
* `component.proxy(address)`: a table with the component's methods, and its
  `address`, `type` and `slot`
* `component.get(prefix [, type])`: the full address that starts with `prefix`
* `component.isAvailable(type)`, `component.getPrimary(type)`,
  `component.setPrimary(type, address)`
* `component.<type>`: the primary component of a type, like `component.gpu`

### event

* `event.pull([timeout,] [name, ...])`: waits for a signal whose name matches
  the pattern `name` and whose values equal the other arguments that aren't
  `nil`
* `event.pullFiltered([timeout,] filter)`, `event.pullMultiple(name, ...)`
* `event.listen(name, callback)`, `event.ignore(name, callback)`: calls
  `callback(name, ...)` for signals while any program waits for signals; a
  callback that returns `false` stops listening
* `event.timer(interval, callback [, times])`: calls `callback` every
  `interval` seconds, `times` times (`math.huge` for ever); returns an id
* `event.cancel(id)`, `event.push(name, ...)`

`os.sleep(seconds)` waits while running listeners and timers.

### Signals

| Signal | Values |
| --- | --- |
| `modem_message` | receiver address, sender address, port, distance, the message's values |
| `redstone_changed` | redstone address, side, old level, new level |
| `component_added`, `component_removed` | address, type (when cards go in or out) |
| `internet_ready` | internet card address, request id |
| `touch` | screen address, x, y, button (0), player name |

### term, io and print

* `print(...)`, `io.write(...)`, `term.write(value)` write on the terminal
* `io.read([format])` and `term.read()` read a line typed on the terminal
* `io.open(path [, mode])` opens a file (`"r"`, `"w"` or `"a"`) with `read`,
  `write`, `lines`, `seek` and `close`; `io.lines(path)` goes through its lines
* `term.clear()`, `term.getCursor()`, `term.setCursor(x, y)`,
  `term.getViewport()`

### filesystem

Paths are relative to the working directory.

* `filesystem.exists(path)`, `filesystem.isDirectory(path)`,
  `filesystem.size(path)`, `filesystem.lastModified(path)`
* `filesystem.list(path)`: an iterator over the names in a directory, with a
  `/` after directories
* `filesystem.makeDirectory(path)`, `filesystem.remove(path)`,
  `filesystem.rename(from, to)`, `filesystem.copy(from, to)`
* `filesystem.open(path [, mode])`: a handle with `read(count)`,
  `write(text)`, `seek(whence, offset)` and `close()`
* `filesystem.canonical(path)`, `filesystem.concat(...)`,
  `filesystem.path(path)`, `filesystem.name(path)`, `filesystem.segments(path)`

### Other libraries

* `shell`: `getWorkingDirectory()`, `setWorkingDirectory(path)`,
  `resolve(name)`, `parse(...)` (returns arguments and options),
  `execute(command, env, ...)`, `getPath()`, `setPath(value)`
* `os`: `sleep(seconds)`, `exit()`, `getenv(name)`, `setenv(name, value)`
  (up to 256 variables of 4 KiB), `remove(path)`, `rename(from, to)`,
  `tmpname()`
* `serialization`: `serialize(value [, pretty])` and `unserialize(text)`
* `text`: `trim`, `padLeft`, `padRight`, `detab`, `tokenize`
* `unicode`: `char`, `len`, `sub`, `reverse`, `lower`, `upper`, `wlen`,
  `wtrunc`, `isWide`, `charWidth`, for UTF-8 strings
* `sides`: side numbers by name, `sides.front` and so on, and names by number
* `colors`: palette indices by name, `colors.red` and so on
* `internet`: `isHttpEnabled()` and `request(url [, data [, headers [, method]]])`,
  which returns a function that gives the body in chunks
* `require(name)`, `loadfile(path [, mode [, env]])`, `dofile(path)`,
  `package.loaded`, `package.preload`, `package.path`

## Components

### gpu

The GPU draws on the monitors. While a program draws, the monitors show what it
drew instead of the terminal, until the program ends. Right-clicking the screen
then sends the program a `touch` signal with the cell that was clicked; sneak
and right-click to open the terminal instead.

* `getResolution()`, `setResolution(width, height)`, `maxResolution()`,
  `getViewport()`: the resolution starts out filling the monitors
* `getDepth()`, `maxDepth()`: 1, 4 or 8 bits
* `setForeground(color [, isPaletteIndex])`,
  `setBackground(color [, isPaletteIndex])`: colors are `0xRRGGBB` numbers, or
  palette indices; they return the old color
* `getForeground()`, `getBackground()`, `getPaletteColor(index)`,
  `setPaletteColor(index, color)`
* `set(x, y, text [, vertical])`, `get(x, y)`: returns the character, its
  foreground and its background
* `fill(x, y, width, height, char)`, `copy(x, y, width, height, dx, dy)`
* `getCursor()`, `setCursor(x, y)`: where `print` writes while drawing

```lua
local gpu = component.gpu
local width, height = gpu.getResolution()
gpu.setBackground(0x000080)
gpu.fill(1, 1, width, height, " ")
gpu.setForeground(0xFFFF00)
gpu.set(2, 2, "Hello from the GPU")
os.sleep(5)
```

### filesystem

The hard drive: `spaceUsed()`, `spaceTotal()`, `isReadOnly()`, `getLabel()`,
`setLabel(label)`, `exists(path)`, `isDirectory(path)`, `size(path)`,
`lastModified(path)`, `list(path)`, `makeDirectory(path)`, `remove(path)`,
`rename(from, to)`, and `open(path, mode)` which returns a handle for
`read(handle, count)`, `write(handle, text)`, `seek(handle, whence, offset)` and
`close(handle)`. Paths are absolute.

### redstone

Built into the tower. Sides are numbers (see `sides`) or names.

* `getInput([side])`: the signal level coming in, 0 to 15, or a table of all
  sides
* `getOutput([side])`, `setOutput(side, level)`: outputs are on (15) or off (0)

```lua
-- Blink a lamp behind the computer
for _ = 1, 10 do
    component.redstone.setOutput(sides.back, 15)
    os.sleep(0.5)
    component.redstone.setOutput(sides.back, 0)
    os.sleep(0.5)
end
```

### modem (wireless card)

A tier 1 wireless card reaches 16 blocks, a tier 2 card 400. Messages go to the
modems of other computers that have the port open and are within the sender's
strength.

* `open(port)`, `close([port])`, `isOpen(port)`: ports are 1 to 65535, and at
  most 16 can be open
* `send(address, port, ...)`, `broadcast(port, ...)`: send nil, boolean, number
  and string values, up to `maxPacketSize()` (8192) bytes; a modem sends at
  most 16 messages a second, and returns `false` when it can't send now
* `getStrength()`, `setStrength(blocks)`, `isWireless()`, `isWired()`

```lua
-- Chat with nearby computers
local modem = component.modem
modem.open(1)
event.listen("modem_message", function(_, _, from, _, distance, text)
    print(from:sub(1, 8) .. " (" .. math.floor(distance) .. "m): " .. tostring(text))
end)
while true do
    local line = io.read()
    if line == "exit" then break end
    modem.broadcast(1, line)
end
```

### internet (internet card)

HTTP requests, when the server allows them (see the README).

* `isHttpEnabled()`, `isTcpEnabled()` (always `false`)
* `request(url [, data [, headers [, method]]])`: starts a request and returns
  its id; `finishConnect(id)`, `response(id)` (status code), `read(id, count)`
  (`""` until the response arrives, `nil` at the end) and `close(id)`

The `internet` library wraps these: `for chunk in internet.request(url) do`.

### data (data card)

`encode64`, `decode64`, `sha256`, `sha1`, `crc32` (return raw bytes),
`deflate`, `inflate`, `random(count)` and `getLimit()`. Inputs are at most
64 KiB.
