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
    if [ -f "${STATE_FILE:-}" ]; then
        echo -e "${CYAN}${BOLD}[RESUME READY]${NC} State has been preserved in: ${BOLD}${STATE_FILE}${NC}"
        echo -e "After resolving any issues, run ${BOLD}sudo bash install.sh${NC} to resume from this checkpoint!\n"
    fi
    echo -e "To view the last 30 lines of the log file:"
    echo -e "  ${CYAN}tail -n 30 ${LOG_FILE}${NC}\n"
    exit "$code"
}
trap 'cleanup_on_error $LINENO "$BASH_COMMAND" $?' ERR

# ------------------------------------------------------------------------------
# State Tracking & Resume Management
# ------------------------------------------------------------------------------
STATE_FILE="${LOG_DIR}/install_state.env"
[ ! -w "$(dirname "$STATE_FILE" 2>/dev/null)" ] 2>/dev/null && STATE_FILE="/tmp/frappe_install_state.env"
RESUME_MODE=false
FORCE_CLEAN=false

save_state_var() {
    local var_name="$1"
    local var_val="$2"
    touch "$STATE_FILE" 2>/dev/null || return 0
    if grep -q "^${var_name}=" "$STATE_FILE" 2>/dev/null; then
        sed -i "s|^${var_name}=.*|${var_name}=\"${var_val}\"|" "$STATE_FILE"
    else
        echo "${var_name}=\"${var_val}\"" >> "$STATE_FILE"
    fi
}

save_all_state_vars() {
    save_state_var "NON_INTERACTIVE" "$NON_INTERACTIVE"
    save_state_var "INSTALL_MODE" "$INSTALL_MODE"
    save_state_var "ERP_VERSION" "$ERP_VERSION"
    save_state_var "DOMAIN_NAME" "$DOMAIN_NAME"
    save_state_var "DOMAIN_TYPE" "$DOMAIN_TYPE"
    save_state_var "SITE_NAME" "$SITE_NAME"
    save_state_var "HTTP_PORT" "$HTTP_PORT"
    save_state_var "SSL_TYPE" "$SSL_TYPE"
    save_state_var "CF_MODE" "$CF_MODE"
    save_state_var "BENCH_USER" "$BENCH_USER"
    save_state_var "BENCH_NAME" "$BENCH_NAME"
    save_state_var "ADMIN_PASS" "$ADMIN_PASS"
    save_state_var "DB_ROOT_PASS" "$DB_ROOT_PASS"
    save_state_var "ADMIN_EMAIL" "$ADMIN_EMAIL"
    save_state_var "SAVED_APPS" "${SELECTED_APPS[*]}"
    save_state_var "CUSTOM_APP_URL" "$CUSTOM_APP_URL"
    save_state_var "CUSTOM_APP_BRANCH" "$CUSTOM_APP_BRANCH"
    save_state_var "ENABLE_UFW" "$ENABLE_UFW"
    save_state_var "ENABLE_BACKUP_CRON" "$ENABLE_BACKUP_CRON"
}

load_state_vars() {
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        source "$STATE_FILE"
        if [ -n "${SAVED_APPS:-}" ]; then
            read -r -a SELECTED_APPS <<< "$SAVED_APPS"
        fi
    fi
}

mark_stage_done() {
    local stage="$1"
    save_state_var "${stage}" "done"
    log "STATE" "Stage ${stage} marked as completed."
}

is_stage_done() {
    local stage="$1"
    if [ -f "$STATE_FILE" ]; then
        grep -q "^${stage}=\"done\"" "$STATE_FILE" 2>/dev/null
        return $?
    fi
    return 1
}

clear_state() {
    rm -f "$STATE_FILE"
}

# ------------------------------------------------------------------------------
# Old Installation Cleanup & Uninstaller System
# ------------------------------------------------------------------------------
is_db_safe_to_drop() {
    local db="$1"
    [ -z "$db" ] && return 1
    # Safeguard list of protected databases - NEVER DROP THESE
    case "$db" in
        information_schema|mysql|performance_schema|sys|shopsuite|aranya_erp)
            return 1 ;;
    esac
    # Must only contain alphanumeric and underscore
    if [[ ! "$db" =~ ^[a-zA-Z0-9_]+$ ]]; then
        return 1
    fi
    return 0
}

