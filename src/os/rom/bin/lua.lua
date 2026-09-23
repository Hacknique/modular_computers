-- An interactive Lua prompt. Type exit to leave.
local environment = setmetatable({}, { __index = _G })
print("Lua 5.1 on Modular Computers. Type exit to leave.")
while true do
    io.write("lua> ")
    local line = io.read()
    if line == nil or line == "exit" then
        break
    end
    local fn, err = load("return " .. line, "stdin", "t", environment)
    if not fn then
        fn, err = load(line, "stdin", "t", environment)
    end
    if not fn then
        print(err)
    else
        local results = table.pack(pcall(fn))
        if not results[1] then
            print(results[2])
        elseif results.n > 1 then
            local parts = {}
            for i = 2, results.n do
                parts[i - 1] = tostring(results[i])
            end
            print(table.concat(parts, "\t"))
        end
    end
end
