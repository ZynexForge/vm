#!/bin/bash
set -euo pipefail

# ZynexForge CloudStack™ Platform
# Non-Root Edition
# Made by FaaizXD

# Global Configuration
USER_HOME="$HOME"
CONFIG_DIR="$USER_HOME/.zynexforge"
DATA_DIR="$USER_HOME/.zynexforge/data"
LOG_FILE="$USER_HOME/.zynexforge/zynexforge.log"
NODES_DB="$CONFIG_DIR/nodes.yml"
GLOBAL_CONFIG="$CONFIG_DIR/config.yml"
SSH_KEY_FILE="$USER_HOME/.ssh/zynexforge_ed25519"

# ASCII Art Definitions
ASCII_MAIN_ART=$(cat << 'EOF'
__________                           ___________                         
\____    /__.__. ____   ____ ___  __\_   _____/__________  ____   ____  
  /     /<   |  |/    \_/ __ \\  \/  /|    __)/  _ \_  __ \/ ___\_/ __ \ 
 /     /_ \___  |   |  \  ___/ >    < |     \(  <_> )  | \/ /_/  >  ___/ 
/_______ \/ ____|___|  /\___  >__/\_ \\___  / \____/|__|  \___  / \___  >
        \/\/         \/     \/      \/    \/             /_____/      \/ 
EOF
)

OS_ASCII_ART=$(cat << 'EOF'
                        %@@@@@                      
                  @%*+:........:+#@@                
                @+:.....-=++=-:*%#-::#@             
             @@*...:=@@@@@@@@%*:......:*@           
            @#:...*@@@@@@@#-.....-#%#:..:*          
           @%...=%@@@@%*.....:=@@@@@@@+..:#         
          @@...=@@@%=.....-*%@@%+:..:+%*...%        
        ::@+...@%-##...=@@@@@@@+........=%-:%       
       #:=@-..=@@#%#*@@@@@@@@@@@@@@@#-....:#@       
       #-*@-..:@@@@@@@@@@@@@@@@@@@#:-%@%-...+@      
       %--@+....-#@@@@@@@@@@@@@@@@#..:#@@=..-#      
       @+.+@@*:....-#@@@@@@@@@@@@@#..:#@@+..-#      
       @@-..=%@@*:..+@@@@@@@@@@@%@#..:#@@+..=#      
       @@@=....=#@@@@@@@@@@@%+:.-@#..:#@%-..=       
        @@@@:......#@@@@@%-.....=@#..:%@+..:%       
         @+.+##=:..-*@*-.....-#@@%:..=@+..-%        
          @+...:+%@=:.....+%@@@@+...:@=..=%         
           @%-........-*@@@@%#-....=#..:*@          
             @#+...+#*-:::...........-*%            
                @@#:..............:*@               
                   @%#+++===+++*%@                  
EOF
)

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" >/dev/null
}

# Print colored messages
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️ $1${NC}"
}

print_header() {
    clear
    echo -e "${CYAN}"
    echo "$ASCII_MAIN_ART"
    echo -e "${NC}"
    echo -e "${YELLOW}⚡ ZynexForge CloudStack™${NC}"
    echo -e "${WHITE}🔥 Made by FaaizXD${NC}"
    echo "=============================================="
    
    # System capabilities summary
    echo -e "${BLUE}🖥️ System Capabilities:${NC}"
    
    # Check KVM access
    if [[ -r "/dev/kvm" ]] && groups | grep -q -E "(kvm|libvirt)"; then
        echo -e "  ⚡ KVM: Available (Hardware Acceleration)"
    else
        echo -e "  ⚡ KVM: Not Available (Software Emulation)"
    fi
    
    # Check Docker access
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        echo -e "  🐳 Docker: Available"
    else
        echo -e "  🐳 Docker: Not Available"
    fi
    
    # Check QEMU
    if command -v qemu-system-x86_64 >/dev/null 2>&1; then
        echo -e "  🖥️ QEMU: Available"
    else
        echo -e "  🖥️ QEMU: Not Available"
    fi
    
    local vm_count=0
    local docker_count=0
    
    if [[ -d "$DATA_DIR/vms" ]]; then
        vm_count=$(find "$DATA_DIR/vms" -name "*.conf" -type f 2>/dev/null | wc -l)
    fi
    
    if [[ -d "$DATA_DIR/dockervm" ]]; then
        docker_count=$(find "$DATA_DIR/dockervm" -name "*.conf" -type f 2>/dev/null | wc -l)
    fi
    
    echo -e "  📊 Active VMs: $vm_count"
    echo -e "  📊 Docker VMs: $docker_count"
    echo "=============================================="
    echo ""
}

# Initialize platform
initialize_platform() {
    log "Initializing ZynexForge CloudStack™ Platform (Non-Root Edition)"
    
    # Create directory structure
    mkdir -p "$CONFIG_DIR" \
             "$DATA_DIR/vms" \
             "$DATA_DIR/disks" \
             "$DATA_DIR/cloudinit" \
             "$DATA_DIR/dockervm" \
             "$DATA_DIR/lxd" \
             "$DATA_DIR/jupyter" \
             "$USER_HOME/zynexforge/templates/cloud" \
             "$USER_HOME/zynexforge/templates/iso" \
             "$USER_HOME/zynexforge/logs"
    
    # Create default config if not exists
    if [[ ! -f "$GLOBAL_CONFIG" ]]; then
        cat > "$GLOBAL_CONFIG" << EOF
# ZynexForge Global Configuration
platform:
  name: "ZynexForge CloudStack™"
  version: "1.0.0"
  default_node: "local"
  ssh_base_port: 22000
  max_vms_per_node: 50
  user_mode: true
  user_home: "$USER_HOME"

security:
  firewall_enabled: false
  default_ssh_user: "zynexuser"
  password_min_length: 8
  use_ssh_keys: true

paths:
  templates: "$USER_HOME/zynexforge/templates/cloud"
  isos: "$USER_HOME/zynexforge/templates/iso"
  vm_configs: "$DATA_DIR/vms"
  vm_disks: "$DATA_DIR/disks"
  logs: "$USER_HOME/zynexforge/logs"
EOF
    fi
    
    # Create nodes database if not exists
    if [[ ! -f "$NODES_DB" ]]; then
        cat > "$NODES_DB" << EOF
nodes:
  local:
    node_id: "local"
    node_name: "Local Node"
    location_name: "Local, Server"
    provider: "Self-Hosted"
    public_ip: "127.0.0.1"
    capabilities: ["kvm", "qemu", "lxd", "docker"]
    tags: ["production"]
    status: "active"
    created_at: "$(date -Iseconds)"
    user_mode: true
EOF
    fi
    
    # Generate SSH key if not exists
    if [[ ! -f "$SSH_KEY_FILE" ]]; then
        echo "Generating SSH key for ZynexForge..."
        ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q
        chmod 600 "$SSH_KEY_FILE"
        chmod 644 "${SSH_KEY_FILE}.pub"
        print_success "SSH key generated"
    fi
    
    # Check dependencies
    check_dependencies
}

# Check and install required packages
check_dependencies() {
    print_info "Checking dependencies..."
    
    local missing_packages=()
    local required_tools=("qemu-system-x86_64" "qemu-img" "cloud-localds" "genisoimage" "ssh-keygen")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            missing_packages+=("$tool")
        fi
    done
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        print_warning "Missing packages: ${missing_packages[*]}"
        
        if command -v apt-get >/dev/null 2>&1; then
            print_info "Installing packages on Debian/Ubuntu..."
            sudo apt-get update
            sudo apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils genisoimage openssh-client
        elif command -v dnf >/dev/null 2>&1; then
            print_info "Installing packages on Fedora/RHEL..."
            sudo dnf install -y qemu-system-x86 qemu-img cloud-utils genisoimage openssh-clients
        elif command -v yum >/dev/null 2>&1; then
            print_info "Installing packages on CentOS..."
            sudo yum install -y qemu-kvm qemu-img cloud-utils genisoimage openssh-clients
        elif command -v pacman >/dev/null 2>&1; then
            print_info "Installing packages on Arch..."
            sudo pacman -S --noconfirm qemu qemu-arch-extra cloud-init cdrtools openssh
        else
            print_error "Unsupported package manager"
            print_info "Please install manually: qemu-system-x86, qemu-utils, cloud-image-utils, genisoimage"
        fi
    else
        print_success "All required tools are available"
    fi
    
    # Check for Docker
    if ! command -v docker >/dev/null 2>&1; then
        print_warning "Docker not installed. Docker VM features will be limited."
    fi
}

# Check if a port is available
check_port_available() {
    local port=$1
    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":${port} "; then
            return 1
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":${port} "; then
            return 1
        fi
    fi
    return 0
}

# Find an available port
find_available_port() {
    local base_port=${1:-22000}
    local max_port=23000
    local port=$base_port
    
    while [[ $port -le $max_port ]]; do
        if check_port_available "$port"; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
    done
    
    # If no port found, use a random one above 30000
    echo $((RANDOM % 10000 + 30000))
}

# Main menu
main_menu() {
    while true; do
        print_header
        echo -e "${GREEN}Main Menu:${NC}"
        echo "  1) ⚡ KVM + QEMU VM Cloud"
        echo "  2) 🖥️ QEMU VM Cloud (Universal)"
        echo "  3) 🧊 LXD Cloud (VMs/Containers)"
        echo "  4) 🖥️ Docker VM Cloud (Container VPS)"
        echo "  5) 🖥️ Jupyter Cloud Lab"
        echo ""
        echo "  6) 🖥️ Nodes (Locations + Join)"
        echo "  7) ⚙️ Templates + ISO Library"
        echo "  8) 🛡️ Security"
        echo "  9) 📊 Monitoring"
        echo "  10) ⚙️ VM Manager (Lifecycle Menu)"
        echo ""
        echo "  0) ❌ Exit"
        echo ""
        
        read -p "Select option: " choice
        
        case $choice in
            1) kvm_qemu_menu ;;
            2) qemu_universal_menu ;;
            3) lxd_cloud_menu ;;
            4) docker_vm_menu ;;
            5) jupyter_cloud_menu ;;
            6) nodes_menu ;;
            7) templates_menu ;;
            8) security_menu ;;
            9) monitoring_menu ;;
            10) vm_manager_menu ;;
            0) 
                echo "Exiting ZynexForge CloudStack™"
                exit 0
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# Nodes Management
nodes_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🖥️ Nodes Management:${NC}"
        echo "  1) Add Node (Create Node Record)"
        echo "  2) List Nodes"
        echo "  3) Show Node Details"
        echo "  4) Remove Node"
        echo "  0) Back"
        echo ""
        
        read -p "Select option: " choice
        
        case $choice in
            1) add_node ;;
            2) list_nodes ;;
            3) show_node_details ;;
            4) remove_node ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# Region/location presets
