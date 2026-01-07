#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge V2 - Production VPS Platform
# =============================

# Configuration
readonly CONFIG_DIR="$HOME/.zynexforge"
readonly VM_BASE_DIR="$HOME/zynexforge/vms"
readonly NETWORK_CONFIG="/etc/netplan/00-zynexforge.yaml"
readonly LIBVIRT_XML_DIR="/etc/libvirt/qemu"
readonly LOG_DIR="$HOME/.zynexforge/logs"
readonly LOG_FILE="$LOG_DIR/zynexforge.log"

# Function to display header
display_header() {
    clear
    cat << "EOF"
__________                           ___________                         
\____    /__.__. ____   ____ ___  __\_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /|    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    < |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \\___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/    \/             /_____/      \/ 

                    ⚡ ZynexForge V2 ⚡
              Production VPS/VM Management Platform
========================================================================
EOF
    echo
}

# Function to display colored output
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "\033[1;34m[INFO]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m[WARN]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m[ERROR]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[SUCCESS]\033[0m $message" ;;
        "INPUT") echo -e "\033[1;36m[INPUT]\033[0m $message" ;;
        *) echo "[$type] $message" ;;
    esac
    # Create log directory if it doesn't exist
    mkdir -p "$LOG_DIR" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$type] $message" >> "$LOG_FILE" 2>/dev/null || true
}

# Function to check if command exists with fallback
command_exists() {
    command -v "$1" &> /dev/null
}

# Safe sudo function that handles permission issues
safe_sudo() {
    if command_exists sudo && sudo -n true 2>/dev/null; then
        sudo "$@"
    else
        print_status "WARN" "sudo not available or broken, attempting without..."
        "$@"
    fi
}

# Function to check and install dependencies
check_dependencies() {
    print_status "INFO" "Checking dependencies..."
    
    # Check for broken sudo first
    if command_exists sudo; then
        if ! sudo -l >/dev/null 2>&1; then
            print_status "WARN" "sudo has permission issues. Some features may be limited."
            print_status "INFO" "To fix sudo, run: chown root:root /usr/bin/sudo && chmod 4755 /usr/bin/sudo"
        fi
    fi
    
    local deps=("qemu-system-x86_64" "libvirt-daemon-system" "virt-manager" \
                "bridge-utils" "cloud-image-utils" "wget" "qemu-img" \
                "libguestfs-tools" "nftables" "jq" "xmlstarlet" "sshpass")
    
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "INFO" "Missing dependencies: ${missing_deps[*]}"
        
        # Check if we can install packages
        if command_exists apt-get && [ "$EUID" -eq 0 ]; then
            apt update && apt install -y "${missing_deps[@]}"
        elif command_exists apt-get && command_exists sudo; then
            print_status "INFO" "Attempting to install with sudo..."
            if sudo apt update && sudo apt install -y "${missing_deps[@]}"; then
                print_status "SUCCESS" "Dependencies installed"
            else
                print_status "ERROR" "Failed to install dependencies"
                print_status "INFO" "Please install manually: sudo apt install ${missing_deps[*]}"
                exit 1
            fi
        else
            print_status "ERROR" "Cannot install dependencies automatically"
            print_status "INFO" "Please install manually: ${missing_deps[*]}"
            exit 1
        fi
    fi
    
    # Check KVM support
    if command_exists kvm-ok; then
        if ! kvm-ok 2>/dev/null; then
            print_status "WARN" "KVM acceleration not available. Continuing without hardware acceleration."
        fi
    fi
}

# Function to initialize platform
initialize_platform() {
    print_status "INFO" "Initializing ZynexForge V2 platform..."
    
    # Create directories with proper permissions
    mkdir -p "$CONFIG_DIR"/{profiles,networks,scripts,ddos} 2>/dev/null || {
        print_status "ERROR" "Failed to create config directories"
        exit 1
    }
    
    mkdir -p "$VM_BASE_DIR"/{images,configs,disks,isos} 2>/dev/null || {
        print_status "ERROR" "Failed to create VM directories"
        exit 1
    }
    
    mkdir -p "$LOG_DIR" 2>/dev/null || {
        print_status "ERROR" "Failed to create log directory"
        exit 1
    }
    
    # Create empty log file
    touch "$LOG_FILE" 2>/dev/null || true
    
    # Initialize network configuration if not exists
    if [ ! -f "$NETWORK_CONFIG" ]; then
        print_status "INFO" "Network configuration will be created when needed"
    fi
    
    # Initialize VM profiles
    initialize_vm_profiles
    
    print_status "SUCCESS" "Platform initialized successfully"
}

