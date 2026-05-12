FROM golang:1.21 AS builder

WORKDIR /go/src/app
COPY catgpt/go.mod catgpt/go.sum ./
RUN go mod download

COPY catgpt/. .
RUN CGO_ENABLED=0 go build -o /go/bin/app

FROM gcr.io/distroless/static-debian12:latest-amd64 AS runtime

COPY --from=builder /go/bin/app /
EXPOSE 8080 9090
CMD ["/app"]