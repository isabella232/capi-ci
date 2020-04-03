#!/bin/bash

set -eux -o pipefail

export CF_FOR_K8s_DIR="${PWD}/cf-for-k8s"
export SERVICE_ACCOUNT_KEY="${PWD}/${GOOGLE_KEY_FILE_PATH}"

function getImageReference () {
  pushd $1 >/dev/null
    echo "$(cat repository)@$(cat digest)"
  popd >/dev/null
}

echo "Logging into gcloud..."
gcloud auth activate-service-account \
  "${GOOGLE_SERVICE_ACCOUNT_EMAIL}" \
  --key-file="${GOOGLE_KEY_FILE_PATH}" \
  --project="${GOOGLE_PROJECT_NAME}"

echo "Updating images..."
echo "Updating ccng image to cloud_controller_ng git SHA: $(cat capi-docker-image/rootfs/cloud_controller_ng/head-tag-file)"
echo "Updating nginx image to cloud_controller_ng git SHA: $(cat capi-docker-image/rootfs/nginx-docker-image/head-tag-file)"
echo "Updating watcher image to cloud_controller_ng git SHA: $(cat capi-docker-image/rootfs/capi_kpack_watcher/head-tag-file)"

cat <<- EOF > "${PWD}/update-images.yml"
---
- type: replace
  path: /images/ccng
  value: $(getImageReference capi-docker-image)
- type: replace
  path: /images/nginx
  value: $(getImageReference nginx-docker-image)
- type: replace
  path: /images/capi_kpack_watcher
  value: $(getImageReference watcher-docker-image)
EOF

pushd "capi-k8s-release"
  bosh interpolate values.yml -o "../update-images.yml" > values-int.yml

  echo "#@data/values" > values.yml
  echo "---" >> values.yml
  cat values-int.yml >> values.yml

  scripts/bump-cf-for-k8s.sh
popd

source "capi-ci-private/${CAPI_ENVIRONMENT_NAME}/.envrc"
pushd "cf-for-k8s"
  hack/generate-values.sh -d "${CAPI_ENVIRONMENT_NAME}.capi.land" -g "${SERVICE_ACCOUNT_KEY}" > cf-install-values.yml
  bin/install-cf.sh ./cf-install-values.yml
popd

cp cf-for-k8s/cf-install-values.yml env-metadata/cf-install-values.yml
bosh interpolate --path /cf_admin_password cf-for-k8s/cf-install-values.yml > env-metadata/cf-admin-password.txt
echo "${CAPI_ENVIRONMENT_NAME}.capi.land" > env-metadata/dns-domain.txt

cat > env-metadata/integration_config.json << EOF
{
  "api": "api.${CAPI_ENVIRONMENT_NAME}.capi.land",
  "apps_domain": "${CAPI_ENVIRONMENT_NAME}.capi.land",
  "admin_user": "admin",
  "admin_password": "$(cat env-metadata/cf-admin-password.txt)",
  "skip_ssl_validation": true
}
EOF
