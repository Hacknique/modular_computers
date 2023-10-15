modular_computers.command.register_command("echo", {
    func = function(player, argc, ...)
        return "", table.concat({...}, " ") .. "\n", "", 0
    end,
})
