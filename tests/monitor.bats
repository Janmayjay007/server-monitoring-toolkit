#!/usr/bin/env bats

setup() {
    load test_helper
}

teardown() {
    stop_bg
}

# --- usage -------------------------------------------------------------

@test "help exits 0 and documents exit codes" {
    run "$MONITOR" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"2 CRITICAL"* ]]
}

@test "an unknown command exits 3 (UNKNOWN)" {
    run "$MONITOR" not-a-command
    [ "$status" -eq 3 ]
}

# --- thresholds --------------------------------------------------------

@test "disk is OK below the thresholds" {
    run env DISK_THRESHOLD=101 DISK_CRITICAL=101 "$MONITOR" disk
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OK]"* ]]
}

@test "disk warns past the warning threshold" {
    run env DISK_THRESHOLD=0 DISK_CRITICAL=101 "$MONITOR" disk
    [ "$status" -eq 1 ]
    [[ "$output" == *"[WARN]"* ]]
}

@test "disk is critical past the critical threshold" {
    run env DISK_THRESHOLD=0 DISK_CRITICAL=0 "$MONITOR" disk
    [ "$status" -eq 2 ]
    [[ "$output" == *"[CRIT]"* ]]
}

@test "memory is OK below the thresholds" {
    run env MEM_THRESHOLD=101 MEM_CRITICAL=101 "$MONITOR" memory
    [ "$status" -eq 0 ]
}

@test "memory warns past the warning threshold" {
    run env MEM_THRESHOLD=0 MEM_CRITICAL=101 "$MONITOR" memory
    [ "$status" -eq 1 ]
}

@test "memory is critical past the critical threshold" {
    run env MEM_THRESHOLD=0 MEM_CRITICAL=0 "$MONITOR" memory
    [ "$status" -eq 2 ]
}

# --- http --------------------------------------------------------------

@test "http: a healthy endpoint is OK" {
    port=$(free_port)
    start_static_server "$port"
    run "$MONITOR" http "http://127.0.0.1:$port/"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[UP]"*"200"* ]]
}

@test "http: a 404 is critical" {
    port=$(free_port)
    start_static_server "$port"
    run "$MONITOR" http "http://127.0.0.1:$port/missing"
    [ "$status" -eq 2 ]
    [[ "$output" == *"[FAIL]"*"404"* ]]
}

@test "http: nothing listening is critical (running is not the same as serving)" {
    port=$(free_port)
    run "$MONITOR" http "http://127.0.0.1:$port/"
    [ "$status" -eq 2 ]
    [[ "$output" == *"[DOWN]"*"connection refused"* ]]
}

@test "http: a slow answer is a warning" {
    port=$(free_port)
    start_static_server "$port"
    run env HTTP_SLOW_MS=0 "$MONITOR" http "http://127.0.0.1:$port/"
    [ "$status" -eq 1 ]
    [[ "$output" == *"[SLOW]"* ]]
}

@test "http: the worst of several URLs wins" {
    port=$(free_port)
    start_static_server "$port"
    run "$MONITOR" http "http://127.0.0.1:$port/" "http://127.0.0.1:$port/missing"
    [ "$status" -eq 2 ]
}

@test "http: no URL is a usage error" {
    run "$MONITOR" http
    [ "$status" -eq 3 ]
}

# --- ports -------------------------------------------------------------

@test "port: a listening port is OK" {
    port=$(free_port)
    start_static_server "$port"
    run "$MONITOR" port "$port"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OPEN]"* ]]
}

@test "port: a closed port is critical" {
    port=$(free_port)
    run "$MONITOR" port "127.0.0.1:$port"
    [ "$status" -eq 2 ]
    [[ "$output" == *"[CLOSED]"* ]]
}

@test "port: something that is not a port is UNKNOWN" {
    run "$MONITOR" port eighty
    [ "$status" -eq 3 ]
}

@test "an UNKNOWN never hides a CRITICAL" {
    port=$(free_port)
    run "$MONITOR" port eighty "$port"
    [ "$status" -eq 2 ]
}

# --- services and all --------------------------------------------------

@test "services: a service asked for by name that does not exist is critical" {
    run "$MONITOR" services definitely-not-a-real-service
    [ "$status" -eq 2 ]
}

@test "all: includes CHECK_URLS and exits with the worst result" {
    port=$(free_port)
    run env CHECK_URLS="http://127.0.0.1:$port/" "$MONITOR" all
    [ "$status" -eq 2 ]
    [[ "$output" == *"HTTP Health"* ]]
    [[ "$output" == *"Result: CRITICAL (exit 2)"* ]]
}

# --- web dashboard -----------------------------------------------------

@test "web: serves stats and listens on 127.0.0.1 only by default" {
    port=$(free_port)
    start_bg python3 "$SERVER" "$port"
    wait_for_port "$port"

    run curl -s -i "http://127.0.0.1:$port/api/stats"
    [ "$status" -eq 0 ]
    [[ "$output" == *"application/json"* ]]
    [[ "$output" == *'"disk"'* ]]
    [[ "$output" != *"Access-Control-Allow-Origin"* ]]

    run lsof -nP -iTCP:"$port" -sTCP:LISTEN
    [[ "$output" == *"127.0.0.1:$port"* ]]
    [[ "$output" != *"*:$port"* ]]
}
