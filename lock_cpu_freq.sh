sudo cpupower --cpu all frequency-set --freq 2000MHz
sudo sh -c 'echo 0 > /sys/devices/system/cpu/cpufreq/boost'

# Just for easy copy
# sudo cpupower --cpu all frequency-set --governor ondemand
