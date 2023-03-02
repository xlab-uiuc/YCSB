#YCSB_WORKLOADS=("r" "s" "t" "u" "w")
#YCSB_WORKLOADS=("uu" "uz")
#YCSB_WORKLOADS=("r" "s") # a 50r 50u
#YCSB_WORKLOADS=("s") # b 95r 5u
#YCSB_WORKLOADS=("t") # c 100r cleanup
#YCSB_WORKLOADS=("u" "uu" "uz") # d 95r 5i
YCSB_WORKLOADS=("w") # f 50r 50raw ?update
#NODE=("local" "remote" "interleave")

#YCSB_WORKLOADS=("u" ) # d 95r 5i
#YCSB_WORKLOADS=("r" "s" "t" "u" "uu" "uz" "w")
#YCSB_WORKLOADS=("r")
NODE=("interleave")

for node in ${NODE[@]}; do
    for workload in ${YCSB_WORKLOADS[@]}; do
        echo "sleep 1"
        sleep 1
        echo "${workload} ${node}" 
        #sudo ./run_redis.sh $workload $node 200000 output_workload_${workload}/output_${node}_max
        #sudo ./run_redis.sh $workload $node 200000 output_workload_${workload}/output_${node}_max_perf
        #sudo ./run_redis.sh $workload $node 200000 output_workload_${workload}/output_${node}_snc_d2_c1_max_perf

        #python3 process_output.py -i output_workload_${workload}/output_${node}_max_perf/ -o max_perf_${workload}_${node}.xlsx 
        #python3 process_output.py -i output_workload_${workload}/output_${node}_max/ -o max_${workload}_${node}.xlsx 
        #python3 process_output.py -i output_workload_${workload}/output_${node}_loop/ -o loop_${workload}_${node}.xlsx 
        python3 process_output.py -i output_workload_${workload}/output_${node}_snc_d2_c1_max_perf/ -o max_perf_${workload}_${node}_snc_d2_c1.xlsx 
    done
done
