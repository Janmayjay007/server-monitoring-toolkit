#!/usr/bin/env bash

# server-monitoring-toolkit
# Quick health check script for Linux and macOS servers.

VERSION="2.0"
DISK_THRESHOLD="${DISK_THRESHOLD:-85}"
MEM_THRESHOLD="${MEM_THRESHOLD:-85}"
SERVICES=("nginx" "ssh" "sshd" "cron" "crond" "docker")

# Colors (only if running in a terminal)
if [ -t 1 ]; then
    BOLD="\033[1m"
    DIM="\033[2m"
    GREEN="\033[0;32m"
    RED="\033[0;31m"
    YELLOW="\033[0;33m"
    CYAN="\033[0;36m"
    NC="\033[0m"
else
    BOLD=""
    DIM=""
    GREEN=""
    RED=""
    YELLOW=""
    CYAN=""
    NC=""
fi

print_banner() {
    local host
    host=$(hostname 2>/dev/null || echo "localhost")
    echo -e "${BOLD}Server Health Monitor${NC} ${DIM}(v${VERSION})${NC}"
    echo -e "${DIM}Host: ${host} | Date: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${DIM}--------------------------------------------------${NC}"
}

print_header() {
    echo ""
    echo -e "${BOLD}:: $1${NC}"
}

# Progress bar: draw_bar <percent> [width]
draw_bar() {
    local pct="${1:-0}"
    local width="${2:-20}"

    [ "$pct" -gt 100 ] && pct=100
    [ "$pct" -lt 0 ] && pct=0

    local filled=$(( (pct * width) / 100 ))
    local empty=$(( width - filled ))

    local color="${GREEN}"
    if [ "$pct" -ge "$DISK_THRESHOLD" ]; then
        color="${RED}"
    elif [ "$pct" -ge 70 ]; then
        color="${YELLOW}"
    fi

    printf " ["
    printf "%b" "${color}"
    local i=0
    while [ "$i" -lt "$filled" ]; do
        printf "#"
        i=$((i + 1))
    done
    printf "%b" "${NC}"
    i=0
    while [ "$i" -lt "$empty" ]; do
        printf "-"
        i=$((i + 1))
    done
    printf "] %3d%%\n" "$pct"
}

check_disk() {
    print_header "Disk Usage"

    local line
    line=$(df -P / 2>/dev/null | tail -1)
    if [ -z "$line" ]; then
        echo "Error: unable to read disk usage from df." >&2
        return 1
    fi

    local fs total used avail pct mount
    fs=$(echo "$line" | awk '{print $1}')
    total=$(echo "$line" | awk '{print $2}')
    used=$(echo "$line" | awk '{print $3}')
    avail=$(echo "$line" | awk '{print $4}')
    pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')

    local total_gb=$(( total / 1048576 ))
    local used_gb=$(( used / 1048576 ))
    local avail_gb=$(( avail / 1048576 ))

    echo "  Mount:   $mount ($fs)"
    echo "  Space:   ${used_gb}G / ${total_gb}G (${avail_gb}G free)"
    printf "  Usage:  "
    draw_bar "$pct" 20

    if [ "$pct" -ge "$DISK_THRESHOLD" ]; then
        echo -e "  Status:  ${RED}[WARN] Disk usage is above ${DISK_THRESHOLD}%${NC}"
    else
        echo -e "  Status:  ${GREEN}[OK] Disk space looks good.${NC}"
    fi
}

