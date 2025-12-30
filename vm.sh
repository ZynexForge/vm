#!/bin/bash
set -euo pipefail

# ================================================
# ZYNEXFORGE VM ENGINE
# Advanced QEMU/KVM Virtualization Manager
# Version: 6.0
# Author: FaaizJohar
# Optimized for AMD EPYC
# ================================================

# Global Variables
VM_DIR="${VM_DIR:-$HOME/zynexforge-vms}"
CONFIG_DIR="$VM_DIR/configs"
LOG_DIR="$VM_DIR/logs"
SCRIPT_VERSION="6.0"
BRAND_PREFIX="ZynexForge-"

# EPYC CPU Optimizations
EPYC_CPU_FLAGS="host,topoext=on,svm=on,kvm=on"
EPYC_CPU_TOPOLOGY="sockets=1,dies=1,cores=8,threads=2"

# Display banner
display_banner() {
    clear
    cat << "EOF"
__________                             ___________                         
\____    /__>.__. ____   ____ ___  ___ \_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /  |    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    <   |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \  \___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/      \/             /_____/      \/ 

        ZynexForge VM Engine v6.0 | AMD EPYC Optimized | Powered by FaaizXD
===============================================================================
EOF
    echo ""
}

# Color functions
print_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
print_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
print_error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }
print_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
print_input() { echo -e "\033[1;36m[INPUT]\033[0m $1"; }

# Logging
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$LOG_DIR"
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/zynexforge.log"
}

# Initialize directories
init_dirs() {
    mkdir -p "$VM_DIR" "$CONFIG_DIR" "$LOG_DIR" "$VM_DIR/isos" "$VM_DIR/disks"
    chmod 755 "$VM_DIR" "$CONFIG_DIR" "$LOG_DIR"
}

# Check dependencies
check_deps() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "openssl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing: ${missing[*]}"
        print_info "Install: sudo apt install qemu-system cloud-image-utils wget openssl"
        exit 1
    fi
}

# Check EPYC optimizations
check_epyc() {
    if grep -qi "AMD EPYC" /proc/cpuinfo; then
        print_info "AMD EPYC detected - optimizations enabled"
    else
        print_warn "Non-EPYC CPU - some optimizations limited"
    fi
    
    if [ ! -e /dev/kvm ]; then
        print_warn "KVM not available (check BIOS/virtualization)"
    fi
}

# Validation functions (improved from script 2)
validate_input() {
    local type="$1"
    local value="$2"
    
    case $type in
        "number")
            [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 1 ]
            ;;
        "size")
            [[ "$value" =~ ^[0-9]+[GgMm]$ ]]
            ;;
        "port")
            [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 1024 ] && [ "$value" -le 65535 ]
            ;;
        "name")
            [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] && [ ${#1} -le 32 ]
            ;;
        "username")
            [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]] && [ ${#1} -le 32 ]
            ;;
        *)
            return 1
            ;;
    esac
}

check_port_free() {
    ! ss -tln 2>/dev/null | grep -q ":$1 "
}

# Check if VM is running
is_vm_running() {
    local vm_name="$1"
    if pgrep -f "qemu-system-x86_64.*$vm_name" >/dev/null; then
        return 0
    else
        return 1
    fi
}

# OS Options
declare -A OS_IMAGES=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Kali Linux"]="kali|rolling|https://cloud.kali.org/kali/images/kali-2024.4/kali-linux-2024.4-genericcloud-amd64.qcow2|kali|kali|kali"
    ["Arch Linux"]="arch|latest|https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2|archlinux|arch|arch"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
)

# Download image with retry - IMPROVED VERSION
download_image() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0
    
    # Ensure directory exists
    mkdir -p "$(dirname "$output")"
    
    print_info "Downloading: $(basename "$url")"
    
    while [ $retry_count -lt $max_retries ]; do
        if wget --progress=bar:force --timeout=60 --tries=3 "$url" -O "$output.tmp"; then
            mv "$output.tmp" "$output"
            print_success "Download completed: $(basename "$output")"
            return 0
        fi
        
        ((retry_count++))
        
        if [ $retry_count -lt $max_retries ]; then
            print_warn "Download failed, retrying ($retry_count/$max_retries)..."
            sleep 2
        fi
    done
    
    print_error "Download failed after $max_retries attempts"
    return 1
}

