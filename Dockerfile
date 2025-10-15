# Use Alpine Linux as base image for smaller size
FROM alpine:3.18

# Install required packages
RUN apk add --no-cache \
    openssl \
    jq \
    coreutils \
    ca-certificates \
    curl

# Create app directory
WORKDIR /app

# Copy the SSL checker script
COPY ssl_checker.sh /app/ssl_checker.sh

# Make the script executable
RUN chmod +x /app/ssl_checker.sh

# Create a volume mount point for JSON files
VOLUME ["/app/data"]

# Set the default command
ENTRYPOINT ["/app/ssl_checker.sh"]

# Default argument (can be overridden)
CMD ["/app/data/hostnames.json"]