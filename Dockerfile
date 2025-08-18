FROM scratch
COPY build/gateway /app
CMD ["/app"]
