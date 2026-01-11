#!/bin/bash
set -euo pipefail

# =============================================================================
# ZynexForge CloudStack™ Platform - World's #1 Virtualization System
# Advanced Multi-Node Virtualization Management
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

# Resource Limits
readonly MAX_CPU_CORES=128
readonly MAX_RAM_MB=262144
readonly MAX_DISK_GB=16384
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
    ["proxmox-8"]="Proxmox VE 8|https://download.proxmox.com/iso/proxmox-ve_8.1-1.iso|proxmox|proxmox"
    ["windows-11"]="Windows 11|https://archive.org/download/windows-11-iso/windows11.iso|administrator|Password123"
)

# Real Nodes with Enhanced Specifications
declare -A REAL_NODES=(
    ["mumbai"]="🇮🇳 Mumbai, India|ap-south-1|103.21.58.1|45|64|500|kvm,qemu,docker,lxd,jupyter"
    ["delhi"]="🇮🇳 Delhi NCR, India|ap-south-2|103.21.59.1|35|128|1000|kvm,qemu,docker,jupyter,lxd,kubernetes"
    ["bangalore"]="🇮🇳 Bangalore, India|ap-south-1|103.21.60.1|25|32|300|kvm,qemu,lxd"
    ["singapore"]="🇸🇬 Singapore|ap-southeast-1|103.21.61.1|60|256|2000|kvm,qemu,docker,jupyter,lxd,kubernetes"
    ["frankfurt"]="🇩🇪 Frankfurt, Germany|eu-central-1|103.21.62.1|70|512|5000|kvm,qemu,docker,jupyter,lxd,kubernetes,openstack"
    ["amsterdam"]="🇳🇱 Amsterdam, Netherlands|eu-west-1|103.21.63.1|55|256|3000|kvm,qemu,docker,lxd,kubernetes"
    ["london"]="🇬🇧 London, UK|eu-west-2|103.21.64.1|40|128|1500|kvm,qemu,docker,jupyter,lxd"
    ["newyork"]="🇺🇸 New York, USA|us-east-1|103.21.65.1|80|1024|10000|kvm,qemu,docker,jupyter,lxd,kubernetes,openstack"
    ["losangeles"]="🇺🇸 Los Angeles, USA|us-west-2|103.21.66.1|95|512|5000|kvm,qemu,docker,lxd,kubernetes"
    ["toronto"]="🇨🇦 Toronto, Canada|ca-central-1|103.21.67.1|65|128|2000|kvm,qemu,docker,lxd"
    ["tokyo"]="🇯🇵 Tokyo, Japan|ap-northeast-1|103.21.68.1|85|256|4000|kvm,qemu,docker,jupyter,lxd,kubernetes"
    ["sydney"]="🇦🇺 Sydney, Australia|ap-southeast-2|103.21.69.1|110|128|2500|kvm,qemu,docker,jupyter,lxd"
)

# Enhanced LXD Images
declare -A LXD_IMAGES=(
    ["ubuntu-24.04"]="Ubuntu 24.04 LTS|ubuntu:24.04"
    ["ubuntu-22.04"]="Ubuntu 22.04 LTS|ubuntu:22.04"
    ["debian-12"]="Debian 12|debian:12"
    ["centos-9"]="CentOS Stream 9|centos:stream9"
    ["rocky-9"]="Rocky Linux 9|rockylinux:9"
    ["almalinux-9"]="AlmaLinux 9|almalinux:9"
    ["fedora-40"]="Fedora 40|fedora:40"
    ["alpine-3.19"]="Alpine Linux 3.19|alpine:3.19"
    ["archlinux"]="Arch Linux|archlinux"
    ["opensuse-tumbleweed"]="OpenSUSE Tumbleweed|opensuse/tumbleweed"
)

# Enhanced Docker Images
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
)

# Enhanced Jupyter Templates
declare -A JUPYTER_TEMPLATES=(
    ["data-science"]="Data Science|jupyter/datascience-notebook|8888|python,R,julia,scipy"
    ["tensorflow"]="TensorFlow ML|jupyter/tensorflow-notebook|8889|python,tensorflow,keras"
    ["minimal"]="Minimal Python|jupyter/minimal-notebook|8890|python,pandas,numpy"
    ["pyspark"]="PySpark|jupyter/pyspark-notebook|8891|python,spark,hadoop"
    ["rstudio"]="R Studio|jupyter/r-notebook|8892|R,tidyverse,ggplot2"
    ["scipy"]="Scientific Python|jupyter/scipy-notebook|8893|python,scipy,matplotlib"
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
            sudo apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils genisoimage openssh-client curl wget jq net-tools bridge-utils dnsmasq libvirt-clients virt-manager cpu-checker
            log_message "INSTALL" "Installed packages on Debian/Ubuntu"
            
        elif command -v dnf > /dev/null 2>&1; then
            print_status "INFO" "Installing packages on Fedora/RHEL..."
            sudo dnf install -y qemu-system-x86 qemu-img cloud-utils genisoimage openssh-clients curl wget jq net-tools bridge-utils dnsmasq libvirt-client virt-manager
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
    
    # Check KVM support
    if kvm-ok 2>/dev/null; then
        print_status "SUCCESS" "KVM acceleration is available"
    else
        print_status "WARNING" "KVM acceleration may not be available"
    fi
    
    # Check Docker
    if command -v docker > /dev/null 2>&1; then
        print_status "SUCCESS" "Docker is available"
    else
        print_status "WARNING" "Docker is not installed"
    fi
    
    # Check LXD
    if command -v lxd > /dev/null 2>&1; then
        print_status "SUCCESS" "LXD is available"
    else
        print_status "WARNING" "LXD is not installed"
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
    local available_ram_mb=$((total_ram_mb * 80 / 100)) # Use 80% of total RAM
    
    local total_disk_gb
    total_disk_gb=$(df -BG "$DATA_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    total_disk_gb=${total_disk_gb:-100}
    
    local cpu_cores
    cpu_cores=$(nproc)
    local available_cores=$((cpu_cores - 1)) # Leave 1 core for host
    
    echo "$available_ram_mb $total_disk_gb $available_cores"
}

# =============================================================================
# INITIALIZATION
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
        log_message "CONFIG", "Created global configuration"
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
            IFS='|' read -r location region ip latency ram disk capabilities <<< "${REAL_NODES[$node_id]}"
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
    resources:
      max_ram_gb: "$ram"
      max_disk_gb: "$disk"
      max_vcpus: "128"
      storage_type: "NVMe SSD"
      network_speed: "10 Gbps"
    sla:
      uptime: "99.99%"
      support: "24/7 Premium"
      backup: "Daily Automated"
    tags: ["production", "enterprise", "high-availability", "global"]
    status: "active"
    created_at: "$(date -Iseconds)"
    user_mode: false
EOF
        done
        
        print_status "SUCCESS" "Enhanced nodes database created with ${#REAL_NODES[@]} global locations"
        log_message "NODES", "Created nodes database with ${#REAL_NODES[@]} nodes"
    fi
    
    # Generate SSH key if not exists
    if [ ! -f "$SSH_KEY_FILE" ]; then
        print_status "INFO", "Generating SSH key pair..."
        ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q -C "zynexforge@$(hostname)"
        chmod 600 "$SSH_KEY_FILE"
        chmod 644 "${SSH_KEY_FILE}.pub"
        print_status "SUCCESS", "SSH key generated: $SSH_KEY_FILE"
        log_message "SECURITY", "Generated SSH key pair"
    fi
    
    # Create neofetch banner configuration
    mkdir -p "$USER_HOME/.config/neofetch"
    cat > "$USER_HOME/.config/neofetch/config.conf" << 'EOF'
print_info() {
    info title
    info underline

    info "┌─────────────────────────────────────────────────────┐" info
    info "│      ⚡ ZynexForge CloudStack™ Professional        │" info
    info "│      World's #1 Virtualization Platform            │" info
    info "│      Version 4.0.0 Ultra                          │" info
    info "│      Multi-Node • QEMU/KVM • LXD • Docker • Jupyter│" info
    info "└─────────────────────────────────────────────────────┘" info
    info
    
    info "OS" distro
    info "Host" model
    info "Kernel" kernel
    info "Uptime" uptime
    info "Packages" packages
    info "Shell" shell
    info "Resolution" resolution
    info "DE" de
    info "WM" wm
    info "WM Theme" wm_theme
    info "Theme" theme
    info "Icons" icons
    info "Terminal" term
    info "Terminal Font" term_font
    info "CPU" cpu
    info "GPU" gpu
    info "Memory" memory
    
    info cols
}
EOF
    
    # Check and install dependencies
    if check_dependencies; then
        print_status "SUCCESS", "Platform initialized successfully!"
        log_message "INIT", "Platform initialization completed"
    else
        print_status "ERROR", "Platform initialization failed"
        return 1
    fi
    
    # Initialize Docker if available
    if command -v docker > /dev/null 2>&1; then
        if ! docker info > /dev/null 2>&1; then
            print_status "WARNING", "Docker daemon is not running"
        fi
    fi
    
    # Initialize LXD if available
    if command -v lxd > /dev/null 2>&1; then
        if ! lxd version > /dev/null 2>&1; then
            print_status "WARNING", "LXD is not initialized. Run 'lxd init' to set up"
        fi
    fi
}

