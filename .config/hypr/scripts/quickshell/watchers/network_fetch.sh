#!/usr/bin/env bash

get_wifi_radio() {
    LANG=C nmcli radio wifi 2>/dev/null
}

get_wifi_ssid() {
    local ssid=""
    if command -v iw &>/dev/null; then
        ssid=$(iw dev 2>/dev/null | awk '/\s+ssid/ { $1=""; sub(/^ /, ""); print; exit }')
    fi
    if [ -z "$ssid" ]; then
        ssid=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '/802-11-wireless/ {print $1; exit}')
    fi
    echo "${ssid:-}"
}

get_wifi_strength() {
    local signal=$(awk 'NR==3 {gsub(/\./,"",$3); print int($3 * 100 / 70)}' /proc/net/wireless 2>/dev/null)
    echo "${signal:-0}"
}

get_eth_status() {
    # Fix: Checking active connection profiles instead of devices.
    # This ignores virtual interfaces (Docker, bridges) and only returns "Connected" 
    # if a real ethernet profile is actively handling traffic.
    if nmcli -t -f TYPE con show --active 2>/dev/null | grep -qiE '802-3-ethernet|ethernet'; then
        echo "Connected"
    else
        echo "Disconnected"
    fi
}

get_wifi_data() {
    local radio=$(get_wifi_radio)
    local icon=""
    local ssid=""
    local status=""

    if [ "$radio" = "disabled" ]; then
        status="disabled"
        icon="󰤮"
        ssid=""
    else
        status="enabled"
        ssid=$(get_wifi_ssid)
        
        if [ -n "$ssid" ]; then
            local signal=$(get_wifi_strength)
            if [ "$signal" -ge 75 ]; then icon="󰤨"
            elif [ "$signal" -ge 50 ]; then icon="󰤥"
            elif [ "$signal" -ge 25 ]; then icon="󰤢"
            else icon="󰤟"; fi
        else
            icon="󰤯"
            ssid=""
        fi
    fi

    echo "$status|$ssid|$icon"
}

toggle_wifi() {
    if [ "$(get_wifi_radio)" = "enabled" ]; then
        nmcli radio wifi off
        notify-send -u low -i network-wireless-disabled "WiFi" "Disabled"
    else
        nmcli radio wifi on
        notify-send -u low -i network-wireless-enabled "WiFi" "Enabled"
    fi
}

case $1 in
    --toggle) toggle_wifi ;;
    *) 
        IFS='|' read -r status ssid icon <<< "$(get_wifi_data)"
        eth=$(get_eth_status)
        
        jq -n -c \
            --arg status "$status" \
            --arg ssid "$ssid" \
            --arg icon "$icon" \
            --arg eth "$eth" \
            '{status: $status, ssid: $ssid, icon: $icon, eth_status: $eth}' ;;
esac
