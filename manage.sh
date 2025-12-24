#!/bin/bash

# OpenVPN Admin Panel - Management Menu
# Usage: bash manage.sh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# Check if stdin is a terminal (not piped from curl)
if [ ! -t 0 ]; then
    echo -e "${YELLOW}Detected non-interactive mode (piped from curl).${NC}"
    echo -e "${YELLOW}Downloading script for interactive use...${NC}"
    TEMP_SCRIPT="/tmp/openvpn-manage-$$.sh"
    curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/manage.sh -o "$TEMP_SCRIPT"
    chmod +x "$TEMP_SCRIPT"
    echo -e "${GREEN}Starting interactive menu...${NC}"
    exec bash "$TEMP_SCRIPT" "$@"
    exit 0
fi

show_menu() {
    clear
    echo -e "${CYAN}=====================================${NC}"
    echo -e "${CYAN}   OpenVPN Admin Panel Manager${NC}"
    echo -e "${CYAN}=====================================${NC}"
    echo ""
    echo -e "${GREEN}1)${NC} Install OpenVPN Admin Panel"
    echo -e "${GREEN}2)${NC} Update OpenVPN Admin Panel"
    echo -e "${GREEN}3)${NC} Uninstall OpenVPN Admin Panel"
    echo -e "${GREEN}4)${NC} Restart Admin Panel Service"
    echo -e "${GREEN}5)${NC} View Admin Panel Status"
    echo -e "${GREEN}6)${NC} View Admin Panel Logs"
    echo -e "${GREEN}7)${NC} Show Admin Credentials"
    echo -e "${GREEN}8)${NC} Reinstall (Uninstall + Install)"
    echo -e "${RED}9)${NC} Exit"
    echo ""
    echo -e "${CYAN}=====================================${NC}"
}

check_installation() {
    if [ -f /etc/systemd/system/openvpn-admin.service ] && [ -d /opt/openvpn-admin ]; then
        return 0
    else
        return 1
    fi
}

show_credentials() {
    echo -e "${BLUE}Retrieving admin credentials...${NC}"
    if [ -f /root/.openvpn-admin-credentials ]; then
        cat /root/.openvpn-admin-credentials
    else
        echo -e "${RED}Credentials file not found!${NC}"
        echo -e "${YELLOW}You may need to reinstall the admin panel.${NC}"
    fi
}

show_status() {
    echo -e "${BLUE}OpenVPN Admin Panel Status:${NC}"
    systemctl status openvpn-admin --no-pager
    echo ""
    echo -e "${BLUE}OpenVPN Server Status:${NC}"
    systemctl status openvpn-server@server --no-pager || echo -e "${YELLOW}OpenVPN server not found${NC}"
}

show_logs() {
    echo -e "${BLUE}Admin Panel Logs (last 50 lines):${NC}"
    journalctl -u openvpn-admin -n 50 --no-pager
}

restart_service() {
    echo -e "${BLUE}Restarting OpenVPN Admin Panel...${NC}"
    systemctl restart openvpn-admin
    sleep 2
    if systemctl is-active --quiet openvpn-admin; then
        echo -e "${GREEN}✓ Service restarted successfully${NC}"
    else
        echo -e "${RED}✗ Service failed to restart${NC}"
        echo -e "${YELLOW}Check logs with option 6${NC}"
    fi
}

install_panel() {
    echo -e "${BLUE}Starting installation...${NC}"
    if [ -f "$SCRIPT_DIR/install_repository.sh" ]; then
        bash "$SCRIPT_DIR/install_repository.sh"
    else
        echo -e "${YELLOW}Downloading installer...${NC}"
        curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/install_repository.sh | bash
    fi
}

update_panel() {
    echo -e "${BLUE}Updating OpenVPN Admin Panel...${NC}"
    
    if ! check_installation; then
        echo -e "${RED}Admin panel is not installed!${NC}"
        echo -e "${YELLOW}Please install it first using option 1.${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Stopping service...${NC}"
    systemctl stop openvpn-admin
    
    echo -e "${BLUE}Backing up current installation...${NC}"
    BACKUP_DIR="/opt/openvpn-admin-backup-$(date +%Y%m%d-%H%M%S)"
    cp -r /opt/openvpn-admin "$BACKUP_DIR"
    echo -e "${GREEN}✓ Backup saved to: $BACKUP_DIR${NC}"
    
    echo -e "${BLUE}Pulling latest changes...${NC}"
    cd /opt/openvpn-admin
    git fetch origin
    git reset --hard origin/main
    
    echo -e "${BLUE}Installing/updating dependencies...${NC}"
    source venv/bin/activate
    pip install -r requirements.txt --upgrade
    deactivate
    
    echo -e "${BLUE}Restarting service...${NC}"
    systemctl start openvpn-admin
    
    echo -e "${GREEN}✓ Update complete!${NC}"
    echo -e "${YELLOW}Backup location: $BACKUP_DIR${NC}"
}

uninstall_panel() {
    if [ -f "$SCRIPT_DIR/uninstall.sh" ]; then
        bash "$SCRIPT_DIR/uninstall.sh"
    else
        echo -e "${YELLOW}Downloading uninstaller...${NC}"
        curl -sL https://raw.githubusercontent.com/amirhkfar/open_vpn_admin/main/uninstall.sh | bash
    fi
}

reinstall_panel() {
    echo -e "${YELLOW}This will completely remove and reinstall the admin panel.${NC}"
    read -r -p "Continue? (yes/no): " REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${YELLOW}Reinstall cancelled.${NC}"
        return
    fi
    
    uninstall_panel
    echo ""
    echo -e "${BLUE}Waiting 3 seconds before reinstall...${NC}"
    sleep 3
    install_panel
}

# Main loop
while true; do
    show_menu
    read -r -p "Please select an option [1-9]: " choice
    echo ""
    
    case $choice in
        1)
            install_panel
            ;;
        2)
            update_panel
            ;;
        3)
            uninstall_panel
            ;;
        4)
            restart_service
            ;;
        5)
            show_status
            ;;
        6)
            show_logs
            ;;
        7)
            show_credentials
            ;;
        8)
            reinstall_panel
            ;;
        9)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please try again.${NC}"
            ;;
    esac
    
    echo ""
    read -r -p "Press Enter to continue..."
done
