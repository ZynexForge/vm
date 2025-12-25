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
        "LOCATION") echo -e "${COLOR_MAGENTA}[LOCATION]${COLOR_RESET} $message" ;;
        "NODE") echo -e "${COLOR_GRAY}[NODE]${COLOR_RESET} $message" ;;
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
    esac
    return 0
}

# Function to check dependencies
check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "On Ubuntu/Debian, try: sudo apt install qemu-system cloud-image-utils wget"
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
        unset LOCATION NODE_PATH LOCATION_ID NETWORK_RANGE
        
        source "$config_file"
        
        # Update paths based on location
        if [[ -n "$LOCATION" && -n "${LOCATION_NODES[$LOCATION]}" ]]; then
            NODE_PATH="${LOCATION_NODES[$LOCATION]}"
            LOCATION_ID="${LOCATION_IDS[$LOCATION]}"
            NETWORK_RANGE="${LOCATION_NETWORKS[$LOCATION]}"
            IMG_FILE="$NODE_PATH/$VM_NAME.img"
            SEED_FILE="$NODE_PATH/$VM_NAME-seed.iso"
        fi
        
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
LOCATION="$LOCATION"
NODE_PATH="$NODE_PATH"
LOCATION_ID="$LOCATION_ID"
NETWORK_RANGE="$NETWORK_RANGE"
EOF
    
    print_status "SUCCESS" "Configuration saved"
}

