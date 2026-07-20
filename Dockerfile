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

RUN flutter pub get
RUN flutter build web --release \
    --dart-define=API_URL=${API_URL} \
    --dart-define=GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID} \
    --dart-define=MICROSOFT_CLIENT_ID=${MICROSOFT_CLIENT_ID} \
    --dart-define=MICROSOFT_TENANT_ID=${MICROSOFT_TENANT_ID}

# Cache-busting: append build timestamp to JS URLs so CDN caches are bypassed
RUN BUILD_VER=$(date +%s) && \
    sed -i "s|flutter_bootstrap.js|flutter_bootstrap.js?v=${BUILD_VER}|g" build/web/index.html && \
    sed -i "s|\"main.dart.js\"|\"main.dart.js?v=${BUILD_VER}\"|g" build/web/flutter_bootstrap.js

# Stage 2: Serve with nginx
FROM nginx:alpine

RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
