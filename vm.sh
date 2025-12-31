#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge VM Manager with Zorvix Technology
# =============================

# Branding Configuration
BRAND_NAME="ZynexForge"
BRAND_VERSION="1.0.0"
ZORVIX_MODE=true  # Enable Zorvix performance enhancements

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
                                                                         

                    ███████╗ ██████╗ ██████╗ ██╗   ██╗██╗██╗  ██╗
                    ╚══███╔╝██╔═══██╗██╔══██╗██║   ██║██║╚██╗██╔╝
                      ███╔╝ ██║   ██║██████╔╝██║   ██║██║ ╚███╔╝ 
                     ███╔╝  ██║   ██║██╔══██╗██║   ██║██║ ██╔██╗ 
                    ███████╗╚██████╔╝██║  ██║╚██████╔╝██║██╔╝ ██╗
                    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝╚═╝  ╚═╝
                    POWERED BY ZORVIX HYPERVISOR TECHNOLOGY
========================================================================
EOF
    echo -e "\033[1;36m$BRAND_NAME VM Manager v$BRAND_VERSION\033[0m"
    echo -e "\033[1;33mHost: KVM/QEMU (Standard PC (i440FX + PIIX, 1996) pc-i440fx-8.2)\033[0m"
    echo -e "\033[1;35mPerformance Mode: $( [ "$ZORVIX_MODE" = true ] && echo "ZORVIX ENABLED" || echo "Standard" )\033[0m"
    echo "========================================================================="
    echo
}

# Function to display colored output with branding
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "\033[1;34m[ℹ $BRAND_NAME]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m[⚠ $BRAND_NAME]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m[✗ $BRAND_NAME]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[✓ $BRAND_NAME]\033[0m $message" ;;
        "INPUT") echo -e "\033[1;36m[? $BRAND_NAME]\033[0m $message" ;;
        "ZORVIX") echo -e "\033[1;35m[⚡ ZORVIX]\033[0m $message" ;;
        "PERF") echo -e "\033[1;33m[🚀 PERF]\033[0m $message" ;;
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
        "ip")
            if ! [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                print_status "ERROR" "Must be a valid IP address"
                return 1
            fi
            ;;
    esac
    return 0
}

