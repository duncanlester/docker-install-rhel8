#!/bin/bash

# Prompt for rules file and service
read -rp "Enter the fapolicyd rules file name (e.g., 99-docker.rules): " RULES_FILENAME
if [ -z "$RULES_FILENAME" ]; then
  echo "Rules file name is required. Exiting."
  exit 1
fi

RULES_FILE="/etc/fapolicyd/rules.d/$RULES_FILENAME"

read -rp "Enter the service name (eg docker, jenkins, or 'all' for all binaries): " SERVICE
if [ -z "$SERVICE" ]; then
  echo "Service name is required. Exiting."
  exit 1
fi

echo "Running fapolicyd in --debug-deny mode for service: $SERVICE."
echo "Will monitor denials for $SERVICE for 1 hour, checking every 30 seconds for no denials."

# Track when last denial occurred for this service and when monitoring started
LAST_DENIAL_TIME=$(date +%s)
START_TIME=$(date +%s)
NO_DENIAL_TIMEOUT=30
MAX_MONITOR_TIME=3600  # 1 hour

fapolicyd --debug-deny 2>&1 | \
while read -r line; do
        if echo "$line" | grep -q 'decide access=execute.*denied'; then
                BIN_PATH=$(echo "$line" | awk -F 'path=' '{if (NF>1) print $2}' | awk '{print $1}')
                BIN_NAME=$(basename "$BIN_PATH")
                
                # Check if this denial is related to our service
                SERVICE_RELATED=false
                if [[ "$BIN_NAME" == *"$SERVICE"* ]] || [[ "$BIN_PATH" == *"$SERVICE"* ]]; then
                        SERVICE_RELATED=true
                        LAST_DENIAL_TIME=$(date +%s)
                fi
                
                if [ -n "$BIN_PATH" ] && ! grep -q "$BIN_PATH" "$RULES_FILE"; then
                        echo "Adding allow rule for $BIN_PATH ($BIN_NAME)"
                        echo "allow perm=execute all : dir=$(dirname $BIN_PATH)/ name=$BIN_NAME" >> "$RULES_FILE"
                        systemctl reload fapolicyd
                fi
        fi
        
        CURRENT_TIME=$(date +%s)
        
        # Check if we've been monitoring for the max time (1 hour)
        TOTAL_TIME=$((CURRENT_TIME - START_TIME))
        if [ $TOTAL_TIME -gt $MAX_MONITOR_TIME ]; then
                echo "Maximum monitoring time of 1 hour reached."
                echo "Restarting fapolicyd and exiting monitor."
                systemctl restart fapolicyd
                break
        fi
        
        # Check if we should exit due to no service-specific denials
        TIME_DIFF=$((CURRENT_TIME - LAST_DENIAL_TIME))
        if [ $TIME_DIFF -gt $NO_DENIAL_TIMEOUT ]; then
                echo "No $SERVICE denials detected for $NO_DENIAL_TIMEOUT seconds."
                echo "Restarting fapolicyd and exiting monitor."
                systemctl restart fapolicyd
                break
        fi
