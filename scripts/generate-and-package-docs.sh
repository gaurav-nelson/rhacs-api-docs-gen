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

# Function to print banner
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

# Set the version from environment variable
VERSION=${VERSION:-"4.6.0"}
print_banner
print_message $BLUE "Starting API docs generation for RHACS version: $VERSION"

# Set working directories
WORK_DIR="/rhacs-api-docs-gen"
OPENSHIFT_DOCS_DIR="/openshift-docs"
OUTPUT_DIR="/output"

# Create output directory if it doesn't exist
mkdir -p $OUTPUT_DIR

# 1. Download the OpenAPI specifications
print_message $BLUE "📥 Downloading OpenAPI specifications for version $VERSION..."
cd $WORK_DIR
URL_V1="https://mirror.openshift.com/pub/rhacs/openapi-spec/${VERSION}/v1.swagger.json"
URL_V2="https://mirror.openshift.com/pub/rhacs/openapi-spec/${VERSION}/v2.swagger.json"
OUTPUT_FILE_V1="v1.swagger.json"
OUTPUT_FILE_V2="v2.swagger.json"

curl -o $OUTPUT_FILE_V1 $URL_V1
if [[ $? -ne 0 ]]; then
    print_message $RED "❌ Failed to download the OpenAPI specification v1."
    exit 1
fi
print_message $GREEN "✅ Downloaded OpenAPI specification v1."

curl -o $OUTPUT_FILE_V2 $URL_V2
if [[ $? -ne 0 ]]; then
    print_message $RED "❌ Failed to download the OpenAPI specification v2."
    exit 1
fi
print_message $GREEN "✅ Downloaded OpenAPI specification v2."

# 2. Clone openshift-docs repository
print_message $BLUE "📂 Cloning openshift-docs repository..."
# Extract major and minor version numbers for the branch name (e.g., 4.6.3 -> 4.6)
BRANCH_VERSION=$(echo $VERSION | grep -oE '^[0-9]+\.[0-9]+')
if [[ -z "$BRANCH_VERSION" ]]; then
    print_message $RED "❌ Failed to extract branch version from $VERSION"
    exit 1
fi
BRANCH_NAME="rhacs-docs-$BRANCH_VERSION"
print_message $CYAN "Using branch: $BRANCH_NAME"

git clone --depth 1 --branch $BRANCH_NAME https://github.com/openshift/openshift-docs.git $OPENSHIFT_DOCS_DIR
if [[ $? -ne 0 ]]; then
    print_message $RED "❌ Failed to clone branch $BRANCH_NAME. Branch may not exist."
    exit 1
fi
cd $OPENSHIFT_DOCS_DIR
print_message $GREEN "✅ Cloned openshift-docs repository with branch $BRANCH_NAME."

# 3. Process V1 spec
cd $WORK_DIR
print_message $BLUE "🔄 Processing V1 specification..."
node splitspecwithoutdefinitions.js v1.swagger.json 2>&1 | grep -i "error" || true

# Generate AsciiDoc for V1
print_message $BLUE "📄 Generating AsciiDoc files for V1..."
mkdir -p "rest_api/v1"

