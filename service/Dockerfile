FROM golang:1.25-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git ca-certificates

COPY go.mod go.sum* ./
RUN go mod download

ARG APP_VERSION=0.2.0

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -v -ldflags="-s -w -X main.Version=${APP_VERSION}" -o /app/server .

FROM alpine:3.21

WORKDIR /app

RUN apk add --no-cache ca-certificates tzdata

COPY --from=builder /app/server /app/server

ENV PORT=8080
EXPOSE 8080

CMD ["/app/server"]
