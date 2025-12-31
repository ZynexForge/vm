#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge Multi-VM Manager
# =============================

# Function to display header
display_header() {
    clear
    cat << "EOF"
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   __________                           ___________                          │
│   \____    /__.__. ____   ____ ___  __\_   _____/__________  ____   ____   │
│     /     /<   |  |/    \_/ __ \\  \/  /|    __)/  _ \_  __ \/ ___\_/ __ \  │
│    /     /_ \___  |   |  \  ___/ >    < |     \(  <_> )  | \/ /_/  >  ___/  │
│   /_______ \/ ____|___|  /\___  >__/\_ \\___  / \____/|__|  \___  / \___  > │
│           \/\/         \/     \/      \/    \/             /_____/      \/  │
│                                                                             │
│                    ⚡ ZynexForge VM Manager v2.0 ⚡                         │
│                   Enterprise Multi-VM Management Suite                      │
│=============================================================================│
│                      Virtualization Power Unleashed                         │
└─────────────────────────────────────────────────────────────────────────────┘
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
        "ZYNE") echo -e "\033[1;35m[ZYNE]\033[0m $message" ;;
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
        "mac")
            if ! [[ "$value" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                print_status "ERROR" "Must be a valid MAC address (format: XX:XX:XX:XX:XX:XX)"
                return 1
            fi
            ;;
    esac
    return 0
}

# Function to check dependencies
check_dependencies() {
    print_status "INFO" "Checking system dependencies..."
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "genisoimage" "virt-install")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "On Ubuntu/Debian, try: sudo apt install qemu-system cloud-image-utils wget genisoimage virtinst"
        exit 1
    fi
    print_status "SUCCESS" "All dependencies satisfied"
}

# Function to cleanup temporary files
cleanup() {
    if [ -f "user-data" ]; then rm -f "user-data"; fi
    if [ -f "meta-data" ]; then rm -f "meta-data"; fi
    if [ -f "network-config" ]; then rm -f "network-config"; fi
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
        unset NETWORK_TYPE BRIDGE_INTERFACE MAC_ADDRESS
        
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
NETWORK_TYPE="$NETWORK_TYPE"
BRIDGE_INTERFACE="$BRIDGE_INTERFACE"
MAC_ADDRESS="$MAC_ADDRESS"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to display OS selection menu
display_os_menu() {
    print_status "INFO" "Available Operating Systems:"
    echo "┌─────────────────────────────────────────────────────────────────────┐"
    echo "│ Category         │ ID  │ Operating System                          │"
    echo "├──────────────────┼─────┼───────────────────────────────────────────┤"
    
    local categories=("Enterprise" "Desktop" "Server" "Specialized")
    local i=1
    
    for category in "${categories[@]}"; do
        local first_in_category=true
        for os in "${!OS_OPTIONS[@]}"; do
            IFS='|' read -r os_type os_category _ <<< "${OS_OPTIONS[$os]}"
            if [[ "$os_category" == "$category" ]]; then
                if $first_in_category; then
                    printf "│ \033[1;36m%-16s\033[0m │ %3d │ %-41s │\n" "$category" $i "$os"
                    first_in_category=false
                else
                    printf "│                  │ %3d │ %-41s │\n" $i "$os"
                fi
                ((i++))
            fi
        done
        if [[ "$category" != "Specialized" ]]; then
            echo "├──────────────────┼─────┼───────────────────────────────────────────┤"
        fi
    done
    echo "└──────────────────┴─────┴───────────────────────────────────────────┘"
    echo
}

# Function to create new VM
create_new_vm() {
    print_status "ZYNE" "Creating a new Virtual Machine"
    echo "─────────────────────────────────────────────────────────────────────"
    
    # OS Selection
    display_os_menu
    
    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        os_options[$i]="$os"
        ((i++))
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Enter your choice (1-${#OS_OPTIONS[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE OS_CATEGORY CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD NOTES <<< "${OS_OPTIONS[$os]}"
            
            print_status "INFO" "Selected: $os"
            if [[ -n "$NOTES" ]]; then
                print_status "INFO" "Notes: $NOTES"
            fi
            break
        else
            print_status "ERROR" "Invalid selection. Try again."
        fi
    done

    # Custom Inputs with validation
    echo
    print_status "INFO" "VM Configuration"
    echo "─────────────────────────────────────────────────────────────────────"
    
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

    # Hardware Configuration
    echo
    print_status "INFO" "Hardware Configuration"
    echo "─────────────────────────────────────────────────────────────────────"
    
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

    # Network Configuration
    echo
    print_status "INFO" "Network Configuration"
    echo "─────────────────────────────────────────────────────────────────────"
    
    while true; do
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
    done

    # Network Type Selection
    echo
    print_status "INFO" "Select Network Type:"
    echo "  1) NAT (User Networking) - Default, easier setup"
    echo "  2) Bridge - Better performance, direct network access"
    
    while true; do
        read -p "$(print_status "INPUT" "Enter choice (1-2, default: 1): ")" network_choice
        network_choice="${network_choice:-1}"
        case $network_choice in
            1)
                NETWORK_TYPE="nat"
                BRIDGE_INTERFACE=""
                break
                ;;
            2)
                NETWORK_TYPE="bridge"
                # Get available bridge interfaces
                local bridges=$(brctl show 2>/dev/null | awk 'NR>1 {print $1}' | tr '\n' ',')
                if [[ -n "$bridges" ]]; then
                    print_status "INFO" "Available bridge interfaces: ${bridges%,}"
                fi
                read -p "$(print_status "INPUT" "Enter bridge interface name (e.g., br0): ")" BRIDGE_INTERFACE
                break
                ;;
            *)
                print_status "ERROR" "Invalid selection"
                ;;
        esac
    done

    # MAC Address (optional)
    read -p "$(print_status "INPUT" "Custom MAC address (press Enter for auto): ")" MAC_ADDRESS
    if [[ -n "$MAC_ADDRESS" ]]; then
        if ! validate_input "mac" "$MAC_ADDRESS"; then
            MAC_ADDRESS=""
            print_status "INFO" "Using auto-generated MAC address"
        fi
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

    # Additional network options
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80, press Enter for none): ")" PORT_FORWARDS

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    # Download and setup VM image
    setup_vm_image
    
    # Save configuration
    save_vm_config
}

