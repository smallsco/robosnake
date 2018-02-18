local algorithm = {}


-- Lua optimization: any functions from another module called more than once
-- are faster if you create a local reference to that function.
local mdist = util.mdist
local n_complement = util.n_complement
local printWorldMap = util.printWorldMap

local logger = require "logger"
log = logger.log

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
-- @param boolean failsafe If true, don't consider if the neighbour is safe or not
-- @return boolean
local function isSafeSquare( v, failsafe )
    if failsafe then
        return true
    else
        return v == '.' or v == 'O' or v == '*'
    end
end


--- Returns true if a square is safe to pass over, false otherwise
-- @param v The value of a particular tile on the grid
-- @return boolean
local function isSafeSquareFloodfill( v )
    return v == '.' or v == 'O'
end


-- "Floods" the grid in order to find out how many squares are accessible to us
-- This ruins the grid, make sure you always work on a deepcopy of the grid!
-- @see https://en.wikipedia.org/wiki/Flood_fill#Stack-based_recursive_implementation_.28four-way.29
local function floodfill( pos, grid, numSafe )

    local y = pos[ 'y' ]
    local x = pos[ 'x' ]
    if isSafeSquareFloodfill( grid[y][x] ) then
        grid[y][x] = 1
        numSafe = numSafe + 1
        local n = algorithm.neighbours( pos, grid )
        for i = 1, #n do
            numSafe = floodfill( n[i], grid, numSafe )
        end
    end
    return numSafe
end


