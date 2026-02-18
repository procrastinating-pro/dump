# 📂 Project UndeadZero: Secure Data Science & Ops Center

**Status:** Phase 2 (Analytics & IDS) – **Active** 🟢
**Version:** 2.1 (Data Lake Edition)
**Architecture:** Hybrid (Docker Sidecar + Bare Metal IDS)

## 1. Project Overview

NodeOne is a highly hardened, private home server designed with a **Zero Trust** philosophy. Unlike typical home labs, it exposes **zero ports** to the public internet. All access is mediated through an encrypted Mesh VPN.
The system now serves a dual purpose:

1. **Operations:** Network-wide AdBlocking and Password Management.
2. **Security Analytics:** Real-time Intrusion Detection (IDS) with a native RStudio environment for log analysis and threat hunting.

## 2. Infrastructure

* **Hardware:** Raspberry Pi 5 (8GB RAM) + NVMe SSD (PCIe).
* **Network Interface:** Gigabit Ethernet (Hardwired).
* **IP Configuration:** Static IP (via Netplan) to ensure stable DNS serving for the LAN.
* **OS:** Ubuntu Server (Headless).

## 3. Security Architecture (The "Fortress")

### A. Network Invisibility (Cloaking)

* **No Port Forwarding:** The router firewall is completely closed. Shodan/Nmap scans from the WAN side show the host as "offline."
* **VPN Ingress:** Access to services (RStudio, Vaultwarden) is possible *only* via **Tailscale** (WireGuard).
* **Subnet Routing:** The server acts as a gateway, allowing authorized VPN devices to access the local LAN securely.

### B. System Hardening

* **Docker User Namespace Remapping (`userns-remap`):**
* Container processes run as `root` inside the container but map to an unprivileged user (UID > 100000) on the host.
* **Benefit:** Prevents container breakout attacks from compromising the host system.


* **Bare Metal IDS (Suricata):**
* Running directly on the host (not Docker) to inspect raw network packets on `eth0`.
* Configured to ignore hardware offloading (GRO/LRO) for accurate inspection.
* **Output:** Generates EVE JSON logs for machine learning/analytics.



## 4. The Software Stack

The system uses a **Sidecar Pattern**. The VPN container (`tailscale`) manages the network stack, and application containers attach to it.

### 📊 Data Science & Analytics

* **RStudio Server (Dockerized):**
* **Role:** Integrated Development Environment (IDE) for data analysis.
* **Access:** Served via `https://nodeone...:8443` (Tailscale Encrypted).
* **Data Pipeline:**
* Mounts Suricata logs (`/var/log/suricata/eve.json`) as **Read-Only**.
* Mounts AdGuard logs (`querylog.json`) as **Read-Only**.


* **Goal:** Statistical analysis of network traffic, threat visualization, and DNS query auditing using R (`dplyr`, `jsonlite`).



### 🛡️ Core Services

* **Tailscale (The Backbone):**
* Acts as the network interface for all containers.
* Handles SSL termination (Let's Encrypt) via `tailscale serve`.
* Advertises routes (`--advertise-routes`) to the LAN.


* **AdGuard Home (DNS):**
* Network-wide ad and tracker blocking.
* Serves DNS to the entire local network via the Static IP.


* **Vaultwarden (Secrets):**
* Self-hosted Bitwarden instance.
* **Hardened:** Signups disabled (`SIGNUPS_ALLOWED=false`), accessible only via HTTPS over VPN.



### 🤖 Maintenance

* **Watchtower:**
* Updates containers automatically.
* **Config:** Forced `userns_mode: host` and `API 1.44` to bypass permission issues on the hardened Docker daemon.



## 5. Data Flow (The "Data Lake")

1. **Traffic** hits the `eth0` interface.
2. **Suricata** (Host) inspects packets → Writes to `eve.json`.
3. **AdGuard** (Container) filters DNS → Writes to `querylog.json`.
4. **RStudio** (Container) reads both logs via bind-mounts → User performs analysis.

## 6. Current Roadmap

* **Phase 3:** Active Defense. Implementing `endlessh` (SSH Tarpit) to trap and slow down internal network scanners.
* **Phase 4:** Long-term metrics storage (InfluxDB or SQLite) for RStudio reporting.

---

**Signed:** NodeOne SysAdmin.
