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
        "PERFORMANCE") echo -e "\033[1;95m[PERFORMANCE]\033[0m $message" ;;
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
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "tmate" "git" "htop" "docker" "docker-compose" "python3" "node" "java")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "Please install required packages first"
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

# Function to calculate network using python
calculate_network() {
    local ip_cidr=$1
    python3 -c "
import ipaddress
try:
    net = ipaddress.ip_network('$ip_cidr', strict=False)
    print(f'{net.network_address}/{net.prefixlen}')
    print(f'{net.netmask}')
    print(f'{net.network_address + 1}')  # Gateway
except Exception as e:
    print('ERROR')
"
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
    
    # Generate tmate keys if needed
    if [ ! -f "$ssh_dir/tmate_rsa" ]; then
        ssh-keygen -t rsa -b 4096 -f "$ssh_dir/tmate_rsa" -N "" -q
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
        unset DDoS_PROTECTION CPU_PINNING LOW_LATENCY_TUNING
        unset MONITOR_SOCKET SERIAL_SOCKET TAP_INTERFACE
        
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
MONITOR_SOCKET="$MONITOR_SOCKET"
SERIAL_SOCKET="$SERIAL_SOCKET"
TAP_INTERFACE="$TAP_INTERFACE"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to create network bridge using ip command
setup_network_bridge() {
    print_status "NETWORK" "Configuring network..."
    
    # Check if bridge exists using ip command
    if ! ip link show "$BRIDGE_NAME" &>/dev/null; then
        print_status "WARN" "Bridge $BRIDGE_NAME does not exist. Creating..."
        sudo ip link add name "$BRIDGE_NAME" type bridge
        sudo ip link set "$BRIDGE_NAME" up
        print_status "SUCCESS" "Bridge $BRIDGE_NAME created and activated"
    else
        # Ensure bridge is up
        sudo ip link set "$BRIDGE_NAME" up
    fi
    
    # Generate MAC if not provided
    if [ -z "$MAC_ADDRESS" ]; then
        MAC_ADDRESS="52:54:00:$(openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/.$//')"
        print_status "INFO" "Generated MAC address: $MAC_ADDRESS"
    fi
    
    # Calculate network info if static IP
    if [[ "$IPV4_ADDRESS" != "dhcp" ]]; then
        local network_info
        network_info=$(calculate_network "$IPV4_ADDRESS")
        if [[ "$network_info" == "ERROR" ]]; then
            print_status "ERROR" "Invalid network configuration: $IPV4_ADDRESS"
            return 1
        fi
        IFS=$'\n' read -r NETWORK NETMASK GATEWAY <<< "$network_info"
        
        # Set IP on bridge if not already configured
        if ! ip addr show "$BRIDGE_NAME" | grep -q "$NETWORK"; then
            sudo ip addr add "$NETWORK" dev "$BRIDGE_NAME"
        fi
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
            MEMORY="${MEMORY:-8192}"
            CPUS="${CPUS:-4}"
            DISK_SIZE="${DISK_SIZE:-100G}"
            ;;
        "workload")
            VM_ROLE="Heavy Workload"
            LOW_LATENCY_TUNING=false
            CPU_PINNING=true
            DDoS_PROTECTION=true
            OPEN_PORTS="22,80,443,3306,5432,6379,8080,9000"
            MEMORY="${MEMORY:-16384}"
            CPUS="${CPUS:-8}"
            DISK_SIZE="${DISK_SIZE:-200G}"
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
            MEMORY="${MEMORY:-4096}"
            CPUS="${CPUS:-2}"
            DISK_SIZE="${DISK_SIZE:-50G}"
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

# Function to setup DDoS protection using iptables
setup_ddos_protection() {
    local vm_name=$1
    local ip_address=$2
    
    if [[ "$DDoS_PROTECTION" != "true" ]]; then
        return 0
    fi
    
    print_status "SECURITY" "Setting up DDoS protection for $ip_address"
    
    # Create iptables rules
    local iptables_rules="/tmp/iptables-$vm_name.rules"
    
    cat > "$iptables_rules" <<EOF
# Flush existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Rate limiting for SSH
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP

# Rate limiting for game ports
iptables -A INPUT -p udp -m multiport --dports 27015,27016,25565 -m state --state NEW -m limit --limit 50/sec --limit-burst 100 -j ACCEPT
iptables -A INPUT -p udp -m multiport --dports 27015,27016,25565 -m state --state NEW -j DROP

# SYN flood protection
iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
iptables -A INPUT -p tcp --syn -j DROP

# UDP flood protection
iptables -A INPUT -p udp -m limit --limit 1000/sec --limit-burst 2000 -j ACCEPT
iptables -A INPUT -p udp -j DROP

# Allow specific ports
EOF
    
    # Add allowed ports
    IFS=',' read -ra ports <<< "$OPEN_PORTS"
    for port_range in "${ports[@]}"; do
        if [[ "$port_range" =~ ^[0-9]+-[0-9]+$ ]]; then
            echo "iptables -A INPUT -p tcp --match multiport --dports $port_range -j ACCEPT" >> "$iptables_rules"
            echo "iptables -A INPUT -p udp --match multiport --dports $port_range -j ACCEPT" >> "$iptables_rules"
        else
            echo "iptables -A INPUT -p tcp --dport $port_range -j ACCEPT" >> "$iptables_rules"
            echo "iptables -A INPUT -p udp --dport $port_range -j ACCEPT" >> "$iptables_rules"
        fi
    done
    
    # Apply rules
    sudo bash "$iptables_rules"
    sudo iptables-save > "/etc/iptables/rules.v4"
    
    print_status "SUCCESS" "DDoS protection rules applied for $vm_name"
}

# Function to start tmate session
start_tmate_session() {
    local vm_name=$1
    
    print_status "TMATCHAT" "Starting secure tmate session for VM: $vm_name"
    echo "================================================================================"
    echo "This tmate session will allow you to connect to this VM management interface"
    echo "from anywhere. Share the connection strings below securely."
    echo "================================================================================"
    echo
    
    # Create tmate configuration
    local tmate_conf="$VM_DIR/$vm_name/tmate.conf"
    cat > "$tmate_conf" <<EOF
set -g tmate-server-host tmate.io
set -g tmate-server-port 22
set -g tmate-server-rsa-fingerprint SHA256:2e:1c:70:cf:1d:46:68:bc:95:cb:07:40:07:9b:3a:8d:6b:22:25:bb:ee:d5:0a:ff:83:59:ba:90:2c:9d:fb:1f
set -g tmate-server-ed25519-fingerprint SHA256:KE1kXKxE8PM5mCv7jGgujKzF2cO8oGJXzbqKl2WjJPs
set -g tmate-session-name "$vm_name-$(date +%s)"
set -g tmate-session-length 24
EOF
    
    # Start tmate session
    TMATE_SOCKET="/tmp/tmate-$vm_name.sock"
    tmate -S "$TMATE_SOCKET" -f "$tmate_conf" new-session -d -s "$vm_name"
    tmate -S "$TMATE_SOCKET" wait tmate-ready
    
    # Get connection strings
    TMATE_SSH=$(tmate -S "$TMATE_SOCKET" display -p '#{tmate_ssh}')
    TMATE_WEB=$(tmate -S "$TMATE_SOCKET" display -p '#{tmate_web}')
    
    print_status "TMATCHAT" "SSH Connection: $TMATE_SSH"
    print_status "TMATCHAT" "Web URL: https://$TMATE_WEB"
    print_status "TMATCHAT" ""
    print_status "TMATCHAT" "This session will expire in 24 hours."
    print_status "TMATCHAT" "To close session: Ctrl+C or kill the tmate process"
    echo
    
    # Save connection info
    echo "SSH: $TMATE_SSH" > "$VM_DIR/$vm_name/tmate_connection.txt"
    echo "Web: https://$TMATE_WEB" >> "$VM_DIR/$vm_name/tmate_connection.txt"
    
    # Show session
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
        local network_info
        network_info=$(calculate_network "$IPV4_ADDRESS")
        if [[ "$network_info" == "ERROR" ]]; then
            print_status "ERROR" "Invalid network configuration"
            IPV4_ADDRESS="dhcp"
            GATEWAY=""
            DNS_SERVERS="8.8.8.8,8.8.4.4"
        else
            IFS=$'\n' read -r NETWORK NETMASK GATEWAY <<< "$network_info"
            DNS_SERVERS="8.8.8.8,8.8.4.4"
        fi
    else
        GATEWAY=""
        DNS_SERVERS="8.8.8.8,8.8.4.4"
    fi

    # Resource Configuration (respecting profile defaults)
    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: $DISK_SIZE): ")" input_disk
        if [ -n "$input_disk" ]; then
            DISK_SIZE="$input_disk"
        fi
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Memory in MB (default: $MEMORY): ")" input_mem
        if [ -n "$input_mem" ]; then
            MEMORY="$input_mem"
        fi
        if validate_input "number" "$MEMORY"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (default: $CPUS): ")" input_cpus
        if [ -n "$input_cpus" ]; then
            CPUS="$input_cpus"
        fi
        if validate_input "number" "$CPUS"; then
            break
        fi
    done

    SSH_PORT=22
    
    # GUI mode for desktop VMs
    if [[ "$VM_ROLE" == "XRDP Desktop" ]]; then
        GUI_MODE=true
        read -p "$(print_status "INPUT" "Install XRDP automatically? (y/N): ")" install_xrdp
        if [[ "$install_xrdp" =~ ^[Yy]$ ]]; then
            XRDP_INSTALLED=true
            XRDP_PORT=3389
            XRDP_ENABLED=true
            OPEN_PORTS="22,3389"
        else
            XRDP_INSTALLED=false
            XRDP_ENABLED=false
        fi
    else
        GUI_MODE=false
        XRDP_INSTALLED=false
        XRDP_ENABLED=false
    fi

    # Additional port configuration
    if [[ "$VM_ROLE" != "Game Server" ]] && [[ "$VM_ROLE" != "XRDP Desktop" ]]; then
        read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80, press Enter for none): ")" PORT_FORWARDS
    else
        PORT_FORWARDS=""
    fi

    # DDoS Protection
    if [[ "$DDoS_PROTECTION" == "true" ]]; then
        print_status "SECURITY" "DDoS protection will be enabled for this VM"
    else
        read -p "$(print_status "INPUT" "Enable DDoS protection? (Y/n): ")" ddos_choice
        ddos_choice="${ddos_choice:-y}"
        if [[ "$ddos_choice" =~ ^[Yy]$ ]]; then
            DDoS_PROTECTION=true
        else
            DDoS_PROTECTION=false
        fi
    fi

    # CPU Pinning
    if [[ "$CPU_PINNING" == "true" ]]; then
        print_status "PERFORMANCE" "CPU pinning will be enabled"
    else
        read -p "$(print_status "INPUT" "Enable CPU pinning? (y/N): ")" cpu_pin_choice
        if [[ "$cpu_pin_choice" =~ ^[Yy]$ ]]; then
            CPU_PINNING=true
        else
            CPU_PINNING=false
        fi
    fi

    IMG_FILE="$VM_DIR/$VM_NAME/disk.img"
    SEED_FILE="$VM_DIR/$VM_NAME/seed.iso"
    MONITOR_SOCKET="/tmp/qemu-$VM_NAME.monitor"
    SERIAL_SOCKET="/tmp/qemu-$VM_NAME.serial"
    TAP_INTERFACE="tap-$VM_NAME"
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
        setup_ddos_protection "$VM_NAME" "${IPV4_ADDRESS%/*}"
    fi
    
    # Display summary
    echo
    print_status "SUCCESS" "VM '$VM_NAME' created successfully!"
    print_status "INFO" "Role: $VM_ROLE"
    print_status "INFO" "IP: $IPV4_ADDRESS"
    print_status "INFO" "SSH: ssh $USERNAME@${HOSTNAME}"
    print_status "INFO" "Password: $PASSWORD"
    if [[ "$XRDP_INSTALLED" == "true" ]]; then
        print_status "INFO" "XRDP: xfreerdp /v:\${VM_IP}:$XRDP_PORT"
    fi
    print_status "INFO" "Open Ports: $OPEN_PORTS"
    echo
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
        if ! wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp" 2>&1 | tail -f -n +2; then
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
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(mkpasswd -m sha-512 "$PASSWORD" | tr -d '\n')
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
  - echo 'xfce4-session' > /home/$USERNAME/.xsession
  - chown $USERNAME:$USERNAME /home/$USERNAME/.xsession"
