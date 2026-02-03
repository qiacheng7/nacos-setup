#!/bin/bash

# Nacos Setup Installation Script
# This script downloads and installs nacos-setup from remote repository

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# Configuration
# ============================================================================

REMOTE_DOWNLOAD_URL="https://nacos.io/download/nacos-server/nacos-setup-VERSION.zip"
INSTALL_DIR="/usr/local/nacos-setup"
BIN_DIR="/usr/local/bin"
SCRIPT_NAME="nacos-setup"
TEMP_DIR="/tmp/nacos-setup-install-$$"
CACHE_DIR="${HOME}/.nacos/cache"  # 缓存目录

# Detect installation mode
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/nacos-setup.sh" ] && [ -d "$SCRIPT_DIR/lib" ]; then
    INSTALL_MODE="local"
else
    INSTALL_MODE="remote"
fi

# ============================================================================
# Check Requirements
# ============================================================================

check_requirements() {
    print_info "Checking system requirements..."
    
    # Check if running on macOS or Linux
    if [[ "$OSTYPE" != "darwin"* ]] && [[ "$OSTYPE" != "linux-gnu"* ]]; then
        print_error "Unsupported OS: $OSTYPE"
        print_error "This script only supports macOS and Linux"
        exit 1
    fi
    
    # Check for required commands (only for remote mode)
    if [ "$INSTALL_MODE" = "remote" ]; then
        local missing_commands=()
        
        if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
            missing_commands+=("curl or wget")
        fi
        
        if ! command -v unzip >/dev/null 2>&1; then
            missing_commands+=("unzip")
        fi
        
        if [ ${#missing_commands[@]} -gt 0 ]; then
            print_error "Missing required commands: ${missing_commands[*]}"
            echo ""
            print_info "Please install missing commands:"
            if [[ "$OSTYPE" == "darwin"* ]]; then
                echo "  brew install curl unzip"
            else
                echo "  sudo apt-get install curl unzip  # Debian/Ubuntu"
                echo "  sudo yum install curl unzip      # CentOS/RHEL"
            fi
            return 1
        fi
    fi
    
    # Check if we have write permission to install directory
    if [ ! -w "$(dirname "$INSTALL_DIR")" ]; then
        print_warn "No write permission to $(dirname "$INSTALL_DIR")"
        print_warn "You may need to run with sudo"
        return 1
    fi
    
    return 0
}

# ============================================================================
# Download
# ============================================================================

download_file() {
    local url=$1
    local output=$2
    
    print_info "Downloading nacos-setup from $url..."
    
    # Try curl first, then wget
    if command -v curl >/dev/null 2>&1; then
        if curl -fSL --progress-bar "$url" -o "$output"; then
            return 0
        else
            print_error "Download failed with curl"
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --show-progress "$url" -O "$output"; then
            return 0
        else
            print_error "Download failed with wget"
            return 1
        fi
    else
        print_error "Neither curl nor wget is available"
        return 1
    fi
}

# Download nacos-setup package with caching support
# Parameters: version
# Returns: path to zip file (in cache or temp) or empty on error
download_nacos_setup() {
    local version=$1
    local zip_filename="nacos-setup-${version}.zip"
    local download_url="${REMOTE_DOWNLOAD_URL/VERSION/$version}"
    local cached_file="$CACHE_DIR/$zip_filename"
    
    # Create cache directory
    mkdir -p "$CACHE_DIR" 2>/dev/null
    
    # Check if cached file exists and is valid
    if [ -f "$cached_file" ] && [ -s "$cached_file" ]; then
        # Verify the cached zip file is valid
        if unzip -t "$cached_file" >/dev/null 2>&1; then
            print_info "Found cached package: $cached_file"
            print_info "Skipping download, using cached file"
            echo ""
            echo "$cached_file"
            return 0
        else
            print_warn "Cached file is corrupted, re-downloading..."
            rm -f "$cached_file"
        fi
    fi
    
    # Download the file to cache
    print_info "Downloading nacos-setup version: $version"
    echo ""
    
    if ! download_file "$download_url" "$cached_file"; then
        print_error "Failed to download nacos-setup"
        rm -f "$cached_file"
        return 1
    fi
    
    echo ""
    
    # Verify downloaded file is a valid zip
    if ! unzip -t "$cached_file" >/dev/null 2>&1; then
        print_error "Downloaded file is corrupted or invalid"
        rm -f "$cached_file"
        return 1
    fi
    
    print_info "Download completed: $zip_filename"
    echo "$cached_file"
    return 0
}

# ============================================================================
# Installation
# ============================================================================

install_nacos_setup() {
    print_info "Installing nacos-setup..."
    echo ""
    
    local extracted_dir=""
    local setup_version=""
    
    if [ "$INSTALL_MODE" = "local" ]; then
        # Local installation mode
        print_info "Installation mode: Local"
        
        # Detect version from nacos-setup.sh
        if [ -f "$SCRIPT_DIR/nacos-setup.sh" ]; then
            setup_version=$(grep '^NACOS_SETUP_VERSION=' "$SCRIPT_DIR/nacos-setup.sh" | cut -d'"' -f2)
            if [ -z "$setup_version" ]; then
                # Fallback: try to extract from comment
                setup_version=$(grep '# Version:' "$SCRIPT_DIR/nacos-setup.sh" | head -1 | awk '{print $3}')
            fi
            if [ -z "$setup_version" ]; then
                setup_version="unknown"
            fi
        fi
        
        print_info "Detected version: $setup_version"
        extracted_dir="$SCRIPT_DIR"
        
    else
        # Remote installation mode
        print_info "Installation mode: Remote"
        
        # Use default version or detect from URL
        setup_version="0.0.1"
        
        print_info "Target version: $setup_version"
        
        # Download nacos-setup (with caching)
        local zip_file=$(download_nacos_setup "$setup_version")
        
        if [ -z "$zip_file" ]; then
            print_error "Failed to download nacos-setup"
            exit 1
        fi
        
        print_success "Package ready: $zip_file"
        echo ""
        
        # Create temporary directory for extraction
        mkdir -p "$TEMP_DIR"
        
        # Extract zip file
        print_info "Extracting nacos-setup..."
        if ! unzip -q "$zip_file" -d "$TEMP_DIR"; then
            print_error "Failed to extract zip file"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
        
        # Find extracted directory (should be nacos-setup-VERSION or similar)
        extracted_dir=$(find "$TEMP_DIR" -maxdepth 1 -type d ! -path "$TEMP_DIR" | head -1)
        
        if [ -z "$extracted_dir" ] || [ ! -d "$extracted_dir" ]; then
            print_error "Failed to find extracted directory"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    fi
    
    # Verify required files
    if [ ! -f "$extracted_dir/nacos-setup.sh" ]; then
        print_error "nacos-setup.sh not found in package"
        [ "$INSTALL_MODE" = "remote" ] && rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    if [ ! -d "$extracted_dir/lib" ]; then
        print_error "lib directory not found in package"
        [ "$INSTALL_MODE" = "remote" ] && rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Remove old installation if exists
    if [ -d "$INSTALL_DIR" ]; then
        print_info "Removing old installation..."
        rm -rf "$INSTALL_DIR"
    fi
    
    # Create installation directory
    print_info "Creating installation directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    
    # Copy nacos-setup.sh to bin directory
    print_info "Installing nacos-setup command..."
    mkdir -p "$INSTALL_DIR/bin"
    cp "$extracted_dir/nacos-setup.sh" "$INSTALL_DIR/bin/$SCRIPT_NAME"
    chmod +x "$INSTALL_DIR/bin/$SCRIPT_NAME"
    
    # Copy lib directory
    print_info "Installing libraries..."
    cp -r "$extracted_dir/lib" "$INSTALL_DIR/"
    
    # Make all lib scripts executable
    chmod +x "$INSTALL_DIR/lib"/*.sh
    
    # Create symlink in /usr/local/bin
    print_info "Creating global command..."
    if [ -L "$BIN_DIR/$SCRIPT_NAME" ] || [ -f "$BIN_DIR/$SCRIPT_NAME" ]; then
        rm -f "$BIN_DIR/$SCRIPT_NAME"
    fi
    
    ln -s "$INSTALL_DIR/bin/$SCRIPT_NAME" "$BIN_DIR/$SCRIPT_NAME"
    
    # Cleanup temporary directory (only for remote mode)
    if [ "$INSTALL_MODE" = "remote" ]; then
        rm -rf "$TEMP_DIR"
    fi
    
    # Store version info
    echo "$setup_version" > "$INSTALL_DIR/.version"
    
    print_success "Installation completed!"
    echo ""
    
    # Export version for later use
    INSTALLED_VERSION="$setup_version"
}

# ============================================================================
# Verification
# ============================================================================

verify_installation() {
    print_info "Verifying installation..."
    
    if [ ! -f "$BIN_DIR/$SCRIPT_NAME" ]; then
        print_error "Installation failed: $BIN_DIR/$SCRIPT_NAME not found"
        return 1
    fi
    
    if ! command -v $SCRIPT_NAME >/dev/null 2>&1; then
        print_error "Command not found in PATH"
        print_warn "Please add $BIN_DIR to your PATH"
        print_warn "Add this to your ~/.bashrc or ~/.zshrc:"
        echo ""
        echo "    export PATH=\"$BIN_DIR:\$PATH\""
        echo ""
        return 1
    fi
    
    print_success "Installation verified successfully!"
    echo ""
    
    return 0
}

# ============================================================================
# Post-installation Info
# ============================================================================

print_usage_info() {
    local version="${INSTALLED_VERSION:-unknown}"
    
    echo "========================================"
    echo "  Nacos Setup Installation Complete"
    echo "========================================"
    echo ""
    echo "Version: $version"
    echo "Installation location: $INSTALL_DIR"
    echo "Global command: $SCRIPT_NAME"
    echo ""
    echo "Quick Start:"
    echo ""
    echo "  # Show help"
    echo "  $SCRIPT_NAME --help"
    echo ""
    echo "  # Install Nacos standalone"
    echo "  $SCRIPT_NAME -v 3.1.1"
    echo ""
    echo "  # Install Nacos cluster"
    echo "  $SCRIPT_NAME -c prod -n 3"
    echo ""
    echo "  # Configure datasource"
    echo "  $SCRIPT_NAME --datasource-conf"
    echo ""
    echo "Documentation: https://nacos.io"
    echo ""
    echo "========================================"
}

# ============================================================================
# Version Check
# ============================================================================

check_installed_version() {
    if [ -f "$INSTALL_DIR/.version" ]; then
        local version=$(cat "$INSTALL_DIR/.version")
        print_info "Installed nacos-setup version: $version"
        print_info "Installation location: $INSTALL_DIR"
        return 0
    else
        print_warn "nacos-setup is not installed or version information not found"
        return 1
    fi
}

# ============================================================================
# Uninstallation
# ============================================================================

uninstall_nacos_setup() {
    print_info "Uninstalling nacos-setup..."
    
    # Remove installation directory
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        print_success "Removed $INSTALL_DIR"
    fi
    
    # Remove symlink
    if [ -L "$BIN_DIR/$SCRIPT_NAME" ] || [ -f "$BIN_DIR/$SCRIPT_NAME" ]; then
        rm -f "$BIN_DIR/$SCRIPT_NAME"
        print_success "Removed $BIN_DIR/$SCRIPT_NAME"
    fi
    
    print_success "Uninstallation completed!"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "========================================"
    echo "  Nacos Setup Installer"
    echo "========================================"
    echo ""
    
    # Parse arguments
    case "${1:-}" in
        version|--version|-v)
            check_installed_version
            exit $?
            ;;
        uninstall|--uninstall|-u)
            uninstall_nacos_setup
            exit 0
            ;;
        --help|-h)
            echo "Usage: bash install.sh [OPTION]"
            echo ""
            echo "Options:"
            echo "  (none)              Install nacos-setup (local or remote)"
            echo "  version, -v         Show installed version"
            echo "  uninstall, -u       Uninstall nacos-setup"
            echo "  --help, -h          Show this help message"
            echo ""
            echo "Installation Modes:"
            echo "  Local:  Run from nacos-setup source directory"
            echo "  Remote: Download from https://nacos.io"
            echo ""
            exit 0
            ;;
    esac
    
    # Check requirements
    if ! check_requirements; then
        print_error "Requirements check failed"
        print_info "Try running with sudo: sudo bash install.sh"
        exit 1
    fi
    
    # Install
    install_nacos_setup
    
    # Verify
    if verify_installation; then
        print_usage_info
        exit 0
    else
        print_error "Installation verification failed"
        exit 1
    fi
}

# Run main
main "$@"
