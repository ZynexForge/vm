#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge VM Manager
# Universal Version - Works Everywhere
# Proxmox-Supported OS with Performance Boost
# =============================

# Function to display header with ZynexForge branding
display_header() {
    clear
    cat << "EOF"

__________                           ___________                         
\____    /__.__. ____   ____ ___  __\_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /|    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    < |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \\___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/    \/             /_____/      \/ 
                                                                         

                    ⚡ ZynexForge VM Manager ⚡
                    Universal Version - Works Everywhere
========================================================================

EOF
    echo
}

# Function to display colored output
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "\033[1;34m[ℹ]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m[⚠]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m[✗]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[✓]\033[0m $message" ;;
        "INPUT") echo -e "\033[1;36m[?]\033[0m $message" ;;
        "PERF") echo -e "\033[1;35m[⚡]\033[0m $message" ;;
        "ZYNEX") echo -e "\033[1;33m[ZynexForge]\033[0m $message" ;;
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
    print_status "ZYNEX" "Checking system dependencies..."
    
    local deps=("qemu-system-x86_64" "wget" "qemu-img")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "On Ubuntu/Debian, try: sudo apt install qemu-system wget"
        print_status "INFO" "On CentOS/RHEL, try: sudo yum install qemu-kvm wget"
        print_status "INFO" "On Arch Linux, try: sudo pacman -S qemu-base wget"
        exit 1
    fi
    
    # Check for cloud-localds or genisoimage
    if ! command -v cloud-localds &> /dev/null && ! command -v genisoimage &> /dev/null; then
        print_status "WARN" "cloud-localds or genisoimage not found. Will attempt to create seed image manually."
    fi
    
    print_status "SUCCESS" "All dependencies satisfied"
}

# Function to cleanup temporary files
cleanup() {
    if [ -f "user-data" ]; then rm -f "user-data"; fi
    if [ -f "meta-data" ]; then rm -f "meta-data"; fi
    if [ -f "seed.iso" ]; then rm -f "seed.iso"; fi
}

