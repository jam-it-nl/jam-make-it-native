# MxBuild works on Mono 5.18.0.240 
# Curl >= 7.76.0 -> --fail-with-body support

FROM node:16

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get -yq upgrade
RUN apt-get install -yq jq
RUN apt-get install -yq gettext-base
RUN apt-get install -yq npm
RUN apt-get install -yq ruby-full
RUN apt-get install -yq default-jdk

RUN npm install -g appcenter-cli
RUN npm install -g @mendix/native-mobile-toolkit fs-extra

RUN gem install jwt

COPY docker .

RUN apt remove -yq curl && apt purge curl
COPY docker/curl-i386 /usr/bin/curl
RUN chmod +x /usr/bin/curl

ENV SKIP_SIGNING="false"
ENV REBUILD_IOS_PROFILE="true"

ENTRYPOINT ["./entrypoint.sh"]