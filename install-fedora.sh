#!/usr/bin/env bash

# ==============================================================================
# Script Versioning & Initialization
# ==============================================================================
DOTS_VERSION="1.6.0"
VERSION_FILE="$HOME/.local/state/imperative-dots-version"

# ==============================================================================
# Terminal UI Colors & Formatting
# ==============================================================================
RESET="\e[0m"
BOLD="\e[1m"
DIM="\e[2m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_RED="\e[31m"
C_MAGENTA="\e[35m"

# ==============================================================================
# Early Distro Detection (Strictly isolated to prevent state bypasses)
# ==============================================================================
if [ -f /etc/os-release ]; then
    # Use awk to strictly extract the ID without sourcing the file.
    DETECTED_OS=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2}' /etc/os-release)
else
    echo -e "${C_RED}Cannot detect OS. /etc/os-release not found.${RESET}"
    exit 1
fi

case "$DETECTED_OS" in
    fedora|rhel|centos|almalinux|rocky)
        OS="$DETECTED_OS"
        ;;
    *)
        echo -e "${C_RED}Unsupported OS ($DETECTED_OS). This script strictly supports Fedora and RHEL derivatives.${RESET}"
        exit 1
        ;;
esac

# Prevent the TTY/Console from falling asleep (black screen) during long package builds
setterm -blank 0 -powerdown 0 2>/dev/null || true
printf '\033[9;0]' 2>/dev/null || true

# Global Variables & Initial States (Defaults)
USER_PICTURES_DIR=""

if [ -f "$HOME/.config/user-dirs.dirs" ]; then
    USER_PICTURES_DIR=$(grep '^XDG_PICTURES_DIR' "$HOME/.config/user-dirs.dirs" | cut -d= -f2 | tr -d '"' | sed "s|\$HOME|$HOME|g")
fi

if [[ -z "$USER_PICTURES_DIR" || "$USER_PICTURES_DIR" == "$HOME" ]]; then
    USER_PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null)"
fi

if [[ -z "$USER_PICTURES_DIR" || "$USER_PICTURES_DIR" == "$HOME" ]]; then
    USER_PICTURES_DIR="$HOME/Pictures"
fi

USER_PICTURES_DIR="${USER_PICTURES_DIR%/}"

USER_VIDEOS_DIR=""

if [ -f "$HOME/.config/user-dirs.dirs" ]; then
    USER_VIDEOS_DIR=$(grep '^XDG_VIDEOS_DIR' "$HOME/.config/user-dirs.dirs" | cut -d= -f2 | tr -d '"' | sed "s|\$HOME|$HOME|g")
fi

if [[ -z "$USER_VIDEOS_DIR" || "$USER_VIDEOS_DIR" == "$HOME" ]]; then
    USER_VIDEOS_DIR="$(xdg-user-dir VIDEOS 2>/dev/null)"
fi

if [[ -z "$USER_VIDEOS_DIR" || "$USER_VIDEOS_DIR" == "$HOME" ]]; then
    USER_VIDEOS_DIR="$HOME/Videos"
fi

USER_VIDEOS_DIR="${USER_VIDEOS_DIR%/}"

WALLPAPER_DIR="$USER_PICTURES_DIR/Wallpapers"
WEATHER_API_KEY=""
WEATHER_CITY_ID=""
WEATHER_UNIT=""
FAILED_PKGS=()

TARGET_BRANCH="master"

# Check if the --dev flag was passed
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dev) TARGET_BRANCH="dev"; shift ;;
        *) shift ;;
    esac
done

if [[ "$TARGET_BRANCH" == "dev" ]]; then
    echo -e "${C_YELLOW}[!] RUNNING IN DEVELOPMENT MODE (Branch: dev)${RESET}"
fi

# Optional Component States
OPT_SDDM=false
OPT_NVIM=false
OPT_ZSH=false
OPT_WALLPAPERS=false

INSTALL_NVIM=false
INSTALL_ZSH=false
INSTALL_SDDM=false
REPLACE_DM=false
SETUP_SDDM_THEME=false

DRIVER_CHOICE="None (Skipped)"
DRIVER_PKGS=()
HAS_NVIDIA_PROPRIETARY=false
LAST_COMMIT=""
KEEP_OLD_ENV=true # Default to preserving existing weather config

ENABLE_TELEMETRY=true # Default telemetry state to ON

# Submenu Completion Tracking
VISITED_PKGS=false
VISITED_OVERVIEW=false
VISITED_WEATHER=false
VISITED_DRIVERS=false
VISITED_KEYBOARD=false

# Keyboard State Defaults
KB_LAYOUTS="us"
KB_LAYOUTS_DISPLAY="English (US)"
KB_OPTIONS="grp:alt_shift_toggle"

mkdir -p "$(dirname "$VERSION_FILE")"

# Load previous choices if the file exists
if [ -f "$VERSION_FILE" ] && [ -s "$VERSION_FILE" ]; then
    source "$VERSION_FILE"
    if [ -n "$LOCAL_VERSION" ] && [ "$LOCAL_VERSION" != "Not Installed" ]; then
        [ -n "$KB_LAYOUTS" ] && VISITED_KEYBOARD=true
        [ -n "$WEATHER_API_KEY" ] && VISITED_WEATHER=true
        [[ "$DRIVER_CHOICE" != "None (Skipped)" && -n "$DRIVER_CHOICE" ]] && VISITED_DRIVERS=true
    fi
else
    LOCAL_VERSION="Not Installed"
fi

# Generate Telemetry ID
if [ -z "$TELEMETRY_ID" ]; then
    if command -v uuidgen &> /dev/null; then
        TELEMETRY_ID=$(uuidgen)
    else
        TELEMETRY_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
    fi
    echo "TELEMETRY_ID=\"$TELEMETRY_ID\"" >> "$VERSION_FILE"
fi

# ==============================================================================
# Package Arrays
# ==============================================================================
FEDORA_PKGS=(
    "hyprland" "hypridle" "weston" "kitty" "cava" "zbar" "rofi-wayland"
    "pavucontrol" "alsa-utils"
    "wl-clipboard" "fd-find" "qt6-qtmultimedia" "qt6-qt5compat" "ripgrep"
    "jq" "socat" "inotify-tools" "pamixer" "brightnessctl" "acpi" "iw"
    "bluez" "bluez-tools" "libnotify" "NetworkManager" "lm_sensors" "bc"
    "pipewire" "wireplumber" "pipewire-pulseaudio" "pipewire-alsa" "pipewire-jack-audio-connection-kit"
    "pulseaudio-libs" "python3"
    "ImageMagick" "wget" "file" "git" "psmisc"
    "ffmpeg" "fastfetch" "unzip" "python3-websockets" "qt6-qtwebsockets"
    "grim" "playerctl" "yq" "xdg-desktop-portal-gtk" "slurp" "mpv"
    "wmctrl" "power-profiles-daemon" "easyeffects" "nautilus" "lsp-plugins-lv2" "hyprpolkitagent"
    "qt5-qtwayland" "qt5-qtquickcontrols" "qt5-qtquickcontrols2" "qt5-qtgraphicaleffects" "qt6-qtwayland"
    "qt5ct" "qt6ct" "adw-gtk3-theme"
)

# Fedora Extra info (packages not available in standard repos)
FEDORA_EXTRA_PKGS_INFO=(
    "wl-screenrec        : cargo install wl-screenrec   (Wayland screen recorder)"
    "awww / swww         : cargo install swww  (aliased as awww via wrapper)"
    "cliphist            : cargo install cliphist"
    "matugen             : cargo install matugen"
    "quickshell          : build from https://github.com/outfoxxed/quickshell"
    "satty               : cargo install satty"
    "swayosd             : dnf copr enable solopasha/hyprland && dnf install swayosd"
    "networkmanager-dmenu: pip install networkmanager-dmenu (https://github.com/firecat53/networkmanager-dmenu)"
    "gpu-screen-recorder : flatpak install flathub com.dec05eba.gpu_screen_recorder"
)

# ==============================================================================
# Early Dependency Bootstrap
# ==============================================================================
PKGS=("${FEDORA_PKGS[@]}")
DISTRO_FAMILY="fedora"

# 1. Bootstrap TUI dependencies
if ! command -v fzf &> /dev/null || ! command -v lspci &> /dev/null || ! command -v jq &> /dev/null || ! command -v curl &> /dev/null; then
    echo -e "${C_CYAN}Bootstrapping TUI dependencies (fzf, pciutils, jq, curl)...${RESET}"
    sudo dnf install -y fzf pciutils jq curl > /dev/null 2>&1
fi

# 2. Enable RPM Fusion (Free + NonFree)
if ! rpm -q rpmfusion-free-release &>/dev/null; then
    echo -e "${C_CYAN}Enabling RPM Fusion Free repository...${RESET}"
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
        > /dev/null 2>&1
fi
if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    echo -e "${C_CYAN}Enabling RPM Fusion NonFree repository...${RESET}"
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm" \
        > /dev/null 2>&1
fi

# 3. Enable COPR hyprland repo
if ! dnf copr list --enabled 2>/dev/null | grep -q "solopasha/hyprland"; then
    echo -e "${C_CYAN}Enabling COPR solopasha/hyprland...${RESET}"
    sudo dnf copr enable -y solopasha/hyprland > /dev/null 2>&1
fi

# 4. Ensure Rust/Cargo is available (needed for extra packages)
if ! command -v cargo &> /dev/null; then
    echo -e "${C_CYAN}Installing Rust/Cargo (needed for extra packages)...${RESET}"
    sudo dnf install -y cargo rust > /dev/null 2>&1
fi

PKG_MANAGER="sudo dnf install -y"

# Helper: check if an RPM package is installed
is_pkg_installed() {
    rpm -q "$1" &>/dev/null
}

# ==============================================================================
# Hardware Information Gathering & Universal GPU Detection
# ==============================================================================
USER_NAME=$USER
OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
CPU_INFO=$(grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)

# Detect ALL GPUs (VGA, 3D, and Display controllers) instead of just the first one
GPU_RAW=$(lspci -nn | grep -iE 'vga|3d|display')

# Flatten multi-line output into a single string and strip revision info for a cleaner TUI
GPU_INFO=$(echo "$GPU_RAW" | cut -d: -f3 | sed -E 's/ \(rev [0-9a-f]+\)//g' | xargs)
[[ -z "$GPU_INFO" ]] && GPU_INFO="Unknown / Virtual Machine"

# Categorize GPU for the driver menu
GPU_VENDOR="Unknown / Generic VM"
if echo "$GPU_INFO" | grep -qi "nvidia"; then
    GPU_VENDOR="NVIDIA"
elif echo "$GPU_INFO" | grep -qi "amd\|radeon"; then
    GPU_VENDOR="AMD"
elif echo "$GPU_INFO" | grep -qi "intel"; then
    GPU_VENDOR="INTEL"
elif echo "$GPU_INFO" | grep -qi "vmware\|virtualbox\|qxl\|virtio\|bochs"; then
    GPU_VENDOR="VM"
fi

