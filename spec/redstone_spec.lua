require("mineunit")

mineunit("core")
mineunit("server")
sourcefile("init")

describe("redstone", function()

	local NODE_NAME = "modular_computers:computer"
	local redstone = modular_computers.redstone
	local pos = {x=0, y=0, z=0}

	world.set_default_node({name="air",param2=0})
	mineunit:mods_loaded()

	local function place(param2)
		world.set_node(pos, {name=NODE_NAME, param2=param2 or 0})
		return core.get_node(pos)
	end

	it("gives every side of every rotation its own direction", function()
		for param2 = 0, 23 do
			place(param2)
			local seen = {}
			for _, side in ipairs(redstone.SIDES) do
				local direction = redstone.get_direction_name(pos, side)
				assert.not_nil(direction)
				assert.is_nil(seen[direction])
				seen[direction] = true
			end
		end
	end)

	it("names sides as seen by a player looking at the screen", function()
		-- The screen faces south
		place(0)
		assert.equals("south", redstone.get_direction_name(pos, "front"))
		assert.equals("north", redstone.get_direction_name(pos, "back"))
		assert.equals("west", redstone.get_direction_name(pos, "left"))
		assert.equals("east", redstone.get_direction_name(pos, "right"))
		assert.equals("up", redstone.get_direction_name(pos, "top"))
		assert.equals("down", redstone.get_direction_name(pos, "bottom"))

		-- The screen faces west
		place(1)
		assert.equals("west", redstone.get_direction_name(pos, "front"))
		assert.equals("north", redstone.get_direction_name(pos, "left"))
		assert.equals("south", redstone.get_direction_name(pos, "right"))
	end)

	it("reads mesecons signals", function()
		local node = place(0)
		local effector = core.registered_nodes[NODE_NAME].mesecons.effector
		effector.action_change(pos, node, {x=0, y=0, z=-1}, "on")
		assert.equals(15, redstone.get_input(pos, "front"))
		assert.equals(0, redstone.get_input(pos, "back"))
		effector.action_change(pos, node, {x=0, y=0, z=-1}, "off")
		assert.equals(0, redstone.get_input(pos, "front"))
	end)

	it("reads mcl_redstone signals", function()
		local node = place(0)
		rawset(_G, "mcl_redstone", {
			get_power = function(_, dir)
				return dir.y == 1 and 7 or 0
			end,
		})
		core.registered_nodes[NODE_NAME]._mcl_redstone.update(pos, node)
		rawset(_G, "mcl_redstone", nil)
		assert.equals(7, redstone.get_input(pos, "top"))
		assert.equals(0, redstone.get_input(pos, "front"))
	end)

	it("powers the sides it outputs to", function()
		place(0)
		assert.is_true(redstone.set_output(pos, "left", true))
		assert.is_true(redstone.get_output(pos, "left"))
		assert.is_false(redstone.get_output(pos, "right"))

		local node = core.get_node(pos)
		assert.equals(NODE_NAME .. "_001000", node.name)
		local def = core.registered_nodes[node.name]
		assert.equals(NODE_NAME, def.drop)
		assert.equals(1, def.groups.not_in_creative_inventory)

		-- Left is west, as seen from the front
		assert.equals(15, (def._mcl_redstone.get_power(node, vector.new(-1, 0, 0))))
		assert.equals(0, (def._mcl_redstone.get_power(node, vector.new(1, 0, 0))))
		assert.equals("on", def.mesecons.receptor.state)
		assert.same({{x=-1, y=0, z=0}}, def.mesecons.receptor.rules(node))

		assert.is_true(redstone.set_output(pos, "left", false))
		assert.nodename(NODE_NAME, pos)
		assert.equals("off", core.registered_nodes[NODE_NAME].mesecons.receptor.state)
		assert.is_nil(core.registered_nodes[NODE_NAME]._mcl_redstone.get_power)
	end)

	it("refuses unknown sides", function()
		place(0)
		assert.is_false(redstone.set_output(pos, "sideways", true))
		assert.nodename(NODE_NAME, pos)
	end)

	it("turns its outputs with the computer", function()
		place(0)
		redstone.set_output(pos, "front", true)
		local node = core.get_node(pos)
		assert.is_true(core.registered_nodes[node.name].on_rotate(pos, node, nil, 1, 1))
		node = core.get_node(pos)
		assert.equals(NODE_NAME .. "_100000", node.name)
		assert.equals(1, node.param2)
		assert.same({{x=-1, y=0, z=0}}, core.registered_nodes[node.name].mesecons.receptor.rules(node))
	end)

end)
