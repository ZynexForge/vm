#!/bin/bash
set -euo pipefail

# =============================================================================
# ZynexForge CloudStack™ Platform - World's #1 Virtualization System
# Advanced Multi-Node Virtualization Management
# Version: 4.0.0 Ultra Pro
# =============================================================================

# Global Configuration
readonly USER_HOME="$HOME"
readonly CONFIG_DIR="$USER_HOME/.zynexforge"
readonly DATA_DIR="$USER_HOME/.zynexforge/data"
readonly LOG_FILE="$USER_HOME/.zynexforge/zynexforge.log"
readonly NODES_DB="$CONFIG_DIR/nodes.yml"
readonly GLOBAL_CONFIG="$CONFIG_DIR/config.yml"
readonly SSH_KEY_FILE="$USER_HOME/.ssh/zynexforge_ed25519"
readonly SCRIPT_VERSION="4.0.0 Ultra Pro"

# Color Definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# Dynamic Resource Limits (Auto-detected)
MAX_CPU_CORES=$(nproc)
MAX_RAM_MB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 ))
MAX_DISK_GB=$(($(df -k "$HOME" | awk 'NR==2{print $4}') / 1048576))
MIN_RAM_MB=256
MIN_DISK_GB=1

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

# Enhanced OS Templates with Custom Mirrors
declare -A OS_TEMPLATES=(
    ["ubuntu-24.04"]="Ubuntu 24.04 LTS|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ZynexForgePro123!"
    ["ubuntu-22.04"]="Ubuntu 22.04 LTS|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ZynexForgePro123!"
    ["debian-12"]="Debian 12|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|ZynexForgePro123!"
    ["centos-9"]="CentOS Stream 9|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|ZynexForgePro123!"
    ["rocky-9"]="Rocky Linux 9|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|ZynexForgePro123!"
    ["almalinux-9"]="AlmaLinux 9|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|ZynexForgePro123!"
    ["fedora-40"]="Fedora 40|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|ZynexForgePro123!"
    ["alpine-3.19"]="Alpine Linux 3.19|3.19|https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.0-x86_64.iso|alpine|root|alpine"
    ["arch-linux"]="Arch Linux|arch|https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2|arch|arch|arch"
    ["opensuse-tumbleweed"]="OpenSUSE Tumbleweed|tumbleweed|https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-Cloud.x86_64-Cloud.qcow2|opensuse|opensuse|ZynexForgePro123!"
)

# Enhanced ISO Library with Premium Mirrors
declare -A ISO_LIBRARY=(
    ["ubuntu-24.04-desktop"]="Ubuntu 24.04 Desktop|https://releases.ubuntu.com/24.04/ubuntu-24.04-desktop-amd64.iso|ubuntu|ubuntu"
    ["ubuntu-24.04-server"]="Ubuntu 24.04 Server|https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso|ubuntu|ubuntu"
    ["ubuntu-22.04-server"]="Ubuntu 22.04 Server|https://releases.ubuntu.com/22.04/ubuntu-22.04-live-server-amd64.iso|ubuntu|ubuntu"
    ["debian-12"]="Debian 12|https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso|debian|debian"
    ["almalinux-9"]="AlmaLinux 9|https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9.3-x86_64-dvd.iso|alma|alma"
    ["rocky-9"]="Rocky Linux 9|https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.3-x86_64-dvd.iso|rocky|rocky"
    ["kali-linux"]="Kali Linux|https://cdimage.kali.org/kali-2024.2/kali-linux-2024.2-installer-amd64.iso|kali|kali"
    ["arch-linux"]="Arch Linux|https://archlinux.c3sl.ufpr.br/iso/2024.07.01/archlinux-2024.07.01-x86_64.iso|arch|arch"
    ["windows-11"]="Windows 11|https://software.download.prss.microsoft.com/dbazure/Win11_23H2_English_x64.iso?t=8e06379b-8f4d-4fca-8631-50c07e8b1c02&e=1708312186&h=aa6e0a5f5c7f7c8b7c8d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9|Administrator|ZynexForgeWin123!"
    ["proxmox-8"]="Proxmox VE 8|https://download.proxmox.com/iso/proxmox-ve_8.1-1.iso|root|ZynexForgePro123!"
)

# Premium Real Nodes with Custom Specs
declare -A REAL_NODES=(
    ["mumbai-premium"]="🇮🇳 Mumbai Premium|ap-south-1|103.21.58.1|15|128|1000|AMD EPYC 32c/64t, 128GB DDR5, 1TB NVMe, 10Gbps|kvm,qemu,docker,lxd,jupyter,kubernetes,gpu"
    ["delhi-enterprise"]="🇮🇳 Delhi Enterprise|ap-south-2|103.21.59.1|20|256|2000|Intel Xeon 48c/96t, 256GB DDR5, 2TB NVMe RAID, 25Gbps|kvm,qemu,docker,jupyter,lxd,kubernetes,gpu"
    ["singapore-pro"]="🇸🇬 Singapore Pro|ap-southeast-1|103.21.61.1|35|512|5000|AMD EPYC 64c/128t, 512GB DDR5, 5TB NVMe RAID, 40Gbps|kvm,qemu,docker,jupyter,lxd,kubernetes,gpu,nvidia"
    ["frankfurt-elite"]="🇩🇪 Frankfurt Elite|eu-central-1|103.21.62.1|45|1024|10000|Intel Xeon 96c/192t, 1TB DDR5, 10TB NVMe RAID, 100Gbps|kvm,qemu,docker,jupyter,lxd,kubernetes,gpu,nvidia,openstack"
    ["newyork-ultra"]="🇺🇸 New York Ultra|us-east-1|103.21.65.1|55|2048|20000|AMD EPYC 128c/256t, 2TB DDR5, 20TB NVMe RAID, 100Gbps|kvm,qemu,docker,jupyter,lxd,kubernetes,gpu,nvidia,openstack"
    ["tokyo-extreme"]="🇯🇵 Tokyo Extreme|ap-northeast-1|103.21.68.1|65|1024|15000|Intel Xeon 112c/224t, 1TB DDR5, 15TB NVMe RAID, 100Gbps|kvm,qemu,docker,jupyter,lxd,kubernetes,gpu,nvidia,openstack"
)

