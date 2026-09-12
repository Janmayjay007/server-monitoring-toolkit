#!/usr/bin/env bash

# ==============================================================================
# Server Monitoring Toolkit
# An interactive, lightweight system health & diagnostics CLI for servers.
# Supports: Linux (systemd/SysV) and macOS
# Compatible: Bash 3.2+
# ==============================================================================

# Default configurations
DISK_THRESHOLD="${DISK_THRESHOLD:-85}"
MEM_THRESHOLD="${MEM_THRESHOLD:-85}"
DEFAULT_SERVICES=("nginx" "ssh" "sshd" "cron" "crond" "docker")
VERSION="2.0.0"

# ANSI Color Palette
if [ -t 1 ]; then
    BOLD="\033[1m"
    DIM="\033[2m"
    GREEN="\033[0;32m"
    RED="\033[0;31m"
    YELLOW="\033[1;33m"
    CYAN="\033[0;36m"
    BLUE="\033[0;34m"
    MAGENTA="\033[0;35m"
    NC="\033[0m" # No Color
else
    BOLD=""
    DIM=""
    GREEN=""
    RED=""
    YELLOW=""
    CYAN=""
    BLUE=""
    MAGENTA=""
    NC=""
fi

# ------------------------------------------------------------------------------
# UI & Helper Functions
# ------------------------------------------------------------------------------

