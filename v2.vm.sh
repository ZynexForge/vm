#!/bin/bash
set -euo pipefail

# =============================================================================
# ZynexForge CloudStack™ Platform - World's #1 Virtualization System
# Advanced Multi-Node Virtualization Management (User Mode)
# Version: 4.0.0 Ultra
# =============================================================================

# Global Configuration
readonly USER_HOME="$HOME"
readonly CONFIG_DIR="$USER_HOME/.zynexforge"
readonly DATA_DIR="$USER_HOME/.zynexforge/data"
readonly LOG_FILE="$USER_HOME/.zynexforge/zynexforge.log"
readonly NODES_DB="$CONFIG_DIR/nodes.yml"
readonly GLOBAL_CONFIG="$CONFIG_DIR/config.yml"
readonly SSH_KEY_FILE="$USER_HOME/.ssh/zynexforge_ed25519"
readonly SCRIPT_VERSION="4.0.0 Ultra"

# Color Definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Resource Limits (User mode safe)
readonly MAX_CPU_CORES=$(nproc)
readonly MAX_RAM_MB=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 * 80 / 100)) # 80% of total
readonly MAX_DISK_GB=100
readonly MIN_RAM_MB=256
readonly MIN_DISK_GB=1

# ASCII Art - Your Original Banner
readonly ASCII_MAIN_ART=$(cat << 'EOF'
__________                           ___________                         
\____    /__.__. ____   ____ ___  __\_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /|    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    < |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \\___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/    \/             /_____/      \/ 
EOF
)

# Enhanced OS Templates with multiple mirrors
declare -A OS_TEMPLATES=(
    ["ubuntu-24.04"]="Ubuntu 24.04 LTS|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ZynexForge123"
    ["ubuntu-22.04"]="Ubuntu 22.04 LTS|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ZynexForge123"
    ["debian-12"]="Debian 12|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|ZynexForge123"
    ["centos-9"]="CentOS Stream 9|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|ZynexForge123"
    ["rocky-9"]="Rocky Linux 9|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|ZynexForge123"
    ["almalinux-9"]="AlmaLinux 9|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|ZynexForge123"
    ["fedora-40"]="Fedora 40|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|ZynexForge123"
    ["alpine-3.19"]="Alpine Linux 3.19|3.19|https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.0-x86_64.iso|alpine|root|alpine"
)

# Enhanced ISO Library with CDN mirrors
declare -A ISO_LIBRARY=(
    ["ubuntu-24.04-desktop"]="Ubuntu 24.04 Desktop|https://releases.ubuntu.com/24.04/ubuntu-24.04-desktop-amd64.iso|ubuntu|ubuntu"
    ["ubuntu-24.04-server"]="Ubuntu 24.04 Server|https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso|ubuntu|ubuntu"
    ["ubuntu-22.04-server"]="Ubuntu 22.04 Server|https://releases.ubuntu.com/22.04/ubuntu-22.04-live-server-amd64.iso|ubuntu|ubuntu"
    ["debian-12"]="Debian 12|https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso|debian|debian"
    ["almalinux-9"]="AlmaLinux 9|https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9.3-x86_64-dvd.iso|alma|alma"
    ["rocky-9"]="Rocky Linux 9|https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.3-x86_64-dvd.iso|rocky|rocky"
    ["kali-linux"]="Kali Linux|https://cdimage.kali.org/kali-2024.2/kali-linux-2024.2-installer-amd64.iso|kali|kali"
    ["arch-linux"]="Arch Linux|https://archlinux.c3sl.ufpr.br/iso/2024.07.01/archlinux-2024.07.01-x86_64.iso|arch|arch"
)

# Real Nodes for reference (cloud deployment targets)
declare -A REAL_NODES=(
    ["mumbai"]="🇮🇳 Mumbai, India|ap-south-1|103.21.58.1|45|64|500|kvm,qemu,docker,lxd,jupyter"
    ["singapore"]="🇸🇬 Singapore|ap-southeast-1|103.21.61.1|60|256|2000|kvm,qemu,docker,jupyter,lxd,kubernetes"
    ["frankfurt"]="🇩🇪 Frankfurt, Germany|eu-central-1|103.21.62.1|70|512|5000|kvm,qemu,docker,jupyter,lxd,kubernetes,openstack"
    ["newyork"]="🇺🇸 New York, USA|us-east-1|103.21.65.1|80|1024|10000|kvm,qemu,docker,jupyter,lxd,kubernetes,openstack"
    ["tokyo"]="🇯🇵 Tokyo, Japan|ap-northeast-1|103.21.68.1|85|256|4000|kvm,qemu,docker,jupyter,lxd,kubernetes"
)

# Enhanced Docker Images (user mode)
declare -A DOCKER_IMAGES=(
    ["ubuntu-24.04"]="Ubuntu 24.04|ubuntu:24.04"
    ["debian-12"]="Debian 12|debian:12"
    ["alpine"]="Alpine Linux|alpine:latest"
    ["nginx"]="Nginx Web Server|nginx:alpine"
    ["mysql"]="MySQL Database|mysql:8.0"
    ["postgres"]="PostgreSQL|postgres:16"
    ["redis"]="Redis Cache|redis:alpine"
    ["nodejs"]="Node.js 20|node:20-alpine"
    ["python"]="Python 3.12|python:3.12-alpine"
    ["jupyter"]="Jupyter Notebook|jupyter/base-notebook"
    ["code-server"]="VS Code Server|codercom/code-server:latest"
)

# Enhanced Jupyter Templates
declare -A JUPYTER_TEMPLATES=(
    ["data-science"]="Data Science|jupyter/datascience-notebook|8888|python,R,julia,scipy"
    ["tensorflow"]="TensorFlow ML|jupyter/tensorflow-notebook|8889|python,tensorflow,keras"
    ["minimal"]="Minimal Python|jupyter/minimal-notebook|8890|python,pandas,numpy"
    ["pyspark"]="PySpark|jupyter/pyspark-notebook|8891|python,spark,hadoop"
)

# =============================================================================
# CORE FUNCTIONS
# =============================================================================

print_header() {
    clear
    echo -e "${CYAN}"
    echo "$ASCII_MAIN_ART"
    echo -e "${NC}"
    echo -e "${YELLOW}⚡ ZynexForge CloudStack™ - World's #1 Virtualization Platform${NC}"
    echo -e "${WHITE}🔥 Professional Edition | Version: ${SCRIPT_VERSION}${NC}"
    echo "=================================================================="
    echo
}

print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "SUCCESS") echo -e "${GREEN}✓ [SUCCESS]${NC} $message" ;;
        "ERROR") echo -e "${RED}✗ [ERROR]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}⚠ [WARNING]${NC} $message" ;;
        "INFO") echo -e "${BLUE}ℹ [INFO]${NC} $message" ;;
        "INPUT") echo -e "${MAGENTA}? [INPUT]${NC} $message" ;;
        "PROGRESS") echo -e "${CYAN}⟳ [PROGRESS]${NC} $message" ;;
        *) echo "[$type] $message" ;;
    esac
}

log_message() {
    local level=$1
    local message=$2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" >> "$LOG_FILE"
}

