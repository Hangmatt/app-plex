# Changelog

All notable changes to this project will be documented in this file.

## [1.43.5.11029-6bf8af3f0]

### ✨ New Features

- **Startup update check**: Automatically check for and install newer Plex Media Server releases when the add-on boots or restarts (`/etc/s6-overlay/scripts/update-check.sh`).
- **Channel configuration**: Added `channel` option with support for `public`, `beta` (requires active Plex Pass claim token), or `disabled`.
- **Integrity verification**: Downloads packages from official Plex distribution endpoints and verifies SHA-1 checksums before applying updates via `dpkg`.
- **Home Assistant update automation**: Documented workflow to trigger automated updates using Home Assistant's native `update.plex_server_update` entity.

### ⬆️ Dependency & Base System Updates

- Update base image to `ghcr.io/hassio-addons/debian-base:9.5.1`.
- Update Plex Media Server base image version to `1.43.5.11029-6bf8af3f0`.
- Update `uuid-runtime` package to `2.41.5-0+deb13u1`.