cleanup_old_installation() {
    local force_flag="${1:-false}"

    echo -e "\n${YELLOW}${BOLD}================================================================${NC}"
    echo -e "${YELLOW}${BOLD}        FRAPPE & ERPNEXT INSTALLATION CLEANUP SYSTEM             ${NC}"
    echo -e "${YELLOW}${BOLD}================================================================${NC}"
    echo -e "This will safely clean up and uninstall previous Frappe / ERPNext components:"
    echo -e "  • Stop Frappe Supervisor processes & remove supervisor configurations"
    echo -e "  • Remove Frappe Nginx site configuration & reload Nginx"
    echo -e "  • Safely drop associated Frappe site databases (strictly excludes protected DBs)"
    echo -e "  • Remove Frappe Bench directory (~/${BENCH_NAME:-frappe-bench})"
    echo -e "  • Remove Frappe automated backup cron jobs"
    echo -e "  • Clear installer state checkpoints and temporary files"
    echo -e "${RED}${BOLD}  Note: Protected databases ('shopsuite', 'aranya_erp', system DBs)${NC}"
    echo -e "${RED}${BOLD}        and non-Frappe Nginx sites will NEVER be touched.${NC}"
    echo -e "${YELLOW}================================================================${NC}\n"

    if [ "$force_flag" != "true" ] && [ "$NON_INTERACTIVE" = false ]; then
        local confirm_clean
        confirm_clean=$(prompt_with_default "Are you sure you want to clean up the previous installation? [y/N]" "n")
        if [[ ! "$confirm_clean" =~ ^[Yy]$ ]]; then
            msg_info "Cleanup operation aborted by user."
            return 0
        fi
    fi

    msg_info "Starting cleanup of old Frappe / ERPNext installation..."

    # Detect target bench user and bench path
    local target_user="${BENCH_USER:-}"
    if [ -z "$target_user" ]; then
        if [ -L /etc/supervisor/conf.d/frappe-bench.conf ]; then
            local sup_target
            sup_target=$(readlink -f /etc/supervisor/conf.d/frappe-bench.conf 2>/dev/null || true)
            target_user=$(echo "$sup_target" | cut -d'/' -f3)
        fi
    fi
    if [ -z "$target_user" ]; then
        if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            target_user="$SUDO_USER"
        else
            target_user="frappe"
        fi
    fi

    local user_home
    user_home=$(eval echo "~$target_user" 2>/dev/null || echo "/home/$target_user")
    local bench_path="${user_home}/${BENCH_NAME:-frappe-bench}"

    msg_info "Target user: ${BOLD}${target_user}${NC} | Bench path: ${BOLD}${bench_path}${NC}"

    # 1. Stop and remove Supervisor processes
    msg_info "1. Stopping Frappe supervisor processes and removing configs..."
    if command -v supervisorctl >/dev/null 2>&1; then
        supervisorctl stop "${BENCH_NAME:-frappe-bench}:*" >> "$LOG_FILE" 2>&1 || true
        supervisorctl stop frappe-bench:* >> "$LOG_FILE" 2>&1 || true
    fi
    rm -f /etc/supervisor/conf.d/frappe-bench.conf
    rm -f /etc/supervisor/conf.d/*frappe*.conf
    if command -v supervisorctl >/dev/null 2>&1; then
        supervisorctl reread >> "$LOG_FILE" 2>&1 || true
        supervisorctl update >> "$LOG_FILE" 2>&1 || true
    fi

    # 2. Remove Frappe Nginx configs safely and test/reload
    msg_info "2. Removing Frappe Nginx configs and reloading web server..."
    rm -f /etc/nginx/conf.d/frappe-bench.conf
    rm -f /etc/nginx/conf.d/*frappe*.conf
    rm -f /etc/nginx/sites-enabled/frappe-bench.conf
    if command -v nginx >/dev/null 2>&1; then
        if nginx -t >> "$LOG_FILE" 2>&1; then
            systemctl reload nginx >> "$LOG_FILE" 2>&1 || true
            msg_success "Nginx successfully reloaded. Coexisting sites remain active."
        else
            msg_warn "Nginx configuration notice. Preserving existing configs."
        fi
    fi

    # 3. Clean up MariaDB site databases and users safely
    msg_info "3. Inspecting and removing Frappe site databases..."
    local mysql_auth=""
    if [ -n "$DB_ROOT_PASS" ]; then
        mysql_auth="-u root -p${DB_ROOT_PASS}"
    elif mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
        mysql_auth="-u root"
    fi

    local dbs_to_drop=()

    # Extract db_name from site_config.json files in bench
    if [ -d "${bench_path}/sites" ]; then
        for sc in "${bench_path}"/sites/*/site_config.json; do
            if [ -f "$sc" ]; then
                local s_db
                s_db=$(grep -o '"db_name"[^,]*' "$sc" 2>/dev/null | cut -d'"' -f4 || true)
                if [ -n "$s_db" ] && is_db_safe_to_drop "$s_db"; then
                    dbs_to_drop+=("$s_db")
                fi
            fi
        done
    fi

    # If mysql_auth is available, also search for any Frappe site databases matching `^_`
    if [ -n "$mysql_auth" ]; then
        local raw_dbs
        raw_dbs=$(mysql $mysql_auth -N -e "SHOW DATABASES;" 2>/dev/null || true)
        for db in $raw_dbs; do
            if [[ "$db" =~ ^_[0-9a-f]{16}$ ]] && is_db_safe_to_drop "$db"; then
                dbs_to_drop+=("$db")
            fi
        done
    fi

    if [ ${#dbs_to_drop[@]} -gt 0 ]; then
        local unique_dbs
        unique_dbs=($(printf "%s\n" "${dbs_to_drop[@]}" | sort -u))
        for db in "${unique_dbs[@]}"; do
            if is_db_safe_to_drop "$db"; then
                if [ -n "$mysql_auth" ]; then
                    msg_info "Safely dropping Frappe site database and user: ${BOLD}${db}${NC}..."
                    mysql $mysql_auth -e "DROP DATABASE IF EXISTS \`${db}\`;" >> "$LOG_FILE" 2>&1 || true
                    mysql $mysql_auth -e "DROP USER IF EXISTS '${db}'@'%';" >> "$LOG_FILE" 2>&1 || true
                    mysql $mysql_auth -e "DROP USER IF EXISTS '${db}'@'localhost';" >> "$LOG_FILE" 2>&1 || true
                    mysql $mysql_auth -e "FLUSH PRIVILEGES;" >> "$LOG_FILE" 2>&1 || true
                    msg_success "Dropped database '${db}'."
                else
                    msg_warn "MariaDB credentials not provided. Database '${db}' was not dropped automatically."
                fi
            fi
        done
    else
        msg_info "No Frappe site databases found to drop."
    fi

    # 4. Remove automated backup cron jobs
    msg_info "4. Removing Frappe cron jobs..."
    rm -f /etc/cron.d/frappe_backup_*

    # 5. Remove Bench directory
    if [ -d "$bench_path" ]; then
        msg_info "5. Removing Bench directory: ${bench_path}..."
        rm -rf "$bench_path"
        msg_success "Bench directory removed."
    else
        msg_info "5. Bench directory not present: ${bench_path}"
    fi

    # 6. Clear installer checkpoint state
    msg_info "6. Clearing installer state checkpoints..."
    clear_state
    rm -f /var/log/frappe-installer/install_state.env /tmp/frappe_install_state.env

    msg_success "Cleanup completed successfully!"
    echo -e "${GREEN}${BOLD}Previous Frappe / ERPNext installation has been cleanly purged.${NC}\n"
}

check_resume_option() {
    if [ "$FORCE_CLEANUP_FIRST" = true ]; then
        msg_info "Clean-install requested. Purging previous Frappe installation before starting..."
        cleanup_old_installation true
        return 0
    fi

    if [ "$FORCE_CLEAN" = true ]; then
        msg_info "Clean flag specified. Purging previous installation checkpoint..."
        clear_state
        return 0
    fi

    if [ -f "$STATE_FILE" ]; then
        local prev_site prev_version prev_user
        prev_site=$(grep '^SITE_NAME=' "$STATE_FILE" 2>/dev/null | cut -d'"' -f2 || true)
        prev_version=$(grep '^ERP_VERSION=' "$STATE_FILE" 2>/dev/null | cut -d'"' -f2 || true)
        prev_user=$(grep '^BENCH_USER=' "$STATE_FILE" 2>/dev/null | cut -d'"' -f2 || true)

        if [ -n "$prev_site" ] || [ -n "$prev_version" ]; then
            if is_stage_done "STAGE_COMPLETED"; then
                if [ "$NON_INTERACTIVE" = false ]; then
                    echo -e "\n${YELLOW}${BOLD}[NOTICE] A completed installation was found in state history:${NC}"
                    echo -e "  Site: ${prev_site} | Version: ${prev_version} | User: ${prev_user}"
                    echo -e "  1) Keep existing and exit"
                    echo -e "  2) Clean up / Uninstall old installation and start fresh"
                    echo -e "  3) Start fresh without cleaning up old bench"
                    local post_choice
                    post_choice=$(prompt_with_default "Select option [1-3]" "1")
                    if [ "$post_choice" == "2" ]; then
                        cleanup_old_installation true
                        clear_state
                        return 0
                    elif [ "$post_choice" == "3" ]; then
                        clear_state
                        return 0
                    else
                        msg_info "Exiting."
                        exit 0
                    fi
                fi
                return 0
            fi

            # Incomplete previous installation found
            echo -e "\n${YELLOW}${BOLD}================================================================${NC}"
            echo -e "${YELLOW}${BOLD}       ⚠️  PREVIOUS INCOMPLETE INSTALLATION DETECTED ⚠️          ${NC}"
            echo -e "${YELLOW}${BOLD}================================================================${NC}"
            echo -e "  Target User    : ${BOLD}${prev_user:-unknown}${NC}"
            echo -e "  Target Site    : ${BOLD}${prev_site:-unknown}${NC}"
            echo -e "  ERP Version    : ${BOLD}${prev_version:-unknown}${NC}"
            echo -e "${YELLOW}----------------------------------------------------------------${NC}"

            if [ "$NON_INTERACTIVE" = true ]; then
                if [ "$RESUME_MODE" = true ]; then
                    msg_info "Non-interactive mode: Resuming previous installation from state checkpoint..."
                    load_state_vars
                    return 0
                else
                    msg_info "Non-interactive mode without --resume: Cleaning state and starting fresh..."
                    clear_state
                    return 0
                fi
            else
                echo -e "How would you like to proceed?"
                echo -e "  ${GREEN}1) Resume installation from where it stopped (Recommended)${NC}"
                echo -e "  2) Clean up old installation completely and start fresh"
                echo -e "  3) Discard previous state and start fresh without cleanup"
                local resume_choice
                resume_choice=$(prompt_with_default "Select option [1-3]" "1")
                if [ "$resume_choice" == "1" ]; then
                    RESUME_MODE=true
                    load_state_vars
                    msg_info "Resuming installation with saved parameters."
                    return 0
                elif [ "$resume_choice" == "2" ]; then
                    cleanup_old_installation true
                    clear_state
                    return 0
                else
                    msg_info "Discarding previous state. Starting fresh..."
                    clear_state
                    return 0
                fi
            fi
        fi
    fi
}

get_target_python_version() {
    case "$ERP_VERSION" in
        "version-13") echo "3.10" ;;
        "version-14") echo "3.11" ;;
        "version-15") echo "3.11" ;;
        "version-16"|"develop") echo "3.14" ;;
        *) echo "3.11" ;;
    esac
}

