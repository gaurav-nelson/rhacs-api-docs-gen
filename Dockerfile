# Stage 1: Build the Node.js dependencies
FROM node:22-slim AS build

# Set the working directory
WORKDIR /app

# Copy the package.json and package-lock.json (if available)
COPY package*.json ./

# Install the required Node.js packages
RUN npm ci && npm cache clean --force

# Stage 2: Create the final image
FROM openapitools/openapi-generator-cli:v7.8.0

# Install Node.js and other dependencies
RUN apt-get update && apt-get install -y nodejs

# Set the working directory
WORKDIR /rhacs-api-docs-gen

# Copy the current directory contents into the container at /rhacs-api-docs-gen
COPY ./scripts /rhacs-api-docs-gen

# Copy the Node.js dependencies from the previous stage
COPY --from=build /app/node_modules /rhacs-api-docs-gen/node_modules

# Make the script executable
RUN chmod +x /rhacs-api-docs-gen/rhacs-api-docs-gen.sh

# Entrypoint
ENTRYPOINT ["bash", "/rhacs-api-docs-gen/rhacs-api-docs-gen.sh"]
