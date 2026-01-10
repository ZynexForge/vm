#!/bin/bash
set -euo pipefail

# =============================================================================
# ZynexForge CloudStack™ Platform - Professional Edition
# Advanced Virtualization Management System
# Version: 3.0.0
# Made by FaaizXD
# =============================================================================

# Global Configuration
readonly USER_HOME="$HOME"
readonly CONFIG_DIR="$USER_HOME/.zynexforge"
readonly DATA_DIR="$USER_HOME/.zynexforge/data"
readonly LOG_FILE="$USER_HOME/.zynexforge/zynexforge.log"
readonly NODES_DB="$CONFIG_DIR/nodes.yml"
readonly GLOBAL_CONFIG="$CONFIG_DIR/config.yml"
readonly SSH_KEY_FILE="$USER_HOME/.ssh/zynexforge_ed25519"
readonly SCRIPT_VERSION="3.0.0"

# Color Definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m'

# ASCII Art
readonly ASCII_MAIN_ART=$(cat << 'EOF'
__________                           ___________                         
\____    /__.__. ____   ____ ___  __\_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /|    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    < |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \\___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/    \/             /_____/      \/ 
EOF
)

# OS Templates
declare -A OS_TEMPLATES=(
    ["ubuntu-24.04"]="Ubuntu 24.04 LTS|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ZynexForge123"
    ["ubuntu-22.04"]="Ubuntu 22.04 LTS|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ZynexForge123"
    ["debian-12"]="Debian 12|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|ZynexForge123"
    ["debian-11"]="Debian 11|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|ZynexForge123"
    ["centos-9"]="CentOS Stream 9|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|ZynexForge123"
    ["rocky-9"]="Rocky Linux 9|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|ZynexForge123"
    ["almalinux-9"]="AlmaLinux 9|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|ZynexForge123"
    ["fedora-40"]="Fedora 40|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|ZynexForge123"
    ["alpine-3.19"]="Alpine Linux 3.19|3.19|https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.0-x86_64.iso|alpine|alpine|ZynexForge123"
)

# ISO Images Library
declare -A ISO_LIBRARY=(
    ["ubuntu-24.04"]="Ubuntu 24.04 Desktop|https://releases.ubuntu.com/24.04/ubuntu-24.04-desktop-amd64.iso"
    ["ubuntu-24.04-server"]="Ubuntu 24.04 Server|https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso"
    ["ubuntu-22.04"]="Ubuntu 22.04 Server|https://releases.ubuntu.com/22.04/ubuntu-22.04-live-server-amd64.iso"
    ["debian-12"]="Debian 12|https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso"
    ["centos-9"]="CentOS Stream 9|https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-dvd1.iso"
    ["rocky-9"]="Rocky Linux 9|https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.3-x86_64-dvd.iso"
    ["kali-linux"]="Kali Linux|https://cdimage.kali.org/kali-2024.2/kali-linux-2024.2-installer-amd64.iso"
    ["arch-linux"]="Arch Linux|https://archlinux.c3sl.ufpr.br/iso/2024.07.01/archlinux-2024.07.01-x86_64.iso"
    ["proxmox-8"]="Proxmox VE 8|https://download.proxmox.com/iso/proxmox-ve_8.1-1.iso"
)

# =============================================================================
# CORE FUNCTIONS
# =============================================================================

print_header() {
    clear
    echo -e "${CYAN}"
    echo "$ASCII_MAIN_ART"
    echo -e "${NC}"
    echo -e "${YELLOW}⚡ ZynexForge CloudStack™ Professional Edition${NC}"
    echo -e "${WHITE}🔥 Made by FaaizXD | Version: ${SCRIPT_VERSION}${NC}"
    echo "=================================================================="
    echo
}

print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
        "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
        "INPUT") echo -e "${MAGENTA}[INPUT]${NC} $message" ;;
        *) echo "[$type] $message" ;;
    esac
}

validate_input() {
    local type=$1
    local value=$2
    
    case $type in
        "number")
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                print_status "ERROR" "Must be a number"
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
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 23 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "Must be a valid port number (23-65535)"
                return 1
            fi
            ;;
        "name")
            if ! [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                print_status "ERROR" "VM name can only contain letters, numbers, hyphens, and underscores"
                return 1
            fi
            ;;
    esac
    return 0
}

check_dependencies() {
    print_status "INFO" "Checking dependencies..."
    
    local missing_packages=()
    local required_tools=("qemu-system-x86_64" "qemu-img" "ssh-keygen")
    
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
            sudo apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils genisoimage openssh-client curl wget
        elif command -v dnf > /dev/null 2>&1; then
            print_status "INFO" "Installing packages on Fedora/RHEL..."
            sudo dnf install -y qemu-system-x86 qemu-img cloud-utils genisoimage openssh-clients curl wget
        else
            print_status "ERROR" "Unsupported package manager"
            print_status "INFO" "Please install manually: qemu-system-x86, qemu-utils, cloud-image-utils, genisoimage, curl, wget"
        fi
    else
        print_status "SUCCESS" "All required tools are available"
    fi
}

check_port_available() {
    local port=$1
    if command -v ss > /dev/null 2>&1; then
        if ss -tuln | grep -q ":${port} "; then
            return 1
        fi
    elif command -v netstat > /dev/null 2>&1; then
        if netstat -tuln | grep -q ":${port} "; then
            return 1
        fi
    fi
    return 0
}

find_available_port() {
    local base_port=${1:-22000}
    local max_port=23000
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
    tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c "$length"
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
             "$DATA_DIR/backups" \
             "$USER_HOME/zynexforge/templates/cloud" \
             "$USER_HOME/zynexforge/templates/iso" \
             "$USER_HOME/zynexforge/logs"
    
    # Create default config if not exists
    if [ ! -f "$GLOBAL_CONFIG" ]; then
        cat > "$GLOBAL_CONFIG" << 'EOF'
# ZynexForge Global Configuration
platform:
  name: "ZynexForge CloudStack™ Professional"
  version: "3.0.0"
  default_node: "local"
  ssh_base_port: 22000
  max_vms_per_node: 50
  user_mode: true

security:
  firewall_enabled: false
  default_ssh_user: "zynexuser"
  password_min_length: 8
  use_ssh_keys: true

paths:
  templates: "$USER_HOME/zynexforge/templates/cloud"
  isos: "$DATA_DIR/isos"
  vm_configs: "$DATA_DIR/vms"
  vm_disks: "$DATA_DIR/disks"
  logs: "$USER_HOME/zynexforge/logs"
EOF
        print_status "SUCCESS" "Global configuration created"
    fi
    
    # Create nodes database if not exists
    if [ ! -f "$NODES_DB" ]; then
        cat > "$NODES_DB" << EOF
# ZynexForge Nodes Database
nodes:
  local:
    node_id: "local"
    node_name: "Local Node"
    location_name: "Local, Server"
    provider: "Self-Hosted"
    public_ip: "127.0.0.1"
    capabilities: ["kvm", "qemu", "docker", "jupyter"]
    tags: ["production"]
    status: "active"
    created_at: "$(date -Iseconds)"
    user_mode: true
EOF
        print_status "SUCCESS" "Nodes database created"
    fi
    
    # Generate SSH key if not exists
    if [ ! -f "$SSH_KEY_FILE" ]; then
        print_status "INFO" "Generating SSH key..."
        ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q
        chmod 600 "$SSH_KEY_FILE"
        chmod 644 "${SSH_KEY_FILE}.pub"
        print_status "SUCCESS" "SSH key generated"
    fi
    
    # Check dependencies
    check_dependencies
    
    print_status "SUCCESS" "Platform initialized successfully!"
}

# =============================================================================
# MAIN MENU
# =============================================================================

