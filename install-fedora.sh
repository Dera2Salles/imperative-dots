#!/usr/bin/env bash

# ==============================================================================
# Script Versioning & Initialization
# ==============================================================================
DOTS_VERSION="1.5.0"
VERSION_FILE="$HOME/.local/state/imperative-dots-version"

# Prevent the TTY/Console from falling asleep (black screen) during long package builds
setterm -blank 0 -powerdown 0 2>/dev/null || true
printf '\033[9;0]' 2>/dev/null || true

# Global Variables & Initial States (Defaults)
WALLPAPER_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Wallpapers"
WEATHER_API_KEY=""
WEATHER_CITY_ID=""
WEATHER_UNIT=""
FAILED_PKGS=()

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
# Package Arrays
# ==============================================================================
# Fedora package mapping
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
    "wmctrl" "power-profiles-daemon" "easyeffects" "nautilus" "lsp-plugins-lv2"
    "qt5-qtwayland" "qt5-qtquickcontrols" "qt5-qtquickcontrols2" "qt5-qtgraphicaleffects" "qt6-qtwayland"
)

# Fedora Extra info (Ported from 1.2.1)
FEDORA_EXTRA_PKGS_INFO=(
    "wl-screenrec   : cargo install wl-screenrec   (enregistrement écran Wayland)"
    "awww            : Non disponible sur Fedora — installation de swww avec alias awww"
    "cliphist        : cargo install cliphist"
    "matugen         : cargo install matugen"
    "quickshell      : compilé depuis https://github.com/outfoxxed/quickshell"
    "satty           : cargo install satty"
    "swayosd         : COPR : dnf copr enable solopasha/hyprland puis dnf install swayosd"
    "networkmanager-dmenu : pip install networkmanager-dmenu (https://github.com/firecat53/networkmanager-dmenu)"
)

# ==============================================================================
# Early Distro Detection & TUI Dependency Bootstrap
# ==============================================================================
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${C_RED}Cannot detect OS. /etc/os-release not found.${RESET}"
    exit 1
fi

# Distro Check
case $OS in
    fedora|rhel|centos|almalinux|rocky)
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

        # 4. Assurer que cargo/rust est disponible
        if ! command -v cargo &> /dev/null; then
            echo -e "${C_CYAN}Installing Rust/Cargo (needed for extra packages)...${RESET}"
            sudo dnf install -y cargo rust > /dev/null 2>&1
        fi

        PKG_MANAGER="sudo dnf install -y"
        ;;
    *)
        echo -e "${C_RED}Unsupported OS ($OS). This script strictly supports Fedora/RHEL derivatives.${RESET}"
        exit 1
        ;;
esac

# Helper: check if a package is installed
is_pkg_installed() {
    local pkg="$1"
    rpm -q "$pkg" &>/dev/null
}

