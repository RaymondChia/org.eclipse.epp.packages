#!/bin/sh
set -x
umask 0022
ulimit -n 2048

# change this if building on build.eclipse.org to "server"; "local" otherwise
BUILDLOCATION="server"

# Location of the build input
HTTP_BASE="http://download.eclipse.org"
FILESYSTEM_BASE="file:///home/data/httpd/download.eclipse.org"
if [ ${BUILDLOCATION} = "server" ]
then
  BASE_URL=${FILESYSTEM_BASE}
else
  BASE_URL=${HTTP_BASE}
fi

# Galileo Repositories
REPO_ECLIPSE35="${BASE_URL}/eclipse/updates/3.5milestones"
#REPO_GALILEO="${BASE_URL}/releases/galileo/"
if [ ${BUILDLOCATION} = "server" ]
then
  REPO_GALILEO="file:///opt/users/hudsonbuild/downloads/galileo/"
else
  REPO_GALILEO="http://build.eclipse.org/galileo/staging/"
fi
REPO_EPP_GALILEO="${BASE_URL}/technology/epp/packages/galileo/milestones"

# Repositories (Galileo)
METADATAREPOSITORIES="${REPO_ECLIPSE35},${REPO_GALILEO},${REPO_EPP_GALILEO}"
ARTIFACTREPOSITORIES="${REPO_ECLIPSE35},${REPO_GALILEO}"

# Eclipse installation, Java, etc.
if [ ${BUILDLOCATION} = "server" ]
then
  ECLIPSE="/shared/technology/epp/epp_build/35/eclipse/eclipse"
  JRE="/opt/ibm/java2-ppc-50/bin/java"
else
  ECLIPSE="eclipse"
  JRE="java"
fi

PACKAGES="epp.package.javame epp.package.cpp epp.package.java epp.package.jee epp.package.modeling epp.package.rcp epp.package.reporting"
PACKAGES_NAMES=( "JavaME" "CPP" "Java" "JEE" "Modeling" "RCP" "Reporting" )
OSes=( win32 linux linux macosx )
WSes=( win32 gtk gtk carbon )
ARCHes=( x86 x86 x86_64 ppc )
FORMAT=( zip tar.gz tar.gz tar.gz )

BASE_DIR=/shared/technology/epp/epp_build/35
DOWNLOAD_BASE_DIR=${BASE_DIR}/download
DOWNLOAD_BASE_URL="http://build.eclipse.org/technology/epp/epp_build/35/download"
BUILD_DIR=${BASE_DIR}/build

###############################################################################

# variables
START_TIME=`date -u +%Y%m%d-%H%M`
LOCKFILE="/tmp/epp.build35.lock"
MARKERFILENAME=".epp.nightlybuild"
STATUSFILENAME="status.stub"

###############################################################################

# only one build process allowed
if [ -e ${LOCKFILE} ]; then
    echo "${START_TIME} EPP build - lockfile ${LOCKFILE} exists" >/dev/stderr
    exit 1
fi
trap "rm -f ${LOCKFILE}; exit" INT TERM EXIT
touch ${LOCKFILE}

# create download directory and files
DOWNLOAD_DIR=${DOWNLOAD_BASE_DIR}/${START_TIME}
mkdir ${DOWNLOAD_DIR}
MARKERFILE="${DOWNLOAD_DIR}/${MARKERFILENAME}"
touch ${MARKERFILE}
STATUSFILE="${DOWNLOAD_DIR}/${STATUSFILENAME}"
touch ${STATUSFILE}

# log to file
LOGFILE="${DOWNLOAD_DIR}/build.log"
exec 1>${LOGFILE} 2>&1

# start statusfile
echo "<tr>" >>${STATUSFILE}
echo "<td>${START_TIME}</td>" >>${STATUSFILE}

