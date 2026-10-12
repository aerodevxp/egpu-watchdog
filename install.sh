#!/bin/bash
set -u

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

tty_read() {
    read -rp "$1" "$2" < /dev/tty
}

# Must be root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root: sudo bash $0"
    exit 1
fi

# Check required tools
for cmd in lspci systemctl getent sed; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Required command not found: $cmd"
        exit 1
    fi
done

# Check for curl or wget
if command -v curl >/dev/null 2>&1; then
    FETCH_CMD="curl -fsSL"
elif command -v wget >/dev/null 2>&1; then
    FETCH_CMD="wget -qO-"
else
    error "curl or wget is required"
    exit 1
fi

# Detect primary user (UID 1000)
USER_INFO=$(getent passwd 1000 2>/dev/null) || true
if [ -z "$USER_INFO" ]; then
    error "Could not find user with UID 1000"
    exit 1
fi
USER_NAME=$(echo "$USER_INFO" | cut -d: -f1)
USER_HOME=$(echo "$USER_INFO" | cut -d: -f6)
info "Primary user: ${CYAN}$USER_NAME${NC} (${CYAN}$USER_HOME${NC})"

# Stop existing service
systemctl stop egpu-watcher.service 2>/dev/null || true

# ============================================================
# Download scripts from GitHub
# ============================================================
BASE_URL="https://raw.githubusercontent.com/aerodevxp/egpu-watchdog/refs/heads/main"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

info "Downloading scripts from GitHub..."

$FETCH_CMD "$BASE_URL/usr/local/bin/egpu-watcher.sh" > "$TMPDIR/egpu-watcher.sh" || { error "Failed to download egpu-watcher.sh"; exit 1; }
$FETCH_CMD "$BASE_URL/homedir/bin/switch-egpu.sh" > "$TMPDIR/switch-egpu.sh" || { error "Failed to download switch-egpu.sh"; exit 1; }
$FETCH_CMD "$BASE_URL/homedir/bin/switch-internal.sh" > "$TMPDIR/switch-internal.sh" || { error "Failed to download switch-internal.sh"; exit 1; }
$FETCH_CMD "$BASE_URL/etc/systemd/system/egpu-watcher.service" > "$TMPDIR/egpu-watcher.service" || { error "Failed to download egpu-watcher.service"; exit 1; }

info "All scripts downloaded."

# ============================================================
# Dock Settings
# ============================================================
echo ""
echo -e "${CYAN}=== Dock Settings ===${NC}"
echo "The docksettings script switches game/application settings when docking/undocking."
echo ""
echo "Options:"
echo "  1. Enter a custom path to your docksettings directory"
echo "  2. Press Enter to clone from GitHub to ~/.docksettings"
echo "  3. Type 'skip' to skip (game settings won't be switched)"
echo ""

DOCKSETTINGS_INPUT=""
tty_read "Choice [Enter=clone/skip]: " DOCKSETTINGS_INPUT || { echo "Aborted."; exit 1; }

DOCKSETTINGS_SCRIPT=""
DOCKSETTINGS_DIR=""

if [ "$DOCKSETTINGS_INPUT" = "skip" ]; then
    warn "Docksettings skipped. Game settings will not be switched."
elif [ -z "$DOCKSETTINGS_INPUT" ]; then
    # Clone from GitHub to ~/.docksettings
    DOCKSETTINGS_DIR="$USER_HOME/.docksettings"

    if ! command -v git >/dev/null 2>&1; then
        error "git is required to clone. Install git or provide a path."
        exit 1
    fi

    if [ -d "$DOCKSETTINGS_DIR" ]; then
        info "Directory exists. Pulling latest..."
        sudo -u "$USER_NAME" git -C "$DOCKSETTINGS_DIR" pull || warn "Could not pull latest changes"
    else
        info "Cloning egpudocksettings to ${CYAN}$DOCKSETTINGS_DIR${NC}..."
        sudo -u "$USER_NAME" git clone https://github.com/aerodevxp/egpudocksettings "$DOCKSETTINGS_DIR" || {
            error "Failed to clone repository"
            exit 1
        }
    fi
else
    # User provided a path — expand ~ if needed
    DOCKSETTINGS_DIR="${DOCKSETTINGS_INPUT/#\~/$USER_HOME}"
fi