# ==============================================================================
# Hardware Information Gathering & Universal GPU Detection
# ==============================================================================
USER_NAME=$USER
OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
CPU_INFO=$(grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
GPU_RAW=$(lspci -nn | grep -iE 'vga|3d|display')
GPU_INFO=$(echo "$GPU_RAW" | cut -d: -f3 | sed -E 's/ \(rev [0-9a-f]+\)//g' | xargs)
[[ -z "$GPU_INFO" ]] && GPU_INFO="Unknown / Virtual Machine"

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
# Telemetry Function
# ==============================================================================
WORKER_URL="https://dots-telemetry.ilyamiro-work.workers.dev"

send_telemetry() {
    local mode=$1
    if [[ -n "$WORKER_URL" && "$WORKER_URL" != *"YOUR_USERNAME"* ]]; then
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

send_telemetry "init"

# ==============================================================================
# Interactive TUI Functions
# ==============================================================================

draw_header() {
    printf "\033[H"
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
    printf "\033[J"
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

        local current_driver="None"
        if command -v lsmod &> /dev/null; then
            if lsmod | grep -wq nvidia; then current_driver="nvidia";
            elif lsmod | grep -wq nouveau; then current_driver="nouveau";
            elif lsmod | grep -Ewq "amdgpu|radeon"; then current_driver="amd";
            elif lsmod | grep -Ewq "i915|xe"; then current_driver="intel"; fi
        fi

        local options=""
        case "$GPU_VENDOR" in
            "NVIDIA")
                if [[ "$current_driver" == "nouveau" ]]; then
                    options="1. Update/Keep Nouveau (Open Source)\n2. Skip Driver Installation"
                elif [[ "$current_driver" == "nvidia" ]]; then
                    options="1. Update/Keep Proprietary NVIDIA Drivers\n2. Skip Driver Installation"
                else
                    options="1. Install Proprietary NVIDIA Drivers (Recommended for Gaming/Wayland)\n2. Install Nouveau (Open Source, Better VM compat)\n3. Skip Driver Installation"
                fi ;;
            "AMD") options="1. Install AMD Mesa & Vulkan Drivers (RADV)\n2. Skip Driver Installation" ;;
            "INTEL") options="1. Install Intel Mesa & Vulkan Drivers (ANV)\n2. Skip Driver Installation" ;;
            *) options="1. Install Generic Mesa Drivers (For VMs / Software Rendering)\n2. Skip Driver Installation" ;;
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

        DRIVER_PKGS=()
        HAS_NVIDIA_PROPRIETARY=false

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
    local selected_codes=("us")
    local selected_names=("English (US)")

    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Keyboard Layout Configuration ===${RESET}\n"
        if [ ${#selected_codes[@]} -gt 0 ]; then
            echo -e "Currently added (US is mandatory): ${C_GREEN}$(IFS=', '; echo "${selected_names[*]}")${RESET}\n"
        fi
        local choice
        choice=$(printf "%s\n" "Done (Finish Selection)" "${available_layouts[@]}" | fzf \
            --layout=reverse \
            --border=rounded \
            --margin=1,2 \
            --height=20 \
            --prompt=" Add Layout > " \
            --pointer=">" \
            --header=" Select a language to add, or select Done ")
        if [[ -z "$choice" || "$choice" == *"Done"* ]]; then break; fi
        local code=$(echo "$choice" | awk '{print $1}')
        local name=$(echo "$choice" | cut -d'-' -f2- | sed 's/^ //')
        selected_codes+=("$code")
        selected_names+=("$name")
    done

    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== Keyboard Layout Configuration ===${RESET}\n"
        echo -e "Currently added: ${C_GREEN}$(IFS=', '; echo "${selected_names[*]}")${RESET}\n"
        echo -e "${C_CYAN}Choose a key combination to switch between layouts:${RESET}"
        local options="1. Alt + Shift (grp:alt_shift_toggle)\n2. Win + Space (grp:win_space_toggle)\n3. Caps Lock (grp:caps_toggle)\n4. Ctrl + Shift (grp:ctrl_shift_toggle)\n5. Ctrl + Alt (grp:ctrl_alt_toggle)\n6. Right Alt (grp:toggle)\n7. No Toggle (Single Layout)"
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
    clear; draw_header
    echo -e "${BOLD}${C_MAGENTA}=== System Overview & Keybinds ===${RESET}\n"
    print_kb() { printf "  ${C_CYAN}[${RESET} ${BOLD}%-17s${RESET} ${C_CYAN}]${RESET}  ${C_YELLOW}➜${RESET}  %s\n" "$1" "$2"; }
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
    print_kb "SUPER + SHIFT + S" "Toggle Stewart (RESERVED)"
    print_kb "SUPER + V" "Toggle Volume Control"
    echo ""
    echo -e "${BOLD}${C_BLUE}--- Window Management ---${RESET}"
    print_kb "ALT + F4" "Close Active Window / Widget"
    print_kb "SUPER + SHIFT + F" "Toggle Floating"
    print_kb "SUPER + Arrows" "Move Focus"
    echo ""
    echo -e "${BOLD}${C_BLUE}--- System Controls ---${RESET}"
    print_kb "SUPER + L" "Lock Screen"
    print_kb "Print Screen" "Screenshot"
    print_kb "SHIFT + Print" "Screenshot (Edit)"
    print_kb "ALT + SHIFT" "Switch Keyboard Layout"
    echo ""
    echo -e "${BOLD}${C_GREEN}Press ENTER to return to the Main Menu...${RESET}"
    read -r; VISITED_OVERVIEW=true
}

set_weather_api() {
    while true; do
        draw_header
        echo -e "${BOLD}${C_CYAN}=== OpenWeatherMap Interactive Setup ===${RESET}"
        ENV_FILE="$HOME/.config/hypr/scripts/quickshell/calendar/.env"
        if [ -f "$ENV_FILE" ] || [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
            echo -e "${C_GREEN}An existing Weather configuration (.env) was detected.${RESET}"
        fi
        read -p "Enter your OpenWeather API Key (or press Enter to skip/keep): " input_key
        if [[ -z "$input_key" ]]; then
            if [ -f "$ENV_FILE" ] || [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then
                KEEP_OLD_ENV=true; VISITED_WEATHER=true; break
            else
                read -r -p "Are you 100% sure you want to proceed without it? (y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then WEATHER_API_KEY="Skipped"; KEEP_OLD_ENV=false; VISITED_WEATHER=true; break; fi
                continue
            fi
        fi
        WEATHER_API_KEY=$(echo "$input_key" | tr -d ' ')
        read -p "Enter City ID: " input_id
        if [[ -z "$input_id" || ! "$input_id" =~ ^[0-9]+$ ]]; then echo -e "${C_RED}Invalid ID.${RESET}"; sleep 1; continue; fi
        WEATHER_CITY_ID="$input_id"
        unit_choice=$(echo -e "metric (Celsius)\nimperial (Fahrenheit)\nstandard (Kelvin)" | fzf --layout=reverse --border=rounded --height=12 --prompt=" Unit > ")
        WEATHER_UNIT=$(echo "$unit_choice" | awk '{print $1}')
        [[ -z "$WEATHER_UNIT" ]] && WEATHER_UNIT="metric"
        KEEP_OLD_ENV=false; VISITED_WEATHER=true; break
    done
}

manage_telemetry() {
    while true; do
        draw_header
        echo -e "Current Status: ${BOLD}$([ "$ENABLE_TELEMETRY" == true ] && echo -e "${C_GREEN}ON${RESET}" || echo -e "${DIM}OFF${RESET}")${RESET}\n"
        action=$(echo -e "1. Enable Telemetry\n2. Disable Telemetry\n3. Back to Main Menu" | fzf --layout=reverse --border=rounded --height=12 --prompt=" Telemetry > ")
        case "$action" in
            *"1"*) ENABLE_TELEMETRY=true; break ;;
            *"2"*) ENABLE_TELEMETRY=false; break ;;
            *"3"*) break ;;
            *) break ;;
        esac
    done
}

