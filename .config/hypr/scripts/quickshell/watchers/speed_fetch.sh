#!/usr/bin/env bash

# File to store previous values
CACHE_FILE="/tmp/qs_net_speed"

# Get current RX/TX bytes
# We sum up all interfaces (rx is field 2, tx is field 10 in /proc/net/dev)
read -r current_rx current_tx <<< "$(awk 'NR > 2 { rx += $2; tx += $10 } END { print rx, tx }' /proc/net/dev)"

# Get current timestamp in nanoseconds
current_time=$(date +%s%N)

if [ -f "$CACHE_FILE" ]; then
    read -r last_rx last_tx last_time < "$CACHE_FILE"
    
    # Calculate difference
    # Handle overflow (though unlikely to happen in a short interval)
    diff_rx=$((current_rx - last_rx))
    diff_tx=$((current_tx - last_tx))
    diff_time=$((current_time - last_time)) # diff in nanoseconds
    
    # If time difference is very small (less than 100ms), we might get weird results
    if [ "$diff_time" -gt 100000000 ]; then
        # Speed in bytes per second
        # (diff * 1,000,000,000 / diff_time)
        rx_bps=$((diff_rx * 1000000000 / diff_time))
        tx_bps=$((diff_tx * 1000000000 / diff_time))
    else
        rx_bps=0
        tx_bps=0
    fi
else
    rx_bps=0
    tx_bps=0
fi

# Save current values for next run
echo "$current_rx $current_tx $current_time" > "$CACHE_FILE"

# Format function
format_speed() {
    local speed=$1
    if [ "$speed" -ge 1048576 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $speed/1048576}")M"
    elif [ "$speed" -ge 1024 ]; then
        echo "$(awk "BEGIN {printf \"%.1f\", $speed/1024}")K"
    else
        echo "${speed}"
    fi
}

rx_fmt=$(format_speed $rx_bps)
tx_fmt=$(format_speed $tx_bps)

jq -n -c \
    --arg rx "$rx_fmt" \
    --arg tx "$tx_fmt" \
    '{rx: $rx, tx: $tx}'
