#!/bin/bash
set -euo pipefail

# ============================================================
# Advanced VM Manager - Fixed UI Edition
# ============================================================

# Global Configuration
SCRIPT_VERSION="2.3"
BASE_DIR="${BASE_DIR:-$HOME/vm-manager}"
VM_DIR="$BASE_DIR/vms"
CONFIG_DIR="$BASE_DIR/configs"
LOG_DIR="$BASE_DIR/logs"
ISO_DIR="$BASE_DIR/isos"
TEMP_DIR="/tmp/vm-manager-$$"

# Simple colors (no complex formatting)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# CPU Models Database
declare -A CPU_MODELS=(
    # AMD Ryzen Desktop
    ["AMD_RYZEN_9_7950X"]="EPYC-Genoa"
    ["AMD_RYZEN_9_7900X"]="EPYC-Genoa"
    ["AMD_RYZEN_9_5950X"]="EPYC-Rome"
    ["AMD_RYZEN_9_5900X"]="EPYC-Rome"
    ["AMD_RYZEN_7_7800X3D"]="EPYC-Genoa"
    ["AMD_RYZEN_7_7700X"]="EPYC-Genoa"
    ["AMD_RYZEN_7_5800X3D"]="EPYC-Rome"
    ["AMD_RYZEN_7_5800X"]="EPYC-Rome"
    ["AMD_RYZEN_5_7600X"]="EPYC-Genoa"
    ["AMD_RYZEN_5_5600X"]="EPYC-Rome"
    
    # AMD EPYC Server
    ["AMD_EPYC_GENOA"]="EPYC-Genoa"
    ["AMD_EPYC_MILAN"]="EPYC-Milan"
    ["AMD_EPYC_ROME"]="EPYC-Rome"
    ["AMD_EPYC_NAPLES"]="EPYC"
    
    # Intel
    ["INTEL_PLATINUM_8380"]="Cascadelake-Server"
    ["INTEL_PLATINUM_8375C"]="Icelake-Server"
    ["INTEL_XEON_GOLD_6348"]="Cascadelake-Server"
    ["INTEL_CORE_i9_14900K"]="Skylake-Client"
    ["INTEL_CORE_i7_14700K"]="Skylake-Client"
    ["INTEL_CORE_i5_14600K"]="Skylake-Client"
    
    # Generic
    ["HOST_PASSTHROUGH"]="host"
    ["MAX_PERFORMANCE"]="max"
    ["QEMU64"]="qemu64"
)

