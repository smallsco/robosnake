'''
Prompts user for game replay choice.
Searches logs for data and generates
play-by-play ASCII table.

TODOs:
  * Get snake death rattle / winner
  * Get board width, height
  * Get snake health
'''
import json
import glob
import re
import time
import unicodedata
import sys
import multiprocessing as mp
import os
import copy

from datetime import datetime

LOG_DIR = '/var/log/td-agent/'

REPLAY_FILES = LOG_DIR + 'replays.*'
LOG_FILES = LOG_DIR + 'luasnake.*'


def get_replay_keys():
  '''
  Reads every replay file; Keys are loaded returned in a list of tuples.
  For now, this should be small enough to not worry about memory space.
  '''
  options = []

  # logfiles should not exist without at least one replay file
  replayFileExists = glob.glob(REPLAY_FILES)
  if not replayFileExists:
    raise Exception('No matches have been played yet.')

  print(replayFileExists)

  for filename in replayFileExists:
    with open(filename, 'r') as key_file:
      for line in key_file:
        # Grab JSON
        matches = re.search('\{.*\}', line)
        data = matches.group(0)

        log = json.loads(data)
        log_id = unicodedata.normalize('NFKD', log['log_id']).encode('ascii', 'ignore')

        ids = re.search('([0-9]*)(?::)(.*)(?::)(.*)', log_id)

        if (ids.group(3) == ''):
          continue

        time_float = float(ids.group(3))

        time_utc = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime( time_float ) )

        # game_id, my snake_id, timestamp
        options.append( ( time_utc, ids.group(1), ids.group(2) ) )

  return options


def search_line(line, key):
  '''
  Check if file line is regex match to key
  '''
  pass


def process_wrapper(filename, key, chunkStart, chunkSize):
  '''
  Searches a file (in chunks) for line matches to passed in key
  '''
  result_data = []

  with open(filename) as f:
    f.seek(chunkStart)
    lines = f.read(chunkSize).splitlines()
    
    for line in lines:
      # [time, tag, payload ]
      splits = line.split('\t')

      tag = splits[1]
      payload = splits[2]

      # Keys are matched in the tag
      key_matches = re.search('(?:luasnake.info.)(.*)', tag)
      if key_matches is None:
        continue

      keys = key_matches.group(0).split(':')

      # ignore old, broken logs
      if len(keys) < 3:
        continue

      game_id = keys[0][-1]
      snake_id = keys[1]
      timestamp = keys[2]

      # ignore old, broken logs
      if timestamp == '':
        continue

      time_float = float(timestamp)
      time_utc = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime( time_float ) )

      if key[2] == snake_id and key[1] == game_id and key[0] == time_utc:
        result_data.append(payload)

  return result_data


def chunkify(fname,size=1024*1024):
  '''
  Describe!
  '''
  fileEnd = os.path.getsize(fname)
  with open(fname,'r') as f:
    chunkEnd = f.tell()
    while True:
      chunkStart = chunkEnd
      f.seek(size,1)
      f.readline()
      chunkEnd = f.tell()
      yield chunkStart, chunkEnd - chunkStart
      if chunkEnd > fileEnd:
        break


def search_log_files(key):
  '''
  Some fun with multiprocessing.
  http://www.blopig.com/blog/2016/08/processing-large-files-using-python/

  We have potentially N log files where user choice of logs could be spread
  between 1 or 2 of them. The max size of these are quite large; we'd like
  to parallelize searching them where we can.
  Instead of using `grep` and loading the lines into memory, we attempt this
  minimal, on-the-fly to build each turn's data.

  @params `key` : tuple(game_id, snake_id, timestamp)
  @returns 
  '''
  # initialize multi-core processing pools
  cores = mp.cpu_count()
  pool = mp.Pool(cores)
  jobs = []

  logfiles = glob.glob(LOG_FILES)
  if not logfiles:
    raise Exception('FATAL : Could not find logfiles')

  # create search jobs
  for filename in logfiles:
    for chunkStart, chunkSize in chunkify(filename):
      jobs.append( pool.apply_async(process_wrapper, (filename, key, chunkStart, chunkSize)) )

  # wait for all searches to finish
  payloads = []

  for job in jobs:
    result = job.get()
    payloads.append(result)

  # cleanup
  pool.close()

  # Return flattend list of payloads
  results = [ item for items in payloads for item in items]

  return results

  
def get_user_input(option_list):
  '''
  Command line I/O; prompt user for log data (replay) choice
  @returns key, err
  '''
  print('\nEnter INDEX for which game logfiles to lookup or -1 to replay the most recent')
  print('\n[INDEX]\ttimestamp, game_id, robosnake_id')

  for index, keys in enumerate(option_list):
    print('[{}]\t{}'.format(index, str(keys)[1:-1]))

  choice = input('Choice: ')

  if (choice < -1 or choice > len(option_list)):
    raise Exception('Choice out of range')

  return option_list[choice]


