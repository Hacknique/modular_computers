require("mineunit")

mineunit("core")

-- A clock that doesn't move, so only the instruction budget limits programs here
function core.get_us_time()
	return 0
end

sourcefile("init")

describe("sandbox", function()

	local sandbox = modular_computers.sandbox

	-- Runs source in a fresh sandbox; returns the task and the results of resuming it
	local function run(source, options)
		local env, string_library = sandbox.new_environment()
		options = options or {}
		options.string = string_library
		local task = sandbox.new_task(options)
		local fn = assert(sandbox.load(source, "test", env))
		local results = sandbox.resume(task, coroutine.create(fn))
		return task, results, env
	end

	it("runs code and returns its results", function()
		local task, results = run("return 1 + 2, ('x'):rep(3)")
		assert.is_nil(task.killed)
		assert.same({ n = 3, true, 3, "xxx" }, results)
	end)

	it("stops code that runs too long", function()
		local task = run("while true do end", { instructions = 100000 })
		assert.equals("too long without yielding", task.killed)
	end)

	it("doesn't let pcall or coroutines catch the stop", function()
		local task, _, env = run([[
			caught = pcall(function() while true do end end)
		]], { instructions = 100000 })
		assert.equals("too long without yielding", task.killed)
		assert.is_nil(env.caught)

		task, _, env = run([[
			local co = coroutine.create(function() while true do end end)
			resumed = coroutine.resume(co)
		]], { instructions = 100000 })
		assert.equals("too long without yielding", task.killed)
		assert.is_nil(env.resumed)
	end)

	it("stops slow pattern matching", function()
		local task = run([[ ("a"):rep(20000):find(".-.-.-.-b") ]], { instructions = 200000 })
		assert.equals("too long without yielding", task.killed)
	end)

	it("charges library functions for their work", function()
		local task = run([[
			local t = {}
			for i = 1, 5000 do t[i] = i end
			while true do table.sort(t) end
		]], { instructions = 200000 })
		assert.equals("too long without yielding", task.killed)
	end)

	it("refuses huge strings", function()
		local _, results = run([[ return pcall(string.rep, "x", 1e9) ]])
		assert.is_false(results[2])
		assert.is_truthy(results[3]:find("too large", 1, true))
	end)

	it("hides the server", function()
		local _, results = run([[
			return getmetatable(""), rawget(_G, "minetest"), string.dump, setfenv, getfenv, debug.getinfo, loadstring
		]])
		assert.same({ n = 8, true }, results)
		assert.same({ nil, "binary chunks are not allowed" }, { sandbox.load(string.char(27) .. "Lua", "x", {}) })
	end)

	it("gives programs their own string library", function()
		local _, results = run([[
			string.upper = function() return "changed" end
			return ("a"):upper()
		]])
		assert.equals("changed", results[2])
		assert.equals("A", ("a"):upper())
		assert.equals(string, getmetatable("").__index)
	end)

	it("turns errors into messages without running program code", function()
		local _, results = run([[ error(setmetatable({}, { __tostring = function() while true do end end })) ]])
		assert.is_false(results[1])
		assert.equals("(error object is a table value)", sandbox.error_message(results[2]))
	end)

	it("stops strings that would take too much memory", function()
		local attacks = {
			'local s = ("x"):rep(8) for i = 1, 40 do s = s .. s end',
			'local s = ("x"):rep(8) for i = 1, 40 do s = s .. s .. s end',
			'local sep = ("x"):rep(100000) local t = {} for i = 1, 301 do t[i] = "" end return table.concat(t, sep)',
			'local big = ("x"):rep(100000) return (("a"):rep(300):gsub(".", function() return big end))',
			'return (("x"):rep(20000):gsub(".+", ("%0"):rep(500)))',
			'local s = ("x"):rep(1000) for i = 1, 40 do s = ("%s%s"):format(s, s) end',
			'local s, t = ("x"):rep(500000), {} for i = 1, 100 do t[i] = s:sub(i) end',
		}
		for _, attack in ipairs(attacks) do
			local task = run(attack, { memory = 4096 })
			assert.equals("not enough memory", task.killed, attack)
		end
	end)

	it("concatenates like Lua does", function()
		local _, results = run([[
			local meta = setmetatable({}, { __concat = function(a, b)
				return (type(a) == "table" and "T" or a) .. "+" .. (type(b) == "table" and "T" or b)
			end })
			return 1 .. 2, "a" .. "b" .. 3, meta .. "x", "x" .. meta, "a" .. "b" .. meta, (1 .. ""):len()
		]])
		-- Right to left: "b" .. meta first
		assert.same({ n = 7, true, "12", "ab3", "T+x", "x+T", "ab+T", 1 }, results)
	end)

	it("reports concatenation errors where they happen", function()
		local _, results = run('local x\n\nreturn "a" .. x')
		assert.is_false(results[1])
		assert.equals("test:3: attempt to concatenate a nil value", results[2])
		_, results = run('return pcall(function() return {} .. "a" .. "b" end)')
		assert.is_false(results[2])
		assert.equals("test:1: attempt to concatenate a table value", results[3])
		-- Errors in __concat metamethods keep their own place
		_, results = run('local t = setmetatable({}, { __concat = function() error("mine") end })\nreturn t .. "a"')
		assert.equals("test:1: mine", results[2])
	end)

	it("gives programs their own random numbers", function()
		local before = math.random()
		local _, first = run("math.randomseed(7) return math.random(), math.random(10), math.random(5, 6)")
		local _, second = run("math.randomseed(7) return math.random(), math.random(10), math.random(5, 6)")
		assert.same(first, second)
		assert.is_true(first[2] >= 0 and first[2] < 1)
		assert.is_true(first[3] >= 1 and first[3] <= 10)
		assert.is_true(first[4] == 5 or first[4] == 6)
		assert.not_equals(before, math.random())
	end)

	it("keeps server paths out of error messages", function()
		local strip = sandbox.strip_paths
		assert.equals("components.lua:123: bad argument",
			strip("/home/u/.minetest/mods/modular_computers/src/os/components.lua:123: bad argument"))
		assert.equals("x.lua:1: z.lua:2: two", strip("/a/mods/x.lua:1: /b/mods/y/z.lua:2: two"))
		assert.equals("x.lua:5: windows", strip("C:\\Users\\u\\mods\\mc\\x.lua:5: windows"))
		assert.equals("/test.lua:3: a program's own error", strip("/test.lua:3: a program's own error"))
		-- Long messages made by programs go through once
		local long = ("a/mods/b"):rep(20000)
		assert.equals(long, strip(long))

		local _, results = run([[ return debug.traceback(("x"):rep(100000) .. "/mods/") ]])
		assert.equals(("x"):rep(100000) .. "/mods/", results[2]:sub(1, 100006))
		-- The program's message keeps its text; lines of the stack in the server's files go
		assert.is_nil(results[2]:find("/mods/", 100007, true))
	end)

	it("refuses long date formats", function()
		local _, results = run([[ return pcall(os.date, ("%c"):rep(1000)) ]])
		assert.is_false(results[2])
		assert.is_truthy(results[3]:find("format too long", 1, true))
		_, results = run([[ return os.date("!%Y", 0) ]])
		assert.equals("1970", results[2])
	end)

	it("charges string.format for many arguments", function()
		local task = run([[
			local t = {} for i = 1, 7000 do t[i] = 1 end
			local format = ("%d"):rep(7000)
			while true do string.format(format, unpack(t)) end
		]], { instructions = 1000000, memory = 65536 })
		assert.equals("too long without yielding", task.killed)
	end)

	it("gives bit32 unsigned results", function()
		if not rawget(_G, "bit") then
			return
		end
		local _, results = run([[ return bit32.bnot(0), bit32.band(0xFFFFFFFF, 0xF0F0F0F0) ]])
		assert.same({ n = 3, true, 4294967295, 4042322160 }, results)
	end)

end)

