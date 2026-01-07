#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge VPS Platform
# =============================

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
                                                                         

                ⚡ ZynexForge VPS Platform - Professional VM Management ⚡
                High-Performance KVM Virtualization with DDoS Protection
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
        "SECURITY") echo -e "\033[1;35m[SECURITY]\033[0m $message" ;;
        "NETWORK") echo -e "\033[1;94m[NETWORK]\033[0m $message" ;;
        "TMATCHAT") echo -e "\033[1;93m[TMATCHAT]\033[0m $message" ;;
        *) echo "[$type] $message" ;;
    esac
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
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "Must be a valid port number (1-65535)"
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
        "ipv4")
            if ! [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]] && ! [[ "$value" =~ ^dhcp$ ]]; then
                print_status "ERROR" "Must be a valid IPv4 address with optional CIDR (e.g., 192.168.1.100/24) or 'dhcp'"
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

# Function to check dependencies
check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "tmate" "bridge-utils" "ipcalc")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "On Ubuntu/Debian, try: sudo apt install qemu-system cloud-image-utils wget tmate bridge-utils ipcalc"
        exit 1
    fi
}

# Function to cleanup temporary files
cleanup() {
    if [ -f "user-data" ]; then rm -f "user-data"; fi
    if [ -f "meta-data" ]; then rm -f "meta-data"; fi
}

# Function to generate secure password
generate_password() {
    local length=${1:-12}
    tr -dc 'A-Za-z0-9@#$%^&*+' < /dev/urandom | head -c "$length"
    echo
}

# Function to generate SSH keys
generate_ssh_keys() {
    local vm_name=$1
    local ssh_dir="$VM_DIR/$vm_name/ssh"
    
    mkdir -p "$ssh_dir"
    
    # Generate root SSH key
    if [ ! -f "$ssh_dir/root_id_rsa" ]; then
        ssh-keygen -t rsa -b 4096 -f "$ssh_dir/root_id_rsa" -N "" -q
        cp "$ssh_dir/root_id_rsa.pub" "$ssh_dir/authorized_keys"
    fi
    
    # Generate user SSH key
    if [ ! -f "$ssh_dir/user_id_rsa" ]; then
        ssh-keygen -t rsa -b 4096 -f "$ssh_dir/user_id_rsa" -N "" -q
        cat "$ssh_dir/user_id_rsa.pub" >> "$ssh_dir/authorized_keys"
    fi
}

# Function to get all VM configurations
get_vm_list() {
    find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

# Function to load VM configuration
load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf"
    
    if [[ -f "$config_file" ]]; then
        # Clear previous variables
        unset VM_NAME VM_ROLE OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        unset NETWORK_MODE BRIDGE_NAME MAC_ADDRESS IPV4_ADDRESS GATEWAY DNS_SERVERS
        unset XRDP_INSTALLED XRDP_PORT XRDP_ENABLED OPEN_PORTS
        unset DDoS_PROTECTION CPU_PINNING LOW_LATENCY TUNING
        
        source "$config_file"
        return 0
    else
        print_status "ERROR" "Configuration for VM '$vm_name' not found"
        return 1
    fi
}

