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
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing: ${missing[*]}"
        print_info "Install: sudo apt install qemu-system cloud-image-utils wget"
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

# Validation functions
validate_number() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ]
}

validate_size() {
    [[ "$1" =~ ^[0-9]+[GgMm]$ ]]
}

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1024 ] && [ "$1" -le 65535 ]
}

validate_name() {
    [[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]] && [ ${#1} -le 32 ]
}

validate_username() {
    [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]] && [ ${#1} -le 32 ]
}

check_port_free() {
    ! ss -tln 2>/dev/null | grep -q ":$1 "
}

# OS Options with fallback URLs
declare -A OS_IMAGES=(
    ["ubuntu22"]="Ubuntu 22.04|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu|ubuntu"
    ["ubuntu24"]="Ubuntu 24.04|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu|ubuntu"
    ["debian11"]="Debian 11|bullseye|https://cloud.debian.org/images/cloud/bullseye/20240210-1620/debian-11-generic-amd64-20240210-1620.qcow2|debian|debian"
    ["debian12"]="Debian 12|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian|debian"
    ["kali"]="Kali Linux|rolling|https://cloud.kali.org/kali/images/kali-2024.4/kali-linux-2024.4-genericcloud-amd64.qcow2|kali|kali"
    ["arch"]="Arch Linux|latest|https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2|arch|arch"
    ["fedora40"]="Fedora 40|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora|fedora"
    ["centos9"]="CentOS Stream 9|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos|centos"
)

# Fallback URLs if primary fails
declare -A FALLBACK_URLS=(
    ["debian11"]="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2"
    ["debian12"]="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
)

# Download image with retry
download_image() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        print_info "Download attempt $((retry_count + 1))/$max_retries..."
        
        if wget --progress=bar:force --timeout=60 --tries=3 "$url" -O "$output.tmp" 2>&1 | tee /tmp/wget.log; then
            mv "$output.tmp" "$output"
            print_success "Download completed"
            return 0
        fi
        
        ((retry_count++))
        
        if [ $retry_count -lt $max_retries ]; then
            print_warn "Download failed, retrying in 5 seconds..."
            sleep 5
        fi
    done
    
    return 1
}

# Try alternative URLs
try_alternative_urls() {
    local os_key="$1"
    local output="$2"
    
    # Check for fallback URL
    if [[ -n "${FALLBACK_URLS[$os_key]}" ]]; then
        print_info "Trying fallback URL..."
        if download_image "${FALLBACK_URLS[$os_key]}" "$output"; then
            return 0
        fi
    fi
    
    # Generic fallbacks based on OS type
    case $os_key in
        debian11)
            print_info "Trying alternative Debian 11 URL..."
            local alt_urls=(
                "https://cloud.debian.org/images/cloud/bullseye/daily/20250101/debian-11-generic-amd64-daily-20250101.qcow2"
                "https://cloud.debian.org/images/cloud/bullseye/daily/latest/debian-11-generic-amd64-daily.qcow2"
                "https://cdimage.debian.org/cdimage/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"
            )
            for alt_url in "${alt_urls[@]}"; do
                print_info "Trying: $(basename "$alt_url")"
                if download_image "$alt_url" "$output"; then
                    return 0
                fi
            done
            ;;
        debian12)
            print_info "Trying alternative Debian 12 URL..."
            local alt_urls=(
                "https://cloud.debian.org/images/cloud/bookworm/daily/latest/debian-12-generic-amd64-daily.qcow2"
                "https://cdimage.debian.org/cdimage/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
            )
            for alt_url in "${alt_urls[@]}"; do
                print_info "Trying: $(basename "$alt_url")"
                if download_image "$alt_url" "$output"; then
                    return 0
                fi
            done
            ;;
    esac
    
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
    print_success "Config saved: $config"
    log_message "CONFIG" "Saved: $VM_NAME"
}

