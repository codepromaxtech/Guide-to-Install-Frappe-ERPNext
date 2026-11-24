# 🚀 Enterprise Automated Frappe & ERPNext Installer (v15, v16, v14)

[![ERPNext Version](https://img.shields.io/badge/ERPNext-v15%20%7C%20v16%20%7C%20v14-0089FF?style=for-the-badge&logo=frappe&logoColor=white)](https://erpnext.com)
[![Ubuntu LTS](https://img.shields.io/badge/Ubuntu-24.04%20%7C%2022.04%20LTS-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)](https://ubuntu.com)
[![Proxmox VE](https://img.shields.io/badge/Proxmox%20VE-7.x%20%7C%208.x%20LXC-E57000?style=for-the-badge&logo=proxmox&logoColor=white)](https://proxmox.com)
[![WhatsApp Support](https://img.shields.io/badge/WhatsApp-Contact%20CodeProMax-25D366?style=for-the-badge&logo=whatsapp&logoColor=white)](https://wa.me/8801302016151?text=Hello%20CodeProMax%20Tech,%20I%20would%20like%20to%20inquire%20about%20your%20services.)
[![Website](https://img.shields.io/badge/Website-codepromax.com.de-4F46E5?style=for-the-badge&logo=google-chrome&logoColor=white)](https://codepromax.com.de/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

An enterprise-grade, production-ready, interactive, and fully automated installer for **Frappe Bench & ERPNext**. Engineered for seamless deployment on bare-metal servers, virtual machines, cloud VPS (AWS, DigitalOcean, Hetzner, Linode), and **Proxmox VE LXC containers**.

Supports **ERPNext v15, v16 (develop), v14, and v13**, automated multi-app bundling (**HRMS, Payments, Webshop, CRM**), Ubuntu 24.04 LTS (PEP 668 compliant via Astral `uv`), Ubuntu 22.04 LTS, Debian, Cloudflare Real-IP restoration, Let's Encrypt SSL, and safe coexistence with existing web services and databases.

---

## 📞 Professional Support & Enterprise Services — CodeProMax Tech

Need expert assistance with ERPNext implementation, custom app development, Cloudflare CDN/WAF, or high-availability server infrastructure? **CodeProMax Tech** provides end-to-end consulting, migration, and 24/7 technical support.

| Channel | Contact Information |
| :--- | :--- |
| 🌐 **Official Website** | [https://codepromax.com.de/](https://codepromax.com.de/) |
| 💬 **Primary Hotline & WhatsApp** | [+880 130 201 6151 (Primary Hotline & WhatsApp)](https://wa.me/8801302016151?text=Hello%20CodeProMax%20Tech,%20I%20would%20like%20to%20inquire%20about%20your%20services.) |
| 📞 **Direct Support Line** | **+880 176 441 4949** |
| ✉️ **Direct Email** | [codepromaxtech@gmail.com](mailto:codepromaxtech@gmail.com) |
| ⏰ **Business Hours** | **Sunday to Thursday: 09:00 AM – 06:00 PM** *(Emergency & Critical Support available 24/7)* |

### Our Core Services
- **ERPNext Turnkey Implementation & Customization** (Manufacturing, Retail, Healthcare, Services)
- **Custom Frappe App Development** & Third-Party API Integrations
- **Cloud & Proxmox VE Infrastructure**: Unprivileged LXC containers, ZFS storage tuning, clustering & high availability
- **Security Hardening**: Cloudflare Full/Strict SSL, WAF rules, Fail2ban, UFW firewalling
- **ERPNext Version Migration & Database Troubleshooting** (v12/v13/v14 ➔ v15/v16)
- **Ongoing Server Maintenance & 24/7 SLA Monitoring**

---

## 📑 Table of Contents

- [⚡ 1-Minute Quick Start](#-1-minute-quick-start)
- [📦 Proxmox VE LXC Automated Deployment](#-proxmox-ve-lxc-automated-deployment)
- [✨ Key Capabilities & Highlights](#-key-capabilities--highlights)
- [🤖 Non-Interactive Automation (CLI Flags Reference)](#-non-interactive-automation-cli-flags-reference)
- [🧹 Old Installation Cleanup & Uninstaller](#-old-installation-cleanup--uninstaller)
- [🛡️ Production Architecture & Auto-Start Recovery on Reboot](#️-production-architecture--auto-start-recovery-on-reboot)
- [☁️ Cloudflare Proxy & SSL Configuration](#️-cloudflare-proxy--ssl-configuration)
- [🛠️ Manual Step-by-Step Installation Reference (Ubuntu 24.04 / v15 / v16)](#️-manual-step-by-step-installation-reference-ubuntu-2404--v15--v16)
- [🔍 Troubleshooting & Frequently Asked Questions (FAQ)](#-troubleshooting--frequently-asked-questions-faq)
- [📄 License & Authors](#-license--authors)

---

## ⚡ 1-Minute Quick Start

### Option A: Standard Interactive Installation
Clone the repository and run the automated script with `sudo`:

```bash
git clone https://github.com/codepromaxtech/Guide-to-Install-Frappe-ERPNext.git
cd Guide-to-Install-Frappe-ERPNext
sudo bash install.sh
```

### Option B: 1-Line Remote Quick Launcher
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/codepromaxtech/Guide-to-Install-Frappe-ERPNext/main/install.sh)"
```

The script displays an intuitive interactive menu that guides you through password setup, ERPNext version selection, domain configuration, app selection, and SSL preferences.

---

## 📦 Proxmox VE LXC Automated Deployment

Provision a dedicated, production-ready Ubuntu LXC container with ERPNext pre-installed in a single command executed directly from your **Proxmox VE Node Shell**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/codepromaxtech/Guide-to-Install-Frappe-ERPNext/main/create_erpnext_lxc.sh)"
```

Or from a cloned repository:
```bash
chmod +x create_erpnext_lxc.sh
./create_erpnext_lxc.sh
```

### Proxmox LXC Key Features
- **Auto-Detection**: Queries next available Container ID (`CTID`), storage pools (`local-lvm`, `local-zfs`), and template cache (`local`).
- **Template Management**: Downloads official **Ubuntu 24.04 LTS (Noble)** or **Ubuntu 22.04 LTS (Jammy)** appliances automatically.
- **Security & Stability**: Creates an unprivileged container with `--features nesting=1,keyctl=1` (required for systemd, MariaDB, and Redis).
- **Auto-Boot**: Sets `--onboot 1` so ERPNext starts automatically whenever the Proxmox host boots.
- **Network Modes**: Supports DHCP or Static IP with CIDR, Gateway, and custom DNS.

---

## ✨ Key Capabilities & Highlights

| Feature | Description |
| :--- | :--- |
| **Multi-Version Support** | Seamlessly deploy **ERPNext v15** (LTS Recommended), **v16** (develop / next-gen), **v14**, or **v13**. |
| **Ubuntu 24.04 (PEP 668) Ready** | Utilizes Astral **`uv`** to install isolated Python versions (3.11 for v14/v15, **3.14 for v16/develop**, 3.10 for v13), completely eliminating Ubuntu 24.04 pip restriction errors. |
| **Safe Cleanup & Uninstaller** | Dedicated uninstaller (`--cleanup-only` / `--clean-install`) stops supervisor services, cleans Nginx configs, and purges only Frappe databases/benches while strictly preserving existing websites and production databases. |
| **Checkpoint & Resume Engine** | Automatically tracks completed stages in a persistent state file. If installation is interrupted or an error occurs, re-running the script offers to resume immediately from the exact failure point without re-prompting or starting over. |
| **Smart Port Detection & Coexistence** | Automatically scans port availability. If port 80/443 is occupied by existing websites (ShopSuite, WordPress, Apache, PHP), automatically suggests or assigns the next free port (e.g., 8088/8090) and configures Nginx seamlessly. Auto-maps server IP addresses so browser access works out-of-the-box without site lookup errors. |
| **Multi-App Installer** | Bundle **ERPNext, HRMS, Payments, Webshop, Helpdesk, Frappe CRM**, or any custom private Git repository in one run. |
| **Complete SSL Stack** | Automated **Let's Encrypt** with auto-renewal, **Cloudflare Real-IP proxy integration**, Self-Signed SSL, or HTTP mode. |
| **Auto-Memory Tuning** | Detects available RAM; automatically provisions a 2GB swapfile on small VPS instances (<2.5GB) to prevent out-of-memory build failures. |
| **Enterprise Hardening** | MariaDB `utf8mb4_unicode_ci` tuning, Gunicorn WSGI prefork pool, Supervisor process supervision, and automated daily backup cron. |

---

## 🤖 Non-Interactive Automation (CLI Flags Reference)

For DevOps pipelines (Cloud-init, Terraform, Ansible, Docker, CI/CD), use non-interactive CLI flags:

```bash
sudo bash install.sh \
  --non-interactive \
  --mode fresh \
  --version 15 \
  --domain erp.company.com \
  --site erp.company.com \
  --port 80 \
  --ssl letsencrypt \
  --email "admin@company.com" \
  --user frappe \
  --admin-pass "SuperAdminPassword123!" \
  --db-pass "MariaDbRootPass123!" \
  --apps "erpnext,hrms,payments" \
  --ufw
```

### Supported CLI Flags

| Flag | Parameter / Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `--non-interactive`, `-y` | Flag | `false` | Run without interactive prompts |
| `--resume` | Flag | `false` | Resume interrupted installation from previous checkpoint |
| `--clean` | Flag | `false` | Discard previous checkpoint and start fresh |
| `--cleanup-only`, `--uninstall` | Flag | `false` | Safely remove existing Frappe bench, supervisor services, Nginx configs, and Frappe databases |
| `--clean-install` | Flag | `false` | Purge any old Frappe bench installation before performing a clean install |
| `--force`, `-f` | Flag | `false` | Force cleanup operations without interactive confirmation |
| `--mode` | `fresh` \| `existing` | `fresh` | Installation mode (fresh VPS vs. existing server) |
| `--version` | `14` \| `15` \| `16` \| `13` | `15` | Target Frappe / ERPNext version |
| `--domain` | `<domain.com>` \| `<IP>` | Host IP | Server domain name or public IP |
| `--site` | `<site_name>` | Domain | Frappe site name |
| `--port` | `<number>` | `80` | HTTP Web port (useful for reverse proxy coexistence) |
| `--ssl` | `letsencrypt` \| `cloudflare` \| `selfsigned` \| `none` | `none` | SSL encryption strategy |
| `--cf-mode` | `proxy` \| `origin` | `proxy` | Cloudflare SSL mode (`proxy` or `origin`) |
| `--user` | `<username>` | `frappe` | Dedicated system bench user |
| `--admin-pass` | `<password>` | Generated | Frappe `Administrator` user password |
| `--db-pass` | `<password>` | Generated | MariaDB `root` database password |
| `--email` | `<email>` | None | Admin email for Let's Encrypt expiration notices |
| `--apps` | Comma-separated | `erpnext` | App list (`erpnext,hrms,payments,webshop`) |
| `--custom-app` | `<git_repo_url>` | None | Custom Git repository URL |
| `--custom-branch` | `<branch_name>` | `main` | Branch for custom Git repository |
| `--ufw` | Flag | `false` | Automatically configure and enable UFW firewall |
| `--no-cron` | Flag | `false` | Disable automated 02:00 AM database backup cron |
| `--help`, `-h` | Flag | - | Display help menu and CLI usage |

---

## 🧹 Old Installation Cleanup & Uninstaller

If you have a broken, partial, or old Frappe/ERPNext installation, the installer provides a safe, integrated cleanup engine:
- **Service Termination**: Stops all Frappe supervisor worker and socket processes.
- **Supervisor Clean**: Removes `/etc/supervisor/conf.d/frappe-bench.conf` and reloads supervisor.
- **Nginx Clean**: Unlinks `/etc/nginx/conf.d/frappe-bench.conf` and reloads Nginx safely, preserving all non-Frappe websites.
- **Database Safety Guard**: Inspects `site_config.json` and drops **only** Frappe databases and users. It **strictly protects** system and third-party databases (such as `shopsuite`, `aranya_erp`, `mysql`).
- **Bench Cleanup**: Removes the bench directory (`/home/<user>/frappe-bench`) and automated backup crons.

### Running Standalone Cleanup
```bash
# Interactive mode (asks for confirmation)
sudo bash install.sh --cleanup-only

# Automated / non-interactive mode
sudo bash install.sh --cleanup-only --force --user erp --db-pass "YourDbPassword"
```

### Performing a Fresh Clean Install
To completely purge an old installation and immediately proceed with a fresh installation:
```bash
sudo bash install.sh --clean-install
```

---

## 🛡️ Production Architecture & Auto-Start Recovery on Reboot

The installer configures an industrial-grade production environment that is **reboot-resilient and self-healing**:

```
                       ┌─────────────────────────┐
                       │   Internet / Visitors   │
                       └────────────┬────────────┘
                                    │ (Port 80 / 443 / 8088)
                                    ▼
                       ┌─────────────────────────┐
                       │      Nginx (Proxy)      │
                       └────────────┬────────────┘
                                    │
               ┌────────────────────┴────────────────────┐
               ▼ (Port 8000)                             ▼ (Port 9000)
    ┌─────────────────────┐                   ┌─────────────────────┐
    │  Gunicorn (Web App) │                   │  Node.js (SocketIO) │
    └──────────┬──────────┘                   └──────────┬──────────┘
               │                                         │
               └────────────────────┬────────────────────┘
                                    ▼
               ┌─────────────────────────────────────────┐
               │    Supervisor Master Process Manager    │
               │         (systemctl: enabled)            │
               └─┬──────────────┬──────────────┬─────────┘
                 │              │              │
                 ▼              ▼              ▼
          ┌─────────────┐┌─────────────┐┌──────────────┐
          │Redis Cache  ││Redis Queue  ││Celery/RQ     │
          │(Port 13000) ││(Port 11000) ││Workers (x2)  │
          └─────────────┘└─────────────┘└──────────────┘
```

### Systemd Services Enabled on Boot
- **`mariadb.service`** — Starts database engine and binds InnoDB tables.
- **`redis-server.service`** — In-memory caching daemon.
- **`supervisor.service`** — Master supervisor daemon managing all 7 bench worker and web processes.
- **`nginx.service`** — Reverse proxy serving static assets, SSL certificates, and socket traffic.
- **`cron.service`** — Runs automated daily database backups at 02:00 AM.

### Supervisor Process Supervision (`autorestart=true`)
In `/etc/supervisor/conf.d/frappe-bench.conf`:
- `autostart=true`: Guarantees that every bench service starts immediately upon system boot.
- `autorestart=true`: Automatically restarts any service if terminated by OOM, crash, or memory limits.
- `killasgroup=true`: Prevents orphan worker processes during updates or reloads.

---

## ☁️ Cloudflare Proxy & SSL Configuration

When using Cloudflare, select `--ssl cloudflare` to configure **Real-IP restoration** and avoid visitor IP masking.

The installer automatically writes `/etc/nginx/conf.d/00-cloudflare.conf` with all official Cloudflare IPv4 and IPv6 CIDR blocks:
```nginx
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 141.101.64.0/18;
...
real_ip_header CF-Connecting-IP;
```

---

## 🛠️ Manual Step-by-Step Installation Reference (Ubuntu 24.04 / v15 / v16)

For administrators who wish to inspect or execute each step manually:

### Step 1: System Packages & Python Setup via UV
```bash
sudo apt-get update -y && sudo apt-get upgrade -y
sudo apt-get install -y git curl software-properties-common xvfb libfontconfig \
  libmariadb-dev pkg-config redis-server cron supervisor nginx build-essential

# Install Astral UV (Solves Ubuntu 24.04 PEP 668 restrictions)
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc
uv python install 3.11
```

### Step 2: Node.js 20 & Yarn
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g yarn
```

### Step 3: wkhtmltopdf with Patched Qt
```bash
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
sudo dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb
sudo apt-get -f install -y
```

### Step 4: MariaDB Configuration
Add the required UTF-8 mb4 configuration to `/etc/mysql/mariadb.conf.d/99-frappe.cnf`:
```ini
[server]
user = mysql
bind-address = 127.0.0.1

[mysqld]
innodb-file-format = barracuda
innodb-file-per-table = 1
innodb-large-prefix = 1
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
```
Restart MariaDB:
```bash
sudo systemctl restart mariadb
```

### Step 5: Bench Init & App Installation
```bash
uv tool install frappe-bench
bench init --frappe-branch version-15 frappe-bench
cd frappe-bench

# Create new site
bench new-site erp.yourdomain.com
bench --site erp.yourdomain.com enable-scheduler

# Get and install apps
bench get-app --branch version-15 erpnext
bench get-app --branch version-15 hrms
bench --site erp.yourdomain.com install-app erpnext
bench --site erp.yourdomain.com install-app hrms
```

### Step 6: Production Setup
```bash
bench setup nginx
bench setup supervisor
sudo ln -sf $(pwd)/config/supervisor.conf /etc/supervisor/conf.d/frappe-bench.conf
sudo ln -sf $(pwd)/config/nginx.conf /etc/nginx/conf.d/frappe-bench.conf
sudo supervisorctl reread && sudo supervisorctl update && sudo supervisorctl restart all
sudo systemctl reload nginx
```

---

## 🔍 Troubleshooting & Frequently Asked Questions (FAQ)

### Q1: `error: externally-managed-environment` on Ubuntu 24.04?
**Cause:** Ubuntu 24.04 enforces PEP 668 preventing direct `pip install`.  
**Fix:** Our installer automatically uses Astral `uv` to manage isolated Python versions without touching the OS python environment.

### Q2: `redis.exceptions.ConnectionError: Error 111 connecting to 127.0.0.1:11000`?
**Cause:** Bench Redis Queue (11000) or Cache (13000) is not running when `bench install-app` executes.  
**Fix:** The installer launches Supervisor Redis instances prior to running `install-app`, preventing this failure.

### Q3: `nginx: [emerg] unknown log format "main"`?
**Cause:** Debian/Ubuntu Nginx defaults to `combined` rather than `main`.  
**Fix:** The installer writes `/etc/nginx/conf.d/00-frappe-log-format.conf` to declare `log_format main` before Nginx reloads.

### Q4: Can I run ERPNext on a port other than 80?
**Answer:** Yes! Use `--port 8088` (or any custom port) to run ERPNext side-by-side with other websites on the same server.

### Q5: How does the Resume Feature work if my installation is interrupted?
**Answer:** The installer saves your configuration parameters and checkpoint states into `/var/log/frappe-installer/install_state.env`. If a run is interrupted or fails (e.g. network disconnect, power loss), simply re-running `sudo bash install.sh` prompts:
```text
  1) Resume installation from where it stopped (Recommended)
  2) Discard previous state and start fresh
```
In non-interactive scripts or automation, use `--resume` to continue or `--clean` to wipe state.

### Q6: Why does Frappe / ERPNext v16 fail on older Python versions?
**Answer:** Upstream Frappe Framework `version-16` and `develop` branches enforce `requires-python = ">=3.14,<3.15"`. Attempting to initialize with Python 3.11 or 3.12 fails with dependency resolution errors. Our installer automatically identifies this and provisions isolated **Python 3.14** via Astral `uv` for version-16.

---

## 📄 License & Authors

- **Author & Maintainer:** [CodeProMax Tech](https://codepromax.com.de/)
- **Contact:** [+880 130 201 6151](https://wa.me/8801302016151?text=Hello%20CodeProMax%20Tech,%20I%20would%20like%20to%20inquire%20about%20your%20services.) | [codepromaxtech@gmail.com](mailto:codepromaxtech@gmail.com)
- **License:** Released under the [MIT License](https://opensource.org/licenses/MIT).

---

<sub>**Keywords:** erpnext install script, frappe bench installer, erpnext ubuntu 24.04, erpnext ubuntu 22.04, proxmox lxc erpnext, erpnext v15 installation guide, erpnext v16 develop, erpnext hrms installer, cloudflare erpnext ssl, codepromax tech, frappe bench automated script</sub>
