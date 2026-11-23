#!/usr/bin/env bash
# ==============================================================================
# Script Name   : create_erpnext_lxc.sh
# Description   : Automated Proxmox VE LXC Container Provisioner for Frappe & ERPNext
# Author        : CodeProMaxTech (https://github.com/codepromaxtech)
# License       : MIT
# Requirements  : Proxmox VE 7.x / 8.x (must be executed as root on PVE host)
# ==============================================================================

set -euo pipefail

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

msg_info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
msg_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
msg_warn()    { echo -e "${YELLOW}[WARNING]${NC} $*"; }
msg_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Helper to prompt with default
prompt_with_default() {
    local prompt_msg="$1"
    local default_val="$2"
    local user_val
    read -r -p "$(echo -e "${BOLD}${prompt_msg}${NC} [${GREEN}${default_val}${NC}]: ")" user_val
    echo "${user_val:-$default_val}"
}

# Helper to prompt secret with default
prompt_secret() {
    local prompt_msg="$1"
    local default_val="$2"
    local user_val
    read -r -s -p "$(echo -e "${BOLD}${prompt_msg}${NC} [${GREEN}${default_val}${NC}]: ")" user_val
    echo "" >&2
    echo "${user_val:-$default_val}"
}

# Generate random secure string
generate_random_password() {
    local length="${1:-16}"
    tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length" || head /dev/urandom | tr -dc A-Za-z0-9 | head -c "$length"
}

