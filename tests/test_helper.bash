# Shared helpers for the bats tests.
# shellcheck shell=bash

# MONITOR and SERVER are used by monitor.bats
# shellcheck disable=SC2034
MONITOR="$BATS_TEST_DIRNAME/../monitor.sh"
# shellcheck disable=SC2034
SERVER="$BATS_TEST_DIRNAME/../web/server.py"
BG_PIDS=()

# free_port: print a TCP port nothing is listening on
free_port() {
    python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'
}

# wait_for_port <port>: wait up to 10s for something to listen on 127.0.0.1:<port>.
# On failure, print the background servers' output to explain why.
wait_for_port() {
    if python3 - "$1" <<'EOF'
import socket, sys, time
deadline = time.time() + 10
while time.time() < deadline:
    try:
        socket.create_connection(("127.0.0.1", int(sys.argv[1])), 0.2).close()
        sys.exit(0)
    except OSError:
        time.sleep(0.05)
sys.exit(1)
EOF
    then
        return 0
    fi
    echo "nothing started listening on port $1" >&2
    cat "$BATS_TEST_TMPDIR/bg.log" >&2 2>/dev/null
    return 1
}

# start_bg <command...>: run a server in the background, stopped in teardown.
# fd 3 is closed so bats does not wait for the process to exit.
start_bg() {
    "$@" >>"$BATS_TEST_TMPDIR/bg.log" 2>&1 3>&- &
    BG_PIDS+=("$!")
}

# start_static_server <port>: a plain HTTP server where / answers 200
# and any other path answers 404
start_static_server() {
    local root="$BATS_TEST_TMPDIR/www"
    mkdir -p "$root"
    echo "ok" > "$root/index.html"
    start_bg python3 "$BATS_TEST_DIRNAME/static_server.py" "$1" "$root"
    wait_for_port "$1"
}

stop_bg() {
    local pid
    for pid in "${BG_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    BG_PIDS=()
}
