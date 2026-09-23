require("mineunit")

mineunit("core")
mineunit("server")
sourcefile("init")

describe("terminal", function()

	local terminal = modular_computers.terminal
	local command = modular_computers.command

	world.set_default_node({name="air",param2=0})
	mineunit:mods_loaded()

	local function new_meta(x)
		local pos = {x=x, y=100, z=0}
		world.set_node(pos, {name="air"})
		return core.get_meta(pos)
	end

	it("wraps long lines", function()
		local rows = terminal.get_rows(string.rep("a", 100) .. "\n", "")
		assert.same({ string.rep("a", 80), string.rep("a", 20) }, rows)
	end)

	it("counts multibyte characters as one column", function()
		local rows = terminal.get_rows(string.rep("ї", 81) .. "\n", "")
		assert.same({ string.rep("ї", 80), "ї" }, rows)
	end)

	it("removes escape sequences and control characters", function()
		local rows = terminal.get_rows(core.colorize("#FF0000", "red") .. "\7\tbell\r\n", "")
		assert.same({ "red    bell" }, rows)
	end)

	it("keeps a limited scrollback", function()
		local meta = new_meta(1)
		for i = 1, terminal.MAX_LINES + 5 do
			terminal.append(meta, "line " .. i .. "\n")
		end
		local rows = terminal.get_rows(terminal.get_text(meta), "")
		assert.equals(terminal.MAX_LINES, #rows)
		assert.equals("line 6", rows[1])
		assert.equals("line " .. (terminal.MAX_LINES + 5), rows[#rows])
	end)

	it("clears the screen", function()
		local meta = new_meta(2)
		terminal.append(meta, "old\n")
		terminal.append(meta, "gone\n" .. terminal.CLEAR .. "new")
		assert.equals("new\n", terminal.get_text(meta))
	end)

	it("remembers commands once", function()
		local meta = new_meta(3)
		terminal.add_history(meta, "ls")
		terminal.add_history(meta, "ls")
		terminal.add_history(meta, "echo hi")
		assert.same({ "ls", "echo hi" }, terminal.get_history(meta))
	end)

	it("escapes the typed text", function()
		assert.is_truthy(terminal.formspec("", "a;b]", ""):find("terminal_in;;a\\;b\\]]", 1, true))
	end)

	it("reports unknown commands", function()
		assert.is_truthy(command.execute("frobnicate"):find("command not found", 1, true))
	end)

	it("survives commands that fail", function()
		command.register("explode", { func = function() error("boom") end })
		assert.is_truthy(command.execute("explode"):find("boom", 1, true))
	end)

	it("tells commands which computer runs them", function()
		local seen
		command.register("where", { func = function()
			seen = command.get_computer_pos()
		end })
		command.execute_at({x=1, y=2, z=3}, "where")
		assert.same({x=1, y=2, z=3}, seen)
		assert.is_nil(command.get_computer_pos())
	end)

	it("lists commands", function()
		local output = command.execute("help")
		for _, name in ipairs({ "clear", "echo", "help", "redstone" }) do
			assert.is_truthy(output:find(name, 1, true))
		end
	end)

end)