# Function to initialize VM profiles
initialize_vm_profiles() {
    cat << 'EOF' > "$CONFIG_DIR/profiles/default.yaml"
profiles:
  web:
    description: "Optimized for HTTP/HTTPS hosting"
    cpu_type: "host-passthrough"
    cpu_topology:
      sockets: 1
      cores: 2
      threads: 1
    cpu_pinning: "auto"
    memory: 4096
    memory_backing: "hugepages-2M"
    disk:
      size: "50G"
      cache: "writeback"
      io: "threads"
      iothreads: 2
    network:
      model: "virtio"
      driver: "vhost"
      queues: 2
    features:
      acpi: true
      apic: true
      hyperv: true
      kvm_hidden: false
    optimization:
      hugepages: true
      numa: true
      iothread: true
    default_ports:
      tcp: [22, 80, 443]
      udp: []
    
  backend:
    description: "APIs, databases, workers"
    cpu_type: "host-passthrough"
    cpu_topology:
      sockets: 1
      cores: 4
      threads: 1
    cpu_pinning: "0-3"
    memory: 8192
    memory_backing: "hugepages-2M"
    disk:
      size: "100G"
      cache: "writethrough"
      io: "native"
      iothreads: 4
    network:
      model: "virtio"
      driver: "vhost"
      queues: 4
    features:
      acpi: true
      apic: true
      hyperv: true
    optimization:
      hugepages: true
      numa: true
    default_ports:
      tcp: [22, 3306, 5432, 6379]
      udp: []
    
  llm-ai:
    description: "High CPU/Memory for AI workloads"
    cpu_type: "host-passthrough"
    cpu_topology:
      sockets: 2
      cores: 8
      threads: 2
    cpu_pinning: "0-31"
    memory: 65536
    memory_backing: "hugepages-1G"
    disk:
      size: "500G"
      cache: "none"
      io: "native"
      iothreads: 8
      discard: "unmap"
    network:
      model: "virtio"
      driver: "vhost"
      queues: 8
    features:
      acpi: true
      apic: true
      hyperv: false
      kvm_hidden: true
    optimization:
      hugepages: true
      numa: true
      cpu_mode: "maximum"
    default_ports:
      tcp: [22, 7860, 8000, 8080]
      udp: []
    
  game-server:
    description: "Low-latency game servers"
    cpu_type: "host-passthrough"
    cpu_topology:
      sockets: 1
      cores: 4
      threads: 2
    cpu_pinning: "isolated"
    memory: 16384
    memory_backing: ""
    disk:
      size: "200G"
      cache: "writethrough"
      io: "threads"
      iothreads: 2
    network:
      model: "virtio"
      driver: "vhost"
      queues: 2
      latency: "low"
    features:
      acpi: true
      apic: true
      hyperv: false
    optimization:
      cpu_realtime: true
      no_hypervisor: true
    default_ports:
      tcp: [22, 25565, 27015]
      udp: [19132, 25565, 27015]
    
  desktop:
    description: "XRDP-ready desktop VM"
    cpu_type: "host-passthrough"
    cpu_topology:
      sockets: 1
      cores: 4
      threads: 1
    cpu_pinning: "0-3"
    memory: 8192
    memory_backing: ""
    disk:
      size: "100G"
      cache: "writeback"
      io: "threads"
      iothreads: 2
    network:
      model: "virtio"
      driver: "vhost"
      queues: 2
    features:
      acpi: true
      apic: true
      hyperv: true
      virgl: true
    devices:
      graphics: "spice"
      video: "qxl"
      sound: "ac97"
    default_ports:
      tcp: [22, 3389]
      udp: []
    
  heavy-task:
    description: "High CPU/Memory/Disk workloads"
    cpu_type: "host-passthrough"
    cpu_topology:
      sockets: 2
      cores: 12
      threads: 2
    cpu_pinning: "0-47"
    memory: 131072
    memory_backing: "hugepages-1G"
    disk:
      size: "1000G"
      cache: "none"
      io: "native"
      iothreads: 16
      discard: "unmap"
    network:
      model: "virtio"
      driver: "vhost"
      queues: 8
    features:
      acpi: true
      apic: true
      hyperv: false
    optimization:
      hugepages: true
      numa: true
      iothread_poll: true
    default_ports:
      tcp: [22]
      udp: []
EOF
    print_status "SUCCESS" "VM profiles initialized"
}

# Function to create network configuration (non-sudo version)
create_network_config() {
    print_status "INFO" "Creating user-space network configuration..."
    
    # Find primary network interface
    local primary_iface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -z "$primary_iface" ]; then
        primary_iface="eth0"
    fi
    
    # Create user-space network config
    local user_network_config="$CONFIG_DIR/networks/br0.conf"
    
    cat << EOF > "$user_network_config"
# ZynexForge Network Configuration
# Bridge: br0
# Interface: $primary_iface
# 
# To apply this configuration:
# 1. Copy to /etc/netplan/00-zynexforge.yaml
# 2. Run: sudo netplan apply
# 3. Reboot if necessary

network:
  version: 2
  renderer: networkd
  ethernets:
    $primary_iface:
      dhcp4: false
      dhcp6: false
      accept-ra: false
  bridges:
    br0:
      interfaces: [$primary_iface]
      addresses: []
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      parameters:
        stp: false
        forward-delay: 0
      dhcp4: false
      dhcp6: false