print_banner() {
    local host_name
    host_name=$(hostname 2>/dev/null || echo "localhost")
    local current_time
    current_time=$(date "+%Y-%m-%d %H:%M:%S")

    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
  ___ ___ _____   _____ ___   __  __  ___  _  _ ___ _____ ___  ___ 
 / __| __| _ \ \ / / __| _ \ |  \/  |/ _ \| \| |_ _|_   _/ _ \| _ \
 \__ \ _||   /\ V /| _||   / | |\/| | (_) | .` || |  | || (_) |   /
 |___/___|_|_\ \_/ |___|_|_\ |_|  |_|\___/|_|\_|___| |_| \___/|_|_\
EOF
    echo -e "${NC}"
    echo -e "${BOLD} Server Monitoring Toolkit ${NC}${DIM}v${VERSION}${NC}"
    echo -e " ${DIM}Host:${NC} ${BOLD}${host_name}${NC}  ${DIM}•  Time:${NC} ${current_time}"
    echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"
}

print_header() {
    local title="$1"
    echo ""
    echo -e "${BOLD}${BLUE}▸ ${title}${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
}

# Draw visual gauge / progress bar: draw_progress_bar <percent> <width>
draw_progress_bar() {
    local percent="${1:-0}"
    local width="${2:-24}"

    # Clamp percentage between 0 and 100
    if [ "$percent" -gt 100 ]; then
        percent=100
    elif [ "$percent" -lt 0 ]; then
        percent=0
    fi

    local filled=$(( (percent * width) / 100 ))
    local empty=$(( width - filled ))

    # Color coded based on severity
    local bar_color="${GREEN}"
    if [ "$percent" -ge 85 ]; then
        bar_color="${RED}"
    elif [ "$percent" -ge 70 ]; then
        bar_color="${YELLOW}"
    fi

    printf " ["
    printf "%b" "${bar_color}"
    local i=0
    while [ "$i" -lt "$filled" ]; do
        printf "█"
        i=$((i + 1))
    done
    printf "%b" "${DIM}"
    i=0
    while [ "$i" -lt "$empty" ]; do
        printf "░"
        i=$((i + 1))
    done
    printf "%b] %b%3d%%%b\n" "${NC}" "${BOLD}" "$percent" "${NC}"
}

badge_ok() {
    echo -e "${GREEN}${BOLD}[  OK  ]${NC}"
}

badge_warn() {
    echo -e "${YELLOW}${BOLD}[ WARN ]${NC}"
}

badge_crit() {
    echo -e "${RED}${BOLD}[ CRIT ]${NC}"
}

badge_active() {
    echo -e "${GREEN}${BOLD}[ ACTIVE ]   ${NC}"
}

badge_inactive() {
    echo -e "${RED}${BOLD}[ INACTIVE ] ${NC}"
}

badge_unknown() {
    echo -e "${DIM}[ NOT FOUND ]${NC}"
}

# ------------------------------------------------------------------------------
# Core Monitoring Diagnostics
# ------------------------------------------------------------------------------

# 1. Disk Usage
check_disk() {
    print_header "Disk Filesystem Usage"
    
    local df_output
    df_output=$(df -P / 2>/dev/null | tail -1)
    
    if [ -z "$df_output" ]; then
        echo -e "${RED}Error: Unable to retrieve disk usage.${NC}" >&2
        return 1
    fi

    local filesystem total used avail usage mount_point
    filesystem=$(echo "$df_output" | awk '{print $1}')
    total=$(echo "$df_output" | awk '{print $2}')
    used=$(echo "$df_output" | awk '{print $3}')
    avail=$(echo "$df_output" | awk '{print $4}')
    usage=$(echo "$df_output" | awk '{print $5}' | tr -d '%')
    mount_point=$(echo "$df_output" | awk '{print $6}')

    if ! [[ "$usage" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid disk usage percentage format ($usage).${NC}" >&2
        return 1
    fi

    # Convert 1K-blocks to Human Readable if possible
    local human_total human_used human_avail
    if [ "$total" -ge 1048576 ]; then
        human_total="$(( total / 1048576 )) GB"
        human_used="$(( used / 1048576 )) GB"
        human_avail="$(( avail / 1048576 )) GB"
    else
        human_total="$(( total / 1024 )) MB"
        human_used="$(( used / 1024 )) MB"
        human_avail="$(( avail / 1024 )) MB"
    fi

    echo -e "  Mount Point:   ${BOLD}${mount_point}${NC} (${filesystem})"
    echo -e "  Capacity:      ${human_used} used / ${human_total} total (${human_avail} free)"
    echo -n "  Utilization:  "
    draw_progress_bar "$usage" 25

    echo ""
    if [ "$usage" -ge 90 ]; then
        echo -e "  Status: $(badge_crit) ${RED}${BOLD}Critical: Disk utilization exceeds 90%! Action required.${NC}"
    elif [ "$usage" -ge "$DISK_THRESHOLD" ]; then
        echo -e "  Status: $(badge_warn) ${YELLOW}Warning: Disk usage (${usage}%) is above warning threshold (${DISK_THRESHOLD}%).${NC}"
    else
        echo -e "  Status: $(badge_ok) ${GREEN}Disk filesystem health is normal.${NC}"
    fi
}

# 2. Memory Usage (Cross-platform Linux /proc/meminfo or free, macOS vm_stat fallback)
check_memory() {
    print_header "System Memory & Swap"

    local total_mem=0
    local used_mem=0
    local mem_percent=0
    local total_h="N/A"
    local used_h="N/A"
    local free_h="N/A"

    if [ -f /proc/meminfo ]; then
        # Linux standard proc filesystem
        local mem_total_kb mem_available_kb
        mem_total_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
        mem_available_kb=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || true)
        
        if [ -n "$mem_total_kb" ] && [ "$mem_total_kb" -gt 0 ]; then
            if [ -z "$mem_available_kb" ]; then
                # Fallback calculation if MemAvailable is missing in older kernels
                local mem_free_kb buffers_kb cached_kb
                mem_free_kb=$(awk '/MemFree:/ {print $2}' /proc/meminfo)
                buffers_kb=$(awk '/Buffers:/ {print $2}' /proc/meminfo)
                cached_kb=$(awk '/^Cached:/ {print $2}' /proc/meminfo)
                mem_available_kb=$(( mem_free_kb + buffers_kb + cached_kb ))
            fi
            
            local used_kb=$(( mem_total_kb - mem_available_kb ))
            mem_percent=$(( (used_kb * 100) / mem_total_kb ))
            total_h="$(( mem_total_kb / 1024 )) MB"
            used_h="$(( used_kb / 1024 )) MB"
            free_h="$(( mem_available_kb / 1024 )) MB"
        fi
    elif command -v free >/dev/null 2>&1; then
        # Linux free command
        local free_data
        free_data=$(free -m | awk 'NR==2{printf "%s %s %s", $2, $3, $7}')
        total_h="$(echo "$free_data" | awk '{print $1}') MB"
        used_h="$(echo "$free_data" | awk '{print $2}') MB"
        free_h="$(echo "$free_data" | awk '{print $3}') MB"
        local t_val u_val
        t_val=$(echo "$free_data" | awk '{print $1}')
        u_val=$(echo "$free_data" | awk '{print $2}')
        if [ -n "$t_val" ] && [ "$t_val" -gt 0 ]; then
            mem_percent=$(( (u_val * 100) / t_val ))
        fi
    elif [ "$(uname -s)" = "Darwin" ]; then
        # macOS Darwin memory calculation
        local hw_mem
        hw_mem=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        local page_size
        page_size=$(vm_stat 2>/dev/null | awk '/page size of/ {print $8}' || echo 16384)
        local pages_free pages_inactive pages_speculative
        pages_free=$(vm_stat 2>/dev/null | awk '/Pages free:/ {print $3}' | tr -d '.')
        pages_inactive=$(vm_stat 2>/dev/null | awk '/Pages inactive:/ {print $3}' | tr -d '.')
        pages_speculative=$(vm_stat 2>/dev/null | awk '/Pages speculative:/ {print $3}' | tr -d '.')

        pages_free=${pages_free:-0}
        pages_inactive=${pages_inactive:-0}
        pages_speculative=${pages_speculative:-0}

        # On macOS, inactive and speculative memory can be reclaimed on demand
        local avail_pages=$(( pages_free + pages_inactive + pages_speculative ))
        local avail_bytes=$(( avail_pages * page_size ))
        local total_bytes=$hw_mem

        if [ "$total_bytes" -gt 0 ]; then
            local used_bytes=$(( total_bytes - avail_bytes ))
            [ "$used_bytes" -lt 0 ] && used_bytes=0
            mem_percent=$(( (used_bytes * 100) / total_bytes ))
            total_h="$(( total_bytes / 1048576 )) MB"
            used_h="$(( used_bytes / 1048576 )) MB"
            free_h="$(( avail_bytes / 1048576 )) MB"
        fi
    fi

    if [ -n "$mem_percent" ] && [ "$mem_percent" -ge 0 ] && [ "$total_h" != "N/A" ]; then
        echo -e "  Physical RAM:  ${used_h} used / ${total_h} total (${free_h} free)"
        echo -n "  Utilization:  "
        draw_progress_bar "$mem_percent" 25

        echo ""
        if [ "$mem_percent" -ge 90 ]; then
            echo -e "  Status: $(badge_crit) ${RED}${BOLD}Critical: Memory pressure is high (${mem_percent}%)!${NC}"
        elif [ "$mem_percent" -ge "$MEM_THRESHOLD" ]; then
            echo -e "  Status: $(badge_warn) ${YELLOW}Warning: Memory usage is above threshold (${MEM_THRESHOLD}%).${NC}"
        else
            echo -e "  Status: $(badge_ok) ${GREEN}System memory allocation is healthy.${NC}"
        fi
    else
        echo -e "  ${YELLOW}Note: Unable to accurately parse memory statistics on this platform.${NC}"
    fi
}

# 3. Service Status Health Check
check_services() {
    print_header "Key Service Health Status"

    local custom_list=("$@")
    local services_to_check=()
    if [ ${#custom_list[@]} -gt 0 ]; then
        services_to_check=("${custom_list[@]}")
    else
        services_to_check=("${DEFAULT_SERVICES[@]}")
    fi

    if command -v systemctl >/dev/null 2>&1; then
        echo -e "  ${DIM}Engine: systemd (systemctl)${NC}\n"
        printf "  %-16s %-16s %s\n" "SERVICE" "STATUS" "HEALTH"
        echo -e "  ──────────────────────────────────────────"

        for s in "${services_to_check[@]}"; do
            if systemctl list-unit-files "$s.service" &>/dev/null || systemctl is-active --quiet "$s" 2>/dev/null; then
                if systemctl is-active --quiet "$s" 2>/dev/null; then
                    printf "  %-16s %b  %b\n" "$s" "$(badge_active)" "${GREEN}Running${NC}"
                else
                    printf "  %-16s %b  %b\n" "$s" "$(badge_inactive)" "${RED}Stopped${NC}"
                fi
            else
                printf "  %-16s %b  %b\n" "$s" "$(badge_unknown)" "${DIM}Uninstalled${NC}"
            fi
        done
    elif command -v service >/dev/null 2>&1; then
        echo -e "  ${DIM}Engine: SysV init (service)${NC}\n"
        printf "  %-16s %-16s %s\n" "SERVICE" "STATUS" "HEALTH"
        echo -e "  ──────────────────────────────────────────"
        for s in "${services_to_check[@]}"; do
            if service "$s" status >/dev/null 2>&1; then
                printf "  %-16s %b  %b\n" "$s" "$(badge_active)" "${GREEN}Running${NC}"
            else
                printf "  %-16s %b  %b\n" "$s" "$(badge_inactive)" "${DIM}Inactive / Missing${NC}"
            fi
        done
    else
        echo -e "  ${DIM}Notice: systemctl/service not available. Checking process table...${NC}\n"
        printf "  %-16s %-16s %s\n" "PROCESS" "STATUS" "DETAILS"
        echo -e "  ──────────────────────────────────────────"
        for s in "${services_to_check[@]}"; do
            if pgrep -x "$s" >/dev/null 2>&1 || pgrep -f "$s" >/dev/null 2>&1; then
                printf "  %-16s %b  %b\n" "$s" "$(badge_active)" "${GREEN}Process Detected${NC}"
            else
                printf "  %-16s %b  %b\n" "$s" "$(badge_inactive)" "${DIM}Not Running${NC}"
            fi
        done
    fi
}

# 4. CPU & System Overview
check_system_load() {
    print_header "System Load & Uptime"

    local os_info
    if [ -f /etc/os-release ]; then
        os_info=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
    elif command -v sw_vers >/dev/null 2>&1; then
        os_info="$(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null)"
    else
        os_info="$(uname -s) $(uname -r)"
    fi

    local uptime_info
    uptime_info=$(uptime 2>/dev/null || echo "N/A")
    
    local cpu_cores
    if [ -f /proc/cpuinfo ]; then
        cpu_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
    elif command -v sysctl >/dev/null 2>&1; then
        cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
    else
        cpu_cores=1
    fi

    # Extract load averages
    local load_avg
    load_avg=$(echo "$uptime_info" | awk -F'load averages?:' '{print $2}' | sed 's/^[ \t]*//')
    [ -z "$load_avg" ] && load_avg="N/A"

    echo -e "  Operating System: ${BOLD}${os_info}${NC}"
    echo -e "  CPU Cores:        ${BOLD}${cpu_cores}${NC}"
    echo -e "  Load Averages:    ${BOLD}${load_avg}${NC} (1m, 5m, 15m)"
    echo -e "  Uptime:           ${DIM}${uptime_info}${NC}"

    # Load alert check if 1m load > cpu_cores
    local one_min_load
    one_min_load=$(echo "$load_avg" | awk '{print $1}' | tr -d ',')
    if [[ "$one_min_load" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        local int_load
        int_load=${one_min_load%.*}
        if [ "$int_load" -ge "$cpu_cores" ] 2>/dev/null; then
            echo ""
            echo -e "  Status: $(badge_warn) ${YELLOW}Warning: 1-minute load average (${one_min_load}) exceeds core count (${cpu_cores})!${NC}"
        else
            echo ""
            echo -e "  Status: $(badge_ok) ${GREEN}CPU load is within normal operational capacity.${NC}"
        fi
    fi
}

# 5. Composite Health Audit
run_all_checks() {
    check_system_load
    check_disk
    check_memory
    check_services
    echo ""
    echo -e "${GREEN}${BOLD}✔ Full server health audit complete.${NC}"
}

# 6. Live Watch Mode
watch_mode() {
    local interval="${1:-2}"
    trap 'echo -e "\n${CYAN}Exiting live monitor...${NC}"; exit 0' INT TERM
    while true; do
        clear 2>/dev/null || true
        print_banner
        echo -e "${MAGENTA}${BOLD}● LIVE WATCH MODE${NC} ${DIM}(Refreshing every ${interval}s • Press Ctrl+C to exit)${NC}"
        run_all_checks
        sleep "$interval"
    done
}

# ------------------------------------------------------------------------------
# Interactive Menu System
# ------------------------------------------------------------------------------

interactive_menu() {
    local choice=""
    while true; do
        clear 2>/dev/null || true
        print_banner
        echo -e " ${BOLD}Select a diagnostic option:${NC}"
        echo ""
        echo -e "   ${CYAN}${BOLD}[1]${NC} 💾 Check Disk Usage ${DIM}(Visual gauge & threshold)${NC}"
        echo -e "   ${CYAN}${BOLD}[2]${NC} 🧠 Check Memory & Swap ${DIM}(RAM utilization)${NC}"
        echo -e "   ${CYAN}${BOLD}[3]${NC} ⚙️  Check Service Health ${DIM}(Nginx, SSH, Cron, etc.)${NC}"
        echo -e "   ${CYAN}${BOLD}[4]${NC} ⚡ Check System & CPU Load ${DIM}(Uptime, OS, Cores)${NC}"
        echo -e "   ${CYAN}${BOLD}[5]${NC} 📊 Run Complete Health Audit ${DIM}(All checks in one)${NC}"
        echo -e "   ${CYAN}${BOLD}[6]${NC} ⏱️  Live Dashboard Watch Mode ${DIM}(Auto-refresh)${NC}"
        echo -e "   ${CYAN}${BOLD}[7]${NC} 🛠️  Configure Alert Thresholds"
        echo -e "   ${CYAN}${BOLD}[q]${NC} 🚪 Exit Toolkit"
        echo ""
        echo -e "${DIM}─────────────────────────────────────────────────────────────${NC}"
        printf "${BOLD}Enter choice [1-7, q]: ${NC}"
        read -r choice

        case "$choice" in
            1)
                check_disk
                echo ""
                printf "${DIM}Press Enter to return to menu...${NC}"
                read -r _
                ;;
            2)
                check_memory
                echo ""
                printf "${DIM}Press Enter to return to menu...${NC}"
                read -r _
                ;;
            3)
                check_services
                echo ""
                printf "${DIM}Press Enter to return to menu...${NC}"
                read -r _
                ;;
            4)
                check_system_load
                echo ""
                printf "${DIM}Press Enter to return to menu...${NC}"
                read -r _
                ;;
            5)
                run_all_checks
                echo ""
                printf "${DIM}Press Enter to return to menu...${NC}"
                read -r _
                ;;
            6)
                printf "${BOLD}Enter refresh interval in seconds [default: 2]: ${NC}"
                local sec
                read -r sec
                sec="${sec:-2}"
                watch_mode "$sec"
                ;;
            7)
                echo ""
                echo -e "${BOLD}Current Alert Thresholds:${NC}"
                echo -e "  Disk Usage Warning: ${DISK_THRESHOLD}%"
                echo -e "  Memory Warning:     ${MEM_THRESHOLD}%"
                echo ""
                printf "Enter new Disk warning threshold %% [1-99, or Enter to keep %d]: " "$DISK_THRESHOLD"
                local new_disk
                read -r new_disk
                if [[ "$new_disk" =~ ^[0-9]+$ ]] && [ "$new_disk" -ge 1 ] && [ "$new_disk" -le 99 ]; then
                    DISK_THRESHOLD="$new_disk"
                    echo -e "${GREEN}✔ Disk threshold updated to ${DISK_THRESHOLD}%.${NC}"
                fi

                printf "Enter new Memory warning threshold %% [1-99, or Enter to keep %d]: " "$MEM_THRESHOLD"
                local new_mem
                read -r new_mem
                if [[ "$new_mem" =~ ^[0-9]+$ ]] && [ "$new_mem" -ge 1 ] && [ "$new_mem" -le 99 ]; then
                    MEM_THRESHOLD="$new_mem"
                    echo -e "${GREEN}✔ Memory threshold updated to ${MEM_THRESHOLD}%.${NC}"
                fi

                sleep 1
                ;;
            q|Q|exit|quit)
                echo -e "\n${GREEN}Thank you for using Server Monitoring Toolkit. Goodbye!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid selection. Please enter 1-7 or q.${NC}"
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Help & Usage
# ------------------------------------------------------------------------------

show_help() {
    print_banner
    cat << EOF
Usage: ./monitor.sh [COMMAND|OPTION]

Interactive Mode:
  ./monitor.sh                    Launch full interactive TUI menu
  ./monitor.sh -i, --interactive  Launch full interactive TUI menu

Subcommands:
  disk                            Check root filesystem disk utilization
  memory, mem                     Check system RAM and swap memory usage
  services, svc                   Check status of key system services
  system, cpu                     Check OS details, uptime, and CPU load averages
  all                             Run full composite health audit

Options:
  -w, --watch [SECONDS]           Run live dashboard mode (default: 2s)
  -t, --threshold PERCENT         Set custom disk alert threshold (default: 85%)
  -h, --help                      Display this help and exit
  -v, --version                   Display version information and exit

Examples:
  ./monitor.sh                    # Open interactive terminal menu
  ./monitor.sh all                # Quick one-shot audit for scripts or CI
  ./monitor.sh disk -t 90         # Check disk with a custom 90% threshold
  ./monitor.sh --watch 3          # Live refresh dashboard every 3 seconds

EOF
}

# ------------------------------------------------------------------------------
# Command Line Parser
# ------------------------------------------------------------------------------

# Handle empty invocation -> open interactive mode if connected to a terminal, or all if piped
if [ $# -eq 0 ]; then
    if [ -t 0 ]; then
        interactive_menu
        exit 0
    else
        run_all_checks
        exit 0
    fi
fi

# Parse arguments & flags
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help|help)
            show_help
            exit 0
            ;;
        -v|--version|version)
            echo "Server Monitoring Toolkit v${VERSION}"
            exit 0
            ;;
        -i|--interactive)
            interactive_menu
            exit 0
            ;;
        -w|--watch)
            shift
            interval="${1:-2}"
            if [[ "$interval" =~ ^- ]]; then
                interval=2
            fi
            watch_mode "$interval"
            exit 0
            ;;
        -t|--threshold)
            shift
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                DISK_THRESHOLD="$1"
            else
                echo -e "${RED}Error: Threshold must be a numeric integer.${NC}" >&2
                exit 1
            fi
            shift
            ;;
        disk)
            if [ "${2:-}" = "-t" ] || [ "${2:-}" = "--threshold" ]; then
                if [[ "${3:-}" =~ ^[0-9]+$ ]]; then
                    DISK_THRESHOLD="$3"
                fi
            fi
            check_disk
            exit 0
            ;;
        memory|mem)
            check_memory
            exit 0
            ;;
        services|svc)
            shift
            check_services "$@"
            exit 0
            ;;
        system|cpu|load)
            check_system_load
            exit 0
            ;;
        all)
            run_all_checks
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown argument: $1${NC}" >&2
            echo "Run './monitor.sh --help' for available commands." >&2
            exit 1
            ;;
    esac
done
