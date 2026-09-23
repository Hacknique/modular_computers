unused_args = false
allow_defined_top = true

globals = {
    "minetest",
}

read_globals = {
    string = {fields = {"split", "trim"}},
    table = {fields = {"copy", "getn"}},

    -- Builtin
    "vector", "ItemStack",
    "dump", "DIR_DELIM", "VoxelArea", "Settings", "SecureRandom", "PcgRandom",

    -- MTG
    "default", "sfinv", "creative",

    -- Mineclonia / VoxeLibre / mesecons
    "mcl_sounds", "mcl_redstone", "mcl_formspec", "mesecon",
}

files["spec/"] = {
    std = "+busted",
    globals = {"core", "mineunit"},
    read_globals = {"sourcefile", "fixture", "world", "Player"},
}

-- Programs and libraries that run on the computers, in their sandbox
files["src/os/rom/"] = {
    std = "lua51",
    globals = {"os", "io", "print", "loadfile", "dofile", "require"},
    read_globals = {
        "component", "computer", "event", "filesystem", "term", "serialization", "sides", "colors", "text",
        "shell", "internet", "package", "bit32", "unicode",
        table = {fields = {"pack", "unpack"}},
    },
}
