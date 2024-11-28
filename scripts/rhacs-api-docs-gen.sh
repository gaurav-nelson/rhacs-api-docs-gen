#!/bin/bash

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_message() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Function to print messages with color
print_message_disappearing() {
    local color=$1
    shift
    # Clear the line by printing spaces
    printf "\r\033[K" # \033[K clears the line from the cursor to the end
    printf "${color}%s${NC}" "$@"
}

# Banner
print_banner() {
    cat <<"EOF"
                 ____  _   _    _    ____ ____
                |  _ \| | | |  / \  / ___/ ___|
                | |_) | |_| | / _ \| |   \___ \
                |  _ <|  _  |/ ___ | |___ ___) |
                |_| \_|_| |_/_/   \_\____|____/

    _    ____ ___   ____   ___   ____ ____     ____ _____ _   _
   / \  |  _ |_ _| |  _ \ / _ \ / ___/ ___|   / ___| ____| \ | |
  / _ \ | |_) | |  | | | | | | | |   \___ \  | |  _|  _| |  \| |
 / ___ \|  __/| |  | |_| | |_| | |___ ___) | | |_| | |___| |\  |
/_/   \_|_|  |___| |____/ \___/ \____|____/   \____|_____|_| \_|

EOF
}

# Function to show help message
show_help() {
    # multiline asciiart
    echo -e "${CYAN}"
    print_banner
    printf "${NC}"
    printf "${BLUE}Usage: bash rhacs-api-docs-gen.sh [command]${NC}\n"
    printf "${YELLOW}Commands:${NC}\n"
    printf "  generate  Download the OpenAPI spec and generate AsciiDoc files.\n"
    printf "  clean     Remove the 'api' directory.\n"
    printf "  help      Show this help message.\n"
}

# Function to prompt for version number
prompt_for_version() {
    read -p "$(print_message $YELLOW 'Enter the version number of the RHACS release (e.g., 4.6.0): ')" version
    echo $version
}

# Function to download the OpenAPI specification
download_spec() {
    local version=$1
    local url="https://mirror.openshift.com/pub/rhacs/openapi-spec/${version}/swagger.json"
    local output_file="swagger.json"

    print_message $BLUE "📥 Downloading OpenAPI specification from $url..."
    curl -o $output_file $url

    if [[ $? -ne 0 ]]; then
        print_message $RED "❌ Failed to download the OpenAPI specification."
        exit 1
    fi

    print_message $GREEN "✅ Downloaded OpenAPI specification."
}

# Function to split the OpenAPI specification
split_spec() {
    local input_file=$1
    print_message $BLUE "✂️ Splitting OpenAPI specification..."
    node splitspecwithoutdefinitions.js $input_file

    if [[ $? -ne 0 ]]; then
        print_message $RED "❌ Failed to split the OpenAPI specification."
        exit 1
    fi
    #print_message $GREEN "✅ Split OpenAPI specification."
}

