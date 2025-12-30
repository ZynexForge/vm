#!/bin/bash
set -euo pipefail

# ============================================================
# Advanced VM Manager with GPU Passthrough
# Simple Best UI Edition
# ============================================================

# Global Configuration
SCRIPT_VERSION="2.1"
BASE_DIR="${BASE_DIR:-$HOME/vm-manager}"
VM_DIR="$BASE_DIR/vms"
CONFIG_DIR="$BASE_DIR/configs"
LOG_DIR="$BASE_DIR/logs"
ISO_DIR="$BASE_DIR/isos"
TEMP_DIR="/tmp/vm-manager-$$"

# Color Configuration
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# CPU Configuration Database - Extended with AMD Ryzen models
declare -A CPU_MODELS=(
    # AMD Ryzen Series
    ["AMD_RYZEN_9_7950X"]="EPYC-Genoa,+avx512f,+invtsc,+topoext"  # Zen 4
    ["AMD_RYZEN_9_7900X"]="EPYC-Genoa,+avx512f,+invtsc,+topoext"
    ["AMD_RYZEN_9_5950X"]="EPYC-Rome,+avx2,+invtsc,+topoext"      # Zen 3
    ["AMD_RYZEN_9_5900X"]="EPYC-Rome,+avx2,+invtsc,+topoext"
    ["AMD_RYZEN_7_7800X3D"]="EPYC-Genoa,+avx512f,+invtsc,+topoext" # Zen 4 3D V-Cache
    ["AMD_RYZEN_7_7700X"]="EPYC-Genoa,+avx512f,+invtsc,+topoext"
    ["AMD_RYZEN_7_5800X3D"]="EPYC-Rome,+avx2,+invtsc,+topoext"    # Zen 3 3D V-Cache
    ["AMD_RYZEN_7_5800X"]="EPYC-Rome,+avx2,+invtsc,+topoext"
    ["AMD_RYZEN_5_7600X"]="EPYC-Genoa,+avx512f,+invtsc,+topoext"
    ["AMD_RYZEN_5_5600X"]="EPYC-Rome,+avx2,+invtsc,+topoext"
    
    # AMD EPYC Server Series
    ["AMD_EPYC_GENOA"]="EPYC-Genoa,+avx512f,+sha-ni,+invtsc,+topoext"        # Zen 4
    ["AMD_EPYC_MILAN"]="EPYC-Milan,+avx2,+sha-ni,+invtsc,+topoext"           # Zen 3
    ["AMD_EPYC_ROME"]="EPYC-Rome,+avx2,+invtsc,+topoext"                     # Zen 2
    ["AMD_EPYC_NAPLES"]="EPYC,+invtsc"                                       # Zen 1
    
    # Intel Series
    ["INTEL_PLATINUM_8380"]="Cascadelake-Server,+avx512f,+avx512-vnni"       # Xeon Platinum
    ["INTEL_PLATINUM_8375C"]="Icelake-Server,+avx512f,+avx512-vnni"
    ["INTEL_XEON_GOLD_6348"]="Cascadelake-Server,+avx512f"
    ["INTEL_CORE_i9_14900K"]="Skylake-Client,+avx2,+avx512f"                 # Raptor Lake
    ["INTEL_CORE_i7_14700K"]="Skylake-Client,+avx2,+avx512f"
    ["INTEL_CORE_i5_14600K"]="Skylake-Client,+avx2"
    
    # Generic/Other
    ["HOST_PASSTHROUGH"]="host"
    ["MAX_PERFORMANCE"]="max"
    ["QEMU64"]="qemu64,+ssse3,+sse4_2"
    ["QEMU32"]="qemu32"
)

# GPU Vendor IDs
declare -A GPU_VENDORS=(
    ["10de"]="NVIDIA"
    ["1002"]="AMD"
    ["8086"]="Intel"
    ["1b36"]="Red Hat"
)

# Supported OS Images
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
# UI Functions
# ============================================================

function display_banner() {
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
    echo -e "${WHITE}Advanced VM Manager v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo
}