# Function to save VM configuration
save_vm_config() {
    local config_file="$VM_DIR/$VM_NAME.conf"
    local vm_dir="$VM_DIR/$VM_NAME"
    
    mkdir -p "$vm_dir"
    
    cat > "$config_file" <<EOF
VM_NAME="$VM_NAME"
VM_ROLE="$VM_ROLE"
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
NETWORK_MODE="$NETWORK_MODE"
BRIDGE_NAME="$BRIDGE_NAME"
MAC_ADDRESS="$MAC_ADDRESS"
IPV4_ADDRESS="$IPV4_ADDRESS"
GATEWAY="$GATEWAY"
DNS_SERVERS="$DNS_SERVERS"
XRDP_INSTALLED="$XRDP_INSTALLED"
XRDP_PORT="$XRDP_PORT"
XRDP_ENABLED="$XRDP_ENABLED"
OPEN_PORTS="$OPEN_PORTS"
DDoS_PROTECTION="$DDoS_PROTECTION"
CPU_PINNING="$CPU_PINNING"
LOW_LATENCY_TUNING="$LOW_LATENCY_TUNING"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to configure network bridge
setup_network_bridge() {
    print_status "NETWORK" "Configuring network..."
    
    # Check if bridge exists
    if ! ip link show "$BRIDGE_NAME" &>/dev/null; then
        print_status "WARN" "Bridge $BRIDGE_NAME does not exist. Creating..."
        sudo brctl addbr "$BRIDGE_NAME"
        sudo ip link set "$BRIDGE_NAME" up
    fi
    
    # Generate MAC if not provided
    if [ -z "$MAC_ADDRESS" ]; then
        MAC_ADDRESS="52:54:00:$(openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/.$//')"
        print_status "INFO" "Generated MAC address: $MAC_ADDRESS"
    fi
}

# Function to create VM profiles
apply_vm_profile() {
    local profile="$1"
    
    case "$profile" in
        "gameserver")
            VM_ROLE="Game Server"
            LOW_LATENCY_TUNING=true
            CPU_PINNING=true
            DDoS_PROTECTION=true
            OPEN_PORTS="22,80,443,25565-25575,27015-27030,9987,30033"
            ;;
        "workload")
            VM_ROLE="Heavy Workload"
            LOW_LATENCY_TUNING=false
            CPU_PINNING=true
            DDoS_PROTECTION=true
            OPEN_PORTS="22,80,443,3306,5432,6379"
            ;;
        "desktop")
            VM_ROLE="XRDP Desktop"
            GUI_MODE=true
            XRDP_INSTALLED=false
            XRDP_PORT=3389
            XRDP_ENABLED=false
            LOW_LATENCY_TUNING=false
            CPU_PINNING=false
            DDoS_PROTECTION=true
            OPEN_PORTS="22,3389"
            ;;
        "custom")
            VM_ROLE="Custom"
            LOW_LATENCY_TUNING=false
            CPU_PINNING=false
            DDoS_PROTECTION=false
            OPEN_PORTS="22"
            ;;
    esac
}

