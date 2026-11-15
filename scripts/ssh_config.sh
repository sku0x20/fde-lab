#!/usr/bin/env bash
# Writes the repo's .ssh/config (gitignored) with a host entry for a pod, so ssh uses the
# repo's key and known_hosts and never touches ~/.ssh.
#
# usage: scripts/ssh_config.sh <name> <pod id>
#   e.g. scripts/ssh_config.sh comfyui $(tofu -chdir=infra/comfyui output -raw pod_id)
# then:  ssh -F .ssh/config <name>
set -euo pipefail

name=$1 pod=$2
dir="$(cd "$(dirname "$0")/.." && pwd)/.ssh" # absolute: ssh resolves relative paths oddly

# the direct connection (public IP + mapped 22/tcp), from `runpodctl pod get`. `runpodctl
# ssh info` lagged behind it on a fresh pod. Empty until the container is running
read -r host port < <(runpodctl pod get "$pod" | python3 -I -c '
import json, sys
s = json.load(sys.stdin).get("ssh") or {}
print(s.get("ip", ""), s.get("port", ""))')
if [[ -z $host || -z $port ]]; then
  echo "pod $pod has no direct SSH address yet; wait for it to run and retry" >&2
  exit 1
fi

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
if [[ -f $dir/known_hosts ]]; then
  ssh-keygen -R "[$host]:$port" -f "$dir/known_hosts" >/dev/null 2>&1 || true
  rm -f "$dir/known_hosts.old"
fi
echo "wrote $dir/config ($host:$port): ssh -F .ssh/config $name"
