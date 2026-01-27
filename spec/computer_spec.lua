require("mineunit")

-- Load fixtures and mod
mineunit("core")
mineunit("auth")
mineunit("server")
sourcefile("init")

local NODE_NAME = "modular_computers:computer"

describe(NODE_NAME, function()

	local function M(s) return require("luassert.match").matches(s) end

	world.set_default_node({name="air",param2=0})

	local player = Player("Sam")

	-- Execute on mods loaded callbacks to finish loading.
	mineunit:mods_loaded()
	-- Tell mods that 1 minute passed already to execute all weird core.after hacks.
	mineunit:execute_globalstep(60)

	setup(function()
		mineunit:execute_on_joinplayer(player)
	end)

	teardown(function()
		mineunit:execute_on_leaveplayer(player)
	end)

	it("can be placed", function()
		-- Give few nodes to player
		player:set_wielded_item(NODE_NAME .. " 2")
		-- Try to place one from above
		player:do_set_pos_fp({x=0, y=2, z=0})
		player:do_place({x=0, y=1, z=0})

		-- Check for in world node
		assert.nodename(NODE_NAME, {x=0, y=0, z=0})
		-- Make sure exactly one item were removed from inventory
		assert.has_item(player, "main", 1, NODE_NAME .. " 1")
	end)

	it("can be placed with aux1", function()
		-- Give few nodes and try to place one
		player:set_wielded_item(NODE_NAME .. " 2")
		-- Try to place one from below, this one should go above your head
		player:do_set_pos_fp({x=1, y=-1, z=1})
		player:do_place({x=1, y=0, z=1}, { aux1 = true })

		-- Check for in world node
		assert.nodename(NODE_NAME, {x=1, y=1, z=1})
		-- Make sure exactly one item were removed from inventory
		assert.has_item(player, "main", 1, NODE_NAME .. " 1")
	end)

	it("can be used", function()
		-- Give few nodes and try to place one
		player:set_wielded_item(NODE_NAME .. " 2")
		-- Maybe it does something if we'd just use it
		player:do_set_pos_fp({x=1, y=-1, z=1})
		player:do_use({x=2, y=0, z=1})

		-- Check that we still have both computers
		assert.has_item(player, "main", 1, NODE_NAME .. " 2")
	end)

	it("can be used with aux1", function()
		-- Give few nodes and try to place one
		player:set_wielded_item(NODE_NAME .. " 2")
		-- Using it didn't do anything interesting, maybe if we'd hold aux1 and try again
		player:do_set_pos_fp({x=1, y=-1, z=1})
		player:do_use({x=2, y=0, z=1}, { aux1 = true })

		-- Make sure nobody stole our computer
		assert.has_item(player, "main", 1, NODE_NAME .. " 2")
	end)

	it("accepts echo command", function()
		-- Take away any leftover stuff
		mineunit:clear_InvRef(player:get_inventory())

		-- Maybe it does something if we'd right click it
		player:do_place_from_above({x=1, y=1, z=1})

		-- We should have received a formspec, parse it and find input field
		local form1 = mineunit:get_player_formspec(player)
		assert.is_Form(form1)
		local input = form1:one("_in$", "field")
		assert.not_nil(input)

		-- Try some fancy command and send the form
		input:value("echo Hello World")
		form1:send(player)

		-- Get response form and output field
		local form2 = mineunit:get_player_formspec(player)
		assert.is_Form(form2)
		local output = form2:one("_out$", "textarea")
		assert.not_nil(output)

		-- Check if output matches expected value which is our command and its output
		assert.match("echo Hello World\nHello World", output:value())

		-- Close form
		core.close_formspec(player:get_player_name())
	end)

end)
