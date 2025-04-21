#!/bin/bash
#
# copyright 2010 Peer Oliver Schmidt
# licence GPL v3
#
# Purpose: Create a builder environment for LinuxMCE from scratch.
#
# rev 1.1
# - add innodb settings to my.cnf
# - add licence header
# - add changelog
# - use the DISTRIBUTION variable to fill sources.list
# rev ??
# - ruthlessly edited and altered by phenigma at various times, for years now.
# - latest revisions add 2204, and some glue for 2404. - 2025/4/20

set -x
set -e

# comment out to not use or to use defaults
PROXY="http://192.168.2.60:3142/"
#SKIN_HOST="192.168.2.60"
#MEDIA_HOST="192.168.2.60"

# These options must be set to create the builder,
# default options are shown.  Uncomment one of the
# following lines to set the options accordingly.
#
# ### RPI Builds - raspbian until buster, debian from bookworm on ###
# FLAVOR="raspbian"; DISTRIBUTION="wheezy"; ARCH="armhf";
# FLAVOR="raspbian"; DISTRIBUTION="jessie"; ARCH="armhf";
# FLAVOR="raspbian"; DISTRIBUTION="stretch"; ARCH="armhf";
# FLAVOR="raspbian"; DISTRIBUTION="buster"; ARCH="armhf";

# ### Debian Builds ###
# FLAVOR="debian"; DISTRIBUTION="bookworm"; ARCH="amd64"; ## Not implemented
# FLAVOR="debian"; DISTRIBUTION="bookworm"; ARCH="armhf"; ## Not implemented

### Ubuntu Builds ###
# FLAVOR="ubuntu"; DISTRIBUTION="intrepid"; ARCH="i386";
# FLAVOR="ubuntu"; DISTRIBUTION="lucid"; ARCH="i386";
# FLAVOR="ubuntu"; DISTRIBUTION="precise"; ARCH="i386";
# FLAVOR="ubuntu"; DISTRIBUTION="trusty"; ARCH="i386";
# FLAVOR="ubuntu"; DISTRIBUTION="trusty"; ARCH="armhf";
# FLAVOR="ubuntu"; DISTRIBUTION="trusty"; ARCH="amd64";
# FLAVOR="ubuntu"; DISTRIBUTION="xenial"; ARCH="armhf";
# FLAVOR="ubuntu"; DISTRIBUTION="xenial"; ARCH="i386";
# FLAVOR="ubuntu"; DISTRIBUTION="xenial"; ARCH="amd64";
# FLAVOR="ubuntu"; DISTRIBUTION="xenial"; ARCH="armhf";
# FLAVOR="ubuntu"; DISTRIBUTION="bionic"; ARCH="i386";
# FLAVOR="ubuntu"; DISTRIBUTION="bionic"; ARCH="amd64";
# FLAVOR="ubuntu"; DISTRIBUTION="bionic"; ARCH="armhf";
FLAVOR="ubuntu"; DISTRIBUTION="jammy"; ARCH="amd64"; ## 2204 Needs tlc and DB updates
# FLAVOR="ubuntu"; DISTRIBUTION="jammy"; ARCH="armhf"; ## 2204 Needs tlc and DB updates

# FLAVOR="ubuntu"; DISTRIBUTION="noble"; ARCH="amd64"; ## 2404 Needs tlc and DB updates
# FLAVOR="ubuntu"; DISTRIBUTION="noble"; ARCH="armhf"; ## 2404 Needs tlc and DB updates
#

#
# Use shared source location? !! EXPERIMENTAL - NOT RECOMMENDED !! BUILD WILL FAIL !!
# SHARED_SOURCE="yes"
#

#################################################################33

[ -z "$FLAVOR" ] && FLAVOR="ubuntu"
[ -z "$DISTRIBUTION" ] && DISTRIBUTION="jammy"
[ -z "$ARCH" ] && ARCH="amd64"

COMMON_DIR_BASE="/usr/local/lmce"
ROOT_OF_BUILDER="/opt/builder-$FLAVOR-$DISTRIBUTION-$ARCH"
#COMMON_SRC_DIR="$COMMON_DIR_BASE/scm"
COMMON_SKINS_AND_MEDIA_DIR="$COMMON_DIR_BASE/home/samba/www_docs"

