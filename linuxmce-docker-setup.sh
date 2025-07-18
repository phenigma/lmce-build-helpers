#!/bin/bash
#
# LinuxMCE Docker Setup Script
# License GPL v3
#
# Purpose: Set up a Docker-based build environment for LinuxMCE with repository mapping
# Can run headless or with user input

set -e

# Get host UID/GID for setting user/group for host volume files.
HOST_UID=$(id -u)
HOST_GID=$(id -g)

# Default config values
OS="ubuntu"
VERSION="noble"
ARCH="amd64"

# Set the default git branch to checkout/build.
BRANCH="master"

# Uncomment to use an apt-proxy inside the container
#APT_PROXY="http://192.168.2.60:3142"

# Set the runtime dir for mysql inside the container if using myql on HOST to share the DB.
MYSQL_RUN="/run/mysqld"



###################### Common builder configurations ######################
# ## COMMON CONFIGURATIONS ##
# ## Ubuntu Builds ###
# OS="ubuntu"; VERSION="trusty"; ARCH="amd64"; BRANCH="ubuntu-trusty";	## 1404
# OS="ubuntu"; VERSION="trusty"; ARCH="armhf"; BRANCH="ubuntu-trusty";	## 1404
# OS="ubuntu"; VERSION="xenial"; ARCH="amd64"; BRANCH="ubuntu-trusty";	## 1604
# OS="ubuntu"; VERSION="xenial"; ARCH="armhf"; BRANCH="ubuntu-trusty";	## 1604
# OS="ubuntu"; VERSION="bionic"; ARCH="amd64";	## 1804
# OS="ubuntu"; VERSION="bionic"; ARCH="armhf";	## 1804
# OS="ubuntu"; VERSION="noble"; ARCH="amd64";
# OS="ubuntu"; VERSION="noble"; ARCH="arm64";

# ### RPI Builds - raspbian until buster, debian from bookworm on ###
# OS="raspbian"; VERSION="wheezy"; ARCH="armhf"; BRANCH="ubuntu-trusty"; SOURCES="raspbian";	## unsupported by docker
# OS="raspbian"; VERSION="jessie"; ARCH="armhf"; BRANCH="ubuntu-trusty"; SOURCES="raspbian";	## 32-bit arm
# OS="raspbian"; VERSION="stretch"; ARCH="armhf"; BRANCH="ubuntu-trusty"; SOURCES="raspbian";	## 32-bit arm
# OS="raspbian"; VERSION="buster"; ARCH="armhf"; BRANCH="ubuntu-trusty"; SOURCES="rpios";	## 32-bit arm
# OS="debian"; VERSION="bookworm"; ARCH="arm64"; BRANCH="master"; SOURCES="rpios";	## R12/2023 Needs tlc and DB updates

# ### Debian Builds ###
# OS="debian"; VERSION="bookworm"; ARCH="amd64"; BRANCH="master";	## R12/2023 Needs tlc and DB updates
# OS="debian"; VERSION="bookworm"; ARCH="arm64"; BRANCH="master";	## R12/2023 Needs tlc and DB updates



###################### User feedback functions ######################
# Parse command line arguments
function print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --headless           Run in headless mode without user prompts (default)"
    echo "  --interactive        Run in in interactive mode with user prompts for mounts (default)"
    echo "  --base-dir DIR       Set the base directory where builders will be located (default: $HOME/linuxmce-docker)"
    echo "  --os NAME            Set the Operating System name (default: ubuntu)"
    echo "  --version VER        Set OS version for Docker image (default: $VERSION)"
    echo "  --arch ARCH          Set arch for Docker image (default: $ARCH)"
    echo "  --sources NAME       Add additional source locations (defult: N/A, optional: raspbian|rpios)"
    echo "  --help               Show this help message"
    echo ""
    echo " This script will check for directories named 'LinuxMCE' and 'Ubuntu_Helpers_NoHardcode' in $HOME"
    echo " If found they will be checked for the lmce git repo, and if found it will be used as a shared"
    echo " copy of the build scripts. Multiple docker based builders will share this set of build scripts."
    echo ""
    echo " Specifying --sources allows choosing the old raspbian sources, or the new native debian rpios."
    echo " Note: This is for RPI builds only, other arm builds should not use this option."

   exit 1
}

# Print colored messages
print_info() {
    echo -e "\e[1;34m[INFO] $1\e[0m" >&2
}

print_success() {
    echo -e "\e[1;32m[SUCCESS] $1\e[0m" >&2
}

print_error() {
    echo -e "\e[1;31m[ERROR] $1\e[0m" >&2
}



###################### Check cmdline options ######################
# Parse command line options
HEADLESS=true
while [[ $# -gt 0 ]]; do
    case $1 in
        --headless)
            HEADLESS=true
            shift
            ;;
        --interactive)
            HEADLESS=false
            shift
            ;;
        --base-dir)
            BASE_DIR="$2"
            shift 2
            ;;
        --os)
            OS="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --sources)
            SOURCES="$2"
            shift 2
            ;;
        --help)
            print_usage
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            ;;
    esac
done



###################### Set project name ######################
PROJECT_NAME="linuxmce-$OS-$VERSION-$ARCH"
[ -n "$SOURCES" ] && PROJECT_NAME="${PROJECT_NAME}-${SOURCES}"  # Add identifier for variant (raspbian/rpios)



