ARG ARCH=frommakefile
ARG DISTRIB=frommakefile
ARG DOCKERSRC=frommakefile
ARG USERNAME=frommakefile
#
FROM ${USERNAME}/${DOCKERSRC}:${DISTRIB}_${ARCH}
#
RUN apt-get update && apt-get -y -q install --no-install-recommends bind9 bind9utils dnsutils net-tools procps lsof glusterfs-client&& apt-get clean && rm -rf /var/cache/apt/* /var/lib/apt/lists/*

ADD entrypoint.sh /usr/local/entrypoint.sh
RUN chmod 755 /usr/local/entrypoint.sh
RUN chown bind:bind /etc/bind/
ENTRYPOINT ["/usr/local/entrypoint.sh"]