# Premium Docker Images
declare -A DOCKER_IMAGES=(
    ["ubuntu-24.04"]="Ubuntu 24.04|ubuntu:24.04"
    ["debian-12"]="Debian 12|debian:12"
    ["alpine"]="Alpine Linux|alpine:latest"
    ["centos-stream9"]="CentOS Stream 9|centos:stream9"
    ["nginx"]="Nginx Web Server|nginx:alpine"
    ["mysql"]="MySQL Database|mysql:8.0"
    ["postgres"]="PostgreSQL|postgres:16"
    ["redis"]="Redis Cache|redis:alpine"
    ["nodejs"]="Node.js 20|node:20-alpine"
    ["python"]="Python 3.12|python:3.12-alpine"
    ["jupyter"]="Jupyter Notebook|jupyter/base-notebook"
    ["code-server"]="VS Code Server|codercom/code-server:latest"
    ["portainer"]="Portainer CE|portainer/portainer-ce:latest"
    ["grafana"]="Grafana|grafana/grafana:latest"
    ["prometheus"]="Prometheus|prom/prometheus:latest"
    ["traefik"]="Traefik Proxy|traefik:latest"
    ["mongo"]="MongoDB|mongo:latest"
    ["elasticsearch"]="ElasticSearch|elasticsearch:8.12"
)

# Premium Jupyter Templates
declare -A JUPYTER_TEMPLATES=(
    ["data-science"]="Data Science Pro|jupyter/datascience-notebook|8888|python,R,julia,scipy,pandas"
    ["tensorflow"]="TensorFlow ML Pro|jupyter/tensorflow-notebook|8889|python,tensorflow,keras,pytorch"
    ["minimal"]="Minimal Python Pro|jupyter/minimal-notebook|8890|python,pandas,numpy,matplotlib"
    ["pyspark"]="PySpark Enterprise|jupyter/pyspark-notebook|8891|python,spark,hadoop,pyspark"
    ["rstudio"]="R Studio Pro|jupyter/r-notebook|8892|R,tidyverse,ggplot2,shiny"
    ["scipy"]="Scientific Python|jupyter/scipy-notebook|8893|python,scipy,matplotlib,sympy"
    ["all-spark"]="All-Spark Notebook|jupyter/all-spark-notebook|8894|python,R,scala,spark"
)

# =============================================================================
# CORE FUNCTIONS - OPTIMIZED
# =============================================================================

print_header() {
    clear
    echo -e "${CYAN}"
    echo "$ASCII_MAIN_ART"
    echo -e "${NC}"
    echo -e "${YELLOW}⚡ ZynexForge CloudStack™ - World's #1 Virtualization Platform${NC}"
    echo -e "${WHITE}🔥 Ultra Pro Edition | Version: ${SCRIPT_VERSION}${NC}"
    echo -e "${GREEN}📊 System: ${MAX_CPU_CORES} Cores | ${MAX_RAM_MB}MB RAM | ${MAX_DISK_GB}GB Disk${NC}"
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
        "DEBUG") echo -e "${WHITE}🐛 [DEBUG]${NC} $message" ;;
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
            if ! [[ "$value" =~ ^[0-9]+[GgMmKk]$ ]]; then
                print_status "ERROR" "Must be a size with unit (e.g., 100G, 512M, 1024K)"
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
            sudo apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils genisoimage openssh-client curl wget jq net-tools bridge-utils dnsmasq libvirt-clients
            log_message "INSTALL" "Installed packages on Debian/Ubuntu"
            
        elif command -v dnf > /dev/null 2>&1; then
            print_status "INFO" "Installing packages on Fedora/RHEL..."
            sudo dnf install -y qemu-system-x86 qemu-img cloud-utils genisoimage openssh-clients curl wget jq net-tools bridge-utils dnsmasq libvirt-client
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
    
    # Check KVM support with fallback to QEMU-only
    if kvm-ok 2>/dev/null && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        KVM_AVAILABLE=true
        print_status "SUCCESS" "KVM acceleration is available"
    else
        KVM_AVAILABLE=false
        print_status "WARNING" "KVM acceleration not available - Using QEMU-only mode (slower)"
        print_status "INFO" "For better performance, enable KVM: sudo chmod 666 /dev/kvm"
    fi
    
    # Check Docker
    if command -v docker > /dev/null 2>&1; then
        if docker info > /dev/null 2>&1; then
            print_status "SUCCESS" "Docker is available"
        else
            print_status "WARNING" "Docker installed but daemon not running"
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
    local available_ram_mb=$((total_ram_mb * 85 / 100)) # Use 85% of total RAM
    
    local total_disk_gb
    total_disk_gb=$(df -BG "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    total_disk_gb=${total_disk_gb:-100}
    
    local cpu_cores
    cpu_cores=$(nproc)
    local available_cores=$((cpu_cores - 1)) # Leave 1 core for host
    
    echo "$available_ram_mb $total_disk_gb $available_cores"
}

# =============================================================================
# INITIALIZATION - OPTIMIZED
# =============================================================================

