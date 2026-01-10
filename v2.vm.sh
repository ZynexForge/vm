#!/bin/bash
set -euo pipefail

# ZynexForge CloudStack™ Platform
# Premium Terminal-Based Virtualization Platform
# Made by FaaizXD

# Global Configuration
CONFIG_DIR="/etc/zynexforge"
DATA_DIR="/var/lib/zynexforge"
LOG_FILE="/var/log/zynexforge.log"
NODES_DB="$CONFIG_DIR/nodes.yml"
GLOBAL_CONFIG="$CONFIG_DIR/config.yml"

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

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Initialize platform
initialize_platform() {
    log "Initializing ZynexForge CloudStack™ Platform"
    
    # Create directory structure
    mkdir -p "$CONFIG_DIR" \
             "$DATA_DIR/vms" \
             "$DATA_DIR/disks" \
             "$DATA_DIR/cloudinit" \
             "$DATA_DIR/dockervm" \
             "$DATA_DIR/lxd" \
             "$DATA_DIR/jupyter" \
             "/storage/templates/cloud" \
             "/storage/templates/iso" \
             "/var/log"
    
    # Create default config if not exists
    if [[ ! -f "$GLOBAL_CONFIG" ]]; then
        cat > "$GLOBAL_CONFIG" << EOF
# ZynexForge Global Configuration
platform:
  name: "ZynexForge CloudStack™"
  version: "1.0.0"
  default_node: "local"
  ssh_base_port: 22000
  max_vms_per_node: 100

security:
  firewall_enabled: true
  default_ssh_user: "zynexuser"
  password_min_length: 8

paths:
  templates: "/storage/templates/cloud"
  isos: "/storage/templates/iso"
  vm_configs: "$DATA_DIR/vms"
  vm_disks: "$DATA_DIR/disks"
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
EOF
    fi
    
    # Check and install dependencies
    check_dependencies
}

# Check and install required packages
check_dependencies() {
    local required_packages=(
        "qemu-system-x86"
        "qemu-utils"
        "cloud-image-utils"
        "genisoimage"
        "jq"
        "yq"
        "nftables"
        "docker.io"
        "lxd"
        "lxd-client"
        "python3"
        "python3-pip"
        "neofetch"
    )
    
    for pkg in "${required_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            echo "⚙️ Installing missing package: $pkg"
            apt-get update && apt-get install -y "$pkg"
        fi
    done
    
    # Install Python packages for Jupyter
    if ! python3 -c "import jupyter" 2>/dev/null; then
        pip3 install jupyterlab
    fi
}

