# Build from the REPOSITORY ROOT (the server shares the game's simulation code):
#   docker build -f server/Dockerfile -t inktide-server .
#   docker run -p 8080:8080 inktide-server
# NOTE: written from Dart's documented Docker recipe but not run in this repo's
# test environment - build it once before relying on it.
FROM dart:stable AS build
WORKDIR /app
COPY lib/game/sim ./lib/game/sim
COPY lib/game/net ./lib/game/net
COPY server ./server
WORKDIR /app/server
RUN dart pub get && dart compile exe bin/server.dart -o /app/inktide_server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/inktide_server /app/inktide_server
ENV PORT=8080
EXPOSE 8080
CMD ["/app/inktide_server"]
