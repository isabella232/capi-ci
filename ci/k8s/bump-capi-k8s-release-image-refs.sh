#!/bin/bash

set -eu -o pipefail

MESSAGE_FILE="$(mktemp)"

function get_image_digest_for_resource () {
  pushd $1 >/dev/null
    echo "$(cat digest)"
  popd >/dev/null
}

CAPI_IMAGE="cloudfoundry/cloud-controller-ng@$(get_image_digest_for_resource capi-docker-image)"
NGINX_IMAGE="cloudfoundry/capi-nginx@$(get_image_digest_for_resource nginx-docker-image)"
CONTROLLERS_IMAGE="cloudfoundry/cf-api-controllers@$(get_image_digest_for_resource cf-api-controllers-docker-image)"
PACKAGE_IMAGE_UPLOADER_IMAGE="cloudfoundry/cf-api-package-image-uploader@$(get_image_digest_for_resource package-image-uploader-docker-image)"

CCNG_DIR="cloud_controller_ng"
CF_API_CONTROLLERS_DIR="cf-api-controllers"
PACKAGE_IMAGE_UPLOADER_DIR="package-image-uploader"
NGINX_DIR="capi-nginx"

function bump_image_references() {
    cat <<- EOF > "${PWD}/update-images.yml"
---
- type: replace
  path: /images/ccng
  value: ${CAPI_IMAGE}
- type: replace
  path: /images/nginx
  value: ${NGINX_IMAGE}
- type: replace
  path: /images/cf_api_controllers
  value: ${CONTROLLERS_IMAGE}
- type: replace
  path: /images/package_image_uploader
  value: ${PACKAGE_IMAGE_UPLOADER_IMAGE}
EOF

    pushd "capi-k8s-release"
      bosh interpolate values/images.yml -o "../update-images.yml" > values-int.yml

      echo "#@data/values" > values/images.yml
      echo "---" >> values/images.yml
      cat values-int.yml >> values/images.yml
    popd
}

function make_git_commit() {
    shopt -s dotglob
    pushd "capi-k8s-release"
      git config user.name "${GIT_COMMIT_USERNAME}"
      git config user.email "${GIT_COMMIT_EMAIL}"
      git add values/images.yml

      # dont make a commit if there aren't new images
      if ! git diff --cached --exit-code; then
        ./scripts/generate-shortlog.sh
        echo "committing!"
        git commit -F <(./scripts/generate-shortlog.sh)
      fi
    popd

    cp -R "capi-k8s-release/." "updated-capi-k8s-release"
}

bump_image_references
make_git_commit
