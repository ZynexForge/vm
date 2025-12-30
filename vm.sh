#!/bin/bash
set -euo pipefail

# ================================================
# ZYNEXFORGE VM ENGINE - Advanced Virtualization Manager
# Version: 6.0
# Author: FaaizJohar
# Optimized for AMD EPYC with QEMU/KVM
# ================================================

# Global configuration
readonly VM_DIR="${VM_DIR:-$HOME/zynexforge-vms}"
readonly CONFIG_DIR="$VM_DIR/configs"
readonly LOG_DIR="$VM_DIR/logs"
readonly SCRIPT_VERSION="6.0"
readonly BRAND_PREFIX="ZynexForge-"

# EPYC CPU optimization flags
readonly EPYC_CPU_FLAGS="host,migratable=no,host-cache-info=on,topoext=on,pmu=on,x2apic=on,acpi=on,ssbd=required,pdpe1gb=on"
readonly EPYC_CPU_TOPOLOGY="sockets=1,dies=1,cores=8,threads=2"

# Performance tuning defaults
readonly DISK_CACHE="directsync"
readonly NET_TYPE="virtio-net-pci"
readonly NET_QUEUES="4"

# Supported OS images
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04 LTS"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04 LTS"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11 Bullseye"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12 Bookworm"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Kali Linux Rolling"]="kali|rolling|https://cloud.kali.org/kali/images/kali-2024.4/kali-linux-2024.4-genericcloud-amd64.qcow2|kali-rolling|kali|kali"
    ["Arch Linux Latest"]="arch|latest|https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2|archlinux|arch|arch"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
)

# ================================================
# INITIALIZATION FUNCTIONS
# ================================================

init_directories() {
    mkdir -p "$VM_DIR" "$CONFIG_DIR" "$LOG_DIR" "$VM_DIR/isos" "$VM_DIR/disks"
    chmod 755 "$VM_DIR" "$CONFIG_DIR" "$LOG_DIR"
}

display_banner() {
    clear
    cat << "EOF"
__________                             ___________                         
\____    /__>.__. ____   ____ ___  ___ \_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /  |    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    <   |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \  \___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/      \/             /_____/      \/ 

        ZynexForge VM Engine v6.0 | AMD EPYC Optimized | Powered by HopingBoyz
===============================================================================
EOF
    echo ""
}

# Color output functions
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO")    echo -e "\033[1;34m[INFO]\033[0m $message" ;;
        "WARN")    echo -e "\033[1;33m[WARN]\033[0m $message" ;;
        "ERROR")   echo -e "\033[1;31m[ERROR]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[SUCCESS]\033[0m $message" ;;
        "INPUT")   echo -e "\033[1;36m[INPUT]\033[0m $message" ;;
        "DEBUG")   echo -e "\033[1;35m[DEBUG]\033[0m $message" ;;
        *)         echo "[$type] $message" ;;
    esac
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$LOG_DIR"
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/zynexforge.log"
}

# ================================================
# DEPENDENCY & SYSTEM CHECKS
# ================================================

check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "mkpasswd")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "Install with: sudo apt install qemu-system cloud-image-utils wget whois"
        exit 1
    fi
}

check_epyc_optimizations() {
    # Check for AMD EPYC CPU
    if grep -qi "AMD EPYC" /proc/cpuinfo; then
        print_status "INFO" "AMD EPYC processor detected - applying optimizations"
    else
        print_status "WARN" "Non-EPYC processor detected. Some optimizations may be limited."
    fi
    
    # Check for KVM support
    if [ ! -e /dev/kvm ]; then
        print_status "WARN" "KVM not available. Ensure virtualization is enabled in BIOS"
    fi
}

# ================================================
# VALIDATION FUNCTIONS
# ================================================

