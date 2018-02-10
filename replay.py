'''
TODO : THIS DESCRIPTION

note: todo to make an actual UUID? Still isn't unique enough...
'''
import json
import glob
import re
import time

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

        # convert json string into python dict
        log = json.loads(data)
        time_ms = log['time']
        time_utc = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(time_ms))

        log_id = log['log_id']

        ids = re.search('([0-9]*)(?::)(.*)', log_id)

        # game_id, snake_id, timestamp
        options.append((ids.group(1), ids.group(2), time_utc))

  print('\nEnter INDEX for which game logfiles to lookup or \'xx\' to replay the most recent')
  print('format: [INDEX] Game id, Your Snake Id, Timestamp\n')
  for index, keys in enumerate(options):
    print(index, keys[:])

  choice = input('Choice: ')
  print(choice)

if __name__ == '__main__':
  main()