prompt_optional_features_menu() {
    DM_SERVICES=("gdm" "gdm3" "lightdm" "sddm" "lxdm" "lxdm-gtk3" "ly")
    CURRENT_DM=""
    for dm in "${DM_SERVICES[@]}"; do
        if systemctl is-enabled "$dm.service" &>/dev/null || systemctl is-active "$dm.service" &>/dev/null; then CURRENT_DM="$dm"; break; fi
    done
    local DM_LABEL="Display Manager Integration (SDDM)"
    if [[ "$CURRENT_DM" == "sddm" ]]; then DM_LABEL="Configure SDDM Theme (sddm detected)"; elif [[ -n "$CURRENT_DM" ]]; then DM_LABEL="Replace $CURRENT_DM with SDDM"; fi

    while true; do
        clear
        echo -e "${BOLD}${C_CYAN}=== Optional Component Setup ===${RESET}\n"
        local S_SDDM=$([ "$OPT_SDDM" = true ] && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}")
        local S_NVIM=$([ "$OPT_NVIM" = true ] && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}")
        local S_ZSH=$([ "$OPT_ZSH" = true ] && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}")
        local S_WP=$([ "$OPT_WALLPAPERS" = true ] && echo -e "${C_GREEN}[x]${RESET}" || echo -e "${DIM}[ ]${RESET}")
        local MENU_ITEMS="1. $S_SDDM $DM_LABEL\n2. $S_NVIM Neovim Matugen Configuration\n3. $S_ZSH Zsh Shell Setup\n4. $S_WP Download FULL Wallpaper Pack (Unchecked = 3 Random)\n5. ${BOLD}${C_GREEN}Proceed with Installation / Update${RESET}\n6. ${DIM}Back to Main Menu${RESET}"
        local choice=$(echo -e "$MENU_ITEMS" | fzf --ansi --layout=reverse --border=rounded --height=13 --prompt=" Options > ")
        case "$choice" in
            *"1."*) OPT_SDDM=$([ "$OPT_SDDM" = true ] && echo false || echo true) ;;
            *"2."*) OPT_NVIM=$([ "$OPT_NVIM" = true ] && echo false || echo true) ;;
            *"3."*) OPT_ZSH=$([ "$OPT_ZSH" = true ] && echo false || echo true) ;;
            *"4."*) OPT_WALLPAPERS=$([ "$OPT_WALLPAPERS" = true ] && echo false || echo true) ;;
            *"5."*)
                if [ "$OPT_SDDM" = true ]; then
                    if [[ -z "$CURRENT_DM" ]]; then INSTALL_SDDM=true; SETUP_SDDM_THEME=true; PKGS+=("sddm")
                    elif [[ "$CURRENT_DM" == "sddm" ]]; then SETUP_SDDM_THEME=true
                    else INSTALL_SDDM=true; REPLACE_DM=true; SETUP_SDDM_THEME=true; PKGS+=("sddm"); fi
                fi
                if [ "$OPT_NVIM" = true ]; then INSTALL_NVIM=true; PKGS+=("neovim" "lua-language-server" "unzip" "nodejs" "npm" "python3"); fi
                if [ "$OPT_ZSH" = true ]; then INSTALL_ZSH=true; PKGS+=("zsh"); fi
                return 0 ;;
            *"6."*) return 1 ;;
            *) ;;
        esac
    done
}