validate_input() {
    local type=$1
    local value=$2
    
    case $type in
        "number")
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ]; then
                print_status "ERROR" "Must be a positive number"
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
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1024 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "Must be a valid port number (1024-65535)"
                return 1
            fi
            ;;
        "name")
            if ! [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] || [ ${#value} -gt 32 ]; then
                print_status "ERROR" "VM name can only contain letters, numbers, hyphens, underscores (max 32 chars)"
                return 1
            fi
            ;;
        "username")
            if ! [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]] || [ ${#value} -gt 32 ]; then
                print_status "ERROR" "Username must start with a letter or underscore, contain only lowercase letters, numbers, hyphens, underscores (max 32 chars)"
                return 1
            fi
            ;;
    esac
    return 0
}

check_port_available() {
    local port=$1
    if ss -tln 2>/dev/null | grep -q ":$port "; then
        print_status "ERROR" "Port $port is already in use"
        return 1
    fi
    return 0
}

# ================================================
# VM CONFIGURATION MANAGEMENT
# ================================================

get_vm_list() {
    find "$CONFIG_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

load_vm_config() {
    local vm_name=$1
    local config_file="$CONFIG_DIR/$vm_name.conf"
    
    if [[ -f "$config_file" ]]; then
        # Clear previous variables
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        unset ENABLE_HUGEPAGES ENABLE_NUMA VIRTIO_OPTIONS
        
        source "$config_file"
        return 0
    else
        print_status "ERROR" "Configuration for VM '$vm_name' not found"
        return 1
    fi
}

save_vm_config() {
    local config_file="$CONFIG_DIR/$VM_NAME.conf"
    
    cat > "$config_file" <<EOF
# ZynexForge VM Engine Configuration
# Generated: $(date)
# Engine Version: $SCRIPT_VERSION

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
ENABLE_HUGEPAGES="$ENABLE_HUGEPAGES"
ENABLE_NUMA="$ENABLE_NUMA"
VIRTIO_OPTIONS="$VIRTIO_OPTIONS"
EOF
    
    chmod 600 "$config_file"
    print_status "SUCCESS" "Configuration saved to $config_file"
    log_message "CONFIG" "Saved config for VM: $VM_NAME"
}

# ================================================
# VM CREATION & IMAGE MANAGEMENT
# ================================================

create_new_vm() {
    display_banner
    print_status "INFO" "Creating new ZynexForge VM"
    
    # OS Selection
    print_status "INFO" "Select an OS distribution:"
    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        printf "  %2d) %s\n" "$i" "$os"
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

    # VM Name with branding
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (default: ${BRAND_PREFIX}${DEFAULT_HOSTNAME}): ")" input_name
        VM_NAME="${input_name:-${BRAND_PREFIX}${DEFAULT_HOSTNAME}}"
        if validate_input "name" "$VM_NAME"; then
            if [[ -f "$CONFIG_DIR/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM with name '$VM_NAME' already exists"
            else
                break
            fi
        fi
    done

    # Hostname
    while true; do
        read -p "$(print_status "INPUT" "Enter hostname (default: $VM_NAME): ")" HOSTNAME
        HOSTNAME="${HOSTNAME:-$VM_NAME}"
        if validate_input "name" "$HOSTNAME"; then
            break
        fi
    done

    # Username
    while true; do
        read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    # Password
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

    # Resource allocation with validation
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
            if [ "$MEMORY" -lt 512 ]; then
                print_status "WARN" "Minimum recommended memory is 512MB"
            fi
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Number of vCPUs (default: 4): ")" CPUS
        CPUS="${CPUS:-4}"
        if validate_input "number" "$CPUS"; then
            local core_count=$(nproc 2>/dev/null || echo 4)
            if [ "$CPUS" -gt "$core_count" ]; then
                print_status "WARN" "Warning: Requested $CPUS vCPUs but host only has $core_count cores"
            fi
            break
        fi
    done

    # SSH Port
    while true; do
        read -p "$(print_status "INPUT" "SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT" && check_port_available "$SSH_PORT"; then
            break
        fi
    done

    # GUI Mode
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

    # Performance optimizations
    while true; do
        read -p "$(print_status "INPUT" "Enable performance optimizations? (y/n, default: y): ")" perf_input
        perf_input="${perf_input:-y}"
        if [[ "$perf_input" =~ ^[Yy]$ ]]; then
            ENABLE_HUGEPAGES=true
            ENABLE_NUMA=true
            break
        elif [[ "$perf_input" =~ ^[Nn]$ ]]; then
            ENABLE_HUGEPAGES=false
            ENABLE_NUMA=false
            break
        else
            print_status "ERROR" "Please answer y or n"
        fi
    done

    # Additional port forwards
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80,8443:443, press Enter for none): ")" PORT_FORWARDS

    # Set file paths
    IMG_FILE="$VM_DIR/disks/$VM_NAME.qcow2"
    SEED_FILE="$VM_DIR/isos/$VM_NAME-seed.iso"
    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Set optimization flags
    VIRTIO_OPTIONS="iothread=on,discard=unmap"
    
    # Setup VM image
    setup_vm_image
    
    # Save configuration
    save_vm_config
    
    print_status "SUCCESS" "ZynexForge VM '$VM_NAME' created successfully!"
    print_status "INFO" "Configuration: $CPUS vCPUs, ${MEMORY}MB RAM, $DISK_SIZE disk"
    print_status "INFO" "To start: Select VM from main menu"
}

setup_vm_image() {
    print_status "INFO" "Preparing VM image with AMD EPYC optimizations..."
    
    # Download image if not exists
    if [[ ! -f "$IMG_FILE" ]]; then
        print_status "INFO" "Downloading OS image from $IMG_URL..."
        if ! wget --progress=bar:force --tries=3 --timeout=30 "$IMG_URL" -O "$IMG_FILE.tmp" 2>/dev/null; then
            print_status "ERROR" "Failed to download image from $IMG_URL"
            exit 1
        fi
        mv "$IMG_FILE.tmp" "$IMG_FILE"
    fi
    
    # Resize disk using qcow2 with fast allocation
    print_status "INFO" "Configuring disk to $DISK_SIZE..."
    if ! qemu-img resize -f qcow2 "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
        print_status "WARN" "Creating new disk image..."
        qemu-img create -f qcow2 -o preallocation=metadata "$IMG_FILE" "$DISK_SIZE"
    fi
    
    # Generate password hash using mkpasswd (from whois package)
    local password_hash
    if command -v mkpasswd &> /dev/null; then
        password_hash=$(mkpasswd -m sha-512 "$PASSWORD" | tr -d '\n')
    else
        # Fallback to simple hash if mkpasswd not available
        password_hash=$(echo -n "$PASSWORD" | openssl passwd -6 -stdin 2>/dev/null | tr -d '\n' || echo "")
    fi
    
    if [ -z "$password_hash" ]; then
        print_status "WARN" "Could not generate password hash, using plain text (install 'whois' for secure hashing)"
        password_hash="$PASSWORD"
    fi
    
    # Create cloud-init configuration with ZynexForge branding
    cat > /tmp/user-data <<EOF
#cloud-config
# ZynexForge VM Engine - Cloud Init Configuration
hostname: $HOSTNAME
manage_etc_hosts: true
ssh_pwauth: true
disable_root: false
package_update: true
package_upgrade: true
timezone: UTC
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $password_hash
    ssh_authorized_keys: []
    groups: [sudo, docker, admin]
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
write_files:
  - path: /etc/motd
    content: |
      Welcome to ZynexForge VM Engine
      Hostname: $HOSTNAME
      Created: $CREATED
      OS: $OS_TYPE $CODENAME
      Engine Version: $SCRIPT_VERSION
      
      This VM is managed by ZynexForge VM Engine
      For support, check your host system documentation.
    owner: root:root
    permissions: '0644'
packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - cloud-init clean --logs
final_message: |
  ZynexForge VM Setup Complete!
  Hostname: $HOSTNAME
  Username: $USERNAME
  SSH Port: $SSH_PORT
  Connect: ssh -p $SSH_PORT $USERNAME@localhost
EOF

    cat > /tmp/meta-data <<EOF
instance-id: zynexforge-$VM_NAME
local-hostname: $HOSTNAME
EOF

    # Create seed image
    print_status "INFO" "Creating cloud-init seed image..."
    if ! cloud-localds "$SEED_FILE" /tmp/user-data /tmp/meta-data; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
    
    # Cleanup temp files
    rm -f /tmp/user-data /tmp/meta-data
    
    print_status "SUCCESS" "VM image preparation complete"
    log_message "CREATE" "Created VM: $VM_NAME with $OS_TYPE"
}

# ================================================
# VM OPERATIONS
# ================================================

start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting ZynexForge VM: $vm_name"
        
        # Check if already running
        if is_vm_running "$vm_name"; then
            print_status "WARN" "VM '$vm_name' is already running"
            return 0
        fi
        
        # Verify files exist
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "VM image file not found: $IMG_FILE"
            return 1
        fi
        
        if [[ ! -f "$SEED_FILE" ]]; then
            print_status "WARN" "Seed file not found, recreating..."
            setup_vm_image
        fi
        
        print_status "INFO" "SSH Access: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Password: $PASSWORD"
        
        # Build QEMU command with EPYC optimizations
        local qemu_cmd=(
            qemu-system-x86_64
            -name "zynexforge-$VM_NAME"
            -enable-kvm
            -machine "q35,accel=kvm"
            -cpu "$EPYC_CPU_FLAGS"
            -smp "$CPUS,$EPYC_CPU_TOPOLOGY"
            -m "$MEMORY"
            -rtc base=utc,clock=host
            -serial mon:stdio
            -nodefaults
            -sandbox on
        )
        
        # Add hugepages if enabled
        if [[ "$ENABLE_HUGEPAGES" == true ]] && [ -d /sys/kernel/mm/hugepages ]; then
            qemu_cmd+=(-mem-path /dev/hugepages)
        fi
        
        # Storage configuration
        qemu_cmd+=(
            -drive "file=$IMG_FILE,if=virtio,format=qcow2,cache=$DISK_CACHE"
            -drive "file=$SEED_FILE,if=virtio,format=raw,readonly=on"
        )
        
        # Network configuration
        qemu_cmd+=(
            -netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22"
            -device "virtio-net-pci,netdev=net0,mac=52:54:00:$(printf '%02x' $((RANDOM%256))):$(printf '%02x' $((RANDOM%256))):$(printf '%02x' $((RANDOM%256)))"
        )
        
        # Add additional port forwards
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            local net_id=1
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                if [[ -n "$host_port" && -n "$guest_port" ]]; then
                    qemu_cmd+=(
                        -netdev "user,id=net$net_id,hostfwd=tcp::$host_port-:$guest_port"
                        -device "virtio-net-pci,netdev=net$net_id"
                    )
                    ((net_id++))
                fi
            done
        fi
        
        # GUI or console mode
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(
                -vga virtio
                -display gtk
                -usb
                -device usb-tablet
            )
        else
            qemu_cmd+=(
                -nographic
                -vga none
            )
        fi
        
        # Additional devices
        qemu_cmd+=(
            -device virtio-balloon-pci
            -object "rng-random,id=rng0,filename=/dev/urandom"
            -device virtio-rng-pci,rng=rng0
        )
        
        # Start VM
        local log_file="$LOG_DIR/$VM_NAME-$(date '+%Y%m%d-%H%M%S').log"
        print_status "INFO" "Starting QEMU with EPYC optimizations..."
        print_status "DEBUG" "Log file: $log_file"
        
        # Execute QEMU
        if [[ "$GUI_MODE" == true ]]; then
            "${qemu_cmd[@]}" 2>&1 | tee "$log_file" &
        else
            "${qemu_cmd[@]}" 2>&1 | tee "$log_file" > /dev/null &
        fi
        
        local qemu_pid=$!
        echo "$qemu_pid" > "$VM_DIR/$VM_NAME.pid"
        
        # Wait for VM to boot
        print_status "INFO" "VM starting (PID: $qemu_pid)..."
        sleep 3
        
        if is_vm_running "$vm_name"; then
            print_status "SUCCESS" "VM '$vm_name' started successfully"
            log_message "START" "Started VM: $vm_name (PID: $qemu_pid)"
        else
            print_status "ERROR" "Failed to start VM"
            return 1
        fi
    fi
}

stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM: $vm_name"
            
            # Try graceful shutdown
            if [[ -f "$VM_DIR/$vm_name.pid" ]]; then
                local pid=$(cat "$VM_DIR/$vm_name.pid")
                kill -SIGTERM "$pid" 2>/dev/null
                
                # Wait for graceful shutdown
                local timeout=30
                while is_vm_running "$vm_name" && [ $timeout -gt 0 ]; do
                    sleep 1
                    ((timeout--))
                done
                
                if is_vm_running "$vm_name"; then
                    print_status "WARN" "VM did not shutdown gracefully, forcing..."
                    kill -SIGKILL "$pid" 2>/dev/null
                fi
            else
                # Fallback to pkill
                pkill -f "qemu-system-x86_64.*$IMG_FILE"
                sleep 2
                if is_vm_running "$vm_name"; then
                    pkill -9 -f "qemu-system-x86_64.*$IMG_FILE"
                fi
            fi
            
            # Cleanup PID file
            rm -f "$VM_DIR/$vm_name.pid"
            
            print_status "SUCCESS" "VM $vm_name stopped"
            log_message "STOP" "Stopped VM: $vm_name"
        else
            print_status "INFO" "VM $vm_name is not running"
        fi
    fi
}

delete_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "WARN" "This will PERMANENTLY delete VM '$vm_name' and all associated data!"
        print_status "WARN" "This action cannot be undone!"
        
        read -p "$(print_status "INPUT" "Are you absolutely sure? (type 'DELETE' to confirm): ")" confirmation
        if [[ "$confirmation" != "DELETE" ]]; then
            print_status "INFO" "Deletion cancelled"
            return 0
        fi
        
        # Stop VM if running
        if is_vm_running "$vm_name"; then
            print_status "INFO" "VM is running, stopping first..."
            stop_vm "$vm_name"
            sleep 2
        fi
        
        # Remove all VM files
        rm -f "$IMG_FILE" "$SEED_FILE" "$CONFIG_DIR/$vm_name.conf" "$VM_DIR/$vm_name.pid" 2>/dev/null
        
        # Cleanup logs
        find "$LOG_DIR" -name "$vm_name-*.log" -delete 2>/dev/null
        
        print_status "SUCCESS" "ZynexForge VM '$vm_name' has been completely deleted"
        log_message "DELETE" "Deleted VM: $vm_name"
    fi
}

