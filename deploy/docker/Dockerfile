FROM golang:1.22-alpine AS builder
RUN apk add --no-cache git ca-certificates tzdata
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o /out/zanzipay-server ./cmd/zanzipay-server/

FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /out/zanzipay-server /zanzipay-server
COPY config.yaml /config.yaml
EXPOSE 50053 8090 9090
ENTRYPOINT ["/zanzipay-server", "--config", "/config.yaml"]