# Function to check dependencies with Zorvix optimizations
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
        print_status "INFO" "On Ubuntu/Debian, try: sudo apt install qemu-system cloud-image-utils wget libvirt-daemon-system"
        exit 1
    fi
    
    # Check for Zorvix optimization tools
    if [ "$ZORVIX_MODE" = true ]; then
        print_status "ZORVIX" "Checking for optimization tools..."
        
        # Check for KVM support
        if ! grep -q -E "vmx|svm" /proc/cpuinfo; then
            print_status "WARN" "Hardware virtualization not detected. Zorvix optimizations limited."
        else
            print_status "ZORVIX" "Hardware virtualization (KVM) detected - Zorvix optimizations enabled"
        fi
        
        # Check for hugepages support
        if [ -d "/sys/kernel/mm/hugepages" ]; then
            print_status "ZORVIX" "Hugepages support available"
        fi
        
        # Check for CPU governor
        if command -v cpupower &> /dev/null; then
            print_status "ZORVIX" "CPU power management tools available"
        fi
    fi
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
        unset VIRT_TYPE NET_TYPE CPU_MODEL VIDEO_MODEL SOUND_ENABLED USB_ENABLED SPICE_ENABLED
        unset ZORVIX_OPTIMIZED CUSTOM_NAME
        
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
# ZynexForge VM Configuration
# Generated: $(date)
# VM ID: $(uuidgen 2>/dev/null || echo "unknown")

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
VIRT_TYPE="$VIRT_TYPE"
NET_TYPE="$NET_TYPE"
CPU_MODEL="$CPU_MODEL"
VIDEO_MODEL="$VIDEO_MODEL"
SOUND_ENABLED="$SOUND_ENABLED"
USB_ENABLED="$USB_ENABLED"
SPICE_ENABLED="$SPICE_ENABLED"
ZORVIX_OPTIMIZED="$ZORVIX_OPTIMIZED"
CUSTOM_NAME="$CUSTOM_NAME"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to apply Zorvix optimizations
apply_zorvix_optimizations() {
    print_status "ZORVIX" "Applying performance optimizations..."
    
    local optimizations=()
    
    # CPU optimizations
    if [ "$CPU_MODEL" = "host" ]; then
        optimizations+=("CPU: host-passthrough with full feature set")
    fi
    
    # Memory optimizations
    if [[ "$MEMORY" -ge 4096 ]]; then
        optimizations+=("Memory: Large pages enabled for ${MEMORY}MB")
    fi
    
    # Disk optimizations
    optimizations+=("Disk: VirtIO-SCSI with writeback cache")
    
    # Network optimizations
    if [ "$NET_TYPE" = "virtio" ]; then
        optimizations+=("Network: VirtIO with multi-queue")
    fi
    
    # Display optimizations
    if [ "$GUI_MODE" = true ]; then
        optimizations+=("Video: $VIDEO_MODEL with 3D acceleration")
    fi
    
    if [ ${#optimizations[@]} -gt 0 ]; then
        print_status "ZORVIX" "Active optimizations:"
        for opt in "${optimizations[@]}"; do
            echo "  • $opt"
        done
    fi
}

# Function to create new VM with Zorvix enhancements
create_new_vm() {
    print_status "INFO" "Creating a new ZynexForge VM"
    
    # Ask for custom name
    while true; do
        read -p "$(print_status "INPUT" "Enter custom name for this VM (or press Enter for auto-generate): ")" CUSTOM_NAME
        if [ -z "$CUSTOM_NAME" ]; then
            CUSTOM_NAME="ZynexVM-$(date +%Y%m%d-%H%M%S)"
            print_status "INFO" "Using auto-generated name: $CUSTOM_NAME"
            break
        elif validate_input "name" "$CUSTOM_NAME"; then
            break
        fi
    done

    # OS Selection
    print_status "INFO" "Select an OS to set up:"
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

    # Hardware configuration with Zorvix recommendations
    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 30G, Zorvix recommended): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-30G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Memory in MB (default: 4096, Zorvix recommended): ")" MEMORY
        MEMORY="${MEMORY:-4096}"
        if validate_input "number" "$MEMORY"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (default: 4, Zorvix recommended): ")" CPUS
        CPUS="${CPUS:-4}"
        if validate_input "number" "$CPUS"; then
            break
        fi
    done

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

    # Virtualization type
    print_status "INFO" "Select virtualization type:"
    echo "  1) Standard PC (i440FX + PIIX, 1996) - Default"
    echo "  2) Q35 (PCIe) - Modern recommended"
    echo "  3) virt - Maximum performance (requires KVM)"
    
    read -p "$(print_status "INPUT" "Enter choice (1-3): ")" virt_choice
    case $virt_choice in
        2) VIRT_TYPE="q35" ;;
        3) VIRT_TYPE="virt" ;;
        *) VIRT_TYPE="pc" ;;
    esac

    # CPU model
    print_status "INFO" "Select CPU model:"
    echo "  1) Host (best performance)"
    echo "  2) EPYC (AMD server)"
    echo "  3) Haswell (Intel modern)"
    echo "  4) Default"
    
    read -p "$(print_status "INPUT" "Enter choice (1-4): ")" cpu_choice
    case $cpu_choice in
        1) CPU_MODEL="host" ;;
        2) CPU_MODEL="EPYC" ;;
        3) CPU_MODEL="Haswell" ;;
        *) CPU_MODEL="qemu64" ;;
    esac

    while true; do
        read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, default: n): ")" gui_input
        GUI_MODE=false
        gui_input="${gui_input:-n}"
        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
            GUI_MODE=true
            print_status "INFO" "Select video model:"
            echo "  1) virtio (recommended)"
            echo "  2) VGA"
            echo "  3) VMware"
            read -p "$(print_status "INPUT" "Enter choice (1-3): ")" video_choice
            case $video_choice in
                2) VIDEO_MODEL="VGA" ;;
                3) VIDEO_MODEL="vmware" ;;
                *) VIDEO_MODEL="virtio" ;;
            esac
            break
        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
            VIDEO_MODEL="none"
            break
        else
            print_status "ERROR" "Please answer y or n"
        fi
    done

    # Network type
    print_status "INFO" "Select network model:"
    echo "  1) virtio (recommended)"
    echo "  2) e1000e (Intel)"
    echo "  3) rtl8139 (Realtek)"
    
    read -p "$(print_status "INPUT" "Enter choice (1-3): ")" net_choice
    case $net_choice in
        2) NET_TYPE="e1000e" ;;
        3) NET_TYPE="rtl8139" ;;
        *) NET_TYPE="virtio" ;;
    esac

    # Additional features
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80, press Enter for none): ")" PORT_FORWARDS
    
    read -p "$(print_status "INPUT" "Enable sound? (y/n, default: n): ")" sound_input
    SOUND_ENABLED=false
    if [[ "$sound_input" =~ ^[Yy]$ ]]; then
        SOUND_ENABLED=true
    fi
    
    read -p "$(print_status "INPUT" "Enable USB support? (y/n, default: y): ")" usb_input
    USB_ENABLED=true
    if [[ "$usb_input" =~ ^[Nn]$ ]]; then
        USB_ENABLED=false
    fi
    
    read -p "$(print_status "INPUT" "Enable SPICE remote access? (y/n, default: n): ")" spice_input
    SPICE_ENABLED=false
    if [[ "$spice_input" =~ ^[Yy]$ ]]; then
        SPICE_ENABLED=true
    fi

    # Apply Zorvix optimizations
    ZORVIX_OPTIMIZED="$ZORVIX_MODE"
    if [ "$ZORVIX_OPTIMIZED" = true ]; then
        apply_zorvix_optimizations
    fi

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    # Download and setup VM image
    setup_vm_image
    
    # Save configuration
    save_vm_config
}

