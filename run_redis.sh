#!/bin/bash

# example commands:
# mkdir output_experiment3
# sudo ./run_redis.sh b remote 50000 output_experiment3/output_remote  or:
# sudo ./run_redis.sh a local loop output_experiment3/output_local
# python3 process_output.py -i output_experiment3/output_remote/ -o report/experiment3/remote.xlsx

# Command to stop Redis server if nother else would work:
# /etc/init.d/redis-server stop

# script patameters passed from terminal
WORKLOAD=$1
NODE_CONFIG=$2
[ ! $4 ] && OUTPUT_FOLDER="output" || OUTPUT_FOLDER=$4

# Change local parameters here
THREADS=12      # number of threads
LOOP_BASE=5000     # the starting point of the loop
LOOP_STEP=10000  # the step of the loop
LOOP_ITER=7     # the number of iterations of the loop
if [ ! $3 ]; then
    TARGET=100000 # requests per second
elif [ $3 == "loop" ]; then
    QPS_LOOP=1
else
    QPS_LOOP=0
    TARGET=$3
fi

# if no parameter is passed, print help info
if [ ! $1 ]; then
    echo "Usage:"
    echo ""
    echo "Run Experiment:"
    echo "sudo ./run_redis.sh b remote 50000 output_experiment3/output_remote"
    echo ""
    echo "Data Process:"
    echo "python3 process_output.py -i output_experiment3/output_remote/ -o report/experiment3/remote.xlsx"
    echo ""
    exit 0
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
elif [ "$NODE_CONFIG" == "interleave" ]; then
    sudo sh ./load_cxl_mem.sh
    sudo numactl --cpunodebind=0 --interleave 0,1,2 redis-server --daemonize yes
else
    echo "Wrong NUMA config."
    exit 1
fi

mkdir -p $OUTPUT_FOLDER

# create output folder if not exist
# if [ ! -d $OUTPUT_FOLDER ]; then
# fi

# lock CPU freq to 2GHz
sh lock_cpu_freq.sh
sh check_cpu_freq.sh

REDIS_PID=`pgrep redis-server`
echo "redis-server pid = ${REDIS_PID}"


# Set ITERATION to 10 if QPS_LOOP is 1
[ $QPS_LOOP == 1 ] && ITERATION=$LOOP_ITER || ITERATION=1
for ((i=0;i<$ITERATION;i++)); do

    if [ $QPS_LOOP == 1 ]; then
        TARGET=$(($LOOP_BASE+$i*$LOOP_STEP))
        echo "========= QPS - $TARGET ========="
    fi
    # continue # for testing

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
        -threads $THREADS > $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_Load.txt

    echo "lauching perf ..."
    sudo perf stat -e LLC-loads,LLC-load-misses,LLC-stores,LLC-store-misses -p $REDIS_PID -o $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_perf.txt&
    #sudo perf stat -e L1-dcache-load-misses,L1-dcache-loads,L1-dcache-stores,L1-icache-load-misses -p $REDIS_PID -o $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_perf_L1.txt&
    PERF_PID=$!
    #sudo /opt/intel/oneapi/vtune/2023.0.0/bin64/vtune -collect uarch-exploration -target-pid $REDIS_PID -result-dir $OUTPUT_FOLDER/vtune_out&

    echo ""
    echo "*************"
    echo "  RUN PHASE"
    echo "*************"
    echo ""
    # actual YSCB client 
    ./bin/ycsb run redis -s -P workloads/workload$WORKLOAD \
        -p "redis.host=127.0.0.1" -p "redis.port=6379" \
        -threads $THREADS -target $TARGET > $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_Run.txt
    
    # end background tasks
    sudo kill -INT $PERF_PID
    #sudo /opt/intel/oneapi/vtune/2023.0.0/bin64/vtune -r $OUTPUT_FOLDER/vtune_out -command stop
    #sudo /opt/intel/oneapi/vtune/2023.0.0/bin64/vtune  -report summary -result-dir $OUTPUT_FOLDER/vtune_out/ -report-output $OUTPUT_FOLDER/vtune_summary.txt  
    sudo pkill -f "get_mem.sh"
done

# unlock CPU freq to on demand
sh unlock_cpu_freq.sh
