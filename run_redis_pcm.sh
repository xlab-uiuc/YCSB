#!/bin/bash
# the pcm command: sudo ./pcm -ns -nsys -csv=output.csv
THREADS=12      # number of threads
NODE=$1     # memory node to run on
PORT=$2     # port of the redis server
CORE=$3     # core affinity. 0x200000000 is 33, 0x800000000 is 35.
WORKLOAD=p
TARGET=100000
OUTPUT_FOLDER=report/experiment6


set -e

# Check if the remote CXL memory is online
echo ""
echo "[INFO] Checking CXL memory..."
if [[ -z $(numactl -H | awk '$1=="node" && $2==1 {print $0}') ]]; then
    sh ./load_cxl_mem.sh
else
    echo "OK"
fi


# Check if the CPU frequency is locked.
echo ""
echo "[INFO] Checking the CPU frequency..."
CPUPOWER_OUT=$(sudo /home/yans3/linux-6.0.2/tools/power/cpupower/cpupower --cpu all frequency-info | grep "current CPU frequency" | awk '$4 != 2.00 {print $0}')
if [[ -n $CPUPOWER_OUT ]]; then
    sh ./lock_cpu_freq.sh
else
    echo "OK"
fi


# if the redis is already set up, shut it down first
EXISTING_INST=0
if [ `redis-cli -p $PORT ping` == "PONG" ];then
    EXISTING_INST=1
    echo "There is already a redis instance running on port $PORT. Are you sure you want to continue? [y/n]"
    read READY
    if [ $READY != "y" ];then
        exit 0
    fi
fi


# start the redis server
if [ $EXISTING_INST == 0 ]; then
    if [ $NODE == "local" ]; then
        sudo numactl --cpunodebind=0 --membind=0 redis-server --port $PORT --daemonize yes
    elif [ $NODE == "remote" ]; then
        sudo numactl --cpunodebind=0 --membind=1 redis-server --port $PORT --daemonize yes
    fi
fi


# pinning to a specific core
if [ -z $CORE ];then
    echo "[ERROR] No core pinning is given."
    exit 0
fi
REDIS_PID=`ps aux | grep "redis-server \*:${PORT}" | awk '{print $2}'`
echo "[INFO] redis pid: $REDIS_PID"
sudo taskset -p $CORE $REDIS_PID
# exit 0


echo "**************"
echo "  LOAD PHASE"
echo "**************"
echo ""
./bin/ycsb load redis -s -P workloads/workload$WORKLOAD -p "redis.host=127.0.0.1" -p "redis.port=${PORT}" \
    -threads $THREADS -target $TARGET > $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE}_qps${TARGET}_Load.txt

echo ""
echo "Load complete. Ready to run the benchmark? [y/n]"
read READY
if [ $READY != "y" ]; then
    exit 0
fi

echo ""
echo "*************"
echo "  RUN PHASE"
echo "*************"
echo ""
# actual YSCB client 
./bin/ycsb run redis -s -P workloads/workload$WORKLOAD \
    -p "redis.host=127.0.0.1" -p "redis.port=${PORT}" \
    -threads $THREADS -target $TARGET > $OUTPUT_FOLDER/workload${WORKLOAD}_${NODE}_qps${TARGET}_Run.txt


redis-cli -p $PORT shutdown
exit 0
