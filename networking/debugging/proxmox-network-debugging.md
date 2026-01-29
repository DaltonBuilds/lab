# Proxmox Network Debugging 'Cheat Sheet'
**Summary of what I did to debug networking issues with Proxmox host**

## The Problem
- After setting up my UniFi network the way I wanted (VLANs for proper segmentation), all was good and well until I introduced a new USW Flex 2.5G 8 port switch to the mix. I needed more ports to power other devices like the 3 M920q's that I recently acquired which will soon become nodes in my Kubernetes cluster.

- The addition of this new switch was supposed to be 'simple' but turned into several hours of debugging. Is it Proxmox? Is it UniFi? Is it me!?

- Nothing was reachable on the Proxmox host anymore. I could not ping the gateway (192.168.40.1) and all NICs (enp5s0, 6s0, etc.) were DOWN. Proxmox was now an isolated island.

- The Proxmox host was effectively “plugged into the wrong network” because the switch port/path to it wasn’t carrying VLAN 40 the way the host expected (VLAN tagging/trunk/PVID mismatch), so its ARP to 192.168.40.1 never got a reply and it looked isolated even though everything else on the network was fine.

## The Solution
- After doing everything under the sun, including getting an adapter so I could plug the ethernet cable from the PC (Proxmox host) into my MacBook Pro to test things out, I finally uncovered the root problem(s) with the help of ChatGPT. 

- It was `tcpdump -eni enp5s0` (or `tcpdump -ni enp5s0 arp or icmp`) that exposed the smoking gun by showing 802.1Q frames coming in tagged as VLAN 20 when I expected to be on VLAN 40/untagged.

- The fix was to correct the UniFi port/VLAN settings (PVID/native + allowed/tagged VLANs) on the Flex/uplink so the Proxmox NIC was actually receiving VLAN 40 (or untagged on the right VLAN) instead of being shoved onto/tagged by the wrong VLAN, after which ARP to 192.168.40.1 started working immediately.

- I know for a fact I tried this early on in the process but another key move was to ensure all changes were actually applied by rebooting and/or timely use of commands like `systemctl restart networking` for instance.

## 'Cheat Sheet' Commands That Were Useful

### Quick identity + addressing

- `ip -br a`
    
    Show interfaces + state + IPs (fast “what’s up / what has an address?” view).
    
- `ip addr show <iface>`
    
    Full detail for one interface (IPs, flags, etc.).
    
- `ip link show`
    
    Link-layer status (UP/DOWN, LOWER_UP, master/bridge relationships).
    
- `ip route`
    
    Routing table (look for `default via ...` and the correct subnet routes).
    
- `resolvectl status`
    
    Systemd-resolved DNS status (which DNS server is in use per interface).
    

---

### Basic connectivity tests

- `ping -c 3 <gateway-ip>`
    
    Tests L3 reachability to your gateway (first “is my LAN alive?” check).
    
- `ping -c 3 1.1.1.1`
    
    Tests raw internet reachability without DNS.
    
- `ping -c 3 google.com`
    
    Tests DNS + routing together.
    

---

### ARP / neighbor discovery (where we got our biggest clues)

- `ip neigh`
    
    Shows ARP/neighbor table (look for `FAILED`, `INCOMPLETE`, stale entries).
    
- `ip neigh show | head -n 30`
    
    Same as above, just trimmed for readability.
    
- `arp -n` *(if installed)*
    
    Old-school ARP table view (similar purpose as `ip neigh`).
    

---

### Watch link changes live

- `ip monitor link`
    
    Live stream of link state changes (great while unplugging/replugging cables).
    

---

### Physical link / NIC health

- `ethtool <iface>`
    
    Shows NIC negotiated speed/duplex and `Link detected: yes/no`.
    
- `for i in /sys/class/net/*; do i=${i##*/}; [ -f "/sys/class/net/$i/carrier" ] && echo "$i carrier=$(cat /sys/class/net/$i/carrier) operstate=$(cat /sys/class/net/$i/operstate)"; done`
    
    Quick “carrier vs operstate” across all interfaces (`carrier=1` usually means physical link present).
    
- `cat /sys/class/net/<iface>/carrier`
    
    `1` = link present, `0` = no link (physical).
    
- `cat /sys/class/net/<iface>/operstate`
    
    Kernel’s operational state (`up`, `down`, `unknown`, `lowerlayerdown`).
    

---

### Packet-level truth (ARP/ICMP)

- `tcpdump -ni <iface> arp or icmp`
    
    Sniffs ARP + ping traffic to confirm packets are leaving/arriving on the wire.
    
- `tcpdump -eni <iface> vlan`
    
    Verifies whether frames are tagged (useful when chasing VLAN/trunk mistakes).
    

---

### Proxmox / bridges / VLANs (host-side)

- `bridge link`
    
    Shows Linux bridge ports and whether they’re forwarding/disabled.
    
- `bridge vlan show`
    
    Shows VLAN membership/PVID/egress tagging on Linux bridges (critical for “where did my VLAN go?”).
    
- `ip -d link show vmbr0`
    
    Detailed link info for the bridge (VLAN filtering/bridge flags, etc.).
    
- `systemctl restart networking`
    
    Restarts Debian/Proxmox networking (use after `/etc/network/interfaces` changes).
    

---

### “Emergency” temporary tests (use carefully)

- `ip addr add <ip>/<cidr> dev <iface-or-bridge>`
    
    Temporarily add an IP to test connectivity (good for isolating VLAN vs config issues).
    
- `ip addr del <ip>/<cidr> dev <iface-or-bridge>`
    
    Remove that temporary IP when done.
    
- `ip route get <destination>`
    
    Shows which route/interface will be used to reach a destination (fast sanity check).
