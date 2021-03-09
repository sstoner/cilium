#!/bin/bash

# run `TCE_ARCH=x86 sh tce_build.sh` for test locally

set -o nounset
set -o errexit
set -o pipefail

cd $( dirname "${BASH_SOURCE[0]}" )

# ******** global variables begin ********
REGISTRY=registry.tce.com/infra
PUBLIC_REGISTRY=mirrors.tencent.com/tcs-infra

# currently not supported cross-platform compile, just for future extension
GOOS=linux
GOARCH=""
TCE_BUILD_DIR=./tce_build

if [ x"${TCE_ARCH-}" = x"arm" ]; then
    GOARCH=arm64
    TCE_BUILD_DIR=./tce_build.arm
elif [ x"${TCE_ARCH-}" = x"x86" ]; then
    GOARCH=amd64
else
    echo "unsupported TCE_ARCH ${TCE_ARCH}"
    exit 1
fi

rm -rf $TCE_BUILD_DIR && mkdir -p $TCE_BUILD_DIR

TAG=v1.9.0
GIT_SHA=$(git rev-parse --short HEAD)
VERSION=${TAG}-${GIT_SHA}-${GOARCH}
CILIUM_IMAGE=${REGISTRY}/cilium:${VERSION}
CILIUM_OPERATOR_IMAGE=${REGISTRY}/cilium-operator-generic:${VERSION}
HUBBLE_RELAY_IMAGE=${REGISTRY}/cilium-hubble-relay:${VERSION}

# ******** global variables end ********
if [ x"${TCE_ARCH-}" = x"arm" ]; then
    wget -O tcs-build/qemu-aarch64-static https://github.com/multiarch/qemu-user-static/releases/download/v3.0.0/qemu-aarch64-static
fi

# make cilium image

curl --fail --show-error --silent --location "https://github.com/cilium/hubble/releases/download/v0.7.1/hubble-linux-${GOARCH}.tar.gz" --output "/tmp/hubble.tgz"
tar -C "./tcs-build" -xf "/tmp/hubble.tgz" hubble
docker build -f tcs-build/cilium-${GOARCH}.Dockerfile -t ${CILIUM_IMAGE} .
docker save ${CILIUM_IMAGE} | gzip > ${TCE_BUILD_DIR}/cilium.tar.gz

# make cilium-operator image
cd operator && make cilium-operator-generic && cd ..
docker build -f tcs-build/cilium-operator-generic-${GOARCH}.Dockerfile -t ${CILIUM_OPERATOR_IMAGE} .
docker save ${CILIUM_OPERATOR_IMAGE} | gzip > ${TCE_BUILD_DIR}/cilium-operator.tar.gz

# make cilium-hubble-relay image
cd hubble-relay && make hubble-relay && cd ..
docker build -f tcs-build/hubble-relay-${GOARCH}.Dockerfile -t ${HUBBLE_RELAY_IMAGE} .
docker save ${HUBBLE_RELAY_IMAGE} | gzip > ${TCE_BUILD_DIR}/cilium-hubble-relay.tar.gz

function save_image() {
  image=$1
  tag=$2
  retag=$3
  docker pull ${PUBLIC_REGISTRY}/${image}:${tag}
  docker tag ${PUBLIC_REGISTRY}/${image}:${tag} ${REGISTRY}/${image}:${retag}
  docker save ${REGISTRY}/${image}:${retag} | gzip > ${TCE_BUILD_DIR}/${image}.tar.gz
}

# envoy/nginx/busybox multi-arch-support
save_image hubble-ui v0.7.3 v0.7.3
save_image hubble-ui-backend v0.7.3-${GOARCH} v0.7.3
save_image envoy v1.14.5 v1.14.5
# nginx and busybox used to test
save_image nginx latest latest
save_image busybox latest latest

# make helm install
cp -r install/kubernetes/cilium ${TCE_BUILD_DIR}/helm
cp tcs-build/helm-values.yaml ${TCE_BUILD_DIR}/helm/values.yaml
cp tcs-build/helm-cilium-configmap.yaml ${TCE_BUILD_DIR}/helm/templates/cilium-configmap.yaml
sed -i "s#{{ REGISTRY }}#${REGISTRY}#g" ${TCE_BUILD_DIR}/helm/values.yaml
sed -i "s#{{ TAG }}#${VERSION}#g" ${TCE_BUILD_DIR}/helm/values.yaml
sed -i "s#1.9.0#${TAG}#g" ${TCE_BUILD_DIR}/helm/Chart.yaml

cd ${TCE_BUILD_DIR}
tar zcf helm.tar.gz helm && rm -r helm