# ------------------------------------------------------------------------------
# Default Variables
# ------------------------------------------------------------------------------
NON_INTERACTIVE=false
RUN_CLEANUP_ONLY=false
FORCE_CLEANUP_FIRST=false
FORCE_FLAG=false
INSTALL_MODE="fresh"        # "fresh" or "existing"
ERP_VERSION="version-15"    # "version-14", "version-15", "version-16", "develop"
DOMAIN_TYPE="domain"        # "domain" or "local"
DOMAIN_NAME=""
SITE_NAME=""
HTTP_PORT="80"
PORT_EXPLICITLY_SET=false
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

is_port_in_use() {
    local port="$1"
    [ -z "$port" ] && return 1
    if command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -qE "(:|\\])${port}\\s" && return 0
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -qE "(:|\\])${port}\\s" && return 0
    elif command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:"${port}" -sTCP:LISTEN -P -n >/dev/null 2>&1 && return 0
    fi
    return 1
}

find_next_available_port() {
    local candidate="${1:-80}"
    if ! is_port_in_use "$candidate"; then
        echo "$candidate"
        return 0
    fi
    local common_ports=(8088 8080 8090 8008 8888 8081 8085 9080)
    for p in "${common_ports[@]}"; do
        if ! is_port_in_use "$p"; then
            echo "$p"
            return 0
        fi
    done
    local p=8089
    while [ "$p" -lt 9999 ]; do
        if ! is_port_in_use "$p"; then
            echo "$p"
            return 0
        fi
        p=$((p + 1))
    done
    echo "8088"
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
    msg_info "Checking existing system services and port availability..."
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
    if is_port_in_use 80; then
        local p80_proc
        p80_proc=$(ss -tulpn 2>/dev/null | grep -E '(:|\])80\s' | head -n1 | grep -o 'users:(([^)]*))' | sed 's/users:(("//;s/".*//' || echo "another web server")
        local alt_port
        alt_port=$(find_next_available_port 80)
        msg_warn "Port 80 is occupied by [${p80_proc:-another service}]. Installer can automatically assign available port ${BOLD}${alt_port}${NC}."
    else
        msg_info "Port 80 is free and available."
    fi

    if is_port_in_use 443; then
        msg_info "Port 443 (HTTPS) is currently in use."
    fi
}

