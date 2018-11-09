#!/usr/bin/env bash
# (c) 2018, Ivan Aragones Muniesa <iaragone@redhat.com>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# 
# Usage: bash_mutex.sh [-n <max_queue_length>] "command to run in a semaphore-like manner"
#
# Example: bash_mutex.sh 'echo $$ >> /tmp/test'
# Example: bash_mutex.sh -n 3 'echo $$ >> /tmp/test'
#

# Check for the input parameters
if [ $# -eq 0 ]; then
  echo ""
  echo "Usage: bash_mutex.sh [-n <max_queue_length] \"command to run in a semaphore-like manner\""
  echo ""
  echo "Example: bash_mutex.sh 'echo $$ >> /tmp/test'"
  echo "Example: bash_mutex.sh -n 3 'echo $$ >> /tmp/test'"
  echo ""
  exit
fi

# By default, no limit on number of processes waiting for the mutex.
let _MAX_QUEUE_LEN=0
# Set it to ${2} if "-n" is the first argument
if [ "${1}" == "-n" ]; then
  _MAX_QUEUE_LEN=${2}
  shift
  shift
fi

# Lock directory
_LOCK_DIR="/var/tmp/bash_mutex.lck"

# Maximum amount of time to maintain the lock (in seconds)
_MAX_LOCK_TIME=5
# Maximum time we'll wait for the lock (in seconds)
_MAX_WAIT_TIME=60
# Sum the time to wait for (get the lock + being locked)
let _SUM_LOCK_TIME=_MAX_LOCK_TIME+_MAX_WAIT_TIME

function clean_exit {
  # remove us from the queue
  rmdir ${_LOCK_DIR}_$$ &>/dev/null
  if [ ! -z "$(pstree -p ${_ALARM_GENERATOR_PID})" ]; then
    kill -SIGKILL ${_ALARM_GENERATOR_PID} &>/dev/null
  fi
  exit
}

# Function to lock
function lock {
  let _counter=1
  # first, put ourselves in the mutex queue
  mkdir ${_LOCK_DIR}_$$ >&/dev/null
  # if the queue is full, exit before try getting the lock
  if [ ${_MAX_QUEUE_LEN} -ne 0 ]; then
    if [ $(ls -d ${_LOCK_DIR}_* | wc -l) -gt ${_MAX_QUEUE_LEN} ]; then
      echo "Max queue length has been reached. No command is executed"
      clean_exit
    fi
  fi
  while ! mkdir ${_LOCK_DIR} &>/dev/null; do
    if [ ${_counter} -gt ${_MAX_WAIT_TIME} ]; then
      echo "Max wait time exhausted... No command is executed"
      clean_exit
      break
    fi
    let _counter+=1
    sleep 1
  done
}

# Function to unlock 
function unlock {
  # first of all, get out of the queue to let another process to get the slot
  rmdir ${_LOCK_DIR}_$$ &>/dev/null
  rmdir ${_LOCK_DIR} &>/dev/null
  # Can remove the auto-unlock timer
  if [ ! -z "$(pstree -p ${_ALARM_GENERATOR_PID})" ]; then
    kill -SIGKILL ${_ALARM_GENERATOR_PID} &>/dev/null
  fi
}

# Configure SIGALRM handler
function unlock_signal {
  unlock
  exit
}
trap unlock_signal ALRM

# Program auto-unlock
(sleep ${_SUM_LOCK_TIME}; kill -SIGALRM $$ &>/dev/null; exit)&
_ALARM_GENERATOR_PID=$!

# Get the lock
lock

# MAIN process
echo "executing the given command: $@"
date
eval $@

# MAIN process finished
# Release the lock
unlock

# Kill the auto-unlocker sub-shell before regular exit
kill -SIGKILL ${_ALARM_GENERATOR_PID} &>/dev/null

exit 0