declare -A REGIONS=(
    [1]="🇮🇳 Mumbai, India"
    [2]="🇮🇳 Delhi NCR, India"
    [3]="🇮🇳 Bangalore, India"
    [4]="🇸🇬 Singapore"
    [5]="🇩🇪 Frankfurt, Germany"
    [6]="🇳🇱 Amsterdam, Netherlands"
    [7]="🇬🇧 London, UK"
    [8]="🇺🇸 New York, USA"
    [9]="🇺🇸 Los Angeles, USA"
    [10]="🇨🇦 Toronto, Canada"
    [11]="🇯🇵 Tokyo, Japan"
    [12]="🇦🇺 Sydney, Australia"
)

add_node() {
    print_header
    echo -e "${GREEN}➕ Add New Node${NC}"
    echo ""
    
    # Select region
    echo "Select region/location:"
    for i in {1..12}; do
        if [[ -n "${REGIONS[$i]}" ]]; then
            echo "  $i) ${REGIONS[$i]}"
        fi
    done
    echo "  0) Custom location"
    echo ""
    
    read -p "Enter choice: " region_choice
    
    if [[ "$region_choice" == "0" ]]; then
        read -p "Enter custom location (City, Country): " custom_location
        location_name="$custom_location"
    elif [[ -n "${REGIONS[$region_choice]}" ]]; then
        location_name="${REGIONS[$region_choice]}"
    else
        print_error "Invalid choice"
        sleep 1
        return
    fi
    
    # Node details
    read -p "Node ID (unique identifier): " node_id
    read -p "Node name: " node_name
    read -p "Provider (optional): " provider
    read -p "Public IP address: " public_ip
    
    # Capabilities
    echo ""
    echo "Select capabilities (comma-separated):"
    echo "  kvm, qemu, lxd, docker"
    read -p "Capabilities: " capabilities
    
    # Tags
    echo ""
    echo "Tags (comma-separated):"
    echo "  production, testing, development, edge"
    read -p "Tags: " tags_input
    
    # Validate node ID
    if [[ -z "$node_id" ]]; then
        print_error "Node ID cannot be empty"
        sleep 1
        return
    fi
    
    # Create node entry
    node_entry="  $node_id:
    node_id: \"$node_id\"
    node_name: \"$node_name\"
    location_name: \"$location_name\"
    provider: \"$provider\"
    public_ip: \"$public_ip\"
    capabilities: [${capabilities// /}]
    tags: [${tags_input// /}]
    status: \"active\"
    created_at: \"$(date -Iseconds)\"
    user_mode: true"
    
    # Add to nodes database
    if [[ -f "$NODES_DB" ]]; then
        # Simple append to file
        if ! grep -q "^  $node_id:" "$NODES_DB"; then
            # Remove the last line (closing brace)
            head -n -1 "$NODES_DB" > "$NODES_DB.tmp"
            echo "$node_entry" >> "$NODES_DB.tmp"
            echo "}" >> "$NODES_DB.tmp"
            mv "$NODES_DB.tmp" "$NODES_DB"
            print_success "Node '$node_name' added successfully!"
            log "Added new node: $node_id ($node_name)"
        else
            print_error "Node ID '$node_id' already exists"
        fi
    fi
    
    sleep 2
}

list_nodes() {
    print_header
    echo -e "${GREEN}📋 Available Nodes:${NC}"
    echo ""
    
    if [[ -f "$NODES_DB" ]]; then
        echo "Nodes:"
        echo "======"
        # Simple parsing of YAML
        while IFS= read -r line; do
            if [[ "$line" =~ ^\ \ ([a-zA-Z0-9_]*): ]]; then
                node_id="${BASH_REMATCH[1]}"
                echo -n "• $node_id: "
            elif [[ "$line" =~ \ \ node_name:\ (.*) ]]; then
                echo -n "${BASH_REMATCH[1]} "
            elif [[ "$line" =~ \ \ location_name:\ (.*) ]]; then
                echo -n "[${BASH_REMATCH[1]}] "
            elif [[ "$line" =~ \ \ status:\ (.*) ]]; then
                echo "- ${BASH_REMATCH[1]}"
            fi
        done < "$NODES_DB"
    else
        echo "No nodes configured"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

show_node_details() {
    print_header
    echo -e "${GREEN}🔍 Node Details${NC}"
    echo ""
    
    read -p "Enter Node ID: " node_id
    
    if [[ -z "$node_id" ]]; then
        print_error "Node ID cannot be empty"
        sleep 1
        return
    fi
    
    if [[ -f "$NODES_DB" ]]; then
        echo "Node Details for '$node_id':"
        echo "=========================="
        
        # Find the node section
        local in_node=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^\ \ $node_id: ]]; then
                in_node=true
                continue
            elif [[ "$in_node" == "true" ]] && [[ "$line" =~ ^\ \ [a-zA-Z0-9_]*: ]]; then
                break
            elif [[ "$in_node" == "true" ]]; then
                echo "$line"
            fi
        done < "$NODES_DB"
        
        if [[ "$in_node" == "false" ]]; then
            print_error "Node '$node_id' not found"
        fi
    else
        print_error "Nodes database not found"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

remove_node() {
    print_header
    echo -e "${RED}🗑️ Remove Node${NC}"
    echo ""
    
    read -p "Enter Node ID to remove: " node_id
    
    if [[ -z "$node_id" ]]; then
        print_error "Node ID cannot be empty"
        sleep 1
        return
    fi
    
    if [[ "$node_id" == "local" ]]; then
        print_error "Cannot remove local node!"
        sleep 1
        return
    fi
    
    if [[ -f "$NODES_DB" ]]; then
        if grep -q "^  $node_id:" "$NODES_DB"; then
            echo "⚠️ Warning: This will remove node '$node_id' from the database."
            read -p "Are you sure? (y/n): " confirm
            
            if [[ "$confirm" == "y" ]]; then
                # Simple removal using sed
                local start_line=$(grep -n "^  $node_id:" "$NODES_DB" | cut -d: -f1)
                if [[ -n "$start_line" ]]; then
                    # Find where this node section ends
                    local total_lines=$(wc -l < "$NODES_DB")
                    local end_line=$total_lines
                    
                    for ((i=start_line+1; i<=total_lines; i++)); do
                        line=$(sed -n "${i}p" "$NODES_DB")
                        if [[ "$line" =~ ^\ \ [a-zA-Z0-9_]*: ]]; then
                            end_line=$((i-1))
                            break
                        fi
                    done
                    
                    # Remove the node section
                    sed -i "${start_line},${end_line}d" "$NODES_DB"
                    print_success "Node '$node_id' removed"
                    log "Removed node: $node_id"
                fi
            else
                print_info "Removal cancelled"
            fi
        else
            print_error "Node '$node_id' not found"
        fi
    else
        print_error "Nodes database not found"
    fi
    
    sleep 1
}

# VM Creation Wizard
vm_create_wizard() {
    print_header
    echo -e "${GREEN}🚀 Create New VM${NC}"
    echo ""
    
    # Node selection
    echo "Select Node:"
    list_nodes_simple
    echo ""
    read -p "Enter Node ID (default: local): " node_id
    node_id=${node_id:-local}
    
    # Runtime selection
    echo ""
    echo "Select runtime:"
    echo "  [1] KVM+QEMU fast (requires /dev/kvm access)"
    echo "  [2] QEMU universal (software emulation)"
    read -p "Choice (1/2): " runtime_choice
    
    if [[ "$runtime_choice" == "1" ]]; then
        if [[ ! -r "/dev/kvm" ]]; then
            print_error "KVM not available or no read permission on /dev/kvm!"
            print_info "Try: sudo chmod 666 /dev/kvm (temporary) or add user to kvm group"
            sleep 2
            return
        fi
        acceleration="kvm"
    else
        acceleration="tcg"
    fi
    
    # OS selection
    echo ""
    echo "Select OS:"
    echo "FAST Templates:"
    echo "  1) ubuntu-24.04"
    echo "  2) ubuntu-22.04"
    echo "  3) debian-12"
    echo "  4) debian-11"
    echo "  5) almalinux-9"
    echo "  6) rocky-9"
    echo "  7) alpine-linux"
    echo ""
    echo "ISO Boot:"
    echo "  8) proxmox-ve"
    echo "  9) arch-linux"
    echo "  10) kali-linux"
    echo ""
    read -p "Choice (1-10): " os_choice
    
    case $os_choice in
        1) os_template="ubuntu-24.04" ;;
        2) os_template="ubuntu-22.04" ;;
        3) os_template="debian-12" ;;
        4) os_template="debian-11" ;;
        5) os_template="almalinux-9" ;;
        6) os_template="rocky-9" ;;
        7) os_template="alpine-linux" ;;
        8) os_template="proxmox-ve" ;;
        9) os_template="arch-linux" ;;
        10) os_template="kali-linux" ;;
        *) print_error "Invalid choice"; return ;;
    esac
    
    # VM details
    echo ""
    read -p "VM Name: " vm_name
    
    if [[ -z "$vm_name" ]]; then
        print_error "VM Name cannot be empty"
        sleep 1
        return
    fi
    
    # Check if VM already exists
    if [[ -f "$DATA_DIR/vms/${vm_name}.conf" ]]; then
        print_error "VM '$vm_name' already exists"
        sleep 1
        return
    fi
    
    # Resource allocation
    echo ""
    read -p "CPU cores (1-8, default: 1): " cpu_cores
    cpu_cores=${cpu_cores:-1}
    
    if ! [[ "$cpu_cores" =~ ^[0-9]+$ ]] || [[ "$cpu_cores" -lt 1 ]] || [[ "$cpu_cores" -gt 8 ]]; then
        print_error "Invalid CPU cores. Using default: 1"
        cpu_cores=1
    fi
    
    read -p "RAM in MB (512-8192, default: 1024): " ram_mb
    ram_mb=${ram_mb:-1024}
    
    if ! [[ "$ram_mb" =~ ^[0-9]+$ ]] || [[ "$ram_mb" -lt 512 ]] || [[ "$ram_mb" -gt 8192 ]]; then
        print_error "Invalid RAM. Using default: 1024"
        ram_mb=1024
    fi
    
    read -p "Disk size in GB (10-100, default: 20): " disk_gb
    disk_gb=${disk_gb:-20}
    
    if ! [[ "$disk_gb" =~ ^[0-9]+$ ]] || [[ "$disk_gb" -lt 10 ]] || [[ "$disk_gb" -gt 100 ]]; then
        print_error "Invalid disk size. Using default: 20"
        disk_gb=20
    fi
    
    # SSH port (auto-find available)
    echo ""
    print_info "Finding available SSH port..."
    ssh_port=$(find_available_port)
    echo "Using SSH port: $ssh_port"
    
    # Credentials
    echo ""
    read -p "Username (default: zynexuser): " vm_user
    vm_user=${vm_user:-zynexuser}
    
    read -sp "Password (default: ZynexForge123): " vm_pass
    vm_pass=${vm_pass:-ZynexForge123}
    echo ""
    
    # Confirm
    echo ""
    echo "Summary:"
    echo "  Node: $node_id"
    echo "  Runtime: $acceleration"
    echo "  OS: $os_template"
    echo "  VM Name: $vm_name"
    echo "  Resources: ${cpu_cores}vCPU, ${ram_mb}MB RAM, ${disk_gb}GB Disk"
    echo "  SSH Port: $ssh_port"
    echo "  Username: $vm_user"
    echo ""
    
    read -p "Create VM? (y/n): " confirm
    
    if [[ "$confirm" == "y" ]]; then
        create_vm "$vm_name" "$node_id" "$acceleration" "$os_template" "$cpu_cores" "$ram_mb" "$disk_gb" "$ssh_port" "$vm_user" "$vm_pass"
    else
        print_info "VM creation cancelled"
        sleep 1
    fi
}

