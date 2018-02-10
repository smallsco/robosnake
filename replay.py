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

from datetime import datetime

LOG_DIR = '/var/log/td-agent/'

REPLAY_FILES = LOG_DIR + 'replays.*'
LOG_FILEs = LOG_DIR + 'luasnake.'

def main():
  replayFileExists = glob.glob(REPLAY_FILES)
  if not replayFileExists:
    print('No game has been played yet')

  '''
  Parse replay files for log keys
  '''
  options = []
  for filename in replayFileExists:
    with open(filename, 'r') as key_file:
      for line in key_file:
        matches = re.search('\{.*\}', line)
        data = matches.group(0)

        log = json.loads(data)
        log_id = unicodedata.normalize('NFKD', log['log_id']).encode('ascii', 'ignore')

        ids = re.search('([0-9]*)(?::)(.*)(?::)(.*)', log_id)

        time_float = float(ids.group(3))
        time_utc = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime( time_float ) )

        # game_id, my snake_id, timestamp
        options.append( ( time_utc, ids.group(1), ids.group(2) ) )

  print('\nEnter INDEX for which game logfiles to lookup or \'xx\' to replay the most recent')

  print('\n[INDEX]\ttimestamp, game_id, robosnake_id')
  for index, keys in enumerate(options):
    print('[{}]\t{}'.format(index, str(keys)[1:-1]))


  choice = input('Choice: ')
  print(choice)

if __name__ == '__main__':
  main()