# ================================================
# VM STATUS & INFORMATION
# ================================================

is_vm_running() {
    local vm_name=$1
    if [[ -f "$VM_DIR/$vm_name.pid" ]]; then
        local pid=$(cat "$VM_DIR/$vm_name.pid" 2>/dev/null)
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        fi
        rm -f "$VM_DIR/$vm_name.pid"
    fi
    return 1
}

show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo ""
        echo "┌─────────────────────────────────────────────────────┐"
        echo "│            ZYNEXFORGE VM INFORMATION                │"
        echo "├─────────────────────────────────────────────────────┤"
        printf "│ %-20s: %-30s │\n" "VM Name" "$VM_NAME"
        printf "│ %-20s: %-30s │\n" "Status" "$(is_vm_running "$vm_name" && echo "Running" || echo "Stopped")"
        printf "│ %-20s: %-30s │\n" "OS Type" "$OS_TYPE"
        printf "│ %-20s: %-30s │\n" "Hostname" "$HOSTNAME"
        printf "│ %-20s: %-30s │\n" "Username" "$USERNAME"
        printf "│ %-20s: %-30s │\n" "SSH Port" "$SSH_PORT"
        printf "│ %-20s: %-30s │\n" "Memory" "${MEMORY}MB"
        printf "│ %-20s: %-30s │\n" "vCPUs" "$CPUS"
        printf "│ %-20s: %-30s │\n" "Disk Size" "$DISK_SIZE"
        printf "│ %-20s: %-30s │\n" "GUI Mode" "$GUI_MODE"
        printf "│ %-20s: %-30s │\n" "HugePages" "$ENABLE_HUGEPAGES"
        printf "│ %-20s: %-30s │\n" "NUMA" "$ENABLE_NUMA"
        printf "│ %-20s: %-30s │\n" "Created" "$CREATED"
        printf "│ %-20s: %-30s │\n" "Port Forwards" "${PORT_FORWARDS:-None}"
        echo "├─────────────────────────────────────────────────────┤"
        echo "│ CONNECTION INFO                                     │"
        echo "├─────────────────────────────────────────────────────┤"
        echo "│ SSH: ssh -p $SSH_PORT $USERNAME@localhost           │"
        echo "│ Password: $PASSWORD                                 │"
        echo "└─────────────────────────────────────────────────────┘"
        echo ""
        
        if is_vm_running "$vm_name"; then
            local pid=$(cat "$VM_DIR/$vm_name.pid" 2>/dev/null)
            if [[ -n "$pid" ]]; then
                echo "Process Information:"
                ps -p "$pid" -o pid,%cpu,%mem,vsz,rss,etime,cmd --no-headers
                echo ""
            fi
        fi
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# ================================================
# VM MANAGEMENT FUNCTIONS
# ================================================

