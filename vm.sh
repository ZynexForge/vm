#!/bin/bash
set -euo pipefail

# =============================
# ZYNEXFORGE™ - Advanced VM Virtualization Platform
# =============================

# Terminal colors
COLOR_RESET="\033[0m"
COLOR_BLUE="\033[1;34m"
COLOR_CYAN="\033[1;36m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_WHITE="\033[1;37m"
COLOR_MAGENTA="\033[1;35m"
COLOR_GRAY="\033[90m"

# UI constants
SEPARATOR="========================================================================="
SUBTLE_SEP="─────────────────────────────────────────────────────────────────────────"

# Function to display header
display_header() {
    clear
    cat << "EOF"

__________                             ___________                         
\____    /___.__. ____   ____ ___  ___ \_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /  |    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    <   |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \  \___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/      \/             /_____/      \/ 
EOF
    echo -e "${COLOR_CYAN}ZYNEXFORGE™${COLOR_RESET}"
    echo -e "${COLOR_WHITE}Enterprise Virtualization Platform v3.0${COLOR_RESET}"
    echo "$SEPARATOR"
    echo
}

# Function to print styled messages
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $message" ;;
        "WARN") echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $message" ;;
        "ERROR") echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $message" ;;
        "SUCCESS") echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $message" ;;
        "INPUT") echo -e "${COLOR_CYAN}[INPUT]${COLOR_RESET} $message" ;;
        "NETWORK") echo -e "${COLOR_MAGENTA}[NETWORK]${COLOR_RESET} $message" ;;
        *) echo -e "${COLOR_WHITE}[$type]${COLOR_RESET} $message" ;;
    esac
}

# Function to display section header
section_header() {
    local title=$1
    echo
    echo -e "${COLOR_WHITE}$title${COLOR_RESET}"
    echo "$SUBTLE_SEP"
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
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 22 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "Must be a valid port number (22-65535)"
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
            if ! [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                print_status "ERROR" "Must be a valid IP address (e.g., 10.0.0.1)"
                return 1
            fi
            ;;
        "network")
            if ! [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
                print_status "ERROR" "Must be a valid CIDR notation (e.g., 10.0.0.0/24)"
                return 1
            fi
            ;;
    esac
    return 0
}

# Function to check dependencies
check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "ip" "bridge-utils")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "On Ubuntu/Debian, try: sudo apt install qemu-system cloud-image-utils wget bridge-utils"
        exit 1
    fi
}

# Function to cleanup temporary files
cleanup() {
    if [ -f "user-data" ]; then rm -f "user-data"; fi
    if [ -f "meta-data" ]; then rm -f "meta-data"; fi
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
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        unset NETWORK_MODE BRIDGE_NAME IP_ADDRESS GATEWAY DNS_SERVERS
        
        source "$config_file"
        
        # Set default network values if not set
        NETWORK_MODE="${NETWORK_MODE:-user}"
        BRIDGE_NAME="${BRIDGE_NAME:-virbr0}"
        IP_ADDRESS="${IP_ADDRESS:-}"
        GATEWAY="${GATEWAY:-}"
        DNS_SERVERS="${DNS_SERVERS:-8.8.8.8,8.8.4.4}"
        
        # Update paths
        IMG_FILE="$VM_DIR/$VM_NAME.img"
        SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
        
        return 0
    else
        print_status "ERROR" "Configuration for VM '$vm_name' not found"
        return 1
    fi
}

# Function to save VM configuration
save_vm_config() {
    local config_file="$VM_DIR/$VM_NAME.conf"
    
    cat > "$config_file" <<EOF
VM_NAME="$VM_NAME"
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
IP_ADDRESS="$IP_ADDRESS"
GATEWAY="$GATEWAY"
DNS_SERVERS="$DNS_SERVERS"
EOF
    
    print_status "SUCCESS" "Configuration saved"
}

