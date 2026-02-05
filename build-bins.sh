#!/bin/bash
#
# build-bins.sh
# Cross-compiles media-mux-controller and creates pre-built tarball for ARM64
#
# Output: bins/media-mux-bins-VERSION-arm64.tar.gz
#

set -e

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build-tmp"
OUTPUT_DIR="$SCRIPT_DIR/bins"
VERSION=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#------------------------------------------------------------------------------
# Helper functions
#------------------------------------------------------------------------------
log() { echo -e "${GREEN}[build-bins]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

#------------------------------------------------------------------------------
# Show help
#------------------------------------------------------------------------------
show_help() {
    cat << EOF
Media-Mux Binary Package Builder

Cross-compiles media-mux-controller for ARM64 and creates a pre-built
tarball containing all necessary files for deployment.

Usage:
  $0 [OPTIONS] [VERSION]

Arguments:
  VERSION           Version string for the package (default: 01)

Options:
  -h, --help        Show this help message
  -c, --check-only  Only check dependencies, don't build
  -o, --output DIR  Output directory (default: ./bins)
  -v, --verbose     Verbose output during build

Examples:
  $0                    # Build with default version (01)
  $0 02                 # Build version 02
  $0 --check-only       # Only verify dependencies
  $0 -o /tmp/out 03     # Build version 03 to /tmp/out

Requirements:
  - aarch64-linux-gnu-gcc   Cross-compiler for ARM64
  - npm                     Node.js package manager
  - tar                     Archive utility
  - file                    File type detection

Output:
  bins/media-mux-bins-VERSION-arm64.tar.gz

Package Contents:
  - media-mux-controller    Pre-compiled ARM64 binary (static)
  - kodisync/               Node.js sync tool with node_modules
  - media-mux-*.sh          Shell scripts
  - rc.local.*              Startup scripts
  - *.xml                   Kodi configuration files
  - VERSION                 Build metadata

EOF
    exit 0
}

#------------------------------------------------------------------------------
# Check dependencies
#------------------------------------------------------------------------------
check_dependencies() {
    local missing=0

    log "Checking dependencies..."
    echo ""

    # Check aarch64-linux-gnu-gcc
    printf "  %-35s" "aarch64-linux-gnu-gcc"
    if command -v aarch64-linux-gnu-gcc &> /dev/null; then
        local gcc_ver=$(aarch64-linux-gnu-gcc --version | head -1 | awk '{print $NF}')
        echo -e "${GREEN}[OK]${NC} (version $gcc_ver)"
    else
        echo -e "${RED}[MISSING]${NC}"
        info "    Install: sudo pacman -S aarch64-linux-gnu-gcc  (Arch)"
        info "    Install: sudo apt install gcc-aarch64-linux-gnu  (Debian/Ubuntu)"
        missing=1
    fi

    # Check npm
    printf "  %-35s" "npm"
    if command -v npm &> /dev/null; then
        local npm_ver=$(npm --version 2>/dev/null)
        echo -e "${GREEN}[OK]${NC} (version $npm_ver)"
    else
        echo -e "${RED}[MISSING]${NC}"
        info "    Install: sudo pacman -S npm  (Arch)"
        info "    Install: sudo apt install npm  (Debian/Ubuntu)"
        missing=1
    fi

    # Check tar
    printf "  %-35s" "tar"
    if command -v tar &> /dev/null; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[MISSING]${NC}"
        missing=1
    fi

    # Check file
    printf "  %-35s" "file"
    if command -v file &> /dev/null; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[MISSING]${NC}"
        missing=1
    fi

    echo ""

    # Check source files
    log "Checking source files..."
    echo ""

    printf "  %-35s" "media-mux-controller.c"
    if [ -f "$SCRIPT_DIR/media-mux-controller.c" ]; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[MISSING]${NC}"
        missing=1
    fi

    printf "  %-35s" "kodisync submodule"
    if [ -d "$SCRIPT_DIR/kodisync" ] && [ -f "$SCRIPT_DIR/kodisync/package.json" ]; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[MISSING]${NC}"
        info "    Run: git submodule update --init"
        missing=1
    fi

    printf "  %-35s" "media-mux-sync-kodi-players.sh"
    if [ -f "$SCRIPT_DIR/media-mux-sync-kodi-players.sh" ]; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[MISSING]${NC}"
        missing=1
    fi

    printf "  %-35s" "rc.local.auto"
    if [ -f "$SCRIPT_DIR/rc.local.auto" ]; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${YELLOW}[MISSING]${NC} (optional)"
    fi

    echo ""

    if [ $missing -eq 1 ]; then
        error "Missing dependencies. Please install required packages and try again."
    fi

    log "All dependencies satisfied"
    return 0
}

#------------------------------------------------------------------------------
# Parse arguments
#------------------------------------------------------------------------------
CHECK_ONLY=0
VERBOSE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -c|--check-only)
            CHECK_ONLY=1
            shift
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -*)
            error "Unknown option: $1\nUse --help for usage information"
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
done

