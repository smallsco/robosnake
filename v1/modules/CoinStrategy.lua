local CoinStrategy = {}
CoinStrategy.__index = CoinStrategy
setmetatable( CoinStrategy, {
    __call = function( cls, ... )
        return cls.new( ... )
    end
})

-- Lua optimization: any functions from another module called more than once
-- are faster if you create a local reference to that function.
local compare = Util.compare
local isSafeSquare = Map.isSafeSquare
local mdist = Util.manhattan_distance
local neighbours = Util.neighbours

--- Constructor function
-- @param table gameState
-- @return CoinStrategy self
function CoinStrategy.new( gameState )
    local self = setmetatable( {}, CoinStrategy )
    
    self.gold = gameState['gold']
    
    -- self.snakeheads is an array of the heads of all snakes on the map.
    -- self.me stores the index of our snake in self.snakeheads.
    self.snakeHeads = {}
    self.snakeLengths = {}
    self.snakeCoords = {}
    for i = 1, #gameState['snakes'] do
        if gameState['snakes'][i]['status'] == 'alive' then
            table.insert(self.snakeHeads, gameState['snakes'][i]['coords'][1])
            table.insert(self.snakeLengths, #gameState['snakes'][i]['coords'])
            table.insert(self.snakeCoords, gameState['snakes'][i]['coords'])
        end
        if gameState['snakes'][i]['id'] == Util.SNAKE_ID then
            self.me = #self.snakeHeads
        end
    end
    
    return self 
end

--- Test the strategy
-- @return boolean False if the strategy is not possible for this board configuration, otherwise True
function CoinStrategy:test()
    
    -- If there's no coins on the map, abort
    if #self.gold == 0 then
        ngx.log( ngx.DEBUG, 'Abort CoinStrategy - no coins on map' )
        return false
    end
    
    return true
    
end

--- Execute the strategy
-- @param Map map an instance of the game board
-- @return mixed The next coordinate pair on the path, or false if execution failed
function CoinStrategy:execute( map )
    --[[
        Given a list of potential targets (gold, food, snakes etc)...
        1) Measure the distance from each target to me.
        2) Measure the distance from each target to another snake.
        3) Remove any targets that I am not the closest to.
        4) For each target...
           a) search for a path from me to that target
           b) If we find a path, break, return our next movement
           c) If we do not find a path, repeat for the next target
        5) If there are no paths to any target, return nil :(
    ]]

    -- OPTIONS:
    -- -- shortest vs. longest distance target
    -- -- whether to remove targets that others are closer to or not
    
    -- Initialize Jumper
    local jgrid = Grid( map:getGrid() )
    local pathfinder = Pathfinder( jgrid, 'ASTAR', isSafeSquare )
    pathfinder:setHeuristic('MANHATTAN')
    pathfinder:setMode('ORTHOGONAL')
    
    -- Initialize the targets array
    -- Each item will be of the form { distance, coordinate pair }
    local targets = {}
    for i = 1, #self.gold do
        
        -- Find distance from me to the target
        local my_distance = mdist( self.snakeHeads[self.me], self.gold[i] )
        
        -- Find distance from each enemy to the target
        local enemy_is_closer = false
        for j = 1, #self.snakeHeads do
            if j ~= self.me then
                local enemy_distance = mdist( self.snakeHeads[j], self.gold[i] )
                -- If I'm the closest, add the gold to the targets array
                ngx.log( ngx.DEBUG, string.format(
                    'Target [%s,%s]: my_distance %s, enemy_distance %s',
                    self.gold[i][1],
                    self.gold[i][2],
                    my_distance,
                    enemy_distance
                ))
                if enemy_distance <= my_distance then
                    enemy_is_closer = true
                    break
                end
            end
        end
        
        if not enemy_is_closer then
            table.insert( targets, { my_distance, self.gold[i] } )
        end
    end
    
    -- If there's no targets left, we need to try another strategy
    if #targets == 0 then
        ngx.log( ngx.DEBUG, 'Abort CoinStrategy - no available targets' )
        return false
    end
    
    -- Sort the targets by the shortest distance to me
    table.sort( targets, compare )
    
    -- DEBUG: pretty-print the targets array
    ngx.log( ngx.DEBUG, 'Targets:' )
    for i = 1, #targets do
        ngx.log( ngx.DEBUG, inspect( targets[i] ) )
    end
    
    for i = 1, #targets do
        -- Find path to target
        local path_reverse = {}
        ngx.log( ngx.DEBUG, string.format(
            'Snake [%s,%s] ----> Target [%s,%s]',
            self.snakeHeads[self.me][1],
            self.snakeHeads[self.me][2],
            targets[i][2][1],
            targets[i][2][2]
        ))
        local jpath = pathfinder:getPath(
            self.snakeHeads[self.me][1],
            self.snakeHeads[self.me][2],
            targets[i][2][1],
            targets[i][2][2]
        )
        if jpath then
            ngx.log( ngx.DEBUG, 'Path found, length: ' .. jpath:getLength() )
            local destination
            for node, count in jpath:nodes() do
                table.insert(path_reverse, 1, {node.x, node.y})
                ngx.log( ngx.DEBUG, string.format( 'Step %s - [%s,%s]', count, node.x, node.y ) )
            end
            
            -- If I were to move to this space, could I get back to where I came from?
            ngx.log( ngx.DEBUG, 'Testing for exit' )
            local new_me_coords = {}
            local grid2 = map:getGrid()
            for j = 1, self.snakeLengths[self.me] do
                
                -- erase my old position    
                for k = 1, #self.snakeCoords[self.me] do
                    grid2[self.snakeCoords[self.me][k][2]][self.snakeCoords[self.me][k][1]] = '.'
                end
                
                if path_reverse[j] then
                    table.insert( new_me_coords, path_reverse[j] )
                    -- set my new position
                    if j == 1 then
                        grid2[path_reverse[j][2]][path_reverse[j][1]] = '@'
                    else
                        grid2[path_reverse[j][2]][path_reverse[j][1]] = '#'
                    end
                else
                    -- i am longer than the path, use my history to extend
                    local offset = self.snakeLengths[self.me] - (j-2)
                    table.insert( new_me_coords, self.snakeCoords[self.me][offset] )
                    grid2[self.snakeCoords[self.me][offset][2]][self.snakeCoords[self.me][offset][1]] = '#'
                end
                
            end
            
            -- Find a random free neighbour next to my start point
            -- (the start point itself may contain my tail)
            local square, square_val
            local start_neighbours = neighbours( self.snakeHeads[self.me], #grid2[1][1], #grid2[1] )
            for j = 1, #start_neighbours do
                square = start_neighbours[j]
                square_val = grid2[ start_neighbours[j][2] ][ start_neighbours[j][1] ]
                if square_val == '.' or square_val == '$' or square_val == 'O' then
                   break 
                end
            end
            if not square then
                -- fall back to the start point
                square = self.snakeHeads[self.me]
            end
            ngx.log( ngx.DEBUG, string.format('Searching for exit to [%s,%s]', square[1], square[2]) )
            
            local jgrid2 = Grid( grid2 )
            local pathfinder2 = Pathfinder( jgrid, 'ASTAR', isSafeSquare )
            pathfinder2:setHeuristic('MANHATTAN')
            pathfinder2:setMode('ORTHOGONAL')
            ngx.log( ngx.DEBUG, string.format(
                'Target [%s,%s] ----> Exit [%s,%s]',
                new_me_coords[1][1],
                new_me_coords[1][2],
                square[1],
                square[2]
            ))
            local jpath2 = pathfinder:getPath(
                new_me_coords[1][1],
                new_me_coords[1][2],
                square[1],
                square[2]
            )
            if jpath2 then
                ngx.log( ngx.DEBUG, 'Exit found, length: ' .. jpath2:getLength() )
                for node, count in jpath2:nodes() do
                    ngx.log( ngx.DEBUG, string.format( 'Step %s - [%s,%s]', count, node.x, node.y ) )
                end
                destination = path_reverse[#path_reverse - 1]
                return destination
            else
                ngx.log( ngx.DEBUG, 'No exit from target' )
            end
        else
            ngx.log( ngx.DEBUG, 'No path to target' )
        end
    end
    
    ngx.log( ngx.DEBUG, 'Abort CoinStrategy - no available paths' )
    return false
    
end

return CoinStrategy