EOF
    
    print_status "INFO" "Network configuration template created at: $user_network_config"
    print_status "INFO" "Please edit this file to add your public IP addresses"
    print_status "INFO" "Then copy to /etc/netplan/ and run: sudo netplan apply"
}

# Function to get all VM configurations
get_vm_list() {
    find "$VM_BASE_DIR/configs" -name "*.json" -exec basename {} .json \; 2>/dev/null | sort
}

# Function to load VM configuration
load_vm_config() {
    local vm_name=$1
    local config_file="$VM_BASE_DIR/configs/$vm_name.json"
    
    if [[ -f "$config_file" ]]; then
        if command_exists jq; then
            VM_NAME=$(jq -r '.vm_name' "$config_file")
            VM_PROFILE=$(jq -r '.profile' "$config_file")
            OS_TYPE=$(jq -r '.os_type' "$config_file")
            CODENAME=$(jq -r '.codename' "$config_file")
            IMG_URL=$(jq -r '.img_url' "$config_file")
            HOSTNAME=$(jq -r '.hostname' "$config_file")
            USERNAME=$(jq -r '.username' "$config_file")
            PASSWORD=$(jq -r '.password' "$config_file")
            PUBLIC_IP=$(jq -r '.network.public_ip' "$config_file")
            MAC_ADDRESS=$(jq -r '.network.mac_address' "$config_file")
            DISK_SIZE=$(jq -r '.disk.size' "$config_file")
            MEMORY=$(jq -r '.memory' "$config_file")
            CPUS=$(jq -r '.cpus' "$config_file")
            SSH_PORT=$(jq -r '.ports.ssh' "$config_file")
            XRDP_ENABLED=$(jq -r '.xrdp.enabled' "$config_file")
            XRDP_PORT=$(jq -r '.xrdp.port' "$config_file")
            DDOS_PROTECTION=$(jq -r '.security.ddos_protection' "$config_file")
            OPEN_PORTS=$(jq -r '.ports.open // "[]"' "$config_file")
            CREATED=$(jq -r '.created' "$config_file")
            return 0
        elif [ -f "${config_file%.json}.conf" ]; then
            source "${config_file%.json}.conf"
            return 0
        fi
    fi
    return 1
}

