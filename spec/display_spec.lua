require("mineunit")

mineunit("core")
mineunit("server")
sourcefile("init")

describe("display", function()

	local TOWER = "modular_computers:tower"
	local MONITOR = "modular_computers:monitor"
	local display = modular_computers.display

	world.set_default_node({name="air",param2=0})
	mineunit:mods_loaded()

	-- Screens are entities, which mineunit can't run
	display.update = function() end

	local function tower(x, z)
		world.set_node({x=x, y=0, z=z}, {name=TOWER, param2=0})
		return {x=x, y=0, z=z}
	end

	local function monitor(x, y, z, param2)
		world.set_node({x=x, y=y, z=z}, {name=MONITOR, param2=param2 or 0})
	end

	local function size(tower_pos)
		local wall = display.get_wall(tower_pos)
		return wall and { wall.width, wall.height }
	end

	it("starts at the monitor on top of the tower", function()
		local pos = tower(0, 0)
		assert.is_nil(display.get_wall(pos))
		monitor(0, 1, 0)
		assert.same({ 1, 1 }, size(pos))
	end)

	it("joins monitors beside and above", function()
		local pos = {x=0, y=0, z=0}
		monitor(-1, 1, 0)
		monitor(1, 1, 0)
		monitor(-1, 2, 0)
		monitor(0, 2, 0)
		assert.same({ 3, 1 }, size(pos))
		monitor(1, 2, 0)
		assert.same({ 3, 2 }, size(pos))
		assert.same({x=0, y=0, z=0}, display.find_tower({x=1, y=2, z=0}))
		assert.same({x=0, y=0, z=0}, display.find_tower({x=-1, y=1, z=0}))
	end)

	it("only joins monitors facing the same way", function()
		monitor(-2, 1, 0, 1)
		assert.same({ 3, 2 }, size({x=0, y=0, z=0}))
		assert.is_nil(display.find_tower({x=-2, y=1, z=0}))
	end)

	it("shares a row of monitors between towers", function()
		local left, right = tower(10, 0), tower(13, 0)
		for x = 10, 13 do
			monitor(x, 1, 0)
		end
		assert.same({ 2, 1 }, size(left))
		assert.same({ 2, 1 }, size(right))
		assert.same(left, display.find_tower({x=11, y=1, z=0}))
		assert.same(right, display.find_tower({x=12, y=1, z=0}))
	end)

	it("gives a monitor to the tower under it", function()
		local left = tower(20, 0)
		for x = 20, 22 do
			monitor(x, 1, 0)
		end
		assert.same({ 3, 1 }, size(left))
		local right = tower(22, 0)
		assert.same({ 2, 1 }, size(left))
		assert.same({ 1, 1 }, size(right))
	end)

	it("limits the size of a screen", function()
		local pos = tower(30, 0)
		for x = 25, 40 do
			for y = 1, 8 do
				monitor(x, y, 0)
			end
		end
		assert.same({ display.MAX_WIDTH, display.MAX_HEIGHT }, size(pos))
	end)

	it("makes the text bigger on bigger screens", function()
		local one = { width = 1, height = 1 }
		local four = { width = 2, height = 2 }
		assert.same({ 20, 12 }, { display.get_grid(one, 1) })
		assert.same({ 20, 12 }, { display.get_grid(four, 1) })
		-- Better GPUs show more text
		assert.same({ 33, 20 }, { display.get_grid(one, 3) })
		-- Wide screens show longer lines
		local columns, rows = display.get_grid({ width = 3, height = 1 }, 1)
		assert.is_true(columns > 20)
		assert.is_true(rows <= 12)
	end)

	it("draws text with font glyphs", function()
		local texture = display.render({ "Hi", "", "?" }, 20, 12, "#D0D0D0")
		assert.equals("[fill:124x124:#000000^[combine:124x124:2,2=modular_computers_font_48.png:"
			.. "8,2=modular_computers_font_69.png:2,22=modular_computers_font_3f.png^[multiply:#D0D0D0", texture)
		-- Characters the font doesn't have show as question marks
		assert.is_truthy(display.render({ "ї" }, 20, 12, "#D0D0D0"):find("font_3f.png", 1, true))
	end)

end)