[ ! -z "$PROXY" ] && echo exporting http_proxy="$PROXY"
[ ! -z "$PROXY" ] && export http_proxy="$PROXY"
[ ! -z "$PROXY" ] && echo 'Acquire::http { Proxy "'$PROXY'"; };' > /etc/apt/apt.conf.d/02proxy

# set the proper mirror
case "${FLAVOR}" in
	"ubuntu")
		case "$DISTRIBUTION" in
			"intrepid")
				MIRROR="http://old-releases.ubuntu.com/ubuntu/"
				SECURITY_ADDRESS="http://old-releases.ubuntu.com/ubuntu/"
				;;
			"precise")
				MIRROR="http://old-releases.ubuntu.com/ubuntu/"
				SECURITY_ADDRESS="http://old-releases.ubuntu.com/ubuntu/"
				;;
			"lucid")
				MIRROR="http://old-releases.ubuntu.com/ubuntu/"
				SECURITY_ADDRESS="http://old-releases.ubuntu.com/ubuntu/"
				;;
			*)
				case "${ARCH}" in
					armhf)
						MIRROR="http://ports.ubuntu.com/"
						SECURITY_ADDRESS="http://ports.ubuntu.com/"
						;;
					*)
						MIRROR="http://archive.ubuntu.com/ubuntu/"
						SECURITY_ADDRESS="http://security.ubuntu.com/ubuntu/"
						;;
				esac
				;;
		esac
		;;
	"raspbian")
		MIRROR=http://archive.raspbian.org/raspbian/
		;;
esac

# Create a common source dir
# Disabled - from testing a shared source tree across builders. DO NOT USE, BUILDS WILL FAIL.
#[ "${SHARED_SOURCE}" == "yes" ] && mkdir -p "$COMMON_SRC_DIR"

# Create source dir
mkdir -p "$ROOT_OF_BUILDER/var/lmce-build/scm"

# Create a common skins/media dir
mkdir -p "$COMMON_SKINS_AND_MEDIA_DIR"
mkdir -p "$ROOT_OF_BUILDER/home/samba/www_docs"

# Get the needed packages including debootstrap
# Ubuntu 2310 removes the qemu meta package, qemu-user-static is all that *should* be necessary here
# apt-get -y install binfmt-support qemu qemu-user-static debootstrap mysql-server
apt-get -y install binfmt-support qemu-user-static debootstrap mysql-server

# Setup the new debootstrap environment
mkdir -p "$ROOT_OF_BUILDER"

# debootstrap was not arch aware on old builders < 2204 (jammy)
#qemu-debootstrap --arch $ARCH $DISTRIBUTION $ROOT_OF_BUILDER $MIRROR

# debootstrap is arch aware now >= 2204 (jammy)
debootstrap --arch $ARCH $DISTRIBUTION $ROOT_OF_BUILDER $MIRROR

# prepare the fstab to contain required mount information for the builder
cat <<-EOF >>/etc/fstab
	# new builder at $ROOT_OF_BUILDER
	/etc/resolv.conf $ROOT_OF_BUILDER/etc/resolv.conf none bind 0 0
	/dev            $ROOT_OF_BUILDER/dev				none    bind
	none            $ROOT_OF_BUILDER/proc         			proc
	none            $ROOT_OF_BUILDER/sys            		sysfs
	none            $ROOT_OF_BUILDER/dev/pts        		devpts
	#/var/run/mysqld $ROOT_OF_BUILDER/var/run/mysqld			none	bind
	/run/mysqld $ROOT_OF_BUILDER/run/mysqld				none	bind
	$COMMON_SKINS_AND_MEDIA_DIR  $ROOT_OF_BUILDER/home/samba/www_docs 	none bind
	EOF

# Disabled - from testing a shared source tree across builders. DO NOT USE, BUILDS WILL FAIL.
#[ "${SHARED_SOURCE}" == "yes" ] && echo "$COMMON_SRC_DIR  $ROOT_OF_BUILDER/var/lmce-build/scm 		none bind" >> /etc/fstab

