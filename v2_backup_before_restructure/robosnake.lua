--[[
    CONSTANTS
]]
local SNAKE_ID = 'robosnake'
local MAX_RECURSION_DEPTH = 6


--[[
    FUNCTIONS
]]

local function buildWorldMap( gameState )
    -- Generate the tile grid
    ngx.log( ngx.DEBUG, 'Generating tile grid' )
    local grid = {}
    for y = 1, gameState['height'] do
        grid[y] = {}
        for x = 1, gameState['width'] do
            grid[y][x] = '.'
        end
    end
    
    -- Place walls
    for i = 1, #gameState['walls'] do
        local wall = gameState['walls'][i]
        grid[wall[2]][wall[1]] = 'X'
        ngx.log( ngx.DEBUG, string.format('Placed wall at [%s, %s]', wall[1], wall[2]) )
    end
    
    -- Place gold
    for i = 1, #gameState['gold'] do
        local gold = gameState['gold'][i]
        grid[gold[2]][gold[1]] = '$'
        ngx.log( ngx.DEBUG, string.format('Placed gold at [%s, %s]', gold[1], gold[2]) )
    end
    
    -- Place food
    for i = 1, #gameState['food'] do
        local food = gameState['food'][i]
        grid[food[2]][food[1]] = 'O'
        ngx.log( ngx.DEBUG, string.format('Placed food at [%s, %s]', food[1], food[2]) )
    end
    
    -- Place snakes
    for i = 1, #gameState['snakes'] do
        for j = 1, #gameState['snakes'][i]['coords'] do
            local snake = gameState['snakes'][i]['coords'][j]
            if j == 1 then
                grid[snake[2]][snake[1]] = '@'
                ngx.log( ngx.DEBUG, string.format('Placed snake head at [%s, %s]', snake[1], snake[2]) )
            else
                grid[snake[2]][snake[1]] = '#'
                ngx.log( ngx.DEBUG, string.format('Placed snake tail at [%s, %s]', snake[1], snake[2]) )
            end
        end
    end
    
    return grid
end

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

local function convert_coordinates( coords )
    return { coords[1]+1, coords[2]+1 }
end

local function convert_gamestate( gameState )
    
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

function direction( src, dst )
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

-- @see https://github.com/vadi2/mudlet-lua/blob/2630cbeefc3faef3079556cb06459d1f53b8f842/lua/TableUtils.lua#L332
local function n_complement(set1, set2)
    if not set1 and set2 then return false end

    local complement = {}

    for _, val1 in pairs(set1) do
        local insert = true
        for _, val2 in pairs(set2) do
            if _comp(val1, val2) then
                    insert = false
            end
        end
        if insert then table.insert(complement, val1) end
    end

    return complement
end

local function isSafeSquare(v)
    return v == '.' or v == '$' or v == 'O' 
end

local function neighbours( pos, grid )
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

local function printWorldMap( grid )
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
end

local function mdist( src, dst )
    local dx = math.abs( src[1] - dst[1] )
    local dy = math.abs( src[2] - dst[2] )
    return ( dx + dy )
end

-- this ruins the grid, make sure you always work on a copy of the grid
-- @see https://en.wikipedia.org/wiki/Flood_fill#Stack-based_recursive_implementation_.28four-way.29
local function floodfill( pos, grid, numSafe )
    local y = pos[2]
    local x = pos[1]
    if isSafeSquare(grid[y][x]) then
        grid[y][x] = 1
        numSafe = numSafe + 1
        local n = neighbours(pos, grid)
        for i = 1, #n do
            numSafe = floodfill(n[i], grid, numSafe)
        end
    end
    return numSafe
end

