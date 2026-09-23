-- Modules: require loads libraries from /lib on the hard drive or those that come with the computer
local host, loaded = ...
local package = { loaded = loaded, preload = {}, path = "/lib/?.lua;/usr/lib/?.lua;./?.lua" }

function _G.loadfile(path, _, environment)
    local source, resolved = host.read_file(path)
    if not source then
        return nil, resolved
    end
    return load(source, resolved, "t", environment)
end

function _G.dofile(path)
    local fn = assert(loadfile(path))
    return fn()
end

function _G.require(name)
    if type(name) ~= "string" then
        error("bad argument #1 to 'require' (string expected)", 2)
    end
    if loaded[name] ~= nil then
        return loaded[name]
    end
    if package.preload[name] then
        local module = package.preload[name](name)
        loaded[name] = module == nil and true or module
        return loaded[name]
    end
    local file_name = name:gsub("%.", "/")
    local tried = {}
    for template in package.path:gmatch("[^;]+") do
        local path = template:gsub("%?", function() return file_name end)
        local source, resolved = host.read_file(path)
        if source then
            local fn, err = load(source, resolved)
            if not fn then
                error(err, 2)
            end
            local module = fn(name)
            loaded[name] = module == nil and true or module
            return loaded[name]
        end
        table.insert(tried, "\n\tno file '" .. path .. "'")
    end
    error("module '" .. name .. "' not found:" .. table.concat(tried), 2)
end

return package
