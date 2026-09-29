# PANNA authoritative game server (Swift/Vapor). Build context: repo root.
FROM swift:6.0-jammy AS build
WORKDIR /build
COPY Packages ./Packages
COPY Server ./Server
WORKDIR /build/Server
RUN swift build -c release --product PannaServer --static-swift-stdlib

FROM ubuntu:jammy
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libcurl4 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /build/Server/.build/release/PannaServer /app/PannaServer
ENV DATA_DIR=/data
EXPOSE 8080
CMD ["/app/PannaServer"]