list_nodes_simple() {
    if [[ -f "$NODES_DB" ]]; then
        echo "Available Nodes:"
        while IFS= read -r line; do
            if [[ "$line" =~ ^\ \ ([a-zA-Z0-9_]*): ]]; then
                node_id="${BASH_REMATCH[1]}"
                echo -n "  $node_id: "
            elif [[ "$line" =~ \ \ node_name:\ (.*) ]]; then
                echo -n "${BASH_REMATCH[1]} "
            elif [[ "$line" =~ \ \ location_name:\ (.*) ]]; then
                echo "[${BASH_REMATCH[1]}]"
            fi
        done < "$NODES_DB"
    else
        echo "  local: Local Node [Local, Server]"
    fi
}

create_vm() {
    local vm_name=$1 node_id=$2 acceleration=$3 os_template=$4 cpu_cores=$5 ram_mb=$6 disk_gb=$7 ssh_port=$8 vm_user=$9 vm_pass=${10}
    
    log "Creating VM: $vm_name on node $node_id"
    
    # Create VM directory
    local vm_dir="$DATA_DIR/vms"
    local disk_dir="$DATA_DIR/disks"
    local cloudinit_dir="$DATA_DIR/cloudinit/$vm_name"
    
    mkdir -p "$vm_dir" "$disk_dir" "$cloudinit_dir"
    
    # Create disk
    local disk_path="$disk_dir/${vm_name}.qcow2"
    
    print_info "Creating disk image..."
    
    # Check if template exists in user's home directory
    local template_path="$USER_HOME/zynexforge/templates/cloud/${os_template}.qcow2"
    if [[ -f "$template_path" ]]; then
        print_info "Using template: $os_template"
        cp "$template_path" "$disk_path"
        qemu-img resize "$disk_path" "${disk_gb}G" >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            print_error "Failed to resize disk"
            return 1
        fi
    else
        print_info "Creating blank disk"
        qemu-img create -f qcow2 "$disk_path" "${disk_gb}G"
        if [[ $? -ne 0 ]]; then
            print_error "Failed to create disk image"
            return 1
        fi
    fi
    
    # Create cloud-init data
    print_info "Creating cloud-init configuration..."
    
    # Get SSH public key
    local ssh_pub_key=""
    if [[ -f "${SSH_KEY_FILE}.pub" ]]; then
        ssh_pub_key=$(cat "${SSH_KEY_FILE}.pub")
    else
        ssh_pub_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... (generate with: ssh-keygen)"
    fi
    
    cat > "$cloudinit_dir/user-data" << EOF
#cloud-config
hostname: $vm_name
manage_etc_hosts: true
users:
  - name: $vm_user
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: '$vm_pass'
    ssh_authorized_keys:
      - $ssh_pub_key
packages:
  - neofetch
  - openssh-server
  - curl
  - wget
package_update: true
package_upgrade: true
runcmd:
  - echo "$OS_ASCII_ART" > /etc/zynexforge-os.ascii
  - echo -e '#!/bin/bash\nclear\nneofetch\ncat /etc/zynexforge-os.ascii\necho -e "\\\\033[1;36m⚡ ZynexForge CloudStack™\\\\033[0m"\necho -e "\\\\033[1;33m🔥 Made by FaaizXD\\\\033[0m"\necho -e "\\\\033[1;32mStatus: Premium VPS Active\\\\033[0m"\necho -e "\\\\033[1;35mStats: \$(free -h | awk '\''/Mem:/ {print "RAM: " \$2 "/" \$3}'\''), Cores: \$(nproc), Disk: \$(df -h / | tail -1 | awk '\''{print \$4}'\''), Load: \$(uptime | awk -F"load average:" '\''{print \$2}'\''), Uptime: \$(uptime -p)"\\\\033[0m"\necho' > /etc/profile.d/zynexforge-login.sh
  - chmod +x /etc/profile.d/zynexforge-login.sh
  - sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/g' /etc/ssh/sshd_config
  - sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config
  - systemctl restart sshd
EOF
    
    cat > "$cloudinit_dir/meta-data" << EOF
instance-id: $vm_name
local-hostname: $vm_name
EOF
    
    # Create seed ISO
    print_info "Creating cloud-init seed ISO..."
    if command -v cloud-localds >/dev/null 2>&1; then
        cloud-localds "$cloudinit_dir/seed.iso" "$cloudinit_dir/user-data" "$cloudinit_dir/meta-data"
    elif command -v genisoimage >/dev/null 2>&1; then
        genisoimage -output "$cloudinit_dir/seed.iso" -volid cidata -joliet -rock \
            "$cloudinit_dir/user-data" "$cloudinit_dir/meta-data" >/dev/null 2>&1
    else
        print_error "No ISO creation tool found (install cloud-image-utils or genisoimage)"
        return 1
    fi
    
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create cloud-init ISO"
        return 1
    fi
    
    # Create VM config file
    cat > "$vm_dir/${vm_name}.conf" << EOF
# ZynexForge VM Configuration
vm_name: "$vm_name"
node_id: "$node_id"
acceleration: "$acceleration"
os_template: "$os_template"
cpu_cores: "$cpu_cores"
ram_mb: "$ram_mb"
disk_gb: "$disk_gb"
ssh_port: "$ssh_port"
vm_user: "$vm_user"
vm_pass: "$vm_pass"
status: "stopped"
created_at: "$(date -Iseconds)"
disk_path: "$disk_path"
pid_file: "/tmp/zynexforge_${vm_name}.pid"
user_mode: true
EOF
    
    print_success "VM '$vm_name' created successfully!"
    echo ""
    echo "📋 Access Information:"
    echo "  VM Name: $vm_name"
    echo "  SSH Port: $ssh_port"
    echo "  Username: $vm_user"
    echo "  Password: $vm_pass"
    echo ""
    echo "🔗 SSH Commands:"
    echo "  ssh -p $ssh_port $vm_user@localhost"
    echo "  ssh -o StrictHostKeyChecking=no -p $ssh_port $vm_user@localhost"
    echo "  ssh -i $SSH_KEY_FILE -p $ssh_port $vm_user@localhost"
    echo ""
    
    read -p "Start VM now? (y/n): " start_now
    if [[ "$start_now" == "y" ]]; then
        start_vm "$vm_name"
    fi
    
    sleep 2
}

start_vm() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [[ ! -f "$vm_config" ]]; then
        print_error "VM '$vm_name' not found"
        return 1
    fi
    
    # Read config
    local ssh_port=$(grep "ssh_port:" "$vm_config" | awk '{print $2}' | tr -d '"')
    local cpu_cores=$(grep "cpu_cores:" "$vm_config" | awk '{print $2}' | tr -d '"')
    local ram_mb=$(grep "ram_mb:" "$vm_config" | awk '{print $2}' | tr -d '"')
    local disk_path=$(grep "disk_path:" "$vm_config" | awk '{print $2}' | tr -d '"')
    local acceleration=$(grep "acceleration:" "$vm_config" | awk '{print $2}' | tr -d '"')
    local seed_iso="$DATA_DIR/cloudinit/$vm_name/seed.iso"
    
    # Check if VM is already running
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file" 2>/dev/null)
        if ps -p "$pid" > /dev/null 2>&1; then
            print_error "VM '$vm_name' is already running (PID: $pid)"
            return 1
        fi
    fi
    
    # Check if port is available
    if ! check_port_available "$ssh_port"; then
        print_error "Port $ssh_port is already in use!"
        read -p "Find new port? (y/n): " find_new
        if [[ "$find_new" == "y" ]]; then
            ssh_port=$(find_available_port)
            print_info "Using new port: $ssh_port"
            # Update config
            sed -i "s/ssh_port:.*/ssh_port: \"$ssh_port\"/" "$vm_config"
        else
            return 1
        fi
    fi
    
    # Build QEMU command for user mode
    local cmd="qemu-system-x86_64"
    local args="-name $vm_name"
    
    # Acceleration
    if [[ "$acceleration" == "kvm" ]] && [[ -r "/dev/kvm" ]]; then
        args="$args -enable-kvm -cpu host"
    else
        args="$args -cpu qemu64"
    fi
    
    # Resources
    args="$args -smp $cpu_cores -m $ram_mb"
    
    # Display (none for headless)
    args="$args -display none -vga none"
    
    # Network with hostfwd - user mode networking
    args="$args -netdev user,id=net0,hostfwd=tcp::$ssh_port-:22"
    args="$args -device virtio-net-pci,netdev=net0"
    
    # Storage
    args="$args -drive file=$disk_path,if=virtio,format=qcow2"
    args="$args -drive file=$seed_iso,if=virtio,format=raw"
    
    # Miscellaneous
    args="$args -daemonize -pidfile $pid_file"
    
    print_info "Starting VM '$vm_name'..."
    
    # Start VM
    $cmd $args 2>&1 | tee -a "$LOG_FILE"
    
    if [[ $? -eq 0 ]]; then
        # Update status
        sed -i "s/status:.*/status: \"running\"/" "$vm_config"
        
        print_success "VM '$vm_name' started successfully"
        echo "📡 SSH accessible on port: $ssh_port"
        
        # Wait a moment for VM to boot
        print_info "Waiting for VM to boot (15 seconds)..."
        sleep 15
        
        # Show access info
        show_vm_access "$vm_name"
    else
        print_error "Failed to start VM '$vm_name'"
        rm -f "$pid_file"
    fi
}

stop_vm() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    
    if [[ ! -f "$vm_config" ]]; then
        print_error "VM '$vm_name' not found"
        return 1
    fi
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file" 2>/dev/null)
        if ps -p "$pid" > /dev/null 2>&1; then
            print_info "Stopping VM '$vm_name' (PID: $pid)..."
            kill "$pid"
            
            # Wait for process to terminate
            local wait_time=0
            while ps -p "$pid" > /dev/null 2>&1 && [[ $wait_time -lt 30 ]]; do
                sleep 1
                wait_time=$((wait_time + 1))
            done
            
            if ps -p "$pid" > /dev/null 2>&1; then
                print_warning "VM did not stop gracefully, forcing kill..."
                kill -9 "$pid"
            fi
            
            rm -f "$pid_file"
            print_success "VM '$vm_name' stopped"
        else
            print_warning "VM '$vm_name' was not running (stale PID file)"
            rm -f "$pid_file"
        fi
    else
        print_warning "VM '$vm_name' is not running"
    fi
    
    # Update status
    sed -i "s/status:.*/status: \"stopped\"/" "$vm_config"
}