for tag_dir in specs/*/; do
    tag_name=$(basename "$tag_dir")
    output_tag_dir="rest_api/v1/$tag_name"
    mkdir -p "$output_tag_dir"

    for spec_file in "$tag_dir"/*.json; do
        base_name=$(basename "$spec_file" .json)

        # Skip files starting with _v2 for v1
        if [[ "$base_name" == _v2* ]]; then
            continue
        fi

        output_file="$output_tag_dir/${base_name//[\{\}]/}.adoc"

        # Generate AsciiDoc files
        bash /usr/local/bin/docker-entrypoint.sh generate \
            -i "$spec_file" \
            -g asciidoc \
            -o "$output_tag_dir" >/dev/null 2>&1

        # Rename the generated index.adoc to match the spec file name
        if [ -f "$output_tag_dir/index.adoc" ]; then
            mv "$output_tag_dir/index.adoc" "$output_file"
        fi
    done

    # Remove empty directories
    if [ -z "$(ls -A "$output_tag_dir")" ]; then
        rmdir "$output_tag_dir"
    fi
done

# Update AsciiDoc files for V1
print_message $BLUE "🔧 Updating AsciiDoc files for V1..."
total_files=$(find "rest_api/v1" -type f -name "*.adoc" | wc -l)
current=0
progress_step=$((total_files / 10 > 0 ? total_files / 10 : 1))  # Show progress every ~10% or at least every file

find "rest_api/v1" -type f -name "*.adoc" | while read -r adoc_file; do
    current=$((current + 1))

    # Show progress at intervals
    if [[ $((current % progress_step)) -eq 0 ]] || [[ $current -eq $total_files ]]; then
        percentage=$((current * 100 / total_files))
        print_message $CYAN "  Progress: $current/$total_files files ($percentage%)"
    fi

    node updateasciidoc.js "$adoc_file" > /dev/null 2>&1 || print_message $RED "❌ Error updating $adoc_file"
done
print_message $GREEN "✅ Processed $total_files V1 AsciiDoc files."

# 4. Process V2 spec
print_message $BLUE "🔄 Processing V2 specification..."
rm -rf specs
node splitspecwithoutdefinitions.js v2.swagger.json 2>&1 | grep -i "error" || true

# Generate AsciiDoc for V2
print_message $BLUE "📄 Generating AsciiDoc files for V2..."
mkdir -p "rest_api/v2"

for tag_dir in specs/*/; do
    tag_name=$(basename "$tag_dir")
    output_tag_dir="rest_api/v2/$tag_name"
    mkdir -p "$output_tag_dir"

    for spec_file in "$tag_dir"/*.json; do
        base_name=$(basename "$spec_file" .json)

        # Skip files starting with _v1 for v2
        if [[ "$base_name" == _v1* ]]; then
            continue
        fi

        output_file="$output_tag_dir/${base_name//[\{\}]/}.adoc"

        # Generate AsciiDoc files
        bash /usr/local/bin/docker-entrypoint.sh generate \
            -i "$spec_file" \
            -g asciidoc \
            -o "$output_tag_dir" >/dev/null 2>&1

        # Rename the generated index.adoc to match the spec file name
        if [ -f "$output_tag_dir/index.adoc" ]; then
            mv "$output_tag_dir/index.adoc" "$output_file"
        fi
    done

    # Remove empty directories
    if [ -z "$(ls -A "$output_tag_dir")" ]; then
        rmdir "$output_tag_dir"
    fi
done

# Update AsciiDoc files for V2
print_message $BLUE "🔧 Updating AsciiDoc files for V2..."
total_files=$(find "rest_api/v2" -type f -name "*.adoc" | wc -l)
current=0
progress_step=$((total_files / 10 > 0 ? total_files / 10 : 1))  # Show progress every ~10% or at least every file

find "rest_api/v2" -type f -name "*.adoc" | while read -r adoc_file; do
    current=$((current + 1))

    # Show progress at intervals
    if [[ $((current % progress_step)) -eq 0 ]] || [[ $current -eq $total_files ]]; then
        percentage=$((current * 100 / total_files))
        print_message $CYAN "  Progress: $current/$total_files files ($percentage%)"
    fi

    node updateasciidoc.js "$adoc_file" > /dev/null 2>&1 || print_message $RED "❌ Error updating $adoc_file"
done
print_message $GREEN "✅ Processed $total_files V2 AsciiDoc files."

# 5. Fix tags using the fix_tags.sh script
print_message $BLUE "🔧 Fixing tags in AsciiDoc files..."
bash fix_tags.sh
print_message $GREEN "✅ Fixed tags in AsciiDoc files."

# 6. Create topic map
print_message $BLUE "🗂️ Creating topic map..."

# Define the root directory and output YAML file
ROOT_DIR="rest_api"
OUTPUT_FILE="api_reference.yml"

# Start the YAML structure
echo "---" > "$OUTPUT_FILE"
echo "Name: API reference" >> "$OUTPUT_FILE"
echo "Dir: $ROOT_DIR" >> "$OUTPUT_FILE"
echo "Distros: openshift-acs" >> "$OUTPUT_FILE"
echo "Topics:" >> "$OUTPUT_FILE"

# Function to process each service directory
process_service() {
    local service_dir="$1"
    local service_name="$2"

    echo "  - Name: $service_name" >> "$OUTPUT_FILE"
    echo "    Dir: $service_name" >> "$OUTPUT_FILE"
    echo "    Topics:" >> "$OUTPUT_FILE"

    # Process each .adoc file in the service directory
    for file in "$service_dir"/*.adoc; do
        if [[ -f "$file" ]]; then
            # Extract the name from the file
            name=$(grep -m 1 '^=' "$file" | sed 's/^= //')
            file_name=$(basename "$file" .adoc) # Remove the .adoc extension
            echo "    - Name: $name" >> "$OUTPUT_FILE"
            echo "      File: $file_name" >> "$OUTPUT_FILE"
        fi
    done
}

# Process each version directory
for version in "v1" "v2"; do
    echo "- Name: Version $version" >> "$OUTPUT_FILE"
    echo "  Dir: $version" >> "$OUTPUT_FILE"
    echo "  Topics:" >> "$OUTPUT_FILE"

    # Process each service directory within the version directory
    for service in "$ROOT_DIR/$version"/*/; do
        service_name=$(basename "$service")
        process_service "$service" "$service_name"
    done
done

# Add new line at the end of the file
echo "" >> "$OUTPUT_FILE"

# Copy the rest_api directory to the openshift-docs repo
cp -r rest_api $OPENSHIFT_DOCS_DIR/

# Update the topic_map.yml file
node updatetopicmap.js "$(cat $OUTPUT_FILE)" > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    print_message $RED "❌ Failed to update topic map."
    exit 1
fi
print_message $GREEN "✅ Created topic map."

# 7. ZIP directories for artifact creation
print_message $BLUE "📦 Creating ZIP archive of documentation..."
cd $OPENSHIFT_DOCS_DIR

# Create a temporary directory for the specific content
mkdir -p /tmp/docs_export
cp -r _topic_maps /tmp/docs_export/
cp -r rest_api /tmp/docs_export/

# Create the ZIP from the temporary directory
cd /tmp/docs_export
zip -rq "${OUTPUT_DIR}/${VERSION}_api_docs.zip" _topic_maps rest_api

print_message $GREEN "✅ Created ZIP archive: ${VERSION}_api_docs.zip containing only _topic_maps and rest_api directories"

# Clean up
print_message $BLUE "🧹 Cleaning up..."
cd $WORK_DIR
rm -rf specs v1.swagger.json v2.swagger.json rest_api api_reference.yml /tmp/docs_export
print_message $GREEN "✅ Cleanup completed."

print_message $GREEN "🎉 Documentation generation completed successfully!"
print_message $YELLOW "📋 Documentation package is available at: ${OUTPUT_DIR}/${VERSION}_api_docs.zip"