print_banner() {
    clear 2>/dev/null || true
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
  ____                                    __   __ _____    _     __   ______ 
 |  _ \ _ __ _____  ___ __ ___   _____  __\ \ / /| ____|  | |    \ \ / / ___|
 | |_) | '__/ _ \ \/ / '_ ` _ \ / _ \ \/ / \ V / |  _|    | |     \ V / |    
 |  __/| | | (_) >  <| | | | | | (_) >  <   | |  | |___ _ | |___   | || |___ 
 |_|   |_|  \___/_/\_\_| |_| |_|\___/_/\_\  |_|  |_____(_)|_____|  |_| \____|
               Enterprise ERPNext Proxmox LXC Provisioner
EOF
    echo -e "${NC}"
}

# ------------------------------------------------------------------------------
# Pre-flight Checks
# ------------------------------------------------------------------------------
check_proxmox_environment() {
    if [ "$(id -u)" -ne 0 ]; then
        msg_error "This script must be executed as root on a Proxmox VE host."
        exit 1
    fi

    if ! command -v pct >/dev/null 2>&1 || ! command -v pveam >/dev/null 2>&1; then
        msg_error "Proxmox VE container commands (pct, pveam, pvesm) not found!"
        msg_error "This script is designed to run directly on a Proxmox VE node."
        msg_info "To install ERPNext on a standard Ubuntu server, use 'install.sh' instead."
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Hardware & Resource Gathering
# ------------------------------------------------------------------------------
gather_proxmox_defaults() {
    # Suggest next container ID
    SUGGESTED_ID=$(pvesh get /cluster/nextid 2>/dev/null || echo "100")

    # Detect RootFS Storage Pool (content rootdir)
    SUGGESTED_ROOT_STORAGE=$(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 {print $1}' | head -n1 || echo "local-lvm")
    [ -z "$SUGGESTED_ROOT_STORAGE" ] && SUGGESTED_ROOT_STORAGE="local-lvm"

    # Detect Template Storage Pool (content vztmpl)
    SUGGESTED_TMPL_STORAGE=$(pvesm status -content vztmpl 2>/dev/null | awk 'NR>1 {print $1}' | head -n1 || echo "local")
    [ -z "$SUGGESTED_TMPL_STORAGE" ] && SUGGESTED_TMPL_STORAGE="local"

    # Host CPU cores
    HOST_CORES=$(nproc 2>/dev/null || echo "4")
    DEFAULT_CORES=$(( HOST_CORES > 2 ? 4 : 2 ))
}

# ------------------------------------------------------------------------------
# Interactive Wizard
# ------------------------------------------------------------------------------
run_lxc_wizard() {
    echo -e "${BOLD}${PURPLE}--- 1. Proxmox Container Specifications ---${NC}"
    CT_ID=$(prompt_with_default "Enter Container ID (CTID)" "$SUGGESTED_ID")
    CT_NAME=$(prompt_with_default "Enter Container Hostname" "erpnext-lxc")
    STORAGE_ROOT=$(prompt_with_default "Target RootFS Storage Pool" "$SUGGESTED_ROOT_STORAGE")
    STORAGE_TMPL=$(prompt_with_default "Template Storage Pool" "$SUGGESTED_TMPL_STORAGE")
    DISK_SIZE=$(prompt_with_default "Container Disk Size in GB (minimum 16GB recommended)" "20")
    RAM_SIZE=$(prompt_with_default "Container RAM in MB (minimum 4096MB recommended)" "4096")
    SWAP_SIZE=$(prompt_with_default "Container Swap in MB" "2048")
    CORE_COUNT=$(prompt_with_default "CPU Cores allocated" "$DEFAULT_CORES")

    echo -e "\n${BOLD}${PURPLE}--- 2. OS Template (Ubuntu) ---${NC}"
    echo "  1) Ubuntu 24.04 LTS (Noble - Recommended)"
    echo "  2) Ubuntu 22.04 LTS (Jammy)"
    local os_choice
    os_choice=$(prompt_with_default "Select Ubuntu template" "1")
    if [ "$os_choice" == "2" ]; then
        UBUNTU_SERIES="ubuntu-22.04"
    else
        UBUNTU_SERIES="ubuntu-24.04"
    fi

    echo -e "\n${BOLD}${PURPLE}--- 3. Network Configuration ---${NC}"
    NET_BRIDGE=$(prompt_with_default "Network Bridge interface" "vmbr0")
    echo "  1) DHCP (Automatic IP assignment - Recommended)"
    echo "  2) Static IP"
    local net_mode
    net_mode=$(prompt_with_default "Network IP Configuration Mode" "1")
    if [ "$net_mode" == "2" ]; then
        STATIC_IP=$(prompt_with_default "Enter Static IP with CIDR (e.g. 192.168.1.150/24)" "192.168.1.150/24")
        STATIC_GW=$(prompt_with_default "Enter Gateway IP (e.g. 192.168.1.1)" "192.168.1.1")
        STATIC_DNS=$(prompt_with_default "Enter Nameserver DNS (e.g. 1.1.1.1 8.8.8.8)" "1.1.1.1")
        NET_CONFIG="name=eth0,bridge=${NET_BRIDGE},ip=${STATIC_IP},gw=${STATIC_GW}"
    else
        NET_CONFIG="name=eth0,bridge=${NET_BRIDGE},ip=dhcp"
        STATIC_DNS=""
    fi

    echo -e "\n${BOLD}${PURPLE}--- 4. ERPNext Configuration ---${NC}"
    echo "  1) Version 15 (Current Stable - Recommended)"
    echo "  2) Version 14 (Previous Stable)"
    echo "  3) Version 16 (Develop / Next Gen)"
    echo "  4) Version 13 (Legacy)"
    local ver_choice
    ver_choice=$(prompt_with_default "Select ERPNext Version" "1")
    case "$ver_choice" in
        2) ERP_VERSION="14" ;;
        3) ERP_VERSION="16" ;;
        4) ERP_VERSION="13" ;;
        *) ERP_VERSION="15" ;;
    esac

    BENCH_USER=$(prompt_with_default "Frappe Bench System User" "frappe")
    SITE_NAME=$(prompt_with_default "Frappe Site Name (e.g. erp.local or domain.com)" "erp.local")
    
    local default_pass
    default_pass=$(generate_random_password 16)
    ADMIN_PASS=$(prompt_secret "Frappe Administrator Password" "$default_pass")
    DB_PASS=$(prompt_secret "MariaDB Root Password" "$default_pass")

    echo -e "\n${BOLD}${PURPLE}--- 5. Applications Selection ---${NC}"
    echo "  1) ERPNext core only"
    echo "  2) ERPNext + HRMS (Human Resources & Payroll)"
    echo "  3) ERPNext + HRMS + Payments + Webshop"
    local apps_choice
    apps_choice=$(prompt_with_default "Select applications bundle" "1")
    case "$apps_choice" in
        2) APPS_LIST="erpnext,hrms" ;;
        3) APPS_LIST="erpnext,hrms,payments,webshop" ;;
        *) APPS_LIST="erpnext" ;;
    esac

    echo -e "\n${BOLD}${PURPLE}--- 6. Web & SSL Strategy ---${NC}"
    HTTP_PORT=$(prompt_with_default "HTTP Web Port" "80")
    echo "  1) None / Plain HTTP (Standard for internal/NAT or reverse proxy setups)"
    echo "  2) Let's Encrypt automated SSL"
    echo "  3) Cloudflare Proxy / Real-IP mode"
    echo "  4) Self-Signed SSL"
    local ssl_choice
    ssl_choice=$(prompt_with_default "Select SSL strategy" "1")
    case "$ssl_choice" in
        2) SSL_TYPE="letsencrypt" ;;
        3) SSL_TYPE="cloudflare" ;;
        4) SSL_TYPE="selfsigned" ;;
        *) SSL_TYPE="none" ;;
    esac

    ADMIN_EMAIL=""
    if [ "$SSL_TYPE" == "letsencrypt" ]; then
        ADMIN_EMAIL=$(prompt_with_default "Administrator Email for SSL expiry alerts" "admin@${SITE_NAME}")
    fi

    echo -e "\n${CYAN}================================================================${NC}"
    echo -e "                   ${BOLD}PROVISIONING SUMMARY${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo -e "  ${BOLD}Container ID     :${NC} ${CT_ID}"
    echo -e "  ${BOLD}Hostname         :${NC} ${CT_NAME}"
    echo -e "  ${BOLD}OS Template      :${NC} ${UBUNTU_SERIES} standard"
    echo -e "  ${BOLD}Storage Pool     :${NC} ${STORAGE_ROOT} (${DISK_SIZE}GB Disk)"
    echo -e "  ${BOLD}Compute          :${NC} ${CORE_COUNT} vCPUs, ${RAM_SIZE}MB RAM, ${SWAP_SIZE}MB Swap"
    echo -e "  ${BOLD}Network          :${NC} ${NET_CONFIG}"
    echo -e "  ${BOLD}ERPNext Version  :${NC} ${ERP_VERSION}"
    echo -e "  ${BOLD}Site Name        :${NC} ${SITE_NAME}"
    echo -e "  ${BOLD}Installed Apps   :${NC} ${APPS_LIST}"
    echo -e "  ${BOLD}HTTP Port        :${NC} ${HTTP_PORT}"
    echo -e "  ${BOLD}SSL Strategy     :${NC} ${SSL_TYPE}"
    echo -e "${CYAN}================================================================${NC}\n"

    local confirm
    confirm=$(prompt_with_default "Proceed with container creation and installation? [Y/n]" "y")
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        msg_warn "Proxmox LXC provisioning aborted by user."
        exit 0
    fi
}

# ------------------------------------------------------------------------------
# Template Acquisition
# ------------------------------------------------------------------------------
prepare_template() {
    msg_info "Updating Proxmox appliance catalogue..."
    pveam update >> /tmp/pveam_update.log 2>&1 || true

    msg_info "Checking for available '${UBUNTU_SERIES}' template..."
    TEMPLATE_REMOTE=$(pveam available | grep "${UBUNTU_SERIES}-standard" | sort -r | head -n1 | awk '{print $1}' || echo "")

    if [ -z "$TEMPLATE_REMOTE" ]; then
        msg_warn "Exact template '${UBUNTU_SERIES}-standard' not found in online catalogue. Trying fallback search..."
        TEMPLATE_REMOTE=$(pveam available | grep "ubuntu" | sort -r | head -n1 | awk '{print $1}')
    fi

    local tmpl_filename
    tmpl_filename=$(basename "$TEMPLATE_REMOTE")
    TEMPLATE_STORAGE_PATH="${STORAGE_TMPL}:vztmpl/${tmpl_filename}"

    # Check if template already cached in template storage
    if ! pvesm list "$STORAGE_TMPL" 2>/dev/null | grep -q "$tmpl_filename"; then
        msg_info "Downloading template '${tmpl_filename}' to storage '${STORAGE_TMPL}'..."
        pveam download "$STORAGE_TMPL" "$TEMPLATE_REMOTE"
        msg_success "Template downloaded."
    else
        msg_info "Template '${tmpl_filename}' is already available in storage '${STORAGE_TMPL}'."
    fi
}

# ------------------------------------------------------------------------------
# Container Creation & Configuration
# ------------------------------------------------------------------------------
create_lxc_container() {
    if pct status "$CT_ID" >/dev/null 2>&1; then
        msg_error "Container ID ${CT_ID} already exists on this Proxmox node!"
        exit 1
    fi

    msg_info "Creating LXC Container ${CT_ID} (${CT_NAME})..."
    
    local dns_arg=""
    if [ -n "${STATIC_DNS:-}" ]; then
        dns_arg="--nameserver ${STATIC_DNS}"
    fi

    # Unprivileged container with nesting=1 and keyctl=1 (essential for Redis & MariaDB systemd services)
    pct create "$CT_ID" "$TEMPLATE_STORAGE_PATH" \
        --hostname "$CT_NAME" \
        --cores "$CORE_COUNT" \
        --memory "$RAM_SIZE" \
        --swap "$SWAP_SIZE" \
        --rootfs "${STORAGE_ROOT}:${DISK_SIZE}" \
        --net0 "${NET_CONFIG}" \
        ${dns_arg} \
        --ostype ubuntu \
        --unprivileged 1 \
        --features nesting=1,keyctl=1 \
        --onboot 1

    msg_success "LXC Container ${CT_ID} created successfully."

    msg_info "Starting container ${CT_ID}..."
    pct start "$CT_ID"

    msg_info "Waiting for container network initialization..."
    local attempts=0
    local max_attempts=30
    local connected=false

    while [ "$attempts" -lt "$max_attempts" ]; do
        if pct exec "$CT_ID" -- ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
            connected=true
            break
        fi
        sleep 2
        attempts=$((attempts + 1))
    done

    if [ "$connected" = false ]; then
        msg_warn "Could not verify external internet connectivity via ping inside container."
        msg_warn "Proceeding with caution; please verify network bridge and gateway settings."
    else
        msg_success "Container network is active and connected to internet."
    fi
}

# ------------------------------------------------------------------------------
# Deploy Installer Script
# ------------------------------------------------------------------------------
inject_and_run_installer() {
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local local_installer="${script_dir}/install.sh"

    if [ -f "$local_installer" ]; then
        msg_info "Pushing local install.sh to container ${CT_ID}..."
        pct push "$CT_ID" "$local_installer" /root/install.sh
    else
        msg_info "Fetching latest install.sh from GitHub inside container..."
        pct exec "$CT_ID" -- bash -c '
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y && apt-get install -y curl ca-certificates
            curl -fsSL https://raw.githubusercontent.com/codepromaxtech/Guide-to-Install-Frappe-ERPNext/main/install.sh -o /root/install.sh
        '
    fi

    pct exec "$CT_ID" -- chmod +x /root/install.sh

    msg_info "Launching automated Frappe & ERPNext installer inside container..."
    echo -e "${YELLOW}----------------------------------------------------------------${NC}"
    echo -e "${YELLOW}Container installer output follows. This may take 5 - 10 minutes.${NC}"
    echo -e "${YELLOW}----------------------------------------------------------------${NC}\n"

    # Build execution flags
    local exec_flags=(
        "--non-interactive"
        "--mode" "fresh"
        "--version" "$ERP_VERSION"
        "--domain" "$SITE_NAME"
        "--site" "$SITE_NAME"
        "--port" "$HTTP_PORT"
        "--ssl" "$SSL_TYPE"
        "--user" "$BENCH_USER"
        "--admin-pass" "$ADMIN_PASS"
        "--db-pass" "$DB_PASS"
        "--apps" "$APPS_LIST"
    )

    if [ -n "$ADMIN_EMAIL" ]; then
        exec_flags+=("--email" "$ADMIN_EMAIL")
    fi

    pct exec "$CT_ID" -- bash /root/install.sh "${exec_flags[@]}"
}

# ------------------------------------------------------------------------------
# Final Summary Output
# ------------------------------------------------------------------------------
print_lxc_summary() {
    local ct_ip
    ct_ip=$(pct exec "$CT_ID" -- ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}' | cut -d'/' -f1 || echo "<container-ip>")

    local access_url
    if [ "$HTTP_PORT" == "80" ]; then
        access_url="http://${ct_ip}"
    else
        access_url="http://${ct_ip}:${HTTP_PORT}"
    fi

    echo -e "\n${GREEN}${BOLD}"
    cat << "EOF"
================================================================
   PROXMOX LXC CONTAINER PROVISIONING & ERPNEXT DEPLOYMENT COMPLETE
================================================================
EOF
    echo -e "${NC}"
    echo -e "  ${BOLD}Container ID       :${NC} ${CT_ID}"
    echo -e "  ${BOLD}Container Hostname :${NC} ${CT_NAME}"
    echo -e "  ${BOLD}Container IPv4     :${NC} ${ct_ip}"
    echo -e "  ${BOLD}Frappe Site        :${NC} ${SITE_NAME}"
    echo -e "  ${BOLD}Frappe Admin User  :${NC} Administrator"
    echo -e "  ${BOLD}Admin Password     :${NC} ${ADMIN_PASS}"
    echo -e "  ${BOLD}MariaDB Root Pass  :${NC} ${DB_PASS}"
    echo -e "  ${BOLD}Bench System User  :${NC} ${BENCH_USER}"
    echo -e "  ${BOLD}Direct Access URL  :${NC} ${access_url}"
    echo -e "${CYAN}----------------------------------------------------------------${NC}"
    echo -e "  ${BOLD}Proxmox Management Commands:${NC}"
    echo -e "    Enter container shell : ${CYAN}pct enter ${CT_ID}${NC}"
    echo -e "    Container status      : ${CYAN}pct status ${CT_ID}${NC}"
    echo -e "    Reboot container      : ${CYAN}pct reboot ${CT_ID}${NC}"
    echo -e "    Stop container        : ${CYAN}pct stop ${CT_ID}${NC}"
    echo -e "${GREEN}================================================================${NC}\n"
}

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------
main() {
    print_banner
    check_proxmox_environment
    gather_proxmox_defaults
    run_lxc_wizard
    prepare_template
    create_lxc_container
    inject_and_run_installer
    print_lxc_summary
}

main "$@"
