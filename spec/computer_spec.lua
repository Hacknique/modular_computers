require("mineunit")

-- Load fixtures and mod
mineunit("core")
mineunit("auth")
mineunit("server")
sourcefile("init")

local NODE_NAME = "modular_computers:computer"
local FORMNAME = "modular_computers:computer_formspec"

-- Splits formspec list content on unescaped separators and removes the escapes
local function split_escaped(text, separator)
	local items, current, escaped = {}, {}, false
	for char in text:gmatch(".") do
		if escaped then
			table.insert(current, char)
			escaped = false
		elseif char == "\\" then
			escaped = true
		elseif char == separator then
			table.insert(items, table.concat(current))
			current = {}
		else
			table.insert(current, char)
		end
	end
	table.insert(items, table.concat(current))
	return items
end

-- Rows shown on the terminal screen
local function terminal_rows(form)
	local cells = form:text():match("table%[[^;]*;[^;]*;terminal_out_%d+;(.-);%d+%]")
	assert.not_nil(cells, "terminal output table not found")
	return split_escaped(cells, ",")
end

-- Text in the terminal input field
local function terminal_input(form)
	local value = form:text():match("field%[[^;]*;[^;]*;terminal_in;[^;]*;(.-)%]")
	assert.not_nil(value, "terminal input field not found")
	return split_escaped(value, "")[1]
end

