#!/bin/bash
set -e

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]
Deploy Docker offline installation to one or more RHEL8 machines

OPTIONS:
    -r, --repo-dir PATH     Directory containing Docker RPMs (required)
    -m, --machines FILE     File containing list of machines (one per line)
    -s, --single HOSTNAME   Install on a single machine
    -u, --user USERNAME     SSH username (default: current user)
    -k, --key PATH          SSH private key path (default: ~/.ssh/id_rsa)
    -p, --parallel N        Number of parallel installations (default: 3)
    -h, --help              Show this help message

EXAMPLES:
    $0 -r /path/to/rpms -s server1.example.com
    $0 -r /path/to/rpms -m machines.txt -u admin -p 5
    $0 --repo-dir /opt/docker-rpms --machines hostlist.txt

MACHINE LIST FILE FORMAT:
    server1.example.com
    server2.example.com
    192.168.1.100
    server3.example.com:2222  # Custom SSH port
EOF
}

# Default values
REPO_DIR=""
MACHINES_FILE=""
SINGLE_MACHINE=""
SSH_USER="$USER"
SSH_KEY="$HOME/.ssh/id_rsa"
PARALLEL_JOBS=3

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--repo-dir)
            REPO_DIR="$2"
            shift 2
            ;;
        -m|--machines)
            MACHINES_FILE="$2"
            shift 2
            ;;
        -s|--single)
            SINGLE_MACHINE="$2"
            shift 2
            ;;
        -u|--user)
            SSH_USER="$2"
            shift 2
            ;;
        -k|--key)
            SSH_KEY="$2"
            shift 2
            ;;
        -p|--parallel)
            PARALLEL_JOBS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$REPO_DIR" ]; then
    echo "Error: Repository directory is required (-r/--repo-dir)"
    usage
    exit 1
fi

if [ ! -d "$REPO_DIR" ]; then
    echo "Error: Directory $REPO_DIR does not exist"
    exit 1
fi

if [ -z "$MACHINES_FILE" ] && [ -z "$SINGLE_MACHINE" ]; then
    echo "Error: Either machines file (-m) or single machine (-s) must be specified"
    usage
    exit 1
fi

if [ -n "$MACHINES_FILE" ] && [ ! -f "$MACHINES_FILE" ]; then
    echo "Error: Machines file $MACHINES_FILE does not exist"
    exit 1
fi

# Check if SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    echo "Error: SSH key $SSH_KEY not found"
    exit 1
fi

REPO_NAME="docker-offline"
REPO_FILE="/etc/yum.repos.d/${REPO_NAME}.repo"

