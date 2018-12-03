#!/usr/bin/env bash
# (c) 2018, Ivan Aragones Muniesa <iaragone@redhat.com>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# 
# Usage: bash_mutex.sh <-m 'mutex_name'> [-s] [-r] [-n <max_queue_length>] [-ml <max_lock_time>] [-mw <max_wait_time>] "command to run in a semaphore-like manner"
#
# Example: bash_mutex.sh -m 'echo' 'echo $$ >> /tmp/test'"
# Example: bash_mutex.sh -m 'echo2' -n 3 'echo $$ >> /tmp/test'"
# Example: bash_mutex.sh -m 'mutex' -ml 60 'echo $$ >> /tmp/test'"
# Example: bash_mutex.sh -m 'mutex2' -mw 30 'echo $$ >> /tmp/test'"
# Example: bash_mutex.sh -m 'label1' -n 3 -ml 60 -mw 30 'echo $$ >> /tmp/test'"
# Example: bash_mutex.sh -m 'get_static_mutex' -s
# Example: bash_mutex.sh -m 'get_static_mutex' -s -mw 30
# Example: bash_mutex.sh -m 'release_static_mutex' -r
#
# NOTE: -s and -r options are used to set and release the mutexes manually for long running or multi-command mutex requirements. In that cases,
# the calling process is the responsible of the correct muttex release as <max_lock_time> is completely ignored.
#

# Check for the input parameters
if [ $# -eq 0 ]; then
  echo ""
  echo "Usage: bash_mutex.sh <-m 'mutex_name'> [-s] [-r] [-n <max_queue_length>] [-ml <max_lock_time>] [-mw <max_wait_time>] \"command to run in a semaphore-like manner\""
  echo ""
  echo "Example: bash_mutex.sh -m 'echo' 'echo $$ >> /tmp/test'"
  echo "Example: bash_mutex.sh -m 'echo2' -n 3 'echo $$ >> /tmp/test'"
  echo "Example: bash_mutex.sh -m 'mutex' -ml 60 'echo $$ >> /tmp/test'"
  echo "Example: bash_mutex.sh -m 'mutex2' -mw 30 'echo $$ >> /tmp/test'"
  echo "Example: bash_mutex.sh -m 'label1' -n 3 -ml 60 -mw 30 'echo $$ >> /tmp/test'"
  echo "Example: bash_mutex.sh -m 'get_static_mutex' -s"
  echo "Example: bash_mutex.sh -m 'get_static_mutex' -s -n 3 -mw 30"
  echo "Example: bash_mutex.sh -m 'release_static_mutex' -r"
  echo ""
  echo "NOTE: -s and -r options are used to set and release the mutexes manually for long running or multi-command mutex requirements. In that cases,"
  echo "the calling process is the responsible of the correct muttex release as <max_lock_time> is completely ignored."
  echo ""
  echo "Error codes:"
  echo "  0: no errors"
  echo "  1: Missing parameters"
  echo "  2: Missing required parameter '-m'"
  echo "  3: SIGALRM received. The command is killed"
  echo ""
  echo "Environment variables:"
  echo "  LOCK_PATH: Indicates where to create the mutexes (default: /var/tmp/)"
  echo ""
  exit 1
fi

### Variables

# Lock directory
_LOCK_PATH="${LOCK_PATH:-/var/tmp}"
_MUTEX_PREFIX="bash_mutex_"
_MUTEX_NAME=""

# Maximum amount of time to maintain the lock (in seconds)
_MAX_LOCK_TIME=5
# Maximum time we'll wait for the lock (in seconds)
_MAX_WAIT_TIME=60
# By default, no limit on number of processes waiting for the mutex.
let _MAX_QUEUE_LEN=0
_AUTO_UNLOCK_ENABLED=1
_RUN_RELEASE=0

# Parse arguments
if [ "${1}" == "-m" ]; then
  _MUTEX_NAME="${2//[[:space:]]/_}"
  shift
  shift
else
  echo "You must give a name for the mutex (-m)"
  exit 2
fi

while [ "${1#-}" != "${1}" ]; do
  case "${1}" in
    "-ml")
          _MAX_LOCK_TIME=${2}
          shift
          shift
          ;;
    "-mw")
          _MAX_WAIT_TIME=${2}
          shift
          shift
          ;;
    "-n")
          _MAX_QUEUE_LEN=${2}
          shift
          shift
          ;;
    "-s")
          _AUTO_UNLOCK_ENABLED=0
          shift
          ;;
    "-r")
          _RUN_RELEASE=1
          shift
          ;;
  esac
