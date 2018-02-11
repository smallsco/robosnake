'''
Prompts user for game replay choice.
Searches logs for data and generates
play-by-play ASCII table.
'''
import json
import glob
import re
import time
import unicodedata
import sys
import multiprocessing as mp
import os

from datetime import datetime

LOG_DIR = '/var/log/td-agent/'

REPLAY_FILES = LOG_DIR + 'replays.*'
LOG_FILES = LOG_DIR + 'luasnake.*.log'


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

  for filename in replayFileExists:
    with open(filename, 'r') as key_file:
      for line in key_file:
        # Grab JSON
        matches = re.search('\{.*\}', line)
        data = matches.group(0)

        log = json.loads(data)
        log_id = unicodedata.normalize('NFKD', log['log_id']).encode('ascii', 'ignore')

        ids = re.search('([0-9]*)(?::)(.*)(?::)(.*)', log_id)

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
  Describe
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
      game_id = keys[0][-1]
      snake_id = keys[1]
      timestamp = keys[2]

      # print(timestamp, game_id, snake_id)
      # print(key)

      if key[2] == snake_id and key[1] == game_id:
        # print('MATCH')
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
  # TODO : can I get data from these get?
  payloads = []
  for job in jobs:
    result = job.get()
    payloads.append(result)

  # cleanup
  pool.close()

  return payloads

  
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


def search_and_return_log_data():
  '''
  Grabs relevant data from logfiles and returns per-turn data objects
  ready for ASCII printing
  '''
  options = get_replay_keys()

  key = get_user_input(options)

  payloads = search_log_files(key)

  # TODO : with payloads, extract & build turn-by-turn data
  if len(payloads) == 0:
    raise Exception('FATAL: No log data found')
  return 'TODO'


def main():
  '''
  Description
  '''

#  try:
  turn_data = search_and_return_log_data()
 # except Exception as err:
  #  print(err)
   # sys.exit(0)

  # Todo : print turn_data


if __name__ == '__main__':
  main()
