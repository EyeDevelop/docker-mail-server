FROM alpine:latest

# Install bash.
RUN apk add -U bash

# Add the config files to a template directory.
RUN mkdir -p /template
COPY config/dovecot /template/dovecot
COPY config/postfix /template/postfix

# Run the entrypoint.
COPY entrypoint.sh /
CMD ["/entrypoint.sh"]