# Print header with system info
print_header() {
    clear
    echo -e "\033[1;36m"
    echo "$ASCII_MAIN_ART"
    echo -e "\033[0m"
    echo -e "\033[1;33m⚡ ZynexForge CloudStack™\033[0m"
    echo -e "\033[1;37m🔥 Made by FaaizXD\033[0m"
    echo "=============================================="
    
    # System capabilities summary
    echo -e "\033[1;34m🖥️ System Capabilities:\033[0m"
    if [[ -e "/dev/kvm" ]]; then
        echo -e "  ⚡ KVM: Available (Hardware Acceleration)"
    else
        echo -e "  ⚡ KVM: Not Available (Software Emulation)"
    fi
    
    if systemctl is-active --quiet docker; then
        echo -e "  🐳 Docker: Running"
    else
        echo -e "  🐳 Docker: Not Running"
    fi
    
    if command -v lxd &> /dev/null; then
        echo -e "  🧊 LXD: Available"
    else
        echo -e "  🧊 LXD: Not Available"
    fi
    
    local vm_count=$(ls "$DATA_DIR/vms"/*.conf 2>/dev/null | wc -l)
    local docker_count=$(ls "$DATA_DIR/dockervm"/*.conf 2>/dev/null | wc -l)
    echo -e "  📊 Active VMs: $vm_count"
    echo -e "  📊 Docker VMs: $docker_count"
    echo "=============================================="
    echo ""
}

# Main menu
main_menu() {
    while true; do
        print_header
        echo -e "\033[1;32mMain Menu:\033[0m"
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
            *) echo "❌ Invalid option"; sleep 1 ;;
        esac
    done
}

# Nodes Management
nodes_menu() {
    while true; do
        print_header
        echo -e "\033[1;32m🖥️ Nodes Management:\033[0m"
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
            *) echo "❌ Invalid option"; sleep 1 ;;
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
    echo -e "\033[1;32m➕ Add New Node\033[0m"
    echo ""
    
    # Select region
    echo "Select region/location:"
    for i in "${!REGIONS[@]}"; do
        echo "  $i) ${REGIONS[$i]}"
    done
    echo "  0) Custom location"
    echo ""
    
    read -p "Enter choice: " region_choice
    
    if [[ $region_choice == "0" ]]; then
        read -p "Enter custom location (City, Country): " custom_location
        location_name="$custom_location"
    elif [[ -n "${REGIONS[$region_choice]}" ]]; then
        location_name="${REGIONS[$region_choice]}"
    else
        echo "❌ Invalid choice"
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
    
    # Create node entry
    node_entry=$(cat << EOF
  $node_id:
    node_id: "$node_id"
    node_name: "$node_name"
    location_name: "$location_name"
    provider: "$provider"
    public_ip: "$public_ip"
    capabilities: [${capabilities// /}]
    tags: [${tags_input// /}]
    status: "active"
    created_at: "$(date -Iseconds)"
EOF
)
    
    # Add to nodes database
    if [[ -f "$NODES_DB" ]]; then
        # Using yq to update YAML if available
        if command -v yq &> /dev/null; then
            yq eval ".nodes.$node_id = {\"node_id\": \"$node_id\", \"node_name\": \"$node_name\", \"location_name\": \"$location_name\", \"provider\": \"$provider\", \"public_ip\": \"$public_ip\", \"capabilities\": [${capabilities// /}], \"tags\": [${tags_input// /}], \"status\": \"active\", \"created_at\": \"$(date -Iseconds)\"}" "$NODES_DB" -i
        else
            # Simple append if yq not available
            echo "$node_entry" >> "$NODES_DB"
        fi
    fi
    
    echo "✅ Node '$node_name' added successfully!"
    log "Added new node: $node_id ($node_name)"
    sleep 2
}

list_nodes() {
    print_header
    echo -e "\033[1;32m📋 Available Nodes:\033[0m"
    echo ""
    
    if [[ -f "$NODES_DB" ]]; then
        if command -v yq &> /dev/null; then
            yq eval '.nodes | to_entries | .[] | "• \(.key): \(.value.node_name) [\(.value.location_name)] - \(.value.status)"' "$NODES_DB"
        else
            grep -A 8 "node_id:" "$NODES_DB" | grep -E "(node_id|node_name|location_name|status)" | sed 's/^[[:space:]]*//'
        fi
    else
        echo "No nodes configured"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

show_node_details() {
    print_header
    echo -e "\033[1;32m🔍 Node Details\033[0m"
    echo ""
    
    read -p "Enter Node ID: " node_id
    
    if [[ -f "$NODES_DB" ]] && grep -q "$node_id:" "$NODES_DB"; then
        echo "Node Details for '$node_id':"
        echo "=========================="
        grep -A 10 "$node_id:" "$NODES_DB" | sed 's/^[[:space:]]*//'
    else
        echo "❌ Node '$node_id' not found"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

remove_node() {
    print_header
    echo -e "\033[1;31m🗑️ Remove Node\033[0m"
    echo ""
    
    read -p "Enter Node ID to remove: " node_id
    
    if [[ "$node_id" == "local" ]]; then
        echo "❌ Cannot remove local node!"
        sleep 1
        return
    fi
    
    if [[ -f "$NODES_DB" ]] && grep -q "$node_id:" "$NODES_DB"; then
        echo "⚠️ Warning: This will remove node '$node_id' from the database."
        read -p "Are you sure? (y/n): " confirm
        
        if [[ "$confirm" == "y" ]]; then
            if command -v yq &> /dev/null; then
                yq eval "del(.nodes.$node_id)" "$NODES_DB" -i
            else
                # Simple removal (crude but works for basic format)
                sed -i "/$node_id:/,+8d" "$NODES_DB"
            fi
            echo "✅ Node '$node_id' removed"
            log "Removed node: $node_id"
        fi
    else
        echo "❌ Node '$node_id' not found"
    fi
    
    sleep 1
}

# VM Creation Wizard
vm_create_wizard() {
    print_header
    echo -e "\033[1;32m🚀 Create New VM\033[0m"
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
    echo "  [1] KVM+QEMU fast (requires /dev/kvm)"
    echo "  [2] QEMU universal"
    read -p "Choice (1/2): " runtime_choice
    
    if [[ "$runtime_choice" == "1" ]]; then
        if [[ ! -e "/dev/kvm" ]]; then
            echo "❌ KVM not available on this system!"
            sleep 1
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
        *) echo "❌ Invalid choice"; return ;;
    esac
    
    # VM details
    echo ""
    read -p "VM Name: " vm_name
    
    # Resource allocation
    echo ""
    read -p "CPU cores (1-16): " cpu_cores
    read -p "RAM in MB (512-32768): " ram_mb
    read -p "Disk size in GB (10-500): " disk_gb
    
    # SSH port
    echo ""
    read -p "SSH Port (e.g., 22001): " ssh_port
    
    # Credentials
    echo ""
    read -p "Username: " vm_user
    read -sp "Password: " vm_pass
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
    fi
}

list_nodes_simple() {
    if [[ -f "$NODES_DB" ]]; then
        if command -v yq &> /dev/null; then
            yq eval '.nodes | to_entries | .[] | "  \(.key): \(.value.node_name) [\(.value.location_name)]"' "$NODES_DB"
        else
            grep -B 1 -A 1 "node_id:" "$NODES_DB" | grep -E "(node_id|node_name)" | sed 's/^[[:space:]]*//'
        fi
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
    
    # Check if template exists
    local template_path="/storage/templates/cloud/${os_template}.qcow2"
    if [[ -f "$template_path" ]]; then
        echo "📦 Using template: $os_template"
        cp "$template_path" "$disk_path"
        qemu-img resize "$disk_path" "${disk_gb}G" >/dev/null 2>&1
    else
        echo "📦 Creating blank disk"
        qemu-img create -f qcow2 "$disk_path" "${disk_gb}G"
    fi
    
    # Create cloud-init data
    cat > "$cloudinit_dir/user-data" << EOF
#cloud-config
hostname: $vm_name
manage_etc_hosts: true
users:
  - name: $vm_user
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: $vm_pass
    ssh_authorized_keys:
      - $(cat ~/.ssh/id_rsa.pub 2>/dev/null || echo "ssh-rsa AAAAB3NzaC1yc2E...")
packages:
  - neofetch
  - openssh-server
  - curl
  - wget
package_update: true
package_upgrade: true
runcmd:
  - echo "$OS_ASCII_ART" > /etc/zynexforge-os.ascii
  - echo -e '#!/bin/bash\nneofetch\ncat /etc/zynexforge-os.ascii\necho -e "\\033[1;36m⚡ ZynexForge CloudStack™\\033[0m"\necho -e "\\033[1;33m🔥 Made by FaaizXD\\033[0m"\necho -e "\\033[1;32mStatus: Premium VPS Active\\033[0m"\necho -e "\\033[1;35mStats: $(free -h | awk '\''/Mem:/ {print "RAM: " $2 "/" $3}'\''), Cores: $(nproc), Disk: $(df -h / | tail -1 | awk '\''{print $4}'\''), Load: $(uptime | awk -F'load average:' '\''{print $2}'\''), Uptime: $(uptime -p)"\\033[0m"' > /etc/profile.d/zynexforge-login.sh
  - chmod +x /etc/profile.d/zynexforge-login.sh
  - systemctl restart sshd
EOF
    
    cat > "$cloudinit_dir/meta-data" << EOF
instance-id: $vm_name
local-hostname: $vm_name
EOF
    
    # Create seed ISO
    genisoimage -output "$cloudinit_dir/seed.iso" -volid cidata -joliet -rock \
        "$cloudinit_dir/user-data" "$cloudinit_dir/meta-data" >/dev/null 2>&1
    
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
EOF
    
    echo "✅ VM '$vm_name' created successfully!"
    echo ""
    echo "📋 Access Information:"
    echo "  VM Name: $vm_name"
    echo "  SSH Port: $ssh_port"
    echo "  Username: $vm_user"
    echo "  Password: $vm_pass"
    echo ""
    echo "🔗 SSH Command:"
    echo "  ssh -p $ssh_port $vm_user@localhost"
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
        echo "❌ VM '$vm_name' not found"
        return 1
    fi
    
    # Read config
    local ssh_port=$(grep "ssh_port:" "$vm_config" | awk '{print $2}')
    local cpu_cores=$(grep "cpu_cores:" "$vm_config" | awk '{print $2}')
    local ram_mb=$(grep "ram_mb:" "$vm_config" | awk '{print $2}')
    local disk_path=$(grep "disk_path:" "$vm_config" | awk '{print $2}')
    local acceleration=$(grep "acceleration:" "$vm_config" | awk '{print $2}')
    local seed_iso="$DATA_DIR/cloudinit/$vm_name/seed.iso"
    
    # Build QEMU command
    local cmd="qemu-system-x86_64"
    local args="-name $vm_name"
    
    # Acceleration
    if [[ "$acceleration" == "kvm" && -e "/dev/kvm" ]]; then
        args="$args -enable-kvm -cpu host"
    else
        args="$args -cpu qemu64"
    fi
    
    # Resources
    args="$args -smp $cpu_cores -m $ram_mb"
    
    # Display (none for headless)
    args="$args -display none -vga none"
    
    # Network with hostfwd
    args="$args -netdev user,id=net0,hostfwd=tcp::$ssh_port-:22"
    args="$args -device virtio-net-pci,netdev=net0"
    
    # Storage
    args="$args -drive file=$disk_path,if=virtio,format=qcow2"
    args="$args -drive file=$seed_iso,if=virtio,format=raw"
    
    # Miscellaneous
    args="$args -daemonize -pidfile /tmp/zynexforge_${vm_name}.pid"
    
    echo "🚀 Starting VM '$vm_name'..."
    $cmd $args
    
    # Update status
    sed -i "s/status:.*/status: \"running\"/" "$vm_config"
    
    echo "✅ VM '$vm_name' started"
    echo "📡 SSH accessible on port: $ssh_port"
    
    # Show access info
    show_vm_access "$vm_name"
}

stop_vm() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    
    if [[ ! -f "$vm_config" ]]; then
        echo "❌ VM '$vm_name' not found"
        return 1
    fi
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        kill "$pid" 2>/dev/null
        rm -f "$pid_file"
        echo "🛑 VM '$vm_name' stopped"
    else
        echo "⚠️ VM '$vm_name' not running"
    fi
    
    # Update status
    sed -i "s/status:.*/status: \"stopped\"/" "$vm_config"
}

