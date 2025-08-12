#!/bin/bash
# Fix VS Code Extension EACCESS issues on RHEL8
# This script addresses "spawn EACCES" errors when /home is mounted with noexec
# Works with any VS Code extension that has executable binaries

set -e

echo "VS Code Extension EACCESS Fix for RHEL8"
echo "======================================"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo "This script should not be run as root. Please run as a regular user with sudo access."
    exit 1
fi

# Variables
VSCODE_EXTENSIONS_DIR="$HOME/.vscode/extensions"
WORKSPACE_EXTENSIONS_PATH="/workspace/vscode-extensions"

# Function to find executable files in extension directories
find_executables() {
    local ext_dir="$1"
    find "$ext_dir" -type f -executable 2>/dev/null || true
}

# Function to fix a specific extension
fix_extension() {
    local ext_path="$1"
    local ext_name=$(basename "$ext_path")
    local workspace_ext_path="$WORKSPACE_EXTENSIONS_PATH/$ext_name"

    echo "Processing extension: $ext_name"

    # Find executable files in the extension
    local executables=($(find_executables "$ext_path"))

    if [[ ${#executables[@]} -eq 0 ]]; then
        echo "  No executable files found in $ext_name, skipping..."
        return 0
    fi

    echo "  Found ${#executables[@]} executable file(s):"
    for exec_file in "${executables[@]}"; do
        echo "    - $(basename "$exec_file")"
    done

    # Create workspace directory for this extension
    echo "  Creating workspace directory..."
    sudo mkdir -p "$workspace_ext_path"

    # Copy the entire extension directory to workspace
    echo "  Copying extension files to workspace..."
    sudo cp -r "$ext_path"/* "$workspace_ext_path/"

    # Fix ownership and permissions
    echo "  Setting correct ownership and permissions..."
    sudo chown -R "$USER:$(id -gn)" "$workspace_ext_path"
    sudo chmod -R 755 "$workspace_ext_path"

    # Create symbolic links for each executable
    for exec_file in "${executables[@]}"; do
        local relative_path="${exec_file#$ext_path/}"
        local original_file="$ext_path/$relative_path"
        local workspace_file="$workspace_ext_path/$relative_path"

        # Backup original file if it exists and isn't already a symlink
        if [[ -f "$original_file" && ! -L "$original_file" ]]; then
            echo "  Backing up $(basename "$original_file")..."
            sudo mv "$original_file" "${original_file}.backup"
        fi

        # Create symbolic link
        echo "  Creating symbolic link for $(basename "$original_file")..."
        sudo ln -sf "$workspace_file" "$original_file"
    done

    # Test one of the executables to verify the fix
    local test_exec="${executables[0]}"
    local workspace_test_exec="$workspace_ext_path/${test_exec#$ext_path/}"

    if [[ -x "$workspace_test_exec" ]]; then
        echo "  ✅ Extension $ext_name fixed successfully!"
        return 0
    else
        echo "  ❌ Fix verification failed for $ext_name"
        return 1
    fi
}

echo "Checking for VS Code extension EACCESS issues..."

# Check if VS Code extensions directory exists
if [[ ! -d "$VSCODE_EXTENSIONS_DIR" ]]; then
    echo "❌ VS Code extensions directory not found: $VSCODE_EXTENSIONS_DIR"
    echo "Make sure VS Code is installed and has extensions."
    exit 1
fi

# Check if /home is mounted with noexec
if ! mount | grep -q "/home.*noexec"; then
    echo "✅ /home directory allows execution, extensions should work normally."
    echo "The EACCESS issue may be caused by something else."
    exit 0
fi

echo "/home directory has noexec mount option, scanning for extensions with executables..."

# Allow user to specify extension(s) or scan all
if [[ $# -gt 0 ]]; then
    # Process specific extensions provided as arguments
    echo "Processing specified extensions: $*"
    for ext_pattern in "$@"; do
        found_extensions=($(compgen -G "$VSCODE_EXTENSIONS_DIR/$ext_pattern" 2>/dev/null || true))
        if [[ ${#found_extensions[@]} -eq 0 ]]; then
            echo "❌ No extensions found matching pattern: $ext_pattern"
            continue
        fi

        for ext_path in "${found_extensions[@]}"; do
            if [[ -d "$ext_path" ]]; then
                fix_extension "$ext_path"
            fi
        done
    done
else
    # Scan all extensions for executable files
    echo "Scanning all extensions for executable files..."
    extensions_with_executables=()

    for ext_path in "$VSCODE_EXTENSIONS_DIR"/*; do
        if [[ -d "$ext_path" ]]; then
            local executables=($(find_executables "$ext_path"))
            if [[ ${#executables[@]} -gt 0 ]]; then
                extensions_with_executables+=("$ext_path")
            fi
        fi
    done

    if [[ ${#extensions_with_executables[@]} -eq 0 ]]; then
        echo "✅ No extensions with executable files found."
        exit 0
    fi

    echo "Found ${#extensions_with_executables[@]} extension(s) with executable files:"
    for ext_path in "${extensions_with_executables[@]}"; do
        echo "  - $(basename "$ext_path")"
    done

    echo ""
    read -p "Do you want to fix all these extensions? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi

    # Fix all extensions with executables
    fixed_count=0
    for ext_path in "${extensions_with_executables[@]}"; do
        echo ""
        if fix_extension "$ext_path"; then
            ((fixed_count++))
        fi
    done

    echo ""
    echo "✅ Fixed $fixed_count out of ${#extensions_with_executables[@]} extensions."
fi

echo ""
echo "Fix complete! Restart VS Code to apply changes."
echo ""
echo "Usage examples:"
echo "  $0                                    # Scan and fix all extensions"
echo "  $0 'ms-azuretools.*'                 # Fix Azure tools extensions"
echo "  $0 'ms-python.*' 'ms-vscode.*'       # Fix specific extension patterns"
echo ""
echo "If you continue to have issues:"
echo "1. Restart VS Code completely"
echo "2. Check VS Code extension settings for custom server paths"
echo "3. Verify the extensions are enabled"
