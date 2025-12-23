#!/bin/bash

# OpenVPN Admin Panel - One-Line Installer
# Usage: curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/install_repository.sh | bash

set -e

REPO_URL="https://github.com/amirhkfar/open_vpn_admin.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}OpenVPN Admin Panel Installer${NC}"
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

# Check if OpenVPN is installed
if ! command -v openvpn &> /dev/null; then
    echo -e "${YELLOW}OpenVPN not found. Please install OpenVPN server first.${NC}"
    echo -e "${YELLOW}You can use: https://git.io/vpn${NC}"
    exit 1
fi

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"

if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    apt-get update
    apt-get install -y python3 python3-pip python3-venv git
elif [[ "$OS" == "centos" ]] || [[ "$OS" == "fedora" ]]; then
    yum install -y python3 python3-pip git
fi

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

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${YELLOW}Admin Panel URL:${NC} http://$SERVER_IP:5000"
echo -e "${YELLOW}Username:${NC} admin"
echo -e "${YELLOW}Password:${NC} $ADMIN_PASSWORD"
echo ""
echo -e "${RED}IMPORTANT: Save these credentials!${NC}"
echo ""
echo -e "${YELLOW}To change password, edit:${NC} $INSTALL_DIR/.env"
echo -e "${YELLOW}To check for updates:${NC} sudo $INSTALL_DIR/update.sh"
echo -e "${YELLOW}Service commands:${NC}"
echo "  systemctl status openvpn-admin"
echo "  systemctl restart openvpn-admin"
echo "  systemctl stop openvpn-admin"
echo ""
echo -e "${GREEN}=====================================${NC}"
