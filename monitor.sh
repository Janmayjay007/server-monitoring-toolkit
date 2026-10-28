#!/usr/bin/env bash

# server-monitoring-toolkit
# Quick health check script for Linux and macOS servers.

VERSION="2.1"
DISK_THRESHOLD="${DISK_THRESHOLD:-85}"
DISK_CRITICAL="${DISK_CRITICAL:-95}"
MEM_THRESHOLD="${MEM_THRESHOLD:-85}"
MEM_CRITICAL="${MEM_CRITICAL:-95}"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-5}"
HTTP_SLOW_MS="${HTTP_SLOW_MS:-2000}"
CHECK_URLS="${CHECK_URLS:-}"
CHECK_PORTS="${CHECK_PORTS:-}"
SERVICES=("nginx" "ssh" "sshd" "cron" "crond" "docker")

# Exit codes follow the Nagios plugin convention, so cron, CI and
# monitoring systems can act on the result.
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATUS=$STATE_OK

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

# severity <code>: rank results as OK < UNKNOWN < WARNING < CRITICAL,
# so a check that could not run never hides a real outage
severity() {
    case "$1" in
        "$STATE_OK")       echo 0 ;;
        "$STATE_UNKNOWN")  echo 1 ;;
        "$STATE_WARNING")  echo 2 ;;
        "$STATE_CRITICAL") echo 3 ;;
    esac
}

# raise_status <code>: the script exits with the most severe result it saw
raise_status() {
    if [ "$(severity "$1")" -gt "$(severity "$STATUS")" ]; then
        STATUS=$1
    fi
}

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

print_summary() {
    local label color
    case "$STATUS" in
        "$STATE_OK")       label="OK";       color="$GREEN" ;;
        "$STATE_WARNING")  label="WARNING";  color="$YELLOW" ;;
        "$STATE_CRITICAL") label="CRITICAL"; color="$RED" ;;
        *)                 label="UNKNOWN";  color="$DIM" ;;
    esac
    echo ""
    echo -e "${BOLD}Result:${NC} ${color}${label}${NC} ${DIM}(exit ${STATUS})${NC}"
}

# Progress bar: draw_bar <percent> <warn-at> <critical-at> [width]
draw_bar() {
    local pct="${1:-0}"
    local warn="${2:-70}"
    local crit="${3:-90}"
    local width="${4:-20}"

    [ "$pct" -gt 100 ] && pct=100
    [ "$pct" -lt 0 ] && pct=0

    local filled=$(( (pct * width) / 100 ))
    local empty=$(( width - filled ))

    local color="${GREEN}"
    if [ "$pct" -ge "$crit" ]; then
        color="${RED}"
    elif [ "$pct" -ge "$warn" ]; then
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
        raise_status "$STATE_UNKNOWN"
        return
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
    draw_bar "$pct" "$DISK_THRESHOLD" "$DISK_CRITICAL" 20

    if [ "$pct" -ge "$DISK_CRITICAL" ]; then
        echo -e "  Status:  ${RED}[CRIT] Disk usage is above ${DISK_CRITICAL}%${NC}"
        raise_status "$STATE_CRITICAL"
    elif [ "$pct" -ge "$DISK_THRESHOLD" ]; then
        echo -e "  Status:  ${YELLOW}[WARN] Disk usage is above ${DISK_THRESHOLD}%${NC}"
        raise_status "$STATE_WARNING"
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
        draw_bar "$pct" "$MEM_THRESHOLD" "$MEM_CRITICAL" 20

        if [ "$pct" -ge "$MEM_CRITICAL" ]; then
            echo -e "  Status:  ${RED}[CRIT] Memory usage is above ${MEM_CRITICAL}% (${pct}%)${NC}"
            raise_status "$STATE_CRITICAL"
        elif [ "$pct" -ge "$MEM_THRESHOLD" ]; then
            echo -e "  Status:  ${YELLOW}[WARN] High memory usage (${pct}%)${NC}"
            raise_status "$STATE_WARNING"
        else
            echo -e "  Status:  ${GREEN}[OK] Memory is healthy.${NC}"
        fi
    else
        echo "  Note: Could not calculate memory on this system."
        raise_status "$STATE_UNKNOWN"
    fi
}

