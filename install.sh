#!/usr/bin/env bash
# ==============================================================================
# Frappe & ERPNext Automated Enterprise Installer
# Supports: Ubuntu 20.04 (Focal), 22.04 (Jammy), 24.04 (Noble), Debian 11/12
# Architectures: x86_64 (amd64), aarch64 (arm64)
# Versions: Frappe & ERPNext v14, v15, v16 (develop), v13
# Modes: Fresh Install or Coexistence With Other Services
# SSL: Let's Encrypt, Cloudflare (Proxy/Origin/Tunnel), Self-Signed, HTTP Only
# Apps: ERPNext, HRMS, Payments, Webshop, Helpdesk, CRM, Lending, Insights, Custom
# ==============================================================================

set -eo pipefail

# ------------------------------------------------------------------------------
# Color & Style Definitions
# ------------------------------------------------------------------------------
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    BOLD=''
    DIM=''
    NC=''
fi

# ------------------------------------------------------------------------------
# Logging Setup
# ------------------------------------------------------------------------------
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="/var/log/frappe-installer"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
LOG_FILE="${LOG_DIR}/install_${TIMESTAMP}.log"
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/install_${TIMESTAMP}.log"

log() {
    local level="$1"
    shift
    local msg="$*"
    local time_str
    time_str=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[$time_str] [$level] $msg" >> "$LOG_FILE"
}

msg_info() {
    echo -e "${CYAN}${BOLD}[INFO]${NC} $*"
    log "INFO" "$*"
}

msg_success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $*"
    log "SUCCESS" "$*"
}

msg_warn() {
    echo -e "${YELLOW}${BOLD}[WARNING]${NC} $*"
    log "WARNING" "$*"
}

msg_error() {
    echo -e "${RED}${BOLD}[ERROR]${NC} $*" >&2
    log "ERROR" "$*"
}

# ------------------------------------------------------------------------------
# Error Trap
# ------------------------------------------------------------------------------
cleanup_on_error() {
    local line=$1
    local cmd=$2
    local code=$3
    log "ERROR" "Installation failed on line $line: command '${cmd}' exited with status $code."
    echo -e "\n${RED}${BOLD}================================================================${NC}"
    echo -e "${RED}${BOLD}                       INSTALLATION FAILED                       ${NC}"
    echo -e "${RED}${BOLD}================================================================${NC}"
    echo -e "${RED}Error on line $line: command '${cmd}' exited with status $code.${NC}"
    echo -e "${YELLOW}Detailed execution logs are available at:${NC}"
    echo -e "  ${BOLD}${LOG_FILE}${NC}\n"
    echo -e "To view the last 30 lines of the log file:"
    echo -e "  ${CYAN}tail -n 30 ${LOG_FILE}${NC}\n"
    exit "$code"
}
trap 'cleanup_on_error $LINENO "$BASH_COMMAND" $?' ERR

# ------------------------------------------------------------------------------
# Default Variables
# ------------------------------------------------------------------------------
NON_INTERACTIVE=false
INSTALL_MODE="fresh"        # "fresh" or "existing"
ERP_VERSION="version-15"    # "version-14", "version-15", "version-16", "develop"
DOMAIN_TYPE="domain"        # "domain" or "local"
DOMAIN_NAME=""
SITE_NAME=""
HTTP_PORT="80"
SSL_TYPE="letsencrypt"      # "letsencrypt", "cloudflare", "selfsigned", "none"
CF_MODE="proxy"             # "proxy" (Full/Flexible) or "origin" (Origin CA) or "tunnel"
BENCH_USER=""
BENCH_NAME="frappe-bench"
DB_ROOT_PASS=""
ADMIN_PASS=""
ADMIN_EMAIL="admin@example.com"
ENABLE_UFW=false
ENABLE_BACKUP_CRON=true
SELECTED_APPS=("erpnext")
CUSTOM_APP_URL=""
CUSTOM_APP_BRANCH=""

# OS & Architecture info
OS_ID=""
OS_VERSION_ID=""
OS_CODENAME=""
CPU_ARCH=$(uname -m)

# ------------------------------------------------------------------------------
# Banner
# ------------------------------------------------------------------------------
print_banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
  ███████╗██████╗ ██████╗ ███╗   ██╗███████╗██╗  ██╗████████╗
  ██╔════╝██╔══██╗██╔══██╗████╗  ██║██╔════╝╚██╗██╔╝╚══██╔══╝
  █████╗  ██████╔╝██████╔╝██╔██╗ ██║█████╗   ╚███╔╝    ██║   
  ██╔══╝  ██╔══██╗██╔═══╝ ██║╚██╗██║██╔══╝   ██╔██╗    ██║   
  ███████╗██║  ██║██║     ██║ ╚████║███████╗██╔╝ ██╗   ██║   
  ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝   ╚═╝   
EOF
    echo -e "${NC}"
    echo -e "${BOLD}     Automated Multi-Version Installer for Linux (Ubuntu / Debian)${NC}"
    echo -e "${DIM}     Supports v14, v15, v16 | Cloudflare & Let's Encrypt SSL | Multi-Apps${NC}"
    echo -e "${CYAN}----------------------------------------------------------------------${NC}\n"
}

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------
prompt_with_default() {
    local prompt_text="$1"
    local default_val="$2"
    local result
    echo -ne "${BOLD}${prompt_text}${NC} [${GREEN}${default_val}${NC}]: " >&2
    read -r result
    echo "${result:-$default_val}"
}

prompt_secret_with_default() {
    local prompt_text="$1"
    local default_val="$2"
    local result
    if [ -n "$default_val" ]; then
        echo -ne "${BOLD}${prompt_text}${NC} [default: (press Enter to keep auto-generated)]: " >&2
    else
        echo -ne "${BOLD}${prompt_text}${NC}: " >&2
    fi
    read -rs result
    echo "" >&2
    echo "${result:-$default_val}"
}

generate_random_password() {
    local len="${1:-16}"
    tr -dc 'A-Za-z0-9!#%*+=' < /dev/urandom | head -c "$len" 2>/dev/null || date +%s | sha256sum | base64 | head -c "$len"
}

# ------------------------------------------------------------------------------
# System & Pre-flight Checks
# ------------------------------------------------------------------------------
check_privileges() {
    if [ "$(id -u)" -ne 0 ]; then
        msg_error "This script must be run with root or sudo privileges."
        echo -e "Please execute as: ${BOLD}sudo bash $0${NC}"
        exit 1
    fi
}