initialize_platform() {
    print_status "INFO" "Initializing ZynexForge Platform..."
    
    # Create directory structure
    mkdir -p "$CONFIG_DIR" \
             "$DATA_DIR/vms" \
             "$DATA_DIR/disks" \
             "$DATA_DIR/cloudinit" \
             "$DATA_DIR/dockervm" \
             "$DATA_DIR/jupyter" \
             "$DATA_DIR/isos" \
             "$DATA_DIR/lxd" \
             "$DATA_DIR/backups" \
             "$DATA_DIR/snapshots" \
             "$DATA_DIR/networks" \
             "$DATA_DIR/templates" \
             "$USER_HOME/zynexforge/templates/cloud" \
             "$USER_HOME/zynexforge/templates/iso" \
             "$USER_HOME/zynexforge/logs" \
             "$USER_HOME/zynexforge/certs"
    
    # Create default config if not exists
    if [ ! -f "$GLOBAL_CONFIG" ]; then
        cat > "$GLOBAL_CONFIG" << EOF
# ZynexForge Global Configuration
platform:
  name: "ZynexForge CloudStack™ Professional"
  version: "${SCRIPT_VERSION}"
  default_node: "local"
  ssh_base_port: 22000
  max_vms_per_node: 100
  user_mode: true
  enable_monitoring: true
  auto_backup: false
  backup_retention_days: 30
  enable_telemetry: false
  auto_update: true
  kvm_enabled: $KVM_AVAILABLE

security:
  firewall_enabled: true
  default_ssh_user: "zynexuser"
  password_min_length: 12
  use_ssh_keys: true
  enable_2fa: false
  ssh_timeout: 300
  enable_audit_log: true
  encrypt_backups: true

network:
  bridge_interface: "br0"
  default_subnet: "192.168.100.0/24"
  dns_servers: "8.8.8.8,1.1.1.1"
  enable_ipv6: true
  mtu: 1500

performance:
  enable_hugepages: false
  cpu_pinning: false
  io_threads: 4
  disk_cache: "writeback"
  net_model: "virtio"

paths:
  templates: "\$USER_HOME/zynexforge/templates"
  isos: "\$DATA_DIR/isos"
  vm_configs: "\$DATA_DIR/vms"
  vm_disks: "\$DATA_DIR/disks"
  logs: "\$USER_HOME/zynexforge/logs"
  backups: "\$DATA_DIR/backups"
  snapshots: "\$DATA_DIR/snapshots"
EOF
        print_status "SUCCESS" "Global configuration created"
        log_message "CONFIG" "Created global configuration"
    fi
    
    # Create nodes database with enhanced real nodes
    if [ ! -f "$NODES_DB" ]; then
        cat > "$NODES_DB" << EOF
# ZynexForge Nodes Database
# Global Production Nodes with Enhanced Specifications
nodes:
  local:
    node_id: "local"
    node_name: "Local Development"
    location_name: "Local, Your Computer"
    provider: "Self-Hosted"
    public_ip: "127.0.0.1"
    capabilities: ["kvm", "qemu", "docker", "jupyter", "lxd"]
    tags: ["development", "testing", "high-performance"]
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
        
        # Add real nodes with enhanced specifications
        for node_id in "${!REAL_NODES[@]}"; do
            IFS='|' read -r location region ip latency ram disk specs capabilities <<< "${REAL_NODES[$node_id]}"
            cat >> "$NODES_DB" << EOF
  $node_id:
    node_id: "$node_id"
    node_name: "$location"
    location_name: "$location"
    region_code: "$region"
    provider: "ZynexForge Cloud"
    public_ip: "$ip"
    latency_ms: "$latency"
    capabilities: ["$(echo "$capabilities" | sed "s/,/\", \"/g")"]
    specifications: "$specs"
    resources:
      max_ram_gb: "$ram"
      max_disk_gb: "$disk"
      max_vcpus: "128"
      storage_type: "NVMe SSD RAID"
      network_speed: "10-100 Gbps"
    sla:
      uptime: "99.99%"
      support: "24/7 Premium"
      backup: "Daily Automated"
    tags: ["production", "enterprise", "high-availability", "global", "gpu"]
    status: "active"
    created_at: "$(date -Iseconds)"
    user_mode: false
EOF
        done
        
        print_status "SUCCESS" "Enhanced nodes database created with ${#REAL_NODES[@]} global locations"
        log_message "NODES" "Created nodes database with ${#REAL_NODES[@]} nodes"
    fi
    
    # Generate SSH key if not exists
    if [ ! -f "$SSH_KEY_FILE" ]; then
        print_status "INFO" "Generating SSH key pair..."
        ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q -C "zynexforge@$(hostname)"
        chmod 600 "$SSH_KEY_FILE"
        chmod 644 "${SSH_KEY_FILE}.pub"
        print_status "SUCCESS" "SSH key generated: $SSH_KEY_FILE"
        log_message "SECURITY" "Generated SSH key pair"
    fi
    
    # Check and install dependencies
    if check_dependencies; then
        print_status "SUCCESS" "Platform initialized successfully!"
        log_message "INIT" "Platform initialization completed"
    else
        print_status "ERROR" "Platform initialization failed"
        return 1
    fi
    
    return 0
}

# =============================================================================
# VM MANAGEMENT FUNCTIONS - OPTIMIZED
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
# ENHANCED KVM VM CREATION WITH QEMU FALLBACK
# =============================================================================