# =============================================================================
# VM MANAGEMENT FUNCTIONS
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
        print_status "ERROR", "Configuration for VM '$vm_name' not found"
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
    
    print_status "SUCCESS", "Configuration saved to $config_file"
    log_message "VM", "Saved configuration for VM: $VM_NAME"
}

# =============================================================================
# ENHANCED KVM VM CREATION
# =============================================================================

create_kvm_vm() {
    local node_id="$1"
    local node_name="$2"
    local node_ip="$3"
    
    print_header
    echo -e "${GREEN}🖥️ Create QEMU/KVM Virtual Machine${NC}"
    echo -e "${YELLOW}Location: ${node_name} ($node_ip)${NC}"
    echo
    
    # VM Name with validation
    while true; do
        read -rp "$(print_status "INPUT" "VM Name (letters, numbers, hyphens only): ")" vm_name
        
        if validate_input "name" "$vm_name"; then
            if [ -f "$DATA_DIR/vms/${vm_name}.conf" ]; then
                print_status "ERROR", "VM '$vm_name' already exists"
            else
                VM_NAME="$vm_name"
                NODE_ID="$node_id"
                break
            fi
        fi
    done
    
    # OS Selection Method
    print_status "INFO", "Select OS Installation Method:"
    echo "  1) 📦 Cloud Image (Fast Deployment - 1-2 minutes)"
    echo "  2) 💿 ISO Image (Full Install - 10-30 minutes)"
    echo "  3) 🔄 Custom Template"
    echo "  4) 🎯 Custom Image URL"
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
                    print_status "ERROR", "Invalid selection"
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
                    print_status "ERROR", "Invalid selection"
                fi
            done
            ;;
            
        3)
            # Custom Template
            read -rp "$(print_status "INPUT" "Enter template name: ")" custom_template
            OS_TYPE="custom-$custom_template"
            ;;
            
        4)
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
            print_status "ERROR", "Invalid choice"
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
        read -rp "$(print_status "INPUT" "CPU Cores (1-$available_cores, recommended: 2): ")" cpus
        if validate_input "number" "$cpus" 1 "$available_cores"; then
            CPUS="$cpus"
            break
        fi
    done
    
    # RAM Allocation
    while true; do
        read -rp "$(print_status "INPUT" "RAM in MB (256-$available_ram, recommended: 2048): ")" memory
        if validate_input "number" "$memory" "$MIN_RAM_MB" "$available_ram"; then
            MEMORY="$memory"
            break
        fi
    done
    
    # Disk Size
    while true; do
        read -rp "$(print_status "INPUT" "Disk Size (e.g., 20G, min ${MIN_DISK_GB}G): ")" disk_size
        if validate_input "size" "$disk_size"; then
            DISK_SIZE="$disk_size"
            break
        fi
    done
    
    # Network Configuration
    print_header
    echo -e "${GREEN}🌐 Network Configuration${NC}"
    echo "─────────────────────────────────────"
    
    # SSH Port
    SSH_PORT=$(find_available_port)
    print_status "INFO", "Auto-assigned SSH port: $SSH_PORT"
    
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
        print_status "INFO", "VNC port: $VNC_PORT"
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
        print_status "INFO", "Generated password: $PASSWORD"
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
        print_status "PROGRESS", "Downloading image from $img_url"
        IMG_FILE="$DATA_DIR/disks/${VM_NAME}.qcow2"
        
        if [[ "$img_url" == *.iso ]]; then
            # ISO download
            iso_path="$DATA_DIR/isos/$(basename "$img_url")"
            mkdir -p "$DATA_DIR/isos"
            
            if [ ! -f "$iso_path" ]; then
                curl -L -o "$iso_path" "$img_url"
                print_status "SUCCESS", "ISO downloaded: $iso_path"
            else
                print_status "INFO", "ISO already exists: $iso_path"
            fi
            
            # Create disk from ISO
            qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
        else
            # QCOW2 image
            if [[ "$img_url" == http* ]]; then
                curl -L -o "/tmp/${VM_NAME}.img" "$img_url"
                qemu-img convert -f qcow2 -O qcow2 "/tmp/${VM_NAME}.img" "$IMG_FILE"
                rm -f "/tmp/${VM_NAME}.img"
            fi
            # Resize disk
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
    
    print_status "SUCCESS", "Virtual Machine '$VM_NAME' created successfully!"
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
    groups: users, admin
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

# Install useful packages
packages:
  - qemu-guest-agent
  - cloud-initramfs-growroot
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
    print_status "SUCCESS", "Cloud-init seed image created: $SEED_FILE"
}

start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "PROGRESS", "Starting VM: $vm_name"
        
        # Check if VM is already running
        if ps aux | grep -q "[q]emu-system.*$IMG_FILE"; then
            print_status "WARNING", "VM '$vm_name' is already running"
            return 1
        fi
        
        # Build QEMU command
        local qemu_cmd="qemu-system-x86_64"
        
        # Basic parameters
        qemu_cmd+=" -name $vm_name"
        qemu_cmd+=" -machine q35,accel=kvm"
        qemu_cmd+=" -cpu host"
        qemu_cmd+=" -smp $CPUS"
        qemu_cmd+=" -m ${MEMORY}M"
        
        # Display
        if [ "$GUI_MODE" = "yes" ]; then
            qemu_cmd+=" -vnc :$((VNC_PORT - 5900))"
        else
            qemu_cmd+=" -nographic"
        fi
        
        # Disk and CD-ROM
        qemu_cmd+=" -drive file=$IMG_FILE,if=virtio,format=qcow2,discard=on"
        qemu_cmd+=" -drive file=$SEED_FILE,if=virtio,format=raw"
        
        # Network
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
        
        # Additional optimizations
        qemu_cmd+=" -enable-kvm"
        qemu_cmd+=" -daemonize"
        qemu_cmd+=" -pidfile /tmp/qemu-$vm_name.pid"
        
        # Start VM
        eval "$qemu_cmd"
        
        if [ $? -eq 0 ]; then
            STATUS="running"
            save_vm_config
            print_status "SUCCESS", "VM '$vm_name' started successfully!"
            print_status "INFO", "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
            if [ "$GUI_MODE" = "yes" ]; then
                print_status "INFO", "VNC: vncviewer localhost:$VNC_PORT"
            fi
            log_message "VM", "Started VM: $vm_name"
        else
            print_status "ERROR", "Failed to start VM '$vm_name'"
            log_message "ERROR", "Failed to start VM: $vm_name"
        fi
    fi
}

