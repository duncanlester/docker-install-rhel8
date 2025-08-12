#!/bin/bash

# Jenkins Slave fapolicyd Setup Script
# Sets up fapolicyd rules for Jenkins slaves and monitors for additional denials

set -e

JENKINS_RULES_FILE="/etc/fapolicyd/rules.d/99-jenkins.rules"

echo "Setting up fapolicyd rules for Jenkins slave..."

# Create Jenkins-specific fapolicyd rules
cat <<EOF > "$JENKINS_RULES_FILE"
# Jenkins Slave fapolicyd Rules

# Java Runtime Environment (required for Jenkins agent)
allow perm=execute all : dir=/usr/bin/ name=java
allow perm=execute all : dir=/usr/lib/jvm/*/bin/ name=java
allow perm=execute all : dir=/opt/java/*/bin/ name=java

# Jenkins agent jar execution
allow perm=execute all : path=/tmp/jenkins-*.jar
allow perm=execute all : path=/home/*/jenkins-*.jar
allow perm=execute all : path=/var/lib/jenkins/jenkins-*.jar

# Common build tools
allow perm=execute all : dir=/usr/bin/ name=git
allow perm=execute all : dir=/usr/bin/ name=mvn
allow perm=execute all : dir=/usr/bin/ name=gradle
allow perm=execute all : dir=/usr/bin/ name=ant
allow perm=execute all : dir=/usr/bin/ name=make
allow perm=execute all : dir=/usr/bin/ name=gcc
allow perm=execute all : dir=/usr/bin/ name=g++
allow perm=execute all : dir=/usr/bin/ name=nodejs
allow perm=execute all : dir=/usr/bin/ name=node
allow perm=execute all : dir=/usr/bin/ name=npm
allow perm=execute all : dir=/usr/bin/ name=yarn

# Docker (if Jenkins slave runs Docker containers)
allow perm=execute all : dir=/usr/bin/ name=docker
allow perm=execute all : dir=/usr/bin/ name=dockerd
allow perm=execute all : dir=/usr/bin/ name=containerd
allow perm=execute all : dir=/usr/bin/ name=containerd-shim
allow perm=execute all : dir=/usr/bin/ name=containerd-shim-runc-v2
allow perm=execute all : dir=/usr/bin/ name=runc

# SSH and remote access
allow perm=execute all : dir=/usr/bin/ name=ssh
allow perm=execute all : dir=/usr/bin/ name=scp
allow perm=execute all : dir=/usr/bin/ name=rsync

# Archive and compression tools
allow perm=execute all : dir=/usr/bin/ name=tar
allow perm=execute all : dir=/usr/bin/ name=gzip
allow perm=execute all : dir=/usr/bin/ name=unzip
allow perm=execute all : dir=/usr/bin/ name=zip

# Text processing and utilities
allow perm=execute all : dir=/usr/bin/ name=sed
allow perm=execute all : dir=/usr/bin/ name=awk
allow perm=execute all : dir=/usr/bin/ name=grep
allow perm=execute all : dir=/usr/bin/ name=curl
allow perm=execute all : dir=/usr/bin/ name=wget

# Shell interpreters
allow perm=execute all : dir=/bin/ name=bash
allow perm=execute all : dir=/bin/ name=sh
allow perm=execute all : dir=/usr/bin/ name=python3
allow perm=execute all : dir=/usr/bin/ name=python
allow perm=execute all : dir=/usr/bin/ name=ruby
allow perm=execute all : dir=/usr/bin/ name=perl

# Jenkins workspace executables (dynamically created)
allow perm=execute all : dir=/var/lib/jenkins/workspace/*/
allow perm=execute all : path=/home/jenkins/workspace/*/
allow perm=execute all : path=/tmp/jenkins-*
EOF

echo "Reloading fapolicyd with new Jenkins rules..."
systemctl reload fapolicyd

echo "Jenkins fapolicyd rules have been added to $JENKINS_RULES_FILE"
echo ""
echo "To monitor for additional denials during Jenkins jobs, run:"
echo "  ./monitor-fapolicyd-jenkins.sh"
echo "  Enter rules file: 99-jenkins.rules"
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