# ==============================================================================
# Main Menu Loop
# ==============================================================================
clear
while true; do
    draw_header
    S_PKG=$( [ "$VISITED_PKGS" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_OVW=$( [ "$VISITED_OVERVIEW" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_WTH=$( [ "$VISITED_WEATHER" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_DRV=$( [ "$VISITED_DRIVERS" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_YELLOW}[-]${RESET}" )
    S_KBD=$( [ "$VISITED_KEYBOARD" = true ] && echo -e "${C_GREEN}[✓]${RESET}" || echo -e "${C_RED}[ ]${RESET}" )
    S_TEL=$( [ "$ENABLE_TELEMETRY" = true ] && echo -e "${C_GREEN}[ON]${RESET}" || echo -e "${DIM}[OFF]${RESET}" )
    API_DISPLAY="Not Set"
    if [[ "$WEATHER_API_KEY" == "Skipped" ]]; then API_DISPLAY="Skipped"
    elif [[ -n "$WEATHER_API_KEY" ]]; then API_DISPLAY="Set ($WEATHER_UNIT)"
    elif [ -f "$HOME/.config/hypr/scripts/quickshell/calendar/.env" ]; then API_DISPLAY="Set (.env)"; fi
    INSTALL_LABEL=$([ "$LOCAL_VERSION" != "Not Installed" ] && echo "UPDATE" || echo "START")
    MENU_ITEMS="1. $S_PKG ${C_GREEN}Manage Packages${RESET} [${#PKGS[@]} queued]\n2. $S_OVW ${C_CYAN}Overview & Keybinds${RESET}\n3. $S_WTH ${C_YELLOW}Set Weather API Key${RESET} [${API_DISPLAY}]\n4. $S_DRV ${C_RED}[ DRIVERS ] Setup${RESET} [${DRIVER_CHOICE}]\n5. $S_KBD ${C_BLUE}Keyboard Layout Setup${RESET} [${KB_LAYOUTS_DISPLAY:-$KB_LAYOUTS}]\n6. $S_TEL ${C_CYAN}Telemetry Settings${RESET}\n7. ${BOLD}${C_MAGENTA}${INSTALL_LABEL}${RESET}\n8. ${DIM}Exit${RESET}"
    MENU_OPTION=$(echo -e "$MENU_ITEMS" | fzf --ansi --layout=reverse --border=rounded --height=17 --prompt=" Main Menu > ")
    case "$MENU_OPTION" in
        *"1."*) manage_packages ;;
        *"2."*) show_overview ;;
        *"3."*) set_weather_api ;;
        *"4."*) manage_drivers ;;
        *"5."*) manage_keyboard ;;
        *"6."*) manage_telemetry ;;
        *"7."*) if [ "$VISITED_KEYBOARD" = false ]; then echo -e "\n${C_RED}[!] Configure Keyboard first.${RESET}"; sleep 2; continue; fi
                if prompt_optional_features_menu; then break; else continue; fi ;;
        *"8."*) clear; exit 0 ;;
        *) exit 0 ;;
    esac
done

# ==============================================================================
# Installation Process
# ==============================================================================
clear; draw_header
echo -e "${BOLD}${C_BLUE}::${RESET} ${BOLD}Starting Installation Process...${RESET}\n"
send_telemetry "full"
sudo -v