# ==============================================================================
# Sync State from Existing settings.json (Prevents drift on updates)
# ==============================================================================
EXISTING_SETTINGS="$HOME/.config/hypr/scripts/settings.json"
if [ -f "$EXISTING_SETTINGS" ] && command -v jq &>/dev/null; then
    _sj_lang=$(jq -r 'if has("language") then (.language // "") else "IGNORE_ME" end' "$EXISTING_SETTINGS" 2>/dev/null)
    _sj_kbopt=$(jq -r 'if has("kbOptions") then (.kbOptions // "") else "IGNORE_ME" end' "$EXISTING_SETTINGS" 2>/dev/null)
    _sj_wpdir=$(jq -r 'if has("wallpaperDir") then (.wallpaperDir // "") else "IGNORE_ME" end' "$EXISTING_SETTINGS" 2>/dev/null)

    if [[ "$_sj_lang" != "IGNORE_ME" ]]; then
        KB_LAYOUTS="$_sj_lang"
        if [ "$KB_LAYOUTS" != "$( (source "$VERSION_FILE" 2>/dev/null; echo "$KB_LAYOUTS") )" ] || [ -z "$KB_LAYOUTS_DISPLAY" ]; then
            KB_LAYOUTS_DISPLAY="$_sj_lang"
        fi
        VISITED_KEYBOARD=true
    fi

    if [[ "$_sj_kbopt" != "IGNORE_ME" ]]; then
        KB_OPTIONS="$_sj_kbopt"
    fi

    if [[ "$_sj_wpdir" != "IGNORE_ME" ]] && [[ -n "$_sj_wpdir" ]]; then
        _sj_wpdir="${_sj_wpdir%/}" # Strip trailing slash from JSON load
        WALLPAPER_DIR="$_sj_wpdir"
        USER_PICTURES_DIR="$(dirname "$_sj_wpdir")"
    fi
fi

# ==============================================================================
# Telemetry Function (Secure Serverless Method)
# ==============================================================================
WORKER_URL="https://dots-telemetry.ilyamiro-work.workers.dev"

send_telemetry() {
    local mode=$1
    if [[ -n "$WORKER_URL" && "$WORKER_URL" != *"YOUR_USERNAME"* ]]; then

        # Mode 1: Just opened the script (No PII/Hardware info)
        if [[ "$mode" == "init" ]]; then
            local payload=$(cat <<EOF
{
  "type": "init",
  "version": "${DOTS_VERSION}",
  "id": "${TELEMETRY_ID}"
}
EOF
)
            curl -X POST -H "Content-Type: application/json" -d "$payload" "$WORKER_URL" -s -o /dev/null &

        # Mode 2: Started Installation with Telemetry Enabled
        elif [[ "$mode" == "full" && "$ENABLE_TELEMETRY" == true ]]; then
            local ram=$(awk '/MemTotal/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "Unknown")
            local kernel=$(uname -r 2>/dev/null || echo "Unknown")
            local current_de=${XDG_CURRENT_DESKTOP:-"TTY / Unknown"}

            local payload=$(cat <<EOF
{
  "type": "full",
  "version": "${DOTS_VERSION}",
  "id": "${TELEMETRY_ID}",
  "os": "${OS_NAME//\"/\\\"}",
  "kernel": "${kernel//\"/\\\"}",
  "ram": "${ram//\"/\\\"}",
  "de": "${current_de//\"/\\\"}",
  "cpu": "${CPU_INFO//\"/\\\"}",
  "gpu": "${GPU_INFO//\"/\\\"}"
}
EOF
)
            curl -X POST -H "Content-Type: application/json" -d "$payload" "$WORKER_URL" -s -o /dev/null &

        # Mode 3: Installation Completed
        elif [[ "$mode" == "done" ]]; then
            local failed_str=""
            if [[ "$ENABLE_TELEMETRY" == true && ${#FAILED_PKGS[@]} -gt 0 ]]; then
                failed_str="${FAILED_PKGS[*]}"
            fi
            
            local payload=$(cat <<EOF
{
  "type": "done",
  "version": "${DOTS_VERSION}",
  "id": "${TELEMETRY_ID}",
  "telemetry_enabled": ${ENABLE_TELEMETRY},
  "failed_packages": "${failed_str//\"/\\\"}"
}
EOF
)
            curl -X POST -H "Content-Type: application/json" -d "$payload" "$WORKER_URL" -s -o /dev/null &
        fi
    fi
}

# Ping the worker instantly to show the script was executed (No hardware info sent here)
send_telemetry "init"

# ==============================================================================
# Interactive TUI Functions
# ==============================================================================

draw_header() {
    clear 
    printf "${BOLD}${C_CYAN}"
    cat << "EOF"
 ██╗██╗     ██╗   ██╗ █████╗ ███╗   ███╗██╗██████╗  ██████╗ 
 ██║██║     ╚██╗ ██╔╝██╔══██╗████╗ ████║██║██╔══██╗██╔═══██╗
 ██║██║      ╚████╔╝ ███████║██╔████╔██║██║██████╔╝██║   ██║
 ██║██║       ╚██╔╝  ██╔══██║██║╚██╔╝██║██║██╔══██╗██║   ██║
 ██║███████╗   ██║   ██║  ██║██║ ╚═╝ ██║██║██║  ██║╚██████╔╝
 ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═╝ ╚═════╝ 
EOF
    printf "${RESET}\n"

    # OSC 8 Escape Sequences for Clickable Hyperlinks
    local OSC8_GH="\e]8;;https://github.com/ilyamiro/imperative-dots.git\a"
    local OSC8_TW="\e]8;;https://twitter.com/ilyamirox\a"
    local OSC8_RD="\e]8;;https://reddit.com/r/ilyamiro1\a"
    local OSC8_KF="\e]8;;https://ko-fi.com/ilyamiro\a"
    local OSC8_END="\e]8;;\a"

    printf "\033[K${C_BLUE} -----------------------------------------------------------------${RESET}\n"
    printf "\033[K${BOLD}${C_GREEN} GitHub:${RESET}  ${OSC8_GH}https://github.com/ilyamiro/imperative-dots.git${OSC8_END}\n"
    printf "\033[K${BOLD}${C_CYAN} Twitter:${RESET} ${OSC8_TW}@ilyamirox${OSC8_END}  |  ${BOLD}${C_RED}Reddit:${RESET} ${OSC8_RD}r/ilyamiro1${OSC8_END}\n"
    printf "\033[K${BOLD}${C_MAGENTA} Donate:${RESET}  ${OSC8_KF}Donate on Ko-fi (Help the project!)${OSC8_END}\n"
    printf "\033[K${C_BLUE} -----------------------------------------------------------------${RESET}\n"
    printf "\033[K${BOLD} User:           ${RESET} %s\n" "$USER_NAME"
    printf "\033[K${BOLD} OS:             ${RESET} %s\n" "$OS_NAME"
    printf "\033[K${BOLD} CPU:            ${RESET} %s\n" "$CPU_INFO"
    printf "\033[K${BOLD} GPU:            ${RESET} %s\n" "$GPU_INFO"
    printf "\033[K${C_BLUE} -----------------------------------------------------------------${RESET}\n"
    printf "\033[K${BOLD} Server Version: ${RESET} %s\n" "$DOTS_VERSION"
    printf "\033[K${BOLD} Local Version:  ${RESET} %s\n" "$LOCAL_VERSION"
    printf "\033[K${C_BLUE} =================================================================${RESET}\n\n"
}

manage_packages() {
    while true; do
        draw_header
        local action
        action=$(echo -e "1. View Packages to be Installed\n2. Add Custom Packages\n3. Back to Main Menu" | fzf \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=15 \
            --prompt=" Package Manager > " \
            --pointer=">" \
            --header=" Use ARROW KEYS and ENTER ")

        case "$action" in
            *"1"*)
                echo "${PKGS[@]}" | tr ' ' '\n' | fzf \
                    --layout=reverse \
                    --border=rounded \
                    --margin=1,2 \
                    --height=25 \
                    --prompt=" Current Packages > " \
                    --pointer=">" \
                    --header=" Press ESC or ENTER to return to menu "
                ;;
            *"2"*)
                echo -e "${C_CYAN}Enter package names to add (separated by space) ${BOLD}[Leave empty and press ENTER to cancel]${RESET}${C_CYAN}:${RESET}"
                read -r new_pkgs
                if [ -n "$new_pkgs" ]; then
                    PKGS+=($new_pkgs)
                    echo -e "${C_GREEN}Packages added!${RESET}"
                    sleep 1
                fi
                ;;
            *"3"*) VISITED_PKGS=true; break ;;
            *) VISITED_PKGS=true; break ;;
        esac
    done
}

