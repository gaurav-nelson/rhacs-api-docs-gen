# RHACS API Documentation Generator

This is a simple tool to generate API documentation for RHACS. It uses the [OpenAPI Generator](https://openapi-generator.tech/) to generate the documentation.

## Usage

To generate the documentation:

1. Open your `openshift-docs` repository and create a new branch.
   ```bash
    cd openshift-docs
    git checkout -b <branch-name>
    ```
2. Run the docker container to generate the documentation.
   ```bash
    docker run --rm -it -v "$(pwd)":/rhacs-api-docs-gen quay.io/ganelson/rhacs-api-docs-gen generate
    ```
3. Enter the version of RHACS you want to generate the documentation for.
   ```bash
    Please provide the version number of the RHACS release (e.g., 4.5.1): <version>
    ```
4. The documentation gets generated in the `api` directory.
5. Copy the output form the terminal and update the `_topic_map.yml` file:
   ```yaml
    - Name: API reference
      Dir: api
      Distros: openshift-acs
      Topics:
        - Name: AdministrationEventService
          File: AdministrationEventService
        - Name: AdministrationUsageService
          File: AdministrationUsageService

    ```