local function heuristic( grid, state, my_moves, enemy_moves )

    if #my_moves == 0 then
        ngx.log( ngx.DEBUG, 'I am trapped.' )
        return -math.huge
    end
    
    if #enemy_moves == 0 then
        ngx.log( ngx.DEBUG, 'Enemy is trapped.' )
        return math.huge
    end
    
    if state['me']['health'] <= 0 then
        ngx.log( ngx.DEBUG, 'I am out of health.' )
        return -math.huge
    end
    
    if state['enemy']['health'] <= 0 then
        ngx.log( ngx.DEBUG, 'Enemy is out of health.' )
        return math.huge
    end
    
    if state['me']['gold'] >= 5 then
        ngx.log( ngx.DEBUG, 'I got all the gold.' )
        return math.huge
    end
    
    if state['enemy']['gold'] >= 5 then
        ngx.log( ngx.DEBUG, 'Enemy got all the gold.' )
        return -math.huge
    end
    
    -- honestly floodfill heuristic alone is pretty terrible
    -- it will always avoid food, since food increases your length,
    -- and thus making less squares available
    local floodfill_grid = deepcopy(grid)
    floodfill_grid[state['me']['coords'][1][2]][state['me']['coords'][1][1]] = '.'
    local accessible_squares = floodfill( state['me']['coords'][1], floodfill_grid, 0 )
    local percent_accessible = accessible_squares / ( #grid * #grid[1] )
    
    -- FAILSAFE: If there are less accessible squares than my length, never go there
    -- this is to address a race condition with the earlier logic where a square
    -- that will trap us ranks highly if it also contains food (since food weights get 0'ed)
    if accessible_squares <= #state['me']['coords'] then
        ngx.log( ngx.DEBUG, 'I smell a trap!' )
        return -9999999
    end
    
    -- honestly floodfill heuristic alone is pretty terrible
    -- it will always avoid food, since food increases your length,
    -- and thus making less squares available
    local enemy_floodfill_grid = deepcopy(grid)
    enemy_floodfill_grid[state['enemy']['coords'][1][2]][state['enemy']['coords'][1][1]] = '.'
    local enemy_accessible_squares = floodfill( state['enemy']['coords'][1], enemy_floodfill_grid, 0 )
    local enemy_percent_accessible = enemy_accessible_squares / ( #grid * #grid[1] )
    if enemy_accessible_squares <= #state['enemy']['coords'] then
        ngx.log( ngx.DEBUG, 'Enemy might be trapped!' )
        return 9999999
    end
    
    

    -- get food/gold from grid since it's a pain to update state every time we pass through minimax
    local food = {}
    local gold = {}
    for y = 1, #grid do
        for x = 1, #grid[y] do
            if grid[y][x] == 'O' then
                table.insert(food, {x, y})
            elseif grid[y][x] == '$' then
                table.insert(gold, {x, y})
            end
        end
    end
    
    -- Default board score: 100% of squares accessible
    local score = 100
    
    -- If there's food on the board, and I'm hungry, go for it
    -- If I'm not hungry, ignore it
    local foodWeight = 100 - state['me']['health']
    ngx.log(ngx.DEBUG, 'Food Weight: ' .. foodWeight)
    for i = 1, #food do
        local dist = mdist( state['me']['coords'][1], food[i] )
        score = score - ( dist * foodWeight )
        ngx.log( ngx.DEBUG, string.format('Food %s, distance %s, score %s', inspect(food[i]), dist, (dist*foodWeight) ) )
    end
    
    -- If there's gold on the board, weight it highly... go for it unless I'm REALLY hungry
    for i = 1, #gold do
        local dist = mdist( state['me']['coords'][1], gold[i] )
        score = score - (dist * 5000)
        ngx.log( ngx.DEBUG, string.format('Gold %s, distance %s, score %s', inspect(gold[i]), dist, (dist * 5000) ) )
    end
    
    -- If I'm not hungry and there's no gold on the board, then keep some distance from the enemy
    local dist = mdist( state['me']['coords'][1], state['enemy']['coords'][1] )
    score = score + (dist * 1000)
    ngx.log( ngx.DEBUG, string.format('Enemy distance %s, score %s', dist, dist*1000 ) )
    
    
    ngx.log( ngx.DEBUG, 'Original score: ' .. score )
    ngx.log( ngx.DEBUG, 'Percent accessible: ' .. percent_accessible )
    if score < 0 then
        score = score * (1/percent_accessible)
    elseif score > 0 then
        score = score * percent_accessible
    end
    
    ngx.log( ngx.DEBUG, 'Score: ' .. score )
    printWorldMap( grid )

    return score
end


local function alphabeta(grid, state, depth, alpha, beta, alphaMove, betaMove, maximizingPlayer)

    ngx.log( ngx.DEBUG, 'Depth: ' .. depth )

    local moves = {}
    local my_moves = neighbours( state['me']['coords'][1], grid )
    local enemy_moves = neighbours( state['enemy']['coords'][1], grid )    
    my_moves = n_complement(my_moves, enemy_moves)
    
    if maximizingPlayer then
        moves = my_moves
        ngx.log( ngx.DEBUG, string.format( 'My Turn. Possible moves: %s', inspect(moves) ) )
    else
        moves = enemy_moves
        ngx.log( ngx.DEBUG, string.format( 'Enemy Turn. Possible moves: %s', inspect(moves) ) )
    end
    
    
    if depth == MAX_RECURSION_DEPTH or #moves == 0 then
        return heuristic( grid, state, my_moves, enemy_moves )
    end
  
    if maximizingPlayer then
        for i = 1, #moves do
                        
            -- Update grid and coords for this move
            ngx.log( ngx.DEBUG, string.format( 'My move: %s', inspect(moves[i]) ) )
            local new_grid = deepcopy( grid )
            local new_state = deepcopy( state )
            table.insert( new_state['me']['coords'], 1, moves[i] )
            local length = #new_state['me']['coords']
            if new_grid[new_state['me']['coords'][1][2]][new_state['me']['coords'][1][1]] ~= 'O' then
                new_grid[new_state['me']['coords'][length][2]][new_state['me']['coords'][length][1]] = '.'
                table.remove( new_state['me']['coords'] )
                new_state['me']['health'] = new_state['me']['health'] - 1
            else
                if new_state['me']['health'] < 70 then
                    new_state['me']['health'] = new_state['me']['health'] + 30
                else
                    new_state['me']['health'] = 100
                end
            end
            if new_grid[new_state['me']['coords'][1][2]][new_state['me']['coords'][1][1]] == '$' then
                new_state['me']['gold'] = new_state['me']['gold'] + 1
            end
            new_grid[new_state['me']['coords'][1][2]][new_state['me']['coords'][1][1]] = '@'
            if #new_state['me']['coords'] > 1 then
                new_grid[new_state['me']['coords'][2][2]][new_state['me']['coords'][2][1]] = '#'
            end
            
            
            local newAlpha = alphabeta(new_grid, new_state, depth + 1, alpha, beta, alphaMove, betaMove, false)
            if newAlpha > alpha then
                alpha = newAlpha
                alphaMove = moves[i]
            end
            if beta <= alpha then break end
        end
        return alpha, alphaMove
    else
        for i = 1, #moves do
            
            -- Update grid and coords for this move
            ngx.log( ngx.DEBUG, string.format( 'Enemy move: %s', inspect(moves[i]) ) )
            local new_grid = deepcopy( grid )
            local new_state = deepcopy( state )
            table.insert( new_state['enemy']['coords'], 1, moves[i] )
            local length = #new_state['enemy']['coords']
            if new_grid[new_state['enemy']['coords'][1][2]][new_state['enemy']['coords'][1][1]] ~= 'O' then
                new_grid[new_state['enemy']['coords'][length][2]][new_state['enemy']['coords'][length][1]] = '.'
                table.remove( new_state['enemy']['coords'] )
                new_state['enemy']['health'] = new_state['enemy']['health'] - 1
            else
                if new_state['enemy']['health'] < 70 then
                    new_state['enemy']['health'] = new_state['enemy']['health'] + 30
                else
                    new_state['enemy']['health'] = 100
                end
            end
            if new_grid[new_state['enemy']['coords'][1][2]][new_state['enemy']['coords'][1][1]] == '$' then
                new_state['enemy']['gold'] = new_state['enemy']['gold'] + 1
            end
            new_grid[new_state['enemy']['coords'][1][2]][new_state['enemy']['coords'][1][1]] = '@'
            if #new_state['enemy']['coords'] > 1 then
                new_grid[new_state['enemy']['coords'][2][2]][new_state['enemy']['coords'][2][1]] = '#'
            end
            
            
            local newBeta = alphabeta(new_grid, new_state, depth + 1, alpha, beta, alphaMove, betaMove, true)
            if newBeta < beta then
                beta = newBeta
                betaMove = moves[i]
            end
            if beta <= alpha then break end
        end
        return beta, betaMove
    end
  
end


--[[
    MAIN APP LOGIC
]]

-- Seed Lua's PRNG
math.randomseed( os.time() )

local request_body = ngx.var.request_body
ngx.log( ngx.DEBUG, 'Got request data: ' .. request_body )
local gameState = cjson.decode( request_body )

ngx.log( ngx.DEBUG, 'Converting Coordinates' )
gameState = convert_gamestate( gameState )

ngx.log( ngx.DEBUG, 'Building World Map' )
local grid = buildWorldMap( gameState )
printWorldMap( grid )


-- This snake makes use of minimax and alpha-beta pruning to
-- advance the gamestate and predict enemy behavior. However, it
-- only works for a single enemy. You can put it into a game with
-- multiple snakes, however it will only look at the first living
-- enemy when deciding the next move to make.
if #gameState['snakes'] > 2 then
    str = "WARNING: Multiple enemies detected. My behavior will be undefined."
    ngx.log( ngx.DEBUG, str )
end

-- Convenience vars
local me, enemy
for i = 1, #gameState['snakes'] do
    if gameState['snakes'][i]['id'] == SNAKE_ID then
        me = gameState['snakes'][i]
    end
end
for i = 1, #gameState['snakes'] do
    if gameState['snakes'][i]['id'] ~= SNAKE_ID then
        if gameState['snakes'][i]['status'] == 'alive' then
            enemy = gameState['snakes'][i]
            break
        end
    end
end
local myState = {
    me = me,
    enemy = enemy,
    food = gameState['food'],
    gold = gameState['gold']
}

local score, move
local bestScore, bestMove = alphabeta(grid, myState, 0, -math.huge, math.huge, nil, nil, true)
ngx.log( ngx.DEBUG, string.format('Best score: %s', bestScore) )
ngx.log( ngx.DEBUG, string.format('Best move: %s', inspect(bestMove)) )

-- FAILSAFE #1
-- Prediction thinks we're going to die soon, however, predictions can be wrong.
-- Pick a random safe neighbour and move there.
if not bestMove then
    ngx.log( ngx.DEBUG, "WARNING: Trying to cheat death." )
    local my_moves = neighbours( myState['me']['coords'][1], grid )
    local enemy_moves = neighbours( myState['enemy']['coords'][1], grid )    
    my_moves = n_complement(my_moves, enemy_moves)
    if #my_moves > 0 then
        bestMove = my_moves[math.random(#my_moves)]
    end
end

-- FAILSAFE #2
-- should only be reached if there is literally nowhere we can move
-- this really only exists to ensure we always return a valid http response
if not bestMove then
    ngx.log( ngx.DEBUG, "WARNING: Using failsafe move. I'm probably trapped and about to die." )
    bestMove = {me['coords'][1][1]-1,me['coords'][1][2]}
end

-- Move to the destination we decided on
local dir = direction( me['coords'][1], bestMove )
ngx.log( ngx.DEBUG, string.format( 'Decision: Moving %s to [%s,%s]', dir, bestMove[1], bestMove[2] ) )


-- Return response to the arena
local response = { move = dir }
ngx.print( cjson.encode(response) )