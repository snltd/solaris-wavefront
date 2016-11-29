#==========================================================================
#
# build_wf_proxy.sh
# -----------------
#
# Build a Wavefront proxy JAR on Solaris 11 or SmartOS. If you are doing
# the latter, it's easiest to spin up a 'java' image in the JPC and use
# that.
#
# The script expects one or two arguments. The first is mandatory,
# and is the version of the proxy to build. This should be a release
# tag, listed at https://github.com/wavefrontHQ/java/releases. The
# second, optional argument 'install' will make the script attempt
# to install the tools necessary to build the proxy. It needs
# elevated privileges to do this.
#
# Output is a single file. On Solaris, if you have FPM you'll get a
# SYSV package. On SmartOS, if you have FPM. you'll get a pkgin
# package. If you don't have FPM you'll get a tarball in $HOME.  The
# packages include an SMF method and manifest. They don't have
# postinstall script to add a `wavefront` user. You can write
# Solaris packages to another directory with the SOLARIS_PKG_DIR
# variable. At the moment FPM seems to ignore the `-p` flag when
# creating pkgin packages, so you will find the package in your
# current working directory.
#
# Works for Solaris 11.3 and SmartOS 16.2 at the time of writing,
# but there's no guarantee Wavefront won't change their build
# process and break it.
#
# R Fisher 08/2016
#
#==========================================================================

#--------------------------------------------------------------------------
# VARIABLES

PATH=/bin:/opt/puppet/bin
ROOT=${0%/*}
WORK_DIR=$(mktemp -d)
MVN_MIRROR="http://mirror.ox.ac.uk/sites/rsync.apache.org"
MVN_VER=3.3.9
MVN_SRC="apache-maven-${MVN_VER}-bin.tar.gz"
SOLARIS_PKG_DIR="/net/shark/js/export/pkg/x86/misc"

#--------------------------------------------------------------------------
# FUNCTIONS

die() {
    print -u2 "ERROR: $1"
    [[ -n $3 && -n $WORK_DIR && -d $WORK_DIR ]] && rm -fr $WORK_DIR
    exit ${2:-1}
}

setup_env() {
    if [[ -n $IS_SOLARIS ]]
    then
        PATH=${PATH}:${WORK_DIR}/bin:${PATH}:/usr/local/apache-maven/bin
        PKG_TYPE=solaris
        PKG_PREFIX=/opt/wavefront
        PKG_NAME="SDEFwfproxy"
        PKG_ARTEFACT="${SOLARIS_PKG_DIR}/${PKG_NAME}.pkg"
    else
        PATH=${PATH}:/opt/local/bin:/opt/local/git/bin:/opt/local/sbin
        JAVA_HOME=/opt/local
        PKG_TYPE=pkgin
        PKG_PREFIX=/opt/local/wavefront
        PKG_NAME="wavefront-proxy"
        PKG_ARTEFACT="${HOME}/${PKG_NAME}.pkgin"
    fi
}

check_for() {
    if which $1 >/dev/null 2>&1
    then
	    print "Prerequisite: $1"
    else
        if [[ -n $INSTALL_DEPS ]]
        then
            print "  installing $1"
            install_$1
        else
            die "could not find '$1'."
        fi

		which $1 >/dev/null 2>&1 || die "failed to install '$1'"
    fi
}

install_java() {
	if [[ -n $IS_SOLARIS ]]
	then
 		pkg install --accept jdk-8
	else
		pkgin -y in openjdk8
	fi
}

install_mvn() {
	if [[ -n $IS_SOLARIS ]]
	then
		curl -Ls \
            "${MVN_MIRROR}/maven/maven-3/${MVN_VER}/binaries/${MVN_SRC}" \
        	| gtar -C $WORK_DIR -zxf -

		MVN=${WORK_DIR}/apache-maven-${MVN_VER}/bin/mvn
		PATH=$PATH:${WORK_DIR}/apache-maven-${MVN_VER}/bin
		gsed -i 's|#!/bin/sh|#!/bin/bash|' $MVN
	else
		pkgin -y in apache-maven
	fi
}

install_git() {
	if [[ -n $IS_SOLARIS ]]
	then
 		pkg install developer/versioning/git
	else
		pkgin -y in git-base
	fi
}

get_wf_source() {
    print "Getting proxy source from tag ${1}"

    curl -Lks \
        https://github.com/wavefrontHQ/java/archive/${VER}.tar.gz \
        | gtar -C $WORK_DIR -zxf >/dev/null 2>&1 - \
    || die "Couldn't get archive fron Github. Check your tag." 2
}

build_proxy() {
    print "Building proxy"

    print $MVN -am package --projects proxy -f ${SRC_DIR}/pom.xml
    $MVN -am package --projects proxy -f ${SRC_DIR}/pom.xml \
        || die "Failed to build proxy. Source at ${SRC_DIR}." 3 1
}

build_package() {
    PKG_DIR=${WORK_DIR}/pkg
    PKG_VER=${ARTEFACT##*proxy-}
    PKG_VER=${PKG_VER%%-*}
    mkdir -p $PKG_DIR
    gtar -xf $ARTEFACT -C $PKG_DIR
    mkdir -p ${PKG_DIR}/lib/svc/method ${PKG_DIR}/lib/svc/manifest

    sed "s|__PREFIX__|$PKG_PREFIX|g" \
        ${ROOT}/smf/manifest/wavefront-proxy.xml \
        >${PKG_DIR}/lib/svc/manifest/wavefront-proxy.xml

    sed "s|__PREFIX__|$PKG_PREFIX|g" ${ROOT}/smf/method/wavefront-proxy \
        >${PKG_DIR}/lib/svc/method/wavefront-proxy
    chmod 755 ${PKG_DIR}/lib/svc/method/wavefront-proxy


    fpm --verbose -v $PKG_VER -n $PKG_NAME -s dir -t $PKG_TYPE \
        --description="Wavefront proxy server" --vendor=Wavefront \
        --license="Apache 2.0" -C $PKG_DIR  -f \
        --url=https://github.com/wavefrontHQ/java \
        -p $PKG_ARTEFACT --prefix=$PKG_PREFIX $(ls ${PKG_DIR})
}

#--------------------------------------------------------------------------
# SCRIPT STARTS HERE

[[ $(uname -s) == "SunOS" ]] || die "this is not a SunOS system"

if [[ $# == 1 || $# == 2 ]]
then
    VER=$1
else
    print "usage: ${0##*/} <version> [install]"
    exit 1
fi

[[ $2 == "install" ]] && INSTALL_DEPS=true

grep -q Solaris /etc/release && IS_SOLARIS=true
setup_env

check_for java

java -version 2>&1 | grep -q '1\.8' || die "Needs Java 8"

check_for mvn
check_for git
get_wf_source $VER
#WORK_DIR=/tmp/tmp_08.327

MVN=$(which mvn)
SRC_DIR=${WORK_DIR}/java-${VER}
ARTEFACT=${SRC_DIR}/proxy/target/proxy-${VER##*-}-bin.tar.gz

[[ -d $SRC_DIR ]] || die "no source at ${SRC_DIR}."

build_proxy

[[ -s $ARTEFACT ]] \
    || die "No artefact at ${ARTEFACT}. Build at $SRC_DIR" 4 1

if which fpm >/dev/null 2>&1
then
    build_package
    print "package at $PKG_ARTEFACT"
else
    mv $ARTEFACT $HOME
    print "tarball at ${HOME}/${ARTEFACT##*/}"
fi

rm -fr $WORK_DIR
exit 0
