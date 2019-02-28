#!/usr/bin/env bash
# (c) 2018, Ivan Aragones Muniesa <iaragone@redhat.com>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# 
# Usage: bash_lock.sh <-m 'mutex_name'> [-s] [-r] [-p] [-n <max_queue_length>] [-ml <max_lock_time>] [-mw <max_wait_time>]
#
# Example: bash_lock.sh -m 'get_static_mutex' -s
# Example: bash_lock.sh -m 'get_static_mutex' -s -mw 30
# Example: bash_lock.sh -m 'program_end_of_static_mutex' -p -ml 30 &
# Example: bash_lock.sh -m 'release_static_mutex' -r
#
# NOTE: '-s', '-p' and '-r' options are used to set and release the mutexes manually for long running or multi-command mutex requirements.
# In that cases, the calling process is the responsible of the correct muttex release as <max_lock_time> is completely ignored.
#
# NOTE: '-p' may be usually executed in background (&), as it only programs the lock auto-release (don't execute any command).
#

# Check for the input parameters
if [ $# -eq 0 ]; then
  echo ""
  echo "Usage: bash_lock.sh <-m 'mutex_name'> [-s] [-r] [-p] [-n <max_queue_length>] [-ml <max_lock_time>] [-mw <max_wait_time>]"
  echo ""
  echo "Example: bash_lock.sh -m 'get_static_mutex' -s"
  echo "Example: bash_lock.sh -m 'get_static_mutex' -s -n 3 -mw 30"
  echo "Example: bash_lock.sh -m 'program_end_of_static_mutex' -p -ml 30"
  echo "Example: bash_lock.sh -m 'release_static_mutex' -r"
  echo ""
  echo "NOTE: '-s', '-p' and '-r' options are used to set and release the mutexes manually for long running or multi-command mutex requirements."
  echo "In '-s' and '-r' cases, the calling process is the responsible of the correct mutex release as <max_lock_time> is completely ignored."
  echo ""
  echo "NOTE: '-p' may be usually executed in background (&), as it only programs the lock auto-release as per <max_lock_time> specified."
  echo ""
  echo "Error codes:"
  echo "  0: no errors"
  echo "  101: Missing parameters"
  echo "  102: Missing required parameter '-m'"
  echo "  103: SIGALRM received. The command is killed"
  echo "  104: <max_queue_length> queue size reached"
  echo "  105: <max_wait_time> time exhausted"
  echo ""
  echo "Environment variables:"
  echo "  LOCK_PATH: Indicates where to create the mutexes (default: /var/tmp/)"
  echo ""
  exit 101
fi

### Variables

# Lock directory
_LOCK_PATH="${LOCK_PATH:-/var/tmp}"
_MUTEX_PREFIX="bash_lock_"
_MUTEX_NAME=""

# Maximum amount of time to maintain the lock (in seconds)
_MAX_LOCK_TIME=5
# Maximum time we'll wait for the lock (in seconds)
_MAX_WAIT_TIME=60
# By default, no limit on number of processes waiting for the mutex.
let _MAX_QUEUE_LEN=0
_ONLY_GET_LOCK=0
_PROGRAM_RELEASE=0
_RUN_RELEASE=0

# Parse arguments
if [ "${1}" == "-m" -a "${2}" == "${2#-}" ]; then
  _MUTEX_NAME="${2//[[:space:]]/_}"
  shift
  shift
else
  echo "You must give a name for the mutex (-m)"
  exit 102
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
          _ONLY_GET_LOCK=1
          shift
          ;;
    "-p")
          _PROGRAM_RELEASE=1
          shift
          ;;
    "-r")
          _RUN_RELEASE=1
          shift
          ;;
  esac
done

_LOCK_DIR="${_LOCK_PATH}/${_MUTEX_PREFIX}${_MUTEX_NAME}.lck"

echo "_ONLY_GET_LOCK = ${_ONLY_GET_LOCK}"
echo "_PROGRAM_RELEASE = ${_PROGRAM_RELEASE}"
echo "_RUN_RELEASE = ${_RUN_RELEASE}"
echo "_MAX_LOCK_TIME = ${_MAX_LOCK_TIME}"
echo "_MAX_WAIT_TIME = ${_MAX_WAIT_TIME}"
echo "_MAX_QUEUE_LEN = ${_MAX_QUEUE_LEN}"