# Function to setup DDoS protection
setup_ddos_protection() {
    local vm_name=$1
    local ip_address=$2
    
    if [[ "$DDoS_PROTECTION" != "true" ]]; then
        return 0
    fi
    
    print_status "SECURITY" "Setting up DDoS protection for $ip_address"
    
    # Create nftables ruleset for the VM
    local nft_rules="/etc/nftables.conf.d/$vm_name.conf"
    
    sudo tee "$nft_rules" > /dev/null <<EOF
table inet $vm_name {
    set blacklist {
        type ipv4_addr
        flags timeout
        timeout 1h
    }
    
    chain input {
        type filter hook input priority 0; policy drop;
        
        # Allow established connections
        ct state established,related accept
        
        # Allow loopback
        iif lo accept
        
        # Rate limiting for SYN packets
        tcp flags syn tcp dport {22,80,443} limit rate over 10/second burst 20 packets add @blacklist { ip saddr }
        
        # Rate limiting for UDP packets
        udp dport {27015,27016,27017,25565} limit rate over 1000/second burst 2000 packets add @blacklist { ip saddr }
        
        # Drop blacklisted IPs
        ip saddr @blacklist drop
        
        # Connection tracking limits
        ct state new limit rate over 50/second burst 100 packets drop
        
        # Allow specific ports
        tcp dport { ${OPEN_PORTS//,/ } } accept
        udp dport { ${OPEN_PORTS//,/ } } accept
        
        # Drop everything else
        drop
    }
    
    chain forward {
        type filter hook forward priority 0; policy accept;
        
        # Limit forwarded packets to VM
        ip daddr $ip_address limit rate over 10000/second burst 20000 packets drop
    }
}
EOF
    
    # Reload nftables
    sudo nft -f "$nft_rules"
    print_status "SUCCESS" "DDoS protection rules applied"
}

# Function to start tmate session
start_tmate_session() {
    local vm_name=$1
    
    print_status "TMATCHAT" "Starting secure tmate session for VM: $vm_name"
    echo "================================================================================"
    echo "This tmate session will allow you to connect to this VM management interface"
    echo "from anywhere for 24 hours. Share the SSH connection string below securely."
    echo "================================================================================"
    echo
    
    # Start tmate with specific socket
    TMATE_SOCKET="/tmp/tmate-$vm_name.sock"
    
    tmate -S "$TMATE_SOCKET" new-session -d -s "$vm_name"
    tmate -S "$TMATE_SOCKET" wait tmate-ready
    
    # Get connection strings
    TMATE_SSH=$(tmate -S "$TMATE_SOCKET" display -p '#{tmate_ssh}')
    TMATE_WEB=$(tmate -S "$TMATE_SOCKET" display -p '#{tmate_web}')
    
    print_status "TMATCHAT" "SSH Connection: $TMATE_SSH"
    print_status "TMATCHAT" "Web URL: https://$TMATE_WEB"
    print_status "TMATCHAT" ""
    print_status "TMATCHAT" "This session will expire in 24 hours."
    print_status "TMATCHAT" "To close session: Ctrl+C or 'tmate -S $TMATE_SOCKET kill-session'"
    echo
    
    # Show session in background
    tmate -S "$TMATE_SOCKET" attach
}

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating a new VM"
    
    # VM Profile Selection
    print_status "INFO" "Select VM Profile:"
    echo "  1) Game Server (Low latency, DDoS protection, UDP optimized)"
    echo "  2) Heavy Workload (High CPU/Memory, Production ready)"
    echo "  3) XRDP Desktop (GUI, Remote desktop ready)"
    echo "  4) Custom (Configure manually)"
    
    while true; do
        read -p "$(print_status "INPUT" "Enter your choice (1-4): ")" profile_choice
        case "$profile_choice" in
            1) apply_vm_profile "gameserver"; break ;;
            2) apply_vm_profile "workload"; break ;;
            3) apply_vm_profile "desktop"; break ;;
            4) apply_vm_profile "custom"; break ;;
            *) print_status "ERROR" "Invalid selection. Try again." ;;
        esac
    done
    
    # OS Selection
    print_status "INFO" "Select an OS:"
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

    # Custom Inputs with validation
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
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

    # Generate secure password
    PASSWORD=$(generate_password 16)
    print_status "SUCCESS" "Generated secure password: $PASSWORD"
    
    # Ask if user wants to add their own SSH key
    read -p "$(print_status "INPUT" "Add your SSH public key? (optional, paste key or press Enter to skip): ")" user_ssh_key

    # Network Configuration
    print_status "NETWORK" "Network Configuration"
    NETWORK_MODE="bridge"
    
    while true; do
        read -p "$(print_status "INPUT" "Bridge name (default: br0): ")" BRIDGE_NAME
        BRIDGE_NAME="${BRIDGE_NAME:-br0}"
        if [ -n "$BRIDGE_NAME" ]; then
            break
        fi
    done
    
    while true; do
        read -p "$(print_status "INPUT" "MAC address (press Enter to auto-generate): ")" MAC_ADDRESS
        if [ -z "$MAC_ADDRESS" ]; then
            MAC_ADDRESS="52:54:00:$(openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/.$//')"
            break
        elif validate_input "mac" "$MAC_ADDRESS"; then
            break
        fi
    done
    
    while true; do
        read -p "$(print_status "INPUT" "IPv4 Address/CIDR (e.g., 192.168.1.100/24) or 'dhcp': ")" IPV4_ADDRESS
        IPV4_ADDRESS="${IPV4_ADDRESS:-dhcp}"
        if validate_input "ipv4" "$IPV4_ADDRESS"; then
            break
        fi
    done
    
    if [[ "$IPV4_ADDRESS" != "dhcp" ]]; then
        IFS='/' read -r ip_addr cidr <<< "$IPV4_ADDRESS"
        GATEWAY="${ip_addr%.*}.1"
        DNS_SERVERS="8.8.8.8,8.8.4.4"
    fi

    # Resource Configuration
    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 50G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-50G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Memory in MB (default: 4096): ")" MEMORY
        MEMORY="${MEMORY:-4096}"
        if validate_input "number" "$MEMORY"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (default: 4): ")" CPUS
        CPUS="${CPUS:-4}"
        if validate_input "number" "$CPUS"; then
            break
        fi
    done

    SSH_PORT=22  # Standard SSH port for bridge networking
    
    # GUI mode for desktop VMs
    if [[ "$VM_ROLE" == "XRDP Desktop" ]]; then
        GUI_MODE=true
        read -p "$(print_status "INPUT" "Install XRDP automatically? (y/N): ")" install_xrdp
        if [[ "$install_xrdp" =~ ^[Yy]$ ]]; then
            XRDP_INSTALLED=true
            XRDP_PORT=3389
            XRDP_ENABLED=true
        fi
    else
        GUI_MODE=false
        XRDP_INSTALLED=false
    fi

    # Additional port configuration
    if [[ "$VM_ROLE" == "Game Server" ]]; then
        PORT_FORWARDS=""
        print_status "INFO" "Game Server ports will be open: $OPEN_PORTS"
    else
        read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80, press Enter for none): ")" PORT_FORWARDS
    fi

    # DDoS Protection
    if [[ "$DDoS_PROTECTION" == "true" ]]; then
        print_status "SECURITY" "DDoS protection will be enabled for this VM"
    else
        read -p "$(print_status "INPUT" "Enable DDoS protection? (Y/n): ")" ddos_choice
        ddos_choice="${ddos_choice:-y}"
        if [[ "$ddos_choice" =~ ^[Yy]$ ]]; then
            DDoS_PROTECTION=true
        fi
    fi

    IMG_FILE="$VM_DIR/$VM_NAME/disk.img"
    SEED_FILE="$VM_DIR/$VM_NAME/seed.iso"
    CREATED="$(date)"

    # Generate SSH keys
    generate_ssh_keys "$VM_NAME"
    
    # Setup network bridge
    setup_network_bridge
    
    # Download and setup VM image
    setup_vm_image "$user_ssh_key"
    
    # Save configuration
    save_vm_config
    
    # Setup DDoS protection if enabled
    if [[ "$DDoS_PROTECTION" == "true" ]] && [[ "$IPV4_ADDRESS" != "dhcp" ]]; then
        setup_ddos_protection "$VM_NAME" "$ip_addr"
    fi
    
    print_status "SUCCESS" "VM '$VM_NAME' created successfully!"
    print_status "INFO" "Role: $VM_ROLE"
    print_status "INFO" "IP: $IPV4_ADDRESS"
    print_status "INFO" "SSH: ssh $USERNAME@${ip_addr:-$HOSTNAME}"
    print_status "INFO" "Password: $PASSWORD"
    if [[ "$XRDP_INSTALLED" == "true" ]]; then
        print_status "INFO" "XRDP: xfreerdp /v:${ip_addr:-$HOSTNAME}:$XRDP_PORT"
    fi
}