# Function to create seed image
create_seed_image() {
    local seed_file="$1"
    local hostname="$2"
    local username="$3"
    local password="$4"
    
    # Create cloud-init config
    cat > user-data <<EOF
#cloud-config
hostname: $hostname
ssh_pwauth: true
disable_root: false
users:
  - name: $username
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $(echo "$password" | mkpasswd -m sha-512 -s 2>/dev/null || echo "$password")
chpasswd:
  list: |
    root:$password
    $username:$password
  expire: false
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - curl
  - wget
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "=== ZynexForge Optimized VM ===" > /etc/motd
  - echo "Powered by ZynexForge Universal VM Manager" >> /etc/motd
EOF

    cat > meta-data <<EOF
instance-id: iid-$hostname
local-hostname: $hostname
EOF
    
    # Try to create seed image
    if command -v cloud-localds &> /dev/null; then
        cloud-localds "$seed_file" user-data meta-data
    elif command -v genisoimage &> /dev/null; then
        genisoimage -output "$seed_file" -volid cidata -joliet -rock user-data meta-data
    else
        # Fallback: create simple seed image
        print_status "WARN" "Creating basic seed image without cloud-localds/genisoimage"
        mkdir -p cidata
        cp user-data meta-data cidata/
        xorriso -as mkisofs -joliet -rock -volid cidata -output "$seed_file" cidata/ 2>/dev/null || \
        (cd cidata && tar -cf - . | gzip > "../$seed_file")
        rm -rf cidata
    fi
    
    if [ -f "$seed_file" ]; then
        print_status "SUCCESS" "Seed image created: $seed_file"
        return 0
    else
        print_status "ERROR" "Failed to create seed image"
        return 1
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
        unset VM_NAME OS_TYPE IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        unset PERF_BOOST CPU_PIN IO_URING VIRTIO_OPT DISK_CACHE NET_TYPE
        
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
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
PERF_BOOST="$PERF_BOOST"
CPU_PIN="$CPU_PIN"
IO_URING="$IO_URING"
VIRTIO_OPT="$VIRTIO_OPT"
DISK_CACHE="$DISK_CACHE"
NET_TYPE="$NET_TYPE"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to configure performance options
configure_performance() {
    print_status "PERF" "Performance Configuration"
    
    # Performance boost option
    while true; do
        read -p "$(print_status "INPUT" "Enable Performance Boost? (y/n, default: y): ")" perf_input
        perf_input="${perf_input:-y}"
        if [[ "$perf_input" =~ ^[Yy]$ ]]; then 
            PERF_BOOST=true
            break
        elif [[ "$perf_input" =~ ^[Nn]$ ]]; then
            PERF_BOOST=false
            break
        else
            print_status "ERROR" "Please answer y or n"
        fi
    done
    
    if [[ "$PERF_BOOST" == true ]]; then
        # CPU Pinning
        while true; do
            read -p "$(print_status "INPUT" "Enable CPU Pinning? (y/n, default: y): ")" cpu_pin_input
            cpu_pin_input="${cpu_pin_input:-y}"
            if [[ "$cpu_pin_input" =~ ^[Yy]$ ]]; then
                CPU_PIN=true
                break
            elif [[ "$cpu_pin_input" =~ ^[Nn]$ ]]; then
                CPU_PIN=false
                break
            else
                print_status "ERROR" "Please answer y or n"
            fi
        done
        
        # IO Uring for faster disk I/O
        while true; do
            read -p "$(print_status "INPUT" "Enable IO Uring (faster disk I/O)? (y/n, default: y): ")" io_input
            io_input="${io_input:-y}"
            if [[ "$io_input" =~ ^[Yy]$ ]]; then
                IO_URING=true
                break
            elif [[ "$io_input" =~ ^[Nn]$ ]]; then
                IO_URING=false
                break
            else
                print_status "ERROR" "Please answer y or n"
            fi
        done
        
        # Disk cache mode
        echo "Select Disk Cache Mode:"
        echo "  1) none - Direct I/O (Fastest, No Cache)"
        echo "  2) writethrough - Write Through Cache"
        echo "  3) writeback - Write Back Cache (Balanced)"
        echo "  4) unsafe - No Sync (Fastest but Risky)"
        
        while true; do
            read -p "$(print_status "INPUT" "Enter choice (1-4, default: 1): ")" cache_choice
            cache_choice="${cache_choice:-1}"
            case $cache_choice in
                1) DISK_CACHE="none" ;;
                2) DISK_CACHE="writethrough" ;;
                3) DISK_CACHE="writeback" ;;
                4) DISK_CACHE="unsafe" ;;
                *) print_status "ERROR" "Invalid choice"; continue ;;
            esac
            break
        done
        
        print_status "SUCCESS" "Performance optimizations configured"
    else
        PERF_BOOST=false
        CPU_PIN=false
        IO_URING=false
        DISK_CACHE="writeback"
    fi
    
    # Always enable VirtIO and set network type
    VIRTIO_OPT=true
    NET_TYPE="virtio-net-pci"
}

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating a new VM"
    print_status "ZYNEX" "Universal VM Manager - Works on any Linux distribution"
    echo
    
    # OS Selection - Simple list as requested
    echo "Select OS:"
    echo "  1) AlmaLinux 9"
    echo "  2) Fedora 40 Cloud"
    echo "  3) Debian 12 Bookworm"
    echo "  4) Ubuntu 22.04 LTS"
    echo "  5) CentOS Stream 9"
    echo "  6) Rocky Linux 9"
    echo "  7) Ubuntu 24.04 LTS"
    echo "  8) Debian 11 Bullseye"
    echo "  9) Debian 12"
    echo "  10) AlmaLinux 9"
    echo "  11) Ubuntu 24.04"
    echo "  12) Proxmox"
    echo
    
    while true; do
        read -p "$(print_status "INPUT" "Enter your choice (1-12): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le 12 ]; then
            case $choice in
                1) OS_TYPE="AlmaLinux 9"; IMG_URL="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"; DEFAULT_HOSTNAME="almalinux9"; DEFAULT_USERNAME="alma"; DEFAULT_PASSWORD="alma123" ;;
                2) OS_TYPE="Fedora 40"; IMG_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2"; DEFAULT_HOSTNAME="fedora40"; DEFAULT_USERNAME="fedora"; DEFAULT_PASSWORD="fedora123" ;;
                3) OS_TYPE="Debian 12"; IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"; DEFAULT_HOSTNAME="debian12"; DEFAULT_USERNAME="debian"; DEFAULT_PASSWORD="debian123" ;;
                4) OS_TYPE="Ubuntu 22.04"; IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"; DEFAULT_HOSTNAME="ubuntu22"; DEFAULT_USERNAME="ubuntu"; DEFAULT_PASSWORD="ubuntu123" ;;
                5) OS_TYPE="CentOS 9"; IMG_URL="https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"; DEFAULT_HOSTNAME="centos9"; DEFAULT_USERNAME="centos"; DEFAULT_PASSWORD="centos123" ;;
                6) OS_TYPE="Rocky Linux 9"; IMG_URL="https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"; DEFAULT_HOSTNAME="rocky9"; DEFAULT_USERNAME="rocky"; DEFAULT_PASSWORD="rocky123" ;;
                7) OS_TYPE="Ubuntu 24.04"; IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"; DEFAULT_HOSTNAME="ubuntu24"; DEFAULT_USERNAME="ubuntu"; DEFAULT_PASSWORD="ubuntu123" ;;
                8) OS_TYPE="Debian 11"; IMG_URL="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"; DEFAULT_HOSTNAME="debian11"; DEFAULT_USERNAME="debian"; DEFAULT_PASSWORD="debian123" ;;
                9) OS_TYPE="Debian 12"; IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"; DEFAULT_HOSTNAME="debian12"; DEFAULT_USERNAME="debian"; DEFAULT_PASSWORD="debian123" ;;
                10) OS_TYPE="AlmaLinux 9"; IMG_URL="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"; DEFAULT_HOSTNAME="almalinux9"; DEFAULT_USERNAME="alma"; DEFAULT_PASSWORD="alma123" ;;
                11) OS_TYPE="Ubuntu 24.04"; IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"; DEFAULT_HOSTNAME="ubuntu24"; DEFAULT_USERNAME="ubuntu"; DEFAULT_PASSWORD="ubuntu123" ;;
                12) OS_TYPE="Proxmox"; IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"; DEFAULT_HOSTNAME="proxmox-vm"; DEFAULT_USERNAME="proxmox"; DEFAULT_PASSWORD="proxmox123" ;;
            esac
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

    # Disk Size
    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 20G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-20G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    # Memory
    while true; do
        read -p "$(print_status "INPUT" "Memory in MB (default: 2048): ")" MEMORY
        MEMORY="${MEMORY:-2048}"
        if validate_input "number" "$MEMORY"; then
            break
        fi
    done

    # CPUs
    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (default: 2): ")" CPUS
        CPUS="${CPUS:-2}"
        if validate_input "number" "$CPUS"; then
            break
        fi
    done

    # SSH Port
    while true; do
        read -p "$(print_status "INPUT" "SSH Port (default: $((2200 + RANDOM % 1000))): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-$((2200 + RANDOM % 1000))}"
        if validate_input "port" "$SSH_PORT"; then
            # Check if port is already in use
            if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "Port $SSH_PORT is already in use"
            elif netstat -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "Port $SSH_PORT is already in use"
            else
                break
            fi
        fi
    done

    # GUI mode
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

    # Additional port forwards
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80, press Enter for none): ")" PORT_FORWARDS

    # Configure performance options
    configure_performance

    IMG_FILE="$VM_DIR/$VM_NAME.qcow2"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date '+%Y-%m-%d %H:%M:%S')"

    # Download and setup VM image
    setup_vm_image
    
    # Save configuration
    save_vm_config
    
    print_status "ZYNEX" "VM '$VM_NAME' created successfully!"
    echo
    print_status "INFO" "To start VM: Select option 2 from main menu"
    print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
}

