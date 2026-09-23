-- Lists the components of the computer: components [type]
local filter = ...
local list = {}
for address, kind in component.list(filter) do
    table.insert(list, { kind, address })
end
table.sort(list, function(a, b)
    return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
end)
for _, entry in ipairs(list) do
    print(string.format("%-11s %s", entry[1], entry[2]))
end
