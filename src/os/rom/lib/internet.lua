-- HTTP requests through an internet card
local internet = {}

function internet.isHttpEnabled()
    return component.isAvailable("internet") and component.internet.isHttpEnabled()
end

-- Starts a request. The result can be called to go through the body in chunks, and has
-- read, response and close.
function internet.request(url, data, headers, method)
    local card = component.internet
    local id = card.request(url, data, headers, method)
    local request = {}
    function request.finishConnect() return card.finishConnect(id) end
    function request.response() return card.response(id) end
    function request.read(count)
        while true do
            local chunk, err = card.read(id, count or math.huge)
            if chunk ~= "" then
                return chunk, err
            end
            os.sleep(0.05)
        end
    end
    function request.close() return card.close(id) end
    return setmetatable(request, { __call = function()
        local chunk, err = request.read()
        if err then
            error(err, 2)
        end
        if not chunk then
            request.close()
        end
        return chunk
    end })
end

return internet
