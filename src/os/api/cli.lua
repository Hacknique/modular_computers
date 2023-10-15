modular_computers.command = {}
modular_computers.internal.command = {registered_commands = {}}

function modular_computers.command.register_command(name, callback)
    modular_computers.internal.command.registered_commands[name] = callback
end
