const fs = require('fs');
const path = require('path');

function splitOpenApiSpec(inputFilePath) {
    // Read the input OpenAPI spec
    const inputSpec = JSON.parse(fs.readFileSync(inputFilePath, 'utf8'));

    // Create a map to hold paths by tags
    const tagMap = {};
    let changesMade = 0; // Track changes made to references

    // Function to uppercase the first character of a string
    function uppercaseFirstChar(str) {
        return str.charAt(0).toUpperCase() + str.slice(1);
    }

    // Function to update references to match definitions
    function replaceRefValues(obj) {
        if (typeof obj === 'object') {
            for (const key in obj) {
                if (key === '$ref' && obj[key].includes('#/definitions/')) {
                    const refValue = obj[key].split('#/definitions/')[1];
                    if (refValue[0] === refValue[0].toLowerCase()) {
                        obj[key] = `#/definitions/${uppercaseFirstChar(refValue)}`;
                        changesMade++;
                    }
                } else if (typeof obj[key] === 'object') {
                    replaceRefValues(obj[key]);
                }
            }
        }
    }

    // Update references in the input spec
    replaceRefValues(inputSpec);

    // Function to collect definitions from a schema reference
    function collectDefinitions(tag, schema, definitions) {
        if (schema.$ref) {
            const refName = schema.$ref.split('/').pop(); // Get the last part after the last '/'
            // Perform a case-insensitive search for the definition
            const matchingDefinition = Object.keys(definitions).find(defName => defName.toLowerCase() === refName.toLowerCase());
            if (matchingDefinition && !tagMap[tag].definitions[uppercaseFirstChar(matchingDefinition)]) {
                // Add the definition with the first character uppercased
                tagMap[tag].definitions[uppercaseFirstChar(matchingDefinition)] = definitions[matchingDefinition];
                // Recursively collect definitions from the referenced definition
                collectDefinitions(tag, definitions[matchingDefinition], definitions);
            }
        } else if (schema.type === 'object' && schema.properties) {
            for (const prop of Object.values(schema.properties)) {
                collectDefinitions(tag, prop, definitions);
            }
        } else if (schema.type === 'array' && schema.items) {
            collectDefinitions(tag, schema.items, definitions);
        }
    }

    // Function to collect definitions from various parts of the OpenAPI spec
    function collectFromSpec(tag, specPart) {
        if (specPart.responses) {
            for (const response of Object.values(specPart.responses)) {
                if (response.schema) {
                    collectDefinitions(tag, response.schema, inputSpec.definitions);
                }
            }
        }

        if (specPart.requestBody && specPart.requestBody.content) {
            for (const contentType of Object.keys(specPart.requestBody.content)) {
                const schema = specPart.requestBody.content[contentType].schema;
                if (schema) {
                    collectDefinitions(tag, schema, inputSpec.definitions);
                }
            }
        }

        if (specPart.parameters) {
            for (const parameter of specPart.parameters) {
                if (parameter.schema) {
                    collectDefinitions(tag, parameter.schema, inputSpec.definitions);
                }
            }
        }
    }

    // Iterate through paths and group them by tags
    for (const [pathKey, pathValue] of Object.entries(inputSpec.paths)) {
        for (const method of Object.keys(pathValue)) {
            const tags = pathValue[method].tags || [];
            for (const tag of tags) {
                if (!tagMap[tag]) {
                    tagMap[tag] = {
                        swagger: inputSpec.swagger,
                        info: inputSpec.info,
                        consumes: inputSpec.consumes,
                        produces: inputSpec.produces,
                        paths: {},
                        definitions: {}
                    };
                }
                // Add the path to the corresponding tag
                tagMap[tag].paths[pathKey] = pathValue;

                // Collect definitions from the current path's spec
                collectFromSpec(tag, pathValue[method]);
            }
        }
    }

    // Write each tag's spec to a separate file
    let filesCreated = 0; // Track the number of files created

    // Create the 'specs' directory if it doesn't exist
    const specsDir = path.join(__dirname, 'specs');
    if (!fs.existsSync(specsDir)) {
        fs.mkdirSync(specsDir);
    }

    for (const [tag, spec] of Object.entries(tagMap)) {
        const outputFilePath = path.join(specsDir, `${tag}.json`); // Update the path to the 'specs' directory
        fs.writeFileSync(outputFilePath, JSON.stringify(spec, null, 2));
        filesCreated++;
    }

    // Output the results
    console.log(`Made ${changesMade} changes to $ref values`);
    console.log(`Created ${filesCreated} files`);
}

// Get the input file path from command line arguments
const inputFilePath = process.argv[2];
if (!inputFilePath) {
    console.error('Please provide the path to the OpenAPI spec JSON file.');
    process.exit(1);
}

// Run the function
splitOpenApiSpec(inputFilePath);
