#!/bin/bash
set -euo pipefail

# ============================================================
# Advanced VM Manager with GPU Passthrough & TUI
# ============================================================

# Global Configuration
SCRIPT_VERSION="2.0"
BASE_DIR="${BASE_DIR:-$HOME/vm-manager}"
VM_DIR="$BASE_DIR/vms"
CONFIG_DIR="$BASE_DIR/configs"
LOG_DIR="$BASE_DIR/logs"
ISO_DIR="$BASE_DIR/isos"
TEMP_DIR="/tmp/vm-manager-$$"

# Color and Display Configuration
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# CPU Configuration Database
declare -A CPU_MODELS=(
    ["INTEL_SKYLAKE"]="Skylake-Client,+avx2,+aes,+ssse3,+sse4_2"
    ["INTEL_CASCADELAKE"]="Cascadelake-Server,+avx512f,+sha-ni"
    ["INTEL_ICELAKE"]="Icelake-Server,+avx512-vnni"
    ["AMD_EPYC_ROME"]="EPYC-Rome,+invtsc,+topoext,+svm"
    ["AMD_EPYC_MILAN"]="EPYC-Milan,+avx2,+invtsc"
    ["AMD_EPYC_GENOA"]="EPYC-Genoa,+avx512f"
    ["ARM_NEOVERSE_N1"]="neoverse-n1"
    ["GENERIC_QEMU64"]="qemu64,+ssse3,+sse4_2"
    ["GENERIC_QEMU32"]="qemu32"
    ["HOST_PASSTHROUGH"]="host"
    ["MAX_PERFORMANCE"]="max"
)

# GPU Vendor IDs (Common GPUs)
declare -A GPU_VENDORS=(
    ["10de"]="NVIDIA"
    ["1002"]="AMD"
    ["8086"]="Intel"
    ["1b36"]="Red Hat"  # QXL
)

# Supported OS Images (Updated with verified URLs)
declare -A OS_IMAGES=(
    ["Ubuntu 22.04 LTS"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    ["Ubuntu 24.04 LTS"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
    ["Fedora 39"]="fedora|39|https://download.fedoraproject.org/pub/fedora/linux/releases/39/Cloud/x86_64/images/Fedora-Cloud-Base-39-1.5.x86_64.qcow2"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
    ["Rocky Linux 9"]="rocky|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
    ["AlmaLinux 9"]="alma|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
    ["openSUSE Leap 15.5"]="opensuse|leap15.5|https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-OpenStack.x86_64.qcow2"
)

# ============================================================
# Core Functions
# ============================================================

function init_environment() {
    mkdir -p "$VM_DIR" "$CONFIG_DIR" "$LOG_DIR" "$ISO_DIR"
    mkdir -p "$TEMP_DIR"
    chmod 700 "$BASE_DIR"
}

function cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

function log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${timestamp} [${level}] ${message}" >> "$LOG_DIR/vm-manager.log"
    
    case $level in
        "ERROR") echo -e "${RED}[ERROR]${NC} ${message}" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} ${message}" ;;
        "INFO") echo -e "${GREEN}[INFO]${NC} ${message}" ;;
        "DEBUG") echo -e "${CYAN}[DEBUG]${NC} ${message}" ;;
        *) echo "[${level}] ${message}" ;;
    esac
}

function check_dependencies() {
    local required=("qemu-system-x86_64" "qemu-img" "wget" "cloud-localds" "virtiofsd")
    local missing=()
    
    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing dependencies: ${missing[*]}"
        log_message "INFO" "Install with: sudo apt install qemu-system qemu-utils cloud-image-utils wget"
        return 1
    fi
    return 0
}

# ============================================================
# Hardware Detection Functions
# ============================================================

