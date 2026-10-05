# syntax=docker/dockerfile:1
ARG BASE_IMAGE="antilax3/wolfi:latest"

# set versions for ipmi_exporter and freeipmi
# renovate: datasource=github-releases depName=ipmi_exporter packageName=prometheus-community/ipmi_exporter
ARG IPMIEXPORTER_VERSION="1.10.1"
# renovate: datasource=custom.freeipmi depName=freeipmi
ARG FREEIPMI_VERSION="1.6.20"

FROM --platform=${BUILDPLATFORM} ${BASE_IMAGE} AS build

ARG TARGETARCH
ARG IPMIEXPORTER_VERSION
ARG FREEIPMI_VERSION

SHELL ["/bin/ash", "-euo", "pipefail", "-c"]

RUN <<'EOF'
set -euo pipefail

# the key freeipmi's maintainer signs its releases with, as listed in the gnu keyring
FREEIPMI_KEY="A865A9FB6F0387624468543A3EFB7C4BE8303927"

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

# docker names architectures the way go and ipmi_exporter do; apk and the toolchain use the kernel's names
case "${TARGETARCH}" in
  amd64) TARGET_APK_ARCH="x86_64" ;;
  arm64) TARGET_APK_ARCH="aarch64" ;;
  *) echo "no ipmi_exporter build is published for ${TARGETARCH}" >&2; exit 1 ;;
esac

IPMIEXPORTER_RELEASE="https://github.com/prometheus-community/ipmi_exporter/releases/download/v${IPMIEXPORTER_VERSION}"
IPMIEXPORTER_TARBALL="ipmi_exporter-${IPMIEXPORTER_VERSION}.linux-${TARGETARCH}.tar.gz"
FREEIPMI_RELEASE="https://ftp.gnu.org/gnu/freeipmi"
FREEIPMI_TARBALL="freeipmi-${FREEIPMI_VERSION}.tar.gz"

if ls /lib/ld-musl-* > /dev/null 2>&1; then
  TARGET_TRIPLE="${TARGET_APK_ARCH}-alpine-linux-musl"
  BUILD_PACKAGES="clang curl gnupg lld llvm make"
  SYSROOT_PACKAGES="argp-standalone gcc libgcrypt-dev musl-dev"
else
  case "${TARGET_APK_ARCH}" in
    x86_64) TARGET_TRIPLE="x86_64-pc-linux-gnu" ;;
    aarch64) TARGET_TRIPLE="aarch64-unknown-linux-gnu" ;;
  esac
  BUILD_PACKAGES="clang curl gnupg-dirmngr gpg lld llvm make"
  SYSROOT_PACKAGES="gcc glibc-dev libgcrypt-dev"
fi

echo "**** install build packages ****"
# shellcheck disable=SC2086 # the package lists are deliberately word split.
apk add --no-cache ${BUILD_PACKAGES}

echo "**** create ${TARGET_TRIPLE} sysroot ****"
mkdir -p /tmp/keys
for key in /etc/apk/keys/* "/usr/share/apk/keys/${TARGET_APK_ARCH}"/*; do
  cp "${key}" /tmp/keys/
done
# shellcheck disable=SC2086 # as above.
apk add --no-cache --arch "${TARGET_APK_ARCH}" --root /sysroot --initdb --no-scripts --keys-dir /tmp/keys \
  --repositories-file /etc/apk/repositories ${SYSROOT_PACKAGES}

cd /tmp

GNUPGHOME="$(mktemp -d)"
export GNUPGHOME

echo "**** download ipmi_exporter ****"
# The exporter publishes its checksums unsigned beside the release, so the manifest is trusted over https alone.
curl -fsSLO "${IPMIEXPORTER_RELEASE}/sha256sums.txt"
curl -fsSLO "${IPMIEXPORTER_RELEASE}/${IPMIEXPORTER_TARBALL}"
grep " ${IPMIEXPORTER_TARBALL}$" sha256sums.txt | sha256sum -c -
mkdir -p /out/app
tar -xzf "${IPMIEXPORTER_TARBALL}" -C /out/app --strip-components=1

echo "**** build freeipmi ****"
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
./configure \
  --build="$(clang -dumpmachine)" \
  --host="${TARGET_TRIPLE}" \
  CC="clang --target=${TARGET_TRIPLE} --sysroot=/sysroot -fuse-ld=lld" \
  LD="ld.lld" \
  AR="llvm-ar" \
  NM="llvm-nm" \
  RANLIB="llvm-ranlib" \
  STRIP="llvm-strip" \
  CPP_FOR_BUILD="/usr/bin/clang-cpp" \
  ac_cv_func_mmap_fixed_mapped="yes" \
  ac_cv_file__dev_random="yes" \
  ac_cv_file__dev_urandom="yes"
make -j"$(nproc)"
make install-strip DESTDIR=/out
EOF

FROM ${BASE_IMAGE}

# set version label
ARG build_date
ARG version
LABEL build_date="${build_date}"
LABEL version="${version}"
LABEL maintainer="Nightah"

# set working directory
WORKDIR /app

# copy local files
COPY --link root/ /
COPY --link --from=build /out/ /

# install runtime packages
RUN apk add --no-cache \
  libgcrypt

# ports and volumes
EXPOSE 9290
