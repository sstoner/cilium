# envoy
FROM mirrors.tencent.com/tcs-infra/cilium-envoy:1177896bebde79915fe5f9092409bf0254084b4e as cilium-envoy

#
# cilium builer
#
FROM mirrors.tencent.com/tcs-infra/cilium-builder:2020-11-09-v1.9 as builder
WORKDIR /go/src/github.com/cilium/cilium
COPY . ./

RUN make PKG_BUILD=1 SKIP_DOCS=true GOARCH=amd64 DESTDIR=/tmp/install \
    build-container install-container licenses-all

FROM mirrors.tencent.com/tcs-infra/cilium-runtime:2020-11-09-v1.9
COPY --from=cilium-envoy / /
COPY ./tcs-build/hubble /usr/bin/hubble
COPY --from=builder /tmp/install /
COPY --from=builder /go/src/github.com/cilium/cilium/plugins/cilium-cni/cni-install.sh /cni-install.sh
COPY --from=builder /go/src/github.com/cilium/cilium/plugins/cilium-cni/cni-uninstall.sh /cni-uninstall.sh
COPY --from=builder /go/src/github.com/cilium/cilium/contrib/packaging/docker/init-container.sh /init-container.sh
COPY --from=builder /go/src/github.com/cilium/cilium/LICENSE.all /LICENSE.all
WORKDIR /home/cilium

ENV INITSYSTEM="SYSTEMD"
CMD ["/usr/bin/cilium"]