validate_input() {
    local type=$1
    local value=$2
    local min=${3:-0}
    local max=${4:-999999}
    
    case $type in
        "number")
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                print_status "ERROR" "Must be a number"
                return 1
            fi
            if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
                print_status "ERROR" "Must be between $min and $max"
                return 1
            fi
            ;;
        "size")
            if ! [[ "$value" =~ ^[0-9]+[GgMm]$ ]]; then
                print_status "ERROR" "Must be a size with unit (e.g., 100G, 512M)"
                return 1
            fi
            ;;
        "port")
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "Must be a valid port number (1-65535)"
                return 1
            fi
            ;;
        "name")
            if ! [[ "$value" =~ ^[a-zA-Z0-9_-]{3,50}$ ]]; then
                print_status "ERROR" "Name must be 3-50 chars, letters, numbers, hyphens, underscores only"
                return 1
            fi
            ;;
        "ip")
            if ! [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                print_status "ERROR" "Must be a valid IP address"
                return 1
            fi
            ;;
        "email")
            if ! [[ "$value" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                print_status "ERROR" "Must be a valid email address"
                return 1
            fi
            ;;
        "url")
            if ! [[ "$value" =~ ^https?://.+ ]]; then
                print_status "ERROR" "Must be a valid URL starting with http:// or https://"
                return 1
            fi
            ;;
    esac
    return 0
}

check_dependencies() {
    print_status "INFO" "Checking system dependencies..."
    
    local missing_packages=()
    local required_tools=("qemu-system-x86_64" "qemu-img" "ssh-keygen" "curl" "wget")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" > /dev/null 2>&1; then
            missing_packages+=("$tool")
        fi
    done
    
    if [ ${#missing_packages[@]} -gt 0 ]; then
        print_status "WARNING" "Missing packages: ${missing_packages[*]}"
        
        if command -v apt-get > /dev/null 2>&1; then
            print_status "INFO" "Installing packages on Debian/Ubuntu..."
            sudo apt-get update
            sudo apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils genisoimage openssh-client curl wget jq
            log_message "INSTALL" "Installed packages on Debian/Ubuntu"
            
        elif command -v dnf > /dev/null 2>&1; then
            print_status "INFO" "Installing packages on Fedora/RHEL..."
            sudo dnf install -y qemu-system-x86 qemu-img cloud-utils genisoimage openssh-clients curl wget jq
            log_message "INSTALL" "Installed packages on Fedora/RHEL"
        else
            print_status "ERROR" "Unsupported package manager"
            print_status "INFO" "Please install manually: qemu-system-x86, qemu-utils, cloud-image-utils, genisoimage, curl, wget"
            return 1
        fi
        
        print_status "SUCCESS" "Dependencies installed successfully"
    else
        print_status "SUCCESS" "All required tools are available"
    fi
    
    # Check if user can use KVM (non-root)
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        print_status "SUCCESS" "KVM acceleration is available"
    else
        print_status "WARNING" "KVM acceleration may not be available (check /dev/kvm permissions)"
    fi
    
    # Check Docker (user mode)
    if command -v docker > /dev/null 2>&1; then
        if docker info > /dev/null 2>&1; then
            print_status "SUCCESS" "Docker is available"
        else
            print_status "WARNING" "Docker daemon is not running or permission issues"
        fi
    fi
    
    return 0
}

check_port_available() {
    local port=$1
    if ss -tuln 2>/dev/null | grep -q ":${port} "; then
        return 1
    fi
    return 0
}

find_available_port() {
    local base_port=${1:-22000}
    local max_port=22999
    local port=$base_port
    
    while [ $port -le $max_port ]; do
        if check_port_available "$port"; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
    done
    echo $((30000 + RANDOM % 10000))
}

generate_password() {
    local length=${1:-16}
    local use_special=${2:-true}
    
    if [ "$use_special" = true ]; then
        tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c "$length"
    else
        tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
    fi
}

get_system_resources() {
    local total_ram_kb
    total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram_mb=$((total_ram_kb / 1024))
    local available_ram_mb=$((total_ram_mb * 70 / 100)) # Use 70% of total RAM for user mode
    
    local total_disk_gb
    total_disk_gb=$(df -BG "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    total_disk_gb=${total_disk_gb:-50}
    
    local cpu_cores
    cpu_cores=$(nproc)
    local available_cores=$((cpu_cores - 1)) # Leave 1 core for host
    
    echo "$available_ram_mb $total_disk_gb $available_cores"
}

# =============================================================================
# INITIALIZATION (User Mode)
# =============================================================================

initialize_platform() {
    print_status "INFO" "Initializing ZynexForge Platform (User Mode)..."
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_status "WARNING" "Running as root is not recommended for this script"
        print_status "INFO" "Please run as regular user for better security"
        exit 1
    fi
    
    # Create directory structure in user home
    mkdir -p "$CONFIG_DIR" \
             "$DATA_DIR/vms" \
             "$DATA_DIR/disks" \
             "$DATA_DIR/cloudinit" \
             "$DATA_DIR/dockervm" \
             "$DATA_DIR/jupyter" \
             "$DATA_DIR/isos" \
             "$DATA_DIR/backups" \
             "$DATA_DIR/snapshots" \
             "$USER_HOME/zynexforge/templates" \
             "$USER_HOME/zynexforge/logs"
    
    # Create default config for user mode
    if [ ! -f "$GLOBAL_CONFIG" ]; then
        cat > "$GLOBAL_CONFIG" << EOF
# ZynexForge Global Configuration (User Mode)
platform:
  name: "ZynexForge CloudStack™ Professional"
  version: "${SCRIPT_VERSION}"
  default_node: "local"
  ssh_base_port: 22000
  max_vms_per_node: 10
  user_mode: true
  enable_monitoring: true
  auto_backup: false
  backup_retention_days: 7
  enable_telemetry: false
  auto_update: true

security:
  firewall_enabled: false
  default_ssh_user: "$USER"
  password_min_length: 8
  use_ssh_keys: true
  enable_2fa: false
  ssh_timeout: 300
  enable_audit_log: true
  encrypt_backups: false

network:
  bridge_interface: ""
  default_subnet: "192.168.100.0/24"
  dns_servers: "8.8.8.8,1.1.1.1"
  enable_ipv6: false
  mtu: 1500

performance:
  enable_hugepages: false
  cpu_pinning: false
  io_threads: 2
  disk_cache: "writeback"
  net_model: "virtio"

paths:
  templates: "$USER_HOME/zynexforge/templates"
  isos: "$DATA_DIR/isos"
  vm_configs: "$DATA_DIR/vms"
  vm_disks: "$DATA_DIR/disks"
  logs: "$USER_HOME/zynexforge/logs"
  backups: "$DATA_DIR/backups"
  snapshots: "$DATA_DIR/snapshots"
EOF
        print_status "SUCCESS" "User mode configuration created"
        log_message "CONFIG" "Created user mode configuration"
    fi
    
    # Create nodes database with local node only
    if [ ! -f "$NODES_DB" ]; then
        cat > "$NODES_DB" << EOF
# ZynexForge Nodes Database (User Mode)
nodes:
  local:
    node_id: "local"
    node_name: "Local User Mode"
    location_name: "Local, Your Computer"
    provider: "Self-Hosted (User Mode)"
    public_ip: "127.0.0.1"
    capabilities: ["kvm", "qemu", "docker", "jupyter"]
    tags: ["development", "testing", "user-mode"]
    status: "active"
    created_at: "$(date -Iseconds)"
    user_mode: true
    resources:
      cpu_cores: "$(nproc)"
      total_ram_mb: "$(free -m | awk '/^Mem:/{print $2}')"
      available_ram_mb: "$(free -m | awk '/^Mem:/{print $7}')"
      total_disk_gb: "$(df -BG $HOME | awk 'NR==2{print $2}' | sed 's/G//')"
      available_disk_gb: "$(df -BG $HOME | awk 'NR==2{print $4}' | sed 's/G//')"
EOF
        print_status "SUCCESS" "User mode nodes database created"
        log_message "NODES" "Created nodes database for user mode"
    fi
    
    # Generate SSH key if not exists
    if [ ! -f "$SSH_KEY_FILE" ]; then
        print_status "INFO" "Generating SSH key pair for user mode..."
        ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q -C "zynexforge-user@$(hostname)"
        chmod 600 "$SSH_KEY_FILE"
        chmod 644 "${SSH_KEY_FILE}.pub"
        print_status "SUCCESS" "SSH key generated: $SSH_KEY_FILE"
        log_message "SECURITY" "Generated SSH key pair for user mode"
    fi
    
    # Check and install dependencies
    if check_dependencies; then
        print_status "SUCCESS" "Platform initialized successfully in user mode!"
        log_message "INIT" "Platform initialization completed in user mode"
    else
        print_status "ERROR" "Platform initialization failed"
        return 1
    fi
}

# =============================================================================
# VM MANAGEMENT FUNCTIONS (User Mode)
# =============================================================================

get_vm_list() {
    find "$DATA_DIR/vms" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

load_vm_config() {
    local vm_name=$1
    local config_file="$DATA_DIR/vms/$vm_name.conf"
    
    if [[ -f "$config_file" ]]; then
        # Clear previous variables
        unset VM_NAME NODE_ID OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED STATUS
        
        source "$config_file" 2>/dev/null
        return 0
    else
        print_status "ERROR" "Configuration for VM '$vm_name' not found"
        return 1
    fi
}

save_vm_config() {
    local config_file="$DATA_DIR/vms/${VM_NAME}.conf"
    
    cat > "$config_file" << EOF
VM_NAME="$VM_NAME"
NODE_ID="$NODE_ID"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
STATUS="$STATUS"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
    log_message "VM" "Saved configuration for VM: $VM_NAME"
}

# =============================================================================
# ENHANCED KVM VM CREATION (User Mode)
# =============================================================================

create_kvm_vm() {
    local node_id="$1"
    local node_name="$2"
    local node_ip="$3"
    
    print_header
    echo -e "${GREEN}🖥️ Create QEMU/KVM Virtual Machine (User Mode)${NC}"
    echo -e "${YELLOW}Location: ${node_name} ($node_ip)${NC}"
    echo
    
    # VM Name with validation
    while true; do
        read -rp "$(print_status "INPUT" "VM Name (letters, numbers, hyphens only): ")" vm_name
        
        if validate_input "name" "$vm_name"; then
            if [ -f "$DATA_DIR/vms/${vm_name}.conf" ]; then
                print_status "ERROR" "VM '$vm_name' already exists"
            else
                VM_NAME="$vm_name"
                NODE_ID="$node_id"
                break
            fi
        fi
    done
    
    # OS Selection Method
    print_status "INFO" "Select OS Installation Method:"
    echo "  1) 📦 Cloud Image (Fast Deployment - 1-2 minutes)"
    echo "  2) 💿 ISO Image (Full Install - 10-30 minutes)"
    echo "  3) 🎯 Custom Image URL"
    echo
    
    read -rp "$(print_status "INPUT" "Choice (1-3): ")" os_method_choice
    
    local os_template=""
    local iso_path=""
    local img_url=""
    
    case $os_method_choice in
        1)
            # Cloud Image Selection
            print_header
            echo -e "${GREEN}📦 Select Cloud Image${NC}"
            echo "─────────────────────────────────────"
            local index=1
            local template_keys=("${!OS_TEMPLATES[@]}")
            for key in "${template_keys[@]}"; do
                IFS='|' read -r name codename url username default_user default_pass <<< "${OS_TEMPLATES[$key]}"
                printf "%2d) %-20s %s\n" "$index" "$name" "($codename)"
                ((index++))
            done
            echo
            
            while true; do
                read -rp "$(print_status "INPUT" "Select image (1-${#OS_TEMPLATES[@]}): ")" template_choice
                
                if [[ "$template_choice" =~ ^[0-9]+$ ]] && [ "$template_choice" -ge 1 ] && [ "$template_choice" -le ${#OS_TEMPLATES[@]} ]; then
                    local selected_key="${template_keys[$((template_choice-1))]}"
                    IFS='|' read -r os_name CODENAME img_url default_user OS_TYPE default_pass <<< "${OS_TEMPLATES[$selected_key]}"
                    OS_TYPE="$selected_key"
                    break
                else
                    print_status "ERROR" "Invalid selection"
                fi
            done
            ;;
            
        2)
            # ISO Image Selection
            print_header
            echo -e "${GREEN}💿 Select ISO Image${NC}"
            echo "─────────────────────────────────────"
            local index=1
            local iso_keys=("${!ISO_LIBRARY[@]}")
            for key in "${iso_keys[@]}"; do
                IFS='|' read -r name url username default_pass <<< "${ISO_LIBRARY[$key]}"
                printf "%2d) %-25s\n" "$index" "$name"
                ((index++))
            done
            echo
            
            while true; do
                read -rp "$(print_status "INPUT" "Select ISO (1-${#ISO_LIBRARY[@]}): ")" iso_choice
                
                if [[ "$iso_choice" =~ ^[0-9]+$ ]] && [ "$iso_choice" -ge 1 ] && [ "$iso_choice" -le ${#ISO_LIBRARY[@]} ]; then
                    local selected_key="${iso_keys[$((iso_choice-1))]}"
                    IFS='|' read -r iso_name img_url default_user default_pass <<< "${ISO_LIBRARY[$selected_key]}"
                    OS_TYPE="$selected_key-iso"
                    iso_path="$DATA_DIR/isos/$(basename "$img_url")"
                    break
                else
                    print_status "ERROR" "Invalid selection"
                fi
            done
            ;;
            
        3)
            # Custom Image URL
            while true; do
                read -rp "$(print_status "INPUT" "Enter image URL (QCOW2/ISO): ")" img_url
                if validate_input "url" "$img_url"; then
                    OS_TYPE="custom-url"
                    break
                fi
            done
            ;;
            
        *)
            print_status "ERROR" "Invalid choice"
            return 1
            ;;
    esac
    
    # Resource Allocation (User mode limits)
    print_header
    echo -e "${GREEN}📊 Resource Allocation${NC}"
    echo "─────────────────────────────────────"
    
    # Get available resources
    IFS=' ' read -r available_ram total_disk available_cores <<< "$(get_system_resources)"
    
    # CPU Cores
    while true; do
        read -rp "$(print_status "INPUT" "CPU Cores (1-$available_cores, recommended: 2): ")" cpus
        if validate_input "number" "$cpus" 1 "$available_cores"; then
            CPUS="$cpus"
            break
        fi
    done
    
    # RAM Allocation
    while true; do
        read -rp "$(print_status "INPUT" "RAM in MB (256-$available_ram, recommended: 1024): ")" memory
        if validate_input "number" "$memory" "$MIN_RAM_MB" "$available_ram"; then
            MEMORY="$memory"
            break
        fi
    done
    
    # Disk Size (limited for user mode)
    while true; do
        read -rp "$(print_status "INPUT" "Disk Size (e.g., 20G, min ${MIN_DISK_GB}G, max 50G): ")" disk_size
        if validate_input "size" "$disk_size"; then
            local size_num=${disk_size%[GgMm]}
            local size_unit=${disk_size: -1}
            if [[ "$size_unit" =~ [Gg] ]] && [ "$size_num" -gt 50 ]; then
                print_status "ERROR" "Maximum disk size for user mode is 50G"
            else
                DISK_SIZE="$disk_size"
                break
            fi
        fi
    done
    
    # Network Configuration
    print_header
    echo -e "${GREEN}🌐 Network Configuration${NC}"
    echo "─────────────────────────────────────"
    
    # SSH Port
    SSH_PORT=$(find_available_port)
    print_status "INFO" "Auto-assigned SSH port: $SSH_PORT"
    
    # Additional Port Forwarding
    echo
    read -rp "$(print_status "INPUT" "Add additional port forwards? (y/n): ")" add_ports
    if [[ "$add_ports" =~ ^[Yy]$ ]]; then
        read -rp "$(print_status "INPUT" "Enter port forwards (format: 80:8080,443:8443): ")" port_forwards
        PORT_FORWARDS="$port_forwards"
    else
        PORT_FORWARDS=""
    fi
    
    # GUI Mode
    read -rp "$(print_status "INPUT" "Enable GUI/VNC? (y/n): ")" enable_gui
    if [[ "$enable_gui" =~ ^[Yy]$ ]]; then
        GUI_MODE="yes"
        VNC_PORT=$((5900 + $(find_available_port 5900) % 100))
        print_status "INFO" "VNC port: $VNC_PORT"
    else
        GUI_MODE="no"
    fi
    
    # User Credentials
    print_header
    echo -e "${GREEN}🔐 User Credentials${NC}"
    echo "─────────────────────────────────────"
    
    read -rp "$(print_status "INPUT" "Hostname (default: $VM_NAME): ")" hostname_input
    HOSTNAME="${hostname_input:-$VM_NAME}"
    
    read -rp "$(print_status "INPUT" "Username (default: $USER): ")" username_input
    USERNAME="${username_input:-$USER}"
    
    read -rp "$(print_status "INPUT" "Password (leave empty to generate): ")" password_input
    if [ -z "$password_input" ]; then
        PASSWORD=$(generate_password 12 true)
        print_status "INFO" "Generated password: $PASSWORD"
    else
        PASSWORD="$password_input"
    fi
    
    # SSH Key Injection
    read -rp "$(print_status "INPUT" "Inject SSH public key? (y/n): ")" inject_ssh
    if [[ "$inject_ssh" =~ ^[Yy]$ ]]; then
        SSH_PUB_KEY=$(cat "${SSH_KEY_FILE}.pub")
    else
        SSH_PUB_KEY=""
    fi
    
    # Create Cloud-Init Config
    CREATED=$(date -Iseconds)
    STATUS="stopped"
    
    # Download image if needed
    if [ -n "$img_url" ]; then
        print_status "PROGRESS" "Downloading image from $img_url"
        IMG_FILE="$DATA_DIR/disks/${VM_NAME}.qcow2"
        
        if [[ "$img_url" == *.iso ]]; then
            # ISO download
            iso_path="$DATA_DIR/isos/$(basename "$img_url")"
            mkdir -p "$DATA_DIR/isos"
            
            if [ ! -f "$iso_path" ]; then
                curl -L -o "$iso_path" "$img_url"
                print_status "SUCCESS" "ISO downloaded: $iso_path"
            else
                print_status "INFO" "ISO already exists: $iso_path"
            fi
            
            # Create disk from ISO (user mode)
            qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
        else
            # QCOW2 image (user mode - direct download)
            if [[ "$img_url" == http* ]]; then
                curl -L -o "/tmp/${VM_NAME}.img" "$img_url"
                qemu-img convert -f qcow2 -O qcow2 "/tmp/${VM_NAME}.img" "$IMG_FILE"
                rm -f "/tmp/${VM_NAME}.img"
            fi
            # Resize disk if needed
            qemu-img resize "$IMG_FILE" "$DISK_SIZE"
        fi
    else
        IMG_FILE="$DATA_DIR/disks/${VM_NAME}.qcow2"
        qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
    fi
    
    # Create cloud-init seed image
    SEED_FILE="$DATA_DIR/cloudinit/${VM_NAME}-seed.img"
    create_cloud_init_seed "$VM_NAME" "$HOSTNAME" "$USERNAME" "$PASSWORD" "$SSH_PUB_KEY"
    
    # Save configuration
    save_vm_config
    
    # Offer to start VM
    echo
    read -rp "$(print_status "INPUT" "Start VM now? (y/n): ")" start_now
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
        start_vm "$VM_NAME"
    fi
    
    print_status "SUCCESS" "Virtual Machine '$VM_NAME' created successfully!"
    echo
    echo -e "${GREEN}📋 VM Details:${NC}"
    echo "─────────────────────────────────────"
    echo "Name: $VM_NAME"
    echo "Hostname: $HOSTNAME"
    echo "Username: $USERNAME"
    echo "Password: $PASSWORD"
    echo "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
    echo "Resources: ${CPUS}vCPU, ${MEMORY}MB RAM, ${DISK_SIZE} disk"
    echo "Status: $STATUS"
    echo
}

create_cloud_init_seed() {
    local vm_name=$1
    local hostname=$2
    local username=$3
    local password=$4
    local ssh_key=$5
    
    local cloud_dir="/tmp/cloud-init-$vm_name"
    mkdir -p "$cloud_dir"
    
    # Create user-data
    cat > "$cloud_dir/user-data" << EOF
#cloud-config
hostname: $hostname
manage_etc_hosts: true
users:
  - name: $username
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $(echo "$password" | openssl passwd -6 -stdin)
    ssh_authorized_keys:
      - $ssh_key
    groups: users, sudo
    home: /home/$username
    system: false
    primary_group: $username

# Enable password authentication with SSH
ssh_pwauth: true
disable_root: false

# Update packages on first boot
package_update: true
package_upgrade: true

# Install useful packages
packages:
  - qemu-guest-agent
  - curl
  - wget
  - nano
  - htop
  - net-tools

# Run commands on first boot
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - systemctl restart sshd
EOF
    
    # Create meta-data
    cat > "$cloud_dir/meta-data" << EOF
instance-id: $vm_name
local-hostname: $hostname
EOF
    
    # Create network-config
    cat > "$cloud_dir/network-config" << EOF
version: 2
ethernets:
  eth0:
    dhcp4: true
    dhcp6: true
    optional: true
EOF
    
    # Create seed image
    cloud-localds -v "$SEED_FILE" \
        "$cloud_dir/user-data" \
        "$cloud_dir/meta-data" \
        "$cloud_dir/network-config"
    
    rm -rf "$cloud_dir"
    print_status "SUCCESS" "Cloud-init seed image created: $SEED_FILE"
}

start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "PROGRESS" "Starting VM: $vm_name"
        
        # Check if VM is already running
        if ps aux | grep -q "[q]emu-system.*$IMG_FILE"; then
            print_status "WARNING" "VM '$vm_name' is already running"
            return 1
        fi
        
        # Build QEMU command (user mode)
        local qemu_cmd="qemu-system-x86_64"
        
        # Basic parameters
        qemu_cmd+=" -name $vm_name"
        qemu_cmd+=" -machine q35"
        qemu_cmd+=" -cpu host"
        qemu_cmd+=" -smp $CPUS"
        qemu_cmd+=" -m ${MEMORY}M"
        
        # Try to use KVM if available
        if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            qemu_cmd+=" -enable-kvm"
        fi
        
        # Display
        if [ "$GUI_MODE" = "yes" ]; then
            qemu_cmd+=" -vnc :$((VNC_PORT - 5900))"
        else
            qemu_cmd+=" -nographic"
        fi
        
        # Disk and CD-ROM
        qemu_cmd+=" -drive file=$IMG_FILE,if=virtio,format=qcow2"
        qemu_cmd+=" -drive file=$SEED_FILE,if=virtio,format=raw"
        
        # Network (user mode networking)
        qemu_cmd+=" -netdev user,id=net0,hostfwd=tcp::$SSH_PORT-:22"
        
        # Add additional port forwards
        if [ -n "$PORT_FORWARDS" ]; then
            IFS=',' read -ra ports <<< "$PORT_FORWARDS"
            for port_pair in "${ports[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$port_pair"
                qemu_cmd+=",hostfwd=tcp::$host_port-:$guest_port"
            done
        fi
        
        qemu_cmd+=" -device virtio-net-pci,netdev=net0"
        
        # Additional optimizations for user mode
        qemu_cmd+=" -daemonize"
        qemu_cmd+=" -pidfile /tmp/qemu-$vm_name.pid"
        
        # Start VM
        eval "$qemu_cmd"
        
        if [ $? -eq 0 ]; then
            STATUS="running"
            save_vm_config
            print_status "SUCCESS" "VM '$vm_name' started successfully!"
            print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
            if [ "$GUI_MODE" = "yes" ]; then
                print_status "INFO" "VNC: vncviewer localhost:$VNC_PORT"
            fi
            log_message "VM" "Started VM: $vm_name"
        else
            print_status "ERROR" "Failed to start VM '$vm_name'"
            log_message "ERROR" "Failed to start VM: $vm_name"
        fi
    fi
}

# =============================================================================
# DOCKER VM FUNCTIONS (User Mode)
# =============================================================================

create_docker_vm_advanced() {
    local node_id="$1"
    local node_name="$2"
    
    print_header
    echo -e "${GREEN}🐳 Create Docker Container (User Mode)${NC}"
    echo -e "${YELLOW}Location: ${node_name}${NC}"
    echo
    
    # Check Docker availability
    if ! command -v docker > /dev/null 2>&1; then
        print_status "ERROR" "Docker is not installed"
        print_status "INFO" "Install Docker with: curl -fsSL https://get.docker.com | sh"
        print_status "INFO" "Then add user to docker group: sudo usermod -aG docker $USER"
        return 1
    fi
    
    # Check if user can run docker
    if ! docker info > /dev/null 2>&1; then
        print_status "ERROR" "Cannot connect to Docker daemon"
        print_status "INFO" "Make sure Docker is running and user has permissions"
        print_status "INFO" "You may need to log out and log back in after adding to docker group"
        return 1
    fi
    
    # Container Name
    while true; do
        read -rp "$(print_status "INPUT" "Container Name: ")" container_name
        if validate_input "name" "$container_name"; then
            if docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
                print_status "ERROR" "Container '$container_name' already exists"
            else
                break
            fi
        fi
    done
    
    # Image Selection
    print_header
    echo -e "${GREEN}📦 Select Docker Image${NC}"
    echo "─────────────────────────────────────"
    local index=1
    local image_keys=("${!DOCKER_IMAGES[@]}")
    for key in "${image_keys[@]}"; do
        IFS='|' read -r name image <<< "${DOCKER_IMAGES[$key]}"
        printf "%2d) %-25s → %s\n" "$index" "$name" "$image"
        ((index++))
    done
    echo
    echo "  c) Custom Image"
    echo
    
    read -rp "$(print_status "INPUT" "Select image (1-${#DOCKER_IMAGES[@]} or 'c'): ")" image_choice
    
    local docker_image=""
    if [[ "$image_choice" == "c" ]]; then
        read -rp "$(print_status "INPUT" "Enter Docker image name (e.g., nginx:alpine): ")" docker_image
    elif [[ "$image_choice" =~ ^[0-9]+$ ]] && [ "$image_choice" -ge 1 ] && [ "$image_choice" -le ${#DOCKER_IMAGES[@]} ]; then
        local selected_key="${image_keys[$((image_choice-1))]}"
        IFS='|' read -r name docker_image <<< "${DOCKER_IMAGES[$selected_key]}"
    else
        print_status "ERROR" "Invalid selection"
        return 1
    fi
    
    # Port Mapping
    local port_mapping=""
    read -rp "$(print_status "INPUT" "Add port mapping? (e.g., 80:8080 or leave empty): ")" ports_input
    if [ -n "$ports_input" ]; then
        port_mapping="-p $ports_input"
    fi
    
    # Volume Mapping (user home directory)
    local volume_mapping=""
    read -rp "$(print_status "INPUT" "Mount host directory? (e.g., ~/data:/data or leave empty): ")" volume_input
    if [ -n "$volume_input" ]; then
        # Expand ~ to home directory
        volume_input="${volume_input/#\~/$HOME}"
        volume_mapping="-v $volume_input"
    fi
    
    # Environment Variables
    local env_vars=""
    read -rp "$(print_status "INPUT" "Add environment variables? (e.g., KEY=value or leave empty): ")" env_input
    if [ -n "$env_input" ]; then
        env_vars="-e $env_input"
    fi
    
    # Create container
    print_status "PROGRESS" "Pulling image: $docker_image"
    docker pull "$docker_image"
    
    local docker_cmd="docker run -d"
    docker_cmd+=" --name $container_name"
    docker_cmd+=" --restart unless-stopped"
    [ -n "$port_mapping" ] && docker_cmd+=" $port_mapping"
    [ -n "$volume_mapping" ] && docker_cmd+=" $volume_mapping"
    [ -n "$env_vars" ] && docker_cmd+=" $env_vars"
    docker_cmd+=" $docker_image"
    
    print_status "PROGRESS" "Creating container: $container_name"
    if eval "$docker_cmd"; then
        print_status "SUCCESS" "Docker container '$container_name' created successfully!"
        
        # Save configuration
        local config_file="$DATA_DIR/dockervm/${container_name}.conf"
        cat > "$config_file" << EOF
CONTAINER_NAME="$container_name"
DOCKER_IMAGE="$docker_image"
PORTS="$ports_input"
VOLUMES="$volume_input"
ENV_VARS="$env_input"
CREATED="$(date -Iseconds)"
STATUS="running"
EOF
        
        log_message "DOCKER" "Created container: $container_name"
        
        # Show container info
        echo
        echo -e "${GREEN}📋 Container Details:${NC}"
        echo "─────────────────────────────────────"
        echo "Name: $container_name"
        echo "Image: $docker_image"
        echo "Status: running"
        [ -n "$ports_input" ] && echo "Ports: $ports_input"
        docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_name" | xargs -I {} echo "IP Address: {}"
        
        # Show useful commands
        echo
        echo -e "${YELLOW}Useful Commands:${NC}"
        echo "  Stop: docker stop $container_name"
        echo "  Start: docker start $container_name"
        echo "  Logs: docker logs $container_name"
        echo "  Shell: docker exec -it $container_name /bin/bash"
    else
        print_status "ERROR" "Failed to create container"
    fi
}

# =============================================================================
# JUPYTER NOTEBOOK FUNCTIONS (User Mode)
# =============================================================================

create_jupyter_vm() {
    local node_id="$1"
    local node_name="$2"
    
    print_header
    echo -e "${GREEN}🔬 Create Jupyter Notebook Server (User Mode)${NC}"
    echo -e "${YELLOW}Location: ${node_name}${NC}"
    echo
    
    # Check Docker availability
    if ! command -v docker > /dev/null 2>&1; then
        print_status "ERROR" "Docker is required for Jupyter notebooks"
        return 1
    fi
    
    # Notebook Name
    while true; do
        read -rp "$(print_status "INPUT" "Notebook Server Name: ")" notebook_name
        if validate_input "name" "$notebook_name"; then
            if [ -f "$DATA_DIR/jupyter/${notebook_name}.conf" ]; then
                print_status "ERROR" "Notebook '$notebook_name' already exists"
            else
                break
            fi
        fi
    done
    
    # Template Selection
    print_header
    echo -e "${GREEN}📚 Select Jupyter Template${NC}"
    echo "─────────────────────────────────────"
    local index=1
    local template_keys=("${!JUPYTER_TEMPLATES[@]}")
    for key in "${template_keys[@]}"; do
        IFS='|' read -r name image port tags <<< "${JUPYTER_TEMPLATES[$key]}"
        printf "%2d) %-25s → %s\n" "$index" "$name" "$tags"
        ((index++))
    done
    echo
    
    while true; do
        read -rp "$(print_status "INPUT" "Select template (1-${#JUPYTER_TEMPLATES[@]}): ")" template_choice
        
        if [[ "$template_choice" =~ ^[0-9]+$ ]] && [ "$template_choice" -ge 1 ] && [ "$template_choice" -le ${#JUPYTER_TEMPLATES[@]} ]; then
            local selected_key="${template_keys[$((template_choice-1))]}"
            IFS='|' read -r notebook_name_full notebook_image notebook_port notebook_tags <<< "${JUPYTER_TEMPLATES[$selected_key]}"
            break
        else
            print_status "ERROR" "Invalid selection"
        fi
    done
    
    # Port Configuration
    local available_port=$(find_available_port "$notebook_port")
    print_status "INFO" "Jupyter port: $available_port"
    
    # Volume for persistent data (in user home)
    local volume_path="$HOME/jupyter/${notebook_name}"
    mkdir -p "$volume_path"
    
    # Token generation
    local jupyter_token=$(generate_password 32 false)
    
    # Create Jupyter container
    print_status "PROGRESS" "Creating Jupyter notebook server: $notebook_name"
    
    local docker_cmd="docker run -d"
    docker_cmd+=" --name jupyter-$notebook_name"
    docker_cmd+=" -p $available_port:8888"
    docker_cmd+=" -v $volume_path:/home/jovyan/work"
    docker_cmd+=" -e JUPYTER_TOKEN=$jupyter_token"
    docker_cmd+=" --restart unless-stopped"
    docker_cmd+=" $notebook_image"
    
    if eval "$docker_cmd"; then
        print_status "SUCCESS" "Jupyter notebook server created successfully!"
        
        # Save configuration
        local config_file="$DATA_DIR/jupyter/${notebook_name}.conf"
        cat > "$config_file" << EOF
NOTEBOOK_NAME="$notebook_name"
JUPYTER_IMAGE="$notebook_image"
JUPYTER_PORT="$available_port"
JUPYTER_TOKEN="$jupyter_token"
VOLUME_PATH="$volume_path"
CREATED="$(date -Iseconds)"
STATUS="running"
EOF
        
        log_message "JUPYTER" "Created notebook server: $notebook_name"
        
        # Show access details
        echo
        echo -e "${GREEN}📋 Jupyter Details:${NC}"
        echo "─────────────────────────────────────"
        echo "Name: $notebook_name"
        echo "URL: http://localhost:$available_port"
        echo "Token: $jupyter_token"
        echo "Volume: $volume_path"
        echo
        echo -e "${YELLOW}Access your notebook at: http://localhost:$available_port${NC}"
        echo -e "${YELLOW}Use token: $jupyter_token${NC}"
        
        # Auto-open browser if possible
        if command -v xdg-open > /dev/null 2>&1; then
            read -rp "$(print_status "INPUT" "Open in browser now? (y/n): ")" open_browser
            if [[ "$open_browser" =~ ^[Yy]$ ]]; then
                xdg-open "http://localhost:$available_port" &
            fi
        fi
    else
        print_status "ERROR" "Failed to create Jupyter notebook server"
    fi
}

# =============================================================================
# VM MANAGEMENT DASHBOARD
# =============================================================================

stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        local pid_file="/tmp/qemu-$vm_name.pid"
        
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file")
            if kill -TERM "$pid" 2>/dev/null; then
                print_status "SUCCESS" "VM '$vm_name' stopped successfully"
                STATUS="stopped"
                save_vm_config
                rm -f "$pid_file"
                log_message "VM" "Stopped VM: $vm_name"
            else
                print_status "ERROR" "Failed to stop VM '$vm_name'"
            fi
        else
            print_status "WARNING" "VM '$vm_name' is not running or PID file not found"
        fi
    fi
}

delete_vm() {
    local vm_name=$1
    
    print_header
    echo -e "${RED}⚠️ DELETE VIRTUAL MACHINE⚠️${NC}"
    echo "─────────────────────────────────────"
    echo -e "${YELLOW}This will permanently delete:${NC}"
    echo "• VM Configuration"
    echo "• Virtual Disk"
    echo "• Snapshots"
    echo "• Cloud-init seed"
    echo
    
    read -rp "$(print_status "INPUT" "Type '$vm_name' to confirm deletion: ")" confirm
    
    if [ "$confirm" = "$vm_name" ]; then
        # Stop VM if running
        stop_vm "$vm_name" 2>/dev/null
        
        # Remove files
        rm -f "$DATA_DIR/vms/$vm_name.conf"
        rm -f "$DATA_DIR/disks/$vm_name.qcow2"
        rm -f "$DATA_DIR/cloudinit/$vm_name-seed.img"
        rm -f "/tmp/qemu-$vm_name.pid"
        rm -rf "$DATA_DIR/snapshots/$vm_name"
        
        print_status "SUCCESS" "VM '$vm_name' deleted successfully"
        log_message "VM" "Deleted VM: $vm_name"
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

view_vm_details() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_header
        echo -e "${GREEN}📋 VM Details: $vm_name${NC}"
        echo "─────────────────────────────────────"
        echo "Name: $VM_NAME"
        echo "Node: $NODE_ID"
        echo "OS Type: $OS_TYPE"
        echo "Hostname: $HOSTNAME"
        echo "Username: $USERNAME"
        echo "Password: $PASSWORD"
        echo "SSH Port: $SSH_PORT"
        echo "Created: $CREATED"
        echo "Status: $STATUS"
        echo
        echo -e "${CYAN}Resources:${NC}"
        echo "  CPU Cores: $CPUS"
        echo "  Memory: ${MEMORY}MB"
        echo "  Disk: $DISK_SIZE"
        echo
        echo -e "${CYAN}Network:${NC}"
        echo "  SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        if [ "$GUI_MODE" = "yes" ]; then
            echo "  VNC: vncviewer localhost:$VNC_PORT"
        fi
        if [ -n "$PORT_FORWARDS" ]; then
            echo "  Port Forwards: $PORT_FORWARDS"
        fi
        echo
        echo -e "${CYAN}Files:${NC}"
        echo "  Disk: $IMG_FILE"
        echo "  Seed: $SEED_FILE"
        echo "  Config: $DATA_DIR/vms/$vm_name.conf"
    fi
}

connect_vm_ssh() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Connecting to $vm_name via SSH..."
        echo -e "${YELLOW}Username: $USERNAME${NC}"
        echo -e "${YELLOW}Password: $PASSWORD${NC}"
        echo -e "${YELLOW}Port: $SSH_PORT${NC}"
        echo
        
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -p "$SSH_PORT" "$USERNAME@localhost"
    fi
}

create_snapshot() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        local snapshot_name="${vm_name}-snapshot-$(date +%Y%m%d-%H%M%S)"
        local snapshot_dir="$DATA_DIR/snapshots/$vm_name"
        mkdir -p "$snapshot_dir"
        
        # Stop VM before snapshot
        stop_vm "$vm_name"
        
        # Create snapshot copy
        if cp "$IMG_FILE" "$snapshot_dir/${snapshot_name}.qcow2"; then
            # Copy configuration
            cp "$DATA_DIR/vms/$vm_name.conf" "$snapshot_dir/${snapshot_name}.conf"
            
            print_status "SUCCESS" "Snapshot '$snapshot_name' created successfully"
            log_message "SNAPSHOT" "Created snapshot for VM: $vm_name"
        else
            print_status "ERROR" "Failed to create snapshot"
        fi
    fi
}

# =============================================================================
# MAIN MENU (User Mode)
# =============================================================================

main_menu() {
    while true; do
        print_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        # Display VM status if any exist
        if [ $vm_count -gt 0 ]; then
            echo -e "${GREEN}📊 Virtual Machines (${vm_count} total):${NC}"
            echo "─────────────────────────────────────"
            
            for i in "${!vms[@]}"; do
                local vm_name="${vms[$i]}"
                local status="🔴 Stopped"
                local config_file="$DATA_DIR/vms/$vm_name.conf"
                
                if [[ -f "$config_file" ]]; then
                    source "$config_file" 2>/dev/null
                    
                    # Check if VM is running
                    local pid_file="/tmp/qemu-$vm_name.pid"
                    if [ -f "$pid_file" ] && ps -p "$(cat "$pid_file")" > /dev/null 2>&1; then
                        status="🟢 Running"
                    fi
                    
                    printf "  %2d) %-25s %-12s\n" $((i+1)) "$vm_name" "$status"
                else
                    printf "  %2d) %-25s %-12s\n" $((i+1)) "$vm_name" "❓ Unknown"
                fi
            done
            echo
        fi
        
        # Enhanced Main Menu Options (User Mode)
        echo -e "${GREEN}🏠 Main Menu (User Mode):${NC}"
        echo "   1) ⚡ Create New Virtual Machine"
        echo "   2) 🖥️  VM Management Dashboard"
        echo "   3) 🐳 Docker Containers"
        echo "   4) 🔬 Jupyter Notebooks"
        echo "   5) 📦 ISO & Template Library"
        echo "   6) 💾 Backup & Restore"
        echo "   7) ⚙️  Settings"
        echo "   8) 🔧 System Diagnostics"
        echo "   9) 📚 Documentation & Help"
        echo "   0) 🚪 Exit"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-9): ")" choice
        
        case $choice in
            1) create_new_vm_advanced ;;
            2) vm_management_dashboard ;;
            3) docker_vm_menu ;;
            4) jupyter_cloud_menu ;;
            5) iso_library_menu ;;
            6) backup_menu ;;
            7) settings_menu ;;
            8) system_diagnostics_menu ;;
            9) show_documentation ;;
            0) 
                print_status "INFO" "Thank you for using ZynexForge CloudStack™!"
                log_message "SYSTEM" "User exited from main menu"
                exit 0
                ;;
            *) 
                print_status "ERROR" "Invalid option. Please try again."
                sleep 1
                ;;
        esac
    done
}

create_new_vm_advanced() {
    print_header
    echo -e "${GREEN}🚀 Create New Virtual Machine (User Mode)${NC}"
    echo -e "${YELLOW}Step 1: Select Virtualization Technology${NC}"
    echo
    
    # In user mode, we only support local deployment
    local node_id="local"
    local node_name="Local User Mode"
    local node_ip="127.0.0.1"
    
    echo "Available Virtualization Types:"
    echo "───────────────────────────────"
    echo "  1) 🖥️  QEMU/KVM Virtual Machine"
    echo "     └─ Complete OS isolation • Best performance"
    echo
    echo "  2) 🐳 Docker Container"
    echo "     └─ Lightweight • Fast startup • Portable"
    echo
    echo "  3) 🔬 Jupyter Notebook Server"
    echo "     └─ Data science • Machine learning • Code sandbox"
    echo
    
    while true; do
        read -rp "$(print_status "INPUT" "Select virtualization type (1-3): ")" vm_type_choice
        
        case $vm_type_choice in
            1)
                create_kvm_vm "$node_id" "$node_name" "$node_ip"
                break
                ;;
            2)
                create_docker_vm_advanced "$node_id" "$node_name"
                break
                ;;
            3)
                create_jupyter_vm "$node_id" "$node_name"
                break
                ;;
            *)
                print_status "ERROR" "Invalid selection. Please enter 1-3."
                ;;
        esac
    done
}

