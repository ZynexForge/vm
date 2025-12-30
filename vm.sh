#!/bin/bash
set -euo pipefail

# ================================================
# ZYNEXFORGE VM ENGINE
# Advanced QEMU/KVM Virtualization Manager
# Version: 6.4
# Author: FaaizJohar
# Optimized for AMD EPYC
# ================================================

# Global Variables
VM_DIR="${VM_DIR:-$HOME/zynexforge-vms}"
CONFIG_DIR="$VM_DIR/configs"
LOG_DIR="$VM_DIR/logs"
SCRIPT_VERSION="6.4"
BRAND_PREFIX="ZynexForge-"

# EPYC CPU Model (try different AMD CPU models for better compatibility)
EPYC_CPU_MODELS=("EPYC" "EPYC-Rome" "EPYC-Milan" "EPYC-Genoa" "host")
EPYC_CPU_FLAGS="+invtsc,+topoext,+svm,+kvm,+pmu,+x2apic,+ibpb,+virt-ssbd,+amd-ssbd,+amd-no-ssb"

# Network settings
DEFAULT_IP="10.0.2.15"
DEFAULT_GATEWAY="10.0.2.2"
DEFAULT_DNS="8.8.8.8,8.8.4.4"
QEMU_DNS="8.8.8.8"
QEMU_NET="10.0.2.0/24"
QEMU_HOST="10.0.2.2"

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

        ZynexForge VM Engine v6.4 | AMD EPYC Optimized | Powered by FaaizXD
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

# Enhanced AMD EPYC CPU detection and configuration
check_epyc() {
    print_info "Checking CPU and virtualization capabilities..."
    
    # Get detailed CPU information
    local cpu_vendor=$(grep -m1 "vendor_id" /proc/cpuinfo | cut -d: -f2 | xargs)
    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
    
    print_info "CPU Vendor: $cpu_vendor"
    print_info "CPU Model: $cpu_model"
    
    if [[ "$cpu_vendor" == "AuthenticAMD" ]]; then
        if echo "$cpu_model" | grep -qi "EPYC"; then
            print_success "AMD EPYC processor detected!"
            
            # Determine EPYC generation
            if echo "$cpu_model" | grep -qi "Genoa"; then
                SELECTED_CPU_MODEL="EPYC-Genoa"
                print_info "EPYC Generation: Genoa (Zen 4)"
            elif echo "$cpu_model" | grep -qi "Milan"; then
                SELECTED_CPU_MODEL="EPYC-Milan"
                print_info "EPYC Generation: Milan (Zen 3)"
            elif echo "$cpu_model" | grep -qi "Rome"; then
                SELECTED_CPU_MODEL="EPYC-Rome"
                print_info "EPYC Generation: Rome (Zen 2)"
            else
                SELECTED_CPU_MODEL="EPYC"
                print_info "EPYC Generation: Generic"
            fi
            
            # Check AMD-V (SVM)
            if grep -q "svm" /proc/cpuinfo; then
                print_success "AMD-V (SVM) virtualization enabled"
            else
                print_warn "AMD-V not enabled in BIOS/UEFI - virtualization will be slow"
            fi
            
            # Check CPU flags
            local cpu_flags=$(grep -m1 "flags" /proc/cpuinfo)
            if echo "$cpu_flags" | grep -q "topoext"; then
                print_info "✓ Topology extensions available"
            fi
            if echo "$cpu_flags" | grep -q "svm"; then
                print_info "✓ SVM (AMD-V) available"
            fi
            if echo "$cpu_flags" | grep -q "x2apic"; then
                print_info "✓ x2APIC available"
            fi
            
        else
            print_warn "AMD processor detected but not EPYC - using generic AMD optimizations"
            SELECTED_CPU_MODEL="host"
        fi
    elif [[ "$cpu_vendor" == "GenuineIntel" ]]; then
        print_warn "Intel processor detected - AMD EPYC optimizations limited"
        SELECTED_CPU_MODEL="host"
        EPYC_CPU_FLAGS="+vmx,+kvm,+invtsc"
    else
        print_warn "Unknown processor - using generic CPU"
        SELECTED_CPU_MODEL="max"
    fi
    
    # Check KVM availability
    if [ -e /dev/kvm ]; then
        print_success "KVM acceleration available"
        if lsmod | grep -q "kvm_amd"; then
            print_info "KVM AMD module loaded"
        elif lsmod | grep -q "kvm_intel"; then
            print_info "KVM Intel module loaded"
        fi
    else
        print_error "KVM not available - performance will be poor"
        print_info "Check: lsmod | grep kvm"
        print_info "Ensure virtualization is enabled in BIOS/UEFI"
        print_info "For AMD: sudo modprobe kvm_amd"
        print_info "For Intel: sudo modprobe kvm_intel"
        SELECTED_CPU_MODEL="max"  # Fallback to software emulation
    fi
}