# Function to setup VM image
setup_vm_image() {
    print_status "INFO" "Downloading and preparing image..."
    
    # Create VM directory if it doesn't exist
    mkdir -p "$VM_DIR"
    
    # Special handling for Proxmox
    if [[ "$OS_TYPE" == "proxmox" ]]; then
        setup_proxmox_vm
        return
    fi
    
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

    # Create cloud-init configuration
    create_cloud_init_config
    
    if ! cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
    
    print_status "SUCCESS" "VM '$VM_NAME' created successfully."
}

# Function to setup Proxmox VM
setup_proxmox_vm() {
    print_status "INFO" "Setting up Proxmox VE..."
    
    # Check if Proxmox ISO exists
    if [[ ! -f "$IMG_FILE" ]]; then
        print_status "INFO" "Downloading Proxmox VE ISO..."
        if ! wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE"; then
            print_status "ERROR" "Failed to download Proxmox VE ISO"
            exit 1
        fi
    fi
    
    # Create a disk image for Proxmox
    local disk_file="$VM_DIR/$VM_NAME-disk.qcow2"
    qemu-img create -f qcow2 "$disk_file" "$DISK_SIZE"
    
    # For Proxmox, we use the ISO directly and the disk image
    IMG_FILE="$disk_file"
    
    print_status "SUCCESS" "Proxmox VE setup complete. Boot from ISO to install."
}

# Function to create cloud-init configuration
create_cloud_init_config() {
    # Basic cloud-init config
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

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF
}

