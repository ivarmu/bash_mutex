bash_mutex
==========

This script is intended to execute commands from the bash in a mutex-like way.
```
# 
# Usage: bash_mutex.sh [-n <max_queue_length>] "command to run in a semaphore-like manner"
#
# Example: bash_mutex.sh 'echo $$ >> /tmp/test'
# Example: bash_mutex.sh -n 3 'echo $$ >> /tmp/test'
#
```
