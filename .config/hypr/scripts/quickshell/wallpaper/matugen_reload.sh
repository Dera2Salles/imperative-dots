#!/usr/bin/env bash

# Reload Kitty instances
killall -USR1 .kitty-wrapped


# Reload CAVA
if pgrep -x "cava" > /dev/null; then
    # Rebuild the final config file from the base and newly generated colors
    cat ~/.config/cava/config_base ~/.config/cava/colors > ~/.config/cava/config 2>/dev/null
    # Tell CAVA to reload the config
    killall -USR1 cava
fi

# Reload SwayNC CSS styling dynamically without killing the daemon
if command -v swaync-client &> /dev/null; then
    swaync-client -rs
fi

# Putting swayosd reload into the background to not clutter the reloading process
if systemctl --user is-active --quiet swayosd.service; then
    systemctl --user restart swayosd.service &
fi

wait
