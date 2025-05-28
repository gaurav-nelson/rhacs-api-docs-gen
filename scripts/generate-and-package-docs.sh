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

# Function to print messages with color and overwrite previous line
print_message_disappearing() {
    local color=$1
    shift
    printf "\r\033[K" # Clear the line
    printf "${color}%s${NC}" "$@"
}

# Function to print banner
print_banner() {
    cat <<"EOF"
            ____  _   _   _    ____ ____
           |  _ \| | | |  / \  / ___/ ___|
           | |_) | |_| | / _ \| |   \___ \
           |  _ <|  _  |/ ___ | |___ ___) |
           |_| \_|_| |_/_/   \_\____|____/

    _    ____ ___   ____   ___   ____ ____     ____ _____ _   _
   / \  |  _ |_ _| |  _ \ / _ \ / ___/ ___|   / ___| ____| \ | |
  / _ \ | |_) | |  | | | | | | | |   \___ \  | |  _|  _| |  \| |
 / ___ \|  __/| |  | |_| | |_| | |___ ___) | | |_| | |___| |\  |
/_/   \_\_|  |___| |____/ \___/ \____|____/   \____|_____|_| \_|

EOF
}

# Set the version from environment variable
VERSION=${VERSION:-"4.6.0"} # Default version if not set
print_banner
print_message $BLUE "🚀 Starting API docs generation for RHACS version: $VERSION"

# Set working directories
WORK_DIR="/rhacs-api-docs-gen" # This is where the script and its tools are
OPENSHIFT_DOCS_DIR="/openshift-docs" # Target directory for openshift-docs clone
OUTPUT_DIR="/output" # Final ZIP output directory (mounted from host)

# --- Helper Script Paths ---
# Define paths for helper scripts, checking in $WORK_DIR and then $WORK_DIR/scripts/
SPLITSCRIPT_PATH="$WORK_DIR/splitspec.js"
if [ ! -f "$SPLITSCRIPT_PATH" ]; then
    SPLITSCRIPT_PATH="$WORK_DIR/scripts/splitspec.js"
fi

UPDATEADOC_SCRIPT_PATH="$WORK_DIR/updateasciidoc.js"
if [ ! -f "$UPDATEADOC_SCRIPT_PATH" ]; then
    UPDATEADOC_SCRIPT_PATH="$WORK_DIR/scripts/updateasciidoc.js"
fi

UPDATETOPICMAP_SCRIPT_PATH="$WORK_DIR/updatetopicmap.js"
if [ ! -f "$UPDATETOPICMAP_SCRIPT_PATH" ]; then
    UPDATETOPICMAP_SCRIPT_PATH="$WORK_DIR/scripts/updatetopicmap.js"
fi

# Create output directory if it doesn't exist
mkdir -p $OUTPUT_DIR
cd $WORK_DIR # Ensure we are in the correct working directory

# 0. Pre-flight checks for helper scripts
if [ ! -f "$SPLITSCRIPT_PATH" ]; then
    print_message $RED "❌ splitspec.js not found at $SPLITSCRIPT_PATH or $WORK_DIR/scripts/splitspec.js. Exiting."
    exit 1
fi
if [ ! -f "$UPDATEADOC_SCRIPT_PATH" ]; then
    print_message $YELLOW "⚠️ updateasciidoc.js not found at its expected locations. AsciiDoc updates might be incomplete if this script is crucial."
    # Not exiting, as some workflows might not need it, but it's a critical warning.
fi


# 1. Download the OpenAPI specifications
print_message $BLUE "📥 Downloading OpenAPI specifications for version $VERSION..."
URL_V1="https://mirror.openshift.com/pub/rhacs/openapi-spec/${VERSION}/v1.swagger.json"
URL_V2="https://mirror.openshift.com/pub/rhacs/openapi-spec/${VERSION}/v2.swagger.json"
OUTPUT_FILE_V1="v1.swagger.json"
OUTPUT_FILE_V2="v2.swagger.json"