check_memory() {
    print_header "Memory"

    local total_mb=0 used_mb=0 free_mb=0 pct=0

    if [ -f /proc/meminfo ]; then
        local total_kb avail_kb
        total_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
        avail_kb=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || true)

        if [ -z "$avail_kb" ]; then
            local free_kb buf_kb cache_kb
            free_kb=$(awk '/MemFree:/ {print $2}' /proc/meminfo)
            buf_kb=$(awk '/Buffers:/ {print $2}' /proc/meminfo)
            cache_kb=$(awk '/^Cached:/ {print $2}' /proc/meminfo)
            avail_kb=$(( free_kb + buf_kb + cache_kb ))
        fi

        total_mb=$(( total_kb / 1024 ))
        free_mb=$(( avail_kb / 1024 ))
        used_mb=$(( total_mb - free_mb ))
        [ "$total_mb" -gt 0 ] && pct=$(( (used_mb * 100) / total_mb ))

    elif command -v free >/dev/null 2>&1; then
        local line
        line=$(free -m | awk 'NR==2{print $2, $3, $7}')
        total_mb=$(echo "$line" | awk '{print $1}')
        used_mb=$(echo "$line" | awk '{print $2}')
        free_mb=$(echo "$line" | awk '{print $3}')
        [ "$total_mb" -gt 0 ] && pct=$(( (used_mb * 100) / total_mb ))

    elif [ "$(uname -s)" = "Darwin" ]; then
        local hw_mem page_size
        hw_mem=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        page_size=$(vm_stat 2>/dev/null | awk '/page size of/ {print $8}' || echo 16384)

        local p_free p_inactive p_spec
        p_free=$(vm_stat 2>/dev/null | awk '/Pages free:/ {print $3}' | tr -d '.')
        p_inactive=$(vm_stat 2>/dev/null | awk '/Pages inactive:/ {print $3}' | tr -d '.')
        p_spec=$(vm_stat 2>/dev/null | awk '/Pages speculative:/ {print $3}' | tr -d '.')

        local avail_bytes=$(( (p_free + p_inactive + p_spec) * page_size ))
        total_mb=$(( hw_mem / 1048576 ))
        free_mb=$(( avail_bytes / 1048576 ))
        used_mb=$(( total_mb - free_mb ))
        [ "$used_mb" -lt 0 ] && used_mb=0
        [ "$total_mb" -gt 0 ] && pct=$(( (used_mb * 100) / total_mb ))
    fi

    if [ "$total_mb" -gt 0 ]; then
        echo "  RAM:     ${used_mb}MB / ${total_mb}MB (${free_mb}MB available)"
        printf "  Usage:  "
        draw_bar "$pct" 20

        if [ "$pct" -ge "$MEM_THRESHOLD" ]; then
            echo -e "  Status:  ${RED}[WARN] High memory usage (${pct}%)${NC}"
        else
            echo -e "  Status:  ${GREEN}[OK] Memory is healthy.${NC}"
        fi
    else
        echo "  Note: Could not calculate memory on this system."
    fi
}

