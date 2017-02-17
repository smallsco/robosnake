local Util = {}

-- Constants
Util.SNAKE_ID = 'robosnake'

local abs = math.abs
local random = math.random

--- Converts coordinates from 0-based indexing to 1-based indexing
-- @access private
-- @param table coords The source coordinate pair
-- @return table The converted coordinate pair
local function convert_coordinates( coords )
    return { coords[1]+1, coords[2]+1 }
end

--- Compares two tables (to be used in table.sort)
-- @param table a The first table
-- @param table b The second table
-- @return boolean True if the first table's first element is smaller than the second table's
function Util.compare( a, b )
    return a[1] < b[1]
end

--- Converts an entire gamestate from 0-based indexing to 1-based indexing
-- @param table gameState The source game state
-- @return table The converted game state
function Util.convert_gamestate( gameState )
    
    local newState = {
        game = gameState['game'],
        mode = gameState['mode'],
        turn = gameState['turn'],
        height = gameState['height'],
        width = gameState['width'],
        snakes = {},
        food = {},
        walls = {},
        gold = {}
    }
    
    for i = 1, #gameState['food'] do
        table.insert( newState['food'], convert_coordinates( gameState['food'][i] ) )
    end
    
    for i = 1, #gameState['walls'] do
        table.insert( newState['walls'], convert_coordinates( gameState['walls'][i] ) )
    end
    
    for i = 1, #gameState['gold'] do
        table.insert( newState['gold'], convert_coordinates( gameState['gold'][i] ) )
    end
    
    for i = 1, #gameState['snakes'] do
        local newSnake = {
            id = gameState['snakes'][i]['id'],
            name = gameState['snakes'][i]['name'],
            status = gameState['snakes'][i]['status'],
            message = gameState['snakes'][i]['message'],
            taunt = gameState['snakes'][i]['taunt'],
            age = gameState['snakes'][i]['age'],
            health = gameState['snakes'][i]['health'],
            coords = {},
            kills = gameState['snakes'][i]['kills'],
            food = gameState['snakes'][i]['food'],
            gold = gameState['snakes'][i]['gold']
        }
        for j = 1, #gameState['snakes'][i]['coords'] do
            table.insert( newSnake['coords'], convert_coordinates( gameState['snakes'][i]['coords'][j] ) )
        end
        table.insert( newState['snakes'], newSnake )
    end
    
    return newState
end

--- Clones a table.
-- @param table orig The source table
-- @return table The copy of the table
-- @see http://lua-users.org/wiki/CopyTable
function Util.deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[Util.deepcopy(orig_key)] = Util.deepcopy(orig_value)
        end
        setmetatable(copy, Util.deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

--- Calculates the direction, given a source and destination coordinate pair
-- @param table src The source coordinate pair
-- @param table dst The destination coordinate pair
-- @return string The name of the direction
function Util.direction( src, dst )
    if dst[1] == src[1]+1 and dst[2] == src[2] then
        return 'east'
    elseif dst[1] == src[1]-1 and dst[2] == src[2] then
        return 'west'
    elseif dst[1] == src[1] and dst[2] == src[2]+1 then
        return 'south'
    elseif dst[1] == src[1] and dst[2] == src[2]-1 then
        return 'north'
    end
end

--- Calculates the manhattan distance between two coordinate pairs
-- @param table src The source coordinate pair
-- @param table dst The destination coordinate pair
-- @return int The distance between the pairs
function Util.manhattan_distance( src, dst )
    local dx = abs( src[1] - dst[1] )
    local dy = abs( src[2] - dst[2] )
    return ( dx + dy )
end

-- Returns the set of all coordinate pairs on the board that are adjacent to the given position
-- @param table pos The source coordinate pair
-- @return table The neighbours of the source coordinate pair
function Util.neighbours( pos, height, width )
    local neighbours = {}
    local north = {pos[1], pos[2]-1}
    local south = {pos[1], pos[2]+1}
    local east = {pos[1]+1, pos[2]}
    local west = {pos[1]-1, pos[2]}
    
    if pos[2]-1 > 0 and pos[2]-1 <= height then
        table.insert( neighbours, north )
    end
    if pos[2]+1 > 0 and pos[2]+1 <= height then
        table.insert( neighbours, south )
    end
    if pos[1]+1 > 0 and pos[1]+1 <= width then
        table.insert( neighbours, east )
    end
    if pos[1]-1 > 0 and pos[1]-1 <= width then
        table.insert( neighbours, west )
    end
    
    return neighbours
end

--- get up, get on up, get up, get on up, and DANCE
-- @return string A random dance move
function Util.taunt()
    local taunts = {
        [[:D|-<]],
        [[:D\-<]],
        [[:D/-<]]
    }
    return taunts[random(#taunts)]
end


return Util