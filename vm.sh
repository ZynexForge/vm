#!/bin/bash
set -euo pipefail

# =============================
# ZynexForge VM Manager - Simplified
# =============================

# Branding Configuration
BRAND_NAME="ZynexForge"
BRAND_VERSION="2.0"
ZORVIX_MODE=true

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
                    Auto-Configured for Performance
========================================================================
EOF
    echo -e "\033[1;36m$BRAND_NAME v$BRAND_VERSION | 24GB RAM | 8 Cores | 500GB Disk\033[0m"
    echo -e "\033[1;33mHost: KVM/QEMU (Standard PC (i440FX + PIIX, 1996))\033[0m"
    echo -e "\033[1;35mPerformance Mode: ZORVIX OPTIMIZED\033[0m"
    echo "========================================================================="
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
    esac
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
        print_status "ERROR" "Missing: ${missing_deps[*]}"
        print_status "INFO" "Install: sudo apt install qemu-system cloud-image-utils wget"
        exit 1
    fi
}

# Function to cleanup
cleanup() {
    rm -f user-data meta-data network-config 2>/dev/null
}

# Function to get VM list
get_vm_list() {
    find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

# Function to load VM config
load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf"
    
    if [[ -f "$config_file" ]]; then
        source "$config_file"
        return 0
    else
        print_status "ERROR" "VM '$vm_name' not found"
        return 1
    fi
}

# Function to save VM config
save_vm_config() {
    local config_file="$VM_DIR/$VM_NAME.conf"
    
    cat > "$config_file" <<EOF
VM_NAME="$VM_NAME"
OS_TYPE="$OS_TYPE"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
EOF
    
    print_status "SUCCESS" "Config saved"
}

# Function to create new VM
create_new_vm() {
    display_header
    print_status "INFO" "Creating new VM with recommended settings:"
    print_status "PERF" "• 24GB RAM • 8 Cores • 500GB Disk"
    echo
    
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
    echo "Select OS:"
    echo "  1) Ubuntu 22.04 LTS"
    echo "  2) Ubuntu 24.04 LTS"
    echo "  3) Debian 12"
    echo "  4) Rocky Linux 9"
    echo "  5) Fedora 40"
    
    while true; do
        read -p "$(print_status "INPUT" "Choice (1-5): ")" choice
        case $choice in
            1)
                OS_TYPE="ubuntu22"
                IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
                break
                ;;
            2)
                OS_TYPE="ubuntu24"
                IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
                break
                ;;
            3)
                OS_TYPE="debian12"
                IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
                break
                ;;
            4)
                OS_TYPE="rocky9"
                IMG_URL="https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
                break
                ;;
            5)
                OS_TYPE="fedora40"
                IMG_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2"
                break
                ;;
            *)
                print_status "ERROR" "Invalid choice"
                ;;
        esac
    done
    
    # Set recommended defaults
    HOSTNAME="$VM_NAME"
    USERNAME="admin"
    PASSWORD="ZynexForge2024!"
    
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
    
    # Resize disk to 500GB
    print_status "INFO" "Resizing disk to 500GB..."
    qemu-img resize "$IMG_FILE" 500G >/dev/null 2>&1
    
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
    password: $(echo "$PASSWORD" | openssl passwd -6 -stdin)
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
runcmd:
  - apt-get update && apt-get upgrade -y 2>/dev/null || true
  - dnf update -y 2>/dev/null || true
EOF
    
    cat > meta-data <<EOF
instance-id: $VM_NAME
local-hostname: $HOSTNAME
EOF
    
    # Create seed image
    print_status "INFO" "Creating cloud-init config..."
    if cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "SUCCESS" "VM '$VM_NAME' created!"
        save_vm_config
    else
        print_status "ERROR" "Failed to create seed image"
        return 1
    fi
}

