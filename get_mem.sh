#!/bin/bash
PID=$1
while true ; do ps -p $1 -o %mem,rss | awk 'FNR == 2 {print $2}'; sleep 1 ; done