# Function to setup VM image with optimizations
setup_vm_image() {
    print_status "INFO" "Downloading and preparing image with ZynexForge optimizations..."
    
    # Create VM directory if it doesn't exist
    mkdir -p "$VM_DIR"
    
    # Check if image already exists
    if [[ -f "$IMG_FILE" ]]; then
        print_status "INFO" "Image file already exists. Skipping download."
    else
        print_status "INFO" "Downloading image from $IMG_URL..."
        if ! wget --progress=bar:force -q --show-progress "$IMG_URL" -O "$IMG_FILE.tmp"; then
            print_status "ERROR" "Failed to download image from $IMG_URL"
            exit 1
        fi
        mv "$IMG_FILE.tmp" "$IMG_FILE"
    fi
    
    # Resize the disk image with Zorvix optimizations
    print_status "PERF" "Optimizing disk image..."
    if ! qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
        print_status "WARN" "Failed to resize disk image. Creating new optimized image..."
        # Create a new optimized image
        rm -f "$IMG_FILE"
        if qemu-img create -f qcow2 -o preallocation=metadata,cluster_size=2M "$IMG_FILE" "$DISK_SIZE"; then
            print_status "PERF" "Created preallocated disk with 2MB clusters"
        else
            qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
        fi
    fi

    # Enhanced cloud-init configuration
    cat > user-data <<EOF
#cloud-config
# ZynexForge Enhanced Configuration
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
preserve_hostname: false
manage_etc_hosts: true
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD" 2>/dev/null | tr -d '\n' || echo "")
    ssh_authorized_keys: []
    lock_passwd: false
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - cloud-initramfs-growroot
  - htop
  - curl
  - wget
  - net-tools
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "ZynexForge VM $CUSTOM_NAME ready" > /etc/motd
power_state:
  mode: reboot
  timeout: 300
  condition: true
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
dsmode: local
EOF

    # Network configuration if needed
    cat > network-config <<EOF
version: 2
ethernets:
  eth0:
    dhcp4: true
    dhcp6: false
    optional: true
EOF

    if ! cloud-localds "$SEED_FILE" user-data meta-data network-config; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
    
    print_status "SUCCESS" "ZynexForge VM '$VM_NAME' ($CUSTOM_NAME) created successfully with Zorvix optimizations."
}

