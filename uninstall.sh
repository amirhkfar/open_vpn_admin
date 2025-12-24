#!/bin/bash

# OpenVPN Complete Uninstaller
# Removes both Admin Panel and OpenVPN Server
# Usage: bash uninstall.sh [--panel-only]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}=====================================${NC}"
echo -e "${RED}OpenVPN Complete Uninstaller${NC}"
echo -e "${RED}=====================================${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

PANEL_ONLY=false
if [[ "$1" == "--panel-only" ]]; then
    PANEL_ONLY=true
fi

if [ "$PANEL_ONLY" = true ]; then
    echo -e "${YELLOW}This will remove:${NC}"
    echo -e "  - OpenVPN Admin Panel only"
    echo ""
    echo -e "${GREEN}OpenVPN server and client configs will be preserved.${NC}"
else
    echo -e "${YELLOW}This will remove:${NC}"
    echo -e "  - OpenVPN Admin Panel (/opt/openvpn-admin)"
    echo -e "  - OpenVPN Server (/etc/openvpn)"
    echo -e "  - All client configurations"
    echo -e "  - All certificates and keys"
    echo -e "  - Firewall rules"
    echo ""
    echo -e "${RED}WARNING: This is a COMPLETE removal!${NC}"
    echo -e "${RED}All VPN clients will stop working!${NC}"
fi
echo ""

read -r -p "Are you sure you want to uninstall? (yes/no): " REPLY
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Uninstall cancelled.${NC}"
    exit 0
fi

# Uninstall Admin Panel
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

# Uninstall OpenVPN Server if not panel-only
if [ "$PANEL_ONLY" = false ]; then
    echo ""
    echo -e "${BLUE}Stopping OpenVPN server...${NC}"
    if systemctl is-active --quiet openvpn@server; then
        systemctl stop openvpn@server
        echo -e "${GREEN}✓ OpenVPN server stopped${NC}"
    fi
    
    echo -e "${BLUE}Disabling OpenVPN server...${NC}"
    if systemctl is-enabled --quiet openvpn@server 2>/dev/null; then
        systemctl disable openvpn@server
        echo -e "${GREEN}✓ OpenVPN server disabled${NC}"
    fi
    
    echo -e "${BLUE}Removing OpenVPN configuration and certificates...${NC}"
    if [ -d /etc/openvpn ]; then
        rm -rf /etc/openvpn
        echo -e "${GREEN}✓ OpenVPN directory removed${NC}"
    fi
    
    echo -e "${BLUE}Removing OpenVPN logs...${NC}"
    rm -f /var/log/openvpn*.log
    echo -e "${GREEN}✓ Logs removed${NC}"
    
    echo -e "${BLUE}Removing firewall rules...${NC}"
    # Remove iptables rules
    IFACE=$(ip route | grep default | awk '{print $5}' 2>/dev/null || echo "eth0")
    iptables -t nat -D POSTROUTING -s 10.8.0.0/24 -o $IFACE -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i tun0 -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -o tun0 -j ACCEPT 2>/dev/null || true
    echo -e "${GREEN}✓ Firewall rules removed${NC}"
fi

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}Uninstall Complete!${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

if [ "$PANEL_ONLY" = true ]; then
    echo -e "${GREEN}Admin panel removed. OpenVPN server still running.${NC}"
else
    echo -e "${GREEN}OpenVPN server and admin panel completely removed.${NC}"
fi
echo ""