edit_vm_config() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "ERROR" "Cannot edit configuration while VM is running"
            return 1
        fi
        
        print_status "INFO" "Editing VM: $vm_name"
        
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
            echo "  0) Save and Return"
            echo ""
            
            read -p "$(print_status "INPUT" "Select option to edit: ")" edit_choice
            
            case $edit_choice in
                1)
                    while true; do
                        read -p "$(print_status "INPUT" "New hostname [$HOSTNAME]: ")" new_hostname
                        new_hostname="${new_hostname:-$HOSTNAME}"
                        if validate_input "name" "$new_hostname"; then
                            HOSTNAME="$new_hostname"
                            break
                        fi
                    done
                    ;;
                2)
                    while true; do
                        read -p "$(print_status "INPUT" "New username [$USERNAME]: ")" new_username
                        new_username="${new_username:-$USERNAME}"
                        if validate_input "username" "$new_username"; then
                            USERNAME="$new_username"
                            break
                        fi
                    done
                    ;;
                3)
                    while true; do
                        read -s -p "$(print_status "INPUT" "New password (press Enter to keep current): ")" new_password
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
                        read -p "$(print_status "INPUT" "New SSH port [$SSH_PORT]: ")" new_port
                        new_port="${new_port:-$SSH_PORT}"
                        if validate_input "port" "$new_port" && check_port_available "$new_port"; then
                            SSH_PORT="$new_port"
                            break
                        fi
                    done
                    ;;
                5)
                    while true; do
                        read -p "$(print_status "INPUT" "New memory in MB [$MEMORY]: ")" new_mem
                        new_mem="${new_mem:-$MEMORY}"
                        if validate_input "number" "$new_mem"; then
                            MEMORY="$new_mem"
                            break
                        fi
                    done
                    ;;
                6)
                    while true; do
                        read -p "$(print_status "INPUT" "New vCPU count [$CPUS]: ")" new_cpus
                        new_cpus="${new_cpus:-$CPUS}"
                        if validate_input "number" "$new_cpus"; then
                            CPUS="$new_cpus"
                            break
                        fi
                    done
                    ;;
                7)
                    while true; do
                        read -p "$(print_status "INPUT" "Enable GUI? (y/n) [$GUI_MODE]: ")" gui_input
                        gui_input="${gui_input:-}"
                        if [[ "$gui_input" =~ ^[Yy]$ ]]; then
                            GUI_MODE=true
                            break
                        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
                            GUI_MODE=false
                            break
                        elif [ -z "$gui_input" ]; then
                            break
                        fi
                    done
                    ;;
                8)
                    read -p "$(print_status "INPUT" "New port forwards [$PORT_FORWARDS]: ")" new_forwards
                    PORT_FORWARDS="${new_forwards:-$PORT_FORWARDS}"
                    ;;
                0)
                    # Recreate seed image if user/password/hostname changed
                    print_status "INFO" "Updating cloud-init configuration..."
                    setup_vm_image
                    save_vm_config
                    print_status "SUCCESS" "Configuration updated successfully"
                    return 0
                    ;;
                *)
                    print_status "ERROR" "Invalid option"
                    ;;
            esac
        done
    fi
}