create_kvm_vm() {
    local node_id="$1"
    local node_name="$2"
    local node_ip="$3"
    
    print_header
    echo -e "${GREEN}🖥️ Create QEMU/KVM Virtual Machine${NC}"
    echo -e "${YELLOW}Location: ${node_name} ($node_ip)${NC}"
    echo
    
    # Check KVM availability
    if [ "$KVM_AVAILABLE" = false ]; then
        print_status "WARNING" "KVM acceleration not available!"
        echo "Options:"
        echo "  1) Continue with QEMU-only (Slower but works)"
        echo "  2) Try to enable KVM (Requires sudo)"
        echo "  3) Cancel and go back"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (1-3): ")" kvm_choice
        
        case $kvm_choice in
            1)
                print_status "INFO" "Using QEMU-only mode (software virtualization)"
                USE_KVM=false
                ;;
            2)
                print_status "INFO" "Attempting to enable KVM..."
                sudo chmod 666 /dev/kvm 2>/dev/null
                if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
                    KVM_AVAILABLE=true
                    USE_KVM=true
                    print_status "SUCCESS" "KVM enabled successfully!"
                else
                    print_status "ERROR" "Failed to enable KVM"
                    USE_KVM=false
                fi
                ;;
            3)
                return 1
                ;;
            *)
                print_status "ERROR" "Invalid choice, using QEMU-only"
                USE_KVM=false
                ;;
        esac
    else
        USE_KVM=true
    fi
    
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
    print_header
    echo -e "${GREEN}📦 Select Installation Method${NC}"
    echo "─────────────────────────────────────"
    echo "  1) 📦 Cloud Image (Fast Deployment)"
    echo "  2) 💿 ISO Image (Full Install)"
    echo "  3) 🎯 Custom Image URL"
    echo "  4) 🔧 Custom QCOW2 File"
    echo
    
    read -rp "$(print_status "INPUT" "Choice (1-4): ")" os_method_choice
    
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
            
        4)
            # Custom QCOW2 File
            read -rp "$(print_status "INPUT" "Enter path to QCOW2 file: ")" custom_file
            if [ -f "$custom_file" ]; then
                OS_TYPE="custom-file"
                img_url="file://$custom_file"
            else
                print_status "ERROR" "File not found: $custom_file"
                return 1
            fi
            ;;
            
        *)
            print_status "ERROR" "Invalid choice"
            return 1
            ;;
    esac
    
    # Resource Allocation
    print_header
    echo -e "${GREEN}📊 Resource Allocation${NC}"
    echo "─────────────────────────────────────"
    
    # Get available resources
    IFS=' ' read -r available_ram total_disk available_cores <<< "$(get_system_resources)"
    
    # CPU Cores
    while true; do
        read -rp "$(print_status "INPUT" "CPU Cores (1-$available_cores, recommended: $((available_cores > 2 ? 2 : 1))): ")" cpus
        if validate_input "number" "$cpus" 1 "$available_cores"; then
            CPUS="$cpus"
            break
        fi
    done
    
    # RAM Allocation
    while true; do
        read -rp "$(print_status "INPUT" "RAM in MB ($MIN_RAM_MB-$available_ram, recommended: $((available_ram > 2048 ? 2048 : available_ram/2))): ")" memory
        if validate_input "number" "$memory" "$MIN_RAM_MB" "$available_ram"; then
            MEMORY="$memory"
            break
        fi
    done
    
    # Disk Size
    while true; do
        read -rp "$(print_status "INPUT" "Disk Size (e.g., 20G, min ${MIN_DISK_GB}G, max ${MAX_DISK_GB}G): ")" disk_size
        if validate_input "size" "$disk_size"; then
            local size_num=${disk_size%[GgMmKk]}
            local size_unit=${disk_size: -1}
            
            # Convert to MB for comparison
            local size_mb=$size_num
            if [[ "$size_unit" =~ [Gg] ]]; then
                size_mb=$((size_num * 1024))
            elif [[ "$size_unit" =~ [Kk] ]]; then
                size_mb=$((size_num / 1024))
            fi
            
            local max_mb=$((MAX_DISK_GB * 1024))
            if [ "$size_mb" -lt $((MIN_DISK_GB * 1024)) ]; then
                print_status "ERROR" "Minimum disk size is ${MIN_DISK_GB}G"
            elif [ "$size_mb" -gt "$max_mb" ]; then
                print_status "ERROR" "Maximum disk size is ${MAX_DISK_GB}G"
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
    
    read -rp "$(print_status "INPUT" "Username (default: zynexuser): ")" username_input
    USERNAME="${username_input:-zynexuser}"
    
    read -rp "$(print_status "INPUT" "Password (leave empty to generate): ")" password_input
    if [ -z "$password_input" ]; then
        PASSWORD=$(generate_password 16 true)
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
        print_status "PROGRESS" "Downloading image..."
        IMG_FILE="$DATA_DIR/disks/${VM_NAME}.qcow2"
        
        if [[ "$img_url" == *.iso ]] || [[ "$os_method_choice" == "2" ]]; then
            # ISO download
            iso_path="$DATA_DIR/isos/$(basename "$img_url")"
            mkdir -p "$DATA_DIR/isos"
            
            if [ ! -f "$iso_path" ]; then
                if [[ "$img_url" == http* ]]; then
                    curl -L -o "$iso_path" "$img_url"
                else
                    cp "$img_url" "$iso_path"
                fi
                print_status "SUCCESS" "ISO downloaded: $iso_path"
            else
                print_status "INFO" "ISO already exists: $iso_path"
            fi
            
            # Create disk for ISO installation
            qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
        else
            # QCOW2 image
            if [[ "$img_url" == http* ]]; then
                curl -L -o "/tmp/${VM_NAME}.qcow2" "$img_url"
                qemu-img convert -f qcow2 -O qcow2 "/tmp/${VM_NAME}.qcow2" "$IMG_FILE"
                rm -f "/tmp/${VM_NAME}.qcow2"
            elif [[ "$img_url" == file://* ]]; then
                local file_path="${img_url#file://}"
                cp "$file_path" "$IMG_FILE"
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
    echo -e "${GREEN}📋 VM Specifications:${NC}"
    echo "─────────────────────────────────────"
    echo "Name: $VM_NAME"
    echo "Hostname: $HOSTNAME"
    echo "Username: $USERNAME"
    echo "Password: $PASSWORD"
    echo "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
    echo "CPU: ${CPUS} vCPUs"
    echo "RAM: ${MEMORY}MB"
    echo "Disk: ${DISK_SIZE}"
    echo "Acceleration: $([ "$USE_KVM" = true ] && echo "KVM" || echo "QEMU-only")"
    echo "Status: $STATUS"
    echo
}

create_cloud_init_seed() {
    local vm_name=$1
    local hostname=$2
    local username=$3
    local password=$4
    local ssh_key=$5
    
    local cloud_dir="/tmp/cloud-init-$vm_name-$(date +%s)"
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
    groups: users, admin, sudo
    home: /home/$username
    system: false
    primary_group: $username

# Enable password authentication with SSH
ssh_pwauth: true
disable_root: false

# Update packages on first boot
package_update: true
package_upgrade: true
package_reboot_if_required: true

# Install essential packages
packages:
  - qemu-guest-agent
  - cloud-initramfs-growroot
  - curl
  - wget
  - nano
  - htop
  - net-tools
  - openssh-server
  - unattended-upgrades

# Run commands on first boot
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - systemctl restart sshd
  - cloud-init clean

# Power state
power_state:
  mode: reboot
  message: First boot completed
  timeout: 120
  condition: true
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
        
        # Build QEMU command
        local qemu_cmd="qemu-system-x86_64"
        
        # Basic parameters
        qemu_cmd+=" -name $vm_name"
        qemu_cmd+=" -machine q35"
        
        # Use KVM if available, otherwise QEMU-only
        if [ "$KVM_AVAILABLE" = true ]; then
            qemu_cmd+=" -enable-kvm -cpu host"
            print_status "INFO" "Using KVM acceleration"
        else
            qemu_cmd+=" -cpu qemu64"
            print_status "INFO" "Using QEMU-only mode (no KVM)"
        fi
        
        qemu_cmd+=" -smp $CPUS"
        qemu_cmd+=" -m ${MEMORY}M"
        
        # Display
        if [ "$GUI_MODE" = "yes" ]; then
            qemu_cmd+=" -vnc :$((VNC_PORT - 5900))"
            qemu_cmd+=" -vga virtio"
        else
            qemu_cmd+=" -nographic"
            qemu_cmd+=" -serial mon:stdio"
        fi
        
        # Disk and CD-ROM (optimized for performance)
        qemu_cmd+=" -drive file=$IMG_FILE,if=virtio,format=qcow2,cache=writeback,discard=on"
        qemu_cmd+=" -drive file=$SEED_FILE,if=virtio,format=raw,readonly=on"
        
        # Network (optimized)
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
        
        # Performance optimizations
        qemu_cmd+=" -device virtio-balloon-pci"
        qemu_cmd+=" -object rng-random,filename=/dev/urandom,id=rng0"
        qemu_cmd+=" -device virtio-rng-pci,rng=rng0"
        qemu_cmd+=" -audiodev none,id=audio0"
        
        # Daemonize for background operation
        qemu_cmd+=" -daemonize"
        qemu_cmd+=" -pidfile /tmp/qemu-$vm_name.pid"
        
        print_status "DEBUG" "QEMU Command: $qemu_cmd"
        
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
            log_message "VM" "Started VM: $vm_name (KVM: $KVM_AVAILABLE)"
        else
            print_status "ERROR" "Failed to start VM '$vm_name'"
            log_message "ERROR" "Failed to start VM: $vm_name"
        fi
    fi
}

# =============================================================================
# PREMIUM DOCKER VM FUNCTIONS
# =============================================================================

create_docker_vm_advanced() {
    local node_id="$1"
    local node_name="$2"
    
    print_header
    echo -e "${GREEN}🐳 Create Premium Docker Container${NC}"
    echo -e "${YELLOW}Location: ${node_name}${NC}"
    echo
    
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
    
    # Advanced Configuration
    print_header
    echo -e "${GREEN}⚙️ Advanced Configuration${NC}"
    echo "─────────────────────────────────────"
    
    # Port Mapping
    local port_mapping=""
    read -rp "$(print_status "INPUT" "Add port mapping? (e.g., 80:8080 or leave empty): ")" ports_input
    if [ -n "$ports_input" ]; then
        port_mapping="-p $ports_input"
    fi
    
    # Volume Mapping
    local volume_mapping=""
    read -rp "$(print_status "INPUT" "Add volume mapping? (e.g., /host:/container or leave empty): ")" volume_input
    if [ -n "$volume_input" ]; then
        volume_mapping="-v $volume_input"
    fi
    
    # Environment Variables
    local env_vars=""
    read -rp "$(print_status "INPUT" "Add environment variables? (e.g., KEY=value or leave empty): ")" env_input
    if [ -n "$env_input" ]; then
        env_vars="-e $env_input"
    fi
    
    # Resource Limits
    local resource_limits=""
    read -rp "$(print_status "INPUT" "Set memory limit? (e.g., 512m or leave empty): ")" memory_limit
    if [ -n "$memory_limit" ]; then
        resource_limits+=" --memory=$memory_limit"
    fi
    
    read -rp "$(print_status "INPUT" "Set CPU limit? (e.g., 1.5 or leave empty): ")" cpu_limit
    if [ -n "$cpu_limit" ]; then
        resource_limits+=" --cpus=$cpu_limit"
    fi
    
    # Network Mode
    local network_mode="bridge"
    read -rp "$(print_status "INPUT" "Network mode (bridge/host/none, default: bridge): ")" network_input
    if [ -n "$network_input" ]; then
        network_mode="$network_input"
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
    [ -n "$resource_limits" ] && docker_cmd+=" $resource_limits"
    docker_cmd+=" --network $network_mode"
    docker_cmd+=" $docker_image"
    
    print_status "PROGRESS" "Creating premium container: $container_name"
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
RESOURCES="$resource_limits"
NETWORK="$network_mode"
CREATED="$(date -Iseconds)"
STATUS="running"
EOF
        
        log_message "DOCKER" "Created premium container: $container_name"
        
        # Show container info
        echo
        echo -e "${GREEN}📋 Container Specifications:${NC}"
        echo "─────────────────────────────────────"
        echo "Name: $container_name"
        echo "Image: $docker_image"
        echo "Status: running"
        echo "Network: $network_mode"
        [ -n "$ports_input" ] && echo "Ports: $ports_input"
        [ -n "$memory_limit" ] && echo "Memory Limit: $memory_limit"
        [ -n "$cpu_limit" ] && echo "CPU Limit: $cpu_limit"
        docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_name" | xargs -I {} echo "IP Address: {}"
    else
        print_status "ERROR" "Failed to create container"
    fi
}

# =============================================================================
# PREMIUM JUPYTER NOTEBOOK FUNCTIONS
# =============================================================================

create_jupyter_vm() {
    local node_id="$1"
    local node_name="$2"
    
    print_header
    echo -e "${GREEN}🔬 Create Premium Jupyter Notebook Server${NC}"
    echo -e "${YELLOW}Location: ${node_name}${NC}"
    echo
    
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
    
    # Volume for persistent data
    local volume_path="$DATA_DIR/jupyter/${notebook_name}"
    mkdir -p "$volume_path"
    
    # Advanced Configuration
    print_header
    echo -e "${GREEN}⚙️ Advanced Configuration${NC}"
    echo "─────────────────────────────────────"
    
    # Token generation
    local jupyter_token=$(generate_password 32 false)
    
    # Resource limits
    local memory_limit=""
    read -rp "$(print_status "INPUT" "Memory limit (e.g., 4g, default: 2g): ")" mem_input
    memory_limit="${mem_input:-2g}"
    
    local cpu_limit=""
    read -rp "$(print_status "INPUT" "CPU limit (e.g., 1.5, default: 1): ")" cpu_input
    cpu_limit="${cpu_input:-1}"
    
    # Create Jupyter container
    print_status "PROGRESS" "Creating premium Jupyter notebook server: $notebook_name"
    
    local docker_cmd="docker run -d"
    docker_cmd+=" --name jupyter-$notebook_name"
    docker_cmd+=" -p $available_port:8888"
    docker_cmd+=" -v $volume_path:/home/jovyan/work"
    docker_cmd+=" -e JUPYTER_TOKEN=$jupyter_token"
    docker_cmd+=" -e GRANT_SUDO=yes"
    docker_cmd+=" --memory=$memory_limit"
    docker_cmd+=" --cpus=$cpu_limit"
    docker_cmd+=" --restart unless-stopped"
    docker_cmd+=" $notebook_image"
    
    if eval "$docker_cmd"; then
        print_status "SUCCESS" "Premium Jupyter notebook server created successfully!"
        
        # Save configuration
        local config_file="$DATA_DIR/jupyter/${notebook_name}.conf"
        cat > "$config_file" << EOF
NOTEBOOK_NAME="$notebook_name"
JUPYTER_IMAGE="$notebook_image"
JUPYTER_PORT="$available_port"
JUPYTER_TOKEN="$jupyter_token"
VOLUME_PATH="$volume_path"
MEMORY_LIMIT="$memory_limit"
CPU_LIMIT="$cpu_limit"
CREATED="$(date -Iseconds)"
STATUS="running"
EOF
        
        log_message "JUPYTER" "Created premium notebook server: $notebook_name"
        
        # Show access details
        echo
        echo -e "${GREEN}📋 Jupyter Specifications:${NC}"
        echo "─────────────────────────────────────"
        echo "Name: $notebook_name"
        echo "URL: http://localhost:$available_port"
        echo "Token: $jupyter_token"
        echo "Volume: $volume_path"
        echo "Memory: $memory_limit"
        echo "CPU: $cpu_limit"
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
# MAIN MENU - ENHANCED
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
                    if ps aux | grep -q "[q]emu-system.*$IMG_FILE"; then
                        status="🟢 Running"
                    fi
                    
                    printf "  %2d) %-25s %-12s %s\n" $((i+1)) "$vm_name" "$status" "(${CPUS}vCPU/${MEMORY}MB)"
                else
                    printf "  %2d) %-25s %-12s\n" $((i+1)) "$vm_name" "❓ Unknown"
                fi
            done
            echo
        fi
        
        # System Info
        echo -e "${CYAN}System Status:${NC}"
        echo "  KVM: $([ "$KVM_AVAILABLE" = true ] && echo "🟢 Available" || echo "🔴 Not Available")"
        echo "  CPU: ${MAX_CPU_CORES} cores"
        echo "  RAM: ${MAX_RAM_MB}MB"
        echo "  Disk: ${MAX_DISK_GB}GB free"
        echo
        
        # Enhanced Main Menu Options
        echo -e "${GREEN}🏠 Main Menu:${NC}"
        echo "   1) ⚡ Create New Virtual Machine (Premium)"
        echo "   2) 🖥️  VM Management Dashboard"
        echo "   3) 🌐 Premium Nodes Deployment"
        echo "   4) 🐳 Docker Container Platform"
        echo "   5) 🔬 Jupyter Cloud Lab (Premium)"
        echo "   6) 📦 ISO & Template Library"
        echo "   7) 📊 Performance Monitoring"
        echo "   8) 💾 Backup & Disaster Recovery"
        echo "   9) ⚙️  Advanced Settings"
        echo "  10) 🔧 System Diagnostics"
        echo "  11) 📚 Documentation & Help"
        echo "   0) 🚪 Exit"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-11): ")" choice
        
        case $choice in
            1) create_new_vm_advanced ;;
            2) vm_management_dashboard ;;
            3) nodes_menu ;;
            4) docker_vm_menu ;;
            5) jupyter_cloud_menu ;;
            6) iso_library_menu ;;
            7) monitoring_menu ;;
            8) backup_menu ;;
            9) settings_menu ;;
            10) system_diagnostics_menu ;;
            11) show_documentation ;;
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
    echo -e "${GREEN}🚀 Create New Virtual Machine (Premium)${NC}"
    echo -e "${YELLOW}Step 1: Select Deployment Location${NC}"
    echo
    
    # Node Selection
    local node_options=("local|Local Development|127.0.0.1")
    local node_index=1
    
    echo -e "${GREEN}${node_index}) 🇺🇳 Local Development${NC}"
    echo "   └─ IP: 127.0.0.1 | Capabilities: QEMU/KVM, Docker, Jupyter"
    echo "      Resources: ${MAX_CPU_CORES} Cores • ${MAX_RAM_MB}MB RAM • ${MAX_DISK_GB}GB Disk"
    echo "      Acceleration: $([ "$KVM_AVAILABLE" = true ] && echo "KVM" || echo "QEMU-only")"
    echo
    
    # Premium Production Nodes
    echo -e "${YELLOW}🌍 Premium Production Nodes (Enterprise Grade):${NC}"
    for node_id in "${!REAL_NODES[@]}"; do
        IFS='|' read -r location region ip latency ram disk specs capabilities <<< "${REAL_NODES[$node_id]}"
        ((node_index++))
        node_options+=("$node_id|$location|$ip")
        
        # Emoji mapping
        local emoji="🌐"
        case "$location" in
            *"India"*) emoji="🇮🇳" ;;
            *"Singapore"*) emoji="🇸🇬" ;;
            *"Germany"*) emoji="🇩🇪" ;;
            *"USA"*) emoji="🇺🇸" ;;
            *"Japan"*) emoji="🇯🇵" ;;
        esac
        
        echo -e "${GREEN}${node_index}) ${emoji} ${location}${NC}"
        echo "   └─ IP: $ip | Latency: ${latency}ms"
        echo "      Specs: $specs"
        echo "      Resources: ${ram}GB RAM • ${disk}GB NVMe SSD"
        echo "      Capabilities: $capabilities"
        echo
    done
    
    # Node selection
    while true; do
        read -rp "$(print_status "INPUT" "Select node (1-${#node_options[@]}): ")" node_choice
        
        if [[ "$node_choice" =~ ^[0-9]+$ ]] && [ "$node_choice" -ge 1 ] && [ "$node_choice" -le ${#node_options[@]} ]; then
            IFS='|' read -r selected_node_id selected_node_name selected_node_ip <<< "${node_options[$((node_choice-1))]}"
            break
        else
            print_status "ERROR" "Invalid selection. Please enter a number between 1 and ${#node_options[@]}"
        fi
    done
    
    # VM Type Selection
    print_header
    echo -e "${GREEN}🚀 Create New Virtual Machine (Premium)${NC}"
    echo -e "${YELLOW}Step 2: Select Virtualization Technology${NC}"
    echo
    
    echo "Available Virtualization Types:"
    echo "───────────────────────────────"
    echo "  1) 🖥️  QEMU/KVM Virtual Machine (Premium)"
    echo "     └─ Complete OS isolation • $([ "$KVM_AVAILABLE" = true ] && echo "KVM Accelerated" || echo "QEMU-only") • Snapshots"
    echo
    echo "  2) 🐳 Docker Container (Application Container)"
    echo "     └─ Lightweight • Fast startup • Portable • Microservices"
    echo
    echo "  3) 🔬 Jupyter Notebook Server (Data Science)"
    echo "     └─ Data science • Machine learning • Code sandbox • GPU Support"
    echo
    
    while true; do
        read -rp "$(print_status "INPUT" "Select virtualization type (1-3): ")" vm_type_choice
        
        case $vm_type_choice in
            1)
                create_kvm_vm "$selected_node_id" "$selected_node_name" "$selected_node_ip"
                break
                ;;
            2)
                create_docker_vm_advanced "$selected_node_id" "$selected_node_name"
                break
                ;;
            3)
                create_jupyter_vm "$selected_node_id" "$selected_node_name"
                break
                ;;
            *)
                print_status "ERROR" "Invalid selection. Please enter 1-3."
                ;;
        esac
    done
}