curl -fsSL -o $OUTPUT_FILE_V1 $URL_V1
if [[ $? -ne 0 ]]; then
    print_message $RED "❌ Failed to download the OpenAPI specification v1."
    exit 1
fi
print_message $GREEN "✅ Downloaded OpenAPI specification v1."

curl -fsSL -o $OUTPUT_FILE_V2 $URL_V2
if [[ $? -ne 0 ]]; then
    print_message $RED "❌ Failed to download the OpenAPI specification v2."
    exit 1
fi
print_message $GREEN "✅ Downloaded OpenAPI specification v2."

# 2. Clone openshift-docs repository
print_message $BLUE "📂 Cloning openshift-docs repository..."
BRANCH_VERSION=$(echo $VERSION | grep -oE '^[0-9]+\.[0-9]+')
if [[ -z "$BRANCH_VERSION" ]]; then
    print_message $RED "❌ Failed to extract branch version from $VERSION"
    exit 1
fi
BRANCH_NAME="rhacs-docs-$BRANCH_VERSION"
print_message $CYAN "Attempting to clone branch: $BRANCH_NAME"

if [ -d "$OPENSHIFT_DOCS_DIR" ]; then
    print_message $YELLOW "Removing existing $OPENSHIFT_DOCS_DIR for a clean clone..."
    rm -rf "$OPENSHIFT_DOCS_DIR"
fi

git clone --depth 1 --branch $BRANCH_NAME https://github.com/openshift/openshift-docs.git $OPENSHIFT_DOCS_DIR
if [[ $? -ne 0 ]]; then
    print_message $YELLOW "⚠️ Failed to clone branch $BRANCH_NAME. Attempting to clone default branch (e.g., main) as fallback..."
    git clone --depth 1 https://github.com/openshift/openshift-docs.git $OPENSHIFT_DOCS_DIR
    if [[ $? -ne 0 ]]; then
        print_message $RED "❌ Failed to clone openshift-docs repository even with fallback."
        exit 1
    fi
    print_message $GREEN "✅ Cloned openshift-docs repository using a default branch (fallback)."
else
    print_message $GREEN "✅ Cloned openshift-docs repository with branch $BRANCH_NAME."
fi

# 3. Process OpenAPI Specifications using splitspec.js
print_message $BLUE "🔄 Processing OpenAPI specifications..."
rm -rf specs # Clean specs directory before starting
mkdir -p specs
# Also remove existing common_object_reference.json if it's outside specs from a previous run
if [ -f "common_object_reference.json" ]; then
    rm -f "common_object_reference.json"
fi

print_message $BLUE "⚙️ Splitting V1 OpenAPI specification with $SPLITSCRIPT_PATH..."
node "$SPLITSCRIPT_PATH" "$OUTPUT_FILE_V1"
if [[ $? -ne 0 ]]; then
    print_message $RED "❌ Failed to process V1 OpenAPI specification with $SPLITSCRIPT_PATH."
    # Decide if this is a fatal error. For now, let's try to continue with V2.
fi

print_message $BLUE "⚙️ Splitting V2 OpenAPI specification with $SPLITSCRIPT_PATH (merging common definitions)..."
node "$SPLITSCRIPT_PATH" "$OUTPUT_FILE_V2"
if [[ $? -ne 0 ]]; then
    print_message $RED "❌ Failed to process V2 OpenAPI specification with $SPLITSCRIPT_PATH."
    # exit 1 # Potentially fatal
fi
print_message $GREEN "✅ Finished splitting specifications. Check 'specs/' directory."

# 4. Generate AsciiDoc files (Unified)
print_message $BLUE "📄 Generating AsciiDoc files into $WORK_DIR/rest_api/..."
BASE_API_DIR="$WORK_DIR/rest_api"
rm -rf "$BASE_API_DIR" # Clean slate for rest_api generation
mkdir -p "$BASE_API_DIR"

