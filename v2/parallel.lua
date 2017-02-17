-- Lua optimization: any functions from another module called more than once
-- are faster if you create a local reference to that function.
local DEBUG = ngx.DEBUG
local log = ngx.log

newrelic.set_transaction_name( tonumber( ngx.var.transaction_id ), "Parallel" )

local request_body = ngx.var.request_body
log( DEBUG, 'Got subrequest data: ' .. request_body )
local parallelState = cjson.decode( request_body )

local move = parallelState['move']
local new_grid = parallelState['grid']
local new_state = parallelState['state']
local depth = parallelState['depth']
local maximizingPlayer = parallelState['maximizingPlayer']
local bestScore = parallelState['bestScore']
local bestMove

if maximizingPlayer then
    
    -- Update grid and coords for this move
    log( DEBUG, string.format( 'My move: %s', inspect(move) ) )
    table.insert( new_state['me']['coords'], 1, move )
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
    
    local newScore = algorithm.parallel_minimax( new_grid, new_state, depth+1, false )
    if bestScore < newScore then
        bestScore = newScore
        bestMove = move
    end
    
else
    
    -- Update grid and coords for this move
    log( DEBUG, string.format( 'Enemy move: %s', inspect(move) ) )
    table.insert( new_state['enemy']['coords'], 1, move )
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
        
    local newScore = algorithm.parallel_minimax( new_grid, new_state, depth+1, true )
    if bestScore > newScore then
        bestScore = newScore
        bestMove = move
    end
    
end

ngx.print(cjson.encode({
    score = bestScore,
    move = bestMove
}))