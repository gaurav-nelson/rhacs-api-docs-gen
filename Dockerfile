# Use the OpenAPI Generator CLI as the base image
FROM openapitools/openapi-generator-cli:v7.8.0

# Install Node.js and other dependencies
RUN apt-get update && apt-get install -y nodejs

# Set the working directory
WORKDIR /rhacs-api-docs-gen

# Copy the current directory contents into the container at /rhacs-api-docs-gen
COPY . .

# Make the script executable
RUN chmod +x rhacs-api-docs-gen.sh

# Entrypoint
ENTRYPOINT ["bash", "rhacs-api-docs-gen.sh"]
