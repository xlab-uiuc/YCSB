#YCSB_WORKLOADS=("s" "t" "u" "w")
YCSB_WORKLOADS=("s") # b 95r 5u
#YCSB_WORKLOADS=("t") # c 100r cleanup
#YCSB_WORKLOADS=("u") # d 95r 5i
#YCSB_WORKLOADS=("w") # f 50r 50raw ?update
NODE=("local" "remote")

for node in ${NODE[@]}; do
    for workload in ${YCSB_WORKLOADS[@]}; do
        echo "sleep 1"
        sleep 1
        echo "${workload} ${node}" 
        #sudo ./run_redis.sh $workload $node loop output_workload_${workload}/output_${node}_loop
        python3 process_output.py -i output_workload_${workload}/output_${node}_loop/ -o loop_${workload}_${node}.xlsx 
    done
done