resize_vm_disk() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "ERROR" "Cannot resize disk while VM is running"
            return 1
        fi
        
        print_status "INFO" "Current disk size: $DISK_SIZE"
        
        while true; do
            read -p "$(print_status "INPUT" "Enter new disk size (e.g., 100G): ")" new_disk_size
            if validate_input "size" "$new_disk_size"; then
                if [[ "$new_disk_size" == "$DISK_SIZE" ]]; then
                    print_status "INFO" "Disk size unchanged"
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
                    print_status "WARN" "WARNING: Shrinking disk may cause DATA LOSS!"
                    read -p "$(print_status "INPUT" "Type 'SHRINK' to confirm: ")" confirm
                    if [[ "$confirm" != "SHRINK" ]]; then
                        print_status "INFO" "Disk resize cancelled"
                        return 0
                    fi
                fi
                
                # Resize disk
                print_status "INFO" "Resizing disk to $new_disk_size..."
                if qemu-img resize -f qcow2 "$IMG_FILE" "$new_disk_size"; then
                    DISK_SIZE="$new_disk_size"
                    save_vm_config
                    print_status "SUCCESS" "Disk resized successfully to $new_disk_size"
                    log_message "RESIZE" "Resized disk for $vm_name to $new_disk_size"
                else
                    print_status "ERROR" "Failed to resize disk"
                    return 1
                fi
                break
            fi
        done
    fi
}

