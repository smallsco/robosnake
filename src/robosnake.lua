--[[
      ______  _____  ______   _____  _______ __   _ _______ _     _ _______
     |_____/ |     | |_____] |     | |______ | \  | |_____| |____/  |______
     |    \_ |_____| |_____] |_____| ______| |  \_| |     | |    \_ |______
                                                                           
                    _______ _     _        _____ _____ _____               
                    |  |  | |____/           |     |     |                 
                    |  |  | |    \_ .      __|__ __|__ __|__               
                                                                           
    -----------------------------------------------------------------------
    
    @author Scott Small <smallsco@gmail.com>
    @copyright 2017-2018 Redbrick Technologies, Inc.
    @copyright 2019 Scott Small
    @license MIT
]]


-- Lua optimization: any functions from another module called more than once
-- are faster if you create a local reference to that function.
local DEBUG = ngx.DEBUG
local INFO = ngx.INFO
local NOTICE = ngx.NOTICE
local log = ngx.log
local mdist = util.mdist
local neighbours = algorithm.neighbours
local now = ngx.now
local update_time = ngx.update_time


--[[
    MAIN APP LOGIC
]]

-- Seed Lua's PRNG
math.randomseed( os.time() )

-- Get the POST request and decode the JSON
local request_body = ngx.var.request_body
local gameState = cjson.decode( request_body )
log( NOTICE, string.format('---TURN %s---', gameState['turn'] ) )
log( NOTICE, 'Got request data: ' .. request_body )

-- Convert to 1-based indexing
log( DEBUG, 'Converting Coordinates' )
for i = 1, #gameState[ 'board' ][ 'food' ] do
    gameState[ 'board' ][ 'food' ][ i ][ 'x' ] = gameState[ 'board' ][ 'food' ][ i ][ 'x' ] + 1
    gameState[ 'board' ][ 'food' ][ i ][ 'y' ] = gameState[ 'board' ][ 'food' ][ i ][ 'y' ] + 1
end
for i = 1, #gameState[ 'board' ][ 'snakes' ] do
    for j = 1, #gameState[ 'board' ][ 'snakes' ][ i ][ 'body' ] do
        gameState[ 'board' ][ 'snakes' ][ i ][ 'body' ][ j ][ 'x' ] = gameState[ 'board' ][ 'snakes' ][ i ][ 'body' ][ j ][ 'x' ] + 1
        gameState[ 'board' ][ 'snakes' ][ i ][ 'body' ][ j ][ 'y' ] = gameState[ 'board' ][ 'snakes' ][ i ][ 'body' ][ j ][ 'y' ] + 1
    end
end
for i = 1, #gameState[ 'you' ][ 'body' ] do
    gameState[ 'you' ][ 'body' ][ i ][ 'x' ] = gameState[ 'you' ][ 'body' ][ i ][ 'x' ] + 1
    gameState[ 'you' ][ 'body' ][ i ][ 'y' ] = gameState[ 'you' ][ 'body' ][ i ][ 'y' ] + 1
end

log( DEBUG, 'Building World Map' )
local grid = util.buildWorldMap( gameState )
util.printWorldMap( grid, INFO )


-- This snake makes use of alpha-beta pruning to advance the gamestate
-- and predict enemy behavior. However, it only works for a single
-- enemy. While you can put it into a game with multiple snakes, it
-- will only look at the closest enemy when deciding the next move
-- to make.
if #gameState[ 'board' ][ 'snakes' ] > 2 then
    log( DEBUG, "WARNING: Multiple enemies detected. Choosing the closest snake for behavior prediction." )
end

-- Convenience vars
local me = gameState[ 'you' ]
local possibleEnemies = {}
local enemy = nil
local shortestDistance = 99999
for i = 1, #gameState[ 'board' ][ 'snakes' ] do
    if gameState[ 'board' ][ 'snakes' ][ i ][ 'id' ] ~= me[ 'id' ] then
        local d = mdist(
            me[ 'body' ][1],
            gameState[ 'board' ][ 'snakes' ][ i ][ 'body' ][1]
        )
        if d == shortestDistance then
            table.insert( possibleEnemies, gameState[ 'board' ][ 'snakes' ][ i ] )
        elseif d < shortestDistance then
            shortestDistance = d
            possibleEnemies = { gameState[ 'board' ][ 'snakes' ][ i ] }
        end
    end
end

