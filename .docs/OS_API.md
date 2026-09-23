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
  command started through `execute_at` runs, and `nil` otherwise.
* `modular_computers.command.list()` returns the names of all commands.

# Redstone

Computers work with mesecons and with Mineclonia's redstone. Sides are
`front` (the screen), `back`, `left`, `right`, `top` and `bottom`, with left and
right as seen by a player looking at the screen.

* `modular_computers.redstone.get_input(pos, side)` returns the signal level
  (0-15) coming into a side.
* `modular_computers.redstone.get_output(pos, side)` returns `true` if the
  computer powers a side.
* `modular_computers.redstone.set_output(pos, side, on)` powers a side, or all
  of them when `side` is `"all"`.

The `redstone` terminal command uses these to show and set the signals.