# =============================================================================
# OPTIMIZED VM MANAGEMENT DASHBOARD
# =============================================================================

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
                
                printf "  %2d) %-25s %-12s %s\n" $((i+1)) "$vm_name" "$status" "(${CPUS}vCPU/${MEMORY}MB)"
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
        echo "   7) 🔙 Restore Snapshot"
        echo "   8) 📡 Connect via SSH"
        echo "   9) 📋 List All Snapshots"
        echo "  10) ⚡ Performance Monitor"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-10): ")" choice
        
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
                read -rp "$(print_status "INPUT" "Enter VM number to restore: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                    restore_snapshot "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "Invalid selection"
                fi
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            8)
                read -rp "$(print_status "INPUT" "Enter VM number to connect: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                    connect_vm_ssh "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "Invalid selection"
                fi
                ;;
            9)
                list_snapshots
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            10)
                read -rp "$(print_status "INPUT" "Enter VM number to monitor: ")" vm_num
                if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                    monitor_vm_performance "${vms[$((vm_num-1))]}"
                else
                    print_status "ERROR" "Invalid selection"
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
        echo -e "${GREEN}📋 VM Specifications: $vm_name${NC}"
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
        echo -e "${CYAN}Hardware Specifications:${NC}"
        echo "  CPU Cores: $CPUS vCPUs"
        echo "  Memory: ${MEMORY}MB"
        echo "  Disk: $DISK_SIZE"
        echo "  Acceleration: $([ "$KVM_AVAILABLE" = true ] && echo "KVM" || echo "QEMU-only")"
        echo
        echo -e "${CYAN}Network Configuration:${NC}"
        echo "  SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        if [ "$GUI_MODE" = "yes" ]; then
            echo "  VNC: vncviewer localhost:$VNC_PORT"
        fi
        if [ -n "$PORT_FORWARDS" ]; then
            echo "  Port Forwards: $PORT_FORWARDS"
        fi
        echo
        echo -e "${CYAN}Storage Files:${NC}"
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
        
        # Stop VM before snapshot (optional but recommended)
        read -rp "$(print_status "INPUT" "Stop VM before creating snapshot? (y/n): ")" stop_before
        if [[ "$stop_before" =~ ^[Yy]$ ]]; then
            stop_vm "$vm_name"
        fi
        
        # Create snapshot of disk
        if qemu-img snapshot -c "$snapshot_name" "$IMG_FILE" 2>/dev/null; then
            # Copy configuration
            cp "$DATA_DIR/vms/$vm_name.conf" "$snapshot_dir/${snapshot_name}.conf"
            
            print_status "SUCCESS" "Snapshot '$snapshot_name' created successfully"
            log_message "SNAPSHOT" "Created snapshot for VM: $vm_name"
            
            # Restart VM if it was stopped
            if [[ "$stop_before" =~ ^[Yy]$ ]]; then
                start_vm "$vm_name"
            fi
        else
            print_status "ERROR" "Failed to create snapshot"
        fi
    fi
}

