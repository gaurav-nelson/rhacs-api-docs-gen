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
    printf "\r\033[K"  # \033[K clears the line from the cursor to the end
    printf "${color}%s${NC}" "$@"
}


# Function to show help message
show_help() {
    # multiline asciiart
    echo -e "${CYAN}"
    cat << "EOF"
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
    printf "${NC}"
    printf "${BLUE}Usage: bash rhacs-api-docs-gen.sh [command]${NC}\n"
    printf "${YELLOW}Commands:${NC}\n"
    printf "  generate  Download the OpenAPI spec and generate AsciiDoc files.\n"
    printf "  clean     Remove the 'rest_api' directory.\n"
    printf "  help      Show this help message.\n"
}

# Function to prompt for version number
prompt_for_version() {
    read -p "$(print_message $YELLOW 'Please provide the version number of the RHACS release (e.g., 4.5.1): ')" version
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
    node splitspec.js $input_file

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

    for spec_file in specs/*.json; do
        local base_name=$(basename "$spec_file" .json)
        print_message_disappearing $BLUE "🔧 Generating AsciiDoc for $base_name.json..."

        # Generate AsciiDoc files in the rest_api directory, suppressing output
        bash /usr/local/bin/docker-entrypoint.sh generate \
            -i "$spec_file" \
            -g asciidoc \
            -o "rest_api/" > /dev/null 2>&1

        # Rename the generated index.adoc to match the spec file name
        if [ -f "rest_api/index.adoc" ]; then
            mv "rest_api/index.adoc" "rest_api/$base_name.adoc"
        else
            print_message $RED "❌ index.adoc not found for $base_name.json."
        fi
    done

    print_message $GREEN "\n✅ Generated AsciiDoc files."
}


# Function to update the AsciiDoc files
update_asciidoc() {
    print_message $BLUE "🔧 Updating AsciiDoc files..."
    # For all "*.adoc" files in the "rest_api" directory run the updateasciidoc.js script
    for adoc_file in rest_api/*.adoc; do
        print_message_disappearing $BLUE "🔧 Updating AsciiDoc for $adoc_file..."
        node updateasciidoc.js $adoc_file
        #print_message_disappearing $GREEN "✔ Updated AsciiDoc for $adoc_file."
    done

    print_message $GREEN "\n✅ Updated AsciiDoc files."
}

# Function to remove generated spec files and artifacts
remove_spec_files() {
    print_message $BLUE "🧹 Removing generated spec files..."
    rm -rf specs swagger.json rest_api/.openapi-generator-ignore rest_api/.openapi-generator/

    if [[ $? -ne 0 ]]; then
        print_message $RED "❌ Failed to remove generated spec files and artifacts."
        exit 1
    fi

    print_message $GREEN "✅ Removed generated spec files."
}

# Function to create topic map
create_topic_map() {
    print_message $BLUE "🗂️ Creating topic map..."

    # Initialize the topic map content
    local topic_map="Name: API reference\nDir: rest_api\nDistros: openshift-acs\nTopics:\n"

    # Loop through all .adoc files in the rest_api directory
    for file in rest_api/*.adoc; do
        # Get the filename without the extension
        local filename=$(basename "$file" .adoc)
        topic_map+="  - Name: $filename\n    File: $filename\n"
    done

    # remove the existing rest_api dir if it exists
    rm -rf /openshift-docs/rest_api

    # copy the rest_api dir to the /openshift-docs/rest_api
    cp -r rest_api /openshift-docs/

    # Update the topic_map.yml file
    node updatetopicmap.js "$topic_map"

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
        print_message $RED "❌ Invalid command. Use 'help' to see available commands."
        ;;
esac