###################### Check for root ######################
# Check if running as root
if [ "$(id -u)" -eq 0 ]; then
    print_error "Please do not run this script as root or with sudo."
    print_info "The script will prompt for sudo password when needed."
    exit 1
fi



###################### Check for Debian ######################
# Check for Debian
if [ ! -f /etc/debian_version ]; then
    print_error "This script is designed for Debian systems only."
    exit 1
fi



###################### Check for required variables ######################
if [[ -z "$ARCH" || -z "$OS" || -z "$VERSION" || -z "$BRANCH" ]]; then
    echo "Usage: $0 <arch: amd64|i386|armhf|arm64> <os: ubuntu|debian> <version: bullseye|focal|...> <branch: master|ubunty-trusty|...>"
    exit 1
fi



###################### Docker Arch mappings ######################
# Mapping for Docker image platforms
case "$ARCH" in
  amd64)  PLATFORM="linux/amd64";;
  i386)   PLATFORM="linux/386";;
  armhf)  PLATFORM="linux/arm/v7";;
  arm64)  PLATFORM="linux/arm64";;
  *) echo "Unsupported architecture: $ARCH"; exit 1;;
esac



###################### Setup directories ######################
print_info "Starting LinuxMCE build environment setup..."

# Locations within the container
BUILDER_WORKDIR=${BUILDER_WORKDIR:-/var/lmce-build}
BUILDER_BUILD_SCRIPTS=${BUILDER_BUILD_SCRIPTS:-/root/Ubuntu_Helpers_NoHardcode}

# Project directory setup
BASE_DIR=${BASE_DIR:-$HOME/linuxmce-docker}
PROJECT_DIR="$BASE_DIR/$PROJECT_NAME"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR
print_info "Project directory: $PROJECT_DIR"

# Create build directory
mkdir -p $PROJECT_DIR/lmce-build
print_info "Project build directory: $PROJECT_DIR/lmce_build"



###################### Get Docker on host ######################
print_info "Checking for Docker from official sources..."
# Check for docker keyring, get it if it doesn't exist
if [ ! -f "/etc/apt/keyrings/docker.asc" ] || [ ! -s "/etc/apt/keyrings/docker.asc" ]; then
	print_info "Installing Docker from official sources..."
	print_info "Installing Docker official source certificates in apt..."
	sudo apt-get update
	sudo apt-get install -y ca-certificates curl
	sudo install -m 0755 -d /etc/apt/keyrings
	sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	sudo chmod a+r /etc/apt/keyrings/docker.asc
fi

# Check for docker apt source, add it if it doesn't exist
if [ ! -f "/etc/apt/sources.list.d/docker.list" ] || [ ! -s "/etc/apt/sources.list.d/docker.list" ]; then
	print_info "Adding Docker official repository to apt..."
	# Add the repository to Apt sources:
	echo \
	  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
	  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
	  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
	sudo apt-get update
fi

check_and_install() {
	local missing_pkgs=""

	for pkg in "$@"; do
		if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
			missing_pkgs="$missing_pkgs $pkg"
		fi
	done

	if [ -n "$missing_pkgs" ]; then
		print_info "Installing packages..."
		sudo apt-get update
		sudo apt-get -y install $missing_pkgs
	fi
}
# Check for and install Docker packages
print_info "Checking for Docker packages..."
check_and_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Check if the current use is a member of the docker group, add to group if not
print_info "Checking if $USER is a member of the the docker group."
if ! id -nG "$USER" | grep -qw "docker"; then
	# Add current user to docker group
	sudo usermod -aG docker $USER
	print_info "Added $USER to the docker group. You may need to log out and back in for this to take effect."
fi

# Pull raspbian base images from docker hub - jessie and stretch are available.
if [ "$OS" = "raspbian" ]; then
    docker pull ${OS}/${VERSION} 
fi



###################### Volume Mapping - sources & mysql ######################
# Arrays to store repository mappings
REPO_MAPPINGS_LIST=()

if $HEADLESS; then
    print_info "Running in headless mode"
fi

# Function to find repositories
find_repositories() {
    print_info "Searching for LinuxMCE repositories in $HOME..."

    # Arrays to store found repositories
    declare -a FOUND_REPOS=()

    # Common repository names to search for
    REPO_NAMES=("LinuxMCE" "Ubuntu_Helpers_NoHardcode")

    # Search for each repository
    for REPO_NAME in "${REPO_NAMES[@]}"; do
        FOUND_PATHS=$(find $HOME -type d -name "$REPO_NAME" -o -name "$REPO_NAME.git" 2>/dev/null)

        # Add each found path to our array
        while IFS= read -r path; do
            if [ -n "$path" ]; then
                if [ -d "$path/.git" ] || [ "${path##*.}" == "git" ]; then
                    FOUND_REPOS+=("$path")
                    print_info "Found repository: $path"
                fi
            fi
        done <<< "$FOUND_PATHS"
    done

    # Return the found repositories
    echo "${FOUND_REPOS[@]}"
}

