# VLAN Local Significance & Translation Lab

This lab demonstrates VLAN local significance and VLAN translation with Nokia SR Linux using `containerlab`. It proves that even when multiple clients share the same IP subnet, SR Linux MAC-VRFs and VLAN segmentation keep traffic isolated.

## Lab goals

- Show VLAN IDs are locally significant, not globally unique.
- Demonstrate VLAN translation between client-facing VLANs and service-facing VLANs.
- Use MAC-VRFs on Nokia SR Linux to separate client traffic.
- Use Linux network namespaces to simulate isolated hosts on the same subnet.
- Prove that `client1` and `client2` cannot reach each other even with overlapping addressing.

## Topology

```
           +------------------+
           |   nutanix host   |
           |  ns101 @ VLAN 101|--\
           |  ns102 @ VLAN 102|   \  e1-1
           +------------------+    \
                                    +-----------------------+
                                    | Nokia 7220 IXR-D3L    |
                                    |      SR Linux         |
                                    |       leaf_switch     |
                                    +-----------------------+
                                   /             \
                                  /               \
                    e1-5 VLAN 10 /                 \ VLAN 10 e1-6
                                /                   \
                    +----------------+       +----------------+
                    | firewall_a     |       | firewall_b     |
                    | client1 domain |       | client2 domain |
                    +----------------+       +----------------+
```

### Mappings

- `nutanix:e1-1` carries:
  - VLAN `101` for Client 1
  - VLAN `102` for Client 2
- `leaf_switch:e1-5` carries:
  - VLAN `10` for Client 1
- `leaf_switch:e1-6` carries:
  - VLAN `10` for Client 2

### MAC-VRF service design

- `l2_cliente_a`:
  - `ethernet-1/1.101`
  - `ethernet-1/5.10`
- `l2_cliente_b`:
  - `ethernet-1/1.102`
  - `ethernet-1/6.10`

This means VLAN `10` is reused on two different firewall-facing ports, but traffic remains separated by distinct MAC-VRFs.

## Files included

- `lab_vlan_switching_1_leaf.clab.yml`
  - `containerlab` topology definition
- `create_vlan_namespace.sh`
  - script used by Linux nodes to create VLAN interfaces and namespaces
- `leaf_switch.flat.txt`
  - Nokia SR Linux startup configuration for the leaf switch
- `README.md_old`
  - previous README content preserved for reference

## What happens in the lab

### Nutanix side

- The `nutanix` node simulates two clients using Linux namespaces:
  - `ns101` on VLAN `101`
  - `ns102` on VLAN `102`
- Both namespaces use the same IPv4 subnet (`10.10.10.0/24`) and derived IPv6 addresses.
- The `create_vlan_namespace.sh` script creates:
  - a VLAN sub-interface
  - a dedicated network namespace
  - deterministic MAC address
  - IPv4/IPv6 addresses
  - supernet routes for validation

### Firewall side

- The `firewall_a` Linux node represents Client 1's firewall-facing service.
- The `firewall_b` Linux node represents Client 2's firewall-facing service.
- Each firewall node is configured with a VLAN `10` sub-interface in its namespace.

### Leaf switch side

- The Nokia switch translates:
  - VLAN `101` from the Nutanix side to VLAN `10` on `ethernet-1/5`
  - VLAN `102` from the Nutanix side to VLAN `10` on `ethernet-1/6`
- `MAC-VRF` instances keep the two services isolated even though the same VLAN ID is reused.


## Quick start

1. Deploy the topology:

```bash
containerlab deploy --topo lab_vlan_switching_1_leaf.clab.yml
```

2. Confirm the nodes are up:

```bash
containerlab inspect --topo lab_vlan_switching_1_leaf.clab.yml
```

3. Enter a node shell:

```bash
docker exec -it clab-lab_vlan_switching_1_leaf-nutanix bash
```

4. Verify namespaces on the `nutanix` node:

```bash
ip netns list
```

5. Run the isolation checks:

```bash
ip netns exec ns101 ping -c 3 10.10.10.101
ip netns exec ns102 ping -c 3 10.10.10.102
```

6. Tear down the lab when done:

```bash
containerlab destroy --topo lab_vlan_switching_1_leaf.clab.yml
```

## Verification

Use the Linux node consoles or `ip netns exec` inside `nutanix`, `firewall_a`, and `firewall_b`.

### Expected reachability

From `nutanix`:

- `ns101` should reach `firewall_a`
- `ns101` should NOT reach `firewall_b`
- `ns102` should reach `firewall_b`
- `ns102` should NOT reach `firewall_a`
- `ns101` should NOT reach `ns102`

### Example checks

On `nutanix`:

```bash
ip netns exec ns101 ping -c 3 10.10.10.101
ip netns exec ns101 ping -c 3 10.10.10.102
ip netns exec ns102 ping -c 3 10.10.10.102
ip netns exec ns102 ping -c 3 10.10.10.101
```

On firewalls:

```bash
ip netns exec ns10 ip addr show
ip netns exec ns10 ip -6 addr show
```

## Key takeaway

This lab proves that:

- VLANs are locally significant.
- SR Linux can translate VLANs between different domains.
- MAC-VRFs provide isolation even when VLAN IDs and IP subnets overlap.
- Linux namespaces simulate isolated clients on the same physical host.

## Notes

- `create_vlan_namespace.sh` derives IPv6 addresses from IPv4 using `2002::/96` and generates deterministic locally administered MAC addresses.
- The same IPv4 subnet is reused intentionally to show that traffic separation is enforced by VLAN/MAC-VRF boundaries, not by IP addressing alone.
