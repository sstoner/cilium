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
CNI_PLUGIN_VERSION=v0.8.7
KUBE_PROXY_TAG=v1.16.6
GIT_SHA=$(git rev-parse --short HEAD)
VERSION=${TAG}-${GIT_SHA}-${GOARCH}
CILIUM_IMAGE=${REGISTRY}/cilium:${VERSION}
CILIUM_OPERATOR_IMAGE=${REGISTRY}/cilium-operator-generic:${VERSION}
HUBBLE_RELAY_IMAGE=${REGISTRY}/cilium-hubble-relay:${VERSION}

# ******** global variables end ********
# download plugins
if [ x"${TCE_ARCH-}" = x"arm" ]; then
    wget -O tcs-build/qemu-aarch64-static https://github.com/multiarch/qemu-user-static/releases/download/v3.0.0/qemu-aarch64-static
fi
wget -O tcs-build/cni-plugins.tgz https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGIN_VERSION}/cni-plugins-linux-${GOARCH}-${CNI_PLUGIN_VERSION}.tgz
tar xvf tcs-build/cni-plugins.tgz -C tcs-build

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

# pull kube-proxy image
git clone --branch ${KUBE_PROXY_TAG}-tcs-develop git@git.code.oa.com:tce-platform/inf/kubernetes.git /tmp/kubernetes && cd /tmp/kubernetes
KUBE_PROXY_COMMIT=$(git rev-parse --short=8 HEAD)
KUBE_PROXY_IMAGE_VERSION=${KUBE_PROXY_TAG}-${KUBE_PROXY_COMMIT}
cd - && rm -r /tmp/kubernetes

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
save_image kube-proxy ${KUBE_PROXY_IMAGE_VERSION}-${GOARCH} ${KUBE_PROXY_IMAGE_VERSION}

# make cilium chart
mkdir ${TCE_BUILD_DIR}/charts
cp -r install/kubernetes/cilium ${TCE_BUILD_DIR}/charts/
cp tcs-build/charts/cilium/values.yaml ${TCE_BUILD_DIR}/charts/cilium/values.yaml
cp tcs-build/charts/cilium/templates/* ${TCE_BUILD_DIR}/charts/cilium/templates/
sed -i "s#{{ REGISTRY }}#${REGISTRY}#g" ${TCE_BUILD_DIR}/charts/cilium/values.yaml
sed -i "s#{{ TAG }}#${VERSION}#g" ${TCE_BUILD_DIR}/charts/cilium/values.yaml
sed -i "s#1.9.0#${TAG}#g" ${TCE_BUILD_DIR}/charts/cilium/Chart.yaml
# make kube-proxy-cilium chart
cp -r tcs-build/charts/kube-proxy-cilium ${TCE_BUILD_DIR}/charts/
sed -i "s#repository: registry.tce.com/infra/kube-proxy#repository: ${REGISTRY}/kube-proxy#g" ${TCE_BUILD_DIR}/charts/kube-proxy-cilium/values.yaml
sed -i "s#tag: v1.16.6-db03827a#tag: ${KUBE_PROXY_IMAGE_VERSION}#g" ${TCE_BUILD_DIR}/charts/kube-proxy-cilium/values.yaml

cd ${TCE_BUILD_DIR}
tar zcf charts.tar.gz charts && rm -r charts
