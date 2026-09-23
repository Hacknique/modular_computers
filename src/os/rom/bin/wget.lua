-- Downloads a file with the internet card: wget <url> [file]
local url, path = ...
if not url then
    print("usage: wget <url> [file]")
    return
end
if not component.isAvailable("internet") then
    print("wget: this computer has no internet card")
    return
end
if not internet.isHttpEnabled() then
    print("wget: HTTP requests are turned off on this server")
    return
end
if not path then
    local address = url:gsub("[?#].*$", "")
    path = address:match("^%a[%w+.-]*://[^/]+/.-([^/]+)$") or "index.html"
end

local ok, result = pcall(function()
    local chunks = {}
    for chunk in internet.request(url) do
        table.insert(chunks, chunk)
    end
    return table.concat(chunks)
end)
if not ok then
    print("wget: " .. tostring(result))
    return
end

local file, err = io.open(path, "w")
if not file then
    print("wget: " .. tostring(err))
    return
end
file:write(result)
file:close()
print("Saved " .. #result .. " bytes to " .. path)