function print_menu() {
    echo -e "${WHITE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║                 MAIN MENU                           ║${NC}"
    echo -e "${WHITE}╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║                                                      ║${NC}"
    echo -e "${WHITE}║   ${GREEN}1${NC}) ${CYAN}Create New VM${NC}                                  ║${NC}"
    echo -e "${WHITE}║   ${GREEN}2${NC}) ${CYAN}List VMs${NC}                                       ║${NC}"
    echo -e "${WHITE}║   ${GREEN}3${NC}) ${CYAN}Start VM${NC}                                       ║${NC}"
    echo -e "${WHITE}║   ${GREEN}4${NC}) ${CYAN}Stop VM${NC}                                        ║${NC}"
    echo -e "${WHITE}║   ${GREEN}5${NC}) ${CYAN}Delete VM${NC}                                      ║${NC}"
    echo -e "${WHITE}║   ${GREEN}6${NC}) ${CYAN}VM Information${NC}                                 ║${NC}"
    echo -e "${WHITE}║   ${GREEN}7${NC}) ${CYAN}Hardware Info${NC}                                  ║${NC}"
    echo -e "${WHITE}║   ${GREEN}8${NC}) ${RED}Exit${NC}                                         ║${NC}"
    echo -e "${WHITE}║                                                      ║${NC}"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════╝${NC}"
    echo
}

function print_status() {
    local level="$1"
    local message="$2"
    
    case $level in
        "INFO") echo -e "${CYAN}[INFO]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        "WARN") echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "INPUT") echo -e "${BLUE}[INPUT]${NC} $message" ;;
        *) echo -e "[$level] $message" ;;
    esac
}

function print_header() {
    local title="$1"
    echo -e "\n${WHITE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║ ${CYAN}$title${NC}"
    echo -e "${WHITE}╚══════════════════════════════════════════════════════╝${NC}"
}

function input_prompt() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [[ -n "$default" ]]; then
        read -p "$(print_status "INPUT" "$prompt (default: $default): ")" input_value
        input_value="${input_value:-$default}"
    else
        read -p "$(print_status "INPUT" "$prompt: ")" input_value
    fi
    
    eval "$var_name=\"$input_value\""
}

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

function check_dependencies() {
    local required=("qemu-system-x86_64" "qemu-img" "wget" "cloud-localds")
    local missing=()
    
    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_status "ERROR" "Missing dependencies: ${missing[*]}"
        print_status "INFO" "Install with: sudo apt install qemu-system qemu-utils cloud-image-utils wget"
        return 1
    fi
    return 0
}

# ============================================================
# Hardware Detection
# ============================================================