# OS Images
declare -A OS_IMAGES=(
    ["Ubuntu 22.04 LTS"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    ["Ubuntu 24.04 LTS"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
    ["Rocky Linux 9"]="rocky|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
)

# ============================================================
# Display Functions
# ============================================================

show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
__________                             ___________                         
\____    /___.__. ____   ____ ___  ___ \_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /  |    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    <   |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \  \___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/      \/             /_____/      \/ 
EOF
    echo -e "${NC}"
    echo -e "Advanced VM Manager v${SCRIPT_VERSION}"
    echo -e "=================================================\n"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# ============================================================
# System Functions
# ============================================================

init_environment() {
    mkdir -p "$VM_DIR" "$CONFIG_DIR" "$LOG_DIR" "$ISO_DIR"
    mkdir -p "$TEMP_DIR"
    chmod 700 "$BASE_DIR"
}

cleanup() {
    rm -rf "$TEMP_DIR"
}

check_dependencies() {
    local deps=("qemu-system-x86_64" "qemu-img" "wget" "cloud-localds")
    local missing=()
    
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing[*]}"
        print_info "Install with: sudo apt install qemu-system qemu-utils cloud-image-utils wget"
        return 1
    fi
    return 0
}

# ============================================================
# Menu Functions
# ============================================================

show_menu() {
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║                 MAIN MENU                           ║"
    echo "╠══════════════════════════════════════════════════════╣"
    echo "║                                                      ║"
    echo "║   1) Create New VM                                  ║"
    echo "║   2) List VMs                                       ║"
    echo "║   3) Start VM                                       ║"
    echo "║   4) Stop VM                                        ║"
    echo "║   5) Delete VM                                      ║"
    echo "║   6) VM Information                                 ║"
    echo "║   7) Hardware Info                                  ║"
    echo "║   8) Exit                                           ║"
    echo "║                                                      ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo
}

get_menu_choice() {
    local choice
    while true; do
        echo -n "Select option (1-8): "
        read -r choice
        
        # Remove any extra spaces
        choice=$(echo "$choice" | tr -d '[:space:]')
        
        if [[ "$choice" =~ ^[1-8]$ ]]; then
            echo "$choice"
            return
        else
            print_error "Invalid option. Please enter a number between 1 and 8."
            echo
        fi
    done
}

# ============================================================
# Hardware Detection
# ============================================================

detect_hardware() {
    echo -e "\n=== HARDWARE INFORMATION ===\n"
    
    # CPU Info
    if grep -q "AuthenticAMD" /proc/cpuinfo; then
        CPU_VENDOR="AMD"
        print_info "CPU Vendor: AMD"
    elif grep -q "GenuineIntel" /proc/cpuinfo; then
        CPU_VENDOR="Intel"
        print_info "CPU Vendor: Intel"
    else
        CPU_VENDOR="Unknown"
        print_warn "CPU Vendor: Unknown"
    fi
    
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
    print_info "CPU Model: $CPU_MODEL"
    
    # KVM Check
    if [[ -e /dev/kvm ]]; then
        KVM_AVAILABLE=true
        if lsmod | grep -q "kvm_amd"; then
            print_success "AMD KVM Available"
        elif lsmod | grep -q "kvm_intel"; then
            print_success "Intel KVM Available"
        fi
    else
        KVM_AVAILABLE=false
        print_warn "KVM not available - will use TCG emulation"
    fi
    
    # Memory Info
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    print_info "Total Memory: ${TOTAL_MEM}MB"
    
    echo
    read -p "Press Enter to continue..."
}

# ============================================================
# VM Creation
# ============================================================

create_vm() {
    show_banner
    print_info "Creating new VM"
    echo
    
    # VM Name
    local vm_name
    while true; do
        read -p "Enter VM name: " vm_name
        if [[ -n "$vm_name" ]]; then
            if [[ -f "$CONFIG_DIR/$vm_name.conf" ]]; then
                print_error "VM '$vm_name' already exists"
            else
                break
            fi
        else
            print_error "VM name cannot be empty"
        fi
    done
    
    # OS Selection
    echo -e "\n=== OS SELECTION ==="
    local i=1
    local os_names=()
    
    for os in "${!OS_IMAGES[@]}"; do
        echo "  $i) $os"
        os_names[$i]="$os"
        ((i++))
    done
    
    local os_choice
    while true; do
        read -p "Select OS (1-$((i-1))): " os_choice
        if [[ "$os_choice" =~ ^[0-9]+$ ]] && [[ $os_choice -ge 1 ]] && [[ $os_choice -lt $i ]]; then
            SELECTED_OS="${os_names[$os_choice]}"
            IFS='|' read -r OS_TYPE OS_CODENAME IMG_URL <<< "${OS_IMAGES[$SELECTED_OS]}"
            break
        fi
        print_error "Invalid selection"
    done
    
    # Resource Configuration
    echo -e "\n=== RESOURCE CONFIGURATION ==="
    
    # Memory
    local memory
    while true; do
        read -p "Memory in MB (default: 4096): " memory
        memory="${memory:-4096}"
        if [[ "$memory" =~ ^[0-9]+$ ]] && [[ $memory -gt 0 ]]; then
            break
        fi
        print_error "Must be a positive number"
    done
    
    # CPU Cores
    local cpus
    while true; do
        read -p "CPU cores (default: 4): " cpus
        cpus="${cpus:-4}"
        if [[ "$cpus" =~ ^[0-9]+$ ]] && [[ $cpus -gt 0 ]]; then
            break
        fi
        print_error "Must be a positive number"
    done
    
    # Disk Size
    local disk_size
    while true; do
        read -p "Disk size (e.g., 50G, default: 50G): " disk_size
        disk_size="${disk_size:-50G}"
        if [[ "$disk_size" =~ ^[0-9]+[GgMm]$ ]]; then
            break
        fi
        print_error "Must be a size with unit (e.g., 50G, 100M)"
    done
    
    # Network
    echo -e "\n=== NETWORK CONFIGURATION ==="
    echo "  1) User-mode NAT (Default)"
    echo "  2) Bridge networking"
    
    local net_choice
    while true; do
        read -p "Select network type (1-2): " net_choice
        case $net_choice in
            1)
                NET_TYPE="user"
                local ssh_port
                while true; do
                    read -p "SSH port (default: 2222): " ssh_port
                    ssh_port="${ssh_port:-2222}"
                    if [[ "$ssh_port" =~ ^[0-9]+$ ]] && [[ $ssh_port -ge 1024 ]] && [[ $ssh_port -le 65535 ]]; then
                        # Check if port is in use
                        if ss -tln 2>/dev/null | grep -q ":$ssh_port "; then
                            print_error "Port $ssh_port is already in use"
                        else
                            SSH_PORT="$ssh_port"
                            break
                        fi
                    else
                        print_error "Port must be between 1024 and 65535"
                    fi
                done
                break
                ;;
            2)
                NET_TYPE="bridge"
                read -p "Bridge interface (default: br0): " BRIDGE_IFACE
                BRIDGE_IFACE="${BRIDGE_IFACE:-br0}"
                SSH_PORT=""
                break
                ;;
            *)
                print_error "Invalid selection"
                ;;
        esac
    done
    
    # CPU Selection
    echo -e "\n=== CPU SELECTION ==="
    
    # Group CPUs
    declare -A cpu_groups
    cpu_groups["AMD Ryzen"]="AMD_RYZEN_9_7950X AMD_RYZEN_9_7900X AMD_RYZEN_9_5950X AMD_RYZEN_9_5900X AMD_RYZEN_7_7800X3D AMD_RYZEN_7_7700X AMD_RYZEN_7_5800X3D AMD_RYZEN_7_5800X AMD_RYZEN_5_7600X AMD_RYZEN_5_5600X"
    cpu_groups["AMD EPYC"]="AMD_EPYC_GENOA AMD_EPYC_MILAN AMD_EPYC_ROME AMD_EPYC_NAPLES"
    cpu_groups["Intel"]="INTEL_PLATINUM_8380 INTEL_PLATINUM_8375C INTEL_XEON_GOLD_6348 INTEL_CORE_i9_14900K INTEL_CORE_i7_14700K INTEL_CORE_i5_14600K"
    cpu_groups["Generic"]="HOST_PASSTHROUGH MAX_PERFORMANCE QEMU64"
    
    local i=1
    declare -A cpu_map
    
    for group in "AMD Ryzen" "AMD EPYC" "Intel" "Generic"; do
        echo -e "\n$group:"
        for cpu in ${cpu_groups[$group]}; do
            printf "  %2d) %s\n" "$i" "$cpu"
            cpu_map[$i]="$cpu"
            ((i++))
        done
    done
    
    local cpu_choice
    while true; do
        read -p "Select CPU model (1-$((i-1))): " cpu_choice
        if [[ "$cpu_choice" =~ ^[0-9]+$ ]] && [[ $cpu_choice -ge 1 ]] && [[ $cpu_choice -lt $i ]]; then
            SELECTED_CPU="${cpu_map[$cpu_choice]}"
            CPU_MODEL="${CPU_MODELS[$SELECTED_CPU]}"
            break
        fi
        print_error "Invalid selection"
    done
    
    # User Configuration
    echo -e "\n=== USER CONFIGURATION ==="
    
    local username
    read -p "Username (default: user): " username
    username="${username:-user}"
    
    local password
    while true; do
        read -s -p "Password: " password
        echo
        if [[ -n "$password" ]]; then
            break
        fi
        print_error "Password cannot be empty"
    done
    
    # GPU Configuration
    echo -e "\n=== GPU CONFIGURATION ==="
    echo "  1) VirtIO-GPU (Recommended)"
    echo "  2) QXL"
    echo "  3) None"
    
    local gpu_choice
    while true; do
        read -p "Select GPU type (1-3): " gpu_choice
        case $gpu_choice in
            1) VGPU_TYPE="virtio"; break ;;
            2) VGPU_TYPE="qxl"; break ;;
            3) VGPU_TYPE="none"; break ;;
            *) print_error "Invalid selection" ;;
        esac
    done
    
    # Create VM
    print_info "Creating VM '$vm_name'..."
    
    # Create configuration
    local config_file="$CONFIG_DIR/$vm_name.conf"
    cat > "$config_file" <<EOF
