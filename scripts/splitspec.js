const fs = require('fs');
const path = require('path');

function splitOpenApiSpec(inputFilePath) {
    // Read the input OpenAPI spec
    const inputSpec = JSON.parse(fs.readFileSync(inputFilePath, 'utf8'));

    let changesMadeToRefValues = 0; // Track changes made to $ref values for standardization
    let filesCreated = 0; // Will be incremented for common_object_reference.json only once if merged

    // Function to uppercase the first character of a string
    function uppercaseFirstChar(str) {
        if (typeof str !== 'string' || str.length === 0) {
            return str;
        }
        return str.charAt(0).toUpperCase() + str.slice(1);
    }

    // Function to standardize definition references (uppercase first letter of definition name)
    // This function ensures that $ref paths within definitions are consistently formatted.
    function standardizeDefinitionRefsInObject(obj) {
        if (typeof obj === 'object' && obj !== null) {
            for (const key in obj) {
                if (obj.hasOwnProperty(key)) {
                    if (key === '$ref' && typeof obj[key] === 'string' && obj[key].startsWith('#/definitions/')) {
                        const defName = obj[key].substring('#/definitions/'.length);
                        const uppercasedDefName = uppercaseFirstChar(defName);
                        const newRef = `#/definitions/${uppercasedDefName}`; // Internal refs always use this full path

                        if (obj[key] !== newRef) {
                            obj[key] = newRef;
                            changesMadeToRefValues++;
                        }
                    } else {
                        standardizeDefinitionRefsInObject(obj[key]);
                    }
                }
            }
        } else if (Array.isArray(obj)) {
            for (let i = 0; i < obj.length; i++) {
                standardizeDefinitionRefsInObject(obj[i]);
            }
        }
    }

    // Function to update $ref paths in tag-specific files to point to the common definitions file
    function pointRefsToCommonFile(obj, commonFileRelativePath) {
        if (typeof obj === 'object' && obj !== null) {
            for (const key in obj) {
                if (obj.hasOwnProperty(key)) {
                    if (key === '$ref' && typeof obj[key] === 'string' && obj[key].startsWith('#/definitions/')) {
                        const defName = obj[key].substring('#/definitions/'.length); // Assumes defName is already uppercased
                        obj[key] = `${commonFileRelativePath}#/definitions/${defName}`; // e.g., ./common_object_reference.json#/definitions/MyDefinition
                    } else {
                        pointRefsToCommonFile(obj[key], commonFileRelativePath);
                    }
                }
            }
        } else if (Array.isArray(obj)) {
            for (let i = 0; i < obj.length; i++) {
                pointRefsToCommonFile(obj[i], commonFileRelativePath);
            }
        }
    }

    // --- Step 1: Create the 'specs' directory ---
    const specsDir = path.join(__dirname, 'specs');
    if (!fs.existsSync(specsDir)) {
        fs.mkdirSync(specsDir);
    }

    // --- Step 2: Process and Save/Merge Definitions into common_object_reference.json ---
    const commonDefsFileRelativePath = './common_object_reference.json';
    const commonDefsFileAbsolutePath = path.join(specsDir, 'common_object_reference.json');
    let commonDefinitionsFileContent;

    if (fs.existsSync(commonDefsFileAbsolutePath)) {
        // Load existing common definitions if file exists
        commonDefinitionsFileContent = JSON.parse(fs.readFileSync(commonDefsFileAbsolutePath, 'utf8'));
        // Ensure essential fields are present
        commonDefinitionsFileContent.swagger = commonDefinitionsFileContent.swagger || inputSpec.swagger;
        commonDefinitionsFileContent.info = commonDefinitionsFileContent.info || JSON.parse(JSON.stringify(inputSpec.info));
        commonDefinitionsFileContent.paths = commonDefinitionsFileContent.paths || {};
        commonDefinitionsFileContent.definitions = commonDefinitionsFileContent.definitions || {};
        if (inputSpec.consumes && (!commonDefinitionsFileContent.consumes || commonDefinitionsFileContent.consumes.length === 0)) {
            commonDefinitionsFileContent.consumes = [...inputSpec.consumes];
        }
        if (inputSpec.produces && (!commonDefinitionsFileContent.produces || commonDefinitionsFileContent.produces.length === 0)) {
            commonDefinitionsFileContent.produces = [...inputSpec.produces];
        }
         if (inputSpec.tags && (!commonDefinitionsFileContent.tags || commonDefinitionsFileContent.tags.length === 0)) {
             commonDefinitionsFileContent.tags = JSON.parse(JSON.stringify(inputSpec.tags));
        }


    } else {
        // Initialize if file doesn't exist
        commonDefinitionsFileContent = {
            swagger: inputSpec.swagger,
            info: JSON.parse(JSON.stringify(inputSpec.info)),
            consumes: inputSpec.consumes ? [...inputSpec.consumes] : undefined,
            produces: inputSpec.produces ? [...inputSpec.produces] : undefined,
            paths: {}, // Add empty paths object for OpenAPI compliance
            definitions: {}
        };
        if (inputSpec.tags) {
            commonDefinitionsFileContent.tags = JSON.parse(JSON.stringify(inputSpec.tags));
        }
        filesCreated++; // Count file creation only once
    }

    // Process and merge definitions from the current inputSpec
    if (inputSpec.definitions) {
        for (const [defName, defValue] of Object.entries(inputSpec.definitions)) {
            const uppercasedDefName = uppercaseFirstChar(defName);
            const clonedDefValue = JSON.parse(JSON.stringify(defValue));
            // Standardize refs *within* this definition object to be #/definitions/AnotherDef
            standardizeDefinitionRefsInObject(clonedDefValue);
            commonDefinitionsFileContent.definitions[uppercasedDefName] = clonedDefValue; // Add or overwrite
        }
    }

    fs.writeFileSync(commonDefsFileAbsolutePath, JSON.stringify(commonDefinitionsFileContent, null, 2));

    // --- Step 3: Prepare Main Spec for Splitting (Tag-specific files) ---
    const specForSplitting = JSON.parse(JSON.stringify(inputSpec));
    delete specForSplitting.definitions; // Remove definitions from tag-specific files

    // Standardize $refs in the paths and other parts of the specForSplitting to use uppercased definition names
    // e.g., #/definitions/someName -> #/definitions/SomeName
    standardizeDefinitionRefsInObject(specForSplitting);

    // Point $refs to the common definitions file, ensuring the path includes #/definitions/
    // e.g., #/definitions/SomeName -> ./common_object_reference.json#/definitions/SomeName
    pointRefsToCommonFile(specForSplitting, commonDefsFileRelativePath);


    // --- Step 4: Split Paths by Tag ---
    const tagMap = {};
    if (specForSplitting.paths) {
        for (const [pathKey, pathValue] of Object.entries(specForSplitting.paths)) {
            for (const method of Object.keys(pathValue)) {
                const operation = pathValue[method];
                const operationTags = operation.tags || [];
                for (const tag of operationTags) {
                    if (!tagMap[tag]) {
                        tagMap[tag] = {
                            swagger: specForSplitting.swagger,
                            info: JSON.parse(JSON.stringify(specForSplitting.info)),
                            consumes: specForSplitting.consumes ? [...specForSplitting.consumes] : undefined,
                            produces: specForSplitting.produces ? [...specForSplitting.produces] : undefined,
                            paths: {},
                            tags: []
                        };
                        if (inputSpec.tags && Array.isArray(inputSpec.tags)) {
                            const currentTagObject = inputSpec.tags.find(t => t.name === tag);
                            if (currentTagObject) {
                                tagMap[tag].tags.push(JSON.parse(JSON.stringify(currentTagObject)));
                            }
                        }
                    }
                    if (!tagMap[tag].paths[pathKey]) {
                        tagMap[tag].paths[pathKey] = {};
                    }
                    tagMap[tag].paths[pathKey][method] = operation;
                }
            }
        }
    }

    // --- Step 5: Write Tag-Specific Files ---
    let tagSpecificFilesCreated = 0;
    for (const [tag, spec] of Object.entries(tagMap)) {
        const outputFilePath = path.join(specsDir, `${tag}.json`);
        fs.writeFileSync(outputFilePath, JSON.stringify(spec, null, 2));
        tagSpecificFilesCreated++;
    }
    // Adjust filesCreated to reflect total files (common + tag-specific)
    // If common file was pre-existing, filesCreated is 0 initially for it.
    // If it was new, filesCreated is 1. Then add tagSpecificFilesCreated.
    // This logic is a bit complex due to potential merging.
    // Let's simplify the log message for now.

    console.log(`Made ${changesMadeToRefValues} changes to $ref values (standardizing to uppercase).`);
    console.log(`Processed definitions into ${commonDefsFileAbsolutePath}.`);
    console.log(`Created ${tagSpecificFilesCreated} tag-specific spec files in ${specsDir}.`);
}

if (require.main === module) {
    const inputFilePathArg = process.argv[2];
    if (!inputFilePathArg) {
        console.error('Usage: node splitspec.js <path-to-openapi-spec.json>');
        console.error('Please provide the path to the OpenAPI spec JSON file.');
        process.exit(1);
    }
    console.log(`Processing OpenAPI spec: ${inputFilePathArg}`);
    try {
        splitOpenApiSpec(inputFilePathArg);
        console.log(`Successfully processed OpenAPI specification: ${inputFilePathArg}`);
    } catch (error) {
        console.error("Error processing the OpenAPI spec:", error.message);
        console.error(error.stack);
        process.exit(1);
    }
}

module.exports = { splitOpenApiSpec };
