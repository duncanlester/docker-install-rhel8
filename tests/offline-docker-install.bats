#!/usr/bin/env bats

# Test: offline-docker-install.sh should exit if RPM directory does not exist
@test "Exit if RPM directory does not exist" {
  run bash ../offline-docker-install.sh <<< "/tmp/nonexistent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist. Exiting."* ]]
}

# Test: offline-docker-install.sh should install createrepo if missing
@test "Install createrepo if missing" {
  # Simulate missing createrepo
  PATH_BACKUP="$PATH"
  PATH="/tmp/empty:":$PATH
  mkdir -p /tmp/docker-rpms-test
  run bash ../offline-docker-install.sh <<< "/tmp/docker-rpms-test"
  PATH="$PATH_BACKUP"
  [[ "$output" == *"createrepo not found. Installing createrepo..."* ]]
  rm -rf /tmp/docker-rpms-test
}

# Test: offline-docker-install.sh should create repo config file
@test "Create repo config file" {
  mkdir -p /tmp/docker-rpms-test
  run bash ../offline-docker-install.sh <<< "/tmp/docker-rpms-test"
  [ -f /etc/yum.repos.d/docker-offline.repo ]
  grep -q "baseurl=file:///tmp/docker-rpms-test" /etc/yum.repos.d/docker-offline.repo
  rm -rf /tmp/docker-rpms-test
}

# Test: offline-docker-install.sh should add fapolicyd rules for Docker
@test "Add fapolicyd rules for Docker" {
  mkdir -p /tmp/docker-rpms-test
  run bash ../offline-docker-install.sh <<< "/tmp/docker-rpms-test"
  [ -f /etc/fapolicyd/rules.d/99-docker.rules ]
  grep -q "allow perm=execute all : dir=/usr/bin/ name=docker" /etc/fapolicyd/rules.d/99-docker.rules
  grep -q "allow perm=execute all : dir=/usr/bin/ name=containerd" /etc/fapolicyd/rules.d/99-docker.rules
  rm -rf /tmp/docker-rpms-test
}

# Test: offline-docker-install.sh should set fapolicyd to debug deny mode
@test "Set fapolicyd to debug deny mode" {
  mkdir -p /tmp/docker-rpms-test
  echo -e "mode = ENFORCE\ndecision = ALLOW" > /tmp/fapolicyd.conf
  cp /tmp/fapolicyd.conf /etc/fapolicyd/fapolicyd.conf
  run bash ../offline-docker-install.sh <<< "/tmp/docker-rpms-test"
  grep -q "mode = DEBUG" /etc/fapolicyd/fapolicyd.conf
  grep -q "decision = DENY" /etc/fapolicyd/fapolicyd.conf
  rm -rf /tmp/docker-rpms-test
}

# Test: offline-docker-install.sh should enable and start Docker
@test "Enable and start Docker" {
  mkdir -p /tmp/docker-rpms-test
  run bash ../offline-docker-install.sh <<< "/tmp/docker-rpms-test"
  systemctl is-enabled docker | grep -q enabled
  systemctl is-active docker | grep -q active
  rm -rf /tmp/docker-rpms-test
}

# Test: offline-docker-install.sh should print completion message
@test "Print completion message" {
  mkdir -p /tmp/docker-rpms-test
  run bash ../offline-docker-install.sh <<< "/tmp/docker-rpms-test"
  [[ "$output" == *"Offline Docker installation complete!"* ]]
  rm -rf /tmp/docker-rpms-test
}
