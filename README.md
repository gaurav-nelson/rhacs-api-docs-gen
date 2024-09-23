# RHACS API Documentation Generator

This is a simple tool to generate API documentation for RHACS. It uses the [OpenAPI Generator](https://openapi-generator.tech/) to generate the documentation.

## Usage


![image](https://github.com/user-attachments/assets/8cccd4ab-9c9d-4ba4-bfbb-c7a7b3004775)

To generate the documentation:

1. Open your `openshift-docs` repository and create a new branch:
   ```bash
    cd openshift-docs
    git checkout -b <branch-name>
    ```
2. Pull the latest image:
   ```bash
    docker pull quay.io/ganelson/rhacs-api-docs-gen
   ```
2. Run the docker container to generate the documentation:
   ```bash
    docker run --rm -it -v "$(pwd)":/openshift-docs quay.io/ganelson/rhacs-api-docs-gen generate
    ```
3. Enter the version of RHACS you want to generate the documentation for:
   ```bash
    Please provide the version number of the RHACS release (e.g., 4.5.1): <version>
    ```
4. `rhacs-api-docs-gen` generates the documentation in the `rest_api` directory and updates the `_topic_map.yml` file with the new API documentation.