describe(NODE_NAME, function()

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

	-- Type a command into the open terminal and press enter
	local function enter(command)
		mineunit:execute_on_player_receive_fields(player, FORMNAME, {
			terminal_in = command,
			key_enter = "true",
			key_enter_field = "terminal_in",
		})
		return mineunit:get_player_formspec(player)
	end

	-- Press an arrow key while text is typed into the open terminal
	local function press(key, typed)
		mineunit:execute_on_player_receive_fields(player, FORMNAME, { terminal_in = typed, [key] = "true" })
		return terminal_input(mineunit:get_player_formspec(player))
	end

	it("does not stack", function()
		assert.equals(1, ItemStack(NODE_NAME):get_stack_max())

		mineunit:clear_InvRef(player:get_inventory())
		player:get_inventory():add_item("main", NODE_NAME)
		player:get_inventory():add_item("main", NODE_NAME)
		assert.has_item(player, "main", 1, NODE_NAME .. " 1")
		assert.has_item(player, "main", 2, NODE_NAME .. " 1")
	end)

	it("can be placed", function()
		mineunit:clear_InvRef(player:get_inventory())
		player:set_wielded_item(NODE_NAME)
		-- Try to place one from above
		player:do_set_pos_fp({x=0, y=2, z=0})
		player:do_place({x=0, y=1, z=0})

		-- Check for in world node
		assert.nodename(NODE_NAME, {x=0, y=0, z=0})
		-- Make sure our only computer was used
		assert.is_true(player:get_wielded_item():is_empty())
	end)

	it("can be placed with aux1", function()
		player:set_wielded_item(NODE_NAME)
		-- Try to place one from below, this one should go above your head
		player:do_set_pos_fp({x=1, y=-1, z=1})
		player:do_place({x=1, y=0, z=1}, { aux1 = true })

		-- Check for in world node
		assert.nodename(NODE_NAME, {x=1, y=1, z=1})
		assert.is_true(player:get_wielded_item():is_empty())
	end)

	it("can be used", function()
		player:set_wielded_item(NODE_NAME)
		-- Maybe it does something if we'd just use it
		player:do_set_pos_fp({x=1, y=-1, z=1})
		player:do_use({x=2, y=0, z=1})

		-- Check that we still have our computer
		assert.has_item(player, "main", 1, NODE_NAME .. " 1")
	end)

	it("can be used with aux1", function()
		player:set_wielded_item(NODE_NAME)
		-- Using it didn't do anything interesting, maybe if we'd hold aux1 and try again
		player:do_set_pos_fp({x=1, y=-1, z=1})
		player:do_use({x=2, y=0, z=1}, { aux1 = true })

		-- Make sure nobody stole our computer
		assert.has_item(player, "main", 1, NODE_NAME .. " 1")
	end)

	it("opens a black terminal when right clicked", function()
		-- Take away any leftover stuff
		mineunit:clear_InvRef(player:get_inventory())

		player:do_place_from_above({x=1, y=1, z=1})

		local form = mineunit:get_player_formspec(player)
		assert.is_Form(form)
		assert.equals(FORMNAME, form:name())
		assert.is_truthy(form:text():find("bgcolor[#000000;false]", 1, true))
		-- Enter runs commands without closing the terminal, there is no button for it
		assert.is_truthy(form:text():find("field_close_on_enter[terminal_in;false]", 1, true))
		assert.is_nil(form:one(".*", "button"))
		-- A new computer greets the player
		assert.is_truthy(table.concat(terminal_rows(form), "\n"):find("help", 1, true))
		assert.equals("", terminal_input(form))
	end)

	it("accepts echo command", function()
		local form = enter("echo Hello World")

		local rows = terminal_rows(form)
		assert.equals("$ echo Hello World", rows[#rows - 1])
		assert.equals("Hello World", rows[#rows])
		assert.equals("", terminal_input(form))
	end)

	it("keeps the newest output right above the prompt", function()
		local rows = terminal_rows(enter("echo bottom"))
		assert.is_true(#rows >= modular_computers.terminal.ROWS)
		assert.equals("bottom", rows[#rows])
	end)

	it("reports unknown commands", function()
		local rows = terminal_rows(enter("frobnicate"))
		assert.equals("$ frobnicate", rows[#rows - 1])
		assert.is_truthy(rows[#rows]:find("command not found", 1, true))
	end)

	it("recalls commands with the arrow keys", function()
		enter("echo one")
		enter("echo two")

		assert.equals("echo two", press("key_up", "draft"))
		assert.equals("echo one", press("key_up", "echo two"))
		assert.equals("echo two", press("key_down", "echo one"))
		assert.equals("draft", press("key_down", "echo two"))
		assert.equals("draft", press("key_down", "draft"))
	end)

	it("keeps typed text when the output is clicked", function()
		mineunit:execute_on_player_receive_fields(player, FORMNAME, { terminal_in = "ech", terminal_out_1 = "CHG:3:1" })
		assert.equals("ech", terminal_input(mineunit:get_player_formspec(player)))
	end)

	it("clears the screen", function()
		for _, row in ipairs(terminal_rows(enter("clear"))) do
			assert.equals("", row)
		end
	end)

	it("switches redstone outputs", function()
		local pos = {x=1, y=1, z=1}
		enter("redstone set front on")
		assert.nodename(NODE_NAME .. "_100000", pos)
		enter("redstone set all on")
		assert.nodename(NODE_NAME .. "_111111", pos)
		enter("redstone set all off")
		assert.nodename(NODE_NAME, pos)

		local rows = terminal_rows(enter("redstone set sideways on"))
		assert.is_truthy(table.concat(rows, "\n"):find("usage: redstone", 1, true))
		assert.nodename(NODE_NAME, pos)
	end)

	it("shows the redstone state of every side", function()
		local pos = {x=1, y=1, z=1}
		enter("redstone set top on")
		local rows = terminal_rows(enter("redstone"))
		enter("redstone set top off")

		-- This computer was placed against the ceiling, so it is upside down
		local direction_name = modular_computers.redstone.get_direction_name
		assert.equals("down", direction_name(pos, "top"))
		assert.equals(string.format("front   %-6s in 0   out off", direction_name(pos, "front")), rows[#rows - 5])
		assert.equals("top     down   in 0   out on", rows[#rows - 1])
	end)

	it("stops taking commands once closed", function()
		local pos = {x=1, y=1, z=1}
		local name = core.get_node(pos).name
		mineunit:execute_on_player_receive_fields(player, FORMNAME, { quit = "true" })
		enter("redstone set bottom on")
		assert.nodename(name, pos)
	end)

end)