# Function to start a VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "ZYNE" "Starting VM: $vm_name"
        echo "─────────────────────────────────────────────────────────────────────"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Password: $PASSWORD"
        
        # Check if image file exists
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "VM image file not found: $IMG_FILE"
            return 1
        fi
        
        # Special handling for Proxmox
        if [[ "$OS_TYPE" == "proxmox" ]]; then
            start_proxmox_vm
            return
        fi
        
        # Check if seed file exists
        if [[ ! -f "$SEED_FILE" ]]; then
            print_status "WARN" "Seed file not found, recreating..."
            setup_vm_image
        fi
        
        # Base QEMU command
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -cpu host
            -m "$MEMORY"
            -smp "$CPUS,sockets=1,cores=$CPUS,threads=1"
            -drive "file=$IMG_FILE,format=qcow2,if=virtio,discard=on"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -boot "order=c,menu=on"
        )

        # Network configuration
        if [[ "$NETWORK_TYPE" == "bridge" && -n "$BRIDGE_INTERFACE" ]]; then
            qemu_cmd+=(-netdev "bridge,id=net0,br=$BRIDGE_INTERFACE")
            qemu_cmd+=(-device "virtio-net-pci,netdev=net0,mac=${MAC_ADDRESS:-$(generate_mac)}")
        else
            qemu_cmd+=(-device "virtio-net-pci,netdev=n0")
            qemu_cmd+=(-netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22")
        fi

        # Add port forwards if specified (only for NAT)
        if [[ "$NETWORK_TYPE" == "nat" && -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                qemu_cmd+=(-device "virtio-net-pci,netdev=n${#qemu_cmd[@]}")
                qemu_cmd+=(-netdev "user,id=n${#qemu_cmd[@]},hostfwd=tcp::$host_port-:$guest_port")
            done
        fi

        # Add GUI or console mode
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga virtio -display gtk,gl=on)
            qemu_cmd+=(-usb -device usb-tablet)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi

        # Add performance enhancements
        qemu_cmd+=(
            -device virtio-balloon-pci
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
            -device virtio-scsi-pci,id=scsi
            -drive if=none,id=hd0,file=$IMG_FILE,format=qcow2
            -device scsi-hd,drive=hd0
        )

        # Add sound device if GUI mode
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-device AC97)
        fi

        print_status "INFO" "Starting QEMU with command:"
        echo "  ${qemu_cmd[@]}"
        echo
        
        # Start the VM
        if ! "${qemu_cmd[@]}"; then
            print_status "ERROR" "Failed to start VM"
            return 1
        fi
        
        print_status "INFO" "VM $vm_name has been shut down"
    fi
}