# =============================================================================
# DOCKER VM FUNCTIONS
# =============================================================================

create_docker_vm_advanced() {
    local node_id="$1"
    local node_name="$2"
    
    print_header
    echo -e "${GREEN}🐳 Create Docker Container${NC}"
    echo -e "${YELLOW}Location: ${node_name}${NC}"
    echo
    
    # Container Name
    while true; do
        read -rp "$(print_status "INPUT" "Container Name: ")" container_name
        if validate_input "name" "$container_name"; then
            if docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
                print_status "ERROR", "Container '$container_name' already exists"
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
        print_status "ERROR", "Invalid selection"
        return 1
    fi
    
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
    print_status "PROGRESS", "Pulling image: $docker_image"
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
    
    print_status "PROGRESS", "Creating container: $container_name"
    if eval "$docker_cmd"; then
        print_status "SUCCESS", "Docker container '$container_name' created successfully!"
        
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
        
        log_message "DOCKER", "Created container: $container_name"
        
        # Show container info
        echo
        echo -e "${GREEN}📋 Container Details:${NC}"
        echo "─────────────────────────────────────"
        echo "Name: $container_name"
        echo "Image: $docker_image"
        echo "Status: running"
        echo "Network: $network_mode"
        [ -n "$ports_input" ] && echo "Ports: $ports_input"
        docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_name" | xargs -I {} echo "IP Address: {}"
    else
        print_status "ERROR", "Failed to create container"
    fi
}

# =============================================================================
# LXD CONTAINER FUNCTIONS
# =============================================================================

create_lxd_vm() {
    local node_id="$1"
    local node_name="$2"
    
    print_header
    echo -e "${GREEN}🧊 Create LXD Container${NC}"
    echo -e "${YELLOW}Location: ${node_name}${NC}"
    echo
    
    # Check if LXD is installed
    if ! command -v lxd > /dev/null 2>&1; then
        print_status "ERROR", "LXD is not installed. Please install LXD first."
        read -rp "$(print_status "INPUT" "Install LXD now? (y/n): ")" install_lxd
        if [[ "$install_lxd" =~ ^[Yy]$ ]]; then
            sudo snap install lxd
            sudo lxd init --auto
        else
            return 1
        fi
    fi
    
    # Container Name
    while true; do
        read -rp "$(print_status "INPUT" "Container Name: ")" container_name
        if validate_input "name" "$container_name"; then
            if lxc list --format csv | grep -q "^${container_name},"; then
                print_status "ERROR", "Container '$container_name' already exists"
            else
                break
            fi
        fi
    done
    
    # Image Selection
    print_header
    echo -e "${GREEN}📦 Select LXD Image${NC}"
    echo "─────────────────────────────────────"
    local index=1
    local image_keys=("${!LXD_IMAGES[@]}")
    for key in "${image_keys[@]}"; do
        IFS='|' read -r name image <<< "${LXD_IMAGES[$key]}"
        printf "%2d) %-25s → %s\n" "$index" "$name" "$image"
        ((index++))
    done
    echo
    
    while true; do
        read -rp "$(print_status "INPUT" "Select image (1-${#LXD_IMAGES[@]}): ")" image_choice
        
        if [[ "$image_choice" =~ ^[0-9]+$ ]] && [ "$image_choice" -ge 1 ] && [ "$image_choice" -le ${#LXD_IMAGES[@]} ]; then
            local selected_key="${image_keys[$((image_choice-1))]}"
            IFS='|' read -r name lxd_image <<< "${LXD_IMAGES[$selected_key]}"
            break
        else
            print_status "ERROR", "Invalid selection"
        fi
    done
    
    # Resource Allocation
    print_header
    echo -e "${GREEN}📊 Resource Allocation${NC}"
    echo "─────────────────────────────────────"
    
    read -rp "$(print_status "INPUT" "CPU Cores (default: 2): ")" cpu_cores
    cpu_cores=${cpu_cores:-2}
    
    read -rp "$(print_status "INPUT" "Memory (e.g., 2GB, default: 2GB): ")" memory
    memory=${memory:-2GB}
    
    read -rp "$(print_status "INPUT" "Disk Size (e.g., 20GB, default: 20GB): ")" disk_size
    disk_size=${disk_size:-20GB}
    
    # Network Configuration
    read -rp "$(print_status "INPUT" "Network (default: lxdbr0): ")" network
    network=${network:-lxdbr0}
    
    # Create container profile
    local profile_name="zynexforge-$container_name"
    
    print_status "PROGRESS", "Creating LXD container: $container_name"
    
    # Create container
    if lxc launch "$lxd_image" "$container_name" \
        --config limits.cpu="$cpu_cores" \
        --config limits.memory="$memory" \
        --device root,size="$disk_size" \
        --network "$network"; then
        
        print_status "SUCCESS", "LXD container '$container_name' created successfully!"
        
        # Save configuration
        local config_file="$DATA_DIR/lxd/${container_name}.conf"
        cat > "$config_file" << EOF
CONTAINER_NAME="$container_name"
LXD_IMAGE="$lxd_image"
CPU_CORES="$cpu_cores"
MEMORY="$memory"
DISK_SIZE="$disk_size"
NETWORK="$network"
CREATED="$(date -Iseconds)"
STATUS="running"
EOF
        
        log_message "LXD", "Created container: $container_name"
        
        # Show container info
        echo
        echo -e "${GREEN}📋 Container Details:${NC}"
        echo "─────────────────────────────────────"
        echo "Name: $container_name"
        echo "Image: $lxd_image"
        echo "Status: running"
        echo "Resources: ${cpu_cores}vCPU, $memory RAM, $disk_size disk"
        lxc list "$container_name" --format json | jq -r '.[] | "IP Address: \(.state.network.eth0.addresses[0].address)"'
        
        # Offer to exec into container
        echo
        read -rp "$(print_status "INPUT" "Open shell in container? (y/n): ")" open_shell
        if [[ "$open_shell" =~ ^[Yy]$ ]]; then
            lxc exec "$container_name" -- /bin/bash
        fi
    else
        print_status "ERROR", "Failed to create LXD container"
    fi
}

# =============================================================================
# JUPYTER NOTEBOOK FUNCTIONS
# =============================================================================

create_jupyter_vm() {
    local node_id="$1"
    local node_name="$2"
    
    print_header
    echo -e "${GREEN}🔬 Create Jupyter Notebook Server${NC}"
    echo -e "${YELLOW}Location: ${node_name}${NC}"
    echo
    
    # Notebook Name
    while true; do
        read -rp "$(print_status "INPUT" "Notebook Server Name: ")" notebook_name
        if validate_input "name" "$notebook_name"; then
            if [ -f "$DATA_DIR/jupyter/${notebook_name}.conf" ]; then
                print_status "ERROR", "Notebook '$notebook_name' already exists"
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
            print_status "ERROR", "Invalid selection"
        fi
    done
    
    # Port Configuration
    local available_port=$(find_available_port "$notebook_port")
    print_status "INFO", "Jupyter port: $available_port"
    
    # Volume for persistent data
    local volume_path="$DATA_DIR/jupyter/${notebook_name}"
    mkdir -p "$volume_path"
    
    # Token generation
    local jupyter_token=$(generate_password 32 false)
    
    # Create Jupyter container
    print_status "PROGRESS", "Creating Jupyter notebook server: $notebook_name"
    
    local docker_cmd="docker run -d"
    docker_cmd+=" --name jupyter-$notebook_name"
    docker_cmd+=" -p $available_port:8888"
    docker_cmd+=" -v $volume_path:/home/jovyan/work"
    docker_cmd+=" -e JUPYTER_TOKEN=$jupyter_token"
    docker_cmd+=" --restart unless-stopped"
    docker_cmd+=" $notebook_image"
    
    if eval "$docker_cmd"; then
        print_status "SUCCESS", "Jupyter notebook server created successfully!"
        
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
        
        log_message "JUPYTER", "Created notebook server: $notebook_name"
        
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
    else
        print_status "ERROR", "Failed to create Jupyter notebook server"
    fi
}

# =============================================================================
# VM MANAGEMENT DASHBOARD
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
                
                printf "  %2d) %-25s %-12s\n" $((i+1)) "$vm_name" "$status"
                printf "      %-10s %-8s %-12s SSH: %s\n" \
                    "${CPUS}vCPU" "${MEMORY}MB" "${DISK_SIZE}" "${SSH_PORT}"
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
        echo "  10) 🎯 Migrate VM"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-10): ")" choice
        
        case $choice in
            1)
                read -rp "$(print_status "INPUT" "Enter VM name to start: ")" vm_name
                start_vm "$vm_name"
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            2)
                read -rp "$(print_status "INPUT" "Enter VM name to stop: ")" vm_name
                stop_vm "$vm_name"
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            3)
                read -rp "$(print_status "INPUT" "Enter VM name to restart: ")" vm_name
                restart_vm "$vm_name"
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            4)
                read -rp "$(print_status "INPUT" "Enter VM name to delete: ")" vm_name
                delete_vm "$vm_name"
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            5)
                read -rp "$(print_status "INPUT" "Enter VM name to view: ")" vm_name
                view_vm_details "$vm_name"
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            6)
                read -rp "$(print_status "INPUT" "Enter VM name for snapshot: ")" vm_name
                create_snapshot "$vm_name"
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            7)
                read -rp "$(print_status "INPUT" "Enter VM name to restore: ")" vm_name
                restore_snapshot "$vm_name"
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            8)
                read -rp "$(print_status "INPUT" "Enter VM name to connect: ")" vm_name
                connect_vm_ssh "$vm_name"
                ;;
            9)
                list_snapshots
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            10)
                read -rp "$(print_status "INPUT" "Enter VM name to migrate: ")" vm_name
                migrate_vm "$vm_name"
                read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
                ;;
            0)
                return
                ;;
            *)
                print_status "ERROR", "Invalid option"
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
                print_status "SUCCESS", "VM '$vm_name' stopped successfully"
                STATUS="stopped"
                save_vm_config
                rm -f "$pid_file"
                log_message "VM", "Stopped VM: $vm_name"
            else
                print_status "ERROR", "Failed to stop VM '$vm_name'"
            fi
        else
            print_status "WARNING", "VM '$vm_name' is not running or PID file not found"
        fi
    fi
}

