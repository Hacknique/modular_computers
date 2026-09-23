-- The terminal: writing output and reading typed lines
local host = ...
local term = {}

function term.write(value)
    host.write(tostring(value))
end

function term.clear()
    host.clear()
end

function term.clearLine() end

-- Returns a line typed on the terminal, ending in a newline unless dobreak is false
function term.read(_, dobreak)
    local line = host.read()
    if line == nil or dobreak == false then
        return line
    end
    return line .. "\n"
end

function term.isAvailable() return true end
function term.getCursor() return component.gpu.getCursor() end
function term.setCursor(x, y) return component.gpu.setCursor(x, y) end

function term.getViewport()
    local width, height = component.gpu.getResolution()
    return width, height, 0, 0, 1, 1
end

function term.gpu() return component.gpu end
function term.screen() return component.screen.address end
function term.keyboard() return nil end
function term.getCursorBlink() return false end
function term.setCursorBlink() end

return term