show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo ""
        echo "┌─────────────────────────────────────────────────────┐"
        echo "│           ZYNEXFORGE VM PERFORMANCE                 │"
        echo "├─────────────────────────────────────────────────────┤"
        
        if is_vm_running "$vm_name"; then
            local pid=$(cat "$VM_DIR/$vm_name.pid" 2>/dev/null)
            if [[ -n "$pid" ]]; then
                echo "│ QEMU Process Statistics:                          │"
                echo "├─────────────────────────────────────────────────────┤"
                ps -p "$pid" -o pid,%cpu,%mem,sz,rss,vsz,etime,cmd --no-headers | while read line; do
                    printf "│ %-55s │\n" "$line"
                done
                echo "├─────────────────────────────────────────────────────┤"
                
                # Show system resources
                echo "│ System Resources:                                  │"
                echo "├─────────────────────────────────────────────────────┤"
                free -h | head -2 | while read line; do
                    printf "│ %-55s │\n" "$line"
                done
            fi
        else
            echo "│ VM is not running                                    │"
            echo "├─────────────────────────────────────────────────────┤"
            echo "│ Configuration:                                      │"
            printf "│ %-20s: %-30s │\n" "Memory" "${MEMORY}MB"
            printf "│ %-20s: %-30s │\n" "vCPUs" "$CPUS"
            printf "│ %-20s: %-30s │\n" "Disk" "$DISK_SIZE"
            printf "│ %-20s: %-30s │\n" "HugePages" "$ENABLE_HUGEPAGES"
            printf "│ %-20s: %-30s │\n" "NUMA" "$ENABLE_NUMA"
        fi
        echo "└─────────────────────────────────────────────────────┘"
        echo ""
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# ================================================
# MAIN MENU
# ================================================

main_menu() {
    while true; do
        display_banner
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        # Show VM list if any exist
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Managed VMs ($vm_count):"
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
            print_status "INFO" "No VMs found. Create your first VM to get started."
            echo ""
        fi
        
        # Main menu options
        echo "ZynexForge VM Engine v$SCRIPT_VERSION - Main Menu"
        echo "─────────────────────────────────────────────────────"
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
                    read -p "$(print_status "INPUT" "Enter VM number for info: ")" vm_num
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
                    if [[ "$vm_name" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
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
                    read -p "$(print_status "INPUT" "Enter VM number for performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            0)
                print_status "INFO" "Thank you for using ZynexForge VM Engine!"
                exit 0
                ;;
            *)
                print_status "ERROR" "Invalid option"
                ;;
        esac
        
        echo ""
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

# ================================================
# SCRIPT ENTRY POINT
# ================================================

# Cleanup function
cleanup() {
    rm -f /tmp/user-data /tmp/meta-data 2>/dev/null
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Main execution
init_directories
check_dependencies
check_epyc_optimizations
main_menu