# Function to save VM configuration
save_vm_config() {
    local config_file="$VM_BASE_DIR/configs/$VM_NAME.json"
    
    # Create directories if needed
    mkdir -p "$(dirname "$config_file")"
    
    # Create JSON configuration
    if command_exists jq; then
        cat > "$config_file" << EOF
{
  "vm_name": "$VM_NAME",
  "profile": "$VM_PROFILE",
  "os_type": "$OS_TYPE",
  "codename": "$CODENAME",
  "img_url": "$IMG_URL",
  "hostname": "$HOSTNAME",
  "username": "$USERNAME",
  "password": "$PASSWORD",
  "network": {
    "public_ip": "$PUBLIC_IP",
    "mac_address": "$MAC_ADDRESS",
    "bridge": "br0"
  },
  "disk": {
    "size": "$DISK_SIZE",
    "path": "$VM_BASE_DIR/disks/$VM_NAME.qcow2"
  },
  "memory": $MEMORY,
  "cpus": $CPUS,
  "ports": {
    "ssh": $SSH_PORT,
    "open": []
  },
  "xrdp": {
    "enabled": $XRDP_ENABLED,
    "port": $XRDP_PORT
  },
  "security": {
    "ddos_protection": $DDOS_PROTECTION,
    "ssh_key_only": true
  },
  "created": "$CREATED",
  "status": "stopped"
}
EOF
    else
        # Simple JSON without jq
        cat > "$config_file" << EOF
{
  "vm_name": "$VM_NAME",
  "profile": "$VM_PROFILE",
  "os_type": "$OS_TYPE",
  "codename": "$CODENAME",
  "img_url": "$IMG_URL",
  "hostname": "$HOSTNAME",
  "username": "$USERNAME",
  "password": "$PASSWORD",
  "network": {
    "public_ip": "$PUBLIC_IP",
    "mac_address": "$MAC_ADDRESS",
    "bridge": "br0"
  },
  "disk": {
    "size": "$DISK_SIZE",
    "path": "$VM_BASE_DIR/disks/$VM_NAME.qcow2"
  },
  "memory": $MEMORY,
  "cpus": $CPUS,
  "ports": {
    "ssh": $SSH_PORT,
    "open": []
  },
  "xrdp": {
    "enabled": $XRDP_ENABLED,
    "port": $XRDP_PORT
  },
  "security": {
    "ddos_protection": $DDOS_PROTECTION,
    "ssh_key_only": true
  },
  "created": "$CREATED",
  "status": "stopped"
}
EOF
    fi
    
    # Also create a shell-readable config
    cat > "${config_file%.json}.conf" << EOF
VM_NAME="$VM_NAME"
VM_PROFILE="$VM_PROFILE"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
PUBLIC_IP="$PUBLIC_IP"
MAC_ADDRESS="$MAC_ADDRESS"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
XRDP_ENABLED="$XRDP_ENABLED"
XRDP_PORT="$XRDP_PORT"
DDOS_PROTECTION="$DDOS_PROTECTION"
CREATED="$CREATED"
EOF
    
    print_status "SUCCESS" "Configuration saved"
}

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating a new VM"
    
    # OS Selection
    print_status "INFO" "Select an OS to set up:"
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        echo "  $i) $os"
        ((i++))
    done
    
    local os_count=${#OS_OPTIONS[@]}
    local os_keys=(${!OS_OPTIONS[@]})
    
    while true; do
        read -p "$(print_status "INPUT" "Enter your choice (1-$os_count): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $os_count ]; then
            local os="${os_keys[$((choice-1))]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            break
        else
            print_status "ERROR" "Invalid selection. Try again."
        fi
    done

    # VM Profile Selection
    print_status "INFO" "Select VM Profile:"
    echo "  1) WEB - Website hosting (HTTP/HTTPS)"
    echo "  2) BACKEND - APIs, databases, workers"
    echo "  3) LLM/AI - High CPU/Memory for AI workloads"
    echo "  4) GAME SERVER - Low-latency game servers"
    echo "  5) DESKTOP - XRDP-ready desktop"
    echo "  6) HEAVY TASK - High CPU/Memory/Disk workloads"
    
    while true; do
        read -p "$(print_status "INPUT" "Enter profile choice (1-6): ")" profile_choice
        case $profile_choice in
            1) VM_PROFILE="web" ;;
            2) VM_PROFILE="backend" ;;
            3) VM_PROFILE="llm-ai" ;;
            4) VM_PROFILE="game-server" ;;
            5) VM_PROFILE="desktop" ;;
            6) VM_PROFILE="heavy-task" ;;
            *) print_status "ERROR" "Invalid selection. Try again."; continue ;;
        esac
        break
    done

    # VM Name
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if [[ "$VM_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            if [[ -f "$VM_BASE_DIR/configs/$VM_NAME.json" ]]; then
                print_status "ERROR" "VM with name '$VM_NAME' already exists"
            else
                break
            fi
        else
            print_status "ERROR" "VM name can only contain letters, numbers, hyphens, and underscores"
        fi
    done

    # Hostname
    read -p "$(print_status "INPUT" "Enter hostname (default: $VM_NAME): ")" HOSTNAME
    HOSTNAME="${HOSTNAME:-$VM_NAME}"

    # Username
    read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
    USERNAME="${USERNAME:-$DEFAULT_USERNAME}"

    # Password
    read -s -p "$(print_status "INPUT" "Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
    PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
    echo

    # Public IP Assignment
    print_status "INFO" "Network Configuration:"
    while true; do
        read -p "$(print_status "INPUT" "Enter public IPv4 address with CIDR (e.g., 192.168.1.10/24): ")" PUBLIC_IP
        if [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            if grep -r "$PUBLIC_IP" "$VM_BASE_DIR/configs/" >/dev/null 2>&1; then
                print_status "ERROR" "IP address $PUBLIC_IP is already assigned"
            else
                break
            fi
        else
            print_status "ERROR" "Must be a valid IP address with CIDR (e.g., 192.168.1.10/24)"
        fi
    done

    # MAC Address
    read -p "$(print_status "INPUT" "Enter MAC address (press Enter to auto-generate): ")" MAC_ADDRESS
    if [ -z "$MAC_ADDRESS" ]; then
        MAC_ADDRESS="52:54:00:$(openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/.$//' 2>/dev/null || echo "12:34:56")"
        print_status "INFO" "Auto-generated MAC: $MAC_ADDRESS"
    fi

    # Resource allocation based on profile
    load_profile_settings "$VM_PROFILE"
    
    # Show proposed resources
    print_status "INFO" "Profile '$VM_PROFILE' settings:"
    echo "  Memory: ${MEMORY}MB"
    echo "  CPUs: ${CPUS}"
    echo "  Disk: ${DISK_SIZE}"
    
    # SSH Port
    read -p "$(print_status "INPUT" "SSH Port inside VM (default: 22): ")" SSH_PORT
    SSH_PORT="${SSH_PORT:-22}"

    # XRDP option
    if [[ "$VM_PROFILE" == "desktop" ]]; then
        XRDP_ENABLED="true"
        XRDP_PORT="3389"
        print_status "INFO" "XRDP will be enabled for desktop VM"
    else
        XRDP_ENABLED="false"
        XRDP_PORT="3389"
    fi

    # DDoS protection
    DDOS_PROTECTION="true"
    if [[ "$VM_PROFILE" == "web" || "$VM_PROFILE" == "game-server" ]]; then
        print_status "INFO" "DDoS protection enabled by default"
    fi

    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"

    # Create VM
    print_status "INFO" "Creating VM '$VM_NAME'..."
    if create_vm_image && create_vm_configuration; then
        save_vm_config
        
        print_status "SUCCESS" "VM '$VM_NAME' created successfully!"
        print_status "INFO" "Public IP: $PUBLIC_IP"
        print_status "INFO" "SSH: ssh $USERNAME@${PUBLIC_IP%/*} -p $SSH_PORT"
        
        if [[ "$XRDP_ENABLED" == "true" ]]; then
            print_status "INFO" "XRDP: Available at ${PUBLIC_IP%/*}:$XRDP_PORT"
        fi
        
        print_status "INFO" "Configuration saved to: $VM_BASE_DIR/configs/$VM_NAME.json"
    else
        print_status "ERROR" "Failed to create VM '$VM_NAME'"
        return 1
    fi
}

# Function to load profile settings
load_profile_settings() {
    local profile=$1
    
    case $profile in
        "web")
            MEMORY=4096
            CPUS=2
            DISK_SIZE="50G"
            ;;
        "backend")
            MEMORY=8192
            CPUS=4
            DISK_SIZE="100G"
            ;;
        "llm-ai")
            MEMORY=65536
            CPUS=16
            DISK_SIZE="500G"
            ;;
        "game-server")
            MEMORY=16384
            CPUS=8
            DISK_SIZE="200G"
            ;;
        "desktop")
            MEMORY=8192
            CPUS=4
            DISK_SIZE="100G"
            ;;
        "heavy-task")
            MEMORY=131072
            CPUS=24
            DISK_SIZE="1000G"
            ;;
        *)
            MEMORY=2048
            CPUS=2
            DISK_SIZE="20G"
            ;;
    esac
}