# ------------------------------------------------------------------------------
# Interactive Wizard
# ------------------------------------------------------------------------------
run_interactive_wizard() {
    # Check if an existing bench directory or supervisor config exists
    local check_bench_user="${SUDO_USER:-frappe}"
    local check_bench_home
    check_bench_home=$(eval echo "~$check_bench_user" 2>/dev/null || echo "/home/$check_bench_user")
    if [ -d "${check_bench_home}/frappe-bench" ] || [ -f /etc/supervisor/conf.d/frappe-bench.conf ]; then
        echo -e "\n${YELLOW}${BOLD}================================================================${NC}"
        echo -e "${YELLOW}${BOLD}       ⚠️  EXISTING FRAPPE BENCH DETECTED ON SERVER ⚠️           ${NC}"
        echo -e "${YELLOW}${BOLD}================================================================${NC}"
        echo -e "Found existing installation at: ${BOLD}${check_bench_home}/frappe-bench${NC}"
        echo "Would you like to:"
        echo -e "  ${GREEN}1) Clean up / Purge old installation and start fresh (Recommended)${NC}"
        echo "  2) Coexist with existing installation (Preserve old bench, configure side-by-side)"
        echo "  3) Exit installer"
        local exist_choice
        exist_choice=$(prompt_with_default "Select option [1-3]" "1")
        if [ "$exist_choice" == "1" ]; then
            cleanup_old_installation false
            INSTALL_MODE="fresh"
        elif [ "$exist_choice" == "2" ]; then
            INSTALL_MODE="existing"
        else
            msg_info "Installation cancelled by user."
            exit 0
        fi
        echo ""
    fi

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
    local suggested_port
    suggested_port=$(find_next_available_port 80)
    if [ "$suggested_port" != "80" ]; then
        msg_warn "Port 80 is occupied by an existing service."
        echo -e "${YELLOW}Suggested available HTTP port: ${BOLD}${suggested_port}${NC}"
        HTTP_PORT=$(prompt_with_default "Enter HTTP web port" "$suggested_port")
    else
        HTTP_PORT=$(prompt_with_default "Enter HTTP web port" "80")
    fi

    # Validate chosen port
    while true; do
        if [[ ! "$HTTP_PORT" =~ ^[0-9]+$ ]] || [ "$HTTP_PORT" -lt 1 ] || [ "$HTTP_PORT" -gt 65535 ]; then
            msg_warn "Invalid port '$HTTP_PORT'. Must be a number between 1 and 65535."
            HTTP_PORT=$(prompt_with_default "Enter HTTP web port" "$suggested_port")
            continue
        fi

        if is_port_in_use "$HTTP_PORT"; then
            msg_warn "Port ${HTTP_PORT} is currently in use by another process!"
            local next_p
            next_p=$(find_next_available_port "$HTTP_PORT")
            local use_other
            use_other=$(prompt_with_default "Use next available port [${next_p}] instead? [Y/n]" "y")
            if [[ "$use_other" =~ ^[Yy]$ ]]; then
                HTTP_PORT="$next_p"
                msg_info "Selected port: ${HTTP_PORT}"
                break
            fi
        fi
        break
    done
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
    if is_stage_done "STAGE_SWAP"; then
        msg_info "Swap space already configured. Skipping..."
        return 0
    fi

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
    mark_stage_done "STAGE_SWAP"
}

