ARG ELIXIR_IMAGE=elixir:1.20-otp-29-slim
FROM ${ELIXIR_IMAGE} AS build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential ca-certificates git && rm -rf /var/lib/apt/lists/*
ENV MIX_ENV=prod
WORKDIR /src
COPY apps/arion_control_plane apps/arion_control_plane
COPY apps/arion_ctl apps/arion_ctl
WORKDIR /src/apps/arion_ctl
RUN mix local.hex --force && mix local.rebar --force && mix deps.get --only prod --check-locked && mix release
FROM ${ELIXIR_IMAGE}
RUN useradd --create-home --uid 10001 arion && mkdir -p /var/lib/arion-ctl && chown arion:arion /var/lib/arion-ctl
WORKDIR /app
COPY --from=build --chown=arion:arion /src/apps/arion_ctl/_build/prod/rel/arion_ctl ./
USER arion
ENV ARION_CTL_STATE_DIR=/var/lib/arion-ctl
EXPOSE 50051
ENTRYPOINT ["/app/bin/arionctl"]
CMD ["serve"]