vm_management_dashboard() {
    while true; do
        print_header
        echo -e "${GREEN}🖥️ VM Management Dashboard${NC}"
        echo "─────────────────────────────────────"
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -eq 0 ]; then
            echo -e "${YELLOW}No virtual machines found.${NC}"
            echo
            read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to return...")"
            return
        fi
        
        # Display VMs with status
        echo -e "${CYAN}Virtual Machines (${vm_count} total):${NC}"
        echo "─────────────────────────────────────"
        
        for i in "${!vms[@]}"; do
            local vm_name="${vms[$i]}"
            local config_file="$DATA_DIR/vms/$vm_name.conf"
            
            if [[ -f "$config_file" ]]; then
                source "$config_file" 2>/dev/null
                
                # Check if VM is running
                local status="🔴 Stopped"
                local pid_file="/tmp/qemu-$vm_name.pid"
                if [ -f "$pid_file" ] && ps -p "$(cat "$pid_file")" > /dev/null 2>&1; then
                    status="🟢 Running"
                fi
                
                printf "  %2d) %-25s %-12s\n" $((i+1)) "$vm_name" "$status"
            fi
        done
        
        echo
        echo -e "${GREEN}📋 Management Options:${NC}"
        echo "   1) ▶️  Start VM"
        echo "   2) ⏹️  Stop VM"
        echo "   3) 🔄 Restart VM"
        echo "   4) 🗑️  Delete VM"
        echo "   5) 📊 View VM Details"
        echo "   6) 💾 Create Snapshot"
        echo "   7) 📡 Connect via SSH"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-7): ")" choice
        
        case $choice in
            1)
                read -rp "$(print_status "INPUT" "Enter VM number to start: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                    start_vm "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "Invalid selection"
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            2)
                read -rp "$(print_status "INPUT" "Enter VM number to stop: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                    stop_vm "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "Invalid selection"
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            3)
                read -rp "$(print_status "INPUT" "Enter VM number to restart: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                    stop_vm "${vms[$((vm_num-1))]}"
                    sleep 2
                    start_vm "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "Invalid selection"
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            4)
                read -rp "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                    delete_vm "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "Invalid selection"
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            5)
                read -rp "$(print_status "INPUT" "Enter VM number to view: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                    view_vm_details "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "Invalid selection"
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            6)
                read -rp "$(print_status "INPUT" "Enter VM number for snapshot: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                    create_snapshot "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "Invalid selection"
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            7)
                read -rp "$(print_status "INPUT" "Enter VM number to connect: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                    connect_vm_ssh "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "Invalid selection"
                fi
                ;;
            0)
                return
                ;;
            *)
                print_status "ERROR" "Invalid option"
                sleep 1
                ;;
        esac
    done
}

