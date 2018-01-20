--[[
                    _______  _____  __   _       _____  _______            
                    |______ |     | | \  |      |     | |______            
                    ______| |_____| |  \_|      |_____| |                  
                                                                           
      ______  _____  ______   _____  _______ __   _ _______ _     _ _______
     |_____/ |     | |_____] |     | |______ | \  | |_____| |____/  |______
     |    \_ |_____| |_____] |_____| ______| |  \_| |     | |    \_ |______
                                                                           
    -----------------------------------------------------------------------
    
    @author Scott Small <scott.small@rdbrck.com>
    @author Tyler Sebastian <tyler.sebastian@rdbrck.com>
    @author Erika Burdon <erika.burdon@rdbrck.com>
    @copyright 2017-2018 Redbrick Technologies, Inc.
    @license MIT
]]


-- Lua optimization: any functions from another module called more than once
-- are faster if you create a local reference to that function.
local DEBUG = ngx.DEBUG
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
log( DEBUG, 'Got request data: ' .. request_body )
local gameState = cjson.decode( request_body )

-- Convert to 1-based indexing
log( DEBUG, 'Converting Coordinates' )
for i = 1, #gameState[ 'food' ][ 'data' ] do
    gameState[ 'food' ][ 'data' ][i][ 'x' ] = gameState[ 'food' ][ 'data' ][i][ 'x' ] + 1
    gameState[ 'food' ][ 'data' ][i][ 'y' ] = gameState[ 'food' ][ 'data' ][i][ 'y' ] + 1
end
for i = 1, #gameState[ 'snakes' ][ 'data' ] do
    for j = 1, #gameState[ 'snakes' ][ 'data' ][i][ 'body' ][ 'data' ] do
        gameState[ 'snakes' ][ 'data' ][i][ 'body' ][ 'data' ][j][ 'x' ] = gameState[ 'snakes' ][ 'data' ][i][ 'body' ][ 'data' ][j][ 'x' ] + 1
        gameState[ 'snakes' ][ 'data' ][i][ 'body' ][ 'data' ][j][ 'y' ] = gameState[ 'snakes' ][ 'data' ][i][ 'body' ][ 'data' ][j][ 'y' ] + 1
    end
end
for i = 1, #gameState[ 'you' ][ 'body' ][ 'data' ] do
    gameState[ 'you' ][ 'body' ][ 'data' ][i][ 'x' ] = gameState[ 'you' ][ 'body' ][ 'data' ][i][ 'x' ] + 1
    gameState[ 'you' ][ 'body' ][ 'data' ][i][ 'y' ] = gameState[ 'you' ][ 'body' ][ 'data' ][i][ 'y' ] + 1
end

log( DEBUG, 'Building World Map' )
local grid = util.buildWorldMap( gameState )
util.printWorldMap( grid )


-- This snake makes use of alpha-beta pruning to advance the gamestate
-- and predict enemy behavior. However, it only works for a single
-- enemy. While you can put it into a game with multiple snakes, it
-- will only look at the closest enemy when deciding the next move
-- to make.
if #gameState[ 'snakes' ][ 'data' ] > 2 then
    log( DEBUG, "WARNING: Multiple enemies detected. Choosing the closest snake for behavior prediction." )
end

-- Convenience vars
local me = gameState[ 'you' ]
local enemy = nil
local distance = 99999
for i = 1, #gameState[ 'snakes' ][ 'data' ] do
    if gameState[ 'snakes' ][ 'data' ][i][ 'id' ] ~= me[ 'id' ] then
        local d = mdist(
            me[ 'body' ][ 'data' ][1],
            gameState[ 'snakes' ][ 'data' ][i][ 'body' ][ 'data' ][1]
        )
        if d < distance then
            distance = d
            enemy = gameState[ 'snakes' ][ 'data' ][i]
        end
    end
end

-- This is just to keep from crashing if we're testing in an arena by ourselves
-- though I am curious to see what will happen when trying to predict my own behavior!
if not enemy then
    log( DEBUG, "WARNING: I am the only snake in the game! Using MYSELF for behavior prediction." )
    enemy = me
end

log( DEBUG, 'Enemy Snake: ' .. enemy[ 'name' ] )
local myState = {
    me = me,
    enemy = enemy
}

-- Alpha-Beta Pruning algorithm
-- This is significantly faster than minimax on a single processor, but very challenging to parallelize
local bestScore, bestMove = algorithm.alphabeta( grid, myState, 0, -math.huge, math.huge, nil, nil, true )
log( DEBUG, string.format( 'Best score: %s', bestScore ) )
log( DEBUG, string.format( 'Best move: %s', inspect( bestMove ) ) )

-- FAILSAFE #1
-- Prediction thinks we're going to die soon, however, predictions can be wrong.
-- Pick a random safe neighbour and move there.
if not bestMove then
    log( DEBUG, "WARNING: Trying to cheat death." )
    local my_moves = neighbours( myState[ 'me' ][ 'body' ][ 'data' ][1], grid )
    local enemy_moves = neighbours( myState[ 'enemy' ][ 'body' ][ 'data' ][1], grid )
    local safe_moves = util.n_complement( my_moves, enemy_moves )
    
    if #myState[ 'me' ][ 'body' ][ 'data' ] <= #myState[ 'enemy' ][ 'body' ][ 'data' ] and #safe_moves > 0 then
        my_moves = safe_moves
    end
    
    if #my_moves > 0 then
        bestMove = my_moves[ math.random( #my_moves ) ]
    end
end

-- FAILSAFE #2
-- should only be reached if there is literally nowhere we can move
-- this really only exists to ensure we always return a valid http response
-- always goes left
if not bestMove then
    log( DEBUG, "WARNING: Using failsafe move. I'm probably trapped and about to die." )
    bestMove = { x = me[ 'body' ][ 'data' ][1][ 'x' ] - 1, y = me[ 'body' ][ 'data' ][1][ 'y' ] }
end

-- Move to the destination we decided on
local dir = util.direction( me[ 'body' ][ 'data' ][1], bestMove )
log( DEBUG, string.format( 'Decision: Moving %s to [%s,%s]', dir, bestMove[ 'x' ], bestMove[ 'y' ] ) )


-- Return response to the arena
local response = { move = dir, taunt = util.bieberQuote() }
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
log(DEBUG, string.format('time to response: %.2f, total time: %.2f', respTime, totalTime))