main_menu() {
    while true; do
        print_header
        echo -e "${GREEN}Main Menu:${NC}"
        echo "  1) ⚡ Create New VM (KVM/QEMU)"
        echo "  2) 🖥️  VM Manager"
        echo "  3) 🐳 Docker VM Cloud"
        echo "  4) 🔬 Jupyter Cloud Lab"
        echo "  5) 📦 ISO Library"
        echo "  6) 🌐 Nodes Management"
        echo "  7) 📊 Monitoring"
        echo "  8) 💾 Backup & Restore"
        echo "  9) ⚙️  Settings"
        echo "  10) ℹ️  System Info"
        echo "  0) ❌ Exit"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case $choice in
            1) create_new_vm ;;
            2) vm_manager_menu ;;
            3) docker_vm_menu ;;
            4) jupyter_cloud_menu ;;
            5) iso_library_menu ;;
            6) nodes_menu ;;
            7) monitoring_menu ;;
            8) backup_menu ;;
            9) settings_menu ;;
            10) system_info_menu ;;
            0) 
                print_status "INFO" "Thank you for using ZynexForge CloudStack™!"
                exit 0
                ;;
            *) print_status "ERROR" "Invalid option"; sleep 1 ;;
        esac
    done
}

# =============================================================================
# VM CREATION WIZARD
# =============================================================================

create_new_vm() {
    print_header
    echo -e "${GREEN}🚀 Create New VM${NC}"
    echo
    
    # VM Name
    while true; do
        read -rp "$(print_status "INPUT" "VM Name: ")" vm_name
        if validate_input "name" "$vm_name"; then
            if [ -f "$DATA_DIR/vms/${vm_name}.conf" ]; then
                print_status "ERROR" "VM '$vm_name' already exists"
            else
                break
            fi
        fi
    done
    
    # OS Selection
    print_status "INFO" "Select OS Type:"
    echo "  1) Cloud Image (Fast Deployment)"
    echo "  2) ISO Image (Full Install)"
    echo
    read -rp "$(print_status "INPUT" "Choice (1-2): ")" os_type_choice
    
    local os_template=""
    local iso_path=""
    
    if [ "$os_type_choice" = "1" ]; then
        # Cloud Images
        print_status "INFO" "Select Cloud Image:"
        local i=1
        for os in "${!OS_TEMPLATES[@]}"; do
            echo "  $i) $os"
            ((i++))
        done
        echo
        
        read -rp "$(print_status "INPUT" "Choice: ")" os_choice
        local os_keys=("${!OS_TEMPLATES[@]}")
        os_template="${os_keys[$((os_choice-1))]}"
    else
        # ISO Images
        iso_library_menu "select"
        if [ -n "$SELECTED_ISO" ]; then
            iso_path="$SELECTED_ISO"
            os_template="custom-iso"
        else
            print_status "ERROR" "No ISO selected"
            return
        fi
    fi
    
    # Resources
    while true; do
        read -rp "$(print_status "INPUT" "CPU cores (1-8, default: 2): ")" cpu_cores
        cpu_cores=${cpu_cores:-2}
        if validate_input "number" "$cpu_cores" && [ "$cpu_cores" -ge 1 ] && [ "$cpu_cores" -le 8 ]; then
            break
        fi
        print_status "ERROR" "Invalid CPU cores (1-8)"
    done
    
    while true; do
        read -rp "$(print_status "INPUT" "RAM in MB (512-8192, default: 2048): ")" ram_mb
        ram_mb=${ram_mb:-2048}
        if validate_input "number" "$ram_mb" && [ "$ram_mb" -ge 512 ] && [ "$ram_mb" -le 8192 ]; then
            break
        fi
        print_status "ERROR" "Invalid RAM (512-8192 MB)"
    done
    
    while true; do
        read -rp "$(print_status "INPUT" "Disk size in GB (10-500, default: 50): ")" disk_gb
        disk_gb=${disk_gb:-50}
        if validate_input "number" "$disk_gb" && [ "$disk_gb" -ge 10 ] && [ "$disk_gb" -le 500 ]; then
            break
        fi
        print_status "ERROR" "Invalid disk size (10-500 GB)"
    done
    
    # SSH Port
    print_status "INFO" "Finding available SSH port..."
    ssh_port=$(find_available_port)
    print_status "INFO" "Using SSH port: $ssh_port"
    
    # Credentials
    while true; do
        read -rp "$(print_status "INPUT" "Username (default: zynexuser): ")" vm_user
        vm_user=${vm_user:-zynexuser}
        if [ -n "$vm_user" ]; then
            break
        fi
        print_status "ERROR" "Username cannot be empty"
    done
    
    read -rsp "$(print_status "INPUT" "Password (press Enter to generate): ")" vm_pass
    echo
    if [ -z "$vm_pass" ]; then
        vm_pass=$(generate_password 12)
        print_status "INFO" "Generated password: $vm_pass"
    fi
    
    # Network
    print_status "INFO" "Network Configuration:"
    echo "  1) NAT (User-mode networking)"
    echo "  2) Bridge (Requires setup)"
    echo
    read -rp "$(print_status "INPUT" "Choice (1-2, default: 1): ")" network_choice
    network_choice=${network_choice:-1}
    
    # Acceleration
    print_status "INFO" "Acceleration:"
    echo "  1) KVM (Hardware, if available)"
    echo "  2) TCG (Software)"
    echo
    read -rp "$(print_status "INPUT" "Choice (1-2, default: 1): ")" accel_choice
    accel_choice=${accel_choice:-1}
    acceleration=$([ "$accel_choice" = "1" ] && echo "kvm" || echo "tcg")
    
    # Confirm
    echo
    print_status "INFO" "Summary:"
    echo "  VM Name: $vm_name"
    echo "  OS: $os_template"
    echo "  CPU: ${cpu_cores} cores"
    echo "  RAM: ${ram_mb} MB"
    echo "  Disk: ${disk_gb} GB"
    echo "  SSH Port: $ssh_port"
    echo "  Username: $vm_user"
    echo "  Network: $([ "$network_choice" = "1" ] && echo "NAT" || echo "Bridge")"
    echo "  Acceleration: $acceleration"
    echo
    
    read -rp "$(print_status "INPUT" "Create VM? (y/N): ")" confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        create_vm "$vm_name" "$os_template" "$cpu_cores" "$ram_mb" "$disk_gb" "$ssh_port" "$vm_user" "$vm_pass" "$network_choice" "$acceleration" "$iso_path"
    else
        print_status "INFO" "VM creation cancelled"
    fi
}