# Set default version if not specified
VERSION="${VERSION:-01}"
TARBALL_NAME="media-mux-bins-${VERSION}-arm64.tar.gz"

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
echo ""
log "=============================================="
log "Media-Mux Binary Package Builder"
log "=============================================="
log "Version: $VERSION"
log "Output: $OUTPUT_DIR/$TARBALL_NAME"
echo ""

# Check dependencies first
check_dependencies

# Exit if check-only mode
if [ $CHECK_ONLY -eq 1 ]; then
    log "Dependency check complete (--check-only mode)"
    exit 0
fi

#------------------------------------------------------------------------------
# Prepare build directory
#------------------------------------------------------------------------------
log "Preparing build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

#------------------------------------------------------------------------------
# Cross-compile media-mux-controller
#------------------------------------------------------------------------------
log "Cross-compiling media-mux-controller for ARM64..."
if [ $VERBOSE -eq 1 ]; then
    aarch64-linux-gnu-gcc -O2 -static \
        "$SCRIPT_DIR/media-mux-controller.c" \
        -o "$BUILD_DIR/media-mux-controller"
else
    aarch64-linux-gnu-gcc -O2 -static \
        "$SCRIPT_DIR/media-mux-controller.c" \
        -o "$BUILD_DIR/media-mux-controller" 2>&1
fi

# Verify it's ARM64
FILE_TYPE=$(file "$BUILD_DIR/media-mux-controller")
if [[ "$FILE_TYPE" != *"aarch64"* ]] && [[ "$FILE_TYPE" != *"ARM aarch64"* ]]; then
    error "Compilation failed - not an ARM64 binary: $FILE_TYPE"
fi
log "Compiled: $(ls -lh "$BUILD_DIR/media-mux-controller" | awk '{print $5}') (static ARM64)"

#------------------------------------------------------------------------------
# Install kodisync dependencies
#------------------------------------------------------------------------------
log "Installing kodisync dependencies (production only)..."
cp -r "$SCRIPT_DIR/kodisync" "$BUILD_DIR/kodisync"
cd "$BUILD_DIR/kodisync"
if [ $VERBOSE -eq 1 ]; then
    npm install --production
else
    npm install --production --silent 2>&1
fi
# Remove unnecessary files
rm -rf .git .gitignore
cd "$SCRIPT_DIR"
log "kodisync node_modules: $(du -sh "$BUILD_DIR/kodisync/node_modules" | cut -f1)"

#------------------------------------------------------------------------------
# Copy shell scripts and config files
#------------------------------------------------------------------------------
log "Copying scripts and configuration files..."

# Shell scripts
cp "$SCRIPT_DIR/media-mux-sync-kodi-players.sh" "$BUILD_DIR/"
cp "$SCRIPT_DIR/media-mux-first-boot.sh" "$BUILD_DIR/"
cp "$SCRIPT_DIR/media-mux-autoplay-master.sh" "$BUILD_DIR/" 2>/dev/null || warn "media-mux-autoplay-master.sh not found"
cp "$SCRIPT_DIR/media-mux-autoplay-slave.sh" "$BUILD_DIR/" 2>/dev/null || warn "media-mux-autoplay-slave.sh not found"
cp "$SCRIPT_DIR/stress-test-sync.sh" "$BUILD_DIR/" 2>/dev/null || true