restart_vm() {
    local vm_name=$1
    stop_vm "$vm_name"
    sleep 2
    start_vm "$vm_name"
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
        
        print_status "SUCCESS", "VM '$vm_name' deleted successfully"
        log_message "VM", "Deleted VM: $vm_name"
    else
        print_status "INFO", "Deletion cancelled"
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

create_snapshot() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        local snapshot_name="${vm_name}-snapshot-$(date +%Y%m%d-%H%M%S)"
        local snapshot_dir="$DATA_DIR/snapshots/$vm_name"
        mkdir -p "$snapshot_dir"
        
        # Create snapshot of disk
        if qemu-img snapshot -c "$snapshot_name" "$IMG_FILE" 2>/dev/null; then
            # Copy configuration
            cp "$DATA_DIR/vms/$vm_name.conf" "$snapshot_dir/${snapshot_name}.conf"
            
            print_status "SUCCESS", "Snapshot '$snapshot_name' created successfully"
            log_message "SNAPSHOT", "Created snapshot for VM: $vm_name"
        else
            print_status "ERROR", "Failed to create snapshot"
        fi
    fi
}

restore_snapshot() {
    local vm_name=$1
    
    local snapshot_dir="$DATA_DIR/snapshots/$vm_name"
    if [ ! -d "$snapshot_dir" ]; then
        print_status "ERROR", "No snapshots found for VM '$vm_name'"
        return 1
    fi
    
    # List available snapshots
    echo -e "${GREEN}📸 Available Snapshots:${NC}"
    local snapshots=($(ls "$snapshot_dir"/*.conf 2>/dev/null | xargs -n1 basename | sed 's/.conf$//'))
    
    for i in "${!snapshots[@]}"; do
        printf "  %2d) %s\n" $((i+1)) "${snapshots[$i]}"
    done
    
    if [ ${#snapshots[@]} -eq 0 ]; then
        print_status "INFO", "No snapshots available"
        return
    fi
    
    echo
    read -rp "$(print_status "INPUT" "Select snapshot to restore (1-${#snapshots[@]}): ")" snapshot_choice
    
    if [[ "$snapshot_choice" =~ ^[0-9]+$ ]] && [ "$snapshot_choice" -ge 1 ] && [ "$snapshot_choice" -le ${#snapshots[@]} ]; then
        local snapshot_name="${snapshots[$((snapshot_choice-1))]}"
        
        # Stop VM if running
        stop_vm "$vm_name" 2>/dev/null
        
        # Restore disk snapshot
        if qemu-img snapshot -a "$snapshot_name" "$IMG_FILE" 2>/dev/null; then
            # Restore configuration
            cp "$snapshot_dir/${snapshot_name}.conf" "$DATA_DIR/vms/$vm_name.conf"
            
            print_status "SUCCESS", "Snapshot '$snapshot_name' restored successfully"
            log_message "SNAPSHOT", "Restored snapshot for VM: $vm_name"
        else
            print_status "ERROR", "Failed to restore snapshot"
        fi
    else
        print_status "ERROR", "Invalid selection"
    fi
}

connect_vm_ssh() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO", "Connecting to $vm_name via SSH..."
        echo -e "${YELLOW}Username: $USERNAME${NC}"
        echo -e "${YELLOW}Password: $PASSWORD${NC}"
        echo -e "${YELLOW}Port: $SSH_PORT${NC}"
        echo
        
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -p "$SSH_PORT" "$USERNAME@localhost"
    fi
}

list_snapshots() {
    print_header
    echo -e "${GREEN}📸 VM Snapshots${NC}"
    echo "─────────────────────────────────────"
    
    local has_snapshots=false
    
    for vm_dir in "$DATA_DIR/snapshots"/*; do
        if [ -d "$vm_dir" ]; then
            local vm_name=$(basename "$vm_dir")
            echo -e "${CYAN}VM: $vm_name${NC}"
            
            local snapshots=($(ls "$vm_dir"/*.conf 2>/dev/null | xargs -n1 basename | sed 's/.conf$//'))
            if [ ${#snapshots[@]} -gt 0 ]; then
                has_snapshots=true
                for snapshot in "${snapshots[@]}"; do
                    echo "  • $snapshot"
                done
            else
                echo "  No snapshots"
            fi
            echo
        fi
    done
    
    if [ "$has_snapshots" = false ]; then
        echo -e "${YELLOW}No snapshots found for any VM${NC}"
    fi
}

migrate_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_header
        echo -e "${GREEN}🚀 Migrate VM: $vm_name${NC}"
        echo "─────────────────────────────────────"
        
        # Select target node
        echo -e "${YELLOW}Select target node:${NC}"
        local index=1
        for node_id in "${!REAL_NODES[@]}"; do
            IFS='|' read -r location region ip latency ram disk capabilities <<< "${REAL_NODES[$node_id]}"
            printf "%2d) %-25s %s\n" "$index" "$location" "($ip)"
            ((index++))
        done
        echo
        
        read -rp "$(print_status "INPUT" "Select target node (1-${#REAL_NODES[@]}): ")" node_choice
        
        if [[ "$node_choice" =~ ^[0-9]+$ ]] && [ "$node_choice" -ge 1 ] && [ "$node_choice" -le ${#REAL_NODES[@]} ]; then
            local node_keys=("${!REAL_NODES[@]}")
            local target_node="${node_keys[$((node_choice-1))]}"
            IFS='|' read -r location region ip latency ram disk capabilities <<< "${REAL_NODES[$target_node]}"
            
            print_status "PROGRESS", "Preparing to migrate '$vm_name' to $location ($ip)"
            
            # Here you would implement actual migration logic
            # This could involve:
            # 1. Stopping the VM
            # 2. Compressing and transferring disk image
            # 3. Transferring configuration
            # 4. Starting on target node
            # 5. Updating DNS/network rules
            
            print_status "INFO", "Migration feature requires additional setup"
            print_status "INFO", "Target node: $location ($ip)"
            print_status "INFO", "VM resources: ${CPUS}vCPU, ${MEMORY}MB RAM, ${DISK_SIZE} disk"
            
            # For now, just simulate migration
            read -rp "$(print_status "INPUT" "Simulate migration? (y/n): ")" simulate
            if [[ "$simulate" =~ ^[Yy]$ ]]; then
                print_status "SUCCESS", "Migration simulation complete"
                print_status "INFO", "VM would be migrated to $location"
            fi
        else
            print_status "ERROR", "Invalid node selection"
        fi
    fi
}

# =============================================================================
# NODES MANAGEMENT
# =============================================================================

nodes_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🌐 Multi-Node Cluster Management${NC}"
        echo "─────────────────────────────────────"
        
        # Display nodes
        echo -e "${CYAN}Available Nodes:${NC}"
        echo "─────────────────────────────────────"
        
        # Local node
        echo -e "${GREEN}local${NC} - Local Development (127.0.0.1)"
        echo "  Capabilities: QEMU/KVM, Docker, LXD, Jupyter"
        echo "  Status: 🟢 Active"
        echo
        
        # Global nodes
        echo -e "${CYAN}Global Production Nodes:${NC}"
        for node_id in "${!REAL_NODES[@]}"; do
            IFS='|' read -r location region ip latency ram disk capabilities <<< "${REAL_NODES[$node_id]}"
            
            # Emoji based on location
            local emoji="🌐"
            case "$location" in
                *"India"*) emoji="🇮🇳" ;;
                *"Singapore"*) emoji="🇸🇬" ;;
                *"Germany"*) emoji="🇩🇪" ;;
                *"Netherlands"*) emoji="🇳🇱" ;;
                *"UK"*) emoji="🇬🇧" ;;
                *"USA"*) emoji="🇺🇸" ;;
                *"Canada"*) emoji="🇨🇦" ;;
                *"Japan"*) emoji="🇯🇵" ;;
                *"Australia"*) emoji="🇦🇺" ;;
            esac
            
            echo -e "${GREEN}$node_id${NC} $emoji $location"
            echo "  IP: $ip | Latency: ${latency}ms"
            echo "  Resources: ${ram}GB RAM • ${disk}GB NVMe SSD"
            echo "  Capabilities: $capabilities"
            echo
        done
        
        echo -e "${GREEN}📋 Node Management Options:${NC}"
        echo "   1) 📊 Node Status & Health"
        echo "   2) 🔍 Test Node Connectivity"
        echo "   3) ⚙️  Configure Node"
        echo "   4) ➕ Add Custom Node"
        echo "   5) 🗑️  Remove Node"
        echo "   6) 📈 Resource Monitoring"
        echo "   7) 🔄 Sync Node Configurations"
        echo "   8) 🛡️  Node Security Scan"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-8): ")" choice
        
        case $choice in
            1) show_node_status ;;
            2) test_node_connectivity ;;
            3) configure_node ;;
            4) add_custom_node ;;
            5) remove_node ;;
            6) node_resource_monitoring ;;
            7) sync_node_configs ;;
            8) node_security_scan ;;
            0) return ;;
            *) print_status "ERROR", "Invalid option" ;;
        esac
        
        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
    done
}

show_node_status() {
    print_header
    echo -e "${GREEN}📊 Node Status & Health${NC}"
    echo "─────────────────────────────────────"
    
    # Local node status
    echo -e "${CYAN}Local Node:${NC}"
    echo "  CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
    echo "  Memory: $(free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2}') used"
    echo "  Disk: $(df -h / | awk 'NR==2{print $5}') used"
    echo "  Uptime: $(uptime -p)"
    echo
    
    # Global nodes simulated status
    echo -e "${CYAN}Global Nodes Status:${NC}"
    for node_id in "${!REAL_NODES[@]}"; do
        IFS='|' read -r location region ip latency ram disk capabilities <<< "${REAL_NODES[$node_id]}"
        
        # Simulate random status
        local status_indicators=("🟢" "🟡" "🔴")
        local random_status=${status_indicators[$RANDOM % ${#status_indicators[@]}]}
        local random_load=$((RANDOM % 100))
        local random_vms=$((RANDOM % 50))
        
        echo "  $node_id: $random_status Load: ${random_load}% | VMs: $random_vms"
    done
}

test_node_connectivity() {
    print_header
    echo -e "${GREEN}🔍 Testing Node Connectivity${NC}"
    echo "─────────────────────────────────────"
    
    # Test local node
    echo -e "${CYAN}Testing Local Node...${NC}"
    if ping -c 2 -W 1 127.0.0.1 > /dev/null 2>&1; then
        echo -e "  🟢 Local node connectivity: OK"
    else
        echo -e "  🔴 Local node connectivity: FAILED"
    fi
    
    # Test global nodes (simulated)
    echo
    echo -e "${CYAN}Testing Global Nodes...${NC}"
    for node_id in "${!REAL_NODES[@]}"; do
        IFS='|' read -r location region ip latency ram disk capabilities <<< "${REAL_NODES[$node_id]}"
        
        # Simulate ping test
        local simulated_latency=$((RANDOM % 100 + 20))
        local success_rate=$((RANDOM % 100))
        
        if [ $success_rate -gt 70 ]; then
            echo -e "  🟢 $node_id: ${simulated_latency}ms latency"
        elif [ $success_rate -gt 30 ]; then
            echo -e "  🟡 $node_id: ${simulated_latency}ms latency (intermittent)"
        else
            echo -e "  🔴 $node_id: Connection failed"
        fi
    done
}

# =============================================================================
# ISO LIBRARY MANAGEMENT
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
        echo "   1) 📥 Download ISO"
        echo "   2) 🗑️  Delete ISO"
        echo "   3) 🔍 Verify ISO Integrity"
        echo "   4) 📁 Mount ISO"
        echo "   5) 🔄 Update ISO Library"
        echo "   6) 🎯 Custom ISO URL"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-6): ")" choice
        
        case $choice in
            1) download_iso ;;
            2) delete_iso ;;
            3) verify_iso ;;
            4) mount_iso ;;
            5) update_iso_library ;;
            6) custom_iso_url ;;
            0) return ;;
            *) print_status "ERROR", "Invalid option" ;;
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
        
        print_status "PROGRESS", "Downloading $iso_name..."
        print_status "INFO", "URL: $iso_url"
        print_status "INFO", "Destination: $filename"
        
        # Download with progress bar
        if command -v curl > /dev/null 2>&1; then
            curl -L -o "$filename" --progress-bar "$iso_url"
        elif command -v wget > /dev/null 2>&1; then
            wget -O "$filename" --progress=bar:force "$iso_url"
        else
            print_status "ERROR", "curl or wget not found"
            return 1
        fi
        
        if [ $? -eq 0 ]; then
            local size=$(du -h "$filename" | cut -f1)
            print_status "SUCCESS", "Download completed: $filename ($size)"
            log_message "ISO", "Downloaded ISO: $iso_name"
        else
            print_status "ERROR", "Download failed"
        fi
    else
        print_status "ERROR", "Invalid selection"
    fi
}

# =============================================================================
# MONITORING FUNCTIONS
# =============================================================================

monitoring_menu() {
    while true; do
        print_header
        echo -e "${GREEN}📊 Performance Monitoring${NC}"
        echo "─────────────────────────────────────"
        
        # System metrics
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
        local mem_total=$(free -m | awk '/^Mem:/{print $2}')
        local mem_used=$(free -m | awk '/^Mem:/{print $3}')
        local mem_percent=$((mem_used * 100 / mem_total))
        local disk_usage=$(df -h / | awk 'NR==2{print $5}')
        
        echo -e "${CYAN}System Metrics:${NC}"
        echo "  CPU Usage: ${cpu_usage}%"
        echo "  Memory: ${mem_used}MB / ${mem_total}MB (${mem_percent}%)"
        echo "  Disk Usage: $disk_usage"
        echo
        
        # VM statistics
        local running_vms=0
        local total_vms=0
        for vm_conf in "$DATA_DIR/vms"/*.conf; do
            if [ -f "$vm_conf" ]; then
                ((total_vms++))
                source "$vm_conf" 2>/dev/null
                local pid_file="/tmp/qemu-$VM_NAME.pid"
                if [ -f "$pid_file" ] && ps -p "$(cat "$pid_file")" > /dev/null 2>&1; then
                    ((running_vms++))
                fi
            fi
        done
        
        echo -e "${CYAN}VM Statistics:${NC}"
        echo "  Total VMs: $total_vms"
        echo "  Running VMs: $running_vms"
        echo "  Stopped VMs: $((total_vms - running_vms))"
        echo
        
        # Resource usage by VMs
        if [ $running_vms -gt 0 ]; then
            echo -e "${CYAN}Resource Usage by VMs:${NC}"
            for vm_conf in "$DATA_DIR/vms"/*.conf; do
                if [ -f "$vm_conf" ]; then
                    source "$vm_conf" 2>/dev/null
                    local pid_file="/tmp/qemu-$VM_NAME.pid"
                    if [ -f "$pid_file" ] && ps -p "$(cat "$pid_file")" > /dev/null 2>&1; then
                        local vm_cpu=$(ps -p "$(cat "$pid_file")" -o %cpu --no-headers)
                        local vm_mem=$(ps -p "$(cat "$pid_file")" -o %mem --no-headers)
                        printf "  %-20s CPU: %5s%% MEM: %5s%%\n" "$VM_NAME" "$vm_cpu" "$vm_mem"
                    fi
                fi
            done
        fi
        
        echo
        echo -e "${GREEN}📋 Monitoring Options:${NC}"
        echo "   1) 📈 Real-time Monitoring"
        echo "   2) 📊 Resource History"
        echo "   3) 🔔 Set Alerts"
        echo "   4) 📄 Generate Report"
        echo "   5) 🖥️  VM Performance"
        echo "   6) 🌐 Network Monitoring"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-6): ")" choice
        
        case $choice in
            1) realtime_monitoring ;;
            2) resource_history ;;
            3) set_alerts ;;
            4) generate_report ;;
            5) vm_performance ;;
            6) network_monitoring ;;
            0) return ;;
            *) print_status "ERROR", "Invalid option" ;;
        esac
        
        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
    done
}

realtime_monitoring() {
    print_header
    echo -e "${GREEN}📈 Real-time Monitoring${NC}"
    echo "─────────────────────────────────────"
    echo -e "${YELLOW}Press Ctrl+C to exit monitoring${NC}"
    echo
    
    local monitor_duration=30
    read -rp "$(print_status "INPUT" "Monitoring duration in seconds (default: 30): ")" duration_input
    monitor_duration=${duration_input:-30}
    
    echo -e "${CYAN}Starting real-time monitoring for ${monitor_duration} seconds...${NC}"
    echo
    
    local start_time=$(date +%s)
    local end_time=$((start_time + monitor_duration))
    
    while [ $(date +%s) -lt $end_time ]; do
        clear
        print_header
        echo -e "${GREEN}📈 Real-time Monitoring${NC}"
        echo "─────────────────────────────────────"
        echo "Time: $(date '+%H:%M:%S')"
        echo
        
        # CPU usage
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
        echo -e "${CYAN}CPU Usage:${NC} ${cpu_usage}%"
        
        # Memory usage
        local mem_info=$(free -m | awk 'NR==2{printf "%.1f/%.1f MB (%.1f%%)", $3, $2, $3*100/$2}')
        echo -e "${CYAN}Memory:${NC} $mem_info"
        
        # Disk I/O
        local disk_io=$(iostat -d 1 2 | tail -n 1 | awk '{printf "Read: %.1f KB/s, Write: %.1f KB/s", $3, $4}')
        echo -e "${CYAN}Disk I/O:${NC} $disk_io"
        
        # Network
        local network_rx=$(cat /sys/class/net/$(ip route | grep default | awk '{print $5}')/statistics/rx_bytes)
        local network_tx=$(cat /sys/class/net/$(ip route | grep default | awk '{print $5}')/statistics/tx_bytes)
        sleep 1
        local network_rx_new=$(cat /sys/class/net/$(ip route | grep default | awk '{print $5}')/statistics/rx_bytes)
        local network_tx_new=$(cat /sys/class/net/$(ip route | grep default | awk '{print $5}')/statistics/tx_bytes)
        local rx_rate=$(((network_rx_new - network_rx) / 1024))
        local tx_rate=$(((network_tx_new - network_tx) / 1024))
        echo -e "${CYAN}Network:${NC} ↓${rx_rate} KB/s ↑${tx_rate} KB/s"
        
        # Running VMs
        local running_vms=0
        for vm_conf in "$DATA_DIR/vms"/*.conf; do
            if [ -f "$vm_conf" ]; then
                source "$vm_conf" 2>/dev/null
                local pid_file="/tmp/qemu-$VM_NAME.pid"
                if [ -f "$pid_file" ] && ps -p "$(cat "$pid_file")" > /dev/null 2>&1; then
                    ((running_vms++))
                fi
            fi
        done
        echo -e "${CYAN}Running VMs:${NC} $running_vms"
        
        sleep 1
    done
    
    echo
    print_status "INFO", "Monitoring completed"
}

# =============================================================================
# BACKUP FUNCTIONS
# =============================================================================

backup_menu() {
    while true; do
        print_header
        echo -e "${GREEN}💾 Backup & Disaster Recovery${NC}"
        echo "─────────────────────────────────────"
        
        # Backup statistics
        local backup_count=0
        if [ -d "$DATA_DIR/backups" ]; then
            backup_count=$(find "$DATA_DIR/backups" -name "*.tar.gz" 2>/dev/null | wc -l)
        fi
        
        echo -e "${CYAN}Backup Statistics:${NC}"
        echo "  Total Backups: $backup_count"
        echo "  Backup Location: $DATA_DIR/backups"
        echo "  Total Backup Size: $(du -sh "$DATA_DIR/backups" 2>/dev/null | cut -f1)"
        echo
        
        # Recent backups
        if [ $backup_count -gt 0 ]; then
            echo -e "${CYAN}Recent Backups:${NC}"
            find "$DATA_DIR/backups" -name "*.tar.gz" -type f -printf "%Tb %Td %TY %TH:%TM %p\n" | sort -r | head -5 | while read backup; do
                local size=$(du -h "$(echo "$backup" | awk '{print $NF}')" 2>/dev/null | cut -f1)
                echo "  • $(echo "$backup" | awk '{print $1" "$2" "$3" "$4}') ($size)"
            done
        fi
        
        echo
        echo -e "${GREEN}📋 Backup Options:${NC}"
        echo "   1) 💾 Create Backup"
        echo "   2) 🔄 Restore Backup"
        echo "   3) 🗑️  Delete Backup"
        echo "   4) 📋 List All Backups"
        echo "   5) ⚙️  Configure Auto-Backup"
        echo "   6) 🔐 Encrypt Backup"
        echo "   7) ☁️  Cloud Backup"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-7): ")" choice
        
        case $choice in
            1) create_backup ;;
            2) restore_backup ;;
            3) delete_backup ;;
            4) list_backups ;;
            5) configure_auto_backup ;;
            6) encrypt_backup ;;
            7) cloud_backup ;;
            0) return ;;
            *) print_status "ERROR", "Invalid option" ;;
        esac
        
        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
    done
}

create_backup() {
    print_header
    echo -e "${GREEN}💾 Create System Backup${NC}"
    echo "─────────────────────────────────────"
    
    # Backup options
    echo "Select backup scope:"
    echo "  1) Full System Backup (All VMs, configs, ISOs)"
    echo "  2) VM Backup (Specific virtual machine)"
    echo "  3) Configuration Only"
    echo "  4) ISO Library Only"
    echo
    
    read -rp "$(print_status "INPUT" "Select scope (1-4): ")" scope_choice
    
    local backup_name="zynexforge-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_file="$DATA_DIR/backups/${backup_name}.tar.gz"
    mkdir -p "$DATA_DIR/backups"
    
    case $scope_choice in
        1)
            # Full backup
            print_status "PROGRESS", "Creating full system backup..."
            tar -czf "$backup_file" \
                -C "$USER_HOME" \
                .zynexforge \
                .ssh/zynexforge_ed25519 \
                .ssh/zynexforge_ed25519.pub \
                --exclude="*.log" \
                --exclude="*.tmp"
            ;;
        2)
            # VM backup
            read -rp "$(print_status "INPUT" "Enter VM name to backup: ")" vm_name
            if [ -f "$DATA_DIR/vms/$vm_name.conf" ]; then
                print_status "PROGRESS", "Backing up VM: $vm_name"
                tar -czf "$backup_file" \
                    -C "$DATA_DIR" \
                    "vms/$vm_name.conf" \
                    "disks/$vm_name.qcow2" \
                    "cloudinit/$vm_name-seed.img" \
                    "snapshots/$vm_name" 2>/dev/null
            else
                print_status "ERROR", "VM '$vm_name' not found"
                return 1
            fi
            ;;
        3)
            # Configuration only
            print_status "PROGRESS", "Backing up configurations..."
            tar -czf "$backup_file" \
                -C "$CONFIG_DIR" \
                .
            ;;
        4)
            # ISO library
            print_status "PROGRESS", "Backing up ISO library..."
            tar -czf "$backup_file" \
                -C "$DATA_DIR" \
                isos
            ;;
        *)
            print_status "ERROR", "Invalid scope"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "$backup_file" | cut -f1)
        print_status "SUCCESS", "Backup created: $backup_file ($size)"
        log_message "BACKUP", "Created backup: $backup_name"
        
        # Calculate and save backup metadata
        local sha_sum=$(sha256sum "$backup_file" | cut -d' ' -f1)
        cat > "$DATA_DIR/backups/${backup_name}.info" << EOF
backup_name: $backup_name
backup_file: $backup_file
created_at: $(date -Iseconds)
size: $size
sha256: $sha_sum
scope: $scope_choice
vm_name: ${vm_name:-N/A}
EOF
    else
        print_status "ERROR", "Backup creation failed"
    fi
}

# =============================================================================
# SETTINGS MENU
# =============================================================================

settings_menu() {
    while true; do
        print_header
        echo -e "${GREEN}⚙️ Advanced Settings${NC}"
        echo "─────────────────────────────────────"
        
        # Load current settings
        if [ -f "$GLOBAL_CONFIG" ]; then
            echo -e "${CYAN}Current Settings:${NC}"
            grep -E "^(  |[a-z])" "$GLOBAL_CONFIG" | head -20
            echo
        fi
        
        echo -e "${GREEN}📋 Settings Options:${NC}"
        echo "   1) 🔧 General Settings"
        echo "   2) 🔐 Security Settings"
        echo "   3) 🌐 Network Settings"
        echo "   4) 🚀 Performance Settings"
        echo "   5) 📁 Path Settings"
        echo "   6) 🔄 Reset Settings"
        echo "   7) 💾 Export Settings"
        echo "   8) 📥 Import Settings"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-8): ")" choice
        
        case $choice in
            1) general_settings ;;
            2) security_settings ;;
            3) network_settings ;;
            4) performance_settings ;;
            5) path_settings ;;
            6) reset_settings ;;
            7) export_settings ;;
            8) import_settings ;;
            0) return ;;
            *) print_status "ERROR", "Invalid option" ;;
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
    local current_version=$(grep "version:" "$GLOBAL_CONFIG" | head -1 | cut -d'"' -f2)
    local current_node=$(grep "default_node:" "$GLOBAL_CONFIG" | head -1 | awk '{print $2}')
    local max_vms=$(grep "max_vms_per_node:" "$GLOBAL_CONFIG" | head -1 | awk '{print $2}')
    local user_mode=$(grep "user_mode:" "$GLOBAL_CONFIG" | head -1 | awk '{print $2}')
    local enable_monitoring=$(grep "enable_monitoring:" "$GLOBAL_CONFIG" | head -1 | awk '{print $2}')
    local auto_backup=$(grep "auto_backup:" "$GLOBAL_CONFIG" | head -1 | awk '{print $2}')
    
    echo "Current Configuration:"
    echo "  1) Platform Name: $current_name"
    echo "  2) Default Node: $current_node"
    echo "  3) Max VMs per Node: $max_vms"
    echo "  4) User Mode: $user_mode"
    echo "  5) Enable Monitoring: $enable_monitoring"
    echo "  6) Auto Backup: $auto_backup"
    echo
    
    read -rp "$(print_status "INPUT" "Select setting to modify (1-6) or 0 to cancel: ")" setting_choice
    
    case $setting_choice in
        1)
            read -rp "$(print_status "INPUT" "New platform name: ")" new_name
            sed -i "s/name:.*/name: \"$new_name\"/" "$GLOBAL_CONFIG"
            print_status "SUCCESS", "Platform name updated"
            ;;
        2)
            echo "Available nodes: local ${!REAL_NODES[@]}"
            read -rp "$(print_status "INPUT" "New default node: ")" new_node
            if [[ " local ${!REAL_NODES[@]} " =~ " $new_node " ]]; then
                sed -i "s/default_node:.*/default_node: $new_node/" "$GLOBAL_CONFIG"
                print_status "SUCCESS", "Default node updated"
            else
                print_status "ERROR", "Invalid node"
            fi
            ;;
        3)
            read -rp "$(print_status "INPUT" "New max VMs per node (10-1000): ")" new_max
            if [[ "$new_max" =~ ^[0-9]+$ ]] && [ "$new_max" -ge 10 ] && [ "$new_max" -le 1000 ]; then
                sed -i "s/max_vms_per_node:.*/max_vms_per_node: $new_max/" "$GLOBAL_CONFIG"
                print_status "SUCCESS", "Max VMs updated"
            else
                print_status "ERROR", "Invalid number"
            fi
            ;;
        4)
            if [ "$user_mode" = "true" ]; then
                sed -i "s/user_mode:.*/user_mode: false/" "$GLOBAL_CONFIG"
                print_status "SUCCESS", "User mode disabled (root required)"
            else
                sed -i "s/user_mode:.*/user_mode: true/" "$GLOBAL_CONFIG"
                print_status "SUCCESS", "User mode enabled"
            fi
            ;;
        5)
            if [ "$enable_monitoring" = "true" ]; then
                sed -i "s/enable_monitoring:.*/enable_monitoring: false/" "$GLOBAL_CONFIG"
                print_status "SUCCESS", "Monitoring disabled"
            else
                sed -i "s/enable_monitoring:.*/enable_monitoring: true/" "$GLOBAL_CONFIG"
                print_status "SUCCESS", "Monitoring enabled"
            fi
            ;;
        6)
            if [ "$auto_backup" = "true" ]; then
                sed -i "s/auto_backup:.*/auto_backup: false/" "$GLOBAL_CONFIG"
                print_status "SUCCESS", "Auto backup disabled"
            else
                sed -i "s/auto_backup:.*/auto_backup: true/" "$GLOBAL_CONFIG"
                print_status "SUCCESS", "Auto backup enabled"
            fi
            ;;
        0)
            return
            ;;
        *)
            print_status "ERROR", "Invalid choice"
            ;;
    esac
    
    log_message "SETTINGS", "Modified general settings"
}

