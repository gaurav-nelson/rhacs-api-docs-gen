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
    echo -e "${CYAN}"
    print_banner
    printf "${NC}"
    printf "${BLUE}Usage: bash rhacs-api-docs-gen.sh [command]${NC}\n"
    printf "${YELLOW}Commands:${NC}\n"
    printf "  generate  Download the OpenAPI spec and generate AsciiDoc files.\n"
    printf "  clean     Remove the 'rest_api' directory and other generated files.\n"
    printf "  help      Show this help message.\n"
}

# Function to prompt for version number
prompt_for_version() {
    read -p "$(print_message $YELLOW 'Enter the version number of the RHACS release (e.g., 4.6.0): ')" version_input
    echo $version_input
}

# Function to download the OpenAPI specifications
download_spec() {
    local version_num=$1
    local url_v1="https://mirror.openshift.com/pub/rhacs/openapi-spec/${version_num}/v1.swagger.json"
    local url_v2="https://mirror.openshift.com/pub/rhacs/openapi-spec/${version_num}/v2.swagger.json"
    local output_file_v1="v1.swagger.json"
    local output_file_v2="v2.swagger.json"

    print_message $BLUE "📥 Downloading OpenAPI specification v1 from $url_v1..."
    curl -fsSL -o $output_file_v1 $url_v1

    if [[ $? -ne 0 ]]; then
        print_message $RED "❌ Failed to download the OpenAPI specification v1."
        exit 1
    fi
    print_message $GREEN "✅ Downloaded OpenAPI specification v1."

    print_message $BLUE "📥 Downloading OpenAPI specification v2 from $url_v2..."
    curl -fsSL -o $output_file_v2 $url_v2

    if [[ $? -ne 0 ]]; then
        print_message $RED "❌ Failed to download the OpenAPI specification v2."
        exit 1
    fi
    print_message $GREEN "✅ Downloaded OpenAPI specification v2."
}

# Function to split the OpenAPI specification
split_spec() {
    local input_file=$1
    local script_path="./splitspec.js"
    if [ ! -f "$script_path" ]; then
        script_path="./scripts/splitspec.js"
        if [ ! -f "$script_path" ]; then
            print_message $RED "❌ splitspec.js not found. Searched in ./ and ./scripts/"
            exit 1
        fi
    fi
    print_message $BLUE "✂️ Processing OpenAPI specification $input_file with $script_path..."
    node $script_path $input_file # splitspec.js will handle merging common definitions

    if [[ $? -ne 0 ]]; then
        print_message $RED "❌ Failed to process the OpenAPI specification $input_file."
        exit 1
    fi
}