# Get VM list
list_vms() {
    find "$CONFIG_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

# Load VM config
load_config() {
    local vm="$1"
    local config="$CONFIG_DIR/$vm.conf"
    
    if [[ -f "$config" ]]; then
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        
        source "$config"
        return 0
    else
        print_error "Config not found: $vm"
        return 1
    fi
}

# Save VM config
save_config() {
    local config="$CONFIG_DIR/$VM_NAME.conf"
    
    cat > "$config" <<EOF
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
EOF
    
    chmod 600 "$config"
    print_success "Configuration saved: $config"
    log_message "CONFIG" "Saved: $VM_NAME"
}

# Create VM (improved with better validation)
create_vm() {
    display_banner
    print_info "Creating new ZynexForge VM"
    
    # OS selection - display with numbers
    print_info "Select an OS distribution:"
    local i=1
    local os_names=()
    for os_name in "${!OS_IMAGES[@]}"; do
        printf "  %2d) %s\n" "$i" "$os_name"
        os_names[$i]="$os_name"
        ((i++))
    done
    
    local choice
    while true; do
        read -p "$(print_input "Enter your choice (1-${#OS_IMAGES[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_IMAGES[@]} ]; then
            local selected_os="${os_names[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USER DEFAULT_PASS <<< "${OS_IMAGES[$selected_os]}"
            break
        fi
        print_error "Invalid selection. Try again."
    done
    
    # VM name with branding
    local vm_name
    while true; do
        read -p "$(print_input "Enter VM name (default: ${BRAND_PREFIX}${DEFAULT_HOSTNAME}): ")" vm_name
        vm_name="${vm_name:-${BRAND_PREFIX}${DEFAULT_HOSTNAME}}"
        if validate_input "name" "$vm_name"; then
            if [[ -f "$CONFIG_DIR/$vm_name.conf" ]]; then
                print_error "VM with name '$vm_name' already exists"
            else
                VM_NAME="$vm_name"
                break
            fi
        else
            print_error "VM name can only contain letters, numbers, hyphens, underscores (max 32 chars)"
        fi
    done
    
    # Hostname
    while true; do
        read -p "$(print_input "Enter hostname (default: $VM_NAME): ")" HOSTNAME
        HOSTNAME="${HOSTNAME:-$VM_NAME}"
        if validate_input "name" "$HOSTNAME"; then
            break
        fi
    done
    
    # Username
    while true; do
        read -p "$(print_input "Enter username (default: $DEFAULT_USER): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USER}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
        print_error "Username must start with a letter or underscore, contain only lowercase letters, numbers, hyphens, underscores"
    done
    
    # Password
    while true; do
        read -s -p "$(print_input "Enter password (default: $DEFAULT_PASS): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASS}"
        echo
        if [ -n "$PASSWORD" ]; then
            break
        else
            print_error "Password cannot be empty"
        fi
    done
    
    # Disk size
    while true; do
        read -p "$(print_input "Disk size (default: 50G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-50G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
        print_error "Must be a size with unit (e.g., 50G, 100G, 500G)"
    done
    
    # Memory
    while true; do
        read -p "$(print_input "Memory in MB (default: 4096): ")" MEMORY
        MEMORY="${MEMORY:-4096}"
        if validate_input "number" "$MEMORY"; then
            break
        fi
        print_error "Must be a positive number"
    done
    
    # vCPUs
    while true; do
        read -p "$(print_input "Number of vCPUs (default: 4): ")" CPUS
        CPUS="${CPUS:-4}"
        if validate_input "number" "$CPUS"; then
            break
        fi
        print_error "Must be a positive number"
    done
    
    # SSH Port
    while true; do
        read -p "$(print_input "SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT"; then
            if check_port_free "$SSH_PORT"; then
                break
            else
                print_error "Port $SSH_PORT is already in use"
            fi
        else
            print_error "Port must be between 1024-65535"
        fi
    done
    
    # GUI mode
    while true; do
        read -p "$(print_input "Enable GUI mode? (y/N): ")" gui_choice
        gui_choice="${gui_choice:-n}"
        if [[ "$gui_choice" =~ ^[Yy]$ ]]; then
            GUI_MODE=true
            break
        elif [[ "$gui_choice" =~ ^[Nn]$ ]]; then
            GUI_MODE=false
            break
        else
            print_error "Please answer y or n"
        fi
    done
    
    # Port forwards
    read -p "$(print_input "Additional port forwards (e.g., 8080:80,8443:443): ")" PORT_FORWARDS
    
    # Set file paths
    IMG_FILE="$VM_DIR/disks/$VM_NAME.qcow2"
    SEED_FILE="$VM_DIR/isos/$VM_NAME-seed.iso"
    CREATED=$(date)
    
    # Setup VM
    setup_vm
    
    # Save config
    save_config
    
    print_success "ZynexForge VM '$VM_NAME' created successfully!"
    print_info "Configuration: $CPUS vCPUs, ${MEMORY}MB RAM, $DISK_SIZE disk"
    print_info "To start: Select VM from main menu"
}

# Setup VM image (improved)
setup_vm() {
    print_info "Preparing VM image..."
    
    # Ensure directories exist
    mkdir -p "$(dirname "$IMG_FILE")" "$(dirname "$SEED_FILE")"
    
    # Download image if not exists
    if [[ ! -f "$IMG_FILE" ]]; then
        print_info "Downloading OS image: $OS_TYPE"
        if ! download_image "$IMG_URL" "$IMG_FILE"; then
            print_error "Failed to download image. Please check your internet connection and try again."
            exit 1
        fi
    else
        print_info "Image already exists, skipping download"
    fi
    
    # Resize disk (improved from script 2)
    print_info "Configuring disk to $DISK_SIZE..."
    if ! qemu-img resize -f qcow2 "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
        print_info "Creating new disk image with specified size..."
        qemu-img create -f qcow2 -o preallocation=metadata "$IMG_FILE" "$DISK_SIZE"
    fi
    
    # Generate password hash using openssl (improved)
    local pass_hash
    if command -v openssl &> /dev/null; then
        pass_hash=$(openssl passwd -6 "$PASSWORD" 2>/dev/null || echo "$PASSWORD")
    elif command -v mkpasswd &> /dev/null; then
        pass_hash=$(mkpasswd -m sha-512 "$PASSWORD" 2>/dev/null || echo "$PASSWORD")
    else
        pass_hash="$PASSWORD"
        print_warn "Using plain password (install 'openssl' package for secure hashing)"
    fi
    
    # Cloud-init config
    cat > /tmp/user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    password: $pass_hash
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
EOF
    
    cat > /tmp/meta-data <<EOF
instance-id: $VM_NAME
local-hostname: $HOSTNAME
EOF
    
    # Create seed image
    print_info "Creating cloud-init seed image..."
    if cloud-localds "$SEED_FILE" /tmp/user-data /tmp/meta-data; then
        print_success "Cloud-init seed created"
    else
        print_error "Failed to create cloud-init seed image"
        exit 1
    fi
    
    rm -f /tmp/user-data /tmp/meta-data
    print_success "VM setup complete"
    log_message "CREATE" "Created VM: $VM_NAME ($OS_TYPE)"
}

# Start VM (FIXED - runs in foreground like Script 2)
start_vm() {
    local vm="$1"
    
    if load_config "$vm"; then
        # Check if running
        if is_vm_running "$vm"; then
            print_warn "$vm is already running"
            return 0
        fi
        
        # Remove stale PID file
        rm -f "$VM_DIR/$vm.pid" 2>/dev/null
        
        # Verify files exist
        if [[ ! -f "$IMG_FILE" ]]; then
            print_error "VM image file not found: $IMG_FILE"
            print_info "Recreating VM setup..."
            setup_vm
        fi
        
        if [[ ! -f "$SEED_FILE" ]]; then
            print_warn "Seed file not found, recreating..."
            setup_vm
        fi
        
        print_info "Starting ZynexForge VM: $vm"
        print_info "SSH Access: ssh -p $SSH_PORT $USERNAME@localhost"
        print_info "Password: $PASSWORD"
        
        # Build QEMU command
        local qemu_cmd=(
            qemu-system-x86_64
            -name "$vm"
            -enable-kvm
            -cpu "$EPYC_CPU_FLAGS"
            -smp "$CPUS"
            -m "$MEMORY"
            -drive "file=$IMG_FILE,if=virtio,format=qcow2,cache=directsync"
            -drive "file=$SEED_FILE,if=virtio,format=raw,readonly=on"
            -netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22"
            -device "virtio-net-pci,netdev=net0,mac=52:54:00:$(printf '%02x' $((RANDOM%256))):$(printf '%02x' $((RANDOM%256))):$(printf '%02x' $((RANDOM%256)))"
            -device virtio-balloon-pci
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
            -rtc base=utc,clock=host
            -nodefaults
            -boot order=c
        )
        
        # Add port forwards (improved from script 2)
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            local net_id=1
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                if [[ -n "$host_port" && -n "$guest_port" ]]; then
                    qemu_cmd+=(-device "virtio-net-pci,netdev=net$net_id")
                    qemu_cmd+=(-netdev "user,id=net$net_id,hostfwd=tcp::$host_port-:$guest_port")
                    ((net_id++))
                fi
            done
        fi
        
        # GUI or console mode
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga virtio -display gtk,gl=on)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi
        
        print_info "Starting QEMU with EPYC optimizations..."
        echo ""
        print_info "══════════════════════════════════════════════════"
        print_info "VM '$vm' is now running!"
        print_info "SSH Connection: ssh -p $SSH_PORT $USERNAME@localhost"
        print_info "Password: $PASSWORD"
        if [[ "$GUI_MODE" == false ]]; then
            print_info "To exit: Press 'Ctrl+A' then 'X'"
        fi
        print_info "══════════════════════════════════════════════════"
        echo ""
        
        # Run QEMU in FOREGROUND (like Script 2)
        "${qemu_cmd[@]}"
        
        # After QEMU exits (VM is shut down)
        print_info "VM $vm has been shut down"
        log_message "STOP" "VM stopped: $vm"
    fi
}

# Stop VM (for use from menu when VM is running in background)
stop_vm() {
    local vm="$1"
    
    if load_config "$vm"; then
        if is_vm_running "$vm"; then
            print_info "Stopping VM: $vm"
            
            # Try graceful shutdown first
            pkill -f "qemu-system-x86_64.*$vm"
            
            # Wait for graceful shutdown
            local timeout=30
            while is_vm_running "$vm" && [ $timeout -gt 0 ]; do
                sleep 1
                ((timeout--))
            done
            
            if is_vm_running "$vm"; then
                print_warn "VM did not shutdown gracefully, forcing..."
                pkill -9 -f "qemu-system-x86_64.*$vm"
                sleep 2
            fi
            
            print_success "VM $vm stopped"
            log_message "STOP" "Stopped VM: $vm"
        else
            print_info "VM $vm is not running"
        fi
        
        # Cleanup PID file
        rm -f "$VM_DIR/$vm.pid" 2>/dev/null
    fi
}

# Delete VM (improved)
delete_vm() {
    local vm="$1"
    
    if load_config "$vm"; then
        print_warn "This will PERMANENTLY delete VM '$vm' and all associated data!"
        print_warn "This action cannot be undone!"
        
        read -p "$(print_input "Are you absolutely sure? (type 'DELETE' to confirm): ")" confirm
        if [[ "$confirm" != "DELETE" ]]; then
            print_info "Deletion cancelled"
            return 0
        fi
        
        # Stop VM if running
        if is_vm_running "$vm"; then
            print_info "VM is running, stopping first..."
            stop_vm "$vm"
            sleep 2
        fi
        
        # Remove all VM files
        rm -f "$IMG_FILE" "$SEED_FILE" "$CONFIG_DIR/$vm.conf" "$VM_DIR/$vm.pid" 2>/dev/null
        
        # Cleanup logs
        find "$LOG_DIR" -name "$vm-*.log" -delete 2>/dev/null
        
        print_success "ZynexForge VM '$vm' has been completely deleted"
        log_message "DELETE" "Deleted VM: $vm"
    fi
}

# Show VM info
show_vm_info() {
    local vm="$1"
    
    if load_config "$vm"; then
        local status="Stopped"
        if is_vm_running "$vm"; then
            status="Running"
        fi
        
        echo ""
        echo "┌─────────────────────────────────────────────────────┐"
        echo "│            ZYNEXFORGE VM INFORMATION                │"
        echo "├─────────────────────────────────────────────────────┤"
        printf "│ %-20s: %-30s │\n" "VM Name" "$VM_NAME"
        printf "│ %-20s: %-30s │\n" "Status" "$status"
        printf "│ %-20s: %-30s │\n" "OS Type" "$OS_TYPE"
        printf "│ %-20s: %-30s │\n" "Hostname" "$HOSTNAME"
        printf "│ %-20s: %-30s │\n" "Username" "$USERNAME"
        printf "│ %-20s: %-30s │\n" "SSH Port" "$SSH_PORT"
        printf "│ %-20s: %-30s │\n" "Memory" "${MEMORY}MB"
        printf "│ %-20s: %-30s │\n" "vCPUs" "$CPUS"
        printf "│ %-20s: %-30s │\n" "Disk Size" "$DISK_SIZE"
        printf "│ %-20s: %-30s │\n" "GUI Mode" "$GUI_MODE"
        printf "│ %-20s: %-30s │\n" "Created" "$CREATED"
        printf "│ %-20s: %-30s │\n" "Port Forwards" "${PORT_FORWARDS:-None}"
        echo "├─────────────────────────────────────────────────────┤"
        echo "│ CONNECTION INFO                                     │"
        echo "├─────────────────────────────────────────────────────┤"
        echo "│ SSH: ssh -p $SSH_PORT $USERNAME@localhost           │"
        echo "│ Password: $PASSWORD                                 │"
        echo "└─────────────────────────────────────────────────────┘"
        echo ""
        
        read -p "$(print_input "Press Enter to continue...")"
    fi
}

# Edit VM config (improved from script 2)
edit_vm() {
    local vm="$1"
    
    if load_config "$vm"; then
        if is_vm_running "$vm"; then
            print_error "Cannot edit configuration while VM is running"
            return 1
        fi
        
        print_info "Editing VM: $vm"
        
        while true; do
            echo ""
            echo "Edit Options:"
            echo "  1) Hostname (Current: $HOSTNAME)"
            echo "  2) Username (Current: $USERNAME)" 
            echo "  3) Password (Current: ****)"
            echo "  4) SSH Port (Current: $SSH_PORT)"
            echo "  5) Memory (Current: ${MEMORY}MB)"
            echo "  6) vCPUs (Current: $CPUS)"
            echo "  7) GUI Mode (Current: $GUI_MODE)"
            echo "  8) Port Forwards (Current: ${PORT_FORWARDS:-None})"
            echo "  9) Disk Size (Current: $DISK_SIZE)"
            echo "  0) Save and Return"
            echo ""
            
            read -p "$(print_input "Select option to edit: ")" choice
            
            case $choice in
                1)
                    while true; do
                        read -p "$(print_input "New hostname [$HOSTNAME]: ")" new_hostname
                        new_hostname="${new_hostname:-$HOSTNAME}"
                        if validate_input "name" "$new_hostname"; then
                            HOSTNAME="$new_hostname"
                            break
                        fi
                    done
                    ;;
                2)
                    while true; do
                        read -p "$(print_input "New username [$USERNAME]: ")" new_username
                        new_username="${new_username:-$USERNAME}"
                        if validate_input "username" "$new_username"; then
                            USERNAME="$new_username"
                            break
                        fi
                    done
                    ;;
                3)
                    while true; do
                        read -s -p "$(print_input "New password (press Enter to keep current): ")" new_password
                        echo
                        if [ -n "$new_password" ]; then
                            PASSWORD="$new_password"
                            break
                        else
                            break
                        fi
                    done
                    ;;
                4)
                    while true; do
                        read -p "$(print_input "New SSH port [$SSH_PORT]: ")" new_port
                        new_port="${new_port:-$SSH_PORT}"
                        if validate_input "port" "$new_port"; then
                            if [ "$new_port" != "$SSH_PORT" ] && ! check_port_free "$new_port"; then
                                print_error "Port $new_port is already in use"
                            else
                                SSH_PORT="$new_port"
                                break
                            fi
                        fi
                    done
                    ;;
                5)
                    while true; do
                        read -p "$(print_input "New memory in MB [$MEMORY]: ")" new_mem
                        new_mem="${new_mem:-$MEMORY}"
                        if validate_input "number" "$new_mem"; then
                            MEMORY="$new_mem"
                            break
                        fi
                    done
                    ;;
                6)
                    while true; do
                        read -p "$(print_input "New vCPU count [$CPUS]: ")" new_cpus
                        new_cpus="${new_cpus:-$CPUS}"
                        if validate_input "number" "$new_cpus"; then
                            CPUS="$new_cpus"
                            break
                        fi
                    done
                    ;;
                7)
                    while true; do
                        read -p "$(print_input "Enable GUI? (y/N) [$GUI_MODE]: ")" gui_choice
                        gui_choice="${gui_choice:-}"
                        if [[ "$gui_choice" =~ ^[Yy]$ ]]; then
                            GUI_MODE=true
                            break
                        elif [[ "$gui_choice" =~ ^[Nn]$ ]]; then
                            GUI_MODE=false
                            break
                        elif [ -z "$gui_choice" ]; then
                            break
                        else
                            print_error "Please answer y or n"
                        fi
                    done
                    ;;
                8)
                    read -p "$(print_input "New port forwards [$PORT_FORWARDS]: ")" new_forwards
                    PORT_FORWARDS="${new_forwards:-$PORT_FORWARDS}"
                    ;;
                9)
                    while true; do
                        read -p "$(print_input "New disk size [$DISK_SIZE]: ")" new_disk_size
                        new_disk_size="${new_disk_size:-$DISK_SIZE}"
                        if validate_input "size" "$new_disk_size"; then
                            DISK_SIZE="$new_disk_size"
                            break
                        fi
                    done
                    ;;
                0)
                    # Update cloud-init
                    print_info "Updating cloud-init configuration..."
                    setup_vm
                    save_config
                    print_success "Configuration updated successfully"
                    return 0
                    ;;
                *)
                    print_error "Invalid option"
                    ;;
            esac
        done
    fi
}

