#!/bin/bash

# Script to compare package availability between two Ubuntu/Debian releases
# Usage: ./compare_packages.sh [package_list_file]

# Default variables
OLD_DISTRO="ubuntu"        # Old distribution: ubuntu or debian
NEW_DISTRO="ubuntu"        # New distribution: ubuntu or debian
OLD_CODENAME="trusty"      # Old release codename
NEW_CODENAME="noble"       # New release codename
ARCH="amd64"               # Architecture
OUTPUT_DIR="./package_comparison_results"
TEMP_DIR="/tmp/pkg_compare_$"  # Temp directory with PID to avoid conflicts

# Files for results
PACKAGES_EXIST="${OUTPUT_DIR}/packages_exist.txt"
PACKAGES_NOT_EXIST="${OUTPUT_DIR}/packages_not_exist.txt"
PACKAGES_DIFFERENT="${OUTPUT_DIR}/packages_different_version.txt"
PACKAGES_REPLACEMENTS="${OUTPUT_DIR}/packages_replacements.txt"

# Help function
function show_help() {
    echo "Usage: $0 [OPTIONS] [package_list_file]"
    echo
    echo "Compare package availability between two distributions/releases"
    echo
    echo "Options:"
    echo "  -h, --help                   Show this help message"
    echo "  -d1, --old-distro DISTRO     Set old distribution (ubuntu or debian)"
    echo "  -d2, --new-distro DISTRO     Set new distribution (ubuntu or debian)"
    echo "  -o, --old CODENAME           Set old release codename"
    echo "  -n, --new CODENAME           Set new release codename"
    echo "  -a, --arch ARCHITECTURE      Set architecture (default: amd64)"
    echo "  -O, --output-dir DIRECTORY   Set output directory"
    echo
    echo "If package_list_file is not provided, packages will be read from stdin"
    echo "Each line in the file should contain a single package name"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -d1|--old-distro)
            OLD_DISTRO="$2"
            shift 2
            ;;
        -d2|--new-distro)
            NEW_DISTRO="$2"
            shift 2
            ;;
        -o|--old)
            OLD_CODENAME="$2"
            shift 2
            ;;
        -n|--new)
            NEW_CODENAME="$2"
            shift 2
            ;;
        -a|--arch)
            ARCH="$2"
            shift 2
            ;;
        -O|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            show_help
            ;;
        *)
            PACKAGE_LIST_FILE="$1"
            shift
            ;;
    esac
done