VM_NAME="$vm_name"
OS_TYPE="$OS_TYPE"
OS_CODENAME="$OS_CODENAME"
IMG_URL="$IMG_URL"
VM_MEMORY="$memory"
VM_CPUS="$cpus"
DISK_SIZE="$disk_size"
NET_TYPE="$NET_TYPE"
SSH_PORT="$SSH_PORT"
BRIDGE_IFACE="$BRIDGE_IFACE"
USERNAME="$username"
PASSWORD="$password"
SELECTED_CPU="$SELECTED_CPU"
CPU_MODEL="$CPU_MODEL"
VGPU_TYPE="$VGPU_TYPE"
CREATED="$(date)"
EOF
    
    # Download image if needed
    local image_file="$ISO_DIR/${OS_TYPE}-${OS_CODENAME}.qcow2"
    if [[ ! -f "$image_file" ]]; then
        print_info "Downloading OS image..."
        wget -q --show-progress -O "$image_file.tmp" "$IMG_URL"
        mv "$image_file.tmp" "$image_file"
    fi
    
    # Create VM disk
    local vm_disk="$VM_DIR/$vm_name.qcow2"
    print_info "Creating disk image..."
    qemu-img create -f qcow2 -b "$image_file" -F qcow2 "$vm_disk" "$disk_size"
    
    # Create cloud-init seed
    local seed_file="$VM_DIR/$vm_name-seed.iso"
    local user_data="$TEMP_DIR/user-data"
    local meta_data="$TEMP_DIR/meta-data"
    
    cat > "$user_data" <<EOF
