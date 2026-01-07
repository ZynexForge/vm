#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge V2 - Production VPS Platform
# =============================

# Configuration
readonly CONFIG_DIR="/etc/zynexforge"
readonly VM_BASE_DIR="/var/lib/zynexforge/vms"
readonly NETWORK_CONFIG="/etc/netplan/00-zynexforge.yaml"
readonly LIBVIRT_XML_DIR="/etc/libvirt/qemu"
readonly LOG_DIR="/var/log/zynexforge"
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
    mkdir -p "$LOG_DIR" 2>/dev/null || sudo mkdir -p "$LOG_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$type] $message" | sudo tee -a "$LOG_FILE" >/dev/null
}

# Function to validate input
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
        "username")
            if ! [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                print_status "ERROR" "Username must start with a letter or underscore, and contain only letters, numbers, hyphens, and underscores"
                return 1
            fi
            ;;
        "ip")
            if ! [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
                print_status "ERROR" "Must be a valid IP address with CIDR (e.g., 192.168.1.10/24)"
                return 1
            fi
            ;;
        "mac")
            if ! [[ "$value" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                print_status "ERROR" "Must be a valid MAC address (e.g., 52:54:00:12:34:56)"
                return 1
            fi
            ;;
    esac
    return 0
}

# Function to check and install dependencies
check_dependencies() {
    print_status "INFO" "Checking dependencies..."
    
    local deps=("qemu-system-x86_64" "libvirt-daemon-system" "virt-manager" \
                "bridge-utils" "cloud-image-utils" "wget" "qemu-img" \
                "libguestfs-tools" "nftables" "jq" "xmlstarlet" "sshpass")
    
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "INFO" "Installing missing dependencies..."
        sudo apt update
        sudo apt install -y "${missing_deps[@]}" || {
            print_status "ERROR" "Failed to install dependencies"
            exit 1
        }
        
        # Enable and start libvirt
        sudo systemctl enable libvirtd
        sudo systemctl start libvirtd
    fi
    
    # Check KVM support
    if ! kvm-ok 2>/dev/null; then
        if ! sudo kvm-ok 2>/dev/null; then
            print_status "WARN" "KVM acceleration not available. Continuing without hardware acceleration."
        fi
    fi
}

# Function to initialize platform
initialize_platform() {
    print_status "INFO" "Initializing ZynexForge V2 platform..."
    
    # Create directories with proper permissions
    sudo mkdir -p "$CONFIG_DIR"/{profiles,networks,scripts,ddos} || {
        print_status "ERROR" "Failed to create config directories"
        exit 1
    }
    
    sudo mkdir -p "$VM_BASE_DIR"/{images,configs,disks,isos} || {
        print_status "ERROR" "Failed to create VM directories"
        exit 1
    }
    
    sudo mkdir -p "$LOG_DIR" || {
        print_status "ERROR" "Failed to create log directory"
        exit 1
    }
    
    # Set permissions
    sudo chown -R "$USER:$USER" "$CONFIG_DIR" 2>/dev/null || true
    sudo chown -R "$USER:$USER" "$VM_BASE_DIR" 2>/dev/null || true
    sudo chown -R "$USER:$USER" "$LOG_DIR" 2>/dev/null || true
    
    # Create empty log file
    sudo touch "$LOG_FILE"
    sudo chown "$USER:$USER" "$LOG_FILE"
    
    # Initialize network configuration if not exists
    if [ ! -f "$NETWORK_CONFIG" ]; then
        create_network_config
    fi
    
    # Initialize VM profiles
    initialize_vm_profiles
    
    print_status "SUCCESS" "Platform initialized successfully"
}

# Function to create network configuration
create_network_config() {
    print_status "INFO" "Creating network configuration..."
    
    # Find primary network interface
    local primary_iface=$(ip route | grep default | awk '{print $5}' | head -1)
    if [ -z "$primary_iface" ]; then
        primary_iface="eth0"
    fi
    
    cat << EOF | sudo tee "$NETWORK_CONFIG" > /dev/null
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
    
    print_status "INFO" "Network configuration created at $NETWORK_CONFIG"
    print_status "INFO" "Please edit $NETWORK_CONFIG to add your public IP addresses"
    print_status "INFO" "Then run: sudo netplan apply"
}

# Function to initialize VM profiles
initialize_vm_profiles() {
    cat << 'EOF' | sudo tee "$CONFIG_DIR/profiles/default.yaml" > /dev/null
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

# Function to get all VM configurations
get_vm_list() {
    find "$VM_BASE_DIR/configs" -name "*.json" -exec basename {} .json \; 2>/dev/null | sort
}

# Function to load VM configuration
load_vm_config() {
    local vm_name=$1
    local config_file="$VM_BASE_DIR/configs/$vm_name.json"
    
    if [[ -f "$config_file" ]]; then
        # Parse JSON configuration
        if command -v jq &> /dev/null; then
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
        else
            # Fallback to source if jq not available
            if [ -f "${config_file%.json}.conf" ]; then
                source "${config_file%.json}.conf"
                return 0
            else
                print_status "ERROR" "Configuration file not found for $vm_name"
                return 1
            fi
        fi
    else
        print_status "ERROR" "Configuration for VM '$vm_name' not found"
        return 1
    fi
}

# Function to save VM configuration
save_vm_config() {
    local config_file="$VM_BASE_DIR/configs/$VM_NAME.json"
    
    # Create JSON configuration
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
    "open": $OPEN_PORTS
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
    
    # Also create a shell-readable config for compatibility
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
OPEN_PORTS='$OPEN_PORTS'
CREATED="$CREATED"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to create new VM (with same user experience as original)
create_new_vm() {
    print_status "INFO" "Creating a new VM"
    
    # OS Selection (same as original)
    print_status "INFO" "Select an OS to set up:"
    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        echo "  $i) $os"
        os_options[$i]="$os"
        ((i++))
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Enter your choice (1-${#OS_OPTIONS[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            break
        else
            print_status "ERROR" "Invalid selection. Try again."
        fi
    done

    # VM Profile Selection (NEW)
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

    # Custom Inputs with validation (same as original)
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            # Check if VM name already exists
            if [[ -f "$VM_BASE_DIR/configs/$VM_NAME.json" ]]; then
                print_status "ERROR" "VM with name '$VM_NAME' already exists"
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter hostname (default: $VM_NAME): ")" HOSTNAME
        HOSTNAME="${HOSTNAME:-$VM_NAME}"
        if validate_input "name" "$HOSTNAME"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    while true; do
        read -s -p "$(print_status "INPUT" "Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        if [ -n "$PASSWORD" ]; then
            break
        else
            print_status "ERROR" "Password cannot be empty"
        fi
    done

    # Public IP Assignment (NEW)
    print_status "INFO" "Network Configuration:"
    while true; do
        read -p "$(print_status "INPUT" "Enter public IPv4 address with CIDR (e.g., 192.168.1.10/24): ")" PUBLIC_IP
        if validate_input "ip" "$PUBLIC_IP"; then
            # Check if IP is already assigned
            if grep -r "$PUBLIC_IP" "$VM_BASE_DIR/configs/" >/dev/null 2>&1; then
                print_status "ERROR" "IP address $PUBLIC_IP is already assigned to another VM"
            else
                break
            fi
        fi
    done

    # MAC Address (auto-generate or manual)
    while true; do
        read -p "$(print_status "INPUT" "Enter MAC address (press Enter to auto-generate): ")" MAC_ADDRESS
        if [ -z "$MAC_ADDRESS" ]; then
            # Generate random MAC address
            MAC_ADDRESS="52:54:00:$(openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/.$//')"
            print_status "INFO" "Auto-generated MAC: $MAC_ADDRESS"
            break
        elif validate_input "mac" "$MAC_ADDRESS"; then
            break
        fi
    done

    # Resource allocation based on profile
    load_profile_settings "$VM_PROFILE"
    
    # Show proposed resources and allow customization
    print_status "INFO" "Profile '$VM_PROFILE' settings:"
    echo "  Memory: ${MEMORY}MB"
    echo "  CPUs: ${CPUS}"
    echo "  Disk: ${DISK_SIZE}"
    
    read -p "$(print_status "INPUT" "Press Enter to accept or 'c' to customize: ")" custom_choice
    if [[ "$custom_choice" == "c" ]]; then
        while true; do
            read -p "$(print_status "INPUT" "Memory in MB (default: ${MEMORY}): ")" custom_memory
            custom_memory="${custom_memory:-$MEMORY}"
            if validate_input "number" "$custom_memory"; then
                MEMORY="$custom_memory"
                break
            fi
        done

        while true; do
            read -p "$(print_status "INPUT" "Number of CPUs (default: ${CPUS}): ")" custom_cpus
            custom_cpus="${custom_cpus:-$CPUS}"
            if validate_input "number" "$custom_cpus"; then
                CPUS="$custom_cpus"
                break
            fi
        done

        while true; do
            read -p "$(print_status "INPUT" "Disk size (default: ${DISK_SIZE}): ")" custom_disk
            custom_disk="${custom_disk:-$DISK_SIZE}"
            if validate_input "size" "$custom_disk"; then
                DISK_SIZE="$custom_disk"
                break
            fi
        done
    fi

    # SSH Port
    while true; do
        read -p "$(print_status "INPUT" "SSH Port (default: 22 inside VM): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-22}"
        if validate_input "port" "$SSH_PORT"; then
            break
        fi
    done

    # Additional ports
    read -p "$(print_status "INPUT" "Additional TCP ports to open (comma-separated, press Enter for none): ")" tcp_ports
    read -p "$(print_status "INPUT" "Additional UDP ports to open (comma-separated, press Enter for none): ")" udp_ports

    # Convert ports to JSON array
    OPEN_PORTS='{"tcp": [], "udp": []}'
    if command -v jq &> /dev/null; then
        if [ -n "$tcp_ports" ] || [ -n "$udp_ports" ]; then
            OPEN_PORTS=$(jq -n \
                --arg tcp "$tcp_ports" \
                --arg udp "$udp_ports" \
                '($tcp | split(",") | map(select(. != ""))) as $tcp_ports |
                 ($udp | split(",") | map(select(. != ""))) as $udp_ports |
                 {"tcp": $tcp_ports, "udp": $udp_ports}')
        fi
    else
        # Simple format if jq not available
        OPEN_PORTS="{\"tcp\": [${tcp_ports//,/, }], \"udp\": [${udp_ports//,/, }]}"
    fi

    # XRDP option for desktop profile
    if [[ "$VM_PROFILE" == "desktop" ]]; then
        XRDP_ENABLED="true"
        XRDP_PORT="3389"
        print_status "INFO" "XRDP will be automatically enabled for desktop VM"
    else
        XRDP_ENABLED="false"
        XRDP_PORT="3389"
    fi

    # DDoS protection
    DDOS_PROTECTION="true"
    if [[ "$VM_PROFILE" == "web" || "$VM_PROFILE" == "game-server" ]]; then
        print_status "INFO" "DDoS protection enabled by default for $VM_PROFILE profile"
    fi

    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"

    # Create VM
    print_status "INFO" "Creating VM '$VM_NAME'..."
    if create_vm_image && create_libvirt_config && setup_ddos_protection; then
        # Save configuration
        save_vm_config
        
        print_status "SUCCESS" "VM '$VM_NAME' created successfully!"
        print_status "INFO" "Public IP: $PUBLIC_IP"
        print_status "INFO" "SSH: ssh $USERNAME@${PUBLIC_IP%/*} -p $SSH_PORT"
        
        if [[ "$XRDP_ENABLED" == "true" ]]; then
            print_status "INFO" "XRDP: Available at ${PUBLIC_IP%/*}:$XRDP_PORT"
        fi
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
    
    print_status "INFO" "Downloading and preparing image..."
    
    # Create directories if they don't exist
    mkdir -p "$VM_BASE_DIR/images" "$VM_BASE_DIR/disks" "$VM_BASE_DIR/isos" "$VM_BASE_DIR/configs"
    
    # Download base image if not exists
    if [[ ! -f "$image_file" ]]; then
        print_status "INFO" "Downloading image from $IMG_URL..."
        if ! wget --progress=bar:force "$IMG_URL" -O "${image_file}.tmp" 2>>"$LOG_FILE"; then
            print_status "ERROR" "Failed to download image from $IMG_URL"
            return 1
        fi
        mv "${image_file}.tmp" "$image_file"
    fi
    
    # Create disk with specified size
    local disk_file="$VM_BASE_DIR/disks/${VM_NAME}.qcow2"
    if ! qemu-img create -f qcow2 -F qcow2 -b "$image_file" "$disk_file" "$DISK_SIZE" 2>>"$LOG_FILE"; then
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
    
    # Generate SSH key for the VM
    if ! ssh-keygen -t ed25519 -f "$seed_dir/id_ed25519" -N "" -q 2>>"$LOG_FILE"; then
        print_status "WARN" "Failed to generate SSH key, using default"
        echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIl3p2l5fQ6cJk7J8V8T7m5Xq2Yw1zL9aKjH8g7n5pB $USERNAME@$HOSTNAME" > "$seed_dir/id_ed25519.pub"
    fi
    
    # Create user-data
    cat > "$seed_dir/user-data" <<EOF
#cloud-config
hostname: $HOSTNAME
fqdn: $HOSTNAME.localdomain
manage_etc_hosts: true
ssh_pwauth: false
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $(echo "$PASSWORD" | openssl passwd -6 -stdin | tr -d '\n')
    ssh_authorized_keys:
      - $(cat "$seed_dir/id_ed25519.pub" 2>/dev/null || echo "")
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
  - sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  - sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
  - systemctl restart sshd
  - echo "vm_name=$VM_NAME" >> /etc/environment
  - echo "vm_profile=$VM_PROFILE" >> /etc/environment
EOF
    
    # Create meta-data
    cat > "$seed_dir/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $HOSTNAME
network-interfaces: |
  auto ens3
  iface ens3 inet static
  address ${PUBLIC_IP%/*}
  gateway $(echo $PUBLIC_IP | cut -d'/' -f1 | sed 's/[0-9]*$/1/')
  netmask $(ipcalc -m "$PUBLIC_IP" 2>/dev/null | cut -d= -f2 || echo "255.255.255.0")
  dns-nameservers 8.8.8.8 1.1.1.1
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
    if ! cloud-localds "$VM_BASE_DIR/isos/${VM_NAME}-seed.iso" \
        "$seed_dir/user-data" \
        "$seed_dir/meta-data" \
        --network-config "$seed_dir/network-config" 2>>"$LOG_FILE"; then
        print_status "ERROR" "Failed to create cloud-init ISO"
        rm -rf "$seed_dir"
        return 1
    fi
    
    # Cleanup
    rm -rf "$seed_dir"
    return 0
}

# Function to create libvirt XML configuration
create_libvirt_config() {
    local xml_file="$LIBVIRT_XML_DIR/$VM_NAME.xml"
    
    # Create XML configuration
    cat > "/tmp/${VM_NAME}.xml" <<EOF
<domain type='kvm'>
  <name>$VM_NAME</name>
  <uuid>$(uuidgen 2>/dev/null || echo "$(cat /proc/sys/kernel/random/uuid)")</uuid>
  <metadata>
    <zynexforge:profile xmlns:zynexforge="http://zynexforge.com">$VM_PROFILE</zynexforge:profile>
  </metadata>
  <memory unit='KiB'>$((MEMORY * 1024))</memory>
  <currentMemory unit='KiB'>$((MEMORY * 1024))</currentMemory>
  <vcpu placement='static'>$CPUS</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-7.2'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <vmport state='off'/>
  </features>
  <cpu mode='host-passthrough' check='none'>
    <topology sockets='1' cores='$CPUS' threads='1'/>
  </cpu>
  <clock offset='utc'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='writeback' io='threads'/>
      <source file='$VM_BASE_DIR/disks/${VM_NAME}.qcow2'/>
      <target dev='vda' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x04' slot='0x00' function='0x0'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$VM_BASE_DIR/isos/${VM_NAME}-seed.iso'/>
      <target dev='sda' bus='sata'/>
      <readonly/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
    </disk>
    <controller type='usb' index='0' model='qemu-xhci' ports='15'>
      <address type='pci' domain='0x0000' bus='0x02' slot='0x00' function='0x0'/>
    </controller>
    <controller type='sata' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x1f' function='0x2'/>
    </controller>
    <controller type='pci' index='0' model='pcie-root'/>
    <controller type='pci' index='1' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='1' port='0x10'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0' multifunction='on'/>
    </controller>
    <controller type='virtio-serial' index='0'>
      <address type='pci' domain='0x0000' bus='0x03' slot='0x00' function='0x0'/>
    </controller>
    <interface type='bridge'>
      <mac address='$MAC_ADDRESS'/>
      <source bridge='br0'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
    </interface>
    <serial type='pty'>
      <target type='isa-serial' port='0'>
        <model name='isa-serial'/>
      </target>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
      <address type='virtio-serial' controller='0' bus='0' port='1'/>
    </channel>
    <input type='tablet' bus='usb'>
      <address type='usb' bus='0' port='1'/>
    </input>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <graphics type='spice' autoport='yes'>
      <listen type='address'/>
      <image compression='off'/>
    </graphics>
    <sound model='ich9'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x1b' function='0x0'/>
    </sound>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x0'/>
    </video>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x05' slot='0x00' function='0x0'/>
    </memballoon>
    <rng model='virtio'>
      <backend model='random'>/dev/urandom</backend>
      <address type='pci' domain='0x0000' bus='0x06' slot='0x00' function='0x0'/>
    </rng>
  </devices>
</domain>
EOF
    
    # Copy to libvirt directory and define VM
    sudo cp "/tmp/${VM_NAME}.xml" "$xml_file"
    if sudo virsh define "$xml_file" 2>>"$LOG_FILE"; then
        print_status "SUCCESS" "Libvirt domain created for $VM_NAME"
        rm -f "/tmp/${VM_NAME}.xml"
        return 0
    else
        print_status "ERROR" "Failed to define libvirt domain"
        rm -f "/tmp/${VM_NAME}.xml"
        return 1
    fi
}

# Function to setup DDoS protection
setup_ddos_protection() {
    if [[ "$DDOS_PROTECTION" != "true" ]]; then
        return 0
    fi
    
    local ip_address="${PUBLIC_IP%/*}"
    local config_file="$CONFIG_DIR/ddos/$VM_NAME.nft"
    
    mkdir -p "$(dirname "$config_file")"
    
    # Create nftables rules for DDoS protection
    cat > "$config_file" <<EOF
#!/usr/sbin/nft -f

# Flush the table if it exists
flush table inet zynexforge_ddos

# Create table
table inet zynexforge_ddos {
    set ${VM_NAME}_blacklist {
        type ipv4_addr
        flags timeout
        timeout 1h
    }
    
    chain input {
        type filter hook input priority filter - 10; policy drop;
        
        # Allow established connections
        ct state established,related accept
        
        # Drop invalid connections
        ct state invalid drop
        
        # Blacklist check
        ip saddr @${VM_NAME}_blacklist drop
        
        # Rate limiting per IP
        ip saddr $ip_address limit rate 1000/second burst 2000 packets accept
        
        # SYN flood protection
        tcp flags syn limit rate 200/second burst 300 packets accept
        tcp flags syn drop
        
        # UDP flood protection
        udp limit rate 1000/second burst 2000 packets accept
        
        # ICMP flood protection
        ip protocol icmp limit rate 100/second burst 200 packets accept
        
        # Accept SSH if needed
        tcp dport {22} ip saddr $ip_address accept
        
        # Drop everything else
        drop
    }
    
    chain forward {
        type filter hook forward priority filter - 10; policy accept;
        
        # Traffic shaping for this VM
        ip daddr $ip_address limit rate 10000/second burst 20000 packets accept
        ip saddr $ip_address limit rate 10000/second burst 20000 packets accept
    }
}
EOF
    
    # Load rules
    if sudo nft -f "$config_file" 2>>"$LOG_FILE"; then
        print_status "SUCCESS" "DDoS protection configured for $VM_NAME ($ip_address)"
        return 0
    else
        print_status "WARN" "Failed to load DDoS protection rules (nftables may not be available)"
        return 1
    fi
}

# Function to start a VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $vm_name"
        
        # Start libvirt domain
        if sudo virsh start "$vm_name" 2>>"$LOG_FILE"; then
            print_status "SUCCESS" "VM $vm_name started"
            print_status "INFO" "Public IP: ${PUBLIC_IP%/*}"
            print_status "INFO" "SSH: ssh $USERNAME@${PUBLIC_IP%/*} -p $SSH_PORT"
            
            if [[ "$XRDP_ENABLED" == "true" ]]; then
                print_status "INFO" "XRDP: Connect to ${PUBLIC_IP%/*}:$XRDP_PORT"
            fi
            
            # Update status in config
            if command -v jq &> /dev/null; then
                jq '.status = "running"' "$VM_BASE_DIR/configs/$vm_name.json" > "/tmp/${vm_name}.tmp"
                mv "/tmp/${vm_name}.tmp" "$VM_BASE_DIR/configs/$vm_name.json"
            fi
        else
            print_status "ERROR" "Failed to start VM $vm_name"
        fi
    fi
}

# Function to stop a VM
stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Stopping VM: $vm_name"
        
        if sudo virsh shutdown "$vm_name" 2>>"$LOG_FILE"; then
            # Wait for shutdown
            sleep 5
            
            # Force stop if still running
            if sudo virsh domstate "$vm_name" 2>/dev/null | grep -q "running"; then
                sudo virsh destroy "$vm_name" 2>>"$LOG_FILE"
            fi
            
            print_status "SUCCESS" "VM $vm_name stopped"
            
            # Update status in config
            if command -v jq &> /dev/null; then
                jq '.status = "stopped"' "$VM_BASE_DIR/configs/$vm_name.json" > "/tmp/${vm_name}.tmp"
                mv "/tmp/${vm_name}.tmp" "$VM_BASE_DIR/configs/$vm_name.json"
            fi
        else
            print_status "ERROR" "Failed to stop VM $vm_name"
        fi
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
            if sudo virsh domstate "$vm_name" 2>/dev/null | grep -q "running"; then
                stop_vm "$vm_name"
            fi
            
            # Undefine libvirt domain
            sudo virsh undefine "$vm_name" --nvram 2>/dev/null || true
            
            # Remove files
            rm -f "$VM_BASE_DIR/disks/${vm_name}.qcow2"
            rm -f "$VM_BASE_DIR/isos/${vm_name}-seed.iso"
            rm -f "$VM_BASE_DIR/configs/${vm_name}.json"
            rm -f "$VM_BASE_DIR/configs/${vm_name}.conf"
            sudo rm -f "$LIBVIRT_XML_DIR/${vm_name}.xml"
            sudo rm -f "$CONFIG_DIR/ddos/${vm_name}.nft"
            
            print_status "SUCCESS" "VM '$vm_name' has been completely deleted"
        fi
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

# Function to enable XRDP (one-click feature)
enable_xrdp() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Enabling XRDP for $vm_name..."
        
        # Check if VM is running
        if ! sudo virsh domstate "$vm_name" 2>/dev/null | grep -q "running"; then
            print_status "ERROR" "VM must be running to enable XRDP. Starting VM first..."
            start_vm "$vm_name"
            sleep 10
        fi
        
        # Get VM IP
        local vm_ip="${PUBLIC_IP%/*}"
        
        # Create installation script
        local install_script="/tmp/install_xrdp_${vm_name}.sh"
        cat > "$install_script" <<'EOF'
#!/bin/bash
set -e

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    echo "Cannot detect OS"
    exit 1
fi

# Install XRDP based on OS
case $OS in
    ubuntu|debian)
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y xrdp xorgxrdp
        systemctl enable xrdp
        systemctl start xrdp
        
        # Configure firewall
        if command -v ufw &> /dev/null; then
            ufw allow 3389/tcp
        fi
        
        # Add to xrdp user group
        usermod -a -G ssl-cert xrdp 2>/dev/null || true
        
        # Configure desktop environment
        if [ -f /usr/bin/xfce4-session ]; then
            echo "xfce4-session" > ~/.xsession
        elif [ -f /usr/bin/gnome-session ]; then
            echo "gnome-session" > ~/.xsession
        elif [ -f /usr/bin/startplasma-x11 ]; then
            echo "startplasma-x11" > ~/.xsession
        else
            echo "xterm" > ~/.xsession
        fi
        ;;
        
    fedora|centos|rhel|rocky|almalinux)
        if command -v dnf &> /dev/null; then
            dnf install -y xrdp xorgxrdp
        else
            yum install -y xrdp xorgxrdp
        fi
        systemctl enable xrdp
        systemctl start xrdp
        
        # Configure firewall
        if command -v firewall-cmd &> /dev/null; then
            firewall-cmd --permanent --add-port=3389/tcp
            firewall-cmd --reload
        fi
        
        # Configure desktop environment
        if [ -f /usr/bin/gnome-session ]; then
            echo "gnome-session" > ~/.Xclients
        elif [ -f /usr/bin/startxfce4 ]; then
            echo "startxfce4" > ~/.Xclients
        else
            echo "xterm" > ~/.Xclients
        fi
        chmod +x ~/.Xclients
        ;;
        
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

# Configure XRDP
sed -i 's/port=3389/port=3389\nmax_bpp=32\ndefault.bpp=32/' /etc/xrdp/xrdp.ini 2>/dev/null || true

echo "XRDP installed and configured successfully"
echo "Connect using: $(hostname -I | awk '{print $1}'):3389"
EOF
        
        # Make script executable
        chmod +x "$install_script"
        
        # Copy script to VM using SSH
        print_status "INFO" "Installing XRDP on $vm_name ($vm_ip)..."
        
        # Try SSH with password
        if sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
            "$install_script" "$USERNAME@$vm_ip:/tmp/install_xrdp.sh" 2>>"$LOG_FILE"; then
            
            if sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
                "$USERNAME@$vm_ip" "sudo bash /tmp/install_xrdp.sh" 2>>"$LOG_FILE"; then
                
                # Update config
                if command -v jq &> /dev/null; then
                    jq '.xrdp.enabled = true' "$VM_BASE_DIR/configs/$vm_name.json" > "/tmp/${vm_name}.tmp"
                    mv "/tmp/${vm_name}.tmp" "$VM_BASE_DIR/configs/$vm_name.json"
                fi
                
                print_status "SUCCESS" "XRDP enabled for $vm_name"
                print_status "INFO" "Connect using: ${vm_ip}:3389"
                print_status "INFO" "Username: $USERNAME"
                print_status "INFO" "Password: $PASSWORD"
            else
                print_status "ERROR" "Failed to execute XRDP installation script"
            fi
        else
            print_status "ERROR" "Failed to copy XRDP installation script to VM"
            print_status "INFO" "Make sure VM is running and SSH is accessible"
        fi
        
        rm -f "$install_script"
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
        echo "Status: $(sudo virsh domstate "$vm_name" 2>/dev/null || echo 'unknown')"
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
        
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
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
            echo "  8) Enable/Disable DDoS Protection"
            echo "  0) Back to main menu"
            
            read -p "$(print_status "INPUT" "Enter your choice: ")" edit_choice
            
            case $edit_choice in
                1)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new hostname (current: $HOSTNAME): ")" new_hostname
                        new_hostname="${new_hostname:-$HOSTNAME}"
                        if validate_input "name" "$new_hostname"; then
                            HOSTNAME="$new_hostname"
                            break
                        fi
                    done
                    ;;
                2)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new username (current: $USERNAME): ")" new_username
                        new_username="${new_username:-$USERNAME}"
                        if validate_input "username" "$new_username"; then
                            USERNAME="$new_username"
                            break
                        fi
                    done
                    ;;
                3)
                    while true; do
                        read -s -p "$(print_status "INPUT" "Enter new password (current: ****): ")" new_password
                        new_password="${new_password:-$PASSWORD}"
                        echo
                        if [ -n "$new_password" ]; then
                            PASSWORD="$new_password"
                            break
                        else
                            print_status "ERROR" "Password cannot be empty"
                        fi
                    done
                    ;;
                4)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new memory in MB (current: $MEMORY): ")" new_memory
                        new_memory="${new_memory:-$MEMORY}"
                        if validate_input "number" "$new_memory"; then
                            MEMORY="$new_memory"
                            break
                        fi
                    done
                    ;;
                5)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new CPU count (current: $CPUS): ")" new_cpus
                        new_cpus="${new_cpus:-$CPUS}"
                        if validate_input "number" "$new_cpus"; then
                            CPUS="$new_cpus"
                            break
                        fi
                    done
                    ;;
                6)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new disk size (current: $DISK_SIZE): ")" new_disk_size
                        new_disk_size="${new_disk_size:-$DISK_SIZE}"
                        if validate_input "size" "$new_disk_size"; then
                            DISK_SIZE="$new_disk_size"
                            break
                        fi
                    done
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
                    if [[ "$DDOS_PROTECTION" == "true" ]]; then
                        DDOS_PROTECTION="false"
                        print_status "INFO" "DDoS protection disabled"
                    else
                        DDOS_PROTECTION="true"
                        print_status "INFO" "DDoS protection enabled"
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

# Main menu function (same structure as original)
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Found $vm_count existing VM(s):"
            for i in "${!vms[@]}"; do
                local status="unknown"
                if sudo virsh list --all 2>/dev/null | grep -q " ${vms[$i]} "; then
                    if sudo virsh domstate "${vms[$i]}" 2>/dev/null | grep -q "running"; then
                        status="Running"
                    else
                        status="Stopped"
                    fi
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
            echo "  8) Show platform status"
        fi
        echo "  9) Initialize/Repair Platform"
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
                show_platform_status
                ;;
            9)
                initialize_platform
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

# Function to show platform status
show_platform_status() {
    echo
    print_status "INFO" "Platform Status"
    echo "=========================================="
    echo "Hypervisor: $(sudo virsh version 2>/dev/null | grep -i 'running' | head -1 || echo 'Not available')"
    echo "Total VMs: $(sudo virsh list --all 2>/dev/null | grep -c -E 'running|shut off' || echo '0')"
    echo "Running VMs: $(sudo virsh list --state-running 2>/dev/null | grep -c running || echo '0')"
    echo "Bridge Interface: $(ip link show br0 2>/dev/null | grep -c UP || echo 'Not active')"
    echo "Storage Pool: $(sudo virsh pool-list --all 2>/dev/null | grep -c default || echo '0')"
    echo "Log File: $LOG_FILE"
    echo "Config Directory: $CONFIG_DIR"
    echo "VM Directory: $VM_BASE_DIR"
    echo "=========================================="
    echo
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Supported OS list (same as original)
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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_status "WARN" "Running as root is not recommended. Please run as regular user with sudo privileges."
    read -p "$(print_status "INPUT" "Continue anyway? (y/N): ")" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Main execution
check_dependencies
initialize_platform
main_menu