# Function to create VM image
create_vm_image() {
    local image_file="$VM_BASE_DIR/images/${VM_NAME}.qcow2"
    
    print_status "INFO" "Preparing VM image..."
    
    # Create directories if they don't exist
    mkdir -p "$VM_BASE_DIR/images" "$VM_BASE_DIR/disks" "$VM_BASE_DIR/isos" "$VM_BASE_DIR/configs"
    
    # Check if image already exists
    if [[ -f "$image_file" ]]; then
        print_status "INFO" "Reusing existing base image"
    else
        print_status "INFO" "Downloading image from $IMG_URL..."
        if ! wget --progress=bar:force -q --show-progress "$IMG_URL" -O "${image_file}.tmp"; then
            print_status "ERROR" "Failed to download image"
            return 1
        fi
        mv "${image_file}.tmp" "$image_file"
    fi
    
    # Create disk with specified size
    local disk_file="$VM_BASE_DIR/disks/${VM_NAME}.qcow2"
    if ! qemu-img create -f qcow2 -F qcow2 -b "$image_file" "$disk_file" "$DISK_SIZE" 2>/dev/null; then
        print_status "ERROR" "Failed to create disk image"
        return 1
    fi
    
    # Create cloud-init ISO
    if ! create_cloud_init_iso; then
        print_status "ERROR" "Failed to create cloud-init ISO"
        return 1
    fi
    
    return 0
}

# Function to create cloud-init ISO
create_cloud_init_iso() {
    local seed_dir="$VM_BASE_DIR/configs/${VM_NAME}-seed"
    mkdir -p "$seed_dir"
    
    # Create user-data
    cat > "$seed_dir/user-data" <<EOF
#cloud-config
hostname: $HOSTNAME
fqdn: $HOSTNAME.localdomain
manage_etc_hosts: true
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $(echo "$PASSWORD" | openssl passwd -6 -stdin 2>/dev/null | tr -d '\n' || echo "$PASSWORD")
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
packages:
  - qemu-guest-agent
  - fail2ban
  - nftables
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "vm_name=$VM_NAME" >> /etc/environment
  - echo "vm_profile=$VM_PROFILE" >> /etc/environment
EOF
    
    # Create meta-data
    cat > "$seed_dir/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $HOSTNAME
EOF
    
    # Create network-config
    cat > "$seed_dir/network-config" <<EOF
version: 2
ethernets:
  ens3:
    match:
      macaddress: "$MAC_ADDRESS"
    addresses:
      - $PUBLIC_IP
    gateway4: $(echo $PUBLIC_IP | cut -d'/' -f1 | sed 's/[0-9]*$/1/')
    nameservers:
      addresses: [8.8.8.8, 1.1.1.1]
EOF
    
    # Create ISO
    if command_exists cloud-localds; then
        if ! cloud-localds "$VM_BASE_DIR/isos/${VM_NAME}-seed.iso" \
            "$seed_dir/user-data" \
            "$seed_dir/meta-data" \
            --network-config "$seed_dir/network-config" 2>/dev/null; then
            print_status "WARN" "Failed to create cloud-init ISO, using basic setup"
        fi
    else
        print_status "WARN" "cloud-localds not found, skipping cloud-init ISO"
    fi
    
    # Cleanup
    rm -rf "$seed_dir"
    return 0
}