# Find docksettings.sh in the directory
if [ -n "$DOCKSETTINGS_DIR" ]; then
    if [ -f "$DOCKSETTINGS_DIR/docksettings.sh" ]; then
        DOCKSETTINGS_SCRIPT="$DOCKSETTINGS_DIR/docksettings.sh"
    else
        DOCKSETTINGS_SCRIPT=$(find "$DOCKSETTINGS_DIR" -name "docksettings.sh" -type f 2>/dev/null | head -1)
    fi

    if [ -z "$DOCKSETTINGS_SCRIPT" ]; then
        warn "Could not find docksettings.sh in $DOCKSETTINGS_DIR"
        warn "Switch scripts will skip the settings switch."
    else
        info "Using docksettings: ${CYAN}$DOCKSETTINGS_SCRIPT${NC}"
    fi
fi

# ============================================================
# all-ways-egpu
# ============================================================
echo ""
echo -e "${CYAN}=== all-ways-egpu ===${NC}"
ALL_WAYS_EGPU=""
for path in "$USER_HOME/bin/all-ways-egpu" "/usr/local/bin/all-ways-egpu" "/usr/bin/all-ways-egpu"; do
    if [ -f "$path" ]; then
        ALL_WAYS_EGPU="$path"
        break
    fi
done

if [ -n "$ALL_WAYS_EGPU" ]; then
    info "Found all-ways-egpu: ${CYAN}$ALL_WAYS_EGPU${NC}"
else
    warn "all-ways-egpu not found."
    warn "Compositor primary GPU switch will be skipped on switch."
    warn "MESA_VK_DEVICE_SELECT will still handle Vulkan device selection."
    warn "Install from: https://github.com/ewagner12/all-ways-egpu"
fi

# ============================================================
# GPU IDs
# ============================================================
echo ""
echo -e "${CYAN}=== GPU Detection ===${NC}"
echo "Detected GPUs:"
lspci -nn | grep -E 'VGA|3D|Display' || true
echo ""

EGPU_ID=""
tty_read "Enter your eGPU PCI ID (e.g., 1002:73bf): " EGPU_ID || { echo "Aborted."; exit 1; }
if [ -z "$EGPU_ID" ]; then
    error "eGPU PCI ID is required"
    exit 1
fi

IGPU_ID=""
tty_read "Enter your iGPU PCI ID (e.g., 1002:1638): " IGPU_ID || { echo "Aborted."; exit 1; }
if [ -z "$IGPU_ID" ]; then
    error "iGPU PCI ID is required"
    exit 1
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${CYAN}=== Configuration Summary ===${NC}"
echo "  User:          $USER_NAME"
echo "  Home:          $USER_HOME"
echo "  eGPU ID:       $EGPU_ID"
echo "  iGPU ID:       $IGPU_ID"
echo "  Dock Settings: ${DOCKSETTINGS_SCRIPT:-skipped}"
echo "  all-ways-egpu: ${ALL_WAYS_EGPU:-NOT FOUND}"
echo "  Service runs:  as root"
echo ""

tty_read "Proceed with installation? (y/N): " CONFIRM || { echo "Aborted."; exit 1; }
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

# ============================================================
# Patch scripts
# ============================================================
echo ""
info "Patching scripts..."

# --- egpu-watcher.sh ---
WATCHER="$TMPDIR/egpu-watcher.sh"
info "Patching egpu-watcher.sh..."

# Replace GPU IDs (flexible pattern to match any existing ID value)
sed -i "s/^EGPU_ID=\"[^\"]*\".*/EGPU_ID=\"$EGPU_ID\"/" "$WATCHER"
sed -i "s/^IGPU_ID=\"[^\"]*\".*/IGPU_ID=\"$IGPU_ID\"/" "$WATCHER"

# Remove `systemctl stop display-manager` at the top (before the loop)
# This causes black screen on boot if no eGPU is connected — the watcher
# only needs to act on state changes, not stop the DM unconditionally
sed -i '/^systemctl stop display-manager$/d' "$WATCHER"

# Change STATE_FILE to /run/ (root-accessible, doesn't depend on user session existing)
sed -i 's|STATE_FILE="/run/user/${USER_UID}/egpu-watcher.state"|STATE_FILE="/run/egpu-watcher.state"|' "$WATCHER"

