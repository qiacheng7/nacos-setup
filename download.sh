#!/bin/bash

# Copyright 1999-2025 Alibaba Group Holding Ltd.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Download Management Library
# Handles Nacos package download, caching, and extraction

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ============================================================================
# Constants
# ============================================================================

CACHE_DIR="${NACOS_CACHE_DIR:-$HOME/.nacos/cache}"
DOWNLOAD_BASE_URL="https://download.nacos.io/nacos-server"
REFERER_URL="https://nacos.io/download/nacos-server/?spm=nacos_install"

# ============================================================================
# Version Management
# ============================================================================

# Get latest Nacos version from GitHub API
get_latest_version() {
    print_info "Fetching latest Nacos version..."
    
    local latest_version=$(curl -fsSL https://api.github.com/repos/alibaba/nacos/releases/latest 2>/dev/null | \
        sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -1)
    
    if [ -z "$latest_version" ]; then
        print_warn "Could not fetch latest version from GitHub, using default"
        latest_version="3.1.1"
    fi
    
    echo "$latest_version"
}

# ============================================================================
# Download Functions
# ============================================================================

# Download Nacos package (with caching)
# Parameters: version
# Returns: path to zip file (in cache) or empty on error
download_nacos() {
    local version=$1
    local zip_filename="nacos-server-${version}.zip"
    local download_url="${DOWNLOAD_BASE_URL}/${zip_filename}?spm=nacos_install&file=${zip_filename}"
    local cached_file="$CACHE_DIR/$zip_filename"
    
    # Create cache directory
    mkdir -p "$CACHE_DIR" 2>/dev/null
    
    # Check if cached file exists and is valid
    if [ -f "$cached_file" ] && [ -s "$cached_file" ]; then
        # Verify the cached zip file is valid
        if unzip -t "$cached_file" >/dev/null 2>&1; then
            print_info "Found cached package: $cached_file" >&2
            print_info "Skipping download, using cached file" >&2
            echo "" >&2
            echo "$cached_file"
            return 0
        else
            print_warn "Cached file is corrupted, re-downloading..." >&2
            rm -f "$cached_file"
        fi
    fi
    
    # Download the file
    print_info "Downloading Nacos version: $version" >&2
    print_info "Download URL: $download_url" >&2
    echo "" >&2
    
    # Download with progress bar and Referer header
    if curl -fL -# -H "Referer: $REFERER_URL" -o "$cached_file" "$download_url" >&2; then
        echo "" >&2
        
        # Verify downloaded file is a valid zip
        if ! unzip -t "$cached_file" >/dev/null 2>&1; then
            print_error "Downloaded file is corrupted or invalid" >&2
            rm -f "$cached_file"
            return 1
        fi
        
        print_info "Download completed: $zip_filename" >&2
        echo "$cached_file"
        return 0
    else
        echo "" >&2
        print_error "Failed to download Nacos $version" >&2
        print_info "Please check if version $version exists" >&2
        print_info "Available versions: https://github.com/alibaba/nacos/releases" >&2
        rm -f "$cached_file"
        return 1
    fi
}

# ============================================================================
# Extraction Functions
# ============================================================================

# Extract Nacos package to temporary directory
# Parameters: zip_file
# Returns: path to extracted directory or empty on error
extract_nacos_to_temp() {
    local zip_file=$1
    local tmp_dir="/tmp/nacos-extract-$$"
    
    print_info "Extracting Nacos package..." >&2
    
    # Verify zip file exists
    if [ ! -f "$zip_file" ]; then
        print_error "Zip file not found: $zip_file" >&2
        return 1
    fi
    
    # Create temp directory
    mkdir -p "$tmp_dir"
    
    # Extract
    if ! unzip -q "$zip_file" -d "$tmp_dir" >&2; then
        print_error "Failed to extract Nacos archive" >&2
        rm -rf "$tmp_dir"
        return 1
    fi
    
    # Find the extracted directory
    local extracted_dir=$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d -name "nacos" 2>/dev/null | head -1)
    
    if [ -z "$extracted_dir" ]; then
        print_error "Could not find extracted Nacos directory" >&2
        rm -rf "$tmp_dir"
        return 1
    fi
    
    # Verify structure
    if [ ! -d "$extracted_dir/bin" ] || [ ! -d "$extracted_dir/conf" ]; then
        print_error "Extracted Nacos directory has invalid structure" >&2
        rm -rf "$tmp_dir"
        return 1
    fi
    
    echo "$extracted_dir"
    return 0
}

# Extract Nacos package to target directory with custom name
# Parameters: zip_file, target_base_dir, node_name
# Returns: 0 on success, 1 on failure
extract_nacos_to_target() {
    local zip_file=$1
    local target_base_dir=$2
    local node_name=$3
    local final_path="$target_base_dir/$node_name"
    
    print_info "Setting up: $node_name..." >&2
    
    # Remove existing directory if present
    if [ -d "$final_path" ]; then
        print_info "Removing existing directory: $final_path" >&2
        rm -rf "$final_path"
    fi
    
    # Create base directory
    mkdir -p "$target_base_dir"
    
    # Extract to temporary location first
    local temp_extract="$target_base_dir/.tmp_extract_$$"
    mkdir -p "$temp_extract"
    
    if ! unzip -q "$zip_file" -d "$temp_extract" >&2; then
        print_error "Failed to extract Nacos package" >&2
        rm -rf "$temp_extract"
        return 1
    fi
    
    # Move extracted nacos directory to final location
    if [ -d "$temp_extract/nacos" ]; then
        mv "$temp_extract/nacos" "$final_path"
        rm -rf "$temp_extract"
        
        # Set permissions
        chmod +x "$final_path/bin/"*.sh 2>/dev/null || true
        
        print_info "Node extracted: $final_path" >&2
        return 0
    else
        print_error "Extracted package structure is unexpected" >&2
        rm -rf "$temp_extract"
        return 1
    fi
}

# ============================================================================
# Installation Functions
# ============================================================================

# Install extracted Nacos to target directory (move operation)
# Parameters: source_dir, target_dir
# Returns: 0 on success, 1 on failure
install_nacos() {
    local source_dir=$1
    local target_dir=$2
    
    # Validate source directory
    if [ ! -d "$source_dir" ]; then
        print_error "Source directory does not exist: $source_dir"
        return 1
    fi
    
    if [ ! -d "$source_dir/bin" ] || [ ! -d "$source_dir/conf" ]; then
        print_error "Invalid Nacos package structure in: $source_dir"
        return 1
    fi
    
    # Remove old installation if exists
    if [ -d "$target_dir" ]; then
        print_info "Removing old installation: $target_dir"
        rm -rf "$target_dir"
    fi
    
    print_info "Installing Nacos to: $target_dir"
    
    # Create parent directory
    mkdir -p "$(dirname "$target_dir")"
    
    # Move to installation directory
    if ! mv "$source_dir" "$target_dir"; then
        print_error "Failed to move Nacos to installation directory"
        return 1
    fi
    
    # Verify installation
    if [ ! -d "$target_dir/conf" ] || [ ! -f "$target_dir/conf/application.properties" ]; then
        print_error "Installation verification failed: missing configuration"
        return 1
    fi
    
    # Set permissions for bin scripts
    chmod +x "$target_dir/bin/"*.sh 2>/dev/null || true
    
    print_info "Installation completed: $target_dir"
    return 0
}

# ============================================================================
# Cleanup Functions
# ============================================================================

# Cleanup temporary extraction directory
cleanup_temp_dir() {
    local temp_dir=$1
    
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        print_info "Cleaning up temporary files..."
        rm -rf "$temp_dir"
    fi
}
