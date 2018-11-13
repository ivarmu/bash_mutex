bash_mutex
==========

This script is intended to execute commands from the bash in a mutex-like way.
```
# 
# Usage: bash_mutex.sh [-n <max_queue_length>] "command to run in a semaphore-like manner"
#
# Example: bash_mutex.sh -m 'echo' 'echo $$ >> /tmp/test'"
# Example: bash_mutex.sh -m 'echo2' -n 3 'echo $$ >> /tmp/test'"
# Example: bash_mutex.sh -m 'mutex' -ml 60 'echo $$ >> /tmp/test'"
# Example: bash_mutex.sh -m 'mutex2' -mw 30 'echo $$ >> /tmp/test'"
# Example: bash_mutex.sh -m 'label1' -n 3 -ml 60 -mw 30 'echo $$ >> /tmp/test'"
#
# Error codes:"
#   0: no errors"
#   1: Missing parameters"
#   2: Missing required parameter '-m'"
#   3: SIGALRM received. The command is killed"
#
```
