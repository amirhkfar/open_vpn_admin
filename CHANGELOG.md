# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-12-23

### Added
- 🎨 Modern UI redesign with 3x-ui inspired design
- 🔄 Cumulative bandwidth tracking (total usage per client)
- 📊 Session vs Total bandwidth columns
- 🎨 Softer color palette with light sidebar
- 📱 Responsive sidebar navigation
- 🔄 Automatic update system with version checking
- 📝 Version display in sidebar
- 💾 Persistent bandwidth statistics across sessions
- 📈 Total bandwidth summary row in clients table
- ⚙️ Server IP, port, and protocol auto-detection

### Changed
- 🎨 Sidebar color from dark (#1e293b) to light (#f8fafc)
- 🎨 Gradient purple theme to solid indigo (#6366f1)
- 📏 Reduced sidebar width from 250px to 240px
- 🔤 Smaller button sizes and fonts for natural look
- 📊 Separated dashboard and clients into distinct pages
- 🔐 Session-based authentication (24-hour sessions)

### Fixed
- 🐛 Action dropdown menu hiding inside table container
- 🐛 Empty dashboard statistics
- 🐛 Client data persistence when disconnected
- 🐛 Undefined value errors in templates
- 🐛 Bandwidth not showing in human-readable format
- 🐛 Multi-connection detection from .ovpn files
- 🐛 Expiry date field mapping

## [1.0.0] - Initial Release

### Added
- ✨ Basic OpenVPN client management
- ➕ Add new clients with custom expiry dates
- 🚫 Revoke client certificates
- 📥 Download .ovpn configuration files
- 📋 Export configs as base64
- 🟢 Real-time connection monitoring
- 📊 Basic dashboard with statistics
- 🔐 HTTP Basic Authentication
- 🎨 Bootstrap-based UI

[2.0.0]: https://github.com/amirhkfar/open_vpn_admin/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/amirhkfar/open_vpn_admin/releases/tag/v1.0.0
