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

local mdist = util.mdist
local neighbours = algorithm.neighbours
local now = ngx.now
local update_time = ngx.update_time
local log = logger.log


--[[
    MAIN APP LOGIC
]]

-- Seed Lua's PRNG
math.randomseed( os.time() )

-- Get the POST request and decode the JSON
local request_body = ngx.var.request_body

local gameState = cjson.decode( request_body )

--[[
    Data received from gameboard is not unique between games.
    E.g., One instance of the game board will have the same               
    game id and snake id for each restart, but different
    start times. We use all three to create a shared log_id

    We create a unique log_id based on turn 0's timestamp. This
    is written to the cache, and retrieved based on game and snake ids.
--]]

local game_start_time = ngx.ctx.startTime
local cache_key = "" .. gameState[ 'id' ] .. ":" .. gameState[ 'you' ][ 'id' ]

if gameState[ 'turn' ] == 0 then
    ngx.shared.game_keys:set(cache_key, game_start_time)
    log("replay_key", { log_id = "" .. gameState[ 'id' ] .. ":" .. gameState[ 'you' ][ 'id' ] .. ":" .. game_start_time } )
else
    game_start_time = ngx.shared.game_keys:get(cache_key)
end

local log_id = cache_key .. ":" .. game_start_time

-- Logging tags
-- INFO for parseable data. DEBUG for human-friendly.
local INFO = "info." .. log_id
local DEBUG = "debug." .. log_id

log( INFO, { turn = gameState[ 'turn' ], who = "game", game_id = log_id, width = gameState[ 'width' ], height = gameState[ 'height' ] } )

-- Convert to 1-based indexing
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

local grid = util.buildWorldMap( gameState, log_id )

-- print to local NGX
-- util.printWorldMap( grid )

-- This snake makes use of alpha-beta pruning to advance the gamestate
-- and predict enemy behavior. However, it only works for a single
-- enemy. While you can put it into a game with multiple snakes, it
-- will only look at the closest enemy when deciding the next move
-- to make.
if #gameState[ 'snakes' ][ 'data' ] > 2 then
    log( DEBUG, "WARNING: Multiple enemies detected. Choosing closest snake for prediction." )
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
    log( DEBUG, "WARNING: I am the only snake in the game!" )
    enemy = me
end

log(DEBUG, "Enemy Snake: " .. enemy[ 'name' ] )

local myState = {
    me = me,
    enemy = enemy
}

-- Alpha-Beta Pruning algorithm
-- This is significantly faster than minimax on a single processor, but very challenging to parallelize
local bestScore, bestMove = algorithm.alphabeta( grid, myState, 0, -math.huge, math.huge, nil, nil, true, {}, {}, log_id )

log( DEBUG, string.format( 'Best score: %s\tBest move: %s', bestScore, inspect( bestMove ) ) )

-- FAILSAFE #1
-- This is reached if no move is returned by the alphabeta pruning algorithm.
-- This can happen if the recursion depth is 0 or if searching up to the recursion depth
-- results in all unwinnable scenarios. However this doesn't mean we are doomed, we may
-- have moved into a space that appears to trap us, but at some move beyond the
-- max recursion depth we are able to break free (i.e. trapped by the enemy's tail which
-- later gets out of the way)
if not bestMove then
    log( DEBUG, "WARNING: No best move returned from alphabeta!" )

    local my_moves = neighbours( myState[ 'me' ][ 'body' ][ 'data' ][1], grid )
    local enemy_moves = neighbours( myState[ 'enemy' ][ 'body' ][ 'data' ][1], grid )
    local safe_moves = util.n_complement( my_moves, enemy_moves )
    
    if #myState[ 'me' ][ 'body' ][ 'data' ] <= #myState[ 'enemy' ][ 'body' ][ 'data' ] and #safe_moves > 0 then
        -- We're smaller than the enemy and there's one or more safe squares (a square that
        -- we can reach and the enemy can not) available - prefer those squares.
        log( DEBUG, "Moving to random safe neighbour" )
        my_moves = safe_moves
    else
        -- We're _larger_ than the enemy, or we're smaller but there are no safe squares
        -- available - we may end up in a head-on-head collision.
        log( DEBUG, "Moving to random free neighbour" )
    end
    
    if #my_moves > 0 then
        -- Move to any square that _may_ give us a chance of living.
        bestMove = my_moves[ math.random( #my_moves ) ]
    else
        -- If we reach this point, there isn't anywhere safe to move to and we're going to die.
        -- This just prefers snake deaths over wall deaths, so that the official battlesnake
        -- unit tests pass.
        log( DEBUG, "FATAL: No free neighbours; avoiding wall." )
        my_moves = neighbours( myState[ 'me' ][ 'body' ][ 'data' ][1], grid, true )
        bestMove = my_moves[ math.random( #my_moves ) ]
    end
end

-- FAILSAFE #2
-- We're dead. This only exists to ensure that we always return a valid JSON response
-- to the game board. It always goes left.
if not bestMove then
    log( DEBUG, "FATAL: Wall collision unavoidable. Moving left!" )
    bestMove = { x = me[ 'body' ][ 'data' ][1][ 'x' ] - 1, y = me[ 'body' ][ 'data' ][1][ 'y' ] }
end

-- Move to the destination we decided on
local dir = util.direction( me[ 'body' ][ 'data' ][1], bestMove )
log( DEBUG, string.format( 'Decision: Moving myself %s to [%s,%s]', dir, bestMove[ 'x' ], bestMove[ 'y' ] ) )

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
    ngx.log(ngx.ERR, "Could not complete ngx EOF function\t" .. err)
end
collectgarbage()
collectgarbage()

update_time()
totalTime = now() - ngx.ctx.startTime
log( DEBUG, { who = "game", item = "time", value = { response = string.format('%.2f', respTime), total = string.format('%.2f', totalTime) } } )
