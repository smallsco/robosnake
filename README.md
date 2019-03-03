```
  ______  _____  ______   _____  _______ __   _ _______ _     _ _______
 |_____/ |     | |_____] |     | |______ | \  | |_____| |____/  |______
 |    \_ |_____| |_____] |_____| ______| |  \_| |     | |    \_ |______
                                                                       
                _______ _     _        _____ _____ _____               
                |  |  | |____/           |     |     |                 
                |  |  | |    \_ .      __|__ __|__ __|__               
                                                                       
```

## About
The Robosnake (Robo) is a snake for the 2019 [Battlesnake](http://www.battlesnake.io) AI programming competition. It is written using [Lua](https://www.lua.org/) and designed to be run under [OpenResty](http://openresty.org/).

In previous years it was [Redbrick](http://www.rdbrck.com)'s bounty snake. You can see those versions here:

* 2017: https://github.com/rdbrck/bountysnake2017
* 2018: https://github.com/rdbrck/bountysnake2018


## 2019 Results
Robo did not compete in the 2019 tournament however it did challenge a number of Bounty Snakes:

* **Defeated:** Pixel Union, Schneider Electric, Workday, Semaphore, Bambora, Rooof, FreshWorks, Sendwithus (Level 7)
* **Lost To:** Giftbit, Checkfront

On the [play.battlesnake.io](http://play.battlesnake.io) leaderboard Robo had a high of position #7 and a low of position #29, averaging somewhere around #13.


## Strategy
Robo makes use of [alpha-beta pruning](https://en.wikipedia.org/wiki/Alpha%E2%80%93beta_pruning) in order to make predictions about the future state of the game. All possible moves by ourself are evaluated, as well as all possible moves by the enemy. Robo will always select for itself the move that results in the best possible state of the game board, and it will select for the enemy the move that results in the worst possible state of the game board (from Robo's point of view, that is).

In order to evaluate a particular game board state, we look at the following metrics to produce a numeric score:

* How much health do I have?
* How much health does the enemy have?
* How many moves are available to me from my current position?
* How many moves are available to the enemy from its' current position?
* How many free squares can I see from my current position? (flood fill)
* How many free squares can the enemy see from its' current position? (another flood fill)
* How hungry am I right now?
* How close am I to food?
* How close am I to the enemy's head?
* How close am I to the edge of the game board?

In the event that we're playing in an arena containing more than one enemy snake, the closest snake to Robo will be chosen as the "enemy" for the purposes of algorithmic computation. If two snakes are equally close to Robo, the shorter of the two will be selected.

In the event that we're playing in an empty arena, Robo will choose *itself* as the "enemy". This will often lead to hilarity!


## How to Run (Docker)
1. Download and install [Docker](http://docker.com/).
2. Navigate to the directory where you checked out this repository and run `docker-compose up`
3. That's it! Robo will be listening on port `5000`.


## How to Run (Classic)
1. Download and install [OpenResty](http://openresty.org/).
2. Using LuaRocks, install `cjson` which is a mandatory dependency: `/usr/share/luajit/bin/luarocks install cjson`
3. Symlink `config/http.conf` into the `/etc/nginx/conf.d` directory.
4. Symlink `config/server.dev.conf` into the `/etc/nginx/sites-enabled` directory (and remove anything else in that directory).
5. Restart the nginx process and give the snake a try!


## Configuration
Configuration is done in `/config/http.conf`. 

* `MAX_RECURSION_DEPTH` - this affects how far the alpha-beta pruning algorithm will look ahead. Increasing this will make Robo much smarter, but response times will be much longer.
* `HUNGER_HEALTH` - when Robo's health dips to this value (or below) it will start looking for food.
* `LOW_FOOD` - if the food on the game board is at this number or lower, Robo will use a less aggressive heuristic and prioritize food.
