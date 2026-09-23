-- The working directory, and running programs from other programs
local host = ...
local shell = {}

function shell.getWorkingDirectory() return host.cwd() end

function shell.setWorkingDirectory(path)
    return host.set_cwd(path)
end

function shell.getPath() return os.getenv("PATH") end
function shell.setPath(value) os.setenv("PATH", value) end

-- Finds the file of a program: a path, or a name looked up in PATH, with or without .lua
function shell.resolve(path, extension)
    if path:find("/", 1, true) then
        local resolved = host.resolve(path)
        if resolved and filesystem.exists(resolved) and not filesystem.isDirectory(resolved) then
            return resolved
        end
        if resolved and filesystem.exists(resolved .. ".lua") then
            return resolved .. ".lua"
        end
        return nil, "file not found"
    end
    for directory in (os.getenv("PATH") or "/bin"):gmatch("[^:]+") do
        for _, name in ipairs({ path .. "." .. (extension or "lua"), path }) do
            local candidate = host.resolve(directory .. "/" .. name)
            if candidate and host.read_file(candidate) then
                return candidate
            end
        end
    end
    return nil, "file not found"
end

-- Splits arguments into plain arguments and options (-x and --name=value)
function shell.parse(...)
    local args, options = {}, {}
    local all = table.pack(...)
    for i = 1, all.n do
        local value = all[i]
        if type(value) == "string" and value:sub(1, 2) == "--" and #value > 2 then
            local name, option = value:match("^%-%-([^=]+)=?(.*)$")
            options[name] = option ~= "" and option or true
        elseif type(value) == "string" and value:sub(1, 1) == "-" and #value > 1 then
            for letter in value:sub(2):gmatch(".") do
                options[letter] = true
            end
        else
            table.insert(args, value)
        end
    end
    return args, options
end

-- Runs a program in this program, with arguments separated by spaces
function shell.execute(command, environment, ...)
    local words = {}
    for word in command:gmatch("%S+") do
        table.insert(words, word)
    end
    if #words == 0 then
        return true
    end
    local path, err = shell.resolve(words[1])
    if not path then
        return false, words[1] .. ": " .. err
    end
    local fn
    fn, err = loadfile(path, nil, setmetatable({}, { __index = environment or _G }))
    if not fn then
        return false, err
    end
    local args = { table.unpack(words, 2) }
    for _, value in ipairs({ ... }) do
        table.insert(args, value)
    end
    return pcall(fn, table.unpack(args))
end

return shell
