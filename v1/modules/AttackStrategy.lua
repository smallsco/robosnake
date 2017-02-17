local AttackStrategy = {}
AttackStrategy.__index = AttackStrategy
setmetatable( AttackStrategy, {
    __call = function( cls, ... )
        return cls.new( ... )
    end
})

-- Lua optimization: any functions from another module called more than once
-- are faster if you create a local reference to that function.
local compare = Util.compare
local direction = Util.direction
local isSafeSquare = function(v) return v == '.' or v == '$' or v == 'O' or v == '@' end
local mdist = Util.manhattan_distance

--- Constructor function
-- @param table gameState
-- @return AttackStrategy self
function AttackStrategy.new( gameState )
    local self = setmetatable( {}, AttackStrategy )
    
    -- Grab living enemy snakes from the game state.
    -- Track how long they are.
    self.enemies = {}
    self.enemy_lengths = {}
    self.height = gameState['height']
    self.width = gameState['width']
    for i = 1, #gameState['snakes'] do
        if gameState['snakes'][i]['status'] == 'alive' then
            if gameState['snakes'][i]['id'] == Util.SNAKE_ID then
                self.me = gameState['snakes'][i]
            else
                table.insert(self.enemy_lengths, #gameState['snakes'][i]['coords'])
                table.insert(self.enemies, gameState['snakes'][i])
            end
        end
    end
    
    return self 
end

--- Test the strategy
-- @return boolean False if the strategy is not possible for this board configuration, otherwise True
function AttackStrategy:test()
    
    if #self.enemies == 0 then
        ngx.log( ngx.DEBUG, 'Abort AttackStrategy - no enemies on map' )
        return false
    end
    
    return true
end

--- Execute the strategy
-- @param Map map an instance of the game board
-- @return mixed The next coordinate pair on the path, or false if execution failed
function AttackStrategy:execute( map )
    
    --[[
        If there are any snakes smaller than us on the map,
        find the one closest to us and TAKE IT'S HEAD
    ]]
    
    -- Initialize the targets array
    -- Each item will be of the form { distance, coordinate pair }
    local targets = {}
    local grid = Util.deepcopy( map:getGrid() )
    for i=1, #self.enemy_lengths do
        if self.enemy_lengths[i] < #self.me['coords'] then
            local distance = mdist( self.me['coords'][1], self.enemies[i]['coords'][1] )
            table.insert( targets, { distance, self.enemies[i]['coords'][1] } )
        end
    end
    
    -- If there's no targets available for headshots, try the tail cutoff instead
    if #targets == 0 then
        ngx.log( ngx.DEBUG, 'Abort AttackStrategy - No snakes smaller than me on the board' )
        return false
    end
    
    -- Sort the targets by the shortest distance to me
    table.sort( targets, compare )
    
    -- DEBUG: pretty-print the targets array
    ngx.log( ngx.DEBUG, 'Targets:' )
    for i = 1, #targets do
        ngx.log( ngx.DEBUG, inspect( targets[i] ) )
    end
    
    -- Initialize Jumper
    local jgrid = Grid( grid )
    local pathfinder = Pathfinder( jgrid, 'ASTAR', isSafeSquare )
    pathfinder:setHeuristic('MANHATTAN')
    pathfinder:setMode('ORTHOGONAL')
    
    for i = 1, #targets do
        -- Find path to target
        ngx.log( ngx.DEBUG, string.format(
            '[%s,%s] ----> [%s,%s]',
            self.me['coords'][1][1],
            self.me['coords'][1][2],
            targets[i][2][1],
            targets[i][2][2]
        ))
        local path = pathfinder:getPath(
            self.me['coords'][1][1],
            self.me['coords'][1][2],
            targets[i][2][1],
            targets[i][2][2]
        )
        if path then
            ngx.log( ngx.DEBUG, 'Path found, length: ' .. path:getLength() )
            local destination
            for node, count in path:nodes() do
                if count == 2 then
                    destination = { node.x, node.y } 
                end
                ngx.log( ngx.DEBUG, string.format( 'Step %s - [%s,%s]', count, node.x, node.y ) )
            end
            return destination
        else
            ngx.log( ngx.DEBUG, 'No path to target' )
        end
    end
    
    ngx.log( ngx.DEBUG, 'Abort AttackStrategy - no available paths' )
    return false
    
end

return AttackStrategy