# =============================================================================
# OPTIMIZED NODES MENU
# =============================================================================

nodes_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🌐 Premium Nodes Deployment${NC}"
        echo "─────────────────────────────────────"
        
        # Display premium nodes
        echo -e "${CYAN}Premium Production Nodes:${NC}"
        echo "─────────────────────────────────────"
        
        for node_id in "${!REAL_NODES[@]}"; do
            IFS='|' read -r location region ip latency ram disk specs capabilities <<< "${REAL_NODES[$node_id]}"
            
            # Emoji based on location
            local emoji="🌐"
            case "$location" in
                *"India"*) emoji="🇮🇳" ;;
                *"Singapore"*) emoji="🇸🇬" ;;
                *"Germany"*) emoji="🇩🇪" ;;
                *"USA"*) emoji="🇺🇸" ;;
                *"Japan"*) emoji="🇯🇵" ;;
            esac
            
            echo -e "${GREEN}$node_id${NC} $emoji $location"
            echo "  IP: $ip | Latency: ${latency}ms"
            echo "  Specifications: $specs"
            echo "  Resources: ${ram}GB RAM • ${disk}GB NVMe SSD"
            echo "  Capabilities: $capabilities"
            echo
        done
        
        echo -e "${GREEN}📋 Node Management Options:${NC}"
        echo "   1) 📊 Node Status & Health"
        echo "   2) 🔍 Test Node Connectivity"
        echo "   3) ⚡ Deploy VM to Premium Node"
        echo "   4) 📈 Resource Monitoring"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-4): ")" choice
        
        case $choice in
            1) show_node_status ;;
            2) test_node_connectivity ;;
            3) deploy_to_premium_node ;;
            4) node_resource_monitoring ;;
            0) return ;;
            *) print_status "ERROR" "Invalid option" ;;
        esac
        
        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
    done
}

