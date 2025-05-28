# Stage 1: Build the Node.js dependencies
FROM node:24-slim AS build

# Set the working directory
WORKDIR /app

# Copy the package.json and package-lock.json
COPY package*.json ./

# Install the required Node.js packages
RUN npm ci && \
    npm cache clean --force && \
    rm -rf /app/node_modules/.cache

# Stage 2: Create the final image
FROM openapitools/openapi-generator-cli:v7.13.0

# Install Node.js and other dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends nodejs git zip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /rhacs-api-docs-gen

# Copy the current directory contents into the container at /rhacs-api-docs-gen
COPY ./scripts /rhacs-api-docs-gen

# Copy the Node.js dependencies from the previous stage
COPY --from=build /app/node_modules /rhacs-api-docs-gen/node_modules

# Make the scripts executable
RUN chmod +x /rhacs-api-docs-gen/rhacs-api-docs-gen.sh && \
    chmod +x /rhacs-api-docs-gen/generate-and-package-docs.sh && \
    chmod +x /rhacs-api-docs-gen/fix_tags.sh

# Entrypoint
ENTRYPOINT ["bash", "/rhacs-api-docs-gen/rhacs-api-docs-gen.sh"]