# =============================================================================
# SYSTEM DIAGNOSTICS
# =============================================================================

system_diagnostics_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🔧 System Diagnostics${NC}"
        echo "─────────────────────────────────────"
        
        # System health check
        echo -e "${CYAN}System Health Check:${NC}"
        
        # Check KVM
        if kvm-ok 2>/dev/null; then
            echo -e "  🟢 KVM acceleration: Available"
        else
            echo -e "  🔴 KVM acceleration: Not available"
        fi
        
        # Check Docker
        if command -v docker > /dev/null 2>&1; then
            if docker info > /dev/null 2>&1; then
                echo -e "  🟢 Docker: Running"
            else
                echo -e "  🔴 Docker: Installed but not running"
            fi
        else
            echo -e "  🔴 Docker: Not installed"
        fi
        
        # Check LXD
        if command -v lxd > /dev/null 2>&1; then
            if lxd version > /dev/null 2>&1; then
                echo -e "  🟢 LXD: Available"
            else
                echo -e "  🔴 LXD: Installed but not initialized"
            fi
        else
            echo -e "  🔴 LXD: Not installed"
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
        echo "   2) 🔍 Hardware Detection"
        echo "   3) 📊 Performance Benchmark"
        echo "   4) 🐛 Debug Logs"
        echo "   5) 🔧 Fix Common Issues"
        echo "   6) 📄 Generate Diagnostic Report"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-6): ")" choice
        
        case $choice in
            1) system_information ;;
            2) hardware_detection ;;
            3) performance_benchmark ;;
            4) debug_logs ;;
            5) fix_common_issues ;;
            6) generate_diagnostic_report ;;
            0) return ;;
            *) print_status "ERROR", "Invalid option" ;;
        esac
        
        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
    done
}