manage_drivers() {
    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Hardware Driver Configuration ===${RESET}"
        echo -e "${BOLD}${C_RED}=================== EXPERIMENTAL WARNING ===================${RESET}"
        echo -e "${C_RED}This automated driver installer is highly experimental and${RESET}"
        echo -e "${C_RED}can be unreliable across different kernel/distro variations.${RESET}"
        echo -e "${C_RED}It is strongly recommended to SKIP this and install your${RESET}"
        echo -e "${C_RED}graphics drivers manually according to your distro's wiki.${RESET}"
        echo -e "${BOLD}${C_RED}============================================================${RESET}\n"
        echo -e "Detected GPU Vendor: ${BOLD}${C_YELLOW}$GPU_VENDOR${RESET}\n"

        # Determine if a kernel driver is currently in use to prevent conflicts
        local current_driver="None"
        if command -v lsmod &> /dev/null; then
            if lsmod | grep -wq nvidia; then
                current_driver="nvidia"
            elif lsmod | grep -wq nouveau; then
                current_driver="nouveau"
            elif lsmod | grep -Ewq "amdgpu|radeon"; then
                current_driver="amd"
            elif lsmod | grep -Ewq "i915|xe"; then
                current_driver="intel"
            fi
        fi

        local options=""
        case "$GPU_VENDOR" in
            "NVIDIA")
                if [[ "$current_driver" == "nouveau" ]]; then
                    echo -e "${C_YELLOW}[!] Notice: Open-source 'nouveau' drivers are currently loaded.${RESET}"
                    echo -e "${C_RED}[!] Proprietary installation is locked out to prevent initramfs conflicts/black screens.${RESET}\n"
                    options="1. Update/Keep Nouveau (Open Source)\n2. Skip Driver Installation"
                elif [[ "$current_driver" == "nvidia" ]]; then
                    echo -e "${C_YELLOW}[!] Notice: Proprietary 'nvidia' drivers are currently loaded.${RESET}"
                    echo -e "${C_RED}[!] Open-source installation is locked out to prevent conflicts.${RESET}\n"
                    options="1. Update/Keep Proprietary NVIDIA Drivers\n2. Skip Driver Installation"
                else
                    options="1. Install Proprietary NVIDIA Drivers (Recommended for Gaming/Wayland)\n2. Install Nouveau (Open Source, Better VM compat)\n3. Skip Driver Installation"
                fi
                ;;
            "AMD")
                options="1. Install AMD Mesa & Vulkan Drivers (RADV)\n2. Skip Driver Installation"
                ;;
            "INTEL")
                options="1. Install Intel Mesa & Vulkan Drivers (ANV)\n2. Skip Driver Installation"
                ;;
            *)
                options="1. Install Generic Mesa Drivers (For VMs / Software Rendering)\n2. Skip Driver Installation"
                ;;
        esac

        local choice
        choice=$(echo -e "$options\nBack to Main Menu" | fzf \
            --ansi \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=15 \
            --prompt=" Drivers > " \
            --pointer=">" \
            --header=" Select the graphics drivers to install ")

        if [[ "$choice" == *"Back"* ]]; then break; fi

        # Require confirmation to INSTALL drivers, rather than skipping.
        if [[ "$choice" != *"Skip"* ]]; then
            echo -e "\n${BOLD}${C_RED}=================== ACTION REQUIRED ===================${RESET}"
            echo -e "${C_YELLOW}You have selected to AUTOMATICALLY install/configure drivers.${RESET}"
            echo -e "${C_YELLOW}If your system already has working drivers, this might break your boot sequence.${RESET}"
            echo -n -e "Are you ${BOLD}${C_RED}100% sure${RESET} you want to proceed with this driver installation? (y/n): "
            read -r confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "\n${C_RED}Driver setup aborted. Returning to menu...${RESET}"
                sleep 1.2
                continue
            fi
        fi

        # Strictly reset states before applying the verified configuration
        DRIVER_PKGS=()
        HAS_NVIDIA_PROPRIETARY=false

        # Fedora uses akmod-nvidia (RPM Fusion) instead of nvidia-dkms
        if [[ "$choice" == *"Proprietary NVIDIA"* ]]; then
            DRIVER_CHOICE="NVIDIA Proprietary"
            HAS_NVIDIA_PROPRIETARY=true
            DRIVER_PKGS+=("akmod-nvidia" "xorg-x11-drv-nvidia-cuda" "egl-wayland")

        elif [[ "$choice" == *"Nouveau"* ]]; then
            DRIVER_CHOICE="NVIDIA Nouveau"
            DRIVER_PKGS+=("mesa-dri-drivers" "vulkan-nouveau")

        elif [[ "$choice" == *"AMD"* ]]; then
            DRIVER_CHOICE="AMD Drivers"
            DRIVER_PKGS+=("mesa-dri-drivers" "mesa-vulkan-drivers" "xorg-x11-drv-amdgpu")

        elif [[ "$choice" == *"Intel"* ]]; then
            DRIVER_CHOICE="Intel Drivers"
            DRIVER_PKGS+=("mesa-dri-drivers" "mesa-vulkan-drivers" "intel-media-driver")

        elif [[ "$choice" == *"Generic"* ]]; then
            DRIVER_CHOICE="Generic / VM"
            DRIVER_PKGS+=("mesa-dri-drivers")

        elif [[ "$choice" == *"Skip"* ]]; then
            DRIVER_CHOICE="Skipped"
            DRIVER_PKGS=()
        fi

        echo -e "\n${C_GREEN}Driver configuration saved!${RESET}"
        sleep 1.2
        VISITED_DRIVERS=true
        break
    done
}

manage_keyboard() {
    local available_layouts=(
        "gb - English (UK)" "au - English (Australia)"
        "ca - English/French (Canada)" "ie - English (Ireland)"
        "nz - English (New Zealand)" "za - English (South Africa)"
        "fr - French" "be - Belgian" "ch - Swiss"
        "de - German" "at - Austrian" "nl - Dutch" "lu - Luxembourgish"
        "es - Spanish" "pt - Portuguese" "br - Portuguese (Brazil)"
        "it - Italian" "gr - Greek" "mt - Maltese"
        "se - Swedish" "no - Norwegian" "dk - Danish"
        "fi - Finnish" "is - Icelandic"
        "pl - Polish" "cz - Czech" "sk - Slovak" "hu - Hungarian"
        "ro - Romanian" "bg - Bulgarian" "ru - Russian" "ua - Ukrainian"
        "by - Belarusian" "rs - Serbian" "hr - Croatian" "si - Slovenian"
        "mk - Macedonian" "ba - Bosnian" "me - Montenegrin"
        "lt - Lithuanian" "lv - Latvian" "ee - Estonian"
        "am - Armenian" "ge - Georgian" "kz - Kazakh" "kg - Kyrgyz"
        "tj - Tajik" "tm - Turkmen" "uz - Uzbek" "mn - Mongolian"
        "il - Hebrew" "ara - Arabic" "ir - Persian (Farsi)"
        "iq - Iraqi" "sy - Syrian"
        "in - Indian" "pk - Pakistani" "bd - Bangla"
        "th - Thai" "vn - Vietnamese" "la - Lao"
        "mm - Burmese" "kh - Khmer"
        "cn - Chinese" "jp - Japanese" "kr - Korean" "tw - Taiwanese"
        "ng - Nigerian" "ma - Moroccan" "dz - Algerian" "et - Ethiopian"
        "latam - Spanish (Latin America)"
        "al - Albanian" "fo - Faroese"
    )
    
    local selected_codes=()
    local selected_names=()

    # Seed the interactive menu arrays with your globally saved layouts
    if [[ -n "$KB_LAYOUTS" ]]; then
        IFS=',' read -ra tmp_codes <<< "$KB_LAYOUTS"
        for code in "${tmp_codes[@]}"; do
            selected_codes+=("$(echo "$code" | xargs)")
        done
    else
        selected_codes=("us")
    fi

    if [[ -n "$KB_LAYOUTS_DISPLAY" ]]; then
        IFS=',' read -ra tmp_names <<< "$KB_LAYOUTS_DISPLAY"
        for name in "${tmp_names[@]}"; do
            selected_names+=("$(echo "$name" | xargs)")
        done
    else
        selected_names=("English (US)")
    fi

    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Keyboard Layout Configuration ===${RESET}\n"

        if [ ${#selected_codes[@]} -gt 0 ]; then
            echo -e "Currently added (US is mandatory): ${C_GREEN}$(IFS=', '; echo "${selected_names[*]}")${RESET}\n"
        fi

        local choice
        choice=$(printf "%s\n" "Done (Finish Selection)" "Reset (Clear All Except US)" "${available_layouts[@]}" | fzf \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=20 \
            --prompt=" Add Layout > " \
            --pointer=">" \
            --header=" Select a language to add, or select Done ")

        if [[ -z "$choice" || "$choice" == *"Done"* ]]; then
            break
        fi
        
        if [[ "$choice" == *"Reset"* ]]; then
            selected_codes=("us")
            selected_names=("English (US)")
            continue
        fi

        local code=$(echo "$choice" | awk '{print $1}')
        local name=$(echo "$choice" | cut -d'-' -f2- | sed 's/^ //')

        # Prevent adding duplicates
        local duplicate=false
        for existing in "${selected_codes[@]}"; do
            if [[ "$existing" == "$code" ]]; then
                duplicate=true
                break
            fi
        done

        if [ "$duplicate" = false ]; then
            selected_codes+=("$code")
            selected_names+=("$name")
        fi
    done

    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Keyboard Layout Configuration ===${RESET}\n"
        echo -e "Currently added: ${C_GREEN}$(IFS=', '; echo "${selected_names[*]}")${RESET}\n"
        echo -e "${C_CYAN}Choose a key combination to switch between layouts:${RESET}"

        local options="1. Alt + Shift (grp:alt_shift_toggle)\n"
        options+="2. Win + Space (grp:win_space_toggle)\n"
        options+="3. Caps Lock (grp:caps_toggle)\n"
        options+="4. Ctrl + Shift (grp:ctrl_shift_toggle)\n"
        options+="5. Ctrl + Alt (grp:ctrl_alt_toggle)\n"
        options+="6. Right Alt (grp:toggle)\n"
        options+="7. No Toggle (Single Layout)"

        local choice
        choice=$(echo -e "$options" | fzf \
            --ansi \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=15 \
            --prompt=" Toggle Keybind > " \
            --pointer=">" \
            --header=" Select layout switching method ")

        local kb_opt=""
        case "$choice" in
            *"1"*) kb_opt="grp:alt_shift_toggle" ;;
            *"2"*) kb_opt="grp:win_space_toggle" ;;
            *"3"*) kb_opt="grp:caps_toggle" ;;
            *"4"*) kb_opt="grp:ctrl_shift_toggle" ;;
            *"5"*) kb_opt="grp:ctrl_alt_toggle" ;;
            *"6"*) kb_opt="grp:toggle" ;;
            *"7"*) kb_opt="" ;;
            *) kb_opt="grp:alt_shift_toggle" ;;
        esac

        KB_LAYOUTS=$(IFS=','; echo "${selected_codes[*]}")
        KB_LAYOUTS_DISPLAY=$(IFS=', '; echo "${selected_names[*]}")
        KB_OPTIONS="$kb_opt"

        echo -e "\n${C_GREEN}Keyboard configured: Layouts = $KB_LAYOUTS_DISPLAY | Switch = ${KB_OPTIONS:-None}${RESET}"
        sleep 1.5
        VISITED_KEYBOARD=true
        break
    done
}

show_overview() {
    draw_header
    echo -e "${BOLD}${C_MAGENTA}=== System Overview & Keybinds ===${RESET}\n"
    echo -e "This configuration is an adaptation of the ${BOLD}${C_CYAN}ilyamiro/nixos-configuration${RESET} setup."
    echo -e "Here are the core keybindings to navigate your new system once installed:\n"

    print_kb() {
        printf "  ${C_CYAN}[${RESET} ${BOLD}%-17s${RESET} ${C_CYAN}]${RESET}  ${C_YELLOW}➜${RESET}  %s\n" "$1" "$2"
    }

    echo -e "${BOLD}${C_BLUE}--- Applications ---${RESET}"
    print_kb "SUPER + RETURN" "Open Terminal (kitty)"
    print_kb "SUPER + D" "Open App Launcher (rofi)"
    print_kb "SUPER + F" "Open Browser (Firefox)"
    print_kb "SUPER + E" "Open File Manager (nautilus)"
    print_kb "SUPER + C" "Clipboard History (rofi)"
    echo ""

    echo -e "${BOLD}${C_BLUE}--- Quickshell Widgets ---${RESET}"
    print_kb "SUPER + M" "Toggle Monitors"
    print_kb "SUPER + Q" "Toggle Music"
    print_kb "SUPER + B" "Toggle Battery"
    print_kb "SUPER + W" "Toggle Wallpaper"
    print_kb "SUPER + S" "Toggle Calendar"
    print_kb "SUPER + N" "Toggle Network"
    print_kb "SUPER + SHIFT + T" "Toggle FocusTime"
    print_kb "SUPER + SHIFT + S" "Toggle Stewart (RESERVED FOR FUTURE VOICE ASSISTANT)"
    print_kb "SUPER + V" "Toggle Volume Control"
    echo ""

    echo -e "${BOLD}${C_BLUE}--- Window Management ---${RESET}"
    print_kb "ALT + F4" "Close Active Window / Widget"
    print_kb "SUPER + SHIFT + F" "Toggle Floating"
    print_kb "SUPER + Arrows" "Move Focus"
    print_kb "SUPER + CTRL + Arr" "Move Window"
    echo ""

    echo -e "${BOLD}${C_BLUE}--- System Controls ---${RESET}"
    print_kb "SUPER + L" "Lock Screen"
    print_kb "Print Screen" "Screenshot"
    print_kb "SHIFT + Print" "Screenshot (Edit)"
    print_kb "ALT + SHIFT" "Switch Keyboard Layout"
    echo ""

    echo -e "${BOLD}${C_GREEN}Press ENTER to return to the Main Menu...${RESET}"
    read -r
    VISITED_OVERVIEW=true
}