# --- 0. Combine Base Packages ---
ALL_PKGS=("${PKGS[@]}" "${DRIVER_PKGS[@]}")
MISSING_PKGS=()
for pkg in "${ALL_PKGS[@]}"; do [[ -z "$pkg" ]] && continue; if ! is_pkg_installed "$pkg"; then MISSING_PKGS+=("$pkg"); fi; done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing System Packages...\n"
    for pkg in "${MISSING_PKGS[@]}"; do
        if $PKG_MANAGER "$pkg"; then echo -e "${C_GREEN}[ OK ] Successfully installed ${pkg}${RESET}"
        else echo -e "${C_RED}[ FAILED ] Failed to install ${pkg}${RESET}"; FAILED_PKGS+=("$pkg"); fi
    done
fi

# ==============================================================================
# --- Fedora Extra (Cargo / Compilation) ---
# ==============================================================================
echo -e "\n${C_CYAN}[ INFO ]${RESET} Installing Fedora-specific extra packages (Cargo / GitHub)...\n"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# cliphist, matugen, satty, wl-screenrec
for p in cliphist matugen satty wl-screenrec; do
    if ! command -v "$p" &>/dev/null; then cargo install "$p" || FAILED_PKGS+=("$p"); fi
done

# swayosd via DNF (COPR already enabled)
if ! command -v swayosd-server &>/dev/null; then sudo dnf install -y swayosd || FAILED_PKGS+=("swayosd"); fi

# awww fallback to swww
if ! command -v awww &>/dev/null && ! command -v swww &>/dev/null; then
    cargo install swww && { mkdir -p "$HOME/.local/bin"; ln -sf "$(command -v swww)" "$HOME/.local/bin/awww"; } || FAILED_PKGS+=("awww/swww")
fi

# quickshell (Compilation from source)
if ! command -v quickshell &>/dev/null; then
    sudo dnf install -y cmake extra-cmake-modules qt6-qtdeclarative-devel wayland-devel wayland-protocols-devel qt6-qtbase-devel qt6-qtwayland-devel pipewire-devel >/dev/null 2>&1
    QS_BUILD_DIR="/tmp/quickshell-build"
    rm -rf "$QS_BUILD_DIR"
    git clone --depth=1 --recurse-submodules https://github.com/outfoxxed/quickshell.git "$QS_BUILD_DIR" && (
        mkdir -p "$QS_BUILD_DIR/build"; cd "$QS_BUILD_DIR/build"
        cmake .. -DCMAKE_BUILD_TYPE=Release && make -j"$(nproc)" && sudo make install
    ) || FAILED_PKGS+=("quickshell")
    rm -rf "$QS_BUILD_DIR"
fi

# ==============================================================================
# --- 1.5. NVIDIA & DM Setup ---
# ==============================================================================
if [ "$HAS_NVIDIA_PROPRIETARY" = true ]; then
    echo -e "options nvidia-drm modeset=1 fbdev=1" | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null
    sudo dracut --force >/dev/null 2>&1
    sudo akmods --force >/dev/null 2>&1 || true
fi

if [[ "$REPLACE_DM" == true ]]; then
    DMS=("lightdm" "gdm" "gdm3" "lxdm" "lxdm-gtk3" "ly")
    for dm in "${DMS[@]}"; do if systemctl is-enabled "$dm.service" &>/dev/null; then sudo systemctl disable "$dm.service" 2>/dev/null; sudo dnf remove -y "$dm" > /dev/null 2>&1; fi; done
fi
if [[ "$INSTALL_SDDM" == true ]]; then sudo systemctl enable sddm.service -f; fi

# ==============================================================================
# --- 3. Repository & Wallpapers ---
# ==============================================================================
REPO_URL="https://github.com/ilyamiro/imperative-dots.git"; CLONE_DIR="$HOME/.hyprland-dots"
OLD_COMMIT="$LAST_COMMIT"; NEW_COMMIT=""
if [ -d "$CLONE_DIR" ]; then git -C "$CLONE_DIR" fetch --all > /dev/null; git -C "$CLONE_DIR" reset --hard @{u} > /dev/null; NEW_COMMIT=$(git -C "$CLONE_DIR" rev-parse HEAD 2>/dev/null)
else git clone "$REPO_URL" "$CLONE_DIR" > /dev/null; NEW_COMMIT=$(git -C "$CLONE_DIR" rev-parse HEAD 2>/dev/null); fi
REPO_DIR="$CLONE_DIR"