# Function to setup VM image
setup_vm_image() {
    print_status "INFO" "Setting up VM image..."
    
    # Create VM directory if it doesn't exist
    mkdir -p "$VM_DIR"
    
    # Check if image already exists
    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "Image file already exists. Skipping download."
    else
        print_status "INFO" "Downloading $OS_TYPE image..."
        print_status "INFO" "URL: $IMG_URL"
        
        # Try different download methods
        if command -v curl &> /dev/null; then
            curl -L -# -o "$IMG_FILE.tmp" "$IMG_URL"
        elif command -v wget &> /dev/null; then
            wget --show-progress -O "$IMG_FILE.tmp" "$IMG_URL"
        else
            print_status "ERROR" "Neither curl nor wget found. Cannot download image."
            exit 1
        fi
        
        if [ -f "$IMG_FILE.tmp" ]; then
            mv "$IMG_FILE.tmp" "$IMG_FILE"
            print_status "SUCCESS" "Image downloaded successfully"
        else
            print_status "ERROR" "Failed to download image"
            exit 1
        fi
    fi
    
    # Create optimized disk image
    print_status "INFO" "Creating disk image..."
    
    # Convert to qcow2 format with compression if not already
    if [[ ! "$IMG_FILE" == *.qcow2 ]]; then
        qemu-img convert -O qcow2 -c "$IMG_FILE" "$IMG_FILE.tmp" 2>/dev/null
        if [ -f "$IMG_FILE.tmp" ]; then
            mv "$IMG_FILE.tmp" "$IMG_FILE"
        fi
    fi
    
    # Resize disk if needed
    current_size=$(qemu-img info "$IMG_FILE" 2>/dev/null | grep "virtual size" | awk '{print $3$4}')
    if [[ "$current_size" != "$DISK_SIZE" ]]; then
        print_status "INFO" "Resizing disk from $current_size to $DISK_SIZE"
        qemu-img resize -f qcow2 "$IMG_FILE" "$DISK_SIZE" 2>/dev/null
    fi
    
    # Create seed image
    print_status "INFO" "Creating cloud-init seed image..."
    create_seed_image "$SEED_FILE" "$HOSTNAME" "$USERNAME" "$PASSWORD"
    
    print_status "SUCCESS" "VM image setup complete"
}

