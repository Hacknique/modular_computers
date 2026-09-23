unused_args = false
allow_defined_top = true

globals = {
    "minetest",
    "item_tracking"
}

read_globals = {
    string = {fields = {"split", "trim"}},
    table = {fields = {"copy", "getn"}},

    -- Builtin
    "vector", "ItemStack",
    "dump", "DIR_DELIM", "VoxelArea", "Settings",

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