show_vm_access() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [[ ! -f "$vm_config" ]]; then
        print_error "VM '$vm_name' not found"
        return 1
    fi
    
    local ssh_port=$(grep "ssh_port:" "$vm_config" | awk '{print $2}' | tr -d '"')
    local vm_user=$(grep "vm_user:" "$vm_config" | awk '{print $2}' | tr -d '"')
    local vm_pass=$(grep "vm_pass:" "$vm_config" | awk '{print $2}' | tr -d '"')
    
    echo ""
    echo "📋 Access Information for '$vm_name':"
    echo "  SSH Port: $ssh_port"
    echo "  Username: $vm_user"
    echo "  Password: $vm_pass"
    echo ""
    echo "🔗 SSH Commands:"
    echo "  ssh -p $ssh_port $vm_user@localhost"
    echo "  ssh -o StrictHostKeyChecking=no -p $ssh_port $vm_user@localhost"
    echo "  ssh -i $SSH_KEY_FILE -p $ssh_port $vm_user@localhost"
    echo ""
    
    read -p "Auto-connect now? (y/n): " connect_now
    if [[ "$connect_now" == "y" ]]; then
        ssh -o StrictHostKeyChecking=no -p "$ssh_port" "$vm_user@localhost"
    fi
}

# Docker VM Cloud
docker_vm_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🐳 Docker VM Cloud:${NC}"
        echo "  1) Create Docker VM"
        echo "  2) Start Docker VM"
        echo "  3) Stop Docker VM"
        echo "  4) Show Docker VM info"
        echo "  5) Docker VM Console"
        echo "  6) Delete Docker VM"
        echo "  0) Back"
        echo ""
        
        read -p "Select option: " choice
        
        case $choice in
            1) create_docker_vm ;;
            2) start_docker_vm ;;
            3) stop_docker_vm ;;
            4) show_docker_vm_info ;;
            5) docker_vm_console ;;
            6) delete_docker_vm ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

create_docker_vm() {
    print_header
    echo -e "${GREEN}🐳 Create Docker VM${NC}"
    echo ""
    
    # Check Docker availability
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker is not installed"
        print_info "Install Docker first: https://docs.docker.com/engine/install/"
        sleep 2
        return
    fi
    
    # Node selection
    echo "Select Node:"
    list_nodes_simple
    echo ""
    read -p "Enter Node ID (default: local): " node_id
    node_id=${node_id:-local}
    
    # Docker VM details
    read -p "Docker VM Name: " dv_name
    
    if [[ -z "$dv_name" ]]; then
        print_error "Docker VM Name cannot be empty"
        sleep 1
        return
    fi
    
    # Base image
    echo ""
    echo "Select Base Image:"
    echo "  1) ubuntu:24.04"
    echo "  2) debian:12"
    echo "  3) alpine:latest"
    echo "  4) centos:stream9"
    echo "  5) fedora:latest"
    read -p "Choice (1-5): " image_choice
    
    case $image_choice in
        1) base_image="ubuntu:24.04" ;;
        2) base_image="debian:12" ;;
        3) base_image="alpine:latest" ;;
        4) base_image="centos:stream9" ;;
        5) base_image="fedora:latest" ;;
        *) print_error "Invalid choice"; return ;;
    esac
    
    # Resource limits
    echo ""
    read -p "CPU limit (e.g., 1.5 or 2, press Enter for unlimited): " cpu_limit
    read -p "Memory limit (e.g., 512m or 2g, press Enter for unlimited): " memory_limit
    
    # SSH support
    echo ""
    read -p "Enable SSH access? (y/n): " enable_ssh
    if [[ "$enable_ssh" == "y" ]]; then
        ssh_port=$(find_available_port 22022)
        echo "Using SSH port: $ssh_port"
        read -p "SSH Username (default: dockeruser): " ssh_user
        ssh_user=${ssh_user:-dockeruser}
        read -sp "SSH Password (default: DockerVM123): " ssh_pass
        ssh_pass=${ssh_pass:-DockerVM123}
        echo ""
    else
        ssh_port=""
        ssh_user=""
        ssh_pass=""
    fi
    
    # Port mappings
    echo ""
    echo "Port mappings (format: host_port:container_port)"
    echo "Example: 8080:80 8443:443"
    echo "Press Enter for no port mappings"
    read -p "Enter port mappings (space-separated): " port_mappings
    
    # Create Docker VM
    echo ""
    print_info "Creating Docker VM '$dv_name'..."
    
    # Build Docker command
    local docker_cmd="docker run -d"
    docker_cmd="$docker_cmd --name $dv_name"
    docker_cmd="$docker_cmd --hostname $dv_name"
    docker_cmd="$docker_cmd --restart unless-stopped"
    
    if [[ -n "$cpu_limit" ]]; then
        docker_cmd="$docker_cmd --cpus=$cpu_limit"
    fi
    
    if [[ -n "$memory_limit" ]]; then
        docker_cmd="$docker_cmd --memory=$memory_limit"
    fi
    
    if [[ "$enable_ssh" == "y" && -n "$ssh_port" ]]; then
        docker_cmd="$docker_cmd -p $ssh_port:22"
    fi
    
    # Add port mappings
    for mapping in $port_mappings; do
        docker_cmd="$docker_cmd -p $mapping"
    done
    
    docker_cmd="$docker_cmd $base_image"
    
    # Start with tail to keep running (for non-interactive images)
    docker_cmd="$docker_cmd tail -f /dev/null"
    
    print_info "Running: $docker_cmd"
    
    if eval "$docker_cmd"; then
        print_success "Docker VM '$dv_name' created"
        
        # Install SSH if enabled
        if [[ "$enable_ssh" == "y" ]]; then
            print_info "Installing and configuring SSH..."
            
            # Determine package manager and install SSH
            docker exec "$dv_name" sh -c '
                if command -v apt-get >/dev/null 2>&1; then
                    apt-get update && apt-get install -y openssh-server sudo
                elif command -v apk >/dev/null 2>&1; then
                    apk add openssh-server sudo
                elif command -v yum >/dev/null 2>&1; then
                    yum install -y openssh-server sudo
                elif command -v dnf >/dev/null 2>&1; then
                    dnf install -y openssh-server sudo
                fi
            ' 2>/dev/null
            
            # Create user and set password
            docker exec "$dv_name" sh -c "
                if id '$ssh_user' >/dev/null 2>&1; then
                    echo 'User already exists'
                else
                    useradd -m -s /bin/bash '$ssh_user'
                fi
                echo '$ssh_user:$ssh_pass' | chpasswd
                echo '$ssh_user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
                mkdir -p /home/$ssh_user/.ssh
                echo '$(cat "${SSH_KEY_FILE}.pub" 2>/dev/null || echo "")' >> /home/$ssh_user/.ssh/authorized_keys
                chown -R $ssh_user:$ssh_user /home/$ssh_user/.ssh
                chmod 700 /home/$ssh_user/.ssh
                chmod 600 /home/$ssh_user/.ssh/authorized_keys
            " 2>/dev/null
            
            # Start SSH service
            docker exec "$dv_name" sh -c '
                if [ -f /etc/init.d/ssh ]; then
                    /etc/init.d/ssh start
                elif [ -f /usr/sbin/sshd ]; then
                    /usr/sbin/sshd
                fi
            ' 2>/dev/null
            
            print_success "SSH installed on port $ssh_port"
        fi
        
        # Save config
        local dv_dir="$DATA_DIR/dockervm"
        mkdir -p "$dv_dir"
        
        cat > "$dv_dir/${dv_name}.conf" << EOF
# Docker VM Configuration
dv_name: "$dv_name"
node_id: "$node_id"
base_image: "$base_image"
cpu_limit: "$cpu_limit"
memory_limit: "$memory_limit"
enable_ssh: "$enable_ssh"
ssh_port: "$ssh_port"
ssh_user: "$ssh_user"
ssh_pass: "$ssh_pass"
port_mappings: "$port_mappings"
status: "running"
created_at: "$(date -Iseconds)"
container_id: $(docker ps -qf "name=$dv_name" 2>/dev/null || echo "")
user_mode: true
EOF
        
        log "Created Docker VM: $dv_name"
        
        # Show access info
        if [[ "$enable_ssh" == "y" ]]; then
            echo ""
            echo "📋 SSH Access:"
            echo "  ssh -p $ssh_port $ssh_user@localhost"
            echo "  ssh -i $SSH_KEY_FILE -p $ssh_port $ssh_user@localhost"
        fi
        
        echo ""
        echo "🔧 Console Access:"
        echo "  docker exec -it $dv_name /bin/bash"
        
    else
        print_error "Failed to create Docker VM"
        print_info "Check if Docker is running and you have permissions"
    fi
    
    sleep 2
}

start_docker_vm() {
    print_header
    echo -e "${GREEN}🚀 Start Docker VM${NC}"
    echo ""
    
    read -p "Docker VM Name: " dv_name
    
    if [[ -z "$dv_name" ]]; then
        print_error "Docker VM Name cannot be empty"
        sleep 1
        return
    fi
    
    if docker start "$dv_name" 2>/dev/null; then
        print_success "Docker VM '$dv_name' started"
        
        # Update config
        local dv_config="$DATA_DIR/dockervm/${dv_name}.conf"
        if [[ -f "$dv_config" ]]; then
            sed -i "s/status:.*/status: \"running\"/" "$dv_config"
        fi
    else
        print_error "Docker VM '$dv_name' not found"
    fi
    
    sleep 1
}

stop_docker_vm() {
    print_header
    echo -e "${RED}🛑 Stop Docker VM${NC}"
    echo ""
    
    read -p "Docker VM Name: " dv_name
    
    if [[ -z "$dv_name" ]]; then
        print_error "Docker VM Name cannot be empty"
        sleep 1
        return
    fi
    
    if docker stop "$dv_name" 2>/dev/null; then
        print_success "Docker VM '$dv_name' stopped"
        
        # Update config
        local dv_config="$DATA_DIR/dockervm/${dv_name}.conf"
        if [[ -f "$dv_config" ]]; then
            sed -i "s/status:.*/status: \"stopped\"/" "$dv_config"
        fi
    else
        print_error "Docker VM '$dv_name' not found"
    fi
    
    sleep 1
}