# Function to build QEMU command
build_qemu_command() {
    local vm_name=$1
    local qemu_cmd=()
    
    # Base QEMU command with KVM acceleration
    qemu_cmd=(
        qemu-system-x86_64
        -enable-kvm
        -cpu host
        -machine type=q35,accel=kvm
        -smp "$CPUS"
        -m "$MEMORY"
    )
    
    # Performance optimizations
    if [[ "$PERF_BOOST" == true ]]; then
        # CPU pinning for performance
        if [[ "$CPU_PIN" == true ]]; then
            local cpu_count=$(nproc 2>/dev/null || echo 1)
            if [ "$cpu_count" -gt "$CPUS" ]; then
                qemu_cmd+=(-numa node,cpus=0-$((CPUS-1)),nodeid=0)
            fi
        fi
    fi
    
    # Disk configuration
    qemu_cmd+=(
        -drive "file=$IMG_FILE,format=qcow2,if=virtio,cache=$DISK_CACHE"
        -drive "file=$SEED_FILE,format=raw,if=virtio,readonly=on"
    )
    
    # IO Uring for fast I/O
    if [[ "$IO_URING" == true ]]; then
        qemu_cmd+=(-object iothread,id=iothread0)
        qemu_cmd+=(-device virtio-blk-pci,drive=drive0,iothread=iothread0)
    fi
    
    # Network configuration
    qemu_cmd+=(
        -netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22"
        -device "$NET_TYPE,netdev=net0"
    )
    
    # Add port forwards if specified
    if [[ -n "$PORT_FORWARDS" ]]; then
        IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
        for forward in "${forwards[@]}"; do
            IFS=':' read -r host_port guest_port <<< "$forward"
            qemu_cmd+=(-netdev "user,id=net${#qemu_cmd[@]},hostfwd=tcp::$host_port-:$guest_port")
            qemu_cmd+=(-device "virtio-net-pci,netdev=net${#qemu_cmd[@]}")
        done
    fi
    
    # Additional devices
    qemu_cmd+=(
        -device virtio-balloon-pci
        -object rng-random,filename=/dev/urandom,id=rng0
        -device virtio-rng-pci,rng=rng0
    )
    
    # Boot order
    qemu_cmd+=(-boot order=c)
    
    # GUI or console mode
    if [[ "$GUI_MODE" == true ]]; then
        qemu_cmd+=(-vga virtio -display gtk)
    else
        qemu_cmd+=(-nographic)
    fi
    
    echo "${qemu_cmd[@]}"
}

