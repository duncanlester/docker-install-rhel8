#!/bin/bash

# Prompt user for rules file path
read -rp "Enter the full path for the fapolicyd rules file to update [/etc/fapolicyd/rules.d/99-auto-allow.rules]: " RULES_FILE
RULES_FILE=${RULES_FILE:-/etc/fapolicyd/rules.d/99-auto-allow.rules}

echo "Running fapolicyd in --debug-deny mode. Press Ctrl+C to stop."

# Run fapolicyd in debug-deny mode and parse output for denied actions
fapolicyd --debug-deny 2>&1 | \
while read -r line; do
    if echo "$line" | grep -q 'decide access=execute.*denied'; then
        BIN_PATH=$(echo "$line" | awk -F 'path=' '{if (NF>1) print $2}' | awk '{print $1}')
        if [ -n "$BIN_PATH" ] && ! grep -q "$BIN_PATH" "$RULES_FILE"; then
            BIN_NAME=$(basename "$BIN_PATH")
            echo "Adding allow rule for $BIN_PATH ($BIN_NAME)"
            echo "allow perm=execute all : dir=$(dirname $BIN_PATH)/ name=$BIN_NAME" >> "$RULES_FILE"
            systemctl reload fapolicyd
        fi
    fi
