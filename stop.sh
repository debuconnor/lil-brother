#!/bin/bash
PID_FILE=".flutter.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "Not running."
    exit 0
fi

PID=$(cat "$PID_FILE")
kill "$PID" 2>/dev/null && echo "Stopped (PID $PID)." || echo "Process $PID not found."
rm -f "$PID_FILE"