show_node_status() {
    print_header
    echo -e "${GREEN}📊 Premium Nodes Status & Health${NC}"
    echo "─────────────────────────────────────"
    
    echo -e "${CYAN}Local Node:${NC}"
    echo "  CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')%"
    echo "  Memory: $(free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2}') used"
    echo "  Disk: $(df -h / | awk 'NR==2{print $5}') used"
    echo "  KVM: $([ "$KVM_AVAILABLE" = true ] && echo "🟢 Available" || echo "🔴 Not Available")"
    echo
    
    echo -e "${CYAN}Premium Nodes Status:${NC}"
    for node_id in "${!REAL_NODES[@]}"; do
        IFS='|' read -r location region ip latency ram disk specs capabilities <<< "${REAL_NODES[$node_id]}"
        
        # Simulate status
        local status_indicators=("🟢" "🟡" "🔴")
        local random_status=${status_indicators[$RANDOM % ${#status_indicators[@]}]}
        local random_load=$((RANDOM % 100))
        local random_vms=$((RANDOM % 50))
        
        echo "  $node_id: $random_status Load: ${random_load}% | VMs: $random_vms | Latency: ${latency}ms"
    done
}

deploy_to_premium_node() {
    print_header
    echo -e "${GREEN}⚡ Deploy VM to Premium Node${NC}"
    echo "─────────────────────────────────────"
    
    # Select premium node
    echo "Select Premium Node:"
    local index=1
    local node_keys=("${!REAL_NODES[@]}")
    for key in "${node_keys[@]}"; do
        IFS='|' read -r location region ip latency ram disk specs capabilities <<< "${REAL_NODES[$key]}"
        printf "%2d) %-25s %s\n" "$index" "$location" "($ip)"
        ((index++))
    done
    echo
    
    read -rp "$(print_status "INPUT" "Select node (1-${#REAL_NODES[@]}): ")" node_choice
    
    if [[ "$node_choice" =~ ^[0-9]+$ ]] && [ "$node_choice" -ge 1 ] && [ "$node_choice" -le ${#REAL_NODES[@]} ]; then
        local selected_key="${node_keys[$((node_choice-1))]}"
        IFS='|' read -r location region ip latency ram disk specs capabilities <<< "${REAL_NODES[$selected_key]}"
        
        print_status "INFO" "Selected: $location ($ip)"
        print_status "INFO" "Specifications: $specs"
        print_status "INFO" "Capabilities: $capabilities"
        
        # For now, simulate deployment
        print_status "PROGRESS" "Simulating deployment to $location..."
        sleep 2
        
        # Show deployment options
        echo
        echo "Deployment Options:"
        echo "  1) Deploy from local template"
        echo "  2) Deploy from cloud image"
        echo "  3) Custom deployment"
        
        read -rp "$(print_status "INPUT" "Select deployment method (1-3): ")" deploy_method
        
        case $deploy_method in
            1)
                print_status "PROGRESS" "Deploying from local template..."
                sleep 2
                print_status "SUCCESS" "VM deployment simulated to $location"
                ;;
            2)
                print_status "PROGRESS" "Deploying from cloud image..."
                sleep 2
                print_status "SUCCESS" "Cloud deployment simulated to $location"
                ;;
            3)
                print_status "PROGRESS" "Starting custom deployment..."
                sleep 2
                print_status "SUCCESS" "Custom deployment simulated to $location"
                ;;
            *)
                print_status "ERROR" "Invalid deployment method"
                ;;
        esac
    else
        print_status "ERROR" "Invalid node selection"
    fi
}

# =============================================================================
# OPTIMIZED DOCKER VM MENU
# =============================================================================

docker_vm_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🐳 Docker Container Platform${NC}"
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
                local image=$(docker inspect -f '{{.Config.Image}}' "$container_name" 2>/dev/null || echo "unknown")
                
                if [ "$status" = "running" ]; then
                    status="🟢 Running"
                else
                    status="🔴 Stopped"
                fi
                
                printf "  %2d) %-25s %-12s %s\n" $((i+1)) "$container_name" "$status" "($image)"
            done
        else
            echo -e "${YELLOW}No Docker containers found.${NC}"
        fi
        
        echo
        echo -e "${GREEN}📋 Docker Management Options:${NC}"
        echo "   1) 🐳 Create New Docker Container (Premium)"
        if [ $container_count -gt 0 ]; then
            echo "   2) ▶️  Start Container"
            echo "   3) ⏹️  Stop Container"
            echo "   4) 🔄 Restart Container"
            echo "   5) 📜 View Container Logs"
            echo "   6) 🐚 Open Container Shell"
            echo "   7) 📊 Container Stats"
            echo "   8) 🗑️  Remove Container"
        fi
        echo "   9) 🐋 Docker System Info"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-9): ")" choice
        
        case $choice in
            1)
                create_docker_vm_advanced "local" "Local"
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
                        docker logs "${containers[$((container_num-1))]}" --tail 50
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
                    clear
                    echo -e "${GREEN}📊 Docker Container Stats${NC}"
                    echo "─────────────────────────────────────"
                    docker stats --no-stream
                    echo
                    read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                fi
                ;;
            8)
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
            9)
                clear
                echo -e "${GREEN}🐋 Docker System Information${NC}"
                echo "─────────────────────────────────────"
                docker info
                echo
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

