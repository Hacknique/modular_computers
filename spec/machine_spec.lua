require("mineunit")

mineunit("core")
mineunit("auth")
mineunit("server")

-- A clock that only moves when the tests let time pass, so time limits don't depend on how
-- fast the tests run
local now = 0
function core.get_us_time()
	return now
end

sourcefile("init")

local TOWER = "modular_computers:tower"
local MONITOR = "modular_computers:monitor"
local FORMNAME = "modular_computers:computer_formspec"

describe("machine", function()

	world.set_default_node({name="air",param2=0})

	local player = Player("Kim")
	local tower_pos = {x=1, y=1, z=1}
	local monitor_pos = {x=1, y=2, z=1}
	local machine = modular_computers.machine
	local drive = modular_computers.os.fs.drive
	local terminal = modular_computers.terminal

	mineunit:mods_loaded()
	mineunit:execute_globalstep(60)

	-- Screens are entities, which mineunit can't run: see display_spec.lua for the screen logic
	modular_computers.display.update = function() end

	setup(function()
		mineunit:execute_on_joinplayer(player)
	end)

	teardown(function()
		mineunit:execute_on_leaveplayer(player)
	end)

	local function put(list, item, index)
		index = index or 1
		local stack = ItemStack(item)
		local def = core.registered_nodes[core.get_node(tower_pos).name]
		if def.allow_metadata_inventory_put(tower_pos, list, index, stack, player) == 0 then
			return false
		end
		core.get_meta(tower_pos):get_inventory():set_stack(list, index, stack)
		def.on_metadata_inventory_put(tower_pos, list, index, stack, player)
		return true
	end

	-- Lets time pass on the server
	local function wait(seconds)
		for _ = 1, math.ceil(seconds / 0.1) do
			now = now + 100000
			mineunit:execute_globalstep(0.1)
		end
	end

	-- The terminal text, without the escapes of translated strings
	local function output()
		return (terminal.get_text(core.get_meta(tower_pos)):gsub("\27%(.-%)", ""):gsub("\27.", ""))
	end

	-- Runs a program from source until it ends, and returns what it wrote on the terminal
	local function run(source, ...)
		local m = machine.get(tower_pos)
		terminal.append(core.get_meta(tower_pos), terminal.CLEAR)
		assert(drive.write(m.drive, "/test.lua", source, drive.CAPACITY[1]))
		assert(machine.run(m, "/test.lua", { ... }))
		for _ = 1, 100 do
			if not m.foreground then
				break
			end
			wait(0.1)
		end
		machine.flush(m)
		return output()
	end

	-- Types a line on the open terminal and presses enter
	local function enter(line)
		mineunit:execute_on_player_receive_fields(player, FORMNAME, {
			terminal_in = line,
			key_enter = "true",
			key_enter_field = "terminal_in",
		})
	end

	it("starts when the tower has all its parts", function()
		world.set_node(tower_pos, {name=TOWER, param2=0})
		world.set_node(monitor_pos, {name=MONITOR, param2=0})
		assert.is_nil(machine.get(tower_pos))
		assert.is_true(put("motherboard", "modular_computers:motherboard_tier_1"))
		for _, kind in ipairs({ "cpu", "gpu", "ram", "hdd" }) do
			assert.is_true(put(kind, "modular_computers:" .. kind .. "_tier_1"))
		end
		assert.not_nil(machine.get(tower_pos))
		-- The hard drive got an id for its files, which stays with it on the motherboard
		local hdd = core.get_meta(tower_pos):get_inventory():get_stack("hdd", 1)
		local id = hdd:get_meta():get_string("drive_id")
		assert.equals(machine.get(tower_pos).drive, id)
		local installed = modular_computers.hardware.get_installed(
			core.get_meta(tower_pos):get_inventory():get_stack("motherboard", 1))
		assert.equals(id, installed.hdd.meta.drive_id)
	end)

	it("runs programs", function()
		assert.equals("hello\t2\n", run('print("hello", 1 + 1)'))
		assert.equals("a\tb\n", run("print(...)", "a", "b"))
		assert.equals("ABC\txxx\t2\n", run('print(("abc"):upper(), ("x"):rep(3), (("a,b"):find(",", 1, true)))'))
	end)

	it("stops programs that don't yield", function()
		assert.is_truthy(run("while true do end"):find("too long without yielding", 1, true))
		local text = run('print(pcall(function() while true do end end)) print("after")')
		assert.is_truthy(text:find("too long without yielding", 1, true))
		assert.is_nil(text:find("after", 1, true))
	end)

	it("keeps programs away from the server", function()
		assert.equals("nil\tnil\tnil\tnil\tnil\n",
			run('print(getmetatable(""), rawget(_G, "minetest"), rawget(_G, "core"), string.dump, setfenv)'))
		assert.is_truthy(run('print(load(string.char(27) .. "Lua"))'):find("binary chunks are not allowed", 1, true))
		run('string.upper = function() return "changed" end')
		assert.equals("A", ("a"):upper())
	end)

	it("wakes sleeping programs and runs timers", function()
		assert.equals("ticks\t3\n", run([[
			local n = 0
			event.timer(0.1, function() n = n + 1 end, 3)
			os.sleep(0.5)
			print("ticks", n)
		]]))
	end)

	it("reads and writes files", function()
		assert.equals("got one\ngot two\n", run([[
			local f = io.open("notes.txt", "w")
			f:write("one\ntwo\n")
			f:close()
			for line in io.lines("notes.txt") do print("got " .. line) end
		]]))
		local m = machine.get(tower_pos)
		assert.equals("one\ntwo\n", drive.read(m.drive, "/notes.txt"))
	end)

	it("runs commands and programs typed on the terminal", function()
		player:do_place_from_above(monitor_pos)
		enter("lua")
		enter("1 + 2")
		wait(0.2)
		enter("exit")
		wait(0.2)
		local text = output()
		assert.is_truthy(text:find("lua> 1 + 2\n3\n", 1, true), text)
		assert.is_nil(machine.get(tower_pos).foreground)

		enter("clear")
		enter("mkdir docs")
		enter("cd docs")
		enter("pwd")
		enter("ls /")
		text = output()
		assert.is_truthy(text:find("$ pwd\n/docs\n", 1, true), text)
		assert.is_truthy(text:find("bin/", 1, true), text)
		assert.is_truthy(text:find("notes.txt", 1, true), text)
	end)

	it("keeps files when it starts again", function()
		local m = machine.get(tower_pos)
		drive.write(m.drive, "/startup.lua", 'print("started", filesystem.exists("/notes.txt"))', drive.CAPACITY[1])
		modular_computers.computer.restart(tower_pos)
		wait(0.2)
		assert.is_truthy(output():find("started\ttrue", 1, true))
		assert.not_equals(m, machine.get(tower_pos))
	end)

	it("adds cards while it runs", function()
		assert.is_true(put("cards", "modular_computers:wireless_card_tier_1"))
		assert.equals("modem\n", run('print(component.modem.type)'))
		assert.equals("16\n", run('print(component.modem.getStrength())'))
	end)

	it("doesn't run a startup.lua that keeps restarting it", function()
		local m = machine.get(tower_pos)
		drive.write(m.drive, "/startup.lua", "computer.shutdown(true)", drive.CAPACITY[1])
		modular_computers.computer.restart(tower_pos)
		wait(1)
		assert.is_truthy(output():find("startup.lua skipped", 1, true))
		assert.is_true(modular_computers.computer.is_running(tower_pos))
		drive.remove(machine.get(tower_pos).drive, "/startup.lua")
	end)

	it("stops when turned off", function()
		run("computer.shutdown()")
		wait(0.2)
		assert.is_false(modular_computers.computer.is_running(tower_pos))
		assert.is_nil(machine.get(tower_pos))
	end)

end)
