#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e 

# Define the directory where this bash script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define the root of the dotfiles repository (parent of utils folder)
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$SCRIPT_DIR/config.json"

echo "==========================================="
echo "Starting Dotfile Conversion Process..."
echo "Using config: $CONFIG_FILE"
echo "==========================================="

# 1. Run the Hyprland/Hypridle configuration generator
if [ -f "$SCRIPT_DIR/auto-scripts/hyprcfg.py" ]; then
    echo "Running hyprcfg.py..."
    python3 "$SCRIPT_DIR/auto-scripts/hyprcfg.py" --config "$CONFIG_FILE"
else
    echo "Warning: hyprcfg.py not found in $SCRIPT_DIR/auto-scripts/"
fi

echo "-------------------------------------------"

# 2. Run the Scripts & Assets copier (Quickshell, bash scripts, etc.)
if [ -f "$SCRIPT_DIR/auto-scripts/scriptscfg.py" ]; then
    echo "Running scriptscfg.py..."
    python3 "$SCRIPT_DIR/auto-scripts/scriptscfg.py" --config "$CONFIG_FILE"
else
    echo "Warning: scriptscfg.py not found in $SCRIPT_DIR/auto-scripts/"
fi

echo "-------------------------------------------"

# 3. Run the Matugen configuration copier
if [ -f "$SCRIPT_DIR/auto-scripts/matugencfg.py" ]; then
    echo "Running matugencfg.py..."
    python3 "$SCRIPT_DIR/auto-scripts/matugencfg.py" --config "$CONFIG_FILE"
else
    echo "Warning: matugencfg.py not found in $SCRIPT_DIR/auto-scripts/"
fi

echo "-------------------------------------------"

# 4. Clean up personal files
ENV_FILE="$REPO_ROOT/.config/hypr/scripts/quickshell/calendar/.env"
if [ -f "$ENV_FILE" ]; then
    echo "Removing personal API key (.env) file..."
    rm -f "$ENV_FILE"
else
    echo "No personal .env file found to remove."
fi

echo "==========================================="
echo "All tasks completed successfully!"