show_docker_vm_info() {
    print_header
    echo -e "${GREEN}🔍 Docker VM Info${NC}"
    echo ""
    
    read -p "Docker VM Name: " dv_name
    
    if [[ -z "$dv_name" ]]; then
        print_error "Docker VM Name cannot be empty"
        sleep 1
        return
    fi
    
    local dv_config="$DATA_DIR/dockervm/${dv_name}.conf"
    if [[ -f "$dv_config" ]]; then
        echo "Configuration for '$dv_name':"
        echo "=============================="
        cat "$dv_config"
        
        # Show Docker stats
        echo ""
        echo "📊 Docker Container Stats:"
        docker ps -af "name=$dv_name" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Container not found"
    else
        print_error "Docker VM '$dv_name' not found in configuration"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

docker_vm_console() {
    print_header
    echo -e "${GREEN}💻 Docker VM Console${NC}"
    echo ""
    
    read -p "Docker VM Name: " dv_name
    
    if [[ -z "$dv_name" ]]; then
        print_error "Docker VM Name cannot be empty"
        sleep 1
        return
    fi
    
    if docker ps -qf "name=$dv_name" | grep -q .; then
        echo "Connecting to '$dv_name' console..."
        echo "Use 'exit' to return to menu"
        echo ""
        docker exec -it "$dv_name" /bin/bash || docker exec -it "$dv_name" /bin/sh
    else
        print_error "Docker VM '$dv_name' not running"
        sleep 1
    fi
}

delete_docker_vm() {
    print_header
    echo -e "${RED}🗑️ Delete Docker VM${NC}"
    echo ""
    
    read -p "Docker VM Name: " dv_name
    
    if [[ -z "$dv_name" ]]; then
        print_error "Docker VM Name cannot be empty"
        sleep 1
        return
    fi
    
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${dv_name}$"; then
        print_error "Docker VM '$dv_name' not found"
        sleep 1
        return
    fi
    
    echo "⚠️ Warning: This will permanently delete '$dv_name' and all its data"
    read -p "Are you sure? (y/n): " confirm
    
    if [[ "$confirm" == "y" ]]; then
        docker stop "$dv_name" 2>/dev/null
        docker rm "$dv_name" 2>/dev/null
        
        # Remove config
        local dv_config="$DATA_DIR/dockervm/${dv_name}.conf"
        rm -f "$dv_config"
        
        print_success "Docker VM '$dv_name' deleted"
        log "Deleted Docker VM: $dv_name"
    else
        print_info "Deletion cancelled"
    fi
    
    sleep 1
}

# Jupyter Cloud Lab
jupyter_cloud_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🔬 Jupyter Cloud Lab:${NC}"
        echo "  1) Create Jupyter VM"
        echo "  2) List Jupyter VMs"
        echo "  3) Stop Jupyter VM"
        echo "  4) Delete Jupyter VM"
        echo "  5) Show Jupyter URL"
        echo "  0) Back"
        echo ""
        
        read -p "Select option: " choice
        
        case $choice in
            1) create_jupyter_vm ;;
            2) list_jupyter_vms ;;
            3) stop_jupyter_vm ;;
            4) delete_jupyter_vm ;;
            5) show_jupyter_url ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

create_jupyter_vm() {
    print_header
    echo -e "${GREEN}🔬 Create Jupyter VM${NC}"
    echo ""
    
    # Check Docker availability
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker is not installed"
        print_info "Install Docker first: https://docs.docker.com/engine/install/"
        sleep 2
        return
    fi
    
    read -p "Jupyter VM Name: " jv_name
    
    if [[ -z "$jv_name" ]]; then
        print_error "Jupyter VM Name cannot be empty"
        sleep 1
        return
    fi
    
    # Find available port
    jv_port=$(find_available_port 8888)
    echo "Using port: $jv_port"
    
    # Generate token
    local jv_token=$(openssl rand -hex 24)
    
    echo ""
    print_info "Creating Jupyter VM '$jv_name'..."
    
    # Create Docker volume for persistence
    docker volume create "${jv_name}_data" >/dev/null 2>&1
    
    # Start Jupyter container
    if docker run -d \
        --name "$jv_name" \
        -p "$jv_port:8888" \
        -v "${jv_name}_data:/home/jovyan/work" \
        -e JUPYTER_TOKEN="$jv_token" \
        jupyter/datascience-notebook \
        start-notebook.sh --NotebookApp.token="$jv_token"; then
        
        print_success "Jupyter VM '$jv_name' created"
        
        # Save config
        local jv_dir="$DATA_DIR/jupyter"
        mkdir -p "$jv_dir"
        
        cat > "$jv_dir/${jv_name}.conf" << EOF
# Jupyter VM Configuration
jv_name: "$jv_name"
jv_port: "$jv_port"
jv_token: "$jv_token"
volume_name: "${jv_name}_data"
status: "running"
created_at: "$(date -Iseconds)"
container_id: $(docker ps -qf "name=$jv_name" 2>/dev/null || echo "")
user_mode: true
EOF
        
        # Show access URL
        echo ""
        echo "📋 Jupyter Access Information:"
        echo "  URL: http://localhost:$jv_port"
        echo "  Token: $jv_token"
        echo ""
        echo "🔗 Direct URL with token:"
        echo "  http://localhost:$jv_port/?token=$jv_token"
        
        log "Created Jupyter VM: $jv_name"
    else
        print_error "Failed to create Jupyter VM"
    fi
    
    sleep 2
}

list_jupyter_vms() {
    print_header
    echo -e "${GREEN}📋 Jupyter VMs:${NC}"
    echo ""
    
    local jv_dir="$DATA_DIR/jupyter"
    if [[ -d "$jv_dir" ]] && ls "$jv_dir"/*.conf 2>/dev/null | grep -q .; then
        for conf in "$jv_dir"/*.conf; do
            local name=$(basename "$conf" .conf)
            local port=$(grep "jv_port:" "$conf" | awk '{print $2}' | tr -d '"' 2>/dev/null || echo "N/A")
            local status=$(grep "status:" "$conf" | awk '{print $2}' | tr -d '"' 2>/dev/null || echo "unknown")
            echo "  • $name - Port: $port - Status: $status"
        done
    else
        echo "No Jupyter VMs configured"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

stop_jupyter_vm() {
    print_header
    echo -e "${RED}🛑 Stop Jupyter VM${NC}"
    echo ""
    
    read -p "Jupyter VM Name: " jv_name
    
    if [[ -z "$jv_name" ]]; then
        print_error "Jupyter VM Name cannot be empty"
        sleep 1
        return
    fi
    
    if docker stop "$jv_name" 2>/dev/null; then
        print_success "Jupyter VM '$jv_name' stopped"
        
        # Update config
        local jv_config="$DATA_DIR/jupyter/${jv_name}.conf"
        if [[ -f "$jv_config" ]]; then
            sed -i "s/status:.*/status: \"stopped\"/" "$jv_config"
        fi
    else
        print_error "Jupyter VM '$jv_name' not found"
    fi
    
    sleep 1
}

delete_jupyter_vm() {
    print_header
    echo -e "${RED}🗑️ Delete Jupyter VM${NC}"
    echo ""
    
    read -p "Jupyter VM Name: " jv_name
    
    if [[ -z "$jv_name" ]]; then
        print_error "Jupyter VM Name cannot be empty"
        sleep 1
        return
    fi
    
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${jv_name}$"; then
        print_error "Jupyter VM '$jv_name' not found"
        sleep 1
        return
    fi
    
    echo "⚠️ Warning: This will permanently delete '$jv_name' and all its data"
    read -p "Are you sure? (y/n): " confirm
    
    if [[ "$confirm" == "y" ]]; then
        docker stop "$jv_name" 2>/dev/null
        docker rm "$jv_name" 2>/dev/null
        docker volume rm "${jv_name}_data" 2>/dev/null
        
        # Remove config
        local jv_config="$DATA_DIR/jupyter/${jv_name}.conf"
        rm -f "$jv_config"
        
        print_success "Jupyter VM '$jv_name' deleted"
        log "Deleted Jupyter VM: $jv_name"
    else
        print_info "Deletion cancelled"
    fi
    
    sleep 1
}

show_jupyter_url() {
    print_header
    echo -e "${GREEN}🔗 Jupyter URL${NC}"
    echo ""
    
    read -p "Jupyter VM Name: " jv_name
    
    if [[ -z "$jv_name" ]]; then
        print_error "Jupyter VM Name cannot be empty"
        sleep 1
        return
    fi
    
    local jv_config="$DATA_DIR/jupyter/${jv_name}.conf"
    if [[ -f "$jv_config" ]]; then
        local port=$(grep "jv_port:" "$jv_config" | awk '{print $2}' | tr -d '"')
        local token=$(grep "jv_token:" "$jv_config" | awk '{print $2}' | tr -d '"')
        
        echo "Access Information for '$jv_name':"
        echo "================================="
        echo "  URL: http://localhost:$port"
        echo "  Token: $token"
        echo ""
        echo "🔗 Direct URL with token:"
        echo "  http://localhost:$port/?token=$token"
    else
        print_error "Jupyter VM '$jv_name' not found in configuration"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# VM Manager (Lifecycle Menu)
vm_manager_menu() {
    while true; do
        print_header
        echo -e "${GREEN}⚙️ VM Manager:${NC}"
        echo "  1) Create a VM"
        echo "  2) Start a VM"
        echo "  3) Stop a VM"
        echo "  4) Show VM info"
        echo "  5) Edit VM configuration"
        echo "  6) Delete a VM"
        echo "  7) Resize VM disk"
        echo "  8) Show VM performance"
        echo "  9) Access VM (SSH)"
        echo "  0) Back"
        echo ""
        
        read -p "Select option: " choice
        
        case $choice in
            1) vm_create_wizard ;;
            2) 
                print_header
                echo -e "${GREEN}🚀 Start VM${NC}"
                echo ""
                read -p "VM Name: " vm_name
                if [[ -n "$vm_name" ]]; then
                    start_vm "$vm_name"
                else
                    print_error "VM Name cannot be empty"
                    sleep 1
                fi
                ;;
            3)
                print_header
                echo -e "${RED}🛑 Stop VM${NC}"
                echo ""
                read -p "VM Name: " vm_name
                if [[ -n "$vm_name" ]]; then
                    stop_vm "$vm_name"
                else
                    print_error "VM Name cannot be empty"
                    sleep 1
                fi
                ;;
            4)
                print_header
                echo -e "${GREEN}🔍 Show VM Info${NC}"
                echo ""
                read -p "VM Name: " vm_name
                if [[ -n "$vm_name" ]]; then
                    show_vm_info "$vm_name"
                else
                    print_error "VM Name cannot be empty"
                    sleep 1
                fi
                ;;
            5)
                print_header
                echo -e "${GREEN}✏️ Edit VM Configuration${NC}"
                echo ""
                read -p "VM Name: " vm_name
                if [[ -n "$vm_name" ]]; then
                    edit_vm_config "$vm_name"
                else
                    print_error "VM Name cannot be empty"
                    sleep 1
                fi
                ;;
            6)
                print_header
                echo -e "${RED}🗑️ Delete VM${NC}"
                echo ""
                read -p "VM Name: " vm_name
                if [[ -n "$vm_name" ]]; then
                    delete_vm "$vm_name"
                else
                    print_error "VM Name cannot be empty"
                    sleep 1
                fi
                ;;
            7)
                print_header
                echo -e "${GREEN}💾 Resize VM Disk${NC}"
                echo ""
                read -p "VM Name: " vm_name
                if [[ -n "$vm_name" ]]; then
                    resize_vm_disk "$vm_name"
                else
                    print_error "VM Name cannot be empty"
                    sleep 1
                fi
                ;;
            8)
                print_header
                echo -e "${GREEN}📊 Show VM Performance${NC}"
                echo ""
                read -p "VM Name: " vm_name
                if [[ -n "$vm_name" ]]; then
                    show_vm_performance "$vm_name"
                else
                    print_error "VM Name cannot be empty"
                    sleep 1
                fi
                ;;
            9)
                print_header
                echo -e "${GREEN}🔗 Access VM (SSH)${NC}"
                echo ""
                read -p "VM Name: " vm_name
                if [[ -n "$vm_name" ]]; then
                    show_vm_access "$vm_name"
                else
                    print_error "VM Name cannot be empty"
                    sleep 1
                fi
                ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

