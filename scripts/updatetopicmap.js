#!/usr/bin/env node

// This script updates the _topic_map.yml file in openshift-docs repository.
// It reads the content of the file, finds the line number where `Name: API reference` starts,
// deletes the content between `Name: API reference` and `---` or end of file,
// and inserts the new topic_map content at the position where the content was deleted.

const fs = require('fs');
const path = require('path');

// Get the topic_map content from the command line arguments
let topicMap = process.argv[2];
const filePath = path.join('/', 'openshift-docs', '_topic_maps', '_topic_map.yml');

// Read the content of the file
let content = fs.readFileSync(filePath, 'utf8');

// Replace literal \n with actual newlines in topicMap
if (topicMap) {
    topicMap = topicMap.replace(/\\n/g, '\n');
} else {
    console.error('Error: topicMap is empty or undefined');
    //exit with error
    process.exit(1);
}

// Find the line number where `Name: API reference` starts
const startLine = content.split('\n').findIndex(line => line.trim() === 'Name: API reference');

if (startLine !== -1) {
    // Find the line number where `---` or end of file occurs after `Name: API reference`
    const linesAfterStart = content.split('\n').slice(startLine + 1);
    const endLineAfterStart = linesAfterStart.findIndex(line => line.trim() === '---');
    let endLine;
    if (endLineAfterStart !== -1) {
        endLine = startLine + 1 + endLineAfterStart + 1; // Include the '---' line
    } else {
        endLine = content.split('\n').length;
    }

    // Delete lines from startLine to endLine
    const lines = content.split('\n');
    const updatedContent = lines.slice(0, startLine).join('\n');

    // Insert topic_map at the position where lines were deleted
    const finalContent = updatedContent + '\n' + topicMap;

    // Save the updated content back to the file
    fs.writeFileSync(filePath, finalContent, 'utf8');
} else {
    const finalContent = content + '---\n' + topicMap;
    fs.writeFileSync(filePath, finalContent, 'utf8');
}
