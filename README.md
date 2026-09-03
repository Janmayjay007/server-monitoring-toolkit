# Server Monitoring Toolkit (Bash)

A small, mode-based Bash CLI tool for checking basic server health: disk usage and service status. Built as a capstone project to apply core Bash scripting fundamentals — variables, functions, conditionals, loops, and command-line argument handling — into a single reusable tool.

## What it does

```bash
./monitor.sh disk       # check root filesystem disk usage
./monitor.sh services   # check status of nginx, ssh, and cron
./monitor.sh all        # run both checks
./monitor.sh            # no/invalid argument — prints usage and exits non-zero
```

## Example output

```
$ ./monitor.sh disk
Disk usage: 52%
disk usage is healthy.

$ ./monitor.sh services
nginx: active
ssh: inactive
cron: active

$ ./monitor.sh
usage: ./monitor.sh [disk|services|all]
```

## How it works

- **`check_disk()`** — pulls the root filesystem's usage percentage via a `df` → `awk` → `tr` pipeline, strips the `%` symbol so the value can be compared numerically, and warns if usage exceeds 85%.
- **`check_services()`** — loops over a list of service names and uses `systemctl is-active --quiet` to report each one's status without printing systemd's own verbose output.
- **Argument handling** — `$1` (the script's first command-line argument) is checked against `disk`, `services`, and `all`. Anything else — including no argument at all — falls through to a usage message and an `exit 1`, so the script fails predictably instead of doing nothing silently.
- **`set -e`** — the script stops immediately if any command fails, rather than continuing on and potentially reporting misleading results.

## Design notes

- Each check is its own function rather than one long block of top-level code — easier to extend (e.g. add a `memory` mode) without touching unrelated logic.
- String comparisons use `=` rather than `==` inside `[ ]`, since `=` is the POSIX-portable form and works across shells beyond just bash.
- The disk-usage pipeline (`df / | tail -1 | awk '{print $5}' | tr -d '%'`) is a pattern worth reusing: `df /` isolates the root filesystem, `tail -1` drops the header row, `awk` extracts the relevant column, and `tr -d` removes a non-numeric character so the result can be used in a numeric comparison (`-gt`).

## Skills demonstrated

- Bash functions, conditionals, loops, and command-line argument parsing
- Building small, composable pipelines with `df`, `awk`, `tr`, and `tail`
- Defensive scripting: `set -e`, input validation, and a clear usage/error path for invalid input
- Debugging real syntax errors independently (missing spaces around `[`, incorrect quoting, a corrupted mid-edit file) using error messages and `cat -n` rather than guessing

## Possible extensions

- Add a `memory` mode using `free -h`
- Accept a configurable disk-usage threshold as a second argument
- Write results to a log file with a timestamp instead of just printing to stdout