# Clean up function
function cleanup() {
    echo "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Register cleanup function to run on exit
trap cleanup EXIT

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"
mkdir -p "$TEMP_DIR"

# Check if required tools are installed
if ! command -v wget &> /dev/null || ! command -v apt-cache &> /dev/null; then
    echo "Error: This script requires wget and apt-cache. Please install them."
    exit 1
fi

# Clean output files
> "$PACKAGES_EXIST"
> "$PACKAGES_NOT_EXIST"
> "$PACKAGES_DIFFERENT"
> "$PACKAGES_REPLACEMENTS"

# Double check files were created properly
if [[ ! -f "$PACKAGES_EXIST" || ! -f "$PACKAGES_NOT_EXIST" || ! -f "$PACKAGES_DIFFERENT" || ! -f "$PACKAGES_REPLACEMENTS" ]]; then
    echo "Error: Failed to create output files in $OUTPUT_DIR"
    echo "Check if you have write permissions in this directory."
    exit 1
fi

# Function to download package lists
function download_package_lists() {
    local distro=$1
    local codename=$2
    local components
    local mirror
    
    if [ "$distro" == "ubuntu" ]; then
        mirror="http://archive.ubuntu.com/ubuntu"
        components="main universe multiverse restricted"
    else
        mirror="http://ftp.debian.org/debian"
        components="main contrib non-free"
        # For newer Debian versions with non-free-firmware
        if [[ "$codename" == "bookworm" || "$codename" == "trixie" || "$codename" == "sid" ]]; then
            components="$components non-free-firmware"
        fi
    fi
    
    echo "Downloading package lists for $distro $codename..."
    
    for component in $components; do
        local packages_url="${mirror}/dists/${codename}/${component}/binary-${ARCH}/Packages.gz"
        
        echo "Fetching $packages_url..."
        if ! wget -q "$packages_url" -O "${TEMP_DIR}/${distro}_${codename}_${component}_Packages.gz"; then
            echo "Warning: Failed to download package list from $packages_url"
            continue
        fi
        
        # Extract package names and versions
        gunzip -c "${TEMP_DIR}/${distro}_${codename}_${component}_Packages.gz" | awk -v file="${TEMP_DIR}/${distro}_${codename}_packages.list" '
            /^Package:/ {package=$2}
            /^Version:/ {version=$2; print package " " version >> file}
            /^Provides:/ {provides=$0; gsub(/^Provides: /, "", provides); print "PROVIDES " package " " provides >> file}
        '
    done
    
    # Check if we got any packages
    if [ ! -f "${TEMP_DIR}/${distro}_${codename}_packages.list" ] || [ ! -s "${TEMP_DIR}/${distro}_${codename}_packages.list" ]; then
        echo "Error: Failed to get any package information for $distro $codename"
        echo "Check if the codename is correct and the repository is accessible."
        exit 1
    fi
    
    echo "Retrieved $(grep -v "^PROVIDES" ${TEMP_DIR}/${distro}_${codename}_packages.list | wc -l) packages for $distro $codename"
    
    # Create name-based pattern index for replacement detection
    if [ "$distro" == "$NEW_DISTRO" ] && [ "$codename" == "$NEW_CODENAME" ]; then
        echo "Creating package name pattern index for $distro $codename..."
        grep -v "^PROVIDES" "${TEMP_DIR}/${distro}_${codename}_packages.list" | cut -d' ' -f1 > "${TEMP_DIR}/${distro}_${codename}_package_names.list"
    fi
}

# Function to get package version from list
function get_package_version() {
    local package=$1
    local distro=$2
    local codename=$3
    
    # Check if the package list exists
    if [ ! -f "${TEMP_DIR}/${distro}_${codename}_packages.list" ]; then
        echo ""
        return
    fi
    
    # Look for the package in the list and get its version
    local version=$(grep "^$package " "${TEMP_DIR}/${distro}_${codename}_packages.list" | head -1 | awk '{print $2}')
    echo "$version"
}

# Function to find possible replacement packages
function find_replacement() {
    local package=$1
    local possible_replacements=""
    
    # First check if any package provides this one
    local providers=$(grep "^PROVIDES" "${TEMP_DIR}/${NEW_DISTRO}_${NEW_CODENAME}_packages.list" | grep -i " $package[, ]" | cut -d' ' -f2)
    if [ -n "$providers" ]; then
        possible_replacements="$providers"
    fi
    
    # Extract base name without version numbers (e.g., libplist3 -> libplist)
    local base_name=$(echo "$package" | sed -E 's/([a-zA-Z-]+)[0-9.]*$/\1/')
    if [ "$base_name" != "$package" ]; then
        # Find packages that start with the same base name
        local similar_packages=$(grep -i "^$base_name" "${TEMP_DIR}/${NEW_DISTRO}_${NEW_CODENAME}_package_names.list")
        if [ -n "$similar_packages" ]; then
            if [ -n "$possible_replacements" ]; then
                possible_replacements="$possible_replacements $similar_packages"
            else
                possible_replacements="$similar_packages"
            fi
        fi
    fi
    
    # Special cases for common library transitions
    if [[ "$package" == libc5* ]]; then
        local libc6_packages=$(grep "^libc6" "${TEMP_DIR}/${NEW_DISTRO}_${NEW_CODENAME}_package_names.list")
        if [ -n "$libc6_packages" ]; then
            if [ -n "$possible_replacements" ]; then
                possible_replacements="$possible_replacements $libc6_packages"
            else
                possible_replacements="$libc6_packages"
            fi
        fi
    fi
    
    # Return unique list of possible replacements
    echo "$possible_replacements" | tr ' ' '\n' | sort | uniq | tr '\n' ' '
}

# Function to compare package versions
function compare_package() {
    local package=$1
    
    echo -n "Checking package $package... "
    
    # Get versions from package lists
    local old_version=$(get_package_version "$package" "$OLD_DISTRO" "$OLD_CODENAME")
    local new_version=$(get_package_version "$package" "$NEW_DISTRO" "$NEW_CODENAME")
    
    # Compare results
    if [ -n "$new_version" ]; then
        if [ -n "$old_version" ]; then
            if [ "$old_version" = "$new_version" ]; then
                echo "EXISTS in both (same version: $new_version)"
                echo "$package ($new_version)" >> "$PACKAGES_EXIST"
            else
                echo "EXISTS in both (different version: $old_version -> $new_version)"
                echo "$package ($old_version -> $new_version)" >> "$PACKAGES_DIFFERENT"
            fi
        else
            echo "EXISTS only in $NEW_DISTRO $NEW_CODENAME (version: $new_version)"
            echo "$package (only in $NEW_DISTRO $NEW_CODENAME, version: $new_version)" >> "$PACKAGES_EXIST"
        fi
    else
        if [ -n "$old_version" ]; then
            echo -n "NOT FOUND in $NEW_DISTRO $NEW_CODENAME (was in $OLD_DISTRO $OLD_CODENAME with version: $old_version)"
            echo "$package (was in $OLD_DISTRO $OLD_CODENAME with version: $old_version)" >> "$PACKAGES_NOT_EXIST"
            
            # Find potential replacements
            local replacements=$(find_replacement "$package")
            if [ -n "$replacements" ]; then
                echo " - Potential replacements: $replacements"
                echo "$package -> $replacements" >> "$PACKAGES_REPLACEMENTS"
            else
                echo ""  # Just a newline if no replacements found
            fi
        else
            echo "NOT FOUND in either release"
            echo "$package (not found in either release)" >> "$PACKAGES_NOT_EXIST"
        fi
    fi
}

# Main execution
echo "Comparing packages from $OLD_DISTRO $OLD_CODENAME to $NEW_DISTRO $NEW_CODENAME"
echo "Results will be saved in $OUTPUT_DIR"
echo

# Download package lists
download_package_lists "$OLD_DISTRO" "$OLD_CODENAME"
download_package_lists "$NEW_DISTRO" "$NEW_CODENAME"

# Process packages
if [ -n "$PACKAGE_LIST_FILE" ]; then
    if [ ! -f "$PACKAGE_LIST_FILE" ]; then
        echo "Error: Package list file '$PACKAGE_LIST_FILE' not found."
        exit 1
    fi
    
    echo "Reading packages from $PACKAGE_LIST_FILE"
    while IFS= read -r package; do
        # Skip empty lines and comments
        if [ -n "$package" ] && [[ ! "$package" =~ ^\s*# ]]; then
            compare_package "$package"
        fi
    done < "$PACKAGE_LIST_FILE"
else
    echo "Reading packages from stdin (one package per line, Ctrl+D to finish):"
    while IFS= read -r package; do
        if [ -n "$package" ]; then
            compare_package "$package"
        fi
    done
fi

# Print summary
exist_count=$(wc -l < "$PACKAGES_EXIST")
not_exist_count=$(wc -l < "$PACKAGES_NOT_EXIST")
different_count=$(wc -l < "$PACKAGES_DIFFERENT")
replacement_count=$(wc -l < "$PACKAGES_REPLACEMENTS")
total_count=$((exist_count + not_exist_count + different_count))

echo
echo "Summary:"
echo "- Total packages checked: $total_count"
echo "- Packages exist in $NEW_DISTRO $NEW_CODENAME: $exist_count"
echo "- Packages exist with different version in $NEW_DISTRO $NEW_CODENAME: $different_count"
echo "- Packages NOT exist in $NEW_DISTRO $NEW_CODENAME: $not_exist_count"
echo "- Packages with potential replacements identified: $replacement_count"
echo
echo "Detailed results:"
echo "- Packages that exist: $PACKAGES_EXIST"
echo "- Packages with different versions: $PACKAGES_DIFFERENT"
echo "- Packages that don't exist: $PACKAGES_NOT_EXIST"
echo "- Packages with potential replacements: $PACKAGES_REPLACEMENTS"