# Create VM
create_vm() {
    display_banner
    print_info "Creating new ZynexForge VM"
    
    # OS selection
    print_info "Available OS images:"
    local i=1
    local os_keys=()
    for key in "${!OS_IMAGES[@]}"; do
        IFS='|' read -r name _ _ _ _ <<< "${OS_IMAGES[$key]}"
        echo "  $i) $name"
        os_keys[$i]="$key"
        ((i++))
    done
    
    local choice
    while true; do
        read -p "$(print_input "Select OS (1-${#OS_IMAGES[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_IMAGES[@]} ]; then
            local os_key="${os_keys[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_USER DEFAULT_PASS <<< "${OS_IMAGES[$os_key]}"
            DEFAULT_HOSTNAME="${os_key}"
            break
        fi
        print_error "Invalid choice"
    done
    
    # VM name
    local vm_name
    while true; do
        read -p "$(print_input "VM name (default: ${BRAND_PREFIX}${DEFAULT_HOSTNAME}): ")" vm_name
        vm_name="${vm_name:-${BRAND_PREFIX}${DEFAULT_HOSTNAME}}"
        if validate_name "$vm_name"; then
            if [[ -f "$CONFIG_DIR/$vm_name.conf" ]]; then
                print_error "VM '$vm_name' exists"
            else
                VM_NAME="$vm_name"
                break
            fi
        else
            print_error "Invalid name (letters, numbers, _, -)"
        fi
    done
    
    # Hostname
    read -p "$(print_input "Hostname (default: $VM_NAME): ")" HOSTNAME
    HOSTNAME="${HOSTNAME:-$VM_NAME}"
    
    # Username
    while true; do
        read -p "$(print_input "Username (default: $DEFAULT_USER): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USER}"
        if validate_username "$USERNAME"; then
            break
        fi
        print_error "Invalid username (start with letter, lowercase only)"
    done
    
    # Password
    read -s -p "$(print_input "Password (default: $DEFAULT_PASS): ")" PASSWORD
    PASSWORD="${PASSWORD:-$DEFAULT_PASS}"
    echo
    
    # Resources
    while true; do
        read -p "$(print_input "Disk size (default: 50G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-50G}"
        validate_size "$DISK_SIZE" && break
        print_error "Invalid size (e.g., 50G, 100G)"
    done
    
    while true; do
        read -p "$(print_input "Memory in MB (default: 4096): ")" MEMORY
        MEMORY="${MEMORY:-4096}"
        validate_number "$MEMORY" && break
        print_error "Invalid number"
    done
    
    while true; do
        read -p "$(print_input "vCPUs (default: 4): ")" CPUS
        CPUS="${CPUS:-4}"
        validate_number "$CPUS" && break
        print_error "Invalid number"
    done
    
    # SSH Port
    while true; do
        read -p "$(print_input "SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_port "$SSH_PORT" && check_port_free "$SSH_PORT"; then
            break
        fi
        print_error "Port $SSH_PORT invalid or in use"
    done
    
    # GUI mode
    read -p "$(print_input "Enable GUI? (y/N): ")" gui_choice
    if [[ "$gui_choice" =~ ^[Yy]$ ]]; then
        GUI_MODE=true
    else
        GUI_MODE=false
    fi
    
    # Port forwards
    read -p "$(print_input "Port forwards (e.g., 8080:80,443:443): ")" PORT_FORWARDS
    
    # Set file paths
    IMG_FILE="$VM_DIR/disks/$VM_NAME.qcow2"
    SEED_FILE="$VM_DIR/isos/$VM_NAME-seed.iso"
    CREATED=$(date)
    
    # Setup VM
    setup_vm
    
    # Save config
    save_config
    
    print_success "VM '$VM_NAME' created!"
    print_info "Start with: Select from main menu"
}

# Setup VM image
setup_vm() {
    print_info "Setting up VM..."
    
    # Download image with retry logic
    if [[ ! -f "$IMG_FILE" ]]; then
        print_info "Downloading: $(basename "$IMG_URL")"
        
        # Try primary URL
        if ! download_image "$IMG_URL" "$IMG_FILE"; then
            # Extract OS key from URL or use VM_NAME
            local os_key=""
            for key in "${!OS_IMAGES[@]}"; do
                if [[ "$IMG_URL" == *"$key"* ]] || [[ "$OS_TYPE" == *"$key"* ]]; then
                    os_key="$key"
                    break
                fi
            done
            
            if [[ -z "$os_key" ]]; then
                # Try to guess from OS_TYPE
                case $OS_TYPE in
                    *"Ubuntu 22"*) os_key="ubuntu22" ;;
                    *"Ubuntu 24"*) os_key="ubuntu24" ;;
                    *"Debian 11"*) os_key="debian11" ;;
                    *"Debian 12"*) os_key="debian12" ;;
                    *"Kali"*) os_key="kali" ;;
                    *"Arch"*) os_key="arch" ;;
                    *"Fedora"*) os_key="fedora40" ;;
                    *"CentOS"*) os_key="centos9" ;;
                esac
            fi
            
            if [[ -n "$os_key" ]]; then
                print_info "Trying alternative download methods for $OS_TYPE..."
                if ! try_alternative_urls "$os_key" "$IMG_FILE"; then
                    print_error "All download attempts failed for $OS_TYPE"
                    print_info "Please check your internet connection or try a different OS"
                    exit 1
                fi
            else
                print_error "Failed to download image and could not determine OS type"
                exit 1
            fi
        fi
    else
        print_info "Image already exists, skipping download"
    fi
    
    # Resize disk
    print_info "Resizing to $DISK_SIZE"
    if ! qemu-img resize -f qcow2 "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
        print_info "Creating new disk image..."
        qemu-img create -f qcow2 -o preallocation=metadata "$IMG_FILE" "$DISK_SIZE"
    fi
    
    # Generate password hash
    local pass_hash
    if command -v mkpasswd &> /dev/null; then
        pass_hash=$(mkpasswd -m sha-512 "$PASSWORD" 2>/dev/null || echo "$PASSWORD")
    elif command -v openssl &> /dev/null; then
        pass_hash=$(openssl passwd -6 "$PASSWORD" 2>/dev/null || echo "$PASSWORD")
    else
        pass_hash="$PASSWORD"
        print_warn "Using plain password (install 'whois' for hashing)"
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
    passwd: $pass_hash
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
  - cloud-init clean --logs