if #possibleEnemies > 1 then
    -- There's more than one snake that's an equal distance from me!! So let's pick the longest snake.
    log( INFO, "WARNING: Multiple enemies with an equal distance to me. Choosing longest enemy for behavior prediction." )
    local longestLength = 0
    local newPossibleEnemies = {}
    log( INFO, string.format("%s %s", me[ 'name' ], #me[ 'body' ]) )
    for i = 1, #possibleEnemies do
        log( INFO, string.format("%s %s", possibleEnemies[i][ 'name' ], #possibleEnemies[i][ 'body' ]) )
        if #possibleEnemies[i][ 'body' ] == longestLength then
            table.insert( newPossibleEnemies, possibleEnemies[i] )
        elseif #possibleEnemies[i][ 'body' ] > longestLength then
            longestLength = #possibleEnemies[i][ 'body' ]
            newPossibleEnemies = { possibleEnemies[i] }
        end
    end
    if #newPossibleEnemies == 1 then
        -- We've successfully reduced the number of targets to just one!
        enemy = newPossibleEnemies[1]
    else
        log( INFO, "CRITICAL: Multiple enemies with an equal distance to me and equal length. ABANDONING BEHAVIOR PREDICTION." )
        enemy = nil
    end
elseif #possibleEnemies == 1 then
    -- There's just one snake on the board that's closer to me than any other snake
    enemy = possibleEnemies[1]
else
    -- This is just to keep from crashing if we're testing in an arena by ourselves
    -- though I am curious to see what will happen when trying to predict my own behavior!
    log( DEBUG, "WARNING: I am the only snake in the game! Using MYSELF for behavior prediction." )
    enemy = me
end


-- Alpha-Beta Pruning algorithm
-- This is significantly faster than minimax on a single processor, but very challenging to parallelize
local bestMove = nil
local bestScore = nil
if enemy then
    
    log( INFO, 'Enemy Snake: ' .. enemy[ 'name' ] )
    local myState = {
        me = me,
        enemy = enemy,
        numSnakes = #gameState[ 'board' ][ 'snakes' ]
    }
    local abgrid = util.buildWorldMap( gameState )
    
    -- update grid to block off any space that a larger snake other than me or enemy
    -- could possibly move into (assume equal sized snakes will try to avoid us)
    for i = 1, #gameState[ 'board' ][ 'snakes' ] do
        if gameState[ 'board' ][ 'snakes' ][ i ][ 'id' ] ~= me[ 'id' ]
           and gameState[ 'board' ][ 'snakes' ][ i ][ 'id' ] ~= enemy[ 'id' ]
        then
            if #gameState[ 'board' ][ 'snakes' ][ i ][ 'body' ] > #me[ 'body' ] then
                local moves = neighbours( gameState[ 'board' ][ 'snakes' ][ i ][ 'body' ][1], grid )
                for j = 1, #moves do
                    abgrid[ moves[j][ 'y' ] ][ moves[j][ 'x' ] ] = '?'
                end
            end
        end
    end
    
    util.printWorldMap( abgrid, INFO )
    
    bestScore, bestMove = algorithm.alphabeta( abgrid, myState, 0, -math.huge, math.huge, nil, nil, true, {}, {} )
    log( DEBUG, string.format( 'Best score: %s', bestScore ) )
    if bestMove then
        log( DEBUG, string.format( 'Best move: [%s,%s]', bestMove[ 'x' ], bestMove[ 'y' ] ) )
    end
    
end

-- FAILSAFE #1
-- This is reached if no move is returned by the alphabeta pruning algorithm.
-- This can happen if the recursion depth is 0 or if searching up to the recursion depth
-- results in all unwinnable scenarios. However this doesn't mean we are doomed, we may
-- have moved into a space that appears to trap us, but at some move beyond the
-- max recursion depth we are able to break free (i.e. trapped by the enemy's tail which
-- later gets out of the way)
if not bestMove then
    log( INFO, "WARNING: No move returned from alphabeta!" )
    local my_moves = neighbours( me[ 'body' ][1], grid )
    local safe_moves = neighbours( me[ 'body' ][1], grid )
    
    -- safe moves are squares where we can move into that a
    -- larger or equal sized enemy cannot move into
    for i = 1, #gameState[ 'board' ][ 'snakes' ] do
        if gameState[ 'board' ][ 'snakes' ][ i ][ 'id' ] ~= me[ 'id' ] then
            if #gameState[ 'board' ][ 'snakes' ][ i ][ 'body' ] >= #me[ 'body' ] then
                local enemy_moves = neighbours( gameState[ 'board' ][ 'snakes' ][ i ][ 'body' ][1], grid )
                safe_moves = util.n_complement( safe_moves, enemy_moves )
            end
        end
    end
    
    if #safe_moves > 0 then
        -- FIXME: use floodfill instead of picking randomly
        log( INFO, "Moving to a random safe neighbour." )
        bestMove = safe_moves[ math.random( #safe_moves ) ]
    elseif #my_moves > 0 then
        -- We're _larger_ than the enemy, or we're smaller but there are no safe squares
        -- available - we may end up in a head-on-head collision.
        log( INFO, "Moving to a random free neighbour." )
        bestMove = my_moves[ math.random( #my_moves ) ]
    else
        -- If we reach this point, there isn't anywhere safe to move to and we're going to die.
        -- This just prefers snake deaths over wall deaths, so that the official battlesnake
        -- unit tests pass.
        log( INFO, "FATAL: No free neighbours. I'm going to die. Trying to avoid a wall..." )
        my_moves = neighbours( me[ 'body' ][1], grid, true )
        bestMove = my_moves[ math.random( #my_moves ) ]
    end
end

-- FAILSAFE #2
-- We're dead. This only exists to ensure that we always return a valid JSON response
-- to the game board. It always goes left.
if not bestMove then
    log( INFO, "FATAL: Wall collision unavoidable. I'm going to die. Moving left!" )
    bestMove = { x = me[ 'body' ][1][ 'x' ] - 1, y = me[ 'body' ][1][ 'y' ] }
end

-- Move to the destination we decided on
local dir = util.direction( me[ 'body' ][1], bestMove )
log( INFO, string.format( 'Decision: Moving %s to [%s,%s]', dir, bestMove[ 'x' ], bestMove[ 'y' ] ) )


-- Return response to the arena
local response = { move = dir }
ngx.print( cjson.encode(response) )


update_time()
endTime = now()
respTime = endTime - ngx.ctx.startTime


-- Control lua's garbage collection
-- return the response and close the http connection first
-- then do the garbage collection in the worker process before handling the next request
local ok, err = ngx.eof()
if not ok then
    log( ngx.ERR, 'error calling eof function: ' .. err )
end
collectgarbage()
collectgarbage()

update_time()
totalTime = now() - ngx.ctx.startTime
log( DEBUG, string.format( 'time to response: %.2f, total time: %.2f', respTime, totalTime ) )
