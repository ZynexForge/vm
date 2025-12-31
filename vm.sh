#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge VM Manager
# Simple Working Version
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
                                                                         

                    ⚡ ZynexForge VM Manager ⚡
                    Simple Working Version
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
        *) echo "[$type] $message" ;;
    esac
}

# Function to check dependencies
check_dependencies() {
    local deps=("qemu-system-x86_64" "qemu-img")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "On Ubuntu/Debian, try: sudo apt install qemu-system"
        exit 1
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
IMG_FILE="$IMG_FILE"
DISK_FILE="$DISK_FILE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
CREATED="$CREATED"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating a new VM"
    
    # Simple OS Selection
    echo "Select OS type:"
    echo "  1) Ubuntu/Debian Cloud Image (fast)"
    echo "  2) Proxmox VE (ISO installation)"
    echo "  3) Other Linux ISO"
    
    read -p "$(print_status "INPUT" "Enter your choice (1-3): ")" os_choice
    
    case $os_choice in
        1)
            OS_TYPE="ubuntu"
            IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
            DEFAULT_HOSTNAME="ubuntu-vm"
            DEFAULT_USERNAME="ubuntu"
            DEFAULT_PASSWORD="ubuntu"
            ;;
        2)
            OS_TYPE="proxmox"
            IMG_URL="https://download.proxmox.com/iso/proxmox-ve_8.2-1.iso"
            DEFAULT_HOSTNAME="proxmox-vm"
            DEFAULT_USERNAME="root"
            DEFAULT_PASSWORD="proxmox123"
            ;;
        3)
            OS_TYPE="linux"
            read -p "$(print_status "INPUT" "Enter ISO URL: ")" IMG_URL
            DEFAULT_HOSTNAME="linux-vm"
            DEFAULT_USERNAME="user"
            DEFAULT_PASSWORD="password"
            ;;
        *)
            print_status "ERROR" "Invalid selection"
            return 1
            ;;
    esac

    # Get VM name
    read -p "$(print_status "INPUT" "Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
    VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
    
    # Check if VM already exists
    if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
        print_status "ERROR" "VM with name '$VM_NAME' already exists"
        return 1
    fi

    # Simple configuration
    MEMORY="4096"
    CPUS="2"
    SSH_PORT="2222"
    GUI_MODE=false
    CREATED="$(date)"
    
    # Set up files
    if [[ "$OS_TYPE" == "proxmox" || "$OS_TYPE" == "linux" ]]; then
        # ISO installation
        IMG_FILE="$VM_DIR/$VM_NAME.iso"
        DISK_FILE="$VM_DIR/$VM_NAME.qcow2"
        
        # Download ISO if needed
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "INFO" "Downloading ISO..."
            wget --no-check-certificate -O "$IMG_FILE" "$IMG_URL" || {
                print_status "ERROR" "Failed to download ISO"
                return 1
            }
        fi
        
        # Create disk
        if [[ ! -f "$DISK_FILE" ]]; then
            print_status "INFO" "Creating 32GB disk..."
            qemu-img create -f qcow2 "$DISK_FILE" 32G
        fi
    else
        # Cloud image
        IMG_FILE="$VM_DIR/$VM_NAME.qcow2"
        DISK_FILE="$IMG_FILE"
        
        # Download cloud image if needed
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "INFO" "Downloading cloud image..."
            wget --no-check-certificate -O "$IMG_FILE" "$IMG_URL" || {
                print_status "ERROR" "Failed to download image"
                return 1
            }
            # Resize disk
            qemu-img resize "$IMG_FILE" 20G
        fi
    fi
    
    # Save configuration
    save_vm_config
    print_status "SUCCESS" "VM '$VM_NAME' created successfully!"
}