set_weather_api() {
    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== OpenWeatherMap Interactive Setup ===${RESET}"

        ENV_FILE="$HOME/.config/hypr/scripts/quickshell/calendar/.env"

        if [ -f "$ENV_FILE" ] || [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
            echo -e "${C_GREEN}An existing Weather configuration (.env) was detected.${RESET}"
            echo -e "${BOLD}${C_YELLOW}Press ENTER without typing anything to KEEP your existing configuration.${RESET}\n"
        else
            echo -e "${BOLD}${C_YELLOW}Without this, weather widgets WILL NOT WORK.${RESET}\n"
            echo -e "${C_MAGENTA}How to get a free API key:${RESET}"
            echo -e "  1. Visit ${C_BLUE}https://openweathermap.org/${RESET}"
            echo -e "  2. Create a free account and log in."
            echo -e "  3. Click your profile name -> 'My API keys'."
            echo -e "  4. Generate a new key and paste it below."
            echo -e "  ${BOLD}${C_YELLOW}Note: New API keys may take a couple of hours to activate. This installer will NOT block you from using a fresh key.${RESET}\n"
        fi

        read -p "Enter your OpenWeather API Key (or press Enter to skip/keep): " input_key

        if [[ -z "$input_key" ]]; then
            if [ -f "$ENV_FILE" ] || [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
                echo -e "\n${C_GREEN}Keeping existing weather configuration.${RESET}"
                KEEP_OLD_ENV=true
                VISITED_WEATHER=true
                sleep 1.5
                break
            else
                echo -e "\n${C_RED}WARNING: You did not enter an API key.${RESET}"
                echo -n -e "Are you ${BOLD}${C_RED}100% sure${RESET} you want to proceed without it? (y/n): "
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    WEATHER_API_KEY="Skipped"
                    WEATHER_CITY_ID=""
                    WEATHER_UNIT=""
                    KEEP_OLD_ENV=false
                    VISITED_WEATHER=true
                    break
                fi
                continue
            fi
        fi

        input_key=$(echo "$input_key" | tr -d ' ')
        if [[ ${#input_key} -ne 32 ]]; then
            echo -e "\n${C_YELLOW}Warning: OpenWeather API keys are typically exactly 32 characters long.${RESET}"
            echo -e "${C_YELLOW}Your key is ${#input_key} characters long.${RESET}"
            echo -n "Are you sure this key is correct? (y/n): "
            read -r confirm_key
            if [[ ! "$confirm_key" =~ ^[Yy]$ ]]; then
                continue
            fi
        fi

        WEATHER_API_KEY="$input_key"

        echo -e "\n${C_CYAN}Let's set your location using your City ID.${RESET}"
        echo -e "1. Go to ${C_BLUE}https://openweathermap.org/${RESET} and search for your city."
        echo -e "2. Look at the URL in your browser. It will look something like this:"
        echo -e "   ${DIM}https://openweathermap.org/city/${RESET}${BOLD}2643743${RESET}"
        echo -e "3. Copy that number at the end (the City ID) and paste it below.\n"

        read -p "Enter City ID: " input_id

        if [[ -z "$input_id" || ! "$input_id" =~ ^[0-9]+$ ]]; then
            echo -e "${C_RED}Invalid City ID. It must be a number.${RESET}"
            sleep 1.5
            continue
        fi

        WEATHER_CITY_ID="$input_id"

        echo ""
        unit_choice=$(echo -e "metric (Celsius)\nimperial (Fahrenheit)\nstandard (Kelvin)" | fzf \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=12 \
            --prompt=" Select Temperature Unit > " \
            --pointer=">" \
            --header=" Choose your preferred unit format ")

        WEATHER_UNIT=$(echo "$unit_choice" | awk '{print $1}')
        [[ -z "$WEATHER_UNIT" ]] && WEATHER_UNIT="metric"

        KEEP_OLD_ENV=false
        echo -e "\n${C_GREEN}Weather configuration complete! Widget will update once your key is activated by OpenWeather.${RESET}"
        sleep 2.5
        VISITED_WEATHER=true
        break
    done
}

manage_telemetry() {
    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Telemetry Configuration ===${RESET}\n"
        echo -e "To help improve this dotfile environment, this script can send"
        echo -e "anonymous hardware statistics when you start the installation.\n"

        echo -e "${BOLD}What is sent if enabled:${RESET}"
        echo -e "  - Script Version (${DOTS_VERSION})"
        echo -e "  - OS Name (${OS_NAME})"
        echo -e "  - Kernel Version"
        echo -e "  - Total RAM"
        echo -e "  - Previous Desktop Environment"
        echo -e "  - CPU Model"
        echo -e "  - GPU Model\n"

        echo -e "${BOLD}${C_YELLOW}Absolutely NO personal data, IP addresses, or usernames are collected.${RESET}\n"

        local current_status="${DIM}OFF${RESET}"
        if [[ "$ENABLE_TELEMETRY" == true ]]; then
            current_status="${C_GREEN}ON${RESET}"
        fi

        echo -e "Current Status: ${BOLD}$current_status${RESET}\n"

        local action
        action=$(echo -e "1. Enable Telemetry\n2. Disable Telemetry\n3. Back to Main Menu" | fzf \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=12 \
            --prompt=" Telemetry > " \
            --pointer=">" \
            --header=" Use ARROW KEYS and ENTER ")

        case "$action" in
            *"1"*)
                ENABLE_TELEMETRY=true
                echo -e "${C_GREEN}Telemetry Enabled. Thank you!${RESET}"
                sleep 1
                break
                ;;
            *"2"*)
                if [[ "$ENABLE_TELEMETRY" == true ]]; then
                    echo -n -e "\nAre you sure you want to disable telemetry? (y/n)\n${DIM}This hardware info really helps me understand compatibility and fix bugs.${RESET} "
                    read -r confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        ENABLE_TELEMETRY=false
                        echo -e "${C_YELLOW}Telemetry Disabled.${RESET}"
                        sleep 1.2
                        break
                    fi
                else
                    break
                fi
                ;;
            *"3"*) break ;;
            *) break ;;
        esac
    done
}

prompt_optional_features_menu() {
    DM_SERVICES=("gdm" "gdm3" "lightdm" "sddm" "lxdm" "lxdm-gtk3" "ly")
    CURRENT_DM=""
    for dm in "${DM_SERVICES[@]}"; do
        if systemctl is-enabled "$dm.service" &>/dev/null || systemctl is-active "$dm.service" &>/dev/null; then
            CURRENT_DM="$dm"
            break
        fi
    done

    local DM_LABEL="Display Manager Integration (SDDM)"
    if [[ "$CURRENT_DM" == "sddm" ]]; then
        DM_LABEL="Configure SDDM Theme (sddm detected)"
    elif [[ -n "$CURRENT_DM" ]]; then
        DM_LABEL="Replace $CURRENT_DM with SDDM"
    fi

    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Optional Component Setup ===${RESET}\n"
        
        local S_SDDM=$( [ "$OPT_SDDM" = true ] && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}" )
        local S_NVIM=$( [ "$OPT_NVIM" = true ] && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}" )
        local S_ZSH=$( [ "$OPT_ZSH" = true ] && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}" )
        local S_WP=$( [ "$OPT_WALLPAPERS" = true ] && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}" )

        local MENU_ITEMS="1. $S_SDDM $DM_LABEL\n"
        MENU_ITEMS+="2. $S_NVIM Neovim Matugen Configuration\n"
        MENU_ITEMS+="3. $S_ZSH Zsh Shell Setup\n"
        MENU_ITEMS+="4. $S_WP Download FULL Wallpaper Pack (Unchecked = 3 Random)\n"
        MENU_ITEMS+="5. ${BOLD}${C_GREEN}Proceed with Installation / Update${RESET}\n"
        MENU_ITEMS+="6. ${DIM}Back to Main Menu${RESET}"

        local choice
        choice=$(echo -e "$MENU_ITEMS" | fzf \
            --ansi \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=13 \
            --prompt=" Options > " \
            --pointer=">" \
            --header=" SPACE or ENTER to toggle. Select Proceed when ready. ")

        case "$choice" in
            *"1."*) OPT_SDDM=$([ "$OPT_SDDM" = true ] && echo false || echo true) ;;
            *"2."*) OPT_NVIM=$([ "$OPT_NVIM" = true ] && echo false || echo true) ;;
            *"3."*) OPT_ZSH=$([ "$OPT_ZSH" = true ] && echo false || echo true) ;;
            *"4."*) OPT_WALLPAPERS=$([ "$OPT_WALLPAPERS" = true ] && echo false || echo true) ;;
            *"5."*) 
                if [ "$OPT_SDDM" = true ]; then
                    if [[ -z "$CURRENT_DM" ]]; then
                        INSTALL_SDDM=true
                        SETUP_SDDM_THEME=true
                        PKGS+=("sddm")
                    elif [[ "$CURRENT_DM" == "sddm" ]]; then
                        SETUP_SDDM_THEME=true
                    else
                        INSTALL_SDDM=true
                        REPLACE_DM=true
                        SETUP_SDDM_THEME=true
                        PKGS+=("sddm")
                    fi
                fi
                if [ "$OPT_NVIM" = true ]; then
                    INSTALL_NVIM=true
                    PKGS+=("neovim" "lua-language-server" "unzip" "nodejs" "npm" "python3")
                fi
                if [ "$OPT_ZSH" = true ]; then
                    INSTALL_ZSH=true
                    PKGS+=("zsh")
                fi
                return 0
                ;;
            *"6."*) return 1 ;;
            *) ;;
        esac
    done
}

# ==============================================================================
# Main Menu Loop
# ==============================================================================