show_vm_access() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [[ ! -f "$vm_config" ]]; then
        echo "❌ VM '$vm_name' not found"
        return 1
    fi
    
    local ssh_port=$(grep "ssh_port:" "$vm_config" | awk '{print $2}')
    local vm_user=$(grep "vm_user:" "$vm_config" | awk '{print $2}')
    local vm_pass=$(grep "vm_pass:" "$vm_config" | awk '{print $2}')
    
    echo ""
    echo "📋 Access Information for '$vm_name':"
    echo "  SSH Port: $ssh_port"
    echo "  Username: $vm_user"
    echo "  Password: $vm_pass"
    echo ""
    echo "🔗 SSH Commands:"
    echo "  ssh -p $ssh_port $vm_user@localhost"
    echo "  ssh -o StrictHostKeyChecking=no -p $ssh_port $vm_user@localhost"
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
        echo -e "\033[1;32m🐳 Docker VM Cloud:\033[0m"
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
            *) echo "❌ Invalid option"; sleep 1 ;;
        esac
    done
}

create_docker_vm() {
    print_header
    echo -e "\033[1;32m🐳 Create Docker VM\033[0m"
    echo ""
    
    # Node selection
    echo "Select Node:"
    list_nodes_simple
    echo ""
    read -p "Enter Node ID (default: local): " node_id
    node_id=${node_id:-local}
    
    # Docker VM details
    read -p "Docker VM Name: " dv_name
    
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
        *) echo "❌ Invalid choice"; return ;;
    esac
    
    # Resource limits
    echo ""
    read -p "CPU limit (e.g., 1.5 or 2): " cpu_limit
    read -p "Memory limit (e.g., 512m or 2g): " memory_limit
    read -p "PIDs limit (e.g., 100): " pids_limit
    
    # SSH support
    echo ""
    read -p "Enable SSH access? (y/n): " enable_ssh
    if [[ "$enable_ssh" == "y" ]]; then
        read -p "SSH Port (e.g., 22022): " ssh_port
        read -p "SSH Username: " ssh_user
        read -sp "SSH Password: " ssh_pass
        echo ""
    fi
    
    # Port mappings
    echo ""
    echo "Port mappings (e.g., 8080:80 8443:443)"
    read -p "Enter port mappings (space-separated): " port_mappings
    
    # Create Docker VM
    echo ""
    echo "Creating Docker VM '$dv_name'..."
    
    # Build Docker command
    local docker_cmd="docker run -d"
    docker_cmd="$docker_cmd --name $dv_name"
    docker_cmd="$docker_cmd --hostname $dv_name"
    
    if [[ -n "$cpu_limit" ]]; then
        docker_cmd="$docker_cmd --cpus=$cpu_limit"
    fi
    
    if [[ -n "$memory_limit" ]]; then
        docker_cmd="$docker_cmd --memory=$memory_limit"
    fi
    
    if [[ -n "$pids_limit" ]]; then
        docker_cmd="$docker_cmd --pids-limit=$pids_limit"
    fi
    
    if [[ "$enable_ssh" == "y" && -n "$ssh_port" ]]; then
        docker_cmd="$docker_cmd -p $ssh_port:22"
    fi
    
    # Add port mappings
    for mapping in $port_mappings; do
        docker_cmd="$docker_cmd -p $mapping"
    done
    
    docker_cmd="$docker_cmd $base_image"
    
    # Start with bash to keep running
    docker_cmd="$docker_cmd tail -f /dev/null"
    
    # Execute
    if eval "$docker_cmd"; then
        echo "✅ Docker VM '$dv_name' created"
        
        # Install SSH if enabled
        if [[ "$enable_ssh" == "y" ]]; then
            docker exec "$dv_name" apt-get update && \
            docker exec "$dv_name" apt-get install -y openssh-server || \
            docker exec "$dv_name" apk add openssh-server || \
            docker exec "$dv_name" yum install -y openssh-server
            
            # Set password
            docker exec "$dv_name" bash -c "echo '$ssh_user:$ssh_pass' | chpasswd"
            docker exec "$dv_name" service ssh start || \
            docker exec "$dv_name" /usr/sbin/sshd
            
            echo "🔐 SSH installed on port $ssh_port"
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
pids_limit: "$pids_limit"
enable_ssh: "$enable_ssh"
ssh_port: "$ssh_port"
ssh_user: "$ssh_user"
ssh_pass: "$ssh_pass"
port_mappings: "$port_mappings"
status: "running"
created_at: "$(date -Iseconds)"
container_id: $(docker ps -qf "name=$dv_name")
EOF
        
        log "Created Docker VM: $dv_name"
        
        # Show access info
        if [[ "$enable_ssh" == "y" ]]; then
            echo ""
            echo "📋 SSH Access:"
            echo "  ssh -p $ssh_port $ssh_user@localhost"
        fi
    else
        echo "❌ Failed to create Docker VM"
    fi
    
    sleep 2
}