docker_vm_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🐳 Docker Container Management${NC}"
        echo "─────────────────────────────────────"
        
        # List Docker containers
        local containers=()
        if command -v docker > /dev/null 2>&1 && docker info > /dev/null 2>&1; then
            containers=($(docker ps -a --format "{{.Names}}" | sort))
        fi
        
        local container_count=${#containers[@]}
        
        if [ $container_count -gt 0 ]; then
            echo -e "${CYAN}Docker Containers (${container_count} total):${NC}"
            echo "─────────────────────────────────────"
            
            for i in "${!containers[@]}"; do
                local container_name="${containers[$i]}"
                local status=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null || echo "unknown")
                
                if [ "$status" = "running" ]; then
                    status="🟢 Running"
                else
                    status="🔴 Stopped"
                fi
                
                printf "  %2d) %-25s %-12s\n" $((i+1)) "$container_name" "$status"
            done
        else
            echo -e "${YELLOW}No Docker containers found.${NC}"
        fi
        
        echo
        echo -e "${GREEN}📋 Docker Management Options:${NC}"
        echo "   1) 🐳 Create New Docker Container"
        if [ $container_count -gt 0 ]; then
            echo "   2) ▶️  Start Container"
            echo "   3) ⏹️  Stop Container"
            echo "   4) 🔄 Restart Container"
            echo "   5) 📜 View Container Logs"
            echo "   6) 🐚 Open Container Shell"
            echo "   7) 🗑️  Remove Container"
        fi
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-7): ")" choice
        
        case $choice in
            1)
                create_docker_vm_advanced "local" "Local User Mode"
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            2)
                if [ $container_count -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter container number to start: ")" container_num
                    if [[ "$container_num" =~ ^[0-9]+$ ]] && [ "$container_num" -ge 1 ] && [ "$container_num" -le ${#containers[@]} ]; then
                        docker start "${containers[$((container_num-1))]}"
                        print_status "SUCCESS" "Container started"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            3)
                if [ $container_count -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter container number to stop: ")" container_num
                    if [[ "$container_num" =~ ^[0-9]+$ ]] && [ "$container_num" -ge 1 ] && [ "$container_num" -le ${#containers[@]} ]; then
                        docker stop "${containers[$((container_num-1))]}"
                        print_status "SUCCESS" "Container stopped"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            4)
                if [ $container_count -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter container number to restart: ")" container_num
                    if [[ "$container_num" =~ ^[0-9]+$ ]] && [ "$container_num" -ge 1 ] && [ "$container_num" -le ${#containers[@]} ]; then
                        docker restart "${containers[$((container_num-1))]}"
                        print_status "SUCCESS" "Container restarted"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            5)
                if [ $container_count -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter container number for logs: ")" container_num
                    if [[ "$container_num" =~ ^[0-9]+$ ]] && [ "$container_num" -ge 1 ] && [ "$container_num" -le ${#containers[@]} ]; then
                        clear
                        echo -e "${GREEN}📜 Logs for ${containers[$((container_num-1))]}${NC}"
                        echo "─────────────────────────────────────"
                        docker logs "${containers[$((container_num-1))]}"
                        echo
                        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $container_count -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter container number for shell: ")" container_num
                    if [[ "$container_num" =~ ^[0-9]+$ ]] && [ "$container_num" -ge 1 ] && [ "$container_num" -le ${#containers[@]} ]; then
                        clear
                        echo -e "${GREEN}🐚 Shell for ${containers[$((container_num-1))]}${NC}"
                        echo "─────────────────────────────────────"
                        docker exec -it "${containers[$((container_num-1))]}" /bin/bash || \
                        docker exec -it "${containers[$((container_num-1))]}" /bin/sh || \
                        echo "No shell available in container"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            7)
                if [ $container_count -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter container number to remove: ")" container_num
                    if [[ "$container_num" =~ ^[0-9]+$ ]] && [ "$container_num" -ge 1 ] && [ "$container_num" -le ${#containers[@]} ]; then
                        docker rm -f "${containers[$((container_num-1))]}"
                        print_status "SUCCESS" "Container removed"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            0)
                return
                ;;
            *)
                print_status "ERROR" "Invalid option"
                sleep 1
                ;;
        esac
    done
}

jupyter_cloud_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🔬 Jupyter Notebook Management${NC}"
        echo "─────────────────────────────────────"
        
        # List Jupyter notebooks
        local notebooks=()
        if [ -d "$DATA_DIR/jupyter" ]; then
            notebooks=($(find "$DATA_DIR/jupyter" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort))
        fi
        
        local notebook_count=${#notebooks[@]}
        
        if [ $notebook_count -gt 0 ]; then
            echo -e "${CYAN}Jupyter Notebooks (${notebook_count} total):${NC}"
            echo "─────────────────────────────────────"
            
            for i in "${!notebooks[@]}"; do
                local notebook_name="${notebooks[$i]}"
                local config_file="$DATA_DIR/jupyter/$notebook_name.conf"
                
                if [[ -f "$config_file" ]]; then
                    source "$config_file" 2>/dev/null
                    local status=$(docker inspect -f '{{.State.Status}}' "jupyter-$notebook_name" 2>/dev/null || echo "unknown")
                    
                    if [ "$status" = "running" ]; then
                        status="🟢 Running"
                    else
                        status="🔴 Stopped"
                    fi
                    
                    printf "  %2d) %-25s %-12s Port: %s\n" $((i+1)) "$notebook_name" "$status" "$JUPYTER_PORT"
                fi
            done
        else
            echo -e "${YELLOW}No Jupyter notebooks found.${NC}"
        fi
        
        echo
        echo -e "${GREEN}📋 Jupyter Management Options:${NC}"
        echo "   1) 🔬 Create New Jupyter Notebook"
        if [ $notebook_count -gt 0 ]; then
            echo "   2) ▶️  Start Notebook"
            echo "   3) ⏹️  Stop Notebook"
            echo "   4) 🌐 Open in Browser"
            echo "   5) 📜 View Notebook Logs"
            echo "   6) 🗑️  Remove Notebook"
        fi
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-6): ")" choice
        
        case $choice in
            1)
                create_jupyter_vm "local" "Local User Mode"
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            2)
                if [ $notebook_count -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter notebook number to start: ")" notebook_num
                    if [[ "$notebook_num" =~ ^[0-9]+$ ]] && [ "$notebook_num" -ge 1 ] && [ "$notebook_num" -le ${#notebooks[@]} ]; then
                        local notebook_name="${notebooks[$((notebook_num-1))]}"
                        docker start "jupyter-$notebook_name"
                        print_status "SUCCESS" "Jupyter notebook started"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            3)
                if [ $notebook_count -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter notebook number to stop: ")" notebook_num
                    if [[ "$notebook_num" =~ ^[0-9]+$ ]] && [ "$notebook_num" -ge 1 ] && [ "$notebook_num" -le ${#notebooks[@]} ]; then
                        local notebook_name="${notebooks[$((notebook_num-1))]}"
                        docker stop "jupyter-$notebook_name"
                        print_status "SUCCESS" "Jupyter notebook stopped"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            4)
                if [ $notebook_count -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter notebook number to open: ")" notebook_num
                    if [[ "$notebook_num" =~ ^[0-9]+$ ]] && [ "$notebook_num" -ge 1 ] && [ "$notebook_num" -le ${#notebooks[@]} ]; then
                        local notebook_name="${notebooks[$((notebook_num-1))]}"
                        local config_file="$DATA_DIR/jupyter/$notebook_name.conf"
                        
                        if [[ -f "$config_file" ]]; then
                            source "$config_file" 2>/dev/null
                            if command -v xdg-open > /dev/null 2>&1; then
                                xdg-open "http://localhost:$JUPYTER_PORT" &
                                print_status "SUCCESS" "Opening browser..."
                            else
                                print_status "INFO" "Open browser manually: http://localhost:$JUPYTER_PORT"
                                print_status "INFO" "Token: $JUPYTER_TOKEN"
                            fi
                        fi
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            5)
                if [ $notebook_count -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter notebook number for logs: ")" notebook_num
                    if [[ "$notebook_num" =~ ^[0-9]+$ ]] && [ "$notebook_num" -ge 1 ] && [ "$notebook_num" -le ${#notebooks[@]} ]; then
                        local notebook_name="${notebooks[$((notebook_num-1))]}"
                        clear
                        echo -e "${GREEN}📜 Logs for $notebook_name${NC}"
                        echo "─────────────────────────────────────"
                        docker logs "jupyter-$notebook_name"
                        echo
                        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $notebook_count -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter notebook number to remove: ")" notebook_num
                    if [[ "$notebook_num" =~ ^[0-9]+$ ]] && [ "$notebook_num" -ge 1 ] && [ "$notebook_num" -le ${#notebooks[@]} ]; then
                        local notebook_name="${notebooks[$((notebook_num-1))]}"
                        docker rm -f "jupyter-$notebook_name"
                        rm -f "$DATA_DIR/jupyter/$notebook_name.conf"
                        print_status "SUCCESS" "Jupyter notebook removed"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            0)
                return
                ;;
            *)
                print_status "ERROR" "Invalid option"
                sleep 1
                ;;
        esac
    done
}

iso_library_menu() {
    while true; do
        print_header
        echo -e "${GREEN}📦 ISO & Template Library${NC}"
        echo "─────────────────────────────────────"
        
        # Show downloaded ISOs
        local iso_count=0
        if [ -d "$DATA_DIR/isos" ]; then
            iso_count=$(ls "$DATA_DIR/isos"/*.iso 2>/dev/null | wc -l)
        fi
        
        echo -e "${CYAN}Downloaded ISOs ($iso_count):${NC}"
        if [ $iso_count -gt 0 ]; then
            ls -1 "$DATA_DIR/isos"/*.iso 2>/dev/null | xargs -n1 basename | while read iso; do
                local size=$(du -h "$DATA_DIR/isos/$iso" 2>/dev/null | cut -f1)
                echo "  • $iso ($size)"
            done
        else
            echo "  No ISOs downloaded yet"
        fi
        
        echo
        echo -e "${CYAN}Available ISO Templates:${NC}"
        local index=1
        for iso_key in "${!ISO_LIBRARY[@]}"; do
            IFS='|' read -r name url username password <<< "${ISO_LIBRARY[$iso_key]}"
            printf "%2d) %-30s\n" "$index" "$name"
            ((index++))
        done
        
        echo
        echo -e "${GREEN}📋 ISO Management Options:${NC}"
        echo "   1) 📥 Download ISO"
        echo "   2) 🗑️  Delete ISO"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-2): ")" choice
        
        case $choice in
            1) download_iso ;;
            2) delete_iso ;;
            0) return ;;
            *) print_status "ERROR" "Invalid option" ;;
        esac
        
        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
    done
}

download_iso() {
    print_header
    echo -e "${GREEN}📥 Download ISO Image${NC}"
    echo "─────────────────────────────────────"
    
    # List available ISOs
    local index=1
    local iso_keys=("${!ISO_LIBRARY[@]}")
    for key in "${iso_keys[@]}"; do
        IFS='|' read -r name url username password <<< "${ISO_LIBRARY[$key]}"
        printf "%2d) %-30s\n" "$index" "$name"
        ((index++))
    done
    
    echo
    read -rp "$(print_status "INPUT" "Select ISO to download (1-${#ISO_LIBRARY[@]}): ")" iso_choice
    
    if [[ "$iso_choice" =~ ^[0-9]+$ ]] && [ "$iso_choice" -ge 1 ] && [ "$iso_choice" -le ${#ISO_LIBRARY[@]} ]; then
        local selected_key="${iso_keys[$((iso_choice-1))]}"
        IFS='|' read -r iso_name iso_url iso_user iso_pass <<< "${ISO_LIBRARY[$selected_key]}"
        
        local filename="$DATA_DIR/isos/$(basename "$iso_url")"
        mkdir -p "$DATA_DIR/isos"
        
        print_status "PROGRESS" "Downloading $iso_name..."
        print_status "INFO" "URL: $iso_url"
        print_status "INFO" "Destination: $filename"
        
        # Download with progress bar
        if command -v curl > /dev/null 2>&1; then
            curl -L -o "$filename" --progress-bar "$iso_url"
        elif command -v wget > /dev/null 2>&1; then
            wget -O "$filename" --progress=bar:force "$iso_url"
        else
            print_status "ERROR" "curl or wget not found"
            return 1
        fi
        
        if [ $? -eq 0 ]; then
            local size=$(du -h "$filename" | cut -f1)
            print_status "SUCCESS" "Download completed: $filename ($size)"
            log_message "ISO" "Downloaded ISO: $iso_name"
        else
            print_status "ERROR" "Download failed"
        fi
    else
        print_status "ERROR" "Invalid selection"
    fi
}

delete_iso() {
    print_header
    echo -e "${GREEN}🗑️ Delete ISO Image${NC}"
    echo "─────────────────────────────────────"
    
    # List downloaded ISOs
    local isos=()
    if [ -d "$DATA_DIR/isos" ]; then
        isos=($(ls "$DATA_DIR/isos"/*.iso 2>/dev/null | xargs -n1 basename))
    fi
    
    if [ ${#isos[@]} -eq 0 ]; then
        print_status "INFO" "No ISO images found"
        return
    fi
    
    echo "Available ISOs:"
    for i in "${!isos[@]}"; do
        local size=$(du -h "$DATA_DIR/isos/${isos[$i]}" 2>/dev/null | cut -f1)
        printf "%2d) %-40s (%s)\n" $((i+1)) "${isos[$i]}" "$size"
    done
    
    echo
    read -rp "$(print_status "INPUT" "Select ISO to delete (1-${#isos[@]}): ")" iso_choice
    
    if [[ "$iso_choice" =~ ^[0-9]+$ ]] && [ "$iso_choice" -ge 1 ] && [ "$iso_choice" -le ${#isos[@]} ]; then
        local iso_file="${isos[$((iso_choice-1))]}"
        read -rp "$(print_status "INPUT" "Delete '$iso_file'? (y/N): ")" confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -f "$DATA_DIR/isos/$iso_file"
            print_status "SUCCESS" "ISO deleted: $iso_file"
        else
            print_status "INFO" "Deletion cancelled"
        fi
    else
        print_status "ERROR" "Invalid selection"
    fi
}

# =============================================================================
# BACKUP MENU (User Mode)
# =============================================================================

backup_menu() {
    while true; do
        print_header
        echo -e "${GREEN}💾 Backup & Restore${NC}"
        echo "─────────────────────────────────────"
        
        # Backup statistics
        local backup_count=0
        if [ -d "$DATA_DIR/backups" ]; then
            backup_count=$(find "$DATA_DIR/backups" -name "*.tar.gz" 2>/dev/null | wc -l)
        fi
        
        echo -e "${CYAN}Backup Statistics:${NC}"
        echo "  Total Backups: $backup_count"
        echo "  Backup Location: $DATA_DIR/backups"
        
        # Recent backups
        if [ $backup_count -gt 0 ]; then
            echo
            echo -e "${CYAN}Recent Backups:${NC}"
            find "$DATA_DIR/backups" -name "*.tar.gz" -type f -printf "%Tb %Td %TY %TH:%TM %p\n" | sort -r | head -3 | while read backup; do
                local size=$(du -h "$(echo "$backup" | awk '{print $NF}')" 2>/dev/null | cut -f1)
                echo "  • $(echo "$backup" | awk '{print $1" "$2" "$3" "$4}') ($size)"
            done
        fi
        
        echo
        echo -e "${GREEN}📋 Backup Options:${NC}"
        echo "   1) 💾 Create Backup"
        echo "   2) 🔄 Restore Backup"
        echo "   3) 🗑️  Delete Backup"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-3): ")" choice
        
        case $choice in
            1) create_backup ;;
            2) restore_backup ;;
            3) delete_backup ;;
            0) return ;;
            *) print_status "ERROR" "Invalid option" ;;
        esac
        
        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
    done
}

create_backup() {
    print_header
    echo -e "${GREEN}💾 Create Backup${NC}"
    echo "─────────────────────────────────────"
    
    # Backup options
    echo "Select backup scope:"
    echo "  1) Full Backup (All VMs, configs, ISOs)"
    echo "  2) VM Backup (Specific virtual machine)"
    echo "  3) Configuration Only"
    echo
    
    read -rp "$(print_status "INPUT" "Select scope (1-3): ")" scope_choice
    
    local backup_name="zynexforge-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_file="$DATA_DIR/backups/${backup_name}.tar.gz"
    mkdir -p "$DATA_DIR/backups"
    
    case $scope_choice in
        1)
            # Full backup
            print_status "PROGRESS" "Creating full backup..."
            tar -czf "$backup_file" \
                -C "$USER_HOME" \
                .zynexforge \
                --exclude="*.log" \
                --exclude="*.tmp"
            ;;
        2)
            # VM backup
            local vms=($(get_vm_list))
            if [ ${#vms[@]} -eq 0 ]; then
                print_status "ERROR" "No VMs found to backup"
                return 1
            fi
            
            echo "Available VMs:"
            for i in "${!vms[@]}"; do
                printf "%2d) %s\n" $((i+1)) "${vms[$i]}"
            done
            
            read -rp "$(print_status "INPUT" "Select VM to backup (1-${#vms[@]}): ")" vm_choice
            
            if [[ "$vm_choice" =~ ^[0-9]+$ ]] && [ "$vm_choice" -ge 1 ] && [ "$vm_choice" -le ${#vms[@]} ]; then
                local vm_name="${vms[$((vm_choice-1))]}"
                print_status "PROGRESS" "Backing up VM: $vm_name"
                tar -czf "$backup_file" \
                    -C "$DATA_DIR" \
                    "vms/$vm_name.conf" \
                    "disks/$vm_name.qcow2" \
                    "cloudinit/$vm_name-seed.img" \
                    "snapshots/$vm_name" 2>/dev/null
            else
                print_status "ERROR" "Invalid selection"
                return 1
            fi
            ;;
        3)
            # Configuration only
            print_status "PROGRESS" "Backing up configurations..."
            tar -czf "$backup_file" \
                -C "$CONFIG_DIR" \
                .
            ;;
        *)
            print_status "ERROR" "Invalid scope"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "$backup_file" | cut -f1)
        print_status "SUCCESS" "Backup created: $backup_file ($size)"
        log_message "BACKUP" "Created backup: $backup_name"
    else
        print_status "ERROR" "Backup creation failed"
    fi
}

# =============================================================================
# SETTINGS MENU (User Mode)
# =============================================================================

settings_menu() {
    while true; do
        print_header
        echo -e "${GREEN}⚙️ Settings${NC}"
        echo "─────────────────────────────────────"
        
        # Load current settings
        if [ -f "$GLOBAL_CONFIG" ]; then
            echo -e "${CYAN}Current Settings:${NC}"
            echo "  Platform: $(grep "name:" "$GLOBAL_CONFIG" | head -1 | cut -d'"' -f2)"
            echo "  User Mode: $(grep "user_mode:" "$GLOBAL_CONFIG" | head -1 | awk '{print $2}')"
            echo "  Max VMs: $(grep "max_vms_per_node:" "$GLOBAL_CONFIG" | head -1 | awk '{print $2}')"
            echo "  SSH Base Port: $(grep "ssh_base_port:" "$GLOBAL_CONFIG" | head -1 | awk '{print $2}')"
            echo
        fi
        
        echo -e "${GREEN}📋 Settings Options:${NC}"
        echo "   1) 🔧 General Settings"
        echo "   2) 📊 View System Info"
        echo "   3) 🧹 Cleanup Old Files"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-3): ")" choice
        
        case $choice in
            1) general_settings ;;
            2) system_information ;;
            3) cleanup_old_files ;;
            0) return ;;
            *) print_status "ERROR" "Invalid option" ;;
        esac
        
        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
    done
}

general_settings() {
    print_header
    echo -e "${GREEN}🔧 General Settings${NC}"
    echo "─────────────────────────────────────"
    
    # Load current config
    local current_name=$(grep "name:" "$GLOBAL_CONFIG" | head -1 | cut -d'"' -f2)
    local max_vms=$(grep "max_vms_per_node:" "$GLOBAL_CONFIG" | head -1 | awk '{print $2}')
    local ssh_base_port=$(grep "ssh_base_port:" "$GLOBAL_CONFIG" | head -1 | awk '{print $2}')
    
    echo "Current Configuration:"
    echo "  1) Platform Name: $current_name"
    echo "  2) Max VMs: $max_vms"
    echo "  3) SSH Base Port: $ssh_base_port"
    echo
    
    read -rp "$(print_status "INPUT" "Select setting to modify (1-3) or 0 to cancel: ")" setting_choice
    
    case $setting_choice in
        1)
            read -rp "$(print_status "INPUT" "New platform name: ")" new_name
            sed -i "s/name:.*/name: \"$new_name\"/" "$GLOBAL_CONFIG"
            print_status "SUCCESS" "Platform name updated"
            ;;
        2)
            read -rp "$(print_status "INPUT" "New max VMs (1-20): ")" new_max
            if [[ "$new_max" =~ ^[0-9]+$ ]] && [ "$new_max" -ge 1 ] && [ "$new_max" -le 20 ]; then
                sed -i "s/max_vms_per_node:.*/max_vms_per_node: $new_max/" "$GLOBAL_CONFIG"
                print_status "SUCCESS" "Max VMs updated"
            else
                print_status "ERROR" "Invalid number (must be 1-20 for user mode)"
            fi
            ;;
        3)
            read -rp "$(print_status "INPUT" "New SSH base port (1024-65535): ")" new_port
            if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1024 ] && [ "$new_port" -le 65535 ]; then
                sed -i "s/ssh_base_port:.*/ssh_base_port: $new_port/" "$GLOBAL_CONFIG"
                print_status "SUCCESS" "SSH base port updated"
            else
                print_status "ERROR" "Invalid port number"
            fi
            ;;
        0)
            return
            ;;
        *)
            print_status "ERROR" "Invalid choice"
            ;;
    esac
    
    log_message "SETTINGS" "Modified general settings"
}

system_information() {
    print_header
    echo -e "${GREEN}📊 System Information${NC}"
    echo "─────────────────────────────────────"
    
    echo -e "${CYAN}Operating System:${NC}"
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        echo "  Distribution: $NAME"
        echo "  Version: $VERSION"
        echo "  ID: $ID"
    fi
    echo "  Kernel: $(uname -r)"
    echo "  Architecture: $(uname -m)"
    
    echo
    echo -e "${CYAN}CPU Information:${NC}"
    echo "  Model: $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
    echo "  Cores: $(nproc)"
    
    echo
    echo -e "${CYAN}Memory Information:${NC}"
    local mem_total=$(free -h | awk '/^Mem:/{print $2}')
    local mem_used=$(free -h | awk '/^Mem:/{print $3}')
    local mem_available=$(free -h | awk '/^Mem:/{print $7}')
    echo "  Total: $mem_total"
    echo "  Used: $mem_used"
    echo "  Available: $mem_available"
    
    echo
    echo -e "${CYAN}Disk Information:${NC}"
    df -h / | awk 'NR==2{print "  Mount: "$6" | Size: "$2" | Used: "$3" ("$5") | Free: "$4}'
    
    echo
    echo -e "${CYAN}ZynexForge Information:${NC}"
    echo "  Version: $SCRIPT_VERSION"
    echo "  Config Directory: $CONFIG_DIR"
    echo "  Data Directory: $DATA_DIR"
    echo "  User: $USER"
    
    local vm_count=$(get_vm_list | wc -l)
    echo "  Total VMs: $vm_count"
}

cleanup_old_files() {
    print_header
    echo -e "${GREEN}🧹 Cleanup Old Files${NC}"
    echo "─────────────────────────────────────"
    
    # Find old backup files (older than 30 days)
    local old_backups=$(find "$DATA_DIR/backups" -name "*.tar.gz" -type f -mtime +30 2>/dev/null | wc -l)
    
    # Find old log files (older than 7 days)
    local old_logs=$(find "$USER_HOME/zynexforge/logs" -name "*.log" -type f -mtime +7 2>/dev/null | wc -l)
    
    # Find temporary files
    local temp_files=$(find /tmp -name "*zynexforge*" -type f -mtime +1 2>/dev/null | wc -l)
    
    echo "Files that can be cleaned up:"
    echo "  Old backups (>30 days): $old_backups"
    echo "  Old log files (>7 days): $old_logs"
    echo "  Temporary files (>1 day): $temp_files"
    echo
    
    if [ $((old_backups + old_logs + temp_files)) -eq 0 ]; then
        print_status "INFO" "No old files found to clean up"
        return
    fi
    
    read -rp "$(print_status "INPUT" "Clean up these files? (y/N): ")" confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Clean up old backups
        if [ $old_backups -gt 0 ]; then
            find "$DATA_DIR/backups" -name "*.tar.gz" -type f -mtime +30 -delete
            print_status "SUCCESS" "Cleaned up $old_backups old backup(s)"
        fi
        
        # Clean up old logs
        if [ $old_logs -gt 0 ]; then
            find "$USER_HOME/zynexforge/logs" -name "*.log" -type f -mtime +7 -delete
            print_status "SUCCESS" "Cleaned up $old_logs old log file(s)"
        fi
        
        # Clean up temporary files
        if [ $temp_files -gt 0 ]; then
            find /tmp -name "*zynexforge*" -type f -mtime +1 -delete 2>/dev/null || true
            print_status "SUCCESS" "Cleaned up temporary files"
        fi
        
        print_status "SUCCESS" "Cleanup completed"
    else
        print_status "INFO" "Cleanup cancelled"
    fi
}

# =============================================================================
# SYSTEM DIAGNOSTICS (User Mode)
# =============================================================================

system_diagnostics_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🔧 System Diagnostics${NC}"
        echo "─────────────────────────────────────"
        
        # System health check
        echo -e "${CYAN}System Health Check:${NC}"
        
        # Check KVM permissions
        if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            echo -e "  🟢 KVM acceleration: Available"
        else
            echo -e "  🔴 KVM acceleration: Not available (/dev/kvm permissions issue)"
        fi
        
        # Check Docker
        if command -v docker > /dev/null 2>&1; then
            if docker info > /dev/null 2>&1; then
                echo -e "  🟢 Docker: Running"
            else
                echo -e "  🔴 Docker: Installed but not accessible"
                echo -e "     Try: sudo usermod -aG docker $USER"
                echo -e "     Then log out and log back in"
            fi
        else
            echo -e "  🔴 Docker: Not installed"
        fi
        
        # Check resources
        local cpu_cores=$(nproc)
        local total_ram=$(free -m | awk '/^Mem:/{print $2}')
        local available_ram=$(free -m | awk '/^Mem:/{print $7}')
        local disk_space=$(df -h "$DATA_DIR" | awk 'NR==2{print $4}')
        
        echo -e "  ℹ CPU Cores: $cpu_cores"
        echo -e "  ℹ Total RAM: ${total_ram}MB"
        echo -e "  ℹ Available RAM: ${available_ram}MB"
        echo -e "  ℹ Disk Space: $disk_space"
        
        echo
        echo -e "${GREEN}📋 Diagnostic Tools:${NC}"
        echo "   1) 🛠️  System Information"
        echo "   2) 🔍 Check Port Availability"
        echo "   3) 🐛 View Logs"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-3): ")" choice
        
        case $choice in
            1) system_information ;;
            2) check_port_availability ;;
            3) view_logs ;;
            0) return ;;
            *) print_status "ERROR" "Invalid option" ;;
        esac
        
        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
    done
}

check_port_availability() {
    print_header
    echo -e "${GREEN}🔍 Check Port Availability${NC}"
    echo "─────────────────────────────────────"
    
    echo "Checking common ports used by ZynexForge..."
    echo
    
    # Check SSH base port
    local ssh_base_port=$(grep "ssh_base_port:" "$GLOBAL_CONFIG" 2>/dev/null | head -1 | awk '{print $2}')
    ssh_base_port=${ssh_base_port:-22000}
    
    # Check a range of ports
    for port in {22000..22010}; do
        if check_port_available "$port"; then
            echo -e "  🟢 Port $port: Available"
        else
            echo -e "  🔴 Port $port: In use"
        fi
    done
    
    echo
    echo -e "${YELLOW}Note:${NC} Ports 22000-22010 are used for VM SSH access"
    echo "If ports are in use, VMs may fail to start"
}

view_logs() {
    print_header
    echo -e "${GREEN}🐛 View Logs${NC}"
    echo "─────────────────────────────────────"
    
    if [ ! -f "$LOG_FILE" ]; then
        print_status "INFO" "No log file found"
        return
    fi
    
    echo "Log file: $LOG_FILE"
    echo "─────────────────────────────────────"
    tail -50 "$LOG_FILE"
    echo "─────────────────────────────────────"
    
    echo
    echo -e "${YELLOW}Options:${NC}"
    echo "  1) View full log"
    echo "  2) Clear log"
    echo "  3) Search in log"
    echo "  0) Back"
    echo
    
    read -rp "$(print_status "INPUT" "Select option (0-3): ")" choice
    
    case $choice in
        1)
            clear
            cat "$LOG_FILE"
            echo
            read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
            ;;
        2)
            read -rp "$(print_status "INPUT" "Clear log file? (y/N): ")" confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                > "$LOG_FILE"
                print_status "SUCCESS" "Log file cleared"
            fi
            ;;
        3)
            read -rp "$(print_status "INPUT" "Search term: ")" search_term
            if [ -n "$search_term" ]; then
                clear
                grep -i "$search_term" "$LOG_FILE"
                echo
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
            fi
            ;;
    esac
}

# =============================================================================
# DOCUMENTATION (User Mode)
# =============================================================================

show_documentation() {
    while true; do
        print_header
        echo -e "${GREEN}📚 Documentation & Help${NC}"
        echo "─────────────────────────────────────"
        
        echo -e "${CYAN}ZynexForge CloudStack™ Professional Edition${NC}"
        echo "Version: $SCRIPT_VERSION (User Mode)"
        echo
        echo -e "${YELLOW}Quick Start Guide:${NC}"
        echo "  1. Create your first VM from the main menu"
        echo "  2. Manage VMs from the dashboard"
        echo "  3. Use Docker containers for lightweight apps"
        echo "  4. Use Jupyter notebooks for data science"
        echo
        
        echo -e "${YELLOW}Important Notes for User Mode:${NC}"
        echo "  • Runs without root privileges"
        echo "  • Limited to user's home directory"
        echo "  • Max 50GB disk space per VM"
        echo "  • Network uses user-mode SLIRP"
        echo "  • Docker requires user to be in 'docker' group"
        echo
        
        echo -e "${YELLOW}Troubleshooting:${NC}"
        echo "  • KVM not working? Check /dev/kvm permissions"
        echo "  • Docker permission denied? Add user to docker group"
        echo "  • Port already in use? Change SSH base port in settings"
        echo "  • Out of disk space? Clean up old files"
        echo
        
        echo -e "${GREEN}📖 Help Sections:${NC}"
        echo "   1) 📘 User Manual"
        echo "   2) 🔧 Troubleshooting Guide"
        echo "   3) 📖 Tutorials"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-3): ")" choice
        
        case $choice in
            1) show_user_manual ;;
            2) show_troubleshooting_guide ;;
            3) show_tutorials ;;
            0) return ;;
            *) print_status "ERROR" "Invalid option" ;;
        esac
        
        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
    done
}