while true; do
    draw_header

    S_PKG=$( [ "$VISITED_PKGS" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_OVW=$( [ "$VISITED_OVERVIEW" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_WTH=$( [ "$VISITED_WEATHER" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_DRV=$( [ "$VISITED_DRIVERS" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_KBD=$( [ "$VISITED_KEYBOARD" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_RED}[ ]${RESET}" )
    S_TEL=$( [ "$ENABLE_TELEMETRY" = true ] && echo -e "${C_GREEN}[ON]${RESET}" || echo -e "${DIM}[OFF]${RESET}" )

    if [[ -z "$WEATHER_API_KEY" ]]; then
        if [ -f "$HOME/.config/hypr/scripts/quickshell/calendar/.env" ]; then
            API_DISPLAY="Set (from .env file)"
        else
            API_DISPLAY="Not Set"
        fi
    elif [[ "$WEATHER_API_KEY" == "Skipped" ]]; then API_DISPLAY="Skipped"
    else API_DISPLAY="Set ($WEATHER_UNIT, ID: $WEATHER_CITY_ID)"; fi

    if [ "$LOCAL_VERSION" != "Not Installed" ] && [ -n "$LOCAL_VERSION" ]; then
        INSTALL_LABEL="UPDATE"
    else
        INSTALL_LABEL="START"
    fi

    MENU_ITEMS="1. $S_PKG ${C_GREEN}Manage Packages${RESET} [${#PKGS[@]} queued, Optional]\n"
    MENU_ITEMS+="2. $S_OVW ${C_CYAN}Overview & Keybinds${RESET} [Optional]\n"
    MENU_ITEMS+="3. $S_WTH ${C_YELLOW}Set Weather API Key${RESET} [${API_DISPLAY}, Optional]\n"
    MENU_ITEMS+="4. $S_DRV ${C_RED}[ DRIVERS ] Setup${RESET} [${DRIVER_CHOICE}, Optional]\n"
    MENU_ITEMS+="5. $S_KBD ${C_BLUE}Keyboard Layout Setup${RESET} [${KB_LAYOUTS_DISPLAY:-$KB_LAYOUTS}]\n"
    MENU_ITEMS+="6. $S_TEL ${C_CYAN}Telemetry Settings${RESET}\n"
    MENU_ITEMS+="7. ${BOLD}${C_MAGENTA}${INSTALL_LABEL}${RESET}\n"
    MENU_ITEMS+="8. ${DIM}Exit${RESET}"

    MENU_OPTION=$(echo -e "$MENU_ITEMS" | fzf \
        --ansi \
        --layout=reverse \
        --border=rounded \
        --margin=1,2 \
        --height=17 \
        --prompt=" Main Menu > " \
        --pointer=">" \
        --header=" Navigate with ARROWS. Select with ENTER. ")

    case "$MENU_OPTION" in
        *"1."*) manage_packages ;;
        *"2."*) show_overview ;;
        *"3."*) set_weather_api ;;
        *"4."*) manage_drivers ;;
        *"5."*) manage_keyboard ;;
        *"6."*) manage_telemetry ;;
        *"7."*) 
            if [ "$VISITED_KEYBOARD" = false ]; then
                echo -e "\n${C_RED}[!] You must configure your Keyboard Layouts in the submenu before starting.${RESET}"
                sleep 2.5
                continue
            fi
            if prompt_optional_features_menu; then
                break 
            else
                continue
            fi
            ;;
        *"8."*) clear; exit 0 ;;
        *) exit 0 ;;
    esac
done

# ==============================================================================
# Installation Process
# ==============================================================================
clear
draw_header
echo -e "${BOLD}${C_BLUE}::${RESET} ${BOLD}Starting Installation Process...${RESET}\n"

send_telemetry "full"

echo -e "${C_CYAN}[ INFO ]${RESET} Requesting sudo privileges for installation..."
sudo -v

# --- 0. Resolve Package Conflicts (Fedora/DNF) ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Resolving potential package conflicts..."

for jack_pkg in jack-audio-connection-kit jack2; do
    if rpm -q "$jack_pkg" &>/dev/null; then
        echo -e "  -> Removing conflicting package '$jack_pkg'..."
        sudo dnf remove -y "$jack_pkg" 2>/dev/null || true
    fi
done

sudo dnf install -y pipewire-jack-audio-connection-kit > /dev/null 2>&1 || true

CONFLICTING_PKGS=("swayosd" "quickshell" "matugen" "go-yq")
for cpkg in "${CONFLICTING_PKGS[@]}"; do
    if rpm -q "$cpkg" &>/dev/null; then
        echo -e "  -> ${C_YELLOW}Removing conflicting package '$cpkg'...${RESET}"
        systemctl --user stop "$cpkg" 2>/dev/null || true
        sudo systemctl stop "$cpkg" 2>/dev/null || true
        sudo dnf remove -y "$cpkg" > /dev/null 2>&1 || true
    fi
done

# Combine Base Packages with chosen Driver Packages
ALL_PKGS=("${PKGS[@]}" "${DRIVER_PKGS[@]}")
MISSING_PKGS=()

echo -e "\n${C_CYAN}[ INFO ]${RESET} Checking for already installed packages..."
for pkg in "${ALL_PKGS[@]}"; do
    [[ -z "$pkg" ]] && continue

    if rpm -q "$pkg" &>/dev/null; then
        true # Already installed, skip
    else
        MISSING_PKGS+=("$pkg")
    fi
done

# --- 1. Install Dependencies & Drivers ---
if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
    echo -e "  -> ${C_GREEN}All packages are already installed! Skipping package download phase.${RESET}\n"
else
    echo -e "  -> ${C_YELLOW}Found ${#MISSING_PKGS[@]} missing packages to install.${RESET}"
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing System Packages & Drivers...\n"

    for pkg in "${MISSING_PKGS[@]}"; do
        echo -e "\n${C_CYAN}=================================================================${RESET}"
        echo -e "${C_BLUE}::${RESET} ${BOLD}Installing ${pkg}...${RESET}"
        echo -e "${C_CYAN}=================================================================${RESET}"

        SAFE_JOBS=$(( $(nproc) / 2 ))
        [[ $SAFE_JOBS -lt 1 ]] && SAFE_JOBS=1
        [[ $SAFE_JOBS -gt 4 ]] && SAFE_JOBS=4

        if env CARGO_BUILD_JOBS="$SAFE_JOBS" MAKEFLAGS="-j$SAFE_JOBS" $PKG_MANAGER "$pkg"; then
            echo -e "\n${C_GREEN}[ OK ] Successfully installed ${pkg}${RESET}"
        else
            echo -e "\n${C_RED}[ FAILED ] Failed to install ${pkg}${RESET}"
            FAILED_PKGS+=("$pkg")
        fi
        sleep 0.5
    done
fi

# --- 1.5. Cargo-based extra packages (not in DNF repos) ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing Cargo-based extra packages..."

install_cargo_pkg() {
    local crate="$1"
    local bin_name="${2:-$1}"
    if ! command -v "$bin_name" &>/dev/null; then
        echo -e "  -> Installing ${crate} via cargo..."
        if env CARGO_BUILD_JOBS="$SAFE_JOBS" cargo install "$crate" 2>/dev/null; then
            printf "  -> %-30s ${C_GREEN}[ OK ]${RESET}\n" "$crate"
        else
            echo -e "  -> ${C_RED}[ FAILED ]${RESET} cargo install $crate"
            FAILED_PKGS+=("$crate (cargo)")
        fi
    else
        echo -e "  -> ${C_GREEN}$bin_name already installed. Skipping.${RESET}"
    fi
}

SAFE_JOBS=$(( $(nproc) / 2 ))
[[ $SAFE_JOBS -lt 1 ]] && SAFE_JOBS=1
[[ $SAFE_JOBS -gt 4 ]] && SAFE_JOBS=4

install_cargo_pkg "cliphist" "cliphist"
install_cargo_pkg "satty" "satty"
install_cargo_pkg "matugen" "matugen"

if ! command -v swww &>/dev/null; then
    echo -e "  -> Installing swww (used as awww) via cargo..."
    if cargo install swww 2>/dev/null; then
        printf "  -> %-30s ${C_GREEN}[ OK ]${RESET}\n" "swww"
    else
        echo -e "  -> ${C_RED}[ FAILED ]${RESET} cargo install swww"
        FAILED_PKGS+=("swww (cargo)")
    fi
fi

echo -e "\n${C_YELLOW}[ INFO ]${RESET} The following packages require manual installation on Fedora:"
for info in "${FEDORA_EXTRA_PKGS_INFO[@]}"; do
    echo -e "  ${DIM}${info}${RESET}"
done

# --- 1.6. Advanced Proprietary NVIDIA Setup (Fedora uses dracut + akmods) ---
if [ "$HAS_NVIDIA_PROPRIETARY" = true ]; then
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Performing Precise NVIDIA Initialization for Wayland..."

    echo -e "  -> Injecting kernel parameters via modprobe (nvidia-drm.modeset=1 nvidia-drm.fbdev=1)..."
    echo -e "options nvidia-drm modeset=1 fbdev=1" | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null

    echo -e "  -> Waiting for akmod-nvidia to build kernel module (this may take a few minutes)..."
    sudo akmods --force > /dev/null 2>&1 || true

    if command -v dracut &> /dev/null; then
        echo -e "  -> Rebuilding initramfs (dracut)..."
        sudo dracut --force > /dev/null 2>&1
        printf "  -> Dracut rebuild successful %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
fi

# --- 2. Display Manager Cleanup & SDDM Setup ---
if [[ "$INSTALL_SDDM" == true || "$SETUP_SDDM_THEME" == true || "$REPLACE_DM" == true ]]; then
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Configuring Display Manager..."
fi

if [[ "$REPLACE_DM" == true ]]; then
    DMS=("lightdm" "gdm" "gdm3" "lxdm" "lxdm-gtk3" "ly")
    for dm in "${DMS[@]}"; do
        if systemctl is-enabled "$dm.service" &>/dev/null || systemctl is-active "$dm.service" &>/dev/null; then
            echo "  -> Disabling conflicting Display Manager: $dm"
            sudo systemctl disable "$dm.service" 2>/dev/null || true
            sudo dnf remove -y "$dm" > /dev/null 2>&1 || true
        fi
    done
fi

if [[ "$INSTALL_SDDM" == true ]]; then
    sudo systemctl enable sddm.service -f
    printf "  -> SDDM enabled successfully %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# --- 3. Repository Cloning & Wallpapers ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Setting up Dotfiles Repository..."
REPO_URL="https://github.com/ilyamiro/imperative-dots.git"
CLONE_DIR="$HOME/.hyprland-dots"

OLD_COMMIT=""
NEW_COMMIT=""

if [ -f "$(pwd)/install.sh" ] && [ -d "$(pwd)/.config" ] && [ -d "$(pwd)/.git" ] && [ "$(pwd)" != "$CLONE_DIR" ] && [ "$(pwd)" != "$HOME" ]; then
    REPO_DIR="$(pwd)"
    echo "  -> Running from local development repository at $REPO_DIR"
    NEW_COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)
    OLD_COMMIT="$LAST_COMMIT"
else
    if [ -d "$CLONE_DIR" ]; then
        OLD_COMMIT="$LAST_COMMIT"
        git -C "$CLONE_DIR" fetch --all > /dev/null 2>&1
        git -C "$CLONE_DIR" checkout "$TARGET_BRANCH" > /dev/null 2>&1
        git -C "$CLONE_DIR" reset --hard "origin/$TARGET_BRANCH" > /dev/null 2>&1
        NEW_COMMIT=$(git -C "$CLONE_DIR" rev-parse HEAD 2>/dev/null)
    else
        OLD_COMMIT="$LAST_COMMIT"
        git clone -b "$TARGET_BRANCH" --progress "$REPO_URL" "$CLONE_DIR" 2>&1 | tr '\r' '\n' | while read -r line; do
            if [[ "$line" =~ Receiving\ objects:\ *([0-9]+)% ]]; then
                pc="${BASH_REMATCH[1]}"
                fill=$(printf "%*s" $((pc / 2)) "" | tr ' ' '#')
                empty=$(printf "%*s" $((50 - (pc / 2))) "" | tr ' ' '-')
                printf "\r\033[K  -> Downloading repo: [%s%s] %3d%%" "$fill" "$empty" "$pc"
            fi
        done
        echo ""
        NEW_COMMIT=$(git -C "$CLONE_DIR" rev-parse HEAD 2>/dev/null)
    fi
    REPO_DIR="$CLONE_DIR"
