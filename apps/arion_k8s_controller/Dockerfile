ARG ELIXIR_IMAGE=elixir:1.20-otp-29-slim
FROM ${ELIXIR_IMAGE} AS build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential ca-certificates git && rm -rf /var/lib/apt/lists/*
ENV MIX_ENV=prod
WORKDIR /src
COPY apps/arion_control_plane apps/arion_control_plane
COPY apps/arion_k8s_controller apps/arion_k8s_controller
WORKDIR /src/apps/arion_k8s_controller
RUN mix local.hex --force && mix local.rebar --force && mix deps.get --only prod --check-locked && mix release
FROM ${ELIXIR_IMAGE}
RUN useradd --create-home --uid 10001 arion
WORKDIR /app
COPY --from=build --chown=arion:arion /src/apps/arion_k8s_controller/_build/prod/rel/arion_k8s_controller ./
USER arion
EXPOSE 50051
CMD ["bin/arion_k8s_controller", "start"]