# Function to setup VM image with dual authentication
setup_vm_image() {
    local user_ssh_key="$1"
    print_status "INFO" "Downloading and preparing image..."
    
    # Create VM directory
    mkdir -p "$VM_DIR/$VM_NAME"
    
    # Check if image already exists
    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "Image file already exists. Skipping download."
    else
        print_status "INFO" "Downloading image from $IMG_URL..."
        if ! wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp"; then
            print_status "ERROR" "Failed to download image from $IMG_URL"
            exit 1
        fi
        mv "$IMG_FILE.tmp" "$IMG_FILE"
    fi
    
    # Resize the disk image
    if ! qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
        print_status "WARN" "Failed to resize disk image. Creating new image..."
        rm -f "$IMG_FILE"
        qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
    fi

    # Prepare authorized_keys
    local auth_keys="$VM_DIR/$VM_NAME/ssh/authorized_keys"
    
    # Add user's SSH key if provided
    if [ -n "$user_ssh_key" ]; then
        echo "$user_ssh_key" >> "$auth_keys"
        print_status "SUCCESS" "Added your SSH key to authorized_keys"
    fi

    # cloud-init configuration with dual authentication
    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true  # Enable password authentication
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD" | tr -d '\n')
    ssh_authorized_keys:
$(awk '{print "      - " $0}' "$auth_keys")
  - name: root
    ssh_authorized_keys:
$(awk '{print "      - " $0}' "$auth_keys")

chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false

# Configure SSH for dual authentication
ssh_genkeytypes: ['rsa', 'ecdsa']
ssh_authorized_keys:
$(awk '{print "  - " $0}' "$auth_keys")

# Configure network if static IP
$(if [[ "$IPV4_ADDRESS" != "dhcp" ]]; then
echo "network:
  version: 2
  ethernets:
    eth0:
      match:
        macaddress: '$MAC_ADDRESS'
      addresses:
        - $IPV4_ADDRESS
      gateway4: $GATEWAY
      nameservers:
        addresses: [${DNS_SERVERS//,/ }]"
fi)

# Install XRDP for desktop VMs
$(if [[ "$XRDP_INSTALLED" == "true" ]]; then
echo "packages:
  - xrdp
  - xfce4
  - xfce4-goodies
runcmd:
  - systemctl enable xrdp
  - systemctl start xrdp
  - ufw allow 3389/tcp
  - echo 'xfce4-session' > /home/$USERNAME/.xsession
  - chown $USERNAME:$USERNAME /home/$USERNAME/.xsession"
fi)

# Apply performance tuning for game servers
$(if [[ "$LOW_LATENCY_TUNING" == "true" ]]; then
echo "bootcmd:
  - echo 'net.core.rmem_max=134217728' >> /etc/sysctl.conf
  - echo 'net.core.wmem_max=134217728' >> /etc/sysctl.conf
  - echo 'net.ipv4.tcp_rmem=4096 87380 134217728' >> /etc/sysctl.conf
  - echo 'net.ipv4.tcp_wmem=4096 65536 134217728' >> /etc/sysctl.conf
  - echo 'net.core.netdev_max_backlog=30000' >> /etc/sysctl.conf
  - echo 'vm.swappiness=10' >> /etc/sysctl.conf
runcmd:
  - sysctl -p"
fi)

power_state:
  mode: reboot
  timeout: 300
  message: Rebooting after cloud-init configuration
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    if ! cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
    
    print_status "SUCCESS" "VM '$VM_NAME' configured with dual authentication"
}

# Function to start a VM with bridge networking
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $vm_name"
        
        # Check if VM is already running
        if is_vm_running "$vm_name"; then
            print_status "ERROR" "VM '$vm_name' is already running"
            return 1
        fi
        
        # Check if image file exists
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "VM image file not found: $IMG_FILE"
            return 1
        fi
        
        # Check if seed file exists
        if [[ ! -f "$SEED_FILE" ]]; then
            print_status "WARN" "Seed file not found, recreating..."
            setup_vm_image
        fi
        
        # Setup network bridge
        setup_network_bridge
        
        # Create tap interface
        local tap_iface="tap-$vm_name"
        sudo ip tuntap add dev "$tap_iface" mode tap user "$(whoami)"
        sudo ip link set "$tap_iface" up
        sudo brctl addif "$BRIDGE_NAME" "$tap_iface"
        
        # Build QEMU command with bridge networking
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -cpu host,migratable=off
            -m "$MEMORY"
            -smp "$CPUS",sockets=1,cores="$CPUS",threads=1
            -drive "file=$IMG_FILE,format=qcow2,if=virtio,cache=writeback,discard=on"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -boot order=c
            -netdev "tap,id=net0,ifname=$tap_iface,script=no,downscript=no"
            -device "virtio-net-pci,netdev=net0,mac=$MAC_ADDRESS"
            -vga virtio
            -display none
            -daemonize
            -name "$vm_name"
        )
        
        # Add CPU pinning for performance
        if [[ "$CPU_PINNING" == "true" ]]; then
            local cpu_count=$(nproc)
            for ((i=0; i<CPUS; i++)); do
                local cpu=$((i % cpu_count))
                qemu_cmd+=(-vcpu "vcpu=$i,cpuset=$cpu")
            done
        fi
        
        # Add low latency tuning
        if [[ "$LOW_LATENCY_TUNING" == "true" ]]; then
            qemu_cmd+=(
                -device virtio-balloon-pci
                -object rng-random,filename=/dev/urandom,id=rng0
                -device virtio-rng-pci,rng=rng0
                -machine type=pc,accel=kvm,kernel-irqchip=split
            )
        fi
        
        # Add monitor socket for management
        local monitor_socket="/tmp/qemu-$vm_name.monitor"
        qemu_cmd+=(
            -monitor "unix:$monitor_socket,server,nowait"
            -serial "unix:/tmp/qemu-$vm_name.serial,server,nowait"
        )
        
        print_status "INFO" "Starting QEMU with bridge networking..."
        print_status "INFO" "MAC: $MAC_ADDRESS"
        print_status "INFO" "Bridge: $BRIDGE_NAME"
        
        # Start QEMU
        if ! "${qemu_cmd[@]}"; then
            print_status "ERROR" "Failed to start QEMU"
            sudo ip link delete "$tap_iface"
            return 1
        fi
        
        # Wait for VM to boot
        sleep 5
        
        # Get IP address
        local vm_ip=""
        if [[ "$IPV4_ADDRESS" != "dhcp" ]]; then
            vm_ip="${IPV4_ADDRESS%/*}"
        else
            # Try to get IP from DHCP
            for i in {1..30}; do
                vm_ip=$(sudo arp -n | grep -i "$MAC_ADDRESS" | awk '{print $1}')
                if [ -n "$vm_ip" ]; then
                    break
                fi
                sleep 2
            done
        fi
        
        # Display connection information
        echo
        print_status "SUCCESS" "VM '$vm_name' is now running!"
        print_status "INFO" "Role: $VM_ROLE"
        print_status "INFO" "IP Address: ${vm_ip:-$IPV4_ADDRESS}"
        print_status "INFO" "SSH Access: ssh $USERNAME@${vm_ip:-$IPV4_ADDRESS}"
        print_status "INFO" "Password: $PASSWORD"
        
        if [[ "$XRDP_INSTALLED" == "true" ]] && [[ "$XRDP_ENABLED" == "true" ]]; then
            print_status "INFO" "XRDP Access: xfreerdp /v:${vm_ip:-$IPV4_ADDRESS}:$XRDP_PORT"
            print_status "INFO" "XRDP Username: $USERNAME"
            print_status "INFO" "XRDP Password: $PASSWORD"
        fi
        
        print_status "INFO" "Open Ports: $OPEN_PORTS"
        
        # Display SSH key locations
        echo
        print_status "SECURITY" "SSH Keys for this VM:"
        print_status "INFO" "Root key: $VM_DIR/$vm_name/ssh/root_id_rsa"
        print_status "INFO" "User key: $VM_DIR/$vm_name/ssh/user_id_rsa"
        
        # Offer tmate session
        echo
        read -p "$(print_status "INPUT" "Start tmate session for remote management? (y/N): ")" start_tmate
        if [[ "$start_tmate" =~ ^[Yy]$ ]]; then
            start_tmate_session "$vm_name"
        fi
    fi
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    if pgrep -f "qemu-system-x86_64.*-name $vm_name" >/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to stop a running VM
stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM: $vm_name"
            
            # Try graceful shutdown via monitor
            local monitor_socket="/tmp/qemu-$vm_name.monitor"
            if [ -S "$monitor_socket" ]; then
                echo "system_powerdown" | socat - UNIX-CONNECT:"$monitor_socket"
                sleep 5
            fi
            
            # Force stop if still running
            if is_vm_running "$vm_name"; then
                pkill -f "qemu-system-x86_64.*-name $vm_name"
                sleep 2
                if is_vm_running "$vm_name"; then
                    pkill -9 -f "qemu-system-x86_64.*-name $vm_name"
                fi
            fi
            
            # Cleanup tap interface
            local tap_iface="tap-$vm_name"
            sudo ip link delete "$tap_iface" 2>/dev/null || true
            
            # Cleanup sockets
            rm -f "/tmp/qemu-$vm_name.monitor" "/tmp/qemu-$vm_name.serial"
            
            print_status "SUCCESS" "VM $vm_name stopped"
        else
            print_status "INFO" "VM $vm_name is not running"
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
        # Stop VM if running
        if is_vm_running "$vm_name"; then
            stop_vm "$vm_name"
        fi
        
        # Remove DDoS protection rules
        sudo rm -f "/etc/nftables.conf.d/$vm_name.conf"
        
        # Remove VM files
        rm -rf "$VM_DIR/$vm_name" "$VM_DIR/$vm_name.conf"
        
        print_status "SUCCESS" "VM '$vm_name' has been deleted"
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo
        print_status "INFO" "VM Information: $vm_name"
        echo "=========================================="
        echo "Role: $VM_ROLE"
        echo "OS: $OS_TYPE"
        echo "Hostname: $HOSTNAME"
        echo "Username: $USERNAME"
        echo "Password: $PASSWORD (use SSH keys for better security)"
        echo "IP Address: $IPV4_ADDRESS"
        echo "MAC Address: $MAC_ADDRESS"
        echo "Bridge: $BRIDGE_NAME"
        echo "SSH Access: ssh $USERNAME@${IPV4_ADDRESS%/*}"
        echo "Memory: $MEMORY MB"
        echo "CPUs: $CPUS"
        echo "Disk: $DISK_SIZE"
        echo "Created: $CREATED"
        echo "DDoS Protection: $DDoS_PROTECTION"
        echo "CPU Pinning: $CPU_PINNING"
        echo "Low Latency Tuning: $LOW_LATENCY_TUNING"
        
        if [[ "$XRDP_INSTALLED" == "true" ]]; then
            echo "XRDP: Enabled (Port: $XRDP_PORT)"
            echo "XRDP Connection: xfreerdp /v:${IPV4_ADDRESS%/*}:$XRDP_PORT"
        fi
        
        echo "Open Ports: ${OPEN_PORTS:-None}"
        echo "=========================================="
        echo
        
        # Show SSH key locations
        if [ -d "$VM_DIR/$vm_name/ssh" ]; then
            print_status "SECURITY" "SSH Keys available in: $VM_DIR/$vm_name/ssh/"
        fi
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
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
                if is_vm_running "${vms[$i]}"; then
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
            echo "  5) Start tmate session for VM"
            echo "  6) Delete a VM"
        fi
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
                    read -p "$(print_status "INPUT" "Enter VM number for tmate session: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        start_tmate_session "${vms[$((vm_num-1))]}"
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

# Set trap to cleanup on exit
trap cleanup EXIT

# Check dependencies
check_dependencies

# Check for root privileges for network operations
if [ "$EUID" -ne 0 ]; then
    print_status "WARN" "Some operations require root privileges (network bridge setup)"
    print_status "INFO" "You may be prompted for sudo password during VM operations"
fi

# Initialize paths
VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

# Supported OS list
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04 LTS"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04 LTS"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
)

# Start the main menu
main_menu
