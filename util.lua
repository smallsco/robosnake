local util = {}

-- Lua optimization: any functions from another module called more than once
-- are faster if you create a local reference to that function.
local log = logger.log
local random = math.random

--[[
    PRIVATE METHODS
--]]


-- @see https://github.com/vadi2/mudlet-lua/blob/2630cbeefc3faef3079556cb06459d1f53b8f842/lua/Other.lua#L467
local function _comp(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) == 'table' then
        for k, v in pairs(a) do
            if not b[k] then return false end
            if not _comp(v, b[k]) then return false end
        end
    else
        if a ~= b then return false end
    end
    return true
end



--[[
    PUBLIC METHODS
--]]

--- I'M A BELIEBER
-- @return a random quote from Justin Bieber
function util.bieberQuote()
    local bieberquotes = {
        "I make mistakes growing up. I'm not perfect; I'm not a robot. -Justin Bieber",
        "I'm crazy, I'm nuts. Just the way my brain works. I'm not normal. I think differently. -Justin Bieber",
        "Friends are the best to turn to when you're having a rough day. -Justin Bieber",
        "I leave the hip thrusts to Michael Jackson. -Justin Bieber",
        "It's cool when fans spend so much time making things for me. It means a lot. -Justin Bieber",
        "No one can stop me. -Justin Bieber"
    }
    return bieberquotes[random(#bieberquotes)]
end


--- Take the BattleSnake arena's state JSON and use it to create our own grid
-- @param gameState The arena's game state JSON
-- @return A 2D table with each cell mapped to food, snakes, etc.
function util.buildWorldMap( gameState, log_id )

    local INFO = "info." .. log_id
    local DEBUG = "debug." .. log_id

    -- Generate the tile grid
    local grid = {}
    for y = 1, gameState[ 'height' ] do
        grid[y] = {}
        for x = 1, gameState[ 'width' ] do
            grid[y][x] = '.'
        end
    end
    
    -- Place food
    for i = 1, #gameState[ 'food' ][ 'data' ] do
        local food = gameState[ 'food' ][ 'data' ][i]
        grid[ food[ 'y' ] ][ food[ 'x' ] ] = 'O'

        food_log = {
            game_id = log_id,
            width = gameState['width'],
            height = gameState[ 'height'],
            turn = gameState[ 'turn' ],
            who = "game",
            item = "food",
            coordinates = { x = food[ 'x' ], y = food[ 'y' ] }
        }

        log( INFO , food_log )
    end
    
    -- Place living snakes
    for i = 1, #gameState[ 'snakes' ][ 'data' ] do
        local length = #gameState[ 'snakes' ][ 'data' ][i][ 'body' ][ 'data' ]
        local whoami = gameState[ 'snakes' ][ 'data' ][i][ 'id' ]
        local name = gameState[ 'snakes' ][ 'data' ][i][ 'name' ]

        for j = 1, length do
            local snake = gameState[ 'snakes' ][ 'data' ][i][ 'body' ][ 'data' ][j]
            local health = gameState[ 'snakes' ][ 'data' ][i][ 'health' ]
            
            local snake_log = {
                health = health,
                game_id = log_id,
                who = whoami,
                name = name,
                width = gameState['width'],
                height = gameState[ 'height'],
                turn = gameState[ 'turn' ],
                length = length,
                coordinates = { x = snake[ 'x' ], y = snake[ 'y' ] }
             }

            if j == 1 then
                grid[ snake[ 'y' ] ][ snake[ 'x' ] ] = '@'

                snake_log.item = "head"
                log( INFO, snake_log )
                log( DEBUG, string.format( 'Placed snake head at [%s, %s]', snake[ 'x' ], snake[ 'y' ] ) )
            elseif j == length then
                if grid[ snake[ 'y' ] ][ snake[ 'x' ] ] ~= '@' and grid[ snake[ 'y' ] ][ snake[ 'x' ] ] ~= '#' then
                    grid[ snake[ 'y' ] ][ snake[ 'x' ] ] = '*'
                end

                snake_log.item = "tail"
                log(INFO, snake_log)
            else
                if grid[ snake[ 'y' ] ][ snake[ 'x' ] ] ~= '@' then
                    grid[ snake[ 'y' ] ][ snake[ 'x' ] ] = '#'
                end

                snake_log.item = "body"
                log(INFO, snake_log)
                log(DEBUG, string.format( 'Placed snake tail at [%s, %s]', snake[ 'x' ], snake[ 'y' ] ) )
            end
        end
    end
    
    return grid
end


--- Calculates the direction, given a source and destination coordinate pair
-- @param table src The source coordinate pair
-- @param table dst The destination coordinate pair
-- @return string The name of the direction
function util.direction( src, dst )
    if dst[ 'x' ] == src[ 'x' ] + 1 and dst[ 'y' ] == src[ 'y' ] then
        return 'right'
    elseif dst[ 'x' ] == src[ 'x' ] - 1 and dst[ 'y' ] == src[ 'y' ] then
        return 'left'
    elseif dst[ 'x' ] == src[ 'x' ] and dst[ 'y' ] == src[ 'y' ] + 1 then
        return 'down'
    elseif dst[ 'x' ] == src[ 'x' ] and dst[ 'y' ] == src[ 'y' ] - 1 then
        return 'up'
    end
end


--- Calculates the manhattan distance between two coordinate pairs
-- @param table src The source coordinate pair
-- @param table dst The destination coordinate pair
-- @return int The distance between the pairs
function util.mdist( src, dst )
    local dx = math.abs( src[ 'x' ] - dst[ 'x' ] )
    local dy = math.abs( src[ 'y' ] - dst[ 'y' ] )
    return ( dx + dy )
end


-- @see https://github.com/vadi2/mudlet-lua/blob/2630cbeefc3faef3079556cb06459d1f53b8f842/lua/TableUtils.lua#L332
function util.n_complement( set1, set2 )
    if not set1 and set2 then return false end

    local complement = {}

    for _, val1 in pairs( set1 ) do
        local insert = true
        for _, val2 in pairs( set2 ) do
            if _comp( val1, val2 ) then
                    insert = false
            end
        end
        if insert then table.insert( complement, val1 ) end
    end

    return complement
end


--- Prints the grid as an ASCII representation of the world map
-- @param grid The game grid
-- @deprecated. Should be safe to remove, but let's keep incase
-- everything goes horribly horribly wrong.
function util.printWorldMap( grid )
    return

    --[[
    local str = "\n"
    for y = 1, #grid do
        for x = 1, #grid[y] do
            str = str .. grid[y][x]
        end
        if y < #grid then
            str = str .. "\n"
        end
    end

    ngx.log( ngx.DEBUG, str )
    ]]--
end


return util
