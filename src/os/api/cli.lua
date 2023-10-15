modular_computers.command = {}
modular_computers.internal.command = {registered_commands = {}}

function modular_computers.command.register(name, callback)
    modular_computers.internal.command.registered_commands[name] = callback
end
