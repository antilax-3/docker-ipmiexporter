#!/usr/bin/env bash
set -u

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../libs/common.sh"

resolve_image "${VARIANT}"
resolve_platform_image "${PLATFORM}" || exit 1

case "${PLATFORM}" in
  amd64) APK_ARCH="x86_64"; ELF_MACHINE="62" ;;
  arm64) APK_ARCH="aarch64"; ELF_MACHINE="183" ;;
  armv7) APK_ARCH="armv7"; ELF_MACHINE="40" ;;
esac

# The user database is read out of /etc/passwd rather than through getent, which not every base ships.
case "${VARIANT}" in
  alpine)
    OS_ID="alpine"; LIBC="musl"; INTERPRETER="/lib/ld-musl-*"
    RUNTIME_PACKAGES="libgcrypt-dev"; BUILD_PACKAGES="curl gcc make musl-dev patch"
    ;;
esac

REVISION="${BUILDKITE_COMMIT}"
FREEIPMI_RELEASE=$(sed -nE 's/^ARG FREEIPMI_VER="(.*)"$/\1/p' "${DOCKERFILE}")
# The freeipmi tools ipmi_exporter shells out to, one per collector.
FREEIPMI_TOOLS="bmc-info ipmi-chassis ipmi-dcmi ipmi-raw ipmi-sel ipmi-sensors ipmimonitoring"
MARKER="__TEST_OUTPUT__"
FAILURES=0

# Runs a shell script inside the container through /init and with-contenv, the same way the
# image's services run, and returns only the script's output (not the s6 startup banner).
run() {
  local options="$1" script="$2"
  # shellcheck disable=SC2086 # options holds multiple docker run flags and must be word split.
  docker run --rm --platform "${DOCKER_PLATFORM}" ${options} "${PLATFORM_IMAGE}" /command/with-contenv sh -c "echo ${MARKER}; ${script}" 2> /dev/null | sed "1,/^${MARKER}\$/d"
}

check() {
  local description="$1" expected="$2" actual="$3"

  if [[ "${actual}" == "${expected}" ]]; then
    echo "ok - ${description}"
  else
    echo "not ok - ${description}"
    echo "    expected: ${expected}"
    echo "    actual:   ${actual}"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "--- :label: Image metadata [${DOCKER_PLATFORM}]"
check "image platform is ${DOCKER_PLATFORM}" "${DOCKER_PLATFORM}" \
  "$(docker image inspect -f '{{.Os}}/{{.Architecture}}{{with .Variant}}/{{.}}{{end}}' "${PLATFORM_IMAGE}" | sed 's|^linux/arm64/v8$|linux/arm64|')"
check "entrypoint is /init" '["/init"]' "$(docker image inspect -f '{{json .Config.Entrypoint}}' "${PLATFORM_IMAGE}")"
check "version label is ${BUILD_TAG}" "${BUILD_TAG}" "$(docker image inspect -f '{{index .Config.Labels "version"}}' "${PLATFORM_IMAGE}")"
check "build_date label is set" "set" "$(docker image inspect -f '{{with index .Config.Labels "build_date"}}set{{end}}' "${PLATFORM_IMAGE}")"
check "OCI revision label is ${REVISION}" "${REVISION}" "$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.revision"}}' "${PLATFORM_IMAGE}")"
check "OCI source label is the GitHub repository" "https://github.com/${GITHUB_REPOSITORY}" \
  "$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.source"}}' "${PLATFORM_IMAGE}")"
check "OCI version label is ${BUILD_TAG}" "${BUILD_TAG}" "$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "${PLATFORM_IMAGE}")"
check "OCI created label is an RFC 3339 timestamp" "valid" \
  "$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.created"}}' "${PLATFORM_IMAGE}" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' && echo valid)"

echo "--- :package: Inherited base image [${VARIANT}]"
check "base is ${OS_ID}" "${OS_ID}" "$(run "" ". /etc/os-release; echo \${ID}")"
check "apk architecture is ${APK_ARCH}" "${APK_ARCH}" "$(run "" "apk --print-arch")"
check "libc is ${LIBC}" "found" "$(run "" "ls ${INTERPRETER} > /dev/null 2>&1 && echo found")"
check "abc passwd entry" "abc:911:911:/config:/bin/false" \
  "$(run "" "grep '^abc:' /etc/passwd | cut -d: -f1,3,4,6,7")"
check "abc is in the users group" "yes" "$(run "" "id -nG abc | tr ' ' '\\n' | grep -qx users && echo yes")"
check "container keeps s6 supervision" "0" "$(docker run --rm --platform "${DOCKER_PLATFORM}" "${PLATFORM_IMAGE}" true > /dev/null 2>&1; echo $?)"

echo "--- :prometheus: IPMI Exporter ${IPMIEXPORTER_RELEASE}"
check "ipmi_exporter version is ${IPMIEXPORTER_RELEASE}" "${IPMIEXPORTER_RELEASE}" \
  "$(run "" "/app/ipmi_exporter --version 2>&1 | sed -nE 's/^ipmi_exporter, version ([^ ]+) .*/\\1/p'")"
check "ipmi_exporter is built for ${APK_ARCH}" "${ELF_MACHINE}" "$(run "" "od -An -tu2 -j18 -N2 /app/ipmi_exporter" | xargs)"
check "port 9290 is exposed" '{"9290/tcp":{}}' "$(docker image inspect -f '{{json .Config.ExposedPorts}}' "${PLATFORM_IMAGE}")"
check "ipmi-exporter service serves metrics on 9290" "4" \
  "$(run "" "for i in \$(seq 1 20); do wget -qO- http://localhost:9290/metrics 2> /dev/null && break; sleep 0.5; done | grep -c '^ipmi_up{'")"
check "ipmi-exporter service runs as abc" "abc" \
  "$(run "" "sleep 1; for p in /proc/[0-9]*; do [ \"\$(cat \${p}/comm 2> /dev/null)\" = ipmi_exporter ] && stat -c %U \${p}; done")"

echo "--- :gear: FreeIPMI ${FREEIPMI_RELEASE}"
check "freeipmi version is ${FREEIPMI_RELEASE}" "ipmi-sensors - ${FREEIPMI_RELEASE}" "$(run "" "ipmi-sensors --version | head -n1")"
check "every freeipmi tool the exporter calls runs" "${FREEIPMI_TOOLS}" \
  "$(run "" "for t in ${FREEIPMI_TOOLS}; do \${t} --version > /dev/null 2>&1 && echo \${t}; done" | xargs)"

echo "--- :package: Packages"
check "runtime packages are installed" "${RUNTIME_PACKAGES}" \
  "$(run "" "for p in ${RUNTIME_PACKAGES}; do apk info -e \${p}; done" | xargs)"
check "build dependencies are removed" "" \
  "$(run "" "for p in build-dependencies ${BUILD_PACKAGES}; do apk info -e \${p}; done" | xargs)"
check "no build artefacts are left behind" "" "$(run "" "ls -d /tmp/* 2> /dev/null" | xargs)"

if [[ ${FAILURES} -gt 0 ]]; then
  echo "^^^ +++"
  echo "${FAILURES} check(s) failed"
  exit 1
fi

echo "All checks passed"