describe("patterns", function()

	local patterns = modular_computers.patterns

	-- The Lua matcher gives the same results as the one in C, or fails when it fails
	local function same(expected, actual, message)
		if expected[1] or actual[1] then
			assert.same(expected, actual, message)
		end
	end

	local subjects = { "", "hello world", "  key = value  ", "a,b,,c", "(nested (parens))", "x = 1; y = 22",
		"aaa", "\0zero\0", "THE end", "%d literal", "a.b.c" }
	local cases = { "l+", "(%w+) (%w+)", "^%s*(.-)%s*$", "[^,]*", "%b()", "(%a)%s*=%s*(%d+)", "a-", "a*?",
		"%z", "%u+", "%%d", "[%.]", "()a", "(a)%1", "[a-c]+", "[^%s]+$", "%f[%w]%w+", "x?y", "." }

	it("finds what string.find finds", function()
		for _, s in ipairs(subjects) do
			for _, p in ipairs(cases) do
				same({ pcall(string.find, s, p) }, { pcall(patterns.find, s, p) }, s .. " / " .. p)
				same({ pcall(string.match, s, p) }, { pcall(patterns.match, s, p) }, s .. " / " .. p)
			end
		end
	end)

	it("replaces what string.gsub replaces", function()
		for _, s in ipairs(subjects) do
			for _, p in ipairs(cases) do
				same({ pcall(string.gsub, s, p, "<%0>") }, { pcall(patterns.gsub, s, p, "<%0>") }, s .. " / " .. p)
			end
			assert.same({ string.gsub(s, "%w+", string.upper) }, { patterns.gsub(s, "%w+", string.upper) })
			assert.same({ string.gsub(s, "(%w+)", { hello = "bye" }) }, { patterns.gsub(s, "(%w+)", { hello = "bye" }) })
		end
	end)

	it("iterates like string.gmatch", function()
		for _, s in ipairs(subjects) do
			for _, p in ipairs(cases) do
				local expected, actual = {}, {}
				local ok = pcall(function()
					for a, b in string.gmatch(s, p) do
						table.insert(expected, { a, b })
					end
				end)
				if ok then
					for a, b in patterns.gmatch(s, p) do
						table.insert(actual, { a, b })
					end
					assert.same(expected, actual, s .. " / " .. p)
				end
			end
		end
	end)

end)