check_services() {
    print_header "Services"

    local targets=("$@")
    [ ${#targets[@]} -eq 0 ] && targets=("${SERVICES[@]}")

    if command -v systemctl >/dev/null 2>&1; then
        printf "  %-14s %-12s %s\n" "SERVICE" "STATUS" "DETAILS"
        echo "  ------------------------------------"
        for s in "${targets[@]}"; do
            if systemctl list-unit-files "$s.service" &>/dev/null || systemctl is-active --quiet "$s" 2>/dev/null; then
                if systemctl is-active --quiet "$s" 2>/dev/null; then
                    printf "  %-14s %b[ACTIVE]%b     running\n" "$s" "${GREEN}" "${NC}"
                else
                    printf "  %-14s %b[INACTIVE]%b   stopped\n" "$s" "${RED}" "${NC}"
                fi
            else
                printf "  %-14s %b[NOT FOUND]%b  not installed\n" "$s" "${DIM}" "${NC}"
            fi
        done

    elif command -v service >/dev/null 2>&1; then
        printf "  %-14s %-12s %s\n" "SERVICE" "STATUS" "DETAILS"
        echo "  ------------------------------------"
        for s in "${targets[@]}"; do
            if service "$s" status >/dev/null 2>&1; then
                printf "  %-14s %b[ACTIVE]%b     running\n" "$s" "${GREEN}" "${NC}"
            else
                printf "  %-14s %b[INACTIVE]%b   stopped/missing\n" "$s" "${RED}" "${NC}"
            fi
        done

    else
        echo "  (systemctl not found, checking running processes)"
        printf "  %-14s %-12s\n" "PROCESS" "STATUS"
        echo "  --------------------------"
        for s in "${targets[@]}"; do
            if pgrep -x "$s" >/dev/null 2>&1 || pgrep -f "$s" >/dev/null 2>&1; then
                printf "  %-14s %b[ACTIVE]%b\n" "$s" "${GREEN}" "${NC}"
            else
                printf "  %-14s %b[INACTIVE]%b\n" "$s" "${DIM}" "${NC}"
            fi
        done
    fi
}

check_system() {
    print_header "System & Load"

    local os="Unknown"
    if [ -f /etc/os-release ]; then
        os=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
    elif command -v sw_vers >/dev/null 2>&1; then
        os="$(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null)"
    fi

    local cores=1
    if [ -f /proc/cpuinfo ]; then
        cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
    elif command -v sysctl >/dev/null 2>&1; then
        cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
    fi

    local load
    load=$(uptime 2>/dev/null | awk -F'load averages?:' '{print $2}' | sed 's/^[ \t]*//')

    echo "  OS:      $os"
    echo "  Cores:   $cores"
    echo "  Load:    ${load:-N/A} (1m, 5m, 15m)"
    echo "  Uptime:  $(uptime 2>/dev/null | sed 's/.*up \([^,]*\), .*/\1/')"
}

run_all() {
    check_system
    check_disk
    check_memory
    check_services
    echo ""
}

watch_mode() {
    local delay="${1:-2}"
    trap 'echo -e "\nExiting watch mode."; exit 0' INT TERM
    while true; do
        clear 2>/dev/null || true
        print_banner
        echo -e "${CYAN}Live Watch Mode (${delay}s refresh) - Ctrl+C to exit${NC}"
        run_all
        sleep "$delay"
    done
}

interactive_menu() {
    while true; do
        clear 2>/dev/null || true
        print_banner
        echo "Choose an option:"
        echo "  1) Check disk usage"
        echo "  2) Check memory (RAM)"
        echo "  3) Check services"
        echo "  4) Check CPU & system load"
        echo "  5) Run all checks"
        echo "  6) Watch mode (live refresh)"
        echo "  q) Quit"
        echo ""
        printf "Select [1-6, q]: "
        read -r opt

        case "$opt" in
            1) check_disk ;;
            2) check_memory ;;
            3) check_services ;;
            4) check_system ;;
            5) run_all ;;
            6)
                printf "Refresh interval in seconds [default: 2]: "
                read -r sec
                watch_mode "${sec:-2}"
                ;;
            q|Q|exit)
                echo "Bye."
                exit 0
                ;;
            *)
                echo "Invalid option."
                ;;
        esac

        echo ""
        printf "Press Enter to continue..."
        read -r _
    done
}

show_help() {
    echo "Usage: ./monitor.sh [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  (no args)    Open interactive menu"
    echo "  all          Run all checks"
    echo "  disk         Check disk usage"
    echo "  memory       Check RAM usage"
    echo "  services     Check service status (nginx, ssh, cron, docker)"
    echo "  system       Check CPU load and uptime"
    echo "  watch [N]    Live refresh every N seconds (default: 2)"
    echo "  help         Show this message"
    echo ""
    echo "Environment variables:"
    echo "  DISK_THRESHOLD=85   Set disk warning percentage"
    echo "  MEM_THRESHOLD=85    Set memory warning percentage"
}

# If no args passed, open interactive menu if in terminal, or run all if piped
if [ $# -eq 0 ]; then
    if [ -t 0 ]; then
        interactive_menu
    else
        run_all
    fi
    exit 0
fi

case "$1" in
    all) run_all ;;
    disk) check_disk ;;
    memory|mem) check_memory ;;
    services|svc)
        shift
        check_services "$@"
        ;;
    system|cpu|load) check_system ;;
    watch|-w)
        shift
        watch_mode "${1:-2}"
        ;;
    -h|--help|help) show_help ;;
    *)
        echo "Unknown command: $1"
        echo "Run './monitor.sh help' for usage."
        exit 1
        ;;
esac