# Function to create VM configuration (non-libvirt version)
create_vm_configuration() {
    print_status "INFO" "Creating VM configuration..."
    
    # Create a simple startup script
    local startup_script="$VM_BASE_DIR/configs/${VM_NAME}-start.sh"
    
    cat > "$startup_script" <<EOF
#!/bin/bash
# Startup script for $VM_NAME
# Run this to start the VM

VM_NAME="$VM_NAME"
VM_DISK="$VM_BASE_DIR/disks/\$VM_NAME.qcow2"
VM_SEED="$VM_BASE_DIR/isos/\$VM_NAME-seed.iso"
VM_MEMORY="$MEMORY"
VM_CPUS="$CPUS"
VM_MAC="$MAC_ADDRESS"

if [ ! -f "\$VM_DISK" ]; then
    echo "Error: Disk image not found: \$VM_DISK"
    exit 1
fi

# Check if KVM is available
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    KVM_OPT="-enable-kvm"
else
    echo "Warning: KVM not available, using software emulation"
    KVM_OPT=""
fi

# Start QEMU
echo "Starting VM: \$VM_NAME"
echo "Memory: \$VM_MEMORY MB"
echo "CPUs: \$VM_CPUS"
echo "IP: ${PUBLIC_IP%/*}"
echo ""
echo "To connect via SSH: ssh $USERNAME@${PUBLIC_IP%/*} -p $SSH_PORT"
echo "To stop: Press Ctrl+A, then X"

qemu-system-x86_64 \$KVM_OPT \\
  -m \$VM_MEMORY \\
  -smp \$VM_CPUS \\
  -cpu host \\
  -drive file=\$VM_DISK,format=qcow2,if=virtio \\
  -drive file=\$VM_SEED,format=raw,if=virtio \\
  -netdev bridge,br=br0,id=n0 \\
  -device virtio-net-pci,netdev=n0,mac=\$VM_MAC \\
  -nographic \\
  -serial mon:stdio
EOF
    
    chmod +x "$startup_script"
    
    # Create a systemd service file template
    local service_file="$VM_BASE_DIR/configs/${VM_NAME}.service"
    
    cat > "$service_file" <<EOF
[Unit]
Description=ZynexForge VM: $VM_NAME
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=$startup_script
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    print_status "SUCCESS" "VM configuration created"
    print_status "INFO" "Start VM with: $startup_script"
    print_status "INFO" "Or install as service: sudo cp $service_file /etc/systemd/system/ && sudo systemctl enable ${VM_NAME}.service"
    
    return 0
}

# Function to start a VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $vm_name"
        
        local startup_script="$VM_BASE_DIR/configs/${vm_name}-start.sh"
        
        if [ -f "$startup_script" ]; then
            print_status "INFO" "Public IP: ${PUBLIC_IP%/*}"
            print_status "INFO" "SSH: ssh $USERNAME@${PUBLIC_IP%/*} -p $SSH_PORT"
            
            if [[ "$XRDP_ENABLED" == "true" ]]; then
                print_status "INFO" "XRDP: Connect to ${PUBLIC_IP%/*}:$XRDP_PORT"
            fi
            
            # Run in background
            "$startup_script" &
            print_status "SUCCESS" "VM $vm_name started in background"
            print_status "INFO" "Process ID: $!"
        else
            print_status "ERROR" "Startup script not found: $startup_script"
        fi
    fi
}