EOF
    
    cat > /tmp/meta-data <<EOF
instance-id: $VM_NAME
local-hostname: $HOSTNAME
EOF
    
    # Create seed image
    print_info "Creating cloud-init seed..."
    if cloud-localds "$SEED_FILE" /tmp/user-data /tmp/meta-data; then
        print_success "Seed image created"
    else
        print_error "Failed to create seed image"
        exit 1
    fi
    
    rm -f /tmp/user-data /tmp/meta-data
    print_success "VM setup complete"
    log_message "CREATE" "Created: $VM_NAME ($OS_TYPE)"
}

# Start VM
start_vm() {
    local vm="$1"
    
    if load_config "$vm"; then
        # Check if running
        if [[ -f "$VM_DIR/$vm.pid" ]]; then
            local pid=$(cat "$VM_DIR/$vm.pid" 2>/dev/null)
            if kill -0 "$pid" 2>/dev/null; then
                print_warn "$vm is already running (PID: $pid)"
                return 0
            fi
            rm -f "$VM_DIR/$vm.pid"
        fi
        
        # Verify files
        if [[ ! -f "$IMG_FILE" ]]; then
            print_error "Image missing: $IMG_FILE"
            print_info "Recreating VM setup..."
            setup_vm
        fi
        
        if [[ ! -f "$SEED_FILE" ]]; then
            print_warn "Seed missing, recreating..."
            setup_vm
        fi
        
        print_info "Starting $vm"
        print_info "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
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
            -device virtio-rng-pci
            -rtc base=utc,clock=host
            -nodefaults
        )
        
        # Add port forwards
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            local net_id=1
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                if [[ -n "$host_port" && -n "$guest_port" ]]; then
                    qemu_cmd+=(-netdev "user,id=net$net_id,hostfwd=tcp::$host_port-:$guest_port")
                    qemu_cmd+=(-device "virtio-net-pci,netdev=net$net_id")
                    ((net_id++))
                fi
            done
        fi
        
        # GUI or console
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga virtio -display gtk)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi
        
        # Start VM
        local log_file="$LOG_DIR/$vm-$(date '+%Y%m%d-%H%M%S').log"
        print_info "Starting QEMU... (logs: $log_file)"
        
        # Run QEMU in background
        if [[ "$GUI_MODE" == true ]]; then
            "${qemu_cmd[@]}" 2>&1 | tee "$log_file" &
        else
            "${qemu_cmd[@]}" 2>&1 | tee "$log_file" >/dev/null &
        fi
        
        local pid=$!
        echo "$pid" > "$VM_DIR/$vm.pid"
        
        # Wait and check
        sleep 3
        if kill -0 "$pid" 2>/dev/null; then
            print_success "$vm started (PID: $pid)"
            log_message "START" "Started: $vm (PID: $pid)"
            
            echo ""
            print_info "══════════════════════════════════════════════════"
            print_info "VM: $vm"
            print_info "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
            print_info "Password: $PASSWORD"
            print_info "══════════════════════════════════════════════════"
            echo ""
            
            if [[ "$GUI_MODE" == false ]]; then
                print_info "To stop VM: Press 'Ctrl+A' then 'X'"
                print_info "To SSH into VM: Open another terminal and run:"
                print_info "  ssh -p $SSH_PORT $USERNAME@localhost"
            fi
        else
            print_error "Failed to start QEMU"
            print_info "Check log file: $log_file"
            rm -f "$VM_DIR/$vm.pid"
            return 1
        fi
    fi
}

