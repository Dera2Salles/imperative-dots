#!/usr/bin/env bash

# CPU usage — difference in idle/total between two /proc/stat samples (100ms apart)
cpu_line1=$(grep '^cpu ' /proc/stat)
sleep 0.1
cpu_line2=$(grep '^cpu ' /proc/stat)

read -r _ u1 n1 s1 id1 io1 hi1 si1 _ <<< "$cpu_line1"
read -r _ u2 n2 s2 id2 io2 hi2 si2 _ <<< "$cpu_line2"

total1=$((u1 + n1 + s1 + id1 + io1 + hi1 + si1))
total2=$((u2 + n2 + s2 + id2 + io2 + hi2 + si2))
idle1=$id1
idle2=$id2

diff_total=$((total2 - total1))
diff_idle=$((idle2 - idle1))

if [ "$diff_total" -gt 0 ]; then
    cpu=$(( (diff_total - diff_idle) * 100 / diff_total ))
else
    cpu=0
fi

# RAM usage from /proc/meminfo
mem_total=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
mem_available=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
mem_used=$((mem_total - mem_available))

if [ "$mem_total" -gt 0 ]; then
    ram=$(( mem_used * 100 / mem_total ))
else
    ram=0
fi

jq -n -c \
    --argjson cpu "$cpu" \
    --argjson ram "$ram" \
    '{cpu: $cpu, ram: $ram}'
