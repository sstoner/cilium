#### Base image copy from master branch: https://github.com/cilium/cilium/blob/master/images/cilium/Dockerfile
# envoy
FROM mirrors.tencent.com/tcs-infra/cilium-envoy:1bfbbd9c85907c5667f1abd24b7a6c1b5d8bbf29-arm64 as cilium-envoy

#
# cilium builer
# Have no idea why running failed when using mirrors.tencent.com/tcs-infra/cilium-builder
# instead of quay.io/cilium/cilium-builder in arm scenes.
FROM quay.io/cilium/cilium-builder:309d6c32ce304efe7490876be24804622f698999 as builder
WORKDIR /go/src/github.com/cilium/cilium
COPY . ./

RUN export CC=aarch64-linux-gnu-gcc && \
    make PKG_BUILD=1 GOARCH=arm64 SKIP_DOCS=true DESTDIR=/tmp/install \
    build-container install-container licenses-all

FROM mirrors.tencent.com/tcs-infra/cilium-runtime-arm64:tcs-v2.1.0
COPY ./tcs-build/portmap /opt/cni/bin/
COPY ./tcs-build/hubble /usr/bin/hubble
COPY --from=cilium-envoy / /
COPY --from=builder /tmp/install /
COPY --from=builder /go/src/github.com/cilium/cilium/plugins/cilium-cni/cni-install.sh /cni-install.sh
COPY --from=builder /go/src/github.com/cilium/cilium/plugins/cilium-cni/cni-uninstall.sh /cni-uninstall.sh
COPY --from=builder /go/src/github.com/cilium/cilium/contrib/packaging/docker/init-container.sh /init-container.sh
COPY --from=builder /go/src/github.com/cilium/cilium/LICENSE.all /LICENSE.all
WORKDIR /home/cilium

ENV INITSYSTEM="SYSTEMD"
CMD ["/usr/bin/cilium"]