start_docker_vm() {
    print_header
    echo -e "\033[1;32m🚀 Start Docker VM\033[0m"
    echo ""
    
    read -p "Docker VM Name: " dv_name
    
    if docker start "$dv_name" 2>/dev/null; then
        echo "✅ Docker VM '$dv_name' started"
        
        # Update config
        local dv_config="$DATA_DIR/dockervm/${dv_name}.conf"
        if [[ -f "$dv_config" ]]; then
            sed -i "s/status:.*/status: \"running\"/" "$dv_config"
        fi
    else
        echo "❌ Docker VM '$dv_name' not found"
    fi
    
    sleep 1
}

stop_docker_vm() {
    print_header
    echo -e "\033[1;31m🛑 Stop Docker VM\033[0m"
    echo ""
    
    read -p "Docker VM Name: " dv_name
    
    if docker stop "$dv_name" 2>/dev/null; then
        echo "✅ Docker VM '$dv_name' stopped"
        
        # Update config
        local dv_config="$DATA_DIR/dockervm/${dv_name}.conf"
        if [[ -f "$dv_config" ]]; then
            sed -i "s/status:.*/status: \"stopped\"/" "$dv_config"
        fi
    else
        echo "❌ Docker VM '$dv_name' not found"
    fi
    
    sleep 1
}

show_docker_vm_info() {
    print_header
    echo -e "\033[1;32m🔍 Docker VM Info\033[0m"
    echo ""
    
    read -p "Docker VM Name: " dv_name
    
    local dv_config="$DATA_DIR/dockervm/${dv_name}.conf"
    if [[ -f "$dv_config" ]]; then
        echo "Configuration for '$dv_name':"
        echo "=============================="
        cat "$dv_config"
        
        # Show Docker stats
        echo ""
        echo "📊 Docker Container Stats:"
        docker ps -af "name=$dv_name" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        echo "❌ Docker VM '$dv_name' not found"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

docker_vm_console() {
    print_header
    echo -e "\033[1;32m💻 Docker VM Console\033[0m"
    echo ""
    
    read -p "Docker VM Name: " dv_name
    
    if docker ps -qf "name=$dv_name" | grep -q .; then
        echo "Connecting to '$dv_name' console..."
        echo "Use 'exit' to return to menu"
        echo ""
        docker exec -it "$dv_name" /bin/bash || docker exec -it "$dv_name" /bin/sh
    else
        echo "❌ Docker VM '$dv_name' not running"
        sleep 1
    fi
}

delete_docker_vm() {
    print_header
    echo -e "\033[1;31m🗑️ Delete Docker VM\033[0m"
    echo ""
    
    read -p "Docker VM Name: " dv_name
    
    echo "⚠️ Warning: This will permanently delete '$dv_name'"
    read -p "Are you sure? (y/n): " confirm
    
    if [[ "$confirm" == "y" ]]; then
        docker stop "$dv_name" 2>/dev/null
        docker rm "$dv_name" 2>/dev/null
        
        # Remove config
        local dv_config="$DATA_DIR/dockervm/${dv_name}.conf"
        rm -f "$dv_config"
        
        echo "✅ Docker VM '$dv_name' deleted"
        log "Deleted Docker VM: $dv_name"
    fi
    
    sleep 1
}

# Jupyter Cloud Lab
jupyter_cloud_menu() {
    while true; do
        print_header
        echo -e "\033[1;32m🔬 Jupyter Cloud Lab:\033[0m"
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
            *) echo "❌ Invalid option"; sleep 1 ;;
        esac
    done
}

create_jupyter_vm() {
    print_header
    echo -e "\033[1;32m🔬 Create Jupyter VM\033[0m"
    echo ""
    
    read -p "Jupyter VM Name: " jv_name
    read -p "Jupyter Port (e.g., 8888): " jv_port
    read -p "Volume size (e.g., 10g): " volume_size
    
    # Generate token
    local jv_token=$(openssl rand -hex 16)
    
    echo ""
    echo "Creating Jupyter VM '$jv_name'..."
    
    # Create Docker volume for persistence
    docker volume create "${jv_name}_data" >/dev/null 2>&1
    
    # Start Jupyter container
    if docker run -d \
        --name "$jv_name" \
        -p "$jv_port:8888" \
        -v "${jv_name}_data:/home/jovyan/work" \
        -e JUPYTER_TOKEN="$jv_token" \
        jupyter/datascience-notebook \
        start-notebook.sh --NotebookApp.token="$jv_token" \
        --NotebookApp.notebook_dir=/home/jovyan/work; then
        
        echo "✅ Jupyter VM '$jv_name' created"
        
        # Save config
        local jv_dir="$DATA_DIR/jupyter"
        mkdir -p "$jv_dir"
        
        cat > "$jv_dir/${jv_name}.conf" << EOF
# Jupyter VM Configuration
jv_name: "$jv_name"
jv_port: "$jv_port"
jv_token: "$jv_token"
volume_name: "${jv_name}_data"
volume_size: "$volume_size"
status: "running"
created_at: "$(date -Iseconds)"
container_id: $(docker ps -qf "name=$jv_name")
EOF
        
        # Show access URL
        local public_ip=$(curl -s ifconfig.me || echo "localhost")
        
        echo ""
        echo "📋 Jupyter Access Information:"
        echo "  URL: http://$public_ip:$jv_port"
        echo "  Token: $jv_token"
        echo "  Local URL: http://localhost:$jv_port"
        echo ""
        echo "🔗 Direct URL with token:"
        echo "  http://$public_ip:$jv_port/?token=$jv_token"
        
        log "Created Jupyter VM: $jv_name"
    else
        echo "❌ Failed to create Jupyter VM"
    fi
    
    sleep 2
}

list_jupyter_vms() {
    print_header
    echo -e "\033[1;32m📋 Jupyter VMs:\033[0m"
    echo ""
    
    if ls "$DATA_DIR/jupyter"/*.conf 2>/dev/null | grep -q .; then
        for conf in "$DATA_DIR/jupyter"/*.conf; do
            local name=$(basename "$conf" .conf)
            local port=$(grep "jv_port:" "$conf" | awk '{print $2}')
            local status=$(grep "status:" "$conf" | awk '{print $2}')
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
    echo -e "\033[1;31m🛑 Stop Jupyter VM\033[0m"
    echo ""
    
    read -p "Jupyter VM Name: " jv_name
    
    if docker stop "$jv_name" 2>/dev/null; then
        echo "✅ Jupyter VM '$jv_name' stopped"
        
        # Update config
        local jv_config="$DATA_DIR/jupyter/${jv_name}.conf"
        if [[ -f "$jv_config" ]]; then
            sed -i "s/status:.*/status: \"stopped\"/" "$jv_config"
        fi
    else
        echo "❌ Jupyter VM '$jv_name' not found"
    fi
    
    sleep 1
}