function detect_cpu_info() {
    echo "===== CPU Detection ====="
    
    # Get CPU vendor
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        CPU_VENDOR="Intel"
        CPU_FLAGS="+vmx,+svm,+invtsc"
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        CPU_VENDOR="AMD"
        CPU_FLAGS="+svm,+invtsc,+topoext"
    else
        CPU_VENDOR="Unknown"
        CPU_FLAGS=""
    fi
    
    # Check for KVM support
    if [[ -e /dev/kvm ]]; then
        KVM_AVAILABLE=true
        if lsmod | grep -q "kvm_intel"; then
            log_message "INFO" "Intel KVM available"
        elif lsmod | grep -q "kvm_amd"; then
            log_message "INFO" "AMD KVM available"
        fi
    else
        KVM_AVAILABLE=false
        log_message "WARN" "KVM not available - using TCG emulation"
    fi
    
    # Detect CPU features
    if grep -q "avx512" /proc/cpuinfo; then
        CPU_FLAGS+=",+avx512f"
    fi
    if grep -q "avx2" /proc/cpuinfo; then
        CPU_FLAGS+=",+avx2"
    fi
    
    log_message "INFO" "CPU Vendor: $CPU_VENDOR"
    log_message "INFO" "CPU Flags: $CPU_FLAGS"
}

function detect_gpu_info() {
    echo "===== GPU Detection ====="
    
    # Check for available GPUs
    if command -v lspci &>/dev/null; then
        local gpu_info=$(lspci -nn | grep -E "VGA|3D|Display")
        
        if [[ -z "$gpu_info" ]]; then
            log_message "WARN" "No dedicated GPU detected"
            GPU_AVAILABLE=false
            return
        fi
        
        GPU_AVAILABLE=true
        echo "Available GPUs:"
        echo "$gpu_info"
        
        # Extract vendor and device IDs
        while IFS= read -r line; do
            if [[ $line =~ \[([0-9a-f]{4}):([0-9a-f]{4})\] ]]; then
                local vendor_id="${BASH_REMATCH[1]}"
                local device_id="${BASH_REMATCH[2]}"
                local vendor_name="${GPU_VENDORS[$vendor_id]:-Unknown}"
                
                log_message "INFO" "Found GPU: $vendor_name (${vendor_id}:${device_id})"
            fi
        done <<< "$gpu_info"
    else
        log_message "WARN" "lspci not available - cannot detect GPUs"
        GPU_AVAILABLE=false
    fi
}

function detect_ioommu() {
    if [[ -f /sys/kernel/iommu_groups/0/devices ]]; then
        IOMMU_AVAILABLE=true
        log_message "INFO" "IOMMU is available"
    else
        IOMMU_AVAILABLE=false
        log_message "WARN" "IOMMU not detected - required for PCIe passthrough"
    fi
}

# ============================================================
# VM Configuration Functions
# ============================================================

function select_cpu_model() {
    echo "===== CPU Model Selection ====="
    
    local i=1
    local cpu_options=()
    
    for model in "${!CPU_MODELS[@]}"; do
        echo "$i) $model"
        cpu_options[$i]="$model"
        ((i++))
    done
    
    local choice
    while true; do
        read -p "Select CPU model (1-$((i-1))): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -lt $i ]]; then
            SELECTED_CPU="${cpu_options[$choice]}"
            CPU_FLAGS="${CPU_MODELS[$SELECTED_CPU]}"
            log_message "INFO" "Selected CPU: $SELECTED_CPU"
            break
        fi
        echo "Invalid selection"
    done
}

function configure_gpu_passthrough() {
    echo "===== GPU Passthrough Configuration ====="
    
    if [[ $GPU_AVAILABLE != true ]]; then
        log_message "WARN" "No GPU available for passthrough"
        GPU_PASSTHROUGH=false
        return
    fi
    
    if [[ $IOMMU_AVAILABLE != true ]]; then
        log_message "ERROR" "IOMMU not available - required for GPU passthrough"
        GPU_PASSTHROUGH=false
        return
    fi
    
    read -p "Enable GPU passthrough? (y/N): " enable_gpu
    if [[ "$enable_gpu" =~ ^[Yy]$ ]]; then
        GPU_PASSTHROUGH=true
        
        # Get GPU information
        echo "Available GPUs for passthrough:"
        lspci -nn | grep -E "VGA|3D|Display" | cat -n
        
        read -p "Select GPU number (or Enter to skip): " gpu_choice
        if [[ -n "$gpu_choice" ]]; then
            # Extract PCI address
            local pci_info=$(lspci -nn | grep -E "VGA|3D|Display" | sed -n "${gpu_choice}p")
            if [[ $pci_info =~ ^([0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]) ]]; then
                GPU_PCI_ADDRESS="${BASH_REMATCH[1]}"
                log_message "INFO" "Selected GPU at PCI $GPU_PCI_ADDRESS"
                
                # Extract vendor/device IDs
                if [[ $pci_info =~ \[([0-9a-f]{4}):([0-9a-f]{4})\] ]]; then
                    GPU_VENDOR_ID="${BASH_REMATCH[1]}"
                    GPU_DEVICE_ID="${BASH_REMATCH[2]}"
                fi
            fi
        fi
    else
        GPU_PASSTHROUGH=false
    fi
}