# Remove `sudo` from switch script calls (service runs as root)
sed -i 's|sudo "$USER_HOME/bin/switch-egpu.sh"|"$USER_HOME/bin/switch-egpu.sh"|' "$WATCHER"
sed -i 's|sudo "$USER_HOME/bin/switch-internal.sh"|"$USER_HOME/bin/switch-internal.sh"|' "$WATCHER"

# Remove `sudo` from tee commands (already root)
sed -i 's|sudo tee|tee|g' "$WATCHER"

# --- switch-egpu.sh ---
SWITCH_EGPU="$TMPDIR/switch-egpu.sh"
info "Patching switch-egpu.sh..."

# Handle docksettings path
if [ -n "$DOCKSETTINGS_SCRIPT" ]; then
    # Replace the hardcoded docksettings path with the user's path
    sed -i 's|\$USER_HOME/bin/egpudocksettings-main/docksettings.sh|__DOCKSETTINGS__|g' "$SWITCH_EGPU"
    sed -i "s|__DOCKSETTINGS__|$DOCKSETTINGS_SCRIPT|g" "$SWITCH_EGPU"
else
    # Comment out the docksettings call so it's skipped gracefully
    sed -i '/docksettings\.sh/s|^$$[[:space:]]*$$sudo|\1# sudo|' "$SWITCH_EGPU"
fi

# Make all-ways-egpu call conditional (skip with warning if not installed)
sed -i '/sudo "\$USER_HOME\/bin\/all-ways-egpu" set-compositor-primary egpu/c\if [ -f "$USER_HOME/bin/all-ways-egpu" ]; then\n    sudo "$USER_HOME/bin/all-ways-egpu" set-compositor-primary egpu\nelse\n    echo "WARNING: all-ways-egpu not found, skipping compositor primary switch"\nfi' "$SWITCH_EGPU"

# If all-ways-egpu is at a non-default path, update the scripts to use it
if [ -n "$ALL_WAYS_EGPU" ] && [ "$ALL_WAYS_EGPU" != "$USER_HOME/bin/all-ways-egpu" ]; then
    sed -i 's|\$USER_HOME/bin/all-ways-egpu|__AWE_PATH__|g' "$SWITCH_EGPU"
    sed -i "s|__AWE_PATH__|$ALL_WAYS_EGPU|g" "$SWITCH_EGPU"
fi

# --- switch-internal.sh ---
SWITCH_INTERNAL="$TMPDIR/switch-internal.sh"
info "Patching switch-internal.sh..."

# Handle docksettings path
if [ -n "$DOCKSETTINGS_SCRIPT" ]; then
    sed -i 's|\$USER_HOME/bin/egpudocksettings-main/docksettings.sh|__DOCKSETTINGS__|g' "$SWITCH_INTERNAL"
    sed -i "s|__DOCKSETTINGS__|$DOCKSETTINGS_SCRIPT|g" "$SWITCH_INTERNAL"
else
    sed -i '/docksettings\.sh/s|^$$[[:space:]]*$$sudo|\1# sudo|' "$SWITCH_INTERNAL"
fi

# Make all-ways-egpu call conditional
sed -i '/sudo "\$USER_HOME\/bin\/all-ways-egpu" set-compositor-primary internal/c\    if [ -f "$USER_HOME/bin/all-ways-egpu" ]; then\n        sudo "$USER_HOME/bin/all-ways-egpu" set-compositor-primary internal\n    else\n        echo "WARNING: all-ways-egpu not found, skipping compositor primary switch"\n    fi' "$SWITCH_INTERNAL"

# If all-ways-egpu is at a non-default path, update the scripts
if [ -n "$ALL_WAYS_EGPU" ] && [ "$ALL_WAYS_EGPU" != "$USER_HOME/bin/all-ways-egpu" ]; then
    sed -i 's|\$USER_HOME/bin/all-ways-egpu|__AWE_PATH__|g' "$SWITCH_INTERNAL"
    sed -i "s|__AWE_PATH__|$ALL_WAYS_EGPU|g" "$SWITCH_INTERNAL"
fi

# --- egpu-watcher.service ---
SERVICE="$TMPDIR/egpu-watcher.service"
info "Patching egpu-watcher.service..."

# Remove User, Group, Environment lines so the service runs as root
sed -i '/^User=/d' "$SERVICE"
sed -i '/^Group=/d' "$SERVICE"
sed -i '/^Environment=/d' "$SERVICE"

# ============================================================
# Install files
# ============================================================
echo ""
info "Installing files..."