# Function to start a VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $vm_name"
        echo
        print_status "INFO" "=== Connection Details ==="
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Password: $PASSWORD"
        print_status "INFO" "Hostname: $HOSTNAME"
        print_status "INFO" "OS: $OS_TYPE"
        echo
        
        # Check if image file exists
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "VM image file not found: $IMG_FILE"
            return 1
        fi
        
        # Check if seed file exists
        if [[ ! -f "$SEED_FILE" ]]; then
            print_status "WARN" "Seed file not found, recreating..."
            create_seed_image "$SEED_FILE" "$HOSTNAME" "$USERNAME" "$PASSWORD"
        fi
        
        # Build and execute QEMU command
        local qemu_cmd=$(build_qemu_command "$vm_name")
        
        print_status "INFO" "Starting QEMU..."
        print_status "INFO" "Press Ctrl+A then X to stop the VM"
        echo
        
        # Execute the command
        eval "$qemu_cmd"
        
        print_status "INFO" "VM $vm_name has been shut down"
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
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
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
        print_status "ZYNEX" "VM Information: $vm_name"
        echo "=========================================="
        echo "OS: $OS_TYPE"
        echo "Hostname: $HOSTNAME"
        echo "Username: $USERNAME"
        echo "Password: ********"
        echo "SSH Port: $SSH_PORT"
        echo "Memory: $MEMORY MB"
        echo "CPUs: $CPUS"
        echo "Disk: $DISK_SIZE"
        echo "GUI Mode: $GUI_MODE"
        echo "Port Forwards: ${PORT_FORWARDS:-None}"
        echo "Created: $CREATED"
        echo ""
        if [[ "$PERF_BOOST" == true ]]; then
            print_status "PERF" "Performance Optimizations:"
            echo "  CPU Pinning: $CPU_PIN"
            echo "  IO Uring: $IO_URING"
            echo "  Disk Cache: $DISK_CACHE"
        fi
        echo "=========================================="
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    if pgrep -f "qemu-system-x86_64.*$VM_DIR/$vm_name" >/dev/null 2>&1; then
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
        print_status "INFO" "Editing VM: $vm_name"
        
        while true; do
            echo "What would you like to edit?"
            echo "  1) Hostname"
            echo "  2) Username"
            echo "  3) Password"
            echo "  4) SSH Port"
            echo "  5) GUI Mode"
            echo "  6) Port Forwards"
            echo "  7) Memory (RAM)"
            echo "  8) CPU Count"
            echo "  9) Disk Size"
            echo "  10) Performance Settings"
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
                        read -p "$(print_status "INPUT" "Enter new SSH port (current: $SSH_PORT): ")" new_ssh_port
                        new_ssh_port="${new_ssh_port:-$SSH_PORT}"
                        if validate_input "port" "$new_ssh_port"; then
                            if [ "$new_ssh_port" != "$SSH_PORT" ] && (ss -tln 2>/dev/null | grep -q ":$new_ssh_port " || netstat -tln 2>/dev/null | grep -q ":$new_ssh_port "); then
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
                    configure_performance
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
            if [[ "$edit_choice" -eq 1 || "$edit_choice" -eq 2 || "$edit_choice" -eq 3 ]]; then
                print_status "INFO" "Updating cloud-init configuration..."
                create_seed_image "$SEED_FILE" "$HOSTNAME" "$USERNAME" "$PASSWORD"
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
                
                # Resize the disk
                print_status "INFO" "Resizing disk to $new_disk_size..."
                if qemu-img resize -f qcow2 "$IMG_FILE" "$new_disk_size"; then
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
        print_status "INFO" "Performance metrics for VM: $vm_name"
        echo "=========================================="
        
        if is_vm_running "$vm_name"; then
            # Get QEMU process ID
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$IMG_FILE")
            if [[ -n "$qemu_pid" ]]; then
                echo "QEMU Process Stats:"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,vsz,rss,etime,cmd --no-headers 2>/dev/null || echo "Process info not available"
                echo ""
                
                # Show disk usage
                echo "VM Disk Usage:"
                ls -lh "$IMG_FILE" 2>/dev/null || echo "Disk info not available"
            fi
        else
            print_status "INFO" "VM $vm_name is not running"
            echo "Configuration:"
            echo "  Memory: $MEMORY MB"
            echo "  CPUs: $CPUS"
            echo "  Disk: $DISK_SIZE"
        fi
        echo "=========================================="
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to export VM configuration
export_vm_config() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        local export_file="$VM_DIR/$vm_name-export.conf"
        cp "$VM_DIR/$vm_name.conf" "$export_file"
        print_status "SUCCESS" "VM configuration exported to $export_file"
    fi
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        print_status "ZYNEX" "Universal VM Manager - Works on any Linux distribution"
        echo
        
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
            echo "  5) Edit VM configuration"
            echo "  6) Delete a VM"
            echo "  7) Resize VM disk"
            echo "  8) Show VM performance"
            echo "  9) Export VM configuration"
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
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to export: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        export_vm_config "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            0)
                print_status "ZYNEX" "Thank you for using ZynexForge VM Manager!"
                echo "Goodbye!"
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
VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

# Start the main menu
main_menu
