#!/usr/bin/env bash
PIPE="/tmp/qs_network_wait_$$.fifo"
mkfifo "$PIPE" 2>/dev/null
trap 'rm -f "$PIPE"; kill $(jobs -p) 2>/dev/null; exit 0' EXIT INT TERM

# Added "activat|deactivat" to catch ethernet connection profiles going up or down.
nmcli monitor 2>/dev/null | grep --line-buffered -iE "connect|disconnect|enable|disable|available|unavailable|activat|deactivat" > "$PIPE" &
read -r _ < "$PIPE"