detect_system() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION_ID="${VERSION_ID:-unknown}"
        OS_CODENAME="${VERSION_CODENAME:-unknown}"
    else
        msg_error "Cannot detect operating system. /etc/os-release not found."
        exit 1
    fi

    msg_info "Detected OS: ${BOLD}${NAME:-$OS_ID} ${OS_VERSION_ID} (${OS_CODENAME})${NC} | Arch: ${BOLD}${CPU_ARCH}${NC}"

    case "$OS_ID" in
        ubuntu)
            if [[ "$OS_VERSION_ID" != "20.04" && "$OS_VERSION_ID" != "22.04" && "$OS_VERSION_ID" != "24.04" && "$OS_VERSION_ID" != "24.10" ]]; then
                msg_warn "Ubuntu version $OS_VERSION_ID is not officially tested. (Tested: 20.04, 22.04, 24.04 LTS)."
            fi
            ;;
        debian)
            if [[ "$OS_VERSION_ID" != "11" && "$OS_VERSION_ID" != "12" ]]; then
                msg_warn "Debian version $OS_VERSION_ID is not officially tested. (Tested: Debian 11 Bullseye, Debian 12 Bookworm)."
            fi
            ;;
        *)
            msg_warn "Distribution $OS_ID may not be fully supported. Proceeding anyway."
            ;;
    esac

    # RAM Check
    local total_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    msg_info "System RAM: ${BOLD}${total_ram_mb} MB${NC}"
    if [ "$total_ram_mb" -lt 1800 ]; then
        msg_warn "Frappe Bench and ERPNext require at least 2GB (2048 MB) of RAM."
        msg_warn "A swap file will be created automatically to prevent out-of-memory build errors."
    fi
}

detect_services() {
    msg_info "Checking existing system services..."
    local db_running=false
    local nginx_running=false
    local apache_running=false
    local redis_running=false

    if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
        db_running=true
        msg_warn "Database service (MariaDB/MySQL) is already RUNNING on this server."
    fi

    if systemctl is-active --quiet nginx; then
        nginx_running=true
        msg_warn "Nginx web server is already RUNNING on this server."
    fi

    if systemctl is-active --quiet apache2; then
        apache_running=true
        msg_warn "Apache web server is already RUNNING on this server."
    fi

    if systemctl is-active --quiet redis-server || systemctl is-active --quiet redis; then
        redis_running=true
        msg_info "Redis service is already RUNNING."
    fi

    # Check port 80 & 443
    if ss -tuln | grep -q ':80 '; then
        msg_warn "Port 80 is currently occupied by another process."
    fi
}

