#!/bin/bash

# Script to extract dependencies from local .deb packages
# Usage: ./deb-dependency-extractor.sh [--dist DISTRIBUTION] [--release RELEASE] [--direct-only] /path/to/packages/*.deb

set -e

# Default values
DISTRIBUTION=""
RELEASE=""
DIRECT_ONLY=false
PACKAGE_FILES=()
TEMP_DIR=$(mktemp -d)
OUTPUT_FILE="dependencies.list"
SEEN_PACKAGES=()

# Function to clean up temporary files
cleanup() {
    echo "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Register cleanup function to run on exit
trap cleanup EXIT

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dist)
            DISTRIBUTION="$2"
            shift 2
            ;;
        --release)
            RELEASE="$2"
            shift 2
            ;;
        --direct-only)
            DIRECT_ONLY=true
            shift
            ;;
        *)
            # Assume all other arguments are .deb files
            if [[ "$1" == *.deb ]]; then
                PACKAGE_FILES+=("$1")
            else
                echo "Warning: Ignoring non-deb file: $1"
            fi
            shift
            ;;
    esac
done

# Check if we have any package files
if [ ${#PACKAGE_FILES[@]} -eq 0 ]; then
    echo "Error: No .deb package files provided"
    echo "Usage: $0 [--dist DISTRIBUTION] [--release RELEASE] [--direct-only] /path/to/packages/*.deb"
    exit 1
fi

# Detect distribution and release if not explicitly provided
if [ -z "$DISTRIBUTION" ] || [ -z "$RELEASE" ]; then
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [ -z "$DISTRIBUTION" ]; then
            DISTRIBUTION=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        fi
        if [ -z "$RELEASE" ]; then
            RELEASE=$(echo "$VERSION_CODENAME" | tr '[:upper:]' '[:lower:]')
            # If VERSION_CODENAME is not available, try VERSION_ID
            if [ -z "$RELEASE" ]; then
                RELEASE="$VERSION_ID"
            fi
        fi
    else
        echo "Error: Unable to detect distribution and release. Please provide them using --dist and --release options."
        exit 1
    fi
fi

echo "Working with distribution: $DISTRIBUTION, release: $RELEASE"
echo "Direct-only mode: $DIRECT_ONLY"

# Extract package names from local deb files to exclude from final output
ORIGINAL_PACKAGES=()
for pkg in "${PACKAGE_FILES[@]}"; do
    PKG_NAME=$(dpkg-deb -f "$pkg" Package)
    if [ -n "$PKG_NAME" ]; then
        ORIGINAL_PACKAGES+=("$PKG_NAME")
        echo "Added original package: $PKG_NAME"
    else
        echo "Warning: Couldn't extract package name from $pkg"
    fi
done

# Function to get direct dependencies for a package
get_dependencies() {
    local package_name=$1
    local deps_string=""
    
    # Check if it's a local file or a repository package
    if [[ "$package_name" == *.deb ]]; then
        # It's a local file
        deps_string=$(dpkg-deb -f "$package_name" Depends)
    else
        # It's a repository package - use apt-cache
        deps_string=$(apt-cache show "$package_name" 2>/dev/null | grep -m 1 '^Depends:' | cut -d ':' -f 2-)
    fi
    
    # Parse the dependencies string to extract package names
    if [ -n "$deps_string" ]; then
        echo "$deps_string" | tr ',' '\n' | sed -E 's/([a-zA-Z0-9.+-]+)(\s*\([^)]*\))?(\s*\[[^]]*\])?/\1/g' | tr -d ' '
    fi
}

# Function to process a package recursively
process_package() {
    local package=$1
    local pkg_name=""
    
    # If it's a .deb file, extract the package name
    if [[ "$package" == *.deb ]]; then
        pkg_name=$(dpkg-deb -f "$package" Package)
    else
        pkg_name="$package"
    fi
    
    # Skip if we've already processed this package
    for seen in "${SEEN_PACKAGES[@]}"; do
        if [ "$seen" == "$pkg_name" ]; then
            return
        fi
    done
    
    # Add to seen packages to avoid cycles
    SEEN_PACKAGES+=("$pkg_name")
    
    # Get dependencies
    local dependencies=$(get_dependencies "$package")
    
    # Process each dependency recursively
    while read -r dep; do
        if [ -n "$dep" ]; then
            # Skip virtual packages (contains |)
            if [[ "$dep" != *"|"* ]]; then
                # Add to output file if not an original package
                is_original=0
                for orig in "${ORIGINAL_PACKAGES[@]}"; do
                    if [ "$orig" == "$dep" ]; then
                        is_original=1
                        break
                    fi
                done
                
                if [ $is_original -eq 0 ]; then
                    echo "$dep" >> "$TEMP_DIR/$OUTPUT_FILE"
                fi
                
                # Process this dependency recursively
                process_package "$dep"
            fi
        fi
    done <<< "$dependencies"
}

# Make sure the apt cache is up to date
echo "Updating apt cache..."
sudo apt-get update -qq

# Process packages based on mode (direct-only or recursive)
echo "Processing packages and their dependencies..."

if [ "$DIRECT_ONLY" = true ]; then
    echo "Mode: Direct dependencies only"
    # Process direct dependencies only
    for pkg in "${PACKAGE_FILES[@]}"; do
        echo "Processing $pkg..."
        pkg_name=$(dpkg-deb -f "$pkg" Package)
        deps=$(get_dependencies "$pkg")
        
        while read -r dep; do
            if [ -n "$dep" ]; then
                # Skip virtual packages (contains |)
                if [[ "$dep" != *"|"* ]]; then
                    # Skip if it's an original package
                    is_original=0
                    for orig in "${ORIGINAL_PACKAGES[@]}"; do
                        if [ "$orig" == "$dep" ]; then
                            is_original=1
                            break
                        fi
                    done
                    
                    if [ $is_original -eq 0 ]; then
                        echo "$dep" >> "$TEMP_DIR/$OUTPUT_FILE"
                    fi
                fi
            fi
        done <<< "$deps"
    done
else
    echo "Mode: Recursive dependencies"
    # Process recursive dependencies
    for pkg in "${PACKAGE_FILES[@]}"; do
        echo "Processing $pkg..."
        process_package "$pkg"
    done
fi

# Remove duplicates and sort the output
if [ -f "$TEMP_DIR/$OUTPUT_FILE" ]; then
    sort -u "$TEMP_DIR/$OUTPUT_FILE" > "$OUTPUT_FILE"
    echo "Dependency list written to $OUTPUT_FILE"
    echo "Found $(wc -l < "$OUTPUT_FILE") unique dependencies"
else
    echo "No dependencies found"
    touch "$OUTPUT_FILE"
fi

echo "Done!"