# Stop VM
stop_vm() {
    local vm="$1"
    
    if load_config "$vm"; then
        if [[ -f "$VM_DIR/$vm.pid" ]]; then
            local pid=$(cat "$VM_DIR/$vm.pid")
            if kill -0 "$pid" 2>/dev/null; then
                print_info "Stopping $vm..."
                kill -TERM "$pid"
                
                local timeout=30
                while kill -0 "$pid" 2>/dev/null && [ $timeout -gt 0 ]; do
                    sleep 1
                    ((timeout--))
                done
                
                if kill -0 "$pid" 2>/dev/null; then
                    print_warn "Force stopping..."
                    kill -KILL "$pid"
                fi
                
                print_success "$vm stopped"
                log_message "STOP" "Stopped: $vm"
            else
                print_info "$vm not running"
            fi
            rm -f "$VM_DIR/$vm.pid"
        else
            print_info "$vm not running"
        fi
    fi
}

# Delete VM
delete_vm() {
    local vm="$1"
    
    if load_config "$vm"; then
        print_warn "This will DELETE '$vm' permanently!"
        read -p "$(print_input "Type 'DELETE' to confirm: ")" confirm
        [[ "$confirm" != "DELETE" ]] && { print_info "Cancelled"; return 0; }
        
        # Stop if running
        if [[ -f "$VM_DIR/$vm.pid" ]]; then
            print_info "Stopping first..."
            stop_vm "$vm"
            sleep 2
        fi
        
        # Remove files
        rm -f "$IMG_FILE" "$SEED_FILE" "$CONFIG_DIR/$vm.conf" "$VM_DIR/$vm.pid" 2>/dev/null
        find "$LOG_DIR" -name "$vm-*.log" -delete 2>/dev/null
        
        print_success "$vm deleted"
        log_message "DELETE" "Deleted: $vm"
    fi
}

