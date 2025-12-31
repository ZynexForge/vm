#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge VM Manager - Universal Version
# =============================

# Default Performance Configuration
DEFAULT_MEMORY="8192"    # 8GB RAM (reduced for VM environments)
DEFAULT_CPUS="4"         # 4 CPU cores
DEFAULT_DISK="100G"      # 100GB Disk

# Function to display header
display_header() {
    clear
    cat << "EOF"
__________                           ___________                         
\____    /___.__. ____   ____ ___  __\_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /|    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    < |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \\___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/    \/             /_____/      \/ 
                                                                         

                    ⚡ ZynexForge VM Manager ⚡
                    Universal Version - Works Everywhere
========================================================================
EOF
    echo -e "\033[1;36mZynexForge v3.0 | Optimized for Virtual Environments\033[0m"
    echo -e "\033[1;33mHost: QEMU System Emulator\033[0m"
    
    # Check environment
    if [ -f /.dockerenv ]; then
        echo -e "\033[1;35mEnvironment: Docker Container\033[0m"
    elif [[ $(systemd-detect-virt) != "none" ]]; then
        echo -e "\033[1;35mEnvironment: $(systemd-detect-virt | tr '[:lower:]' '[:upper:]')\033[0m"
    else
        echo -e "\033[1;35mEnvironment: Bare Metal / Unknown\033[0m"
    fi
    echo "========================================================================="
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
        "PERF") echo -e "\033[1;35m[PERF]\033[0m $message" ;;
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
        print_status "INFO" "Installing dependencies..."
        
        # Try to install automatically
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils wget
        elif command -v yum &> /dev/null; then
            sudo yum install -y qemu-kvm qemu-img cloud-utils wget
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y qemu-kvm qemu-img cloud-utils wget
        else
            print_status "ERROR" "Cannot auto-install. Please install manually:"
            print_status "INFO" "Ubuntu/Debian: sudo apt install qemu-system cloud-image-utils wget"
            print_status "INFO" "RHEL/CentOS: sudo yum install qemu-kvm qemu-img cloud-utils wget"
            exit 1
        fi
        
        # Check again
        for dep in "${deps[@]}"; do
            if ! command -v "$dep" &> /dev/null; then
                print_status "ERROR" "Still missing after install: $dep"
                exit 1
            fi
        done
    fi
    
    # Check for KVM but don't require it
    if [ ! -c /dev/kvm ]; then
        print_status "WARN" "KVM not available - using software emulation"
        print_status "INFO" "Performance will be slower but VMs will work"
    fi
}

# Function to cleanup temporary files
cleanup() {
    rm -f user-data meta-data network-config 2>/dev/null
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
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
EOF
    
    print_status "SUCCESS" "Configuration saved"
}