# Function to setup repository mappings
setup_repo_mappings() {
    local repos=("$@")

    if [ ${#repos[@]} -eq 0 ]; then
        print_info "No repositories found in $HOME directory."
        return
    fi

    for repo in "${repos[@]}"; do
        if [ -n "$repo" ]; then
            if $HEADLESS; then
                # In headless mode, map all found repositories automatically
                repo_name=$(basename "$repo")
                REPO_MAPPINGS_LIST+=("      - $repo:/root/$repo_name:rw")	# this will mount over (mask) the internal container initial checkout
                print_info "Mapping: $repo -> /root/$repo_name"
               	#REPO_MAPPINGS_LIST+=("      - $repo:$BUILDER_WORKDIR/$repo_name:rw")
                #print_info "Mapping: $repo -> $BUILDER_WORKDIR/$repo_name"
            else
                # In interactive mode, ask for confirmation
                read -p "Map repository $repo to Docker? (y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    read -p "Enter target path in Docker container (default: $BUILDER_WORKDIR/$(basename "$repo")): " target_path
                    target_path=${target_path:-$BUILDER_WORKDIR/$(basename "$repo")}
                    REPO_MAPPINGS_LIST+=("      - $repo:$target_path:rw")
                    print_info "Added mapping: $repo -> $target_path"
                fi
            fi
        fi
    done
}

# Function to add a single repository mapping
add_repo_mapping() {
    local repo_path="$1"
    local target_path="$2"

    REPO_MAPPINGS_LIST+=("      - $repo_path:$target_path:rw")
    print_info "Added mapping: $repo_path -> $target_path"
}

# Function to setup MySQL mapping
setup_mysql_mapping() {
    local mysql_mapping=""

    if $HEADLESS; then
        # In headless mode, don't map MySQL unless specified by environment variable
        if [ -n "$MYSQL_DIR" ] && [ -d "$MYSQL_DIR" ]; then
            mysql_mapping="      - $MYSQL_DIR:/var/lib/mysql:rw"
            print_info "Mapping MySQL data: $MYSQL_DIR -> /var/lib/mysql"
	else
	    if [ -n "$MYSQL_RUN" ] && [ -d "$MYSQL_RUN" ]; then
	        mysql_mapping="      - $MYSQL_RUN:/run/mysqld:rw"
	        print_info "Mapping MySQL runtime: $MYSQL_RUN -> /run/mysqld"
	    fi
        fi
    else
        # In interactive mode, ask if MySQL data directory mapping is needed
        read -p "Do you have MySQL data that needs to be mapped to Docker? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            read -p "Enter path to MySQL data directory: " mysql_dir
            if [ -d "$mysql_dir" ]; then
                mysql_mapping="      - $mysql_dir:/var/lib/mysql:rw"
                print_info "Added MySQL mapping: $mysql_dir -> /var/lib/mysql"
            else
                print_error "Directory $mysql_dir does not exist. MySQL mapping not added."
            fi
        else
            # In interactive mode, ask if MySQL runtime directory mapping is needed
            read -p "Do you have MySQL runtime directory to be mapped to Docker? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                read -p "Enter path to MySQL runtime directory: " mysql_run
                if [ -d "$mysql_run" ]; then
                    mysql_mapping="      - $mysql_run:/run/mysqld:rw"
                    print_info "Added MySQL runtime mapping: $mysql_run -> /run/mysqld"
                else
                    print_error "Directory $mysql_run does not exist. MySQL mapping not added."
                fi
            fi
        fi
    fi
    # Return the MySQL mapping
    echo -e "$mysql_mapping"
}

# Main logic for locating/setting up mappings to host repositories (source dirs)
if $HEADLESS; then
    # Headless mode - use environment variables or defaults
    if [ -z "$REPOS" ]; then
        # If REPOS env var isn't set, try to find repositories
        mapfile -t found_repos < <(find_repositories)
        setup_repo_mappings "${found_repos[@]}"
    else
        # Use provided REPOS env var (comma-separated list)
        IFS=',' read -ra repo_list <<< "$REPOS"
        setup_repo_mappings "${repo_list[@]}"
    fi

    # Setup MySQL mapping if env var is set
    if [ -n "$MYSQL_DIR" ] || [ -n "$MYSQL_RUN" ]; then
        MYSQL_MAPPING=$(setup_mysql_mapping)
    fi
else
    # Interactive mode - query the user
    print_info "Welcome to the LinuxMCE Docker Setup Script"
    print_info "This script will set up a Docker environment for LinuxMCE development."

    # Find and map repositories
    mapfile -t found_repos < <(find_repositories)
    setup_repo_mappings "${found_repos[@]}"

    # Setup MySQL mapping
    MYSQL_MAPPING=$(setup_mysql_mapping)

    # Ask for any additional repositories
    read -p "Would you like to map any additional repositories? (y/n): " add_more
    if [[ "$add_more" =~ ^[Yy]$ ]]; then
        while true; do
            read -p "Enter repository path (or 'done' to finish): " repo_path
            if [ "$repo_path" == "done" ]; then
                break
            fi

            if [ -d "$repo_path" ]; then
                read -p "Enter target path in Docker container: " target_path
                add_repo_mapping "$repo_path" "$target_path"
            else
                print_error "Directory $repo_path does not exist."
            fi
        done
    fi
fi



###################### Add RPIOS sources ######################
add_raspi_repo() {
    local version="$1"

    # Raspberry Pi OS Bookworm
    # Rapsberry Pi arm64
    # deb https://archive.raspberrypi.com/debian/ bookworm main untested
    # Raspberry Pi armhf
    # deb http://raspbian.raspberrypi.com/raspbian/ bookworm main contrib non-free rpi
    if [ "$SOURCES" = "rpios" ]; then
        if [ "$ARCH" = "arm64" ]; then
	    # arm64 (64-bit modern)
            local repo_url="http://archive.raspberrypi.org/debian/"
            local components="main untested"
        else
	    # armhf (32-bit modern)
            local repo_url="http://raspbian.raspberrypi.org/raspbian/"
            local components="main contrib non-free rpi"
        fi

        local repo_list="$PROJECT_DIR/configs/etc/apt/sources.list.d/raspi.list"
        local key_url="https://archive.raspberrypi.org/debian/raspberrypi.gpg.key"
        local keyring_path="$PROJECT_DIR/configs/usr/share/keyrings//raspberrypi-archive-keyring.gpg"
        local keyring_path_real="/usr/share/keyrings/raspberrypi-archive-keyring.gpg"

    elif [ "$SOURCES" = "raspbian" ]; then
        # armhf (32-bit legacy)
	local repo_url="http://legacy.raspbian.org/raspbian/"
        local components="main contrib non-free rpi"

        local repo_list="$PROJECT_DIR/configs/etc/apt/sources.list.d/raspi.list"
        local key_url="https://archive.raspberrypi.org/debian/raspberrypi.gpg.key"
        local keyring_path="$PROJECT_DIR/configs/usr/share/keyrings//raspberrypi-archive-keyring.gpg"
        local keyring_path_real="/usr/share/keyrings/raspberrypi-archive-keyring.gpg"
    fi

#    local repo_list="$PROJECT_DIR/configs/etc/apt/sources.list.d/raspi.list"
#    local key_url="https://archive.raspberrypi.org/debian/raspberrypi.gpg.key"
#    local keyring_path="$PROJECT_DIR/configs/usr/share/keyrings//raspberrypi-archive-keyring.gpg"
#    local keyring_path_real="/usr/share/keyrings/raspberrypi-archive-keyring.gpg"

    print_info "Installing Raspberry Pi GPG key..."
    curl -fsSL "$key_url" | gpg --dearmor | tee "$keyring_path" > /dev/null

    print_info "Adding APT source for '$distro' with version '$version'..."
    echo "deb [signed-by=$keyring_path_real] $repo_url $version main" | tee "$repo_list" > /dev/null
}
mkdir -p $PROJECT_DIR/configs/etc/apt/sources.list.d
mkdir -p $PROJECT_DIR/configs/usr/share/keyrings
touch $PROJECT_DIR/configs/etc/apt/sources.list.d/raspi.list
touch $PROJECT_DIR/configs/usr/share/keyrings/raspberrypi-archive-keyring.gpg
[ -n "$SOURCES" ] && add_raspi_repo $VERSION



###################### Setup Dockerfile ######################
# Create Dockerfile
print_info "Creating Dockerfile..."

# Deal with legacy RPI jessie base image - non-official - from docker hub
FROMNAME="${OS}:${VERSION}"
if [ "$SOURCES" = "raspbian" ]; then
    FROMNAME="${OS}/${VERSION}"
fi

# If running legacy raspbian repo, remove the standard archive repo
REMOVE_NON_LEGACY_REPO=""
if [ "$SOURCES" = "raspbian" ]; then
    REMOVE_NON_LEGACY_REPO="RUN find /etc/apt/ -type f -print0 | xargs -0 sed -i '/archive\.raspbian\.org/d'"
fi

if [ "$VERSION" = "trusty" ] || [ "$VERSION" = "jessie" ]; then
    # Special conditions for legacy trusty and jessie, get it direct from the releases
    GITLFS="mkdir -p /root/git-lfs && \
            cd /root/git-lfs && \
                curl -OJL https://github.com/git-lfs/git-lfs/releases/download/v2.12.1/git-lfs-linux-arm-v2.12.1.tar.gz && \
                tar -xvf git-lfs-linux-arm-v2.12.1.tar.gz && \
                ./install.sh"
else
    # Add the packagecloud repository to apt sources. - Ew, causing issues. :(
    # curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
    # curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash
    GITLFS="apt-get -y install git-lfs"
fi


BASE_PACKAGES="aptitude openssh-client build-essential debhelper git lsb-release nano joe curl wget git dupload ccache screen"
if [ "$OS" = "ubuntu" ]; then
    BASE_PACKAGES+=" language-pack-en-base mysql-client mysql-server"
elif [ "$OS" = "raspbian" ]; then
    BASE_PACKAGES+=" mariadb-client-10.0"
elif [ "$OS" = "debian" ]; then
    BASE_PACKAGES+=" mariadb-client-10.0"
fi
#    wget \\
#    curl \\
#    build-essential \\
#    debhelper \\
#    linux-headers-generic \\
#    language-pack-en-base \\
#    aptitude \\
#    openssh-client \\
#    mysql-server \\
#    git \\
#    autotools-dev \\
#    libgtk2.0-dev \\
#    libvte-dev \\
#    dupload \\
#    nano \\
#    joe \\
#    g++ \\
#    ccache \\
#    lsb-release \\
#    screen

# If shared mysql database then Remove mysql-server from build-packages - requires shared database!!
SHARED_MYSQL_REMOVE_SERVER=""
if [ -n "$MYSQL_RUN" ]; then
    SHARED_MYSQL_REMOVE_SERVER="RUN sed -i '/mysql-server/d' /etc/lmce-build/build-packages || :"
fi



###################### Create Dockerfile ######################
# Create Dockerfile
cat > $PROJECT_DIR/Dockerfile << EOF
FROM ${FROMNAME}

LABEL maintainer="LinuxMCE Community"
LABEL description="LinuxMCE Build Environment"
LABEL version="1.0"

# Avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Setup apt-cache
RUN mkdir -p /etc/apt/apt.conf.d/
COPY configs/etc/apt/apt.conf.d/02proxy /etc/apt/apt.conf.d/

# Setup rpios apt sources.list
RUN mkdir -p /etc/apt/sources.list.d/
COPY configs/etc/apt/sources.list.d/raspi.list /etc/apt/sources.list.d/

# Setup rpios apt repo keyring
RUN mkdir -p /usr/share/keyrings/
COPY configs/usr/share/keyrings/raspberrypi-archive-keyring.gpg /usr/share/keyrings/raspberrypi-archive-keyring.gpg

$REMOVE_NON_LEGACY_REPO

# Set locale
RUN apt-get update && apt-get install -y locales && \\
    localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL C

# Install necessary packages
RUN apt-get -y dist-upgrade
RUN apt-get install -y $BASE_PACKAGES

# Grab the git-lfs repository
#RUN curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash
#RUN apt-get install -y git-lfs
RUN $GITLFS

# Configure MySQL
RUN mkdir -p /etc/mysql/conf.d/
COPY configs/etc/mysql/conf.d/builder.cnf /etc/mysql/conf.d/
# NOTE: This won't work if the mysql-server is not installed. Make this conditional somehow?
RUN mkdir -p /var/run/mysqld && \\
    chown mysql:mysql /var/run/mysqld || :

# Set up working directory
WORKDIR /root

# REMOVE: This is done in the docker-compose.yml file.
# Create directory for build outputs
#VOLUME ["$BUILDER_WORKDIR"]
# Set up build directories
RUN mkdir -p $BUILDER_WORKDIR
#WORKDIR /var/lmce-build

# Clone the LinuxMCE buildscripts repository.
RUN git clone https://github.com/linuxmce/buildscripts.git Ubuntu_Helpers_NoHardcode

# Install build helpers
WORKDIR /root/Ubuntu_Helpers_NoHardcode
RUN chmod +x install.sh
RUN ./install.sh

# If present this will remove mysql-server from build-packages - requires shared database!!
$SHARED_MYSQL_REMOVE_SERVER

# Copy builder custom configuration
COPY configs/etc/lmce-build/builder.custom.conf /etc/lmce-build/

# Backup the builder ssh key files for sharing on the host volume
RUN mkdir -p /root/ssh-key && \
    cp /etc/lmce-build/builder.key /root/ssh-key && \
    cp /etc/lmce-build/builder.key.pub /root/ssh-key

# Backup the builder custom configuration file for sharing on the host volume
COPY configs/etc/lmce-build/builder.custom.conf /etc/lmce-build/
RUN mkdir -p /root/config && \
    cp /etc/lmce-build/builder.custom.conf /root/config/

# Install all the build-required packages and libraries
WORKDIR /usr/local/lmce-build
RUN chmod +x prepare.sh
RUN ./prepare.sh

# Define entrypoint for running builds
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Clean apt repositories and cache location
RUN apt-get clean \\
    && rm -rf /var/lib/apt/lists/*
#RUN rm -f /etc/apt/apt.conf.d/02proxy

# Ensure shells start in the correct dir. Necessary because the shell resolves symlinks.
RUN echo 'cd -L /usr/local/lmce-build' >> /root/.bashrc

# Default command if no arguments are provided
CMD ["shell"]
EOF



###################### Create MySQL configuration ######################
# Create MySQL configuration
print_info "Creating MySQL configuration..."
mkdir -p $PROJECT_DIR/configs/etc/mysql/conf.d
cat > $PROJECT_DIR/configs/etc/mysql/conf.d/builder.cnf << 'EOF'
[mysqld]
skip-networking
innodb_flush_log_at_trx_commit = 2
EOF



###################### Create APT proxy file ######################
## Create apt proxy file
print_info "Creating APT proxy file..."
mkdir -p $PROJECT_DIR/configs/etc/apt/apt.conf.d
touch $PROJECT_DIR/configs/etc/apt/apt.conf.d/02proxy
if [ -n "$APT_PROXY" ]; then
    cat > $PROJECT_DIR/configs/etc/apt/apt.conf.d/02proxy << EOF
Acquire {
    HTTP::proxy "${APT_PROXY}";
}
EOF
fi



###################### Create LinuxMCE builder.custom.conf ######################
# Create builder configuration
print_info "Creating builder configuration..."
mkdir -p $PROJECT_DIR/configs/etc/lmce-build
touch $PROJECT_DIR/configs/etc/lmce-build/builder.custom.conf
cat > $PROJECT_DIR/configs/etc/lmce-build/builder.custom.conf << EOF
# Build configuration for LinuxMCE
# Generated on $(date)

# Set the log file location to a location on the host
log_file="\$build_dir/log/lmce-build.log"
local_mirror_dir="\$build_dir/www"

PROXY="${APT_PROXY}"
SKIN_HOST=""
MEDIA_HOST=""

# Uncomment to avoid DVD build step[s]
do_not_build_sl_dvd="yes"
do_not_build_dl_dvd="yes"

# Uncomment to create fake win32 binaries
win32_create_fake="yes"

# Point to the development sqlCVS server for 1004
sqlcvs_host="schema.linuxmce.org"

[ -n "\$SKIN_HOST" ] && http_skin_host="\$SKIN_HOST"
[ -n "\$MEDIA_HOST" ] && http_media_host="\$MEDIA_HOST"
[ -n "\$PROXY" ] && export http_proxy="\$PROXY"

# OS flavor (ubuntu/debian/raspbian)
flavor="$OS"

# release (trusty/buster/wheezy)
build_name="$VERSION"

arch="$ARCH"

# The git branch to checkout after a pull or clone. This is the branch that will build.
git_branch_name="$BRANCH"

# set the number of cores to use based on detected cpu cores.
NUM_CORES=\`nproc\`

# Don't clean the source tree between builds. Runs git pull to update source instead of fresh clone.
no_clean_scm="true"

# Cache build-replacements, only build if the source has changed. Note: Not all replacements are chached.
# remove the file $/var/lmce-build/replacements/.cache to remove the cache memory and rebuild all replacements.
cache_replacements="true"

# Uncomment to disable packaging "_all" .debs (avwiz sounds, install wizard videos, etc.)
#BUILD_ALL_PKGS="no"

# Skip DB dump and import. Comment this if any databases have changed.
# Uncommenting will prevent ALL DB dump and import, including the pluto_main_build database.
#DB_IMPORT="no"

# Only DB dump and import the pluto_main_build database. Enable this if the build database changed but no other databases have changes.
#IMPORT_BUILD_DB_ONLY="true"

# Uncomment to skip the packaging phase of MakeRelease, useful for compile testing.
#skip_packaging="true"

# Uncomment to make dummy packages for REQUIRED packages that are not building (install testing without DB foobar)
MAKE_DUMMY_INSTALL_PKGS="yes"

EOF




###################### Create entrypoint script ######################
# Create entrypoint script
print_info "Creating entrypoint script..."
cat > $PROJECT_DIR/entrypoint.sh << 'EOF'
#!/bin/bash
#
# Entrypoint script for LinuxMCE Docker build environment
#

set -e

# The first time this runs (first start) the unique builder configs will be copied to the host volume.
# Subsequent runs will copy the files from the host volume back to the temporary root locations.
# This will ensure the updated copies are stored in case they are removed from the host volume.
# Create the log directory
mkdir -p /var/lmce-build/log
# The ssh-key is temporarily stored at /root/ssh-key/ during container creation.
mkdir -p /var/lmce-build/builder-keys
[[ ! -f "/var/lmce-build/builder-keys/builder.key" ]] && [[ -f "/root/ssh-key/builder.key" ]] && cp -a /root/ssh-key/* /var/lmce-build/builder-keys/
cp -a /var/lmce-build/builder-keys/* /root/ssh-key/ || :

# The builder.custom.conf is temporarily stored at /root/config/ during container creation.
mkdir -p /var/lmce-build/config
[[ ! -f "/var/lmce-build/config/builder.custom.conf" ]] && [[ -f "/root/config/builder.custom.conf" ]] && cp -a /root/config/* /var/lmce-build/config/
cp -a /var/lmce-build/config/builder.custom.conf /root/config/ || :
cp -a /var/lmce-build/config/builder.custom.conf /root/config/ || :

# Create symbolic links from the builder config directory to the host volume files.
ln -s /var/lmce-build/builder-keys/builder.key /etc/lmce-build/builder.key || :
ln -s /var/lmce-build/builder-keys/builder.key.pub /etc/lmce-build/builder.key.pub || :
ln -s /var/lmce-build/config/builder.custom.conf /etc/lmce-build/builder.custom.conf || :

# If shell is specified, start a shell
if [ "$1" = "shell" ]; then
    exec /bin/bash
fi

# If mysql-start is specified, start MySQL
if [ "$1" = "mysql-start" ]; then
    if [ -d "/var/lib/mysql" ]; then
        service mysql start
        echo "MySQL service started"
    else
        echo "MySQL data directory not found"
    fi
    exit 0
fi

# If custom command is provided, execute it
exec "$@"
EOF
chmod +x $PROJECT_DIR/entrypoint.sh




###################### Create docker-compose.yml ######################
# Create docker-compose.yml with dynamic mappings
print_info "Creating docker-compose.yml with mappings..."
{
  echo "services:"
  echo "  ${PROJECT_NAME}:"
  echo "    build:"
  echo "      context: ."
  echo "      dockerfile: Dockerfile"
  echo "    image: ${PROJECT_NAME}_image:latest"
  echo "    container_name: ${PROJECT_NAME}"
  echo "    platform: $PLATFORM"
  echo "    volumes:"
  echo "      - ./lmce-build:$BUILDER_WORKDIR:rw"
  
  # Add all repository mappings
  for mapping in "${REPO_MAPPINGS_LIST[@]}"; do
    echo "$mapping"
  done
  
  # Add MySQL mapping if available
  if [ -n "$MYSQL_MAPPING" ]; then
    echo "$MYSQL_MAPPING"
  fi
  
  echo "    environment:"
  echo "      - BUILD_TYPE=release"
  echo "      - OS=${OS}"
  echo "      - VERSION=${VERSION}"
  echo "      - ARCH=${ARCH}"
  echo "      - SOURCES=${SOURCES}"
  echo "    command: shell"
  echo "    stdin_open: true"
  echo "    tty: true"
} > "$PROJECT_DIR/docker-compose.yml"




###################### Create run.sh container control script ######################
# Create run script
print_info "Creating run script..."
cat > $PROJECT_DIR/run.sh << EOF
#!/bin/bash
#
# LinuxMCE Docker Run Script
#

set -e

# Container name from setup
CONTAINER_NAME="${PROJECT_NAME}"

# Print colored messages
print_info() {
    echo -e "\e[1;34m[INFO] \$1\e[0m"
}

print_success() {
    echo -e "\e[1;32m[SUCCESS] \$1\e[0m"
}

print_error() {
    echo -e "\e[1;31m[ERROR] \$1\e[0m"
}

# Handle command line options
case "\$1" in
    --build)
        print_info "Building Docker image..."
        docker compose build
        ;;
    --start)
        print_info "Starting Docker container..."
        docker compose up -d
        ;;
    --stop)
        print_info "Stopping Docker container..."
        docker compose down
        ;;
    --shell)
        print_info "Opening shell in Docker container..."
        docker compose exec \${CONTAINER_NAME} /bin/bash
        ;;
    --mysql-start)
        print_info "Starting MySQL service in the container..."
        docker compose exec \${CONTAINER_NAME} service mysql start
        ;;
    --prepare)
        print_info "Running prepare scripts..."
        docker compose exec \${CONTAINER_NAME} /usr/local/lmce-build/prepare.sh
        ;;
    --build-all)
        print_info "Running a LinuxMCE full build..."
        docker compose exec \${CONTAINER_NAME} /usr/local/lmce-build/build.sh
        ;;
    --build-pkg)
        print_info "Running a LinuxMCE build from the supplied list of packages..."
        docker compose exec \${CONTAINER_NAME} /usr/local/lmce-build/release-pkg.sh $2
        ;;
    --build-replacements)
        print_info "Running a LinuxMCE build of Replacements only..."
        docker compose exec \${CONTAINER_NAME} /usr/local/lmce-build/build-scripts/build-replacements.sh
        ;;
    --import-db)
        print_info "Running a LinuxMCE database import..."
        docker compose exec \${CONTAINER_NAME} /usr/local/lmce-build/build-scripts/import-databases.sh
        ;;
    --tail-log)
        print_info "Tailing /var/log/lmce-build.log in ${CONTAINER_NAME}..."
        docker compose exec \${CONTAINER_NAME} tail -f /var/log/lmce-build.log
        ;;
    --top)
        print_info "Running top in ${CONTAINER_NAME}..."
        docker compose exec \${CONTAINER_NAME} top
        ;;
    --exec)
        shift
        print_info "Executing command in Docker container: \$@"
        docker compose exec \${CONTAINER_NAME} \$@
        ;;
    *)
        # Default is to show help
        echo "LinuxMCE Docker Run Script"
        echo "Usage: \$0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --build         	Build the Docker image"
        echo "  --start         	Start the Docker container"
        echo "  --stop          	Stop the Docker container"
        echo "  --shell         	Open a shell in the running container"
        echo "  --mysql-start   	Start the MySQL service in the container (service mysql start)"
        echo "  --prepare       	Run the LinuxMCE prepare scripts (/usr/local/lmce-build/prepare.sh) [not persistent, redo --build instead for permanent setup]"
        echo "  --build-all	    	Run a LinuxMCE full build (/usr/local/lmce-build/build.sh)"
        echo "  --build-pkg #,# 	Run a LinuxMCE build from list of pkgs (/usr/local/lmce-build/release-pkg.sh)"
        echo "  --build-replacements	Run a LinuxMCE build of Replacements only (/usr/local/lmce-build/build-scripts/build-replacements.sh)"
        echo "  --import-db     	Run a LinuxMCE database import (/usr/local/lmce-build/build-scripts/import-databases.sh)"
        echo "  --tail-log	     	Run tail -f on the build log (/var/log/lmce-build.log)"
        echo "  --top		     	Run top in the container"
        echo "  --exec CMD      	Execute a command in the running container"
        echo "  --help          	Show this help message"
        echo ""
        ;;
esac
EOF
chmod +x $PROJECT_DIR/run.sh




###################### Create README.md ######################
# Create README.md
print_info "Creating README.md..."
cat > $PROJECT_DIR/README.md << EOF
# LinuxMCE Docker Build Environment

This is a Docker-based build environment for LinuxMCE with repository and MySQL mapping.

## Prerequisites

- Docker
- Docker Compose

## Usage

1. Build the Docker image:
   \`\`\`bash
   ./run.sh --build
   \`\`\`

2. Start the Docker container:
   \`\`\`bash
   ./run.sh --start
   \`\`\`

3. Open a shell in the running container:
   \`\`\`bash
   ./run.sh --shell
   \`\`\`

4. Start MySQL in the container (if needed):
   \`\`\`bash
   ./run.sh --mysql-start
   \`\`\`

5. Prepare the container (not persistent, use --build instead for permanent setup):
   \`\`\`bash
   ./run.sh --prepare
   \`\`\`

6. Perform a full LinuxMCE build:
   \`\`\`bash
   ./run.sh --build-all
   \`\`\`

7. Build selected packages (provide comma separated list of package numbers as arguments):
   \`\`\`bash
   ./run.sh --build-pkg "###,###,###,###"
   \`\`\`

8. Build only Replacement packagse:
   \`\`\`bash
   ./run.sh --build-replacements
   \`\`\`

9. Import LinuxMCE databases:
   \`\`\`bash
   ./run.sh --import-db
   \`\`\`

10. Follow (tail -f) the build log:
   \`\`\`bash
   ./run.sh --tail-log
   \`\`\`

11. Run top in the container:
   \`\`\`bash
   ./run.sh --top
   \`\`\`

12. Execute a command in the running container:
   \`\`\`bash
   ./run.sh --exec <command>
   \`\`\`

13. Stop the Docker container:
   \`\`\`bash
   ./run.sh --stop
   \`\`\`

14. Display help:
   \`\`\`bash
   ./run.sh --help
   \`\`\`

## Setup Script Options

The setup script supports the following options:

\`\`\`bash
$0 [OPTIONS]
\`\`\`

Options:
- \`--headless\`: Run in headless mode without user prompts
- \`--project-dir DIR\`: Set the project directory (default: \$HOME/$PROJECT_NAME)
- \`--os NAME\`: Set the Operating System name (default: $OS)
- \`--version VER\`: Set OS version for Docker image (default: $VERSION)
- \`--arch ARCH\`: Set arch for Docker image (default: ${ARCH})
- \`--sources NAME\`: Specify additional sources to use (default: ${SOURCES}, options: raspbian|rpios)
- \`--help\`: Show help message

## Environment Variables

In headless mode, you can use the following environment variables:
- \`REPOS\`: Comma-separated list of repository paths to map
- \`MYSQL_DIR\`: Path to MySQL data directory (usually /var/lib/mysql) 
- \`MYSQL_RUN\`: Path to MySQL runtime dir (usually: /run/mysqld) [ MYSQL_RUN is ignored if MYSQL_DIR is set ]

Example:
\`\`\`bash
REPOS="\$HOME/LinuxMCE,\$HOME/linuxmce-core" MYSQL_DIR="/var/lib/mysql" ./linuxmce-docker-setup.sh --headless
\`\`\`

## Project Structure

\`\`\`
${PROJECT_DIR}/
├── run.sh				# Main run script
├── Dockerfile				# Docker image definition
├── docker-compose.yml			# Docker Compose configuration with mappings
├── entrypoint.sh			# Container entrypoint script
├── configs
│   └── etc/
│       ├── apt/
│       │   └── 02proxy			# apt proxy information
│       │
│       ├── mysql/
│       │   └── conf.d
│       │       └── builder.cnf		# MySQL configuration
│       └── lmce-build			# Custom LinuxMCE builder configuration file
│           └── builder.custom.comf	# Custom LinuxMCE builder configuration file
└── lmce-build/				# Build directory (mounted at /var/lmce-build/ within the container)
\`\`\`

## Additional Build Script Options

These additional operations are available through the main run script (\`run.sh\`):

- \`--prepare\`: Run LinuxMCE prepare scripts. Note: This setup is temporary and lost when the container is stopped. Use \`--build\` to bake it into the image.
- \`--build-all\`: Run the full build script for LinuxMCE inside the container.
- \`--build-pkg\`: Run a LinuxMCE build using a supplied list of packages.
- \`--build-replacements\`: Build only the Replacements set of LinuxMCE packages.
- \`--import-db\`: Import LinuxMCE databases from the build scripts.
EOF




###################### Final info for user - next steps ######################
# Final steps
print_success "Setup complete! Your LinuxMCE Docker build environment is ready."
print_info "Project directory: $PROJECT_DIR"
print_info ""
print_info "To build the Docker image:"
print_info "  cd $PROJECT_DIR"
print_info "  ./run.sh --build"
print_info ""
print_info "To start the Docker container:"
print_info "  ./run.sh --start"
print_info ""
print_info "To open a shell in the running container:"
print_info "  ./run.sh --shell"
print_info ""
print_info "To initiate a build in the running container:"
print_info "  ./run.sh --build-all"
print_info ""
print_info "To initiate a specific package build, include the package and package source numbers:"
print_info "  ./run.sh --release-pkg \"###,###,###,###\""
print_info ""
print_info "For more information, see the README.md file in the project directory."

