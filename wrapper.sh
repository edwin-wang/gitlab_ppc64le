#!/bin/bash

if [ x$ext_ip != x ]; then
  sed -e "0,/host: localhost/s/host: localhost/host: $ext_ip/g" -i /home/git/gitlab/config/gitlab.yml
fi

if [ x$ext_port != x ]; then
  sed -e "0,/port: 80/s/port: 80/port: $ext_port/g" -i /home/git/gitlab/config/gitlab.yml
fi

# Start the first process
service postfix start
status=$?
if [ $status -ne 0 ]; then
  echo "Failed to start postfix: $status"
  exit $status
fi

service postgresql start
status=$?
if [ $status -ne 0 ]; then
  echo "Failed to start postgresql: $status"
  exit $status
fi

service redis-server start
status=$?
if [ $status -ne 0 ]; then
  echo "Failed to start redis-server: $status"
  exit $status
fi

sleep 60

service gitlab start
status=$?
if [ $status -ne 0 ]; then
  echo "Failed to start gitlab: $status"
  exit $status
fi

service nginx start
status=$?
if [ $status -ne 0 ]; then
  echo "Failed to start nginx: $status"
  exit $status
fi

# Naive check runs checks once a minute to see if either of the processes exited.
# This illustrates part of the heavy lifting you need to do if you want to run
# more than one service in a container. The container will exit with an error
# if it detects that either of the processes has exited.
# Otherwise it will loop forever, waking up every 60 seconds

while /bin/true; do
  ps aux | grep postfix | grep -q -v grep
  POSTFIX_STATUS=$?
  ps aux | grep redis | grep -q -v grep
  POSTGRESQL_STATUS=$?
  ps aux | grep redis-server | grep -q -v grep
  REDIS_STATUS=$?
  ps aux | grep gitlab | grep -q -v grep
  GITLAB_STATUS=$?
  ps aux | grep nginx | grep -q -v grep
  NGINX_STATUS=$?
  # If the greps above find anything, they will exit with 0 status
  # If they are not both 0, then something is wrong
  if [ $POSTFIX_STATUS -ne 0 ] && [ $POSTGRESQL_STATUS -ne 0 ] && [ $REDIS_STATUS -ne 0 ] && [ $GITLAB_STATUS -ne 0 ] && [ $NGINX_STATUS -ne 0 ]; then
    echo "One of the processes has already exited."
    exit -1
  fi
  sleep 180
done