create_vm() {
    local vm_name=$1 os_template=$2 cpu_cores=$3 ram_mb=$4 disk_gb=$5
    local ssh_port=$6 vm_user=$7 vm_pass=$8 network_choice=$9
    local acceleration=${10} iso_path=${11}
    
    print_status "INFO" "Creating VM '$vm_name'..."
    
    # Create directories
    mkdir -p "$DATA_DIR/vms" "$DATA_DIR/disks" "$DATA_DIR/cloudinit/$vm_name"
    
    # Disk path
    local disk_path="$DATA_DIR/disks/${vm_name}.qcow2"
    
    # Create disk
    if [ "$os_template" = "custom-iso" ] && [ -n "$iso_path" ]; then
        # For ISO install
        print_status "INFO" "Creating blank disk..."
        qemu-img create -f qcow2 "$disk_path" "${disk_gb}G"
    else
        # Cloud image
        local template_path="$USER_HOME/zynexforge/templates/cloud/${os_template}.qcow2"
        if [ -f "$template_path" ]; then
            print_status "INFO" "Using template: $os_template"
            cp "$template_path" "$disk_path"
            qemu-img resize "$disk_path" "${disk_gb}G" > /dev/null 2>&1
        else
            print_status "INFO" "Downloading template..."
            IFS='|' read -r os_name codename img_url default_hostname default_username default_password <<< "${OS_TEMPLATES[$os_template]}"
            wget -q --show-progress -O "$disk_path" "$img_url"
            qemu-img resize "$disk_path" "${disk_gb}G" > /dev/null 2>&1
        fi
    fi
    
    # Cloud-init for cloud images
    if [ "$os_template" != "custom-iso" ]; then
        print_status "INFO" "Creating cloud-init configuration..."
        
        local ssh_pub_key=""
        if [ -f "${SSH_KEY_FILE}.pub" ]; then
            ssh_pub_key=$(cat "${SSH_KEY_FILE}.pub")
        fi
        
        # user-data
        cat > "$DATA_DIR/cloudinit/$vm_name/user-data" << EOF
#cloud-config
hostname: $vm_name
manage_etc_hosts: true
users:
  - name: $vm_user
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: '$vm_pass'
    ssh_authorized_keys:
      - $ssh_pub_key
packages:
  - neofetch
  - htop
  - curl
  - wget
  - git
package_update: true
package_upgrade: true
runcmd:
  - echo "ZynexForge CloudStack™" > /etc/zynexforge-os.ascii
  - systemctl restart sshd
EOF
        
        # meta-data
        cat > "$DATA_DIR/cloudinit/$vm_name/meta-data" << EOF
instance-id: $vm_name
local-hostname: $vm_name
EOF
        
        # Create seed ISO
        if command -v cloud-localds > /dev/null 2>&1; then
            cloud-localds "$DATA_DIR/cloudinit/$vm_name/seed.iso" \
                "$DATA_DIR/cloudinit/$vm_name/user-data" \
                "$DATA_DIR/cloudinit/$vm_name/meta-data"
        else
            genisoimage -output "$DATA_DIR/cloudinit/$vm_name/seed.iso" \
                -volid cidata -joliet -rock \
                "$DATA_DIR/cloudinit/$vm_name/user-data" \
                "$DATA_DIR/cloudinit/$vm_name/meta-data"
        fi
    fi
    
    # Save VM configuration
    cat > "$DATA_DIR/vms/${vm_name}.conf" << EOF
VM_NAME="$vm_name"
OS_TYPE="$os_template"
CPU_CORES="$cpu_cores"
RAM_MB="$ram_mb"
DISK_GB="$disk_gb"
SSH_PORT="$ssh_port"
VM_USER="$vm_user"
VM_PASS="$vm_pass"
NETWORK_MODE="$network_choice"
ACCELERATION="$acceleration"
DISK_PATH="$disk_path"
ISO_PATH="$iso_path"
STATUS="stopped"
CREATED_AT="$(date -Iseconds)"
EOF
    
    print_status "SUCCESS" "VM '$vm_name' created successfully!"
    
    # Show access info
    echo
    print_status "INFO" "Access Information:"
    echo "  SSH: ssh -p $ssh_port $vm_user@localhost"
    echo "  Password: $vm_pass"
    echo
    
    read -rp "$(print_status "INPUT" "Start VM now? (y/N): ")" start_now
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
        start_vm "$vm_name"
    fi
    
    sleep 2
}

start_vm() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [ ! -f "$vm_config" ]; then
        print_status "ERROR" "VM '$vm_name' not found"
        return 1
    fi
    
    source "$vm_config"
    
    # Check if already running
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "ERROR" "VM '$vm_name' is already running"
            return 1
        fi
    fi
    
    # Check port
    if ! check_port_available "$SSH_PORT"; then
        print_status "ERROR" "Port $SSH_PORT is already in use!"
        return 1
    fi
    
    print_status "INFO" "Starting VM '$vm_name'..."
    
    # Build QEMU command
    local qemu_cmd=("qemu-system-x86_64")
    
    # Basic settings
    qemu_cmd+=("-name" "$vm_name" "-pidfile" "$pid_file" "-daemonize")
    
    # Acceleration
    if [ "$ACCELERATION" = "kvm" ] && [ -r "/dev/kvm" ]; then
        qemu_cmd+=("-enable-kvm" "-cpu" "host")
    else
        qemu_cmd+=("-cpu" "qemu64")
    fi
    
    # Resources
    qemu_cmd+=("-smp" "$CPU_CORES" "-m" "$RAM_MB")
    
    # Display
    qemu_cmd+=("-display" "none" "-vga" "none")
    
    # Network
    if [ "$NETWORK_MODE" = "1" ]; then
        qemu_cmd+=("-netdev" "user,id=net0,hostfwd=tcp::$SSH_PORT-:22")
        qemu_cmd+=("-device" "virtio-net-pci,netdev=net0")
    else
        qemu_cmd+=("-netdev" "bridge,id=net0,br=virbr0")
        qemu_cmd+=("-device" "virtio-net-pci,netdev=net0")
    fi
    
    # Storage
    qemu_cmd+=("-drive" "file=$DISK_PATH,if=virtio,format=qcow2")
    
    # Cloud-init or ISO
    if [ "$OS_TYPE" = "custom-iso" ] && [ -n "$ISO_PATH" ]; then
        qemu_cmd+=("-cdrom" "$ISO_PATH" "-boot" "order=d")
    else
        qemu_cmd+=("-drive" "file=$DATA_DIR/cloudinit/$vm_name/seed.iso,if=virtio,format=raw")
    fi
    
    # Start VM
    if "${qemu_cmd[@]}" > /dev/null 2>&1; then
        sed -i "s/STATUS=.*/STATUS=\"running\"/" "$vm_config"
        print_status "SUCCESS" "VM '$vm_name' started on port $SSH_PORT"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $VM_USER@localhost"
    else
        print_status "ERROR" "Failed to start VM"
        rm -f "$pid_file"
    fi
}

stop_vm() {
    local vm_name=$1
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null)
        if ps -p "$pid" > /dev/null 2>&1; then
            print_status "INFO" "Stopping VM '$vm_name'..."
            kill "$pid"
            sleep 2
            
            if ps -p "$pid" > /dev/null 2>&1; then
                kill -9 "$pid"
            fi
            
            rm -f "$pid_file"
            
            if [ -f "$vm_config" ]; then
                sed -i "s/STATUS=.*/STATUS=\"stopped\"/" "$vm_config"
            fi
            
            print_status "SUCCESS" "VM '$vm_name' stopped"
        else
            print_status "WARNING" "VM '$vm_name' is not running"
            rm -f "$pid_file"
        fi
    else
        print_status "WARNING" "VM '$vm_name' is not running"
    fi
}

# =============================================================================
# VM MANAGER
# =============================================================================

