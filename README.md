# 💀 Project undead-zero

### *The Self-Healing, Zero-Trust Data Fortress.*

**Version:** 1.0 (Genesis)
**Status:** Production (Stable)
**License:** MIT (Code) / CC BY-NC 4.0 (Content)

---

## 1. The Manifesto (Philosophy)

**UndeadZero** is not just a Home Lab. It is an infrastructure philosophy defined by three core pillars:

1. **Invisible (Zero):** Zero open ports on the router. Zero trust for the local network. Complete isolation from the public internet.
2. **Immortal (Undead):** Designed for High Availability (HA). When hardware inevitably fails, services rise from the dead on a backup node (WIP).
3. **Intelligent (Data-Driven):** Instead of blindly logging errors, we use **Data Science (R/RStudio)** to actively hunt for threats and anomalies.

We build it once, correctly, so we can "lazily" reap the benefits of automation.

---

## 2. System Architecture

The system relies on a **Hybrid Model**: Docker Containers (Sidecar Pattern) supported by Host-based services (IDS).

### A. Hardware & Security

* **Primary Node (Master):** Raspberry Pi 5 (8GB RAM, NVMe SSD).
* **Secondary Node (Slave):** Raspberry Pi 4 (Planned for Phase 2).
* **Physical Auth:** Flipper Zero (U2F/FIDO2) acting as a hardware security key.
* **OS:** Ubuntu Server (Headless, Hardened).

### B. Network (Ghost Mode)

* **Ingress:** No public IPv4. All traffic enters via an encrypted Mesh VPN (**Tailscale**).
* **Firewall:** Default "Deny All" policy.
* **User Namespace Remapping:** Container processes are mapped to an unprivileged host user (UID > 100000), preventing Container Breakout attacks.

---

## 3. The Tech Stack

All services run within Docker containers, bound into a single logical network.

| Service | Role | Description |
| --- | --- | --- |
| **Tailscale** | Network Backbone | Mesh VPN, SSL Termination, Subnet Routing. |
| **Suricata** | The Eyes (IDS) | Real-time packet analysis. Listens on `eth0` and `tailscale0`. |
| **AdGuard Home** | The Shield (DNS) | Network-wide blocking of ads, trackers, and malware via DNS. |
| **Vaultwarden** | The Vault | Self-hosted Bitwarden. Passwords never leave your private network. |
| **RStudio Server** | The Brain | Data Science environment for log analysis (`eve.json`) and threat visualization. |
| **Watchtower** | The Automator | Automatic container updates ("Lazy Ambition" module). |

---

## 4. Deployment

### Step 1: Directory Setup

The initialization script creates the "Fortress" structure.

```bash
# Directory structure for UndeadZero
sudo mkdir -p /opt/undeadzero/{tailscale,adguard,vaultwarden,rstudio,data}
sudo chown -R $USER:$USER /opt/undeadzero

```

### Step 2: docker-compose.yml (The Blueprint)

The definition file for the entire infrastructure.

```yaml
services:
  # --- NETWORK BACKBONE (VPN) ---
  tailscale:
    image: tailscale/tailscale:latest
    container_name: undeadzero-tailscale
    hostname: undeadzero
    environment:
      - TS_EXTRA_ARGS=--advertise-exit-node --advertise-routes=192.168.1.0/24
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_USERSPACE=false   # Critical for Suricata visibility!
    volumes:
      - ./tailscale/data:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    restart: unless-stopped

  # --- DNS PROTECTION ---
  adguard:
    image: adguard/adguardhome
    container_name: undeadzero-adguard
    network_mode: "service:tailscale"
    depends_on:
      - tailscale
    volumes:
      - ./adguard/data:/opt/adguardhome/work
      - ./adguard/config:/opt/adguardhome/conf

  # --- DATA SCIENCE & ANALYTICS ---
  rstudio:
    image: rocker/rstudio:latest
    container_name: undeadzero-rstudio
    network_mode: "service:tailscale"
    environment:
      - PASSWORD=${RSTUDIO_PASSWORD}
      - ROOT=true
    volumes:
      - ./rstudio/home:/home/rstudio
      # Log Mapping (Read-Only) for analysis
      - /var/log/suricata:/data/logs/suricata:ro
      - ./adguard/data:/data/logs/adguard:ro

  # --- AUTOMATION ---
  watchtower:
    image: containrrr/watchtower
    container_name: undeadzero-watchtower
    userns_mode: "host"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 86400 --cleanup

```

---

## 5. Security & Procedures (SecOps)

### A. Compromised Endpoint Protocol (Stolen Device)

In the event of a lost device with VPN access:

1. Log into the Tailscale Admin Panel (using U2F Key/Flipper Zero).
2. Locate the device and click **"Revoke Machine"**.
3. The device immediately loses all access to the UndeadZero network.

### B. Threat Hunting

We utilize RStudio to analyze the `/data/logs/suricata/eve.json` file.
Example analysis scenario:

* **Question:** "Did anyone scan my network last night?"
* **Method:** Load JSON logs in R -> Filter by `event_type == "alert"` -> Visualize using `ggplot2`.

### C. Custom Tools

The system includes proprietary tools: `live-tree` (for real-time process tracking) and `pidtree` (for inspecting files inside containers from the host).

---

## 6. Roadmap

* **Phase 2 (High Availability):** Deployment of a secondary node (NodeTwo) utilizing **Keepalived** (VRRP) and **Syncthing** for real-time data replication. Goal: Zero Downtime during hardware failure.
* **Phase 3 (Offensive):** Deploying `endlessh` (SSH Tarpit) to trap bots and gather Cyber Intelligence.

---

*Documentation automatically generated by AI Assistant for the UndeadZero Project Architect.*
*© 2026 UndeadZero Project.*
