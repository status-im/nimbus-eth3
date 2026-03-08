#!/usr/bin/env bash

# Copyright (c) 2026 Status Research & Development GmbH. Licensed under
# either of:
# - Apache License, version 2.0
# - MIT license
# at your option. This file may not be copied, modified, or distributed except
# according to those terms.

set -euo pipefail

SUBREPO_DIR="vendor/nim-eth3-scenarios"
VECTOR_VERSION="v0.4.1"
VECTOR_TARBALL="eth3-lean-spec-vectors-${VECTOR_VERSION}.tar.gz"
VECTOR_OUT_DIR="tests-${VECTOR_VERSION}"

[[ -z "${V:-}" ]] && V=0
[[ -z "${BUILD_MSG:-}" ]] && BUILD_MSG="Downloading Eth3 test vectors"
CACHE_DIR="${1:-}"

dir_has_files() {
  local dir_path="$1"
  [[ -d "${dir_path}" ]] && [[ -n "$(find "${dir_path}" -type f -print -quit)" ]]
}

[[ -d "${SUBREPO_DIR}" ]] || {
  echo "This script should be run from the \"nimbus-eth2\" repo top dir."
  exit 1
}

echo -e "${BUILD_MSG}"
[[ "${V}" == "0" ]] && exec 3>&1 4>&2 &>/dev/null

if [[ -n "${CACHE_DIR}" ]]; then
  mkdir -p "${CACHE_DIR}/tarballs"
  rm -rf "${SUBREPO_DIR}/tarballs"
  ln -s "$(pwd -P)/${CACHE_DIR}/tarballs" "${SUBREPO_DIR}/tarballs"
fi

pushd "${SUBREPO_DIR}" >/dev/null

set +e
./download_test_vectors.sh "${VECTOR_VERSION}"
download_status=$?
set -e

if [[ ${download_status} -ne 0 ]]; then
  tarball_path="tarballs/${VECTOR_VERSION}/${VECTOR_TARBALL}"
  if [[ ! -f "${tarball_path}" ]]; then
    exit "${download_status}"
  fi

  # Work around the current upstream script issue on macOS Bash where an empty
  # EXTRA_TAR array trips `set -u` after the tarball has already been fetched.
  rm -rf "${VECTOR_OUT_DIR}"
  mkdir -p "${VECTOR_OUT_DIR}"
  tar -C "${VECTOR_OUT_DIR}" -xzf "${tarball_path}"
fi

dir_has_files "${VECTOR_OUT_DIR}/test" || {
  echo "Missing or empty Eth3 test vectors in ${SUBREPO_DIR}/${VECTOR_OUT_DIR}/test" >&2
  exit 1
}

dir_has_files "${VECTOR_OUT_DIR}/prod" || {
  echo "Missing or empty Eth3 prod vectors in ${SUBREPO_DIR}/${VECTOR_OUT_DIR}/prod" >&2
  exit 1
}

popd >/dev/null