# Resize disk (improved from script 2)
resize_disk() {
    local vm="$1"
    
    if load_config "$vm"; then
        if is_vm_running "$vm"; then
            print_error "Cannot resize disk while VM is running"
            return 1
        fi
        
        print_info "Current disk size: $DISK_SIZE"
        
        while true; do
            read -p "$(print_input "Enter new disk size (e.g., 100G): ")" new_disk_size
            if validate_input "size" "$new_disk_size"; then
                if [[ "$new_disk_size" == "$DISK_SIZE" ]]; then
                    print_info "Disk size unchanged"
                    return 0
                fi
                
                # Check if shrinking (warn)
                local current_num=${DISK_SIZE%[GgMm]}
                local new_num=${new_disk_size%[GgMm]}
                local current_unit=${DISK_SIZE: -1}
                local new_unit=${new_disk_size: -1}
                
                # Convert to MB for comparison
                if [[ "${current_unit^^}" == "G" ]]; then
                    current_num=$((current_num * 1024))
                fi
                if [[ "${new_unit^^}" == "G" ]]; then
                    new_num=$((new_num * 1024))
                fi
                
                if [[ $new_num -lt $current_num ]]; then
                    print_warn "WARNING: Shrinking disk may cause DATA LOSS!"
                    read -p "$(print_input "Type 'SHRINK' to confirm: ")" confirm
                    if [[ "$confirm" != "SHRINK" ]]; then
                        print_info "Disk resize cancelled"
                        return 0
                    fi
                fi
                
                # Resize disk
                print_info "Resizing disk to $new_disk_size..."
                if qemu-img resize -f qcow2 "$IMG_FILE" "$new_disk_size"; then
                    DISK_SIZE="$new_disk_size"
                    save_config
                    print_success "Disk resized successfully to $new_disk_size"
                    log_message "RESIZE" "Resized disk for $vm to $new_disk_size"
                else
                    print_error "Failed to resize disk"
                    return 1
                fi
                break
            fi
            print_error "Invalid size format (e.g., 100G, 500G)"
        done
    fi
}