install_system_packages() {
    if is_stage_done "STAGE_PACKAGES"; then
        msg_info "System packages already installed. Skipping..."
        return 0
    fi

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
    mark_stage_done "STAGE_PACKAGES"
}

# ------------------------------------------------------------------------------
# Python & UV Setup
# ------------------------------------------------------------------------------
setup_python_and_uv() {
    if is_stage_done "STAGE_PYTHON"; then
        msg_info "Python environment already configured. Skipping..."
        return 0
    fi

    msg_info "Configuring Python environment with uv..."
    local user_home
    user_home=$(eval echo "~$BENCH_USER")

    # Install uv for the target bench user if not present
    if ! sudo -u "$BENCH_USER" test -f "${user_home}/.local/bin/uv"; then
        msg_info "Installing Astral uv package manager for user '${BENCH_USER}'..."
        sudo -u "$BENCH_USER" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' >> "$LOG_FILE" 2>&1
    fi

    # Determine recommended Python version dynamically
    local target_py
    target_py=$(get_target_python_version)

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
    mark_stage_done "STAGE_PYTHON"
}

# ------------------------------------------------------------------------------
# Node.js & Yarn Setup
# ------------------------------------------------------------------------------
setup_nodejs_and_yarn() {
    if is_stage_done "STAGE_NODEJS"; then
        msg_info "Node.js and Yarn already configured. Skipping..."
        return 0
    fi

    msg_info "Configuring Node.js and Yarn..."
    local target_node="20"
    if [ "$ERP_VERSION" == "version-13" ] || [ "$ERP_VERSION" == "version-14" ]; then
        target_node="18"
    elif [ "$ERP_VERSION" == "version-16" ] || [ "$ERP_VERSION" == "develop" ]; then
        target_node="24"
    fi

    # Check if modern node is already installed
    local current_node=""
    if command -v node >/dev/null 2>&1; then
        current_node=$(node -v | cut -d'.' -f1 | tr -d 'v')
    fi

    if [ -z "$current_node" ] || [ "$current_node" -lt "$target_node" ]; then
        msg_info "Installing Node.js ${target_node}.x from NodeSource..."
        export DEBIAN_FRONTEND=noninteractive
        export NEEDRESTART_MODE=a
        curl -fsSL "https://deb.nodesource.com/setup_${target_node}.x" | bash - >> "$LOG_FILE" 2>&1
        apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nodejs >> "$LOG_FILE" 2>&1
    fi

    if ! command -v yarn >/dev/null 2>&1; then
        msg_info "Installing Yarn package manager..."
        npm install -g yarn >> "$LOG_FILE" 2>&1
    fi

    # Enforce ignore-engines and extended network-timeout globally and for bench user
    yarn config set ignore-engines true >> "$LOG_FILE" 2>&1 || true
    yarn config set network-timeout 600000 >> "$LOG_FILE" 2>&1 || true
    if [ -n "$BENCH_USER" ] && id -u "$BENCH_USER" >/dev/null 2>&1; then
        sudo -u "$BENCH_USER" yarn config set ignore-engines true >> "$LOG_FILE" 2>&1 || true
        sudo -u "$BENCH_USER" yarn config set network-timeout 600000 >> "$LOG_FILE" 2>&1 || true
    fi

    msg_success "Node.js $(node -v) and Yarn $(yarn -v) ready."
    mark_stage_done "STAGE_NODEJS"
}