show_vm_info() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [[ ! -f "$vm_config" ]]; then
        print_error "VM '$vm_name' not found"
        read -p "Press Enter to continue..."
        return 1
    fi
    
    print_header
    echo -e "${GREEN}🔍 VM Information: $vm_name${NC}"
    echo ""
    
    echo "Configuration:"
    echo "=============="
    cat "$vm_config"
    echo ""
    
    # Show disk usage
    local disk_path=$(grep "disk_path:" "$vm_config" | awk '{print $2}' | tr -d '"')
    if [[ -f "$disk_path" ]]; then
        echo "📊 Disk Information:"
        qemu-img info "$disk_path" 2>/dev/null | grep -E "(virtual size|disk size|format)" || echo "Cannot get disk info"
    fi
    
    # Show process if running
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file" 2>/dev/null)
        if ps -p "$pid" > /dev/null 2>&1; then
            echo ""
            echo "🔄 Process Status: Running (PID: $pid)"
        else
            echo ""
            echo "🔄 Process Status: Stopped (stale PID file)"
            rm -f "$pid_file"
        fi
    else
        echo ""
        echo "🔄 Process Status: Stopped"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

edit_vm_config() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [[ ! -f "$vm_config" ]]; then
        print_error "VM '$vm_name' not found"
        sleep 1
        return 1
    fi
    
    print_header
    echo -e "${GREEN}✏️ Edit VM Configuration: $vm_name${NC}"
    echo ""
    
    echo "What would you like to edit?"
    echo "  1) SSH Port"
    echo "  2) RAM Size"
    echo "  3) CPU Cores"
    echo "  4) Username"
    echo "  5) Password"
    echo "  0) Cancel"
    echo ""
    
    read -p "Choice: " edit_choice
    
    case $edit_choice in
        1)
            read -p "New SSH Port: " new_port
            if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1024 ]] || [[ "$new_port" -gt 65535 ]]; then
                print_error "Invalid port number (1024-65535)"
            else
                sed -i "s/ssh_port:.*/ssh_port: \"$new_port\"/" "$vm_config"
                print_success "SSH Port updated to $new_port"
            fi
            ;;
        2)
            read -p "New RAM in MB: " new_ram
            if ! [[ "$new_ram" =~ ^[0-9]+$ ]] || [[ "$new_ram" -lt 256 ]] || [[ "$new_ram" -gt 16384 ]]; then
                print_error "Invalid RAM size (256-16384 MB)"
            else
                sed -i "s/ram_mb:.*/ram_mb: \"$new_ram\"/" "$vm_config"
                print_success "RAM updated to ${new_ram}MB"
            fi
            ;;
        3)
            read -p "New CPU Cores: " new_cpu
            if ! [[ "$new_cpu" =~ ^[0-9]+$ ]] || [[ "$new_cpu" -lt 1 ]] || [[ "$new_cpu" -gt 16 ]]; then
                print_error "Invalid CPU cores (1-16)"
            else
                sed -i "s/cpu_cores:.*/cpu_cores: \"$new_cpu\"/" "$vm_config"
                print_success "CPU Cores updated to $new_cpu"
            fi
            ;;
        4)
            read -p "New Username: " new_user
            if [[ -z "$new_user" ]]; then
                print_error "Username cannot be empty"
            else
                sed -i "s/vm_user:.*/vm_user: \"$new_user\"/" "$vm_config"
                print_success "Username updated to $new_user"
            fi
            ;;
        5)
            read -sp "New Password: " new_pass
            echo ""
            if [[ -z "$new_pass" ]]; then
                print_error "Password cannot be empty"
            else
                sed -i "s/vm_pass:.*/vm_pass: \"$new_pass\"/" "$vm_config"
                print_success "Password updated"
            fi
            ;;
        0)
            print_info "Edit cancelled"
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac
    
    sleep 1
}

delete_vm() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [[ ! -f "$vm_config" ]]; then
        print_error "VM '$vm_name' not found"
        sleep 1
        return 1
    fi
    
    print_header
    echo -e "${RED}🗑️ Delete VM: $vm_name${NC}"
    echo ""
    
    echo "⚠️ Warning: This will permanently delete VM '$vm_name'"
    echo "The following will be deleted:"
    echo "  • VM configuration"
    echo "  • Disk image"
    echo "  • Cloud-init files"
    echo "  • PID file"
    echo ""
    
    read -p "Are you sure? (y/n): " confirm
    
    if [[ "$confirm" != "y" ]]; then
        print_info "Deletion cancelled"
        return
    fi
    
    # Stop VM if running
    stop_vm "$vm_name"
    
    # Remove files
    local disk_path=$(grep "disk_path:" "$vm_config" | awk '{print $2}' | tr -d '"')
    local cloudinit_dir="$DATA_DIR/cloudinit/$vm_name"
    
    rm -f "$vm_config"
    if [[ -f "$disk_path" ]]; then
        rm -f "$disk_path"
    fi
    if [[ -d "$cloudinit_dir" ]]; then
        rm -rf "$cloudinit_dir"
    fi
    rm -f "/tmp/zynexforge_${vm_name}.pid"
    
    print_success "VM '$vm_name' deleted"
    log "Deleted VM: $vm_name"
    sleep 1
}

resize_vm_disk() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [[ ! -f "$vm_config" ]]; then
        print_error "VM '$vm_name' not found"
        sleep 1
        return 1
    fi
    
    print_header
    echo -e "${GREEN}💾 Resize VM Disk: $vm_name${NC}"
    echo ""
    
    local disk_path=$(grep "disk_path:" "$vm_config" | awk '{print $2}' | tr -d '"')
    local current_gb=$(grep "disk_gb:" "$vm_config" | awk '{print $2}' | tr -d '"')
    
    echo "Current disk size: ${current_gb}GB"
    read -p "New size in GB (e.g., 50): " new_size
    
    if ! [[ "$new_size" =~ ^[0-9]+$ ]] || [[ "$new_size" -lt 1 ]] || [[ "$new_size" -gt 500 ]]; then
        print_error "Invalid size (1-500 GB)"
        sleep 1
        return 1
    fi
    
    if [[ "$new_size" -le "$current_gb" ]]; then
        print_error "New size must be larger than current size"
        print_info "Disk shrinking is not supported for safety reasons"
        sleep 1
        return 1
    fi
    
    echo "⚠️ Warning: Disk resize cannot be undone"
    read -p "Continue? (y/n): " confirm
    
    if [[ "$confirm" == "y" ]]; then
        # Ensure VM is stopped
        stop_vm "$vm_name"
        
        print_info "Resizing disk from ${current_gb}GB to ${new_size}GB..."
        
        # Resize disk
        if qemu-img resize "$disk_path" "${new_size}G"; then
            # Update config
            sed -i "s/disk_gb:.*/disk_gb: \"$new_size\"/" "$vm_config"
            print_success "Disk resized to ${new_size}GB"
        else
            print_error "Failed to resize disk"
        fi
    else
        print_info "Resize cancelled"
    fi
    
    sleep 1
}

show_vm_performance() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [[ ! -f "$vm_config" ]]; then
        print_error "VM '$vm_name' not found"
        sleep 1
        return 1
    fi
    
    print_header
    echo -e "${GREEN}📊 VM Performance: $vm_name${NC}"
    echo ""
    
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file" 2>/dev/null)
        if ps -p "$pid" >/dev/null 2>&1; then
            echo "Process Resources (PID: $pid):"
            echo "==============================="
            
            # Show process info
            echo "📈 CPU and Memory:"
            ps -p "$pid" -o pid,ppid,pcpu,pmem,etime,cmd --no-headers
            
            # Show CPU percentage
            local cpu_percent=$(ps -p "$pid" -o pcpu --no-headers | tr -d ' ' || echo "0")
            echo "  CPU Usage: ${cpu_percent}%"
            
            # Show memory usage
            local mem_kb=$(ps -p "$pid" -o rss --no-headers | tr -d ' ' || echo "0")
            echo "  Memory Usage: ${mem_kb} KB"
            
            # Show elapsed time
            local elapsed=$(ps -p "$pid" -o etime --no-headers | tr -d ' ' || echo "00:00")
            echo "  Running Time: $elapsed"
            
            # Show disk usage of the VM
            echo ""
            echo "💾 Disk Usage:"
            local disk_path=$(grep "disk_path:" "$vm_config" | awk '{print $2}' | tr -d '"')
            if [[ -f "$disk_path" ]]; then
                local disk_size=$(du -h "$disk_path" | awk '{print $1}')
                echo "  Disk File: $disk_size"
            fi
            
        else
            echo "VM is not running"
            echo "Start the VM to see performance metrics"
        fi
    else
        echo "VM is not running"
        echo "Start the VM to see performance metrics"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Security Menu
security_menu() {
    while true; do
        print_header
        echo -e "${GREEN}🛡️ Security:${NC}"
        echo "  1) Show Security Status"
        echo "  2) Manage SSH Keys"
        echo "  0) Back"
        echo ""
        
        read -p "Select option: " choice
        
        case $choice in
            1) show_security_status ;;
            2) manage_ssh_keys ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

