FROM node:20-alpine
ARG FIREBASE_VERSION=13.11.2
RUN apk --no-cache add openjdk11-jre bash curl openssl gettext nano nginx sudo && \
    npm cache clean --force && \
    npm i -g firebase-tools@$FIREBASE_VERSION

# copy the firebase directory (directory defined in the docker-compose build context)
# to the working directory
COPY . /srv/firebase
COPY emulator/nginx.conf /etc/nginx/
COPY emulator/serve.sh /usr/bin/

RUN chmod +x /usr/bin/serve.sh

WORKDIR /srv/firebase

ENTRYPOINT ["/usr/bin/serve.sh"]
