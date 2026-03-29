#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# ==============================================================================
# Terminal UI Colors & Formatting
# ==============================================================================
RESET="\e[0m"
BOLD="\e[1m"
DIM="\e[2m"

# Colors
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_RED="\e[31m"
C_MAGENTA="\e[35m"

# Logging Functions
log_header() {
    printf "\n${BOLD}${C_MAGENTA}=== %s ===${RESET}\n\n" "$1"
}

log_info() {
    printf "${C_CYAN}[ INFO ]${RESET} %s\n" "$1"
}

log_success() {
    printf "${C_GREEN}[  OK  ]${RESET} %s\n" "$1"
}

log_warn() {
    printf "${C_YELLOW}[ WARN ]${RESET} %s\n" "$1"
}

log_error() {
    printf "${C_RED}[ ERR  ]${RESET} %s\n" "$1"
}

log_step() {
    printf "${BOLD}${C_BLUE}::${RESET} ${BOLD}%s${RESET}\n" "$1"
}

# ==============================================================================
# Setup Paths & Repository Logic
# ==============================================================================
REPO_URL="https://github.com/ilyamiro/imperative-dots.git"
CLONE_DIR="$HOME/.hyprland-dots"

TARGET_CONFIG_DIR="$HOME/.config"
TARGET_FONTS_DIR="$HOME/.local/share/fonts"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d_%H%M%S)"

# Arrays of items to process
CONFIG_FOLDERS=("cava" "hypr" "kitty" "nvim" "rofi" "swaync" "matugen")

# ==============================================================================
# Pre-flight Checks & Cloning
# ==============================================================================
clear
printf "${BOLD}${C_CYAN}"
cat << "EOF"
  _   _                  _                 _   ____        _       
 | | | |_   _ _ __  _ __| | __ _ _ __   __| | |  _ \  ___ | |_ ___ 
 | |_| | | | | '_ \| '__| |/ _` | '_ \ / _` | | | | |/ _ \| __/ __|
 |  _  | |_| | |_) | |  | | (_| | | | | (_| | | |_| | (_) | |_\__ \
 |_| |_|\__, | .__/|_|  |_|\__,_|_| |_|\__,_| |____/ \___/ \__|___/
        |___/|_|                                                   
EOF
printf "${RESET}\n"

log_header "Starting Installation"

log_step "Resolving repository files..."

# Detect if the script is running from a local clone or via curl
if [ -d "$(pwd)/.config" ] && [ -d "$(pwd)/.local" ]; then
    REPO_DIR="$(pwd)"
    log_success "Running from local directory at $REPO_DIR"
else
    log_info "Downloading repository..."
    if command -v git &> /dev/null; then
        if [ -d "$CLONE_DIR" ]; then
            log_warn "Directory $CLONE_DIR already exists. Pulling latest changes..."
            git -C "$CLONE_DIR" pull
        else
            git clone "$REPO_URL" "$CLONE_DIR"
            log_success "Cloned repository to $CLONE_DIR"
        fi
        REPO_DIR="$CLONE_DIR"
    else
        log_error "Git is not installed. Please install git and try again."
        exit 1
    fi
fi

log_step "Checking target directories..."
if [ ! -d "$TARGET_CONFIG_DIR" ]; then
    log_info "Creating $TARGET_CONFIG_DIR"
    mkdir -p "$TARGET_CONFIG_DIR"
fi

if [ ! -d "$TARGET_FONTS_DIR" ]; then
    log_info "Creating $TARGET_FONTS_DIR"
    mkdir -p "$TARGET_FONTS_DIR"
fi

# ==============================================================================
# Backup & Symlink Configurations
# ==============================================================================
log_header "Applying Configurations"

mkdir -p "$BACKUP_DIR"
log_info "Created backup directory at: ${DIM}$BACKUP_DIR${RESET}"

for folder in "${CONFIG_FOLDERS[@]}"; do
    TARGET_PATH="$TARGET_CONFIG_DIR/$folder"
    SOURCE_PATH="$REPO_DIR/.config/$folder"

    log_step "Processing $folder..."

    if [ ! -d "$SOURCE_PATH" ]; then
        log_warn "Folder $folder not found in repository. Skipping."
        continue
    fi

    if [ -e "$TARGET_PATH" ] || [ -L "$TARGET_PATH" ]; then
        log_info "Backing up existing $folder config..."
        mv "$TARGET_PATH" "$BACKUP_DIR/$folder"
    fi

    ln -s "$SOURCE_PATH" "$TARGET_PATH"
    log_success "Symlinked $folder -> $TARGET_CONFIG_DIR/$folder"
done

# ==============================================================================
# Install Fonts
# ==============================================================================
log_header "Installing Fonts"

REPO_FONTS_DIR="$REPO_DIR/.local/share/fonts"

if [ -d "$REPO_FONTS_DIR" ]; then
    log_step "Copying fonts..."
    cp -r "$REPO_FONTS_DIR/"* "$TARGET_FONTS_DIR/"
    log_success "Fonts copied to $TARGET_FONTS_DIR"

    log_step "Updating font cache..."
    if command -v fc-cache &> /dev/null; then
        fc-cache -f "$TARGET_FONTS_DIR"
        log_success "Font cache updated."
    else
        log_warn "fc-cache command not found. You may need to update your font cache manually."
    fi
else
    log_warn "No fonts directory found in repository. Skipping."
fi

# ==============================================================================
# Finalize
# ==============================================================================
log_header "Installation Complete!"

printf "${BOLD}Your old configurations were backed up to:${RESET}\n"
printf "${C_CYAN}$BACKUP_DIR${RESET}\n\n"

printf "Please log out and log back in, or restart Hyprland to apply all changes.\n\n"
