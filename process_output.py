import os


def generate_report():

    overall_dict = {}
    for filename in os.listdir("output"):
        if filename[:8] != "workload": continue
        filename_ = filename[:-4].split('_')
        workload = filename_[0][8]
        node = filename_[1]
        qps = filename_[2][3:]
        suffix = filename_[3]
        print(workload, node, qps, suffix)
        if not (workload, node, qps) in overall_dict.keys():
            overall_dict[(workload, node, qps)] = {}

        if suffix == "Run":
            with open(os.path.join("output", filename), 'r') as f:
                for line in f.readlines():
                    if "Throughput" in line:
                        ops_per_sec = float(line.split(',')[2].strip())
                        continue
                    words = line.split(',')
                    if words[0].strip() == "[READ]" and words[1].strip()[:4] == "99th":
                        read_tail_latency = words[2].strip()
                    elif words[0].strip() == "[UPDATE]" and words[1].strip()[:4] == "99th":
                        update_tail_latency = words[2].strip()
            overall_dict[(workload, node, qps)]["Run"] = (read_tail_latency, update_tail_latency, ops_per_sec)

        elif suffix == "redis":
            with open(os.path.join("output", filename), 'r') as f:
                redis_memory = f.readlines()[-1].strip()
                redis_memory = int(redis_memory) * 2**(-20)
            overall_dict[(workload, node, qps)]["redis"] = redis_memory

        elif suffix == "perf":
            perf_dict = {}
            with open(os.path.join("output", filename), 'r') as f:
                for line in f.readlines()[5:9]:
                    data = line.strip().split()
                    counter = int(data[0].strip().replace(',', ''))
                    percentage = data[-1].strip('(').strip(')')
                    perf_dict[data[1].strip()] = (counter, percentage)
            overall_dict[(workload, node, qps)]["perf"] = perf_dict

    if not os.path.exists("report"):
        os.mkdir("report")
    for file, data in overall_dict.items():
        with open(os.path.join("report", "workload{}_{}_qps{}.txt".format(file[0], file[1], file[2])), 'w') as f:
            f.write("Redis Mem Size: {:.2f}GB\n".format(data["redis"]))
            f.write("99th Tail Latency: [Read] {} [UPDATE] {}\n".format(data["Run"][0], data["Run"][1]))
            f.write("Ops/sec: {:.1f}\n".format(data["Run"][2]))
            for k in data["perf"].keys():
                f.write("{} {} {}\n".format(k, data["perf"][k][0], data["perf"][k][1]))
            f.write("LLC Load Miss Rate: {:.4f}\n".format(data["perf"]["LLC-load-misses"][0] / data["perf"]["LLC-loads"][0]))
            f.write("LLC Write Miss Rate: {:.4f}\n".format(data["perf"]["LLC-store-misses"][0] / data["perf"]["LLC-stores"][0]))

if __name__ == '__main__':
    generate_report()