# Function to generate AsciiDoc files
generate_asciidoc() {
    print_message $BLUE "📄 Generating AsciiDoc files..."
    local base_output_dir="rest_api" # Output directly into rest_api
    mkdir -p "$base_output_dir"

    # Process common_object_reference.json
    local common_spec_file="specs/common_object_reference.json"
    if [ -f "$common_spec_file" ]; then
        local common_output_service_dir="$base_output_dir/CommonObjectReference"
        mkdir -p "$common_output_service_dir"
        local common_adoc_file="$common_output_service_dir/CommonObjectReference.adoc"
        print_message_disappearing $BLUE "🔧 Generating AsciiDoc for common_object_reference.json..."

        bash /usr/local/bin/docker-entrypoint.sh generate \
            -i "$common_spec_file" \
            -g asciidoc \
            -o "$common_output_service_dir" > /dev/null # Redirect stdout to hide verbose logs

        if [ -f "$common_output_service_dir/index.adoc" ]; then
            mv "$common_output_service_dir/index.adoc" "$common_adoc_file"
            #print_message $GREEN "✅ Generated $common_adoc_file"
        else
            print_message $RED "❌ index.adoc not found for common_object_reference.json in $common_output_service_dir. Please check generator logs above."
        fi
    else
        print_message $YELLOW "⚠️ common_object_reference.json not found in specs/ directory. Skipping its AsciiDoc generation."
    fi

    # Process tag-specific spec files
    for spec_file in specs/*.json; do
        local service_name=$(basename "$spec_file" .json)

        if [ "$service_name" == "common_object_reference" ]; then
            continue
        fi

        local output_service_dir="$base_output_dir/$service_name"
        mkdir -p "$output_service_dir"
        local output_adoc_file="$output_service_dir/${service_name}.adoc"

        print_message_disappearing $BLUE "🔧 Generating AsciiDoc for $service_name.json..."
        bash /usr/local/bin/docker-entrypoint.sh generate \
            -i "$spec_file" \
            -g asciidoc \
            -o "$output_service_dir" > /dev/null # Redirect stdout to hide verbose logs

        if [ -f "$output_service_dir/index.adoc" ]; then
            mv "$output_service_dir/index.adoc" "$output_adoc_file"
            #print_message $GREEN "✅ Generated $output_adoc_file"
        else
            print_message $RED "❌ index.adoc not found for $service_name.json in $output_service_dir. Please check generator logs above."
        fi
    done

    print_message $GREEN "🏁 Finished AsciiDoc generation attempts."
}

# Function to update the AsciiDoc files
update_asciidoc() {
    local update_script_path="./updateasciidoc.js"
    if [ ! -f "$update_script_path" ]; then
        update_script_path="./scripts/updateasciidoc.js"
         if [ ! -f "$update_script_path" ]; then
            print_message $RED "❌ updateasciidoc.js not found. Searched in ./ and ./scripts/"
            print_message $YELLOW "⚠️ Skipping AsciiDoc update step."
            return
        fi
    fi

    print_message $BLUE "🛠️ Updating all AsciiDoc files using $update_script_path..."
    # Find .adoc files directly under rest_api/*/ (one level deep for service directories)
    find "rest_api" -mindepth 2 -maxdepth 2 -type f -name "*.adoc" -print0 | while IFS= read -r -d $'\0' adoc_file; do
        print_message_disappearing $BLUE "🛠️ Updating $adoc_file..."
        node $update_script_path "$adoc_file"
    done

    print_message $GREEN "\n✅ Updated AsciiDoc files."
}

# Function to remove specific generated spec files and artifacts
remove_interim_files() {
    print_message $BLUE "🧹 Removing interim generated spec files (specs/ directory and swagger JSONs)..."
    rm -rf specs v1.swagger.json v2.swagger.json
    find rest_api -type f -name ".openapi-generator-ignore" -exec rm -f {} \; >/dev/null 2>&1
    find rest_api -type d -name ".openapi-generator" -exec rm -rf {} \; >/dev/null 2>&1
    print_message $GREEN "✅ Removed interim spec files."
}