# ------------------------------------------------------------------------------
# Interactive Wizard
# ------------------------------------------------------------------------------
run_interactive_wizard() {
    echo -e "${BOLD}${MAGENTA}--- STEP 1: Installation Mode ---${NC}"
    echo "1) Fresh Installation (Default - cleans/configures new environment, sets up MariaDB, Nginx, Redis)"
    echo "2) Coexist With Existing Services (Safe mode - preserves existing DBs, asks for root password, avoids port conflicts)"
    local mode_choice
    mode_choice=$(prompt_with_default "Select installation mode [1-2]" "1")
    if [ "$mode_choice" == "2" ]; then
        INSTALL_MODE="existing"
        msg_info "Selected Mode: Coexist with Existing Services"
    else
        INSTALL_MODE="fresh"
        msg_info "Selected Mode: Fresh Installation"
    fi
    echo ""

    echo -e "${BOLD}${MAGENTA}--- STEP 2: ERPNext Version Selection ---${NC}"
    echo "1) ERPNext v15 (Current Long-Term Stable - Recommended for production)"
    echo "2) ERPNext v16 / Develop (Next generation - Features Python 3.12/3.14 via uv)"
    echo "3) ERPNext v14 (Legacy Stable - Python 3.10/3.11)"
    echo "4) ERPNext v13 (Legacy - Python 3.8/3.10)"
    local ver_choice
    ver_choice=$(prompt_with_default "Select ERPNext version [1-4]" "1")
    case "$ver_choice" in
        1) ERP_VERSION="version-15" ;;
        2) ERP_VERSION="version-16" ;;
        3) ERP_VERSION="version-14" ;;
        4) ERP_VERSION="version-13" ;;
        *) ERP_VERSION="version-15" ;;
    esac
    msg_info "Selected ERPNext Version: ${BOLD}${ERP_VERSION}${NC}"
    echo ""

    echo -e "${BOLD}${MAGENTA}--- STEP 3: Domain & Network Configuration ---${NC}"
    echo "1) Fully Qualified Domain Name (e.g., erp.yourdomain.com)"
    echo "2) Localhost / Server IP (e.g., 192.168.1.50 or site1.local)"
    local dom_choice
    dom_choice=$(prompt_with_default "Select domain setup [1-2]" "1")
    if [ "$dom_choice" == "2" ]; then
        DOMAIN_TYPE="local"
        local default_ip
        default_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
        DOMAIN_NAME=$(prompt_with_default "Enter server IP or local name" "$default_ip")
        SITE_NAME=$(prompt_with_default "Enter Frappe site name" "site1.local")
    else
        DOMAIN_TYPE="domain"
        DOMAIN_NAME=$(prompt_with_default "Enter your domain name (e.g., erp.example.com)" "erp.example.com")
        SITE_NAME="$DOMAIN_NAME"
    fi

    # Web port
    if [ "$INSTALL_MODE" == "existing" ] && ss -tuln | grep -q ':80 '; then
        msg_warn "Port 80 is in use. You can use port 80 with Nginx virtual hosts, or assign a custom HTTP port."
        HTTP_PORT=$(prompt_with_default "Enter HTTP web port" "80")
    else
        HTTP_PORT=$(prompt_with_default "Enter HTTP web port" "80")
    fi
    echo ""

    echo -e "${BOLD}${MAGENTA}--- STEP 4: SSL & Reverse Proxy Setup ---${NC}"
    if [ "$DOMAIN_TYPE" == "domain" ]; then
        echo "1) Let's Encrypt SSL (Regular free SSL certificate with automatic Certbot renewal)"
        echo "2) Cloudflare SSL & Proxy (Cloudflare Proxy / Flexible / Full / Origin CA integration)"
        echo "3) Self-Signed SSL (For testing HTTPS with custom certificate)"
        echo "4) None / HTTP Only (Behind existing reverse proxy / Cloudflare Tunnel / NPM)"
        local ssl_choice
        ssl_choice=$(prompt_with_default "Select SSL configuration [1-4]" "1")
        case "$ssl_choice" in
            1)
                SSL_TYPE="letsencrypt"
                ADMIN_EMAIL=$(prompt_with_default "Enter Administrator email for Let's Encrypt" "admin@${DOMAIN_NAME}")
                ;;
            2)
                SSL_TYPE="cloudflare"
                echo "  Cloudflare Sub-Options:"
                echo "  a) Cloudflare Proxy (Orange Cloud enabled: Nginx trusts Cloudflare Real-IPs, SSL handled by Cloudflare)"
                echo "  b) Cloudflare Origin CA (You will supply or generate origin certificates)"
                local cf_choice
                cf_choice=$(prompt_with_default "  Select Cloudflare mode [a/b]" "a")
                if [ "$cf_choice" == "b" ]; then
                    CF_MODE="origin"
                else
                    CF_MODE="proxy"
                fi
                ;;
            3)
                SSL_TYPE="selfsigned"
                ;;
            4)
                SSL_TYPE="none"
                ;;
            *)
                SSL_TYPE="letsencrypt"
                ;;
        esac
    else
        echo "1) None / HTTP Only (Recommended for local/IP address access)"
        echo "2) Self-Signed SSL (Enables HTTPS for IP/localhost)"
        local local_ssl
        local_ssl=$(prompt_with_default "Select SSL for local setup [1-2]" "1")
        if [ "$local_ssl" == "2" ]; then
            SSL_TYPE="selfsigned"
        else
            SSL_TYPE="none"
        fi
    fi
    msg_info "Selected SSL configuration: ${BOLD}${SSL_TYPE}${NC}"
    echo ""

    echo -e "${BOLD}${MAGENTA}--- STEP 5: System User & Security Credentials ---${NC}"
    # Target bench user
    local default_user="frappe"
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        default_user="$SUDO_USER"
    fi
    BENCH_USER=$(prompt_with_default "Enter system username to run Frappe Bench" "$default_user")

    # DB Root Password
    local default_db_pass
    default_db_pass=$(generate_random_password 16)
    if [ "$INSTALL_MODE" == "existing" ]; then
        echo -e "${YELLOW}Enter your EXISTING MariaDB/MySQL root password:${NC}"
        DB_ROOT_PASS=$(prompt_secret_with_default "MariaDB root password" "")
        while [ -z "$DB_ROOT_PASS" ]; do
            msg_warn "Password cannot be empty for existing database."
            DB_ROOT_PASS=$(prompt_secret_with_default "MariaDB root password" "")
        done
    else
        echo -e "${CYAN}Generated MariaDB root password:${NC} ${BOLD}${default_db_pass}${NC}"
        DB_ROOT_PASS=$(prompt_secret_with_default "MariaDB root password" "$default_db_pass")
    fi

    # Frappe Admin Password
    local default_admin_pass
    default_admin_pass=$(generate_random_password 16)
    echo -e "${CYAN}Generated Frappe Administrator password:${NC} ${BOLD}${default_admin_pass}${NC}"
    ADMIN_PASS=$(prompt_secret_with_default "Frappe Administrator password" "$default_admin_pass")
    echo ""

    echo -e "${BOLD}${MAGENTA}--- STEP 6: ERPNext & Additional Apps Selection ---${NC}"
    echo "Core App: Frappe Framework & ERPNext (${ERP_VERSION}) will be installed by default."
    echo "Select additional apps to automatically download and install into '${SITE_NAME}':"

    local inc_hrms inc_payments inc_webshop inc_helpdesk inc_crm inc_lending inc_custom
    inc_hrms=$(prompt_with_default "Install HRMS (Human Resources & Payroll)? [y/N]" "y")
    inc_payments=$(prompt_with_default "Install Payments (Payment Gateways)? [y/N]" "y")
    inc_webshop=$(prompt_with_default "Install Webshop (E-Commerce Storefront)? [y/N]" "n")
    inc_helpdesk=$(prompt_with_default "Install Helpdesk (Customer Support & Tickets)? [y/N]" "n")
    inc_crm=$(prompt_with_default "Install Frappe CRM? [y/N]" "n")
    inc_lending=$(prompt_with_default "Install Lending (Loan Management)? [y/N]" "n")
    inc_custom=$(prompt_with_default "Install Custom Git App? [y/N]" "n")

    SELECTED_APPS=("erpnext")
    [[ "$inc_payments" =~ ^[Yy]$ ]] && SELECTED_APPS+=("payments")
    [[ "$inc_hrms" =~ ^[Yy]$ ]] && SELECTED_APPS+=("hrms")
    [[ "$inc_webshop" =~ ^[Yy]$ ]] && SELECTED_APPS+=("webshop")
    [[ "$inc_helpdesk" =~ ^[Yy]$ ]] && SELECTED_APPS+=("helpdesk")
    [[ "$inc_crm" =~ ^[Yy]$ ]] && SELECTED_APPS+=("crm")
    [[ "$inc_lending" =~ ^[Yy]$ ]] && SELECTED_APPS+=("lending")

    if [[ "$inc_custom" =~ ^[Yy]$ ]]; then
        CUSTOM_APP_URL=$(prompt_with_default "Enter Custom App Git URL (e.g. https://github.com/user/app.git)" "")
        CUSTOM_APP_BRANCH=$(prompt_with_default "Enter Git branch" "main")
    fi
    echo ""

    echo -e "${BOLD}${MAGENTA}--- STEP 7: Production & Security Options ---${NC}"
    local ufw_choice
    ufw_choice=$(prompt_with_default "Configure UFW firewall (allow SSH, HTTP, HTTPS)? [y/N]" "n")
    [[ "$ufw_choice" =~ ^[Yy]$ ]] && ENABLE_UFW=true

    local cron_choice
    cron_choice=$(prompt_with_default "Enable automated daily database backup cron job? [Y/n]" "y")
    [[ "$cron_choice" =~ ^[Yy]$ ]] && ENABLE_BACKUP_CRON=true
    echo ""

    # Confirmation Screen
    print_summary_confirmation
}