function create_virtual_gpu() {
    echo "===== Virtual GPU Configuration ====="
    
    echo "Virtual GPU options:"
    echo "1) VirtIO-GPU (Recommended for Linux guests)"
    echo "2) QXL (Compatible with Windows guests)"
    echo "3) VMware SVGA"
    echo "4) None (Console only)"
    
    local vgpu_choice
    read -p "Select virtual GPU type (1-4): " vgpu_choice
    
    case $vgpu_choice in
        1)
            VGPU_TYPE="virtio-gpu"
            VGPU_OPTIONS="-device virtio-gpu-pci,max_outputs=2"
            ;;
        2)
            VGPU_TYPE="qxl"
            VGPU_OPTIONS="-device qxl-vga,vgamem_mb=64 -device secondary-vga"
            ;;
        3)
            VGPU_TYPE="vmware"
            VGPU_OPTIONS="-device vmware-svga"
            ;;
        *)
            VGPU_TYPE="none"
            VGPU_OPTIONS=""
            ;;
    esac
    
    # Ask for video memory
    if [[ "$VGPU_TYPE" != "none" ]]; then
        read -p "Video memory in MB (default: 256): " vram_size
        vram_size="${vram_size:-256}"
        VGPU_OPTIONS+=",vgamem_mb=$vram_size"
    fi
    
    log_message "INFO" "Virtual GPU: $VGPU_TYPE"
}

# ============================================================
# VM Creation and Management
# ============================================================