# Function to install Docker on a single machine
install_docker_on_machine() {
    local machine="$1"
    local host_port
    local hostname
    local port=22

    # Parse hostname and port
    if [[ "$machine" == *":"* ]]; then
        hostname="${machine%:*}"
        port="${machine#*:}"
    else
        hostname="$machine"
    fi

    echo "Starting installation on $hostname:$port..."

    # Create remote installation script
    local remote_script="/tmp/docker-install-remote-$$.sh"

    cat > "$remote_script" << 'REMOTE_SCRIPT_EOF'
#!/bin/bash
set -e

REPO_DIR="$1"
REPO_NAME="docker-offline"
REPO_FILE="/etc/yum.repos.d/${REPO_NAME}.repo"
REPO_FILE="/etc/yum.repos.d/${REPO_NAME}.repo"


# 2. Ensure createrepo is installed
if ! command -v createrepo &> /dev/null; then
	echo "createrepo not found. Installing createrepo..."
	dnf install -y createrepo
fi

# 3. Create local repo
echo "Creating local DNF repository..."
createrepo "$REPO_DIR"


# 4. Add local repo config
echo "Configuring local DNF repository..."
cat <<EOF > "$REPO_FILE"
[docker-offline]
name=Docker Offline Repo
baseurl=file://$REPO_DIR
enabled=1
gpgcheck=0
EOF


# 5. Clean and update DNF cache
dnf clean all
dnf makecache


# 6. Install Docker from local repo
echo "Installing Docker and related packages from local repository..."
dnf install -y --disablerepo="*" --enablerepo="${REPO_NAME}" \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	docker-compose-plugin \
	docker-scan-plugin \
	docker-buildx-plugin


# 7. Add fapolicyd rules for Docker binaries
echo "Adding fapolicyd rules for Docker..."

# Create Docker rules in a separate file
mkdir -p /etc/fapolicyd/rules.d
cat <<EOF > /etc/fapolicyd/rules.d/01-docker.rules
allow perm=execute all : path=/usr/bin/docker
allow perm=execute all : path=/usr/bin/dockerd
allow perm=execute all : path=/usr/bin/containerd
allow perm=execute all : path=/usr/bin/containerd-shim
allow perm=execute all : path=/usr/bin/containerd-shim-runc-v2
allow perm=execute all : path=/usr/bin/runc
EOF

echo "Docker rules created in /etc/fapolicyd/rules.d/01-docker.rules"
echo "NOTE: fapolicyd does not automatically load these rules."
echo "Docker may be blocked by fapolicyd until rules are configured."
echo ""

# 8. Test Docker and use fagenrules to capture any additional rules
echo "Testing Docker and monitoring for additional rules needed..."

# Create a simple Docker test script
cat > /tmp/test-docker.sh << 'TEST_SCRIPT_EOF'
#!/bin/bash
echo "Testing Docker functionality..."
systemctl enable --now docker
sleep 2
docker --version
docker info > /dev/null 2>&1
echo "Docker testing complete"
TEST_SCRIPT_EOF

chmod +x /tmp/test-docker.sh

# Check if fagenrules is available for auto-rule generation
if command -v fagenrules &> /dev/null; then
	echo "Using fagenrules to monitor and capture additional Docker rules..."
	
	# Set up temporary log for this session
	TEMP_LOG="/tmp/docker-test-$(date +%s).log"
	
	# Stop fapolicyd and start in debug-deny + permissive mode
	systemctl stop fapolicyd
	fapolicyd --debug-deny --permissive --log "$TEMP_LOG" &
	FAPOLICYD_PID=$!
	sleep 2
	
	# Run Docker tests
	/tmp/test-docker.sh
	
	# Generate any additional rules from the test session
	if [ -s "$TEMP_LOG" ]; then
		echo "Generating additional rules from Docker test session..."
		cat "$TEMP_LOG" | fagenrules >> /etc/fapolicyd/rules.d/01-docker.rules 2>/dev/null || true
		echo "Additional rules added to /etc/fapolicyd/rules.d/01-docker.rules"
	else
		echo "No additional rules needed from fagenrules monitoring"
	fi
	
	# Clean up and restart fapolicyd
	kill $FAPOLICYD_PID 2>/dev/null || true
	rm -f "$TEMP_LOG"
	systemctl start fapolicyd
else
	echo "fagenrules not available, running basic Docker test..."
	/tmp/test-docker.sh
fi

# Clean up test script
rm -f /tmp/test-docker.sh

echo "Docker installation completed on $(hostname)"
REMOTE_SCRIPT_EOF

    # Copy RPM directory to remote machine
    echo "Copying Docker RPMs to $hostname..."
    if ! scp -r -i "$SSH_KEY" -P "$port" -o StrictHostKeyChecking=no "$REPO_DIR" "${SSH_USER}@${hostname}:/tmp/docker-rpms/"; then
        echo "FAILED: Failed to copy RPMs to $hostname"
        rm -f "$remote_script"
        return 1
    fi

    # Copy and execute installation script
    echo "Copying installation script to $hostname..."
    if ! scp -i "$SSH_KEY" -P "$port" -o StrictHostKeyChecking=no "$remote_script" "${SSH_USER}@${hostname}:/tmp/docker-install.sh"; then
        echo "FAILED: Failed to copy installation script to $hostname"
        rm -f "$remote_script"
        return 1
    fi

    echo "Executing installation on $hostname..."
    if ssh -i "$SSH_KEY" -p "$port" -o StrictHostKeyChecking=no "${SSH_USER}@${hostname}" "sudo chmod +x /tmp/docker-install.sh && sudo /tmp/docker-install.sh /tmp/docker-rpms && sudo rm -f /tmp/docker-install.sh && sudo rm -rf /tmp/docker-rpms"; then
        echo "SUCCESS: Successfully installed Docker on $hostname"
    else
        echo "FAILED: Failed to install Docker on $hostname"
        rm -f "$remote_script"
        return 1
    fi

    # Clean up local temp script
    rm -f "$remote_script"
    return 0
}

# Main execution
echo "Docker Offline Installation for Multiple RHEL8 Machines"
echo "========================================================"
echo "Repository: $REPO_DIR"
echo "SSH User: $SSH_USER"
echo "SSH Key: $SSH_KEY"
echo "Parallel Jobs: $PARALLEL_JOBS"
echo ""

# Build machine list
machines=()
if [ -n "$SINGLE_MACHINE" ]; then
    machines=("$SINGLE_MACHINE")
    echo "Target: $SINGLE_MACHINE"
else
    echo "Loading machines from: $MACHINES_FILE"
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        machines+=("$line")
        echo "  - $line"
    done < "$MACHINES_FILE"
fi

echo ""
echo "Total machines: ${#machines[@]}"
echo ""

# Install Docker on all machines
successful=0
failed=0
failed_machines=()

echo "Starting installations..."
echo ""

# Use xargs for parallel execution
printf '%s\n' "${machines[@]}" | xargs -I {} -P "$PARALLEL_JOBS" -n 1 bash -c '
    if install_docker_on_machine "$1"; then
        echo "SUCCESS: $1"
    else
        echo "FAILED: $1"
        exit 1
    fi
' _ {}

# Count results (simplified since we can't easily track in parallel)
echo ""
echo "Installation Summary:"
echo "===================="
for machine in "${machines[@]}"; do
    # Simple connectivity test to verify Docker is running
    hostname="${machine%:*}"
    port="${machine#*:}"
    [[ "$port" == "$hostname" ]] && port=22

    echo -n "Checking $hostname... "
    if ssh -i "$SSH_KEY" -p "$port" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${SSH_USER}@${hostname}" "sudo systemctl is-active docker" &>/dev/null; then
        echo "Docker running"
        ((successful++))
    else
        echo "Docker not running"
        ((failed++))
        failed_machines+=("$machine")
    fi
done

echo ""
echo "Results:"
echo "  Successful: $successful"
echo "  Failed: $failed"

if [ $failed -gt 0 ]; then
    echo ""
    echo "Failed machines:"
    for machine in "${failed_machines[@]}"; do
        echo "  - $machine"
    done
    exit 1
fi

echo ""
echo "All installations completed successfully!"
