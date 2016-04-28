#!/bin/ksh -e

#===========================================================================
#
# build_wf_proxy.sh
# -----------------
#
# Build a Wavefront proxy JAR on Solaris 11. Will eventually work
# for SmartOS but I don't have a box right now. Coming soon.
#
# The script outputs a single file, 'wavefront-push-agent.jar', in
# the user's HOME directory. I don't see much point packaging a
# single file. If you wish to do the work, send me a PR.
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

grep -s Solaris /etc/release && IS_SOLARIS=true
print -n "Prerequisites\n  checking for git: "

if which git >/dev/null 2>&1
then
	print OK
else
	print -n "installing: "
	$IS_SOLARIS && pkg install git
fi

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
git clone https://github.com/wavefrontHQ/java.git ${WORK_DIR}/wf
$MVN -am package --projects proxy -f ${WORK_DIR}/wf/pom.xml
mv ${WORK_DIR}/wf/proxy/target/wavefront-push-agent.jar ${HOME}
rm -fr ${WORK_DIR}
print "file at ${HOME}/wavefront-push-agent.jar"
