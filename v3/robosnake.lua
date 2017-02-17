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


--[[
    MAIN APP LOGIC
]]

-- Seed Lua's PRNG
math.randomseed( os.time() )

local request_body = ngx.var.request_body
log( DEBUG, 'Got request data: ' .. request_body )
local gameState = cjson.decode( request_body )

log( DEBUG, 'Converting Coordinates' )
gameState = util.convert_gamestate( gameState )

log( DEBUG, 'Building World Map' )
local grid = util.buildWorldMap( gameState )
util.printWorldMap( grid )

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


-- Algorithm
--local ok, bestMove = algorithm.recurse(grid, me, enemy, 0, true)
local bestMove = algorithm.move( grid, me, enemy, gameState['food'], gameState['gold'], gameState['mode'] )

if not bestMove then
    -- add safe neighbours
    log( DEBUG, 'FAIL SAFE NEIGHBOURS #2!!!' )
    local moves
    if #me['coords'] > #enemy['coords'] then
        moves = algorithm.neighboursWithHeads( me['coords'][1], grid )
    else
        moves = algorithm.neighbours( me['coords'][1], grid )
    end
    bestMove = moves[math.random(#moves)]
end



-- FAILSAFE
-- should only be reached if there is literally nowhere we can move
-- this really only exists to ensure we always return a valid http response
if not bestMove then
    log( DEBUG, "WARNING: Using failsafe move. I'm probably trapped and about to die." )
    bestMove = {me['coords'][1][1]-1,me['coords'][1][2]}  -- go west young snake
end

-- Move to the destination we decided on
local dir = util.direction( me['coords'][1], bestMove )
log( DEBUG, string.format( 'Decision: Moving %s to [%s,%s]', dir, bestMove[1], bestMove[2] ) )


-- Return response to the arena
local response = { move = dir }
if gameState['turn'] % 10 == 0 then
    response['taunt'] = util.bieberQuote()
end
ngx.print( cjson.encode(response) )