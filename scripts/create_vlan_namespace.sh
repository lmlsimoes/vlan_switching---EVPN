#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------
# Usage
# ------------------------------------------------------
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <parent_if> <vlan_id> <ipv4/subnet>"
  echo "Example: $0 eth1 10 10.10.10.10/24"
  exit 1
fi

PARENT_IF="$1"
VLAN_ID="$2"
IPV4_CIDR="$3"

NS_NAME="ns${VLAN_ID}"
VLAN_IF="${PARENT_IF}.${VLAN_ID}"

# ------------------------------------------------------
# Extract IPv4 octets
# ------------------------------------------------------
IPV4_ADDR="${IPV4_CIDR%%/*}"
IFS='.' read -r O1 O2 O3 O4 <<< "$IPV4_ADDR"

# ------------------------------------------------------
# Derived IPv6 (6to4-style, deterministic)
# ------------------------------------------------------
IPV6_ADDR="2002::${O1}:${O2}:${O3}:${O4}"
IPV6_CIDR="${IPV6_ADDR}/96"

# ------------------------------------------------------
# Derived routes and gateways
# ------------------------------------------------------
IPV4_SUPERNET="${O1}.0.0.0/8"
IPV4_GW="${O1}.${O2}.${O3}.254"

IPV6_SUPERNET="2002::/16"
IPV6_GW="2002::${O1}:${O2}:${O3}:254"

# ------------------------------------------------------
# Deterministic MAC address (locally administered)
# 02:<vlan_hi>:<vlan_lo>:<O1>:<O2>:<O3>
# ------------------------------------------------------
VLAN_HI=$(printf "%02x" $((VLAN_ID / 256)))
VLAN_LO=$(printf "%02x" $((VLAN_ID % 256)))
MAC_ADDR="02:${VLAN_HI}:${VLAN_LO}:$(printf '%02x:%02x:%02x' "$O2" "$O3" "$O4")"

# ------------------------------------------------------
# Sanity checks
# ------------------------------------------------------
if ! ip link show "$PARENT_IF" &>/dev/null; then
  echo "ERROR: Interface ${PARENT_IF} does not exist"
  exit 1
fi

if ip netns list | grep -q "^${NS_NAME}\b"; then
  echo "ERROR: Namespace ${NS_NAME} already exists"
  exit 1
fi

if ip link show "$VLAN_IF" &>/dev/null; then
  echo "ERROR: VLAN interface ${VLAN_IF} already exists"
  exit 1
fi

# ------------------------------------------------------
# Create namespace
# ------------------------------------------------------
ip netns add "$NS_NAME"

# ------------------------------------------------------
# Create VLAN interface
# ------------------------------------------------------
ip link add link "$PARENT_IF" name "$VLAN_IF" type vlan id "$VLAN_ID"
ip link set "$VLAN_IF" up
ip link set "$VLAN_IF" netns "$NS_NAME"

# ------------------------------------------------------
# Configure networking inside namespace
# ------------------------------------------------------
ip netns exec "$NS_NAME" ip link set lo up

# Set MAC (must be BEFORE traffic)
ip netns exec "$NS_NAME" ip link set "$VLAN_IF" down
ip netns exec "$NS_NAME" ip link set "$VLAN_IF" address "$MAC_ADDR"
ip netns exec "$NS_NAME" ip link set "$VLAN_IF" up

# Assign IP addresses
ip netns exec "$NS_NAME" ip addr add "$IPV4_CIDR" dev "$VLAN_IF"
ip netns exec "$NS_NAME" ip -6 addr add "$IPV6_CIDR" dev "$VLAN_IF"

# Enable IPv6 explicitly
ip netns exec "$NS_NAME" sysctl -qw net.ipv6.conf.all.disable_ipv6=0
ip netns exec "$NS_NAME" sysctl -qw net.ipv6.conf.default.disable_ipv6=0

# ------------------------------------------------------
# Add routes
# ------------------------------------------------------
# IPv4 supernet route
ip netns exec "$NS_NAME" ip route add "$IPV4_SUPERNET" \
  via "$IPV4_GW" dev "$VLAN_IF"

# IPv6 supernet route
ip netns exec "$NS_NAME" ip -6 route add "$IPV6_SUPERNET" \
  via "$IPV6_GW" dev "$VLAN_IF"

# ------------------------------------------------------
# Done
# ------------------------------------------------------
echo "✅ Namespace   : $NS_NAME"
echo "✅ Interface   : $VLAN_IF"
echo "✅ MAC         : $MAC_ADDR"
echo "✅ IPv4        : $IPV4_CIDR"
