#!/bin/bash
#set -xe

# script patameters passed from terminal
WORKLOAD=$1
[ ! $2 ] && OUTPUT_FOLDER="output" || OUTPUT_FOLDER=$2



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

kernel=`uname -r`
content=`cat /sys/kernel/mm/transparent_hugepage/enabled`

if [[ $content == *"[always]"* ]]; then
    THP_CONFIG="THP_always"
elif [[ $content == *"[madvise]"* ]]; then
    THP_CONFIG="THP_madvise"
elif [[ $content == *"[never]"* ]]; then
    THP_CONFIG="THP_never"
else
    echo "Unable to determine the status of Transparent Huge Pages."
fi


timestamp=`date +%Y-%m-%d_%H-%M-%S`
OUTPUT_FOLDER=$OUTPUT_FOLDER-${kernel}-${THP_CONFIG}-${timestamp}
echo "Output folder: $OUTPUT_FOLDER"
mkdir -p $OUTPUT_FOLDER

FLAME_PATH=$(realpath ../FlameGraph)
PERF_PATH=perf
ITERATION=1
for ((i=0;i<$ITERATION;i++)); do


    echo "**************"
    echo "  LOAD PHASE"
    echo "**************"
    echo ""

    sudo pkill memcached
    
    
    sudo numactl --cpunodebind=0 --membind=0 --physcpubind=0,1,2,3,4,5,6,7 /usr/bin/memcached -u root -m 131000 -p 11211 -l 127.0.0.1 > $OUTPUT_FOLDER/workload${WORKLOAD}_server_iter${i}.log 2>&1 &
    # /usr/bin/memcached -u root -m 131000 -p 11211 -l 127.0.0.1 > $OUTPUT_FOLDER/workload${WORKLOAD}_server_iter${i}.log 2>&1 &
    sleep 5

    sudo taskset --cpu-list 9-15 ./bin/ycsb load memcached -s -P "workloads/workload$WORKLOAD" -p "memcached.hosts=127.0.0.1" 2>&1 | tee $OUTPUT_FOLDER/workload${WORKLOAD}_Load_iter${i}.txt

    echo ""
    echo "*************"
    echo "  RUN PHASE"
    echo "*************"
    echo ""

    sudo rm perf.data
    sudo $PERF_PATH record -F 50000 -a -g -- sleep 360 &
    PERF_PID=$!
    sleep 1
    echo "perf PID: $PERF_PID"
    pgrep_perf_pid=$(pgrep perf)
    echo "pgrep perf PID: $pgrep_perf_pid"

    sudo taskset --cpu-list 9-15 ./bin/ycsb run memcached -s -P "workloads/workload$WORKLOAD" -p "memcached.hosts=127.0.0.1" 2>&1 | tee $OUTPUT_FOLDER/workload${WORKLOAD}_Run_iter${i}.txt
    
    echo "kill $PERF_PID"
    sudo kill -SIGINT $PERF_PID
    sudo kill -SIGINT $pgrep_perf_pid
    # NOTE: important sleep so that perf.data can be written to disk
    sleep 20
    # sudo $PERF_PATH script
    sudo $PERF_PATH script > $OUTPUT_FOLDER/workload${WORKLOAD}_out.perf 2>&1

    sudo pkill memcached
    sleep 5

    $FLAME_PATH/stackcollapse-perf.pl $OUTPUT_FOLDER/workload${WORKLOAD}_out.perf  \
        > $OUTPUT_FOLDER/workload${WORKLOAD}_out.folded 2>&1
    # sudo rm $OUTPUT_FOLDER/${FILE_PREFIX}_out.perf 
    $FLAME_PATH/flamegraph.pl $OUTPUT_FOLDER/workload${WORKLOAD}_out.folded \
        > $OUTPUT_FOLDER/workload${WORKLOAD}_out.svg 2>&1
    echo "save flamegraph to $OUTPUT_FOLDER/workload${WORKLOAD}_out.svg"
done


# echo "save output to $OUTPUT_FOLDER"

# sudo chmod +666 $OUTPUT_FOLDER
# sudo -u siyuan python3 collect_ycsb_result.py --folder $OUTPUT_FOLDER


