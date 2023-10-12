function ctr.split(str, delim)
    local result = {}
    for match in string.gmatch(str, "([^" .. delim .. "]+)") do
        table.insert(result, match)
    end
    return result
end