# Function to start Proxmox VM
start_proxmox_vm() {
    local qemu_cmd=(
        qemu-system-x86_64
        -enable-kvm
        -cpu host
        -m "$MEMORY"
        -smp "$CPUS"
        -drive "file=$IMG_FILE,format=qcow2,if=virtio"
        -cdrom "$IMG_URL"
        -boot "order=cd,menu=on"
    )

    # Network configuration for Proxmox
    if [[ "$NETWORK_TYPE" == "bridge" && -n "$BRIDGE_INTERFACE" ]]; then
        qemu_cmd+=(-netdev "bridge,id=net0,br=$BRIDGE_INTERFACE")
        qemu_cmd+=(-device "virtio-net-pci,netdev=net0,mac=${MAC_ADDRESS:-$(generate_mac)}")
    else
        qemu_cmd+=(-device "virtio-net-pci,netdev=n0")
        qemu_cmd+=(-netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22")
    fi

    if [[ "$GUI_MODE" == true ]]; then
        qemu_cmd+=(-vga virtio -display gtk,gl=on)
    else
        qemu_cmd+=(-nographic -serial mon:stdio)
    fi

    qemu_cmd+=(-device virtio-balloon-pci)

    print_status "INFO" "Starting Proxmox VE installation..."
    "${qemu_cmd[@]}"
}

# Function to generate MAC address
generate_mac() {
    printf '52:54:%02x:%02x:%02x:%02x' \
        $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "⚠️  This will permanently delete VM '$vm_name' and all its data!"
    echo "─────────────────────────────────────────────────────────────────────"
    read -p "$(print_status "INPUT" "Are you sure? (type 'DELETE' to confirm): ")" -r
    echo
    if [[ "$REPLY" == "DELETE" ]]; then
        if load_vm_config "$vm_name"; then
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
            print_status "SUCCESS" "✅ VM '$vm_name' has been deleted"
        fi
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo
        print_status "ZYNE" "VM Information: $vm_name"
        echo "┌─────────────────────────────────────────────────────────────────────┐"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "OS" "$OS_TYPE"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "Hostname" "$HOSTNAME"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "Username" "$USERNAME"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "Password" "************"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "SSH Port" "$SSH_PORT"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "Memory" "$MEMORY MB"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "CPUs" "$CPUS"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "Disk" "$DISK_SIZE"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "GUI Mode" "$GUI_MODE"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "Network Type" "$NETWORK_TYPE"
        if [[ "$NETWORK_TYPE" == "bridge" ]]; then
            printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "Bridge Interface" "$BRIDGE_INTERFACE"
        fi
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "MAC Address" "${MAC_ADDRESS:-Auto-generated}"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "Port Forwards" "${PORT_FORWARDS:-None}"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "Created" "$CREATED"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "Image File" "$(basename "$IMG_FILE")"
        printf "│ \033[1;36m%-30s\033[0m: %-30s │\n" "Seed File" "$(basename "$SEED_FILE")"
        echo "└─────────────────────────────────────────────────────────────────────┘"
        echo
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
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM: $vm_name"
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
        print_status "ZYNE" "Editing VM: $vm_name"
        echo "─────────────────────────────────────────────────────────────────────"
        
        while true; do
            echo "Select option to edit:"
            echo "┌─────────────────────────────────────────────────────────────┐"
            echo "│  1) Hostname                2) Username                    │"
            echo "│  3) Password                4) SSH Port                    │"
            echo "│  5) GUI Mode                6) Port Forwards               │"
            echo "│  7) Memory (RAM)            8) CPU Count                   │"
            echo "│  9) Disk Size              10) Network Settings            │"
            echo "│  0) Back to main menu                                      │"
            echo "└─────────────────────────────────────────────────────────────┘"
            
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
                        read -p "$(print_status "INPUT" "Enter new SSH port (current: $SSH_PORT): ")" new_ssh_port
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
                    ;;
                5)
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
                    ;;
                6)
                    read -p "$(print_status "INPUT" "Additional port forwards (current: ${PORT_FORWARDS:-None}): ")" new_port_forwards
                    PORT_FORWARDS="${new_port_forwards:-$PORT_FORWARDS}"
                    ;;
                7)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new memory in MB (current: $MEMORY): ")" new_memory
                        new_memory="${new_memory:-$MEMORY}"
                        if validate_input "number" "$new_memory"; then
                            MEMORY="$new_memory"
                            break
                        fi
                    done
                    ;;
                8)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new CPU count (current: $CPUS): ")" new_cpus
                        new_cpus="${new_cpus:-$CPUS}"
                        if validate_input "number" "$new_cpus"; then
                            CPUS="$new_cpus"
                            break
                        fi
                    done
                    ;;
                9)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new disk size (current: $DISK_SIZE): ")" new_disk_size
                        new_disk_size="${new_disk_size:-$DISK_SIZE}"
                        if validate_input "size" "$new_disk_size"; then
                            DISK_SIZE="$new_disk_size"
                            break
                        fi
                    done
                    ;;
                10)
                    echo "Network Settings:"
                    echo "  1) Network Type (current: $NETWORK_TYPE)"
                    echo "  2) Bridge Interface (current: $BRIDGE_INTERFACE)"
                    echo "  3) MAC Address (current: ${MAC_ADDRESS:-Auto})"
                    read -p "$(print_status "INPUT" "Select network option to edit: ")" network_edit
                    case $network_edit in
                        1)
                            echo "Select Network Type:"
                            echo "  1) NAT (User Networking)"
                            echo "  2) Bridge"
                            read -p "$(print_status "INPUT" "Enter choice: ")" net_type
                            case $net_type in
                                1) NETWORK_TYPE="nat" ;;
                                2) NETWORK_TYPE="bridge" ;;
                                *) print_status "ERROR" "Invalid selection" ;;
                            esac
                            ;;
                        2)
                            read -p "$(print_status "INPUT" "Enter bridge interface name: ")" BRIDGE_INTERFACE
                            ;;
                        3)
                            read -p "$(print_status "INPUT" "Enter MAC address (format: XX:XX:XX:XX:XX:XX): ")" MAC_ADDRESS
                            if [[ -n "$MAC_ADDRESS" ]] && ! validate_input "mac" "$MAC_ADDRESS"; then
                                MAC_ADDRESS=""
                            fi
                            ;;
                    esac
                    ;;
                0)
                    return 0
                    ;;
                *)
                    print_status "ERROR" "Invalid selection"
                    continue
                    ;;
            esac
            
            # Recreate seed image with new configuration if user/password/hostname changed
            if [[ "$edit_choice" -eq 1 || "$edit_choice" -eq 2 || "$edit_choice" -eq 3 ]]; then
                print_status "INFO" "Updating cloud-init configuration..."
                setup_vm_image
            fi
            
            # Save configuration
            save_vm_config
            
            read -p "$(print_status "INPUT" "Continue editing? (y/N): ")" continue_editing
            if [[ ! "$continue_editing" =~ ^[Yy]$ ]]; then
                break
            fi
        done
    fi
}

