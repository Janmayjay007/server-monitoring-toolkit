#!/usr/bin/env python3
"""
Lightweight Web Dashboard Server for Server Monitoring Toolkit
Zero dependencies - uses standard Python 3 libraries.
"""

import http.server
import json
import os
import platform
import socketserver
import subprocess
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
WEB_DIR = os.path.dirname(os.path.abspath(__file__))


def get_disk_stats():
    try:
        st = os.statvfs("/")
        total = st.f_blocks * st.f_frsize
        free = st.f_bavail * st.f_frsize
        used = total - free
        pct = round((used / total) * 100, 1) if total > 0 else 0
        return {
            "mount": "/",
            "total_gb": round(total / (1024**3), 1),
            "used_gb": round(used / (1024**3), 1),
            "free_gb": round(free / (1024**3), 1),
            "percent": pct,
        }
    except Exception as e:
        return {"error": str(e), "percent": 0}


def get_memory_stats():
    total_mb = 0
    used_mb = 0
    free_mb = 0
    percent = 0

    if os.path.exists("/proc/meminfo"):
        try:
            mem = {}
            with open("/proc/meminfo", "r") as f:
                for line in f:
                    parts = line.split(":")
                    if len(parts) == 2:
                        key = parts[0].strip()
                        val = int(parts[1].split()[0])
                        mem[key] = val
            total_kb = mem.get("MemTotal", 0)
            avail_kb = mem.get(
                "MemAvailable",
                mem.get("MemFree", 0)
                + mem.get("Buffers", 0)
                + mem.get("Cached", 0),
            )
            used_kb = total_kb - avail_kb
            total_mb = round(total_kb / 1024)
            free_mb = round(avail_kb / 1024)
            used_mb = round(used_kb / 1024)
            if total_mb > 0:
                percent = round((used_mb / total_mb) * 100, 1)
        except Exception:
            pass

    elif platform.system() == "Darwin":
        try:
            hw_mem = int(
                subprocess.check_output(
                    ["sysctl", "-n", "hw.memsize"]
                ).strip()
            )
            vm = subprocess.check_output(["vm_stat"]).decode("utf-8")
            stats = {}
            for line in vm.splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    stats[k.strip()] = v.strip().replace(".", "")

            page_size = 16384
            p_free = int(stats.get("Pages free", 0))
            p_inactive = int(stats.get("Pages inactive", 0))
            p_spec = int(stats.get("Pages speculative", 0))

            avail_bytes = (p_free + p_inactive + p_spec) * page_size
            used_bytes = max(0, hw_mem - avail_bytes)

            total_mb = round(hw_mem / (1024**2))
            used_mb = round(used_bytes / (1024**2))
            free_mb = round(avail_bytes / (1024**2))
            if total_mb > 0:
                percent = round((used_mb / total_mb) * 100, 1)
        except Exception:
            pass

    return {
        "total_mb": total_mb,
        "used_mb": used_mb,
        "free_mb": free_mb,
        "percent": percent,
    }


def get_services():
    target_services = ["nginx", "ssh", "cron", "docker"]
    results = []
    has_systemctl = (
        subprocess.call(
            ["which", "systemctl"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        == 0
    )

    for svc in target_services:
        is_active = False
        if has_systemctl:
            # Check systemctl
            ret = subprocess.call(
                ["systemctl", "is-active", "--quiet", svc],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            is_active = ret == 0
        else:
            # Fallback process check
            ret = subprocess.call(
                ["pgrep", "-f", svc],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            is_active = ret == 0

        results.append(
            {
                "name": svc,
                "status": "active" if is_active else "inactive",
                "running": is_active,
            }
        )
    return results


def get_system_info():
    uptime_str = "Unknown"
    try:
        out = subprocess.check_output(["uptime"]).decode("utf-8").strip()
        if "up" in out:
            uptime_str = out.split("up")[1].split(",")[0].strip()
    except Exception:
        pass

    load_avg = [0.0, 0.0, 0.0]
    try:
        load_avg = [round(x, 2) for x in os.getloadavg()]
    except Exception:
        pass

    return {
        "hostname": platform.node(),
        "os": f"{platform.system()} {platform.release()}",
        "cores": os.cpu_count() or 1,
        "uptime": uptime_str,
        "load": load_avg,
    }


def get_top_processes(limit=10):
    try:
        cmd = ["ps", "-eo", "pid,user,%cpu,%mem,comm"]
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
        lines = out.strip().split("\n")
        procs = []
        for line in lines[1:]:
            parts = line.strip().split(None, 4)
            if len(parts) >= 5:
                try:
                    pid = int(parts[0])
                    user = parts[1]
                    cpu = float(parts[2])
                    mem = float(parts[3])
                    raw_cmd = parts[4].strip()
                    comm = os.path.basename(raw_cmd) if "/" in raw_cmd else raw_cmd
                    procs.append({
                        "pid": pid,
                        "user": user,
                        "cpu": cpu,
                        "mem": mem,
                        "command": comm or raw_cmd,
                    })
                except (ValueError, IndexError):
                    continue

        top_by_cpu = sorted(procs, key=lambda x: x["cpu"], reverse=True)[:limit]
        top_by_mem = sorted(procs, key=lambda x: x["mem"], reverse=True)[:limit]

        return {
            "by_cpu": top_by_cpu,
            "by_mem": top_by_mem,
            "total_count": len(procs),
        }
    except Exception as e:
        return {
            "by_cpu": [],
            "by_mem": [],
            "total_count": 0,
            "error": str(e),
        }


class MonitorHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def do_GET(self):
        if self.path == "/api/stats":
            data = {
                "system": get_system_info(),
                "disk": get_disk_stats(),
                "memory": get_memory_stats(),
                "services": get_services(),
                "processes": get_top_processes(10),
            }
            body = json.dumps(data).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)
        else:
            super().do_GET()

    def log_message(self, format, *args):
        # Suppress routine GET logging for clean terminal
        pass


def main():
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), MonitorHandler) as httpd:
        print(f"\n🚀 Server Monitoring Dashboard active at:")
        print(f"   http://localhost:{PORT}")
        print(f"\nPress Ctrl+C to stop the dashboard.\n")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down web dashboard.")
            sys.exit(0)


if __name__ == "__main__":
    main()
