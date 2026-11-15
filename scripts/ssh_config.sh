#!/usr/bin/env bash
# Writes the repo's .ssh/config (gitignored) with a host entry for a pod, so ssh uses the
# repo's key and known_hosts and never touches ~/.ssh.
#
# usage: scripts/ssh_config.sh <name> <host> <port>
#   host, port: the direct (not proxy) connection from `runpodctl ssh info <pod id>`
# then:  ssh -F .ssh/config <name>
set -euo pipefail

name=$1 host=$2 port=$3
dir="$(cd "$(dirname "$0")/.." && pwd)/.ssh" # absolute: ssh resolves relative paths oddly

cat >"$dir/config" <<CONF
# written by scripts/ssh_config.sh; a new pod gets a new host and port, so rerun it
Host $name
  HostName $host
  Port $port
  User root
  IdentityFile $dir/runpod_ed25519
  IdentitiesOnly yes
  UserKnownHostsFile $dir/known_hosts
  # pods are new hosts each time; record the key on first connect, refuse a changed one
  StrictHostKeyChecking accept-new
CONF
chmod 600 "$dir/config"
# a new pod can land on a host:port an old pod used, with a new host key
[[ -f $dir/known_hosts ]] && ssh-keygen -q -R "[$host]:$port" -f "$dir/known_hosts" 2>/dev/null || true
echo "wrote $dir/config: ssh -F .ssh/config $name"
