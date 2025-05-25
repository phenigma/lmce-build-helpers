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
NEW_OS_ID=1             # not implemented properly
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

raspbian_repo=22
raspbian_lmce=23

#REPOS="$UBUNTU_MIRROR_ID,$LINUXMCE_MIRROR_ID"     # 24,25 ubuntu repo only
REPOS="$LINUXMCE_SVN_ID,$LINUXMCE_MIRROR_ID,$UBUNTU_MIRROR_ID"     # 8,24,25 ubuntu/lmce/svn
#REPOS="$LINUXMCE_SVN_ID,raspbian_lmce,$raspbian_repo"  # 8,23,23 raspbian/lmce/svn

####  Q="SELECT PK_Package_Directory FROM Package_Directory WHERE FK_Package=$PK_Package"
####  Package_Directory_File=$(RunSQL "$Q")


#PK_Package=360

       # Check for (Package Compatibility) to OS/Any, OS/$NEW_CODENAME_ID, Any/Any, empty if not
        Q="SELECT count(PK_Package) FROM Package AS A
                INNER JOIN Package_Compat AS B ON B.FK_Package=PK_Package
		WHERE ((B.FK_OperatingSystem=$OLD_OS_ID AND B.FK_Distro IS NULL)
		     OR B.FK_Distro=$NEW_CODENAME_ID
		     OR (B.FK_OperatingSystem IS NULL AND B.FK_Distro IS NULL))"
        All_Packages_Check=$(RunSQL "$Q")
echo "Total Package Compats found: $All_Packages_Check"


       # Check for (Package Compatibility) to OS/Any, OS/$NEW_CODENAME_ID, Any/Any, empty if not
        Q="SELECT count( DISTINCT PK_Package) FROM Package AS A
                INNER JOIN Package_Compat AS B ON B.FK_Package=PK_Package
		WHERE ((B.FK_OperatingSystem=$OLD_OS_ID AND B.FK_Distro IS NULL)
		     OR B.FK_Distro=$NEW_CODENAME_ID
		     OR (B.FK_OperatingSystem IS NULL AND B.FK_Distro IS NULL))"
        Distinct_Packages_Check=$(RunSQL "$Q")
echo "Packages with Distinct Compats: $Distinct_Packages_Check"

((difference = $All_Packages_Check - $Distinct_Packages_Check))
echo "Packages with duplicate Package_Compats: $difference"

        Q="SELECT PK_Package 
		FROM (
		    SELECT PK_Package, COUNT(*) 
		    FROM Package AS A
		    INNER JOIN Package_Compat AS B ON B.FK_Package=PK_Package
		    WHERE ((B.FK_OperatingSystem=1 AND B.FK_Distro IS NULL)
		         OR B.FK_Distro=27
		         OR (B.FK_OperatingSystem IS NULL AND B.FK_Distro IS NULL))
		    GROUP BY FK_Package
		    HAVING COUNT(*) > 1
		) AS subquery;"
        Duplicate_Package_Compats=$(RunSQL "$Q")

echo "Duplicate Package Compatibilities (shouldn't happen): $Duplicate_Package_Compats"