# Function to generate AsciiDoc files
generate_asciidoc() {
    print_message $BLUE "📄 Generating AsciiDoc files..."
    mkdir -p rest_api

    for tag_dir in specs/*/; do
        local tag_name=$(basename "$tag_dir")
        local output_tag_dir="rest_api/$tag_name"
        mkdir -p "$output_tag_dir"

        for spec_file in "$tag_dir"/*.json; do
            local base_name=$(basename "$spec_file" .json)
            local output_file="$output_tag_dir/${base_name//[\{\}]/}.adoc"
            print_message_disappearing $BLUE "🔧 Generating AsciiDoc for $base_name.json..."

            # Generate AsciiDoc files in the output directory, suppressing output
            bash /usr/local/bin/docker-entrypoint.sh generate \
                -i "$spec_file" \
                -g asciidoc \
                -o "$output_tag_dir" >/dev/null 2>&1

            # Rename the generated index.adoc to match the spec file name
            if [ -f "$output_tag_dir/index.adoc" ]; then
                mv "$output_tag_dir/index.adoc" "$output_file"
            else
                print_message $RED "❌ index.adoc not found for $base_name.json."
            fi
        done
    done

    print_message $GREEN "\n✅ Generated AsciiDoc files."
}

# Function to update the AsciiDoc files
update_asciidoc() {
    print_message $BLUE "🔧 Updating AsciiDoc files..."
    # Recursively find all "*.adoc" files in the "api" directory and run the updateasciidoc.js script
    find rest_api -type f -name "*.adoc" | while read -r adoc_file; do
        print_message_disappearing $BLUE "🔧 Updating AsciiDoc for $adoc_file..."
        node updateasciidoc.js "$adoc_file"
        #print_message_disappearing $GREEN "✔ Updated AsciiDoc for $adoc_file."
    done

    print_message $GREEN "\n✅ Updated AsciiDoc files."
}

# Function to remove specific generated spec files and artifacts
remove_spec_files() {
    print_message $BLUE "🧹 Removing generated spec files..."
    rm -rf specs swagger.json
    # Recursively find and delete .openapi-generator-ignore and .openapi-generator files from all folders inside the api directory
    find rest_api -type f -name ".openapi-generator-ignore" -exec rm -f {} +
    find rest_api -type d -name ".openapi-generator" -exec rm -rf {} +

    if [[ $? -ne 0 ]]; then
        print_message $RED "❌ Failed to remove specific generated spec files and artifacts."
        exit 1
    fi

    print_message $GREEN "✅ Removed specific generated spec files."
}

# Function to create topic map
create_topic_map() {
    print_message $BLUE "🗂️ Creating topic map..."

    # Define the root directory and output YAML file
    local ROOT_DIR="rest_api"
    local OUTPUT_FILE="api_reference.yml"

    # Start the YAML structure
    each "---" > "$OUTPUT_FILE"
    echo "Name: API reference" > "$OUTPUT_FILE"
    echo "Dir: $ROOT_DIR" >> "$OUTPUT_FILE"
    echo "Distros: openshift-acs" >> "$OUTPUT_FILE"
    echo "Topics:" >> "$OUTPUT_FILE"

    # Function to process each service directory
    process_service() {
        local service_dir="$1"
        local service_name="$2"

        echo "- Name: $service_name" >> "$OUTPUT_FILE"
        echo "  Dir: $service_name" >> "$OUTPUT_FILE"
        echo "  Topics:" >> "$OUTPUT_FILE"

        # Process each .adoc file in the service directory
        for file in "$service_dir"/*.adoc; do
            if [[ -f "$file" ]]; then
                # Extract the name from the file
                name=$(grep -m 1 '^=' "$file" | sed 's/^= //')
                file_name=$(basename "$file" .adoc) # Remove the .adoc extension
                echo "  - Name: $name" >> "$OUTPUT_FILE"
                echo "    File: $file_name" >> "$OUTPUT_FILE"
            fi
        done
    }

    # Process each service directory
    for service in "$ROOT_DIR"/*/; do
        service_name=$(basename "$service")
        process_service "$service" "$service_name"
    done

    # remove the existing rest_api dir if it exists
    rm -rf /openshift-docs/rest_api

    # copy the rest_api dir to the /openshift-docs/rest_api
    cp -r rest_api /openshift-docs/

    # add new line at the end of the file
    echo "" >> "$OUTPUT_FILE"

    # Update the topic_map.yml file
    node updatetopicmap.js "$(cat $OUTPUT_FILE)"

    print_message $GREEN "✅ Generated topic map."
}

# Function to clean up generated files
cleanup() {
    print_message $BLUE "🧹 Cleaning up generated files..."
    rm -rf specs rest_api swagger.json
    rm -rf /openshift-docs/rest_api

    if [[ $? -ne 0 ]]; then
        print_message $RED "❌ Failed to clean up generated files."
        exit 1
    fi

    printf "✅ ${GREEN}Cleaned up generated files.${NC}\n"
}

# Main script execution based on command
case "$1" in
generate)
    print_banner
    version=$(prompt_for_version)
    download_spec $version
    split_spec "swagger.json"
    generate_asciidoc
    update_asciidoc
    remove_spec_files
    create_topic_map
    print_message $GREEN "🎉 All tasks completed successfully!"
    ;;
clean)
    cleanup
    ;;
help)
    show_help
    ;;
*)
    print_message $RED "❌ Invalid command. Use one of the available commands."
    show_help
    ;;
esac
