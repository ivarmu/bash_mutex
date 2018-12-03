bash_mutex
==========

This script is intended to execute commands from the bash in a mutex-like way.
```
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
```
