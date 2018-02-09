--[[
    Logger Module

    Common data & functions for exporting play-by-play
    luasnake + game board to fluentd via socket logging.

    TAGS
      "luasnake.[level]" - use for game mechanics
      "debug.[level]"     - use for ngx / lua 

    LEVELS
      info : Parser-friendly statements for replays
      debug : Human-friendly statements of robosnake & algorithm
--]]

local lualog = {}

-- Easy access logger configuration
local SOCKET_HOST = "127.0.0.1"
local SOCKET_PORT = 24224
local SOCKET_TYPE = "tcp"

local json = require "json"
local logger = require "resty.logger.socket"

--[[
    PUBLIC METHODS
--]]

function lualog.connect()
  if not logger.initted() then
    local ok, err = logger.init{
      sock_type = SOCKET_TYPE,
      host = SOCKET_HOST,
      port = SOCKET_PORT,
      flush_limit = 0,
      max_retry_times = 3,
    }

    if not ok then
      ngx.log(ngx.ERR, "Failed to initialize the logger\t", err)
      return
    end
  end
end

function lualog.log( tag, message_string )
  lualog.connect()

  time = ngx.now
  msg = json.encode({ tag, time, { message = message_string } } )

  local bytes, err = logger.log(msg)
  if err then
    ngx.log(ngx.ERR, "Failed to log message\t", err, "\tmessage:\t", msg)
    return
  end
end

return lualog


