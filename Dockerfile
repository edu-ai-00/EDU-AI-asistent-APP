# Stage 1: Build Flutter web app
FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app
COPY . .

ARG API_URL=https://app-api.edu-ai.eu

RUN flutter pub get
RUN flutter build web --release --dart-define=API_URL=${API_URL}

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
