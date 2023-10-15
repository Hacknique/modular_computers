modular_computers.command.register("echo", {
    func = function(player, argc, ...)
        return "", table.concat({...}, " ") .. "\n", "", 0
    end,
})
