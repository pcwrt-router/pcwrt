# pcWRT UI - a user friendly frontend for OpenWrt
## Build steps
1. Run setup.py -s
2. cd openwrt
3. make menuconfig. Select LuCI module luci-mod-pcwrt
4. make V=s

\* Package dependencies are not fully sorted out yet, so please consult the example config files to build a new target.

## Screenshots
* Settings Page
![Settings](screenshots/Settings.png?raw=true "Router Settings")
* VLAN Configuration
![VLAN](screenshots/VLAN.png?raw=true "VLAN Configuration")
* Add an SSID
![Wireless Settings](screenshots/Wireless.png?raw=true "Wireless Configuration")
* OpenVPN Configuration
![OpenVPN](screenshots/OpenVPN.png?raw=true "OpenVPN Configuration")
* WireGuard Configuration
![WireGuard VPN](screenshots/WireGuardVPN.png?raw=true "WireGuard VPN Configuration")