fi)

# Performance tuning for game servers
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

# Install monitoring tools
packages:
  - htop
  - btop
  - iotop
  - nethogs
  - curl
  - wget
  - screen
  - tmux
  - neofetch
  - python3
  - nodejs
  - docker.io
  - docker-compose

runcmd:
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker $USERNAME

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
            setup_vm_image ""
        fi
        
        # Setup network bridge
        setup_network_bridge
        
        # Create tap interface
        sudo ip tuntap add dev "$TAP_INTERFACE" mode tap user "$(whoami)"
        sudo ip link set "$TAP_INTERFACE" up
        sudo ip link set "$TAP_INTERFACE" master "$BRIDGE_NAME"
        
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
            -netdev "tap,id=net0,ifname=$TAP_INTERFACE,script=no,downscript=no"
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
        
        # Add monitor and serial sockets
        qemu_cmd+=(
            -monitor "unix:$MONITOR_SOCKET,server,nowait"
            -serial "unix:$SERIAL_SOCKET,server,nowait"
        )
        
        print_status "INFO" "Starting QEMU with bridge networking..."
        print_status "INFO" "MAC: $MAC_ADDRESS"
        print_status "INFO" "Bridge: $BRIDGE_NAME"
        
        # Start QEMU
        if ! "${qemu_cmd[@]}"; then
            print_status "ERROR" "Failed to start QEMU"
            sudo ip link delete "$TAP_INTERFACE"
            return 1
        fi
        
        # Wait for VM to boot
        sleep 5
        
        # Get IP address
        local vm_ip=""
        if [[ "$IPV4_ADDRESS" != "dhcp" ]]; then
            vm_ip="${IPV4_ADDRESS%/*}"
        else
            # Try to get IP from ARP table
            for i in {1..30}; do
                vm_ip=$(sudo arp -n | grep -i "$MAC_ADDRESS" | awk '{print $1}')
                if [ -n "$vm_ip" ]; then
                    break
                fi
                sleep 2
            done
        fi
        
        # Setup DDoS protection if needed
        if [[ "$DDoS_PROTECTION" == "true" ]] && [ -n "$vm_ip" ]; then
            setup_ddos_protection "$vm_name" "$vm_ip"
        fi
        
        # Display connection information
        echo
        print_status "SUCCESS" "VM '$vm_name' is now running!"
        print_status "INFO" "Role: $VM_ROLE"
        print_status "INFO" "IP Address: ${vm_ip:-$IPV4_ADDRESS}"
        print_status "INFO" "SSH Access: ssh $USERNAME@${vm_ip:-$HOSTNAME}"
        print_status "INFO" "Password: $PASSWORD"
        
        if [[ "$XRDP_INSTALLED" == "true" ]] && [[ "$XRDP_ENABLED" == "true" ]]; then
            print_status "INFO" "XRDP Access: xfreerdp /v:${vm_ip:-$HOSTNAME}:$XRDP_PORT"
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
            if [ -S "$MONITOR_SOCKET" ]; then
                echo "system_powerdown" | sudo socat - UNIX-CONNECT:"$MONITOR_SOCKET"
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
            sudo ip link delete "$TAP_INTERFACE" 2>/dev/null || true
            
            # Cleanup sockets
            sudo rm -f "$MONITOR_SOCKET" "$SERIAL_SOCKET"
            
            # Cleanup DDoS rules
            sudo iptables -F
            sudo iptables -X
            
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
        sudo iptables -F
        sudo iptables -X
        
        # Remove VM files
        sudo rm -rf "$VM_DIR/$vm_name" "$VM_DIR/$vm_name.conf"
        
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
        echo "Password: $PASSWORD"
        echo "IP Address: $IPV4_ADDRESS"
        echo "MAC Address: $MAC_ADDRESS"
        echo "Bridge: $BRIDGE_NAME"
        echo "SSH Access: ssh $USERNAME@${HOSTNAME}"
        echo "Memory: $MEMORY MB"
        echo "CPUs: $CPUS"
        echo "Disk: $DISK_SIZE"
        echo "Created: $CREATED"
        echo "DDoS Protection: $DDoS_PROTECTION"
        echo "CPU Pinning: $CPU_PINNING"
        echo "Low Latency Tuning: $LOW_LATENCY_TUNING"
        
        if [[ "$XRDP_INSTALLED" == "true" ]]; then
            echo "XRDP: Enabled (Port: $XRDP_PORT)"
            echo "XRDP Connection: xfreerdp /v:\${VM_IP}:$XRDP_PORT"
        fi
        
        echo "Open Ports: ${OPEN_PORTS:-None}"
        
        # Show status
        if is_vm_running "$vm_name"; then
            echo "Status: Running"
            # Try to get actual IP
            local vm_ip=$(sudo arp -n | grep -i "$MAC_ADDRESS" | awk '{print $1}')
            if [ -n "$vm_ip" ]; then
                echo "Current IP: $vm_ip"
                if [[ "$XRDP_INSTALLED" == "true" ]]; then
                    echo "Current XRDP: xfreerdp /v:$vm_ip:$XRDP_PORT"
                fi
            fi
        else
            echo "Status: Stopped"
        fi
        echo "=========================================="
        echo
        
        # Show SSH key locations
        if [ -d "$VM_DIR/$vm_name/ssh" ]; then
            print_status "SECURITY" "SSH Keys available in: $VM_DIR/$vm_name/ssh/"
        fi
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to show VM performance metrics
show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "PERFORMANCE" "Performance metrics for VM: $vm_name"
            echo "=========================================="
            
            # Get QEMU process ID
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*-name $vm_name")
            if [[ -n "$qemu_pid" ]]; then
                # Show process stats
                echo "QEMU Process Stats:"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers
                echo
                
                # Show memory usage using htop-style output
                echo "Memory Usage:"
                free -h
                echo
                
                # Show disk usage
                echo "Disk Usage:"
                if command -v btop &> /dev/null; then
                    df -h "$IMG_FILE" 2>/dev/null || du -h "$IMG_FILE"
                else
                    du -h "$IMG_FILE"
                fi
                echo
                
                # Show network statistics
                echo "Network Interface: $TAP_INTERFACE"
                if command -v nethogs &> /dev/null; then
                    echo "Run 'sudo nethogs $TAP_INTERFACE' for network usage"
                fi
                
                # Show CPU information
                echo
                echo "CPU Information:"
                if command -v cpuid &> /dev/null; then
                    cpuid | grep -E "(vendor|model name|cache size)" | head -5
                else
                    lscpu | grep -E "(Model name|CPU\(s\)|Thread)"
                fi
            else
                print_status "ERROR" "Could not find QEMU process for VM $vm_name"
            fi
        else
            print_status "INFO" "VM $vm_name is not running"
            echo "Configuration:"
            echo "  Memory: $MEMORY MB"
            echo "  CPUs: $CPUS"
            echo "  Disk: $DISK_SIZE"
            echo "  CPU Pinning: $CPU_PINNING"
            echo "  Low Latency Tuning: $LOW_LATENCY_TUNING"
        fi
        echo "=========================================="
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
            echo "  7) DDoS Protection"
            echo "  8) CPU Pinning"
            echo "  9) Open Ports"
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
                    read -p "$(print_status "INPUT" "Enable DDoS protection? (current: $DDoS_PROTECTION) (y/N): ")" ddos_choice
                    if [[ "$ddos_choice" =~ ^[Yy]$ ]]; then
                        DDoS_PROTECTION=true
                    else
                        DDoS_PROTECTION=false
                    fi
                    ;;
                8)
                    read -p "$(print_status "INPUT" "Enable CPU pinning? (current: $CPU_PINNING) (y/N): ")" cpu_pin_choice
                    if [[ "$cpu_pin_choice" =~ ^[Yy]$ ]]; then
                        CPU_PINNING=true
                    else
                        CPU_PINNING=false
                    fi
                    ;;
                9)
                    read -p "$(print_status "INPUT" "Enter open ports (current: ${OPEN_PORTS:-None}): ")" new_ports
                    OPEN_PORTS="${new_ports:-$OPEN_PORTS}"
                    ;;
                0)
                    return 0
                    ;;
                *)
                    print_status "ERROR" "Invalid selection"
                    continue
                    ;;
            esac
            
            # Recreate seed image with new configuration
            print_status "INFO" "Updating cloud-init configuration..."
            setup_vm_image ""
            
            # Save configuration
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
            echo "  5) Show VM performance"
            echo "  6) Edit VM configuration"
            echo "  7) Start tmate session for VM"
            echo "  8) Delete a VM"
        fi
        echo "  9) System Information"
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
                    read -p "$(print_status "INPUT" "Enter VM number to show performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to edit: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        edit_vm_config "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number for tmate session: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        start_tmate_session "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            8)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            9)
                echo
                print_status "INFO" "System Information:"
                echo "=========================================="
                if command -v neofetch &> /dev/null; then
                    neofetch --stdout | head -20
                else
                    echo "Hostname: $(hostname)"
                    echo "Kernel: $(uname -r)"
                    echo "CPU: $(lscpu | grep "Model name" | cut -d: -f2 | xargs)"
                    echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
                    echo "Disk: $(df -h / | awk 'NR==2 {print $2}')"
                fi
                echo "QEMU Version: $(qemu-system-x86_64 --version | head -1)"
                echo "Running VMs: $(pgrep -c qemu-system-x86_64 || echo 0)"
                echo "=========================================="
                read -p "$(print_status "INPUT" "Press Enter to continue...")"
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
