#!/bin/ksh -e

#===========================================================================
#
# build_wf_proxy.sh
# -----------------
#
# Build a Wavefront proxy JAR on Solaris 11. Will eventually work
# for SmartOS but I don't have a box right now. Coming soon.
#
# The script expects a single argument, which is the version of the
# proxy to build. Outputs a single file,
# 'wavefront-push-agent-<version>.jar', in the user's HOME directory. I
# don't see much point packaging a single file. If you wish to do the
# work, send me a PR.
#
# SMF manifests can be found at
#
# Works at the time of writing, but there's no guarantee Wavefront
# won't change their build process and break it.
#
#
#===========================================================================

PATH=/bin
WORK_DIR=$(mktemp -d)
MVN_VER=3.3.9
MVN_SRC="apache-maven-${MVN_VER}-bin.tar.gz"

if [[ $(uname -s) != "SunOS" ]]
then
	print -u2 "ERROR: this is not a SunOS system"
	exit 1
fi

if [[ $# == 1 ]]
then
    VER=$1
else
    print "usage: ${0##*/} <version>"
    exit 1
fi

grep -q Solaris /etc/release && IS_SOLARIS=true

print -n "  checking for JDK: "

if which java >/dev/null 2>&1
then
	print OK
else
	print -n "installing: "
	$IS_SOLARIS && pkg install --accept jdk-7
fi

print -n "  checking for Maven: "

if which mvn >/dev/null 2>&1
then
	MVN=$(which mvn)
	print OK
else
	print -n "downloading: "
	wget -q -P ${WORK_DIR} \
		"http://mirror.ox.ac.uk/sites/rsync.apache.org/maven/maven-3/${MVN_VER}/binaries/${MVN_SRC}"
	print -n "installing: "
	gtar zxf ${WORK_DIR}/${MVN_SRC} -C ${WORK_DIR}
	MVN=${WORK_DIR}/apache-maven-${MVN_VER}/bin/mvn
	print -n "doctoring: "
	gsed -i 's|#!/bin/sh|#!/bin/bash|' $MVN
	print OK
fi

print "Getting proxy source: "

curl -Lks https://github.com/wavefrontHQ/java/archive/${VER}.tar.gz \
    | gtar -C $WORK_DIR -zxf -
SRC_DIR=${WORK_DIR}/java-${VER}
ARTEFACT=${HOME}/wavefront-push-agent-${VER}.jar

if [[ ! -d $SRC_DIR ]]
then
    print -u2 "no source at ${SRC_DIR}."
    rm -fr $WORK_DIR
    exit 1
fi

$MVN -am package --projects proxy -f ${SRC_DIR}/pom.xml
mv ${SRC_DIR}/proxy/target/wavefront-push-agent.jar ${ARTEFACT}
#rm -fr $WORK_DIR
print "file at $ARTEFACT"