# Sum the time to wait for (get the lock + being locked)
let _SUM_LOCK_TIME=_MAX_LOCK_TIME+_MAX_WAIT_TIME

### Functions

function clean_exit {
  # remove us from the queue
  rmdir ${_LOCK_DIR}_$$ &>/dev/null

  # if we got the lock, release it
  if [ -f ${_LOCK_DIR}/info.txt ]; then
    if [ ! -z "$(grep $$ ${_LOCK_DIR}/info.txt)" ]; then
      unlock ${1:-0}
    fi
  fi

  exit ${1:-0}
}

# Function to get into the queue
function queue_in {
  # if the queue is full, exit before try getting the lock
  if [ ${_MAX_QUEUE_LEN} -ne 0 ]; then
    # put ourselves in the mutex queue to write to the queue
    ${0%/*}/bash_mutex.sh -m 'queue' -n 0 -mw 3 -ml 3 " \
      if [ \$(ls -d ${_LOCK_DIR}_* 2>/dev/null | wc -l) -lt ${_MAX_QUEUE_LEN} ]; then \
        mkdir ${_LOCK_DIR}_$$ >&/dev/null; \
      else \
        exit 104; \
      fi; \
    " &>/dev/null || clean_exit 104
    if [ $? -ne 0 ]; then
      echo "Max queue length has been reached. No command is executed from $$"
      clean_exit 104
    fi
  fi
}

function queue_out {
  rmdir ${_LOCK_DIR}_$$ &>/dev/null
}

# Function to lock
function lock {
  let _counter=1
  while ! mkdir ${_LOCK_DIR} &>/dev/null; do
    if [ ${_counter} -gt ${_MAX_WAIT_TIME} ]; then
      echo "Could'nt get the lock: timed out..."
      clean_exit 105
      break
    fi
    let _counter+=1
    sleep 1
  done
  # Write some usefull (debug) information to info.txt file
  cat > ${_LOCK_DIR}/info.txt <<EOF
$(hostname) - PID: $$
$(date)
_Max_Lock_Time: ${_MAX_LOCK_TIME}
- Variables de entorno:

$(env | grep "BASH_MUTEX")
EOF
  sync
#  # We are not on the queue, we got the lock
#  queue_out
}

# Function to unlock 
function unlock {
  # first of all, get out of the queue to let another process to get the slot
  rmdir ${_LOCK_DIR}_$$ &>/dev/null
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
  # finally, release the lock
  rm -rf ${_LOCK_DIR} &>/dev/null
}

# Configure SIGALRM handler
function unlock_signal {
  echo "handling the received signal: ${1}"
  unlock ${1}
  exit 103
}

# MAIN

trap 'unlock_signal ALRM' ALRM
trap 'clean_exit 2' INT
trap 'clean_exit 15' TERM
trap 'clean_exit 1' HUP
trap 'clean_exit 6' ABRT

if [ ${_RUN_RELEASE} -eq 1 ]; then
  # If called with -r we only need to release the lock
  rm -rf ${_LOCK_DIR} &> /dev/null
  clean_exit 0
elif [ ${_PROGRAM_RELEASE} -eq 1 ]; then
  # If called with -p we program auto-unlock
  (sleep ${_SUM_LOCK_TIME}; kill -SIGALRM $$ &>/dev/null; exit 0)&
  _ALARM_GENERATOR_PID=$!
  # Write some usefull (debug) information to info.txt file
  cat > ${_LOCK_DIR}/info.txt <<EOF
$(hostname) - PID: $$
$(date)
_Max_Lock_Time: ${_MAX_LOCK_TIME}
- Variables de entorno:

$(env | grep "BASH_MUTEX")
EOF
  sync
  wait ${_ALARM_GENERATOR_PID}
  # Exit assuring the lock has been released
  unlock 0 
  exit 0
elif [ ${_ONLY_GET_LOCK} ]; then
  # If called with -s we try to get the lock
  queue_in
  lock
fi

# Clean exit
exit 0

