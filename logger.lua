local logger = {}

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

-- local restylog = require ("resty.logger.socket")
local restylog = require( "restyloggersocket" )

--[[
    PUBLIC METHODS
--]]

function logger.connect()
  if not restylog.initted() then
    local ok, err = restylog.init{
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

function logger.log( subtag, message_string )
  tag = "luasnake." .. subtag
  time = ngx.now()
  msg = cjson.encode({ tag, time, message_string } )

  local bytes, err = restylog.log(msg)
  if err then
    ngx.log(ngx.ERR, "Failed to log message\t", err, "\tmessage:\t", msg)
    return
  end
end

return logger
