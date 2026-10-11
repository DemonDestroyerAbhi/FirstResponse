# Build from the repo root:  docker build -f apps/api/Dockerfile -t api .
FROM dart:3.13.5 AS build
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
COPY packages/core_rules/pubspec.yaml packages/core_rules/
COPY apps/api/pubspec.yaml apps/api/
# Only the server and its engine are copied in, so drop the other
# workspace members (the Flutter app also needs the Flutter SDK).
RUN sed -i -e '/  - apps\/app/d' -e '/  - apps\/site/d' pubspec.yaml \
    && dart pub get
COPY packages/core_rules packages/core_rules
COPY apps/api apps/api
COPY rules rules
RUN dart compile exe apps/api/bin/server.dart -o /server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /server /app/server
COPY --from=build /src/rules /app/rules
ENV RULES_DIR=/app/rules PORT=8080
EXPOSE 8080
USER 65534
ENTRYPOINT ["/app/server"]