fi

echo -e "\n${C_CYAN}[ INFO ]${RESET} Fetching Wallpapers..."
mkdir -p "$WALLPAPER_DIR"

if [ "$(ls -A "$WALLPAPER_DIR" 2>/dev/null | grep -E '\.(jpg|png|jpeg|gif|webp)$')" ]; then
    echo -e "  -> ${C_GREEN}Wallpapers already present in $WALLPAPER_DIR. Skipping download.${RESET}"
else
    WALLPAPER_REPO="https://github.com/ilyamiro/shell-wallpapers.git"
    WALLPAPER_CLONE_DIR="/tmp/shell-wallpapers"

    if [ -d "$WALLPAPER_CLONE_DIR" ]; then
        rm -rf "$WALLPAPER_CLONE_DIR"
    fi

    if [[ "$OPT_WALLPAPERS" == true ]]; then
        git clone --progress "$WALLPAPER_REPO" "$WALLPAPER_CLONE_DIR" 2>&1 | tr '\r' '\n' | while read -r line; do
            if [[ "$line" =~ Receiving\ objects:\ *([0-9]+)% ]]; then
                pc="${BASH_REMATCH[1]}"
                fill=$(printf "%*s" $((pc / 2)) "" | tr ' ' '#')
                empty=$(printf "%*s" $((50 - (pc / 2))) "" | tr ' ' '-')
                printf "\r\033[K  -> Downloading: [%s%s] %3d%%" "$fill" "$empty" "$pc"
            fi
        done
        echo ""

        if [ -d "$WALLPAPER_CLONE_DIR/images" ]; then
            cp -r "$WALLPAPER_CLONE_DIR/images/"* "$WALLPAPER_DIR/" 2>/dev/null || true
        else
            cp -r "$WALLPAPER_CLONE_DIR/"* "$WALLPAPER_DIR/" 2>/dev/null || true
        fi
        rm -rf "$WALLPAPER_CLONE_DIR"
        printf "  -> Full wallpaper pack installed to %-12s ${C_GREEN}[ OK ]${RESET}\n" "$WALLPAPER_DIR"
    else
        echo -e "  -> ${C_CYAN}Fetching 3 random wallpapers to save time...${RESET}"
        mkdir -p "$WALLPAPER_CLONE_DIR"
        (
            cd "$WALLPAPER_CLONE_DIR" || exit
            git init -q
            git remote add origin "$WALLPAPER_REPO"
            git fetch --depth 1 --filter=blob:none origin HEAD -q
            RANDOM_PICS=$(git ls-tree -r origin/HEAD --name-only | grep -iE '\.(jpg|jpeg|png|gif|webp)$' | shuf -n 3)
            if [ -n "$RANDOM_PICS" ]; then
                for pic in $RANDOM_PICS; do
                    filename=$(basename "$pic")
                    echo -n "    -> Downloading $filename... "
                    git show origin/HEAD:"$pic" > "$WALLPAPER_DIR/$filename" 2>/dev/null
                    echo -e "${C_GREEN}[ DONE ]${RESET}"
                done
            else
                echo -e "    -> ${C_RED}Could not find any images in the repository.${RESET}"
            fi
        )
        rm -rf "$WALLPAPER_CLONE_DIR"
        printf "  -> Random wallpapers installed to %-12s ${C_GREEN}[ OK ]${RESET}\n" "$WALLPAPER_DIR"
    fi
fi

# --- 4. Copying Dotfiles & Backups ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Applying Configurations & Backing Up Old Ones..."
TARGET_CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d_%H%M%S)"

CONFIG_FOLDERS=("cava" "hypr" "kitty" "rofi" "matugen" "zsh" "swayosd")
if [ "$INSTALL_NVIM" = true ]; then CONFIG_FOLDERS+=("nvim"); fi

mkdir -p "$TARGET_CONFIG_DIR" "$BACKUP_DIR"

DO_FULL_INSTALL=true

if [ -z "$OLD_COMMIT" ]; then
    echo -e "  -> No previous commit tracked. Forcing a full overwrite."
    DO_FULL_INSTALL=true
elif [ -n "$OLD_COMMIT" ] && [ "$OLD_COMMIT" != "$NEW_COMMIT" ]; then
    DO_FULL_INSTALL=false
    if git -C "$REPO_DIR" cat-file -t "$OLD_COMMIT" >/dev/null 2>&1; then
        echo -e "  -> Found existing installation. Analyzing updates between ${C_YELLOW}${OLD_COMMIT::7}${RESET} and ${C_YELLOW}${NEW_COMMIT::7}${RESET}..."
    else
        echo -e "  -> Previous commit missing from local tree. Forcing a full overwrite."
        DO_FULL_INSTALL=true
    fi
elif [ "$OLD_COMMIT" == "$NEW_COMMIT" ] && [ -n "$OLD_COMMIT" ]; then
    DO_FULL_INSTALL=false
    echo -e "  -> Repository is up to date (${C_YELLOW}${NEW_COMMIT::7}${RESET}). Only applying upstream changes (None found)."
fi

SETTINGS_FILE="$TARGET_CONFIG_DIR/hypr/scripts/settings.json"

if [ "$DO_FULL_INSTALL" = true ]; then
    echo "  -> Performing Full Install / Overwrite..."
    
    # Pre-backup settings.json specifically to guarantee it survives the copy loop overwrites
    if [ -f "$SETTINGS_FILE" ]; then
        cp "$SETTINGS_FILE" "$BACKUP_DIR/settings.json.bak"
    fi

    for folder in "${CONFIG_FOLDERS[@]}"; do
        TARGET_PATH="$TARGET_CONFIG_DIR/$folder"
        SOURCE_PATH="$REPO_DIR/.config/$folder"

        if [ -d "$SOURCE_PATH" ]; then
            if [ -e "$TARGET_PATH" ] || [ -L "$TARGET_PATH" ]; then
                mv "$TARGET_PATH" "$BACKUP_DIR/$folder"
            fi
            cp -r "$SOURCE_PATH" "$TARGET_PATH"
            printf "  -> Copied %-31s ${C_GREEN}[ OK ]${RESET}\n" "$folder"
        fi
    done
    
    if [ -f "$BACKUP_DIR/settings.json.bak" ]; then
        mkdir -p "$(dirname "$SETTINGS_FILE")"
        cp "$BACKUP_DIR/settings.json.bak" "$SETTINGS_FILE"
        printf "  -> Restored existing settings.json  %-12s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
else
    # Partial Update Logic (Git Diff)
    CHANGED_FILES=""
    DELETED_FILES=""
    
    if [ "$OLD_COMMIT" != "$NEW_COMMIT" ]; then
        CHANGED_FILES=$(git -C "$REPO_DIR" diff --name-only --diff-filter=AM "$OLD_COMMIT" "$NEW_COMMIT" | grep "^\.config/")
        DELETED_FILES=$(git -C "$REPO_DIR" diff --name-only --diff-filter=D "$OLD_COMMIT" "$NEW_COMMIT" | grep "^\.config/")
    fi

    if [ -n "$CHANGED_FILES" ] || [ -n "$DELETED_FILES" ]; then
        echo -e "  -> Performing ${C_GREEN}Partial Update${RESET} based on upstream changes..."
        
        if [ -n "$DELETED_FILES" ]; then
            echo "$DELETED_FILES" | while IFS= read -r file; do
                FOLDER_NAME=$(echo "$file" | cut -d'/' -f2)
                
                valid_folder=false
                for f in "${CONFIG_FOLDERS[@]}"; do
                    if [ "$f" == "$FOLDER_NAME" ]; then
                        valid_folder=true
                        break
                    fi
                done

                if [ "$valid_folder" = true ]; then
                    TARGET_FILE="$HOME/$file"
                    REL_PATH="${file#\.config/}"
                    
                    if [ -f "$TARGET_FILE" ]; then
                        mkdir -p "$(dirname "$BACKUP_DIR/$REL_PATH")"
                        cp "$TARGET_FILE" "$BACKUP_DIR/$REL_PATH"
                        rm -f "$TARGET_FILE"
                        echo "    -> Removed obsolete file: $file"
                    fi
                fi
            done
        fi

        if [ -n "$CHANGED_FILES" ]; then
            echo "$CHANGED_FILES" | while IFS= read -r file; do
                FOLDER_NAME=$(echo "$file" | cut -d'/' -f2)

                valid_folder=false
                for f in "${CONFIG_FOLDERS[@]}"; do
                    if [ "$f" == "$FOLDER_NAME" ]; then
                        valid_folder=true
                        break
                    fi
                done

                if [ "$valid_folder" = true ]; then
                    SOURCE_FILE="$REPO_DIR/$file"
                    TARGET_FILE="$HOME/$file"
                    REL_PATH="${file#\.config/}"

                    if [[ "$file" == *"settings.json" ]]; then
                        echo "    -> Skipped (user-owned): $file"
                        continue
                    fi

                    if [ -f "$TARGET_FILE" ]; then
                        mkdir -p "$(dirname "$BACKUP_DIR/$REL_PATH")"
                        cp "$TARGET_FILE" "$BACKUP_DIR/$REL_PATH"
                    fi

                    mkdir -p "$(dirname "$TARGET_FILE")"
                    cp "$SOURCE_FILE" "$TARGET_FILE"
                    echo "    -> Updated: $file"
                fi
            done
        fi
        printf "  -> Partial update complete %-21s ${C_GREEN}[ OK ]${RESET}\n" ""
    else
        echo "  -> No target config files were changed upstream. Local files kept intact."
    fi
fi

# Weather Configuration persistence/handling
ENV_TARGET_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/calendar"
OLD_ENV_IN_BACKUP="$BACKUP_DIR/hypr/scripts/quickshell/calendar/.env"

