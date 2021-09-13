#!/usr/bin/env bash
set -e
set -u

source profile.sh

docker build --progress plain -t web-server .
docker stop web-server || true
docker rm web-server || true
docker run -d \
    --name web-server \
    --env "MENDIX_USERNAME=${MENDIX_USERNAME}" \
    --env "MENDIX_API_KEY=${MENDIX_API_KEY}" \
    --env "MENDIX_PASSWORD=${MENDIX_PASSWORD}" \
    --env "GITHUB_API_KEY=${GITHUB_API_KEY}" \
    --env "GITHUB_OWNER=${GITHUB_OWNER}" \
    --env "APPCENTER_API_KEY=${APPCENTER_API_KEY}" \
    --env "APPCENTER_OWNER=${APPCENTER_OWNER}" \
    --env "MENDIX_APP_ID"="jam-make-it-native" \
    --env "ANDROID_KEY_ALIAS"="jam-make-it-native" \
    --env "ANDROID_KEY_STORE_PASSWORD"="bnGHJ76%^&" \
    --env "IOS_CERTIFICATE_PASSWORD"="hjkDF6980%^" \
    --env "APP_STORE_CONNECT_API_ISSUER_ID=${APP_STORE_CONNECT_API_ISSUER_ID}" \
    --env "APP_STORE_CONNECT_API_KEY_ID=${APP_STORE_CONNECT_API_KEY_ID}" \
    --env "APP_STORE_CONNECT_API_KEY=${APP_STORE_CONNECT_API_KEY}" \
    --env "REBUILD_IOS_PROFILE"="true" \
    --env "SKIP_SIGNING"="false" \
    --volume "${PWD}/signing/:/signing/" \
    web-server
    
docker start web-server
docker logs -f web-server

# docker exec -it web-server /bin/bash