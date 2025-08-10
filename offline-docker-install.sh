#!/bin/bash
set -e


# 1. Prompt for RPM directory
read -rp "Enter the full path to the directory containing Docker RPMs: " REPO_DIR
if [ ! -d "$REPO_DIR" ]; then
	echo "Directory $REPO_DIR does not exist. Exiting."
	exit 1
fi

REPO_NAME="docker-offline"
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
cat <<EOF > /etc/fapolicyd/rules.d/99-docker.rules
allow perm=execute all : dir=/usr/bin/ name=docker
allow perm=execute all : dir=/usr/bin/ name=dockerd
allow perm=execute all : dir=/usr/bin/ name=containerd
allow perm=execute all : dir=/usr/bin/ name=containerd-shim
allow perm=execute all : dir=/usr/bin/ name=containerd-shim-runc-v2
allow perm=execute all : dir=/usr/bin/ name=runc
EOF


echo "Reloading fapolicyd..."
systemctl reload fapolicyd


# 8. Set fapolicyd to debug deny mode and update rules in real time
echo "Setting fapolicyd to debug deny mode and monitoring for denied actions..."
FAPOLICYD_CONF="/etc/fapolicyd/fapolicyd.conf"
RULES_FILE="/etc/fapolicyd/rules.d/99-docker.rules"
if [ -f "$FAPOLICYD_CONF" ]; then
	sed -i 's/^mode\s*=.*/mode = DEBUG/' "$FAPOLICYD_CONF"
	sed -i 's/^decision\s*=.*/decision = DENY/' "$FAPOLICYD_CONF"
else
	echo "Warning: $FAPOLICYD_CONF not found. Skipping debug deny mode setup."
fi

systemctl reload fapolicyd

# Start Docker before monitoring
echo "Enabling and starting Docker..."
systemctl enable --now docker
# Monitor denied actions for Docker-related binaries and update rules in real time
# Stop when all expected Docker binaries are allowed
EXPECTED_BINS=(
  /usr/bin/docker
  /usr/bin/dockerd
  /usr/bin/containerd
  /usr/bin/containerd-shim
  /usr/bin/containerd-shim-runc-v2
  /usr/bin/runc
)

echo "Monitoring for denied Docker-related actions. Will exit when all expected Docker binaries are allowed."

fapolicyd --debug-deny 2>&1 | \
while read -r line; do
	if echo "$line" | grep -q 'decide access=execute.*denied'; then
		BIN_PATH=$(echo "$line" | awk -F 'path=' '{if (NF>1) print $2}' | awk '{print $1}')
		for expected in "${EXPECTED_BINS[@]}"; do
			if [[ "$BIN_PATH" == "$expected" ]]; then
				if [ -n "$BIN_PATH" ] && ! grep -q "$BIN_PATH" "$RULES_FILE"; then
					BIN_NAME=$(basename "$BIN_PATH")
					echo "Adding allow rule for $BIN_PATH ($BIN_NAME)"
					echo "allow perm=execute all : dir=$(dirname $BIN_PATH)/ name=$BIN_NAME" >> "$RULES_FILE"
					systemctl reload fapolicyd
				fi
			fi
		done
		# Check if all expected binaries are now allowed
		all_allowed=true
		for expected in "${EXPECTED_BINS[@]}"; do
			if ! grep -q "$expected" "$RULES_FILE"; then
				all_allowed=false
				break
			fi
		done
		if $all_allowed; then
			echo "All expected Docker binaries are now allowed. Exiting monitor."
			break
		fi
	fi
done


echo "Offline Docker installation complete!"
