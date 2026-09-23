# Commands

## Registering a command

### Syntax

```lua
modular_computers.command.register(name, {
    description = modular_computers.S("Shown by the help command"),
    func = function(argc, ...)
        return stdin, stdout, stderr, exit_code
    end,
})
```

`func` gets the number of arguments followed by the arguments themselves. Any
return value may be `nil`. When `stderr` is not empty it is shown instead of
`stdout`, and a non-zero `exit_code` is reported on the terminal. Errors raised
by `func` are printed on the terminal instead of crashing the server.

Output containing `modular_computers.terminal.CLEAR` clears the screen first.

### Running commands

* `modular_computers.command.execute(name, ...)` runs a command and returns the
  text to show on the terminal.
* `modular_computers.command.execute_at(pos, name, ...)` does the same for the
  computer at `pos`.
* `modular_computers.command.get_computer_pos()` returns that position while a
  command started through `execute_at` runs, and `nil` otherwise. For commands
  typed into a terminal it is the position of the computer tower.
* `modular_computers.command.get_machine()` returns the Lua machine of that
  computer while it runs.
* `modular_computers.command.get_player_name()` returns the name of the player
  who typed the command, if any.
* `modular_computers.command.list()` returns the names of all commands.

Commands are built into the terminal and run as mod code. Lua programs that run
on the computers themselves are described in [LUA_API.md](LUA_API.md).

# Lua machines

A running computer tower has a Lua machine, which runs the programs typed on
its terminal in a sandbox. Machines exist while their tower is loaded and
running.

* `modular_computers.machine.get(pos)` returns the machine of the tower at
  `pos`, or `nil`.
* `modular_computers.machine.push_signal(m, name, ...)` queues a signal for the
  machine's programs. Values must be nil, booleans, numbers or strings.
* `modular_computers.machine.run(m, path, args)` starts a program from the ROM
  or the hard drive, with a list of string arguments.
* `modular_computers.machine.input(m, line)` gives a typed line to the running
  program, and `modular_computers.machine.interrupt(m)` stops it.
* `modular_computers.computer.restart(pos)` restarts the computer.

# Components and cards

Programs use components through `component.invoke`. A component type is a table
of methods, each called with the machine, the component and the arguments from
the program:

```lua
modular_computers.components.types.thermometer = {
    getTemperature = function(m, component)
        return minetest.get_heat(m.pos)
    end,
}
```

Arguments come from untrusted code: check their types before using them, and
never index, call or compare tables from programs in ways that run their
metamethods. Methods run with the real string library and may raise errors,
which programs get as error messages.

A card is an item with the `modular_computers_card` group set to its tier, and a
`_modular_computers_card` field with its type. When a card is put in a tower,
the function registered for its type adds its component:

```lua
modular_computers.components.cards.thermometer = function(m, address, slot, card)
    modular_computers.components.add(m, address, "thermometer", slot, {
        -- Called when the machine stops or the card is taken out
        close = function(m, component) end,
    })
end

minetest.register_craftitem("mymod:thermometer_card", {
    description = "Thermometer Card",
    inventory_image = "mymod_thermometer_card.png",
    stack_max = 1,
    groups = { modular_computers_card = 1 },
    _modular_computers_card = { type = "thermometer", tier = 1 },
})
```

# Redstone

Computer towers work with mesecons and with Mineclonia's redstone. Sides are
`front` (the tower's front panel), `back`, `left`, `right`, `top` and `bottom`,
with left and right as seen by a player looking at the front. A tower switches
its outputs off when it stops.

* `modular_computers.redstone.get_input(pos, side)` returns the signal level
  (0-15) coming into a side.
* `modular_computers.redstone.get_output(pos, side)` returns `true` if the
  computer powers a side.
* `modular_computers.redstone.set_output(pos, side, on)` powers a side, or all
  of them when `side` is `"all"`.

The `redstone` terminal command uses these to show and set the signals.

Programs get a `redstone_changed` signal when the input on a side changes.