# Function to start VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $vm_name"
        print_status "INFO" "SSH: ssh $USERNAME@localhost -p 2222"
        print_status "INFO" "Password: $PASSWORD"
        
        # Check files exist
        if [[ ! -f "$IMG_FILE" ]] || [[ ! -f "$SEED_FILE" ]]; then
            print_status "ERROR" "VM files missing"
            return 1
        fi
        
        # Start VM with optimized settings
        print_status "PERF" "Starting with 24GB RAM, 8 cores..."
        
        qemu-system-x86_64 \
            -enable-kvm \
            -machine q35,accel=kvm \
            -cpu host \
            -smp 8,sockets=1,cores=8,threads=1 \
            -m 24G \
            -drive file="$IMG_FILE",format=qcow2,if=virtio,cache=writeback \
            -drive file="$SEED_FILE",format=raw,if=virtio \
            -netdev user,id=n0,hostfwd=tcp::2222-:22 \
            -device virtio-net-pci,netdev=n0 \
            -device virtio-balloon-pci \
            -nographic \
            -serial mon:stdio &
        
        echo $! > "$VM_DIR/$vm_name.pid"
        print_status "SUCCESS" "VM started (PID: $(cat "$VM_DIR/$vm_name.pid"))"
    fi
}

# Function to stop VM
stop_vm() {
    local vm_name=$1
    
    if [ -f "$VM_DIR/$vm_name.pid" ]; then
        local pid=$(cat "$VM_DIR/$vm_name.pid")
        print_status "INFO" "Stopping VM..."
        kill "$pid" 2>/dev/null
        sleep 2
        rm -f "$VM_DIR/$vm_name.pid"
        print_status "SUCCESS" "VM stopped"
    else
        print_status "INFO" "VM not running"
    fi
}

# Function to delete VM
delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "Delete VM '$vm_name'? (y/N): "
    read -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        stop_vm "$vm_name"
        rm -f "$VM_DIR/$vm_name.conf" "$VM_DIR/$vm_name.img" "$VM_DIR/$vm_name-seed.iso" 2>/dev/null
        print_status "SUCCESS" "VM deleted"
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo
        echo "=== VM Information ==="
        echo "Name:       $VM_NAME"
        echo "OS:         $OS_TYPE"
        echo "Hostname:   $HOSTNAME"
        echo "Username:   $USERNAME"
        echo "SSH Port:   2222"
        echo "Created:    $CREATED"
        echo "Resources:  24GB RAM, 8 cores, 500GB disk"
        echo
        if [ -f "$VM_DIR/$vm_name.pid" ]; then
            echo "Status:     RUNNING"
        else
            echo "Status:     STOPPED"
        fi
        echo "======================"
        echo
    fi
}

# Main menu
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Your VMs ($vm_count):"
            for i in "${!vms[@]}"; do
                if [ -f "$VM_DIR/${vms[$i]}.pid" ]; then
                    echo "  $((i+1))) ${vms[$i]} 🟢 RUNNING"
                else
                    echo "  $((i+1))) ${vms[$i]} 🔴 STOPPED"
                fi
            done
            echo
        fi
        
        echo "=== Menu ==="
        echo "1) Create VM"
        if [ $vm_count -gt 0 ]; then
            echo "2) Start VM"
            echo "3) Stop VM"
            echo "4) VM Info"
            echo "5) Delete VM"
        fi
        echo "0) Exit"
        echo "==========="
        echo
        
        read -p "$(print_status "INPUT" "Choice: ")" choice
        
        case $choice in
            1)
                create_new_vm
                ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "VM number to start: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        start_vm "${vms[$((vm_num-1))]}"
                    fi
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "VM number to stop: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        stop_vm "${vms[$((vm_num-1))]}"
                    fi
                fi
                ;;
            4)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "VM number for info: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_info "${vms[$((vm_num-1))]}"
                    fi
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    fi
                fi
                ;;
            0)
                print_status "INFO" "Goodbye!"
                exit 0
                ;;
            *)
                print_status "ERROR" "Invalid choice"
                ;;
        esac
        
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

# Initialize
trap cleanup EXIT
check_dependencies
VM_DIR="${VM_DIR:-$HOME/ZynexForge-VMs}"
mkdir -p "$VM_DIR"

# Start
main_menu
