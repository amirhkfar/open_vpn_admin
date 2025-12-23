#!/bin/bash
#
# OpenVPN Admin Panel - Installation Script
# Compatible with Ubuntu, Debian, CentOS, AlmaLinux, Rocky Linux, and Fedora
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/openvpn-admin"
SERVICE_NAME="openvpn-admin"
VENV_DIR="$INSTALL_DIR/venv"

# Detect OS
if grep -qs "ubuntu" /etc/os-release; then
    os="ubuntu"
elif [[ -e /etc/debian_version ]]; then
    os="debian"
elif [[ -e /etc/almalinux-release || -e /etc/rocky-release || -e /etc/centos-release ]]; then
    os="centos"
elif [[ -e /etc/fedora-release ]]; then
    os="fedora"
else
    echo -e "${RED}Error: Unsupported distribution${NC}"
    echo "Supported: Ubuntu, Debian, AlmaLinux, Rocky Linux, CentOS, Fedora"
    exit 1
fi

# Check if running as root
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Check if OpenVPN is installed
if [[ ! -e /etc/openvpn/server/server.conf ]]; then
    echo -e "${RED}Error: OpenVPN server not found${NC}"
    echo "Please install OpenVPN first using:"
    echo "curl -O https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh"
    echo "bash openvpn-install.sh"
    exit 1
fi

echo -e "${GREEN}===================================================${NC}"
echo -e "${GREEN}  OpenVPN Admin Panel - Installation${NC}"
echo -e "${GREEN}===================================================${NC}"
echo ""

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
if [[ "$os" = "ubuntu" || "$os" = "debian" ]]; then
    apt-get update
    apt-get install -y python3 python3-pip python3-venv
elif [[ "$os" = "centos" || "$os" = "fedora" ]]; then
    dnf install -y python3 python3-pip
fi

# Create installation directory
echo -e "${YELLOW}Creating installation directory...${NC}"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Copy application files
echo -e "${YELLOW}Copying application files...${NC}"
if [[ -f "$(dirname "$0")/app.py" ]]; then
    cp "$(dirname "$0")/app.py" "$INSTALL_DIR/"
    cp "$(dirname "$0")/requirements.txt" "$INSTALL_DIR/"
    cp -r "$(dirname "$0")/templates" "$INSTALL_DIR/"
else
    echo -e "${RED}Error: Application files not found${NC}"
    echo "Please run this script from the openvpn-admin directory"
    exit 1
fi

# Create Python virtual environment
echo -e "${YELLOW}Creating Python virtual environment...${NC}"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# Install Python dependencies
echo -e "${YELLOW}Installing Python dependencies...${NC}"
pip install --upgrade pip
pip install -r "$INSTALL_DIR/requirements.txt"

# Create .env file if it doesn't exist
if [[ ! -f "$INSTALL_DIR/.env" ]]; then
    echo -e "${YELLOW}Creating configuration file...${NC}"
    
    # Generate random admin password
    ADMIN_PASS=$(openssl rand -base64 16)
    
    cat > "$INSTALL_DIR/.env" <<EOF
# Admin credentials
ADMIN_USER=admin
ADMIN_PASS=$ADMIN_PASS

# Flask configuration
FLASK_HOST=0.0.0.0
FLASK_PORT=5000
EOF
    
    echo -e "${GREEN}Admin credentials created:${NC}"
    echo "Username: admin"
    echo "Password: $ADMIN_PASS"
    echo ""
    echo -e "${YELLOW}Please save these credentials!${NC}"
    echo ""
fi

# Enable OpenVPN status logging
echo -e "${YELLOW}Configuring OpenVPN status logging...${NC}"
if ! grep -q "status /var/log/openvpn/status.log" /etc/openvpn/server/server.conf; then
    echo "status /var/log/openvpn/status.log" >> /etc/openvpn/server/server.conf
    mkdir -p /var/log/openvpn
    systemctl restart openvpn-server@server || true
fi

# Create systemd service
echo -e "${YELLOW}Creating systemd service...${NC}"
cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=OpenVPN Admin Panel
After=network.target openvpn-server@server.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$VENV_DIR/bin"
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

# Configure firewall
echo -e "${YELLOW}Configuring firewall...${NC}"
if systemctl is-active --quiet firewalld.service; then
    firewall-cmd --permanent --add-port=5000/tcp
    firewall-cmd --reload
elif command -v ufw &> /dev/null; then
    ufw allow 5000/tcp
fi

# Check service status
sleep 2
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo ""
    echo -e "${GREEN}===================================================${NC}"
    echo -e "${GREEN}  Installation completed successfully!${NC}"
    echo -e "${GREEN}===================================================${NC}"
    echo ""
    echo "OpenVPN Admin Panel is running!"
    echo ""
    echo "Access the panel at: http://$(hostname -I | awk '{print $1}'):5000"
    echo ""
    echo "Admin credentials:"
    echo "  Username: admin"
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        echo "  Password: $(grep ADMIN_PASS "$INSTALL_DIR/.env" | cut -d'=' -f2)"
    fi
    echo ""
    echo "Useful commands:"
    echo "  Check status:  systemctl status $SERVICE_NAME"
    echo "  View logs:     journalctl -u $SERVICE_NAME -f"
    echo "  Restart:       systemctl restart $SERVICE_NAME"
    echo "  Stop:          systemctl stop $SERVICE_NAME"
    echo ""
    echo "To change admin password, edit: $INSTALL_DIR/.env"
    echo "Then restart the service: systemctl restart $SERVICE_NAME"
    echo ""
else
    echo -e "${RED}Error: Service failed to start${NC}"
    echo "Check logs with: journalctl -u $SERVICE_NAME -n 50"
    exit 1
fi
