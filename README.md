```
                _______  _____  __   _       _____  _______            
                |______ |     | | \  |      |     | |______            
                ______| |_____| |  \_|      |_____| |                  
                                                                       
  ______  _____  ______   _____  _______ __   _ _______ _     _ _______
 |_____/ |     | |_____] |     | |______ | \  | |_____| |____/  |______
 |    \_ |_____| |_____] |_____| ______| |  \_| |     | |    \_ |______
                                                                       
```

## About
Son of Robosnake (SoR) is [Redbrick](http://www.rdbrck.com)'s bounty snake entry for the 2018 [Battlesnake](http://www.battlesnake.io) AI programming competition. It is written using [Lua](https://www.lua.org/) and designed to be run under [OpenResty](http://openresty.org/).

Our win conditions to claim the bounty are the following:
* *TBD*

Under these conditions, we won *TBD* games and lost *TBD*, for a total win record of *TBD* or *TBD*%.


## Strategy
*TBD*


## Configuration
Configuration is done in `/config/http.conf`. 

* `MAX_RECURSION_DEPTH` - this affects how far the alpha-beta pruning algorithm will look ahead. Increasing this will make SoR much smarter, but response times will be much longer.
* `HUNGER_HEALTH` - when SoR's health dips to this value (or below) it will start looking for food.
