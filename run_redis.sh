#!/bin/bash

# script patameters passed from terminal
WORKLOAD=$1
NODE_CONFIG=$2
[ ! $4 ] && OUTPUT_FOLDER="output" || OUTPUT_FOLDER=$4
# Change local parameters here
THREADS=12   # number of threads
if [ ! $3 ]; then
    TARGET=100000 # requests per second
elif [ $3 == "loop" ]; then
    QPS_LOOP=1
else
    QPS_LOOP=0
    TARGET=$3
fi

# stop and restart redis
if [ `redis-cli ping` == "PONG" ]; then
    echo "[Shutting down the Redis...]"
    redis-cli shutdown
    # sudo systemctl stop redis.service
    if [ -z `redis-cli ping` ]; then
        echo "Shutdown success"
    fi
fi

if [ "$NODE_CONFIG" == "local" ]; then
    sudo numactl --cpunodebind=0 --membind=0 redis-server --daemonize yes
elif [ "$NODE_CONFIG" == "remote" ]; then
    sudo sh ./load_cxl_mem.sh
    sudo numactl --cpunodebind=0 --membind=1 redis-server --daemonize yes
else
    echo "Wrong NUMA config."
    exit 1
fi

# create output folder if not exist
if [ ! -d $OUTPUT_FOLDER ]; then
    mkdir $OUTPUT_FOLDER
fi

# lock CPU freq to 2GHz
sh lock_cpu_freq.sh
sh check_cpu_freq.sh

REDIS_PID=`pgrep redis-server`
echo "redis-server pid = ${REDIS_PID}"


# Set ITERATION to 10 if QPS_LOOP is 1
[ $QPS_LOOP == 1 ] && ITERATION=10 || ITERATION=1
for ((i=1;i<=$ITERATION;i++)); do

    if [ $QPS_LOOP == 1 ]; then
        TARGET=$(($i*5000))
        echo "========= QPS - $TARGET ========="
    fi

    # clear redis database
    echo "[Flushing Redis...]"
    redis-cli FLUSHALL

    echo "monitoring redis memory usage ..."
    # ps output RSS size in KB
    # althernative with pmap? https://stackoverflow.com/a/2816070
    sh get_mem.sh $REDIS_PID > $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_redis_mem.txt&

    echo "**************"
    echo "  LOAD PHASE"
    echo "**************"
    echo ""
    ./bin/ycsb load redis -s -P workloads/workload$WORKLOAD -p "redis.host=127.0.0.1" -p "redis.port=6379" \
        -threads $THREADS -target $TARGET > $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_Load.txt

    echo "lauching perf ..."
    sudo perf stat -e LLC-loads,LLC-load-misses,LLC-stores,LLC-store-misses -p $REDIS_PID -o $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_perf.txt&
    PERF_PID=$!

    echo ""
    echo "*************"
    echo "  RUN PHASE"
    echo "*************"
    echo ""
    # actual YSCB client 
    ./bin/ycsb run redis -s -P workloads/workload$WORKLOAD -p "redis.host=127.0.0.1" -p "redis.port=6379" \
        -threads $THREADS -target $TARGET > $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_Run.txt
    
    # end background tasks
    sudo kill -INT $PERF_PID
    sudo pkill -f "get_mem.sh"
done

# unlock CPU freq to on demand
sh unlock_cpu_freq.sh
