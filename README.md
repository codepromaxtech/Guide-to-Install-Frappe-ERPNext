# 🚀 Enterprise Automated Frappe & ERPNext Installer

An enterprise-grade, interactive, and automated installer for **Frappe Bench & ERPNext**. Supports multiple ERPNext versions, multi-app installations, Ubuntu versions (20.04, 22.04, 24.04), Debian, Cloudflare SSL, Let's Encrypt, custom domains, and safe coexistence on servers with existing services.

---

## ⚡ Quick Start (1-Command Automatic Installation)

Run the automated interactive installer with `sudo`:

```bash
git clone https://github.com/codepromaxtech/Guide-to-Install-Frappe-ERPNext.git
cd Guide-to-Install-Frappe-ERPNext
sudo bash install.sh
```

The script will launch a modern interactive wizard that asks for your preferences and handles everything end-to-end.

---

## ✨ Features

- **Multi-Version Support**:
  - `version-15` (Current LTS Stable — Recommended)
  - `version-16` / `develop` (Next Generation Frappe Framework)
  - `version-14` (Legacy Stable)
  - `version-13` (Legacy)
- **Multi-OS & Multi-Architecture**:
  - Ubuntu 24.04 LTS (Noble Numbat), Ubuntu 22.04 LTS (Jammy), Ubuntu 20.04 LTS (Focal)
  - Debian 11 (Bullseye) & Debian 12 (Bookworm)
  - Architectures: `x86_64` (amd64) and `aarch64` (arm64 / Raspberry Pi / Apple Silicon VMs)
- **Interactive Configuration Wizard**:
  - **Secure Password Handling**: Prompts for MariaDB root and Frappe Administrator passwords with auto-generation options (using hidden inputs).
  - **Domain or Localhost/IP**: Configure for public FQDN (e.g. `erp.yourdomain.com`) or local IP / intranet (`site1.local` / `192.168.x.x`).
  - **SSL & Reverse Proxy Choices**:
    - **Let's Encrypt**: Automatic Certbot certificate generation and auto-renewal.
    - **Cloudflare**: Integrated Cloudflare Real-IP restoration (`CF-Connecting-IP`) and Edge SSL (Flexible/Full/Origin CA).
    - **Self-Signed SSL**: Auto-generated 2048-bit certificate for testing HTTPS.
    - **HTTP Only**: Great for local networks or when behind Traefik, Nginx Proxy Manager, or Cloudflare Tunnel.
- **Fresh vs. Coexistence Mode ("With Other Services")**:
  - **Fresh**: Sets up MariaDB, Nginx, Redis, and system tuning from scratch.
  - **Coexistence**: Detects existing MySQL/MariaDB or Nginx web servers. Prompts for existing credentials without wiping databases, avoids port conflicts, and adds isolated virtual hosts.
- **Multi-App Installer**:
  - ERPNext (core)
  - HRMS (Human Resource Management & Payroll)
  - Payments (Payment Gateways integration)
  - Webshop (E-Commerce Storefront)
  - Helpdesk (Customer Support & Ticketing)
  - Frappe CRM
  - Lending (Loan Management)
  - Custom Git Apps (Provide any Git URL and branch)
- **Performance & Reliability**:
  - Uses Astral `uv` for ultra-fast, isolated Python environment management without violating Ubuntu PEP 668.
  - Automatically provisions swap space on servers with < 2.5GB RAM to prevent build out-of-memory errors.
  - Fully logs installation progress to `/var/log/frappe-installer/`.

---

## 🤖 Non-Interactive Automation (CLI Flags)

For unattended deployments (Cloud-init, Ansible, Proxmox, Docker, CI/CD), pass parameters via command-line flags:

```bash
sudo bash install.sh \
  --non-interactive \
  --version 15 \
  --mode fresh \
  --domain erp.example.com \
  --site erp.example.com \
  --user frappe \
  --admin-pass "AdminSecret123!" \
  --db-pass "DbRootSecret123!" \
  --ssl letsencrypt \
  --email "admin@example.com" \
  --apps "erpnext,hrms,payments" \
  --ufw
```

### Available CLI Flags

| Flag | Values | Description |
|---|---|---|
| `--non-interactive`, `-y` | Flag | Run without interactive prompts |
| `--mode` | `fresh` \| `existing` | Installation mode (default: `fresh`) |
| `--version` | `14` \| `15` \| `16` \| `develop` | Frappe/ERPNext version (default: `15`) |
| `--domain` | string | Domain name or server IP |
| `--site` | string | Frappe site name (defaults to domain) |
| `--port` | number | HTTP port (default: `80`) |
| `--ssl` | `letsencrypt` \| `cloudflare` \| `selfsigned` \| `none` | SSL configuration strategy |
| `--cf-mode` | `proxy` \| `origin` | Cloudflare SSL mode (default: `proxy`) |
| `--user` | string | System user for Frappe bench (default: `frappe`) |
| `--admin-pass` | string | Frappe Administrator password |
| `--db-pass` | string | MariaDB root password |
| `--email` | string | Administrator email for Let's Encrypt |
| `--apps` | string | Comma-separated apps list (`erpnext,hrms,payments,webshop`) |
| `--custom-app` | URL | Custom Git repository URL |
| `--custom-branch` | string | Git branch for custom app |
| `--ufw` | Flag | Enable and configure UFW firewall |
| `--no-cron` | Flag | Disable automated daily backup cron job |
| `--help`, `-h` | Flag | Display help and usage options |

---

## 📦 Proxmox VE LXC Automated Deployment

If you are running Proxmox VE (PVE 7.x or 8.x), you can provision a production-ready LXC container and deploy ERPNext inside it in one command directly from your Proxmox host shell:

