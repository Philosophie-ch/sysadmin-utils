# Sourced by Alexandria sysadmin scripts. Do not execute directly.

# Override ALEXANDRIA_LOCAL_PORT if tunnel.sh wrote an active port file
_tunnel_port_file="$(dirname "${BASH_SOURCE[0]}")/.tunnel-port"
if [ -f "$_tunnel_port_file" ]; then
  ALEXANDRIA_LOCAL_PORT=$(cat "$_tunnel_port_file")
fi
unset _tunnel_port_file

print_target_banner() {
  local port="$1"
  if pgrep -fa "ssh" 2>/dev/null | grep -qE "\b${port}:localhost"; then
    echo "=> Target: PROD (SSH tunnel active on port ${port})"
  else
    echo "=> INFO: Target is LOCAL DEV — no SSH tunnel on port ${port}"
  fi
}