# Function to create new VM
create_new_vm() {
    display_header
    print_status "INFO" "Creating a new VM"
    
    # Get VM name
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name: ")" VM_NAME
        if validate_input "name" "$VM_NAME"; then
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM '$VM_NAME' already exists"
            else
                break
            fi
        fi
    done
    
    # OS Selection
    print_status "INFO" "Select an OS to set up:"
    echo "  1) Ubuntu 22.04 LTS"
    echo "  2) Ubuntu 24.04 LTS"
    echo "  3) Debian 12"
    echo "  4) Rocky Linux 9"
    echo "  5) Alpine Linux 3.19 (Lightweight)"
    
    while true; do
        read -p "$(print_status "INPUT" "Enter choice (1-5): ")" choice
        case $choice in
            1)
                OS_TYPE="ubuntu22"
                IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
                DEFAULT_USERNAME="ubuntu"
                DEFAULT_PASSWORD="ubuntu"
                break
                ;;
            2)
                OS_TYPE="ubuntu24"
                IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
                DEFAULT_USERNAME="ubuntu"
                DEFAULT_PASSWORD="ubuntu"
                break
                ;;
            3)
                OS_TYPE="debian12"
                IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
                DEFAULT_USERNAME="debian"
                DEFAULT_PASSWORD="debian"
                break
                ;;
            4)
                OS_TYPE="rocky9"
                IMG_URL="https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
                DEFAULT_USERNAME="rocky"
                DEFAULT_PASSWORD="rocky"
                break
                ;;
            5)
                OS_TYPE="alpine"
                IMG_URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-standard-3.19.0-x86_64.iso"
                DEFAULT_USERNAME="alpine"
                DEFAULT_PASSWORD="alpine"
                break
                ;;
            *)
                print_status "ERROR" "Invalid selection"
                ;;
        esac
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
    print_status "PERF" "=== Hardware Configuration ==="
    print_status "INFO" "Recommended for virtual environments: ${DEFAULT_MEMORY}MB RAM, ${DEFAULT_CPUS} CPUs, ${DEFAULT_DISK} Disk"
    echo

    # Memory Configuration
    while true; do
        read -p "$(print_status "INPUT" "Memory in MB (default: $DEFAULT_MEMORY): ")" MEMORY
        MEMORY="${MEMORY:-$DEFAULT_MEMORY}"
        if validate_input "number" "$MEMORY"; then
            if [[ $MEMORY -gt 32768 ]]; then
                print_status "WARN" "Large memory allocation may cause issues in virtual environments"
            fi
            break
        fi
    done

    # CPU Configuration
    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (default: $DEFAULT_CPUS): ")" CPUS
        CPUS="${CPUS:-$DEFAULT_CPUS}"
        if validate_input "number" "$CPUS"; then
            if [[ $CPUS -gt 8 ]]; then
                print_status "WARN" "High CPU count may cause performance issues"
            fi
            break
        fi
    done

    # Disk Configuration
    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: $DEFAULT_DISK): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-$DEFAULT_DISK}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    # Network Configuration
    while true; do
        SSH_PORT="2222"
        print_status "INFO" "SSH port set to: $SSH_PORT (default)"
        break
    done

    # Summary
    echo
    print_status "PERF" "=== Configuration Summary ==="
    print_status "INFO" "VM Name: $VM_NAME"
    print_status "INFO" "OS: $OS_TYPE"
    print_status "INFO" "Hostname: $HOSTNAME"
    print_status "INFO" "Username: $USERNAME"
    print_status "INFO" "Memory: ${MEMORY}MB ($((MEMORY/1024))GB)"
    print_status "INFO" "CPUs: $CPUS"
    print_status "INFO" "Disk: $DISK_SIZE"
    print_status "INFO" "SSH Port: $SSH_PORT"
    echo

    # Confirm
    read -p "$(print_status "INPUT" "Create VM with these settings? (y/N): ")" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "INFO" "VM creation cancelled"
        return
    fi

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    # Create VM directory
    mkdir -p "$VM_DIR"
    
    # Download image
    print_status "INFO" "Downloading OS image..."
    if ! wget -q --show-progress -O "$IMG_FILE" "$IMG_URL"; then
        print_status "ERROR" "Download failed"
        return 1
    fi
    
    # Resize disk if needed
    if [[ "$DISK_SIZE" != "100G" ]]; then
        print_status "INFO" "Resizing disk to $DISK_SIZE..."
        qemu-img resize "$IMG_FILE" "$DISK_SIZE" >/dev/null 2>&1 || \
        print_status "WARN" "Could not resize disk, using original size"
    fi

    # Create cloud-init config
    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(echo "$PASSWORD" | openssl passwd -6 -stdin 2>/dev/null || echo "")
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
EOF
    
    cat > meta-data <<EOF
instance-id: $VM_NAME
local-hostname: $HOSTNAME
EOF
    
    # Create seed image
    print_status "INFO" "Creating cloud-init config..."
    if cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "SUCCESS" "VM '$VM_NAME' created successfully!"
        save_vm_config
    else
        print_status "ERROR" "Failed to create seed image"
        return 1
    fi
}

