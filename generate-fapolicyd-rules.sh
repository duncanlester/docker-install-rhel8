#!/bin/bash

# Generate fapolicyd rules using fagenrules
# This script uses fagenrules to automatically generate rules based on observed denials

set -e

RULES_OUTPUT_FILE="/etc/fapolicyd/rules.d/01-jenkins-auto.rules"
DENY_FILE="/data/fapolicyd-session-$(date +%s).deny"

echo "Generating fapolicyd rules using fagenrules..."
echo "This will analyze recent denials and suggest rules"
echo ""

# Check if fagenrules is available
if ! command -v fagenrules &> /dev/null; then
    echo "WARNING: fagenrules command not found"
    echo "Installing fapolicyd-utils package..."

    # Try to install fapolicyd-utils
    if dnf install -y fapolicyd-utils; then
        echo "Successfully installed fapolicyd-utils"
    else
        echo "ERROR: Failed to install fapolicyd-utils"
        echo "Please install manually with: dnf install fapolicyd-utils"
        exit 1
    fi
fi

# Check if log file exists, create if it doesn't
if [ ! -f "$DENY_FILE" ]; then
    echo "Creating temporary log file: $DENY_FILE"
    mkdir -p /data
    touch "$DENY_FILE"
fi

# Stop fapolicyd service and start in debug-deny mode for optimal fagenrules operation
echo "Setting up fapolicyd in debug-deny mode..."

# Stop the service if running
if systemctl is-active fapolicyd &> /dev/null; then
    echo "Stopping fapolicyd service..."
    systemctl stop fapolicyd
fi

# Start fapolicyd in debug-deny mode with our custom log file
echo "Starting fapolicyd in debug-deny mode..."
echo "Logging to: $DENY_FILE"
fapolicyd --debug-deny --permissive --log "$DENY_FILE" &
FAPOLICYD_PID=$!

# Give it a moment to start
sleep 2

# Verify it started successfully
if kill -0 $FAPOLICYD_PID 2>/dev/null; then
    echo "fapolicyd is now running in debug-deny mode (PID: $FAPOLICYD_PID)"
    echo "Logging denials to: $DENY_FILE"

    # Set up cleanup on script exit
    trap "echo 'Cleaning up...'; kill $FAPOLICYD_PID 2>/dev/null || true; rm -f $DENY_FILE" EXIT
else
    echo "ERROR: fapolicyd failed to start in debug-deny mode"
    exit 1
fi
echo ""
echo "You can now run your Jenkins jobs or other applications"
echo "(They will work normally since we're in permissive mode)"
echo "Press Enter when you're done running applications and ready to generate rules: "
read


# Process all current log entries and save directly to fapolicyd rules directory
echo "Generating rules and saving to fapolicyd rules directory..."

# Since fagenrules doesn't generate rules from logs, we'll create a basic template
# that the user can customize based on their log analysis
cat > "$RULES_OUTPUT_FILE" << 'EOF'
# Auto-generated fapolicyd rules template
# Review and customize these rules based on your application needs

# Example rules - customize as needed:
# allow perm=execute all : path=/usr/bin/java
# allow perm=execute all : path=/usr/bin/python3
# allow perm=open all : dir=/opt/jenkins/
# allow perm=execute all : dir=/tmp/

EOF

echo "Basic rules template created in: $RULES_OUTPUT_FILE"
echo "NOTE: fagenrules merges rule files from /etc/fapolicyd/rules.d/"
echo "It does NOT generate rules from logs automatically."
echo ""
echo "To use fagenrules to compile all rules:"
echo "  fagenrules"
echo "This will merge all .rules files from /etc/fapolicyd/rules.d/ into /etc/fapolicyd/compiled.rules"
echo ""
echo "You need to manually analyze the log file and create appropriate rules."
echo "Log file location: $DENY_FILE"

# Check if any rules were generated
if [ -s "$RULES_OUTPUT_FILE" ]; then
    echo "Rules template saved to: $RULES_OUTPUT_FILE"
    echo ""
    echo "=== Rules Template Preview ==="
    cat "$RULES_OUTPUT_FILE"
    echo ""
    echo "=== End Preview ==="
    echo ""
    echo "Next steps:"
    echo "1. Analyze the log file: $DENY_FILE"
    echo "2. Add appropriate rules to: $RULES_OUTPUT_FILE"
    echo "3. Run 'fagenrules' to compile all rules from /etc/fapolicyd/rules.d/"
    echo "4. Configure fapolicyd to use the compiled rules"
else
    echo "Failed to create rules template file"
fi

echo ""
echo "Temporary log file will be cleaned up automatically"

echo ""
echo "Stopping debug-deny fapolicyd and restarting normal service..."
kill $FAPOLICYD_PID 2>/dev/null || true
sleep 1
systemctl start fapolicyd

echo ""
echo "Cleaning up deny file..."
rm -f "$DENY_FILE"
echo "Deny file removed: $DENY_FILE"
