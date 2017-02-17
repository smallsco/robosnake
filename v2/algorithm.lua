local algorithm = {}


-- Lua optimization: any functions from another module called more than once
-- are faster if you create a local reference to that function.
local DEBUG = ngx.DEBUG
local log = ngx.log
local n_complement = util.n_complement
local printWorldMap = util.printWorldMap
local beginSegment = util.beginSegment
local endSegment = util.endSegment


--[[
    PRIVATE METHODS
]]


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


--- Calculates the manhattan distance between two coordinate pairs
-- @param table src The source coordinate pair
-- @param table dst The destination coordinate pair
-- @return int The distance between the pairs
local function mdist( src, dst )
    local dx = math.abs( src[1] - dst[1] )
    local dy = math.abs( src[2] - dst[2] )
    return ( dx + dy )
end


--- The heuristic function used to determine board/gamestate score
-- @param grid The game grid
-- @param state The game state
-- @param my_moves Table containing my possible moves
-- @param enemy_moves Table containing enemy's possible moves
local function heuristic( grid, state, my_moves, enemy_moves )

    beginSegment('Check win/loss conditions')
    if #my_moves == 0 then
        log( DEBUG, 'I am trapped.' )
        return -2147483648
    end
    
    if #enemy_moves == 0 then
        log( DEBUG, 'Enemy is trapped.' )
        return 2147483647
    end
    
    if state['me']['health'] <= 0 then
        log( DEBUG, 'I am out of health.' )
        return -2147483648
    end
    
    if state['enemy']['health'] <= 0 then
        log( DEBUG, 'Enemy is out of health.' )
        return 2147483647
    end
    
    if state['me']['gold'] >= 5 then
        log( DEBUG, 'I got all the gold.' )
        return 2147483647
    end
    
    if state['enemy']['gold'] >= 5 then
        log( DEBUG, 'Enemy got all the gold.' )
        return -2147483648
    end
    endSegment()
    
    -- honestly floodfill heuristic alone is pretty terrible
    -- it will always avoid food, since food increases your length,
    -- and thus making less squares available
    beginSegment('Floodfill - me')
    local floodfill_grid = deepcopy(grid)
    floodfill_grid[state['me']['coords'][1][2]][state['me']['coords'][1][1]] = '.'
    local accessible_squares = floodfill( state['me']['coords'][1], floodfill_grid, 0 )
    local percent_accessible = accessible_squares / ( #grid * #grid[1] )
    endSegment()
    
    -- FAILSAFE: If there are less accessible squares than my length, never go there
    -- this is to address a race condition with the earlier logic where a square
    -- that will trap us ranks highly if it also contains food (since food weights get 0'ed)
    if accessible_squares <= #state['me']['coords'] then
        log( DEBUG, 'I smell a trap!' )
        return -9999999
    end
    
    -- honestly floodfill heuristic alone is pretty terrible
    -- it will always avoid food, since food increases your length,
    -- and thus making less squares available
    beginSegment('Floodfill - enemy')
    local enemy_floodfill_grid = deepcopy(grid)
    enemy_floodfill_grid[state['enemy']['coords'][1][2]][state['enemy']['coords'][1][1]] = '.'
    local enemy_accessible_squares = floodfill( state['enemy']['coords'][1], enemy_floodfill_grid, 0 )
    local enemy_percent_accessible = enemy_accessible_squares / ( #grid * #grid[1] )
    endSegment()
    if enemy_accessible_squares <= #state['enemy']['coords'] then
        log( DEBUG, 'Enemy might be trapped!' )
        return 9999999
    end
    
    

    -- get food/gold from grid since it's a pain to update state every time we pass through minimax
    beginSegment('Get food/gold positions')
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
    endSegment()
    
    -- Default board score: 100% of squares accessible
    local score = 100
    
    -- If there's food on the board, and I'm hungry, go for it
    -- If I'm not hungry, ignore it
    local foodWeight = 100 - state['me']['health']
    log( DEBUG, 'Food Weight: ' .. foodWeight )
    beginSegment('Calculate food distances')
    for i = 1, #food do
        local dist = mdist( state['me']['coords'][1], food[i] )
        score = score - ( dist * foodWeight )
        log( DEBUG, string.format('Food %s, distance %s, score %s', inspect(food[i]), dist, (dist*foodWeight) ) )
    end
    endSegment()
    
    -- If there's gold on the board, weight it highly... go for it unless I'm REALLY hungry
    beginSegment('Calculate gold distances')
    for i = 1, #gold do
        local dist = mdist( state['me']['coords'][1], gold[i] )
        score = score - (dist * 5000)
        log( DEBUG, string.format('Gold %s, distance %s, score %s', inspect(gold[i]), dist, (dist * 5000) ) )
    end
    endSegment()
    
    -- If I'm not hungry and there's no gold on the board, then keep some distance from the enemy
    --[[local dist = mdist( state['me']['coords'][1], state['enemy']['coords'][1] )
    score = score + (dist * 1000)
    log( DEBUG, string.format('Enemy distance %s, score %s', dist, dist*1000 ) )]]
    
    beginSegment('Calculate score and print map')
    log( DEBUG, 'Original score: ' .. score )
    log( DEBUG, 'Percent accessible: ' .. percent_accessible )
    if score < 0 then
        score = score * (1/percent_accessible)
    elseif score > 0 then
        score = score * percent_accessible
    end
    
    log( DEBUG, 'Score: ' .. score )
    printWorldMap( grid )
    endSegment()

    return score
end


--[[
    PUBLIC METHODS
]]

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


--- The Alpha-Beta pruning algorithm.
--- When we reach maximum depth, calculate a "score" (heuristic) based on the game/board state.
--- As we come back up through the call stack, at each depth we toggle between selecting the move
--- that generates the maximum score, and the move that generates the minimum score. The idea is
--- that we want to maximize the score (pick the move that puts us in the best position), and that
--- our opponent wants to minimize the score (pick the move that puts us in the worst position).
-- @param grid The game grid
-- @param state The game state
-- @param depth The current recursion depth
-- @param alpha The highest-ranked board score at the current depth, from my PoV
-- @param beta The lowest-ranked board score at the current depth, from my PoV
-- @param alphaMove The best move at the current depth
-- @param betaMove The worst move at the current depth
-- @param maximizingPlayer True if calculating alpha at this depth, false if calculating beta
function algorithm.alphabeta(grid, state, depth, alpha, beta, alphaMove, betaMove, maximizingPlayer)

    log( DEBUG, 'Depth: ' .. depth )

    beginSegment('Get possible moves')
    local moves = {}
    local my_moves = algorithm.neighbours( state['me']['coords'][1], grid )
    local enemy_moves = algorithm.neighbours( state['enemy']['coords'][1], grid )
    
    -- if i'm smaller than the enemy, never move to a square that the enemy can also move to
    if #state['me']['coords'] <= #state['enemy']['coords'] then
        my_moves = n_complement(my_moves, enemy_moves)
    end
    
    if maximizingPlayer then
        moves = my_moves
        log( DEBUG, string.format( 'My Turn. Possible moves: %s', inspect(moves) ) )
    else
        moves = enemy_moves
        log( DEBUG, string.format( 'Enemy Turn. Possible moves: %s', inspect(moves) ) )
    end
    endSegment()
    
    if
        depth == MAX_RECURSION_DEPTH or
        
        -- short circuit win/loss conditions
        #moves == 0 or
        state['me']['health'] <= 0 or
        state['enemy']['health'] <= 0 or
        state['me']['gold'] >= 5 or
        state['enemy']['gold'] >= 5
    then
        beginSegment('Calculate game board heuristic')
        local heur = heuristic( grid, state, my_moves, enemy_moves )
        endSegment()
        return heur
    end
  
    if maximizingPlayer then
        for i = 1, #moves do
                        
            -- Update grid and coords for this move
            beginSegment('Update grid and coordinates')
            log( DEBUG, string.format( 'My move: %s', inspect(moves[i]) ) )
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
            endSegment()
            
            
            beginSegment('Alpha-Beta Pruning')
            local newAlpha = algorithm.alphabeta(new_grid, new_state, depth + 1, alpha, beta, alphaMove, betaMove, false)
            endSegment()
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
            beginSegment('Update grid and coordinates')
            log( DEBUG, string.format( 'Enemy move: %s', inspect(moves[i]) ) )
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
            endSegment()
            
            
            beginSegment('Alpha-Beta Pruning')
            local newBeta = algorithm.alphabeta(new_grid, new_state, depth + 1, alpha, beta, alphaMove, betaMove, true)
            endSegment()
            if newBeta < beta then
                beta = newBeta
                betaMove = moves[i]
            end
            if beta <= alpha then break end
        end
        return beta, betaMove
    end
  
end

--- When we reach maximum depth, calculate a "score" (heuristic) based on the game/board state.
--- As we come back up through the call stack, at each depth we toggle between selecting the move
--- that generates the maximum score, and the move that generates the minimum score. The idea is
--- that we want to maximize the score (pick the move that puts us in the best position), and that
--- our opponent wants to minimize the score (pick the move that puts us in the worst position).
-- @param grid The game grid
-- @param state The game state
-- @param depth The current recursion depth
-- @param maximizingPlayer True if calculating me at this depth, false if calculating enemy
-- @param bestScore The "best" (could be highest or lowest, depending on player) from maximizingPlayer's PoV
-- @param bestMove The "best" (or worst) move at the current depth
function algorithm.minimax(grid, state, depth, maximizingPlayer, bestScore, bestMove)
    
    log( DEBUG, 'Depth: ' .. depth )

    local moves = {}
    local my_moves = algorithm.neighbours( state['me']['coords'][1], grid )
    local enemy_moves = algorithm.neighbours( state['enemy']['coords'][1], grid )    
    
    -- if i'm smaller than the enemy, never move to a square that the enemy can also move to
    if #state['me']['coords'] <= #state['enemy']['coords'] then
        my_moves = n_complement(my_moves, enemy_moves)
    end
    
    if maximizingPlayer then
        moves = my_moves
        log( DEBUG, string.format( 'My Turn. Possible moves: %s', inspect(moves) ) )
    else
        moves = enemy_moves
        log( DEBUG, string.format( 'Enemy Turn. Possible moves: %s', inspect(moves) ) )
    end
    
    
    if depth == MAX_RECURSION_DEPTH or #moves == 0 then
        return heuristic( grid, state, my_moves, enemy_moves )
    end
  
    if maximizingPlayer then
        bestScore = -math.huge
        
        for i = 1, #moves do
            if not bestMove then
               bestMove = moves[i] 
            end
            
            -- Update grid and coords for this move
            log( DEBUG, string.format( 'My move: %s', inspect(moves[i]) ) )
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
            
            local newScore = algorithm.minimax( new_grid, new_state, depth+1, false )
            if bestScore < newScore then
                bestScore = newScore
                bestMove = moves[i]
            end
            
        end
        return bestScore, bestMove

    else
        bestScore = math.huge
        
        for i = 1, #moves do
            if not bestMove then
               bestMove = moves[i] 
            end
            
            -- Update grid and coords for this move
            log( DEBUG, string.format( 'Enemy move: %s', inspect(moves[i]) ) )
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
                
            local newScore = algorithm.minimax( new_grid, new_state, depth+1, true )
            if bestScore > newScore then
                bestScore = newScore
                bestMove = moves[i]
            end
            
        end
        return bestScore, bestMove

    end
  
end

--- When we reach maximum depth, calculate a "score" (heuristic) based on the game/board state.
--- As we come back up through the call stack, at each depth we toggle between selecting the move
--- that generates the maximum score, and the move that generates the minimum score. The idea is
--- that we want to maximize the score (pick the move that puts us in the best position), and that
--- our opponent wants to minimize the score (pick the move that puts us in the worst position).
-- @param grid The game grid
-- @param state The game state
-- @param depth The current recursion depth
-- @param maximizingPlayer True if calculating me at this depth, false if calculating enemy
-- @param bestScore The "best" (could be highest or lowest, depending on player) from maximizingPlayer's PoV
-- @param bestMove The "best" (or worst) move at the current depth
function algorithm.parallel_minimax(grid, state, depth, maximizingPlayer, bestScore, bestMove)
    
    log( DEBUG, 'Depth: ' .. depth )

    local moves = {}
    local my_moves = algorithm.neighbours( state['me']['coords'][1], grid )
    local enemy_moves = algorithm.neighbours( state['enemy']['coords'][1], grid )    
    
    -- if i'm smaller than the enemy, never move to a square that the enemy can also move to
    if #state['me']['coords'] <= #state['enemy']['coords'] then
        my_moves = n_complement(my_moves, enemy_moves)
    end
    
    if maximizingPlayer then
        moves = my_moves
        log( DEBUG, string.format( 'My Turn. Possible moves: %s', inspect(moves) ) )
    else
        moves = enemy_moves
        log( DEBUG, string.format( 'Enemy Turn. Possible moves: %s', inspect(moves) ) )
    end
    
    
    if depth == MAX_RECURSION_DEPTH or #moves == 0 then
        return heuristic( grid, state, my_moves, enemy_moves )
    end
  
    if maximizingPlayer then
        bestScore = -2147483648
    else
        bestScore = 2147483647
    end

    local reqs = {}
    
    --[[for i = 1, #moves do
        local parallelState = {
            move = moves[i],
            grid = grid,
            state = state,
            depth = depth,
            maximizingPlayer = maximizingPlayer,
            bestScore = bestScore
        }
        table.insert( reqs, { '/parallel', { method = ngx.HTTP_POST, body = cjson.encode(parallelState) } } )
    end
    local resps = { ngx.location.capture_multi(reqs) }
    for _, resp in ipairs( resps ) do
        local body = cjson.decode( resp.body )
        if maximizingPlayer then
            if bestScore < body['score'] then
                bestScore = body['score']
                bestMove = body['move']
            end
        else
            if bestScore > body['score'] then
                bestScore = body['score']
                bestMove = body['move']
            end
        end
    end]]
    
    local httpc = http.new()
    --httpc:set_timeout(HTTP_CONN_TIMEOUT)
    --httpc:connect("127.0.0.1", 80)
    httpc:connect("unix:/var/run/nginx.sock")
    
    for i = 1, #moves do
        local parallelState = {
            move = moves[i],
            grid = grid,
            state = state,
            depth = depth,
            maximizingPlayer = maximizingPlayer,
            bestScore = bestScore
        }
        table.insert( reqs, {
            path = '/parallel',
            method = 'POST',
            body = cjson.encode(parallelState),
            headers = {
                ["Host"] = "127.0.0.1",
            },
        })
    end
    local resps, err = httpc:request_pipeline(reqs)
    if not resps then
        log( ngx.ERR, "Failed to create request pipeline: " .. err )
    end
    for _, resp in ipairs( resps ) do
        if resp.status then
            local body = cjson.decode( resp:read_body() )
            if maximizingPlayer then
                if bestScore < body['score'] then
                    bestScore = body['score']
                    bestMove = body['move']
                end
            else
                if bestScore > body['score'] then
                    bestScore = body['score']
                    bestMove = body['move']
                end
            end
        else
            -- the keepalive connection has been closed
            log( ngx.ERR, "***SHOULD NOT REACH THIS!!!***" )
        end
    end
    
    --local ok, err = httpc:close()
    local ok, err = httpc:set_keepalive()
    --local ok, err = httpc:set_keepalive( HTTP_POOL_TIMEOUT, HTTP_POOL_SIZE )
    if not ok then
        log( ngx.ERR, "Failed to release lua-resty-http connection: " .. err )
    end
    
    return bestScore, bestMove
  
end


return algorithm