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
5. Run the portal build verification script to ensure everything is correct:
   ```bash
    ./scripts/prow-smoke-test.sh -a openshift-acs "Red Hat Advanced Cluster Security" "<version>"
   ```

## Known Issues

### 1. `yamllint` error

You must manually check and update the `_topic_map.yml` file with `yamllint` before committing the changes. The usual errors are:

1. Missing or additional `---` at the beginning of the **API reference** section.
2. No newline at the end of the file.

### 2. Unescaped '<' not allowed in attributes values
The error might be something like `Unescaped '<' not allowed in attributes values, line 70412, column 76 (master.xml, line 70412)`.

To debug this type of error, inspect the generated `master.xml` file at `drupal-build/openshift-acs/rest_api/build/master.xml`.

1. Read the specific line.
    ```
    sed '70412!d' drupal-build/openshift-acs/rest_api/build/master.xml
   <entry align="left" valign="top"><simpara><link linkend="Next_available_tag<emphasis>10__v1_externalbackups_externalBackup.id_patch">Next_available_tag</emphasis>10</link></simpara></entry>
    ```
2. The existence of `Next_available_tag<emphasis>10` is causing this issue. Search for `Next_available_tag__10` in your editor (VS Code) for the matching entry.
3. Fix it by removing all underscores and capitalizing the first character. In this case, change the matching line `| <<Next_available_tag__10_{context}, Next_available_tag__10>>` to `| <<NextAvailableTag10_{context}, NextAvailableTag10>>`.
4. You can also copy the script below and run it locally to fix the these types of tags.
   ```sh
   #!/bin/bash
   DIRECTORY="rest_api"
   if [ ! -d "$DIRECTORY" ]; then
     echo "Directory $DIRECTORY does not exist."
     exit 1
   fi
   find "$DIRECTORY" -type f -name "*.adoc" -exec sed -i.bak -E 's/Next_available_tag__([0-9]+)/NextAvailableTag\1/g; s/Next_Tag__([0-9]+)/NextTag\1/g' {} +
   find "$DIRECTORY" -type f -name "*.adoc" | while read -r file; do
     if [ -f "$file.bak" ]; then
       CHANGES=$(diff -u "$file.bak" "$file" | grep -E '^\+' | grep -vE '^\+\+\+' | wc -l)
       if [ "$CHANGES" -gt 0 ]; then
         echo "Fixed incorrect tags in: $file, Change count: $CHANGES"
       fi
       rm "$file.bak"
     fi
   done
   ```

### 3. Unknown ID or title used as an internal cross reference

You must run the Prow smoke test script and check for Pantheon build errors.

1. Run the smoke test command with the `-a` flag to check for Pantheon build errors:
   ```bash
   ./scripts/prow-smoke-test.sh -a openshift-acs "Red Hat Advanced Cluster Security" "4.6"
   ```
2. The errors will be displayed in the console output.
3. For example, if the error is `Unknown ID or title "AuthServiceUpdateAuthMachineToMachineConfigBody_config__v1_auth_m2m_config.id_put", used as an internal cross reference`. You must search for the ID before the double `__`. That is search for `AuthServiceUpdateAuthMachineToMachineConfigBody_config`. The error in this instance is that there is not ID matching the search term. In the same file you should then search for the matching ID. In this instance it is `AuthServiceUpdateAuthMachineToMachineConfigBodyConfig`. You should then replace the incorrect ID with the correct ID in the adoc file.

## How it works

![image](https://github.com/user-attachments/assets/9388c883-9527-4177-a4e8-2e82f5338562)

## AI-generated content
Parts of the scripts were generated using AI tools.