# Check dependencies
check_deps() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "openssl" "cpuid")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        print_error "Missing: ${missing[*]}"
        print_info "Install: sudo apt install qemu-system cloud-image-utils wget openssl cpuid"
        exit 1
    fi
}

# Validation functions
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
        "ip")
            [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
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

# Download image with retry
download_image() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0
    
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
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD 2>/dev/null
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED 2>/dev/null
        unset VM_IP VM_GATEWAY VM_DNS CPU_TYPE 2>/dev/null
        
        source "$config"
        
        VM_IP="${VM_IP:-$DEFAULT_IP}"
        VM_GATEWAY="${VM_GATEWAY:-$DEFAULT_GATEWAY}"
        VM_DNS="${VM_DNS:-$DEFAULT_DNS}"
        GUI_MODE="${GUI_MODE:-false}"
        PORT_FORWARDS="${PORT_FORWARDS:-}"
        CPU_TYPE="${CPU_TYPE:-$SELECTED_CPU_MODEL}"
        
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
VM_IP="$VM_IP"
VM_GATEWAY="$VM_GATEWAY"
VM_DNS="$VM_DNS"
CPU_TYPE="$CPU_TYPE"
EOF
    
    chmod 600 "$config"
    print_success "Configuration saved: $config"
    log_message "CONFIG" "Saved: $VM_NAME"
}

# Create VM with enhanced CPU options
create_vm() {
    display_banner
    print_info "Creating new ZynexForge VM"
    
    # OS selection
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
    
    # VM name
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
            print_error "VM name can only contain letters, numbers, hyphens, underscores"
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
        print_error "Invalid username format"
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
        print_error "Must be a size with unit (e.g., 50G, 100G)"
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
    
    # CPU Type Selection - ENHANCED
    print_info "CPU Configuration for AMD EPYC:"
    echo "  1) Host CPU Passthrough (Best performance, shows actual CPU)"
    echo "  2) EPYC-Genoa (Zen 4 - Most recent EPYC)"
    echo "  3) EPYC-Milan (Zen 3)"
    echo "  4) EPYC-Rome (Zen 2)"
    echo "  5) EPYC (Generic AMD EPYC)"
    echo "  6) Custom CPU model"
    
    local cpu_choice
    while true; do
        read -p "$(print_input "Select CPU type (1-6, default: 1): ")" cpu_choice
        cpu_choice="${cpu_choice:-1}"
        case $cpu_choice in
            1)
                CPU_TYPE="host"
                print_info "Selected: Host CPU passthrough"
                break
                ;;
            2)
                CPU_TYPE="EPYC-Genoa"
                print_info "Selected: AMD EPYC-Genoa (Zen 4)"
                break
                ;;
            3)
                CPU_TYPE="EPYC-Milan"
                print_info "Selected: AMD EPYC-Milan (Zen 3)"
                break
                ;;
            4)
                CPU_TYPE="EPYC-Rome"
                print_info "Selected: AMD EPYC-Rome (Zen 2)"
                break
                ;;
            5)
                CPU_TYPE="EPYC"
                print_info "Selected: Generic AMD EPYC"
                break
                ;;
            6)
                read -p "$(print_input "Enter custom CPU model (e.g., EPYC, host, max): ")" custom_cpu
                CPU_TYPE="${custom_cpu:-host}"
                print_info "Selected: Custom CPU model '$CPU_TYPE'"
                break
                ;;
            *)
                print_error "Invalid selection. Try again."
                ;;
        esac
    done
    
    # Network settings
    print_info "Network Configuration:"
    print_info "Using QEMU NAT network for internet access"
    VM_IP="$DEFAULT_IP"
    VM_GATEWAY="$QEMU_HOST"
    VM_DNS="$QEMU_DNS"
    
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
    print_info "CPU Model: $CPU_TYPE (will be exposed to guest)"
    print_info "To start: Select VM from main menu"
}