# Function to resize VM disk
resize_vm_disk() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Current disk size: $DISK_SIZE"
        
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
                    print_status "WARN" "Shrinking disk size is not recommended and may cause data loss!"
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
        if is_vm_running "$vm_name"; then
            print_status "ZYNE" "Performance metrics for VM: $vm_name"
            echo "┌─────────────────────────────────────────────────────────────────────┐"
            
            # Get QEMU process ID
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$IMG_FILE")
            if [[ -n "$qemu_pid" ]]; then
                # Show process stats
                echo "│ QEMU Process Stats:                                         │"
                echo "├─────────────────────────────────────────────────────────────┤"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers | awk '{printf "│ PID: %-5s CPU: %-5s MEM: %-5s SIZE: %-8s RSS: %-8s\n", $1, $2, $3, $4, $5}'
                echo "├─────────────────────────────────────────────────────────────┤"
                
                # Show memory usage
                echo "│ Memory Usage:                                              │"
                echo "├─────────────────────────────────────────────────────────────┤"
                free -h | awk 'NR<=2 {printf "│ %-15s %-10s %-10s %-10s %-10s\n", $1, $2, $3, $4, $5}'
                echo "├─────────────────────────────────────────────────────────────┤"
                
                # Show disk usage
                echo "│ Disk Usage:                                                │"
                echo "├─────────────────────────────────────────────────────────────┤"
                if df -h "$IMG_FILE" 2>/dev/null; then
                    df -h "$IMG_FILE" 2>/dev/null | awk 'NR>1 {printf "│ File: %-50s\n│ Size: %-10s Used: %-10s Avail: %-10s Use%%: %-5s\n", $1, $2, $3, $4, $5}'
                else
                    du -h "$IMG_FILE" | awk '{printf "│ Size: %-50s\n", $1}'
                fi
            else
                print_status "ERROR" "Could not find QEMU process for VM $vm_name"
            fi
        else
            print_status "INFO" "VM $vm_name is not running"
            echo "│ Configuration:                                               │"
            echo "├─────────────────────────────────────────────────────────────┤"
            printf "│ %-25s: %-30s │\n" "Memory" "$MEMORY MB"
            printf "│ %-25s: %-30s │\n" "CPUs" "$CPUS"
            printf "│ %-25s: %-30s │\n" "Disk" "$DISK_SIZE"
        fi
        echo "└─────────────────────────────────────────────────────────────────────┘"
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to show system status
show_system_status() {
    print_status "ZYNE" "System Status"
    echo "┌─────────────────────────────────────────────────────────────────────┐"
    echo "│ System Information:                                                │"
    echo "├─────────────────────────────────────────────────────────────────────┤"
    
    # CPU Information
    local cpu_info=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
    local cpu_cores=$(nproc)
    printf "│ %-20s: %-35s │\n" "CPU" "${cpu_info:0:35}"
    printf "│ %-20s: %-35s │\n" "Cores" "$cpu_cores"
    
    # Memory Information
    local mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -h | awk '/^Mem:/ {print $3}')
    printf "│ %-20s: %-35s │\n" "Memory Total" "$mem_total"
    printf "│ %-20s: %-35s │\n" "Memory Used" "$mem_used"
    
    # Disk Information
    local disk_total=$(df -h / | awk 'NR==2 {print $2}')
    local disk_used=$(df -h / | awk 'NR==2 {print $3}')
    local disk_avail=$(df -h / | awk 'NR==2 {print $4}')
    printf "│ %-20s: %-35s │\n" "Disk Total" "$disk_total"
    printf "│ %-20s: %-35s │\n" "Disk Used" "$disk_used"
    printf "│ %-20s: %-35s │\n" "Disk Available" "$disk_avail"
    
    # VM Count
    local vm_count=$(get_vm_list | wc -l)
    local running_vms=0
    for vm in $(get_vm_list); do
        if is_vm_running "$vm"; then
            ((running_vms++))
        fi
    done
    printf "│ %-20s: %-35s │\n" "Total VMs" "$vm_count"
    printf "│ %-20s: %-35s │\n" "Running VMs" "$running_vms"
    
    echo "└─────────────────────────────────────────────────────────────────────┘"
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        # Show system status summary
        local running_vms=0
        for vm in "${vms[@]}"; do
            if is_vm_running "$vm"; then
                ((running_vms++))
            fi
        done
        
        print_status "INFO" "System Status: $running_vms VM(s) running, $vm_count total"
        echo
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Virtual Machines:"
            echo "┌─────┬──────────────────────┬────────────┬────────────────────────────┐"
            echo "│ No. │ Name                 │ Status     │ OS Type                    │"
            echo "├─────┼──────────────────────┼────────────┼────────────────────────────┤"
            
            for i in "${!vms[@]}"; do
                local vm_name="${vms[$i]}"
                local status="🔴 Stopped"
                local os_type="Unknown"
                
                if is_vm_running "$vm_name"; then
                    status="🟢 Running"
                fi
                
                # Load config to get OS type
                if load_vm_config "$vm_name" 2>/dev/null; then
                    os_type="$OS_TYPE"
                fi
                
                printf "│ %3d │ %-20s │ %-10s │ %-26s │\n" \
                    $((i+1)) "${vm_name:0:20}" "$status" "${os_type:0:26}"
            done
            echo "└─────┴──────────────────────┴────────────┴────────────────────────────┘"
            echo
        else
            print_status "INFO" "No virtual machines found. Create your first VM!"
            echo
        fi
        
        echo "Main Menu:"
        echo "┌─────────────────────────────────────────────────────────────────────┐"
        echo "│  1) 🆕 Create a new VM         2) 🚀 Start a VM                    │"
        echo "│  3) ⏹️  Stop a VM             4) 📊 Show VM info                  │"
        echo "│  5) ⚙️  Edit VM configuration 6) 🗑️  Delete a VM                  │"
        echo "│  7) 💾 Resize VM disk         8) 📈 Show VM performance           │"
        echo "│  9) 📊 System Status          0) 🚪 Exit                          │"
        echo "└─────────────────────────────────────────────────────────────────────┘"
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
                else
                    print_status "ERROR" "No VMs available. Create one first."
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
                else
                    print_status "ERROR" "No VMs available"
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
                else
                    print_status "ERROR" "No VMs available"
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
                else
                    print_status "ERROR" "No VMs available"
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
                else
                    print_status "ERROR" "No VMs available"
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
                else
                    print_status "ERROR" "No VMs available"
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
                else
                    print_status "ERROR" "No VMs available"
                fi
                ;;
            9)
                show_system_status
                ;;
            0)
                print_status "ZYNE" "Thank you for using ZynexForge VM Manager! Goodbye!"
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

