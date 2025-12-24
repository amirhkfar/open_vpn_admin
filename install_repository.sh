#!/bin/bash

# OpenVPN Admin Panel - Complete Automated Installer
# Installs both OpenVPN server and Admin Panel
# Usage: curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/install_repository.sh | bash

set -e

REPO_URL="https://github.com/amirhkfar/open_vpn_admin.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}OpenVPN Complete Setup Installer${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# Detect OS
if [[ -e /etc/debian_version ]]; then
    OS="debian"
    if [[ "$(lsb_release -si)" == "Ubuntu" ]]; then
        OS="ubuntu"
    fi
elif [[ -e /etc/centos-release ]]; then
    OS="centos"
elif [[ -e /etc/fedora-release ]]; then
    OS="fedora"
else
    echo -e "${RED}Unsupported OS${NC}"
    exit 1
fi

echo -e "${YELLOW}Detected OS: $OS${NC}"

# Get configuration from environment variables or use defaults
OVPN_PORT="${OVPN_PORT:-1194}"
OVPN_PROTOCOL="${OVPN_PROTOCOL:-udp}"
OVPN_DNS="${OVPN_DNS:-1.1.1.1}"

echo -e "${YELLOW}OpenVPN Configuration:${NC}"
echo "  Port: $OVPN_PORT"
echo "  Protocol: $OVPN_PROTOCOL"
echo "  DNS: $OVPN_DNS"
echo ""

# Install OpenVPN and dependencies
echo -e "${YELLOW}Installing OpenVPN and dependencies...${NC}"

if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt-get update
    apt-get install -y openvpn easy-rsa python3 python3-pip python3-venv git iptables openssl
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "fedora" ]]; then
    yum install -y epel-release
    yum install -y openvpn easy-rsa python3 python3-pip git iptables openssl
fi

# Setup Easy-RSA and generate certificates
echo -e "${YELLOW}Setting up PKI and generating certificates...${NC}"

# Remove old PKI if exists
rm -rf /etc/openvpn/easy-rsa
mkdir -p /etc/openvpn/easy-rsa