# Show VM info
show_vm_info() {
    local vm="$1"
    
    if load_config "$vm"; then
        echo ""
        echo "┌─────────────────────────────────────────────────────┐"
        echo "│            ZYNEXFORGE VM INFORMATION                │"
        echo "├─────────────────────────────────────────────────────┤"
        printf "│ %-20s: %-30s │\n" "Name" "$VM_NAME"
        printf "│ %-20s: %-30s │\n" "OS" "$OS_TYPE"
        printf "│ %-20s: %-30s │\n" "Hostname" "$HOSTNAME"
        printf "│ %-20s: %-30s │\n" "Username" "$USERNAME"
        printf "│ %-20s: %-30s │\n" "SSH Port" "$SSH_PORT"
        printf "│ %-20s: %-30s │\n" "Memory" "${MEMORY}MB"
        printf "│ %-20s: %-30s │\n" "vCPUs" "$CPUS"
        printf "│ %-20s: %-30s │\n" "Disk" "$DISK_SIZE"
        printf "│ %-20s: %-30s │\n" "GUI" "$GUI_MODE"
        printf "│ %-20s: %-30s │\n" "Created" "$CREATED"
        echo "├─────────────────────────────────────────────────────┤"
        echo "│ CONNECTION                                          │"
        echo "├─────────────────────────────────────────────────────┤"
        echo "│ ssh -p $SSH_PORT $USERNAME@localhost                │"
        echo "│ Password: $PASSWORD                                 │"
        echo "└─────────────────────────────────────────────────────┘"
        echo ""
        
        read -p "$(print_input "Press Enter...")"
    fi
}

# Edit VM config
edit_vm() {
    local vm="$1"
    
    if load_config "$vm"; then
        if [[ -f "$VM_DIR/$vm.pid" ]]; then
            print_error "$vm is running - stop first"
            return 1
        fi
        
        print_info "Editing $vm"
        
        while true; do
            echo ""
            echo "1) Hostname [$HOSTNAME]"
            echo "2) Username [$USERNAME]" 
            echo "3) Password [****]"
            echo "4) SSH Port [$SSH_PORT]"
            echo "5) Memory [${MEMORY}MB]"
            echo "6) vCPUs [$CPUS]"
            echo "7) GUI [$GUI_MODE]"
            echo "8) Port Forwards [$PORT_FORWARDS]"
            echo "0) Save & Exit"
            echo ""
            
            read -p "$(print_input "Choose: ")" choice
            
            case $choice in
                1)
                    read -p "$(print_input "New hostname: ")" HOSTNAME
                    HOSTNAME="${HOSTNAME:-$HOSTNAME}"
                    ;;
                2)
                    read -p "$(print_input "New username: ")" USERNAME
                    USERNAME="${USERNAME:-$USERNAME}"
                    ;;
                3)
                    read -s -p "$(print_input "New password: ")" PASSWORD
                    echo
                    ;;
                4)
                    while true; do
                        read -p "$(print_input "New SSH port: ")" SSH_PORT
                        SSH_PORT="${SSH_PORT:-$SSH_PORT}"
                        if validate_port "$SSH_PORT" && check_port_free "$SSH_PORT"; then
                            break
                        fi
                        print_error "Invalid port"
                    done
                    ;;
                5)
                    while true; do
                        read -p "$(print_input "New memory (MB): ")" MEMORY
                        MEMORY="${MEMORY:-$MEMORY}"
                        validate_number "$MEMORY" && break
                        print_error "Invalid number"
                    done
                    ;;
                6)
                    while true; do
                        read -p "$(print_input "New vCPUs: ")" CPUS
                        CPUS="${CPUS:-$CPUS}"
                        validate_number "$CPUS" && break
                        print_error "Invalid number"
                    done
                    ;;
                7)
                    read -p "$(print_input "Enable GUI? (y/N): ")" gui_choice
                    if [[ "$gui_choice" =~ ^[Yy]$ ]]; then
                        GUI_MODE=true
                    else
                        GUI_MODE=false
                    fi
                    ;;
                8)
                    read -p "$(print_input "Port forwards: ")" PORT_FORWARDS
                    ;;
                0)
                    # Update cloud-init
                    print_info "Updating cloud-init..."
                    setup_vm
                    save_config
                    print_success "Updated"
                    return 0
                    ;;
                *)
                    print_error "Invalid choice"
                    ;;
            esac
        done
    fi
}