function detect_hardware() {
    print_header "HARDWARE DETECTION"
    
    # CPU Detection
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        CPU_VENDOR="Intel"
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        CPU_VENDOR="AMD"
    else
        CPU_VENDOR="Unknown"
    fi
    
    # Get CPU model
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[[:space:]]*//')
    
    # Check KVM
    if [[ -e /dev/kvm ]]; then
        KVM_AVAILABLE=true
        if lsmod | grep -q "kvm_intel"; then
            KVM_TYPE="Intel"
        elif lsmod | grep -q "kvm_amd"; then
            KVM_TYPE="AMD"
        fi
    else
        KVM_AVAILABLE=false
        KVM_TYPE="None"
    fi
    
    # Check GPU
    if command -v lspci &>/dev/null; then
        GPU_INFO=$(lspci -nn | grep -E "VGA|3D|Display" | head -1)
        if [[ -n "$GPU_INFO" ]]; then
            GPU_AVAILABLE=true
        else
            GPU_AVAILABLE=false
        fi
    else
        GPU_AVAILABLE=false
    fi
    
    # Display hardware info
    echo -e "${CYAN}CPU:${NC} $CPU_MODEL"
    echo -e "${CYAN}Vendor:${NC} $CPU_VENDOR"
    echo -e "${CYAN}KVM:${NC} $KVM_TYPE ${KVM_AVAILABLE:+${GREEN}(Available)${NC}}${KVM_AVAILABLE:+${RED}(Not Available)${NC}}"
    echo -e "${CYAN}GPU:${NC} ${GPU_AVAILABLE:+${GREEN}Detected${NC}}${GPU_AVAILABLE:+${RED}Not Detected${NC}}"
    
    if [[ "$GPU_AVAILABLE" == true ]]; then
        echo -e "${CYAN}GPU Info:${NC} $GPU_INFO"
    fi
    
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

# ============================================================
# VM Creation
# ============================================================

function create_vm() {
    print_header "CREATE NEW VIRTUAL MACHINE"
    
    # Get VM name and description
    input_prompt "Enter VM name" "" VM_NAME
    input_prompt "Enter VM description" "" VM_DESCRIPTION
    
    # OS Selection
    print_header "OPERATING SYSTEM SELECTION"
    local i=1
    local os_names=()
    
    for os in "${!OS_IMAGES[@]}"; do
        printf "  ${GREEN}%2d${NC}) ${CYAN}%s${NC}\n" "$i" "$os"
        os_names[$i]="$os"
        ((i++))
    done
    
    local os_choice
    while true; do
        read -p "$(print_status "INPUT" "Select OS (1-$((i-1))): ")" os_choice
        if [[ "$os_choice" =~ ^[0-9]+$ ]] && [[ $os_choice -ge 1 ]] && [[ $os_choice -lt $i ]]; then
            SELECTED_OS="${os_names[$os_choice]}"
            IFS='|' read -r OS_TYPE OS_CODENAME IMG_URL <<< "${OS_IMAGES[$SELECTED_OS]}"
            break
        fi
        print_status "ERROR" "Invalid selection"
    done
    
    # Resource Configuration
    print_header "RESOURCE CONFIGURATION"
    
    input_prompt "Memory (MB)" "4096" VM_MEMORY
    input_prompt "CPU cores" "4" VM_CPUS
    input_prompt "Disk size (e.g., 50G)" "50G" DISK_SIZE
    
    # Network Configuration
    print_header "NETWORK CONFIGURATION"
    echo "  1) User-mode NAT (Default)"
    echo "  2) Bridge networking"
    echo "  3) Isolated network"
    
    local net_choice
    read -p "$(print_status "INPUT" "Select network type (1-3): ")" net_choice
    case $net_choice in
        2)
            NET_TYPE="bridge"
            input_prompt "Bridge interface" "br0" BRIDGE_IFACE
            SSH_PORT=""  # Clear SSH_PORT for bridge mode
            ;;
        3)
            NET_TYPE="isolated"
            SSH_PORT=""  # Clear SSH_PORT for isolated mode
            ;;
        *)
            NET_TYPE="user"
            input_prompt "SSH port forward" "2222" SSH_PORT
            ;;
    esac
    
    # Storage Configuration
    print_header "STORAGE CONFIGURATION"
    echo "  1) VirtIO (Recommended)"
    echo "  2) NVMe"
    echo "  3) SATA"
    echo "  4) SCSI"
    
    local storage_choice
    read -p "$(print_status "INPUT" "Select storage interface (1-4): ")" storage_choice
    case $storage_choice in
        2) STORAGE_IFACE="nvme" ;;
        3) STORAGE_IFACE="ide" ;;
        4) STORAGE_IFACE="scsi" ;;
        *) STORAGE_IFACE="virtio" ;;
    esac
    
    # Security Features
    print_header "SECURITY FEATURES"
    
    local enable_tpm
    read -p "$(print_status "INPUT" "Enable TPM 2.0? (y/N): ")" enable_tpm
    [[ "$enable_tpm" =~ ^[Yy]$ ]] && TPM_ENABLED=true || TPM_ENABLED=false
    
    local enable_secureboot
    read -p "$(print_status "INPUT" "Enable Secure Boot? (y/N): ")" enable_secureboot
    [[ "$enable_secureboot" =~ ^[Yy]$ ]] && SECUREBOOT_ENABLED=true || SECUREBOOT_ENABLED=false
    
    # User Configuration
    print_header "USER CONFIGURATION"
    
    input_prompt "Username" "user" VM_USERNAME
    
    local pass1 pass2
    while true; do
        read -s -p "$(print_status "INPUT" "Password: ")" pass1
        echo
        read -s -p "$(print_status "INPUT" "Confirm password: ")" pass2
        echo
        
        if [[ "$pass1" == "$pass2" ]]; then
            VM_PASSWORD="$pass1"
            break
        else
            print_status "ERROR" "Passwords do not match. Try again."
        fi
    done
    
    # CPU Selection
    select_cpu
    
    # GPU Configuration
    configure_gpu
    
    # Create VM
    print_status "INFO" "Creating VM '$VM_NAME'..."
    
    if generate_vm_config && download_os_image && create_disk_image && create_cloud_init; then
        print_status "SUCCESS" "VM '$VM_NAME' created successfully!"
        show_vm_summary
    else
        print_status "ERROR" "Failed to create VM"
        return 1
    fi
    
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

