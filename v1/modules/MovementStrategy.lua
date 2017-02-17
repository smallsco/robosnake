local MovementStrategy = {}
MovementStrategy.__index = MovementStrategy
setmetatable( MovementStrategy, {
    __call = function( cls, ... )
        return cls.new( ... )
    end
})


-- Lua optimization: any functions from another module called more than once
-- are faster if you create a local reference to that function.
local isSafeSquare = Map.isSafeSquare
local mdist = Util.manhattan_distance
local neighbours = Util.neighbours


-- @see http://qiita.com/jdeseno/items/6fbd5663cbcf71ad692b
function MovementStrategy:voronoi( grid )

    local closest_squares_by_snake = {}
    for i = 1, #self.snakeHeads do
        closest_squares_by_snake[i] = 0
    end

    for y = 1, self.height do
        for x = 1, self.width do
            if isSafeSquare( grid[y][x] ) then
                local closest = 99999
                local closest_snake = 0
                for i = 1, #self.snakeHeads do
                    local distance = mdist( self.snakeHeads[i], {x,y} )
                    if distance < closest then
                        closest = distance
                        closest_snake = i
                    end
                end
                closest_squares_by_snake[closest_snake] = closest_squares_by_snake[closest_snake] + 1
            end
        end
    end
    
    return closest_squares_by_snake

end


-- this ruins the grid, make sure you always work on a copy of the grid
-- @see https://en.wikipedia.org/wiki/Flood_fill#Stack-based_recursive_implementation_.28four-way.29
function MovementStrategy:floodfill( pos, grid, numSafe )
    local y = pos[2]
    local x = pos[1]
    if isSafeSquare(grid[y][x]) then
        grid[y][x] = 1
        numSafe = numSafe + 1
        local n = neighbours(pos, self.height, self.width)
        for i = 1, #n do
            numSafe = self:floodfill(n[i], grid, numSafe)
        end
    end
    return numSafe
end



--- Constructor function
-- @param table gameState
-- @return MovementStrategy self
function MovementStrategy.new( gameState )
    local self = setmetatable( {}, MovementStrategy )
    
    self.height = gameState['height']
    self.width = gameState['width']
    
    -- self.snakeheads is an array of the heads of all snakes on the map.
    -- self.me stores the index of our snake in self.snakeheads.
    self.snakeHeads = {}
    self.snakeCoords = {}
    for i = 1, #gameState['snakes'] do
        if gameState['snakes'][i]['status'] == 'alive' then
            table.insert(self.snakeHeads, gameState['snakes'][i]['coords'][1])
            table.insert(self.snakeCoords, gameState['snakes'][i]['coords'])
        end
        if gameState['snakes'][i]['id'] == Util.SNAKE_ID then
            self.me = #self.snakeHeads
        end
    end
    
    self.neighbours = neighbours( self.snakeHeads[self.me], self.height, self.width )
    
    return self 
end

--- Test the strategy
-- @return boolean False if the strategy is not possible for this board configuration, otherwise True
function MovementStrategy:test()
    
    if #self.neighbours == 0 then
        ngx.log( ngx.DEBUG, 'Abort MovementStrategy - no neighbouring squares (this should never be reached!!)' )
        return false
    end
    
    return true
    
end

--- Execute the strategy
-- @param Map map an instance of the game board
-- @return mixed The next coordinate pair on the path, or false if execution failed
function MovementStrategy:execute( map )
    
    --[[local v = self:voronoi( map:getGrid() )
    ngx.log(ngx.DEBUG, inspect(v))]]
    
    --local grid2 = Util.deepcopy( map:getGrid() )
    --grid2[self.snakeHeads[self.me][2]][self.snakeHeads[self.me][1]] = '.'
    --local numSafe = self:floodfill( self.snakeHeads[self.me], grid2, 0 )
    --[[local str = "\n"
    for y = 1, #grid2 do
        for x = 1, #grid2[y] do
            str = str .. grid2[y][x]
        end
        if y < #grid2 then
            str = str .. "\n"
        end
    end
    ngx.log(ngx.DEBUG, str)
    ngx.log(ngx.DEBUG, numSafe)]]
    
    
    local moves = neighbours(self.snakeHeads[self.me], self.height, self.width)
    local bestSafe = 0
    local bestMove
    for i = 1, #moves do
        local grid = Util.deepcopy( map:getGrid() )
        if isSafeSquare( grid[moves[i][2]][moves[i][1]] ) then
            grid[self.snakeHeads[self.me][2]][self.snakeHeads[self.me][1]] = '#'
            grid[self.snakeCoords[self.me][#self.snakeCoords[self.me]][2]][self.snakeCoords[self.me][#self.snakeCoords[self.me]][1]] = '.'
            local numSafe = self:floodfill( moves[i], grid, 0 )
            if numSafe > bestSafe then
                bestSafe = numSafe
                bestMove = moves[i]
            end
            ngx.log(ngx.DEBUG, string.format('move: [%s, %s], reachable squares: %s', moves[i][1], moves[i][2], numSafe))
        end
    end
    
    --[[local moves = neighbours(self.snakeHeads[self.me], self.height, self.width)
    for i = 1, #moves do
        
    end]]
    
    if bestMove then
        return bestMove
    end
    
    ngx.log( ngx.DEBUG, 'Abort MovementStrategy - no available moves' )
    return false
    
end

return MovementStrategy