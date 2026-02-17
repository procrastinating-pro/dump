# 📂 Project NodeOne: Secure Home Operations Center

**Status:** Phase 1 (Core Network Stack) – Completed 🟢
**Version:** 1.0 Stable
**Architecture:** Docker Sidecar + Tailscale Mesh

## 1. Project Goal

Building an uncompromising private home server ("Home Lab") with a strict focus on **Security First** and **Privacy**.
The project moves away from standard "expose everything" configurations in favor of a **Zero Trust** architecture – no open ports on the edge router, access exclusively via an encrypted VPN tunnel, and strict process isolation.

## 2. Hardware Infrastructure

* **Platform:** Raspberry Pi 5 (8GB RAM).
* **Storage:** NVMe SSD (via PCIe HAT) – for maximum I/O performance.
* **Network:** Ethernet 1Gbps (Hardwired).

## 3. Security Foundation (Hardening)

This is not a standard Docker setup. Advanced protection mechanisms have been implemented:

1. **Docker User Namespace Remapping (`userns-remap`):**
* **Mechanism:** Processes inside containers run as `root` only *within* the container scope. On the host system, they are mapped to a high-UID unprivileged user (UID > 100000).
* **Benefit:** Even if an attacker achieves a container breakout, they have zero privileges on the host system.


2. **Zero Open Ports (WAN):**
* No Port Forwarding configured on the ISP router.
* The server remains invisible to external network scanners (Shodan, Nmap).


3. **Tailscale Mesh VPN (WireGuard):**
* All administrative access and service consumption occur via an encrypted WireGuard tunnel.



## 4. Network Architecture: "The Sidecar Pattern"

Due to `userns-remap` isolation, the standard Docker `host` network mode is unavailable for containers. The **Sidecar** pattern was implemented, where service containers attach directly to the VPN container's network stack.

* **Parent Container:** `nodeone-tailscale`
* Handles the network interface, routing, VPN tunneling, and SSL certificate termination.


* **Sidecar Containers:** `adguard`, `vaultwarden`
* Configured with `network_mode: service:tailscale`.
* They communicate with each other via `localhost`.
* They share the same IP address within the VPN mesh.



## 5. Deployed Services (Software Stack)

### 🛡️ A. VPN & Connectivity (Tailscale)

* **Role:** Exit Node (VPN gateway for mobile devices) + Subnet Router (LAN access).
* **Function:** Enables secure internet access and ad-blocking while away from home (on LTE/Public Wi-Fi).
* **Configuration:** Hardcoded Subnet Routing (to bypass auto-detection failures).

### 🛑 B. Network-wide AdBlocking (AdGuard Home)

* **Role:** DNS Server.
* **Integration:** Acts as the primary DNS for the entire Tailscale mesh (via "Override Local DNS").
* **Ports:** 53 (DNS), 3000 (Web UI), 8080 (Block Page).
* **Status:** Blocks trackers and ads on all VPN-connected devices.

### 🔐 C. Password Management (Vaultwarden)

* **Role:** Private, self-hosted Bitwarden instance (Rust implementation).
* **Security:**
* **Invisible to LAN:** No open ports (80/443/8081) exposed on the host IP.
* **Tailscale Serve:** Accessed exclusively via the VPN tunnel.
* **HTTPS/TLS:** End-to-end encryption with automatic Let's Encrypt certificates (managed by Tailscale), terminated on the localhost interface.
* **Hardened:** `SIGNUPS_ALLOWED=false` (Registration disabled after admin creation).



### 🤖 D. Maintenance (Watchtower)

* **Role:** Automated container updates.
* **Fix:** Configured with `userns_mode: host` and `DOCKER_API_VERSION=1.44` to bypass permission issues with the Docker socket on modern API versions.

## 6. Troubleshooting Log (Technical Challenges Resolved)

During deployment, several critical conflicts were resolved:

1. **Port 53 Conflict:** Disabled `systemd-resolved` stub listener to allow AdGuard to bind to the DNS port.
2. **Permission Denied Loops:** Containers entered restart loops due to `userns-remap` file ownership issues.
* *Fix:* Applied `chmod 777` to specific data directories (safe due to UserNS isolation).


3. **Socket Files:** Implemented manual cleanup of `.sock` files before container startup.
4. **API Version Mismatch:** Forced Watchtower to use a compatible Docker API version via environment variables.

## 7. Roadmap

* **Phase 2:** Deployment of **Suricata IDS** (Intrusion Detection System) on "Bare Metal" to monitor raw network traffic bypassing Docker.
* **Phase 3:** Monitoring Stack (Dashboard, Logs).
* **Phase 4:** Databases and Stateful Applications.

---

**Signed:** NodeOne SysAdmin & Gemini AI.