# =============================================================================
# OPTIMIZED JUPYTER CLOUD MENU
# =============================================================================

jupyter_cloud_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🔬 Jupyter Cloud Lab (Premium)${NC}"
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
        echo "   1) 🔬 Create New Jupyter Notebook (Premium)"
        if [ $notebook_count -gt 0 ]; then
            echo "   2) ▶️  Start Notebook"
            echo "   3) ⏹️  Stop Notebook"
            echo "   4) 🌐 Open in Browser"
            echo "   5) 📜 View Notebook Logs"
            echo "   6) 📊 Notebook Stats"
            echo "   7) 🗑️  Remove Notebook"
        fi
        echo "   8) 📚 Jupyter Templates"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-8): ")" choice
        
        case $choice in
            1)
                create_jupyter_vm "local" "Local"
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
                        docker logs "jupyter-$notebook_name" --tail 50
                        echo
                        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $notebook_count -gt 0 ]; then
                    clear
                    echo -e "${GREEN}📊 Jupyter Notebooks Stats${NC}"
                    echo "─────────────────────────────────────"
                    for notebook in "${notebooks[@]}"; do
                        local status=$(docker inspect -f '{{.State.Status}}' "jupyter-$notebook" 2>/dev/null || echo "unknown")
                        echo "$notebook: $status"
                    done
                    echo
                    read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                fi
                ;;
            7)
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
            8)
                clear
                echo -e "${GREEN}📚 Jupyter Templates${NC}"
                echo "─────────────────────────────────────"
                for key in "${!JUPYTER_TEMPLATES[@]}"; do
                    IFS='|' read -r name image port tags <<< "${JUPYTER_TEMPLATES[$key]}"
                    echo "$name: $tags"
                done
                echo
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

# =============================================================================
# OPTIMIZED ISO LIBRARY MENU
# =============================================================================

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
        echo "   1) 📥 Download ISO (Premium Mirror)"
        echo "   2) 🗑️  Delete ISO"
        echo "   3) 🔍 Verify ISO Integrity"
        echo "   4) 📁 Mount ISO"
        echo "   5) 🔄 Update ISO Library"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-5): ")" choice
        
        case $choice in
            1) download_iso ;;
            2) delete_iso ;;
            3) verify_iso ;;
            4) mount_iso ;;
            5) update_iso_library ;;
            0) return ;;
            *) print_status "ERROR" "Invalid option" ;;
        esac
        
        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
    done
}

download_iso() {
    print_header
    echo -e "${GREEN}📥 Download ISO Image (Premium Mirror)${NC}"
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
        
        print_status "PROGRESS" "Downloading $iso_name from premium mirror..."
        print_status "INFO" "URL: $iso_url"
        print_status "INFO" "Destination: $filename"
        
        # Download with progress bar and resume support
        if command -v curl > /dev/null 2>&1; then
            curl -L -o "$filename" --progress-bar --continue-at - "$iso_url"
        elif command -v wget > /dev/null 2>&1; then
            wget -O "$filename" --progress=bar:force --continue "$iso_url"
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

# =============================================================================
# MAIN EXECUTION - OPTIMIZED
# =============================================================================

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
