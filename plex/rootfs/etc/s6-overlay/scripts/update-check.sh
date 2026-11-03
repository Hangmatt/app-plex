#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Community App: Plex Media Server
# Checks for and installs updates for Plex Media Server
# ==============================================================================
readonly prefs="/data/Plex Media Server/Preferences.xml"

# Determine update channel (default: public)
channel="public"
if bashio::config.has_value "channel"; then
    channel=$(bashio::config 'channel')
fi

# Exit if update check is disabled
if [[ "${channel}" = "disabled" ]]; then
    bashio::log.debug "Plex update check is disabled."
    exit 0
fi

# Determine channel ID (16 = Public, 8 = Beta / Plex Pass)
channel_id=16
token=""
if bashio::fs.file_exists "${prefs}"; then
    token="$(xmlstarlet sel -T -t -m "/Preferences" -v "@PlexOnlineToken" -n "${prefs}" 2>/dev/null || true)"
fi

if [[ "${channel,,}" = "beta" ]]; then
    if [[ -z "${token}" ]]; then
        bashio::log.warning "Beta update channel requires a Plex token, but none was found."
        bashio::log.warning "Falling back to the public update channel."
    else
        channel_id=8
    fi
fi

# Detect system architecture
arch=$(dpkg --print-architecture 2>/dev/null || echo "")
if [[ -z "${arch}" ]] && declare -F bashio::info.arch >/dev/null 2>&1; then
    arch=$(bashio::info.arch)
fi

case "${arch}" in
    amd64|x86_64)
        plex_build="linux-x86_64"
        ;;
    aarch64|arm64)
        plex_build="linux-aarch64"
        ;;
    *)
        bashio::log.warning "Plex update check is not supported on architecture: ${arch}."
        exit 0
        ;;
esac

# Determine currently installed version
if dpkg --get-selections plexmediaserver 2>/dev/null | grep -wq "install"; then
    installed_version=$(dpkg-query -W -f='${Version}' plexmediaserver 2>/dev/null || echo "none")
else
    installed_version="none"
fi

# Build Plex API query parameters
declare -a query=(
    --data-urlencode "build=${plex_build}"
    --data-urlencode "channel=${channel_id}"
    --data-urlencode "distro=debian"
)

if [[ -n "${token}" && "${channel_id}" -eq 8 ]]; then
    query+=(--data-urlencode "X-Plex-Token=${token}")
fi

bashio::log.debug "Checking Plex API for updates (${channel} channel, ${plex_build})..."
if ! response=$(curl --silent --show-error --fail -G "${query[@]}" "https://api.plex.tv/downloads/details/5"); then
    bashio::log.warning "Unable to check for Plex updates: could not reach Plex API."
    exit 0
fi

# Extract version and download details from XML
remote_version=""
remote_url=""
remote_file=""
remote_hash=""

if command -v xmlstarlet >/dev/null 2>&1; then
    remote_version=$(xmlstarlet sel -t -v "/MediaContainer/Release/@version" <<< "${response}" 2>/dev/null || true)
    remote_url=$(xmlstarlet sel -t -v "/MediaContainer/Release/Package/@url" <<< "${response}" 2>/dev/null || true)
    remote_file=$(xmlstarlet sel -t -v "/MediaContainer/Release/Package/@file" <<< "${response}" 2>/dev/null || true)
    remote_hash=$(xmlstarlet sel -t -v "/MediaContainer/Release/Package/@fileHash" <<< "${response}" 2>/dev/null || true)
fi

if [[ -z "${remote_version}" ]]; then
    remote_version=$(echo "${response}" | sed -n 's/.*Release.*version="\([^"]*\)".*/\1/p' | head -n 1)
fi
if [[ -z "${remote_url}" ]]; then
    remote_url=$(echo "${response}" | sed -n 's/.*Package.*url="\([^"]*\)".*/\1/p' | head -n 1)
fi
if [[ -z "${remote_file}" ]]; then
    remote_file=$(echo "${response}" | sed -n 's/.*Package.*file="\([^"]*\)".*/\1/p' | head -n 1)
fi
if [[ -z "${remote_hash}" ]]; then
    remote_hash=$(echo "${response}" | sed -n 's/.*Package.*fileHash="\([^"]*\)".*/\1/p' | head -n 1)
fi

if [[ -z "${remote_url}" && -n "${remote_file}" ]]; then
    remote_url="https://api.plex.tv${remote_file}"
fi

if [[ -z "${remote_version}" || -z "${remote_url}" ]]; then
    bashio::log.warning "Could not parse update details from Plex API response."
    exit 0
fi

# Compare installed version with available version
if [[ "${installed_version}" != "none" ]] && ! dpkg --compare-versions "${remote_version}" gt "${installed_version}"; then
    bashio::log.info "Plex Media Server is up to date (${installed_version})."
    exit 0
fi

bashio::log.info "New Plex Media Server version available: ${remote_version} (current: ${installed_version})."

# Download package to temporary file
deb_file=$(mktemp /tmp/plexmediaserver_XXXXXX.deb)
trap 'rm -f "${deb_file}"' EXIT

bashio::log.info "Downloading Plex Media Server update (${remote_version})..."
if ! curl --silent --show-error --fail -L -o "${deb_file}" "${remote_url}"; then
    bashio::log.warning "Failed to download Plex Media Server update."
    exit 0
fi

# Verify downloaded package size
file_size=$(wc -c < "${deb_file}" 2>/dev/null || echo 0)
if [[ "${file_size}" -lt 10000 ]]; then
    bashio::log.warning "Downloaded package is invalid or corrupted."
    exit 0
fi

# Verify SHA1 hash
if [[ -n "${remote_hash}" ]]; then
    bashio::log.debug "Verifying package checksum..."
    if ! echo "${remote_hash}  ${deb_file}" | sha1sum -c --status 2>/dev/null; then
        bashio::log.error "Checksum mismatch for Plex update package! Aborting installation."
        exit 0
    fi
fi

# Install package
bashio::log.info "Installing Plex Media Server ${remote_version}..."
if ! dpkg -i --force-confold --force-architecture "${deb_file}"; then
    bashio::log.error "Failed to install Plex Media Server package ${remote_version}."
    exit 0
fi

bashio::log.info "Plex Media Server successfully updated to ${remote_version}."

# If Plex Media Server is actively running, restart the add-on to apply update
if pgrep -f "/usr/lib/plexmediaserver/Plex Media Server" >/dev/null 2>&1; then
    bashio::log.info "Plex Media Server is running; restarting add-on to apply update..."
    if declare -F bashio::app.restart >/dev/null 2>&1; then
        bashio::app.restart
    elif declare -F bashio::addon.restart >/dev/null 2>&1; then
        bashio::addon.restart
    else
        bashio::log.warning "Please restart the add-on to run the updated version."
    fi
fi

exit 0

