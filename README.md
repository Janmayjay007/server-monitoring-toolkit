# 🚀 Server Monitoring Toolkit

<div align="center">

[![Bash 3.2+](https://img.shields.io/badge/Bash-3.2%2B-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS-0078D6.svg?logo=linux&logoColor=white)](#compatibility)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/)

**An interactive, lightweight terminal health & diagnostics CLI for modern servers and dev workstations.**

[Features](#-key-features) •
[Quick Start](#-quick-start) •
[Interactive TUI](#-interactive-mode) •
[CLI Automation](#-cli-usage--flags) •
[Architecture](#-architecture--design)

</div>

---

## 🖥️ Terminal Showcase

### Interactive Terminal Menu
```text
  ___ ___ _____   _____ ___   __  __  ___  _  _ ___ _____ ___  ___ 
 / __| __| _ \ \ / / __| _ \ |  \/  |/ _ \| \| |_ _|_   _/ _ \| _ \
 \__ \ _||   /\ V /| _||   / | |\/| | (_) | .` || |  | || (_) |   /
 |___/___|_|_\ \_/ |___|_|_\ |_|  |_|\___/|_|\_|___| |_| \___/|_|_\

 Server Monitoring Toolkit v2.0.0
 Host: prod-web-01.internal  •  Time: 2026-09-13 01:42:00
─────────────────────────────────────────────────────────────
 Select a diagnostic option:

   [1] 💾 Check Disk Usage (Visual gauge & threshold)
   [2] 🧠 Check Memory & Swap (RAM utilization)
   [3] ⚙️  Check Service Health (Nginx, SSH, Cron, etc.)
   [4] ⚡ Check System & CPU Load (Uptime, OS, Cores)
   [5] 📊 Run Complete Health Audit (All checks in one)
   [6] ⏱️  Live Dashboard Watch Mode (Auto-refresh)
   [7] 🛠️  Configure Alert Thresholds
   [q] 🚪 Exit Toolkit

─────────────────────────────────────────────────────────────
Enter choice [1-7, q]: 
```

### Visual Diagnostics Output
```text
▸ Disk Filesystem Usage
─────────────────────────────────────────────────────────────
  Mount Point:   / (/dev/nvme0n1p1)
  Capacity:      18 GB used / 80 GB total (59 GB free)
  Utilization:   [█████░░░░░░░░░░░░░░░░░░░]  23%

  Status: [  OK  ] Disk filesystem health is normal.

▸ System Memory & Swap
─────────────────────────────────────────────────────────────
  Physical RAM:  2140 MB used / 7920 MB total (5780 MB free)
  Utilization:   [██████░░░░░░░░░░░░░░░░░░]  27%

  Status: [  OK  ] System memory allocation is healthy.

▸ Key Service Health Status
─────────────────────────────────────────────────────────────
  Engine: systemd (systemctl)

  SERVICE          STATUS           HEALTH
  ──────────────────────────────────────────
  nginx            [ ACTIVE ]     Running
  ssh              [ ACTIVE ]     Running
  cron             [ ACTIVE ]     Running
  docker           [ ACTIVE ]     Running
```

---

## ✨ Key Features

- 🎮 **Interactive TUI Menu**: Launch with zero arguments to access an intuitive menu with colored indicators and on-demand diagnostics.
- 📊 **Visual ASCII Progress Bars**: Color-graded capacity meters (🟢 Green for healthy, 🟡 Amber for warning, 🔴 Crimson for critical).
- 🧠 **Cross-Platform Memory Inspection**: Deep inspection across Linux (`/proc/meminfo` and `free`) and macOS Darwin (`vm_stat` / `sysctl`).
- ⚙️ **Multi-Engine Service Auditing**: Automatically inspects system services via `systemctl` (systemd), `service` (SysV), or process table inspection.
- ⚡ **CPU & System Load Intelligence**: Checks uptime, OS release, CPU cores, and alerts if 1-minute load exceeds physical processor capacity.
- ⏱️ **Live Watch Dashboard**: Real-time auto-refreshing monitor (`--watch`) for stress testing and monitoring live incidents.
- 🤖 **CI/CD & Scripting Ready**: Supports standard subcommands and silent non-interactive piping for cron jobs or automated alert webhooks.

---

## ⚡ Quick Start

### 1. Clone & Permissions
```bash
git clone https://github.com/your-username/server-monitoring-toolkit.git
cd server-monitoring-toolkit
chmod +x monitor.sh
```

### 2. Launch Interactive Menu
```bash
./monitor.sh
```

---

## 💻 CLI Usage & Flags

For automation, cron jobs, or headless servers, invoke `monitor.sh` directly with subcommands:

| Subcommand | Description | Example |
| :--- | :--- | :--- |
| *(none)* / `-i` | Launch the full interactive TUI menu | `./monitor.sh` |
| `all` | Execute all diagnostics sequentially in one report | `./monitor.sh all` |
| `disk` | Check root filesystem utilization against threshold | `./monitor.sh disk` |
| `memory` / `mem` | Check RAM utilization and memory pressure | `./monitor.sh memory` |
| `services` / `svc` | Inspect background system services | `./monitor.sh services` |
| `system` / `cpu` | View OS info, CPU cores, uptime, and load averages | `./monitor.sh system` |
| `-w`, `--watch [N]` | Run auto-refreshing live dashboard (default: 2s) | `./monitor.sh -w 5` |
| `-t`, `--threshold [N]` | Override disk alert threshold percentage (default: 85%) | `./monitor.sh disk -t 90` |
| `-h`, `--help` | Display usage manual and exit | `./monitor.sh --help` |

---

## 🛠️ Configuration & Environment Variables

You can customize operational defaults via environment variables:

```bash
# Set custom disk and memory alert thresholds
export DISK_THRESHOLD=90
export MEM_THRESHOLD=80

./monitor.sh all
```

To check custom services on demand:
```bash
./monitor.sh services postgresql redis-server nginx
```

---

## 🏗️ Architecture & Design

- **POSIX Portability (`df -P`)**: Uses POSIX-standard `df -P /` to prevent line-wrapping errors on long volume identifiers or LVM configurations.
- **Bash 3.2+ Universal Compatibility**: Implemented without Bash 4+ associative arrays to ensure zero-dependency execution on both default macOS (`/bin/bash`) and Linux distros.
- **ANSI Color Protection**: Automatically detects whether stdout is an interactive TTY (`[ -t 1 ]`); disables ANSI escape codes when piping to files or logging systems.
- **Defensive Error Handling**: Uses proper variable quoting and non-zero exit codes on failure paths to prevent misleading test results.

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/).

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.