# Initialize paths
VM_DIR="${VM_DIR:-$HOME/.zynexforge/vms}"
mkdir -p "$VM_DIR"

# Enhanced OS Options with categories and Proxmox
declare -A OS_OPTIONS=(
    # Enterprise Virtualization
    ["Proxmox VE 8.0"]="proxmox|Enterprise|8.0|https://download.proxmox.com/iso/proxmox-ve_8.0-2.iso|proxmox-ve|root|proxmox123|Enterprise virtualization platform"
    
    # Server Distributions
    ["Ubuntu Server 24.04 LTS"]="ubuntu|Server|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu|Latest LTS server edition"
    ["Ubuntu Server 22.04 LTS"]="ubuntu|Server|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu|Stable LTS server edition"
    ["Debian 12 Bookworm"]="debian|Server|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian|Stable and reliable"
    ["Debian 11 Bullseye"]="debian|Server|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian|Long-term support"
    ["CentOS Stream 9"]="centos|Server|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos|Upstream for RHEL"
    ["AlmaLinux 9"]="almalinux|Server|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma|RHEL compatible"
    ["Rocky Linux 9"]="rockylinux|Server|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky|Community enterprise OS"
    
    # Desktop Distributions
    ["Fedora 40 Workstation"]="fedora|Desktop|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora|Cutting edge desktop"
    ["Ubuntu Desktop 24.04"]="ubuntu|Desktop|noble-desktop|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu-desktop|ubuntu|ubuntu|Desktop with cloud-init"
    
    # Specialized Distributions
    ["openSUSE Leap 15.5"]="opensuse|Specialized|leap15.5|https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-JeOS.x86_64-OpenStack.qcow2|opensuse|opensuse|opensuse|SUSE enterprise foundation"
    ["Arch Linux"]="arch|Specialized|latest|https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2|arch|arch|arch|Rolling release, minimal"
)

# Start the main menu
main_menu
