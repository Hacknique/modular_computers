modular_computers.motherboards = {}
modular_computers.motherboard = {}

dofile(modular_computers.mod.path .. "/src/items/motherboards/inventory.lua")
dofile(modular_computers.mod.path ..
           "/src/items/motherboards/attached/inventory.lua")
dofile(modular_computers.mod.path .. "/src/items/motherboards/attached/tier.lua")
dofile(modular_computers.mod.path .. "/src/items/motherboards/utilities.lua")
dofile(modular_computers.mod.path .. "/src/items/motherboards/register.lua")
dofile(modular_computers.mod.path .. "/src/items/motherboards/items.lua")
dofile(modular_computers.mod.path ..
           "/src/items/motherboards/event_handlers.lua")
