#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const checkOnly = args[0] === '--check';
const mcpRoot = checkOnly ? args[1] : args[0];

if (!mcpRoot) {
  console.error('usage: apply-compat-patches.mjs [--check] <mcp-root>');
  process.exit(2);
}

const packageJsonPath = path.join(mcpRoot, 'node_modules/chrome-devtools-mcp/package.json');
const pagesPath = path.join(mcpRoot, 'node_modules/chrome-devtools-mcp/build/src/tools/pages.js');
const marker = 'source-acquisition-runtime compatibility: issue #3';

if (!fs.existsSync(packageJsonPath) || !fs.existsSync(pagesPath)) {
  console.error('ERROR: chrome-devtools-mcp installation is incomplete');
  process.exit(1);
}

const pkg = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
if (pkg.version !== '1.8.0') {
  console.error(`ERROR: compatibility patch is defined only for chrome-devtools-mcp 1.8.0; observed ${pkg.version}`);
  process.exit(1);
}

let source = fs.readFileSync(pagesPath, 'utf8');
if (source.includes(marker)) {
  console.log(`[PASS] chrome-devtools-mcp ${pkg.version} navigate timeout compatibility patch present`);
  process.exit(0);
}

if (checkOnly) {
  console.error(`[FAIL] chrome-devtools-mcp ${pkg.version} navigate timeout compatibility patch missing`);
  process.exit(1);
}

const oldBlock = `                            catch (error) {\n                                response.appendResponseLine(\`Unable to navigate in the selected page: \${error.message}.\`);\n                            }`;
const newBlock = `                            catch (error) {\n                                // ${marker}\n                                // Puppeteer can time out waiting for navigation completion after the\n                                // browser has already reached the requested URL. Distinguish that\n                                // verified state from a true navigation failure so callers do not\n                                // blindly repeat a potentially non-idempotent navigation.\n                                const actualUrl = page.pptrPage.url();\n                                const isNavigationTimeout = error instanceof Error &&\n                                    /^Navigation timeout of \\d+ ms exceeded$/.test(error.message);\n                                let reachedRequestedUrl = false;\n                                try {\n                                    const requested = new URL(request.params.url);\n                                    const actual = new URL(actualUrl);\n                                    requested.hash = '';\n                                    actual.hash = '';\n                                    reachedRequestedUrl = requested.toString() === actual.toString();\n                                }\n                                catch {\n                                    reachedRequestedUrl = actualUrl === request.params.url;\n                                }\n                                if (isNavigationTimeout && reachedRequestedUrl) {\n                                    response.appendResponseLine(\`Navigation reached the requested URL, but load completion timed out: \${error.message}. Verify page state before retrying.\`);\n                                }\n                                else {\n                                    response.appendResponseLine(\`Unable to navigate in the selected page: \${error.message}.\`);\n                                }\n                            }`;

const occurrences = source.split(oldBlock).length - 1;
if (occurrences !== 1) {
  console.error(`ERROR: expected exactly one chrome-devtools-mcp 1.8.0 navigate_page block, found ${occurrences}; refusing to patch`);
  process.exit(1);
}

source = source.replace(oldBlock, newBlock);
fs.writeFileSync(pagesPath, source);
console.log(`[PASS] applied chrome-devtools-mcp ${pkg.version} navigate timeout compatibility patch`);