# check_services [name...]
# A stopped service is critical. A service that is not installed only
# fails the check when it was asked for by name; the default list is
# a best guess and differs between distros (ssh vs sshd, cron vs crond).
check_services() {
    print_header "Services"

    local targets=("$@")
    local explicit=1
    if [ ${#targets[@]} -eq 0 ]; then
        targets=("${SERVICES[@]}")
        explicit=0
    fi

    if command -v systemctl >/dev/null 2>&1; then
        printf "  %-14s %-12s %s\n" "SERVICE" "STATUS" "DETAILS"
        echo "  ------------------------------------"
        local s load_state
        for s in "${targets[@]}"; do
            load_state=$(systemctl show -p LoadState --value "$s" 2>/dev/null)
            if [ "$load_state" = "loaded" ]; then
                if systemctl is-active --quiet "$s" 2>/dev/null; then
                    printf "  %-14s %b[ACTIVE]%b     running\n" "$s" "${GREEN}" "${NC}"
                else
                    printf "  %-14s %b[INACTIVE]%b   stopped\n" "$s" "${RED}" "${NC}"
                    raise_status "$STATE_CRITICAL"
                fi
            elif [ "$explicit" -eq 1 ]; then
                printf "  %-14s %b[NOT FOUND]%b  not installed\n" "$s" "${RED}" "${NC}"
                raise_status "$STATE_CRITICAL"
            else
                printf "  %-14s %b[NOT FOUND]%b  not installed\n" "$s" "${DIM}" "${NC}"
            fi
        done

    elif command -v service >/dev/null 2>&1; then
        printf "  %-14s %-12s %s\n" "SERVICE" "STATUS" "DETAILS"
        echo "  ------------------------------------"
        local s
        for s in "${targets[@]}"; do
            if [ ! -e "/etc/init.d/$s" ]; then
                if [ "$explicit" -eq 1 ]; then
                    printf "  %-14s %b[NOT FOUND]%b  not installed\n" "$s" "${RED}" "${NC}"
                    raise_status "$STATE_CRITICAL"
                else
                    printf "  %-14s %b[NOT FOUND]%b  not installed\n" "$s" "${DIM}" "${NC}"
                fi
            elif service "$s" status >/dev/null 2>&1; then
                printf "  %-14s %b[ACTIVE]%b     running\n" "$s" "${GREEN}" "${NC}"
            else
                printf "  %-14s %b[INACTIVE]%b   stopped\n" "$s" "${RED}" "${NC}"
                raise_status "$STATE_CRITICAL"
            fi
        done

    else
        echo "  (systemctl not found, checking running processes)"
        printf "  %-14s %-12s\n" "PROCESS" "STATUS"
        echo "  --------------------------"
        local s
        for s in "${targets[@]}"; do
            if pgrep -x "$s" >/dev/null 2>&1 || pgrep -f "$s" >/dev/null 2>&1; then
                printf "  %-14s %b[ACTIVE]%b\n" "$s" "${GREEN}" "${NC}"
            elif [ "$explicit" -eq 1 ]; then
                printf "  %-14s %b[INACTIVE]%b\n" "$s" "${RED}" "${NC}"
                raise_status "$STATE_CRITICAL"
            else
                printf "  %-14s %b[INACTIVE]%b\n" "$s" "${DIM}" "${NC}"
            fi
        done
    fi
}

# check_http <url>...
# A service can be "active (running)" and still serve nothing, so this
# asks the service itself: it must answer with a 2xx/3xx in time.
check_http() {
    print_header "HTTP Health"

    if [ $# -eq 0 ]; then
        echo "  Usage: ./monitor.sh http <url> [url...]"
        raise_status "$STATE_UNKNOWN"
        return
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo "  Error: curl is required for HTTP checks." >&2
        raise_status "$STATE_UNKNOWN"
        return
    fi

    local url result rc code ms reason
    for url in "$@"; do
        result=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' \
            --max-time "$HTTP_TIMEOUT" "$url" 2>/dev/null)
        rc=$?
        code=${result%% *}
        ms=$(echo "$result" | awk '{ printf "%d", $2 * 1000 }')

        if [ "$rc" -ne 0 ] || [ "$code" = "000" ]; then
            case "$rc" in
                6)  reason="could not resolve host" ;;
                7)  reason="connection refused" ;;
                28) reason="no answer within ${HTTP_TIMEOUT}s" ;;
                *)  reason="curl error $rc" ;;
            esac
            printf "  %b[DOWN]%b  %-5s %7s  %s\n" "${RED}" "${NC}" "-" "-" "$url ($reason)"
            raise_status "$STATE_CRITICAL"
        elif [ "$code" -ge 400 ]; then
            printf "  %b[FAIL]%b  %-5s %5sms  %s\n" "${RED}" "${NC}" "$code" "$ms" "$url"
            raise_status "$STATE_CRITICAL"
        elif [ "$ms" -ge "$HTTP_SLOW_MS" ]; then
            printf "  %b[SLOW]%b  %-5s %5sms  %s\n" "${YELLOW}" "${NC}" "$code" "$ms" "$url"
            raise_status "$STATE_WARNING"
        else
            printf "  %b[UP]%b    %-5s %5sms  %s\n" "${GREEN}" "${NC}" "$code" "$ms" "$url"
        fi
    done
}

# port_open <host> <port>
port_open() {
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 2 "$1" "$2" >/dev/null 2>&1
    else
        (exec 3<>"/dev/tcp/$1/$2") 2>/dev/null
    fi
}