# ------------------------------------------------------------------------------
# wkhtmltopdf Setup
# ------------------------------------------------------------------------------
setup_wkhtmltopdf() {
    if is_stage_done "STAGE_WKHTMLTOPDF"; then
        msg_info "wkhtmltopdf already configured. Skipping..."
        return 0
    fi

    msg_info "Setting up wkhtmltopdf with Qt patched support..."
    if command -v wkhtmltopdf >/dev/null 2>&1; then
        msg_info "wkhtmltopdf is already installed: $(wkhtmltopdf --version | head -n1)"
        mark_stage_done "STAGE_WKHTMLTOPDF"
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
    mark_stage_done "STAGE_WKHTMLTOPDF"
}

# ------------------------------------------------------------------------------
# MariaDB Setup
# ------------------------------------------------------------------------------
setup_mariadb() {
    if is_stage_done "STAGE_MARIADB"; then
        msg_info "MariaDB already configured. Skipping..."
        return 0
    fi

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
    mark_stage_done "STAGE_MARIADB"
}

# ------------------------------------------------------------------------------
# Redis Setup
# ------------------------------------------------------------------------------
setup_redis() {
    if is_stage_done "STAGE_REDIS"; then
        msg_info "Redis already configured. Skipping..."
        return 0
    fi

    msg_info "Configuring Redis cache and queue server..."
    if ! command -v redis-server >/dev/null 2>&1; then
        apt-get install -y redis-server >> "$LOG_FILE" 2>&1
    fi
    systemctl start redis-server || systemctl start redis
    systemctl enable redis-server || systemctl enable redis
    msg_success "Redis server is running."
    mark_stage_done "STAGE_REDIS"
}

# ------------------------------------------------------------------------------
# Bench User & Directory Setup
# ------------------------------------------------------------------------------
setup_user() {
    if is_stage_done "STAGE_USER"; then
        msg_info "User '${BENCH_USER}' already configured. Skipping..."
        return 0
    fi

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
    mark_stage_done "STAGE_USER"
}

# ------------------------------------------------------------------------------
# Bench Initialization
# ------------------------------------------------------------------------------
initialize_bench() {
    local user_home
    user_home=$(eval echo "~$BENCH_USER")
    local bench_path="${user_home}/${BENCH_NAME}"

    if is_stage_done "STAGE_BENCH_INIT"; then
        msg_info "Frappe Bench already initialized at '${bench_path}'. Skipping..."
        return 0
    fi

    # Check if bench directory exists but is incomplete or broken
    if [ -d "$bench_path" ]; then
        if [ -f "${bench_path}/env/bin/python" ] && [ -d "${bench_path}/apps/frappe" ]; then
            msg_info "Valid Frappe Bench already found at '${bench_path}'. Ensuring assets are compiled..."
            sudo -u "$BENCH_USER" bash -c "
                export PATH=\"${user_home}/.local/bin:/usr/local/bin:/usr/bin:\$PATH\"
                cd \"${bench_path}\"
                yarn config set ignore-engines true 2>/dev/null || true
                yarn config set network-timeout 600000 2>/dev/null || true
                bench build || true
            " >> "$LOG_FILE" 2>&1
            mark_stage_done "STAGE_BENCH_INIT"
            return 0
        else
            msg_warn "Detected incomplete or broken Frappe Bench directory at '${bench_path}'."
            msg_warn "Cleaning up incomplete bench directory before re-initializing..."
            rm -rf "$bench_path"
        fi
    fi

    local target_py
    target_py=$(get_target_python_version)

    msg_info "Initializing Frappe Bench with branch '${ERP_VERSION}' using Python ${target_py}..."
    sudo -u "$BENCH_USER" bash -c "
        set -e
        export PATH=\"${user_home}/.local/bin:/usr/local/bin:/usr/bin:\$PATH\"
        cd \"${user_home}\"
        
        # Ensure yarn ignores engine warnings/blocks and has high network timeout
        yarn config set ignore-engines true 2>/dev/null || true
        yarn config set network-timeout 600000 2>/dev/null || true
        
        # Find exact python path for target version
        PY_PATH=\$(uv python find ${target_py} 2>/dev/null || which python3)
        echo \"[bench init] Executing with Python binary: \$PY_PATH (\$(${PY_PATH} --version 2>/dev/null || true))\"
        
        # Use --skip-assets to decouple asset compilation from bench initialization, preventing rollback crashes
        echo \"n\" | bench init --skip-assets --frappe-branch \"${ERP_VERSION}\" --python \"\$PY_PATH\" \"${BENCH_NAME}\" </dev/null
        
        # Build assets cleanly with retry resilience
        cd \"${bench_path}\"
        bench build || {
            echo '[bench build] Initial build attempt encountered an issue, retrying with cached packages...'
            bench build
        }
    " >> "$LOG_FILE" 2>&1

    # Ensure bench directory is readable for Nginx
    chmod -R o+rx "$bench_path" 2>/dev/null || true

    msg_success "Frappe Bench initialized at ${bench_path}."
    mark_stage_done "STAGE_BENCH_INIT"
}

