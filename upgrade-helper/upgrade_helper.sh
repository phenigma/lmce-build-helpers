#!/bin/bash
 . /usr/pluto/bin/SQL_Ops.sh

#set -x 

# Variables
SHOWIT=yes
#DOIT=yes
DOIT=no
#SOURCE_PKGS=no

echo "" > "./not_found.txt"
echo "" > "./inserts.sql"

# OS and Distro
OLD_OS="ubuntu"
OLD_OS_ID=1
OLD_CODENAME="xenial"
OLD_CODENAME_ID=23
OLD_ARCH="amd64"

NEW_OS="ubuntu"
NEW_OS_ID=1		# not implemented properly
NEW_CODENAME="noble"
NEW_CODENAME_ID=27
NEW_ARCH="amd64"

# Mirrors
UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu"
UBUNTU_MIRROR_ID=24
DEBIAN_MIRROR="http://ftp.debian.org/debian"

# LinuxMCE Repositories
LINUXMCE_REMOTE_REPOS=""
#LINUXMCE_REMOTE_REPOS="http://deb.linuxmce.org/ubuntu/"
LINUXMCE_LOCAL_REPOS="http://192.168.2.153/$NEW_CODENAME-$NEW_ARCH/"
LINUXMCE_MIRROR_ID=25
LINUXMCE_SVN_ID=8

skip_pkgs=""
skip_pkgs="826,827" # agocontrol, obsolete
skip_pkgs="$skip_pkgs,307" # Pluto Generic Serial Device - broken, hopefully this will permit install testing
skip_pkgs="$skip_pkgs,828" # AMQP client for agocontrol, obsolete
skip_pkgs="$skip_pkgs,835" # VLC (non-X parts), obsolete
skip_pkgs="$skip_pkgs,779" # Qt4 Development (obsolete), obsolete
skip_pkgs="$skip_pkgs,739" # VDR Plugin Remotetimers, deprecated for now, needed with new VDR?
skip_pkgs="$skip_pkgs,889" # LinuxMCE Disked MD RPi2
skip_pkgs="$skip_pkgs,866" # OMXPlayer
skip_pkgs="$skip_pkgs,904" # LinuxMCE Disked MD Compute Stick
skip_pkgs="$skip_pkgs,917" # raspi2png
skip_pkgs="$skip_pkgs,367" # tcltk-ruby1.8/2.0 - no longer exists
skip_pkgs="$skip_pkgs,224" # Apache PHP module
skip_pkgs="$skip_pkgs,221" # BlueZ tools
skip_pkgs="$skip_pkgs,295" # iproute
skip_pkgs="$skip_pkgs,519" # IVTV utils
skip_pkgs="$skip_pkgs,501" # libdvdread
skip_pkgs="$skip_pkgs,439" # **djmount (upnp client) (obsolete)
skip_pkgs="$skip_pkgs,348" # Linphone library
skip_pkgs="$skip_pkgs,701" # gerbera (formerly MediaTomb)
skip_pkgs="$skip_pkgs,14"  # nCurses development
skip_pkgs="$skip_pkgs,235" # NetCat
skip_pkgs="$skip_pkgs,312" # **ODBC MySQL Library (obsolete - breaks mysql)
skip_pkgs="$skip_pkgs,218" # OpenOBEX Library
skip_pkgs="$skip_pkgs,231" # PHP  CURL
skip_pkgs="$skip_pkgs,265" # PHP GD
skip_pkgs="$skip_pkgs,42"  # PNG library development
skip_pkgs="$skip_pkgs,166" # libssl - SSL shared libraries
skip_pkgs="$skip_pkgs,764" # **UPnP Internet Gateway Device (obsolete)
skip_pkgs="$skip_pkgs,63,64"  # **X printing extension library (obsolete) and -dev
skip_pkgs="$skip_pkgs,71"  # X Toolkit Intrinsics
skip_pkgs="$skip_pkgs,799" # libavcodecXX
skip_pkgs="$skip_pkgs,800" # libdc1394-22
skip_pkgs="$skip_pkgs,734" # EXIF/IPTC metadata manipulation library
skip_pkgs="$skip_pkgs,29"  # Mesa 3D graphics library
skip_pkgs="$skip_pkgs,352" # OSIP library
skip_pkgs="$skip_pkgs,815" # libowcapi
skip_pkgs="$skip_pkgs,818" # libshairport
skip_pkgs="$skip_pkgs,164" # GNU Standard C++ Library development
skip_pkgs="$skip_pkgs,824,825" # OpenZWave library
skip_pkgs="$skip_pkgs,860" # dansguardian
skip_pkgs="$skip_pkgs,867,870,868" # qml modules
skip_pkgs="$skip_pkgs,885" # s-nail (old heirloom-mailx)
skip_pkgs="$skip_pkgs,933" # libgsoap
skip_pkgs="$skip_pkgs,36"  # FreeType 2 development
skip_pkgs="$skip_pkgs,12"  # ALSA libraries
skip_pkgs="$skip_pkgs,90"  # GLib2 library
skip_pkgs="$skip_pkgs,350" # GTK2.0 library
skip_pkgs="$skip_pkgs,593" # libconfuseX
skip_pkgs="$skip_pkgs,41,42" # PNG library and -dev