show_user_manual() {
    print_header
    echo -e "${GREEN}📘 User Manual${NC}"
    echo "─────────────────────────────────────"
    
    cat << 'EOF'
ZynexForge CloudStack™ User Manual (User Mode)
==============================================

1. Getting Started
------------------
ZynexForge is an advanced virtualization platform that runs entirely in
user mode - no root privileges required!

2. Creating Virtual Machines
---------------------------
There are several ways to create VMs:

  a) Cloud Images: Pre-configured OS images (fast deployment)
  b) ISO Images: Full OS installation
  c) Docker Containers: Lightweight application containers
  d) Jupyter Servers: Data science notebooks

3. User Mode Limitations
------------------------
- Max disk size: 50GB per VM
- Network: User-mode SLIRP (slower than bridge)
- No bridge networking
- Limited to user's home directory space

4. Recommended Setup
--------------------
For best performance in user mode:
1. Ensure KVM permissions: sudo chmod 666 /dev/kvm
2. Add user to docker group: sudo usermod -aG docker $USER
3. Log out and log back in after changes

5. Common Commands
------------------
- Create VM: Main Menu → Option 1
- Manage VMs: Main Menu → Option 2
- Docker: Main Menu → Option 3
- Jupyter: Main Menu → Option 4
- Settings: Main Menu → Option 7

