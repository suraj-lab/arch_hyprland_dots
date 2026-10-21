#!/bin/bash
# Monitor context-mode crashes
while true; do
    if pgrep -f "context-mode" > /dev/null; then
        sleep 5
    else
        echo "[$(date)] context-mode not running" >> ~/.pi/context-mode-crashes.log
        sleep 5
    fi
done
