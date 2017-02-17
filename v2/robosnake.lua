--[[
      ______  _____  ______   _____  _______ __   _ _______ _     _ _______
     |_____/ |     | |_____] |     | |______ | \  | |_____| |____/  |______
     |    \_ |_____| |_____] |_____| ______| |  \_| |     | |    \_ |______
                                                                           
    -----------------------------------------------------------------------
    
    @author Scott Small <scott.small@rdbrck.com>
    @copyright 2017 Redbrick Technologies, Inc.
]]


-- Lua optimization: any functions from another module called more than once
-- are faster if you create a local reference to that function.
local DEBUG = ngx.DEBUG
local log = ngx.log
local beginSegment = util.beginSegment
local endSegment = util.endSegment


-- New Relic
newrelic.set_transaction_name( tonumber( ngx.var.transaction_id ), "Move" )


--[[
    MAIN APP LOGIC
]]

-- Seed Lua's PRNG
beginSegment( 'Seeding PRNG' )
math.randomseed( os.time() )
endSegment()

beginSegment( 'Get Request Data' )
local request_body = ngx.var.request_body
log( DEBUG, 'Got request data: ' .. request_body )
local gameState = cjson.decode( request_body )
endSegment()

beginSegment( 'Converting Coordinates' )
log( DEBUG, 'Converting Coordinates' )
gameState = util.convert_gamestate( gameState )
endSegment()

beginSegment( 'Building World Map' )
log( DEBUG, 'Building World Map' )
local grid = util.buildWorldMap( gameState )
util.printWorldMap( grid )
endSegment()


-- This snake makes use of alpha-beta pruning to advance the gamestate
-- and predict enemy behavior. However, it only works for a single
-- enemy. While you can put it into a game with multiple snakes, it
-- will only look at the first living enemy when deciding the next move
-- to make.
if #gameState['snakes'] > 2 then
    str = "WARNING: Multiple enemies detected. My behavior will be undefined."
    log( DEBUG, str )
end

-- Convenience vars
beginSegment( 'Creating Convenience Vars' )
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
endSegment()

-- Alpha-Beta Pruning algorithm
-- This is significantly faster than minimax on a single processor, but very challenging to parallelize
beginSegment( 'Alpha-Beta Pruning' )
local bestScore, bestMove = algorithm.alphabeta(grid, myState, 0, -math.huge, math.huge, nil, nil, true)
endSegment()

-- Minimax Algorithm
-- This is slower than alpha-beta pruning, but much easier to parallelize
--beginSegment( 'Minimax' )
--local bestScore, bestMove = algorithm.minimax(grid, myState, 0, true, nil, nil)
--endSegment()

-- Parallel Minimax Algorithm
-- This performs significantly worse than both of the above on a t2.micro
-- It *should* perform significantly better on a c4.large or above.
--beginSegment( 'Parallel Minimax' )
--local bestScore, bestMove = algorithm.parallel_minimax(grid, myState, 0, true, nil, nil)
--endSegment()

log( DEBUG, string.format('Best score: %s', bestScore) )
log( DEBUG, string.format('Best move: %s', inspect(bestMove)) )

-- FAILSAFE #1
-- Prediction thinks we're going to die soon, however, predictions can be wrong.
-- Pick a random safe neighbour and move there.
if not bestMove then
    beginSegment( 'Failsafe 1' )
    log( DEBUG, "WARNING: Trying to cheat death." )
    local my_moves = algorithm.neighbours( myState['me']['coords'][1], grid )
    local enemy_moves = algorithm.neighbours( myState['enemy']['coords'][1], grid )    
    my_moves = util.n_complement(my_moves, enemy_moves)
    if #my_moves > 0 then
        bestMove = my_moves[math.random(#my_moves)]
    end
    endSegment()
end

-- FAILSAFE #2
-- should only be reached if there is literally nowhere we can move
-- this really only exists to ensure we always return a valid http response
if not bestMove then
    beginSegment( 'Failsafe 2' )
    log( DEBUG, "WARNING: Using failsafe move. I'm probably trapped and about to die." )
    bestMove = {me['coords'][1][1]-1,me['coords'][1][2]}
    endSegment()
end

-- Move to the destination we decided on
beginSegment( 'Get Direction' )
local dir = util.direction( me['coords'][1], bestMove )
log( DEBUG, string.format( 'Decision: Moving %s to [%s,%s]', dir, bestMove[1], bestMove[2] ) )
endSegment()


-- Return response to the arena
beginSegment( 'Return Response' )
local response = { move = dir }
if gameState['turn'] % 10 == 0 then
    response['taunt'] = util.bieberQuote()
end
ngx.print( cjson.encode(response) )
endSegment()