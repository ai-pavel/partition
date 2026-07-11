FROM elixir:1.16-slim AS build
WORKDIR /app
ENV MIX_ENV=prod
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile
COPY lib/ lib/
RUN mix compile

FROM elixir:1.16-slim
WORKDIR /app
ENV MIX_ENV=prod
COPY --from=build /app/_build/prod/ ./_build/prod/
COPY --from=build /app/deps/ ./deps/
COPY --from=build /root/.mix/ /root/.mix/
COPY config/ config/
COPY lib/ lib/
COPY mix.exs mix.lock ./
EXPOSE 4000
CMD ["mix", "run", "--no-halt"]