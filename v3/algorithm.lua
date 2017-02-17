local algorithm = {}


-- Lua optimization: any functions from another module called more than once
-- are faster if you create a local reference to that function.
local DEBUG = ngx.DEBUG
local log = ngx.log
local ceil = math.ceil


--- Compares two tables (to be used in table.sort)
-- @param table a The first table
-- @param table b The second table
-- @return boolean True if the first table's first element is smaller than the second table's
local function compare( a, b )
    return a[1] < b[1]
end

--- Compares two tables (to be used in table.sort)
-- @param table a The first table
-- @param table b The second table
-- @return boolean True if the first table's first element is larger than the second table's
local function compare_reverse( a, b )
    return a[1] > b[1]
end


--- Clones a table.
-- @param table orig The source table
-- @return table The copy of the table
-- @see http://lua-users.org/wiki/CopyTable
local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end


--- Returns true if a square is safe to pass over, false otherwise
-- @param v The value of a particular tile on the grid
-- @return boolean
local function isSafeSquare(v)
    return v == '.' or v == '$' or v == 'O' 
end

--- Returns true if a square is safe to pass over, false otherwise
-- @param v The value of a particular tile on the grid
-- @return boolean
local function isSafeOrHeadSquare(v)
    return v == '.' or v == '$' or v == 'O' or v == '@'
end


--- Calculates the manhattan distance between two coordinate pairs
-- @param table src The source coordinate pair
-- @param table dst The destination coordinate pair
-- @return int The distance between the pairs
local function mdist( src, dst )
    local dx = math.abs( src[1] - dst[1] )
    local dy = math.abs( src[2] - dst[2] )
    return ( dx + dy )
end


local function updateGameState( grid, snake, move )

    local newGrid = deepcopy(grid)
    local newSnake = deepcopy(snake)
    
    -- Move the snake's head to the new position in the coordinates array
    table.insert( newSnake['coords'], 1, move )
    local length = #newSnake['coords']
    
    if newGrid[newSnake['coords'][1][2]][newSnake['coords'][1][1]] ~= 'O' then
        -- If the new position on the board does not contain food, then move the snake's tail
        -- in the coordinates array and decrement the snake's health by 1
        newGrid[newSnake['coords'][length][2]][newSnake['coords'][length][1]] = '.'
        table.remove( newSnake['coords'] )
        newSnake['health'] = newSnake['health'] - 1
    else
        -- If, on the other hand, the snake moved to a square containing food, then
        -- health needs to be increased instead.
        if newSnake['health'] < 70 then
            newSnake['health'] = newSnake['health'] + 30
        else
            newSnake['health'] = 100
        end
    end
    
    -- If the snake moved to a square containing gold, increment the gold count
    if newGrid[newSnake['coords'][1][2]][newSnake['coords'][1][1]] == '$' then
        newSnake['gold'] = newSnake['gold'] + 1
    end
    
    -- Update head and tail on the grid
    newGrid[newSnake['coords'][1][2]][newSnake['coords'][1][1]] = '@'
    if #newSnake['coords'] > 1 then
        newGrid[newSnake['coords'][2][2]][newSnake['coords'][2][1]] = '#'
    end
    
    return newGrid, newSnake
    
end


-- this ruins the grid, make sure you always work on a copy of the grid
-- @see https://en.wikipedia.org/wiki/Flood_fill#Stack-based_recursive_implementation_.28four-way.29
local function floodfill( pos, grid, numSafe )
    local y = pos[2]
    local x = pos[1]
    if isSafeSquare(grid[y][x]) then
        grid[y][x] = 1
        numSafe = numSafe + 1
        local n = algorithm.neighbours(pos, grid)
        for i = 1, #n do
            numSafe = floodfill(n[i], grid, numSafe)
        end
    end
    return numSafe
end


local function analyze_move( grid, me, enemy )
    
    local moves
    if #me['coords'] > #enemy['coords'] then
        moves = algorithm.neighboursWithHeads( me['coords'][1], grid )
    else
        moves = algorithm.neighbours( me['coords'][1], grid )
    end
    if next(moves) == nil then
        log( DEBUG, 'I am trapped.' )
        return false
    end
    
    local floodfill_grid = deepcopy(grid)
    floodfill_grid[me['coords'][1][2]][me['coords'][1][1]] = '.'
    local accessible_squares = floodfill( me['coords'][1], floodfill_grid, 0 )
    if accessible_squares <= #me['coords'] then
        log( DEBUG, 'I smell a trap!' )
        return false
    end
    
    return true

end

--- Returns the set of all coordinate pairs on the board that are adjacent to the given position
-- @param table pos The source coordinate pair
-- @return table The neighbours of the source coordinate pair
function algorithm.neighbours( pos, grid )
    local neighbours = {}
    local north = {pos[1], pos[2]-1}
    local south = {pos[1], pos[2]+1}
    local east = {pos[1]+1, pos[2]}
    local west = {pos[1]-1, pos[2]}
    
    local height = #grid
    local width = #grid[1]
    
    if north[2] > 0 and north[2] <= height and isSafeSquare(grid[north[2]][north[1]]) then
        table.insert( neighbours, north )
    end
    if south[2] > 0 and south[2] <= height and isSafeSquare(grid[south[2]][south[1]]) then
        table.insert( neighbours, south )
    end
    if east[1] > 0 and east[1] <= width and isSafeSquare(grid[east[2]][east[1]]) then
        table.insert( neighbours, east )
    end
    if west[1] > 0 and west[1] <= width and isSafeSquare(grid[west[2]][west[1]]) then
        table.insert( neighbours, west )
    end
    
    return neighbours
end