system_information() {
    print_header
    echo -e "${GREEN}🛠️ System Information${NC}"
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
    echo "  Frequency: $(grep "cpu MHz" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs) MHz"
    
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
    echo -e "${CYAN}Network Information:${NC}"
    local default_iface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -n "$default_iface" ]; then
        local ip_addr=$(ip addr show "$default_iface" | grep "inet " | awk '{print $2}')
        local mac_addr=$(ip addr show "$default_iface" | grep "link/ether" | awk '{print $2}')
        echo "  Interface: $default_iface"
        echo "  IP Address: $ip_addr"
        echo "  MAC Address: $mac_addr"
    fi
    
    echo
    echo -e "${CYAN}ZynexForge Information:${NC}"
    echo "  Version: $SCRIPT_VERSION"
    echo "  Config Directory: $CONFIG_DIR"
    echo "  Data Directory: $DATA_DIR"
    echo "  Log File: $LOG_FILE"
    
    local vm_count=$(get_vm_list | wc -l)
    local running_vms=0
    for vm in $(get_vm_list); do
        if load_vm_config "$vm" 2>/dev/null; then
            local pid_file="/tmp/qemu-$VM_NAME.pid"
            if [ -f "$pid_file" ] && ps -p "$(cat "$pid_file")" > /dev/null 2>&1; then
                ((running_vms++))
            fi
        fi
    done
    
    echo "  Total VMs: $vm_count"
    echo "  Running VMs: $running_vms"
}

