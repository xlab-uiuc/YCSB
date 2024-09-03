import subprocess
import os
import re
import pandas as pd
import numpy as np
from scipy.stats import gmean
import argparse

def extract_number_after_iter(file_name):
    pattern = r'iter_(\d+)'
    # Search for the pattern in the text
    match = re.search(pattern, file_name)

    if match:
        iter_number = int(match.group(1))
        return iter_number
    else:
        return None

N_iters = 3
def distribute_grep_out_by_files(grep_out, n_iter_dict):
    lines = grep_out.strip().split('\n')
    # files = {}
    # for i in range(N_iters):
    #     files['iter' + str(i)] = ''
        
    for line in lines:
        file_name, number = line.split(':')
        iter_num = extract_number_after_iter(file_name)
        if iter_num != None:
            n_iter_dict['iter' + str(iter_num)] += line + '\n'
            
    return n_iter_dict

def get_n_iter_dict(folder):
    command = ['bash', '-c', 'ls {} | grep iter'.format(folder)]
    output = subprocess.check_output(command, stderr=subprocess.STDOUT, text=True)
    if output == '':
        throw("No iter files found")
    
    lines = output.strip().split('\n')
    files = {}
    
    for line in lines:
        iter_num = extract_number_after_iter(line)
        if iter_num != None:
            files['iter' + str(iter_num)] = ''
    return files
    
def process_grep_out(file_to_grep_out, process_func):
    results = []
    for file_name, grep_out in file_to_grep_out.items():
        results.append(process_func(grep_out))
    return results

def grep_and_get_numbers(folder, file_suffix, grep_pattern, process_func):
    try:
        command = ['bash', '-c', '"grep {} {}/*{} | sort'.format(grep_pattern, folder, file_suffix)]
        print(' '.join(command))
        output = subprocess.check_output(command, stderr=subprocess.STDOUT, text=True)
        # print(output)
        # numbers = extract_number_from_grep_out(output, line_process_func)
        if output == '':
            return None
        files = get_n_iter_dict(folder)
        file_to_grep_out = distribute_grep_out_by_files(output, n_iter_dict=files)
        # print(file_to_grep_out)
        numbers = process_grep_out(file_to_grep_out, process_func)
        # print(numbers)
        return numbers
    except subprocess.CalledProcessError as e:
        print("Error:", e)

def extract_trailing_float(line):
    # Define a regular expression pattern to match a trailing floating-point number
    pattern = r'(\d+(\.\d+)?)$'
    
    # Search for the pattern in the given line
    match = re.search(pattern, line)
    
    if match:
        # Return the matched trailing number
        return float(match.group(1)) if match.group(2) else int(match.group(1))
    else:
        return 0  # No match found

def extract_and_sum(grep_result):
    lines = grep_result.splitlines()

    total_cycles = 0
    for line in lines:
        cur_cycle = extract_trailing_float(line)
        if cur_cycle != None:
            total_cycles += cur_cycle
    return total_cycles

def extract_number_before_samples(line):
    pattern = r'(\d+(?:,\d+)*)\s+sample'
    match = re.search(pattern, line)

    if match:
        number_before_sample = match.group(1).replace(",", "")
        return int(number_before_sample)
    else:
        return None
    
def get_avg_latency(folder):
    pattern = '\"\\[READ\\], AverageLatency(us)\"'
    return grep_and_get_numbers(folder, 'txt', pattern, process_func=extract_trailing_float)

def get_99_9_percentile(folder):
    pattern = '\"\\[READ\\], 99.9PercentileLatency(us)\"'
    return grep_and_get_numbers(folder, 'Run*.txt', pattern, process_func=extract_trailing_float)

# def get_total_run_time(folder):
#     # search inside .svg files
#     pattern = '100.00%'
#     return grep_and_get_numbers(folder, '.svg', pattern, process_func=extract_number_before_samples)

# def get_PF_hanlder_time(folder):
#     # search inside .folded files
#     pattern = 'handle_mm_fault'
#     return grep_and_get_numbers(folder, '.folded', pattern, process_func=extract_and_sum)

# def get_task_numa_work_time(folder):
#     # search inside .folded files
#     pattern = 'task_numa_work'
#     return grep_and_get_numbers(folder, '.folded', pattern, process_func=extract_and_sum)

# def get_numa_migrate_prep_time(folder):
#     # search inside .folded files
#     pattern = 'numa_migrate_prep'
#     return grep_and_get_numbers(folder, '.folded', pattern, process_func=extract_and_sum)

base_dict = {
    "[OVERALL], Throughput(ops/sec)" : 0,
    "[READ], AverageLatency(us)" : 0,
    "[READ], 99thPercentileLatency(us)": 0,
    
}


def extract_latencies(file_path, dict_to_update):
    # print('parsing file:', file_path)

    with open(file_path, 'r') as file:
        for line in file:
            for key in dict_to_update.keys():
                if key in line:
                    dict_to_update[key] = float(line.split(',')[-1].strip())
                    



def get_file_list_from_folder(folder, trailing_key):
    print('folder: {}'.format(folder))
    command = ['bash', '-c', 'ls ' + folder + ' | grep {}'.format(trailing_key) ]
    print('command: {}'.format(' '.join(command)))
    try:
        # Run the grep command and capture the stdout and stderr
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        # Check if the command was successful
        if result.returncode == 0:
            # Return the stdout
            return result.stdout.decode('utf-8').splitlines()
        else:
            # If the command failed, you can optionally handle the error here
            print(f"Error occurred: {result.stderr}")
            return None
    except Exception as e:
        print(f"An error occurred: {e}")
        return None




def get_results(folder):
    print('get results for folder:', folder)
    
    file_list = get_file_list_from_folder(folder, 'Run*')
    print(file_list)
    
    dict_list = []
    for file in file_list:
        file_path = os.path.join(folder, file)
        file_dict = base_dict.copy()
        
        extract_latencies(file_path, file_dict)
        dict_list.append(file_dict)
    
    df = pd.DataFrame(dict_list)
    
    mean_row = df.mean(numeric_only=True)
    geo_mean_row = df.select_dtypes(include=[np.number]).apply(gmean)

    df = df.append(mean_row, ignore_index=True)
    df = df.append(geo_mean_row, ignore_index=True)
    
    df.index = file_list + ['mean', 'geomean']
    print(df)
    
    return df
    


folder_list = [
    'memcached_results-5.15.0-vanilla-THP_never-2024-08-28_10-39-02',
    'memcached_results-5.15.0-gen-x86-THP_never-2024-08-27_17-04-02',
    'memcached_results_c-5.15.0-vanilla-THP_never-2024-08-29_16-31-56'
]

if __name__ == "__main__":
    
    parser = argparse.ArgumentParser(description='An example script with arguments.')
    parser.add_argument('--folder', type=str, help='folder of dynamorio logs. selected with ls | grep _dyna.log | grep -v png')
    
    args = parser.parse_args()
    
    if args.folder:
        folder_list = [args.folder]
    
    csv_paths = []
    for folder in folder_list:
        df = get_results(folder)
        
        csv_path = os.path.join(folder, 'result.csv')
        df.to_csv(csv_path)
        csv_paths.append(csv_path)
        
    print('\n'.join(csv_paths))
        