# Process common_object_reference.json first if it exists
COMMON_SPEC_FILE="$WORK_DIR/specs/common_object_reference.json"
if [ -f "$COMMON_SPEC_FILE" ]; then
    print_message_disappearing $CYAN "🔧 Generating AsciiDoc for common_object_reference.json..." # This one is quick, so keep as is or remove
    COMMON_OUTPUT_SERVICE_DIR="$BASE_API_DIR/CommonObjectReference"
    mkdir -p "$COMMON_OUTPUT_SERVICE_DIR"
    COMMON_ADOC_FILE="$COMMON_OUTPUT_SERVICE_DIR/CommonObjectReference.adoc"

    bash /usr/local/bin/docker-entrypoint.sh generate \
        -i "$COMMON_SPEC_FILE" \
        -g asciidoc \
        -o "$COMMON_OUTPUT_SERVICE_DIR" > /dev/null # Suppress verbose output

    if [ -f "$COMMON_OUTPUT_SERVICE_DIR/index.adoc" ]; then
        mv "$COMMON_OUTPUT_SERVICE_DIR/index.adoc" "$COMMON_ADOC_FILE"
    else
        print_message $RED "\n❌ index.adoc not found for common_object_reference.json in $COMMON_OUTPUT_SERVICE_DIR."
    fi
    printf "\r\033[K" # Clear the disappearing message line
else
    print_message $YELLOW "⚠️ common_object_reference.json not found in specs/. Skipping its direct AsciiDoc generation."
fi

# Process tag-specific (service) spec files
spec_files_to_process=$(find "$WORK_DIR/specs" -maxdepth 1 -name "*.json" -type f ! -name "common_object_reference.json" -print0 | xargs -0)
total_spec_files=$(echo "$spec_files_to_process" | wc -w) # Count files separated by spaces
processed_spec_files=0
# Define progress step: show progress every ~5% or at least every file
progress_step_gen=$((total_spec_files / 20 > 0 ? total_spec_files / 20 : 1))


if [ "$total_spec_files" -gt 0 ]; then
    for spec_file in $spec_files_to_process; do
        if [ ! -f "$spec_file" ]; then continue; fi

        service_name_from_file=$(basename "$spec_file" .json)
        processed_spec_files=$((processed_spec_files + 1))

        # Show progress at intervals
        if [[ $((processed_spec_files % progress_step_gen)) -eq 0 ]] || [[ $processed_spec_files -eq $total_spec_files ]]; then
            percentage_gen=$((processed_spec_files * 100 / total_spec_files))
            print_message_disappearing $CYAN "🔧 Generating AsciiDoc files: $processed_spec_files/$total_spec_files ($percentage_gen%%)"
        fi

        output_service_dir="$BASE_API_DIR/$service_name_from_file"
        mkdir -p "$output_service_dir"
        output_adoc_file="$output_service_dir/${service_name_from_file}.adoc"

        bash /usr/local/bin/docker-entrypoint.sh generate \
            -i "$spec_file" \
            -g asciidoc \
            -o "$output_service_dir" > /dev/null # Suppress verbose output

        if [ -f "$output_service_dir/index.adoc" ]; then
            mv "$output_service_dir/index.adoc" "$output_adoc_file"
        else
            # Print error on a new line if progress bar is active
            printf "\r\033[K" # Clear progress line before printing error
            print_message $RED "❌ index.adoc not found for $service_name_from_file.json in $output_service_dir."
        fi
    done
    printf "\r\033[K" # Clear the final progress message
else
    print_message $YELLOW "ℹ️ No service-specific JSON spec files found in specs/ to generate AsciiDoc from."
fi
print_message $GREEN "✅ Finished AsciiDoc generation attempts."


# 5. Update AsciiDoc files (Unified)
if [ ! -f "$UPDATEADOC_SCRIPT_PATH" ]; then
    print_message $YELLOW "⚠️ $UPDATEADOC_SCRIPT_PATH not found. Skipping AsciiDoc update step."
