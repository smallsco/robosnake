local SimpleStrategy = {}
SimpleStrategy.__index = SimpleStrategy
setmetatable( SimpleStrategy, {
    __call = function( cls, ... )
        return cls.new( ... )
    end
})

-- Lua optimization: any functions from another module called more than once
-- are faster if you create a local reference to that function.
local isSafeSquare = Map.isSafeSquare
local neighbours = Util.neighbours

--- Constructor function
-- @param table gameState
-- @return AttackStrategy self
function SimpleStrategy.new( me, gameState )
    local self = setmetatable( {}, SimpleStrategy )
    
    self.height = gameState['height']
    self.width = gameState['width']
    self.neighbours = neighbours( me, self.height, self.width )
    
    return self
end

--- Test the strategy
-- @return boolean False if the strategy is not possible for this board configuration, otherwise True
function SimpleStrategy:test()
    if #self.neighbours == 0 then
        ngx.log( ngx.DEBUG, 'Abort SimpleStrategy - no neighbouring squares (this should never be reached!!)' )
        return false
    end
    return true
end

--- Execute the strategy
-- @param Map map an instance of the game board
-- @return mixed The next coordinate pair on the path, or false if execution failed
function SimpleStrategy:execute(map)
    
    -- Check each neighbour to my current position to see if it is a safe square.
    -- If so, we will call that square a "candidate neighbour"
    local candidate_neighbours = {}
    for i = 1, #self.neighbours do
        local safe = map:getSquare( self.neighbours[i] )
        if isSafeSquare(safe) then
            table.insert( candidate_neighbours, self.neighbours[i] )
        end
    end
    
    -- DEBUG: pretty-print the candidate neighbours array
    ngx.log( ngx.DEBUG, 'Candidate Neighbours:' )
    for i = 1, #candidate_neighbours do
        ngx.log( ngx.DEBUG, inspect( candidate_neighbours[i] ) )
    end
    
    -- For each candidate neighbour, check each of it's neighbours to see if THAT square is safe
    -- this is so we don't put ourselves into a square surrounded by three walls
    -- this is a naive implementation and doesn't take into consideration possible movements of other snakes
    local safe_neighbours = {}
    for i = 1, #candidate_neighbours do
        local candidate_neighbours_neighbours = neighbours( candidate_neighbours[i], self.height, self.width )
        local candidate_neighbour_safe = false
        for j = 1, #candidate_neighbours_neighbours do
            local safe = map:getSquare( candidate_neighbours_neighbours[j] )
            if isSafeSquare(safe) then
                candidate_neighbour_safe = true
            end
        end
        if candidate_neighbour_safe then
            table.insert( safe_neighbours, candidate_neighbours[i] )
        end
    end
    
    -- DEBUG: pretty-print the safe neighbours array
    ngx.log( ngx.DEBUG, 'Safe Neighbours:' )
    for i = 1, #safe_neighbours do
        ngx.log( ngx.DEBUG, inspect( safe_neighbours[i] ) )
    end
    
    
    if #safe_neighbours > 0 then
        return safe_neighbours[math.random(#safe_neighbours)]
    end
    
    ngx.log( ngx.DEBUG, 'Abort SimpleStrategy - no safe neighbours' )
    return false
end

return SimpleStrategy