--- The heuristic function used to determine board/gamestate score
-- @param grid The game grid
-- @param state The game state
-- @param my_moves Table containing my possible moves
-- @param enemy_moves Table containing enemy's possible moves
local function heuristic( grid, state, my_moves, enemy_moves, log_id )
    local DEBUG = "debug." .. log_id
    local INFO = "info." .. log_id


    -- Default board score
    local score = 0

    -- Handle head-on-head collisions.
    if
        state[ 'me' ][ 'body' ][ 'data' ][1][ 'x' ] == state[ 'enemy' ][ 'body' ][ 'data' ][1][ 'x' ]
        and state[ 'me' ][ 'body' ][ 'data' ][1][ 'y' ] == state[ 'enemy' ][ 'body' ][ 'data' ][1][ 'y' ]
    then
        log( DEBUG, 'Head-on-head collision!' )
        if #state[ 'me' ][ 'body' ][ 'data' ] > #state[ 'enemy' ][ 'body' ][ 'data' ] then
            log( DEBUG, 'I am bigger and win!' )
            score = score + 2147483647
        elseif #state[ 'me' ][ 'body' ][ 'data' ] < #state[ 'enemy' ][ 'body' ][ 'data' ] then
            log( DEBUG, 'I am smaller and lose.' )
            return -2147483648
        else
            -- do not use negative infinity here.
            -- draws are better than losing because the bounty cannot be claimed without a clear victor.
            log( DEBUG, "It's a draw." )
            return -2147483647  -- one less than max int size
        end
    end

    -- My win/loss conditions
    if #my_moves == 0 then
        log( DEBUG, 'I am trapped.' )
        return -2147483648
    end

    if state[ 'me' ][ 'health' ] < 0 then
        log( DEBUG, 'I am out of health.' )
        return -2147483648
    end
    
    -- The floodfill heuristic should never be used alone as it will always avoid food!
    -- The reason for this is that food increases our length by one, causing one less
    -- square on the board to be available for movement.
    
    -- Run a floodfill from my current position, to find out:
    -- 1) How many squares can I reach from this position?
    -- 2) What percentage of the board does that represent?
    local floodfill_grid = deepcopy(grid)
    floodfill_grid[ state[ 'me' ][ 'body' ][ 'data' ][1][ 'y' ] ][ state[ 'me' ][ 'body' ][ 'data' ][1][ 'x' ] ] = '.'
    local accessible_squares = floodfill( state[ 'me' ][ 'body' ][ 'data' ][1], floodfill_grid, 0 )
    local percent_accessible = accessible_squares / ( #grid * #grid[1] )
    
    -- If the number of squares I can see from my current position is less than my length
    -- then moving to this position *may* trap and kill us, and should be avoided if possible
    if accessible_squares <= #state[ 'me' ][ 'body' ][ 'data' ] then
        log( DEBUG, 'I smell a trap!' )
        return -9999999 * ( 1 / percent_accessible )
    end

    
    -- Enemy win/loss conditions
    if #enemy_moves == 0 then
        log( DEBUG, 'Enemy is trapped.' )
        score = score + 2147483647
    end
    if state[ 'enemy' ][ 'health' ] < 0 then
        log( DEBUG, 'Enemy is out of health.' )
        score = score + 2147483647
    end
    
    -- Run a floodfill from the enemy's current position, to find out:
    -- 1) How many squares can the enemy reach from this position?
    -- 2) What percentage of the board does that represent?
    local enemy_floodfill_grid = deepcopy(grid)
    enemy_floodfill_grid[ state[ 'enemy' ][ 'body' ][ 'data' ][1][ 'y' ] ][ state[ 'enemy' ][ 'body' ][ 'data' ][1][ 'x' ] ] = '.'
    local enemy_accessible_squares = floodfill( state[ 'enemy' ][ 'body' ][ 'data' ][1], enemy_floodfill_grid, 0 )
    local enemy_percent_accessible = enemy_accessible_squares / ( #grid * #grid[1] )
    
    -- If the number of squares the enemy can see from their current position is less than their length
    -- then moving to this position *may* trap and kill them, and should be avoided if possible
    if enemy_accessible_squares <= #state[ 'enemy' ][ 'body' ][ 'data' ] then
        log( DEBUG, 'Enemy might be trapped!' )
        score = score + 9999999
    end
    
    
    -- get food from grid since it's a pain to update state every time we pass through minimax
    local food = {}
    for y = 1, #grid do
        for x = 1, #grid[y] do
            if grid[y][x] == 'O' then
                table.insert( food, { x = x, y = y } )
            end
        end
    end
    
    local center_x = math.ceil( #grid[1] / 2 )
    local center_y = math.ceil( #grid / 2 )
    
    -- If there's food on the board, and I'm hungry, go for it
    -- If I'm not hungry, ignore it
    local foodWeight = 0
    if state[ 'me' ][ 'health' ] <= HUNGER_HEALTH then
        foodWeight = 100 - state[ 'me' ][ 'health' ]
    end
    log( DEBUG, 'Food Weight: ' .. foodWeight )
    if foodWeight > 0 then
        for i = 1, #food do
            local dist = mdist( state[ 'me' ][ 'body' ][ 'data' ][1], food[i] )
            -- "i" is used in the score so that two pieces of food that 
            -- are equal distance from me do not have identical weighting
            score = score - ( dist * foodWeight ) - i
            log( DEBUG, string.format('Food %s, distance %s, score %s', inspect( food[i] ), dist, ( dist * foodWeight ) - i ) )
        end
    end

    -- Hang out near the enemy's head
    local kill_squares = algorithm.neighbours( state[ 'enemy' ][ 'body' ][ 'data' ][1], grid )
    for i = 1, #kill_squares do
        local dist = mdist( state[ 'me' ][ 'body' ][ 'data' ][1], kill_squares[i] )
        score = score - (dist * 100)
        log( DEBUG, string.format('Kill square distance %s, score %s', dist, dist*100 ) )
    end
     
    -- Hang out near the center
    -- Temporarily Disabled
    --[[local dist = mdist( state[ 'me' ][ 'body' ][ 'data' ][1], { x = center_x, y = center_y } )
    score = score - (dist * 100)

    log( DEBUG, string.format('Center distance %s, score %s', dist, dist*100 ) )]]
    log( DEBUG, 'Original score: ' .. score )
    log( DEBUG, 'Percent accessible: ' .. percent_accessible )

    if score < 0 then
        score = score * (1/percent_accessible)
    elseif score > 0 then
        score = score * percent_accessible
    end
    
    log( DEBUG, 'Node score: ' .. score )

    return score
end


--[[
    PUBLIC METHODS
]]

--- Returns the set of all coordinate pairs on the board that are adjacent to the given position
-- @param table pos The source coordinate pair
-- @param table grid The game grid
-- @param boolean failsafe If true, don't consider if the neighbour is safe or not
-- @return table The neighbours of the source coordinate pair
function algorithm.neighbours( pos, grid, failsafe )
    local neighbours = {}
    local north = { x = pos[ 'x' ], y = pos[ 'y' ] - 1 }
    local south = { x = pos[ 'x' ], y = pos[ 'y' ] + 1 }
    local east = { x = pos[ 'x' ] + 1, y = pos[ 'y' ] }
    local west = { x = pos[ 'x' ] - 1, y = pos[ 'y' ] }
    
    local height = #grid
    local width = #grid[1]
    
    if north[ 'y' ] > 0 and north[ 'y' ] <= height and isSafeSquare( grid[ north[ 'y' ] ][ north[ 'x' ] ], failsafe ) then
        table.insert( neighbours, north )
    end
    if south[ 'y' ] > 0 and south[ 'y' ] <= height and isSafeSquare( grid[ south[ 'y' ] ][ south[ 'x' ] ], failsafe ) then
        table.insert( neighbours, south )
    end
    if east[ 'x' ] > 0 and east[ 'x' ] <= width and isSafeSquare( grid[ east[ 'y' ] ][ east[ 'x' ] ], failsafe ) then
        table.insert( neighbours, east )
    end
    if west[ 'x' ] > 0 and west[ 'x' ] <= width and isSafeSquare( grid[ west[ 'y' ] ][ west[ 'x' ] ], failsafe ) then
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
function algorithm.alphabeta( grid, state, depth, alpha, beta, alphaMove, betaMove, maximizingPlayer, prev_grid, prev_enemy_moves, log_id)
    local DEBUG = "debug." .. log_id
    local INFO = "info." .. log_id

    log(DEBUG, 'Depth: ' .. depth )

    local moves = {}
    local my_moves = algorithm.neighbours( state[ 'me' ][ 'body' ][ 'data' ][1], grid )
    local enemy_moves = {}
    if maximizingPlayer then
        enemy_moves = algorithm.neighbours( state[ 'enemy' ][ 'body' ][ 'data' ][1], grid )
    else
        enemy_moves = prev_enemy_moves
    end
    
    if maximizingPlayer then
        moves = my_moves
    else
        moves = enemy_moves
    end
    
    if
        depth == MAX_RECURSION_DEPTH or
        
        -- short circuit win/loss conditions
        #moves == 0 or
        state[ 'me' ][ 'health' ] < 0 or
        state[ 'enemy' ][ 'health' ] < 0 or
        (
            state[ 'me' ][ 'body' ][ 'data' ][1][ 'x' ] == state[ 'enemy' ][ 'body' ][ 'data' ][1][ 'x' ]
            and state[ 'me' ][ 'body' ][ 'data' ][1][ 'y' ] == state[ 'enemy' ][ 'body' ][ 'data' ][1][ 'y' ]
        )
    then
        log( DEBUG, 'Reached MAX_RECURSION_DEPTH or endgame state.' )
        return heuristic( grid, state, my_moves, enemy_moves, log_id )
    end
  
    if maximizingPlayer then
        log( DEBUG, string.format( 'My Turn. Position: %s Possible moves: %s', inspect( state[ 'me' ][ 'body' ][ 'data' ] ), inspect( moves ) ) )

        for i = 1, #moves do
                        
            -- Update grid and coords for this move
            log( DEBUG, string.format( 'My move: %s', inspect( moves[i] ) ) )

            local new_grid = deepcopy( grid )
            local new_state = deepcopy( state )
            local eating = false
            
            -- if next tile is food we are eating/healing, otherwise lose 1 health
            if new_grid[ moves[i][ 'y' ] ][ moves[i][ 'x' ] ] == 'O' then
                eating = true
                new_state[ 'me' ][ 'health' ] = 100
            else
                new_state[ 'me' ][ 'health' ] = new_state[ 'me' ][ 'health' ] - 1
            end
            
            -- remove tail from map ONLY if not growing
            local length = #new_state[ 'me' ][ 'body' ][ 'data' ]
            if
              length > 1
              and
              (
                new_state[ 'me' ][ 'body' ][ 'data' ][ length ][ 'x' ] == new_state[ 'me' ][ 'body' ][ 'data' ][ length - 1 ][ 'x' ]
                and new_state[ 'me' ][ 'body' ][ 'data' ][ length ][ 'y' ] == new_state[ 'me' ][ 'body' ][ 'data' ][ length - 1 ][ 'y' ]
              )
            then
                -- do nothing
            else
                new_grid[ new_state[ 'me' ][ 'body' ][ 'data' ][ length ][ 'y' ] ][ new_state[ 'me' ][ 'body' ][ 'data' ][ length ][ 'x' ] ] = '.'
            end
            
            -- always remove tail from state
            table.remove( new_state[ 'me' ][ 'body' ][ 'data' ] )
            
            -- move head in state and on grid
            if length > 1 then
                new_grid[ new_state[ 'me' ][ 'body' ][ 'data' ][1][ 'y' ] ][ new_state[ 'me' ][ 'body' ][ 'data' ][1][ 'x' ] ] = '#'
            end
            table.insert( new_state[ 'me' ][ 'body' ][ 'data' ], 1, moves[i] )
            new_grid[ moves[i][ 'y' ] ][ moves[i][ 'x' ] ] = '@'
            
            -- if eating add to the snake's body
            if eating then
                table.insert(
                    new_state[ 'me' ][ 'body' ][ 'data' ],
                    {
                        x = new_state[ 'me' ][ 'body' ][ 'data' ][ length ][ 'x' ],
                        y = new_state[ 'me' ][ 'body' ][ 'data' ][ length ][ 'y' ]
                    }
                )
                eating = false
            end
            
            -- mark if the tail is a safe square or not
            local length = #new_state[ 'me' ][ 'body' ][ 'data' ]
            if
              length > 1
              and
              (
                new_state[ 'me' ][ 'body' ][ 'data' ][ length ][ 'x' ] == new_state[ 'me' ][ 'body' ][ 'data' ][ length - 1 ][ 'x' ]
                and new_state[ 'me' ][ 'body' ][ 'data' ][ length ][ 'y' ] == new_state[ 'me' ][ 'body' ][ 'data' ][ length - 1 ][ 'y' ]
              )
            then
                new_grid[ new_state[ 'me' ][ 'body' ][ 'data' ][ length ][ 'y' ] ][ new_state[ 'me' ][ 'body' ][ 'data' ][ length ][ 'x' ] ] = '#'
            else
                new_grid[ new_state[ 'me' ][ 'body' ][ 'data' ][ length ][ 'y' ] ][ new_state[ 'me' ][ 'body' ][ 'data' ][ length ][ 'x' ] ] = '*'
            end
            
            printWorldMap( new_grid )
            
            local newAlpha = algorithm.alphabeta( new_grid, new_state, depth + 1, alpha, beta, alphaMove, betaMove, false, grid, enemy_moves, log_id )
            if newAlpha > alpha then
                alpha = newAlpha
                alphaMove = moves[i]
            end
            if beta <= alpha then break end
        end
        return alpha, alphaMove
    else
        log( DEBUG, string.format( 'Enemy Turn. Position: %s Possible moves: %s', inspect( state[ 'enemy' ][ 'body' ][ 'data' ] ), inspect( moves ) ) )

        for i = 1, #moves do
            
            -- Update grid and coords for this move
            log( DEBUG, string.format( 'Enemy move: %s', inspect( moves[i] ) ) )
            local new_grid = deepcopy( grid )
            local new_state = deepcopy( state )
            local eating = false
            
            -- if next tile is food we are eating/healing, otherwise lose 1 health
            if prev_grid[ moves[i][ 'y' ] ][ moves[i][ 'x' ] ] == 'O' then
                eating = true
                new_state[ 'enemy' ][ 'health' ] = 100
            else
                new_state[ 'enemy' ][ 'health' ] = new_state[ 'enemy' ][ 'health' ] - 1
            end
            
            -- remove tail from map ONLY if not growing
            local length = #new_state[ 'enemy' ][ 'body' ][ 'data' ]
            if
              length > 1
              and
              (
                new_state[ 'enemy' ][ 'body' ][ 'data' ][ length ][ 'x' ] == new_state[ 'enemy' ][ 'body' ][ 'data' ][ length - 1 ][ 'x' ]
                and new_state[ 'enemy' ][ 'body' ][ 'data' ][ length ][ 'y' ] == new_state[ 'enemy' ][ 'body' ][ 'data' ][ length - 1 ][ 'y' ]
              )
            then
                -- do nothing
            else
                new_grid[ new_state[ 'enemy' ][ 'body' ][ 'data' ][ length ][ 'y' ] ][ new_state[ 'enemy' ][ 'body' ][ 'data' ][ length ][ 'x' ] ] = '.'
            end
            
            -- always remove tail from state
            table.remove( new_state[ 'enemy' ][ 'body' ][ 'data' ] )
            
            -- move head in state and on grid
            if length > 1 then
                new_grid[ new_state[ 'enemy' ][ 'body' ][ 'data' ][1][ 'y' ] ][ new_state[ 'enemy' ][ 'body' ][ 'data' ][1][ 'x' ] ] = '#'
            end
            table.insert( new_state[ 'enemy' ][ 'body' ][ 'data' ], 1, moves[i] )
            new_grid[ moves[i][ 'y' ] ][ moves[i][ 'x' ] ] = '@'
            
            -- if eating add to the snake's body
            if eating then
                table.insert(
                    new_state[ 'enemy' ][ 'body' ][ 'data' ],
                    {
                        x = new_state[ 'enemy' ][ 'body' ][ 'data' ][ length ][ 'x' ],
                        y = new_state[ 'enemy' ][ 'body' ][ 'data' ][ length ][ 'y' ]
                    }
                )
                eating = false
            end
            
            -- mark if the tail is a safe square or not
            local length = #new_state[ 'enemy' ][ 'body' ][ 'data' ]
            if
              length > 1
              and
              (
                new_state[ 'enemy' ][ 'body' ][ 'data' ][ length ][ 'x' ] == new_state[ 'enemy' ][ 'body' ][ 'data' ][ length - 1 ][ 'x' ]
                and new_state[ 'enemy' ][ 'body' ][ 'data' ][ length ][ 'y' ] == new_state[ 'enemy' ][ 'body' ][ 'data' ][ length - 1 ][ 'y' ]
              )
            then
                new_grid[ new_state[ 'enemy' ][ 'body' ][ 'data' ][ length ][ 'y' ] ][ new_state[ 'enemy' ][ 'body' ][ 'data' ][ length ][ 'x' ] ] = '#'
            else
                new_grid[ new_state[ 'enemy' ][ 'body' ][ 'data' ][ length ][ 'y' ] ][ new_state[ 'enemy' ][ 'body' ][ 'data' ][ length ][ 'x' ] ] = '*'
            end
            
            printWorldMap( new_grid )
            
            local newBeta = algorithm.alphabeta( new_grid, new_state, depth + 1, alpha, beta, alphaMove, betaMove, true, {}, {}, log_id )
            if newBeta < beta then
                beta = newBeta
                betaMove = moves[i]
            end
            if beta <= alpha then break end
        end
        return beta, betaMove
    end
  
end


return algorithm
