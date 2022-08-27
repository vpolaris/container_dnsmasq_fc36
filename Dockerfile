ARG sysroot=/mnt/sysroot
ARG TFTPSERVER="127.0.0.1"
ARG IPRANGE="192.168.0.0"

FROM fedora:36 as builder
ARG sysroot
ARG TFTPSERVER
ARG IPRANGE
ARG DISTVERSION=36
ARG DNFOPTION="--setopt=install_weak_deps=False --nodocs"

#update builder
RUN dnf makecache && dnf -y update && dnf -y install gettext
#install system
RUN dnf -y --installroot=${sysroot} ${DNFOPTION} --releasever ${DISTVERSION} install glibc setup shadow-utils

RUN yes | rm -f ${sysroot}/dev/null \
    &&mknod -m 600 ${sysroot}/dev/initctl p \
    && mknod -m 666 ${sysroot}/dev/full c 1 7 \
    && mknod -m 666 ${sysroot}/dev/null c 1 3 \
    && mknod -m 666 ${sysroot}/dev/ptmx c 5 2 \
    && mknod -m 666 ${sysroot}/dev/random c 1 8 \
    && mknod -m 666 ${sysroot}/dev/tty c 5 0 \
    && mknod -m 666 ${sysroot}/dev/tty0 c 4 0 \
    && mknod -m 666 ${sysroot}/dev/urandom c 1 9


#dhcpd prerequisites
RUN dnf -y --installroot=${sysroot} ${DNFOPTION} --releasever ${DISTVERSION} install --noautoremove busybox dbus-libs gmp libidn2 libnetfilter_conntrack libselinux nettle pcre 
RUN dnf -y --installroot=${sysroot} ${DNFOPTION} --releasever ${DISTVERSION} install --downloadonly --downloaddir=./ dnsmasq initscripts 

COPY ./script.sh "${sysroot}/script.sh"

# RUN echo -n  << EOF  > ${sysroot}/script.sh \
    # #!/bin/bash \
    # PATH=/usr/sbin:/usr/bin \
    # cd /usr/bin \
    # ls /usr/sbin/ \
    # /usr/sbin/busybox --list \
    # for i in $(/usr/sbin/busybox --list); do /usr/sbin/busybox ln -s /usr/sbin/busybox $i; done\
    # EOF \\n\
RUN chmod +u+x "${sysroot}/script.sh" && chroot ${sysroot} /script.sh && rm "${sysroot}/script.sh"

# RUN ARCH="$(uname -m)" \
    # && TLSRPM="$(ls gnutls*${ARCH}.rpm)" \
    # && rpm -ivh --root=${sysroot}  --nodeps --excludedocs ${TLSRPM}

#install dnsmasq
RUN ARCH="$(uname -m)" \
    && DNSMPRPM="$(ls dnsmasq*${ARCH}.rpm)" \
    && DNSMVERSION=$(sed -e "s/dnsmasq-\(.*\)\.${ARCH}.rpm/\1/" <<< $DNSMPRPM) \
    && rpm -ivh --root=${sysroot}  --nodeps --excludedocs ${DNSMPRPM} \
    && printf ${DNSMVERSION} > ${sysroot}/dnsmasq.version

RUN cat << EOF | tee ${sysroot}/etc/sysconfig/network \
    NETWORKING=yes \
    HOSTNAME=localhost.localdomain\
    EOF
 
 COPY "./dnsmasq.conf" "${sysroot}/root/dnsmasq.template"
 COPY "./dnsmasq.service" "${sysroot}/etc/rc.d/init.d/dnsmasq.service"
 COPY "./entrypoint.sh"  "${sysroot}/bin/entrypoint.sh"


RUN chmod u+x  "${sysroot}/etc/rc.d/init.d/dnsmasq.service" "${sysroot}/bin/entrypoint.sh" 

ENV TINI_VERSION v0.19.0
ADD "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini" "${sysroot}/tini"
RUN chmod +x "${sysroot}/tini"

RUN cp "/usr/bin/envsubst" "${sysroot}/usr/bin/envsubst" \
    && envsubst '${TFTPSERVER} ${IPRANGE}'< "${sysroot}/root/dnsmasq.template" > "${sysroot}/etc/dnsmasq.conf"

 
#clean up
RUN dnf -y --installroot=${sysroot} ${DNFOPTION} --releasever ${DISTVERSION} remove shadow-utils

RUN dnf -y --installroot=${sysroot} ${DNFOPTION} --releasever ${DISTVERSION} install --noautoremove libselinux

RUN ARCH="$(uname -m)" \
    && INITRPM="$(ls initscripts*${arch}.rpm)" \
    && rpm -ivh --root=${sysroot}  --nodeps --excludedocs ${INITRPM}
    
RUN dnf -y --installroot=${sysroot} ${DNFOPTION} --releasever ${DISTVERSION}  autoremove \    
    && dnf -y --installroot=${sysroot} ${DNFOPTION} --releasever ${DISTVERSION}  clean all \
    && rm -rf ${sysroot}/usr/{{lib,share}/locale,{lib,lib64}/gconv,bin/localedef,sbin/build-locale-archive} \
#  docs and man pages       
    && rm -rf ${sysroot}/usr/share/{man,doc,info,gnome/help} \
#  purge log files
    && rm -f ${sysroot}/var/log/*|| exit 0 \
#  cracklib
    && rm -rf ${sysroot}/usr/share/cracklib \
#  i18n
    && rm -rf ${sysroot}/usr/share/i18n \
#  packaging
    && rm -rf ${sysroot}/var/cache/dnf/ \
    && mkdir -p --mode=0755 ${sysroot}/var/cache/dnf/ \
    && rm -f ${sysroot}//var/lib/dnf/history.* \
    && rm -f ${sysroot}//usr/lib/sysimage/rpm/* \
#  sln
    && rm -rf ${sysroot}/sbin/sln \
#  ldconfig
    && rm -rf ${sysroot}/etc/ld.so.cache ${sysroot}/var/cache/ldconfig \
    && mkdir -p --mode=0755 ${sysroot}/var/cache/ldconfig

FROM scratch 
ARG sysroot
ARG TFTPSERVER
ARG IPRANGE
COPY --from=builder ${sysroot} /
ENV DISTTAG=f36container FGC=f36 FBR=f36 container=podman
ENV DISTRIB_ID fedora
ENV DISTRIB_RELEASE 36
ENV PLATFORM_ID "platform:f36"
ENV DISTRIB_DESCRIPTION "Fedora 36 Container"
ENV TZ UTC
ENV LANG C.UTF-8
ENV TERM xterm
ENV TFTPSERVER=${TFTPSERVER}
ENV IPRANGE=${IPRANGE}
# 67 udp for DHCP and 53 for DNS
EXPOSE 67/udp 53
ENTRYPOINT ["./tini", "--", "/bin/entrypoint.sh"]
CMD ["start"]
