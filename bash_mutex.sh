#!/usr/bin/env bash
# (c) 2018, Ivan Aragones Muniesa <iaragone@redhat.com>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# 
# Usage: bash_mutex.sh "entire command to run in a semaphore-like manner"
#
# Example: bash_mutex.sh 'echo $$ >> /tmp/test'
#

# Check for the input parameters
if [ $# -ne 1 ]; then
  echo ""
  echo "Usage: bash_mutex.sh \"entire command to run in a semaphore-like manner\""
  echo ""
  echo "Example: bash_mutex.sh 'echo $$ >> /tmp/test'"
  echo ""
  exit
fi

# Lock directory
_LOCK_DIR="/var/tmp/bash_mutex.lck"

# Maximum amount of time to maintain the lock (in seconds)
_MAX_LOCK_TIME=5
# Maximum time we'll wait for the lock (in seconds)
_MAX_WAIT_TIME=60
# Sum the time to wait for (get the lock + being locked)
let _SUM_LOCK_TIME=_MAX_LOCK_TIME+_MAX_WAIT_TIME

# Function to lock
function lock {
  let _counter=1
  while ! mkdir ${_LOCK_DIR} &>/dev/null; do
    if [ ${_counter} -gt ${_MAX_WAIT_TIME} ]; then
      break
    fi
    let _counter+=1
    sleep 1
  done
}

# Function to unlock 
function unlock {
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

# Kill the unto-unlocker sub-shell before regular exit
kill -SIGKILL ${_ALARM_GENERATOR_PID} &>/dev/null

exit 0