# mount the required dirs for the builder
mount $ROOT_OF_BUILDER/dev
mount $ROOT_OF_BUILDER/proc
mount $ROOT_OF_BUILDER/sys
mount $ROOT_OF_BUILDER/dev/pts

mkdir -p $ROOT_OF_BUILDER/run/mysqld
mount $ROOT_OF_BUILDER/run/mysqld

# Disabled - from testing a shared source tree across builders. DO NOT USE, BUILDS WILL FAIL.
#[ "${SHARED_SOURCE}" = "yes" ] && mkdir -p $ROOT_OF_BUILDER/var/lmce-build/scm
#[ "${SHARED_SOURCE}" = "yes" ] && mount $ROOT_OF_BUILDER/var/lmce-build/scm

mkdir -p $ROOT_OF_BUILDER/home/samba/www_docs
mount $ROOT_OF_BUILDER/home/samba/www_docs

# Create the sources.list file for the builder
case "${FLAVOR}" in
	"ubuntu")
		cat <<-EOF >$ROOT_OF_BUILDER/etc/apt/sources.list
			# Required Sources for the builder
			deb     $MIRROR $DISTRIBUTION  main restricted universe multiverse
			deb-src $MIRROR $DISTRIBUTION  main restricted universe
			deb     $MIRROR $DISTRIBUTION-updates  main restricted universe multiverse
			deb-src $MIRROR $DISTRIBUTION-updates  main restricted universe
			deb     $SECURITY_ADDRESS $DISTRIBUTION-security  main restricted universe
			deb-src $SECURITY_ADDRESS $DISTRIBUTION-security  main restricted universe
			EOF
		;;
	"raspbian")
		cat <<-EOF >$ROOT_OF_BUILDER/etc/apt/sources.list
			# Required Sources for the builder
			deb     $MIRROR $DISTRIBUTION  main contrib non-free
			deb-src $MIRROR $DISTRIBUTION  main contrib non-free
			EOF
		;;
esac

[ ! -z "$PROXY" ] && echo 'Acquire::http { Proxy "'$PROXY'"; };' > $ROOT_OF_BUILDER/etc/apt/apt.conf.d/02proxy

BASE_PACKAGES="aptitude openssh-client mysql-client git lsb-release"

case "${FLAVOR}" in
        "ubuntu")
	BASE_PACKAGES+=" language-pack-en-base"
	CONF_FILES_DIR="/conf-files/$DISTRIBUTION-$ARCH/"
### source builds for all releases at the moment, this is unnecessary
#	case "$DISTRIBUTION" in
#		"precise")
#			GIT="https://phenigma@git.linuxmce.org/linuxmce/buildscripts.git"
#			;;
#		"trusty")
#			GIT="https://phenigma@git.linuxmce.org/linuxmce/buildscripts.git"
#			;;
#		"xenial")
#			GIT="https://phenigma@git.linuxmce.org/linuxmce/buildscripts.git"
#			;;
#		"bionic")
#			GIT="https://phenigma@git.linuxmce.org/linuxmce/buildscripts.git"
#			;;
#	esac
	GIT="https://github.com/linuxmce/buildscripts.git"
        ;;
        "raspbian")
		BASE_PACKAGES+=
	        CONF_FILES_DIR="/conf-files/raspbian-$DISTRIBUTION-$ARCH/"
		#GIT="https://phenigma@git.linuxmce.org/linuxmce/buildscripts.git"
		GIT="https://github.com/linuxmce/buildscripts.git"
        ;;
esac


