#!/bin/bash

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Set the version from environment variable
VERSION=${VERSION:-"4.6.0"}
WORK_DIR="/rhacs-api-docs-gen"
OUTPUT_DIR="/output"
ROOT_DIR="rest_api"
TOPIC_MAP_FILE="_topic_map.yml"

# Function definitions
print_message() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

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

                            _   _
                  /\       | | (_)
                 /  \   ___| |_ _  ___  _ __
                / /\ \ / __| __| |/ _ \| '_ \
               / ____ \ (__| |_| | (_) | | | |
              /_/    \_\___|\__|_|\___/|_| |_|

EOF
}

# Download OpenAPI specification for a specific version
download_openapi_spec() {
    local version=$1
    local version_num=$2
    print_message $BLUE "📥 Downloading OpenAPI specification for $version..."
    local url="https://mirror.openshift.com/pub/rhacs/openapi-spec/${VERSION}/${version}.swagger.json"
    local output_file="${version}.swagger.json"

    curl -s -o "$output_file" "$url"
    if [[ $? -ne 0 ]]; then
        print_message $RED "❌ Failed to download the OpenAPI specification $version."
        exit 1
    fi
    print_message $GREEN "✅ Downloaded OpenAPI specification $version."
}

# Process OpenAPI spec files
process_api_version() {
    local version=$1
    local skip_pattern=$2

    print_message $BLUE "🔄 Processing $version specification..."
    # Split the spec into smaller files by tag
    node splitspecwithoutdefinitions.js ${version}.swagger.json 2>&1 | grep -i "error" || true

    # Generate AsciiDoc files
    print_message $BLUE "📄 Generating AsciiDoc files for $version with parallel processing (8 workers)..."
    mkdir -p "$ROOT_DIR/$version"

    # Count total spec files for progress reporting - ensure they exist first
    local total_spec_files=0
    if ! ls specs/*/*.json >/dev/null 2>&1; then
        print_message $RED "❌ No spec files found to process. Splitting may have failed."
        exit 1
    fi

    # Get an accurate count of files to process
    for tag_dir in specs/*/; do
        for spec_file in "$tag_dir"/*.json; do
            base_name=$(basename "$spec_file" .json)
            if [[ "$base_name" != $skip_pattern* ]]; then
                total_spec_files=$((total_spec_files + 1))
            fi
        done
    done

    print_message $CYAN "  Found $total_spec_files spec files to process for $version"
    local current=0
    local progress_step=$((total_spec_files / 10 > 0 ? total_spec_files / 10 : 1))

    # Using a semaphore approach for limited parallelism in generation
    local max_parallel=8
    local running=0
    local pids=()
    local failed_files=0

    # Process each tag directory
    for tag_dir in specs/*/; do
        tag_name=$(basename "$tag_dir")
        output_tag_dir="$ROOT_DIR/$version/$tag_name"
        mkdir -p "$output_tag_dir"

        # Process each spec file in the tag directory
        for spec_file in "$tag_dir"/*.json; do
            base_name=$(basename "$spec_file" .json)

            # Skip files with the specified pattern
            if [[ "$base_name" == $skip_pattern* ]]; then
                continue
            fi

            current=$((current + 1))
            # Show progress at intervals
            if [[ $((current % progress_step)) -eq 0 ]] || [[ $current -eq $total_spec_files ]]; then
                percentage=$((current * 100 / total_spec_files))
                print_message $CYAN "  Progress: $current/$total_spec_files files ($percentage%)"
            fi

            output_file="$output_tag_dir/${base_name//[\{\}]/}.adoc"

            # Wait if we've reached max parallel processes
            if [[ $running -ge $max_parallel ]]; then
                # Wait for any child process to finish
                wait -n
                running=$((running - 1))
            fi

            # Generate AsciiDoc files in the background with proper error capture
            {
                # Run the OpenAPI generator
                bash /usr/local/bin/docker-entrypoint.sh generate \
                    -i "$spec_file" \
                    -g asciidoc \
                    -o "$output_tag_dir" >/dev/null 2>&1

                gen_result=$?

                # Only attempt to rename if generation succeeded
                if [[ $gen_result -eq 0 ]]; then
                    # Rename the generated index.adoc to match the spec file name if it exists
                    if [ -f "$output_tag_dir/index.adoc" ]; then
                        mv "$output_tag_dir/index.adoc" "$output_file"
                    else
                        # Record the failure but don't show an error message during processing
                        # as this would clutter the output during parallel execution
                        failed_files=$((failed_files + 1))
                        echo "Failed to generate file for: $spec_file" >> /tmp/generation_errors.log
                    fi
                else
                    # Record generation failures
                    failed_files=$((failed_files + 1))
                    echo "Generation failed for: $spec_file" >> /tmp/generation_errors.log
                fi
            } &
            pids+=($!)
            running=$((running + 1))
        done
    done

    # Wait for all remaining processes
    wait

    # Check for and report errors after all processes complete
    if [[ $failed_files -gt 0 ]]; then
        print_message $YELLOW "⚠️ $failed_files file(s) could not be generated properly."
        if [[ -f /tmp/generation_errors.log ]]; then
            print_message $YELLOW "See detailed errors in log:"
            cat /tmp/generation_errors.log | head -10 # Show first 10 errors
            if [[ $(cat /tmp/generation_errors.log | wc -l) -gt 10 ]]; then
                print_message $YELLOW "...and more. Total error count: $(cat /tmp.generation_errors.log | wc -l)"
            fi
            rm /tmp/generation_errors.log
        fi
    fi

    # Remove empty directories
    for tag_dir in "$ROOT_DIR/$version"/*/; do
        if [ -d "$tag_dir" ] && [ -z "$(ls -A "$tag_dir" 2>/dev/null)" ]; then
            rmdir "$tag_dir"
        fi
    done

    # Re-count the actual generated files to make sure the counts are accurate
    local generated_files=$(find "$ROOT_DIR/$version" -type f -name "*.adoc" | wc -l)
    print_message $GREEN "✅ Successfully generated $generated_files AsciiDoc files for $version"

    # Update AsciiDoc files to fix links and formatting
    update_asciidoc_files "$version"
}

