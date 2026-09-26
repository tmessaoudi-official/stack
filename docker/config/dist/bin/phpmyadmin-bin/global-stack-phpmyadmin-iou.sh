#!/bin/bash
# iou = install-or-upgrade

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

# Called by global-stack-phpmyadmin-start.sh only when its gate says install; the start
# script writes the marker after this returns. Pin-audit tranche 3 step 21 (rulings
# 2026-09-26 11:17 and 11:43; pinned by startup-prologue.test.sh §73). start.sh used to
# wipe tools/phpmyadmin and its marker BEFORE this script fetched anything; the GitHub
# archives came through `curl -LsS` (no -f, so a 404 page was "downloaded"), and composer
# + yarn then built inside the live dir, so a failed fetch or build left no phpMyAdmin.
# Now the whole tree is downloaded, listed, built and checked in a temp dir, and only then
# replaces the old one. Every failure is a named FATAL that leaves the old tree and the
# marker as they were. A kill mid-copy leaves a partial tree and no new marker, so the
# next boot rebuilds.
_pma_fatal() {
  printf 'FATAL: %s\n' "$1" >&2
  exit 1
}

_pma_v="${GLOBAL_STACK_PHPMYADMIN_VERSION}"
_pma_type="${GLOBAL_STACK_PHPMYADMIN_TYPE_VERSION}"
_pma_dir="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin"
echo -e "\nBuilding phpmyadmin ${_pma_v} (${_pma_type}) ..."

# A GitHub archive's top dir is `phpmyadmin-<ref>`: the FULL sha for a commit
# [measured 2026-09-26], so the listing proves the archive is the commit that was pinned.
case "${_pma_type}" in
  release)
    _pma_asset="phpMyAdmin-${_pma_v}-all-languages.zip"
    _pma_url="https://files.phpmyadmin.net/phpMyAdmin/${_pma_v}/${_pma_asset}"
    _pma_top="phpMyAdmin-${_pma_v}-all-languages"
    ;;
  branch) _pma_url="https://github.com/phpmyadmin/phpmyadmin/archive/refs/heads/${_pma_v}.tar.gz" ;;
  tag) _pma_url="https://github.com/phpmyadmin/phpmyadmin/archive/refs/tags/${_pma_v}.tar.gz" ;;
  commit) _pma_url="https://github.com/phpmyadmin/phpmyadmin/archive/${_pma_v}.tar.gz" ;;
  *) _pma_fatal "phpmyadmin: unknown GLOBAL_STACK_PHPMYADMIN_TYPE_VERSION '${_pma_type}' - phpmyadmin left as it was" ;;
esac
[[ "${_pma_type}" == release ]] || _pma_top="phpmyadmin-${_pma_v}"

_pma_dl="$(mktemp -d)"
if ! curl --connect-timeout 30 --max-time 300 -fsSL -o "${_pma_dl}/archive" "${_pma_url}"; then
  _pma_fatal "phpmyadmin ${_pma_v}: ${_pma_url} could not be downloaded - phpmyadmin left as it was"
fi

mkdir -p "${_pma_dl}/x"
# grep reads the whole listing (no -q): an early exit would SIGPIPE the lister under pipefail.
if [[ "${_pma_type}" == release ]]; then
  if ! curl --connect-timeout 30 --max-time 60 -fsSL -o "${_pma_dl}/archive.sha256" "${_pma_url}.sha256"; then
    _pma_fatal "phpmyadmin ${_pma_v}: ${_pma_url}.sha256 could not be downloaded - phpmyadmin left as it was"
  fi
  if ! _pma_want_sum="$(awk -v n="${_pma_asset}" '$2 == n && length($1) == 64 { print $1 }' "${_pma_dl}/archive.sha256")" \
    || [[ "$(grep -c . <<<"${_pma_want_sum}")" != 1 ]]; then
    _pma_fatal "phpmyadmin ${_pma_v}: its .sha256 lists no single checksum for ${_pma_asset} - phpmyadmin left as it was"
  fi
  if ! printf '%s  %s\n' "${_pma_want_sum}" "${_pma_dl}/archive" | sha256sum -c --quiet - >/dev/null 2>&1; then
    _pma_fatal "phpmyadmin ${_pma_v}: ${_pma_asset} does not match its published SHA-256 - phpmyadmin left as it was"
  fi
  if ! unzip -Z1 "${_pma_dl}/archive" 2>/dev/null | grep -xF "${_pma_top}/index.php" >/dev/null; then
    _pma_fatal "phpmyadmin ${_pma_v}: the download does not hold ${_pma_top}/index.php - phpmyadmin left as it was"
  fi
  unzip -q "${_pma_dl}/archive" -d "${_pma_dl}/x"
else
  if ! tar -tzf "${_pma_dl}/archive" 2>/dev/null | grep -xF "${_pma_top}/index.php" >/dev/null; then
    _pma_fatal "phpmyadmin ${_pma_v}: the download does not hold ${_pma_top}/index.php - phpmyadmin left as it was"
  fi
  tar -C "${_pma_dl}/x" -xzf "${_pma_dl}/archive"
fi
_pma_tree="${_pma_dl}/x/${_pma_top}"

# A source archive is built here, in the temp dir; a release zip ships built. The
# composer.json rename predates this step and moves verbatim (its reason is unrecorded).
if [[ "${_pma_type}" != release ]]; then
  if ! (cd "${_pma_tree}" \
    && sed -i 's/"name": "phpmyadmin\/phpmyadmin",/"name": "phpmyadmin\/phpmyadminx",/' composer.json \
    && composer install --ignore-platform-reqs \
    && yarn install \
    && yarn build); then
    _pma_fatal "phpmyadmin ${_pma_v}: the build failed (composer install / yarn) - phpmyadmin left as it was"
  fi
fi
# shellcheck disable=SC2016  # $argv is PHP's, not the shell's
if [[ ! -f "${_pma_tree}/index.php" ]] || ! php -r 'require $argv[1];' "${_pma_tree}/vendor/autoload.php"; then
  _pma_fatal "phpmyadmin ${_pma_v}: the built tree has no loadable vendor/autoload.php - phpmyadmin left as it was"
fi

# Checked: from here on the old tree is replaced whole.
rm -rf "${_pma_dir}"
mv -T "${_pma_tree}" "${_pma_dir}"
sudo chmod -R a+rwx "${_pma_dir}/"
sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" "${_pma_dir}/"
rm -rf "${_pma_dl}"