if [[ "$KEEP_OLD_ENV" == true ]]; then
    if [ -f "$OLD_ENV_IN_BACKUP" ]; then
        mkdir -p "$ENV_TARGET_DIR"
        cp "$OLD_ENV_IN_BACKUP" "$ENV_TARGET_DIR/.env"
        printf "  -> Restored existing Weather API config from backup %-3s ${C_GREEN}[ OK ]${RESET}\n" ""
    elif [ -f "$ENV_TARGET_DIR/.env" ]; then
        printf "  -> Retained existing Weather API config %-13s ${C_GREEN}[ OK ]${RESET}\n" ""
    elif [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
        mkdir -p "$ENV_TARGET_DIR"
        cat <<EOF > "$ENV_TARGET_DIR/.env"
# OpenWeather API Configuration
OPENWEATHER_KEY=${WEATHER_API_KEY}
OPENWEATHER_CITY_ID=${WEATHER_CITY_ID}
OPENWEATHER_UNIT=${WEATHER_UNIT}
EOF
        chmod 600 "$ENV_TARGET_DIR/.env"
        printf "  -> Regenerated Weather API config from cache %-7s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
elif [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
    mkdir -p "$ENV_TARGET_DIR"
    cat <<EOF > "$ENV_TARGET_DIR/.env"
# OpenWeather API Configuration
OPENWEATHER_KEY=${WEATHER_API_KEY}
OPENWEATHER_CITY_ID=${WEATHER_CITY_ID}
OPENWEATHER_UNIT=${WEATHER_UNIT}
EOF
    chmod 600 "$ENV_TARGET_DIR/.env"
    printf "  -> Saved Weather API config to .env %-7s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# Deploy Cava Wrapper
mkdir -p "$HOME/.local/bin"
if [ -f "$REPO_DIR/utils/bin/cava" ]; then
    cp "$REPO_DIR/utils/bin/cava" "$HOME/.local/bin/cava"
    chmod +x "$HOME/.local/bin/cava"
    printf "  -> Deployed Cava wrapper %-17s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# Enable Pipewire natively for the user environment
sudo systemctl --global enable pipewire wireplumber pipewire-pulse 2>/dev/null || true
systemctl --user start pipewire wireplumber pipewire-pulse 2>/dev/null || true

# --- Enable SwayOSD libinput backend ---
sudo systemctl enable --now swayosd-libinput-backend.service 2>/dev/null || true
printf "  -> SwayOSD libinput backend enabled %-14s ${C_GREEN}[ OK ]${RESET}\n" ""

# --- Enable EasyEffects as a user service ---
mkdir -p "$HOME/.config/systemd/user"
cat <<EOF > "$HOME/.config/systemd/user/easyeffects.service"
[Unit]
Description=EasyEffects daemon
PartOf=graphical-session.target
After=graphical-session.target
After=pipewire.service
After=wireplumber.service

[Service]
ExecStart=/usr/bin/easyeffects --service-mode
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable easyeffects.service 2>/dev/null || true
printf "  -> EasyEffects daemon service enabled %-12s ${C_GREEN}[ OK ]${RESET}\n" ""

if [ "$INSTALL_ZSH" = true ] && command -v zsh &> /dev/null; then
    if [ -f "$HOME/.zshrc" ]; then
        echo -e "  -> Extracting existing aliases from ~/.zshrc..."
        mkdir -p "$TARGET_CONFIG_DIR/zsh"
        grep "^alias " "$HOME/.zshrc" > "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" || true
        if [ -s "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" ]; then
            printf "  -> Custom aliases backed up %-16s ${C_GREEN}[ OK ]${RESET}\n" ""
        else
            rm -f "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh"
        fi
    fi

    cp "$TARGET_CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc"
    chsh -s $(which zsh) "$USER"

    if [ -f "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" ]; then
        sed -i '/# Load User Aliases/d' "$HOME/.zshrc"
        sed -i "\|source $TARGET_CONFIG_DIR/zsh/user_aliases.zsh|d" "$HOME/.zshrc"
        echo -e "\n# Load User Aliases" >> "$HOME/.zshrc"
        echo "source $TARGET_CONFIG_DIR/zsh/user_aliases.zsh" >> "$HOME/.zshrc"
    fi

    printf "  -> Zsh set as default shell %-14s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# --- 5. Fonts ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing Fonts..."
TARGET_FONTS_DIR="$HOME/.local/share/fonts"
REPO_FONTS_DIR="$REPO_DIR/.local/share/fonts"
mkdir -p "$TARGET_FONTS_DIR"

if [ -d "$REPO_FONTS_DIR" ]; then
    cp -r "$REPO_FONTS_DIR/"* "$TARGET_FONTS_DIR/" 2>/dev/null || true
fi

if [ -d "$TARGET_FONTS_DIR/IosevkaNerdFont" ] && [ "$(ls -A "$TARGET_FONTS_DIR/IosevkaNerdFont" 2>/dev/null | grep -i "\.ttf")" ]; then
    echo -e "  -> ${C_GREEN}Iosevka Nerd Fonts already installed in $TARGET_FONTS_DIR. Skipping download.${RESET}"
else
    printf "  -> Creating temporary directory... \n"
    mkdir -p /tmp/iosevka-pack

    printf "  -> Downloading latest full Iosevka Nerd Font pack... \n"
    curl -fLo /tmp/iosevka-pack/Iosevka.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Iosevka.zip

    printf "  -> Extracting fonts... \n"
    unzip -q /tmp/iosevka-pack/Iosevka.zip -d /tmp/iosevka-pack/

    printf "  -> Installing fonts to IosevkaNerdFont directory... \n"
    mkdir -p "$TARGET_FONTS_DIR/IosevkaNerdFont"
    mv /tmp/iosevka-pack/*.ttf "$TARGET_FONTS_DIR/IosevkaNerdFont/"
    sudo cp -r "$TARGET_FONTS_DIR/IosevkaNerdFont" /usr/share/fonts/

    printf "  -> Cleaning up temporary files... \n"
    rm -rf /tmp/iosevka-pack
    rm -f "$TARGET_FONTS_DIR/IosevkaNerdFont/"*Mono*.ttf
fi

find "$TARGET_FONTS_DIR" -type f -exec chmod 644 {} \; 2>/dev/null
find "$TARGET_FONTS_DIR" -type d -exec chmod 755 {} \; 2>/dev/null

if command -v fc-cache &> /dev/null; then
    fc-cache -f "$TARGET_FONTS_DIR" > /dev/null 2>&1
    printf "  -> Font cache updated %-21s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# --- 6. Adaptability Phase & Theming ---
rm -f "$HOME/.cache/wallpaper_initialized"
echo -e "\n${C_CYAN}[ INFO ]${RESET} Adapting configurations to your specific system..."

HYPR_CONF="$TARGET_CONFIG_DIR/hypr/hyprland.conf"
ZSH_RC="$HOME/.zshrc"
WP_QML="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/wallpaper/WallpaperPicker.qml"

# -> Desktop/Laptop Battery Adaptability <-
QS_BAT_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/battery"
REPO_BAT_DIR="$REPO_DIR/.config/hypr/scripts/quickshell/battery"
echo -e "  -> Checking chassis for battery presence..."
if ls /sys/class/power_supply/BAT* 1> /dev/null 2>&1; then
    echo -e "  -> ${C_GREEN}Battery detected.${RESET} Keeping Laptop Battery widget."
    if [ -f "$REPO_BAT_DIR/BatteryPopup.qml" ]; then
        cp -f "$REPO_BAT_DIR/BatteryPopup.qml" "$QS_BAT_DIR/BatteryPopup.qml" 2>/dev/null || true
    fi
else
    echo -e "  -> ${C_YELLOW}No battery detected (Desktop system).${RESET} Swapping to System Monitor widget."
    if [ -f "$REPO_BAT_DIR/BatteryPopupAlt.qml" ]; then
        cp -f "$REPO_BAT_DIR/BatteryPopupAlt.qml" "$QS_BAT_DIR/BatteryPopup.qml" 2>/dev/null || true
    fi
fi

# -> Desktop/Ethernet Network Adaptability <-
QS_NET_DIR="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/network"
REPO_NET_DIR="$REPO_DIR/.config/hypr/scripts/quickshell/network"
echo -e "  -> Checking for Wi-Fi interface..."
if ls /sys/class/net/w* 1> /dev/null 2>&1 || iw dev 2>/dev/null | grep -q Interface; then
    echo -e "  -> ${C_GREEN}Wi-Fi module detected.${RESET} Keeping standard Network widget."
    if [ -f "$REPO_NET_DIR/NetworkPopup.qml" ]; then
        cp -f "$REPO_NET_DIR/NetworkPopup.qml" "$QS_NET_DIR/NetworkPopup.qml" 2>/dev/null || true
    fi
else
    echo -e "  -> ${C_YELLOW}No Wi-Fi module detected (Desktop/Ethernet).${RESET} Swapping to Alternate Network widget."
    if [ -f "$REPO_NET_DIR/NetworkPopupAlt.qml" ]; then
        cp -f "$REPO_NET_DIR/NetworkPopupAlt.qml" "$QS_NET_DIR/NetworkPopup.qml" 2>/dev/null || true
    fi
fi

if [ -f "$HYPR_CONF" ]; then

    # 0. Inject Keyboard Layout Configurations dynamically
    echo -e "  -> Applying Keyboard configuration to hyprland.conf..."
    sed -i -E "s/^[[:space:]]*kb_layout[[:space:]]*=.*/    kb_layout = $KB_LAYOUTS/" "$HYPR_CONF"
    
    if [ -n "$KB_OPTIONS" ]; then
        sed -i -E "s/^[[:space:]]*kb_options[[:space:]]*=.*/    kb_options = $KB_OPTIONS/" "$HYPR_CONF"
    else
        sed -i -E "s/^[[:space:]]*kb_options[[:space:]]*=.*/    kb_options = /" "$HYPR_CONF"
    fi

    # ========================================================================
    # BULLETPROOF HYPRLAND ENV INJECTION
    # ========================================================================
    echo -e "  -> Applying Environment Variables safely..."

    sed -i '/^# === DOTFILES AUTO-INJECTED ENV ===/,/^# === END DOTFILES ENV ===/d' "$HYPR_CONF"

    sed -i '/env = WALLPAPER_DIR/d' "$HYPR_CONF"
    sed -i '/env = SCRIPT_DIR/d' "$HYPR_CONF"
    sed -i '/env = QT_QPA_PLATFORMTHEME/d' "$HYPR_CONF"
    sed -i '/env = XDG_PICTURES_DIR/d' "$HYPR_CONF"
    sed -i '/env = XDG_VIDEOS_DIR/d' "$HYPR_CONF"

    cat <<EOF >> "$HYPR_CONF"

# === DOTFILES AUTO-INJECTED ENV ===
env = XDG_PICTURES_DIR,$USER_PICTURES_DIR
env = XDG_VIDEOS_DIR,$USER_VIDEOS_DIR
env = WALLPAPER_DIR,$WALLPAPER_DIR
env = SCRIPT_DIR,$HOME/.config/hypr/scripts
env = QT_QPA_PLATFORMTHEME,qt6ct
EOF

    if [ "$GPU_VENDOR" == "NVIDIA" ]; then
        echo -e "  -> Applying strict NVIDIA variables..."
        cat <<EOF >> "$HYPR_CONF"
env = ELECTRON_OZONE_PLATFORM_HINT,auto
env = WLR_DRM_DEVICES,/dev/dri/card0:/dev/dri/card1
env = __NV_PRIME_RENDER_OFFLOAD,1
env = __NV_PRIME_RENDER_OFFLOAD_PROVIDER,NVIDIA-G0
env = __GL_GSYNC_ALLOWED,0
env = __GL_VRR_ALLOWED,0
env = __GL_SHADER_DISK_CACHE,1
env = __GL_SHADER_DISK_CACHE_PATH,$HOME/.cache/nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = LIBVA_DRIVER_NAME,nvidia
env = QSG_RHI_BACKEND,vulkan
EOF
    fi

    echo "# === END DOTFILES ENV ===" >> "$HYPR_CONF"

    if ! grep -q "cursor {" "$HYPR_CONF"; then
        echo -e "  -> Restoring deleted cursor block..."
        cat <<EOF >> "$HYPR_CONF"

cursor {
    no_warps = true
}
EOF
    fi
    # ========================================================================
else
    echo -e "${C_RED}Warning: hyprland.conf not found at $HYPR_CONF${RESET}"
fi

# -> Sync settings.json: write only the fields the installer owns.
echo -e "  -> Syncing installer-owned fields to settings.json..."

# 1. Parse keybindings.conf dynamically into a JSON array
KEYBINDS_CONF="$TARGET_CONFIG_DIR/hypr/config/keybindings.conf"
KEYBINDS_JSON="[]"

if [ -f "$KEYBINDS_CONF" ]; then
    echo -e "  -> Parsing $KEYBINDS_CONF into settings.json..."
    KEYBINDS_JSON="["
    
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*#.*$ ]] && continue
        [[ -z "${line// }" ]] && continue
        [[ ! "$line" =~ ^[[:space:]]*bind ]] && continue

        bind_type="${line%%=*}"
        bind_type="${bind_type// /}"
        rest="${line#*=}"

        IFS=',' read -r mods key disp cmd <<< "$rest"

        mods=$(echo "$mods" | xargs)
        key=$(echo "$key" | xargs)
        disp=$(echo "$disp" | xargs)
        cmd=$(echo "$cmd" | xargs)

        obj=$(jq -n \
            --arg t "$bind_type" \
            --arg m "$mods" \
            --arg k "$key" \
            --arg d "$disp" \
            --arg c "$cmd" \
            '{type: $t, mods: $m, key: $k, dispatcher: $d, command: $c}')

        KEYBINDS_JSON="$KEYBINDS_JSON$obj,"
    done < "$KEYBINDS_CONF"

    if [ "$KEYBINDS_JSON" != "[" ]; then
        KEYBINDS_JSON="${KEYBINDS_JSON%,}]"
    else
        KEYBINDS_JSON="[]"
    fi
else
    echo -e "  -> \e[33mkeybindings.conf not found. Skipping keybind parsing.\e[0m"
fi

# 2. Inject the parsed array into settings.json
if [ -f "$SETTINGS_FILE" ]; then
    tmp_json=$(mktemp)
    jq --arg langs "$KB_LAYOUTS" \
       --arg wpdir "$WALLPAPER_DIR" \
       --arg kbopt "$KB_OPTIONS" \
       --argjson binds "$KEYBINDS_JSON" \
       '.language = $langs | .wallpaperDir = $wpdir | .kbOptions = $kbopt | .keybinds = $binds' \
       "$SETTINGS_FILE" > "$tmp_json" && mv "$tmp_json" "$SETTINGS_FILE"
    printf "  -> settings.json updated (user fields preserved) %-3s ${C_GREEN}[ OK ]${RESET}\n" ""
else
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    jq -n \
       --arg langs "$KB_LAYOUTS" \
       --arg wpdir "$WALLPAPER_DIR" \
       --arg kbopt "$KB_OPTIONS" \
       --argjson binds "$KEYBINDS_JSON" \
       '{
         uiScale: 1.0,
         openGuideAtStartup: true,
         topbarHelpIcon: true,
         wallpaperDir: $wpdir,
         language: $langs,
         kbOptions: $kbopt,
         keybinds: $binds
       }' > "$SETTINGS_FILE"
    printf "  -> settings.json created with defaults and parsed keybinds %-13s ${C_GREEN}[ OK ]${RESET}\n" ""
fi

# 4. Patch WallpaperPicker.qml dynamically
if [ -f "$WP_QML" ]; then
    sed -i 's/ \+--source-color-index 0//g' "$WP_QML"
    sed -i 's/matugen image "[^"]*"/& --source-color-index 0/g' "$WP_QML"
fi

if [ -d "$TARGET_CONFIG_DIR/hypr/scripts" ]; then
    find "$TARGET_CONFIG_DIR/hypr/scripts" -type f -exec sed -i -e 's/swww-daemon/awww-daemon/g' -e 's/swww/awww/g' {} +
fi

# Zsh Dynamism
if [ -f "$ZSH_RC" ]; then
    sed -i '/# Dynamic System Paths/d' "$ZSH_RC"
    sed -i '/export WALLPAPER_DIR=/d' "$ZSH_RC"
    sed -i '/export SCRIPT_DIR=/d' "$ZSH_RC"

    echo -e "\n# Dynamic System Paths" >> "$ZSH_RC"
    echo "export WALLPAPER_DIR=\"$WALLPAPER_DIR\"" >> "$ZSH_RC"
    echo "export SCRIPT_DIR=\"$HOME/.config/hypr/scripts\"" >> "$ZSH_RC"

    sed -i "s/OS_LOGO_PLACEHOLDER/${OS}_small/g" "$ZSH_RC"
fi

# --- 6.5 Config GTK and Qt Automated Setup ---
echo -e "\n${C_CYAN}[ INFO ]${RESET} Configuring GTK and Qt Theming Engines..."

gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' 2>/dev/null || true

mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"

echo '@import url("file://'"$HOME"'/.cache/matugen/colors-gtk.css");' > "$HOME/.config/gtk-3.0/gtk.css"
echo '@import url("file://'"$HOME"'/.cache/matugen/colors-gtk.css");' > "$HOME/.config/gtk-4.0/gtk.css"

cat <<EOF > "$HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=adw-gtk3-dark
EOF

cat <<EOF > "$HOME/.config/gtk-4.0/settings.ini"
[Settings]
gtk-application-prefer-dark-theme=1
EOF

mkdir -p "$HOME/.config/qt5ct/colors" "$HOME/.config/qt5ct/qss"
mkdir -p "$HOME/.config/qt6ct/colors" "$HOME/.config/qt6ct/qss"

cat <<EOF > "$HOME/.config/qt5ct/qt5ct.conf"
[Appearance]
color_scheme_path=$HOME/.config/qt5ct/colors/matugen.conf
custom_palette=true
standard_dialogs=default
style=Fusion
stylesheets=$HOME/.config/qt5ct/qss/matugen-style.qss

[Interface]
stylesheets=$HOME/.config/qt5ct/qss/matugen-style.qss
EOF

cat <<EOF > "$HOME/.config/qt6ct/qt6ct.conf"
[Appearance]
color_scheme_path=$HOME/.config/qt6ct/colors/matugen.conf
custom_palette=true
standard_dialogs=default
style=Fusion
stylesheets=$HOME/.config/qt6ct/qss/matugen-style.qss

[Interface]
stylesheets=$HOME/.config/qt6ct/qss/matugen-style.qss
EOF

printf "  -> Matugen GTK & Qt environment initialized %-4s ${C_GREEN}[ OK ]${RESET}\n" ""

echo -e "\n${C_CYAN}[ INFO ]${RESET} Enabling Core System Services..."
sudo systemctl enable NetworkManager.service
printf "  -> NetworkManager enabled %-20s ${C_GREEN}[ OK ]${RESET}\n" ""

# --- 7. Setup SDDM Theme and Config ---
if [[ "$SETUP_SDDM_THEME" == true ]]; then
    if [ -d "$REPO_DIR/.config/sddm/themes/matugen-minimal" ]; then
        sudo mkdir -p /usr/share/sddm/themes/matugen-minimal
        sudo cp -r "$REPO_DIR/.config/sddm/themes/matugen-minimal/"* /usr/share/sddm/themes/matugen-minimal/

        cat <<EOF | sudo tee /usr/share/sddm/themes/matugen-minimal/Colors.qml > /dev/null
pragma Singleton
import QtQuick
QtObject {
    readonly property color base: "#1e1e2e"
    readonly property color crust: "#11111b"
    readonly property color mantle: "#181825"
    readonly property color text: "#cdd6f4"
    readonly property color subtext0: "#a6adc8"
    readonly property color surface0: "#313244"
    readonly property color surface1: "#45475a"
    readonly property color surface2: "#585b70"
    readonly property color mauve: "#cba6f7"
    readonly property color red: "#f38ba8"
    readonly property color peach: "#fab387"
    readonly property color blue: "#89b4fa"
    readonly property color green: "#a6e3a1"
}
EOF
        sudo chown $USER:$USER /usr/share/sddm/themes/matugen-minimal/Colors.qml

        sudo mkdir -p /etc/sddm.conf.d
        cat <<EOF | sudo tee /etc/sddm.conf.d/10-wayland-matugen.conf > /dev/null
[Theme]
Current=matugen-minimal

[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_DISABLE_WINDOWDECORATION=1
EOF

        printf "  -> SDDM Theme configured %-17s ${C_GREEN}[ OK ]${RESET}\n" ""
    fi
fi

# --- 8. Finalize Version Marker & User State Persistence ---
cat <<EOF > "$VERSION_FILE"
LOCAL_VERSION="$DOTS_VERSION"
LAST_COMMIT="$NEW_COMMIT"
WEATHER_API_KEY="$WEATHER_API_KEY"
WEATHER_CITY_ID="$WEATHER_CITY_ID"
WEATHER_UNIT="$WEATHER_UNIT"
DRIVER_CHOICE="$DRIVER_CHOICE"
KB_LAYOUTS="$KB_LAYOUTS"
KB_LAYOUTS_DISPLAY="$KB_LAYOUTS_DISPLAY"
KB_OPTIONS="$KB_OPTIONS"
WALLPAPER_DIR="$WALLPAPER_DIR"
TELEMETRY_ID="$TELEMETRY_ID"
EOF
printf "  -> Configuration and version state saved %-7s ${C_GREEN}[ OK ]${RESET}\n" ""

# ==============================================================================
# Final Output
# ==============================================================================
echo -e "\n${BOLD}${C_GREEN}"
cat << "EOF"
 ___ _  _ ___ _____ _   _    _      _ _____ ___ ___  _  _    ___ ___  __  __ ___ _    ___ _____ ___ 
|_ _| \| / __|_   _/_\ | |  | |    /_\_   _|_ _/ _ \| \| |  / __/ _ \ | \/  | _ \ |  | __|_   _| __|
 | || .` \__ \ | |/ _ \| |__| |__ / _ \| |  | | (_) | .` | | (_| (_) | |\/| |  _/ |__| _|  | | | _| 
|___|_|\_|___/ |_/_/ \_\____|____/_/ \_\_| |___\___/|_|\_|  \___\___/|_|  |_|_| |____|___| |_| |___|
                                                                                                    
EOF
echo -e "${RESET}\n"

echo -e "${BOLD}${C_MAGENTA}=================================================================${RESET}"
echo -e "${BOLD}${C_YELLOW} Support the Creator:${RESET}"
echo -e " If you enjoy this project, consider buying me a coffee!"
echo -e " ${BOLD}${C_CYAN}Ko-fi:${RESET} https://ko-fi.com/ilyamiro"
echo -e "${BOLD}${C_MAGENTA}=================================================================${RESET}\n"

if [ ${#FAILED_PKGS[@]} -ne 0 ]; then
    echo -e "${BOLD}${C_RED}The following packages were NOT installed. Try building them yourself:${RESET}"
    for fp in "${FAILED_PKGS[@]}"; do
        echo -e "  - ${C_YELLOW}$fp${RESET}"
    done
    echo ""
fi

echo -e "Old configurations backed up to: ${C_CYAN}$BACKUP_DIR${RESET}"
echo -e "Please log out and log back in, or restart Hyprland to apply all changes."

# Send completion telemetry
send_telemetry "done"
