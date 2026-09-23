require("mineunit")

-- Load fixtures and mod
mineunit("core")
mineunit("auth")
mineunit("server")
sourcefile("init")

local TOWER = "modular_computers:tower"
local MONITOR = "modular_computers:monitor"
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

describe("computer", function()

	world.set_default_node({name="air",param2=0})

	local player = Player("Sam")
	local tower_pos = {x=1, y=0, z=1}
	local monitor_pos = {x=1, y=1, z=1}

	-- Execute on mods loaded callbacks to finish loading.
	mineunit:mods_loaded()
	-- Tell mods that 1 minute passed already to execute all weird core.after hacks.
	mineunit:execute_globalstep(60)

	-- Screens are entities, which mineunit can't run: see display_spec.lua for the screen logic
	modular_computers.display.update = function() end

	setup(function()
		mineunit:execute_on_joinplayer(player)
	end)

	teardown(function()
		mineunit:execute_on_leaveplayer(player)
	end)

	-- Puts an item into a slot of the tower like a player would, returns whether it went in
	local function put(list, item)
		local stack = ItemStack(item)
		local def = core.registered_nodes[core.get_node(tower_pos).name]
		if def.allow_metadata_inventory_put(tower_pos, list, 1, stack, player) == 0 then
			return false
		end
		core.get_meta(tower_pos):get_inventory():set_stack(list, 1, stack)
		def.on_metadata_inventory_put(tower_pos, list, 1, stack, player)
		return true
	end

	local function take(list)
		local inv = core.get_meta(tower_pos):get_inventory()
		local stack = inv:get_stack(list, 1)
		local def = core.registered_nodes[core.get_node(tower_pos).name]
		inv:set_stack(list, 1, ItemStack(nil))
		def.on_metadata_inventory_take(tower_pos, list, 1, stack, player)
		return stack
	end

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
		for _, name in ipairs({ TOWER, MONITOR, "modular_computers:cpu_tier_1" }) do
			assert.equals(1, ItemStack(name):get_stack_max())
		end

		mineunit:clear_InvRef(player:get_inventory())
		player:get_inventory():add_item("main", TOWER)
		player:get_inventory():add_item("main", TOWER)
		assert.has_item(player, "main", 1, TOWER .. " 1")
		assert.has_item(player, "main", 2, TOWER .. " 1")
	end)

	it("turns old computers into monitors", function()
		assert.equals(MONITOR, core.registered_aliases["modular_computers:computer"])
		assert.equals(MONITOR, core.registered_aliases["modular_computers:computer_100000"])
	end)

	it("can be placed", function()
		mineunit:clear_InvRef(player:get_inventory())
		player:set_wielded_item(TOWER)
		player:do_set_pos_fp({x=1, y=2, z=1})
		player:do_place({x=1, y=1, z=1})
		assert.nodename(TOWER, tower_pos)
		assert.is_true(player:get_wielded_item():is_empty())

		world.set_node(monitor_pos, {name=MONITOR, param2=0})
	end)

	it("needs a computer tower under the monitor", function()
		world.set_node({x=5, y=1, z=5}, {name=MONITOR, param2=0})
		player:do_place_from_above({x=5, y=1, z=5})
		assert.is_nil(mineunit:get_player_formspec(player))
	end)

	it("does not open the terminal without parts", function()
		player:do_place_from_above(monitor_pos)
		assert.is_nil(mineunit:get_player_formspec(player))
		assert.same({ "Motherboard" }, modular_computers.computer.get_missing(tower_pos))
	end)

	it("takes components up to the tier of its motherboard", function()
		assert.is_false(put("cpu", "modular_computers:cpu_tier_1"))
		assert.is_false(put("motherboard", "modular_computers:cpu_tier_1"))
		assert.is_true(put("motherboard", "modular_computers:motherboard_tier_2"))
		assert.is_false(put("cpu", "modular_computers:cpu_tier_3"))
		assert.is_false(put("cpu", "modular_computers:gpu_tier_1"))
		assert.is_true(put("cpu", "modular_computers:cpu_tier_2"))
		assert.is_true(put("gpu", "modular_computers:gpu_tier_1"))
		assert.is_false(modular_computers.computer.is_running(tower_pos))
		assert.same({ "RAM", "Hard Drive" }, modular_computers.computer.get_missing(tower_pos))
	end)

	it("keeps components on the motherboard", function()
		local motherboard = take("motherboard")
		local inv = core.get_meta(tower_pos):get_inventory()
		assert.is_true(inv:is_empty("cpu"))
		assert.is_true(inv:is_empty("gpu"))
		local installed = modular_computers.hardware.get_installed(motherboard)
		assert.equals("modular_computers:cpu_tier_2", ItemStack(installed.cpu):get_name())

		assert.is_true(put("motherboard", motherboard))
		assert.equals("modular_computers:cpu_tier_2", inv:get_stack("cpu", 1):get_name())
		assert.equals("modular_computers:gpu_tier_1", inv:get_stack("gpu", 1):get_name())
	end)

	it("starts when it has all parts", function()
		assert.is_true(put("ram", "modular_computers:ram_tier_1"))
		assert.is_true(put("hdd", "modular_computers:hdd_tier_2"))
		assert.is_true(modular_computers.computer.is_running(tower_pos))
	end)

	it("opens a black terminal when the monitor is right clicked", function()
		mineunit:clear_InvRef(player:get_inventory())
		player:do_place_from_above(monitor_pos)

		local form = mineunit:get_player_formspec(player)
		assert.is_Form(form)
		assert.equals(FORMNAME, form:name())
		assert.is_truthy(form:text():find("bgcolor[#000000;false]", 1, true))
		-- Enter runs commands without closing the terminal, there is no button for it
		assert.is_truthy(form:text():find("field_close_on_enter[terminal_in;false]", 1, true))
		assert.is_nil(form:one(".*", "button"))
		-- The computer greets the player when it starts
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

	it("switches the tower's redstone outputs", function()
		enter("redstone set front on")
		assert.nodename(TOWER .. "_100000", tower_pos)
		enter("redstone set all on")
		assert.nodename(TOWER .. "_111111", tower_pos)
		enter("redstone set all off")
		assert.nodename(TOWER, tower_pos)

		local rows = terminal_rows(enter("redstone set sideways on"))
		assert.is_truthy(table.concat(rows, "\n"):find("usage: redstone", 1, true))
		assert.nodename(TOWER, tower_pos)
	end)

	it("shows the redstone state of every side", function()
		enter("redstone set top on")
		local rows = terminal_rows(enter("redstone"))
		enter("redstone set top off")

		local direction_name = modular_computers.redstone.get_direction_name
		assert.equals(string.format("front   %-6s in 0   out off", direction_name(tower_pos, "front")), rows[#rows - 5])
		assert.equals("top     up     in 0   out on", rows[#rows - 1])
	end)

	it("stops when a part is taken out", function()
		enter("redstone set bottom on")
		take("ram")
		assert.is_false(modular_computers.computer.is_running(tower_pos))
		-- Its outputs switch off with it
		assert.nodename(TOWER, tower_pos)
		-- And its terminal stops taking commands
		enter("redstone set bottom on")
		assert.nodename(TOWER, tower_pos)
	end)

	it("stops taking commands once closed", function()
		assert.is_true(put("ram", "modular_computers:ram_tier_1"))
		player:do_place_from_above(monitor_pos)
		mineunit:execute_on_player_receive_fields(player, FORMNAME, { quit = "true" })
		enter("redstone set bottom on")
		assert.nodename(TOWER, tower_pos)
	end)

end)
