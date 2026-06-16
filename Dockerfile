FROM rust:1.93-alpine AS builder
WORKDIR /app
RUN apk add --no-cache musl-dev pkgconfig openssl-dev openssl-libs-static
ENV CARGO_TARGET_DIR=/usr/src/app/output
COPY . .
RUN rustup target add x86_64-unknown-linux-musl && cargo build --release --target x86_64-unknown-linux-musl

FROM scratch
COPY --from=builder /usr/src/app/output/x86_64-unknown-linux-musl/release/svc-gateway /app
CMD ["/app"]