print_summary_confirmation() {
    echo -e "\n${CYAN}${BOLD}================================================================${NC}"
    echo -e "${CYAN}${BOLD}               INSTALLATION CONFIGURATION SUMMARY                ${NC}"
    echo -e "${CYAN}${BOLD}================================================================${NC}"
    echo -e "  ${BOLD}Installation Mode :${NC} ${INSTALL_MODE}"
    echo -e "  ${BOLD}ERPNext Version   :${NC} ${ERP_VERSION}"
    echo -e "  ${BOLD}Operating System  :${NC} ${OS_ID} ${OS_VERSION_ID} (${CPU_ARCH})"
    echo -e "  ${BOLD}Frappe Bench User :${NC} ${BENCH_USER}"
    echo -e "  ${BOLD}Domain / Hostname :${NC} ${DOMAIN_NAME} (${DOMAIN_TYPE})"
    echo -e "  ${BOLD}Site Name         :${NC} ${SITE_NAME}"
    echo -e "  ${BOLD}HTTP Web Port     :${NC} ${HTTP_PORT}"
    echo -e "  ${BOLD}SSL Strategy      :${NC} ${SSL_TYPE} $( [ "$SSL_TYPE" == "cloudflare" ] && echo "($CF_MODE)" || echo "" )"
    echo -e "  ${BOLD}Installed Apps    :${NC} ${SELECTED_APPS[*]} $( [ -n "$CUSTOM_APP_URL" ] && echo "+ Custom App" || echo "" )"
    echo -e "  ${BOLD}Configure UFW     :${NC} ${ENABLE_UFW}"
    echo -e "  ${BOLD}Daily Auto-Backup :${NC} ${ENABLE_BACKUP_CRON}"
    echo -e "  ${BOLD}Log File Path     :${NC} ${LOG_FILE}"
    echo -e "${CYAN}================================================================${NC}\n"

    if [ "$NON_INTERACTIVE" = false ]; then
        local confirm
        confirm=$(prompt_with_default "Proceed with installation using these settings? [Y/n]" "y")
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            msg_warn "Installation aborted by user."
            exit 0
        fi
    fi
}

# ------------------------------------------------------------------------------
# System Preparation & Dependencies
# ------------------------------------------------------------------------------
setup_swap() {
    local total_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_ram_mb" -lt 2500 ]; then
        if [ ! -f /swapfile ] && [ "$(swapon --show | wc -l)" -le 1 ]; then
            msg_info "Creating 2GB swapfile to prevent out-of-memory errors during build..."
            fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048
            chmod 600 /swapfile
            mkswap /swapfile >> "$LOG_FILE" 2>&1
            swapon /swapfile >> "$LOG_FILE" 2>&1
            if ! grep -q '/swapfile' /etc/fstab; then
                echo '/swapfile none swap sw 0 0' >> /etc/fstab
            fi
            msg_success "2GB Swapfile activated."
        else
            msg_info "Swap space already exists."
        fi
    fi
}

install_system_packages() {
    msg_info "Updating system package repositories..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >> "$LOG_FILE" 2>&1

    msg_info "Installing core system dependencies and build libraries..."
    apt-get install -y \
        git curl wget gnupg2 ca-certificates lsb-release \
        software-properties-common build-essential libssl-dev \
        libffi-dev libfontconfig libxrender1 libxext6 xvfb \
        cron logrotate supervisor nginx pkg-config \
        libmariadb-dev-compat libmariadb-dev libcups2-dev \
        libpq-dev python3-dev python3-setuptools python3-pip \
        python3-venv pipx >> "$LOG_FILE" 2>&1

    msg_success "Core system packages installed."
}

# ------------------------------------------------------------------------------
# Python & UV Setup
# ------------------------------------------------------------------------------
setup_python_and_uv() {
    msg_info "Configuring Python environment with uv..."
    local user_home
    user_home=$(eval echo "~$BENCH_USER")

    # Install uv for the target bench user if not present
    if ! sudo -u "$BENCH_USER" test -f "${user_home}/.local/bin/uv"; then
        msg_info "Installing Astral uv package manager for user '${BENCH_USER}'..."
        sudo -u "$BENCH_USER" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' >> "$LOG_FILE" 2>&1
    fi

    # Determine recommended Python version based on Frappe version
    local target_py="3.11"
    case "$ERP_VERSION" in
        "version-13") target_py="3.10" ;;
        "version-14") target_py="3.11" ;; # Frappe v14 requires Python 3.10/3.11
        "version-15") target_py="3.11" ;; # Frappe v15 officially recommends 3.11 (supports 3.12)
        "version-16"|"develop") target_py="3.12" ;; # Frappe v16 recommends 3.12 or 3.14
    esac

    msg_info "Ensuring Python ${target_py} is available for Frappe ${ERP_VERSION}..."
    sudo -u "$BENCH_USER" bash -c "
        export PATH=\"${user_home}/.local/bin:\$PATH\"
        uv python install ${target_py}
    " >> "$LOG_FILE" 2>&1

    # Install frappe-bench CLI tool
    msg_info "Installing frappe-bench via uv..."
    sudo -u "$BENCH_USER" bash -c "
        export PATH=\"${user_home}/.local/bin:\$PATH\"
        uv tool install frappe-bench --force
    " >> "$LOG_FILE" 2>&1

    # Ensure uv and bench binaries are accessible globally and in user profile
    if [ -f "${user_home}/.local/bin/uv" ]; then
        ln -sf "${user_home}/.local/bin/uv" /usr/local/bin/uv 2>/dev/null || true
    fi
    if [ -f "${user_home}/.local/bin/bench" ]; then
        ln -sf "${user_home}/.local/bin/bench" /usr/local/bin/bench 2>/dev/null || true
    fi
    if [ -f "${user_home}/.bashrc" ] && ! grep -q '.local/bin' "${user_home}/.bashrc"; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${user_home}/.bashrc"
    fi

    msg_success "Python ${target_py} and frappe-bench installed successfully."
}

# ------------------------------------------------------------------------------
# Node.js & Yarn Setup
# ------------------------------------------------------------------------------
setup_nodejs_and_yarn() {
    msg_info "Configuring Node.js and Yarn..."
    local node_ver="20"
    if [ "$ERP_VERSION" == "version-13" ] || [ "$ERP_VERSION" == "version-14" ]; then
        node_ver="18"
    fi

    # Check if modern node is already installed
    local current_node=""
    if command -v node >/dev/null 2>&1; then
        current_node=$(node -v | cut -d'.' -f1 | tr -d 'v')
    fi

    if [ -z "$current_node" ] || [ "$current_node" -lt 18 ]; then
        msg_info "Installing Node.js ${node_ver}.x from NodeSource..."
        curl -fsSL "https://deb.nodesource.com/setup_${node_ver}.x" | bash - >> "$LOG_FILE" 2>&1
        apt-get install -y nodejs >> "$LOG_FILE" 2>&1
    fi

    if ! command -v yarn >/dev/null 2>&1; then
        msg_info "Installing Yarn package manager..."
        npm install -g yarn >> "$LOG_FILE" 2>&1
    fi
    msg_success "Node.js $(node -v) and Yarn $(yarn -v) ready."
}

