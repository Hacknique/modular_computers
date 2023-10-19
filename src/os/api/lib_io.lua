function modular_computers.internal.luaopen_io(stdin, stdout, stderr)
    local lib = {
        stdin = stdin,
        stdout = stdout,
        stderr = stderr,
    }

    function lib.close(f)
        if f == nil then
            return stdout:close()
        end
        return f:close()
    end

    function lib.flush()
        return stdout:flush()
    end

    function lib.input(x)
        if x ~= nil then
            stdin = x
        end
        return stdin
    end

    function lib.lines(path)
        local file = stdin
        if path ~= nil then
            file = lib.open(path)
            if file == nil then
                -- TODO: when a sandbox is implemented, throw an error instead
                return function() return nil end
            end
        end
        local func = file:lines()
        return function()
            local x = func()
            if x == nil then
                file:close()
            end
            return x
        end
    end

    function lib.open()
        return nil, "Not implemented"
    end

    function lib.output(x)
        if x ~= nil then
            stdout = x
        end
        return stdout
    end

    -- TODO: maybe implement io.popen? (Lua 5.1 does not require this though)

    function lib.read(...)
        return stdin.read(...)
    end

    function lib.tmpfile(...)
        return nil, "Not implemented"
    end

    function lib.type(f)
        local st, val = pcall(f.is_closed, f)
        if not st then
            return nil
        elseif val then
            return "closed file"
        else
            return "file"
        end
    end

    function lib.write(...)
        return stdout.write(...)
    end

    local function print(...)
        local count = select("#", ...)
        local args = {...}
        local st = {}
        for k = 1, count do
            st[k] = tostring(args[k])
        end
        stdout:write(table.concat(st, "\t") .. "\n")
    end

    return lib, print
end
