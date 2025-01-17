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
    Please provide the version number of the RHACS release (e.g., 4.6.0): <version>
    ```
4. `rhacs-api-docs-gen` generates the documentation in the `rest_api` directory and updates the `_topic_map.yml` file with the new API documentation.

## Known Issues

### `yamllint` error

You must manually check and update the `_topic_map.yml` file with `yamllint` before committing the changes. The usual errors are:

1. Missing `---` at the beginning of the **API reference** section.
2. No newline at the end of the file.

### Unknown ID or title used as an internal cross reference

You must run the Prow smoke test script and check for Pantheon build errors.

1. Run the smoke test command with the `-a` flag to check for Pantheon build errors:
   ```bash
   ./scripts/prow-smoke-test.sh -a openshift-acs "Red Hat Advanced Cluster Security" "4.6"
   ```
2. The errors will be displayed in the console output.
3. For example, if the error is `Unknown ID or title "AuthServiceUpdateAuthMachineToMachineConfigBody_config__v1_auth_m2m_config.id_put", used as an internal cross reference`. You must search for the ID before the double `__`. That is search for `AuthServiceUpdateAuthMachineToMachineConfigBody_config`. The error in this instance is that there is not ID matching the search term. In the same file you should then search for the matching ID. In this instance it is `AuthServiceUpdateAuthMachineToMachineConfigBodyConfig`. You should then replace the incorrect ID with the correct ID in the adoc file.

## How it works

![image](https://github.com/user-attachments/assets/9388c883-9527-4177-a4e8-2e82f5338562)

