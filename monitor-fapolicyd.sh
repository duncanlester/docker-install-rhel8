#!/bin/bash

# Simple fapolicyd denial monitor and rule generator
# Usage: ./monitor-fapolicyd.sh [service_name]

SERVICE="${1:-docker}"
RULES_FILE="/data/fapolicyd-rules-${SERVICE}.txt"
LOG_FILE="/data/fapolicyd-debug.log"

# Check root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: Must run as root"
   exit 1
fi

echo "Monitoring fapolicyd denials for: $SERVICE"
echo "Generated rules will be saved to: $RULES_FILE"

# Cleanup function
cleanup() {
    echo "Stopping monitoring..."
    pkill -f "fapolicyd --debug-deny"
    systemctl restart fapolicyd
    echo "Rules generated in: $RULES_FILE"
}
trap cleanup EXIT INT TERM

# Stop fapolicyd service
systemctl stop fapolicyd
sleep 2

# Start fapolicyd in debug mode
echo "Starting fapolicyd debug mode..."
fapolicyd --debug-deny --permissive > "$LOG_FILE" 2>&1 &
FAPOLICYD_PID=$!
sleep 3

echo "Fapolicyd debug started (PID: $FAPOLICYD_PID)"
echo "Restart your $SERVICE service now, then press Ctrl+C when done monitoring"

# Create denied paths file
echo "# All denied paths captured at $(date)" > "$RULES_FILE"
echo "# Review these denials and create rules only for paths that should be allowed" >> "$RULES_FILE"
echo "" >> "$RULES_FILE"

# Monitor for denials
tail -f "$LOG_FILE" | while read -r line; do
    if echo "$line" | grep -q 'denied.*path='; then
        echo "$line" >> "$RULES_FILE"
        BIN_PATH=$(echo "$line" | sed -n 's/.*path=\([^ ]*\).*/\1/p')
        echo "Denied: $BIN_PATH"
    fi
done
