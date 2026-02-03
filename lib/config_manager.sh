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

# Configuration Management Library
# Handles Nacos configuration, datasource setup, and security settings

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# ============================================================================
# Global Configuration Paths
# ============================================================================

GLOBAL_DATASOURCE_CONFIG="$HOME/ai-infra/nacos/default.properties"

# ============================================================================
# Datasource Configuration
# ============================================================================

# Load global datasource configuration
# Returns: path to global datasource file or empty string
load_global_datasource_config() {
    # Check if global datasource exists and contains database configuration
    if [ -f "$GLOBAL_DATASOURCE_CONFIG" ] && [ -s "$GLOBAL_DATASOURCE_CONFIG" ]; then
        # Check if global config contains actual database configuration
        if grep -v '^[[:space:]]*#' "$GLOBAL_DATASOURCE_CONFIG" | \
           grep -v '^[[:space:]]*$' | \
           grep -qE '^(spring\.(datasource|sql\.init)\.platform|db\.num)'; then
            echo "$GLOBAL_DATASOURCE_CONFIG"
            return 0
        fi
    fi
    
    # No valid datasource configuration found
    echo ""
    return 1
}

# Apply datasource configuration to node
# Parameters: config_file, datasource_file
# Returns: 0 on success, 1 on failure
apply_datasource_config() {
    local config_file=$1
    local datasource_file=$2
    
    if [ ! -f "$config_file" ]; then
        print_error "Config file not found: $config_file"
        return 1
    fi
    
    # Check if datasource file exists and has valid configuration
    if [ -n "$datasource_file" ] && [ -f "$datasource_file" ] && [ -s "$datasource_file" ]; then
        if grep -v '^[[:space:]]*#' "$datasource_file" | \
           grep -v '^[[:space:]]*$' | \
           grep -qE '^(spring\.(datasource|sql\.init)\.platform|db\.num)'; then
            
            # Read datasource properties and apply them
            while IFS='=' read -r key value; do
                # Skip comments and empty lines
                [[ "$key" =~ ^#.*$ ]] && continue
                [[ -z "$key" ]] && continue
                
                # Trim whitespace
                key=$(echo "$key" | xargs)
                value=$(echo "$value" | xargs)
                
                update_config_property "$config_file" "$key" "$value"
            done < "$datasource_file"
            
            return 0
        fi
    fi
    
    # No external database, use Derby (for cluster mode, must explicitly set)
    # For standalone mode, Derby is the default
    return 1
}

# Configure Derby for cluster mode
# Parameters: config_file
configure_derby_for_cluster() {
    local config_file=$1
    
    if [ ! -f "$config_file" ]; then
        print_error "Config file not found: $config_file"
        return 1
    fi
    
    # For Derby in cluster mode, MUST explicitly set platform to 'derby'
    # spring.sql.init.platform is the new property (Spring Boot 3.x / Nacos 3.x)
    # spring.datasource.platform is the old property (Spring Boot 2.x / Nacos 2.x)
    update_config_property "$config_file" "spring.sql.init.platform" "derby"
    
    # Remove old property if exists (for compatibility)
    sed -i.bak '/^spring\.datasource\.platform=/d' "$config_file"
    
    # Remove any external database configurations that might exist
    sed -i.bak '/^db\.num=/d' "$config_file"
    sed -i.bak '/^db\.url/d' "$config_file"
    sed -i.bak '/^db\.user/d' "$config_file"
    sed -i.bak '/^db\.password/d' "$config_file"
    
    rm -f "$config_file.bak"
}

# ============================================================================
# Security Configuration
# ============================================================================

# Apply security configuration to node
# Parameters: config_file, token_secret, identity_key, identity_value
apply_security_config() {
    local config_file=$1
    local token_secret=$2
    local identity_key=$3
    local identity_value=$4
    
    if [ ! -f "$config_file" ]; then
        print_error "Config file not found: $config_file"
        return 1
    fi
    
    # Enable authentication
    update_config_property "$config_file" "nacos.core.auth.enabled" "true"
    update_config_property "$config_file" "nacos.core.auth.plugin.nacos.token.secret.key" "$token_secret"
    update_config_property "$config_file" "nacos.core.auth.server.identity.key" "$identity_key"
    update_config_property "$config_file" "nacos.core.auth.server.identity.value" "$identity_value"
}

# Configure security for standalone mode
# Parameters: config_file, advanced_mode
# Returns: sets global variables TOKEN_SECRET, IDENTITY_KEY, IDENTITY_VALUE, NACOS_PASSWORD
configure_standalone_security() {
    local config_file=$1
    local advanced_mode=${2:-false}
    
    if [ "$advanced_mode" = false ]; then
        # Simplified mode: auto-generate all credentials
        TOKEN_SECRET=$(generate_secret_key)
        IDENTITY_KEY="nacos_identity_$(date +%s)"
        IDENTITY_VALUE=$(generate_secret_key | cut -c1-16)
        NACOS_PASSWORD=$(generate_password)
        
        echo "" >&2
        print_info "====================================" >&2
        print_info "Auto-Generated Security Configuration" >&2
        print_info "====================================" >&2
        echo "" >&2
        echo "JWT Token Secret Key:" >&2
        echo "  $TOKEN_SECRET" >&2
        echo "" >&2
        echo "Server Identity Key:" >&2
        echo "  $IDENTITY_KEY" >&2
        echo "" >&2
        echo "Server Identity Value:" >&2
        echo "  $IDENTITY_VALUE" >&2
        echo "" >&2
        echo "Admin Password:" >&2
        echo "  $NACOS_PASSWORD" >&2
        echo "" >&2
        print_info "These credentials will be automatically configured" >&2
    else
        # Advanced mode: interactive prompts
        print_info "" >&2
        print_info "====================================" >&2
        print_info "Security Configuration Required" >&2
        print_info "====================================" >&2
        echo "" >&2
        echo "Nacos requires security configuration for production use." >&2
        echo "" >&2
        
        # JWT Token Secret Key
        echo "Step 1/4: JWT Token Secret Key" >&2
        local auto_token=$(generate_secret_key)
        echo "Auto-generated value: $auto_token" >&2
        read -p "Enter JWT token secret key (press Enter to use auto-generated): " user_token
        TOKEN_SECRET=${user_token:-$auto_token}
        echo "" >&2
        
        # Server Identity Key
        echo "Step 2/4: Server Identity Key" >&2
        local auto_id_key="nacos_identity_$(date +%s)"
        echo "Auto-generated value: $auto_id_key" >&2
        read -p "Enter server identity key (press Enter to use auto-generated): " user_id_key
        IDENTITY_KEY=${user_id_key:-$auto_id_key}
        echo "" >&2
        
        # Server Identity Value
        echo "Step 3/4: Server Identity Value" >&2
        local auto_id_value=$(generate_secret_key | cut -c1-16)
        echo "Auto-generated value: $auto_id_value" >&2
        read -p "Enter server identity value (press Enter to use auto-generated): " user_id_value
        IDENTITY_VALUE=${user_id_value:-$auto_id_value}
        echo "" >&2
        
        # Admin Password
        echo "Step 4/4: Nacos Admin Password" >&2
        local auto_password=$(generate_password)
        echo "Auto-generated value: $auto_password" >&2
        read -p "Enter admin password (press Enter to use auto-generated): " user_password
        NACOS_PASSWORD=${user_password:-$auto_password}
        echo "" >&2
        
        print_info "Security keys configured successfully" >&2
    fi
    
    # Apply security configuration
    apply_security_config "$config_file" "$TOKEN_SECRET" "$IDENTITY_KEY" "$IDENTITY_VALUE"
}

# Configure security for cluster mode
# Parameters: cluster_dir, advanced_mode
# Returns: sets global variables and creates share.properties
configure_cluster_security() {
    local cluster_dir=$1
    local advanced_mode=${2:-false}
    local share_properties="$cluster_dir/share.properties"
    
    echo "" >&2
    
    if [ "$advanced_mode" = false ]; then
        # Simplified mode: auto-generate all security credentials
        print_info "Simplified mode: Auto-generating shared security keys for cluster..." >&2
        
        TOKEN_SECRET=$(generate_secret_key)
        IDENTITY_KEY="nacos_cluster_$(date +%s)"
        IDENTITY_VALUE=$(generate_secret_key | cut -c1-16)
        NACOS_PASSWORD=$(generate_password)
        
        echo "" >&2
        print_info "===========================================" >&2
        print_info "Auto-Generated Cluster Security Configuration" >&2
        print_info "===========================================" >&2
        echo "" >&2
        echo "JWT Token Secret Key:" >&2
        echo "  $TOKEN_SECRET" >&2
        echo "" >&2
        echo "Server Identity Key:" >&2
        echo "  $IDENTITY_KEY" >&2
        echo "" >&2
        echo "Server Identity Value:" >&2
        echo "  $IDENTITY_VALUE" >&2
        echo "" >&2
        print_info "These credentials will be shared across all cluster nodes" >&2
        print_info "Admin password will be set after cluster startup" >&2
        echo "" >&2
    else
        # Advanced mode: allow user to customize
        print_info "===========================================" >&2
        print_info "Cluster Security Configuration Required" >&2
        print_info "===========================================" >&2
        echo "" >&2
        echo "All nodes in the cluster must use the same security keys." >&2
        echo "" >&2
        
        # Similar interactive prompts as standalone
        echo "Step 1/4: JWT Token Secret Key" >&2
        local auto_token=$(generate_secret_key)
        echo "Auto-generated value: $auto_token" >&2
        read -p "Enter JWT token secret key (press Enter to use auto-generated): " user_token
        TOKEN_SECRET=${user_token:-$auto_token}
        echo "" >&2
        
        echo "Step 2/4: Server Identity Key" >&2
        local auto_id_key="nacos_cluster_$(date +%s)"
        echo "Auto-generated value: $auto_id_key" >&2
        read -p "Enter server identity key (press Enter to use auto-generated): " user_id_key
        IDENTITY_KEY=${user_id_key:-$auto_id_key}
        echo "" >&2
        
        echo "Step 3/4: Server Identity Value" >&2
        local auto_id_value=$(generate_secret_key | cut -c1-16)
        echo "Auto-generated value: $auto_id_value" >&2
        read -p "Enter server identity value (press Enter to use auto-generated): " user_id_value
        IDENTITY_VALUE=${user_id_value:-$auto_id_value}
        echo "" >&2
        
        echo "Step 4/4: Nacos Admin Password" >&2
        local auto_password=$(generate_password)
        echo "Auto-generated value: $auto_password" >&2
        read -p "Enter admin password (press Enter to use auto-generated): " user_password
        NACOS_PASSWORD=${user_password:-$auto_password}
        echo "" >&2
        
        print_info "Security keys configured successfully" >&2
        print_info "Admin password will be set after cluster startup" >&2
        echo "" >&2
    fi
    
    # Save shared security configuration to share.properties
    cat > "$share_properties" << EOF
# Nacos Cluster Shared Security Configuration
# Auto-generated on $(date)
# DO NOT modify these values unless you update ALL cluster nodes

# JWT Token Secret Key (Base64 encoded, 32+ characters before encoding)
nacos.core.auth.plugin.nacos.token.secret.key=$TOKEN_SECRET

# Server Identity Key (identifies the cluster)
nacos.core.auth.server.identity.key=$IDENTITY_KEY

# Server Identity Value (secret value for the identity key)
nacos.core.auth.server.identity.value=$IDENTITY_VALUE

# Admin Password (for 'nacos' user)
# Note: This is stored for reference only, actual password is set via API
admin.password=$NACOS_PASSWORD
EOF
    
    print_info "Security configuration saved to: $share_properties" >&2
    echo "" >&2
}

# ============================================================================
# Port Configuration
# ============================================================================

# Update port configuration in application.properties
# Parameters: config_file, server_port, console_port, nacos_version
update_port_config() {
    local config_file=$1
    local server_port=$2
    local console_port=$3
    local nacos_version=$4
    
    local nacos_major=$(echo "$nacos_version" | cut -d. -f1)
    
    if [ "$nacos_major" -ge 3 ]; then
        # Nacos 3.x: separate main port and console port
        update_config_property "$config_file" "nacos.server.main.port" "$server_port"
        update_config_property "$config_file" "nacos.console.port" "$console_port"
    else
        # Nacos 2.x: only server.port
        update_config_property "$config_file" "server.port" "$server_port"
    fi
    
    rm -f "$config_file.bak"
}