mkdir -p "$WALLPAPER_DIR"
if [ -z "$(ls -A "$WALLPAPER_DIR" 2>/dev/null | grep -E '\.(jpg|png|jpeg|gif|webp)$')" ]; then
    WP_REPO="https://github.com/ilyamiro/shell-wallpapers.git"; WP_CLONE="/tmp/shell-wallpapers"
    if [[ "$OPT_WALLPAPERS" == true ]]; then
        git clone --progress "$WP_REPO" "$WP_CLONE" 2>&1 | tr '\r' '\n' | while read -r line; do if [[ "$line" =~ Receiving\ objects:\ *([0-9]+)% ]]; then printf "\r\033[K Downloading: %3d%%" "${BASH_REMATCH[1]}"; fi; done
        cp -r "$WP_CLONE/images/"* "$WALLPAPER_DIR/" 2>/dev/null || cp -r "$WP_CLONE/"* "$WALLPAPER_DIR/" 2>/dev/null; rm -rf "$WP_CLONE"; echo ""
    else
        echo -e "Fetching 3 random wallpapers..."
        mkdir -p "$WP_CLONE"; ( cd "$WP_CLONE"; git init -q; git remote add origin "$WP_REPO"; git fetch --depth 1 --filter=blob:none origin HEAD -q
        for pic in $(git ls-tree -r origin/HEAD --name-only | grep -iE '\.(jpg|jpeg|png|gif|webp)$' | shuf -n 3); do git show origin/HEAD:"$pic" > "$WALLPAPER_DIR/$(basename "$pic")" 2>/dev/null; done )
        rm -rf "$WP_CLONE"
    fi
fi

# ==============================================================================
# --- 4. Copying Dotfiles & Adaptability ---
# ==============================================================================
TARGET_CONFIG_DIR="$HOME/.config"; BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d_%H%M%S)"
CONFIG_FOLDERS=("cava" "hypr" "kitty" "rofi" "matugen" "zsh" "swayosd")
[ "$INSTALL_NVIM" = true ] && CONFIG_FOLDERS+=("nvim")
mkdir -p "$TARGET_CONFIG_DIR" "$BACKUP_DIR"
SETTINGS_FILE="$TARGET_CONFIG_DIR/hypr/scripts/settings.json"

echo "  -> Applying Configurations..."
for folder in "${CONFIG_FOLDERS[@]}"; do
    if [ -d "$REPO_DIR/.config/$folder" ]; then [ -e "$TARGET_CONFIG_DIR/$folder" ] && mv "$TARGET_CONFIG_DIR/$folder" "$BACKUP_DIR/$folder"; cp -r "$REPO_DIR/.config/$folder" "$TARGET_CONFIG_DIR/$folder"; fi
done

# Restoring Weather Config
ENV_TARGET="$TARGET_CONFIG_DIR/hypr/scripts/quickshell/calendar"
if [[ "$KEEP_OLD_ENV" == true && -f "$BACKUP_DIR/hypr/scripts/quickshell/calendar/.env" ]]; then cp "$BACKUP_DIR/hypr/scripts/quickshell/calendar/.env" "$ENV_TARGET/.env"
elif [[ -n "$WEATHER_API_KEY" && "$WEATHER_API_KEY" != "Skipped" ]]; then mkdir -p "$ENV_TARGET"; echo -e "OPENWEATHER_KEY=${WEATHER_API_KEY}\nOPENWEATHER_CITY_ID=${WEATHER_CITY_ID}\nOPENWEATHER_UNIT=${WEATHER_UNIT}" > "$ENV_TARGET/.env"; chmod 600 "$ENV_TARGET/.env"; fi

# Cava Wrapper & Pipewire
mkdir -p "$HOME/.local/bin"; [ -f "$REPO_DIR/utils/bin/cava" ] && { cp "$REPO_DIR/utils/bin/cava" "$HOME/.local/bin/cava"; chmod +x "$HOME/.local/bin/cava"; }
systemctl --user enable --now pipewire wireplumber pipewire-pulse 2>/dev/null || true
sudo systemctl enable --now swayosd-libinput-backend.service 2>/dev/null || true

