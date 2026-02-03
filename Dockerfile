# Use full rust image so rustup is available for wasm32 target
# Rust 1.85+ required for edition 2024 (async-graphql-value used by linera-service)
# Use explicit version so --no-cache rebuild pulls correct image
FROM rust:1.85.0-bookworm

SHELL ["bash", "-c"]

RUN apt-get update && apt-get install -y \
    pkg-config \
    protobuf-compiler \
    clang \
    make

RUN rustup target add wasm32-unknown-unknown
RUN cargo install --locked linera-service@0.15.7 linera-storage-service@0.15.7

RUN apt-get update && apt-get install -y curl
RUN curl https://raw.githubusercontent.com/creationix/nvm/v0.40.3/install.sh | bash \
    && . ~/.nvm/nvm.sh \
    && nvm install lts/krypton \
    && npm install -g pnpm

WORKDIR /build

HEALTHCHECK CMD ["curl", "-s", "http://localhost:5173"]

ENTRYPOINT bash /build/run.bash