def transform(data_list):
  '''
  Transform a list of payloads into turn-based data structures
  the printer can parse
  '''
  
  # TODO : I need game board width & height
  # right now, assume 10
  
  turns = []

  for str_data in data_list:
    data = json.loads(str_data)

    # protect against log mistakes
    if isinstance(data, unicode):
      continue

    who = data.get('who')
    what = data.get('item')
    turn = data.get('turn')

    if len(turns) <= turn:
      entry = {
        'turn': turn,
        'height': 10,
        'width': 10,
        'snakes': { 'data': [] },
        'food': { 'data': [] }
      }

      turns.append(entry)

    if what == 'food':
      c = data['coordinates']
      turns[turn]['food']['data'].append({'x': c['x'], 'y': c['y']})

    elif what == 'head' or what == 'tail' or what == 'body':
      c = data['coordinates']
      id = who

      # see if we already have snake data
      snake = filter(lambda snake: snake['id'] == who, turns[turn]['snakes']['data'])

      if len(snake) == 0:
        data = {
          'id': who,
          'data': [{
            'object': what,
            'x': c['x'],
            'y': c['y']
          }],
          'length': 99, # TODO
          'health': 99  # TODO
        }

        turns[turn]['snakes']['data'].append(data)

      else:
          snake[0]['data'].append({'object': what, 'x': c['x'], 'y': c['y']})

      # TODO : ADD DEATH RATTLE

  return turns


def search_and_return_log_data():
  '''
  Grabs relevant data from logfiles and returns per-turn data objects
  ready for ASCII printing
  '''
  options = get_replay_keys()

  key = get_user_input(options)

  payloads = search_log_files(key)

  if len(payloads) == 0:
    raise Exception('FATAL: No log data found')

  # return robosnake id  
  return transform(payloads), key[1]


def generate_printable_board(game_data, robosnake_id):
  """
  Renders each turn in ASCII art. Prompts user to navigate
  between turns.
  @param game_data JSON : list of turns
  """

  ## Unicode Printables Declarations ##

  snake_bodies = {
    # 'at', asterisk
    'head': { robosnake_id: u'\u0040', 'enemy': u'\u2731' },
    # Solid Square, Empty Square
    'body': { robosnake_id: u'\u25A0', 'enemy': u'\u25A1' },
    # Inverse Bullet, 'pound'
    'tail': { robosnake_id: u'\u25D8', 'enemy': u'\u2317' }
  }

  empty_space = u'\u25E6' # empty bullet
  food_space =  u'\u2022' # solid bullet

  # iterate over data; build all turns into strings
  game_board_per_turn = []

  for turn in game_data:
    board_width = turn['width'] + 1 # TODO : FIX
    board_height = turn['height'] + 1 # TODO : FIX

    turn_index = turn['turn']

    # Create basic rows
    empty_row = [ empty_space for w in range(board_width)]

    # Create container for all rows
    game_board = [ copy.deepcopy(empty_row) for h in range(board_height)]

    # Inject food items
    food_list = turn['food']['data']
    for food in food_list:
      game_board[food['y']][food['x']] = food_space

    # Inject snake bodies
    snake_list = turn['snakes']['data']
    for snake in snake_list:
      snake_key = robosnake_id if snake['id'] == robosnake_id else 'enemy'

      for mass in snake['data']:
        game_board[mass['y']][mass['x']] = snake_bodies[mass['object']][snake_key]

    # Convert rows into unicode strings; store in new board container
    printable_rows = []
    for row in game_board:
      unicode_string = unicode.join(u' ', (x for x in row))
      printable_rows.append(unicode_string)

    # convert each row array into single unicode string
    game_board_printable = unicode.join(u'\n', (x for x in printable_rows))

    game_board_per_turn.insert(turn_index, game_board_printable)

  return game_board_per_turn


def render_turn_and_data(game_data, game_board, turn):
  health_string = '\n'
  for snake in game_data[turn]['snakes']['data']:
    health_string += 'Snake: {}\tHealth: {}\n'.format(snake['id'], snake['health'])

  print('\nTurn {}\n'.format(turn))

  print(game_board[turn])
  
  print(health_string)

def render_game_replay(game_data, robosnake_id):
  game_board = generate_printable_board(game_data, robosnake_id)

  print('\n\nROBOSNAKE | INSTANT REPLAY\n\nEnter 2 for NEXT turn, 1 for PREVIOUS, any other number to EXIT.')  
  print('(This match played {} turns.)'.format(len(game_data)))
  # TODO : print winner

  turn = 0
  render_turn_and_data(game_data, game_board, turn)

  while True:
    choice = input('Input: ')

    if choice == 2:
      if turn == len(game_data):
        print('There are no future moves to show.')
        continue
      turn += 1
    elif choice == 1:
        if turn == 0:
          print('There are no older moves to show.')
          continue
        turn -= 1
    else:
      sys.exit(0)

    render_turn_and_data(game_data, game_board, turn)
  

def main():
  # Returns turn-index JSON game data, and OUR snake id
  game_data, robosnake_id = search_and_return_log_data()

  render_game_replay(game_data, robosnake_id)


if __name__ == '__main__':
  main()