# Setup VM image with AMD CPU optimizations
setup_vm() {
    print_info "Preparing VM image with AMD EPYC optimizations..."
    
    mkdir -p "$(dirname "$IMG_FILE")" "$(dirname "$SEED_FILE")"
    
    # Download image if not exists
    if [[ ! -f "$IMG_FILE" ]]; then
        print_info "Downloading OS image: $OS_TYPE"
        if ! download_image "$IMG_URL" "$IMG_FILE"; then
            print_error "Failed to download image"
            exit 1
        fi
    else
        print_info "Image already exists, skipping download"
    fi
    
    # Resize disk
    print_info "Configuring disk to $DISK_SIZE..."
    if ! qemu-img resize -f qcow2 "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
        print_info "Creating new disk image with specified size..."
        qemu-img create -f qcow2 -o preallocation=metadata "$IMG_FILE" "$DISK_SIZE"
    fi
    
    # Generate password hash
    local pass_hash
    if command -v openssl &> /dev/null; then
        pass_hash=$(openssl passwd -6 "$PASSWORD" 2>/dev/null || echo "$PASSWORD")
    elif command -v mkpasswd &> /dev/null; then
        pass_hash=$(mkpasswd -m sha-512 "$PASSWORD" 2>/dev/null || echo "$PASSWORD")
    else
        pass_hash="$PASSWORD"
        print_warn "Using plain password (install 'openssl' for secure hashing)"
    fi
    
    # Create cloud-init config with AMD CPU optimizations
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
manage_etc_hosts: true
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - neofetch
  - cpuid
  - lscpu
  - inxi
  - hwinfo
  - dmidecode
  - msr-tools
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  # Create custom CPU info for neofetch
  - echo "Creating AMD EPYC CPU information..."
  - echo "vendor_id       : AuthenticAMD" > /tmp/cpuinfo_amd
  - echo "cpu family      : 23" >> /tmp/cpuinfo_amd
  - echo "model           : 49" >> /tmp/cpuinfo_amd
  - echo "model name      : AMD EPYC Processor (with IBPB)" >> /tmp/cpuinfo_amd
  - echo "stepping        : 0" >> /tmp/cpuinfo_amd
  - echo "microcode       : 0x8301036" >> /tmp/cpuinfo_amd
  - echo "cpu MHz         : 2800.000" >> /tmp/cpuinfo_amd
  - echo "cache size      : 512 KB" >> /tmp/cpuinfo_amd
  - echo "physical id     : 0" >> /tmp/cpuinfo_amd
  - echo "siblings        : $CPUS" >> /tmp/cpuinfo_amd
  - echo "core id         : 0" >> /tmp/cpuinfo_amd
  - echo "cpu cores       : $CPUS" >> /tmp/cpuinfo_amd
  - echo "apicid          : 0" >> /tmp/cpuinfo_amd
  - echo "initial apicid  : 0" >> /tmp/cpuinfo_amd
  - echo "fpu             : yes" >> /tmp/cpuinfo_amd
  - echo "fpu_exception   : yes" >> /tmp/cpuinfo_amd
  - echo "cpuid level     : 16" >> /tmp/cpuinfo_amd
  - echo "wp              : yes" >> /tmp/cpuinfo_amd
  - echo "flags           : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx mmxext fxsr_opt pdpe1gb rdtscp lm constant_tsc rep_good nopl nonstop_tsc cpuid extd_apicid aperfmperf rapl pni pclmulqdq monitor ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave avx f16c rdrand lahf_lm cmp_legacy svm extapic cr8_legacy abm sse4a misalignsse 3dnowprefetch osvw skinit wdt tce topoext perfctr_core perfctr_nb bpext perfctr_llc mwaitx cpb hw_pstate ssbd ibpb vmmcall fsgsbase bmi1 avx2 smep bmi2 erms invpcid cqm rdt_a rdseed adx smap clflushopt clwb sha_ni xsaveopt xsavec xgetbv1 xsaves cqm_llc cqm_occup_llc cqm_mbm_total cqm_mbm_local clzero irperf xsaveerptr rdpru wbnoinvd arat npt lbrv svm_lock nrip_save tsc_scale vmcb_clean flushbyasid decodeassists pausefilter pfthreshold avic v_vmsave_vmload vgif v_spec_ctrl umip rdpid overflow_recov succor smca" >> /tmp/cpuinfo_amd
  - echo "bugs            : sysret_ss_attrs null_seg spectre_v1 spectre_v2 spec_store_bypass retbleed" >> /tmp/cpuinfo_amd
  - echo "bogomips        : 5600.00" >> /tmp/cpuinfo_amd
  - echo "TLB size        : 2560 4K pages" >> /tmp/cpuinfo_amd
  - echo "clflush size    : 64" >> /tmp/cpuinfo_amd
  - echo "cache_alignment : 64" >> /tmp/cpuinfo_amd
  - echo "address sizes   : 48 bits physical, 48 bits virtual" >> /tmp/cpuinfo_amd
  - echo "power management: ts ttp tm hwpstate cpb eff_freq_ro [13] [14]" >> /tmp/cpuinfo_amd
  # Create custom neofetch config
  - mkdir -p /etc/neofetch
  - echo '--cpu_brand="AMD"' > /etc/neofetch/config.conf
  - echo '--cpu_cores="$CPUS"' >> /etc/neofetch/config.conf
  - echo '--cpu_speed="2800"' >> /etc/neofetch/config.conf
  - echo '--cpu_temp="C"' >> /etc/neofetch/config.conf
  - echo '--cpu_display="on"' >> /etc/neofetch/config.conf
  - echo '--cpu_model="AMD EPYC"' >> /etc/neofetch/config.conf
  # Create motd
  - echo "╔══════════════════════════════════════════════════════════════╗" > /etc/motd
  - echo "║                    ZynexForge VM Engine                      ║" >> /etc/motd
  - echo "║                    Powered by AMD EPYC                       ║" >> /etc/motd
  - echo "╠══════════════════════════════════════════════════════════════╣" >> /etc/motd
  - echo "║ Hostname: $HOSTNAME                                         ║" >> /etc/motd
  - echo "║ Username: $USERNAME                                         ║" >> /etc/motd
  - echo "║ CPU: AMD EPYC (${CPUS} cores @ 2.8GHz)                      ║" >> /etc/motd
  - echo "║ Memory: ${MEMORY}MB RAM                                      ║" >> /etc/motd
  - echo "║ Disk: $DISK_SIZE                                            ║" >> /etc/motd
  - echo "╚══════════════════════════════════════════════════════════════╝" >> /etc/motd
  - echo "" >> /etc/motd
EOF
    
    cat > /tmp/meta-data <<EOF
instance-id: $VM_NAME
local-hostname: $HOSTNAME
EOF
    
    # Create seed image
    print_info "Creating cloud-init seed image..."
    if cloud-localds "$SEED_FILE" /tmp/user-data /tmp/meta-data; then
        print_success "Cloud-init seed created with AMD CPU optimizations"
    else
        print_error "Failed to create cloud-init seed image"
        exit 1
    fi
    
    rm -f /tmp/user-data /tmp/meta-data
    print_success "VM setup complete with AMD EPYC optimizations"
    log_message "CREATE" "Created VM: $VM_NAME ($OS_TYPE) with CPU: $CPU_TYPE"
}

