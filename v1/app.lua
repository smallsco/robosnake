--[[
      ______  _____  ______   _____  _______ __   _ _______ _     _ _______
     |_____/ |     | |_____] |     | |______ | \  | |_____| |____/  |______
     |    \_ |_____| |_____] |_____| ______| |  \_| |     | |    \_ |______
                                                                           
    -----------------------------------------------------------------------
    
    @author Scott Small <scott.small@rdbrck.com>
    @copyright 2017 Redbrick Technologies, Inc.
]]

--[[
     Initialization:
     1) Get the request data
     2) Convert all coordinates from 0-based to 1-based indices
     3) Create an internal representation of the game map for pathfinding
]]

local request_body = ngx.var.request_body
ngx.log( ngx.DEBUG, 'Got request data: ' .. request_body )
local gameState = cjson.decode( request_body )

ngx.log( ngx.DEBUG, 'Converting Coordinates' )
gameState = Util.convert_gamestate( gameState )

ngx.log( ngx.DEBUG, 'Building World Map' )
local map = Map( gameState )
ngx.log( ngx.DEBUG, map )

-- Seed Lua's PRNG
math.randomseed( os.time() )
local taunt = Util.taunt

-- Get my coordinates
local me = map:getMyHead()
if not me then
    ngx.log( ngx.DEBUG, "Couldn't find myself on the map, I'm probably dead" )
    ngx.print( cjson.encode( { move = 'west', taunt = taunt() } ) )
    ngx.exit( ngx.HTTP_OK )
end

-- Sanity checks
if #gameState['snakes'] == 1 then
    -- Having no other snakes on the board is weird, but not a failure condition
    ngx.log( ngx.DEBUG, "Where is everyone?!?" )
end

--[[
    Strategy:
    1) Get Coins
    2) Get Food, if ( hungry or i am smallest snake )
    3) Attack closest snake, of snakes smaller than me
    4) Move to the "best square"
    5) Move to a safe adjacent square
    6) Failsafe
]]

local destination


--[[
    First and foremost, try to get coins (even if hungry).
    Chances are, even if we're hungry, we'll pass over food
    on the way to the coin. If we get 5 coins, we automatically
    win the game, so this should be prioritized highly.
]]
ngx.log( ngx.DEBUG, 'Init CoinStrategy' )
local coin_strategy = CoinStrategy( gameState )
if coin_strategy:test() then
    ngx.log( ngx.DEBUG, 'Exec CoinStrategy' )
    destination = coin_strategy:execute( map )
end


--[[
    If there's no coins around, and we're hungry
    (low health), grab food.
]]
if not destination then
    ngx.log( ngx.DEBUG, 'Init FoodStrategy' )
    local food_strategy = FoodStrategy( gameState )
    if food_strategy:test() then
        ngx.log( ngx.DEBUG, 'Exec FoodStrategy' )
        destination = food_strategy:execute( map )
    end
end


--[[
    Now things get interesting :)
    To win the game, we need to be the last snake
    standing. If we just looked for free/safe spaces
    at this point (and assuming other snakes do the
    same), it comes down to who's got the best pathfinding
    algorithm. And if every snake finds an optimal path,
    then the game comes down to random chance.
    
    That's no fun. Let's hunt some snakes.
]]
--[[if not destination then
    ngx.log( ngx.DEBUG, 'Init AttackStrategy' )
    local attack_strategy = AttackStrategy( gameState )
    if attack_strategy:test() then
        ngx.log( ngx.DEBUG, 'Exec AttackStrategy' )
        destination = attack_strategy:execute( map )
    end
end]]


--[[
    Pick a square to move to with some intelligence!
]]
if not destination then
    ngx.log( ngx.DEBUG, 'Init MovementStrategy' )
    local movement_strategy = MovementStrategy( gameState )
    if movement_strategy:test() then
        ngx.log( ngx.DEBUG, 'Exec MovementStrategy' )
        destination = movement_strategy:execute( map )
    end
end


--[[
    Just pick a square that won't kill us
    (and recurse once to ensure we won't be trapped)
]]
if not destination then
    ngx.log( ngx.DEBUG, 'Init SimpleStrategy' )
    local simple_strategy = SimpleStrategy( me, gameState )
    if simple_strategy:test() then
        ngx.log( ngx.DEBUG, 'Exec SimpleStrategy' )
        destination = simple_strategy:execute( map )
    end
end


--[[
    Literally a fail safe. If the SimpleStrategy failed
    then there are no safe moves available to us and we
    will die this turn. This "strategy" only exists to
    prevent the app from throwing an error, and return
    a valid JSON response to the arena.
]]
if not destination then
    ngx.log( ngx.DEBUG, 'Init FailsafeStrategy' )
    ngx.log( ngx.DEBUG, 'Exec FailsafeStrategy' )
    destination = {me[1]-1,me[2]}  -- go west
end


-- Move to the destination we decided on
local direction = Util.direction( me, destination )
ngx.log( ngx.INFO, string.format( 'Decision: Moving %s to [%s,%s]', direction, destination[1], destination[2] ) )

-- Return response to the arena
local response = {
    move = direction,
    taunt = taunt()
}
ngx.print( cjson.encode(response) )