show_security_status() {
    print_header
    echo -e "${GREEN}🔒 Security Status${NC}"
    echo ""
    
    echo "🔐 SSH Security:"
    if [[ -f ~/.ssh/authorized_keys ]]; then
        echo "  ✅ SSH keys configured"
        key_count=$(grep -c "ssh-" ~/.ssh/authorized_keys 2>/dev/null || echo "0")
        echo "  Number of SSH keys: $key_count"
    else
        echo "  ⚠️ No SSH keys configured (password only)"
    fi
    
    if [[ -f "$SSH_KEY_FILE" ]]; then
        echo "  ✅ ZynexForge SSH key exists"
    else
        echo "  ❌ ZynexForge SSH key not found"
    fi
    
    echo ""
    echo "📊 VM Security:"
    local vm_count=0
    local running_vms=0
    
    if [[ -d "$DATA_DIR/vms" ]]; then
        for conf in "$DATA_DIR/vms"/*.conf 2>/dev/null; do
            if [[ -f "$conf" ]]; then
                vm_count=$((vm_count + 1))
                local status=$(grep "status:" "$conf" | awk '{print $2}' | tr -d '"')
                if [[ "$status" == "running" ]]; then
                    running_vms=$((running_vms + 1))
                fi
            fi
        done
    fi
    
    echo "  Total VMs: $vm_count"
    echo "  Running VMs: $running_vms"
    
    # Check for weak passwords in configs
    echo ""
    echo "🔑 Password Security:"
    weak_passwords=0
    if [[ -d "$DATA_DIR/vms" ]]; then
        for conf in "$DATA_DIR/vms"/*.conf 2>/dev/null; do
            if [[ -f "$conf" ]]; then
                local password=$(grep "vm_pass:" "$conf" | awk '{print $2}' | tr -d '"')
                if [[ ${#password} -lt 8 ]]; then
                    weak_passwords=$((weak_passwords + 1))
                fi
            fi
        done
    fi
    
    if [[ $weak_passwords -gt 0 ]]; then
        echo "  ⚠️ Weak passwords detected: $weak_passwords VMs have passwords < 8 chars"
    else
        echo "  ✅ All VM passwords are at least 8 characters"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

manage_ssh_keys() {
    print_header
    echo -e "${GREEN}🔑 Manage SSH Keys${NC}"
    echo ""
    
    echo "SSH Key Management:"
    echo "  1) Generate new SSH key"
    echo "  2) Show public key"
    echo "  3) List all SSH keys"
    echo "  0) Back"
    echo ""
    
    read -p "Select option: " choice
    
    case $choice in
        1)
            echo ""
            read -p "Key name (default: zynexforge_new): " key_name
            key_name=${key_name:-zynexforge_new}
            
            ssh-keygen -t ed25519 -f "$USER_HOME/.ssh/${key_name}" -N "" -q
            if [[ $? -eq 0 ]]; then
                print_success "SSH key generated: $USER_HOME/.ssh/${key_name}"
                chmod 600 "$USER_HOME/.ssh/${key_name}"
                chmod 644 "$USER_HOME/.ssh/${key_name}.pub"
            else
                print_error "Failed to generate SSH key"
            fi
            ;;
        2)
            echo ""
            if [[ -f "$SSH_KEY_FILE.pub" ]]; then
                echo "Public key for ZynexForge:"
                echo "=========================="
                cat "$SSH_KEY_FILE.pub"
            else
                print_error "SSH key not found"
                read -p "Generate one now? (y/n): " generate_now
                if [[ "$generate_now" == "y" ]]; then
                    ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q
                    chmod 600 "$SSH_KEY_FILE"
                    chmod 644 "${SSH_KEY_FILE}.pub"
                    print_success "SSH key generated"
                fi
            fi
            ;;
        3)
            echo ""
            echo "SSH Keys in ~/.ssh/:"
            echo "===================="
            ls -la ~/.ssh/*.pub 2>/dev/null | awk '{print $9}'
            echo ""
            echo "Contents of authorized_keys:"
            if [[ -f ~/.ssh/authorized_keys ]]; then
                cat ~/.ssh/authorized_keys
            else
                echo "No authorized_keys file"
            fi
            ;;
        0)
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
}

# Monitoring Menu
monitoring_menu() {
    while true; do
        print_header
        echo -e "${GREEN}📊 Monitoring:${NC}"
        echo "  1) System Overview"
        echo "  2) VM Resources"
        echo "  3) Docker Resources"
        echo "  4) Disk Usage"
        echo "  0) Back"
        echo ""
        
        read -p "Select option: " choice
        
        case $choice in
            1) system_overview ;;
            2) vm_resources ;;
            3) docker_resources ;;
            4) disk_usage ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

system_overview() {
    print_header
    echo -e "${GREEN}📊 System Overview${NC}"
    echo ""
    
    # CPU
    echo "🖥️ CPU:"
    echo "  Cores: $(nproc)"
    echo "  Load: $(uptime | awk -F'load average:' '{print $2}')"
    
    # Memory
    echo ""
    echo "🧠 Memory:"
    free -h | awk '/^Mem:/ {
        total=$2
        used=$3
        free=$4
        printf "  Total: %s | Used: %s | Free: %s\n", total, used, free
    }'
    
    # Disk
    echo ""
    echo "💾 Disk:"
    df -h / | tail -1 | awk '{
        total=$2
        used=$3
        free=$4
        used_percent=$5
        printf "  Total: %s | Used: %s (%s) | Free: %s\n", total, used, used_percent, free
    }'
    
    # Uptime
    echo ""
    echo "⏰ Uptime: $(uptime -p | sed 's/up //')"
    
    # User
    echo ""
    echo "👤 User: $USER"
    echo "  Home: $USER_HOME"
    
    echo ""
    read -p "Press Enter to continue..."
}

vm_resources() {
    print_header
    echo -e "${GREEN}📊 VM Resources${NC}"
    echo ""
    
    local total_vms=0
    local running_vms=0
    local total_cpu=0
    local total_ram=0
    
    if [[ -d "$DATA_DIR/vms" ]] && ls "$DATA_DIR/vms"/*.conf 2>/dev/null | grep -q .; then
        echo "Virtual Machines:"
        echo "================="
        for conf in "$DATA_DIR/vms"/*.conf; do
            if [[ -f "$conf" ]]; then
                local vm_name=$(basename "$conf" .conf)
                local status=$(grep "status:" "$conf" | awk '{print $2}' | tr -d '"')
                local cpu=$(grep "cpu_cores:" "$conf" | awk '{print $2}' | tr -d '"')
                local ram=$(grep "ram_mb:" "$conf" | awk '{print $2}' | tr -d '"')
                local ssh_port=$(grep "ssh_port:" "$conf" | awk '{print $2}' | tr -d '"')
                
                total_vms=$((total_vms + 1))
                if [[ "$status" == "running" ]]; then
                    running_vms=$((running_vms + 1))
                    total_cpu=$((total_cpu + cpu))
                    total_ram=$((total_ram + ram))
                fi
                
                # Check if process is actually running
                local pid_file="/tmp/zynexforge_${vm_name}.pid"
                local actual_status="stopped"
                if [[ -f "$pid_file" ]]; then
                    local pid=$(cat "$pid_file" 2>/dev/null)
                    if ps -p "$pid" >/dev/null 2>&1; then
                        actual_status="running"
                    fi
                fi
                
                echo "  • $vm_name: Config: $status | Actual: $actual_status | CPU: ${cpu}v | RAM: ${ram}MB | SSH: $ssh_port"
            fi
        done
        
        echo ""
        echo "📈 Summary:"
        echo "  Total VMs: $total_vms"
        echo "  Running VMs: $running_vms"
        echo "  Stopped VMs: $((total_vms - running_vms))"
        echo "  Total CPU (running): ${total_cpu}v"
        echo "  Total RAM (running): ${total_ram}MB"
    else
        echo "No VMs configured"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

docker_resources() {
    print_header
    echo -e "${GREEN}🐳 Docker Resources${NC}"
    echo ""
    
    if command -v docker >/dev/null 2>&1; then
        echo "📦 Running Containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}" 2>/dev/null || echo "No containers running"
    else
        print_error "Docker not installed"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

disk_usage() {
    print_header
    echo -e "${GREEN}💾 Disk Usage${NC}"
    echo ""
    
    echo "📁 Platform Directories:"
    if [[ -d "$CONFIG_DIR" ]]; then
        echo "  $CONFIG_DIR: $(du -sh "$CONFIG_DIR" 2>/dev/null | awk '{print $1}' || echo "0B")"
    fi
    
    if [[ -d "$DATA_DIR" ]]; then
        echo "  $DATA_DIR: $(du -sh "$DATA_DIR" 2>/dev/null | awk '{print $1}' || echo "0B")"
    fi
    
    # VM disks usage
    local total_disk_size=0
    local total_disk_count=0
    
    if [[ -d "$DATA_DIR/disks" ]]; then
        for disk in "$DATA_DIR/disks"/*.qcow2 2>/dev/null; do
            if [[ -f "$disk" ]]; then
                total_disk_count=$((total_disk_count + 1))
                disk_size=$(du -b "$disk" 2>/dev/null | awk '{print $1}' || echo "0")
                total_disk_size=$((total_disk_size + disk_size))
            fi
        done
        
        if [[ $total_disk_count -gt 0 ]]; then
            echo "  VM Disks: $total_disk_count disks"
        fi
    fi
    
    echo ""
    echo "📊 Overall Disk Usage:"
    df -h 2>/dev/null | head -10
    
    echo ""
    read -p "Press Enter to continue..."
}

# Templates + ISO Library
templates_menu() {
    while true; do
        print_header
        echo -e "${GREEN}⚙️ Templates + ISO Library:${NC}"
        echo "  1) List Cloud Templates"
        echo "  2) Download Cloud Template"
        echo "  3) List ISO Images"
        echo "  4) Download ISO Image"
        echo "  5) Create Custom Template"
        echo "  0) Back"
        echo ""
        
        read -p "Select option: " choice
        
        case $choice in
            1) list_cloud_templates ;;
            2) download_cloud_template ;;
            3) list_iso_images ;;
            4) download_iso_image ;;
            5) create_custom_template ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

list_cloud_templates() {
    print_header
    echo -e "${GREEN}📦 Cloud Templates:${NC}"
    echo ""
    
    local template_dir="$USER_HOME/zynexforge/templates/cloud"
    if [[ -d "$template_dir" ]] && ls "$template_dir"/*.qcow2 2>/dev/null | grep -q .; then
        echo "Available templates:"
        echo "==================="
        for template in "$template_dir"/*.qcow2; do
            local name=$(basename "$template" .qcow2)
            local size=$(du -h "$template" 2>/dev/null | awk '{print $1}' || echo "unknown")
            echo "  • $name ($size)"
        done
    else
        echo "No cloud templates available"
        echo ""
        echo "You can download templates using option 2"
        echo "Templates are stored in: $template_dir"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

download_cloud_template() {
    print_header
    echo -e "${GREEN}⬇️ Download Cloud Template${NC}"
    echo ""
    
    echo "Available templates for download:"
    echo "  1) Ubuntu 24.04 LTS (Server)"
    echo "  2) Ubuntu 22.04 LTS (Server)"
    echo "  3) Debian 12 (Bookworm)"
    echo "  4) Debian 11 (Bullseye)"
    echo "  0) Cancel"
    echo ""
    
    read -p "Select template: " template_choice
    
    declare -A template_urls=(
        [1]="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
        [2]="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
        [3]="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
        [4]="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2"
    )
    
    declare -A template_names=(
        [1]="ubuntu-24.04"
        [2]="ubuntu-22.04"
        [3]="debian-12"
        [4]="debian-11"
    )
    
    if [[ -n "${template_urls[$template_choice]}" ]]; then
        local url="${template_urls[$template_choice]}"
        local name="${template_names[$template_choice]}"
        local output="$USER_HOME/zynexforge/templates/cloud/${name}.qcow2"
        
        echo ""
        echo "Downloading $name..."
        echo "URL: $url"
        echo "Output: $output"
        echo ""
        
        mkdir -p "$(dirname "$output")"
        
        # Check if wget or curl is available
        if command -v wget >/dev/null 2>&1; then
            wget -O "$output" "$url"
            download_status=$?
        elif command -v curl >/dev/null 2>&1; then
            curl -L -o "$output" "$url"
            download_status=$?
        else
            print_error "Neither wget nor curl is available"
            sleep 2
            return
        fi
        
        if [[ $download_status -eq 0 ]]; then
            print_success "Template downloaded: $output"
        else
            print_error "Download failed"
        fi
    elif [[ "$template_choice" == "0" ]]; then
        print_info "Download cancelled"
    else
        print_error "Invalid choice"
    fi
    
    sleep 2
}

list_iso_images() {
    print_header
    echo -e "${GREEN}📀 ISO Images:${NC}"
    echo ""
    
    local iso_dir="$USER_HOME/zynexforge/templates/iso"
    if [[ -d "$iso_dir" ]] && ls "$iso_dir"/*.iso 2>/dev/null | grep -q .; then
        echo "Available ISO images:"
        echo "===================="
        for iso in "$iso_dir"/*.iso; do
            local name=$(basename "$iso" .iso)
            local size=$(du -h "$iso" 2>/dev/null | awk '{print $1}' || echo "unknown")
            echo "  • $name ($size)"
        done
    else
        echo "No ISO images available"
        echo ""
        echo "You can download ISO images using option 4"
        echo "ISOs are stored in: $iso_dir"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

download_iso_image() {
    print_header
    echo -e "${GREEN}⬇️ Download ISO Image${NC}"
    echo ""
    
    echo "Available ISO images for download:"
    echo "  1) Ubuntu 24.04 LTS (Server)"
    echo "  2) Debian 12"
    echo "  0) Cancel"
    echo ""
    
    read -p "Select ISO: " iso_choice
    
    declare -A iso_urls=(
        [1]="https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso"
        [2]="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso"
    )
    
    declare -A iso_names=(
        [1]="ubuntu-24.04-server"
        [2]="debian-12"
    )
    
    if [[ -n "${iso_urls[$iso_choice]}" ]]; then
        local url="${iso_urls[$iso_choice]}"
        local name="${iso_names[$iso_choice]}"
        local output="$USER_HOME/zynexforge/templates/iso/${name}.iso"
        
        echo ""
        echo "Downloading $name..."
        echo "URL: $url"
        echo "Output: $output"
        echo ""
        
        mkdir -p "$(dirname "$output")"
        
        # Check if wget or curl is available
        if command -v wget >/dev/null 2>&1; then
            wget -O "$output" "$url"
            download_status=$?
        elif command -v curl >/dev/null 2>&1; then
            curl -L -o "$output" "$url"
            download_status=$?
        else
            print_error "Neither wget nor curl is available"
            sleep 2
            return
        fi
        
        if [[ $download_status -eq 0 ]]; then
            print_success "ISO downloaded: $output"
        else
            print_error "Download failed"
        fi
    elif [[ "$iso_choice" == "0" ]]; then
        print_info "Download cancelled"
    else
        print_error "Invalid choice"
    fi
    
    sleep 2
}

create_custom_template() {
    print_header
    echo -e "${GREEN}🔧 Create Custom Template${NC}"
    echo ""
    
    echo "This feature allows you to create custom VM templates."
    echo "You can use an existing VM as a base."
    echo ""
    
    # List existing VMs
    echo "Existing VMs:"
    if [[ -d "$DATA_DIR/vms" ]] && ls "$DATA_DIR/vms"/*.conf 2>/dev/null | grep -q .; then
        for conf in "$DATA_DIR/vms"/*.conf; do
            local vm_name=$(basename "$conf" .conf)
            local status=$(grep "status:" "$conf" | awk '{print $2}' | tr -d '"')
            echo "  • $vm_name ($status)"
        done
    else
        echo "No VMs available to use as template source"
        sleep 1
        return
    fi
    
    echo ""
    read -p "Source VM name: " source_vm
    read -p "Template name: " template_name
    
    if [[ -z "$source_vm" ]] || [[ -z "$template_name" ]]; then
        print_error "Source VM and Template name cannot be empty"
        sleep 1
        return
    fi
    
    local vm_config="$DATA_DIR/vms/${source_vm}.conf"
    if [[ ! -f "$vm_config" ]]; then
        print_error "Source VM '$source_vm' not found"
        sleep 1
        return
    fi
    
    local disk_path=$(grep "disk_path:" "$vm_config" | awk '{print $2}' | tr -d '"')
    if [[ ! -f "$disk_path" ]]; then
        print_error "Disk not found for VM '$source_vm'"
        sleep 1
        return
    fi
    
    local template_path="$USER_HOME/zynexforge/templates/cloud/${template_name}.qcow2"
    
    echo ""
    echo "Creating template '$template_name' from VM '$source_vm'..."
    echo "Source disk: $disk_path"
    echo "Template: $template_path"
    echo ""
    
    read -p "Continue? (y/n): " confirm
    
    if [[ "$confirm" == "y" ]]; then
        # Stop VM if running
        stop_vm "$source_vm"
        
        print_info "Copying disk image..."
        
        # Copy disk
        cp "$disk_path" "$template_path"
        
        if [[ $? -eq 0 ]]; then
            print_success "Template created: $template_path"
            echo ""
            echo "You can now use '$template_name' when creating new VMs"
        else
            print_error "Failed to create template"
        fi
    else
        print_info "Template creation cancelled"
    fi
    
    sleep 2
}

# Module menus
kvm_qemu_menu() {
    print_header
    echo -e "${GREEN}⚡ KVM + QEMU VM Cloud${NC}"
    echo ""
    echo "This module provides hardware-accelerated virtualization."
    echo "Requires KVM access and proper permissions."
    echo ""
    echo "Options:"
    echo "  1) Create KVM VM"
    echo "  2) List VMs"
    echo "  3) Return to Main Menu"
    echo ""
    
    read -p "Select option: " choice
    
    case $choice in
        1) vm_create_wizard ;;
        2) list_vms ;;
        3) return ;;
        *) print_error "Invalid option" ;;
    esac
}

qemu_universal_menu() {
    print_header
    echo -e "${GREEN}🖥️ QEMU VM Cloud (Universal)${NC}"
    echo ""
    echo "This module provides software-emulated virtualization."
    echo "Works on any hardware without KVM support."
    echo "Note: Performance will be slower than KVM."
    echo ""
    echo "Options:"
    echo "  1) Create QEMU VM"
    echo "  2) List VMs"
    echo "  3) Return to Main Menu"
    echo ""
    
    read -p "Select option: " choice
    
    case $choice in
        1) vm_create_wizard ;;
        2) list_vms ;;
        3) return ;;
        *) print_error "Invalid option" ;;
    esac
}

lxd_cloud_menu() {
    print_header
    echo -e "${GREEN}🧊 LXD Cloud (VMs/Containers)${NC}"
    echo ""
    echo "This module provides LXD-based virtualization."
    echo ""
    echo "Note: LXD requires separate installation and setup."
    echo ""
    
    echo "Options:"
    echo "  1) Create LXD Instance"
    echo "  2) List LXD Instances"
    echo "  3) Return to Main Menu"
    echo ""
    
    read -p "Select option: " choice
    
    case $choice in
        1)
            create_lxd_instance
            ;;
        2)
            list_lxd_instances
            ;;
        3) return ;;
        *) print_error "Invalid option" ;;
    esac
}

create_lxd_instance() {
    print_header
    echo -e "${GREEN}🧊 Create LXD Instance${NC}"
    echo ""
    
    print_info "LXD support requires manual setup"
    echo "Please install and configure LXD separately"
    echo ""
    echo "Installation commands:"
    echo "  sudo apt install lxd lxd-client"
    echo "  sudo lxd init --auto"
    echo "  sudo usermod -aG lxd \$USER"
    echo "  (logout and login again)"
    echo ""
    echo "After installation, you can use:"
    echo "  lxc launch ubuntu:24.04 my-instance"
    echo "  lxc list"
    
    sleep 2
}

list_lxd_instances() {
    print_header
    echo -e "${GREEN}🧊 LXD Instances${NC}"
    echo ""
    
    if command -v lxc >/dev/null 2>&1; then
        lxc list
    else
        echo "LXC/LXD not installed"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

list_vms() {
    print_header
    echo -e "${GREEN}📋 Virtual Machines${NC}"
    echo ""
    
    if [[ -d "$DATA_DIR/vms" ]] && ls "$DATA_DIR/vms"/*.conf 2>/dev/null | grep -q .; then
        echo "All Virtual Machines:"
        echo "===================="
        for conf in "$DATA_DIR/vms"/*.conf; do
            local vm_name=$(basename "$conf" .conf)
            local status=$(grep "status:" "$conf" | awk '{print $2}' | tr -d '"')
            local node=$(grep "node_id:" "$conf" | awk '{print $2}' | tr -d '"')
            local ssh_port=$(grep "ssh_port:" "$conf" | awk '{print $2}' | tr -d '"')
            local cpu=$(grep "cpu_cores:" "$conf" | awk '{print $2}' | tr -d '"')
            local ram=$(grep "ram_mb:" "$conf" | awk '{print $2}' | tr -d '"')
            
            # Check actual running status
            local actual_status="stopped"
            local pid_file="/tmp/zynexforge_${vm_name}.pid"
            if [[ -f "$pid_file" ]]; then
                local pid=$(cat "$pid_file" 2>/dev/null)
                if ps -p "$pid" >/dev/null 2>&1; then
                    actual_status="running"
                fi
            fi
            
            echo "  • $vm_name [$node] - Config Status: $status - Actual: $actual_status"
            echo "    CPU: ${cpu}v | RAM: ${ram}MB | SSH: $ssh_port"
        done
    else
        echo "No VMs configured"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Main function
main() {
    # Show welcome message
    echo -e "${CYAN}"
    echo "=============================================="
    echo "   ZynexForge CloudStack™ - Non-Root Edition  "
    echo "=============================================="
    echo -e "${NC}"
    echo "🔥 Made by FaaizXD"
    echo ""
    
    # Initialize platform
    initialize_platform
    
    # Start main menu
    main_menu
}

# Handle script arguments
case "${1:-}" in
    "init"|"setup")
        initialize_platform
        print_success "Platform initialized"
        ;;
    "list-vms")
        list_vms
        ;;
    "list-nodes")
        list_nodes
        ;;
    "status")
        print_header
        ;;
    "help"|"--help"|"-h")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  init, setup    Initialize the platform"
        echo "  list-vms       List all virtual machines"
        echo "  list-nodes     List all nodes"
        echo "  status         Show platform status"
        echo "  help           Show this help message"
        echo ""
        echo "Without arguments: Start interactive menu"
        ;;
    *)
        # Start the platform
        main "$@"
        ;;
esac