# Update AsciiDoc files for proper linking and formatting
update_asciidoc_files() {
    local version=$1
    print_message $BLUE "🔧 Updating AsciiDoc files for $version with parallel processing (8 workers)..."

    # Check if there are any files to process
    if ! find "$ROOT_DIR/$version" -type f -name "*.adoc" | grep -q .; then
        print_message $RED "❌ No AsciiDoc files found to update for $version."
        return 1
    fi

    local total_files=$(find "$ROOT_DIR/$version" -type f -name "*.adoc" | wc -l)
    local current=0
    local progress_step=$((total_files / 10 > 0 ? total_files / 10 : 1))
    local failed_updates=0

    local max_parallel=8
    local running=0
    local pids=()

    find "$ROOT_DIR/$version" -type f -name "*.adoc" | while read -r adoc_file; do
        current=$((current + 1))

        # Show progress at intervals
        if [[ $((current % progress_step)) -eq 0 ]] || [[ $current -eq $total_files ]]; then
            percentage=$((current * 100 / total_files))
            print_message $CYAN "  Progress: $current/$total_files files ($percentage%)"
        fi

        # Wait if we've reached max parallel processes
        if [[ $running -ge $max_parallel ]]; then
            # Wait for any child process to finish
            wait -n
            running=$((running - 1))
        fi

        # Process file in the background with proper error handling
        {
            node updateasciidoc.js "$adoc_file" > /dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                echo "Failed to update: $adoc_file" >> /tmp/update_errors.log
                failed_updates=$((failed_updates + 1))
            fi
        } &
        pids+=($!)
        running=$((running + 1))
    done

    # Wait for all remaining processes
    wait

    # Check for and report errors after all processes complete
    if [[ $failed_updates -gt 0 ]]; then
        print_message $YELLOW "⚠️ $failed_updates file(s) could not be updated properly."
        if [[ -f /tmp/update_errors.log ]]; then
            print_message $YELLOW "See detailed errors in log:"
            cat /tmp/update_errors.log | head -10 # Show first 10 errors
            if [[ $(cat /tmp/update_errors.log | wc -l) -gt 10 ]]; then
                print_message $YELLOW "...and more. Total error count: $(cat /tmp/update_errors.log | wc -l)"
            fi
            rm /tmp/update_errors.log
        fi
    fi

    # Re-count the actual updated files to ensure accuracy
    local actual_files=$(find "$ROOT_DIR/$version" -type f -name "*.adoc" | wc -l)
    print_message $GREEN "✅ Processed $actual_files $version AsciiDoc files."
}