#cloud-config
hostname: $vm_name
users:
  - name: $username
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    password: $(openssl passwd -6 "$password" 2>/dev/null || echo "$password")
chpasswd:
  list: |
    root:$password
    $username:$password
  expire: false
EOF
    
    cat > "$meta_data" <<EOF
instance-id: $vm_name
local-hostname: $vm_name
EOF
    
    cloud-localds "$seed_file" "$user_data" "$meta_data"
    
    print_success "VM '$vm_name' created successfully!"
    
    # Show summary
    echo -e "\n=== VM SUMMARY ==="
    echo "Name: $vm_name"
    echo "OS: $SELECTED_OS"
    echo "Memory: ${memory}MB"
    echo "CPUs: $cpus"
    echo "Disk: $disk_size"
    echo "CPU Model: $SELECTED_CPU"
    echo "Network: $NET_TYPE"
    if [[ "$NET_TYPE" == "user" ]]; then
        echo "SSH Port: $SSH_PORT"
        echo "SSH Command: ssh -p $SSH_PORT $username@localhost"
    fi
    
    echo
    read -p "Press Enter to continue..."
}

# ============================================================
# VM Management
# ============================================================

list_vms() {
    show_banner
    echo -e "\n=== VIRTUAL MACHINES ===\n"
    
    local vms=($(find "$CONFIG_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        print_info "No VMs found"
        echo
        read -p "Press Enter to continue..."
        return
    fi
    
    echo "No.  Name              Status        OS"
    echo "────────────────────────────────────────────"
    
    local i=1
    for vm in "${vms[@]}"; do
        local config_file="$CONFIG_DIR/$vm.conf"
        if [[ -f "$config_file" ]]; then
            source "$config_file" 2>/dev/null
            
            # Check if running
            local status="Stopped"
            if pgrep -f "qemu-system.*$vm" &>/dev/null; then
                status="Running"
            fi
            
            printf "%2d)  %-15s  %-12s  %s\n" "$i" "$vm" "$status" "$SELECTED_OS"
            ((i++))
        fi
    done
    
    echo
    read -p "Press Enter to continue..."
}

start_vm() {
    list_vms
    echo
    
    local vms=($(find "$CONFIG_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        return
    fi
    
    local vm_num
    read -p "Enter VM number to start: " vm_num
    
    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [[ $vm_num -ge 1 ]] && [[ $vm_num -le ${#vms[@]} ]]; then
        local vm_name="${vms[$((vm_num-1))]}"
        
        # Check if already running
        if pgrep -f "qemu-system.*$vm_name" &>/dev/null; then
            print_error "VM '$vm_name' is already running"
            read -p "Press Enter to continue..."
            return
        fi
        
        # Load config
        local config_file="$CONFIG_DIR/$vm_name.conf"
        if [[ ! -f "$config_file" ]]; then
            print_error "VM configuration not found"
            return
        fi
        
        source "$config_file"
        
        local vm_disk="$VM_DIR/$vm_name.qcow2"
        local seed_file="$VM_DIR/$vm_name-seed.iso"
        
        if [[ ! -f "$vm_disk" ]]; then
            print_error "VM disk not found"
            return
        fi
        
        print_info "Starting VM '$vm_name'..."
        
        # Build QEMU command
        local qemu_cmd=(
            qemu-system-x86_64
            -name "$vm_name"
            -machine "type=q35,accel=kvm:tcg"
            -m "$VM_MEMORY"
            -smp "$VM_CPUS"
            -cpu "$CPU_MODEL"
            -drive "file=$vm_disk,format=qcow2,if=virtio"
            -drive "file=$seed_file,format=raw,if=virtio,readonly=on"
            -boot "order=c"
        )
        
        # Add network
        if [[ "$NET_TYPE" == "user" ]]; then
            qemu_cmd+=(-netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22")
            qemu_cmd+=(-device "virtio-net-pci,netdev=net0")
        elif [[ "$NET_TYPE" == "bridge" ]]; then
            qemu_cmd+=(-netdev "bridge,id=net0,br=$BRIDGE_IFACE")
            qemu_cmd+=(-device "virtio-net-pci,netdev=net0")
        fi
        
        # Add GPU
        if [[ "$VGPU_TYPE" == "virtio" ]]; then
            qemu_cmd+=(-device "virtio-gpu-pci" -display gtk)
        elif [[ "$VGPU_TYPE" == "qxl" ]]; then
            qemu_cmd+=(-device "qxl-vga" -display gtk)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi
        
        # Add other devices
        qemu_cmd+=(
            -device "virtio-balloon-pci"
            -object "rng-random,filename=/dev/urandom,id=rng0"
            -device "virtio-rng-pci,rng=rng0"
        )
        
        # Start VM
        "${qemu_cmd[@]}" &
        
        sleep 2
        
        if pgrep -f "qemu-system.*$vm_name" &>/dev/null; then
            print_success "VM '$vm_name' started"
            if [[ "$NET_TYPE" == "user" ]]; then
                echo "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
                echo "Password: $PASSWORD"
            fi
        else
            print_error "Failed to start VM"
        fi
        
        echo
        read -p "Press Enter to continue..."
    else
        print_error "Invalid selection"
        read -p "Press Enter to continue..."
    fi
}

stop_vm() {
    list_vms
    echo
    
    local vms=($(find "$CONFIG_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        return
    fi
    
    local vm_num
    read -p "Enter VM number to stop: " vm_num
    
    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [[ $vm_num -ge 1 ]] && [[ $vm_num -le ${#vms[@]} ]]; then
        local vm_name="${vms[$((vm_num-1))]}"
        
        print_info "Stopping VM '$vm_name'..."
        
        local pids=$(pgrep -f "qemu-system.*$vm_name")
        
        if [[ -z "$pids" ]]; then
            print_error "VM '$vm_name' is not running"
        else
            kill -TERM $pids 2>/dev/null
            sleep 2
            
            if pgrep -f "qemu-system.*$vm_name" &>/dev/null; then
                print_warn "VM did not stop gracefully, forcing..."
                pkill -9 -f "qemu-system.*$vm_name"
            fi
            
            print_success "VM '$vm_name' stopped"
        fi
        
        echo
        read -p "Press Enter to continue..."
    else
        print_error "Invalid selection"
        read -p "Press Enter to continue..."
    fi
}

delete_vm() {
    list_vms
    echo
    
    local vms=($(find "$CONFIG_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        return
    fi
    
    local vm_num
    read -p "Enter VM number to delete: " vm_num
    
    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [[ $vm_num -ge 1 ]] && [[ $vm_num -le ${#vms[@]} ]]; then
        local vm_name="${vms[$((vm_num-1))]}"
        
        read -p "Are you sure you want to delete '$vm_name'? (y/N): " confirm
        
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            # Stop if running
            local pids=$(pgrep -f "qemu-system.*$vm_name")
            if [[ -n "$pids" ]]; then
                kill -TERM $pids 2>/dev/null
                sleep 1
                pkill -9 -f "qemu-system.*$vm_name" 2>/dev/null
            fi
            
            # Delete files
            rm -f "$CONFIG_DIR/$vm_name.conf"
            rm -f "$VM_DIR/$vm_name.qcow2"
            rm -f "$VM_DIR/$vm_name-seed.iso"
            
            print_success "VM '$vm_name' deleted"
        else
            print_info "Deletion cancelled"
        fi
        
        echo
        read -p "Press Enter to continue..."
    else
        print_error "Invalid selection"
        read -p "Press Enter to continue..."
    fi
}

show_vm_info() {
    list_vms
    echo
    
    local vms=($(find "$CONFIG_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        return
    fi
    
    local vm_num
    read -p "Enter VM number for info: " vm_num
    
    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [[ $vm_num -ge 1 ]] && [[ $vm_num -le ${#vms[@]} ]]; then
        local vm_name="${vms[$((vm_num-1))]}"
        local config_file="$CONFIG_DIR/$vm_name.conf"
        
        if [[ -f "$config_file" ]]; then
            source "$config_file"
            
            show_banner
            echo -e "\n=== VM INFORMATION ===\n"
            
            # Status
            local status="Stopped"
            if pgrep -f "qemu-system.*$vm_name" &>/dev/null; then
                status="Running"
            fi
            
            echo "Name: $vm_name"
            echo "Status: $status"
            echo "Created: $CREATED"
            echo "OS: $SELECTED_OS"
            echo "CPU: $SELECTED_CPU ($VM_CPUS cores)"
            echo "Memory: $VM_MEMORY MB"
            echo "Disk: $DISK_SIZE"
            echo "Network: $NET_TYPE"
            
            if [[ "$NET_TYPE" == "user" ]]; then
                echo "SSH Port: $SSH_PORT"
                echo "Username: $USERNAME"
                echo "SSH Command: ssh -p $SSH_PORT $USERNAME@localhost"
            fi
            
            echo "GPU: $VGPU_TYPE"
            
            echo
            read -p "Press Enter to continue..."
        fi
    else
        print_error "Invalid selection"
        read -p "Press Enter to continue..."
    fi
}

# ============================================================
# Main Program
# ============================================================

main() {
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Initialize
    init_environment
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    # Main loop
    while true; do
        show_banner
        show_menu
        
        local choice
        choice=$(get_menu_choice)
        
        case $choice in
            1) create_vm ;;
            2) list_vms ;;
            3) start_vm ;;
            4) stop_vm ;;
            5) delete_vm ;;
            6) show_vm_info ;;
            7) detect_hardware ;;
            8)
                print_info "Goodbye!"
                exit 0
                ;;
        esac
    done
}

# Run the program
main