# rc.local variants
cp "$SCRIPT_DIR/rc.local" "$BUILD_DIR/" 2>/dev/null || warn "rc.local not found"
cp "$SCRIPT_DIR/rc.local.master" "$BUILD_DIR/" 2>/dev/null || warn "rc.local.master not found"
cp "$SCRIPT_DIR/rc.local.auto" "$BUILD_DIR/" 2>/dev/null || warn "rc.local.auto not found"

# Kodi configuration
cp "$SCRIPT_DIR/sources.xml" "$BUILD_DIR/" 2>/dev/null || warn "sources.xml not found"
cp "$SCRIPT_DIR/guisettings.xml" "$BUILD_DIR/" 2>/dev/null || warn "guisettings.xml not found"

# Avahi publish script (placeholder - will be regenerated on first boot)
cat > "$BUILD_DIR/avahi-publish-media-mux.sh" << 'EOF'
#!/bin/sh
# Placeholder - will be regenerated by media-mux-first-boot.sh with MAC-based hostname
MY_ID_STRING="media-mux-auto"
MY_ID_PORT=80
MY_ID_SERVICE="_http._tcp"
MY_ID_HW=$(ifconfig |grep -A1 eth0 |grep inet | awk '{print $2}')
avahi-publish-service -s "$MY_ID_STRING [$MY_ID_HW]" $MY_ID_SERVICE $MY_ID_PORT
EOF
chmod +x "$BUILD_DIR/avahi-publish-media-mux.sh"

# Make all scripts executable
chmod +x "$BUILD_DIR"/*.sh 2>/dev/null || true

#------------------------------------------------------------------------------
# Create version file
#------------------------------------------------------------------------------
log "Creating version file..."
cat > "$BUILD_DIR/VERSION" << EOF
MEDIA_MUX_BINS_VERSION=$VERSION
BUILD_DATE=$(date -u +%Y-%m-%d_%H:%M:%S_UTC)
BUILD_HOST=$(hostname)
ARCH=arm64
COMPILER=$(aarch64-linux-gnu-gcc --version | head -1)
EOF

#------------------------------------------------------------------------------
# Create tarball
#------------------------------------------------------------------------------
log "Creating tarball..."
cd "$BUILD_DIR"
if [ $VERBOSE -eq 1 ]; then
    tar -czvf "$OUTPUT_DIR/$TARBALL_NAME" \
        media-mux-controller \
        kodisync/ \
        media-mux-sync-kodi-players.sh \
        media-mux-first-boot.sh \
        avahi-publish-media-mux.sh \
        media-mux-autoplay-master.sh \
        media-mux-autoplay-slave.sh \
        rc.local \
        rc.local.master \
        rc.local.auto \
        sources.xml \
        guisettings.xml \
        VERSION \
        2>/dev/null || true
else
    tar -czf "$OUTPUT_DIR/$TARBALL_NAME" \
        media-mux-controller \
        kodisync/ \
        media-mux-sync-kodi-players.sh \
        media-mux-first-boot.sh \
        avahi-publish-media-mux.sh \
        media-mux-autoplay-master.sh \
        media-mux-autoplay-slave.sh \
        rc.local \
        rc.local.master \
        rc.local.auto \
        sources.xml \
        guisettings.xml \
        VERSION \
        2>/dev/null || true
fi

cd "$SCRIPT_DIR"

#------------------------------------------------------------------------------
# Cleanup
#------------------------------------------------------------------------------
log "Cleaning up build directory..."
rm -rf "$BUILD_DIR"

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo ""
log "=============================================="
log "Build complete!"
log "=============================================="
echo ""
info "Output:   $OUTPUT_DIR/$TARBALL_NAME"
info "Size:     $(ls -lh "$OUTPUT_DIR/$TARBALL_NAME" | awk '{print $5}')"
info "Version:  $VERSION"
echo ""
log "Contents:"
tar -tzvf "$OUTPUT_DIR/$TARBALL_NAME" | head -20
echo "  ..."
echo ""
log "Next steps:"
echo "  1. Test extraction:"
echo "     mkdir -p /tmp/test && tar -xzf $OUTPUT_DIR/$TARBALL_NAME -C /tmp/test"
echo ""
echo "  2. Commit to repo:"
echo "     git add $OUTPUT_DIR/$TARBALL_NAME"
echo "     git commit -m \"add pre-compiled media-mux-bins v$VERSION\""
echo ""