delete_jupyter_vm() {
    print_header
    echo -e "\033[1;31m🗑️ Delete Jupyter VM\033[0m"
    echo ""
    
    read -p "Jupyter VM Name: " jv_name
    
    echo "⚠️ Warning: This will permanently delete '$jv_name'"
    read -p "Are you sure? (y/n): " confirm
    
    if [[ "$confirm" == "y" ]]; then
        docker stop "$jv_name" 2>/dev/null
        docker rm "$jv_name" 2>/dev/null
        docker volume rm "${jv_name}_data" 2>/dev/null
        
        # Remove config
        local jv_config="$DATA_DIR/jupyter/${jv_name}.conf"
        rm -f "$jv_config"
        
        echo "✅ Jupyter VM '$jv_name' deleted"
        log "Deleted Jupyter VM: $jv_name"
    fi
    
    sleep 1
}

show_jupyter_url() {
    print_header
    echo -e "\033[1;32m🔗 Jupyter URL\033[0m"
    echo ""
    
    read -p "Jupyter VM Name: " jv_name
    
    local jv_config="$DATA_DIR/jupyter/${jv_name}.conf"
    if [[ -f "$jv_config" ]]; then
        local port=$(grep "jv_port:" "$jv_config" | awk '{print $2}')
        local token=$(grep "jv_token:" "$jv_config" | awk '{print $2}')
        local public_ip=$(curl -s ifconfig.me || echo "localhost")
        
        echo "Access Information for '$jv_name':"
        echo "================================="
        echo "  URL: http://$public_ip:$port"
        echo "  Token: $token"
        echo "  Local URL: http://localhost:$port"
        echo ""
        echo "🔗 Direct URL with token:"
        echo "  http://$public_ip:$port/?token=$token"
    else
        echo "❌ Jupyter VM '$jv_name' not found"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# VM Manager (Lifecycle Menu)
vm_manager_menu() {
    while true; do
        print_header
        echo -e "\033[1;32m⚙️ VM Manager:\033[0m"
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
                read -p "VM Name: " vm_name
                start_vm "$vm_name"
                ;;
            3)
                read -p "VM Name: " vm_name
                stop_vm "$vm_name"
                ;;
            4)
                read -p "VM Name: " vm_name
                show_vm_info "$vm_name"
                ;;
            5)
                read -p "VM Name: " vm_name
                edit_vm_config "$vm_name"
                ;;
            6)
                read -p "VM Name: " vm_name
                delete_vm "$vm_name"
                ;;
            7)
                read -p "VM Name: " vm_name
                resize_vm_disk "$vm_name"
                ;;
            8)
                read -p "VM Name: " vm_name
                show_vm_performance "$vm_name"
                ;;
            9)
                read -p "VM Name: " vm_name
                show_vm_access "$vm_name"
                ;;
            0) return ;;
            *) echo "❌ Invalid option"; sleep 1 ;;
        esac
    done
}

show_vm_info() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [[ ! -f "$vm_config" ]]; then
        echo "❌ VM '$vm_name' not found"
        return 1
    fi
    
    print_header
    echo -e "\033[1;32m🔍 VM Information: $vm_name\033[0m"
    echo ""
    
    cat "$vm_config"
    echo ""
    
    # Show disk usage
    local disk_path=$(grep "disk_path:" "$vm_config" | awk '{print $2}')
    if [[ -f "$disk_path" ]]; then
        echo "📊 Disk Information:"
        qemu-img info "$disk_path" | grep -E "(virtual size|disk size|format)"
    fi
    
    # Show process if running
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        echo ""
        echo "🔄 Process Status: Running (PID: $pid)"
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
        echo "❌ VM '$vm_name' not found"
        return 1
    fi
    
    print_header
    echo -e "\033[1;32m✏️ Edit VM Configuration: $vm_name\033[0m"
    echo ""
    
    # Show current config
    echo "Current configuration:"
    cat "$vm_config"
    echo ""
    
    echo "What would you like to edit?"
    echo "  1) SSH Port"
    echo "  2) RAM Size"
    echo "  3) CPU Cores"
    echo "  4) Username/Password"
    echo "  0) Cancel"
    echo ""
    
    read -p "Choice: " edit_choice
    
    case $edit_choice in
        1)
            read -p "New SSH Port: " new_port
            sed -i "s/ssh_port:.*/ssh_port: \"$new_port\"/" "$vm_config"
            echo "✅ SSH Port updated to $new_port"
            ;;
        2)
            read -p "New RAM in MB: " new_ram
            sed -i "s/ram_mb:.*/ram_mb: \"$new_ram\"/" "$vm_config"
            echo "✅ RAM updated to ${new_ram}MB"
            ;;
        3)
            read -p "New CPU Cores: " new_cpu
            sed -i "s/cpu_cores:.*/cpu_cores: \"$new_cpu\"/" "$vm_config"
            echo "✅ CPU Cores updated to $new_cpu"
            ;;
        4)
            read -p "New Username: " new_user
            read -sp "New Password: " new_pass
            echo ""
            sed -i "s/vm_user:.*/vm_user: \"$new_user\"/" "$vm_config"
            sed -i "s/vm_pass:.*/vm_pass: \"$new_pass\"/" "$vm_config"
            echo "✅ Credentials updated"
            ;;
        0)
            echo "❌ Edit cancelled"
            ;;
        *)
            echo "❌ Invalid choice"
            ;;
    esac
    
    sleep 1
}

delete_vm() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [[ ! -f "$vm_config" ]]; then
        echo "❌ VM '$vm_name' not found"
        return 1
    fi
    
    print_header
    echo -e "\033[1;31m🗑️ Delete VM: $vm_name\033[0m"
    echo ""
    
    echo "⚠️ Warning: This will permanently delete VM '$vm_name'"
    read -p "Are you sure? (y/n): " confirm
    
    if [[ "$confirm" != "y" ]]; then
        echo "❌ Deletion cancelled"
        return
    fi
    
    # Stop VM if running
    stop_vm "$vm_name"
    
    # Remove files
    local disk_path=$(grep "disk_path:" "$vm_config" | awk '{print $2}')
    local cloudinit_dir="$DATA_DIR/cloudinit/$vm_name"
    
    rm -f "$vm_config"
    rm -f "$disk_path"
    rm -rf "$cloudinit_dir"
    rm -f "/tmp/zynexforge_${vm_name}.pid"
    
    echo "✅ VM '$vm_name' deleted"
    log "Deleted VM: $vm_name"
    sleep 1
}