# build the packages
for PACKAGE in ${PACKAGES};
do
  echo "Building package for IU ${PACKAGE}"
  mkdir -p ${BUILD_DIR}/${PACKAGE}
  echo "<td>"  >>${STATUSFILE}
  for index in 0 1 2 3;
  do
    echo -n "...EPP building ${PACKAGE} ${OSes[$index]} ${WSes[$index]} ${ARCHes[$index]} "
    EXTENSION="${OSes[$index]}.${WSes[$index]}.${ARCHes[$index]}"
    PACKAGE_BUILD_DIR="${BUILD_DIR}/${PACKAGE}/${EXTENSION}"
    rm -rf ${PACKAGE_BUILD_DIR}
    mkdir ${PACKAGE_BUILD_DIR}
    ${ECLIPSE} -nosplash -consoleLog -application org.eclipse.equinox.p2.director.app.application \
      -metadataRepositories ${METADATAREPOSITORIES} -artifactRepositories ${ARTIFACTREPOSITORIES} \
      -installIU ${PACKAGE} \
      -destination ${PACKAGE_BUILD_DIR}/eclipse \
      -profile ${PACKAGE} \
      -profileProperties org.eclipse.update.install.features=true \
      -bundlepool ${PACKAGE_BUILD_DIR}/eclipse \
      -p2.os ${OSes[$index]} \
      -p2.ws ${WSes[$index]} \
      -p2.arch ${ARCHes[$index]} \
      -roaming \
      -vm ${JRE} \
      -vmargs -Declipse.p2.mirrors=false -Declipse.p2.data.area=${PACKAGE_BUILD_DIR}/eclipse/p2 \
         2>&1 >${DOWNLOAD_DIR}/${PACKAGE}_${EXTENSION}.log
    if [ $? = "0" ]; then
      cd ${PACKAGE_BUILD_DIR}
      if [ ${OSes[$index]} = "win32" ]; then
        PACKAGEFILE="${START_TIME}_eclipse-${PACKAGE}-${EXTENSION}.zip"
        zip -r -o -q ${DOWNLOAD_DIR}/${PACKAGEFILE} eclipse
      else
        PACKAGEFILE="${START_TIME}_eclipse-${PACKAGE}-${EXTENSION}.tar.gz"
        tar zc --owner=100 --group=100 -f ${DOWNLOAD_DIR}/${PACKAGEFILE} eclipse
      fi
      cd ..
      rm -r ${PACKAGE_BUILD_DIR}
      echo "...successfully finished ${OSes[$index]} ${WSes[$index]} ${ARCHes[$index]} package build: ${PACKAGEFILE}"
      echo ${PACKAGEFILE} >>${DOWNLOAD_DIR}/${PACKAGE}_${EXTENSION}.log
      echo "<small style=\"background-color: rgb(204, 255, 204);\"><a href=\"${DOWNLOAD_BASE_URL}/${START_TIME}/${PACKAGEFILE}\">${EXTENSION}</a></small><br>"  >>${STATUSFILE}
    else
      echo "...failed while building package ${OSes[$index]} ${WSes[$index]} ${ARCHes[$index]}"
      echo "FAILED" >>${DOWNLOAD_DIR}/${PACKAGE}_${EXTENSION}.log
      echo "<small style=\"background-color: rgb(255, 204, 204);\"><a href=\"${DOWNLOAD_BASE_URL}/${START_TIME}/${PACKAGE}_${EXTENSION}.log\">${EXTENSION}</a></small><br>"  >>${STATUSFILE}
    fi
  done
  echo "</td>"  >>${STATUSFILE}
done

# start statusfile
echo "</tr>" >>${STATUSFILE}

# remove 'some' (which?) files from the download server
echo "...remove oldest build from download directory ${DOWNLOAD_BASE_DIR}"
cd ${DOWNLOAD_BASE_DIR}
TOBEDELETED_TEMP=`find . -name ${MARKERFILENAME} | grep -v "\./${MARKERFILENAME}" | sort | head -n 1`
TOBEDELETED_DIR=`echo ${TOBEDELETED_TEMP} | cut -d "/" -f 2`
echo "......removing ${TOBEDELETED_DIR} from ${DOWNLOAD_BASE_DIR}"
rm -r ${TOBEDELETED_DIR}

# link results somehow in a single file
echo "...recreate ${DOWNLOAD_BASE_DIR}/${STATUSFILENAME}"
rm ${DOWNLOAD_BASE_DIR}/${STATUSFILENAME}
cd ${DOWNLOAD_BASE_DIR}
for FILE in `ls -r */${STATUSFILENAME}`
do
  echo "......adding $FILE"
  cat ${FILE} >>${DOWNLOAD_BASE_DIR}/${STATUSFILENAME}
done
cp -a ${DOWNLOAD_BASE_DIR}/${STATUSFILENAME} /home/data/httpd/download.eclipse.org/technology/epp/downloads/testing/status35.stub


###############################################################################

# remove lockfile
rm ${LOCKFILE}

## EOF