const fs = require("fs");
const path = require("path");

function splitOpenApiSpecWithoutDefinitions(inputFilePath) {
  // Read the input OpenAPI spec
  const inputSpec = JSON.parse(fs.readFileSync(inputFilePath, "utf8"));

  // Create a map to hold paths by tags
  const tagMap = {};
  let changesMade = 0; // Track changes made to references
  const referencedDefinitions = new Set(); // Track referenced definitions

  // Function to uppercase the first character of a string
  function uppercaseFirstChar(str) {
    return str.charAt(0).toUpperCase() + str.slice(1);
  }

  // Function to update references to match definitions and collect referenced definitions
  function replaceRefValues(obj) {
    if (typeof obj === "object") {
      for (const key in obj) {
        if (key === "$ref" && obj[key].includes("#/definitions/")) {
          const refValue = obj[key].split("#/definitions/")[1];
          referencedDefinitions.add(refValue);
          if (refValue[0] === refValue[0].toLowerCase()) {
            obj[key] = `#/definitions/${uppercaseFirstChar(refValue)}`;
            changesMade++;
          }
        } else if (typeof obj[key] === "object") {
          replaceRefValues(obj[key]);
        }
      }
    }
  }

  // Function to collect definitions from a schema reference
  function collectDefinitions(schema, definitions, collectedDefinitions) {
    if (schema.$ref) {
      const refName = schema.$ref.split('/').pop();
      const matchingDefinition = Object.keys(definitions).find(defName => defName.toLowerCase() === refName.toLowerCase());
      if (matchingDefinition && !collectedDefinitions[uppercaseFirstChar(matchingDefinition)]) {
        collectedDefinitions[uppercaseFirstChar(matchingDefinition)] = definitions[matchingDefinition];
        collectDefinitions(definitions[matchingDefinition], definitions, collectedDefinitions);
      }
    } else if (schema.type === 'object' && schema.properties) {
      for (const prop of Object.values(schema.properties)) {
        collectDefinitions(prop, definitions, collectedDefinitions);
      }
    } else if (schema.type === 'array' && schema.items) {
      collectDefinitions(schema.items, definitions, collectedDefinitions);
    } else if (schema.allOf) {
      for (const subSchema of schema.allOf) {
        collectDefinitions(subSchema, definitions, collectedDefinitions);
      }
    } else if (schema.oneOf) {
      for (const subSchema of schema.oneOf) {
        collectDefinitions(subSchema, definitions, collectedDefinitions);
      }
    } else if (schema.anyOf) {
      for (const subSchema of schema.anyOf) {
        collectDefinitions(subSchema, definitions, collectedDefinitions);
      }
    } else if (schema.additionalProperties) {
      collectDefinitions(schema.additionalProperties, definitions, collectedDefinitions);
    }
  }

  // Function to collect definitions from various parts of the OpenAPI spec
  function collectFromSpec(specPart, definitions, collectedDefinitions) {
    if (specPart.responses) {
      for (const response of Object.values(specPart.responses)) {
        if (response.schema) {
          collectDefinitions(response.schema, definitions, collectedDefinitions);
        }
      }
    }

    if (specPart.requestBody && specPart.requestBody.content) {
      for (const contentType of Object.keys(specPart.requestBody.content)) {
        const schema = specPart.requestBody.content[contentType].schema;
        if (schema) {
          collectDefinitions(schema, definitions, collectedDefinitions);
        }
      }
    }

    if (specPart.parameters) {
      for (const parameter of specPart.parameters) {
        if (parameter.schema) {
          collectDefinitions(parameter.schema, definitions, collectedDefinitions);
        }
      }
    }
  }

  // Update references in the input spec
  replaceRefValues(inputSpec);

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
            definitions: {},
          };
        }
        // Add the path to the corresponding tag
        if (!tagMap[tag].paths[pathKey]) {
          tagMap[tag].paths[pathKey] = {};
        }
        tagMap[tag].paths[pathKey][method] = pathValue[method];
      }
    }
  }

  // Write each tag's spec to a separate folder and file
  let filesCreated = 0; // Track the number of files created

  // Create the 'specs' directory if it doesn't exist
  const specsDir = path.join(__dirname, "specs");
  if (!fs.existsSync(specsDir)) {
    fs.mkdirSync(specsDir);
  }

  for (const [tag, spec] of Object.entries(tagMap)) {
    const tagDir = path.join(specsDir, tag);
    if (!fs.existsSync(tagDir)) {
      fs.mkdirSync(tagDir);
    }

    for (const [pathKey, pathValue] of Object.entries(spec.paths)) {
      for (const [method, methodValue] of Object.entries(pathValue)) {
        const collectedDefinitions = {};
        collectFromSpec(methodValue, inputSpec.definitions, collectedDefinitions);

        const fileName = `${pathKey.replace(/\//g, "_")}_${method}.json`;
        const outputFilePath = path.join(tagDir, fileName);
        const pathSpec = {
          swagger: spec.swagger,
          info: spec.info,
          consumes: spec.consumes,
          produces: spec.produces,
          paths: {
            [pathKey]: {
              [method]: methodValue,
            },
          },
          definitions: collectedDefinitions,
        };
        fs.writeFileSync(outputFilePath, JSON.stringify(pathSpec, null, 2));
        filesCreated++;
      }
    }
  }

  // Output the results
  console.log(`Made ${changesMade} changes to $ref values`);
  console.log(`Created ${filesCreated} files`);
}

// Get the input file path from command line arguments
const inputFilePath = process.argv[2];

if (!inputFilePath) {
  console.error("Please provide the path to the OpenAPI spec JSON file.");
  process.exit(1);
}

// Run the function
splitOpenApiSpecWithoutDefinitions(inputFilePath);
