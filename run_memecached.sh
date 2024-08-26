#!/bin/bash
#set -xe

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

prepare() {
	UTIL_FOLDER=`pwd`/utils
	
	bash $UTIL_FOLDER/lock_cpu_freq.sh
	bash $UTIL_FOLDER/check_cpu_freq.sh
	bash $UTIL_FOLDER/hyperthread_ctrl.sh 0
	bash $UTIL_FOLDER/numa_balance_ctrl.sh 0
}

quit() {
	UTIL_FOLDER=`pwd`/utils

	bash $UTIL_FOLDER/unlock_cpu_freq.sh
	bash $UTIL_FOLDER/hyperthread_ctrl.sh 1
	bash $UTIL_FOLDER/numa_balance_ctrl.sh 0

	sudo bash -c "echo madvise > /sys/kernel/mm/transparent_hugepage/enabled"
}

# if no parameter is passed, print help info
if [ ! $1 ]; then
    echo "Usage:"
    echo ""
    echo "Run Experiment:"
    echo "sudo ./run_memcached.sh b remote 50000 output_experiment3/output_remote"
    echo ""
    echo "Data Process:"
    echo "python3 process_output.py -i output_experiment3/output_remote/ -o report/experiment3/remote.xlsx"
    echo ""
    exit 0
fi

mkdir -p $OUTPUT_FOLDER

# create output folder if not exist
# if [ ! -d $OUTPUT_FOLDER ]; then
# fi

# lock CPU freq to 2GHz
# sh lock_cpu_freq.sh
# sh check_cpu_freq.sh

# running memcached
sudo killall memcached
/usr/bin/memcached -u root -m 131000 -p 11211 -l 127.0.0.1 &

# prepare
# Set ITERATION to 10 if QPS_LOOP is 1
[ $QPS_LOOP == 1 ] && ITERATION=$LOOP_ITER || ITERATION=1
for ((i=0;i<$ITERATION;i++)); do

    if [ $QPS_LOOP == 1 ]; then
        TARGET=$(($LOOP_BASE+$i*$LOOP_STEP))
        echo "========= QPS - $TARGET ========="
    fi
    # continue # for testing

    echo "**************"
    echo "  LOAD PHASE"
    echo "**************"
    echo ""

    ./bin/ycsb load memcached -s -P "workloads/workload$WORKLOAD" -p "memcached.hosts=127.0.0.1" 2>&1
    # ./bin/ycsb load redis -s -P workloads/workload$WORKLOAD -p "redis.host=127.0.0.1" -p "redis.port=6379" \
    #     -threads $THREADS > $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_Load.txt

    # echo "lauching perf ..."
    # sudo perf stat -e LLC-loads,LLC-load-misses,LLC-stores,LLC-store-misses -p $REDIS_PID -o $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_perf.txt&
    #sudo perf stat -e L1-dcache-load-misses,L1-dcache-loads,L1-dcache-stores,L1-icache-load-misses -p $REDIS_PID -o $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_perf_L1.txt&
    # PERF_PID=$!
    #sudo /opt/intel/oneapi/vtune/2023.0.0/bin64/vtune -collect uarch-exploration -target-pid $REDIS_PID -result-dir $OUTPUT_FOLDER/vtune_out&

    echo ""
    echo "*************"
    echo "  RUN PHASE"
    echo "*************"
    echo ""

    ./start
    ./bin/ycsb run memcached -s -P "workloads/workload$WORKLOAD" -p "memcached.hosts=127.0.0.1" 2>&1
    ./end
    # actual YSCB client 
    # ./bin/ycsb run redis -s -P workloads/workload$WORKLOAD \
    #     -p "redis.host=127.0.0.1" -p "redis.port=6379" \
    #     -threads $THREADS -target $TARGET > $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE_CONFIG}_qps${TARGET}_Run.txt
    
    # end background tasks
    sudo kill -INT $PERF_PID
    #sudo /opt/intel/oneapi/vtune/2023.0.0/bin64/vtune -r $OUTPUT_FOLDER/vtune_out -command stop
    #sudo /opt/intel/oneapi/vtune/2023.0.0/bin64/vtune  -report summary -result-dir $OUTPUT_FOLDER/vtune_out/ -report-output $OUTPUT_FOLDER/vtune_summary.txt  
    sudo pkill -f "get_mem.sh"
done

# unlock CPU freq to on demand
# sh unlock_cpu_freq.sh

# quit

sudo killall memcached