# Create a script containing the initial steps needed for the builder
cat <<-EOF >$ROOT_OF_BUILDER/root/initialBuilderSetup.sh
	#!/bin/bash
	export LC_ALL=C

	set -e
	set -x

	# prevent services from starting in chroot
	dpkg-divert --local --add /sbin/systemctl
	rm -f /sbin/systemctl
	ln -s /bin/true /sbin/systemctl

	dpkg-divert --local --add /sbin/initctl
	rm -f /sbin/initctl
	ln -s /bin/true /sbin/initctl

	dpkg-divert --local --add /usr/sbin/invoke-rc.d
	rm -f /usr/sbin/invoke-rc.d
	ln -s /bin/true /usr/sbin/invoke-rc.d

	PROXY="$PROXY"
	[ ! -z "\$PROXY" ] && export http_proxy="\$PROXY"

	# TODO: add code to get the repo keys

	apt-get update
	apt-get -y dist-upgrade
	# Install base packages required.
	apt-get -y install $BASE_PACKAGES

	# Make sure mysql is not using the networking (thanks Zaerc)
	# and make sure the innodb_flush_log settings are ok.
	sed 's/^[^#]*bind-address[[:space:]]*=.*$/#&\nskip-networking\ninnodb_flush_log_at_trx_commit = 2/' -i /etc/mysql/my.cnf
	cd /root
	git clone "$GIT"
	ln -s buildscripts Ubuntu_Helpers_NoHardcode
	cd Ubuntu_Helpers_NoHardcode

	#
	# install.sh doesn't detect raspbian properly so we do it here instead
	#
	#this is all taken from ./install.sh
	echo "Running surrogate install.sh"
	Flavor="$FLAVOR"
	Distro="$DISTRIBUTION"
	Arch="$ARCH"

	# Install default config files
	#### remove me
	echo mkdir -p "\$(pwd)/$CONF_FILES_DIR"
	mkdir -p "\$(pwd)/$CONF_FILES_DIR"
	####

	echo "Installing Default Configs For \$Flavor-\$Distro-\$Arch"
	rm -f "/etc/lmce-build"
	ln -s "\$(pwd)/$CONF_FILES_DIR" "/etc/lmce-build"

	rm -f "/usr/local/lmce-build"
	echo "Creating symlink in /usr/local/lmce-build"
	ln -s "\$(pwd)" "/usr/local/lmce-build"


	# Generate ssh key for builder if !exist
	if [ ! -f "/etc/lmce-build/builder.key" ]; then
	        echo "Generating SSH Key for this host : /etc/lmce-build/builder.key"
	        ssh-keygen -N '' -C "LinuxMCE Builder \$Flavor \$Distro \$Arch" -f /etc/lmce-build/builder.key
	else
	        echo "SSH Key found on this host : /etc/lmce-build/builder.key"
	fi

	# Need a >1.7 subversion for all distros
	case "\$Flavor" in
		"ubuntu")
			ppa_distro="\$Distro"
			case "\$Distro" in
				"trusty")
					apt-get install git
					;;
				*)
					apt-get -y install git
					;;
			esac
			;;
		"raspbian")
			apt-get -y install git
			;;
	esac
	EOF
chmod +x $ROOT_OF_BUILDER/root/initialBuilderSetup.sh
chroot $ROOT_OF_BUILDER /root/initialBuilderSetup.sh


# Create initial configuration for the builder
cat <<-EOF >$ROOT_OF_BUILDER/root/Ubuntu_Helpers_NoHardcode/$CONF_FILES_DIR/builder.custom.conf
	PROXY="$PROXY"
	SKIN_HOST="$SKIN_HOST"
	MEDIA_HOST="$MEDIA_HOST"

	# Uncomment to avoid DVD build step[s]
	do_not_build_sl_dvd="yes"
	do_not_build_dl_dvd="yes"

	# Uncomment to create fake win32 binaries
	win32_create_fake="yes"

	# Point to the development sqlCVS server for 1004
	sqlcvs_host="schema.linuxmce.org"

	[ ! -z "\$SKIN_HOST" ] && http_skin_host="\$SKIN_HOST"
	[ ! -z "\$MEDIA_HOST" ] && http_media_host="\$MEDIA_HOST"
	[ ! -z "\$PROXY" ] && export http_proxy="\$PROXY"

	flavor="$FLAVOR"
	build_name="$DISTRIBUTION"
	arch="$ARCH"

	NUM_CORES=`nproc`

	no_clean_scm="true"
	cache_replacements="true"

	# This must run at least once, then uncomment unless the DB changes.
	#DB_IMPORT="no"

	git_branch_name="master"
	EOF


echo "The preparations for the builder have been completed.

To use your builder, start mysql server, chroot into $ROOT_OF_BUILDER, prepare your environment 
and build your build.

mount -a
service mysql start
LC_ALL=C chroot $ROOT_OF_BUILDER
cd /usr/local/lmce-build
./prepare.sh
./build.sh
"
