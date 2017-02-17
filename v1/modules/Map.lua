local Map = {}
Map.__index = Map
setmetatable( Map, {
    __call = function( cls, ... )
        return cls.new( ... )
    end
})

--- Constructor function
function Map.new( gameState )
    
    local self = setmetatable( {}, Map )
    
    -- Generate the tile grid
    ngx.log( ngx.DEBUG, 'Generating tile grid' )
    self.grid = {}
    for y = 1, gameState['height'] do
        self.grid[y] = {}
        for x = 1, gameState['width'] do
            self.grid[y][x] = '.'
        end
    end
    
    -- Place walls
    for i = 1, #gameState['walls'] do
        local wall = gameState['walls'][i]
        self.grid[wall[2]][wall[1]] = 'X'
        ngx.log( ngx.DEBUG, string.format('Placed wall at [%s, %s]', wall[1], wall[2]) )
    end
    
    -- Place gold
    for i = 1, #gameState['gold'] do
        local gold = gameState['gold'][i]
        self.grid[gold[2]][gold[1]] = '$'
        ngx.log( ngx.DEBUG, string.format('Placed gold at [%s, %s]', gold[1], gold[2]) )
    end
    
    -- Place food
    for i = 1, #gameState['food'] do
        local food = gameState['food'][i]
        self.grid[food[2]][food[1]] = 'O'
        ngx.log( ngx.DEBUG, string.format('Placed food at [%s, %s]', food[1], food[2]) )
    end
    
    -- Place snakes
    for i = 1, #gameState['snakes'] do
        if gameState['snakes'][i]['id'] == Util.SNAKE_ID and gameState['snakes'][i]['status'] == 'alive' then
            self.me = gameState['snakes'][i]['coords'][1]
            ngx.log( ngx.DEBUG, string.format( 'Found myself at [%s, %s]', self.me[1], self.me[2] ) )
        end
        for j = 1, #gameState['snakes'][i]['coords'] do
            local snake = gameState['snakes'][i]['coords'][j]
            if j == 1 then
                self.grid[snake[2]][snake[1]] = '@'
                ngx.log( ngx.DEBUG, string.format('Placed snake head at [%s, %s]', snake[1], snake[2]) )
            else
                self.grid[snake[2]][snake[1]] = '#'
                ngx.log( ngx.DEBUG, string.format('Placed snake tail at [%s, %s]', snake[1], snake[2]) )
            end
        end
    end
    
    return self
    
end

function Map.isSafeSquare(v)
    return v == '.' or v == '$' or v == 'O'
end

function Map:__tostring()
    local str = "\n"
    for y = 1, #self.grid do
        for x = 1, #self.grid[y] do
            str = str .. self.grid[y][x]
        end
        if y < #self.grid then
            str = str .. "\n"
        end
    end
    return str
end

function Map:setSquare(pos, val)
    self.grid[pos[2]][pos[1]] = val
end

function Map:getSquare(pos)
    return self.grid[pos[2]][pos[1]]
end

function Map:getGrid()
    return self.grid
end

function Map:getMyHead()
    return self.me
end

return Map