# ------------------------------------------------------------------------------
# Site Creation
# ------------------------------------------------------------------------------
create_frappe_site() {
    local user_home
    user_home=$(eval echo "~$BENCH_USER")
    local bench_path="${user_home}/${BENCH_NAME}"
    local site_dir="${bench_path}/sites/${SITE_NAME}"

    if is_stage_done "STAGE_SITE_CREATE"; then
        msg_info "Site '${SITE_NAME}' already created. Skipping..."
        return 0
    fi

    if [ -d "$site_dir" ]; then
        msg_warn "Site directory '${site_dir}' already exists. Skipping site creation..."
        mark_stage_done "STAGE_SITE_CREATE"
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
        bench use \"${SITE_NAME}\"
        bench set-config -g default_site \"${SITE_NAME}\"
    " >> "$LOG_FILE" 2>&1

    msg_success "Site '${SITE_NAME}' created successfully."
    mark_stage_done "STAGE_SITE_CREATE"
}

# ------------------------------------------------------------------------------
# App Installation
# ------------------------------------------------------------------------------
install_frappe_apps() {
    if is_stage_done "STAGE_APPS"; then
        msg_info "Applications already installed on site '${SITE_NAME}'. Skipping..."
        return 0
    fi

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
            # ERPNext requires payments app to be available in bench
            if [ ! -d "${bench_path}/apps/payments" ]; then
                install_single_app "payments" "$app_branch" || true
            fi
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

    mark_stage_done "STAGE_APPS"
}

# ------------------------------------------------------------------------------
# Production Setup (Supervisor & Nginx)
# ------------------------------------------------------------------------------
configure_production() {
    if is_stage_done "STAGE_PRODUCTION"; then
        msg_info "Production services already configured. Skipping..."
        return 0
    fi

    local user_home
    user_home=$(eval echo "~$BENCH_USER")
    local bench_path="${user_home}/${BENCH_NAME}"

    msg_info "Setting up Production Environment with Nginx & Supervisor..."

    # Set default site and configure DNS multitenancy
    sudo -u "$BENCH_USER" bash -c "
        export PATH=\"${user_home}/.local/bin:\$PATH\"
        cd \"${bench_path}\"
        bench use \"${SITE_NAME}\"
        bench set-config -g default_site \"${SITE_NAME}\"
        bench config dns_multitenant on
    " >> "$LOG_FILE" 2>&1

    # Register DOMAIN_NAME or server IP to site domains if different from SITE_NAME
    if [ -n "$DOMAIN_NAME" ] && [ "$DOMAIN_NAME" != "$SITE_NAME" ]; then
        sudo -u "$BENCH_USER" bash -c "
            export PATH=\"${user_home}/.local/bin:\$PATH\"
            cd \"${bench_path}\"
            bench setup add-domain \"${DOMAIN_NAME}\" --site \"${SITE_NAME}\" 2>/dev/null || true
        " >> "$LOG_FILE" 2>&1
    fi

    # Also register host IP addresses and loopback so direct browser access by IP works natively
    local host_ips
    host_ips=$(hostname -I 2>/dev/null || echo "")
    for ip in $host_ips "127.0.0.1"; do
        if [ -n "$ip" ] && [ "$ip" != "$SITE_NAME" ] && [ "$ip" != "$DOMAIN_NAME" ]; then
            sudo -u "$BENCH_USER" bash -c "
                export PATH=\"${user_home}/.local/bin:\$PATH\"
                cd \"${bench_path}\"
                bench setup add-domain \"${ip}\" --site \"${SITE_NAME}\" 2>/dev/null || true
            " >> "$LOG_FILE" 2>&1
        fi
    done

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

    # If custom HTTP port is set, ensure generated nginx config listens on HTTP_PORT
    if [ "$HTTP_PORT" != "80" ] && [ -f "${bench_path}/config/nginx.conf" ]; then
        sed -i "s/listen 80;/listen ${HTTP_PORT};/g; s/listen \\[::\\]:80;/listen \\[::\\]:${HTTP_PORT};/g" "${bench_path}/config/nginx.conf"
    fi

    # Ensure requests with server IP or unknown host header route to SITE_NAME
    if [ -f "${bench_path}/config/nginx.conf" ]; then
        sed -i "s/default \$host;/default ${SITE_NAME};/g" "${bench_path}/config/nginx.conf"
    fi

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
    mark_stage_done "STAGE_PRODUCTION"
}