function select_cpu() {
    print_header "CPU SELECTION"
    
    # Group CPUs by type for better display
    declare -A cpu_groups=(
        ["AMD Ryzen"]="AMD_RYZEN_9_7950X AMD_RYZEN_9_7900X AMD_RYZEN_9_5950X AMD_RYZEN_9_5900X AMD_RYZEN_7_7800X3D AMD_RYZEN_7_7700X AMD_RYZEN_7_5800X3D AMD_RYZEN_7_5800X AMD_RYZEN_5_7600X AMD_RYZEN_5_5600X"
        ["AMD EPYC"]="AMD_EPYC_GENOA AMD_EPYC_MILAN AMD_EPYC_ROME AMD_EPYC_NAPLES"
        ["Intel"]="INTEL_PLATINUM_8380 INTEL_PLATINUM_8375C INTEL_XEON_GOLD_6348 INTEL_CORE_i9_14900K INTEL_CORE_i7_14700K INTEL_CORE_i5_14600K"
        ["Generic"]="HOST_PASSTHROUGH MAX_PERFORMANCE QEMU64 QEMU32"
    )
    
    local i=1
    declare -A cpu_map
    
    # Display CPUs by groups
    for group in "AMD Ryzen" "AMD EPYC" "Intel" "Generic"; do
        echo -e "\n${WHITE}$group CPUs:${NC}"
        for cpu in ${cpu_groups[$group]}; do
            printf "  ${GREEN}%2d${NC}) ${CYAN}%s${NC}\n" "$i" "$cpu"
            cpu_map[$i]="$cpu"
            ((i++))
        done
    done
    
    local cpu_choice
    while true; do
        read -p "$(print_status "INPUT" "Select CPU model (1-$((i-1))): ")" cpu_choice
        if [[ "$cpu_choice" =~ ^[0-9]+$ ]] && [[ $cpu_choice -ge 1 ]] && [[ $cpu_choice -lt $i ]]; then
            SELECTED_CPU="${cpu_map[$cpu_choice]}"
            CPU_FLAGS="${CPU_MODELS[$SELECTED_CPU]}"
            print_status "INFO" "Selected CPU: $SELECTED_CPU"
            break
        fi
        print_status "ERROR" "Invalid selection"
    done
}

function configure_gpu() {
    print_header "GPU CONFIGURATION"
    
    if [[ "$GPU_AVAILABLE" != true ]]; then
        print_status "WARN" "No GPU detected. Using virtual GPU."
        GPU_PASSTHROUGH=false
        select_virtual_gpu
        return
    fi
    
    local gpu_choice
    read -p "$(print_status "INPUT" "Enable GPU passthrough? (y/N): ")" gpu_choice
    
    if [[ "$gpu_choice" =~ ^[Yy]$ ]]; then
        GPU_PASSTHROUGH=true
        print_status "INFO" "GPU passthrough enabled"
        
        # Get GPU PCI address
        local pci_info=$(lspci -nn | grep -E "VGA|3D|Display" | head -1)
        if [[ $pci_info =~ ^([0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]) ]]; then
            GPU_PCI_ADDRESS="${BASH_REMATCH[1]}"
            print_status "INFO" "Using GPU at PCI: $GPU_PCI_ADDRESS"
        fi
    else
        GPU_PASSTHROUGH=false
        select_virtual_gpu
    fi
}

function select_virtual_gpu() {
    print_header "VIRTUAL GPU SELECTION"
    
    echo "  1) VirtIO-GPU (Recommended for Linux)"
    echo "  2) QXL (Good for Windows)"
    echo "  3) VMware SVGA"
    echo "  4) None (Console only)"
    
    local vgpu_choice
    read -p "$(print_status "INPUT" "Select virtual GPU (1-4): ")" vgpu_choice
    
    case $vgpu_choice in
        1)
            VGPU_TYPE="virtio-gpu"
            input_prompt "Video memory (MB)" "256" VRAM_SIZE
            VGPU_OPTIONS="-device virtio-gpu-pci,max_outputs=2,vgamem_mb=$VRAM_SIZE"
            ;;
        2)
            VGPU_TYPE="qxl"
            input_prompt "Video memory (MB)" "128" VRAM_SIZE
            VGPU_OPTIONS="-device qxl-vga,vgamem_mb=$VRAM_SIZE"
            ;;
        3)
            VGPU_TYPE="vmware"
            input_prompt "Video memory (MB)" "256" VRAM_SIZE
            VGPU_OPTIONS="-device vmware-svga,vgamem_mb=$VRAM_SIZE"
            ;;
        *)
            VGPU_TYPE="none"
            VGPU_OPTIONS=""
            ;;
    esac
    
    print_status "INFO" "Virtual GPU: $VGPU_TYPE"
}