# check_ports <port|host:port>...
check_ports() {
    print_header "Ports"

    if [ $# -eq 0 ]; then
        echo "  Usage: ./monitor.sh port <port|host:port> [...]"
        raise_status "$STATE_UNKNOWN"
        return
    fi

    local target host port
    for target in "$@"; do
        host="127.0.0.1"
        port="$target"
        case "$target" in
            *:*) host="${target%:*}"; port="${target##*:}" ;;
        esac

        case "$port" in
            ''|*[!0-9]*)
                printf "  %b[??]%b      %s (not a port number)\n" "${DIM}" "${NC}" "$target"
                raise_status "$STATE_UNKNOWN"
                continue
                ;;
        esac

        if port_open "$host" "$port"; then
            printf "  %b[OPEN]%b    %s:%s\n" "${GREEN}" "${NC}" "$host" "$port"
        else
            printf "  %b[CLOSED]%b  %s:%s (nothing is listening)\n" "${RED}" "${NC}" "$host" "$port"
            raise_status "$STATE_CRITICAL"
        fi
    done
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

    # Optional health checks, e.g. CHECK_URLS="http://localhost/" CHECK_PORTS="80 443"
    local urls=() ports=()
    read -r -a urls <<< "$CHECK_URLS"
    read -r -a ports <<< "$CHECK_PORTS"
    [ ${#urls[@]} -gt 0 ] && check_http "${urls[@]}"
    [ ${#ports[@]} -gt 0 ] && check_ports "${ports[@]}"

    print_summary
}

watch_mode() {
    local delay="${1:-2}"
    trap 'echo -e "\nExiting watch mode."; exit 0' INT TERM
    while true; do
        STATUS=$STATE_OK
        clear 2>/dev/null || true
        print_banner
        echo -e "${CYAN}Live Watch Mode (${delay}s refresh) - Ctrl+C to exit${NC}"
        run_all
        sleep "$delay"
    done
}

# start_web [port] [host]
start_web() {
    local port="${1:-8080}"
    local host="${2:-127.0.0.1}"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if ! command -v python3 >/dev/null 2>&1; then
        echo "Error: python3 is required to run the web dashboard." >&2
        return 1
    fi

    python3 "$script_dir/web/server.py" "$port" --host "$host"
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
        echo "  7) Launch web dashboard"
        echo "  8) Check a URL (HTTP health)"
        echo "  q) Quit"
        echo ""
        printf "Select [1-8, q]: "
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
            7)
                printf "Port number [default: 8080]: "
                read -r port
                start_web "${port:-8080}"
                ;;
            8)
                printf "URL [default: http://localhost/]: "
                read -r url
                check_http "${url:-http://localhost/}"
                ;;
            q|Q|exit)
                echo "Bye."
                exit 0
                ;;
            *)
                echo "Invalid option."
                ;;
        esac

        STATUS=$STATE_OK
        echo ""
        printf "Press Enter to continue..."
        read -r _
    done
}

show_help() {
    echo "Usage: ./monitor.sh [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  (no args)            Open interactive menu"
    echo "  all                  Run all checks"
    echo "  disk                 Check disk usage"
    echo "  memory               Check RAM usage"
    echo "  services [NAME...]   Check service status (default: nginx, ssh, cron, docker)"
    echo "  system               Check CPU load and uptime"
    echo "  http URL...          Check that URLs answer with 2xx/3xx in time"
    echo "  port PORT...         Check that ports are listening (PORT or HOST:PORT)"
    echo "  watch [N]            Live refresh every N seconds (default: 2)"
    echo "  web [PORT] [HOST]    Start web dashboard (default: 127.0.0.1:8080)"
    echo "  help                 Show this message"
    echo ""
    echo "Exit codes:"
    echo "  0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN"
    echo "  The most severe result wins: CRITICAL > WARNING > UNKNOWN > OK"
    echo ""
    echo "Environment variables:"
    echo "  DISK_THRESHOLD=85    Disk warning percentage"
    echo "  DISK_CRITICAL=95     Disk critical percentage"
    echo "  MEM_THRESHOLD=85     Memory warning percentage"
    echo "  MEM_CRITICAL=95      Memory critical percentage"
    echo "  HTTP_TIMEOUT=5       Seconds before an HTTP check counts as down"
    echo "  HTTP_SLOW_MS=2000    Response time that counts as a warning"
    echo "  CHECK_URLS=\"...\"     URLs that 'all' also checks"
    echo "  CHECK_PORTS=\"...\"    Ports that 'all' also checks"
}

# If no args passed, open interactive menu if in terminal, or run all if piped
if [ $# -eq 0 ]; then
    if [ -t 0 ]; then
        interactive_menu
        exit 0
    fi
    run_all
    exit "$STATUS"
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
    http|url)
        shift
        check_http "$@"
        ;;
    port|ports)
        shift
        check_ports "$@"
        ;;
    watch|-w)
        shift
        watch_mode "${1:-2}"
        ;;
    web)
        shift
        start_web "$@"
        exit $?
        ;;
    -h|--help|help) show_help ;;
    *)
        echo "Unknown command: $1"
        echo "Run './monitor.sh help' for usage."
        exit "$STATE_UNKNOWN"
        ;;
esac

exit "$STATUS"