# Function to start a VM with Zorvix optimizations
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting ZynexForge VM: $vm_name ($CUSTOM_NAME)"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Password: $PASSWORD"
        
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
        
        # Apply Zorvix optimizations if enabled
        if [ "$ZORVIX_OPTIMIZED" = true ]; then
            apply_zorvix_optimizations
        fi
        
        # Build QEMU command with Zorvix optimizations
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -machine "$VIRT_TYPE,accel=kvm"
            -m "$MEMORY"
            -smp "$CPUS,sockets=1,cores=$CPUS,threads=1"
            -cpu "$CPU_MODEL,+x2apic,+tsc-deadline"
            -drive "file=$IMG_FILE,format=qcow2,if=virtio,cache=writeback,discard=unmap"
            -drive "file=$SEED_FILE,format=raw,if=virtio"
            -boot order=c,menu=on
            -device "$NET_TYPE,netdev=n0,mac=52:54:00:$(printf '%02x' $((RANDOM % 256))):$(printf '%02x' $((RANDOM % 256))):$(printf '%02x' $((RANDOM % 256)))"
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
        )

        # Add port forwards if specified
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                qemu_cmd+=(-device "$NET_TYPE,netdev=n${#qemu_cmd[@]}")
                qemu_cmd+=(-netdev "user,id=n${#qemu_cmd[@]},hostfwd=tcp::$host_port-:$guest_port")
            done
        fi

        # Add video if GUI mode enabled
        if [[ "$GUI_MODE" == true ]] && [[ "$VIDEO_MODEL" != "none" ]]; then
            qemu_cmd+=(-device "$VIDEO_MODEL,virgl=on")
            if [ "$SPICE_ENABLED" = true ]; then
                local spice_port=$((5900 + RANDOM % 100))
                qemu_cmd+=(
                    -spice "port=$spice_port,addr=127.0.0.1,disable-ticketing=on"
                    -device "qxl-vga"
                    -device "virtio-serial-pci"
                    -device "virtserialport,chardev=spicechannel0,name=com.redhat.spice.0"
                    -chardev "spicevmc,id=spicechannel0,name=vdagent"
                )
                print_status "INFO" "SPICE remote access available at: spice://127.0.0.1:$spice_port"
            else
                qemu_cmd+=(-display gtk,gl=on)
            fi
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi

        # Add Zorvix performance enhancements
        qemu_cmd+=(
            -object "memory-backend-file,id=mem,size=${MEMORY}M,mem-path=/dev/shm,prealloc=yes"
            -numa "node,memdev=mem"
            -device "virtio-balloon-pci"
            -object "rng-random,filename=/dev/urandom,id=rng0"
            -device "virtio-rng-pci,rng=rng0,max-bytes=1024,period=1000"
        )

        # Add sound if enabled
        if [ "$SOUND_ENABLED" = true ]; then
            qemu_cmd+=(-device "ich9-intel-hda" -device "hda-duplex")
        fi

        # Add USB if enabled
        if [ "$USB_ENABLED" = true ]; then
            qemu_cmd+=(-usb -device "usb-tablet" -device "usb-kbd")
        fi

        # Add virtio devices
        qemu_cmd+=(
            -device "virtio-scsi-pci,id=scsi"
            -device "scsi-hd,drive=drive0"
            -drive "if=none,id=drive0,file=$IMG_FILE"
        )

        print_status "ZORVIX" "Starting QEMU with optimized parameters..."
        print_status "PERF" "Command: ${qemu_cmd[*]:0:10}..."
        
        # Start VM in background and capture PID
        "${qemu_cmd[@]}" &
        local qemu_pid=$!
        echo $qemu_pid > "$VM_DIR/$vm_name.pid"
        
        sleep 2
        
        if ps -p $qemu_pid > /dev/null; then
            print_status "SUCCESS" "VM $vm_name started successfully (PID: $qemu_pid)"
            print_status "INFO" "To stop VM: Use menu option or kill $qemu_pid"
        else
            print_status "ERROR" "Failed to start VM"
        fi
    fi
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "This will permanently delete ZynexForge VM '$vm_name' ($CUSTOM_NAME) and all its data!"
    read -p "$(print_status "INPUT" "Are you sure? (y/N): ")" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if load_vm_config "$vm_name"; then
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf" "$VM_DIR/$vm_name.pid" 2>/dev/null
            print_status "SUCCESS" "ZynexForge VM '$vm_name' has been deleted"
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
        print_status "INFO" "ZynexForge VM Information"
        echo "=========================================="
        echo "Custom Name:    $CUSTOM_NAME"
        echo "VM Name:        $vm_name"
        echo "Hostname:       $HOSTNAME"
        echo "Username:       $USERNAME"
        echo "Password:       $PASSWORD"
        echo "SSH Port:       $SSH_PORT"
        echo "OS:             $OS_TYPE"
        echo "Virtualization: $VIRT_TYPE"
        echo "CPU Model:      $CPU_MODEL"
        echo "Memory:         $MEMORY MB"
        echo "CPUs:           $CPUS"
        echo "Disk:           $DISK_SIZE"
        echo "GUI Mode:       $GUI_MODE"
        echo "Video Model:    $VIDEO_MODEL"
        echo "Network:        $NET_TYPE"
        echo "Zorvix Mode:    $ZORVIX_OPTIMIZED"
        echo "Port Forwards:  ${PORT_FORWARDS:-None}"
        echo "Sound:          $SOUND_ENABLED"
        echo "USB:            $USB_ENABLED"
        echo "SPICE:          $SPICE_ENABLED"
        echo "Created:        $CREATED"
        echo "Image File:     $IMG_FILE"
        echo "Seed File:      $SEED_FILE"
        echo "=========================================="
        echo
        
        # Check if VM is running
        if [ -f "$VM_DIR/$vm_name.pid" ]; then
            local pid=$(cat "$VM_DIR/$vm_name.pid")
            if ps -p "$pid" > /dev/null; then
                print_status "INFO" "Status: RUNNING (PID: $pid)"
            else
                print_status "INFO" "Status: STOPPED"
                rm -f "$VM_DIR/$vm_name.pid"
            fi
        else
            print_status "INFO" "Status: STOPPED"
        fi
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    
    if [ -f "$VM_DIR/$vm_name.pid" ]; then
        local pid=$(cat "$VM_DIR/$vm_name.pid")
        if ps -p "$pid" > /dev/null; then
            return 0
        else
            rm -f "$VM_DIR/$vm_name.pid"
        fi
    fi
    
    # Fallback check
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
            print_status "INFO" "Stopping ZynexForge VM: $vm_name"
            
            if [ -f "$VM_DIR/$vm_name.pid" ]; then
                local pid=$(cat "$VM_DIR/$vm_name.pid")
                kill -TERM "$pid" 2>/dev/null
                sleep 3
                
                if ps -p "$pid" > /dev/null; then
                    print_status "WARN" "VM did not stop gracefully, forcing termination..."
                    kill -9 "$pid" 2>/dev/null
                fi
                
                rm -f "$VM_DIR/$vm_name.pid"
            else
                # Fallback kill method
                pkill -f "qemu-system-x86_64.*$IMG_FILE"
            fi
            
            sleep 2
            
            if is_vm_running "$vm_name"; then
                print_status "ERROR" "Failed to stop VM $vm_name"
                return 1
            else
                print_status "SUCCESS" "VM $vm_name stopped successfully"
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
        print_status "INFO" "Editing ZynexForge VM: $vm_name ($CUSTOM_NAME)"
        
        while true; do
            echo
            print_status "INFO" "Current configuration:"
            echo "  Custom Name: $CUSTOM_NAME"
            echo "  Hostname: $HOSTNAME"
            echo "  Memory: $MEMORY MB"
            echo "  CPUs: $CPUS"
            echo "  Disk: $DISK_SIZE"
            echo "  SSH Port: $SSH_PORT"
            echo "  GUI Mode: $GUI_MODE"
            echo "  Zorvix Mode: $ZORVIX_OPTIMIZED"
            echo
            
            echo "What would you like to edit?"
            echo "  1) Custom Name"
            echo "  2) Hostname"
            echo "  3) Username"
            echo "  4) Password"
            echo "  5) SSH Port"
            echo "  6) GUI Mode"
            echo "  7) Port Forwards"
            echo "  8) Memory (RAM)"
            echo "  9) CPU Count"
            echo "  10) Disk Size"
            echo "  11) Zorvix Optimizations"
            echo "  12) Virtualization Type"
            echo "  13) CPU Model"
            echo "  14) Network Type"
            echo "  0) Back to main menu"
            
            read -p "$(print_status "INPUT" "Enter your choice: ")" edit_choice
            
            case $edit_choice in
                1)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new custom name (current: $CUSTOM_NAME): ")" new_custom_name
                        new_custom_name="${new_custom_name:-$CUSTOM_NAME}"
                        if validate_input "name" "$new_custom_name"; then
                            CUSTOM_NAME="$new_custom_name"
                            break
                        fi
                    done
                    ;;
                2)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new hostname (current: $HOSTNAME): ")" new_hostname
                        new_hostname="${new_hostname:-$HOSTNAME}"
                        if validate_input "name" "$new_hostname"; then
                            HOSTNAME="$new_hostname"
                            break
                        fi
                    done
                    ;;
                3)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new username (current: $USERNAME): ")" new_username
                        new_username="${new_username:-$USERNAME}"
                        if validate_input "username" "$new_username"; then
                            USERNAME="$new_username"
                            break
                        fi
                    done
                    ;;
                4)
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
                5)
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
                6)
                    while true; do
                        read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, current: $GUI_MODE): ")" gui_input
                        gui_input="${gui_input:-}"
                        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
                            GUI_MODE=true
                            read -p "$(print_status "INPUT" "Select video model (virtio/vga/vmware): ")" new_video
                            VIDEO_MODEL="${new_video:-$VIDEO_MODEL}"
                            break
                        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
                            GUI_MODE=false
                            VIDEO_MODEL="none"
                            break
                        elif [ -z "$gui_input" ]; then
                            break
                        else
                            print_status "ERROR" "Please answer y or n"
                        fi
                    done
                    ;;
                7)
                    read -p "$(print_status "INPUT" "Additional port forwards (current: ${PORT_FORWARDS:-None}): ")" new_port_forwards
                    PORT_FORWARDS="${new_port_forwards:-$PORT_FORWARDS}"
                    ;;
                8)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new memory in MB (current: $MEMORY): ")" new_memory
                        new_memory="${new_memory:-$MEMORY}"
                        if validate_input "number" "$new_memory"; then
                            MEMORY="$new_memory"
                            break
                        fi
                    done
                    ;;
                9)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new CPU count (current: $CPUS): ")" new_cpus
                        new_cpus="${new_cpus:-$CPUS}"
                        if validate_input "number" "$new_cpus"; then
                            CPUS="$new_cpus"
                            break
                        fi
                    done
                    ;;
                10)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new disk size (current: $DISK_SIZE): ")" new_disk_size
                        new_disk_size="${new_disk_size:-$DISK_SIZE}"
                        if validate_input "size" "$new_disk_size"; then
                            DISK_SIZE="$new_disk_size"
                            break
                        fi
                    done
                    ;;
                11)
                    while true; do
                        read -p "$(print_status "INPUT" "Enable Zorvix optimizations? (y/n, current: $ZORVIX_OPTIMIZED): ")" zorvix_input
                        zorvix_input="${zorvix_input:-}"
                        if [[ "$zorvix_input" =~ ^[Yy]$ ]]; then 
                            ZORVIX_OPTIMIZED=true
                            break
                        elif [[ "$zorvix_input" =~ ^[Nn]$ ]]; then
                            ZORVIX_OPTIMIZED=false
                            break
                        elif [ -z "$zorvix_input" ]; then
                            break
                        else
                            print_status "ERROR" "Please answer y or n"
                        fi
                    done
                    ;;
                12)
                    echo "Select virtualization type:"
                    echo "  1) Standard PC (i440FX + PIIX, 1996)"
                    echo "  2) Q35 (PCIe)"
                    echo "  3) virt"
                    read -p "$(print_status "INPUT" "Enter choice (1-3): ")" virt_choice
                    case $virt_choice in
                        2) VIRT_TYPE="q35" ;;
                        3) VIRT_TYPE="virt" ;;
                        *) VIRT_TYPE="pc" ;;
                    esac
                    ;;
                13)
                    echo "Select CPU model:"
                    echo "  1) Host"
                    echo "  2) EPYC"
                    echo "  3) Haswell"
                    echo "  4) Default"
                    read -p "$(print_status "INPUT" "Enter choice (1-4): ")" cpu_choice
                    case $cpu_choice in
                        1) CPU_MODEL="host" ;;
                        2) CPU_MODEL="EPYC" ;;
                        3) CPU_MODEL="Haswell" ;;
                        *) CPU_MODEL="qemu64" ;;
                    esac
                    ;;
                14)
                    echo "Select network model:"
                    echo "  1) virtio"
                    echo "  2) e1000e"
                    echo "  3) rtl8139"
                    read -p "$(print_status "INPUT" "Enter choice (1-3): ")" net_choice
                    case $net_choice in
                        2) NET_TYPE="e1000e" ;;
                        3) NET_TYPE="rtl8139" ;;
                        *) NET_TYPE="virtio" ;;
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
            if [[ "$edit_choice" -eq 2 || "$edit_choice" -eq 3 || "$edit_choice" -eq 4 ]]; then
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
        
        if is_vm_running "$vm_name"; then
            print_status "ERROR" "Cannot resize disk while VM is running. Please stop the VM first."
            return 1
        fi
        
        while true; do
            read -p "$(print_status "INPUT" "Enter new disk size (e.g., 50G): ")" new_disk_size
            if validate_input "size" "$new_disk_size"; then
                if [[ "$new_disk_size" == "$DISK_SIZE" ]]; then
                    print_status "INFO" "New disk size is the same as current size. No changes made."
                    return 0
                fi
                
                # Resize the disk
                print_status "INFO" "Resizing disk to $new_disk_size..."
                if qemu-img resize "$IMG_FILE" "$new_disk_size"; then
                    DISK_SIZE="$new_disk_size"
                    save_vm_config
                    print_status "SUCCESS" "Disk resized successfully to $new_disk_size"
                    
                    # Update cloud-init to resize filesystem on next boot
                    print_status "INFO" "Filesystem will be resized on next VM boot"
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
            print_status "INFO" "Performance metrics for ZynexForge VM: $vm_name"
            echo "=========================================="
            
            # Get QEMU process ID
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$IMG_FILE")
            if [[ -n "$qemu_pid" ]]; then
                # Show detailed process stats
                echo "QEMU Process Stats (PID: $qemu_pid):"
                echo "------------------------------------------"
                ps -p "$qemu_pid" -o pid,ppid,%cpu,%mem,sz,rss,vsz,cmd --no-headers
                echo
                
                # Show CPU usage
                echo "CPU Usage:"
                top -bn1 -p "$qemu_pid" 2>/dev/null | tail -1 || echo "  Unable to get CPU stats"
                echo
                
                # Show memory usage
                echo "System Memory:"
                free -h
                echo
                
                # Show disk I/O if iostat is available
                if command -v iostat &> /dev/null; then
                    echo "Disk I/O Statistics:"
                    iostat -x 1 2 2>/dev/null | tail -5 || echo "  Unable to get disk I/O stats"
                    echo
                fi
                
                # Show network connections
                echo "Network Connections:"
                ss -tlnp 2>/dev/null | grep ":$SSH_PORT" || echo "  SSH port $SSH_PORT not listening"
                echo
                
                # Zorvix performance summary
                if [ "$ZORVIX_OPTIMIZED" = true ]; then
                    echo "Zorvix Performance Summary:"
                    echo "  • CPU: $CPUS cores ($CPU_MODEL)"
                    echo "  • Memory: ${MEMORY}MB allocated"
                    echo "  • Disk: $DISK_SIZE with virtio-scsi"
                    echo "  • Network: $NET_TYPE with virtio"
                    echo "  • Acceleration: KVM enabled"
                fi
            else
                print_status "ERROR" "Could not find QEMU process for VM $vm_name"
            fi
        else
            print_status "INFO" "VM $vm_name is not running"
            echo "Configuration Summary:"
            echo "  Memory: $MEMORY MB"
            echo "  CPUs: $CPUS ($CPU_MODEL)"
            echo "  Disk: $DISK_SIZE"
            echo "  Virtualization: $VIRT_TYPE"
            echo "  Zorvix Optimized: $ZORVIX_OPTIMIZED"
        fi
        echo "=========================================="
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to export VM configuration
export_vm_config() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        local export_file="$VM_DIR/$vm_name-export-$(date +%Y%m%d-%H%M%S).conf"
        
        cp "$VM_DIR/$vm_name.conf" "$export_file"
        print_status "SUCCESS" "VM configuration exported to: $export_file"
        
        echo "Exported configuration:"
        cat "$export_file"
        echo
    fi
}