# ------------------------------------------------------------------------------
# wkhtmltopdf Setup
# ------------------------------------------------------------------------------
setup_wkhtmltopdf() {
    msg_info "Setting up wkhtmltopdf with Qt patched support..."
    if command -v wkhtmltopdf >/dev/null 2>&1; then
        msg_info "wkhtmltopdf is already installed: $(wkhtmltopdf --version | head -n1)"
        return 0
    fi

    local arch="amd64"
    if [[ "$CPU_ARCH" == "aarch64" || "$CPU_ARCH" == "arm64" ]]; then
        arch="arm64"
    fi

    local deb_file="wkhtmltox_0.12.6.1-2.jammy_${arch}.deb"
    if [ "$OS_CODENAME" == "focal" ]; then
        deb_file="wkhtmltox_0.12.6.1-2.focal_${arch}.deb"
    fi

    local download_url="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/${deb_file}"
    local tmp_deb="/tmp/${deb_file}"

    msg_info "Downloading ${deb_file} from GitHub releases..."
    if wget -q -O "$tmp_deb" "$download_url"; then
        dpkg -i "$tmp_deb" >> "$LOG_FILE" 2>&1 || apt-get install -f -y >> "$LOG_FILE" 2>&1
        rm -f "$tmp_deb"
    else
        msg_warn "Direct download failed, falling back to apt package..."
        apt-get install -y wkhtmltopdf >> "$LOG_FILE" 2>&1 || true
    fi

    if command -v wkhtmltopdf >/dev/null 2>&1; then
        msg_success "wkhtmltopdf installed successfully."
    else
        msg_warn "Could not verify wkhtmltopdf installation. PDF printing might be degraded."
    fi
}

# ------------------------------------------------------------------------------
# MariaDB Setup
# ------------------------------------------------------------------------------
setup_mariadb() {
    msg_info "Configuring MariaDB Server..."

    if [ "$INSTALL_MODE" == "fresh" ]; then
        if ! command -v mariadb >/dev/null 2>&1 && ! command -v mysql >/dev/null 2>&1; then
            msg_info "Installing MariaDB Server and Client..."
            apt-get install -y mariadb-server mariadb-client >> "$LOG_FILE" 2>&1
        fi

        systemctl start mariadb || systemctl start mysql
        systemctl enable mariadb || systemctl enable mysql

        # Secure root user and set root password for localhost and 127.0.0.1
        msg_info "Securing MariaDB and setting root password..."
        mysql -u root <<EOF >> "$LOG_FILE" 2>&1 || true
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '${DB_ROOT_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    fi

    # Test connection
    if ! mysql -u root -p"${DB_ROOT_PASS}" -e "SELECT 1;" >/dev/null 2>&1; then
        # Try socket authentication if password check failed
        if mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
            mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}'; GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;" >> "$LOG_FILE" 2>&1
        else
            msg_error "Could not connect to MariaDB with provided root password."
            exit 1
        fi
    fi

    # Write Frappe-compliant MariaDB configuration
    msg_info "Applying Frappe UTF-8 mb4 MariaDB configuration..."
    local conf_dir="/etc/mysql/mariadb.conf.d"
    mkdir -p "$conf_dir" 2>/dev/null || conf_dir="/etc/mysql/conf.d"

    cat <<EOF > "${conf_dir}/99-frappe.cnf"
# Frappe Bench & ERPNext MariaDB Optimization
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
EOF

    systemctl restart mariadb || systemctl restart mysql
    msg_success "MariaDB configured with utf8mb4 and restarted."
}

# ------------------------------------------------------------------------------
# Redis Setup
# ------------------------------------------------------------------------------
setup_redis() {
    msg_info "Configuring Redis cache and queue server..."
    if ! command -v redis-server >/dev/null 2>&1; then
        apt-get install -y redis-server >> "$LOG_FILE" 2>&1
    fi
    systemctl start redis-server || systemctl start redis
    systemctl enable redis-server || systemctl enable redis
    msg_success "Redis server is running."
}

# ------------------------------------------------------------------------------
# Bench User & Directory Setup
# ------------------------------------------------------------------------------
setup_user() {
    if ! id -u "$BENCH_USER" >/dev/null 2>&1; then
        msg_info "Creating dedicated system user '${BENCH_USER}'..."
        useradd -m -s /bin/bash -G sudo "$BENCH_USER"
        local user_pass
        user_pass=$(generate_random_password 16)
        echo "${BENCH_USER}:${user_pass}" | chpasswd
        echo "${BENCH_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/frappe_${BENCH_USER}"
        chmod 440 "/etc/sudoers.d/frappe_${BENCH_USER}"
        msg_success "User '${BENCH_USER}' created with sudo privileges."
    else
        msg_info "User '${BENCH_USER}' already exists."
        # Ensure user is in sudo group
        usermod -aG sudo "$BENCH_USER" || true
    fi

    # Frappe requires home directory to be readable for Nginx static asset serving
    local user_home
    user_home=$(eval echo "~$BENCH_USER")
    chmod 755 "$user_home"
}

# ------------------------------------------------------------------------------
# Bench Initialization
# ------------------------------------------------------------------------------
initialize_bench() {
    local user_home
    user_home=$(eval echo "~$BENCH_USER")
    local bench_path="${user_home}/${BENCH_NAME}"

    if [ -d "$bench_path" ]; then
        msg_warn "Bench directory '${bench_path}' already exists. Skipping 'bench init'..."
        return 0
    fi

    msg_info "Initializing Frappe Bench with branch '${ERP_VERSION}'..."
    sudo -u "$BENCH_USER" bash -c "
        set -e
        export PATH=\"${user_home}/.local/bin:/usr/local/bin:/usr/bin:\$PATH\"
        cd \"${user_home}\"
        
        # Find exact python path installed by uv
        PY_PATH=\$(uv python find 3.11 2>/dev/null || uv python find 3.12 2>/dev/null || which python3)
        echo \"Using Python binary: \$PY_PATH\"
        
        bench init --frappe-branch \"${ERP_VERSION}\" --python \"\$PY_PATH\" \"${BENCH_NAME}\"
    " >> "$LOG_FILE" 2>&1

    # Ensure bench directory is readable for Nginx
    chmod -R o+rx "$bench_path" 2>/dev/null || true

    msg_success "Frappe Bench initialized at ${bench_path}."
}

