#!/bin/bash
 . /usr/pluto/bin/SQL_Ops.sh

SHOWIT=yes
#SOURCE_PKGS=no
skip_pkgs=""

OS=1
OLD_DISTRO=23
OLD_DISTRO_NAME=xenial
NEW_DISTRO=27
NEW_DISTRO_NAME=noble

lmce_svn=8
ubuntu_repo=24
ubuntu_lmce=25
raspbian_repo=22
raspbian_lmce=23

skip_pkgs="826,827" # agocontrol, obsolete
skip_pkgs="$skip_pkgs,828" # AMQP client for agocontrol, obsolete

#REPOS="$ubuntu_repo,$ubuntu_lmce"     # 24,25 ubuntu repo only
REPOS="$lmce_svn,$ubuntu_lmce,$ubuntu_repo"     # 8,24,25 ubuntu/lmce/svn
#REPOS="$lmce_svn,raspbian_lmce,$raspbian_repo"	# 8,23,23 raspbian/lmce/svn

## TODO: Make this select DISTINCT/UNIQUE Packages?, then seperate package loop to detect multiple package sources.
# All compatible packages
Q="SELECT PK_Package, Description, FK_Package_SourceCode, IsSource, FK_Distro, FK_OperatingSystem FROM Package AS A 
	INNER JOIN Package_Compat AS B ON B.FK_Package=PK_Package 
	INNER JOIN Package_Source AS C ON C.FK_Package=PK_Package 
	WHERE FK_RepositorySource IN ($REPOS) AND ((B.FK_OperatingSystem=$OS AND B.FK_Distro IS NULL) OR B.FK_Distro=$OLD_DISTRO)"
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

	# Find all (Sources for package) that match the OLD_DISTRO and OS for this package, empty if none
	Q="SELECT PK_Package_Source, Name, FK_OperatingSystem, FK_Distro, MustBuildFromSource, Comments, FK_RepositorySource FROM Package_Source
		INNER JOIN Package_Source_Compat ON FK_Package_Source=PK_Package_Source
		WHERE FK_RepositorySource IN ($REPOS) AND FK_Package=$PK_Package
			AND ((FK_OperatingSystem=$OS AND FK_Distro IS NULL) OR FK_Distro=$OLD_DISTRO OR (FK_OperatingSystem IS NULL AND FK_Distro IS NULL))"
	SourceCompat=$(RunSQL "$Q")

	# Check for (Package Compatibility) to OS/Any, OS/$NEW_DISTRO, Any/Any, empty if not
	Q="SELECT PK_Package FROM Package AS A
		INNER JOIN Package_Compat AS B ON B.FK_Package=PK_Package
		INNER JOIN Package_Source AS C ON C.FK_Package=PK_Package
		WHERE PK_Package=$PK_Package AND FK_RepositorySource IN ($REPOS)
			 AND ((B.FK_OperatingSystem=$OS AND B.FK_Distro IS NULL) OR B.FK_Distro=$NEW_DISTRO OR (B.FK_OperatingSystem IS NULL AND B.FK_Distro IS NULL))"
	Packages_Check=$(RunSQL "$Q")

	# Add (Package Compatibility) if it doesn't already match (OS/Any), (OS/$NEW_DISTRO), or (Any/Any)
	# This only adds the (Package Compatibility) if there is to be a compatible (Sources for Package)
	Package_Compat_Q=""
	if [[ -n "$SourceCompat" && -z "$Packages_Check" ]]; then
		# Add Package_Compat (Package Compatibility) to this package here.
		echo "$pre Package_Compat not compatible - add compatibility for package - $Description."
		Package_Compat_Q="INSERT INTO Package_Compat (FK_Package, FK_Distro, FK_OperatingSystem) VALUES ($PK_Package, $NEW_DISTRO, $FK_OperatingSystem)"
	else
		echo "$pre    ($PK_Package, $NEW_DISTRO, $FK_OperatingSystem) Package_Compat exists."
	fi
	# SHOW/DO the SQL INSERT statement to insert the Package Compatibility
	[[ "$SHOWIT" == "yes" ]] && [[ -n "$Package_Compat_Q" ]] && echo "		$Package_Compat_Q"
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
				AND ((FK_OperatingSystem=$OS AND FK_Distro IS NULL) OR FK_Distro=$NEW_DISTRO OR (FK_OperatingSystem IS NULL AND FK_Distro IS NULL))"
		SourceCompat_Check=$(RunSQL "$Q")

		# ADD PACKAGE_SOURCE_COMPAT FOR PACKAGES HERE
		msg="$pre    ($PK_Package, $PK_Package_Source, $Source_FK_OperatingSystem, $NEW_DISTRO, $FK_RepositorySource, $Name)"
		Source_Compat_Q=""
		if [[ -z "$SourceCompat_Check" ]] ; then
			echo "$msg Package_Source_Compat not showing compatible - add a compatibility for this package source."
			Source_Compat_Q="INSERT INTO Package_Source_Compat (FK_Package_Source, FK_OperatingSystem, FK_Distro, MustBuildFromSource, Comments) VALUES ($PK_Package_Source, $Source_FK_OperatingSystem, $NEW_DISTRO, $MustBuildFromSource, '$Comments')"
		else
			echo "$msg Package_Source_Compat exists."
		fi

		# check if the package exists in the NEW_DISTRO, flag for the user and do not auto insert
		if [[ "$FK_RepositorySource" != "8" && "$IsSource" != "1" ]]; then
			# TODO make this use the repos Packages and Packages.gz files.
			Exists=$(apt-cache policy $Name | grep "$NEW_DISTRO_NAME")
			if [ -n "$Exists" ]; then
				echo "$msg Found in $NEW_DISTRO_NAME."

				[[ "$SHOWIT" == "yes" ]] && [[ -n "$Source_Compat_Q" ]] && echo "		$Source_Compat_Q"
#				[[ "$DOIT" == "yes" ]] && [[ -n "$Source_Compat_Q" ]] && R=$(RunSQL "$Source_Compat_Q")

			else
				# NEED TO FLAG THESE PACKAGES FOR MANUAL VIEWING
				echo "$msg NOT FOUND IN $NEW_DISTRO_NAME REPO!!! NEEDS ATTENTION!!!"
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
