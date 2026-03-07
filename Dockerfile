FROM rust:1.93-alpine as builder
WORKDIR /app
COPY . .
RUN rustup target add x86_64-unknown-linux-musl && cargo build --release --target x86_64-unknown-linux-musl

FROM scratch
COPY --from=builder /usr/src/app/target/x86_64-unknown-linux-musl/release/svc-gateway /app
CMD ["/app"]
