FROM alpine:latest

# Install dependencies
RUN apk add --no-cache \
    curl \
    jq \
    py3-pip \
    bash \
    && pip3 install awscli --break-system-packages \
    && rm -rf /var/cache/apk/*

# Install Infisical CLI
RUN curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.alpine.sh' | bash \
    && apk add infisical

# Add the update script
COPY update-ecr-token.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/update-ecr-token.sh

ENTRYPOINT ["/usr/local/bin/update-ecr-token.sh"]