# Function to start a VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $VM_NAME"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Password: $PASSWORD"
        print_status "PERF" "Resources: ${MEMORY}MB RAM, ${CPUS} CPUs, ${DISK_SIZE} Disk"
        
        # Check files exist
        if [[ ! -f "$IMG_FILE" ]] || [[ ! -f "$SEED_FILE" ]]; then
            print_status "ERROR" "VM files missing"
            return 1
        fi
        
        # Build QEMU command
        local qemu_cmd=(
            qemu-system-x86_64
            -m "$MEMORY"
            -smp "$CPUS"
            -drive "file=$IMG_FILE,format=qcow2,if=virtio"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
            -device "virtio-net-pci,netdev=n0"
            -nographic
            -serial mon:stdio
        )
        
        # Add KVM if available
        if [ -c /dev/kvm ]; then
            qemu_cmd=("-enable-kvm" "${qemu_cmd[@]}")
            print_status "PERF" "Using KVM acceleration"
        else
            print_status "INFO" "Using software emulation"
        fi
        
        # Add Alpine specific options if needed
        if [[ "$OS_TYPE" == "alpine" ]]; then
            qemu_cmd+=(-cdrom "$IMG_FILE" -boot d)
        else
            qemu_cmd+=(-boot c)
        fi
        
        print_status "INFO" "Starting QEMU..."
        echo "Command: ${qemu_cmd[*]}"
        echo
        
        # Run QEMU
        "${qemu_cmd[@]}"
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
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf" "$VM_DIR/$vm_name.pid" 2>/dev/null
            print_status "SUCCESS" "VM '$vm_name' has been deleted"
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
        print_status "INFO" "VM Information: $vm_name"
        echo "=========================================="
        echo "OS: $OS_TYPE"
        echo "Hostname: $HOSTNAME"
        echo "Username: $USERNAME"
        echo "Password: $PASSWORD"
        echo "SSH Port: $SSH_PORT"
        echo "Memory: $MEMORY MB"
        echo "CPUs: $CPUS"
        echo "Disk: $DISK_SIZE"
        echo "Created: $CREATED"
        echo "Image File: $IMG_FILE"
        echo "Seed File: $SEED_FILE"
        echo "=========================================="
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
            print_status "SUCCESS" "VM $vm_name stopped"
        else
            print_status "INFO" "VM $vm_name is not running"
        fi
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
                local status="🔴 Stopped"
                if is_vm_running "${vms[$i]}"; then
                    status="🟢 Running"
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
            echo "  5) Delete a VM"
        fi
        echo "  6) System Information"
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
                    read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                display_header
                print_status "INFO" "System Information"
                echo "=========================================="
                echo "CPU: $(grep -c ^processor /proc/cpuinfo) cores"
                echo "Memory: $(free -h | grep Mem | awk '{print $2}') total"
                echo "Disk: $(df -h / | tail -1 | awk '{print $4}') available"
                echo "QEMU: $(qemu-system-x86_64 --version | head -1)"
                
                if [ -c /dev/kvm ]; then
                    echo "KVM: ✅ Available"
                else
                    echo "KVM: ❌ Not available"
                fi
                
                if [ -f /.dockerenv ]; then
                    echo "Container: ✅ Docker"
                elif [[ $(systemd-detect-virt) != "none" ]]; then
                    echo "Virtualization: $(systemd-detect-virt)"
                fi
                echo "VM Directory: $VM_DIR"
                echo "=========================================="
                read -p "$(print_status "INPUT" "Press Enter to continue...")"
                ;;
            0)
                print_status "INFO" "Thank you for using ZynexForge VM Manager!"
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

# Check and install dependencies
check_dependencies

# Initialize paths
VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

# Start the main menu
print_status "INFO" "Initializing ZynexForge VM Manager..."
sleep 1
main_menu