# ------------------------------------------------------------------------------
# Site Creation
# ------------------------------------------------------------------------------
create_frappe_site() {
    local user_home
    user_home=$(eval echo "~$BENCH_USER")
    local bench_path="${user_home}/${BENCH_NAME}"
    local site_dir="${bench_path}/sites/${SITE_NAME}"

    if [ -d "$site_dir" ]; then
        msg_warn "Site '${SITE_NAME}' already exists. Skipping site creation..."
        return 0
    fi

    msg_info "Creating new Frappe site '${SITE_NAME}'..."
    sudo -u "$BENCH_USER" bash -c "
        set -e
        export PATH=\"${user_home}/.local/bin:/usr/local/bin:/usr/bin:\$PATH\"
        cd \"${bench_path}\"
        bench new-site \"${SITE_NAME}\" \
            --mariadb-root-username root \
            --mariadb-root-password \"${DB_ROOT_PASS}\" \
            --admin-password \"${ADMIN_PASS}\" \
            --no-mariadb-socket
        bench --site \"${SITE_NAME}\" set-maintenance-mode off
        bench --site \"${SITE_NAME}\" enable-scheduler
    " >> "$LOG_FILE" 2>&1

    msg_success "Site '${SITE_NAME}' created successfully."
}

# ------------------------------------------------------------------------------
# App Installation
# ------------------------------------------------------------------------------
install_frappe_apps() {
    local user_home
    user_home=$(eval echo "~$BENCH_USER")
    local bench_path="${user_home}/${BENCH_NAME}"

    msg_info "Installing selected apps for Frappe site '${SITE_NAME}'..."

    # Determine app branch based on ERP_VERSION
    local app_branch="$ERP_VERSION"
    if [ "$ERP_VERSION" == "version-16" ]; then
        app_branch="version-16"
    fi

    # Helper function to get and install an app safely with fallback to default branch
    install_single_app() {
        local app_name="$1"
        local branch="$2"
        local git_url="${3:-}"

        msg_info "--> Processing App: ${BOLD}${app_name}${NC} (branch: ${branch})..."
        sudo -u "$BENCH_USER" bash -c "
            set -e
            export PATH=\"${user_home}/.local/bin:/usr/local/bin:/usr/bin:\$PATH\"
            cd \"${bench_path}\"
            
            if [ ! -d \"apps/${app_name}\" ]; then
                if [ -n \"${git_url}\" ]; then
                    bench get-app --branch \"${branch}\" \"${git_url}\" 2>/dev/null || bench get-app \"${git_url}\"
                else
                    bench get-app --branch \"${branch}\" \"${app_name}\" 2>/dev/null || bench get-app \"${app_name}\"
                fi
            else
                echo \"App ${app_name} already downloaded.\"
            fi

            bench --site \"${SITE_NAME}\" install-app \"${app_name}\"
        " >> "$LOG_FILE" 2>&1
        msg_success "App '${app_name}' installed on '${SITE_NAME}'."
    }

    # Order of installation: payments -> erpnext -> hrms -> webshop -> other apps
    for app in "${SELECTED_APPS[@]}"; do
        if [ "$app" == "payments" ]; then
            install_single_app "payments" "$app_branch"
        fi
    done

    for app in "${SELECTED_APPS[@]}"; do
        if [ "$app" == "erpnext" ]; then
            install_single_app "erpnext" "$app_branch"
        fi
    done

    for app in "${SELECTED_APPS[@]}"; do
        if [[ "$app" != "payments" && "$app" != "erpnext" ]]; then
            install_single_app "$app" "$app_branch"
        fi
    done

    # Custom App if specified
    if [ -n "$CUSTOM_APP_URL" ]; then
        local custom_name
        custom_name=$(basename -s .git "$CUSTOM_APP_URL")
        msg_info "Installing custom app '${custom_name}' from ${CUSTOM_APP_URL}..."
        install_single_app "$custom_name" "$CUSTOM_APP_BRANCH" "$CUSTOM_APP_URL"
    fi
}

# ------------------------------------------------------------------------------
# Production Setup (Supervisor & Nginx)
# ------------------------------------------------------------------------------
configure_production() {
    local user_home
    user_home=$(eval echo "~$BENCH_USER")
    local bench_path="${user_home}/${BENCH_NAME}"

    msg_info "Setting up Production Environment with Nginx & Supervisor..."

    # Configure DNS multitenancy
    sudo -u "$BENCH_USER" bash -c "
        export PATH=\"${user_home}/.local/bin:\$PATH\"
        cd \"${bench_path}\"
        bench config dns_multitenant on
    " >> "$LOG_FILE" 2>&1

    # Add custom domain to site if specified
    if [ "$DOMAIN_TYPE" == "domain" ] && [ "$DOMAIN_NAME" != "$SITE_NAME" ]; then
        sudo -u "$BENCH_USER" bash -c "
            export PATH=\"${user_home}/.local/bin:\$PATH\"
            cd \"${bench_path}\"
            bench setup add-domain \"${DOMAIN_NAME}\" --site \"${SITE_NAME}\"
        " >> "$LOG_FILE" 2>&1
    fi

    # Set custom HTTP port if chosen
    if [ "$HTTP_PORT" != "80" ]; then
        sudo -u "$BENCH_USER" bash -c "
            export PATH=\"${user_home}/.local/bin:\$PATH\"
            cd \"${bench_path}\"
            bench set-nginx-port \"${SITE_NAME}\" \"${HTTP_PORT}\"
        " >> "$LOG_FILE" 2>&1
    fi

    # Generate Nginx and Supervisor configs
    sudo -u "$BENCH_USER" bash -c "
        export PATH=\"${user_home}/.local/bin:\$PATH\"
        cd \"${bench_path}\"
        bench setup nginx --yes
        bench setup supervisor --yes
    " >> "$LOG_FILE" 2>&1

    # Ensure log format 'main' is defined for Debian/Ubuntu Nginx
    if [ ! -f /etc/nginx/conf.d/00-frappe-log-format.conf ]; then
        cat << 'EOF' > /etc/nginx/conf.d/00-frappe-log-format.conf
log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                '$status $body_bytes_sent "$http_referer" '
                '"$http_user_agent" "$http_x_forwarded_for"';
EOF
    fi

    # Link supervisor config
    if [ -f "${bench_path}/config/supervisor.conf" ]; then
        ln -sf "${bench_path}/config/supervisor.conf" /etc/supervisor/conf.d/frappe-bench.conf
    fi

    # Link nginx config
    if [ -f "${bench_path}/config/nginx.conf" ]; then
        ln -sf "${bench_path}/config/nginx.conf" /etc/nginx/conf.d/frappe-bench.conf
        # Disable default Nginx site if it conflicts on port 80
        if [ "$INSTALL_MODE" == "fresh" ] && [ -f /etc/nginx/sites-enabled/default ]; then
            rm -f /etc/nginx/sites-enabled/default
        fi
    fi

    # Enable and start supervisor and nginx for automatic reboot recovery
    systemctl enable supervisor >> "$LOG_FILE" 2>&1 || true
    systemctl start supervisor >> "$LOG_FILE" 2>&1 || true
    systemctl enable nginx >> "$LOG_FILE" 2>&1 || true

    # Update and start supervisor processes
    supervisorctl reread >> "$LOG_FILE" 2>&1 || true
    supervisorctl update >> "$LOG_FILE" 2>&1 || true
    supervisorctl restart all >> "$LOG_FILE" 2>&1 || true

    # Test and reload Nginx
    nginx -t >> "$LOG_FILE" 2>&1
    systemctl reload nginx >> "$LOG_FILE" 2>&1 || systemctl restart nginx >> "$LOG_FILE" 2>&1

    msg_success "Production services configured and running."
}

# ------------------------------------------------------------------------------
# SSL & Cloudflare Configuration
# ------------------------------------------------------------------------------
configure_ssl() {
    local user_home
    user_home=$(eval echo "~$BENCH_USER")
    local bench_path="${user_home}/${BENCH_NAME}"

    case "$SSL_TYPE" in
        "letsencrypt")
            msg_info "Configuring Let's Encrypt SSL certificate via Certbot..."
            apt-get install -y certbot python3-certbot-nginx >> "$LOG_FILE" 2>&1
            
            # Run Certbot non-interactively
            if certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect >> "$LOG_FILE" 2>&1; then
                msg_success "Let's Encrypt SSL installed successfully with automatic renewal."
            else
                msg_warn "Certbot automated issuance failed. Check DNS propagation for '$DOMAIN_NAME'."
                msg_warn "You can manually retry with: certbot --nginx -d $DOMAIN_NAME"
            fi
            ;;

        "cloudflare")
            msg_info "Configuring Cloudflare Real-IP and Proxy settings in Nginx..."
            local cf_conf="/etc/nginx/conf.d/00-cloudflare.conf"

            # Create Cloudflare Real-IP configuration
            cat << 'EOF' > "$cf_conf"
# Cloudflare IPv4 and IPv6 Trusted Ranges & Real IP Mapping
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 131.0.72.0/22;
set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2a06:98c0::/29;
set_real_ip_from 2c0f:f248::/32;

real_ip_header CF-Connecting-IP;
EOF
            nginx -t >> "$LOG_FILE" 2>&1
            systemctl reload nginx >> "$LOG_FILE" 2>&1
            msg_success "Cloudflare Real-IP configuration applied."

            if [ "$CF_MODE" == "proxy" ]; then
                msg_info "Cloudflare Proxy Mode: SSL is managed at Cloudflare Edge (Flexible/Full)."
            fi
            ;;

        "selfsigned")
            msg_info "Generating 2048-bit Self-Signed SSL Certificate..."
            local ssl_dir="/etc/ssl/frappe"
            mkdir -p "$ssl_dir"
            local cert_key="${ssl_dir}/${DOMAIN_NAME}.key"
            local cert_crt="${ssl_dir}/${DOMAIN_NAME}.crt"

            openssl req -x509 -nodes -days 730 -newkey rsa:2048 \
                -keyout "$cert_key" \
                -out "$cert_crt" \
                -subj "/C=US/ST=State/L=City/O=Organization/CN=${DOMAIN_NAME}" >> "$LOG_FILE" 2>&1

            msg_info "Self-signed certificate generated at ${cert_crt}."
            ;;

        "none")
            msg_info "SSL configuration skipped (HTTP only)."
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Firewall Setup (UFW)
# ------------------------------------------------------------------------------
configure_firewall() {
    if [ "$ENABLE_UFW" = true ]; then
        msg_info "Configuring UFW Firewall rules..."
        apt-get install -y ufw >> "$LOG_FILE" 2>&1
        ufw allow 22/tcp || ufw allow ssh
        ufw allow "${HTTP_PORT}/tcp"
        ufw allow 443/tcp
        echo "y" | ufw enable >> "$LOG_FILE" 2>&1 || true
        msg_success "UFW enabled: ports 22, ${HTTP_PORT}, 443 allowed."
    fi
}

