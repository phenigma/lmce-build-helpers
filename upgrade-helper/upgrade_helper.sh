#!/bin/bash
 . /usr/pluto/bin/SQL_Ops.sh

SHOWIT=yes

OS=1
OLD_DISTRO=23
OLD_DISTRO_NAME=xenial
NEW_DISTRO=27
NEW_DISTRO_NAME=noble
#REPOS=8,22,23	# raspbian
REPOS=8,24,25     # ubuntu


## TODO: Make this select DISTINCT Packages, then seperate package loop to detect multiple sources.
# All compatible packages
Q="SELECT PK_Package, Description, FK_Package_SourceCode, IsSource, FK_Distro, FK_OperatingSystem FROM Package AS A 
	INNER JOIN Package_Compat AS B ON B.FK_Package=PK_Package 
	INNER JOIN Package_Source AS C ON C.FK_Package=PK_Package 
	WHERE FK_RepositorySource IN ($REPOS) AND ((B.FK_OperatingSystem=$OS AND B.FK_Distro IS NULL) OR B.FK_Distro=$OLD_DISTRO)"
Packages=$(RunSQL "$Q")

for row_pkg in $Packages; do
	PK_Package=$(Field "1" "$row_pkg")
	Description=$(Field "2" "$row_pkg")
	FK_Package_SourceCode=$(Field "3" "$row_pkg")
	IsSource=$(Field "4" "$row_pkg")
	FK_Distro=$(Field "5" "$row_pkg")
	FK_OperatingSystem=$(Field "6" "$row_pkg")

	pre="pkg/src=($PK_Package/$FK_Package_SourceCode),OS/Dist=[$FK_OperatingSystem/$FK_Distro]:"
	msg="$pre $Description --"
 	[[ "$IsSource" == 1 ]] && msg="$msg IsSource"
	echo "$msg"
	msg=""

	# All compatible Repositories for this package
	Q="SELECT PK_Package_Source, Name, FK_OperatingSystem, FK_Distro, MustBuildFromSource, Comments, FK_RepositorySource FROM Package_Source 
		INNER JOIN Package_Source_Compat ON FK_Package_Source=PK_Package_Source
		WHERE FK_RepositorySource IN ($REPOS) AND FK_Package=$PK_Package 
			AND ((FK_OperatingSystem=$OS AND FK_Distro IS NULL) OR FK_Distro=$OLD_DISTRO OR (FK_OperatingSystem IS NULL AND FK_Distro IS NULL))"
	SourceCompat=$(RunSQL "$Q")

	# Check for package in the new distro already.
	Q="SELECT PK_Package FROM Package AS A 
		INNER JOIN Package_Compat AS B ON B.FK_Package=PK_Package 
		INNER JOIN Package_Source AS C ON C.FK_Package=PK_Package 
		WHERE PK_Package=$PK_Package AND FK_RepositorySource IN ($REPOS)
			 AND ((B.FK_OperatingSystem=$OS AND B.FK_Distro IS NULL) OR B.FK_Distro=$NEW_DISTRO OR (B.FK_OperatingSystem IS NULL AND B.FK_Distro IS NULL))"
	Packages_Check=$(RunSQL "$Q")

	# Don't add a new compatibility entry for if it is already OS/Any
	Package_Compat_Q=""
	if [[ -n "$SourceCompat" && -z "$Packages_Check" ]]; then
		# ADD PACKAGE COMPAT FOR ALL PACKAGES HERE
		Package_Compat_Q="INSERT INTO Package_Compat (FK_Package, FK_Distro, FK_OperatingSystem) VALUES ($PK_Package, $NEW_DISTRO, $FK_OperatingSystem)"
	fi

	# Flag any packages with OS/Distro file limitations in packages for manual viewing
	Q="SELECT PK_Package_Directory FROM Package_Directory WHERE FK_Package=$PK_Package AND FK_Distro=$OLD_DISTRO"
	Package_Directory=$(RunSQL "$Q")

	NEEDS_ATTENTION=""
	[[ -n "$Package_Directory" ]] && NEEDS_ATTENTION="yes"
	Q="SELECT PK_Package_Directory FROM Package_Directory WHERE FK_Package=$PK_Package"
	Package_Directory=$(RunSQL "$Q")
	for pd in $Package_Directory; do
		PK_Package_Directory=$(Field "1" "$pd")
		Q="SELECT PK_Package_Directory_File FROM Package_Directory_File WHERE FK_Package_Directory=$PK_Package_Directory AND FK_Distro=$OLD_DISTRO"
		Package_Directory_File=$(RunSQL "$Q")
		[[ -n "$Package_Directory_File" ]] && NEEDS_ATTENTION="yes"
	done

	for row_source in $SourceCompat; do
		PK_Package_Source=$(Field "1" "$row_source")
		Name=$(Field "2" "$row_source")
		Source_FK_OperatingSystem=$(Field "3" "$row_source")
		Source_FK_Distro=$(Field "4" "$row_source")
		MustBuildFromSource=$(Field "5" "$row_source")
		Comments=$(Field "6" "$row_source")
		FK_RepositorySource=$(Field "7" "$row_source")

		[[ "$MustBuildFromSource" == "NULL" ]] && MustBuildFromSource=0
		[[ "$Comments" == "NULL" ]] && Comments=""

		msg="$pre	Source: $PK_Package_Source -- Repo: $FK_RepositorySource -- Name: $Name"
		[[ -n "$NEEDS_ATTENTION" ]] && echo "$msg -- NEEDS ATTENTION!!!" && NEEDS_ATTENTION=""

		# Check for an already compatible source location for this package
		Q="SELECT PK_Package_Source_Compat FROM Package_Source_Compat 
			WHERE FK_Package_Source=$PK_Package_Source 
				AND ((FK_OperatingSystem=$OS AND FK_Distro IS NULL) OR FK_Distro=$NEW_DISTRO OR (FK_OperatingSystem IS NULL AND FK_Distro IS NULL))"
		SourceCompat_Check=$(RunSQL "$Q")

		# ADD SOURCE_COMPAT FOR PACKAGES HERE
		Source_Compat_Q=""
		if [[ -z "$SourceCompat_Check" ]] ; then
			Source_Compat_Q="INSERT INTO Package_Source_Compat (FK_Package_Source, FK_OperatingSystem, FK_Distro, MustBuildFromSource, Comments) VALUES ($PK_Package_Source, $Source_FK_OperatingSystem, $NEW_DISTRO, $MustBuildFromSource, '$Comments')"
		fi

		if [[ "$FK_RepositorySource" != "8" && "$IsSource" != "1" ]]; then
			Exists=$(apt-cache policy $Name | grep "$NEW_DISTRO_NAME")
			if [ -n "$Exists" ]; then
				msg="$msg Found."
			else
				# NEED TO FLAG THESE PACKAGES FOR MANUAL VIEWING
				msg="$msg NOT FOUND IN REPO!!!!!!"
			fi
		fi

		echo "$msg"
		[[ "$SHOWIT" == "yes" ]] && [[ -n "$Source_Compat_Q" ]] && echo "		$Source_Compat_Q"
#		[[ "$DOIT" == "yes" ]] && [[ -n "$Source_Compat_Q" ]] && R=$(RunSQL "$Source_Compat_Q")

	done

	[[ "$SHOWIT" == "yes" ]] && [[ -n "$Package_Compat_Q" ]] && echo "		$Package_Compat_Q"
#	[[ "$DOIT" == "yes" ]] && [[ -n "$Package_Compat_Q" ]] && R=$(RunSQL "$Package_Compat_Q")

done
