#!/bin/bash

# Server Monitoring Toolkit
# Usage: ./monitor.sh [disk|services|all]

set -e

check_disk() {
    usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')

    echo "Disk usage: $usage%"

    if [ "$usage" -gt 85 ]; then
        echo "WARNING: Disk usage is above 85%!"
    else
        echo "Disk usage is healthy."
    fi
}

check_services() {
    services="nginx ssh cron"

    for service in $services
    do
        if systemctl is-active --quiet "$service"; then
            echo "$service: active"
        else
            echo "$service: inactive"
        fi
    done
}

if [ "$1" = "disk" ]; then
    check_disk
elif [ "$1" = "services" ]; then
    check_services
elif [ "$1" = "all" ]; then
    check_disk
    check_services
else
    echo "usage: ./monitor.sh [disk|services|all]"
    exit 1
fi