# Resize disk
resize_disk() {
    local vm="$1"
    
    if load_config "$vm"; then
        if [[ -f "$VM_DIR/$vm.pid" ]]; then
            print_error "Stop VM first"
            return 1
        fi
        
        print_info "Current: $DISK_SIZE"
        
        while true; do
            read -p "$(print_input "New size (e.g., 100G): ")" new_size
            if validate_size "$new_size"; then
                if [[ "$new_size" == "$DISK_SIZE" ]]; then
                    print_info "No change"
                    return 0
                fi
                
                # Warn about shrinking
                local current_num=${DISK_SIZE%[GgMm]}
                local new_num=${new_size%[GgMm]}
                local current_unit=${DISK_SIZE: -1}
                local new_unit=${new_size: -1}
                
                if [[ "${current_unit^^}" == "G" ]]; then
                    current_num=$((current_num * 1024))
                fi
                if [[ "${new_unit^^}" == "G" ]]; then
                    new_num=$((new_num * 1024))
                fi
                
                if [[ $new_num -lt $current_num ]]; then
                    print_warn "SHRINKING MAY CAUSE DATA LOSS!"
                    read -p "$(print_input "Type 'SHRINK' to confirm: ")" confirm
                    [[ "$confirm" != "SHRINK" ]] && { print_info "Cancelled"; return 0; }
                fi
                
                # Resize
                print_info "Resizing to $new_size..."
                if qemu-img resize -f qcow2 "$IMG_FILE" "$new_size"; then
                    DISK_SIZE="$new_size"
                    save_config
                    print_success "Resized to $new_size"
                    log_message "RESIZE" "$vm disk: $new_size"
                else
                    print_error "Resize failed"
                fi
                break
            fi
            print_error "Invalid size"
        done
    fi
}

# Main menu
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
                
                if [[ -f "$VM_DIR/$vm.pid" ]]; then
                    local pid=$(cat "$VM_DIR/$vm.pid" 2>/dev/null)
                    if kill -0 "$pid" 2>/dev/null; then
                        status="Running"
                        color="32"
                    fi
                fi
                
                printf "│ \033[1;33m%2d\033[0m │ \033[1;37m%-28s\033[0m │ \033[1;%sm%-12s\033[0m │\n" \
                       "$((i+1))" "$vm" "$color" "$status"
            done
            echo "└────┴──────────────────────────────┴──────────────┘"
            echo ""
        else
            print_info "No VMs found. Create one to start."
            echo ""
        fi
        
        # Menu options
        echo "ZynexForge VM Engine v$SCRIPT_VERSION"
        echo "─────────────────────────────────────────────────────"
        echo "  1) Create new VM"
        
        if [ $vm_count -gt 0 ]; then
            echo "  2) Start VM"
            echo "  3) Stop VM"
            echo "  4) VM Info"
            echo "  5) Edit VM"
            echo "  6) Delete VM"
            echo "  7) Resize Disk"
        fi
        
        echo "  0) Exit"
        echo ""
        
        read -p "$(print_input "Choice: ")" choice
        
        case $choice in
            1)
                create_vm
                ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "VM number: ")" num
                    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le $vm_count ]; then
                        start_vm "${vms[$((num-1))]}"
                    else
                        print_error "Invalid"
                    fi
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "VM number: ")" num
                    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le $vm_count ]; then
                        stop_vm "${vms[$((num-1))]}"
                    else
                        print_error "Invalid"
                    fi
                fi
                ;;
            4)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "VM number: ")" num
                    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le $vm_count ]; then
                        show_vm_info "${vms[$((num-1))]}"
                    else
                        print_error "Invalid"
                    fi
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "VM number: ")" num
                    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le $vm_count ]; then
                        edit_vm "${vms[$((num-1))]}"
                    else
                        print_error "Invalid"
                    fi
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "VM number: ")" num
                    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le $vm_count ]; then
                        delete_vm "${vms[$((num-1))]}"
                    else
                        print_error "Invalid"
                    fi
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "VM number: ")" num
                    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le $vm_count ]; then
                        resize_disk "${vms[$((num-1))]}"
                    else
                        print_error "Invalid"
                    fi
                fi
                ;;
            0)
                print_info "Goodbye!"
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