# Show VM performance metrics (from script 2)
show_vm_performance() {
    local vm="$1"
    
    if load_config "$vm"; then
        if is_vm_running "$vm"; then
            print_info "Performance metrics for VM: $vm"
            echo "══════════════════════════════════════════════════"
            
            # Get QEMU process ID
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$vm")
            if [[ -n "$qemu_pid" ]]; then
                # Show process stats
                echo "QEMU Process Stats:"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers
                echo
                
                # Show memory usage
                echo "Memory Usage:"
                free -h
                echo
                
                # Show disk usage
                echo "Disk Usage:"
                df -h "$IMG_FILE" 2>/dev/null || du -h "$IMG_FILE"
            else
                print_error "Could not find QEMU process for VM $vm"
            fi
        else
            print_info "VM $vm is not running"
            echo "Configuration:"
            echo "  Memory: $MEMORY MB"
            echo "  CPUs: $CPUS"
            echo "  Disk: $DISK_SIZE"
        fi
        echo "══════════════════════════════════════════════════"
        read -p "$(print_input "Press Enter to continue...")"
    fi
}

# Main menu (improved)
main_menu() {
    while true; do
        display_banner
        
        # List VMs
        local vms=($(list_vms))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            print_info "Managed VMs ($vm_count):"
            echo "┌────┬──────────────────────────────┬──────────────┐"
            echo "│ #  │ VM Name                      │ Status       │"
            echo "├────┼──────────────────────────────┼──────────────┤"
            
            for i in "${!vms[@]}"; do
                local vm="${vms[$i]}"
                local status="Stopped"
                local color="31"
                
                if is_vm_running "$vm"; then
                    status="Running"
                    color="32"
                fi
                
                printf "│ \033[1;33m%2d\033[0m │ \033[1;37m%-28s\033[0m │ \033[1;%sm%-12s\033[0m │\n" \
                       "$((i+1))" "$vm" "$color" "$status"
            done
            echo "└────┴──────────────────────────────┴──────────────┘"
            echo ""
        else
            print_info "No VMs found. Create your first VM to get started."
            echo ""
        fi
        
        # Menu options
        echo "ZynexForge VM Engine v$SCRIPT_VERSION - Main Menu"
        echo "══════════════════════════════════════════════════"
        echo "  1) Create new ZynexForge VM"
        
        if [ $vm_count -gt 0 ]; then
            echo "  2) Start VM"
            echo "  3) Stop VM"
            echo "  4) Show VM information"
            echo "  5) Edit VM configuration"
            echo "  6) Delete VM"
            echo "  7) Resize VM disk"
            echo "  8) Show VM performance"
        fi
        
        echo "  0) Exit"
        echo ""
        
        read -p "$(print_input "Enter your choice: ")" choice
        
        case $choice in
            1)
                create_vm
                ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "Enter VM number to start: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        # Start VM in foreground (will block until VM exits)
                        start_vm "${vms[$((vm_num-1))]}"
                        # After VM exits, show message and continue
                        echo ""
                        print_info "Returning to main menu..."
                        sleep 2
                    else
                        print_error "Invalid selection"
                    fi
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "Enter VM number to stop: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        stop_vm "${vms[$((vm_num-1))]}"
                    else
                        print_error "Invalid selection"
                    fi
                fi
                ;;
            4)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "Enter VM number for info: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_info "${vms[$((vm_num-1))]}"
                    else
                        print_error "Invalid selection"
                    fi
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "Enter VM number to edit: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        edit_vm "${vms[$((vm_num-1))]}"
                    else
                        print_error "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_error "Invalid selection"
                    fi
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "Enter VM number to resize disk: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        resize_disk "${vms[$((vm_num-1))]}"
                    else
                        print_error "Invalid selection"
                    fi
                fi
                ;;
            8)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "Enter VM number to show performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_error "Invalid selection"
                    fi
                fi
                ;;
            0)
                print_info "Thank you for using ZynexForge VM Engine!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        
        echo ""
        read -p "$(print_input "Press Enter to continue...")"
    done
}

# Cleanup
cleanup() {
    rm -f /tmp/user-data /tmp/meta-data 2>/dev/null
}

# Main
trap cleanup EXIT INT TERM
init_dirs
check_deps
check_epyc
main_menu
