# rebar3 is needed for esqlite3 
FROM --platform=linux/amd64 ghcr.io/gleam-lang/gleam:v1.2.0-rc2-elixir AS base

COPY . .

FROM base AS build

RUN gleam export erlang-shipment

# FROM --platform=linux/amd64 docker.io/erlang:alpine AS release
# FROM --platform=linux/amd64 ghcr.io/gleam-lang/gleam:v1.2.0-rc2-elixir AS release
FROM --platform=linux/amd64 cgr.dev/chainguard/erlang:latest AS release
WORKDIR /app

COPY --from=build /build/erlang-shipment .

# var/lib/sqlite

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]