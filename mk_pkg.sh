#!/bin/ksh

DIR=/tmp/build_pkg
rm -fr $DIR

FSROOT=${DIR}/root

PREFIX="/opt/local"
INST=${FSROOT}/${PREFIX}

mkdir -p ${INST}/lib/svc/method ${INST}/lib/svc/manifest \
	 ${INST}/wavefront/lib \
	 ${INST}/etc/wavefront ${FSROOT}/var/wavefront \
	 ${FSROOT}/var/log/wavefront

sed "s|__PREFIX__|$PREFIX|" ./smf/method/wavefront-proxy \
	>${INST}/lib/svc/method/wavefront-proxy
chmod 755 ${INST}/lib/svc/method/wavefront-proxy

sed "s|__PREFIX__|$PREFIX|" ./smf/manifest/wavefront-proxy.xml \
	>${INST}/lib/svc/manifest/wavefront-proxy.xml

cp /root/wavefront-push-agent.jar ${INST}/wavefront/lib/

find $DIR -type f >${DIR}/pkglist

pkg_info -X pkg_install \
	| egrep '^(MACHINE_ARCH|OPSYS|OS_VERSION|PKGTOOLS_VERSION)' \
	>${DIR}/build-info

print "Wavefront Proxy" >${DIR}/comment
print "Wavefront Proxy" >${DIR}/description

cat ${DIR}/pkglist

pkg_create \
	-B ${DIR}/build-info \
	-d ${DIR}/description \
	-c ${DIR}/comment \
	-f ${DIR}/pkglist \
	-I $PREFIX \
	-p $PREFIX \
	-u root \
	-g root \
	-U \
	wavefront-proxy.tgz