# Copy Easy-RSA
if [ -d "/usr/share/easy-rsa" ]; then
    cp -r /usr/share/easy-rsa/* /etc/openvpn/easy-rsa/
else
    # Download Easy-RSA if not found
    cd /tmp
    wget -O EasyRSA.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.7/EasyRSA-3.1.7.tgz
    tar xzf EasyRSA.tgz
    cp -r EasyRSA-3.1.7/* /etc/openvpn/easy-rsa/
    rm -rf EasyRSA-3.1.7 EasyRSA.tgz
fi

cd /etc/openvpn/easy-rsa

# Initialize PKI
./easyrsa init-pki

# Build CA (non-interactive)
echo "OpenVPN-CA" | ./easyrsa build-ca nopass

# Generate server certificate and key
./easyrsa gen-req server nopass
EASYRSA_BATCH=1 ./easyrsa sign-req server server

# Generate DH parameters
./easyrsa gen-dh

# Generate TLS-auth key
openvpn --genkey secret /etc/openvpn/easy-rsa/pki/ta.key

# Generate CRL
./easyrsa gen-crl

# Copy certificates to OpenVPN directory
cp /etc/openvpn/easy-rsa/pki/ca.crt /etc/openvpn/
cp /etc/openvpn/easy-rsa/pki/issued/server.crt /etc/openvpn/
cp /etc/openvpn/easy-rsa/pki/private/server.key /etc/openvpn/
cp /etc/openvpn/easy-rsa/pki/dh.pem /etc/openvpn/
cp /etc/openvpn/easy-rsa/pki/ta.key /etc/openvpn/
cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/

# Set proper permissions
chmod 600 /etc/openvpn/server.key
chmod 600 /etc/openvpn/ta.key

# Get server IP
SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)

# Create OpenVPN server configuration
echo -e "${YELLOW}Creating OpenVPN server configuration...${NC}"

cat > /etc/openvpn/server.conf <<EOF
port $OVPN_PORT
proto $OVPN_PROTOCOL
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS $OVPN_DNS"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
cipher AES-256-GCM
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn-status.log
log-append /var/log/openvpn.log
verb 3
crl-verify crl.pem
EOF

# Enable IP forwarding
echo -e "${YELLOW}Enabling IP forwarding...${NC}"
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# Configure iptables
echo -e "${YELLOW}Configuring firewall rules...${NC}"
IFACE=$(ip route | grep default | awk '{print $5}')

iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $IFACE -j MASQUERADE
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -o tun0 -j ACCEPT

# Save iptables rules
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
elif [ -f /etc/iptables/rules.v4 ]; then
    iptables-save > /etc/iptables/rules.v4
else
    iptables-save > /etc/iptables.rules
    echo '#!/bin/sh' > /etc/network/if-pre-up.d/iptables
    echo 'iptables-restore < /etc/iptables.rules' >> /etc/network/if-pre-up.d/iptables
    chmod +x /etc/network/if-pre-up.d/iptables
fi

# Start and enable OpenVPN service
echo -e "${YELLOW}Starting OpenVPN server...${NC}"
systemctl enable openvpn@server
systemctl start openvpn@server

# Configure firewall for OpenVPN port
if command -v ufw &> /dev/null; then
    ufw allow $OVPN_PORT/$OVPN_PROTOCOL
    ufw allow 5000/tcp
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=$OVPN_PORT/$OVPN_PROTOCOL
    firewall-cmd --permanent --add-port=5000/tcp
    firewall-cmd --reload
fi

echo -e "${GREEN}OpenVPN server installed and started!${NC}"
echo ""

# Now install Admin Panel
echo -e "${YELLOW}=====================================${NC}"
echo -e "${YELLOW}Installing Admin Panel...${NC}"
echo -e "${YELLOW}=====================================${NC}"
echo ""

# Create installation directory
INSTALL_DIR="/opt/openvpn-admin"
echo -e "${YELLOW}Creating installation directory: $INSTALL_DIR${NC}"
mkdir -p $INSTALL_DIR

# Download or clone repository
echo -e "${YELLOW}Downloading OpenVPN Admin Panel...${NC}"

# Clone from GitHub
rm -rf $INSTALL_DIR
git clone $REPO_URL $INSTALL_DIR

cd $INSTALL_DIR

# Create virtual environment
echo -e "${YELLOW}Creating Python virtual environment...${NC}"
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
echo -e "${YELLOW}Installing Python packages...${NC}"
pip install --upgrade pip
pip install -r requirements.txt

# Generate random admin password
ADMIN_PASSWORD=$(openssl rand -base64 16)

# Create .env file
echo -e "${YELLOW}Creating configuration file...${NC}"
cat > .env <<EOF
ADMIN_USERNAME=admin
ADMIN_PASSWORD=$ADMIN_PASSWORD
SECRET_KEY=$(openssl rand -hex 32)
EOF

chmod 600 .env

# Create systemd service
echo -e "${YELLOW}Creating systemd service...${NC}"
cat > /etc/systemd/system/openvpn-admin.service <<EOF
[Unit]
Description=OpenVPN Admin Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start service
systemctl daemon-reload
systemctl enable openvpn-admin
systemctl start openvpn-admin

# Configure firewall
echo -e "${YELLOW}Configuring firewall...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 5000/tcp
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=5000/tcp
    firewall-cmd --reload
fi

# Get server IP
SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)

# Make update script executable
chmod +x $INSTALL_DIR/update.sh

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${GREEN}OpenVPN Server Status:${NC}"
systemctl status openvpn@server --no-pager | head -5
echo ""
echo -e "${YELLOW}Admin Panel URL:${NC} http://$SERVER_IP:5000"
echo -e "${YELLOW}Username:${NC} admin"
echo -e "${YELLOW}Password:${NC} $ADMIN_PASSWORD"
echo ""
echo -e "${YELLOW}OpenVPN Server:${NC}"
echo "  Port: $OVPN_PORT"
echo "  Protocol: $OVPN_PROTOCOL"
echo "  Network: 10.8.0.0/24"
echo ""
echo -e "${RED}IMPORTANT: Save these credentials!${NC}"
echo ""
echo -e "${YELLOW}Credentials saved to:${NC} /root/.openvpn-admin-credentials"
echo -e "${YELLOW}Service commands:${NC}"
echo "  systemctl status openvpn@server      # Check OpenVPN status"
echo "  systemctl status openvpn-admin       # Check Admin Panel status"
echo "  systemctl restart openvpn@server     # Restart OpenVPN"
echo "  systemctl restart openvpn-admin      # Restart Admin Panel"
echo ""
echo -e "${GREEN}=====================================${NC}"

# Save credentials to file
cat > /root/.openvpn-admin-credentials <<EOF
Admin Panel URL: http://$SERVER_IP:5000
Username: admin
Password: $ADMIN_PASSWORD

OpenVPN Server:
Port: $OVPN_PORT
Protocol: $OVPN_PROTOCOL
Network: 10.8.0.0/24
EOF

chmod 600 /root/.openvpn-admin-credentials