--- Returns the set of all coordinate pairs on the board that are adjacent to the given position
-- @param table pos The source coordinate pair
-- @return table The neighbours of the source coordinate pair
function algorithm.neighboursWithHeads( pos, grid )
    local neighbours = {}
    local north = {pos[1], pos[2]-1}
    local south = {pos[1], pos[2]+1}
    local east = {pos[1]+1, pos[2]}
    local west = {pos[1]-1, pos[2]}
    
    local height = #grid
    local width = #grid[1]
    
    if north[2] > 0 and north[2] <= height and isSafeOrHeadSquare(grid[north[2]][north[1]]) then
        table.insert( neighbours, north )
    end
    if south[2] > 0 and south[2] <= height and isSafeOrHeadSquare(grid[south[2]][south[1]]) then
        table.insert( neighbours, south )
    end
    if east[1] > 0 and east[1] <= width and isSafeOrHeadSquare(grid[east[2]][east[1]]) then
        table.insert( neighbours, east )
    end
    if west[1] > 0 and west[1] <= width and isSafeOrHeadSquare(grid[west[2]][west[1]]) then
        table.insert( neighbours, west )
    end
    
    return neighbours
end


function algorithm.move( grid, me, enemy, food, gold, mode )

    -- Initialize the targets array
    -- Each item will be of the form { distance, coordinate pair }
    local gold_targets = {}
    local targets = {}
    
    -- Find the center of the game board, this is where we check distance from
    -- (prefer to stay close to the center as gold will spawn there)
    local center_y = ceil( #grid / 2 )
    local center_x = ceil( #grid[1] / 2 )
    
    -- Add all food on the board as potential targets
    for i = 1, #food do
        local center_dist = mdist( { center_x, center_y }, food[i] )
        local my_dist = mdist( me['coords'][1], food[i] )
        local enemy_dist = mdist( enemy['coords'][1], food[i] )
        if my_dist < enemy_dist then
            if mode == 'advanced' then
                table.insert( targets, { center_dist, food[i] } )
            else
                table.insert( targets, { my_dist, food[i] } )
            end
        end
    end
    
    -- Sort the targets by the shortest distance to the center of the map
    table.sort( targets, compare )
    
    -- Add gold if it exists to the start of the array
    for i = 1, #gold do
        local center_dist = mdist( { center_x, center_y }, gold[i] )
        local my_dist = mdist( me['coords'][1], gold[i] )
        local enemy_dist = mdist( enemy['coords'][1], gold[i] )
        if my_dist < enemy_dist then
            if mode == 'advanced' then
                table.insert( targets, { center_dist, gold[i] } )
            else
                table.insert( targets, { my_dist, gold[i] } )
            end
        end
    end
    
    -- Sort the targets by the LONGEST distance to the center of the map
    table.sort( gold_targets, compare_reverse )
    
    -- Add gold targets to targets in correct order (this is why we reverse sorted)
    for i = 1, #gold_targets do
        table.insert( targets, 1, gold_targets[i] )  
    end
    
    -- No targets at all?
    if next(targets) == nil then
        -- add safe neighbours
        log( DEBUG, 'FAIL SAFE NEIGHBOURS #1!!!' )
        local moves
        if #me['coords'] > #enemy['coords'] then
            moves = algorithm.neighboursWithHeads( me['coords'][1], grid )
        else
            moves = algorithm.neighbours( me['coords'][1], grid )
        end
        for i = 1, #moves do
            table.insert( targets, { 1, moves[i] } )
        end
    end
    
    -- Sigh... this should never ever be reached.
    if next(targets) == nil then
        log( DEBUG, 'NO TARGETS!!!' )
        return
    end
    
    -- DEBUG: pretty-print the targets array
    log( DEBUG, 'Targets:' )
    for i = 1, #targets do
        log( DEBUG, inspect( targets[i] ) )
    end
    
    -- Initialize Jumper
    local jgrid = Grid( grid )
    local pathfinder
    if #me['coords'] > #enemy['coords'] then
        pathfinder = Pathfinder( jgrid, 'ASTAR', isSafeOrHeadSquare )
    else
        pathfinder = Pathfinder( jgrid, 'ASTAR', isSafeSquare )
    end
    pathfinder:setHeuristic( 'MANHATTAN' )
    pathfinder:setMode( 'ORTHOGONAL' )
    
    -- For all targets...
    for i = 1, #targets do
        
        -- Try and find a path to the target
        log( DEBUG, string.format(
            'Me [%s,%s] ----> Target [%s,%s]',
            me['coords'][1][1],
            me['coords'][1][2],
            targets[i][2][1],
            targets[i][2][2]
        ))
        local jpath = pathfinder:getPath(
            me['coords'][1][1],
            me['coords'][1][2],
            targets[i][2][1],
            targets[i][2][2]
        )
        
        -- Path was found
        if jpath then
            log( DEBUG, 'Path found, length: ' .. jpath:getLength() )
            for node, count in jpath:nodes() do
                --log( DEBUG, string.format( 'Step %s - [%s,%s]', count, node.x, node.y ) )
                if count == 2 then
                    
                    -- Select this move
                    local move = {node.x, node.y}
                    
                    -- Update our representation of the game state to reflect this move
                    local newGrid, newMe = updateGameState( grid, me, move )
                    
                    -- Does it kill me or trap me?
                    if analyze_move( newGrid, newMe, enemy ) then
                        return move
                    end
                    
                end
            end
            
            -- We have a path, but it will cause my death or entrapment
            log( DEBUG, 'Target leads to despair' )
        
        -- Path was not found
        else
            log( DEBUG, 'No path to target' )
        end
    end
    
    -- Every target has no path or a bad path :(
    log( DEBUG, 'Ran out of targets' )
    return
    
end


return algorithm