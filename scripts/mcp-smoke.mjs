#!/usr/bin/env node
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const root = process.env.SOURCE_MCP_ROOT ?? '/opt/source-acquisition-runtime/chrome-devtools-mcp';
const cdpUrl = process.env.SOURCE_CHROME_CDP_URL ?? 'http://127.0.0.1:9222';
const clientModule = pathToFileURL(path.join(root, 'node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js')).href;
const stdioModule = pathToFileURL(path.join(root, 'node_modules/@modelcontextprotocol/sdk/dist/esm/client/stdio.js')).href;
const {Client} = await import(clientModule);
const {StdioClientTransport} = await import(stdioModule);

const transport = new StdioClientTransport({
  command: path.join(root, 'node_modules/.bin/chrome-devtools-mcp'),
  args: [`--browser-url=${cdpUrl}`],
});
const client = new Client({name: 'source-runtime-smoke', version: '0.1.0'}, {capabilities: {}});

function text(result) {
  return (result.content ?? []).filter((item) => item.type === 'text').map((item) => item.text).join('\n');
}

async function call(name, args = {}) {
  const result = await client.callTool({name, arguments: args});
  if (result.isError) throw new Error(`${name} failed: ${text(result)}`);
  return result;
}

try {
  await client.connect(transport);
  const {tools} = await client.listTools();
  const names = new Set(tools.map((tool) => tool.name));
  for (const required of ['list_pages', 'new_page', 'take_snapshot', 'evaluate_script']) {
    if (!names.has(required)) throw new Error(`required tool missing: ${required}`);
  }

  const pages = await call('list_pages');
  console.log(`[PASS] MCP tool discovery (${tools.length} tools)`);
  console.log(`[PASS] list_pages: ${text(pages).slice(0, 300).replaceAll('\n', ' ')}`);

  await call('new_page', {url: 'https://example.com', timeout: 15000});
  const exampleSnapshot = await call('take_snapshot');
  const exampleText = text(exampleSnapshot);
  if (!/Example Domain/i.test(exampleText)) throw new Error('example.com snapshot did not contain expected text');
  console.log('[PASS] outbound navigation + page snapshot: https://example.com');

  const html = '<!doctype html><title>before</title><button id="pilot" onclick="document.title=\'after\';this.textContent=\'clicked\'">click me</button>';
  await call('new_page', {url: `data:text/html,${encodeURIComponent(html)}`});
  const before = text(await call('take_snapshot'));
  if (!/click me/i.test(before)) throw new Error('test button not visible in pre-interaction snapshot');
  const interaction = await call('evaluate_script', {
    function: "() => { const button = document.querySelector('#pilot'); button.click(); return {title: document.title, text: button.textContent}; }",
  });
  const after = text(await call('take_snapshot'));
  if (!/clicked/i.test(after) || !/after/i.test(text(interaction))) throw new Error('browser interaction verification failed');
  console.log('[PASS] page structure + simple interaction via MCP');
} finally {
  await client.close().catch(() => {});
}