# Start VM with AMD CPU exposure
start_vm() {
    local vm="$1"
    
    if load_config "$vm"; then
        if is_vm_running "$vm"; then
            print_warn "$vm is already running"
            return 0
        fi
        
        rm -f "$VM_DIR/$vm.pid" 2>/dev/null
        
        # Verify files exist
        if [[ ! -f "$IMG_FILE" ]]; then
            print_error "VM image file not found"
            setup_vm
        fi
        
        if [[ ! -f "$SEED_FILE" ]]; then
            print_warn "Seed file not found, recreating..."
            setup_vm
        fi
        
        print_info "Starting ZynexForge VM: $vm"
        print_info "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_info "Password: $PASSWORD"
        print_info "CPU Model: $CPU_TYPE"
        
        # Build QEMU command with enhanced AMD CPU exposure
        local qemu_cmd=(
            qemu-system-x86_64
            -name "$vm,process=ZynexForge-$vm"
            -enable-kvm
            # Enhanced CPU configuration for AMD
            -cpu "$CPU_TYPE,$EPYC_CPU_FLAGS"
            -smp "$CPUS,sockets=1,cores=$CPUS,threads=1"
            -m "$MEMORY"
            -drive "file=$IMG_FILE,if=virtio,format=qcow2,cache=directsync"
            -drive "file=$SEED_FILE,if=virtio,format=raw,readonly=on"
            # Networking
            -netdev "user,id=net0,net=$QEMU_NET,host=$QEMU_HOST,dns=$QEMU_DNS,hostfwd=tcp::$SSH_PORT-:22"
            -device "virtio-net-pci,netdev=net0,mac=52:54:00:$(printf '%02x' $((RANDOM%256))):$(printf '%02x' $((RANDOM%256))):$(printf '%02x' $((RANDOM%256)))"
            # Performance optimizations
            -device virtio-balloon-pci
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
            -rtc base=utc,clock=host
            -nodefaults
            -boot order=c
            # Machine and firmware
            -machine "type=q35,accel=kvm,kernel_irqchip=on"
            # SMBIOS for AMD branding
            -smbios "type=0,vendor=AMD"
            -smbios "type=1,manufacturer=AMD,product=EPYC,version=ZynexForge,serial=ZFX-$(echo $VM_NAME | md5sum | cut -c1-8),sku=ZFX-EPYC"
            -smbios "type=4,manufacturer=AMD,sock_pfx=SP3,version=EPYC"
        )
        
        # Add port forwards
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
        
        print_info "Starting QEMU with AMD EPYC CPU exposure..."
        echo ""
        print_info "══════════════════════════════════════════════════"
        print_info "VM '$vm' is now running!"
        print_info "SSH Connection: ssh -p $SSH_PORT $USERNAME@localhost"
        print_info "Password: $PASSWORD"
        print_info ""
        print_info "Inside the VM, check CPU with:"
        print_info "  neofetch                    # Should show AMD EPYC"
        print_info "  cat /proc/cpuinfo           # CPU information"
        print_info "  lscpu                       # CPU architecture"
        print_info "  cpuid                       # CPU capabilities"
        print_info "  inxi -C                     # CPU details"
        print_info ""
        print_info "Note: We've patched neofetch to show AMD EPYC"
        print_info ""
        if [[ "$GUI_MODE" == false ]]; then
            print_info "To exit: Press 'Ctrl+A' then 'X'"
        fi
        print_info "══════════════════════════════════════════════════"
        echo ""
        
        # Run QEMU
        "${qemu_cmd[@]}"
        
        print_info "VM $vm has been shut down"
        log_message "STOP" "VM stopped: $vm"
    fi
}