# Function to create new VM
create_new_vm() {
    display_header
    section_header "CREATE NEW VIRTUAL MACHINE"
    
    # Create VM directory if it doesn't exist
    mkdir -p "$VM_DIR"
    
    # OS Selection
    section_header "OPERATING SYSTEM SELECTION"
    print_status "INFO" "Available operating systems:"
    
    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        echo -e "  ${COLOR_CYAN}$i) $os${COLOR_RESET}"
        os_options[$i]="$os"
        ((i++))
    done
    
    while true; do
        echo
        read -p "$(print_status "INPUT" "Select OS (1-${#OS_OPTIONS[@]}): ")" choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            print_status "INFO" "Selected: $os"
            break
        else
            print_status "ERROR" "Invalid selection. Try again."
        fi
    done

    # VM Configuration
    section_header "VIRTUAL MACHINE CONFIGURATION"
    
    # Name and hostname
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            # Check if VM name already exists
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

    # Credentials
    section_header "ACCESS CREDENTIALS"
    
    while true; do
        read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    while true; do
        echo -e "${COLOR_YELLOW}Password requirements:${COLOR_RESET} Minimum 8 characters"
        read -s -p "$(print_status "INPUT" "Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        if [ -n "$PASSWORD" ] && [ ${#PASSWORD} -ge 8 ]; then
            break
        else
            print_status "ERROR" "Password must be at least 8 characters"
        fi
    done

    # Resources
    section_header "RESOURCE ALLOCATION"
    
    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 20G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-20G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Memory in MB (default: 2048): ")" MEMORY
        MEMORY="${MEMORY:-2048}"
        if validate_input "number" "$MEMORY"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (default: 2): ")" CPUS
        CPUS="${CPUS:-2}"
        if validate_input "number" "$CPUS"; then
            break
        fi
    done

    # Networking
    section_header "NETWORK CONFIGURATION"
    
    # Network mode selection
    while true; do
        echo "Network modes:"
        echo "  1) User mode (NAT with port forwarding)"
        echo "  2) Bridge mode (Direct network access)"
        echo
        read -p "$(print_status "INPUT" "Select network mode (1-2, default: 1): ")" net_choice
        net_choice="${net_choice:-1}"
        
        case $net_choice in
            1)
                NETWORK_MODE="user"
                print_status "NETWORK" "Selected: User mode (NAT)"
                break
                ;;
            2)
                NETWORK_MODE="bridge"
                print_status "NETWORK" "Selected: Bridge mode"
                
                # Get available bridges
                local bridges=($(brctl show 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$'))
                if [ ${#bridges[@]} -eq 0 ]; then
                    print_status "WARN" "No bridges found. You may need to create one manually."
                    read -p "$(print_status "INPUT" "Enter bridge name (default: virbr0): ")" BRIDGE_NAME
                    BRIDGE_NAME="${BRIDGE_NAME:-virbr0}"
                else
                    echo "Available bridges:"
                    for i in "${!bridges[@]}"; do
                        echo "  $((i+1))) ${bridges[$i]}"
                    done
                    read -p "$(print_status "INPUT" "Select bridge (1-${#bridges[@]}, default: 1): ")" bridge_choice
                    bridge_choice="${bridge_choice:-1}"
                    if [[ "$bridge_choice" =~ ^[0-9]+$ ]] && [ "$bridge_choice" -ge 1 ] && [ "$bridge_choice" -le ${#bridges[@]} ]; then
                        BRIDGE_NAME="${bridges[$((bridge_choice-1))]}"
                    else
                        BRIDGE_NAME="${bridges[0]}"
                    fi
                fi
                
                # Get IP configuration
                read -p "$(print_status "INPUT" "Enter IP address (e.g., 192.168.1.100, press Enter for DHCP): ")" IP_ADDRESS
                if [ -n "$IP_ADDRESS" ]; then
                    if validate_input "ip" "$IP_ADDRESS"; then
                        read -p "$(print_status "INPUT" "Enter gateway (e.g., 192.168.1.1): ")" GATEWAY
                        read -p "$(print_status "INPUT" "Enter DNS servers (comma-separated, default: 8.8.8.8,8.8.4.4): ")" DNS_SERVERS
                        DNS_SERVERS="${DNS_SERVERS:-8.8.8.8,8.8.4.4}"
                    else
                        IP_ADDRESS=""
                        GATEWAY=""
                    fi
                fi
                break
                ;;
            *)
                print_status "ERROR" "Invalid selection"
                ;;
        esac
    done
    
    # SSH port configuration
    while true; do
        if [ "$NETWORK_MODE" = "user" ]; then
            read -p "$(print_status "INPUT" "SSH Port (default: 2222): ")" SSH_PORT
            SSH_PORT="${SSH_PORT:-2222}"
            if validate_input "port" "$SSH_PORT"; then
                # Check if port is already in use
                if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                    print_status "ERROR" "Port $SSH_PORT is already in use"
                else
                    break
                fi
            fi
        else
            SSH_PORT="22"
            print_status "INFO" "SSH will be on standard port 22"
            break
        fi
    done

    # Additional port forwards (only for user mode)
    if [ "$NETWORK_MODE" = "user" ]; then
        read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80, press Enter for none): ")" PORT_FORWARDS
    else
        PORT_FORWARDS=""
    fi

    while true; do
        read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, default: n): ")" gui_input
        GUI_MODE=false
        gui_input="${gui_input:-n}"
        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
            GUI_MODE=true
            break
        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
            break
        else
            print_status "ERROR" "Please answer y or n"
        fi
    done

    # Final configuration
    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    section_header "DEPLOYMENT SUMMARY"
    echo -e "${COLOR_WHITE}VM Configuration:${COLOR_RESET}"
    echo -e "  Name: ${COLOR_CYAN}$VM_NAME${COLOR_RESET}"
    echo -e "  OS: ${COLOR_GREEN}$os${COLOR_RESET}"
    echo -e "  Resources: ${COLOR_YELLOW}$CPUS vCPU | ${MEMORY}MB RAM | $DISK_SIZE disk${COLOR_RESET}"
    echo -e "  Network: ${COLOR_MAGENTA}$NETWORK_MODE mode${COLOR_RESET}"
    if [ "$NETWORK_MODE" = "user" ]; then
        echo -e "    SSH on port ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
        [ -n "$PORT_FORWARDS" ] && echo -e "    Port forwards: $PORT_FORWARDS"
    else
        echo -e "    Bridge: ${COLOR_CYAN}$BRIDGE_NAME${COLOR_RESET}"
        [ -n "$IP_ADDRESS" ] && echo -e "    IP: $IP_ADDRESS"
        [ -n "$GATEWAY" ] && echo -e "    Gateway: $GATEWAY"
    fi
    echo -e "  Access: ${COLOR_GREEN}$USERNAME${COLOR_RESET} / ********"
    echo
    
    read -p "$(print_status "INPUT" "Proceed with deployment? (y/N): ")" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "INFO" "Deployment cancelled"
        return
    fi

    # Download and setup VM image
    setup_vm_image
    
    # Save configuration
    save_vm_config
    
    section_header "DEPLOYMENT COMPLETE"
    print_status "SUCCESS" "VM '$VM_NAME' deployed successfully"
    if [ "$NETWORK_MODE" = "user" ]; then
        echo -e "  ${COLOR_GRAY}SSH Access: ssh -p $SSH_PORT $USERNAME@localhost${COLOR_RESET}"
    else
        echo -e "  ${COLOR_GRAY}SSH Access: ssh $USERNAME@$IP_ADDRESS${COLOR_RESET}"
    fi
    echo -e "  ${COLOR_GRAY}Management: $VM_DIR/$VM_NAME.conf${COLOR_RESET}"
}

# Function to setup VM image
setup_vm_image() {
    print_status "INFO" "Initializing VM storage..."
    
    # Create VM directory if it doesn't exist
    mkdir -p "$VM_DIR"
    
    # Check if image already exists
    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "Image file already exists. Skipping download."
    else
        print_status "INFO" "Downloading OS image..."
        if ! wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp"; then
            print_status "ERROR" "Failed to download image from $IMG_URL"
            exit 1
        fi
        mv "$IMG_FILE.tmp" "$IMG_FILE"
    fi
    
    # Resize the disk image if needed
    if ! qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
        print_status "WARN" "Failed to resize disk image. Creating new image with specified size..."
        # Create a new image with the specified size
        rm -f "$IMG_FILE"
        qemu-img create -f qcow2 -F qcow2 -b "$IMG_FILE" "$IMG_FILE.tmp" "$DISK_SIZE" 2>/dev/null || \
        qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
        if [ -f "$IMG_FILE.tmp" ]; then
            mv "$IMG_FILE.tmp" "$IMG_FILE"
        fi
    fi

    # cloud-init configuration with network settings
    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD" | tr -d '\n')
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
EOF

    # Add network configuration for bridge mode with static IP
    if [ "$NETWORK_MODE" = "bridge" ] && [ -n "$IP_ADDRESS" ] && [ -n "$GATEWAY" ]; then
        cat >> user-data <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - $IP_ADDRESS/24
      gateway4: $GATEWAY
      nameservers:
        addresses: [$(echo "$DNS_SERVERS" | tr ',' ' ')]
EOF
    elif [ "$NETWORK_MODE" = "bridge" ]; then
        cat >> user-data <<EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
EOF
    fi

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    if ! cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
}

# Function to start a VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "STARTING VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "${COLOR_WHITE}OS:${COLOR_RESET} $OS_TYPE"
        echo -e "${COLOR_WHITE}Resources:${COLOR_RESET} ${COLOR_YELLOW}$CPUS vCPU | ${MEMORY}MB RAM${COLOR_RESET}"
        echo -e "${COLOR_WHITE}Network:${COLOR_RESET} ${COLOR_MAGENTA}$NETWORK_MODE mode${COLOR_RESET}"
        echo
        
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
        
        # Display access information
        print_status "INFO" "Access Information:"
        if [ "$NETWORK_MODE" = "user" ]; then
            echo -e "  ${COLOR_GRAY}SSH: ssh -p $SSH_PORT $USERNAME@localhost${COLOR_RESET}"
        else
            if [ -n "$IP_ADDRESS" ]; then
                echo -e "  ${COLOR_GRAY}SSH: ssh $USERNAME@$IP_ADDRESS${COLOR_RESET}"
            else
                echo -e "  ${COLOR_GRAY}SSH: Check VM for DHCP address${COLOR_RESET}"
            fi
        fi
        echo -e "  ${COLOR_GRAY}Password: $PASSWORD${COLOR_RESET}"
        echo
        
        # Base QEMU command
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -m "$MEMORY"
            -smp "$CPUS"
            -cpu host
            -drive "file=$IMG_FILE,format=qcow2,if=virtio"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -boot order=c
        )

        # Add network configuration based on mode
        if [ "$NETWORK_MODE" = "user" ]; then
            qemu_cmd+=(-device virtio-net-pci,netdev=n0)
            qemu_cmd+=(-netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22")
            
            # Add additional port forwards
            if [[ -n "$PORT_FORWARDS" ]]; then
                IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
                for forward in "${forwards[@]}"; do
                    IFS=':' read -r host_port guest_port <<< "$forward"
                    qemu_cmd+=(-device "virtio-net-pci,netdev=n${#qemu_cmd[@]}")
                    qemu_cmd+=(-netdev "user,id=n${#qemu_cmd[@]},hostfwd=tcp::$host_port-:$guest_port")
                done
            fi
        else
            # Bridge mode
            qemu_cmd+=(-device virtio-net-pci,netdev=n0,mac="52:54:00:$(dd if=/dev/urandom bs=3 count=1 2>/dev/null | hexdump -e '/1 "-%02X"' | tr -d '-')")
            qemu_cmd+=(-netdev "bridge,id=n0,br=$BRIDGE_NAME")
        fi

        # Add GUI or console mode
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga virtio -display gtk,gl=on)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi

        # Add performance enhancements
        qemu_cmd+=(
            -device virtio-balloon-pci
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
        )

        print_status "INFO" "Starting QEMU instance..."
        echo "$SUBTLE_SEP"
        "${qemu_cmd[@]}"
        
        print_status "INFO" "VM $vm_name has been shut down"
    fi
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "DELETE VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "${COLOR_WHITE}Created:${COLOR_RESET} $CREATED"
        echo
        
        print_status "WARN" "⚠️  This will permanently delete the VM and all its data!"
        print_status "WARN" "The following will be deleted:"
        echo -e "  ${COLOR_RED}• VM configuration${COLOR_RESET}"
        echo -e "  ${COLOR_RED}• Disk image ($DISK_SIZE)${COLOR_RESET}"
        echo -e "  ${COLOR_RED}• Cloud-init seed${COLOR_RESET}"
        echo
        
        read -p "$(print_status "INPUT" "Type 'DELETE' to confirm: ")" confirm
        if [[ "$confirm" == "DELETE" ]]; then
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
            print_status "SUCCESS" "VM '$vm_name' has been deleted"
        else
            print_status "INFO" "Deletion cancelled"
        fi
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "VIRTUAL MACHINE INFORMATION"
        
        echo -e "${COLOR_WHITE}Basic Information:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Name:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Hostname:${COLOR_RESET} $HOSTNAME"
        echo -e "  ${COLOR_GRAY}OS:${COLOR_RESET} $OS_TYPE $CODENAME"
        echo -e "  ${COLOR_GRAY}Created:${COLOR_RESET} $CREATED"
        
        echo
        echo -e "${COLOR_WHITE}Resources:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}vCPUs:${COLOR_RESET} ${COLOR_YELLOW}$CPUS${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Memory:${COLOR_RESET} ${COLOR_YELLOW}${MEMORY}MB${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Disk:${COLOR_RESET} ${COLOR_YELLOW}$DISK_SIZE${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}GUI Mode:${COLOR_RESET} $GUI_MODE"
        
        echo
        echo -e "${COLOR_WHITE}Network:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Mode:${COLOR_RESET} ${COLOR_MAGENTA}$NETWORK_MODE${COLOR_RESET}"
        if [ "$NETWORK_MODE" = "user" ]; then
            echo -e "  ${COLOR_GRAY}SSH Port:${COLOR_RESET} ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
            if [[ -n "$PORT_FORWARDS" ]]; then
                echo -e "  ${COLOR_GRAY}Port Forwards:${COLOR_RESET} $PORT_FORWARDS"
            fi
        else
            echo -e "  ${COLOR_GRAY}Bridge:${COLOR_RESET} $BRIDGE_NAME"
            if [ -n "$IP_ADDRESS" ]; then
                echo -e "  ${COLOR_GRAY}IP Address:${COLOR_RESET} $IP_ADDRESS"
            fi
            if [ -n "$GATEWAY" ]; then
                echo -e "  ${COLOR_GRAY}Gateway:${COLOR_RESET} $GATEWAY"
            fi
            echo -e "  ${COLOR_GRAY}DNS:${COLOR_RESET} $DNS_SERVERS"
        fi
        
        echo
        echo -e "${COLOR_WHITE}Access:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Username:${COLOR_RESET} ${COLOR_GREEN}$USERNAME${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Password:${COLOR_RESET} ********"
        
        echo
        echo -e "${COLOR_WHITE}Storage Paths:${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Configuration:${COLOR_RESET} $VM_DIR/$vm_name.conf"
        echo -e "  ${COLOR_GRAY}Disk Image:${COLOR_RESET} $IMG_FILE"
        echo -e "  ${COLOR_GRAY}Seed Image:${COLOR_RESET} $SEED_FILE"
        
        echo
        echo "$SUBTLE_SEP"
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    if pgrep -f "qemu-system-x86_64.*$vm_name" >/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to stop a running VM
stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "STOP VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM..."
            pkill -f "qemu-system-x86_64.*$IMG_FILE"
            sleep 2
            if is_vm_running "$vm_name"; then
                print_status "WARN" "VM did not stop gracefully, forcing termination..."
                pkill -9 -f "qemu-system-x86_64.*$IMG_FILE"
            fi
            print_status "SUCCESS" "VM $vm_name stopped"
        else
            print_status "INFO" "VM $vm_name is not running"
        fi
    fi
}

# Function to edit VM configuration
edit_vm_config() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "EDIT VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo
        
        while true; do
            echo "Edit Options:"
            echo "  1) Basic Information"
            echo "  2) Resource Allocation"
            echo "  3) Network Configuration"
            echo "  4) Access Credentials"
            echo "  0) Back to main menu"
            echo
            
            read -p "$(print_status "INPUT" "Select option: ")" edit_choice
            
            case $edit_choice in
                1)
                    section_header "EDIT BASIC INFORMATION"
                    
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new hostname (current: $HOSTNAME): ")" new_hostname
                        new_hostname="${new_hostname:-$HOSTNAME}"
                        if validate_input "name" "$new_hostname"; then
                            HOSTNAME="$new_hostname"
                            break
                        fi
                    done
                    
                    # Recreate seed image
                    print_status "INFO" "Updating cloud-init configuration..."
                    setup_vm_image
                    save_vm_config
                    print_status "SUCCESS" "Hostname updated"
                    ;;
                    
                2)
                    section_header "EDIT RESOURCE ALLOCATION"
                    
                    echo "Current resources:"
                    echo -e "  ${COLOR_GRAY}Memory:${COLOR_RESET} ${COLOR_YELLOW}$MEMORY MB${COLOR_RESET}"
                    echo -e "  ${COLOR_GRAY}vCPUs:${COLOR_RESET} ${COLOR_YELLOW}$CPUS${COLOR_RESET}"
                    echo -e "  ${COLOR_GRAY}Disk:${COLOR_RESET} ${COLOR_YELLOW}$DISK_SIZE${COLOR_RESET}"
                    echo
                    
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new memory in MB (current: $MEMORY): ")" new_memory
                        new_memory="${new_memory:-$MEMORY}"
                        if validate_input "number" "$new_memory"; then
                            MEMORY="$new_memory"
                            break
                        fi
                    done
                    
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new CPU count (current: $CPUS): ")" new_cpus
                        new_cpus="${new_cpus:-$CPUS}"
                        if validate_input "number" "$new_cpus"; then
                            CPUS="$new_cpus"
                            break
                        fi
                    done
                    
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new disk size (current: $DISK_SIZE): ")" new_disk_size
                        new_disk_size="${new_disk_size:-$DISK_SIZE}"
                        if validate_input "size" "$new_disk_size"; then
                            DISK_SIZE="$new_disk_size"
                            break
                        fi
                    done
                    
                    save_vm_config
                    print_status "SUCCESS" "Resource allocation updated"
                    ;;
                    
                3)
                    section_header "EDIT NETWORK CONFIGURATION"
                    
                    echo "Current network:"
                    echo -e "  ${COLOR_GRAY}Mode:${COLOR_RESET} ${COLOR_MAGENTA}$NETWORK_MODE${COLOR_RESET}"
                    if [ "$NETWORK_MODE" = "user" ]; then
                        echo -e "  ${COLOR_GRAY}SSH Port:${COLOR_RESET} ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
                        echo -e "  ${COLOR_GRAY}Port Forwards:${COLOR_RESET} ${PORT_FORWARDS:-None}"
                    else
                        echo -e "  ${COLOR_GRAY}Bridge:${COLOR_RESET} $BRIDGE_NAME"
                        echo -e "  ${COLOR_GRAY}IP Address:${COLOR_RESET} ${IP_ADDRESS:-DHCP}"
                        echo -e "  ${COLOR_GRAY}Gateway:${COLOR_RESET} $GATEWAY"
                    fi
                    echo -e "  ${COLOR_GRAY}GUI Mode:${COLOR_RESET} $GUI_MODE"
                    echo
                    
                    # Network mode selection
                    while true; do
                        echo "Network modes:"
                        echo "  1) User mode (NAT with port forwarding)"
                        echo "  2) Bridge mode (Direct network access)"
                        echo "  3) Keep current mode"
                        echo
                        read -p "$(print_status "INPUT" "Select network mode (1-3): ")" net_choice
                        
                        case $net_choice in
                            1)
                                NETWORK_MODE="user"
                                print_status "NETWORK" "Changed to: User mode (NAT)"
                                
                                while true; do
                                    read -p "$(print_status "INPUT" "Enter SSH port (current: $SSH_PORT): ")" new_ssh_port
                                    new_ssh_port="${new_ssh_port:-$SSH_PORT}"
                                    if validate_input "port" "$new_ssh_port"; then
                                        # Check if port is already in use
                                        if [ "$new_ssh_port" != "$SSH_PORT" ] && ss -tln 2>/dev/null | grep -q ":$new_ssh_port "; then
                                            print_status "ERROR" "Port $new_ssh_port is already in use"
                                        else
                                            SSH_PORT="$new_ssh_port"
                                            break
                                        fi
                                    fi
                                done
                                
                                read -p "$(print_status "INPUT" "Additional port forwards (current: ${PORT_FORWARDS:-None}): ")" new_port_forwards
                                PORT_FORWARDS="${new_port_forwards:-$PORT_FORWARDS}"
                                
                                # Clear bridge settings
                                BRIDGE_NAME="virbr0"
                                IP_ADDRESS=""
                                GATEWAY=""
                                DNS_SERVERS="8.8.8.8,8.8.4.4"
                                break
                                ;;
                                
                            2)
                                NETWORK_MODE="bridge"
                                print_status "NETWORK" "Changed to: Bridge mode"
                                
                                # Get available bridges
                                local bridges=($(brctl show 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$'))
                                if [ ${#bridges[@]} -eq 0 ]; then
                                    print_status "WARN" "No bridges found. You may need to create one manually."
                                    read -p "$(print_status "INPUT" "Enter bridge name (default: virbr0): ")" BRIDGE_NAME
                                    BRIDGE_NAME="${BRIDGE_NAME:-virbr0}"
                                else
                                    echo "Available bridges:"
                                    for i in "${!bridges[@]}"; do
                                        echo "  $((i+1))) ${bridges[$i]}"
                                    done
                                    read -p "$(print_status "INPUT" "Select bridge (1-${#bridges[@]}, default: 1): ")" bridge_choice
                                    bridge_choice="${bridge_choice:-1}"
                                    if [[ "$bridge_choice" =~ ^[0-9]+$ ]] && [ "$bridge_choice" -ge 1 ] && [ "$bridge_choice" -le ${#bridges[@]} ]; then
                                        BRIDGE_NAME="${bridges[$((bridge_choice-1))]}"
                                    else
                                        BRIDGE_NAME="${bridges[0]}"
                                    fi
                                fi
                                
                                # Get IP configuration
                                read -p "$(print_status "INPUT" "Enter IP address (e.g., 192.168.1.100, press Enter for DHCP): ")" IP_ADDRESS
                                if [ -n "$IP_ADDRESS" ]; then
                                    if validate_input "ip" "$IP_ADDRESS"; then
                                        read -p "$(print_status "INPUT" "Enter gateway (e.g., 192.168.1.1): ")" GATEWAY
                                        read -p "$(print_status "INPUT" "Enter DNS servers (comma-separated, default: 8.8.8.8,8.8.4.4): ")" DNS_SERVERS
                                        DNS_SERVERS="${DNS_SERVERS:-8.8.8.8,8.8.4.4}"
                                    else
                                        IP_ADDRESS=""
                                        GATEWAY=""
                                    fi
                                fi
                                
                                # Clear user mode settings
                                SSH_PORT="22"
                                PORT_FORWARDS=""
                                break
                                ;;
                                
                            3)
                                print_status "INFO" "Keeping current network mode"
                                break
                                ;;
                                
                            *)
                                print_status "ERROR" "Invalid selection"
                                continue
                                ;;
                        esac
                    done
                    
                    while true; do
                        read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, current: $GUI_MODE): ")" gui_input
                        gui_input="${gui_input:-}"
                        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
                            GUI_MODE=true
                            break
                        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
                            GUI_MODE=false
                            break
                        elif [ -z "$gui_input" ]; then
                            # Keep current value if user just pressed Enter
                            break
                        else
                            print_status "ERROR" "Please answer y or n"
                        fi
                    done
                    
                    # Recreate seed image if network mode changed
                    if [ "$net_choice" = "1" ] || [ "$net_choice" = "2" ]; then
                        print_status "INFO" "Updating cloud-init configuration..."
                        setup_vm_image
                    fi
                    
                    save_vm_config
                    print_status "SUCCESS" "Network configuration updated"
                    ;;
                    
                4)
                    section_header "EDIT ACCESS CREDENTIALS"
                    
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new username (current: $USERNAME): ")" new_username
                        new_username="${new_username:-$USERNAME}"
                        if validate_input "username" "$new_username"; then
                            USERNAME="$new_username"
                            break
                        fi
                    done
                    
                    while true; do
                        read -s -p "$(print_status "INPUT" "Enter new password (current: ****): ")" new_password
                        new_password="${new_password:-$PASSWORD}"
                        echo
                        if [ -n "$new_password" ] && [ ${#new_password} -ge 8 ]; then
                            PASSWORD="$new_password"
                            break
                        else
                            print_status "ERROR" "Password must be at least 8 characters"
                        fi
                    done
                    
                    # Recreate seed image
                    print_status "INFO" "Updating cloud-init configuration..."
                    setup_vm_image
                    save_vm_config
                    print_status "SUCCESS" "Access credentials updated"
                    ;;
                    
                0)
                    return 0
                    ;;
                    
                *)
                    print_status "ERROR" "Invalid selection"
                    continue
                    ;;
            esac
            
            echo
            read -p "$(print_status "INPUT" "Edit another setting? (y/N): ")" continue_editing
            if [[ ! "$continue_editing" =~ ^[Yy]$ ]]; then
                break
            fi
            echo
        done
    fi
}

# Function to resize VM disk
resize_vm_disk() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "RESIZE VM DISK"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "${COLOR_WHITE}Current disk size:${COLOR_RESET} ${COLOR_YELLOW}$DISK_SIZE${COLOR_RESET}"
        echo
        
        while true; do
            read -p "$(print_status "INPUT" "Enter new disk size (e.g., 50G): ")" new_disk_size
            if validate_input "size" "$new_disk_size"; then
                if [[ "$new_disk_size" == "$DISK_SIZE" ]]; then
                    print_status "INFO" "New disk size is the same as current size. No changes made."
                    return 0
                fi
                
                # Check if new size is smaller than current (not recommended)
                local current_size_num=${DISK_SIZE%[GgMm]}
                local new_size_num=${new_disk_size%[GgMm]}
                local current_unit=${DISK_SIZE: -1}
                local new_unit=${new_disk_size: -1}
                
                # Convert both to MB for comparison
                if [[ "$current_unit" =~ [Gg] ]]; then
                    current_size_num=$((current_size_num * 1024))
                fi
                if [[ "$new_unit" =~ [Gg] ]]; then
                    new_size_num=$((new_size_num * 1024))
                fi
                
                if [[ $new_size_num -lt $current_size_num ]]; then
                    print_status "WARN" "⚠️  Shrinking disk size is not recommended and may cause data loss!"
                    read -p "$(print_status "INPUT" "Are you sure you want to continue? (y/N): ")" confirm_shrink
                    if [[ ! "$confirm_shrink" =~ ^[Yy]$ ]]; then
                        print_status "INFO" "Disk resize cancelled."
                        return 0
                    fi
                fi
                
                # Resize the disk
                print_status "INFO" "Resizing disk to $new_disk_size..."
                if qemu-img resize "$IMG_FILE" "$new_disk_size"; then
                    DISK_SIZE="$new_disk_size"
                    save_vm_config
                    print_status "SUCCESS" "Disk resized successfully to $new_disk_size"
                else
                    print_status "ERROR" "Failed to resize disk"
                    return 1
                fi
                break
            fi
        done
    fi
}

# Function to show VM performance metrics
show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "VM PERFORMANCE METRICS"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        
        if is_vm_running "$vm_name"; then
            # Get QEMU process ID
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$IMG_FILE")
            if [[ -n "$qemu_pid" ]]; then
                echo
                echo -e "${COLOR_WHITE}Process Statistics:${COLOR_RESET}"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers | awk '{printf "  PID: %s | CPU: %s%% | MEM: %s%% | Size: %sMB\n", $1, $2, $3, $4/1024}'
                
                echo
                echo -e "${COLOR_WHITE}System Resources:${COLOR_RESET}"
                free -h | head -2 | tail -1 | awk '{print "  Memory: " $3 " / " $2 " used (" $4 " free)"}'
                
                echo
                echo -e "${COLOR_WHITE}Disk Usage:${COLOR_RESET}"
                if [ -f "$IMG_FILE" ]; then
                    local disk_size=$(du -h "$IMG_FILE" 2>/dev/null | cut -f1)
                    echo -e "  VM Disk: $disk_size ($DISK_SIZE allocated)"
                fi
                
                # Network statistics for bridge mode
                if [ "$NETWORK_MODE" = "bridge" ]; then
                    echo
                    echo -e "${COLOR_WHITE}Network Interface:${COLOR_RESET}"
                    # Try to find the tap interface associated with the VM
                    local tap_if=$(ip link show | grep -o "tap[0-9]\+[^:]" | head -1 | tr -d ' ')
                    if [ -n "$tap_if" ]; then
                        echo -e "  Interface: $tap_if"
                        # Show basic interface info
                        ip addr show dev "$tap_if" 2>/dev/null | grep -E "inet|state" | sed 's/^/    /'
                    fi
                fi
            else
                print_status "ERROR" "Could not find QEMU process for VM $vm_name"
            fi
        else
            print_status "INFO" "VM $vm_name is not running"
            echo
            echo -e "${COLOR_WHITE}Configured Resources:${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}vCPUs:${COLOR_RESET} ${COLOR_YELLOW}$CPUS${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}Memory:${COLOR_RESET} ${COLOR_YELLOW}${MEMORY}MB${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}Disk:${COLOR_RESET} ${COLOR_YELLOW}$DISK_SIZE${COLOR_RESET}"
        fi
        
        echo
        echo "$SUBTLE_SEP"
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to show system overview
show_system_overview() {
    display_header
    section_header "SYSTEM OVERVIEW"
    
    # Show total VMs
    local total_vms=$(get_vm_list | wc -l)
    local running_vms=0
    local vms=($(get_vm_list))
    
    for vm in "${vms[@]}"; do
        if is_vm_running "$vm"; then
            ((running_vms++))
        fi
    done
    
    echo -e "${COLOR_WHITE}Platform Statistics:${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Total VMs:${COLOR_RESET} ${COLOR_CYAN}$total_vms${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Running VMs:${COLOR_RESET} ${COLOR_GREEN}$running_vms${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Stopped VMs:${COLOR_RESET} ${COLOR_YELLOW}$((total_vms - running_vms))${COLOR_RESET}"
    echo
    
    # Show storage usage
    echo -e "${COLOR_WHITE}Storage Overview:${COLOR_RESET}"
    if [ -d "$VM_DIR" ]; then
        local total_storage=$(du -sh "$VM_DIR" 2>/dev/null | cut -f1)
        echo -e "  ${COLOR_GRAY}Total Storage:${COLOR_RESET} $total_storage"
    else
        echo -e "  ${COLOR_GRAY}Total Storage:${COLOR_RESET} Not available"
    fi
    echo
    
    # Show network overview
    echo -e "${COLOR_WHITE}Network Overview:${COLOR_RESET}"
    
    # Show available bridges
    local bridges=($(brctl show 2>/dev/null | awk 'NR>1 {print $1}' | grep -v '^$'))
    if [ ${#bridges[@]} -gt 0 ]; then
        echo "  Available bridges:"
        for bridge in "${bridges[@]}"; do
            local bridge_ips=$(ip addr show dev "$bridge" 2>/dev/null | grep -E "inet " | awk '{print $2}' | tr '\n' ' ')
            echo -e "    ${COLOR_CYAN}$bridge${COLOR_RESET}: $bridge_ips"
        done
    else
        echo "  No bridges found. Use 'sudo brctl addbr virbr0' to create one."
    fi
    
    # Show port usage
    echo
    echo -e "${COLOR_WHITE}Port Usage:${COLOR_RESET}"
    local used_ports=$(ss -tln 2>/dev/null | grep -E ":(22|2222|8080|80|443)" | awk '{print $4}' | cut -d: -f2 | sort -un | tr '\n' ' ')
    if [ -n "$used_ports" ]; then
        echo "  Commonly used ports: $used_ports"
    fi
    
    echo
    echo "$SEPARATOR"
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            section_header "VIRTUAL MACHINES"
            print_status "INFO" "Found $vm_count VM(s):"
            echo
            
            for i in "${!vms[@]}"; do
                local vm_name="${vms[$i]}"
                local status="Stopped"
                
                if is_vm_running "$vm_name"; then
                    status="${COLOR_GREEN}● Running${COLOR_RESET}"
                else
                    status="${COLOR_YELLOW}● Stopped${COLOR_RESET}"
                fi
                
                printf "  %2d) %-20s %s\n" $((i+1)) "$vm_name" "$status"
            done
            echo
        else
            section_header "WELCOME"
            echo -e "  ${COLOR_GRAY}No virtual machines found.${COLOR_RESET}"
            echo -e "  ${COLOR_GRAY}Create your first VM to get started.${COLOR_RESET}"
            echo
        fi
        
        section_header "MAIN MENU"
        echo "  1) Create a new VM"
        if [ $vm_count -gt 0 ]; then
            echo "  2) Start a VM"
            echo "  3) Stop a VM"
            echo "  4) Show VM info"
            echo "  5) Edit VM configuration"
            echo "  6) Delete a VM"
            echo "  7) Resize VM disk"
            echo "  8) Show VM performance"
            echo "  9) System overview"
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
                    read -p "$(print_status "INPUT" "Enter VM number to edit: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_name" -le $vm_count ]; then
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
                    read -p "$(print_status "INPUT" "Enter VM number to resize disk: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        resize_vm_disk "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            8)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            9)
                show_system_overview
                ;;
            0)
                print_status "INFO" "Goodbye!"
                exit 0
                ;;
            *)
                print_status "ERROR" "Invalid option"
                ;;
        esac
    done
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check dependencies
check_dependencies

# Initialize paths
VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

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

# Start the main menu
main_menu