# Function to stop a VM
stop_vm() {
    local vm_name=$1
    
    print_status "INFO" "Stopping VM: $vm_name"
    
    # Find and kill QEMU process for this VM
    local pids=$(pgrep -f "qemu.*$vm_name" || true)
    
    if [ -n "$pids" ]; then
        for pid in $pids; do
            kill "$pid" 2>/dev/null && print_status "INFO" "Stopped process $pid"
        done
        print_status "SUCCESS" "VM $vm_name stopped"
    else
        print_status "INFO" "No running process found for VM $vm_name"
    fi
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "This will permanently delete VM '$vm_name' and all its data!"
    read -p "$(print_status "INPUT" "Are you sure? (y/N): ")" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if load_vm_config "$vm_name"; then
            # Stop VM if running
            stop_vm "$vm_name"
            
            # Remove files
            rm -f "$VM_BASE_DIR/disks/${vm_name}.qcow2"
            rm -f "$VM_BASE_DIR/isos/${vm_name}-seed.iso"
            rm -f "$VM_BASE_DIR/configs/${vm_name}.json"
            rm -f "$VM_BASE_DIR/configs/${vm_name}.conf"
            rm -f "$VM_BASE_DIR/configs/${vm_name}-start.sh"
            rm -f "$VM_BASE_DIR/configs/${vm_name}.service"
            rm -f "$VM_BASE_DIR/images/${vm_name}.qcow2"
            
            print_status "SUCCESS" "VM '$vm_name' has been deleted"
        else
            print_status "INFO" "Deleting VM files..."
            rm -rf "$VM_BASE_DIR/disks/${vm_name}.qcow2" \
                   "$VM_BASE_DIR/isos/${vm_name}-seed.iso" \
                   "$VM_BASE_DIR/configs/${vm_name}."* \
                   "$VM_BASE_DIR/images/${vm_name}.qcow2" 2>/dev/null || true
            print_status "SUCCESS" "VM '$vm_name' files deleted"
        fi
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

# Function to enable XRDP (simplified)
enable_xrdp() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "XRDP Setup for $vm_name"
        
        local vm_ip="${PUBLIC_IP%/*}"
        
        echo ""
        echo "To enable XRDP on $vm_name ($vm_ip):"
        echo "1. Connect to the VM: ssh $USERNAME@$vm_ip"
        echo "2. Run these commands inside the VM:"
        echo ""
        echo "   # For Ubuntu/Debian:"
        echo "   sudo apt update"
        echo "   sudo apt install -y xrdp xorgxrdp"
        echo "   sudo systemctl enable xrdp"
        echo "   sudo systemctl start xrdp"
        echo "   sudo ufw allow 3389/tcp"
        echo ""
        echo "   # For CentOS/RHEL/Fedora:"
        echo "   sudo yum install -y xrdp xorgxrdp"
        echo "   sudo systemctl enable xrdp"
        echo "   sudo systemctl start xrdp"
        echo "   sudo firewall-cmd --permanent --add-port=3389/tcp"
        echo "   sudo firewall-cmd --reload"
        echo ""
        echo "3. Connect using: $vm_ip:3389"
        echo "   Username: $USERNAME"
        echo "   Password: $PASSWORD"
        echo ""
        
        # Update config
        if command_exists jq && [ -f "$VM_BASE_DIR/configs/$vm_name.json" ]; then
            jq '.xrdp.enabled = true' "$VM_BASE_DIR/configs/$vm_name.json" > "/tmp/${vm_name}.tmp"
            mv "/tmp/${vm_name}.tmp" "$VM_BASE_DIR/configs/$vm_name.json"
        fi
        
        print_status "SUCCESS" "XRDP setup instructions displayed"
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo
        print_status "INFO" "VM Information: $vm_name"
        echo "=========================================="
        echo "Profile: $VM_PROFILE"
        echo "OS: $OS_TYPE"
        echo "Hostname: $HOSTNAME"
        echo "Username: $USERNAME"
        echo "Public IP: $PUBLIC_IP"
        echo "MAC Address: $MAC_ADDRESS"
        echo "SSH Port: $SSH_PORT"
        echo "Memory: $MEMORY MB"
        echo "CPUs: $CPUS"
        echo "Disk: $DISK_SIZE"
        echo "XRDP Enabled: $XRDP_ENABLED"
        echo "DDoS Protection: $DDOS_PROTECTION"
        echo "Created: $CREATED"
        echo "=========================================="
        
        # Check if running
        if pgrep -f "qemu.*$vm_name" >/dev/null; then
            echo "Status: Running"
        else
            echo "Status: Stopped"
        fi
        
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    else
        print_status "ERROR" "VM not found: $vm_name"
    fi
}