# Stop VM
stop_vm() {
    local vm="$1"
    
    if load_config "$vm"; then
        if is_vm_running "$vm"; then
            print_info "Stopping VM: $vm"
            
            pkill -f "qemu-system-x86_64.*$vm"
            
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
        
        rm -f "$VM_DIR/$vm.pid" 2>/dev/null
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
        printf "│ %-20s: %-30s │\n" "CPU Model" "$CPU_TYPE"
        printf "│ %-20s: %-30s │\n" "Network" "QEMU NAT"
        printf "│ %-20s: %-30s │\n" "Created" "$CREATED"
        printf "│ %-20s: %-30s │\n" "Port Forwards" "${PORT_FORWARDS:-None}"
        echo "├─────────────────────────────────────────────────────┤"
        echo "│ CONNECTION INFO                                     │"
        echo "├─────────────────────────────────────────────────────┤"
        echo "│ SSH: ssh -p $SSH_PORT $USERNAME@localhost           │"
        echo "│ Password: $PASSWORD                                 │"
        echo "│ Note: VM shows AMD EPYC CPU in neofetch            │"
        echo "└─────────────────────────────────────────────────────┘"
        echo ""
        
        read -p "$(print_input "Press Enter to continue...")"
    fi
}

# Main menu
main_menu() {
    while true; do
        display_banner
        
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
            
            # Show CPU info
            print_info "Host System:"
            local cpu_info=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//')
            print_info "CPU: $cpu_info"
            if grep -qi "AMD" /proc/cpuinfo; then
                print_success "AMD processor detected - EPYC optimizations available"
            fi
        else
            print_info "No VMs found. Create your first VM to get started."
            echo ""
        fi
        
        # Menu options
        echo "ZynexForge VM Engine v$SCRIPT_VERSION - Main Menu"
        echo "══════════════════════════════════════════════════"
        echo "  1) Create new ZynexForge VM (AMD EPYC optimized)"
        
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
                        start_vm "${vms[$((vm_num-1))]}"
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
                        # Edit function would go here
                        print_info "Edit feature coming soon!"
                    else
                        print_error "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        # Delete function would go here
                        print_info "Delete feature coming soon!"
                    else
                        print_error "Invalid selection"
                    fi
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "Enter VM number to resize disk: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        # Resize function would go here
                        print_info "Resize feature coming soon!"
                    else
                        print_error "Invalid selection"
                    fi
                fi
                ;;
            8)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_input "Enter VM number to show performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        # Performance function would go here
                        print_info "Performance feature coming soon!"
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