function create_new_vm() {
    log_message "INFO" "Starting new VM creation wizard"
    
    # VM Basic Info
    read -p "Enter VM name: " VM_NAME
    read -p "Enter VM description: " VM_DESCRIPTION
    
    # OS Selection
    echo "===== OS Selection ====="
    local i=1
    local os_names=()
    
    for os in "${!OS_IMAGES[@]}"; do
        echo "$i) $os"
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
        echo "Invalid selection"
    done
    
    # Resource Allocation
    read -p "Memory (MB, default: 4096): " VM_MEMORY
    VM_MEMORY="${VM_MEMORY:-4096}"
    
    read -p "CPU cores (default: 4): " VM_CPUS
    VM_CPUS="${VM_CPUS:-4}"
    
    read -p "Disk size (e.g., 50G, default: 50G): " DISK_SIZE
    DISK_SIZE="${DISK_SIZE:-50G}"
    
    # Network Configuration
    echo "===== Network Configuration ====="
    echo "1) User-mode NAT (Default)"
    echo "2) Bridge networking"
    echo "3) Isolated network"
    
    read -p "Select network type (1-3): " net_choice
    case $net_choice in
        2)
            NET_TYPE="bridge"
            read -p "Bridge interface (default: br0): " BRIDGE_IFACE
            BRIDGE_IFACE="${BRIDGE_IFACE:-br0}"
            ;;
        3)
            NET_TYPE="isolated"
            ;;
        *)
            NET_TYPE="user"
            read -p "SSH port forward (default: 2222): " SSH_PORT
            SSH_PORT="${SSH_PORT:-2222}"
            ;;
    esac
    
    # Storage Configuration
    echo "===== Storage Configuration ====="
    echo "1) VirtIO (Recommended)"
    echo "2) SATA"
    echo "3) NVMe"
    echo "4) SCSI"
    
    read -p "Select storage interface (1-4): " storage_choice
    case $storage_choice in
        2) STORAGE_IFACE="ide";;
        3) STORAGE_IFACE="nvme";;
        4) STORAGE_IFACE="scsi";;
        *) STORAGE_IFACE="virtio";;
    esac
    
    # Advanced Features
    read -p "Enable TPM 2.0? (y/N): " enable_tpm
    [[ "$enable_tpm" =~ ^[Yy]$ ]] && TPM_ENABLED=true || TPM_ENABLED=false
    
    read -p "Enable Secure Boot? (y/N): " enable_secureboot
    [[ "$enable_secureboot" =~ ^[Yy]$ ]] && SECUREBOOT_ENABLED=true || SECUREBOOT_ENABLED=false
    
    # User Configuration
    read -p "Username (default: user): " VM_USERNAME
    VM_USERNAME="${VM_USERNAME:-user}"
    
    read -s -p "Password: " VM_PASSWORD
    echo
    read -s -p "Confirm password: " VM_PASSWORD_CONFIRM
    echo
    
    if [[ "$VM_PASSWORD" != "$VM_PASSWORD_CONFIRM" ]]; then
        log_message "ERROR" "Passwords do not match"
        return 1
    fi
    
    # Hardware Configuration
    select_cpu_model
    configure_gpu_passthrough
    
    if [[ $GPU_PASSTHROUGH != true ]]; then
        create_virtual_gpu
    fi
    
    # Generate VM configuration
    generate_vm_config
    download_os_image
    create_disk_image
    create_cloud_init
    
    log_message "SUCCESS" "VM '$VM_NAME' created successfully!"
    
    # Show connection info
    echo "========================================"
    echo "VM Creation Complete!"
    echo "Name: $VM_NAME"
    echo "OS: $SELECTED_OS"
    echo "Resources: ${VM_MEMORY}MB RAM, ${VM_CPUS} vCPUs"
    echo "Storage: $DISK_SIZE ($STORAGE_IFACE)"
    if [[ $NET_TYPE == "user" ]]; then
        echo "SSH: ssh -p $SSH_PORT $VM_USERNAME@localhost"
    fi
    echo "========================================"
}

function generate_vm_config() {
    local config_file="$CONFIG_DIR/${VM_NAME}.conf"
    
    cat > "$config_file" <<EOF
# VM Configuration: $VM_NAME
# Generated: $(date)

VM_NAME="$VM_NAME"
VM_DESCRIPTION="$VM_DESCRIPTION"
OS_TYPE="$OS_TYPE"
OS_CODENAME="$OS_CODENAME"
IMG_URL="$IMG_URL"
VM_MEMORY="$VM_MEMORY"
VM_CPUS="$VM_CPUS"
DISK_SIZE="$DISK_SIZE"
STORAGE_IFACE="$STORAGE_IFACE"
NET_TYPE="$NET_TYPE"
SSH_PORT="$SSH_PORT"
BRIDGE_IFACE="$BRIDGE_IFACE"
VM_USERNAME="$VM_USERNAME"
VM_PASSWORD="$VM_PASSWORD"
SELECTED_CPU="$SELECTED_CPU"
CPU_FLAGS="$CPU_FLAGS"
GPU_PASSTHROUGH="$GPU_PASSTHROUGH"
GPU_PCI_ADDRESS="$GPU_PCI_ADDRESS"
VGPU_TYPE="$VGPU_TYPE"
VGPU_OPTIONS="$VGPU_OPTIONS"
TPM_ENABLED="$TPM_ENABLED"
SECUREBOOT_ENABLED="$SECUREBOOT_ENABLED"
CREATED="$(date)"
EOF
    
    chmod 600 "$config_file"
    log_message "INFO" "Configuration saved: $config_file"
}

