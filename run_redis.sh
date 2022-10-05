#!/bin/bash

# script patameters passed from terminal
WORKLOAD=$1
NODE_CONFIG=$2
# Change local parameters here
THREADS=12   # number of threads
TARGET=100000 # requests per second

# stop and restart redis
if [ `redis-cli ping` == "PONG" ]; then
    echo "[Shutting down the Redis.]"
    redis-cli shutdown
    # sudo systemctl stop redis.service
    if [ -z `redis-cli ping` ]; then
        echo "Shutdown success"
    fi
fi

if [ "$NODE_CONFIG" == "local" ]; then
    sudo numactl --cpunodebind=0 --membind=0 redis-server --daemonize yes
elif [ "$NODE_CONFIG" == "remote" ]; then
    sudo numactl --cpunodebind=0 --membind=1 redis-server --daemonize yes
else
    echo "Wrong NUMA config."
    exit 1
fi
# clear redis database
redis-cli FLUSHALL

if [ ! -d output ]; then
    mkdir output
fi
echo "**********"
echo "LOAD PHASE"
echo "**********"
echo ""
./bin/ycsb load redis -s -P workloads/workload$WORKLOAD -p "redis.host=127.0.0.1" -p "redis.port=6379" \
    -threads $THREADS -target $TARGET > output/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_Load.txt
echo ""
echo "*********"
echo "RUN PHASE"
echo "*********"
echo ""
./bin/ycsb run redis -s -P workloads/workload$WORKLOAD -p "redis.host=127.0.0.1" -p "redis.port=6379" \
    -threads $THREADS -target $TARGET > output/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_Run.txt