### 1-Line Execution on Proxmox Node
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/codepromaxtech/Guide-to-Install-Frappe-ERPNext/main/create_erpnext_lxc.sh)"
```

Or from a cloned repository:
```bash
chmod +x create_erpnext_lxc.sh
./create_erpnext_lxc.sh
```

### Proxmox LXC Features
- **Next Free ID & Storage Detection**: Automatically detects the next free CTID, available rootfs storage pools (`local-lvm`, `local-zfs`), and template storage (`local`).
- **Ubuntu 24.04 & 22.04 LTS Templates**: Auto-checks local cache and downloads official Ubuntu standard appliances via `pveam`.
- **Unprivileged & Hardened**: Configured with `--unprivileged 1` and `--features nesting=1,keyctl=1` (required for systemd, Redis, and MariaDB).
- **Auto-Start on Boot**: Configured with `--onboot 1` so the container starts automatically when the Proxmox host boots.
- **Dynamic Network Configuration**: Supports both DHCP and static IP with custom gateways and DNS.

---

## 🛡️ Production Readiness & Auto-Start Recovery

The installation is engineered to be **100% production ready** and guarantees automatic recovery after server reboots:

### Systemd Services (Host Boot Level)
The following core daemons are enabled via `systemctl enable`:
- `mariadb.service` — Database engine.
- `redis-server.service` — In-memory caching backend.
- `supervisor.service` — Process manager managing all Frappe workers and Gunicorn.
- `nginx.service` — Reverse proxy handling SSL termination and static assets.
- `cron.service` — Executes automated daily database backups at 02:00 AM.

### Supervisor Process Supervision (`autorestart=true`)
In `/etc/supervisor/conf.d/frappe-bench.conf`, each bench service has:
- `autostart=true`: Automatically launched when supervisor initializes on reboot.
- `autorestart=true`: Automatically respawned if killed by OOM or unexpected errors.
- `killasgroup=true`: Prevents orphan worker processes during restarts.
- `startretries=10`: Graceful startup under high server boot load.

```text
frappe-bench-redis:frappe-bench-redis-cache              RUNNING (port 13000)
frappe-bench-redis:frappe-bench-redis-queue              RUNNING (port 11000)
frappe-bench-web:frappe-bench-frappe-web                 RUNNING (Gunicorn - 9 workers)
frappe-bench-web:frappe-bench-node-socketio              RUNNING (Socket.IO - port 9000)
frappe-bench-workers:frappe-bench-frappe-long-worker-0   RUNNING (Heavy tasks)
frappe-bench-workers:frappe-bench-frappe-schedule        RUNNING (Cron scheduler)
frappe-bench-workers:frappe-bench-frappe-short-worker-0  RUNNING (Fast tasks)
```

---

## 🛠 Manual Step-by-Step Installation Guide (Ubuntu 24.04 / v16 Reference)

If you prefer to execute the commands step-by-step manually, follow the sections below:

### STEP 1: SERVER SETUP

#### 1.1 Update & upgrade system packages
```bash
sudo apt-get update -y
sudo apt-get upgrade -y
```

#### 1.2 Create a new user
```bash
sudo adduser frappe
sudo usermod -aG sudo frappe
su - frappe
```

---

### STEP 2: INSTALL REQUIRED PACKAGES

#### 2.1 Base Packages & Python
```bash
sudo apt-get install -y git curl software-properties-common xvfb libfontconfig libmariadb-dev pkg-config redis-server cron supervisor nginx

# Install Astral UV (Recommended for Frappe v16 / Ubuntu 24.04)
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc
uv python install 3.12 --default
```

#### 2.2 Install Node.js 20 & Yarn
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g yarn
```

#### 2.3 Install wkhtmltopdf
```bash
sudo wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
sudo dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb
sudo apt-get -f install -y
```

---

### STEP 3: CONFIGURE MariaDB SERVER

#### 3.1 Install and configure MariaDB
```bash
sudo apt install mariadb-server mariadb-client -y
sudo mysql_secure_installation
```

#### 3.2 Add Frappe UTF-8 configuration
Create `/etc/mysql/mariadb.conf.d/99-frappe.cnf`:
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

---

### STEP 4: INITIALIZE FRAPPE BENCH

```bash
uv tool install frappe-bench
bench init --frappe-branch version-15 frappe-bench
cd frappe-bench
sudo chmod -R o+rx /home/frappe/
```

---

### STEP 5: CREATE SITE & INSTALL APPS

```bash
bench new-site erp.example.com
bench --site erp.example.com set-maintenance-mode off
bench --site erp.example.com enable-scheduler

# Fetch and install ERPNext & Apps
bench get-app --branch version-15 payments
bench get-app --branch version-15 erpnext
bench get-app --branch version-15 hrms

bench --site erp.example.com install-app payments
bench --site erp.example.com install-app erpnext
bench --site erp.example.com install-app hrms
```

---

### STEP 6: SETUP PRODUCTION & SSL

```bash
bench config dns_multitenant on
bench setup nginx
bench setup supervisor

sudo ln -sf `pwd`/config/supervisor.conf /etc/supervisor/conf.d/frappe-bench.conf
sudo ln -sf `pwd`/config/nginx.conf /etc/nginx/conf.d/frappe-bench.conf

sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart all
sudo systemctl reload nginx

# Install Let's Encrypt SSL
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d erp.example.com
```

---

## 🔧 Useful Bench Commands

```bash
# Switch to bench user
su - frappe
cd ~/frappe-bench

# Process management
sudo supervisorctl status
bench restart

# Site backup
bench --site erp.example.com backup

# Update site & apps
bench update --patch
```

---

## 📄 License
Released under the MIT License.