# Create user bin directory
mkdir -p "$USER_HOME/bin"
chown "$USER_NAME":"$USER_NAME" "$USER_HOME/bin"

# Install watcher (system-wide, root-owned)
cp "$WATCHER" /usr/local/bin/egpu-watcher.sh
chmod 755 /usr/local/bin/egpu-watcher.sh

# Install switch scripts (user-owned, but executable by root)
cp "$SWITCH_EGPU" "$USER_HOME/bin/switch-egpu.sh"
chmod 755 "$USER_HOME/bin/switch-egpu.sh"
chown "$USER_NAME":"$USER_NAME" "$USER_HOME/bin/switch-egpu.sh"

cp "$SWITCH_INTERNAL" "$USER_HOME/bin/switch-internal.sh"
chmod 755 "$USER_HOME/bin/switch-internal.sh"
chown "$USER_NAME":"$USER_NAME" "$USER_HOME/bin/switch-internal.sh"

# Install service file
cp "$SERVICE" /etc/systemd/system/egpu-watcher.service
chmod 644 /etc/systemd/system/egpu-watcher.service

# ============================================================
# Sudoers
# ============================================================
info "Setting up sudoers..."
SUDOERS_FILE="/etc/sudoers.d/egpu-watcher"

cat > "$SUDOERS_FILE" << SUDOERS_EOF
# eGPU watcher — allow $USER_NAME to run switch scripts without password
$USER_NAME ALL=(ALL) NOPASSWD: $USER_HOME/bin/switch-egpu.sh, $USER_HOME/bin/switch-internal.sh
SUDOERS_EOF

if [ -n "$ALL_WAYS_EGPU" ]; then
    echo "$USER_NAME ALL=(ALL) NOPASSWD: $ALL_WAYS_EGPU" >> "$SUDOERS_FILE"
fi

chmod 440 "$SUDOERS_FILE"

# Validate sudoers
if command -v visudo >/dev/null 2>&1; then
    if ! visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
        warn "Sudoers validation failed. Check $SUDOERS_FILE manually."
    else
        info "Sudoers validated."
    fi
fi

# ============================================================
# Enable service
# ============================================================
info "Enabling service..."
systemctl daemon-reload
systemctl enable egpu-watcher.service

# ============================================================
# Done
# ============================================================
echo ""
info "=== Installation Complete ==="
echo ""
echo "Files installed:"
echo "  /usr/local/bin/egpu-watcher.sh"
echo "  $USER_HOME/bin/switch-egpu.sh"
echo "  $USER_HOME/bin/switch-internal.sh"
echo "  /etc/systemd/system/egpu-watcher.service"
echo "  $SUDOERS_FILE"
echo ""
echo "Configuration:"
echo "  eGPU ID:       $EGPU_ID"
echo "  iGPU ID:       $IGPU_ID"
echo "  Dock Settings: ${DOCKSETTINGS_SCRIPT:-skipped}"
if [ -z "$ALL_WAYS_EGPU" ]; then
    echo "  all-ways-egpu: NOT INSTALLED (compositor primary switch disabled)"
else
    echo "  all-ways-egpu: $ALL_WAYS_EGPU"
fi
echo "  Service runs:  as root"
echo ""

if [ -z "$DOCKSETTINGS_SCRIPT" ]; then
    echo "NOTE: Docksettings was skipped. Game settings will not be switched."
    echo "      To add it later: git clone https://github.com/aerodevxp/egpudocksettings ~/.docksettings"
    echo "      Then re-run this installer."
    echo ""
fi

if [ -z "$ALL_WAYS_EGPU" ]; then
    echo "NOTE: all-ways-egpu was not found. Only Vulkan device selection (MESA_VK_DEVICE_SELECT)"
    echo "      will be used. Compositor primary GPU switch is disabled."
    echo "      Install from: https://github.com/ewagner12/all-ways-egpu"
    echo ""
fi

echo "NOTE: The audio sink in switch-egpu.sh is set to 'alsa_output.pci-0000_08_00.1.hdmi-stereo-extra3'"
echo "      Adjust this for your eGPU by editing $USER_HOME/bin/switch-egpu.sh"
echo "      Find available sinks with: pactl list short sinks"
echo ""
echo "Known issue: CachyOS + AG03 Dock may require a reboot before docking a"
echo "second time. If the eGPU isn't detected after 90 seconds, reboot."
echo ""
info "Reboot to activate: sudo reboot"