resize_vm_disk() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [[ ! -f "$vm_config" ]]; then
        echo "❌ VM '$vm_name' not found"
        return 1
    fi
    
    print_header
    echo -e "\033[1;32m💾 Resize VM Disk: $vm_name\033[0m"
    echo ""
    
    local disk_path=$(grep "disk_path:" "$vm_config" | awk '{print $2}')
    local current_size=$(qemu-img info "$disk_path" | grep "virtual size" | awk '{print $3}')
    
    echo "Current disk size: $current_size"
    read -p "New size (e.g., 50G): " new_size
    
    echo "⚠️ Warning: Disk resize cannot be undone"
    read -p "Continue? (y/n): " confirm
    
    if [[ "$confirm" == "y" ]]; then
        # Ensure VM is stopped
        stop_vm "$vm_name"
        
        # Resize disk
        if qemu-img resize "$disk_path" "$new_size"; then
            # Update config
            local new_gb=$(echo "$new_size" | sed 's/[^0-9]*//g')
            sed -i "s/disk_gb:.*/disk_gb: \"$new_gb\"/" "$vm_config"
            echo "✅ Disk resized to $new_size"
        else
            echo "❌ Failed to resize disk"
        fi
    else
        echo "❌ Resize cancelled"
    fi
    
    sleep 1
}

show_vm_performance() {
    local vm_name=$1
    local vm_config="$DATA_DIR/vms/${vm_name}.conf"
    
    if [[ ! -f "$vm_config" ]]; then
        echo "❌ VM '$vm_name' not found"
        return 1
    fi
    
    print_header
    echo -e "\033[1;32m📊 VM Performance: $vm_name\033[0m"
    echo ""
    
    local pid_file="/tmp/zynexforge_${vm_name}.pid"
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        
        echo "Process Resources (PID: $pid):"
        echo "==============================="
        ps -p "$pid" -o pid,ppid,pcpu,pmem,etime,cmd
        
        echo ""
        echo "System Resources:"
        echo "================="
        echo "CPU Usage: $(top -bn1 -p $pid | tail -1 | awk '{print $9}')%"
        echo "Memory Usage: $(top -bn1 -p $pid | tail -1 | awk '{print $10}')%"
        
        # Network connections
        echo ""
        echo "Network Connections:"
        netstat -tunap 2>/dev/null | grep "$pid" || echo "No active network connections"
    else
        echo "VM is not running"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Security Menu
security_menu() {
    while true; do
        print_header
        echo -e "\033[1;32m🛡️ Security:\033[0m"
        echo "  1) Configure Firewall"
        echo "  2) List Firewall Rules"
        echo "  3) Reset Firewall"
        echo "  4) Show Security Status"
        echo "  0) Back"
        echo ""
        
        read -p "Select option: " choice
        
        case $choice in
            1) configure_firewall ;;
            2) list_firewall_rules ;;
            3) reset_firewall ;;
            4) show_security_status ;;
            0) return ;;
            *) echo "❌ Invalid option"; sleep 1 ;;
        esac
    done
}

configure_firewall() {
    print_header
    echo -e "\033[1;32m🛡️ Configure Firewall\033[0m"
    echo ""
    
    # Create basic nftables config
    cat > /tmp/zynexforge.nft << 'EOF'
#!/usr/sbin/nft -f

# Flush existing rules
flush ruleset

# Define variables
define ssh_port = 22
define admin_ips = { 0.0.0.0/0 }

# Create tables
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        
        # Accept established/related connections
        ct state established,related accept
        
        # Accept loopback
        iif lo accept
        
        # Accept ICMP
        ip protocol icmp accept
        
        # Accept SSH
        tcp dport $ssh_port ip saddr $admin_ips accept
        
        # Accept ZynexForge VM ports (22000-23000)
        tcp dport 22000-23000 accept
        
        # Counter for dropped packets
        counter drop
    }
    
    chain forward {
        type filter hook forward priority 0; policy accept;
    }
    
    chain output {
        type filter hook output priority 0; policy accept;
    }
}

table inet nat {
    chain prerouting {
        type nat hook prerouting priority -100; policy accept;
    }
    
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
    }
}
EOF
    
    # Apply rules
    if nft -f /tmp/zynexforge.nft; then
        echo "✅ Firewall configured successfully"
        echo "📋 Rules applied:"
        echo "  • Allow SSH on port 22"
        echo "  • Allow VM SSH ports 22000-23000"
        echo "  • Allow ICMP (ping)"
        echo "  • Drop all other inbound traffic"
    else
        echo "❌ Failed to configure firewall"
    fi
    
    sleep 2
}