# ============================================================
# VM Configuration Files
# ============================================================

function generate_vm_config() {
    local config_file="$CONFIG_DIR/${VM_NAME}.conf"
    
    cat > "$config_file" <<EOF
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
SSH_PORT="${SSH_PORT:-}"
BRIDGE_IFACE="${BRIDGE_IFACE:-}"
VM_USERNAME="$VM_USERNAME"
VM_PASSWORD="$VM_PASSWORD"
SELECTED_CPU="$SELECTED_CPU"
CPU_FLAGS="$CPU_FLAGS"
GPU_PASSTHROUGH="$GPU_PASSTHROUGH"
GPU_PCI_ADDRESS="${GPU_PCI_ADDRESS:-}"
VGPU_TYPE="${VGPU_TYPE:-}"
VGPU_OPTIONS="${VGPU_OPTIONS:-}"
TPM_ENABLED="$TPM_ENABLED"
SECUREBOOT_ENABLED="$SECUREBOOT_ENABLED"
CREATED="$(date)"
EOF
    
    chmod 600 "$config_file"
    print_status "SUCCESS" "Configuration saved"
    return 0
}

function download_os_image() {
    local image_file="$ISO_DIR/${OS_TYPE}-${OS_CODENAME}.qcow2"
    
    if [[ -f "$image_file" ]]; then
        print_status "INFO" "Using existing OS image"
        return 0
    fi
    
    print_status "INFO" "Downloading OS image..."
    
    if command -v wget &>/dev/null; then
        if wget --progress=bar:force -O "$image_file.tmp" "$IMG_URL"; then
            mv "$image_file.tmp" "$image_file"
            print_status "SUCCESS" "Download completed"
            return 0
        fi
    elif command -v curl &>/dev/null; then
        if curl -L -o "$image_file.tmp" "$IMG_URL"; then
            mv "$image_file.tmp" "$image_file"
            print_status "SUCCESS" "Download completed"
            return 0
        fi
    fi
    
    print_status "ERROR" "Download failed"
    return 1
}

function create_disk_image() {
    local base_image="$ISO_DIR/${OS_TYPE}-${OS_CODENAME}.qcow2"
    local vm_disk="$VM_DIR/${VM_NAME}.qcow2"
    
    if [[ ! -f "$base_image" ]]; then
        print_status "ERROR" "Base image not found"
        return 1
    fi
    
    print_status "INFO" "Creating disk image..."
    
    if qemu-img create -f qcow2 -b "$base_image" -F qcow2 "$vm_disk" "$DISK_SIZE"; then
        print_status "SUCCESS" "Disk image created"
        return 0
    else
        print_status "ERROR" "Failed to create disk image"
        return 1
    fi
}

function create_cloud_init() {
    local seed_file="$VM_DIR/${VM_NAME}-seed.iso"
    local user_data="$TEMP_DIR/user-data"
    local meta_data="$TEMP_DIR/meta-data"
    
    # Generate password hash
    local password_hash
    if command -v openssl &>/dev/null; then
        password_hash=$(openssl passwd -6 "$VM_PASSWORD" 2>/dev/null || echo "$VM_PASSWORD")
    else
        password_hash="$VM_PASSWORD"
    fi
    
    # Create user-data
    cat > "$user_data" <<EOF
#cloud-config
hostname: $VM_NAME
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
EOF
    
    # Create meta-data
    cat > "$meta_data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF
    
    # Create seed ISO
    if cloud-localds "$seed_file" "$user_data" "$meta_data"; then
        print_status "SUCCESS" "Cloud-init seed created"
        return 0
    else
        print_status "ERROR" "Failed to create cloud-init seed"
        return 1
    fi
}

# ============================================================
# VM Management
# ============================================================