function download_os_image() {
    local image_file="$ISO_DIR/${OS_TYPE}-${OS_CODENAME}.qcow2"
    
    if [[ -f "$image_file" ]]; then
        log_message "INFO" "OS image already exists"
        return 0
    fi
    
    log_message "INFO" "Downloading OS image from: $IMG_URL"
    
    # Try multiple download methods
    if command -v curl &>/dev/null; then
        curl -L -o "$image_file.tmp" "$IMG_URL"
    elif command -v wget &>/dev/null; then
        wget -O "$image_file.tmp" "$IMG_URL"
    else
        log_message "ERROR" "No download tool available (install curl or wget)"
        return 1
    fi
    
    if [[ $? -eq 0 ]]; then
        mv "$image_file.tmp" "$image_file"
        log_message "SUCCESS" "Download completed: $image_file"
        return 0
    else
        log_message "ERROR" "Download failed"
        return 1
    fi
}

function create_disk_image() {
    local base_image="$ISO_DIR/${OS_TYPE}-${OS_CODENAME}.qcow2"
    local vm_disk="$VM_DIR/${VM_NAME}.qcow2"
    
    if [[ ! -f "$base_image" ]]; then
        log_message "ERROR" "Base image not found: $base_image"
        return 1
    fi
    
    log_message "INFO" "Creating disk image: $vm_disk"
    
    # Create a new disk based on the base image
    qemu-img create -f qcow2 -b "$base_image" -F qcow2 "$vm_disk" "$DISK_SIZE"
    
    if [[ $? -eq 0 ]]; then
        log_message "SUCCESS" "Disk image created: $vm_disk"
        return 0
    else
        log_message "ERROR" "Failed to create disk image"
        return 1
    fi
}

function create_cloud_init() {
    local seed_file="$VM_DIR/${VM_NAME}-seed.iso"
    local user_data="$TEMP_DIR/user-data"
    local meta_data="$TEMP_DIR/meta-data"
    
    # Generate password hash
    local password_hash
    if command -v mkpasswd &>/dev/null; then
        password_hash=$(mkpasswd -m sha-512 "$VM_PASSWORD")
    else
        password_hash=$(echo -n "$VM_PASSWORD" | openssl passwd -6 -stdin 2>/dev/null || echo "$VM_PASSWORD")
    fi
    
    # Create user-data
    cat > "$user_data" <<EOF
#cloud-config
hostname: $VM_NAME
fqdn: $VM_NAME.local
manage_etc_hosts: true
users:
  - name: $VM_USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $password_hash
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
    root:$VM_PASSWORD
    $VM_USERNAME:$VM_PASSWORD
  expire: false
packages:
  - qemu-guest-agent
  - neofetch
  - htop
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "Welcome to $VM_NAME - Managed by Advanced VM Manager" > /etc/motd
EOF
    
    # Create meta-data
    cat > "$meta_data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF
    
    # Create seed ISO
    cloud-localds -f vfat "$seed_file" "$user_data" "$meta_data"
    
    if [[ $? -eq 0 ]]; then
        log_message "SUCCESS" "Cloud-init seed created: $seed_file"
        return 0
    else
        log_message "ERROR" "Failed to create cloud-init seed"
        return 1
    fi
}

# ============================================================
# VM Operations
# ============================================================