list_firewall_rules() {
    print_header
    echo -e "\033[1;32m📋 Firewall Rules\033[0m"
    echo ""
    
    if command -v nft &> /dev/null; then
        nft list ruleset
    else
        echo "nftables not installed"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

reset_firewall() {
    print_header
    echo -e "\033[1;31m🔄 Reset Firewall\033[0m"
    echo ""
    
    echo "⚠️ Warning: This will reset firewall to default (ACCEPT all)"
    read -p "Continue? (y/n): " confirm
    
    if [[ "$confirm" == "y" ]]; then
        nft flush ruleset
        nft add table inet filter
        nft add chain inet filter input { type filter hook input priority 0\; policy accept\; }
        nft add chain inet filter forward { type filter hook forward priority 0\; policy accept\; }
        nft add chain inet filter output { type filter hook output priority 0\; policy accept\; }
        echo "✅ Firewall reset to default (ACCEPT all)"
    else
        echo "❌ Reset cancelled"
    fi
    
    sleep 1
}

show_security_status() {
    print_header
    echo -e "\033[1;32m🔒 Security Status\033[0m"
    echo ""
    
    echo "🛡️ Firewall Status:"
    if systemctl is-active --quiet nftables; then
        echo "  ✅ nftables: Active"
    else
        echo "  ❌ nftables: Inactive"
    fi
    
    echo ""
    echo "🔐 SSH Security:"
    if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
        echo "  ✅ Password auth: Disabled"
    else
        echo "  ⚠️ Password auth: Enabled"
    fi
    
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
        echo "  ✅ Root login: Disabled"
    else
        echo "  ⚠️ Root login: Enabled"
    fi
    
    echo ""
    echo "📊 VM Security:"
    echo "  Total VMs: $(ls "$DATA_DIR/vms"/*.conf 2>/dev/null | wc -l)"
    echo "  Running VMs: $(grep -l "status: \"running\"" "$DATA_DIR/vms"/*.conf 2>/dev/null | wc -l)"
    
    echo ""
    read -p "Press Enter to continue..."
}

# Monitoring Menu
monitoring_menu() {
    while true; do
        print_header
        echo -e "\033[1;32m📊 Monitoring:\033[0m"
        echo "  1) System Overview"
        echo "  2) VM Resources"
        echo "  3) Docker Resources"
        echo "  4) Network Traffic"
        echo "  5) Disk Usage"
        echo "  0) Back"
        echo ""
        
        read -p "Select option: " choice
        
        case $choice in
            1) system_overview ;;
            2) vm_resources ;;
            3) docker_resources ;;
            4) network_traffic ;;
            5) disk_usage ;;
            0) return ;;
            *) echo "❌ Invalid option"; sleep 1 ;;
        esac
    done
}

system_overview() {
    print_header
    echo -e "\033[1;32m📊 System Overview\033[0m"
    echo ""
    
    # CPU
    echo "🖥️ CPU:"
    echo "  Cores: $(nproc)"
    echo "  Load: $(uptime | awk -F'load average:' '{print $2}')"
    echo "  Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
    
    # Memory
    echo ""
    echo "🧠 Memory:"
    free -h | awk '/^Mem:/ {print "  Total: " $2 " | Used: " $3 " | Free: " $4 " | Usage: " $3/$2*100 "%"}'
    
    # Disk
    echo ""
    echo "💾 Disk:"
    df -h / | tail -1 | awk '{print "  Total: " $2 " | Used: " $3 " | Free: " $4 " | Usage: " $5}'
    
    # Uptime
    echo ""
    echo "⏰ Uptime: $(uptime -p)"
    
    echo ""
    read -p "Press Enter to continue..."
}

vm_resources() {
    print_header
    echo -e "\033[1;32m📊 VM Resources\033[0m"
    echo ""
    
    local total_vms=0
    local running_vms=0
    local total_cpu=0
    local total_ram=0
    
    if ls "$DATA_DIR/vms"/*.conf 2>/dev/null | grep -q .; then
        for conf in "$DATA_DIR/vms"/*.conf; do
            local vm_name=$(basename "$conf" .conf)
            local status=$(grep "status:" "$conf" | awk '{print $2}' | tr -d '"')
            local cpu=$(grep "cpu_cores:" "$conf" | awk '{print $2}' | tr -d '"')
            local ram=$(grep "ram_mb:" "$conf" | awk '{print $2}' | tr -d '"')
            
            total_vms=$((total_vms + 1))
            if [[ "$status" == "running" ]]; then
                running_vms=$((running_vms + 1))
                total_cpu=$((total_cpu + cpu))
                total_ram=$((total_ram + ram))
            fi
            
            echo "  • $vm_name: $status | CPU: ${cpu}v | RAM: ${ram}MB"
        done
        
        echo ""
        echo "📈 Summary:"
        echo "  Total VMs: $total_vms"
        echo "  Running VMs: $running_vms"
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
    echo -e "\033[1;32m🐳 Docker Resources\033[0m"
    echo ""
    
    if command -v docker &> /dev/null; then
        echo "📊 Docker System Info:"
        docker system df
        
        echo ""
        echo "📦 Running Containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    else
        echo "Docker not installed"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

network_traffic() {
    print_header
    echo -e "\033[1;32m🌐 Network Traffic\033[0m"
    echo ""
    
    echo "📡 Network Interfaces:"
    ip -br addr show
    
    echo ""
    echo "🔗 Active Connections:"
    ss -tunap | head -20
    
    echo ""
    read -p "Press Enter to continue..."
}

disk_usage() {
    print_header
    echo -e "\033[1;32m💾 Disk Usage\033[0m"
    echo ""
    
    echo "📁 Platform Directories:"
    echo "  /etc/zynexforge: $(du -sh /etc/zynexforge 2>/dev/null | awk '{print $1}')"
    echo "  /var/lib/zynexforge: $(du -sh /var/lib/zynexforge 2>/dev/null | awk '{print $1}')"
    echo "  /storage/templates: $(du -sh /storage/templates 2>/dev/null | awk '{print $1}')"
    echo "  VM Disks: $(du -sh /var/lib/zynexforge/disks 2>/dev/null | awk '{print $1}')"
    
    echo ""
    echo "📊 Overall Disk Usage:"
    df -h
    
    echo ""
    read -p "Press Enter to continue..."
}

# Templates + ISO Library
templates_menu() {
    while true; do
        print_header
        echo -e "\033[1;32m⚙️ Templates + ISO Library:\033[0m"
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
            *) echo "❌ Invalid option"; sleep 1 ;;
        esac
    done
}

list_cloud_templates() {
    print_header
    echo -e "\033[1;32m📦 Cloud Templates:\033[0m"
    echo ""
    
    local template_dir="/storage/templates/cloud"
    if [[ -d "$template_dir" ]] && ls "$template_dir"/*.qcow2 2>/dev/null | grep -q .; then
        for template in "$template_dir"/*.qcow2; do
            local name=$(basename "$template" .qcow2)
            local size=$(du -h "$template" | awk '{print $1}')
            echo "  • $name ($size)"
        done
    else
        echo "No cloud templates available"
        echo ""
        echo "You can download templates using option 2"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

download_cloud_template() {
    print_header
    echo -e "\033[1;32m⬇️ Download Cloud Template\033[0m"
    echo ""
    
    echo "Available templates for download:"
    echo "  1) Ubuntu 24.04 LTS"
    echo "  2) Ubuntu 22.04 LTS"
    echo "  3) Debian 12"
    echo "  4) Debian 11"
    echo "  5) AlmaLinux 9"
    echo "  6) Rocky Linux 9"
    echo "  0) Cancel"
    echo ""
    
    read -p "Select template: " template_choice
    
    declare -A template_urls=(
        [1]="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
        [2]="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
        [3]="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
        [4]="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2"
        [5]="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
        [6]="https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
    )
    
    declare -A template_names=(
        [1]="ubuntu-24.04"
        [2]="ubuntu-22.04"
        [3]="debian-12"
        [4]="debian-11"
        [5]="almalinux-9"
        [6]="rocky-9"
    )
    
    if [[ -n "${template_urls[$template_choice]}" ]]; then
        local url="${template_urls[$template_choice]}"
        local name="${template_names[$template_choice]}"
        local output="/storage/templates/cloud/${name}.qcow2"
        
        echo ""
        echo "Downloading $name..."
        echo "URL: $url"
        
        mkdir -p "/storage/templates/cloud"
        wget -O "$output" "$url"
        
        if [[ $? -eq 0 ]]; then
            echo "✅ Template downloaded: $output"
        else
            echo "❌ Download failed"
        fi
    elif [[ "$template_choice" == "0" ]]; then
        echo "❌ Download cancelled"
    else
        echo "❌ Invalid choice"
    fi
    
    sleep 2
}

list_iso_images() {
    print_header
    echo -e "\033[1;32m📀 ISO Images:\033[0m"
    echo ""
    
    local iso_dir="/storage/templates/iso"
    if [[ -d "$iso_dir" ]] && ls "$iso_dir"/*.iso 2>/dev/null | grep -q .; then
        for iso in "$iso_dir"/*.iso; do
            local name=$(basename "$iso" .iso)
            local size=$(du -h "$iso" | awk '{print $1}')
            echo "  • $name ($size)"
        done
    else
        echo "No ISO images available"
        echo ""
        echo "You can download ISO images using option 4"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

download_iso_image() {
    print_header
    echo -e "\033[1;32m⬇️ Download ISO Image\033[0m"
    echo ""
    
    echo "Available ISO images for download:"
    echo "  1) Ubuntu Server 24.04 LTS"
    echo "  2) Debian 12"
    echo "  3) CentOS Stream 9"
    echo "  4) AlmaLinux 9"
    echo "  5) Rocky Linux 9"
    echo "  0) Cancel"
    echo ""
    
    read -p "Select ISO: " iso_choice
    
    declare -A iso_urls=(
        [1]="https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso"
        [2]="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso"
        [3]="https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.4-x86_64-minimal.iso"
    )
    
    declare -A iso_names=(
        [1]="ubuntu-24.04-server"
        [2]="debian-12"
        [3]="rocky-9"
    )
    
    if [[ -n "${iso_urls[$iso_choice]}" ]]; then
        local url="${iso_urls[$iso_choice]}"
        local name="${iso_names[$iso_choice]}"
        local output="/storage/templates/iso/${name}.iso"
        
        echo ""
        echo "Downloading $name..."
        echo "URL: $url"
        
        mkdir -p "/storage/templates/iso"
        wget -O "$output" "$url"
        
        if [[ $? -eq 0 ]]; then
            echo "✅ ISO downloaded: $output"
        else
            echo "❌ Download failed"
        fi
    elif [[ "$iso_choice" == "0" ]]; then
        echo "❌ Download cancelled"
    else
        echo "❌ Invalid choice"
    fi
    
    sleep 2
}

create_custom_template() {
    print_header
    echo -e "\033[1;32m🔧 Create Custom Template\033[0m"
    echo ""
    
    echo "This feature allows you to create custom VM templates."
    echo "Please use an existing VM as a base."
    echo ""
    
    read -p "Source VM name: " source_vm
    read -p "Template name: " template_name
    
    local vm_config="$DATA_DIR/vms/${source_vm}.conf"
    if [[ ! -f "$vm_config" ]]; then
        echo "❌ Source VM '$source_vm' not found"
        sleep 1
        return
    fi
    
    local disk_path=$(grep "disk_path:" "$vm_config" | awk '{print $2}')
    if [[ ! -f "$disk_path" ]]; then
        echo "❌ Disk not found for VM '$source_vm'"
        sleep 1
        return
    fi
    
    local template_path="/storage/templates/cloud/${template_name}.qcow2"
    
    echo ""
    echo "Creating template '$template_name' from VM '$source_vm'..."
    echo "Source disk: $disk_path"
    echo "Template: $template_path"
    echo ""
    
    read -p "Continue? (y/n): " confirm
    
    if [[ "$confirm" == "y" ]]; then
        # Stop VM if running
        stop_vm "$source_vm"
        
        # Copy disk
        cp "$disk_path" "$template_path"
        
        echo "✅ Template created: $template_path"
        echo ""
        echo "You can now use '$template_name' when creating new VMs"
    else
        echo "❌ Template creation cancelled"
    fi
    
    sleep 2
}

# Module menus (stubs for navigation)
kvm_qemu_menu() {
    print_header
    echo -e "\033[1;32m⚡ KVM + QEMU VM Cloud\033[0m"
    echo ""
    echo "This module provides hardware-accelerated virtualization."
    echo ""
    echo "Options:"
    echo "  1) Create KVM VM"
    echo "  2) List KVM VMs"
    echo "  3) Return to Main Menu"
    echo ""
    
    read -p "Select option: " choice
    
    case $choice in
        1) vm_create_wizard ;;
        2) list_vms ;;
        3) return ;;
        *) echo "❌ Invalid option" ;;
    esac
}

qemu_universal_menu() {
    print_header
    echo -e "\033[1;32m🖥️ QEMU VM Cloud (Universal)\033[0m"
    echo ""
    echo "This module provides software-emulated virtualization."
    echo "Works on any hardware without KVM support."
    echo ""
    echo "Options:"
    echo "  1) Create QEMU VM"
    echo "  2) List QEMU VMs"
    echo "  3) Return to Main Menu"
    echo ""
    
    read -p "Select option: " choice
    
    case $choice in
        1) vm_create_wizard ;;
        2) list_vms ;;
        3) return ;;
        *) echo "❌ Invalid option" ;;
    esac
}

lxd_cloud_menu() {
    print_header
    echo -e "\033[1;32m🧊 LXD Cloud (VMs/Containers)\033[0m"
    echo ""
    echo "This module provides LXD-based virtualization."
    echo ""
    echo "Note: LXD setup requires initialization."
    echo "Please run 'lxd init' first if not already configured."
    echo ""
    
    echo "Options:"
    echo "  1) Initialize LXD"
    echo "  2) Create LXD Instance"
    echo "  3) List LXD Instances"
    echo "  4) Return to Main Menu"
    echo ""
    
    read -p "Select option: " choice
    
    case $choice in
        1) 
            echo "Initializing LXD..."
            lxd init --auto
            ;;
        2)
            create_lxd_instance
            ;;
        3)
            list_lxd_instances
            ;;
        4) return ;;
        *) echo "❌ Invalid option" ;;
    esac
}

create_lxd_instance() {
    echo "Creating LXD Instance..."
    echo "This feature requires manual LXD configuration."
    echo "Please use 'lxc launch' command directly."
    echo "Example: lxc launch ubuntu:24.04 my-instance"
    sleep 2
}

list_lxd_instances() {
    if command -v lxc &> /dev/null; then
        lxc list
    else
        echo "LXC/LXD not installed"
    fi
    read -p "Press Enter to continue..."
}

list_vms() {
    print_header
    echo -e "\033[1;32m📋 Virtual Machines\033[0m"
    echo ""
    
    if ls "$DATA_DIR/vms"/*.conf 2>/dev/null | grep -q .; then
        for conf in "$DATA_DIR/vms"/*.conf; do
            local vm_name=$(basename "$conf" .conf)
            local status=$(grep "status:" "$conf" | awk '{print $2}' | tr -d '"')
            local node=$(grep "node_id:" "$conf" | awk '{print $2}' | tr -d '"')
            local ssh_port=$(grep "ssh_port:" "$conf" | awk '{print $2}' | tr -d '"')
            
            echo "  • $vm_name [$node] - Status: $status - SSH: $ssh_port"
        done
    else
        echo "No VMs configured"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# Main function
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
    
    # Initialize platform
    initialize_platform
    
    # Start main menu
    main_menu
}

# Start the platform
main "$@"