6. Getting Help
---------------
- View logs: Diagnostics → View Logs
- Check system info: Settings → View System Info
- Clean up space: Settings → Cleanup Old Files
EOF
}

show_troubleshooting_guide() {
    print_header
    echo -e "${GREEN}🔧 Troubleshooting Guide${NC}"
    echo "─────────────────────────────────────"
    
    cat << 'EOF'
Common Issues and Solutions
===========================

1. KVM Acceleration Not Available
---------------------------------
Symptoms: VM starts slowly, high CPU usage
Solution: Check /dev/kvm permissions
  Run: ls -l /dev/kvm
  If permissions are wrong:
    sudo chmod 666 /dev/kvm
  Or add user to kvm group:
    sudo usermod -aG kvm $USER
    (Then log out and log back in)

2. Docker Permission Denied
---------------------------
Symptoms: "Cannot connect to Docker daemon"
Solution: Add user to docker group
  sudo usermod -aG docker $USER
  Then log out and log back in
  Verify with: docker ps

3. Port Already in Use
----------------------
Symptoms: VM fails to start, port conflict
Solution: Change SSH base port
  Settings → General Settings → SSH Base Port
  Choose a port above 1024

4. Out of Disk Space
--------------------
Symptoms: Cannot create VM, disk full
Solution: Clean up space
  Settings → Cleanup Old Files
  Or manually remove old backups/ISOs

5. VM Won't Start
-----------------
Symptoms: QEMU error, immediate exit
Solution: Check system resources
  - Enough RAM available?
  - Enough disk space?
  - CPU supports virtualization?
  Check logs: Diagnostics → View Logs

6. Network Not Working in VM
----------------------------
Symptoms: No internet in VM
Solution: User-mode networking limitations
  - Restart VM
  - Check host firewall isn't blocking
  - Try different port forwarding

7. Slow Performance
-------------------
Symptoms: VM runs slowly
Solution:
  - Enable KVM acceleration if available
  - Reduce VM memory/CPU allocation
  - Close other applications on host
  - Use lighter OS (Alpine instead of Ubuntu)

Diagnostic Commands
-------------------
- Check KVM: kvm-ok
- Check Docker: docker info
- Check ports: ss -tln | grep ':<port>'
- Check disk: df -h $HOME
- Check RAM: free -h
EOF
}