else
    print_message $BLUE "🔧 Updating all AsciiDoc files using $UPDATEADOC_SCRIPT_PATH..."
    total_adoc_files=$(find "$BASE_API_DIR" -type f -name "*.adoc" 2>/dev/null | wc -l)
    if [ "$total_adoc_files" -gt 0 ]; then
        current_adoc_file=0
        # Define progress step: show progress every ~5% or at least every file
        progress_step_adoc=$((total_adoc_files / 20 > 0 ? total_adoc_files / 20 : 1))

        find "$BASE_API_DIR" -type f -name "*.adoc" -print0 | while IFS= read -r -d $'\0' adoc_file_to_update; do
            current_adoc_file=$((current_adoc_file + 1))
            if [[ $((current_adoc_file % progress_step_adoc)) -eq 0 ]] || [[ $current_adoc_file -eq $total_adoc_files ]]; then
                percentage_adoc=$((current_adoc_file * 100 / total_adoc_files))
                # This uses print_message_disappearing, which correctly overwrites the line
                print_message_disappearing $CYAN "  Updating AsciiDoc files: $current_adoc_file/$total_adoc_files ($percentage_adoc%%)"
            fi
            node "$UPDATEADOC_SCRIPT_PATH" "$adoc_file_to_update" > /dev/null 2>&1 || {
                # Print error on a new line if progress bar is active
                printf "\r\033[K"; # Clear progress line
                print_message $RED "❌ Error updating $adoc_file_to_update";
            }
        done
        printf "\r\033[K" # Clear the final progress message
        print_message $GREEN "\n✅ Processed $total_adoc_files AsciiDoc files for updates." # Add newline before summary
    else
        print_message $YELLOW "ℹ️ No AsciiDoc files found in $BASE_API_DIR to update."
    fi
fi

# 6. Create topic map (_topic_map.yml) in WORK_DIR
print_message $BLUE "🗂️ Creating topic map structure ($WORK_DIR/_topic_map.yml)..."
TOPIC_MAP_OUTPUT_FILE="$WORK_DIR/_topic_map.yml" # Intermediate topic map in WORK_DIR
# Clean existing topic map file before generation
if [ -f "$TOPIC_MAP_OUTPUT_FILE" ]; then
    rm -f "$TOPIC_MAP_OUTPUT_FILE"
fi

echo "---" > "$TOPIC_MAP_OUTPUT_FILE"
echo "Name: API reference" >> "$TOPIC_MAP_OUTPUT_FILE"
echo "Dir: rest_api" >> "$TOPIC_MAP_OUTPUT_FILE" # Relative to where Antora finds it ($OPENSHIFT_DOCS_DIR)
echo "Distros: openshift-acs" >> "$TOPIC_MAP_OUTPUT_FILE"
echo "Topics:" >> "$TOPIC_MAP_OUTPUT_FILE"

service_dirs_for_topic_map=()
common_obj_ref_dir_for_topic_map=""

