# Shared helpers for the bats tests.
# shellcheck shell=bash

MONITOR="$BATS_TEST_DIRNAME/../monitor.sh"
SERVER="$BATS_TEST_DIRNAME/../web/server.py"
BG_PIDS=()

# free_port: print a TCP port nothing is listening on
free_port() {
    python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'
}

# wait_for_port <port>: wait up to 5s for something to listen on 127.0.0.1:<port>
wait_for_port() {
    local i
    for i in $(seq 1 50); do
        if python3 -c "import socket, sys; socket.create_connection(('127.0.0.1', $1), 0.2)" 2>/dev/null; then
            return 0
        fi
        sleep 0.1
    done
    echo "nothing started listening on port $1" >&2
    return 1
}

# start_bg <command...>: run a server in the background, stopped in teardown.
# fd 3 is closed so bats does not wait for the process to exit.
start_bg() {
    "$@" >/dev/null 2>&1 3>&- &
    BG_PIDS+=("$!")
}

# start_static_server <port>: a plain HTTP server where / answers 200
# and any other path answers 404
start_static_server() {
    local root="$BATS_TEST_TMPDIR/www"
    mkdir -p "$root"
    echo "ok" > "$root/index.html"
    start_bg python3 -m http.server "$1" --bind 127.0.0.1 --directory "$root"
    wait_for_port "$1"
}

stop_bg() {
    local pid
    for pid in "${BG_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    BG_PIDS=()
}