vm_manager_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🖥️  VM Manager${NC}"
        echo
        
        # List VMs
        local vms=()
        if [ -d "$DATA_DIR/vms" ]; then
            for conf in "$DATA_DIR/vms"/*.conf; do
                if [ -f "$conf" ]; then
                    source "$conf"
                    local status="Stopped"
                    local pid_file="/tmp/zynexforge_${VM_NAME}.pid"
                    if [ -f "$pid_file" ]; then
                        local pid
                        pid=$(cat "$pid_file" 2>/dev/null)
                        if ps -p "$pid" > /dev/null 2>&1; then
                            status="Running"
                        fi
                    fi
                    vms+=("$VM_NAME|$status|$CPU_CORES vCPU|$RAM_MB MB|$SSH_PORT")
                fi
            done
        fi
        
        if [ ${#vms[@]} -gt 0 ]; then
            echo "Virtual Machines:"
            echo "────────────────"
            for i in "${!vms[@]}"; do
                IFS='|' read -r name status cpu ram port <<< "${vms[$i]}"
                printf "  %2d) %-20s [%s] %s, %s, Port: %s\n" \
                    "$((i+1))" "$name" "$status" "$cpu" "$ram" "$port"
            done
            echo
        else
            print_status "INFO" "No VMs configured"
            echo
        fi
        
        echo "Options:"
        echo "  1) Start VM"
        echo "  2) Stop VM"
        echo "  3) Restart VM"
        echo "  4) Delete VM"
        echo "  5) Show VM Info"
        echo "  6) SSH Connect"
        echo "  7) Resize Disk"
        echo "  8) Clone VM"
        echo "  9) Back to Main"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case $choice in
            1)
                if [ ${#vms[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter VM number: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                        IFS='|' read -r name status cpu ram port <<< "${vms[$((vm_num-1))]}"
                        start_vm "$name"
                    fi
                fi
                ;;
            2)
                if [ ${#vms[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter VM number: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                        IFS='|' read -r name status cpu ram port <<< "${vms[$((vm_num-1))]}"
                        stop_vm "$name"
                    fi
                fi
                ;;
            3)
                if [ ${#vms[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter VM number: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                        IFS='|' read -r name status cpu ram port <<< "${vms[$((vm_num-1))]}"
                        stop_vm "$name"
                        sleep 2
                        start_vm "$name"
                    fi
                fi
                ;;
            4)
                if [ ${#vms[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter VM number: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                        IFS='|' read -r name status cpu ram port <<< "${vms[$((vm_num-1))]}"
                        delete_vm "$name"
                    fi
                fi
                ;;
            5)
                if [ ${#vms[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter VM number: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                        IFS='|' read -r name status cpu ram port <<< "${vms[$((vm_num-1))]}"
                        show_vm_info "$name"
                    fi
                fi
                ;;
            6)
                if [ ${#vms[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter VM number: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                        IFS='|' read -r name status cpu ram port <<< "${vms[$((vm_num-1))]}"
                        ssh_connect "$name"
                    fi
                fi
                ;;
            7)
                if [ ${#vms[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter VM number: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                        IFS='|' read -r name status cpu ram port <<< "${vms[$((vm_num-1))]}"
                        resize_disk "$name"
                    fi
                fi
                ;;
            8)
                if [ ${#vms[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter VM number: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
                        IFS='|' read -r name status cpu ram port <<< "${vms[$((vm_num-1))]}"
                        clone_vm "$name"
                    fi
                fi
                ;;
            9) return ;;
            *) print_status "ERROR" "Invalid option"; sleep 1 ;;
        esac
        
        [ "$choice" -ne 9 ] && sleep 1
    done
}

delete_vm() {
    local vm_name=$1
    
    print_status "WARNING" "This will permanently delete VM '$vm_name'!"
    read -rp "$(print_status "INPUT" "Are you sure? (y/N): ")" confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        stop_vm "$vm_name"
        
        # Remove files
        rm -f "$DATA_DIR/vms/${vm_name}.conf"
        rm -f "$DATA_DIR/disks/${vm_name}.qcow2"
        rm -rf "$DATA_DIR/cloudinit/$vm_name"
        rm -f "/tmp/zynexforge_${vm_name}.pid"
        
        print_status "SUCCESS" "VM '$vm_name' deleted"
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

show_vm_info() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [ ! -f "$vm_config" ]; then
        print_status "ERROR" "VM '$vm_name' not found"
        return 1
    fi
    
    print_header
    echo -e "${GREEN}🔍 VM Information: $vm_name${NC}"
    echo
    
    source "$vm_config"
    
    echo "Configuration:"
    echo "──────────────"
    echo "  Name: $VM_NAME"
    echo "  OS: $OS_TYPE"
    echo "  CPU: $CPU_CORES cores"
    echo "  RAM: $RAM_MB MB"
    echo "  Disk: $DISK_GB GB"
    echo "  SSH Port: $SSH_PORT"
    echo "  Username: $VM_USER"
    echo "  Status: $STATUS"
    echo "  Created: $CREATED_AT"
    echo
    
    # Disk info
    if [ -f "$DISK_PATH" ]; then
        echo "Disk Information:"
        echo "────────────────"
        qemu-img info "$DISK_PATH" 2>/dev/null | grep -E "(virtual size|disk size|format)" || true
    fi
    
    echo
    read -rp "$(print_status "INPUT" "Press Enter to continue...")"
}

ssh_connect() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [ ! -f "$vm_config" ]; then
        print_status "ERROR" "VM '$vm_name' not found"
        return 1
    fi
    
    source "$vm_config"
    
    # Check if running
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    if [ ! -f "$pid_file" ]; then
        print_status "ERROR" "VM '$vm_name' is not running"
        return 1
    fi
    
    print_status "INFO" "Connecting to $vm_name via SSH..."
    echo -e "${YELLOW}Password: $VM_PASS${NC}"
    echo
    
    ssh -o StrictHostKeyChecking=no -p "$SSH_PORT" "$VM_USER@localhost"
}

resize_disk() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [ ! -f "$vm_config" ]; then
        print_status "ERROR" "VM '$vm_name' not found"
        return 1
    fi
    
    source "$vm_config"
    
    print_header
    echo -e "${GREEN}💾 Resize Disk: $vm_name${NC}"
    echo
    
    echo "Current disk size: ${DISK_GB}GB"
    read -rp "$(print_status "INPUT" "New size in GB: ")" new_size
    
    if ! validate_input "number" "$new_size" || [ "$new_size" -lt "$DISK_GB" ]; then
        print_status "ERROR" "New size must be larger than current size"
        return 1
    fi
    
    stop_vm "$vm_name"
    
    print_status "INFO" "Resizing disk..."
    if qemu-img resize "$DISK_PATH" "${new_size}G"; then
        sed -i "s/DISK_GB=.*/DISK_GB=\"$new_size\"/" "$vm_config"
        print_status "SUCCESS" "Disk resized to ${new_size}GB"
    else
        print_status "ERROR" "Failed to resize disk"
    fi
    
    read -rp "$(print_status "INPUT" "Start VM? (y/N): ")" start_vm_choice
    if [[ "$start_vm_choice" =~ ^[Yy]$ ]]; then
        start_vm "$vm_name"
    fi
}

clone_vm() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [ ! -f "$vm_config" ]; then
        print_status "ERROR" "VM '$vm_name' not found"
        return 1
    fi
    
    print_header
    echo -e "${GREEN}📋 Clone VM: $vm_name${NC}"
    echo
    
    read -rp "$(print_status "INPUT" "New VM name: ")" new_vm_name
    
    if [ -f "$DATA_DIR/vms/${new_vm_name}.conf" ]; then
        print_status "ERROR" "VM '$new_vm_name' already exists"
        return 1
    fi
    
    # Stop source VM if running
    stop_vm "$vm_name"
    
    # Copy disk
    print_status "INFO" "Copying disk..."
    cp "$DATA_DIR/disks/${vm_name}.qcow2" "$DATA_DIR/disks/${new_vm_name}.qcow2"
    
    # Copy config
    cp "$vm_config" "$DATA_DIR/vms/${new_vm_name}.conf"
    
    # Update config
    sed -i "s/VM_NAME=.*/VM_NAME=\"$new_vm_name\"/" "$DATA_DIR/vms/${new_vm_name}.conf"
    sed -i "s/STATUS=.*/STATUS=\"stopped\"/" "$DATA_DIR/vms/${new_vm_name}.conf"
    sed -i "s/CREATED_AT=.*/CREATED_AT=\"$(date -Iseconds)\"/" "$DATA_DIR/vms/${new_vm_name}.conf"
    
    # Find new SSH port
    local new_port=$(find_available_port)
    sed -i "s/SSH_PORT=.*/SSH_PORT=\"$new_port\"/" "$DATA_DIR/vms/${new_vm_name}.conf"
    
    print_status "SUCCESS" "VM cloned to '$new_vm_name'"
    print_status "INFO" "New SSH port: $new_port"
    
    sleep 2
}

# =============================================================================
# DOCKER VM CLOUD
# =============================================================================