# Function to start a VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $vm_name"
        
        # Check if files exist
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "Image file not found: $IMG_FILE"
            return 1
        fi
        
        # Build QEMU command based on file type
        local qemu_cmd=(
            qemu-system-x86_64
            -enable-kvm
            -m "$MEMORY"
            -smp "$CPUS"
            -cpu host
        )
        
        # Check if it's an ISO file
        if [[ "$IMG_FILE" == *.iso ]] || file "$IMG_FILE" | grep -q "ISO 9660"; then
            print_status "INFO" "Booting from ISO installation media"
            
            # For Proxmox, provide installation instructions
            if [[ "$IMG_FILE" == *"proxmox"* ]]; then
                echo "=========================================="
                echo "PROXMOX VE INSTALLATION:"
                echo "1. Select 'Install Proxmox VE'"
                echo "2. Accept agreements"
                echo "3. Choose disk: Select the VirtIO disk"
                echo "4. Set country, timezone, keyboard"
                echo "5. Set password: $DEFAULT_PASSWORD"
                echo "6. Use default settings for network"
                echo "7. Confirm installation"
                echo "8. After reboot, access at: https://localhost:8006"
                echo "=========================================="
            fi
            
            # Add ISO and disk
            qemu_cmd+=(
                -drive "file=$DISK_FILE,format=qcow2,if=virtio"
                -cdrom "$IMG_FILE"
                -boot order=d
            )
        else
            # Cloud image
            print_status "INFO" "Booting cloud image"
            qemu_cmd+=(
                -drive "file=$IMG_FILE,format=qcow2,if=virtio"
                -boot order=c
            )
        fi
        
        # Add network
        qemu_cmd+=(
            -device virtio-net-pci,netdev=net0
            -netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22"
        )
        
        # Add display
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga virtio -display gtk)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi
        
        # Add some performance options
        qemu_cmd+=(
            -device virtio-balloon-pci
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
        )
        
        print_status "INFO" "Starting QEMU..."
        echo "Command: qemu-system-x86_64 -enable-kvm -m $MEMORY -smp $CPUS ..."
        echo
        
        # Run QEMU
        "${qemu_cmd[@]}"
        
        print_status "INFO" "VM $vm_name has stopped"
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo
        print_status "INFO" "VM Information: $vm_name"
        echo "========================================"
        echo "Memory: $MEMORY MB"
        echo "CPUs: $CPUS"
        echo "SSH Port: $SSH_PORT"
        echo "GUI Mode: $GUI_MODE"
        echo "Created: $CREATED"
        echo "Image: $(basename "$IMG_FILE")"
        echo "Disk: $(basename "$DISK_FILE")"
        
        # Check file type
        if [[ "$IMG_FILE" == *.iso ]] || (command -v file >/dev/null && file "$IMG_FILE" | grep -q "ISO 9660"); then
            echo "Type: ISO Installation"
        else
            echo "Type: Cloud Image"
        fi
        
        # Check if running
        if pgrep -f "qemu-system-x86_64.*$(basename "$IMG_FILE")" >/dev/null; then
            echo "Status: Running"
        else
            echo "Status: Stopped"
        fi
        echo "========================================"
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "This will delete VM '$vm_name' and all its data!"
    read -p "$(print_status "INPUT" "Are you sure? (y/N): ")" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if load_vm_config "$vm_name" 2>/dev/null; then
            rm -f "$IMG_FILE" "$DISK_FILE" "$VM_DIR/$vm_name.conf"
            print_status "SUCCESS" "VM '$vm_name' deleted"
        else
            rm -f "$VM_DIR/$vm_name.iso" "$VM_DIR/$vm_name.qcow2" "$VM_DIR/$vm_name.conf" 2>/dev/null
            print_status "SUCCESS" "VM '$vm_name' files deleted"
        fi
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

# Function to stop a VM
stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name" 2>/dev/null; then
        if pgrep -f "qemu-system-x86_64.*$(basename "$IMG_FILE")" >/dev/null; then
            print_status "INFO" "Stopping VM: $vm_name"
            pkill -f "qemu-system-x86_64.*$(basename "$IMG_FILE")"
            sleep 2
            if pgrep -f "qemu-system-x86_64.*$(basename "$IMG_FILE")" >/dev/null; then
                pkill -9 -f "qemu-system-x86_64.*$(basename "$IMG_FILE")"
            fi
            print_status "SUCCESS" "VM stopped"
        else
            print_status "INFO" "VM is not running"
        fi
    fi
}

# Function to fix Proxmox VM
fix_proxmox_vm() {
    local vm_name="$1"
    
    print_status "INFO" "Fixing Proxmox VM: $vm_name"
    
    # Load config if it exists
    if [[ -f "$VM_DIR/$vm_name.conf" ]]; then
        source "$VM_DIR/$vm_name.conf"
    fi
    
    # Check if we have an .img file that's actually an ISO
    local img_file="$VM_DIR/$vm_name.img"
    local iso_file="$VM_DIR/$vm_name.iso"
    local disk_file="$VM_DIR/$vm_name.qcow2"
    
    if [[ -f "$img_file" ]]; then
        # Check if it's an ISO
        if file "$img_file" 2>/dev/null | grep -q "ISO 9660"; then
            print_status "INFO" "Found ISO file with .img extension"
            mv "$img_file" "$iso_file"
            IMG_FILE="$iso_file"
        fi
    fi
    
    # Create disk if needed
    if [[ ! -f "$disk_file" ]]; then
        print_status "INFO" "Creating 32GB disk for installation..."
        qemu-img create -f qcow2 "$disk_file" 32G
        DISK_FILE="$disk_file"
    fi
    
    # Set defaults for Proxmox
    MEMORY="${MEMORY:-4096}"
    CPUS="${CPUS:-2}"
    SSH_PORT="${SSH_PORT:-2222}"
    GUI_MODE="${GUI_MODE:-false}"
    
    # Save fixed configuration
    cat > "$VM_DIR/$vm_name.conf" <<EOF
VM_NAME="$vm_name"
IMG_FILE="$IMG_FILE"
DISK_FILE="$DISK_FILE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
CREATED="$(date)"
EOF
    
    print_status "SUCCESS" "Proxmox VM fixed: $vm_name"
    show_vm_info "$vm_name"
}

# Main menu
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Found $vm_count VM(s):"
            for i in "${!vms[@]}"; do
                local status="Stopped"
                if pgrep -f "qemu-system-x86_64.*${vms[$i]}" >/dev/null; then
                    status="Running"
                fi
                printf "  %2d) %s (%s)\n" $((i+1)) "${vms[$i]}" "$status"
            done
            echo
        fi
        
        echo "Main Menu:"
        echo "  1) Create new VM"
        if [ $vm_count -gt 0 ]; then
            echo "  2) Start VM"
            echo "  3) Stop VM"
            echo "  4) VM Info"
            echo "  5) Delete VM"
            echo "  6) Fix Proxmox VM"
        fi
        echo "  0) Exit"
        echo
        
        read -p "$(print_status "INPUT" "Enter choice: ")" choice
        
        case $choice in
            1)
                create_new_vm
                ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        start_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        stop_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            4)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_info "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to fix: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        fix_proxmox_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
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

# Check dependencies
check_dependencies

# Initialize paths
VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

# Start main menu
main_menu