skip_pkgs="$skip_pkgs,44,45"  # TIFF library and -dev
skip_pkgs="$skip_pkgs,390,365" # libruby1.8/2.0/2.1/2.2 and -dev
skip_pkgs="$skip_pkgs,900,902" # LinuxMCE Disked MID Joggler and source
skip_pkgs="$skip_pkgs,3,4"     #  MySQL client libraries
skip_pkgs="$skip_pkgs,854,855" # Qt JSON library , obsolete
skip_pkgs="$skip_pkgs,840,841" # hupnp, obsolete
skip_pkgs="$skip_pkgs,842,843" # LinuxMCE DLNA & Source, obsolete

raspbian_repo=22
raspbian_lmce=23

#REPOS="$UBUNTU_MIRROR_ID,$LINUXMCE_MIRROR_ID"     # 24,25 ubuntu repo only
REPOS="$LINUXMCE_SVN_ID,$LINUXMCE_MIRROR_ID,$UBUNTU_MIRROR_ID"     # 8,24,25 ubuntu/lmce/svn
#REPOS="$LINUXMCE_SVN_ID,raspbian_lmce,$raspbian_repo"	# 8,23,23 raspbian/lmce/svn

# ###########################################################################

# Fetch and parse Packages.gz
function fetch_packages() {
    local repo_url=$1
    local os=$2
    local codename=$3
    local arch=$4
    local local_flag=$5

    if [[ -f /tmp/packages/$codename-$arch/packages.list ]]; then
        echo "packages.list found not downloading"
        return 0
    fi

    mkdir -p /tmp/packages/$codename-$arch
    if [[ "$local_flag" == "local" ]]; then
        echo "1 - ${repo_url}Packages.gz"
        wget -q "${repo_url}Packages.gz" -O "/tmp/packages/$codename-$arch/Packages.gz" || { echo "1Failed downloading $repo_url"; exit 1; }
    else
        local components="main universe multiverse restricted"
        [[ "$os" == "debian" ]] && components="main contrib non-free"

        for comp in $components; do
            echo "2 - ${repo_url}/dists/$codename/$comp/binary-$arch/Packages.gz"
            wget -q "${repo_url}/dists/$codename/$comp/binary-$arch/Packages.gz" -O "/tmp/packages/$codename-$arch/$comp-Packages.gz" || { echo "2 - ${repo_url}/dists/$codename/$comp/binary-$arch/Packages.gz - Failed downloading ${repo_url} ${comp} ${arch}"; exit 1; }
        done
    fi

    # Parse packages
    gunzip -cf /tmp/packages/$codename-$arch/*.gz | awk '/^Package: /{pkg=$2}/^Version: /{print pkg" "$2}' > "/tmp/packages/$codename-$arch/packages.list"
}

# Check package existence
function check_package_existence() {
    local package=$1
    local codename=$2
    local arch=$3
#echo grep "^${package} " "/tmp/packages/$codename-$arch/packages.list"
    grep -q "^${package} " "/tmp/packages/$codename-$arch/packages.list"
}

# ###########################################################################

# Fetch packages from repos
######## working atm so commented out
fetch_packages $UBUNTU_MIRROR $NEW_OS $NEW_CODENAME $NEW_ARCH ""
for repo in ${LINUXMCE_REMOTE_REPOS//,/ }; do
    #echo old $repo $NEW_OS $NEW_CODENAME $NEW_ARCH
    fetch_packages $repo $NEW_OS $NEW_CODENAME $NEW_ARCH ""
done
[ -n "${LINUXMCE_LOCAL_REPOS}" ] && \
for repo in ${LINUXMCE_LOCAL_REPOS//,/ }; do
    url=$(echo $repo | awk '{print $2}')
    #echo new $url $NEW_OS $NEW_CODENAME $NEW_ARCH "local"

    fetch_packages $repo $NEW_OS $NEW_CODENAME $NEW_ARCH "local"
done

# ###########################################################################

## TODO: Make this select DISTINCT/UNIQUE Packages?, then seperate package loop to detect multiple package sources.
# All compatible packages
Q="SELECT DISTINCT PK_Package, Description, FK_Package_SourceCode, IsSource, FK_Distro, FK_OperatingSystem FROM Package AS A 
	INNER JOIN Package_Compat AS B ON B.FK_Package=PK_Package 
	INNER JOIN Package_Source AS C ON C.FK_Package=PK_Package 
	WHERE FK_RepositorySource IN ($REPOS) AND ((B.FK_OperatingSystem=$OLD_OS_ID AND B.FK_Distro IS NULL) OR B.FK_Distro=$OLD_CODENAME_ID)"
[[ "$SOURCE_PKGS" == "no" ]] && Q="$Q AND (IsSource=0)"
Packages=$(RunSQL "$Q")

for row_pkg in $Packages; do
	PK_Package=$(Field "1" "$row_pkg")
	Description=$(Field "2" "$row_pkg")
	FK_Package_SourceCode=$(Field "3" "$row_pkg")
	IsSource=$(Field "4" "$row_pkg")
	FK_Distro=$(Field "5" "$row_pkg")
	FK_OperatingSystem=$(Field "6" "$row_pkg")

	echo "---"
	pre="pkg/src=($PK_Package/$FK_Package_SourceCode),OS/Dist=[$FK_OperatingSystem/$FK_Distro]:"
	msg="$pre $Description"
 	[[ "$IsSource" == 1 ]] && msg="$msg -- IsSource=1 (Source Code Package)"
	pkg_header="$msg"

	if [[ ",$skip_pkgs," =~ ,$PK_Package, ]]; then
		echo "$msg --- SKIPPING BLOCKED PACKAGE"
		continue;
	fi
	echo "$msg"
	msg=""

	# check for issue of a source code package referencing a source code package - this shouldn't happen.
	if [[ "$IsSource" != "0" && "$FK_Package_SourceCode" != "NULL" ]]; then
		echo "$pre   ISSUE: Package says it is Source Code but references a Source Code Package!!! *** !!!"
	fi

	# Find all (Sources for package) that match the OLD_CODENAME_ID and OS for this package, empty if none
	Q="SELECT PK_Package_Source, Name, FK_OperatingSystem, FK_Distro, MustBuildFromSource, Comments, FK_RepositorySource FROM Package_Source
		INNER JOIN Package_Source_Compat ON FK_Package_Source=PK_Package_Source
		WHERE FK_RepositorySource IN ($REPOS) AND FK_Package=$PK_Package
			AND ((FK_OperatingSystem=$OLD_OS_ID AND FK_Distro IS NULL) OR FK_Distro=$OLD_CODENAME_ID OR (FK_OperatingSystem IS NULL AND FK_Distro IS NULL))"
	SourceCompat=$(RunSQL "$Q")

	# Check for (Package Compatibility) to OS/Any, OS/$NEW_CODENAME_ID, Any/Any, empty if not
	Q="SELECT PK_Package FROM Package AS A
		INNER JOIN Package_Compat AS B ON B.FK_Package=PK_Package
		INNER JOIN Package_Source AS C ON C.FK_Package=PK_Package
		WHERE PK_Package=$PK_Package AND FK_RepositorySource IN ($REPOS)
			 AND ((B.FK_OperatingSystem=$OLD_OS_ID AND B.FK_Distro IS NULL) OR B.FK_Distro=$NEW_CODENAME_ID OR (B.FK_OperatingSystem IS NULL AND B.FK_Distro IS NULL))"
	Packages_Check=$(RunSQL "$Q")

	# Add (Package Compatibility) if it doesn't already match (OS/Any), (OS/$NEW_CODENAME_ID), or (Any/Any)
	# This only adds the (Package Compatibility) if there is to be a compatible (Sources for Package)
	Package_Compat_Q=""
	if [[ -n "$SourceCompat" && -z "$Packages_Check" ]]; then
		# Add Package_Compat (Package Compatibility) to this package here.
		echo "$pre Package_Compat not compatible - add compatibility for package - $Description."
		Package_Compat_Q="INSERT INTO Package_Compat (FK_Package, FK_Distro, FK_OperatingSystem) VALUES ($PK_Package, $NEW_CODENAME_ID, $FK_OperatingSystem)"
	else
		echo "$pre    ($PK_Package, $NEW_CODENAME_ID, $FK_OperatingSystem) Package_Compat exists."
	fi

	# SHOW/DO the SQL INSERT statement to insert the Package Compatibility
	[[ "$SHOWIT" == "yes" ]] && [[ -n "$Package_Compat_Q" ]] && echo "		$Package_Compat_Q"
	[[ "$SHOWIT" == "yes" ]] && [[ -n "$Package_Compat_Q" ]] && echo "### $pkg_header" >> ./inserts.sql && pkg_header=""
	[[ "$SHOWIT" == "yes" ]] && [[ -n "$Package_Compat_Q" ]] && echo "$Package_Compat_Q" >> ./inserts.sql
#	[[ "$DOIT" == "yes" ]] && [[ -n "$Package_Compat_Q" ]] && echo "     -----*****@@@@@ RUNNING INSERT @@@@@*****-----"
#	[[ "$DOIT" == "yes" ]] && [[ -n "$Package_Compat_Q" ]] && R=$(RunSQL "$Package_Compat_Q")


	# This gets entries under (Requested directories and files) for the package in webadmin, empty if none
	# We don't touch (Requested directories and files), it gets complicated. Tell the user it needs attention.
	# Flag any packages with Package_Directory or _Files in (Requested Directories and files) for manual intervention
	NEEDS_ATTENTION=""
	Q="SELECT PK_Package_Directory FROM Package_Directory WHERE FK_Package=$PK_Package"
	Package_Directory=$(RunSQL "$Q")
	[[ -n "$Package_Directory" ]] && NEEDS_ATTENTION="($PK_Package, $Package_Directory) has a Directory in (Requested Directories and files)"
	for pd in $Package_Directory; do
		PK_Package_Directory=$(Field "1" "$pd")
		Q="SELECT PK_Package_Directory_File FROM Package_Directory_File WHERE FK_Package_Directory=$PK_Package_Directory"
		Package_Directory_File=$(RunSQL "$Q")
		[[ -n "$Package_Directory_File" ]] && NEEDS_ATTENTION="($PK_Package, $PK_Package_Directory, $Package_Directory_File) has Files in (Requested Directories and files)"
	done
	msg="$pre   "
	[[ -n "$NEEDS_ATTENTION" ]] && echo "$msg $NEEDS_ATTENTION" && NEEDS_ATTENTION=""

	((SourceCompatCount=0))
	for row_source in $SourceCompat; do
		PK_Package_Source=$(Field "1" "$row_source")
		Name=$(Field "2" "$row_source")
		Source_FK_OperatingSystem=$(Field "3" "$row_source")
		Source_FK_Distro=$(Field "4" "$row_source")
		MustBuildFromSource=$(Field "5" "$row_source")
		Comments=$(Field "6" "$row_source")
		FK_RepositorySource=$(Field "7" "$row_source")

		((SourceCompatCount++))

		[[ "$MustBuildFromSource" == "NULL" ]] && MustBuildFromSource=0
		[[ "$Comments" == "NULL" ]] && Comments=""

		# Check for an already compatible (Source for package) location for this package
		Q="SELECT PK_Package_Source_Compat FROM Package_Source_Compat
			WHERE FK_Package_Source=$PK_Package_Source
				AND ((FK_OperatingSystem=$OLD_OS_ID AND FK_Distro IS NULL) OR FK_Distro=$NEW_CODENAME_ID OR (FK_OperatingSystem IS NULL AND FK_Distro IS NULL))"
		SourceCompat_Check=$(RunSQL "$Q")

		# ADD PACKAGE_SOURCE_COMPAT FOR PACKAGES HERE
		msg="$pre    ($PK_Package, $PK_Package_Source, $Source_FK_OperatingSystem, $NEW_CODENAME_ID, $FK_RepositorySource, $Name)"
		Source_Compat_Q=""
		if [[ -z "$SourceCompat_Check" ]] ; then
			echo "$msg Package_Source_Compat not showing compatible - add a compatibility for this package source."
			Source_Compat_Q="INSERT INTO Package_Source_Compat (FK_Package_Source, FK_OperatingSystem, FK_Distro, MustBuildFromSource, Comments) VALUES ($PK_Package_Source, $Source_FK_OperatingSystem, $NEW_CODENAME_ID, $MustBuildFromSource, '$Comments')"
		else
			echo "$msg Package_Source_Compat exists."
		fi

		# check if the package exists in the NEW_CODENAME_ID, flag for the user and do not auto insert
		if [[ "$FK_RepositorySource" != "8" && "$IsSource" != "1" ]]; then
			# TODO make this use the repos Packages and Packages.gz files.
#			Exists=$(apt-cache policy $Name | grep "$NEW_CODENAME")
#			if [ -n "$Exists" ]; then
			if check_package_existence "$Name" $NEW_CODENAME $NEW_ARCH; then
#			if check_package_existence "$Description" $NEW_CODENAME $NEW_ARCH; then
				echo "$msg Found in $NEW_CODENAME."

				[[ "$SHOWIT" == "yes" ]] && [[ -n "$Source_Compat_Q" ]] && echo "$pre		$Source_Compat_Q"
				[[ "$SHOWIT" == "yes" ]] && [[ -n "$Source_Compat_Q" ]] && [[ -n "$pkg_header" ]] && echo "### $pkg_header" >> ./inserts.sql
				[[ "$SHOWIT" == "yes" ]] && [[ -n "$Source_Compat_Q" ]] && echo "$Source_Compat_Q" >> ./upgrades.sql
#				[[ "$DOIT" == "yes" ]] && [[ -n "$Source_Compat_Q" ]] && echo "     -----*****@@@@@ RUNNING INSERT @@@@@*****-----"
#				[[ "$DOIT" == "yes" ]] && [[ -n "$Source_Compat_Q" ]] && R=$(RunSQL "$Source_Compat_Q")

			else
				# NEED TO FLAG THESE PACKAGES FOR MANUAL VIEWING
				echo "$msg NOT FOUND IN $NEW_CODENAME REPO!!! NEEDS ATTENTION!!!"
				echo "$Name" >> "./not_found.txt"
			fi
		fi

	done
	pre="pkg/src=($PK_Package/$FK_Package_SourceCode),OS/Dist=[$FK_OperatingSystem/$FK_Distro]:"
	msg="($PK_Package) Number of Package_Source_Compat entries $((SourceCompatCount))"
	if [ "$SourceCompatCount" -eq "1" ] && [ "$IsSource" == "1" ]; then
		msg="$msg -- CHECKME: Only 1 Package_Source_Compat entry for source code package *"
# This is ok. These *should* all be libXXXXX-dev packages with both package and old SVN entries.
#	elif [ "$SourceCompatCount" -gt "1" ] && [ "$IsSource" == "0" ]; then
#		msg="$msg -- CHECKME: More than 1 Package_Source_Compat entry for non-source code package **"
	elif [ "$SourceCompatCount" -gt "2" ]; then
		# This should never happen
		msg="$msg -- CHECKME: More than 2 Package_Source_Compat entries ***"
	fi
	echo "$pre    $msg" && msg=""
done