# Create topic map from generated files
create_topic_map() {
    print_message $BLUE "🗂️ Creating topic map..."

    # Start the YAML structure
    echo "---" > "$TOPIC_MAP_FILE"
    echo "Name: API reference" >> "$TOPIC_MAP_FILE"
    echo "Dir: $ROOT_DIR" >> "$TOPIC_MAP_FILE"
    echo "Distros: openshift-acs" >> "$TOPIC_MAP_FILE"
    echo "Topics:" >> "$TOPIC_MAP_FILE"

    # Process each version directory
    for version in "v1" "v2"; do
        echo "- Name: Version $version" >> "$TOPIC_MAP_FILE"
        echo "  Dir: $version" >> "$TOPIC_MAP_FILE"
        echo "  Topics:" >> "$TOPIC_MAP_FILE"

        # Process each service directory
        for service in "$ROOT_DIR/$version"/*/; do
            service_name=$(basename "$service")

            echo "  - Name: $service_name" >> "$TOPIC_MAP_FILE"
            echo "    Dir: $service_name" >> "$TOPIC_MAP_FILE"
            echo "    Topics:" >> "$TOPIC_MAP_FILE"

            # Process each .adoc file in the service directory
            for file in "$service"/*.adoc; do
                if [[ -f "$file" ]]; then
                    # Extract the name from the file
                    name=$(grep -m 1 '^=' "$file" | sed 's/^= //')
                    file_name=$(basename "$file" .adoc) # Remove the .adoc extension
                    echo "    - Name: $name" >> "$TOPIC_MAP_FILE"
                    echo "      File: $file_name" >> "$TOPIC_MAP_FILE"
                fi
            done
        done
    done

    # Add new line at the end of the file
    echo "" >> "$TOPIC_MAP_FILE"

    # Create a directory structure for the _topic_maps directory
    mkdir -p "_topic_maps"
    cp "$TOPIC_MAP_FILE" "_topic_maps/"
    print_message $GREEN "✅ Created topic map."
}

# Package all generated documentation
package_docs() {
    print_message $BLUE "📦 Creating ZIP archive of documentation..."

    # Create the ZIP from the generated directories
    zip -rq "${OUTPUT_DIR}/${VERSION}_api_docs.zip" _topic_maps $ROOT_DIR

    print_message $GREEN "✅ Created ZIP archive: ${VERSION}_api_docs.zip"
}

# Clean up temporary files
cleanup() {
    print_message $BLUE "🧹 Cleaning up..."
    rm -rf specs v1.swagger.json v2.swagger.json $ROOT_DIR _topic_maps $TOPIC_MAP_FILE
    print_message $GREEN "✅ Cleanup completed."
}

# MAIN EXECUTION STARTS HERE

# Create output directory
mkdir -p $OUTPUT_DIR
cd $WORK_DIR

# Print banner and start message
print_banner
print_message $BLUE "Starting API docs generation for RHACS version: $VERSION"

# Download OpenAPI specifications in parallel
download_openapi_spec "v1" &
download_openapi_spec "v2" &
wait

# Process both API versions in parallel
print_message $BLUE "🔄 Processing API versions in parallel..."
process_api_version "v1" "_v2" &
v1_pid=$!
process_api_version "v2" "_v1" &
v2_pid=$!

# Wait for both processes to complete
wait $v1_pid
wait $v2_pid

# Clean up specs directories
rm -rf specs

# Remove OpenAPI generator artifacts
print_message $BLUE "🧹 Removing OpenAPI generator artifacts..."
# Use -depth to process directory contents before the directory itself
find "$ROOT_DIR" -depth -type d -name ".openapi-generator" -exec rm -rf {} \; 2>/dev/null || true
find "$ROOT_DIR" -type f -name ".openapi-generator-ignore" -exec rm -f {} \; 2>/dev/null || true
print_message $GREEN "✅ Removed OpenAPI generator artifacts."

# Fix tags using the fix_tags.sh script
print_message $BLUE "🔧 Fixing tags in AsciiDoc files..."
bash fix_tags.sh
print_message $GREEN "✅ Fixed tags in AsciiDoc files."

# Create topic map, package docs, and clean up
create_topic_map
package_docs
cleanup

print_message $GREEN "🎉 Documentation generation completed successfully!"
print_message $YELLOW "📋 Documentation package is available at: ${OUTPUT_DIR}/${VERSION}_api_docs.zip"
