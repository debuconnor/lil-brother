#!/bin/bash
PID_FILE=".flutter.pid"

if [ -f "$PID_FILE" ]; then
    echo "Already running (PID $(cat "$PID_FILE")). Run ./stop.sh first."
    exit 1
fi

nohup flutter run -d chrome --web-port=8080 > flutter.log 2>&1 &
echo $! > "$PID_FILE"
echo "Started (PID $!). Logs: flutter.log"