# Zsh Shell
if [ "$INSTALL_ZSH" = true ] && command -v zsh &>/dev/null; then
    [ -f "$HOME/.zshrc" ] && grep "^alias " "$HOME/.zshrc" > "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh"
    cp "$TARGET_CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc"; chsh -s $(which zsh) "$USER"
    [ -f "$TARGET_CONFIG_DIR/zsh/user_aliases.zsh" ] && echo "source $TARGET_CONFIG_DIR/zsh/user_aliases.zsh" >> "$HOME/.zshrc"
fi

# Fonts
TARGET_FONTS="$HOME/.local/share/fonts"; mkdir -p "$TARGET_FONTS"
cp -r "$REPO_DIR/.local/share/fonts/"* "$TARGET_FONTS/" 2>/dev/null || true
if [ ! -d "$TARGET_FONTS/IosevkaNerdFont" ]; then
    mkdir -p /tmp/iosevka-pack; curl -fLo /tmp/iosevka-pack/Iosevka.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Iosevka.zip
    unzip -q /tmp/iosevka-pack/Iosevka.zip -d /tmp/iosevka-pack/; mkdir -p "$TARGET_FONTS/IosevkaNerdFont"; mv /tmp/iosevka-pack/*.ttf "$TARGET_FONTS/IosevkaNerdFont/"
    sudo cp -r "$TARGET_FONTS/IosevkaNerdFont" /usr/share/fonts/ 2>/dev/null || true; rm -rf /tmp/iosevka-pack
fi
fc-cache -f "$TARGET_FONTS" > /dev/null 2>&1

# Final Adaptations
HYPR_CONF="$TARGET_CONFIG_DIR/hypr/hyprland.conf"
sed -i "s/^ *kb_layout =.*/    kb_layout = $KB_LAYOUTS/" "$HYPR_CONF"
sed -i "s/^ *kb_options =.*/    kb_options = $KB_OPTIONS/" "$HYPR_CONF"
sed -i '/^# === DOTFILES AUTO-INJECTED ENV ===/,/^# === END DOTFILES ENV ===/d' "$HYPR_CONF"
cat <<EOF >> "$HYPR_CONF"
# === DOTFILES AUTO-INJECTED ENV ===
env = WALLPAPER_DIR,$WALLPAPER_DIR
env = SCRIPT_DIR,$HOME/.config/hypr/scripts
$([ "$GPU_VENDOR" == "NVIDIA" ] && echo "env = LIBVA_DRIVER_NAME,nvidia\nenv = __GLX_VENDOR_LIBRARY_NAME,nvidia")
# === END DOTFILES ENV ===
EOF

# Settings JSON
cat <<EOF > "$SETTINGS_FILE"
{ "uiScale": 1.0, "openGuideAtStartup": true, "wallpaperDir": "$WALLPAPER_DIR", "language": "$KB_LAYOUTS", "kbOptions": "$KB_OPTIONS" }
EOF

# SDDM Theme
if [[ "$SETUP_SDDM_THEME" == true && -d "$REPO_DIR/.config/sddm/themes/matugen-minimal" ]]; then
    sudo mkdir -p /usr/share/sddm/themes/matugen-minimal; sudo cp -r "$REPO_DIR/.config/sddm/themes/matugen-minimal/"* /usr/share/sddm/themes/matugen-minimal/
    sudo mkdir -p /etc/sddm.conf.d; echo -e "[Theme]\nCurrent=matugen-minimal\n\n[General]\nDisplayServer=wayland" | sudo tee /etc/sddm.conf.d/10-wayland-matugen.conf > /dev/null
fi

# Version Marker
cat <<EOF > "$VERSION_FILE"
LOCAL_VERSION="$DOTS_VERSION"; LAST_COMMIT="$NEW_COMMIT"; WEATHER_API_KEY="$WEATHER_API_KEY"; DRIVER_CHOICE="$DRIVER_CHOICE"
KB_LAYOUTS="$KB_LAYOUTS"; KB_LAYOUTS_DISPLAY="$KB_LAYOUTS_DISPLAY"; KB_OPTIONS="$KB_OPTIONS"; TELEMETRY_ID="$TELEMETRY_ID"
EOF

echo -e "\n${BOLD}${C_GREEN}Installation/Update Complete!${RESET}"
if [ ${#FAILED_PKGS[@]} -ne 0 ]; then echo -e "${C_RED}Failed packages: ${FAILED_PKGS[*]}${RESET}"; fi
echo -e "Please log out and log back in to apply changes."
send_telemetry "done"
