#===========================================================================
#
# build_wf_proxy.sh
# -----------------
#
# Build a Wavefront proxy JAR on Solaris 11 or SmartOS. If you are doing
# the latter, it's easiest to spin up a 'java' image in the JPC and use
# that.
#
# The script expects a single argument, which is the version of the
# proxy to build. This should be a release tag, listed at
# https://github.com/wavefrontHQ/java/releases.
#
# Output is a single file, a tarball named
# 'proxy-<version>-bin.tar.gz', in the user's HOME directory. This
# is the artefact produced by the Wavefront build process, which
# this script does not manipulate.
#
# Works for Solaris 11 and SmartOS 16.2 at the time of writing, but
# there's no guarantee Wavefront won't change their build process and
# break it.
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

if [[ -n $IS_SOLARIS ]]
then
    # tar now needs to be gtar
    #mkdir ${WORK_DIR}/bin
    #ln -s $(which gtar) ${WORK_DIR}/bin/tar
    export PATH=${WORK_DIR}/bin:${PATH}:/usr/local/apache-maven/bin
else
    PATH=/opt/local/bin:/bin
fi

print -n "Prerequisites\n  checking for JDK: "

if which java >/dev/null 2>&1 && java -version 2>&1 | grep 'version "1.8'
then
	print OK
else
	print -n "installing: "

	if [[ -n $IS_SOLARIS ]]
	then
 		pkg install --accept jdk-8
	else
		pkgin -y in openjdk8
	fi
fi

print -n "  checking for Maven: "

if which mvn >/dev/null 2>&1
then
	print OK
else
	if [[ -n $IS_SOLARIS ]]
	then
		print -n "downloading: "
		curl -Ls \
        	"http://mirror.ox.ac.uk/sites/rsync.apache.org/maven/maven-3/${MVN_VER}/binaries/${MVN_SRC}" \
        	| gtar -C $WORK_DIR -zxf -

		MVN=${WORK_DIR}/apache-maven-${MVN_VER}/bin/mvn
		print -n "doctoring: "
		gsed -i 's|#!/bin/sh|#!/bin/bash|' $MVN
		print OK
	else
		print "installing"
		pkgin -y in apache-maven
	fi
fi

MVN=$(which mvn)

print "Getting proxy source from tag ${VER}"

if ! curl -Lks https://github.com/wavefrontHQ/java/archive/${VER}.tar.gz \
    | gtar -C $WORK_DIR -zxf >/dev/null 2>&1 -
then
    print -u2 "Couldn't get archive fron Github. Check your tag is valid."
    exit 2
fi

SRC_DIR=${WORK_DIR}/java-${VER}
ARTEFACT=${SRC_DIR}/proxy/target/proxy-${VER##*-}-bin.tar.gz

if [[ ! -d $SRC_DIR ]]
then
    print -u2 "no source at ${SRC_DIR}."
    rm -fr $WORK_DIR
    exit 1
fi

print "Building proxy"

if $MVN -am package --projects proxy -f ${SRC_DIR}/pom.xml
then
    print "Artefact successfully built."
else
    print "Artefact did not build. Leaving ${SRC_DIR} intact."
    exit 1
fi

if [[ -s $ARTEFACT ]]
then
    mv $ARTEFACT $HOME
    print "file at ${HOME}/${ARTEFACT##*/}"
    rm -fr $WORK_DIR
    exit 0
else
    print "No artefact at ${ARTEFACT}. Leaving ${SRC_DIR} intact."
    exit 2
fi