show_tutorials() {
    print_header
    echo -e "${GREEN}📖 Tutorials${NC}"
    echo "─────────────────────────────────────"
    
    cat << 'EOF'
Tutorial 1: Create Your First VM
================================
1. From Main Menu, select option 1
2. Choose "QEMU/KVM Virtual Machine"
3. Select "Ubuntu 24.04 LTS" (cloud image)
4. Name your VM (e.g., "my-first-vm")
5. Set resources: 2 CPU, 2048MB RAM, 20G disk
6. Note the SSH port (e.g., 22000)
7. Start the VM immediately (y)
8. Connect via SSH: ssh -p 22000 <username>@localhost
   Password: ZynexForge123

Tutorial 2: Create a Docker Web Server
======================================
1. From Main Menu, select option 3
2. Choose "Create New Docker Container"
3. Select "Nginx Web Server"
4. Name: "my-web-server"
5. Port mapping: "8080:80"
6. Container will start automatically
7. Open browser: http://localhost:8080
8. To manage: docker logs my-web-server

Tutorial 3: Create Jupyter Notebook
===================================
1. From Main Menu, select option 4
2. Choose "Create New Jupyter Notebook"
3. Select "Data Science" template
4. Name: "my-notebook"
5. Note the URL and token
6. Open browser to the URL
7. Use token to login
8. Start coding in Python/R/Julia

Tutorial 4: Backup and Restore
==============================
1. From Main Menu, select option 6
2. Choose "Create Backup"
3. Select "VM Backup"
4. Choose VM to backup
5. Backup is saved in ~/.zynexforge/backups/
6. To restore: choose "Restore Backup"
7. Select backup file
8. Confirm restoration

Tutorial 5: ISO Installation
============================
1. From Main Menu, select option 5
2. Choose "Download ISO"
3. Select "Ubuntu 24.04 Desktop"
4. Wait for download to complete
5. Create new VM, choose ISO installation
6. Follow on-screen installer
7. GUI mode recommended for ISO install

Tips and Tricks
===============
- Use cloud images for fastest deployment
- Docker containers start in seconds
- Jupyter notebooks auto-save your work
- Regular backups prevent data loss
- Clean up old files to save space
- Check system diagnostics regularly
EOF
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Check if running as root (should NOT be root for user mode)
if [ "$EUID" -eq 0 ]; then
    print_status "ERROR" "This script should NOT be run as root for user mode"
    print_status "INFO" "Please run as regular user: bash <(curl -fsSL ...)"
    exit 1
fi

# Initialize platform
initialize_platform

# Start main menu
main_menu

# Cleanup on exit
cleanup() {
    print_status "INFO" "Shutting down ZynexForge..."
    # Stop all running VMs
    for vm_conf in "$DATA_DIR/vms"/*.conf; do
        if [ -f "$vm_conf" ]; then
            source "$vm_conf" 2>/dev/null
            local pid_file="/tmp/qemu-$VM_NAME.pid"
            if [ -f "$pid_file" ]; then
                kill -TERM "$(cat "$pid_file")" 2>/dev/null
                rm -f "$pid_file"
            fi
        fi
    done
    print_status "INFO" "Goodbye!"
    log_message "SYSTEM" "ZynexForge shutdown completed"
}

trap cleanup EXIT