function start_vm() {
    local vm_name="$1"
    local config_file="$CONFIG_DIR/${vm_name}.conf"
    
    if [[ ! -f "$config_file" ]]; then
        log_message "ERROR" "VM configuration not found: $vm_name"
        return 1
    fi
    
    # Load configuration
    source "$config_file"
    
    local vm_disk="$VM_DIR/${vm_name}.qcow2"
    local seed_file="$VM_DIR/${vm_name}-seed.iso"
    
    if [[ ! -f "$vm_disk" ]]; then
        log_message "ERROR" "VM disk not found: $vm_disk"
        return 1
    fi
    
    log_message "INFO" "Starting VM: $vm_name"
    
    # Build QEMU command
    local qemu_cmd=(
        qemu-system-x86_64
        -name "$vm_name"
        -machine type=q35,accel=kvm:tcg
        -m "$VM_MEMORY"
        -smp "$VM_CPUS,sockets=1,cores=$VM_CPUS,threads=1"
        -cpu "$CPU_FLAGS"
    )
    
    # Add storage
    case $STORAGE_IFACE in
        "virtio")
            qemu_cmd+=(-drive "file=$vm_disk,format=qcow2,if=virtio")
            qemu_cmd+=(-drive "file=$seed_file,format=raw,if=virtio,readonly=on")
            ;;
        "nvme")
            qemu_cmd+=(-drive "file=$vm_disk,format=qcow2,if=none,id=disk0")
            qemu_cmd+=(-device "nvme,serial=deadbeef,drive=disk0")
            ;;
        *)
            qemu_cmd+=(-drive "file=$vm_disk,format=qcow2,if=$STORAGE_IFACE")
            qemu_cmd+=(-drive "file=$seed_file,format=raw,if=$STORAGE_IFACE,readonly=on")
            ;;
    esac
    
    # Add network
    case $NET_TYPE in
        "bridge")
            qemu_cmd+=(-netdev "bridge,id=net0,br=$BRIDGE_IFACE")
            qemu_cmd+=(-device "virtio-net-pci,netdev=net0")
            ;;
        "user")
            qemu_cmd+=(-netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22")
            qemu_cmd+=(-device "virtio-net-pci,netdev=net0")
            ;;
        *)
            qemu_cmd+=(-netdev "user,id=net0,restrict=on")
            qemu_cmd+=(-device "virtio-net-pci,netdev=net0")
            ;;
    esac
    
    # Add GPU configuration
    if [[ $GPU_PASSTHROUGH == true ]] && [[ -n "$GPU_PCI_ADDRESS" ]]; then
        log_message "INFO" "Configuring GPU passthrough for $GPU_PCI_ADDRESS"
        qemu_cmd+=(
            -device "vfio-pci,host=$GPU_PCI_ADDRESS"
            -vga none
            -nographic
        )
    elif [[ -n "$VGPU_OPTIONS" ]]; then
        qemu_cmd+=($VGPU_OPTIONS)
        qemu_cmd+=(-display gtk,gl=on)
    else
        qemu_cmd+=(-nographic -serial mon:stdio)
    fi
    
    # Add TPM if enabled
    if [[ $TPM_ENABLED == true ]]; then
        qemu_cmd+=(
            -chardev "socket,id=chrtpm,path=$TEMP_DIR/swtpm-${vm_name}.sock"
            -tpmdev "emulator,id=tpm0,chardev=chrtpm"
            -device "tpm-tis,tpmdev=tpm0"
        )
    fi
    
    # Add UEFI/BIOS
    if [[ $SECUREBOOT_ENABLED == true ]]; then
        local ovmf_code="/usr/share/OVMF/OVMF_CODE.fd"
        local ovmf_vars="/usr/share/OVMF/OVMF_VARS.fd"
        
        if [[ -f "$ovmf_code" ]] && [[ -f "$ovmf_vars" ]]; then
            qemu_cmd+=(
                -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
                -drive "if=pflash,format=raw,file=$TEMP_DIR/${vm_name}_VARS.fd"
            )
        fi
    fi
    
    # Performance optimizations
    qemu_cmd+=(
        -device "virtio-balloon-pci"
        -object "rng-random,filename=/dev/urandom,id=rng0"
        -device "virtio-rng-pci,rng=rng0"
        -rtc "base=utc,clock=host"
        -boot "order=c"
        -usb
        -device "qemu-xhci"
    )
    
    log_message "INFO" "Starting QEMU with command:"
    echo "${qemu_cmd[@]}"
    echo
    
    # Start the VM
    "${qemu_cmd[@]}"
}

