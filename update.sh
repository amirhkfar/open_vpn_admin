#!/bin/bash

# OpenVPN Admin Panel Update Script
# This script checks for updates and automatically updates the installation

set -e

INSTALL_DIR="/opt/openvpn-admin"
REPO_URL="https://github.com/amirhkfar/open_vpn_admin.git"
BACKUP_DIR="/opt/openvpn-admin-backup-$(date +%Y%m%d_%H%M%S)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  OpenVPN Admin Panel Update Checker  ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}✗ This script must be run as root${NC}"
   exit 1
fi

# Check if installation exists
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}✗ Installation not found at $INSTALL_DIR${NC}"
    exit 1
fi

cd "$INSTALL_DIR"

# Get current version
if [ -f "VERSION" ]; then
    CURRENT_VERSION=$(cat VERSION)
else
    CURRENT_VERSION="1.0.0"
    echo "1.0.0" > VERSION
fi

echo -e "${BLUE}→${NC} Current version: ${GREEN}$CURRENT_VERSION${NC}"

# Fetch latest version from GitHub
echo -e "${BLUE}→${NC} Checking for updates..."

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Clone repository to check version
git clone --depth 1 --quiet "$REPO_URL" repo 2>/dev/null || {
    echo -e "${RED}✗ Failed to connect to repository${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
}

cd repo

if [ -f "VERSION" ]; then
    LATEST_VERSION=$(cat VERSION)
else
    echo -e "${YELLOW}⚠ No VERSION file found in repository${NC}"
    LATEST_VERSION=$CURRENT_VERSION
fi

echo -e "${BLUE}→${NC} Latest version: ${GREEN}$LATEST_VERSION${NC}"
echo ""

# Compare versions
if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo -e "${GREEN}✓ You are running the latest version!${NC}"
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Version comparison function
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

if version_gt "$LATEST_VERSION" "$CURRENT_VERSION"; then
    echo -e "${YELLOW}╔════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║      New Version Available!           ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}→${NC} Update from ${RED}$CURRENT_VERSION${NC} to ${GREEN}$LATEST_VERSION${NC}"
    echo ""
    
    read -p "Do you want to update now? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}⚠ Update cancelled${NC}"
        rm -rf "$TEMP_DIR"
        exit 0
    fi
    
    echo ""
    echo -e "${BLUE}→${NC} Starting update process..."
    
    # Create backup
    echo -e "${BLUE}→${NC} Creating backup at $BACKUP_DIR..."
    cp -r "$INSTALL_DIR" "$BACKUP_DIR"
    
    # Backup .env file
    if [ -f "$INSTALL_DIR/.env" ]; then
        cp "$INSTALL_DIR/.env" "$TEMP_DIR/backup.env"
    fi
    
    # Backup client stats
    if [ -f "$INSTALL_DIR/client_stats.json" ]; then
        cp "$INSTALL_DIR/client_stats.json" "$TEMP_DIR/client_stats.json"
    fi
    
    # Stop service
    echo -e "${BLUE}→${NC} Stopping service..."
    systemctl stop openvpn-admin
    
    # Update files
    echo -e "${BLUE}→${NC} Updating files..."
    cd "$TEMP_DIR/repo"
    
    # Copy new files
    cp -r templates "$INSTALL_DIR/"
    cp app.py "$INSTALL_DIR/"
    cp requirements.txt "$INSTALL_DIR/"
    cp VERSION "$INSTALL_DIR/"
    cp update.sh "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/update.sh"
    
    # Restore .env
    if [ -f "$TEMP_DIR/backup.env" ]; then
        cp "$TEMP_DIR/backup.env" "$INSTALL_DIR/.env"
    fi
    
    # Restore client stats
    if [ -f "$TEMP_DIR/client_stats.json" ]; then
        cp "$TEMP_DIR/client_stats.json" "$INSTALL_DIR/client_stats.json"
    fi
    
    # Update dependencies
    echo -e "${BLUE}→${NC} Updating dependencies..."
    cd "$INSTALL_DIR"
    source venv/bin/activate
    pip install -q --upgrade pip
    pip install -q -r requirements.txt
    
    # Start service
    echo -e "${BLUE}→${NC} Starting service..."
    systemctl start openvpn-admin
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Update Completed Successfully!    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo -e "${GREEN}✓${NC} Updated from ${RED}$CURRENT_VERSION${NC} to ${GREEN}$LATEST_VERSION${NC}"
    echo -e "${BLUE}→${NC} Backup saved at: $BACKUP_DIR"
    echo -e "${BLUE}→${NC} Service status:"
    systemctl status openvpn-admin --no-pager | grep Active
    echo ""
    
else
    echo -e "${YELLOW}⚠ You are running a newer version than the repository${NC}"
    rm -rf "$TEMP_DIR"
fi