for service_path_for_topic_map in "$BASE_API_DIR"/*/; do
    if [ -d "$service_path_for_topic_map" ]; then
        current_service_name_for_topic_map=$(basename "$service_path_for_topic_map")
        if [ "$current_service_name_for_topic_map" == "CommonObjectReference" ]; then
            common_obj_ref_dir_for_topic_map="$service_path_for_topic_map"
        else
            service_dirs_for_topic_map+=("$service_path_for_topic_map")
        fi
    fi
done

# Process regular service directories first
for service_dir_path_item in "${service_dirs_for_topic_map[@]}"; do
    service_name_from_dir_item=$(basename "$service_dir_path_item")
    display_service_name_item=$(echo "$service_name_from_dir_item" | sed -E 's/([A-Z][a-z]+)/ \1/g; s/([a-z])([A-Z])/\1 \2/g; s/^ //')
    adoc_file_path_item="$service_dir_path_item/${service_name_from_dir_item}.adoc"

    if [ -f "$adoc_file_path_item" ]; then
        echo "  - Name: $display_service_name_item" >> "$TOPIC_MAP_OUTPUT_FILE"
        echo "    Dir: $service_name_from_dir_item" >> "$TOPIC_MAP_OUTPUT_FILE"
        echo "    Topics:" >> "$TOPIC_MAP_OUTPUT_FILE"
        adoc_title_item=$(grep -m 1 '^= ' "$adoc_file_path_item" | sed 's/^= //')
        echo "    - Name: '$adoc_title_item'" >> "$TOPIC_MAP_OUTPUT_FILE"
        echo "      File: $service_name_from_dir_item" >> "$TOPIC_MAP_OUTPUT_FILE"
    else
        print_message $YELLOW "⚠️ No .adoc file found for service $service_name_from_dir_item in $service_dir_path_item, skipping for topic map."
    fi
done

# Process CommonObjectReference last
if [ -n "$common_obj_ref_dir_for_topic_map" ] && [ -d "$common_obj_ref_dir_for_topic_map" ]; then
    service_name_cor="CommonObjectReference"
    display_service_name_cor="Common Object Reference"
    adoc_file_path_cor="$common_obj_ref_dir_for_topic_map/${service_name_cor}.adoc"

    if [ -f "$adoc_file_path_cor" ]; then
        echo "  - Name: $display_service_name_cor" >> "$TOPIC_MAP_OUTPUT_FILE"
        echo "    Dir: $service_name_cor" >> "$TOPIC_MAP_OUTPUT_FILE"
        echo "    Topics:" >> "$TOPIC_MAP_OUTPUT_FILE"
        adoc_title_cor=$(grep -m 1 '^= ' "$adoc_file_path_cor" | sed 's/^= //')
        echo "    - Name: '$adoc_title_cor'" >> "$TOPIC_MAP_OUTPUT_FILE"
        echo "      File: $service_name_cor" >> "$TOPIC_MAP_OUTPUT_FILE"
    else
        print_message $YELLOW "⚠️ CommonObjectReference.adoc not found in $common_obj_ref_dir_for_topic_map, skipping for topic map."
    fi
fi
echo "" >> "$TOPIC_MAP_OUTPUT_FILE"
print_message $GREEN "✅ Initial _topic_map.yml structure created at $TOPIC_MAP_OUTPUT_FILE."


# 7. Copy generated 'rest_api' to $OPENSHIFT_DOCS_DIR and process topic map
print_message $BLUE "🔄 Copying generated '$BASE_API_DIR' to '$OPENSHIFT_DOCS_DIR/rest_api'..."
if [ -d "$OPENSHIFT_DOCS_DIR/rest_api" ]; then
    rm -rf "$OPENSHIFT_DOCS_DIR/rest_api" # Clean destination first
fi
cp -r "$BASE_API_DIR" "$OPENSHIFT_DOCS_DIR/"
if [[ $? -ne 0 ]]; then
    print_message $RED "❌ Failed to copy $BASE_API_DIR to $OPENSHIFT_DOCS_DIR/rest_api."
    exit 1
fi
print_message $GREEN "✅ Copied '$BASE_API_DIR' to $OPENSHIFT_DOCS_DIR/rest_api."

# Process the topic map using updatetopicmap.js
if [ ! -f "$UPDATETOPICMAP_SCRIPT_PATH" ]; then
    print_message $YELLOW "⚠️ $UPDATETOPICMAP_SCRIPT_PATH not found. Skipping final topic map processing."
    print_message $YELLOW "Attempting to manually place $TOPIC_MAP_OUTPUT_FILE into $OPENSHIFT_DOCS_DIR/_topic_maps/."
    mkdir -p "$OPENSHIFT_DOCS_DIR/_topic_maps" # Ensure directory exists for cp
    cp "$TOPIC_MAP_OUTPUT_FILE" "$OPENSHIFT_DOCS_DIR/_topic_maps/_topic_map.yml"
    if [ $? -eq 0 ]; then
         print_message $GREEN "✅ Manually copied $TOPIC_MAP_OUTPUT_FILE to $OPENSHIFT_DOCS_DIR/_topic_maps/_topic_map.yml."
    else
         print_message $RED "❌ Failed to manually copy $TOPIC_MAP_OUTPUT_FILE."
    fi
else
    print_message $BLUE "⚙️ Processing topic map with $UPDATETOPICMAP_SCRIPT_PATH..."
    mkdir -p "$OPENSHIFT_DOCS_DIR/_topic_maps" # Ensure target directory exists for updatetopicmap.js
    node "$UPDATETOPICMAP_SCRIPT_PATH" "$(cat "$TOPIC_MAP_OUTPUT_FILE")" > /dev/null 2>&1

    if [[ $? -ne 0 ]]; then
        print_message $RED "❌ Failed to process topic map with $UPDATETOPICMAP_SCRIPT_PATH."
        if [ ! -f "$OPENSHIFT_DOCS_DIR/_topic_maps/_topic_map.yml" ]; then
             print_message $RED "  Final _topic_map.yml not found in $OPENSHIFT_DOCS_DIR/_topic_maps/."
        fi
    else
        if [ -f "$OPENSHIFT_DOCS_DIR/_topic_maps/_topic_map.yml" ]; then
            print_message $GREEN "✅ Topic map processed. Final _topic_map.yml should be in $OPENSHIFT_DOCS_DIR/_topic_maps/."
        else
            print_message $YELLOW "⚠️ $UPDATETOPICMAP_SCRIPT_PATH ran, but final _topic_map.yml not found in $OPENSHIFT_DOCS_DIR/_topic_maps/. Manual check might be needed."
        fi
    fi
fi

# 8. ZIP directories for artifact creation
print_message $BLUE "📦 Creating ZIP archive of documentation..."
cd "$OPENSHIFT_DOCS_DIR" # IMPORTANT: Change to openshift-docs directory for zipping

TEMP_EXPORT_DIR="/tmp/docs_export_$$" # Use process ID for uniqueness
mkdir -p "$TEMP_EXPORT_DIR"

if [ ! -d "$OPENSHIFT_DOCS_DIR/_topic_maps" ] || [ -z "$(ls -A "$OPENSHIFT_DOCS_DIR/_topic_maps" 2>/dev/null)" ]; then
    print_message $YELLOW "⚠️ Directory $OPENSHIFT_DOCS_DIR/_topic_maps is missing or empty. The topic map might be missing in the ZIP."
    mkdir -p "$OPENSHIFT_DOCS_DIR/_topic_maps" # Ensure dir exists for cp, even if empty
fi
if [ ! -d "$OPENSHIFT_DOCS_DIR/rest_api" ]; then
    print_message $RED "❌ Directory $OPENSHIFT_DOCS_DIR/rest_api not found. Cannot create ZIP without API docs."
    rm -rf "$TEMP_EXPORT_DIR"
    exit 1 # Cannot proceed without rest_api
fi

cp -r "$OPENSHIFT_DOCS_DIR/_topic_maps" "$TEMP_EXPORT_DIR/"
cp -r "$OPENSHIFT_DOCS_DIR/rest_api" "$TEMP_EXPORT_DIR/"

cd "$TEMP_EXPORT_DIR"
zip -rq "${OUTPUT_DIR}/${VERSION}_api_docs.zip" _topic_maps rest_api

if [[ $? -eq 0 ]]; then
    print_message $GREEN "✅ Created ZIP archive: ${OUTPUT_DIR}/${VERSION}_api_docs.zip (Contents: _topic_maps/, rest_api/)"
else
    print_message $RED "❌ Failed to create ZIP archive."
fi
rm -rf "$TEMP_EXPORT_DIR" # Clean up temporary export directory

# 9. Final Cleanup of files in WORK_DIR
print_message $BLUE "🧹 Cleaning up temporary files from $WORK_DIR..."
cd $WORK_DIR
rm -f "$OUTPUT_FILE_V1" "$OUTPUT_FILE_V2" # swagger jsons
rm -f "$TOPIC_MAP_OUTPUT_FILE" # $WORK_DIR/_topic_map.yml
rm -rf specs
rm -rf "$BASE_API_DIR" # $WORK_DIR/rest_api
# $OPENSHIFT_DOCS_DIR is not removed here as it's managed separately.

print_message $GREEN "✅ Cleanup completed."
print_message $GREEN "🎉 Documentation generation process finished!"
print_message $YELLOW "📋 Documentation package should be available at: ${OUTPUT_DIR}/${VERSION}_api_docs.zip"