# Function to create topic map
create_topic_map() {
    print_message $BLUE "🗂️ Creating topic map (api_reference.yml)..."

    local ROOT_DIR="rest_api"
    local OUTPUT_FILE="api_reference.yml"

    # Start the YAML structure
    #echo "---" > "$OUTPUT_FILE"
    echo "Name: API reference" >> "$OUTPUT_FILE"
    echo "Dir: $ROOT_DIR" >> "$OUTPUT_FILE"
    echo "Distros: openshift-acs" >> "$OUTPUT_FILE"
    echo "Topics:" >> "$OUTPUT_FILE"

    # Process each service directory in rest_api
    # Sort service directories to ensure CommonObjectReference is last if possible, or handle explicitly
    # For simplicity, let's process CommonObjectReference separately if it exists, then others.

    local service_dirs=()
    local common_obj_ref_dir=""

    for service_path in "$ROOT_DIR"/*/; do
        if [ -d "$service_path" ]; then
            local current_service_name=$(basename "$service_path")
            if [ "$current_service_name" == "CommonObjectReference" ]; then
                common_obj_ref_dir="$service_path"
            else
                service_dirs+=("$service_path")
            fi
        fi
    done

    # Process regular service directories first
    for service_dir_path in "${service_dirs[@]}"; do
        local service_name_from_dir=$(basename "$service_dir_path")
        # Format service name for display (e.g., AdministrationEventService -> Administration Event Service)
        local display_service_name=$(echo "$service_name_from_dir" | sed 's/\([a-z]\)\([A-Z]\)/\1 \2/g')
        local adoc_file_path="$service_dir_path/${service_name_from_dir}.adoc"

        if [ -f "$adoc_file_path" ]; then
            echo "  - Name: $display_service_name" >> "$OUTPUT_FILE"
            echo "    Dir: $service_name_from_dir" >> "$OUTPUT_FILE"
            echo "    Topics:" >> "$OUTPUT_FILE"

            local adoc_title=$(grep -m 1 '^= ' "$adoc_file_path" | sed 's/^= //')
            # Try to extract the first API path (e.g., lines like "=== GET /path/to/endpoint")
            local api_path=$(grep -m 1 -Eo '^=== [A-Z]+ (/.*)$' "$adoc_file_path" | sed -E 's/^=== [A-Z]+ //')

            local topic_name="'$adoc_title'" # Default topic name
            if [ -n "$api_path" ]; then
                topic_name="'$adoc_title [$api_path]'"
            fi

            echo "    - Name: $topic_name" >> "$OUTPUT_FILE"
            echo "      File: $service_name_from_dir" >> "$OUTPUT_FILE"
        else
            print_message $YELLOW "⚠️ No .adoc file found for service $service_name_from_dir, skipping for topic map."
        fi
    done

    # Process CommonObjectReference last
    if [ -n "$common_obj_ref_dir" ] && [ -d "$common_obj_ref_dir" ]; then
        local service_name_from_dir="CommonObjectReference"
        local display_service_name="Common Object Reference" # Explicit display name
        local adoc_file_path="$common_obj_ref_dir/${service_name_from_dir}.adoc"

        if [ -f "$adoc_file_path" ]; then
            echo "  - Name: $display_service_name" >> "$OUTPUT_FILE"
            echo "    Dir: $service_name_from_dir" >> "$OUTPUT_FILE"
            echo "    Topics:" >> "$OUTPUT_FILE"

            local adoc_title=$(grep -m 1 '^= ' "$adoc_file_path" | sed 's/^= //')
            local topic_name="'$adoc_title'"

            echo "    - Name: $topic_name" >> "$OUTPUT_FILE"
            echo "      File: $service_name_from_dir" >> "$OUTPUT_FILE"
        else
            print_message $YELLOW "⚠️ CommonObjectReference.adoc not found, skipping for topic map."
        fi
    fi

    # remove the existing rest_api dir if it exists
    rm -rf /openshift-docs/rest_api

    # copy the rest_api dir to the /openshift-docs/rest_api
    cp -r rest_api /openshift-docs/

    # add new line at the end of the file
    echo "" >> "$OUTPUT_FILE"

    # Update the topic_map.yml file
    node updatetopicmap.js "$(cat $OUTPUT_FILE)"

    print_message $GREEN "✅ Generated topic map and copied rest_api to /openshift-docs/rest_api."
}


# Function to clean up generated files
cleanup() {
    print_message $BLUE "🧹 Cleaning up all generated files (rest_api/, specs/, swagger JSONs, api_reference.yml)..."
    rm -rf rest_api specs v1.swagger.json v2.swagger.json api_reference.yml
    if [ -d "/openshift-docs/rest_api" ]; then
        rm -rf /openshift-docs/rest_api
    fi
    print_message $GREEN "✅ Cleaned up all generated files."
}

trap 'print_message $RED "❌ Script interrupted, Exitting..."; exit 1' SIGINT SIGTERM

#function to copy generator files to the current directory
copy_generator_files() {
    print_message $BLUE "📦 Copying generator files to the current directory..."
    cp -r rest_api /openshift-docs/rest_api
    if [ $? -ne 0 ]; then
        print_message $RED "❌ Failed to copy generator files."
        exit 1
    fi
    print_message $GREEN "✅ Copied generator files to /openshift-docs/generator_files."
}

# Main script execution based on command
case "$1" in
generate)
    print_banner
    release_version=$(prompt_for_version)

    # Clean specs directory before starting to ensure a fresh common_object_reference.json
    if [ -d "specs" ]; then
        print_message $YELLOW "🧹 Pre-cleaning specs/ directory..."
        rm -rf specs/*
    fi
    # Also remove existing common_object_reference.json if it's outside specs from a previous run
    if [ -f "common_object_reference.json" ]; then
        rm -f "common_object_reference.json"
    fi
    # Clean existing api_reference.yml before generation
    if [ -f "api_reference.yml" ]; then
        rm -f "api_reference.yml"
    fi


    download_spec $release_version
    split_spec "v1.swagger.json" # Processes v1, creates/updates common_object_reference.json
    split_spec "v2.swagger.json" # Processes v2, merges into common_object_reference.json

    generate_asciidoc # No version argument needed now
    #copy_generator_files # Copy generator files to the current directory
    update_asciidoc   # No version argument needed now
    remove_interim_files
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