# ------------------------------------------------------------------------------
# SSL & Cloudflare Configuration
# ------------------------------------------------------------------------------
configure_ssl() {
    if is_stage_done "STAGE_SSL"; then
        msg_info "SSL already configured. Skipping..."
        return 0
    fi

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

    mark_stage_done "STAGE_SSL"
}

# ------------------------------------------------------------------------------
# Firewall Setup (UFW)
# ------------------------------------------------------------------------------
configure_firewall() {
    if is_stage_done "STAGE_FIREWALL"; then
        msg_info "Firewall already configured. Skipping..."
        return 0
    fi

    if [ "$ENABLE_UFW" = true ]; then
        msg_info "Configuring UFW Firewall rules..."
        apt-get install -y ufw >> "$LOG_FILE" 2>&1
        ufw allow 22/tcp || ufw allow ssh
        ufw allow "${HTTP_PORT}/tcp"
        ufw allow 443/tcp
        echo "y" | ufw enable >> "$LOG_FILE" 2>&1 || true
        msg_success "UFW enabled: ports 22, ${HTTP_PORT}, 443 allowed."
    fi
    mark_stage_done "STAGE_FIREWALL"
}

# ------------------------------------------------------------------------------
# Automatic Database Backup Cron
# ------------------------------------------------------------------------------
configure_backup_cron() {
    if is_stage_done "STAGE_CRON"; then
        msg_info "Backup cron already configured. Skipping..."
        return 0
    fi

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
    mark_stage_done "STAGE_CRON"
    mark_stage_done "STAGE_COMPLETED"
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
    echo -e "  Update bench    : ${CYAN}bench update${NC}"

    echo -e "\n${BOLD}${CYAN}--- Enterprise Support & Consulting ---${NC}"
    echo -e "  Provided by     : ${BOLD}CodeProMax Tech${NC} (https://codepromax.com.de/)"
    echo -e "  WhatsApp / Call : ${GREEN}+880 130 201 6151${NC} / ${GREEN}+880 176 441 4949${NC}"
    echo -e "  Email           : ${CYAN}codepromaxtech@gmail.com${NC}"
    echo -e "  Support Hours   : Sun - Thu: 09:00 AM – 06:00 PM (Emergency 24/7)\n"
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
                PORT_EXPLICITLY_SET=true
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
            --resume)
                RESUME_MODE=true
                shift
                ;;
            --clean|--fresh-start)
                FORCE_CLEAN=true
                shift
                ;;
            --clean-install)
                FORCE_CLEANUP_FIRST=true
                FORCE_CLEAN=true
                shift
                ;;
            --cleanup-only|--uninstall|--purge)
                RUN_CLEANUP_ONLY=true
                shift
                ;;
            --force|-f)
                FORCE_FLAG=true
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
                echo "  --resume                Resume interrupted installation from checkpoint"
                echo "  --clean                 Discard previous checkpoint and start fresh"
                echo "  --clean-install         Safely purge previous Frappe installation before installing fresh"
                echo "  --cleanup-only          Safely uninstall and clean up previous Frappe bench and configs"
                echo "  --force, -f             Bypass confirmation prompts during cleanup"
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

    # Execute cleanup-only if requested
    if [ "$RUN_CLEANUP_ONLY" = true ]; then
        cleanup_old_installation "$FORCE_FLAG"
        exit 0
    fi

    # Check for previous installation progress and offer resume
    check_resume_option

    if [ "$RESUME_MODE" = false ]; then
        if [ "$NON_INTERACTIVE" = false ]; then
            run_interactive_wizard
        else
            # Set defaults if missing in non-interactive mode
            [ -z "$BENCH_USER" ] && BENCH_USER="frappe"
            [ -z "$DOMAIN_NAME" ] && DOMAIN_NAME=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
            [ -z "$SITE_NAME" ] && SITE_NAME="$DOMAIN_NAME"
            [ -z "$DB_ROOT_PASS" ] && DB_ROOT_PASS=$(generate_random_password 16)
            [ -z "$ADMIN_PASS" ] && ADMIN_PASS=$(generate_random_password 16)
            if [ "$PORT_EXPLICITLY_SET" = false ] && is_port_in_use "$HTTP_PORT"; then
                local auto_port
                auto_port=$(find_next_available_port "$HTTP_PORT")
                msg_warn "Default port ${HTTP_PORT} is currently in use. Auto-assigning available port: ${BOLD}${auto_port}${NC}."
                HTTP_PORT="$auto_port"
            fi
            print_summary_confirmation
        fi
        # Save all options to state file for future resume capability
        save_all_state_vars
    else
        msg_info "Resuming installation with saved settings:"
        echo -e "  User: ${BENCH_USER} | Site: ${SITE_NAME} | Version: ${ERP_VERSION} | Port: ${HTTP_PORT}"
    fi

    msg_info "Starting / Resuming installation process at $(date)..."
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