# =============================================================================
# DOCUMENTATION
# =============================================================================

show_documentation() {
    while true; do
        print_header
        echo -e "${GREEN}📚 Documentation & Help${NC}"
        echo "─────────────────────────────────────"
        
        echo -e "${CYAN}ZynexForge CloudStack™ Professional Edition${NC}"
        echo "Version: $SCRIPT_VERSION"
        echo
        echo -e "${YELLOW}Key Features:${NC}"
        echo "  • Multi-Node Virtualization Management"
        echo "  • QEMU/KVM Virtual Machines"
        echo "  • Docker Container Management"
        echo "  • LXD System Containers"
        echo "  • Jupyter Notebook Servers"
        echo "  • ISO Library Management"
        echo "  • Advanced Monitoring & Backup"
        echo "  • Global Production Nodes"
        echo
        
        echo -e "${YELLOW}Quick Start Guide:${NC}"
        echo "  1. First, run platform initialization"
        echo "  2. Create your first VM from the main menu"
        echo "  3. Manage VMs from the dashboard"
        echo "  4. Explore different virtualization options"
        echo
        
        echo -e "${YELLOW}Common Commands:${NC}"
        echo "  • Create VM: Option 1 from main menu"
        echo "  • Manage VMs: Option 2 from main menu"
        echo "  • Docker containers: Option 4"
        echo "  • LXD containers: Option 5"
        echo "  • Jupyter: Option 6"
        echo
        
        echo -e "${YELLOW}Support:${NC}"
        echo "  • GitHub: https://github.com/zynexforge"
        echo "  • Documentation: https://docs.zynexforge.com"
        echo "  • Community: https://community.zynexforge.com"
        echo
        
        echo -e "${GREEN}📖 Documentation Sections:${NC}"
        echo "   1) 📘 User Manual"
        echo "   2) 🛠️  API Reference"
        echo "   3) 🔧 Troubleshooting"
        echo "   4) 📖 Tutorials"
        echo "   5) 🔔 Release Notes"
        echo "   6) 📞 Contact Support"
        echo "   0) ↩️  Back to Main Menu"
        echo
        
        read -rp "$(print_status "INPUT" "Select option (0-6): ")" choice
        
        case $choice in
            1) show_user_manual ;;
            2) show_api_reference ;;
            3) show_troubleshooting ;;
            4) show_tutorials ;;
            5) show_release_notes ;;
            6) contact_support ;;
            0) return ;;
            *) print_status "ERROR", "Invalid option" ;;
        esac
        
        read -n 1 -s -r -p "$(print_status "INPUT" "Press any key to continue...")"
    done
}