function list_vms() {
    echo "===== Available VMs ====="
    
    local vms=($(find "$CONFIG_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        echo "No VMs found"
        return
    fi
    
    for vm in "${vms[@]}"; do
        local config_file="$CONFIG_DIR/${vm}.conf"
        if [[ -f "$config_file" ]]; then
            source "$config_file" 2>/dev/null
            local status="Stopped"
            
            if pgrep -f "qemu-system.*$vm" &>/dev/null; then
                status="${GREEN}Running${NC}"
            else
                status="${RED}Stopped${NC}"
            fi
            
            printf "%-20s %-15s %-10s %s\n" "$vm" "$OS_TYPE" "$status" "$VM_DESCRIPTION"
        fi
    done
}

function stop_vm() {
    local vm_name="$1"
    
    log_message "INFO" "Stopping VM: $vm_name"
    
    # Find and kill QEMU process
    local pids=$(pgrep -f "qemu-system.*$vm_name")
    
    if [[ -z "$pids" ]]; then
        log_message "WARN" "VM not running: $vm_name"
        return 1
    fi
    
    # Send SIGTERM first
    kill -TERM $pids 2>/dev/null
    sleep 2
    
    # Force kill if still running
    if pgrep -f "qemu-system.*$vm_name" &>/dev/null; then
        log_message "WARN" "VM did not stop gracefully, forcing..."
        pkill -9 -f "qemu-system.*$vm_name"
    fi
    
    log_message "SUCCESS" "VM stopped: $vm_name"
}

function delete_vm() {
    local vm_name="$1"
    
    read -p "Are you sure you want to delete VM '$vm_name'? (y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    
    log_message "INFO" "Deleting VM: $vm_name"
    
    # Stop VM if running
    stop_vm "$vm_name"
    
    # Remove files
    rm -f "$CONFIG_DIR/${vm_name}.conf"
    rm -f "$VM_DIR/${vm_name}.qcow2"
    rm -f "$VM_DIR/${vm_name}-seed.iso"
    
    log_message "SUCCESS" "VM deleted: $vm_name"
}

# ============================================================
# TUI Interface
# ============================================================

function show_menu() {
    clear
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 Advanced VM Manager v$SCRIPT_VERSION                ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║                                                              ║"
    echo "║  1) Create New VM                                            ║"
    echo "║  2) List VMs                                                 ║"
    echo "║  3) Start VM                                                 ║"
    echo "║  4) Stop VM                                                  ║"
    echo "║  5) Delete VM                                                ║"
    echo "║  6) Hardware Detection                                       ║"
    echo "║  7) System Information                                       ║"
    echo "║  8) Exit                                                     ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo
}

function main_tui() {
    init_environment
    
    if ! check_dependencies; then
        log_message "ERROR" "Dependency check failed"
        return 1
    fi
    
    # Initial hardware detection
    detect_cpu_info
    detect_gpu_info
    detect_ioommu
    
    while true; do
        show_menu
        
        read -p "Select option (1-8): " choice
        
        case $choice in
            1)
                create_new_vm
                read -p "Press Enter to continue..."
                ;;
            2)
                list_vms
                read -p "Press Enter to continue..."
                ;;
            3)
                list_vms
                read -p "Enter VM name to start: " vm_start
                if [[ -n "$vm_start" ]]; then
                    start_vm "$vm_start"
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                list_vms
                read -p "Enter VM name to stop: " vm_stop
                if [[ -n "$vm_stop" ]]; then
                    stop_vm "$vm_stop"
                fi
                read -p "Press Enter to continue..."
                ;;
            5)
                list_vms
                read -p "Enter VM name to delete: " vm_delete
                if [[ -n "$vm_delete" ]]; then
                    delete_vm "$vm_delete"
                fi
                read -p "Press Enter to continue..."
                ;;
            6)
                echo "===== Hardware Detection Results ====="
                echo "KVM Available: $KVM_AVAILABLE"
                echo "CPU Vendor: $CPU_VENDOR"
                echo "GPU Available: $GPU_AVAILABLE"
                echo "IOMMU Available: $IOMMU_AVAILABLE"
                read -p "Press Enter to continue..."
                ;;
            7)
                echo "===== System Information ====="
                echo "Script Version: $SCRIPT_VERSION"
                echo "Base Directory: $BASE_DIR"
                echo "Log Directory: $LOG_DIR"
                echo "Config Directory: $CONFIG_DIR"
                echo "Supported CPUs: ${#CPU_MODELS[@]} models"
                echo "Supported OS: ${#OS_IMAGES[@]} distributions"
                read -p "Press Enter to continue..."
                ;;
            8)
                log_message "INFO" "Exiting Advanced VM Manager"
                cleanup
                exit 0
                ;;
            *)
                echo "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# ============================================================
# Main Entry Point
# ============================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Initializing Advanced VM Manager..."
    main_tui
fi