function list_vms() {
    print_header "VIRTUAL MACHINES"
    
    local vms=($(find "$CONFIG_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        print_status "INFO" "No VMs found"
        return
    fi
    
    echo -e "${WHITE}No.  VM Name           Status        OS            CPU${NC}"
    echo -e "${BLUE}─────────────────────────────────────────────────────────${NC}"
    
    local i=1
    for vm in "${vms[@]}"; do
        local config_file="$CONFIG_DIR/${vm}.conf"
        
        if [[ -f "$config_file" ]]; then
            source "$config_file" 2>/dev/null
            
            # Check if VM is running
            local status="${RED}Stopped${NC}"
            if pgrep -f "qemu-system.*$vm" &>/dev/null; then
                status="${GREEN}Running${NC}"
            fi
            
            # Truncate long names
            local display_name="$vm"
            [[ ${#vm} -gt 15 ]] && display_name="${vm:0:12}..."
            
            local display_os="$OS_TYPE"
            [[ ${#OS_TYPE} -gt 10 ]] && display_os="${OS_TYPE:0:7}..."
            
            local display_cpu="${SELECTED_CPU:-Unknown}"
            [[ ${#display_cpu} -gt 12 ]] && display_cpu="${display_cpu:0:9}..."
            
            printf "${WHITE}%2d${NC}  %-15s  %-12s  %-12s  %-12s\n" \
                   "$i" "$display_name" "$status" "$display_os" "$display_cpu"
            
            ((i++))
        fi
    done
    
    echo
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

function start_vm() {
    list_vms
    
    local vms=($(find "$CONFIG_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        print_status "ERROR" "No VMs available"
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
        return
    fi
    
    local vm_num
    read -p "$(print_status "INPUT" "Enter VM number to start: ")" vm_num
    
    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [[ $vm_num -ge 1 ]] && [[ $vm_num -le ${#vms[@]} ]]; then
        local vm_name="${vms[$((vm_num-1))]}"
        start_vm_by_name "$vm_name"
    else
        print_status "ERROR" "Invalid selection"
    fi
    
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

function start_vm_by_name() {
    local vm_name="$1"
    local config_file="$CONFIG_DIR/${vm_name}.conf"
    
    if [[ ! -f "$config_file" ]]; then
        print_status "ERROR" "VM not found"
        return 1
    fi
    
    # Check if already running
    if pgrep -f "qemu-system.*$vm_name" &>/dev/null; then
        print_status "WARN" "VM '$vm_name' is already running"
        return 0
    fi
    
    # Load configuration
    source "$config_file"
    
    local vm_disk="$VM_DIR/${vm_name}.qcow2"
    local seed_file="$VM_DIR/${vm_name}-seed.iso"
    
    if [[ ! -f "$vm_disk" ]]; then
        print_status "ERROR" "VM disk not found"
        return 1
    fi
    
    print_header "STARTING VM: $vm_name"
    
    # Build QEMU command
    local qemu_cmd=(
        qemu-system-x86_64
        -name "$vm_name"
        -machine "type=q35,accel=kvm:tcg"
        -m "$VM_MEMORY"
        -smp "$VM_CPUS"
        -cpu "$CPU_FLAGS"
        -drive "file=$vm_disk,format=qcow2,if=$STORAGE_IFACE"
        -drive "file=$seed_file,format=raw,if=$STORAGE_IFACE,readonly=on"
        -boot "order=c"
    )
    
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
    
    # Add GPU
    if [[ $GPU_PASSTHROUGH == true ]] && [[ -n "$GPU_PCI_ADDRESS" ]]; then
        qemu_cmd+=(-device "vfio-pci,host=$GPU_PCI_ADDRESS" -vga none)
    elif [[ -n "$VGPU_OPTIONS" ]]; then
        qemu_cmd+=($VGPU_OPTIONS -display gtk)
    else
        qemu_cmd+=(-nographic -serial mon:stdio)
    fi
    
    # Add other devices
    qemu_cmd+=(
        -device "virtio-balloon-pci"
        -object "rng-random,filename=/dev/urandom,id=rng0"
        -device "virtio-rng-pci,rng=rng0"
        -usb
        -device "qemu-xhci"
    )
    
    # Start VM in background
    print_status "INFO" "Starting VM..."
    "${qemu_cmd[@]}" &
    
    sleep 2
    
    if pgrep -f "qemu-system.*$vm_name" &>/dev/null; then
        print_status "SUCCESS" "VM '$vm_name' started"
        
        if [[ $NET_TYPE == "user" ]] && [[ -n "$SSH_PORT" ]]; then
            echo -e "${CYAN}SSH Access:${NC} ssh -p $SSH_PORT $VM_USERNAME@localhost"
            echo -e "${CYAN}Password:${NC} $VM_PASSWORD"
        fi
    else
        print_status "ERROR" "Failed to start VM"
    fi
}

function stop_vm() {
    list_vms
    
    local vms=($(find "$CONFIG_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        print_status "ERROR" "No VMs available"
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
        return
    fi
    
    local vm_num
    read -p "$(print_status "INPUT" "Enter VM number to stop: ")" vm_num
    
    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [[ $vm_num -ge 1 ]] && [[ $vm_num -le ${#vms[@]} ]]; then
        local vm_name="${vms[$((vm_num-1))]}"
        stop_vm_by_name "$vm_name"
    else
        print_status "ERROR" "Invalid selection"
    fi
    
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

function stop_vm_by_name() {
    local vm_name="$1"
    
    print_header "STOPPING VM: $vm_name"
    
    local pids=$(pgrep -f "qemu-system.*$vm_name")
    
    if [[ -z "$pids" ]]; then
        print_status "WARN" "VM '$vm_name' is not running"
        return
    fi
    
    print_status "INFO" "Stopping VM..."
    kill -TERM $pids 2>/dev/null
    
    sleep 2
    
    if pgrep -f "qemu-system.*$vm_name" &>/dev/null; then
        print_status "WARN" "VM did not stop gracefully, forcing..."
        pkill -9 -f "qemu-system.*$vm_name"
    fi
    
    print_status "SUCCESS" "VM '$vm_name' stopped"
}

function delete_vm() {
    list_vms
    
    local vms=($(find "$CONFIG_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        print_status "ERROR" "No VMs available"
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
        return
    fi
    
    local vm_num
    read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
    
    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [[ $vm_num -ge 1 ]] && [[ $vm_num -le ${#vms[@]} ]]; then
        local vm_name="${vms[$((vm_num-1))]}"
        delete_vm_by_name "$vm_name"
    else
        print_status "ERROR" "Invalid selection"
    fi
    
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

function delete_vm_by_name() {
    local vm_name="$1"
    
    print_header "DELETE VM: $vm_name"
    
    read -p "$(print_status "INPUT" "Are you sure you want to delete '$vm_name'? (y/N): ")" confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "INFO" "Deletion cancelled"
        return
    fi
    
    # Stop VM if running
    stop_vm_by_name "$vm_name"
    
    # Remove files
    rm -f "$CONFIG_DIR/${vm_name}.conf"
    rm -f "$VM_DIR/${vm_name}.qcow2"
    rm -f "$VM_DIR/${vm_name}-seed.iso"
    
    print_status "SUCCESS" "VM '$vm_name' deleted"
}

function show_vm_info() {
    list_vms
    
    local vms=($(find "$CONFIG_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        print_status "ERROR" "No VMs available"
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
        return
    fi
    
    local vm_num
    read -p "$(print_status "INPUT" "Enter VM number for info: ")" vm_num
    
    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [[ $vm_num -ge 1 ]] && [[ $vm_num -le ${#vms[@]} ]]; then
        local vm_name="${vms[$((vm_num-1))]}"
        show_vm_info_by_name "$vm_name"
    else
        print_status "ERROR" "Invalid selection"
    fi
    
    read -p "$(print_status "INPUT" "Press Enter to continue...")"
}

function show_vm_info_by_name() {
    local vm_name="$1"
    local config_file="$CONFIG_DIR/${vm_name}.conf"
    
    if [[ ! -f "$config_file" ]]; then
        print_status "ERROR" "VM not found"
        return
    fi
    
    source "$config_file"
    
    print_header "VM INFORMATION: $vm_name"
    
    # Status
    local status="${RED}Stopped${NC}"
    if pgrep -f "qemu-system.*$vm_name" &>/dev/null; then
        status="${GREEN}Running${NC}"
    fi
    
    echo -e "${CYAN}Status:${NC} $status"
    echo -e "${CYAN}Description:${NC} $VM_DESCRIPTION"
    echo -e "${CYAN}Created:${NC} $CREATED"
    echo ""
    
    # Configuration
    echo -e "${WHITE}Configuration:${NC}"
    echo -e "  ${CYAN}OS:${NC} $SELECTED_OS"
    echo -e "  ${CYAN}CPU:${NC} $SELECTED_CPU ($VM_CPUS cores)"
    echo -e "  ${CYAN}Memory:${NC} $VM_MEMORY MB"
    echo -e "  ${CYAN}Disk:${NC} $DISK_SIZE ($STORAGE_IFACE)"
    echo -e "  ${CYAN}Network:${NC} $NET_TYPE"
    
    if [[ $NET_TYPE == "user" ]] && [[ -n "$SSH_PORT" ]]; then
        echo -e "  ${CYAN}SSH Port:${NC} $SSH_PORT"
    fi
    
    if [[ $NET_TYPE == "bridge" ]]; then
        echo -e "  ${CYAN}Bridge:${NC} $BRIDGE_IFACE"
    fi
    
    # GPU
    if [[ $GPU_PASSTHROUGH == true ]]; then
        echo -e "  ${CYAN}GPU:${NC} Passthrough ($GPU_PCI_ADDRESS)"
    elif [[ -n "$VGPU_TYPE" ]]; then
        echo -e "  ${CYAN}GPU:${NC} Virtual ($VGPU_TYPE)"
    else
        echo -e "  ${CYAN}GPU:${NC} Console only"
    fi
    
    # Security
    echo -e "  ${CYAN}TPM 2.0:${NC} $TPM_ENABLED"
    echo -e "  ${CYAN}Secure Boot:${NC} $SECUREBOOT_ENABLED"
    
    # Access info
    if [[ $NET_TYPE == "user" ]] && [[ -n "$SSH_PORT" ]]; then
        echo ""
        echo -e "${WHITE}Access Information:${NC}"
        echo -e "  ${CYAN}Username:${NC} $VM_USERNAME"
        echo -e "  ${CYAN}Password:${NC} $VM_PASSWORD"
        echo -e "  ${CYAN}SSH Command:${NC} ssh -p $SSH_PORT $VM_USERNAME@localhost"
    fi
    
    echo ""
    echo -e "${WHITE}Files:${NC}"
    echo -e "  ${CYAN}Config:${NC} $config_file"
    echo -e "  ${CYAN}Disk:${NC} $VM_DIR/${vm_name}.qcow2"
    echo -e "  ${CYAN}Seed:${NC} $VM_DIR/${vm_name}-seed.iso"
}

function show_vm_summary() {
    print_header "VM CREATION SUMMARY"
    
    echo -e "${CYAN}VM Name:${NC} $VM_NAME"
    echo -e "${CYAN}Description:${NC} $VM_DESCRIPTION"
    echo -e "${CYAN}OS:${NC} $SELECTED_OS"
    echo -e "${CYAN}Resources:${NC} ${VM_MEMORY}MB RAM, ${VM_CPUS} vCPUs"
    echo -e "${CYAN}Storage:${NC} $DISK_SIZE ($STORAGE_IFACE)"
    echo -e "${CYAN}CPU Model:${NC} $SELECTED_CPU"
    echo -e "${CYAN}Network:${NC} $NET_TYPE"
    
    if [[ $NET_TYPE == "user" ]] && [[ -n "$SSH_PORT" ]]; then
        echo -e "${CYAN}SSH Access:${NC} ssh -p $SSH_PORT $VM_USERNAME@localhost"
    fi
    
    if [[ $NET_TYPE == "bridge" ]]; then
        echo -e "${CYAN}Bridge:${NC} $BRIDGE_IFACE"
    fi
    
    if [[ $GPU_PASSTHROUGH == true ]]; then
        echo -e "${CYAN}GPU:${NC} Passthrough enabled"
    elif [[ -n "$VGPU_TYPE" ]]; then
        echo -e "${CYAN}GPU:${NC} Virtual ($VGPU_TYPE)"
    fi
}

# ============================================================
# Main Menu
# ============================================================

function main_menu() {
    while true; do
        display_banner
        print_menu
        
        local choice
        read -p "$(print_status "INPUT" "Select option (1-8): ")" choice
        
        case $choice in
            1) create_vm ;;
            2) list_vms ;;
            3) start_vm ;;
            4) stop_vm ;;
            5) delete_vm ;;
            6) show_vm_info ;;
            7) detect_hardware ;;
            8)
                print_status "INFO" "Goodbye!"
                cleanup
                exit 0
                ;;
            *)
                print_status "ERROR" "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# ============================================================
# Main Entry Point
# ============================================================

function main() {
    # Initialize
    init_environment
    
    # Check dependencies
    if ! check_dependencies; then
        print_status "ERROR" "Please install required dependencies"
        exit 1
    fi
    
    # Detect hardware
    detect_hardware
    
    # Start main menu
    main_menu
}

# Run main function
main