docker_vm_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🐳 Docker VM Cloud${NC}"
        echo
        
        # List Docker containers
        local containers=()
        if command -v docker > /dev/null 2>&1; then
            containers=($(docker ps -a --format "{{.Names}}|{{.Status}}|{{.Image}}" 2>/dev/null))
        fi
        
        if [ ${#containers[@]} -gt 0 ]; then
            echo "Docker Containers:"
            echo "──────────────────"
            for i in "${!containers[@]}"; do
                IFS='|' read -r name status image <<< "${containers[$i]}"
                printf "  %2d) %-20s [%s] %s\n" "$((i+1))" "$name" "$status" "$image"
            done
            echo
        else
            print_status "INFO" "No Docker containers"
            echo
        fi
        
        echo "Options:"
        echo "  1) Create Docker VM"
        echo "  2) Start Container"
        echo "  3) Stop Container"
        echo "  4) Console Access"
        echo "  5) Delete Container"
        echo "  6) Docker Stats"
        echo "  7) Back to Main"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case $choice in
            1) create_docker_vm ;;
            2)
                if [ ${#containers[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter container number: ")" cont_num
                    if [[ "$cont_num" =~ ^[0-9]+$ ]] && [ "$cont_num" -ge 1 ] && [ "$cont_num" -le ${#containers[@]} ]; then
                        IFS='|' read -r name status image <<< "${containers[$((cont_num-1))]}"
                        docker start "$name"
                    fi
                fi
                ;;
            3)
                if [ ${#containers[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter container number: ")" cont_num
                    if [[ "$cont_num" =~ ^[0-9]+$ ]] && [ "$cont_num" -ge 1 ] && [ "$cont_num" -le ${#containers[@]} ]; then
                        IFS='|' read -r name status image <<< "${containers[$((cont_num-1))]}"
                        docker stop "$name"
                    fi
                fi
                ;;
            4)
                if [ ${#containers[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter container number: ")" cont_num
                    if [[ "$cont_num" =~ ^[0-9]+$ ]] && [ "$cont_num" -ge 1 ] && [ "$cont_num" -le ${#containers[@]} ]; then
                        IFS='|' read -r name status image <<< "${containers[$((cont_num-1))]}"
                        docker exec -it "$name" /bin/bash || docker exec -it "$name" /bin/sh
                    fi
                fi
                ;;
            5)
                if [ ${#containers[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter container number: ")" cont_num
                    if [[ "$cont_num" =~ ^[0-9]+$ ]] && [ "$cont_num" -ge 1 ] && [ "$cont_num" -le ${#containers[@]} ]; then
                        IFS='|' read -r name status image <<< "${containers[$((cont_num-1))]}"
                        docker rm -f "$name"
                    fi
                fi
                ;;
            6)
                if command -v docker > /dev/null 2>&1; then
                    docker stats --no-stream
                fi
                read -rp "$(print_status "INPUT" "Press Enter to continue...")"
                ;;
            7) return ;;
            *) print_status "ERROR" "Invalid option"; sleep 1 ;;
        esac
        
        [ "$choice" -ne 7 ] && sleep 1
    done
}

create_docker_vm() {
    print_header
    echo -e "${GREEN}🐳 Create Docker VM${NC}"
    echo
    
    if ! command -v docker > /dev/null 2>&1; then
        print_status "ERROR" "Docker not installed"
        return 1
    fi
    
    read -rp "$(print_status "INPUT" "Container name: ")" container_name
    read -rp "$(print_status "INPUT" "Docker image (e.g., ubuntu:24.04): ")" docker_image
    
    print_status "INFO" "Available images: ubuntu:24.04, debian:12, alpine:latest, centos:stream9"
    
    # Resource limits
    read -rp "$(print_status "INPUT" "CPU limit (e.g., 1.5, optional): ")" cpu_limit
    read -rp "$(print_status "INPUT" "Memory limit (e.g., 512m, optional): ")" memory_limit
    
    # Port mappings
    read -rp "$(print_status "INPUT" "Port mappings (e.g., 8080:80, optional): ")" port_mappings
    
    # Build docker command
    local docker_cmd="docker run -d --name $container_name --restart unless-stopped"
    
    if [ -n "$cpu_limit" ]; then
        docker_cmd="$docker_cmd --cpus=$cpu_limit"
    fi
    
    if [ -n "$memory_limit" ]; then
        docker_cmd="$docker_cmd --memory=$memory_limit"
    fi
    
    if [ -n "$port_mappings" ]; then
        docker_cmd="$docker_cmd -p $port_mappings"
    fi
    
    docker_cmd="$docker_cmd $docker_image tail -f /dev/null"
    
    print_status "INFO" "Creating Docker VM..."
    
    if eval "$docker_cmd"; then
        print_status "SUCCESS" "Docker VM created"
        print_status "INFO" "Console: docker exec -it $container_name /bin/bash"
    else
        print_status "ERROR" "Failed to create Docker VM"
    fi
    
    sleep 2
}

# =============================================================================
# JUPYTER CLOUD LAB
# =============================================================================

jupyter_cloud_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🔬 Jupyter Cloud Lab${NC}"
        echo
        
        # List Jupyter instances
        local jupyter_instances=()
        if command -v docker > /dev/null 2>&1; then
            jupyter_instances=($(docker ps -a --filter "ancestor=jupyter" --format "{{.Names}}|{{.Status}}|{{.Ports}}" 2>/dev/null))
        fi
        
        if [ ${#jupyter_instances[@]} -gt 0 ]; then
            echo "Jupyter Instances:"
            echo "──────────────────"
            for i in "${!jupyter_instances[@]}"; do
                IFS='|' read -r name status ports <<< "${jupyter_instances[$i]}"
                printf "  %2d) %-20s [%s] %s\n" "$((i+1))" "$name" "$status" "$ports"
            done
            echo
        else
            print_status "INFO" "No Jupyter instances"
            echo
        fi
        
        echo "Options:"
        echo "  1) Create Jupyter Lab"
        echo "  2) Start Jupyter Lab"
        echo "  3) Stop Jupyter Lab"
        echo "  4) Show Jupyter URL"
        echo "  5) Delete Jupyter Lab"
        echo "  6) Back to Main"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case $choice in
            1) create_jupyter_lab ;;
            2)
                if [ ${#jupyter_instances[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter instance number: ")" inst_num
                    if [[ "$inst_num" =~ ^[0-9]+$ ]] && [ "$inst_num" -ge 1 ] && [ "$inst_num" -le ${#jupyter_instances[@]} ]; then
                        IFS='|' read -r name status ports <<< "${jupyter_instances[$((inst_num-1))]}"
                        docker start "$name"
                    fi
                fi
                ;;
            3)
                if [ ${#jupyter_instances[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter instance number: ")" inst_num
                    if [[ "$inst_num" =~ ^[0-9]+$ ]] && [ "$inst_num" -ge 1 ] && [ "$inst_num" -le ${#jupyter_instances[@]} ]; then
                        IFS='|' read -r name status ports <<< "${jupyter_instances[$((inst_num-1))]}"
                        docker stop "$name"
                    fi
                fi
                ;;
            4)
                if [ ${#jupyter_instances[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter instance number: ")" inst_num
                    if [[ "$inst_num" =~ ^[0-9]+$ ]] && [ "$inst_num" -ge 1 ] && [ "$inst_num" -le ${#jupyter_instances[@]} ]; then
                        IFS='|' read -r name status ports <<< "${jupyter_instances[$((inst_num-1))]}"
                        show_jupyter_url "$name"
                    fi
                fi
                ;;
            5)
                if [ ${#jupyter_instances[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter instance number: ")" inst_num
                    if [[ "$inst_num" =~ ^[0-9]+$ ]] && [ "$inst_num" -ge 1 ] && [ "$inst_num" -le ${#jupyter_instances[@]} ]; then
                        IFS='|' read -r name status ports <<< "${jupyter_instances[$((inst_num-1))]}"
                        docker rm -f "$name"
                    fi
                fi
                ;;
            6) return ;;
            *) print_status "ERROR" "Invalid option"; sleep 1 ;;
        esac
        
        [ "$choice" -ne 6 ] && sleep 1
    done
}

create_jupyter_lab() {
    print_header
    echo -e "${GREEN}🔬 Create Jupyter Lab${NC}"
    echo
    
    if ! command -v docker > /dev/null 2>&1; then
        print_status "ERROR" "Docker not installed"
        return 1
    fi
    
    read -rp "$(print_status "INPUT" "Jupyter Lab name: ")" jupyter_name
    
    # Find available port
    local jupyter_port=$(find_available_port 8888)
    print_status "INFO" "Using port: $jupyter_port"
    
    # Generate token
    local jupyter_token=$(openssl rand -hex 24 2>/dev/null || echo "$RANDOM$RANDOM$RANDOM")
    
    # Create volume
    docker volume create "${jupyter_name}_data" > /dev/null 2>&1
    
    print_status "INFO" "Creating Jupyter Lab..."
    
    if docker run -d \
        --name "$jupyter_name" \
        -p "$jupyter_port:8888" \
        -v "${jupyter_name}_data:/home/jovyan/work" \
        -e JUPYTER_TOKEN="$jupyter_token" \
        jupyter/datascience-notebook \
        start-notebook.sh --NotebookApp.token="$jupyter_token" > /dev/null 2>&1; then
        
        # Save config
        mkdir -p "$DATA_DIR/jupyter"
        cat > "$DATA_DIR/jupyter/${jupyter_name}.conf" << EOF
JUPYTER_NAME="$jupyter_name"
JUPYTER_PORT="$jupyter_port"
JUPYTER_TOKEN="$jupyter_token"
VOLUME_NAME="${jupyter_name}_data"
STATUS="running"
EOF
        
        print_status "SUCCESS" "Jupyter Lab created"
        echo
        print_status "INFO" "Access Information:"
        echo "  URL: http://localhost:$jupyter_port"
        echo "  Token: $jupyter_token"
        echo "  Direct URL: http://localhost:$jupyter_port/?token=$jupyter_token"
    else
        print_status "ERROR" "Failed to create Jupyter Lab"
    fi
    
    sleep 2
}

show_jupyter_url() {
    local jupyter_name=$1
    local jupyter_config="$DATA_DIR/jupyter/${jupyter_name}.conf"
    
    if [ ! -f "$jupyter_config" ]; then
        print_status "ERROR" "Jupyter Lab not found"
        return 1
    fi
    
    source "$jupyter_config"
    
    print_status "INFO" "Jupyter Lab Access:"
    echo "  URL: http://localhost:$JUPYTER_PORT"
    echo "  Token: $JUPYTER_TOKEN"
    echo "  Direct URL: http://localhost:$JUPYTER_PORT/?token=$JUPYTER_TOKEN"
    
    read -rp "$(print_status "INPUT" "Press Enter to continue...")"
}

# =============================================================================
# ISO LIBRARY
# =============================================================================

iso_library_menu() {
    local select_mode=${1:-""}
    
    while true; do
        print_header
        
        if [ "$select_mode" = "select" ]; then
            echo -e "${GREEN}📀 Select ISO Image${NC}"
        else
            echo -e "${GREEN}📀 ISO Library${NC}"
        fi
        echo
        
        # List ISO files
        local iso_files=()
        if [ -d "$DATA_DIR/isos" ]; then
            iso_files=($(find "$DATA_DIR/isos" -name "*.iso" -type f 2>/dev/null))
        fi
        
        if [ ${#iso_files[@]} -gt 0 ]; then
            echo "Available ISO Images:"
            echo "─────────────────────"
            for i in "${!iso_files[@]}"; do
                local iso_name
                iso_name=$(basename "${iso_files[$i]}")
                local iso_size
                iso_size=$(du -h "${iso_files[$i]}" | awk '{print $1}')
                printf "  %2d) %-30s (%s)\n" "$((i+1))" "$iso_name" "$iso_size"
            done
            echo
        else
            print_status "INFO" "No ISO images available"
            echo
        fi
        
        if [ "$select_mode" = "select" ]; then
            echo "Options:"
            echo "  1-${#iso_files[@]}) Select ISO"
            echo "  d) Download ISO"
            echo "  b) Back"
            echo
        else
            echo "Options:"
            echo "  1) Download ISO"
            echo "  2) Delete ISO"
            echo "  3) Back to Main"
            echo
        fi
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        if [ "$select_mode" = "select" ]; then
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#iso_files[@]} ]; then
                SELECTED_ISO="${iso_files[$((choice-1))]}"
                return 0
            elif [[ "$choice" =~ ^[Dd]$ ]]; then
                download_iso
                continue
            elif [[ "$choice" =~ ^[Bb]$ ]]; then
                SELECTED_ISO=""
                return 1
            else
                print_status "ERROR" "Invalid option"
                sleep 1
            fi
        else
            case $choice in
                1) download_iso ;;
                2)
                    if [ ${#iso_files[@]} -gt 0 ]; then
                        read -rp "$(print_status "INPUT" "Enter ISO number: ")" iso_num
                        if [[ "$iso_num" =~ ^[0-9]+$ ]] && [ "$iso_num" -ge 1 ] && [ "$iso_num" -le ${#iso_files[@]} ]; then
                            rm -f "${iso_files[$((iso_num-1))]}"
                            print_status "SUCCESS" "ISO deleted"
                        fi
                    fi
                    ;;
                3) return ;;
                *) print_status "ERROR" "Invalid option"; sleep 1 ;;
            esac
        fi
        
        [ "$choice" -ne 3 ] && [ "$choice" != "b" ] && sleep 1
    done
}

download_iso() {
    print_header
    echo -e "${GREEN}⬇️  Download ISO${NC}"
    echo
    
    echo "Available ISOs:"
    local i=1
    for iso in "${!ISO_LIBRARY[@]}"; do
        IFS='|' read -r iso_name iso_url <<< "${ISO_LIBRARY[$iso]}"
        echo "  $i) $iso_name"
        ((i++))
    done
    echo
    
    read -rp "$(print_status "INPUT" "Select ISO: ")" iso_choice
    
    if [[ "$iso_choice" =~ ^[0-9]+$ ]] && [ "$iso_choice" -ge 1 ] && [ "$iso_choice" -le ${#ISO_LIBRARY[@]} ]; then
        local iso_keys=("${!ISO_LIBRARY[@]}")
        local selected_key="${iso_keys[$((iso_choice-1))]}"
        IFS='|' read -r iso_name iso_url <<< "${ISO_LIBRARY[$selected_key]}"
        
        local output_file="$DATA_DIR/isos/${selected_key}.iso"
        mkdir -p "$DATA_DIR/isos"
        
        print_status "INFO" "Downloading $iso_name..."
        print_status "INFO" "URL: $iso_url"
        
        if command -v wget > /dev/null 2>&1; then
            wget --progress=bar:force -O "$output_file" "$iso_url"
        elif command -v curl > /dev/null 2>&1; then
            curl -L -o "$output_file" "$iso_url"
        else
            print_status "ERROR" "Neither wget nor curl available"
            return 1
        fi
        
        if [ $? -eq 0 ]; then
            print_status "SUCCESS" "ISO downloaded: $output_file"
        else
            print_status "ERROR" "Download failed"
        fi
    else
        print_status "ERROR" "Invalid selection"
    fi
    
    sleep 2
}

# =============================================================================
# NODES MANAGEMENT
# =============================================================================

nodes_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🌐 Nodes Management${NC}"
        echo
        
        echo "Options:"
        echo "  1) Add Node"
        echo "  2) List Nodes"
        echo "  3) Remove Node"
        echo "  4) Back to Main"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case $choice in
            1) add_node ;;
            2) list_nodes ;;
            3) remove_node ;;
            4) return ;;
            *) print_status "ERROR" "Invalid option"; sleep 1 ;;
        esac
    done
}

add_node() {
    print_header
    echo -e "${GREEN}➕ Add Node${NC}"
    echo
    
    read -rp "$(print_status "INPUT" "Node ID: ")" node_id
    read -rp "$(print_status "INPUT" "Node Name: ")" node_name
    read -rp "$(print_status "INPUT" "Location: ")" location
    read -rp "$(print_status "INPUT" "Public IP: ")" public_ip
    
    # Add to database
    if [ -f "$NODES_DB" ]; then
        cat >> "$NODES_DB" << EOF
  $node_id:
    node_id: "$node_id"
    node_name: "$node_name"
    location_name: "$location"
    public_ip: "$public_ip"
    status: "active"
    created_at: "$(date -Iseconds)"
EOF
        print_status "SUCCESS" "Node added"
    fi
    
    sleep 2
}

list_nodes() {
    print_header
    echo -e "${GREEN}📋 List Nodes${NC}"
    echo
    
    if [ -f "$NODES_DB" ]; then
        echo "Nodes:"
        echo "──────"
        while IFS= read -r line; do
            if [[ "$line" =~ ^\ \ ([a-zA-Z0-9_]+): ]]; then
                echo -n "  ${BASH_REMATCH[1]}: "
            elif [[ "$line" =~ \ \ node_name:\ (.*) ]]; then
                echo -n "${BASH_REMATCH[1]} "
            elif [[ "$line" =~ \ \ location_name:\ (.*) ]]; then
                echo "[${BASH_REMATCH[1]}]"
            fi
        done < "$NODES_DB"
    else
        print_status "INFO" "No nodes configured"
    fi
    
    echo
    read -rp "$(print_status "INPUT" "Press Enter to continue...")"
}

remove_node() {
    print_header
    echo -e "${GREEN}🗑️  Remove Node${NC}"
    echo
    
    read -rp "$(print_status "INPUT" "Node ID to remove: ")" node_id
    
    if [ "$node_id" = "local" ]; then
        print_status "ERROR" "Cannot remove local node"
        sleep 1
        return
    fi
    
    if [ -f "$NODES_DB" ]; then
        if grep -q "^  $node_id:" "$NODES_DB"; then
            # Simple removal
            local start_line
            start_line=$(grep -n "^  $node_id:" "$NODES_DB" | cut -d: -f1)
            if [ -n "$start_line" ]; then
                sed -i "${start_line},$((start_line+6))d" "$NODES_DB"
                print_status "SUCCESS" "Node removed"
            fi
        else
            print_status "ERROR" "Node not found"
        fi
    fi
    
    sleep 1
}

# =============================================================================
# MONITORING
# =============================================================================

monitoring_menu() {
    while true; do
        print_header
        echo -e "${GREEN}📊 Monitoring${NC}"
        echo
        
        echo "System Information:"
        echo "───────────────────"
        echo "  CPU: $(uptime | awk -F'load average:' '{print $2}')"
        echo "  Memory: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
        echo "  Disk: $(df -h / | awk 'NR==2 {print $4 " free of " $2}')"
        echo
        
        # VM status
        local running_vms=0
        local total_vms=0
        if [ -d "$DATA_DIR/vms" ]; then
            for conf in "$DATA_DIR/vms"/*.conf; do
                if [ -f "$conf" ]; then
                    ((total_vms++))
                    source "$conf"
                    local pid_file="/tmp/zynexforge_${VM_NAME}.pid"
                    if [ -f "$pid_file" ]; then
                        local pid
                        pid=$(cat "$pid_file" 2>/dev/null)
                        if ps -p "$pid" > /dev/null 2>&1; then
                            ((running_vms++))
                        fi
                    fi
                fi
            done
        fi
        
        echo "VM Status:"
        echo "──────────"
        echo "  Running: $running_vms"
        echo "  Stopped: $((total_vms - running_vms))"
        echo "  Total: $total_vms"
        echo
        
        echo "Options:"
        echo "  1) Show All VMs"
        echo "  2) Show System Stats"
        echo "  3) Back to Main"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case $choice in
            1)
                if [ $total_vms -gt 0 ]; then
                    echo "All VMs:"
                    echo "────────"
                    for conf in "$DATA_DIR/vms"/*.conf; do
                        source "$conf"
                        local status="Stopped"
                        local pid_file="/tmp/zynexforge_${VM_NAME}.pid"
                        if [ -f "$pid_file" ]; then
                            local pid
                            pid=$(cat "$pid_file" 2>/dev/null)
                            if ps -p "$pid" > /dev/null 2>&1; then
                                status="Running"
                            fi
                        fi
                        echo "  $VM_NAME: $status (Port: $SSH_PORT)"
                    done
                fi
                echo
                read -rp "$(print_status "INPUT" "Press Enter to continue...")"
                ;;
            2)
                echo "System Stats:"
                echo "─────────────"
                top -bn1 | head -20
                echo
                read -rp "$(print_status "INPUT" "Press Enter to continue...")"
                ;;
            3) return ;;
            *) print_status "ERROR" "Invalid option"; sleep 1 ;;
        esac
    done
}

# =============================================================================
# BACKUP & RESTORE
# =============================================================================

backup_menu() {
    while true; do
        print_header
        echo -e "${GREEN}💾 Backup & Restore${NC}"
        echo
        
        # List backups
        local backups=()
        if [ -d "$DATA_DIR/backups" ]; then
            backups=($(find "$DATA_DIR/backups" -name "*.tar.gz" -type f 2>/dev/null))
        fi
        
        if [ ${#backups[@]} -gt 0 ]; then
            echo "Available Backups:"
            echo "──────────────────"
            for i in "${!backups[@]}"; do
                local backup_name
                backup_name=$(basename "${backups[$i]}")
                local backup_size
                backup_size=$(du -h "${backups[$i]}" | awk '{print $1}')
                local backup_date
                backup_date=$(stat -c %y "${backups[$i]}" | cut -d' ' -f1)
                printf "  %2d) %-30s (%s, %s)\n" "$((i+1))" "$backup_name" "$backup_size" "$backup_date"
            done
            echo
        else
            print_status "INFO" "No backups available"
            echo
        fi
        
        echo "Options:"
        echo "  1) Backup VM"
        echo "  2) Restore VM"
        echo "  3) Delete Backup"
        echo "  4) Back to Main"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case $choice in
            1) backup_vm ;;
            2)
                if [ ${#backups[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter backup number: ")" backup_num
                    if [[ "$backup_num" =~ ^[0-9]+$ ]] && [ "$backup_num" -ge 1 ] && [ "$backup_num" -le ${#backups[@]} ]; then
                        restore_vm "${backups[$((backup_num-1))]}"
                    fi
                fi
                ;;
            3)
                if [ ${#backups[@]} -gt 0 ]; then
                    read -rp "$(print_status "INPUT" "Enter backup number: ")" backup_num
                    if [[ "$backup_num" =~ ^[0-9]+$ ]] && [ "$backup_num" -ge 1 ] && [ "$backup_num" -le ${#backups[@]} ]; then
                        rm -f "${backups[$((backup_num-1))]}"
                        print_status "SUCCESS" "Backup deleted"
                    fi
                fi
                ;;
            4) return ;;
            *) print_status "ERROR" "Invalid option"; sleep 1 ;;
        esac
        
        [ "$choice" -ne 4 ] && sleep 1
    done
}

backup_vm() {
    print_header
    echo -e "${GREEN}💾 Backup VM${NC}"
    echo
    
    local vms=()
    if [ -d "$DATA_DIR/vms" ]; then
        for conf in "$DATA_DIR/vms"/*.conf; do
            if [ -f "$conf" ]; then
                source "$conf"
                vms+=("$VM_NAME")
            fi
        done
    fi
    
    if [ ${#vms[@]} -eq 0 ]; then
        print_status "ERROR" "No VMs to backup"
        sleep 1
        return
    fi
    
    echo "Select VM to backup:"
    for i in "${!vms[@]}"; do
        echo "  $((i+1))) ${vms[$i]}"
    done
    echo
    
    read -rp "$(print_status "INPUT" "Enter VM number: ")" vm_num
    
    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le ${#vms[@]} ]; then
        local vm_name="${vms[$((vm_num-1))]}"
        local backup_dir="$DATA_DIR/backups"
        mkdir -p "$backup_dir"
        
        local backup_file="$backup_dir/${vm_name}_$(date +%Y%m%d_%H%M%S).tar.gz"
        
        print_status "INFO" "Creating backup of $vm_name..."
        stop_vm "$vm_name"
        
        tar -czf "$backup_file" \
            "$DATA_DIR/vms/${vm_name}.conf" \
            "$DATA_DIR/disks/${vm_name}.qcow2" \
            "$DATA_DIR/cloudinit/$vm_name" 2>/dev/null
        
        print_status "SUCCESS" "Backup created: $backup_file"
        
        read -rp "$(print_status "INPUT" "Start VM? (y/N): ")" start_choice
        if [[ "$start_choice" =~ ^[Yy]$ ]]; then
            start_vm "$vm_name"
        fi
    else
        print_status "ERROR" "Invalid selection"
    fi
    
    sleep 2
}

restore_vm() {
    local backup_file="$1"
    
    print_header
    echo -e "${GREEN}🔄 Restore VM${NC}"
    echo
    
    print_status "WARNING" "Restoring will overwrite existing VM!"
    read -rp "$(print_status "INPUT" "Continue? (y/N): ")" confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local temp_dir="/tmp/zynexforge_restore_$$"
        mkdir -p "$temp_dir"
        
        print_status "INFO" "Extracting backup..."
        tar -xzf "$backup_file" -C "$temp_dir"
        
        # Find VM name from config
        local config_file=$(find "$temp_dir" -name "*.conf" -type f | head -1)
        if [ -f "$config_file" ]; then
            source "$config_file"
            
            # Stop existing VM
            stop_vm "$VM_NAME"
            
            # Copy files
            cp "$temp_dir"/*.conf "$DATA_DIR/vms/"
            cp "$temp_dir"/*.qcow2 "$DATA_DIR/disks/" 2>/dev/null
            cp -r "$temp_dir"/* "$DATA_DIR/cloudinit/" 2>/dev/null
            
            print_status "SUCCESS" "VM restored: $VM_NAME"
        else
            print_status "ERROR" "Invalid backup file"
        fi
        
        rm -rf "$temp_dir"
    else
        print_status "INFO" "Restore cancelled"
    fi
    
    sleep 2
}

# =============================================================================
# SETTINGS
# =============================================================================

settings_menu() {
    while true; do
        print_header
        echo -e "${GREEN}⚙️  Settings${NC}"
        echo
        
        echo "Options:"
        echo "  1) Show SSH Key"
        echo "  2) Generate New SSH Key"
        echo "  3) Change Default Port"
        echo "  4) View Logs"
        echo "  5) Clear Logs"
        echo "  6) Back to Main"
        echo
        
        read -rp "$(print_status "INPUT" "Select option: ")" choice
        
        case $choice in
            1)
                if [ -f "${SSH_KEY_FILE}.pub" ]; then
                    echo "SSH Public Key:"
                    echo "───────────────"
                    cat "${SSH_KEY_FILE}.pub"
                else
                    print_status "ERROR" "SSH key not found"
                fi
                echo
                read -rp "$(print_status "INPUT" "Press Enter to continue...")"
                ;;
            2)
                print_status "INFO" "Generating new SSH key..."
                rm -f "$SSH_KEY_FILE" "${SSH_KEY_FILE}.pub"
                ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q
                chmod 600 "$SSH_KEY_FILE"
                chmod 644 "${SSH_KEY_FILE}.pub"
                print_status "SUCCESS" "New SSH key generated"
                sleep 2
                ;;
            3)
                read -rp "$(print_status "INPUT" "New default SSH port: ")" new_port
                if validate_input "port" "$new_port"; then
                    # Update config
                    sed -i "s/ssh_base_port:.*/ssh_base_port: $new_port/" "$GLOBAL_CONFIG"
                    print_status "SUCCESS" "Default port changed to $new_port"
                fi
                sleep 1
                ;;
            4)
                if [ -f "$LOG_FILE" ]; then
                    echo "Recent Logs:"
                    echo "────────────"
                    tail -50 "$LOG_FILE"
                else
                    print_status "INFO" "No logs available"
                fi
                echo
                read -rp "$(print_status "INPUT" "Press Enter to continue...")"
                ;;
            5)
                if [ -f "$LOG_FILE" ]; then
                    > "$LOG_FILE"
                    print_status "SUCCESS" "Logs cleared"
                fi
                sleep 1
                ;;
            6) return ;;
            *) print_status "ERROR" "Invalid option"; sleep 1 ;;
        esac
    done
}

# =============================================================================
# SYSTEM INFO
# =============================================================================

system_info_menu() {
    print_header
    echo -e "${GREEN}ℹ️  System Information${NC}"
    echo
    
    echo "System:"
    echo "───────"
    echo "  Hostname: $(hostname)"
    echo "  OS: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
    echo "  Kernel: $(uname -r)"
    echo "  Architecture: $(uname -m)"
    echo
    
    echo "Resources:"
    echo "──────────"
    echo "  CPU Cores: $(nproc)"
    echo "  CPU Model: $(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^[ \t]*//')"
    echo "  Memory: $(free -h | awk '/^Mem:/ {print $2}') total, $(free -h | awk '/^Mem:/ {print $4}') free"
    echo "  Disk: $(df -h / | awk 'NR==2 {print $2}') total, $(df -h / | awk 'NR==2 {print $4}') free"
    echo
    
    echo "ZynexForge:"
    echo "───────────"
    echo "  Version: $SCRIPT_VERSION"
    echo "  Config Directory: $CONFIG_DIR"
    echo "  Data Directory: $DATA_DIR"
    echo "  SSH Key: $SSH_KEY_FILE"
    echo
    
    # Count VMs
    local vm_count=0
    local docker_count=0
    local jupyter_count=0
    
    if [ -d "$DATA_DIR/vms" ]; then
        vm_count=$(find "$DATA_DIR/vms" -name "*.conf" -type f 2>/dev/null | wc -l)
    fi
    
    if command -v docker > /dev/null 2>&1; then
        docker_count=$(docker ps -a --format "{{.Names}}" | wc -l)
    fi
    
    if [ -d "$DATA_DIR/jupyter" ]; then
        jupyter_count=$(find "$DATA_DIR/jupyter" -name "*.conf" -type f 2>/dev/null | wc -l)
    fi
    
    echo "Statistics:"
    echo "───────────"
    echo "  Total VMs: $vm_count"
    echo "  Docker Containers: $docker_count"
    echo "  Jupyter Labs: $jupyter_count"
    echo
    
    read -rp "$(print_status "INPUT" "Press Enter to continue...")"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Handle command line arguments
case "${1:-}" in
    "init"|"setup")
        initialize_platform
        print_status "SUCCESS" "Platform initialized"
        ;;
    "start")
        if [ -n "${2:-}" ]; then
            start_vm "$2"
        else
            print_status "ERROR" "Please specify VM name"
        fi
        ;;
    "stop")
        if [ -n "${2:-}" ]; then
            stop_vm "$2"
        else
            print_status "ERROR" "Please specify VM name"
        fi
        ;;
    "list-vms")
        print_header
        echo "Virtual Machines:"
        echo "─────────────────"
        if [ -d "$DATA_DIR/vms" ]; then
            for conf in "$DATA_DIR/vms"/*.conf; do
                source "$conf"
                echo "  $VM_NAME (Port: $SSH_PORT, Status: $STATUS)"
            done
        else
            echo "  No VMs configured"
        fi
        ;;
    "backup")
        if [ -n "${2:-}" ]; then
            backup_vm "$2"
        else
            print_status "ERROR" "Please specify VM name"
        fi
        ;;
    "help"|"--help"|"-h")
        cat << EOF
Usage: $0 [command]

Commands:
  init, setup      Initialize the platform
  start <vm>       Start a VM
  stop <vm>        Stop a VM
  list-vms         List all virtual machines
  backup <vm>      Backup a VM
  help             Show this help message

Without arguments: Start interactive menu
EOF
        ;;
    *)
        # Initialize platform
        initialize_platform
        
        # Start interactive menu
        main_menu
        ;;
esac
