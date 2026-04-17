#!/usr/bin/env bash

# Ensure only one instance runs
pkill -f "cava -p /tmp/qs_cava_cfg" 2>/dev/null
sleep 0.2

CAVA_CONFIG="/tmp/qs_cava_cfg"

cat > "$CAVA_CONFIG" <<'EOF'
[general]
framerate = 25
bars = 12

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 100
EOF

# Output raw semicolon-separated numbers, one line per frame
# e.g.  42;7;88;13;55;91;30;66;17;73;48;22;
cava -p "$CAVA_CONFIG" | while IFS= read -r line; do
    echo "$line" > /tmp/qs_cava
done
