sudo sh -c "echo offline > /sys/devices/system/memory/auto_online_blocks"
sudo daxctl reconfigure-device --mode=system-ram dax0.0