# ------------------------------------------------------------------------------
# Automatic Database Backup Cron
# ------------------------------------------------------------------------------
configure_backup_cron() {
    if [ "$ENABLE_BACKUP_CRON" = true ]; then
        msg_info "Setting up daily Frappe backup cron job..."
        local user_home
        user_home=$(eval echo "~$BENCH_USER")
        local bench_path="${user_home}/${BENCH_NAME}"
        local cron_file="/etc/cron.d/frappe_backup_${BENCH_USER}"

        cat <<EOF > "$cron_file"
# Automated daily backup of all Frappe sites at 02:00 AM
0 2 * * * ${BENCH_USER} cd ${bench_path} && ${user_home}/.local/bin/bench --site all backup >> ${user_home}/frappe_backup.log 2>&1
EOF
        chmod 644 "$cron_file"
        msg_success "Automated daily backup cron job registered."
    fi
}

# ------------------------------------------------------------------------------
# Final Summary Output
# ------------------------------------------------------------------------------
print_final_summary() {
    local protocol="http"
    if [ "$SSL_TYPE" == "letsencrypt" ] || [ "$SSL_TYPE" == "selfsigned" ] || [ "$SSL_TYPE" == "cloudflare" ]; then
        protocol="https"
    fi

    local access_url="${protocol}://${DOMAIN_NAME}"
    if [ "$HTTP_PORT" != "80" ] && [ "$HTTP_PORT" != "443" ]; then
        access_url="${access_url}:${HTTP_PORT}"
    fi

    local user_home
    user_home=$(eval echo "~$BENCH_USER")
    local bench_path="${user_home}/${BENCH_NAME}"

    echo -e "\n${GREEN}${BOLD}================================================================${NC}"
    echo -e "${GREEN}${BOLD}        🎉 FRAPPE & ERPNEXT INSTALLATION COMPLETE! 🎉           ${NC}"
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo -e "  ${BOLD}Site Web URL      :${NC} ${CYAN}${BOLD}${access_url}${NC}"
    echo -e "  ${BOLD}Frappe Admin User :${NC} Administrator"
    echo -e "  ${BOLD}Admin Password    :${NC} ${YELLOW}${BOLD}${ADMIN_PASS}${NC}"
    echo -e "  ${BOLD}Bench Path        :${NC} ${bench_path}"
    echo -e "  ${BOLD}System User       :${NC} ${BENCH_USER}"
    echo -e "  ${BOLD}MariaDB Root User :${NC} root"
    echo -e "  ${BOLD}MariaDB Password  :${NC} ${YELLOW}${BOLD}${DB_ROOT_PASS}${NC}"
    echo -e "  ${BOLD}ERPNext Version   :${NC} ${ERP_VERSION}"
    echo -e "  ${BOLD}Installed Apps    :${NC} ${SELECTED_APPS[*]}"
    echo -e "  ${BOLD}Installation Log  :${NC} ${LOG_FILE}"
    echo -e "${GREEN}================================================================${NC}"

    echo -e "\n${BOLD}${MAGENTA}--- Useful Bench Commands ---${NC}"
    echo -e "  Switch to user  : ${CYAN}su - ${BENCH_USER}${NC}"
    echo -e "  Go to bench     : ${CYAN}cd ${bench_path}${NC}"
    echo -e "  Check status    : ${CYAN}sudo supervisorctl status${NC}"
    echo -e "  Restart bench   : ${CYAN}bench restart${NC}"
    echo -e "  Site backup     : ${CYAN}bench --site ${SITE_NAME} backup${NC}"
    echo -e "  Install app     : ${CYAN}bench get-app <app_name> && bench --site ${SITE_NAME} install-app <app_name>${NC}"
    echo -e "  Update bench    : ${CYAN}bench update${NC}\n"
}

