#!/usr/bin/env bash
################################################################################
#  PROJECT: Squeak Bundle Generation
#  FILE:    prepare.sh
#  CONTENT: Generate different bundles such as the All-in-One.
#
#  AUTHORS: Fabio Niephaus, Hasso Plattner Institute, Potsdam, Germany
#           Marcel Taeumel, Hasso Plattner Institute, Potsdam, Germany
################################################################################

set -o errexit

if [[ -z "${TRAVIS_BUILD_DIR}" ]]; then
  echo "Script needs to run on Travis CI"
  exit 1
fi

readonly FILES_BASE="http://files.squeak.org/base"
readonly RELEASE_URL="${FILES_BASE}/${TRAVIS_SMALLTALK_VERSION/Etoys/Squeak}"
readonly IMAGE_URL="${RELEASE_URL}/base.zip"
readonly VM_BASE="${RELEASE_URL}"
readonly TARGET_URL="https://www.hpi.uni-potsdam.de/hirschfeld/artefacts/squeak/"

readonly TEMPLATE_DIR="${TRAVIS_BUILD_DIR}/templates"
readonly AIO_TEMPLATE_DIR="${TEMPLATE_DIR}/all-in-one"
readonly LIN_TEMPLATE_DIR="${TEMPLATE_DIR}/linux"
readonly MAC_TEMPLATE_DIR="${TEMPLATE_DIR}/macos"
readonly WIN_TEMPLATE_DIR="${TEMPLATE_DIR}/win"

readonly BUILD_DIR="${TRAVIS_BUILD_DIR}/build"
readonly PRODUCT_DIR="${TRAVIS_BUILD_DIR}/product"
readonly TMP_DIR="${TRAVIS_BUILD_DIR}/tmp"
readonly ENCRYPTED_DIR="${TRAVIS_BUILD_DIR}/encrypted"

readonly LOCALE_DIR="${TRAVIS_BUILD_DIR}/locale"
readonly RELEASE_NOTES_DIR="${TRAVIS_BUILD_DIR}/release-notes"

readonly VM_LIN="vm-linux"
readonly VM_MAC="vm-macos"
readonly VM_WIN="vm-win"
readonly VM_ARM6="vm-armv6"

# Extract encrypted files
unzip -q .encrypted.zip
if [[ ! -d "${ENCRYPTED_DIR}" ]]; then
  echo "Failed to locate decrypted files."
  exit 1
fi

# Prepare signing
KEY_CHAIN=macos-build.keychain
security create-keychain -p travis "${KEY_CHAIN}"
security default-keychain -s "${KEY_CHAIN}"
security unlock-keychain -p travis "${KEY_CHAIN}"
security set-keychain-settings -t 3600 -u "${KEY_CHAIN}"
security import "${ENCRYPTED_DIR}/sign.cer" -k ~/Library/Keychains/"${KEY_CHAIN}" -T /usr/bin/codesign
security import "${ENCRYPTED_DIR}/sign.p12" -k ~/Library/Keychains/"${KEY_CHAIN}" -P "${CERT_PASSWORD}" -T /usr/bin/codesign

# Create build, product, and temp folders
mkdir "${BUILD_DIR}" "${PRODUCT_DIR}" "${TMP_DIR}"

echo "...downloading and extracting macOS VM..."
curl -f -s --retry 3 -o "${TMP_DIR}/${VM_MAC}.zip" "${VM_BASE}/${VM_MAC}.zip"
unzip -q "${TMP_DIR}/${VM_MAC}.zip" -d "${TMP_DIR}/${VM_MAC}"

echo "...downloading and extracting Linux VM..."
curl -f -s --retry 3 -o "${TMP_DIR}/${VM_LIN}.zip" "${VM_BASE}/${VM_LIN}.zip"
unzip -q "${TMP_DIR}/${VM_LIN}.zip" -d "${TMP_DIR}/${VM_LIN}"

echo "...downloading and extracting Windows VM..."
curl -f -s --retry 3 -o "${TMP_DIR}/${VM_WIN}.zip" "${VM_BASE}/${VM_WIN}.zip"
unzip -q "${TMP_DIR}/${VM_WIN}.zip" -d "${TMP_DIR}/${VM_WIN}"

is_64bit() {
  [[ "${TRAVIS_SMALLTALK_VERSION}" == *"-64" ]]
}

is_32bit() {
  ! is_64bit
}

is_etoys() {
  [[ "${TRAVIS_SMALLTALK_VERSION}" == "Etoys"* ]]
}

compress() {
  target=$1
  echo "...compressing the bundle..."
  pushd "${BUILD_DIR}" > /dev/null
  # tar czf "${PRODUCT_DIR}/${target}.tar.gz" "./"
  zip -q -r "${PRODUCT_DIR}/${target}.zip" "./"
  popd > /dev/null
  # Reset $BUILD_DIR
  rm -rf "${BUILD_DIR}" && mkdir "${BUILD_DIR}"
  echo "...done."
}

copy_resources() {
  local target=$1
  echo "...copying image files into bundle..."
  cp "${TMP_DIR}/Squeak.image" "${target}/${IMAGE_NAME}.image"
  cp "${TMP_DIR}/Squeak.changes" "${target}/${IMAGE_NAME}.changes"
  cp "${TMP_DIR}/"*.sources "${target}/"
  cp -R "${RELEASE_NOTES_DIR}" "${target}/"
  cp -R "${TMP_DIR}/locale" "${target}/"
  if is_etoys; then
    cp "${TMP_DIR}/"*.pr "${target}/"
    cp -R "${TMP_DIR}/ExampleEtoys" "${target}/"
  fi
}

travis_fold() {
  local action=$1
  local name=$2
  local title="${3:-}"

  if [[ "${TRAVIS:-}" = "true" ]]; then
    echo -en "travis_fold:${action}:${name}\r\033[0K"
  fi
  if [[ -n "${title}" ]]; then
    echo -e "\033[34;1m${title}\033[0m"
  fi
}

# ARMv6 currently only supported on 32-bit
if is_32bit; then
  echo "...downloading and extracting ARMv6 VM..."
  curl -f -s --retry 3 -o "${TMP_DIR}/${VM_ARM6}.zip" "${VM_BASE}/${VM_ARM6}.zip"
  unzip -q "${TMP_DIR}/${VM_ARM6}.zip" -d "${TMP_DIR}/${VM_ARM6}"
fi

source "prepare_image.sh"
source "prepare_aio.sh"
source "prepare_mac.sh"
source "prepare_lin.sh"
source "prepare_win.sh"
if is_32bit; then
  source "prepare_armv6.sh"
fi

if [[ "${TRAVIS_BRANCH}" == "master" ]]; then
  echo "...uploading all files to files.squeak.org..."
  TARGET_PATH="/var/www/files.squeak.org"
  if is_etoys; then
    TARGET_PATH="${TARGET_PATH}/etoys/${SQUEAK_VERSION/Etoys/}"
  else
    TARGET_PATH="${TARGET_PATH}/${SQUEAK_VERSION/Squeak/}"
  fi
  chmod 600 "${ENCRYPTED_DIR}/ssh_deploy_key"
  rsync -crvz -e "ssh -i ${ENCRYPTED_DIR}/ssh_deploy_key" "${PRODUCT_DIR}/" "${ENCRYPTED_HOST}:${TARGET_PATH}/"
  echo "...done."
else
  echo "...not uploading files because this is not the master branch."
fi

# Remove sensitive information
rm -rf "${ENCRYPTED_DIR}"
security delete-keychain "${KEY_CHAIN}"
