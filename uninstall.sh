#!/bin/bash

# OpenVPN Admin Panel - Uninstaller
# Usage: bash uninstall.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}=====================================${NC}"
echo -e "${RED}OpenVPN Admin Panel Uninstaller${NC}"
echo -e "${RED}=====================================${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

echo -e "${YELLOW}This will remove:${NC}"
echo -e "  - OpenVPN Admin Panel (/opt/openvpn-admin)"
echo -e "  - Admin panel service (openvpn-admin.service)"
echo -e "  - Admin panel data and logs"
echo ""
echo -e "${RED}WARNING: This will NOT remove OpenVPN server or its configuration!${NC}"
echo -e "${YELLOW}To also remove OpenVPN server, run the OpenVPN uninstaller separately.${NC}"
echo ""

read -p "Are you sure you want to uninstall? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Uninstall cancelled.${NC}"
    exit 0
fi

echo -e "${BLUE}Stopping OpenVPN Admin Panel service...${NC}"
if systemctl is-active --quiet openvpn-admin; then
    systemctl stop openvpn-admin
    echo -e "${GREEN}✓ Service stopped${NC}"
fi

echo -e "${BLUE}Disabling service...${NC}"
if systemctl is-enabled --quiet openvpn-admin 2>/dev/null; then
    systemctl disable openvpn-admin
    echo -e "${GREEN}✓ Service disabled${NC}"
fi

echo -e "${BLUE}Removing service file...${NC}"
if [ -f /etc/systemd/system/openvpn-admin.service ]; then
    rm -f /etc/systemd/system/openvpn-admin.service
    systemctl daemon-reload
    echo -e "${GREEN}✓ Service file removed${NC}"
fi

echo -e "${BLUE}Removing admin panel directory...${NC}"
if [ -d /opt/openvpn-admin ]; then
    rm -rf /opt/openvpn-admin
    echo -e "${GREEN}✓ Directory removed${NC}"
fi

echo -e "${BLUE}Removing admin credentials file...${NC}"
if [ -f /root/.openvpn-admin-credentials ]; then
    rm -f /root/.openvpn-admin-credentials
    echo -e "${GREEN}✓ Credentials file removed${NC}"
fi

echo -e "${BLUE}Removing logs...${NC}"
if [ -d /var/log/openvpn-admin ]; then
    rm -rf /var/log/openvpn-admin
    echo -e "${GREEN}✓ Logs removed${NC}"
fi

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}Uninstall Complete!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${YELLOW}Note: OpenVPN server and its configuration remain installed.${NC}"
echo -e "${YELLOW}To remove OpenVPN server, you need to run the OpenVPN uninstaller.${NC}"
echo ""
