FROM antilax3/alpine

# set version label
ARG build_date
ARG version
LABEL build_date=$build_date
LABEL version=$version
LABEL maintainer="Nightah"

# set application versions
ARG ARCH="amd64"
ARG IPMIEXPORTER_VERSION="1.4.0"
ARG FREEIPMI_VER="1.6.8"

# set working directory
WORKDIR /app

# copy local files
COPY root/ /

COPY freeipmi-argp-redefine.patch /tmp/freeipmi-${FREEIPMI_VER}/

RUN \
echo "**** install build packages ****" && \
    apk add --no-cache --virtual=build-dependencies \
	curl \
	gcc \
	make \
	musl-dev \
	patch && \
echo "**** install runtime packages ****" && \
    apk add --no-cache \
    libgcrypt-dev && \
    cd /tmp && \
    curl -Lfs -o ipmi_exporter.tar.gz https://github.com/soundcloud/ipmi_exporter/releases/download/v${IPMIEXPORTER_VERSION}/ipmi_exporter-${IPMIEXPORTER_VERSION}.linux-${ARCH}.tar.gz && \
    tar xfz ipmi_exporter.tar.gz -C /app --strip-components 1 && \
    curl -Lfs -o freeipmi.tar.gz https://ftp.gnu.org/gnu/freeipmi/freeipmi-${FREEIPMI_VER}.tar.gz && \
    tar xfz freeipmi.tar.gz && \
    cd freeipmi-${FREEIPMI_VER} && \
    patch -p 0 < freeipmi-argp-redefine.patch && \
    CPPFLAGS="-Dgetmsg\(a,b,c,d\)=errno=-1,-1 -Dputmsg\(a,b,c,d\)=errno=-1,-1" ./configure && \
    make && \
    make install && \
echo "**** Cleanup ****" && \
    apk del --purge \
	build-dependencies && \
    rm -rf /tmp/*

# ports and volumes
EXPOSE 9290