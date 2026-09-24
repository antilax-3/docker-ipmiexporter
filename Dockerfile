# syntax=docker/dockerfile:1
FROM antilax3/alpine:latest

# set version label
ARG build_date
ARG version
LABEL build_date="${build_date}"
LABEL version="${version}"
LABEL maintainer="Nightah"

# set versions for ipmi_exporter and freeipmi
ARG ARCH="amd64"
# renovate: datasource=github-releases depName=ipmi_exporter packageName=prometheus-community/ipmi_exporter
ARG IPMIEXPORTER_VERSION="1.10.0"
# renovate: datasource=custom.freeipmi depName=freeipmi
ARG FREEIPMI_VERSION="1.6.19"

# set working directory
WORKDIR /app

# copy local files
COPY root/ /
COPY freeipmi-argp-redefine.patch /tmp/

SHELL ["/bin/ash", "-euo", "pipefail", "-c"]

RUN <<'EOF'
set -euo pipefail

IPMIEXPORTER_RELEASE="https://github.com/prometheus-community/ipmi_exporter/releases/download/v${IPMIEXPORTER_VERSION}"
IPMIEXPORTER_TARBALL="ipmi_exporter-${IPMIEXPORTER_VERSION}.linux-${ARCH}.tar.gz"
FREEIPMI_RELEASE="https://ftp.gnu.org/gnu/freeipmi"
FREEIPMI_TARBALL="freeipmi-${FREEIPMI_VERSION}.tar.gz"

echo "**** install runtime packages ****"
apk add --no-cache \
  libgcrypt

echo "**** install build packages ****"
apk add --no-cache --virtual=build-dependencies \
  curl \
  gcc \
  libgcrypt-dev \
  make \
  musl-dev \
  patch

cd /tmp

echo "**** install ipmi_exporter ****"
curl -fsSLO "${IPMIEXPORTER_RELEASE}/${IPMIEXPORTER_TARBALL}"
tar -xzf "${IPMIEXPORTER_TARBALL}" -C /app --strip-components=1

echo "**** install freeipmi ****"
curl -fsSLO "${FREEIPMI_RELEASE}/${FREEIPMI_TARBALL}"
tar -xzf "${FREEIPMI_TARBALL}"
cd "freeipmi-${FREEIPMI_VERSION}"
# musl has no argp, so freeipmi compiles its bundled copy, which defines the fmtstream helpers inline in a header
# and again in its source. Under c99 inline rules those are redefinitions, and the patch keeps only the header's.
patch -p 0 < /tmp/freeipmi-argp-redefine.patch
./configure
make -j"$(nproc)"
make install
cd /tmp

echo "**** cleanup ****"
apk del --purge \
  build-dependencies
rm -rf \
  /tmp/*
EOF

# ports and volumes
EXPOSE 9290
