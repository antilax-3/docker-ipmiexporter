# syntax=docker/dockerfile:1
FROM antilax3/alpine:latest

# set version label
ARG build_date
ARG version
LABEL build_date="${build_date}"
LABEL version="${version}"
LABEL maintainer="Nightah"

# set versions for ipmi_exporter and freeipmi
# renovate: datasource=github-releases depName=ipmi_exporter packageName=prometheus-community/ipmi_exporter
ARG IPMIEXPORTER_VERSION="1.10.0"
# renovate: datasource=custom.freeipmi depName=freeipmi
ARG FREEIPMI_VERSION="1.6.19"

# set working directory
WORKDIR /app

# copy local files
COPY root/ /

SHELL ["/bin/ash", "-euo", "pipefail", "-c"]

RUN <<'EOF'
set -euo pipefail

# the key freeipmi's maintainer signs its releases with, as listed in the gnu keyring
FREEIPMI_KEY="A865A9FB6F0387624468543A3EFB7C4BE8303927"

# Imports one key from the first keyserver that returns a usable copy. keys.openpgp.org serves keys with their user
# IDs stripped until the address is verified, and gnupg skips a key with no user ID while still exiting zero, so a
# keyserver has only worked once the key is listed.
recv_key() {
  local key="${1}" keyserver

  for keyserver in keys.openpgp.org keyserver.ubuntu.com; do
    gpg --batch --keyserver "${keyserver}" --recv-keys "${key}" || true
    if gpg --batch --list-keys "${key}" > /dev/null 2>&1; then
      return 0
    fi
  done

  return 1
}

# ipmi_exporter names its builds by go's architecture names, not the distribution's
case "$(apk --print-arch)" in
  x86_64) IPMIEXPORTER_ARCH="amd64" ;;
  aarch64) IPMIEXPORTER_ARCH="arm64" ;;
  *) echo "no ipmi_exporter build is published for $(apk --print-arch)" >&2; exit 1 ;;
esac

IPMIEXPORTER_RELEASE="https://github.com/prometheus-community/ipmi_exporter/releases/download/v${IPMIEXPORTER_VERSION}"
IPMIEXPORTER_TARBALL="ipmi_exporter-${IPMIEXPORTER_VERSION}.linux-${IPMIEXPORTER_ARCH}.tar.gz"
FREEIPMI_RELEASE="https://ftp.gnu.org/gnu/freeipmi"
FREEIPMI_TARBALL="freeipmi-${FREEIPMI_VERSION}.tar.gz"

echo "**** install runtime packages ****"
apk add --no-cache \
  libgcrypt

echo "**** install build packages ****"
apk add --no-cache --virtual=build-dependencies \
  argp-standalone \
  curl \
  gcc \
  gnupg \
  libgcrypt-dev \
  make \
  musl-dev

cd /tmp

GNUPGHOME="$(mktemp -d)"
export GNUPGHOME

echo "**** install ipmi_exporter ****"
# The exporter publishes its checksums unsigned beside the release, so the manifest is trusted over https alone.
curl -fsSLO "${IPMIEXPORTER_RELEASE}/sha256sums.txt"
curl -fsSLO "${IPMIEXPORTER_RELEASE}/${IPMIEXPORTER_TARBALL}"
grep " ${IPMIEXPORTER_TARBALL}$" sha256sums.txt | sha256sum -c -
tar -xzf "${IPMIEXPORTER_TARBALL}" -C /app --strip-components=1

echo "**** install freeipmi ****"
if ! recv_key "${FREEIPMI_KEY}"; then
  echo "no keyserver returned a usable copy of the freeipmi signing key ${FREEIPMI_KEY}" >&2
  exit 1
fi
curl -fsSLO "${FREEIPMI_RELEASE}/${FREEIPMI_TARBALL}"
curl -fsSLO "${FREEIPMI_RELEASE}/${FREEIPMI_TARBALL}.sig"
gpg --batch --verify "${FREEIPMI_TARBALL}.sig" "${FREEIPMI_TARBALL}"
gpgconf --kill all
tar -xzf "${FREEIPMI_TARBALL}"
cd "freeipmi-${FREEIPMI_VERSION}"
# musl has no argp, and freeipmi's bundled fallback no longer compiles, so it links the static argp-standalone
# instead, as alpine's own freeipmi package does.
./configure
make -j"$(nproc)"
make install
cd /tmp

echo "**** cleanup ****"
apk del --purge \
  build-dependencies
rm -rf \
  "${GNUPGHOME}" \
  /tmp/*
EOF

# ports and volumes
EXPOSE 9290
