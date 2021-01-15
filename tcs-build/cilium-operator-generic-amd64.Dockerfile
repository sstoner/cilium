FROM mirrors.tencent.com/tcs-infra/alpine:3.12-amd64 as certs
RUN echo "http://mirrors.tencent.com/alpine/v3.12/main/" > /etc/apk/repositories  \
    && echo "http://mirrors.tencent.com/alpine/v3.12/community" >> /etc/apk/repositories
RUN apk --update add ca-certificates

FROM mirrors.tencent.com/tcs-infra/alpine:3.12-amd64
COPY ./operator/cilium-operator-generic /usr/bin/cilium-operator-generic
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
WORKDIR /
CMD ["/usr/bin/cilium-operator-generic"]
