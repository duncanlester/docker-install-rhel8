#!/bin/bash

# Jenkins Slave fapolicyd Setup Script
# Sets up fapolicyd rules for Jenkins slaves and monitors for additional denials

set -e

JENKINS_RULES_FILE="/etc/fapolicyd/rules.d/01-jenkins.rules"

echo "Setting up fapolicyd rules for Jenkins slave..."

# Create Jenkins-specific fapolicyd rules
cat <<EOF > "$JENKINS_RULES_FILE"
# Jenkins Slave fapolicyd Rules

# PRIORITY: Broad /apps/jenkins/ rule at top (processed first)
allow perm=open all : dir=/apps/jenkins/
allow perm=execute all : dir=/apps/jenkins/

# Java Runtime Environment (required for Jenkins agent)
allow perm=open all : dir=/usr/bin/ ftype=application/x-executable
allow perm=execute all : dir=/usr/bin/ ftype=application/x-executable
allow perm=open all : dir=/usr/lib/jvm/ ftype=application/x-executable
allow perm=execute all : dir=/usr/lib/jvm/ ftype=application/x-executable
allow perm=open all : dir=/opt/java/ ftype=application/x-executable
allow perm=execute all : dir=/opt/java/ ftype=application/x-executable

# Jenkins agent jar execution (directory-based for better coverage)
allow perm=open all : dir=/tmp/ ftype=application/java-archive
allow perm=execute all : dir=/tmp/ ftype=application/java-archive
allow perm=open all : dir=/home/ ftype=application/java-archive
allow perm=execute all : dir=/home/ ftype=application/java-archive
allow perm=open all : dir=/var/lib/jenkins/ ftype=application/java-archive
allow perm=execute all : dir=/var/lib/jenkins/ ftype=application/java-archive

# Jenkins cache directory WAR files (all subdirectories)
allow perm=open all : dir=/var/cache/jenkins/ ftype=application/java-archive
allow perm=execute all : dir=/var/cache/jenkins/ ftype=application/java-archive
allow perm=open all : dir=/var/cache/jenkins/ ftype=application/x-executable
allow perm=execute all : dir=/var/cache/jenkins/ ftype=application/x-executable
allow perm=open all : dir=/var/cache/jenkins/ ftype=application/x-sharedlib
allow perm=execute all : dir=/var/cache/jenkins/ ftype=application/x-sharedlib
# Temporary broad rule for debugging
allow perm=open all : dir=/var/cache/jenkins/
allow perm=execute all : dir=/var/cache/jenkins/

# Additional application directories  
allow perm=open all : dir=/apps/jenkins/ ftype=application/x-sharedlib
allow perm=execute all : dir=/apps/jenkins/ ftype=application/x-sharedlib
allow perm=open all : dir=/apps/jenkins/ ftype=application/java-archive
allow perm=execute all : dir=/apps/jenkins/ ftype=application/java-archive
allow perm=open all : dir=/apps/jenkins/ ftype=application/x-executable
allow perm=execute all : dir=/apps/jenkins/ ftype=application/x-executable
allow perm=execute all : dir=/data/ ftype=application/java-archive

# Common build tools
allow perm=execute all : dir=/usr/bin/ ftype=application/x-executable
allow perm=execute all : dir=/usr/local/bin/ ftype=application/x-executable

# Docker (if Jenkins slave runs Docker containers)
allow perm=execute all : path=/usr/bin/docker
allow perm=execute all : path=/usr/bin/dockerd
allow perm=execute all : path=/usr/bin/containerd
allow perm=execute all : path=/usr/bin/containerd-shim*
allow perm=execute all : path=/usr/bin/runc

# Core shell interpreters (not covered by /usr/bin/ directory rule)
allow perm=execute all : path=/bin/bash
allow perm=execute all : path=/bin/sh

# Jenkins workspace executables (dynamically created)
allow perm=execute all : dir=/var/lib/jenkins/workspace/ ftype=application/x-executable
allow perm=execute all : dir=/home/jenkins/workspace/ ftype=application/x-executable

# Specific Jenkins temp patterns (more secure than broad /tmp/ access)
allow perm=execute all : path=/tmp/jenkins-*
allow perm=execute all : path=/tmp/workspace-*
allow perm=execute all : path=/tmp/build-*

# Windstone-specific rules
allow perm=execute all : path=/usr/bin/windstone
allow perm=execute all : path=/usr/local/bin/windstone
allow perm=execute all : dir=/opt/windstone/ ftype=application/x-executable
allow perm=execute all : path=/tmp/windstone-*
allow perm=execute all : dir=/var/lib/windstone/ ftype=application/x-executable
allow perm=execute all : dir=/home/*/windstone/ ftype=application/x-executable

# Additional /tmp/ coverage for build tools (more specific patterns)
allow perm=execute all : dir=/tmp/ ftype=application/x-sharedlib
allow perm=execute all : dir=/tmp/ ftype=application/x-executable

EOF

echo "Reloading fapolicyd with new Jenkins rules..."
systemctl restart fapolicyd

echo "Jenkins fapolicyd rules have been added to $JENKINS_RULES_FILE"
echo ""
echo "To monitor for additional denials during Jenkins jobs, run:"
echo "  ./monitor-fapolicyd-jenkins.sh"
echo "  Enter rules file: 01-jenkins.rules"
echo "  Enter service: jenkins"
echo ""
echo "Key directories to watch for denials:"
echo "  - Java binaries: /usr/lib/jvm/*/bin/"
echo "  - Jenkins workspace: /var/lib/jenkins/workspace/"
echo "  - Temporary files: /tmp/jenkins-*"
echo "  - Build tool caches: ~/.m2/, ~/.gradle/, ~/.npm/"
echo ""
echo "Common additional rules you might need:"
echo "  - Custom build scripts in workspace directories"
echo "  - Downloaded dependencies and tools"
echo "  - Compiled binaries from build processes"