# Function to edit VM configuration
edit_vm_config() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Editing VM: $vm_name"
        
        while true; do
            echo "What would you like to edit?"
            echo "  1) Hostname"
            echo "  2) Username"
            echo "  3) Password"
            echo "  4) Memory (RAM)"
            echo "  5) CPU Count"
            echo "  6) Disk Size"
            echo "  7) Enable/Disable XRDP"
            echo "  8) IP Address"
            echo "  0) Back to main menu"
            
            read -p "$(print_status "INPUT" "Enter your choice: ")" edit_choice
            
            case $edit_choice in
                1)
                    read -p "$(print_status "INPUT" "Enter new hostname (current: $HOSTNAME): ")" new_hostname
                    HOSTNAME="${new_hostname:-$HOSTNAME}"
                    ;;
                2)
                    read -p "$(print_status "INPUT" "Enter new username (current: $USERNAME): ")" new_username
                    USERNAME="${new_username:-$USERNAME}"
                    ;;
                3)
                    read -s -p "$(print_status "INPUT" "Enter new password (current: ****): ")" new_password
                    new_password="${new_password:-$PASSWORD}"
                    echo
                    PASSWORD="$new_password"
                    ;;
                4)
                    read -p "$(print_status "INPUT" "Enter new memory in MB (current: $MEMORY): ")" new_memory
                    if [[ "$new_memory" =~ ^[0-9]+$ ]]; then
                        MEMORY="$new_memory"
                    fi
                    ;;
                5)
                    read -p "$(print_status "INPUT" "Enter new CPU count (current: $CPUS): ")" new_cpus
                    if [[ "$new_cpus" =~ ^[0-9]+$ ]]; then
                        CPUS="$new_cpus"
                    fi
                    ;;
                6)
                    read -p "$(print_status "INPUT" "Enter new disk size (current: $DISK_SIZE): ")" new_disk_size
                    if [[ "$new_disk_size" =~ ^[0-9]+[GgMm]$ ]]; then
                        DISK_SIZE="$new_disk_size"
                    fi
                    ;;
                7)
                    if [[ "$XRDP_ENABLED" == "true" ]]; then
                        XRDP_ENABLED="false"
                        print_status "INFO" "XRDP disabled"
                    else
                        XRDP_ENABLED="true"
                        print_status "INFO" "XRDP enabled"
                    fi
                    ;;
                8)
                    read -p "$(print_status "INPUT" "Enter new IP address with CIDR (current: $PUBLIC_IP): ")" new_ip
                    if [[ "$new_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
                        PUBLIC_IP="$new_ip"
                    fi
                    ;;
                0)
                    return 0
                    ;;
                *)
                    print_status "ERROR" "Invalid selection"
                    continue
                    ;;
            esac
            
            # Save updated configuration
            save_vm_config
            
            read -p "$(print_status "INPUT" "Continue editing? (y/N): ")" continue_editing
            if [[ ! "$continue_editing" =~ ^[Yy]$ ]]; then
                break
            fi
        done
    fi
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Found $vm_count existing VM(s):"
            for i in "${!vms[@]}"; do
                local status="Stopped"
                if pgrep -f "qemu.*${vms[$i]}" >/dev/null; then
                    status="Running"
                fi
                printf "  %2d) %s (%s)\n" $((i+1)) "${vms[$i]}" "$status"
            done
            echo
        fi
        
        echo "Main Menu:"
        echo "  1) Create a new VM"
        if [ $vm_count -gt 0 ]; then
            echo "  2) Start a VM"
            echo "  3) Stop a VM"
            echo "  4) Show VM info"
            echo "  5) Edit VM configuration"
            echo "  6) Delete a VM"
            echo "  7) Enable XRDP (one-click)"
            echo "  8) Setup Network Bridge"
        fi
        echo "  9) Repair/Reset Platform"
        echo "  0) Exit"
        echo
        
        read -p "$(print_status "INPUT" "Enter your choice: ")" choice
        
        case $choice in
            1)
                create_new_vm
                ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to start: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        start_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to stop: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        stop_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            4)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show info: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_info "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to edit: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        edit_vm_config "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to enable XRDP: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        enable_xrdp "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            8)
                setup_network_bridge
                ;;
            9)
                repair_platform
                ;;
            0)
                print_status "INFO" "Goodbye!"
                exit 0
                ;;
            *)
                print_status "ERROR" "Invalid option"
                ;;
        esac
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

# Function to setup network bridge
setup_network_bridge() {
    print_status "INFO" "Network Bridge Setup"
    echo ""
    echo "To use bridged networking with public IPs:"
    echo ""
    echo "1. Create network configuration:"
    echo "   sudo nano /etc/netplan/00-zynexforge.yaml"
    echo ""
    echo "2. Add configuration (example):"
    echo "   network:"
    echo "     version: 2"
    echo "     ethernets:"
    echo "       eth0:"
    echo "         dhcp4: false"
    echo "     bridges:"
    echo "       br0:"
    echo "         interfaces: [eth0]"
    echo "         addresses:"
    echo "           - 203.0.113.10/24    # Host IP"
    echo "           - 203.0.113.11/32    # VM 1"
    echo "           - 203.0.113.12/32    # VM 2"
    echo "         gateway4: 203.0.113.1"
    echo "         nameservers:"
    echo "           addresses: [8.8.8.8, 1.1.1.1]"
    echo ""
    echo "3. Apply configuration:"
    echo "   sudo netplan apply"
    echo ""
    echo "4. Install bridge utilities:"
    echo "   sudo apt install bridge-utils"
    echo ""
    echo "Note: Replace IP addresses with your actual public IPs"
    echo ""
    
    # Create template if requested
    read -p "$(print_status "INPUT" "Create configuration template? (y/N): ")" create_template
    if [[ "$create_template" =~ ^[Yy]$ ]]; then
        create_network_config
    fi
}

# Function to repair platform
repair_platform() {
    print_status "INFO" "Repairing platform..."
    
    # Recreate directories
    mkdir -p "$CONFIG_DIR" "$VM_BASE_DIR" "$LOG_DIR"
    mkdir -p "$CONFIG_DIR"/{profiles,networks,scripts,ddos}
    mkdir -p "$VM_BASE_DIR"/{images,configs,disks,isos}
    
    # Reinitialize profiles
    if [ ! -f "$CONFIG_DIR/profiles/default.yaml" ]; then
        initialize_vm_profiles
    fi
    
    print_status "SUCCESS" "Platform repaired"
}

# Supported OS list
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
)

# Main execution
check_dependencies
initialize_platform
main_menu
