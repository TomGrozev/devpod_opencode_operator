# syntax=docker/dockerfile:1.7

# Builder: Elixir 1.19.5 (latest 1.19.x) / OTP 28.5.0.2 / Debian bookworm (non-slim).
# Elixir 1.19.4 was never published to Docker Hub; 1.19.5 is the equivalent
# patch within the same 1.19 minor that mix.exs requires. We use the non-slim
# variant (not `-slim`) because the slim variant ships without a /etc/passwd
# entry for root, and OTP 28's `user` application refuses to start with
# `nouser` even during `mix local.hex --force`. CI builds the linux/amd64
# target; this digest resolves to a multi-arch image with both amd64 and
# arm64 manifests.
# Resolved from: hexpm/elixir:1.19.5-erlang-28.5.0.2-debian-bookworm-20260623 (non-slim, multi-arch manifest)
# Pinned by digest for reproducibility.
ARG BUILDER_IMAGE="hexpm/elixir@sha256:869a275662c893b3f4971e7a19781d2c806b04ca2390fc9b9f5bc46ebec225f4"
# Runtime: Debian bookworm slim, latest published date tag.
# Resolved from: debian:bookworm-20260623-slim
# Pinned by digest for reproducibility.
ARG RUNTIME_IMAGE="debian@sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df"

# ---- builder stage ----
FROM ${BUILDER_IMAGE} AS builder

# Build-time env. Keep PROD for a release build.
ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

WORKDIR /build

# Install hex/rebar once (cached layer) and fetch deps.
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy only what `mix deps.get` needs, so the deps layer is cached on dep changes.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

# Now copy the rest of the source and build the release.
COPY config ./config
COPY lib ./lib
RUN mix deps.compile && \
    mix release

# ---- runtime stage ----
FROM ${RUNTIME_IMAGE} AS runtime

# Runtime shared libraries needed by an Elixir release on Debian bookworm-slim.
# libssl3 is required by :ssl; libstdc++6 / libgcc-s1 are pulled in transitively
# by BEAM-included NIFs; ca-certificates for any outbound HTTPS the controller
# does against the K8s API.
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libssl3 \
        libstdc++6 \
        libgcc-s1 \
        tini && \
    rm -rf /var/lib/apt/lists/*

# Non-root user. UID/GID 1000 matches the "restricted" PSS baseline used by
# most distros for the first non-system user.
RUN groupadd --system --gid 1000 app && \
    useradd  --system --uid 1000 --gid app --home-dir /app --shell /sbin/nologin app

WORKDIR /app

# Copy the prepared release from the builder. `--chown` avoids a separate chown layer.
COPY --from=builder --chown=app:app /build/_build/prod/rel/devpod_opencode_operator/ ./

USER app

# tini reaps zombies and forwards signals — important for OTP releases.
ENTRYPOINT ["/usr/bin/tini", "--", "/app/bin/devpod_opencode_operator"]

CMD ["start"]
