#!/bin/sh

env >> /etc/environment

# start cron in the foreground (replacing the current process)
echo "$@"
exec "$@"

# source: https://blog.thesparktree.com/cron-in-docker