done

_LOCK_DIR="${_LOCK_PATH}/${_MUTEX_PREFIX}${_MUTEX_NAME}.lck"

echo "_AUTO_UNLOCK_ENABLED = ${_AUTO_UNLOCK_ENABLED}"
echo "_MAX_LOCK_TIME = ${_MAX_LOCK_TIME}"
echo "_MAX_WAIT_TIME = ${_MAX_WAIT_TIME}"
echo "_MAX_QUEUE_LEN = ${_MAX_QUEUE_LEN}"

# Sum the time to wait for (get the lock + being locked)
let _SUM_LOCK_TIME=_MAX_LOCK_TIME+_MAX_WAIT_TIME

### Functions

function release {
  rmdir ${_LOCK_DIR}
  exit 0
}

function clean_exit {
  # remove us from the queue
  rmdir ${_LOCK_DIR}_$$ &>/dev/null
  # Can remove the auto-unlock timer and all it's childs
  if [ ! -z "${_ALARM_GENERATOR_PID}" ]; then
    _procs="$(pstree -p ${_ALARM_GENERATOR_PID} | grep -Po '[^[:digit:]]*\K[[:digit:]]*' | sort -nr)"
    if [ ! -z "${_procs}" ]; then
      for _pid in ${_procs}; do
        kill -SIGTERM ${_pid} &>/dev/null
      done
    fi
  fi
  exit ${1:-0}
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
  # Can remove the auto-unlock timer and all it's childs
  if [ ! -z "${_ALARM_GENERATOR_PID}" ]; then
    _procs="$(pstree -p ${_ALARM_GENERATOR_PID} | grep -Po '[^[:digit:]]*\K[[:digit:]]*' | sort -nr)"
    if [ ! -z "${_procs}" ]; then
      for _pid in ${_procs}; do
        kill -${1} ${_pid} &>/dev/null
      done
    fi
  fi
  # Can remove the running process and all it's childs
  if [ ! -z "${_COMMAND}" ]; then
    _procs="$(pstree -p ${_COMMAND} | grep -Po '[^[:digit:]]*\K[[:digit:]]*' | sort -nr)"
    if [ ! -z "${_procs}" ]; then
      for _pid in ${_procs}; do
        kill -${1} ${_pid} &>/dev/null
      done
    fi
  fi
}

# Configure SIGALRM handler
function unlock_signal {
  echo "handling the received signal: ${1}"
  unlock ${1}
  exit 3
}

# MAIN

# If called with -r we only need to release the lock
if [ ${_RUN_RELEASE} -eq 1 ]; then
  rmdir ${_LOCK_DIR} &> /dev/null
  exit 0
fi

trap 'unlock_signal ALRM' ALRM
trap 'clean_exit INT' INT
trap 'clean_exit TERM' TERM
trap 'clean_exit HUP' HUP
trap 'clean_exit ABRT' HUP

if [ ${_AUTO_UNLOCK_ENABLED} -eq 1 ]; then
  # Program auto-unlock
  (sleep ${_SUM_LOCK_TIME}; kill -SIGALRM $$ &>/dev/null; exit 0)&
  _ALARM_GENERATOR_PID=$!

  # Get the lock
  lock

  # MAIN process
  echo "executing the given command: $@"
  date
  eval $@ &
  _COMMAND=$!
  wait ${_COMMAND}
  
  # MAIN process finished
  # Release the lock and exit
  unlock
else
  # Get the lock
  lock
fi

clean_exit 0

# Never reached exit
exit 0