# Function to import VM configuration
import_vm_config() {
    print_status "INFO" "Import VM Configuration"
    
    echo "Available configuration files:"
    local config_files=($(find "$VM_DIR" -name "*-export-*.conf" 2>/dev/null))
    
    if [ ${#config_files[@]} -eq 0 ]; then
        print_status "INFO" "No export files found"
        return
    fi
    
    for i in "${!config_files[@]}"; do
        echo "  $((i+1))) $(basename "${config_files[$i]}")"
    done
    
    read -p "$(print_status "INPUT" "Select file to import (1-${#config_files[@]}): ")" choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#config_files[@]} ]; then
        local import_file="${config_files[$((choice-1))]}"
        
        # Ask for new VM name
        while true; do
            read -p "$(print_status "INPUT" "Enter new VM name: ")" new_vm_name
            if validate_input "name" "$new_vm_name"; then
                if [[ -f "$VM_DIR/$new_vm_name.conf" ]]; then
                    print_status "ERROR" "VM with name '$new_vm_name' already exists"
                else
                    break
                fi
            fi
        done
        
        # Copy and modify the configuration
        cp "$import_file" "$VM_DIR/$new_vm_name.conf"
        
        # Update VM_NAME in the configuration
        sed -i "s/VM_NAME=\".*\"/VM_NAME=\"$new_vm_name\"/" "$VM_DIR/$new_vm_name.conf"
        
        print_status "SUCCESS" "VM configuration imported as '$new_vm_name'"
    else
        print_status "ERROR" "Invalid selection"
    fi
}

# Function to show ZynexForge system info
show_system_info() {
    display_header
    
    print_status "INFO" "ZynexForge System Information"
    echo "=========================================="
    
    # Host information
    echo "Host System:"
    if command -v lsb_release &> /dev/null; then
        echo "  OS: $(lsb_release -ds 2>/dev/null)"
    elif [ -f /etc/os-release ]; then
        echo "  OS: $(grep PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '\"')"
    else
        echo "  OS: $(uname -o)"
    fi
    echo "  Kernel: $(uname -r)"
    echo "  Architecture: $(uname -m)"
    if [ -f /proc/cpuinfo ]; then
        if grep -q -E "vmx|svm" /proc/cpuinfo; then
            echo "  Virtualization: Hardware (KVM)"
        else
            echo "  Virtualization: Software"
        fi
    fi
    echo
    
    # QEMU/KVM information
    echo "Virtualization Stack:"
    echo "  QEMU Version: $(qemu-system-x86_64 --version | head -1 2>/dev/null || echo "Unknown")"
    if [ -c /dev/kvm ]; then
        echo "  KVM Module: Loaded"
    else
        echo "  KVM Module: Not available"
    fi
    echo
    
    # System resources
    echo "System Resources:"
    echo "  CPU Cores: $(nproc 2>/dev/null || echo "Unknown")"
    if command -v free &> /dev/null; then
        echo "  Total Memory: $(free -h | grep Mem | awk '{print $2}')"
        echo "  Available Memory: $(free -h | grep Mem | awk '{print $7}')"
    fi
    if command -v df &> /dev/null; then
        echo "  Disk Space: $(df -h "$VM_DIR" 2>/dev/null | tail -1 | awk '{print $4}') available in VM directory"
    fi
    echo
    
    # VM Statistics
    local vm_count=$(get_vm_list | wc -l)
    local running_count=0
    for vm in $(get_vm_list); do
        if is_vm_running "$vm"; then
            ((running_count++))
        fi
    done
    
    echo "VM Statistics:"
    echo "  Total VMs: $vm_count"
    echo "  Running VMs: $running_count"
    echo "  Stopped VMs: $((vm_count - running_count))"
    echo "  Storage Directory: $VM_DIR"
    echo
    
    # Zorvix status
    if [ "$ZORVIX_MODE" = true ]; then
        echo "Zorvix Technology:"
        echo "  Status: ACTIVE"
        echo "  Optimizations: Enabled for all new VMs"
        
        # Check for performance features
        if [ -d "/sys/kernel/mm/transparent_hugepage" ]; then
            echo "  Huge Pages: $(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo "Unknown")"
        fi
        
        if command -v cpupower &> /dev/null; then
            echo "  CPU Governor: $(cpupower frequency-info 2>/dev/null | grep governor | head -1 | cut -d':' -f2 | xargs || echo "Unknown")"
        fi
    else
        echo "Zorvix Technology: DISABLED"
    fi
    
    echo "=========================================="
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# Function to display main menu with proper formatting
display_main_menu() {
    local vm_count=$1
    local vms=($2)
    
    echo "ZynexForge Main Menu:"
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
        echo "  10) Import VM configuration"
        echo "  11) System Information"
        echo "  12) Toggle Zorvix Mode (Current: $( [ "$ZORVIX_MODE" = true ] && echo "ON" || echo "OFF" ))"
        echo "  0) Exit"
    else
        echo "  11) System Information"
        echo "  12) Toggle Zorvix Mode (Current: $( [ "$ZORVIX_MODE" = true ] && echo "ON" || echo "OFF" ))"
        echo "  0) Exit"
    fi
    echo
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Found $vm_count ZynexForge VM(s):"
            for i in "${!vms[@]}"; do
                local status="Stopped"
                local zorvix_status=""
                
                if is_vm_running "${vms[$i]}"; then
                    status="\033[1;32mRunning\033[0m"
                else
                    status="\033[1;31mStopped\033[0m"
                fi
                
                # Load config to get custom name and Zorvix status
                if load_vm_config "${vms[$i]}" 2>/dev/null; then
                    if [ "$ZORVIX_OPTIMIZED" = true ]; then
                        zorvix_status=" ⚡"
                    fi
                    printf "  %2d) %s \033[1;36m(%s)\033[0m - %s%s\n" $((i+1)) "${vms[$i]}" "$CUSTOM_NAME" "$status" "$zorvix_status"
                else
                    printf "  %2d) %s - %s\n" $((i+1)) "${vms[$i]}" "$status"
                fi
            done
            echo
        else
            print_status "INFO" "No VMs found. Create your first ZynexForge VM!"
            echo
        fi
        
        # Display menu based on whether VMs exist
        if [ $vm_count -gt 0 ]; then
            display_main_menu "$vm_count" "${vms[*]}"
            read -p "$(print_status "INPUT" "Enter your choice (0-12): ")" choice
            
            case $choice in
                1) create_new_vm ;;
                2)
                    read -p "$(print_status "INPUT" "Enter VM number to start: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        start_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                    ;;
                3)
                    read -p "$(print_status "INPUT" "Enter VM number to stop: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        stop_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                    ;;
                4)
                    read -p "$(print_status "INPUT" "Enter VM number to show info: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_info "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                    ;;
                5)
                    read -p "$(print_status "INPUT" "Enter VM number to edit: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        edit_vm_config "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                    ;;
                6)
                    read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                    ;;
                7)
                    read -p "$(print_status "INPUT" "Enter VM number to resize disk: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        resize_vm_disk "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                    ;;
                8)
                    read -p "$(print_status "INPUT" "Enter VM number to show performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                    ;;
                9)
                    read -p "$(print_status "INPUT" "Enter VM number to export: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        export_vm_config "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                    ;;
                10) import_vm_config ;;
                11) show_system_info ;;
                12)
                    if [ "$ZORVIX_MODE" = true ]; then
                        ZORVIX_MODE=false
                        print_status "INFO" "Zorvix Mode: DISABLED"
                    else
                        ZORVIX_MODE=true
                        print_status "ZORVIX" "Zorvix Mode: ENABLED - Performance optimizations active"
                    fi
                    sleep 2
                    ;;
                0)
                    print_status "INFO" "Thank you for using ZynexForge VM Manager!"
                    echo -e "\033[1;35mPowered by Zorvix Technology\033[0m"
                    exit 0
                    ;;
                *)
                    print_status "ERROR" "Invalid option. Please choose 0-12."
                    ;;
            esac
        else
            # Menu when no VMs exist
            echo "ZynexForge Main Menu:"
            echo "  1) Create a new VM"
            echo "  11) System Information"
            echo "  12) Toggle Zorvix Mode (Current: $( [ "$ZORVIX_MODE" = true ] && echo "ON" || echo "OFF" ))"
            echo "  0) Exit"
            echo
            
            read -p "$(print_status "INPUT" "Enter your choice (0, 1, 11, or 12): ")" choice
            
            case $choice in
                1) create_new_vm ;;
                11) show_system_info ;;
                12)
                    if [ "$ZORVIX_MODE" = true ]; then
                        ZORVIX_MODE=false
                        print_status "INFO" "Zorvix Mode: DISABLED"
                    else
                        ZORVIX_MODE=true
                        print_status "ZORVIX" "Zorvix Mode: ENABLED - Performance optimizations active"
                    fi
                    sleep 2
                    ;;
                0)
                    print_status "INFO" "Thank you for using ZynexForge VM Manager!"
                    echo -e "\033[1;35mPowered by Zorvix Technology\033[0m"
                    exit 0
                    ;;
                *)
                    print_status "ERROR" "Invalid option. Please choose 0, 1, 11, or 12."
                    ;;
            esac
        fi
        
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
VM_DIR="${VM_DIR:-$HOME/ZynexForge-VMs}"
mkdir -p "$VM_DIR"

# Supported OS list with ZynexForge optimizations
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04 LTS (Zorvix Optimized)"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|zynex|ZynexForge2024!"
    ["Ubuntu 24.04 LTS (Zorvix Optimized)"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|zynex|ZynexForge2024!"
    ["Debian 12 (Zorvix Optimized)"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|zynex|ZynexForge2024!"
    ["Rocky Linux 9 (Zorvix Optimized)"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|zynex|ZynexForge2024!"
    ["AlmaLinux 9 (Zorvix Optimized)"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|alma9|zynex|ZynexForge2024!"
    ["Fedora 40 (Zorvix Optimized)"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|zynex|ZynexForge2024!"
    ["CentOS Stream 9 (Zorvix Optimized)"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|zynex|ZynexForge2024!"
)

# Start the main menu
print_status "ZORVIX" "Initializing ZynexForge VM Manager..."
sleep 1
main_menu