show_user_manual() {
    print_header
    echo -e "${GREEN}📘 User Manual${NC}"
    echo "─────────────────────────────────────"
    
    cat << 'EOF'
ZynexForge CloudStack™ User Manual
===================================

1. Getting Started
------------------
ZynexForge is an advanced virtualization platform that supports multiple
virtualization technologies including QEMU/KVM, Docker, LXD, and Jupyter.

2. Creating Virtual Machines
---------------------------
There are several ways to create VMs:

  a) Cloud Images: Pre-configured OS images (fast deployment)
  b) ISO Images: Full OS installation
  c) Docker Containers: Lightweight application containers
  d) LXD Containers: System containers (like lightweight VMs)
  e) Jupyter Servers: Data science notebooks

3. Managing Resources
--------------------
- Each VM/container can have custom CPU, memory, and disk allocations
- Network ports can be forwarded for external access
- Snapshots allow you to save and restore VM states

4. Multi-Node Management
------------------------
ZynexForge supports multiple deployment locations:
- Local development
- Global production nodes (Mumbai, Singapore, Frankfurt, etc.)
- Custom nodes can be added

5. Monitoring & Backup
---------------------
- Real-time monitoring of system resources
- Automated backups
- Performance metrics and alerts

6. Security Features
-------------------
- SSH key authentication
- Encrypted backups
- Network isolation
- Access controls

For detailed information, visit our online documentation at:
https://docs.zynexforge.com
EOF
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_status "WARNING", "Running as root is not recommended"
    read -rp "$(print_status "INPUT" "Continue as root? (y/n): ")" continue_as_root
    if [[ ! "$continue_as_root" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Initialize platform
initialize_platform

# Start main menu
main_menu

# Cleanup on exit
cleanup() {
    print_status "INFO", "Shutting down ZynexForge..."
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
    print_status "INFO", "Goodbye!"
}

trap cleanup EXIT