# Function to show location selection with availability check
select_location() {
    section_header "DATACENTER LOCATION SELECTION"
    
    local locations=()
    local i=1
    
    print_status "INFO" "Available locations:"
    echo
    
    # Create arrays for menu display
    local location_names=()
    for loc in "${!LOCATION_NODES[@]}"; do
        location_names+=("$loc")
    done
    
    # Sort locations alphabetically
    IFS=$'\n' sorted_locations=($(sort <<<"${location_names[*]}"))
    unset IFS
    
    # Display sorted locations
    for loc in "${sorted_locations[@]}"; do
        local node_path="${LOCATION_NODES[$loc]}"
        
        # Check location availability
        if [ -d "$node_path" ]; then
            echo -e "  ${COLOR_GREEN}$i) $loc${COLOR_RESET}"
        else
            echo -e "  ${COLOR_RED}$i) $loc (OFFLINE)${COLOR_RESET}"
        fi
        ((i++))
    done
    
    echo
    while true; do
        read -p "$(print_status "INPUT" "Select location (1-${#sorted_locations[@]}): ")" choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#sorted_locations[@]} ]; then
            local selected_loc="${sorted_locations[$((choice-1))]}"
            local node_path="${LOCATION_NODES[$selected_loc]}"
            
            if [ -d "$node_path" ]; then
                LOCATION="$selected_loc"
                NODE_PATH="$node_path"
                LOCATION_ID="${LOCATION_IDS[$LOCATION]}"
                NETWORK_RANGE="${LOCATION_NETWORKS[$LOCATION]}"
                
                print_status "LOCATION" "Selected: $LOCATION"
                print_status "NODE" "Node ID: $LOCATION_ID"
                print_status "NODE" "Network: $NETWORK_RANGE"
                break
            else
                print_status "ERROR" "Location '$selected_loc' is unavailable. Please select an online location."
            fi
        else
            print_status "ERROR" "Invalid selection. Please enter a number between 1 and ${#sorted_locations[@]}."
        fi
    done
}

# Function to create new VM
create_new_vm() {
    display_header
    section_header "CREATE NEW VIRTUAL MACHINE"
    
    # Location selection
    select_location
    
    # Create node directory if it doesn't exist
    mkdir -p "$NODE_PATH"
    
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
        echo -e "${COLOR_YELLOW}Password requirements:${COLOR_RESET} Minimum 4 characters"
        read -s -p "$(print_status "INPUT" "Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        if [ -n "$PASSWORD" ] && [ ${#PASSWORD} -ge 4 ]; then
            break
        else
            print_status "ERROR" "Password must be at least 4 characters"
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

    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80, press Enter for none): ")" PORT_FORWARDS

    # Final configuration
    IMG_FILE="$NODE_PATH/$VM_NAME.img"
    SEED_FILE="$NODE_PATH/$VM_NAME-seed.iso"
    CREATED="$(date)"

    section_header "DEPLOYMENT SUMMARY"
    echo -e "${COLOR_WHITE}VM Configuration:${COLOR_RESET}"
    echo -e "  Name: ${COLOR_CYAN}$VM_NAME${COLOR_RESET}"
    echo -e "  Location: ${COLOR_MAGENTA}$LOCATION${COLOR_RESET} (Node: $LOCATION_ID)"
    echo -e "  OS: ${COLOR_GREEN}$os${COLOR_RESET}"
    echo -e "  Resources: ${COLOR_YELLOW}$CPUS vCPU | ${MEMORY}MB RAM | $DISK_SIZE disk${COLOR_RESET}"
    echo -e "  Network: SSH on port ${COLOR_CYAN}$SSH_PORT${COLOR_RESET} ($NETWORK_RANGE)"
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
    print_status "SUCCESS" "VM '$VM_NAME' deployed successfully to $LOCATION"
    echo -e "  ${COLOR_GRAY}Location: $LOCATION (Node: $LOCATION_ID)${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}SSH Access: ssh -p $SSH_PORT $USERNAME@localhost${COLOR_RESET}"
    echo -e "  ${COLOR_GRAY}Management: $VM_DIR/$VM_NAME.conf${COLOR_RESET}"
}

# Function to setup VM image
setup_vm_image() {
    print_status "INFO" "Initializing VM storage in $LOCATION..."
    
    # Create VM directory if it doesn't exist
    mkdir -p "$VM_DIR"
    mkdir -p "$NODE_PATH"
    
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

    # cloud-init configuration
    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD" 2>/dev/null || echo "$PASSWORD" | mkpasswd -m sha-512 -s 2>/dev/null || echo "$PASSWORD")
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

    if ! cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
}

# Function to start a VM with advanced boot options
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "STARTING VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "${COLOR_WHITE}Location:${COLOR_RESET} ${COLOR_MAGENTA}$LOCATION${COLOR_RESET} (Node: $LOCATION_ID)"
        echo -e "${COLOR_WHITE}OS:${COLOR_RESET} $OS_TYPE"
        echo -e "${COLOR_WHITE}Resources:${COLOR_RESET} ${COLOR_YELLOW}$CPUS vCPU | ${MEMORY}MB RAM${COLOR_RESET}"
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
        echo -e "  ${COLOR_GRAY}SSH: ssh -p $SSH_PORT $USERNAME@localhost${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Password: $PASSWORD${COLOR_RESET}"
        echo
        
        # Advanced boot configuration
        print_status "INFO" "Advanced Boot Configuration:"
        echo -e "  ${COLOR_GRAY}Boot Method:${COLOR_RESET} Hard Disk Priority"
        echo -e "  ${COLOR_GRAY}Disk Interface:${COLOR_RESET} VirtIO with write-back caching"
        echo -e "  ${COLOR_GRAY}Boot Priority:${COLOR_RESET} Hard Disk → Cloud-Init Seed"
        
        # Generate random MAC address
        local mac_addr="52:54:00:$(printf '%02x:%02x:%02x' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))"
        
        # Base QEMU command with optimized boot options
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -machine q35,accel=kvm
            -m "$MEMORY"
            -smp "$CPUS"
            -cpu host
            -drive "file=$IMG_FILE,format=qcow2,if=virtio,cache=writeback"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -boot "order=c"
            -device virtio-net-pci,netdev=n0,mac="$mac_addr"
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
        )

        # Add UEFI firmware if available
        if [ -f "/usr/share/OVMF/OVMF_CODE.fd" ] && [ -f "/usr/share/OVMF/OVMF_VARS.fd" ]; then
            qemu_cmd+=(
                -drive "if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd"
                -drive "if=pflash,format=raw,file=/tmp/OVMF_VARS_$VM_NAME.fd"
            )
            cp "/usr/share/OVMF/OVMF_VARS.fd" "/tmp/OVMF_VARS_$VM_NAME.fd" 2>/dev/null || true
        fi

        # Add port forwards if specified
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                qemu_cmd+=(-device "virtio-net-pci,netdev=n${#qemu_cmd[@]}")
                qemu_cmd+=(-netdev "user,id=n${#qemu_cmd[@]},hostfwd=tcp::$host_port-:$guest_port")
            done
        fi

        # Add GUI or console mode with optimized display
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(
                -vga virtio
                -display gtk,gl=on
                -usb
                -device usb-tablet
            )
        else
            qemu_cmd+=(
                -nographic
                -serial mon:stdio
            )
        fi

        # Add performance enhancements
        qemu_cmd+=(
            -device virtio-balloon-pci
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
            -rtc base=utc,clock=host
        )

        print_status "INFO" "Starting QEMU instance..."
        echo "$SUBTLE_SEP"
        
        # Cleanup any previous monitor sockets
        rm -f "/tmp/OVMF_VARS_$VM_NAME.fd" "/tmp/qemu-monitor-$VM_NAME.sock" "/tmp/qemu-qmp-$VM_NAME.sock" 2>/dev/null || true
        
        # Start QEMU
        if "${qemu_cmd[@]}"; then
            print_status "INFO" "VM $vm_name has been shut down"
        else
            print_status "ERROR" "Failed to start VM $vm_name"
            return 1
        fi
    fi
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        section_header "DELETE VIRTUAL MACHINE"
        echo -e "${COLOR_WHITE}VM:${COLOR_RESET} ${COLOR_CYAN}$vm_name${COLOR_RESET}"
        echo -e "${COLOR_WHITE}Location:${COLOR_RESET} ${COLOR_MAGENTA}$LOCATION${COLOR_RESET} (Node: $LOCATION_ID)"
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
            print_status "SUCCESS" "VM '$vm_name' has been deleted from $LOCATION"
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
        echo -e "  ${COLOR_GRAY}Location:${COLOR_RESET} ${COLOR_MAGENTA}$LOCATION${COLOR_RESET} (Node: $LOCATION_ID)"
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
        echo -e "  ${COLOR_GRAY}SSH Port:${COLOR_RESET} ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
        echo -e "  ${COLOR_GRAY}Network Range:${COLOR_RESET} $NETWORK_RANGE"
        if [[ -n "$PORT_FORWARDS" ]]; then
            echo -e "  ${COLOR_GRAY}Port Forwards:${COLOR_RESET} $PORT_FORWARDS"
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
    
    # Check by process name
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
        echo -e "${COLOR_WHITE}Location:${COLOR_RESET} ${COLOR_MAGENTA}$LOCATION${COLOR_RESET}"
        
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM..."
            
            # Get the QEMU process ID
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$vm_name")
            
            if [ -n "$qemu_pid" ]; then
                # Send SIGTERM first
                kill -TERM "$qemu_pid" 2>/dev/null
                sleep 2
                
                # Check if still running
                if kill -0 "$qemu_pid" 2>/dev/null; then
                    print_status "WARN" "VM did not stop gracefully, forcing termination..."
                    kill -KILL "$qemu_pid" 2>/dev/null
                    sleep 1
                fi
            else
                # Try to kill by image file
                pkill -f "qemu-system-x86_64.*$IMG_FILE"
                sleep 2
                if is_vm_running "$vm_name"; then
                    print_status "WARN" "VM did not stop gracefully, forcing termination..."
                    pkill -9 -f "qemu-system-x86_64.*$IMG_FILE"
                fi
            fi
            
            # Cleanup temporary files
            rm -f "/tmp/OVMF_VARS_$vm_name.fd" "/tmp/qemu-monitor-$vm_name.sock" "/tmp/qemu-qmp-$vm_name.sock" 2>/dev/null || true
            
            if is_vm_running "$vm_name"; then
                print_status "ERROR" "Failed to stop VM $vm_name"
                return 1
            else
                print_status "SUCCESS" "VM $vm_name stopped"
            fi
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
        echo -e "${COLOR_WHITE}Location:${COLOR_RESET} ${COLOR_MAGENTA}$LOCATION${COLOR_RESET} (Node: $LOCATION_ID)"
        echo
        
        while true; do
            echo "Edit Options:"
            echo "  1) Basic Information"
            echo "  2) Resource Allocation"
            echo "  3) Network Configuration"
            echo "  4) Access Credentials"
            echo "  5) Change Location"
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
                    echo -e "  ${COLOR_GRAY}SSH Port:${COLOR_RESET} ${COLOR_CYAN}$SSH_PORT${COLOR_RESET}"
                    echo -e "  ${COLOR_GRAY}Port Forwards:${COLOR_RESET} ${PORT_FORWARDS:-None}"
                    echo -e "  ${COLOR_GRAY}GUI Mode:${COLOR_RESET} $GUI_MODE"
                    echo
                    
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
                    
                    read -p "$(print_status "INPUT" "Additional port forwards (current: ${PORT_FORWARDS:-None}): ")" new_port_forwards
                    PORT_FORWARDS="${new_port_forwards:-$PORT_FORWARDS}"
                    
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
                        echo -e "${COLOR_YELLOW}Password requirements:${COLOR_RESET} Minimum 4 characters"
                        read -s -p "$(print_status "INPUT" "Enter new password (current: ****): ")" new_password
                        new_password="${new_password:-$PASSWORD}"
                        echo
                        if [ -n "$new_password" ] && [ ${#new_password} -ge 4 ]; then
                            PASSWORD="$new_password"
                            break
                        else
                            print_status "ERROR" "Password must be at least 4 characters"
                        fi
                    done
                    
                    # Recreate seed image
                    print_status "INFO" "Updating cloud-init configuration..."
                    setup_vm_image
                    save_vm_config
                    print_status "SUCCESS" "Access credentials updated"
                    ;;
                    
                5)
                    section_header "CHANGE VM LOCATION"
                    
                    echo "Current location:"
                    echo -e "  ${COLOR_GRAY}Location:${COLOR_RESET} ${COLOR_MAGENTA}$LOCATION${COLOR_RESET}"
                    echo -e "  ${COLOR_GRAY}Node ID:${COLOR_RESET} $LOCATION_ID"
                    echo -e "  ${COLOR_GRAY}Storage Path:${COLOR_RESET} $NODE_PATH"
                    echo
                    
                    print_status "INFO" "Select new location:"
                    select_location
                    
                    # Move VM files to new location
                    local old_img_file="$IMG_FILE"
                    local old_seed_file="$SEED_FILE"
                    
                    IMG_FILE="$NODE_PATH/$VM_NAME.img"
                    SEED_FILE="$NODE_PATH/$VM_NAME-seed.iso"
                    
                    mkdir -p "$NODE_PATH"
                    if [[ -f "$old_img_file" ]]; then
                        print_status "INFO" "Moving disk image to new location..."
                        mv "$old_img_file" "$IMG_FILE" 2>/dev/null || true
                    fi
                    if [[ -f "$old_seed_file" ]]; then
                        print_status "INFO" "Moving seed image to new location..."
                        mv "$old_seed_file" "$SEED_FILE" 2>/dev/null || true
                    fi
                    
                    save_vm_config
                    print_status "SUCCESS" "VM location changed to $LOCATION"
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
        echo -e "${COLOR_WHITE}Location:${COLOR_RESET} ${COLOR_MAGENTA}$LOCATION${COLOR_RESET}"
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
        echo -e "${COLOR_WHITE}Location:${COLOR_RESET} ${COLOR_MAGENTA}$LOCATION${COLOR_RESET} (Node: $LOCATION_ID)"
        
        if is_vm_running "$vm_name"; then
            # Get QEMU process ID
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$vm_name")
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
    if [ -d "$VM_BASE_DIR" ]; then
        local total_storage=$(du -sh "$VM_BASE_DIR" 2>/dev/null | cut -f1)
        echo -e "  ${COLOR_GRAY}Total Storage:${COLOR_RESET} $total_storage"
    else
        echo -e "  ${COLOR_GRAY}Total Storage:${COLOR_RESET} Not available"
    fi
    echo
    
    # Show location distribution
    echo -e "${COLOR_WHITE}VM Distribution by Location:${COLOR_RESET}"
    for loc in "${!LOCATION_NODES[@]}"; do
        local node_vms=$(grep -l "LOCATION=\"$loc\"" "$VM_DIR"/*.conf 2>/dev/null | wc -l)
        if [ "$node_vms" -gt 0 ]; then
            local node_path="${LOCATION_NODES[$loc]}"
            local node_usage=""
            if [ -d "$node_path" ]; then
                node_usage="($(du -sh "$node_path" 2>/dev/null | cut -f1))"
            fi
            echo -e "  ${COLOR_MAGENTA}📍 $loc:${COLOR_RESET} ${COLOR_CYAN}$node_vms${COLOR_RESET} VM(s) $node_usage"
        fi
    done
    
    echo
    echo -e "${COLOR_WHITE}Location Status:${COLOR_RESET}"
    for loc in "${!LOCATION_NODES[@]}"; do
        local node_path="${LOCATION_NODES[$loc]}"
        if [ -d "$node_path" ]; then
            echo -e "  ${COLOR_GREEN}● $loc${COLOR_RESET} (Online)"
        else
            echo -e "  ${COLOR_RED}● $loc${COLOR_RESET} (Offline)"
        fi
    done
    
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
                local config_file="$VM_DIR/$vm_name.conf"
                local location="Unknown"
                local status="Stopped"
                
                if [ -f "$config_file" ]; then
                    source "$config_file" 2>/dev/null || true
                    location="${LOCATION:-Unknown}"
                fi
                
                if is_vm_running "$vm_name"; then
                    status="${COLOR_GREEN}● Running${COLOR_RESET}"
                else
                    status="${COLOR_YELLOW}● Stopped${COLOR_RESET}"
                fi
                
                printf "  %2d) %-20s %-25s %s\n" $((i+1)) "$vm_name" "[$location]" "$status"
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
        
        if [ "$choice" != "0" ]; then
            read -p "$(print_status "INPUT" "Press Enter to continue...")"
        fi
    done
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check dependencies
check_dependencies

# Initialize paths
VM_DIR="${VM_DIR:-$HOME/vms}"
VM_BASE_DIR="$HOME/.zynexforge"
mkdir -p "$VM_DIR"

# Enterprise Location System
# Format: LOCATION_NODES["Location Name"]="node_storage_path"
declare -A LOCATION_NODES=(
    ["Mumbai"]="$VM_BASE_DIR/nodes/IN-MUM"
    ["Singapore"]="$VM_BASE_DIR/nodes/SG-SIN"
    ["Frankfurt"]="$VM_BASE_DIR/nodes/DE-FRA"
    ["Ashburn"]="$VM_BASE_DIR/nodes/US-ASH"
    ["London"]="$VM_BASE_DIR/nodes/UK-LON"
    ["Paris"]="$VM_BASE_DIR/nodes/FR-PAR"
    ["Amsterdam"]="$VM_BASE_DIR/nodes/NL-AMS"
    ["Tokyo"]="$VM_BASE_DIR/nodes/JP-TYO"
    ["Sydney"]="$VM_BASE_DIR/nodes/AU-SYD"
    ["Dubai"]="$VM_BASE_DIR/nodes/AE-DXB"
    ["Toronto"]="$VM_BASE_DIR/nodes/CA-TOR"
    ["São Paulo"]="$VM_BASE_DIR/nodes/BR-SAO"
    ["Stockholm"]="$VM_BASE_DIR/nodes/SE-STO"
    ["Zurich"]="$VM_BASE_DIR/nodes/CH-ZRH"
    ["Seoul"]="$VM_BASE_DIR/nodes/KR-SEL"
)

# Location metadata
declare -A LOCATION_IDS=(
    ["Mumbai"]="IN-MUM-01"
    ["Singapore"]="SG-SIN-01"
    ["Frankfurt"]="DE-FRA-01"
    ["Ashburn"]="US-ASH-01"
    ["London"]="UK-LON-01"
    ["Paris"]="FR-PAR-01"
    ["Amsterdam"]="NL-AMS-01"
    ["Tokyo"]="JP-TYO-01"
    ["Sydney"]="AU-SYD-01"
    ["Dubai"]="AE-DXB-01"
    ["Toronto"]="CA-TOR-01"
    ["São Paulo"]="BR-SAO-01"
    ["Stockholm"]="SE-STO-01"
    ["Zurich"]="CH-ZRH-01"
    ["Seoul"]="KR-SEL-01"
)

# Location network ranges
declare -A LOCATION_NETWORKS=(
    ["Mumbai"]="10.10.0.0/16"
    ["Singapore"]="10.20.0.0/16"
    ["Frankfurt"]="10.30.0.0/16"
    ["Ashburn"]="10.40.0.0/16"
    ["London"]="10.50.0.0/16"
    ["Paris"]="10.60.0.0/16"
    ["Amsterdam"]="10.70.0.0/16"
    ["Tokyo"]="10.80.0.0/16"
    ["Sydney"]="10.90.0.0/16"
    ["Dubai"]="10.100.0.0/16"
    ["Toronto"]="10.110.0.0/16"
    ["São Paulo"]="10.120.0.0/16"
    ["Stockholm"]="10.130.0.0/16"
    ["Zurich"]="10.140.0.0/16"
    ["Seoul"]="10.150.0.0/16"
)

# Create node directories
for node_path in "${LOCATION_NODES[@]}"; do
    mkdir -p "$node_path"
done

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