# ------------------------------------------------------------------------------
# CLI Flags Parser (for Non-Interactive Automation)
# ------------------------------------------------------------------------------
parse_cli_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --non-interactive|-y)
                NON_INTERACTIVE=true
                shift
                ;;
            --mode)
                INSTALL_MODE="$2"
                shift 2
                ;;
            --version)
                case "$2" in
                    13|v13|version-13) ERP_VERSION="version-13" ;;
                    14|v14|version-14) ERP_VERSION="version-14" ;;
                    15|v15|version-15) ERP_VERSION="version-15" ;;
                    16|v16|version-16) ERP_VERSION="version-16" ;;
                    develop) ERP_VERSION="develop" ;;
                    *) ERP_VERSION="$2" ;;
                esac
                shift 2
                ;;
            --domain)
                DOMAIN_NAME="$2"
                DOMAIN_TYPE="domain"
                shift 2
                ;;
            --site)
                SITE_NAME="$2"
                shift 2
                ;;
            --port)
                HTTP_PORT="$2"
                shift 2
                ;;
            --ssl)
                SSL_TYPE="$2"
                shift 2
                ;;
            --cf-mode)
                CF_MODE="$2"
                shift 2
                ;;
            --user)
                BENCH_USER="$2"
                shift 2
                ;;
            --admin-pass)
                ADMIN_PASS="$2"
                shift 2
                ;;
            --db-pass)
                DB_ROOT_PASS="$2"
                shift 2
                ;;
            --email)
                ADMIN_EMAIL="$2"
                shift 2
                ;;
            --apps)
                IFS=',' read -r -a SELECTED_APPS <<< "$2"
                shift 2
                ;;
            --custom-app)
                CUSTOM_APP_URL="$2"
                shift 2
                ;;
            --custom-branch)
                CUSTOM_APP_BRANCH="$2"
                shift 2
                ;;
            --ufw)
                ENABLE_UFW=true
                shift
                ;;
            --no-cron)
                ENABLE_BACKUP_CRON=false
                shift
                ;;
            --help|-h)
                echo "Usage: sudo bash install.sh [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --non-interactive, -y   Run non-interactively without prompting"
                echo "  --mode <fresh|existing> Installation mode (default: fresh)"
                echo "  --version <14|15|16>    ERPNext version (default: 15)"
                echo "  --domain <domain.com>   Domain name or server IP"
                echo "  --site <site_name>      Frappe site name (default: domain name)"
                echo "  --port <port>           HTTP Web Port (default: 80)"
                echo "  --ssl <type>            SSL type: letsencrypt | cloudflare | selfsigned | none"
                echo "  --cf-mode <proxy|origin> Cloudflare mode (default: proxy)"
                echo "  --user <username>       Bench system user (default: frappe)"
                echo "  --admin-pass <pass>     Frappe Administrator password"
                echo "  --db-pass <pass>        MariaDB root password"
                echo "  --email <email>         Admin email for SSL alerts"
                echo "  --apps <app1,app2>      Comma-separated apps list (e.g., erpnext,hrms,payments)"
                echo "  --custom-app <git_url>  Custom git app repository URL"
                echo "  --custom-branch <branch> Git branch for custom app (default: main)"
                echo "  --ufw                   Enable UFW firewall"
                echo "  --no-cron               Disable automated backup cron"
                echo "  --help, -h              Display this help message"
                exit 0
                ;;
            *)
                msg_error "Unknown argument: $1"
                echo "Use --help for usage instructions."
                exit 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Main Execution Entry Point
# ------------------------------------------------------------------------------
main() {
    # Check for --help or -h first before requiring root privileges
    for arg in "$@"; do
        if [ "$arg" == "--help" ] || [ "$arg" == "-h" ]; then
            parse_cli_arguments "$@"
            exit 0
        fi
    done

    print_banner
    check_privileges
    detect_system
    detect_services

    parse_cli_arguments "$@"

    if [ "$NON_INTERACTIVE" = false ]; then
        run_interactive_wizard
    else
        # Set defaults if missing in non-interactive mode
        [ -z "$BENCH_USER" ] && BENCH_USER="frappe"
        [ -z "$DOMAIN_NAME" ] && DOMAIN_NAME=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
        [ -z "$SITE_NAME" ] && SITE_NAME="$DOMAIN_NAME"
        [ -z "$DB_ROOT_PASS" ] && DB_ROOT_PASS=$(generate_random_password 16)
        [ -z "$ADMIN_PASS" ] && ADMIN_PASS=$(generate_random_password 16)
        print_summary_confirmation
    fi

    msg_info "Starting installation process at $(date)..."
    setup_swap
    setup_user
    install_system_packages
    setup_python_and_uv
    setup_nodejs_and_yarn
    setup_wkhtmltopdf
    setup_mariadb
    setup_redis
    initialize_bench
    create_frappe_site
    configure_production
    install_frappe_apps
    # Restart background workers/web to load new apps and reload Nginx
    supervisorctl restart all >> "$LOG_FILE" 2>&1 || true
    systemctl reload nginx >> "$LOG_FILE" 2>&1 || true
    configure_ssl
    configure_firewall
    configure_backup_cron

    print_final_summary
}

main "$@"
