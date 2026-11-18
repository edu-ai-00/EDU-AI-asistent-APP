# Stage 1: Build Flutter web app
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app
COPY . .

ARG API_URL=https://app-api.edu-ai.eu
# OAuth client config baked into the web build (dart-defines are compile-time).
# Fed by Railway service vars of the same name. Google web also has a <meta>
# fallback in index.html; Microsoft web REQUIRES the client id here.
ARG GOOGLE_WEB_CLIENT_ID=
ARG MICROSOFT_CLIENT_ID=
ARG MICROSOFT_TENANT_ID=common
# Sentry (lib/core/monitoring/sentry_setup.dart). Railway passes the commit it
# builds; it names the release, eduai@<pubspec version>+<commit>, so Sentry
# applies this deploy's source maps to this deploy's errors. Without it the
# app keeps the SDK's own eduai@<version>+<build>.
ARG RAILWAY_GIT_COMMIT_SHA=
# An organization auth token (Railway service variable). Set, the build also
# writes source maps, uploads them and deletes them again, so they are never
# served; unset, the build is the same as without Sentry. A failed upload
# never fails the deploy.
ARG SENTRY_AUTH_TOKEN=

RUN flutter pub get
RUN set -e; \
    release=; \
    if [ -n "$RAILWAY_GIT_COMMIT_SHA" ]; then \
      version=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml); \
      release="eduai@${version}+$(printf %s "$RAILWAY_GIT_COMMIT_SHA" | cut -c1-12)"; \
    fi; \
    source_maps=; \
    if [ -n "$SENTRY_AUTH_TOKEN" ]; then source_maps=--source-maps; fi; \
    flutter build web --release $source_maps \
      --dart-define=API_URL=${API_URL} \
      --dart-define=GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID} \
      --dart-define=MICROSOFT_CLIENT_ID=${MICROSOFT_CLIENT_ID} \
      --dart-define=MICROSOFT_TENANT_ID=${MICROSOFT_TENANT_ID} \
      --dart-define=SENTRY_RELEASE=${release}; \
    if [ -n "$SENTRY_AUTH_TOKEN" ]; then \
      SENTRY_RELEASE="$release" dart run sentry_dart_plugin \
        || echo "Sentry source map upload failed; deploying without it" >&2; \
      find build/web -name '*.map' -delete; \
      find build/web -name '*.js' -exec sed -i '/^\/\/# sourceMappingURL=/d' {} +; \
    fi

# Cache-busting: append build timestamp to JS URLs so CDN caches are bypassed.
# The brand icons get the same stamp: they were served "immutable" for a year
# until BR-EK9P6J, so correcting the header alone leaves every client that
# already cached the old logo pinned to it until 2027. A fresh URL is a fresh
# cache key, which is the only thing that reaches those clients.
RUN BUILD_VER=$(date +%s) && \
    sed -i "s|flutter_bootstrap.js|flutter_bootstrap.js?v=${BUILD_VER}|g" build/web/index.html && \
    sed -i "s|\"main.dart.js\"|\"main.dart.js?v=${BUILD_VER}\"|g" build/web/flutter_bootstrap.js && \
    sed -i -E "s#href=\"(apple-touch-icon\.png|favicon-96x96\.png|favicon\.svg|favicon\.ico|manifest\.json)\"#href=\"\1?v=${BUILD_VER}\"#g" build/web/index.html && \
    sed -i -E "s#\"(icons/web-app-manifest-[0-9]+x[0-9]+\.png)\"#\"\1?v=${BUILD_VER}\"#g" build/web/manifest.json

# Stage 2: Serve with nginx
FROM nginx:alpine

RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
