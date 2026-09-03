#!/usr/bin/env node
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const root = process.env.SOURCE_MCP_ROOT ?? '/opt/source-acquisition-runtime/chrome-devtools-mcp';
const gatewayUrl = process.env.SOURCE_MCP_GATEWAY_URL ?? 'http://127.0.0.1:8765/chrome-devtools/mcp';
const clientModule = pathToFileURL(path.join(root, 'node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js')).href;
const httpModule = pathToFileURL(path.join(root, 'node_modules/@modelcontextprotocol/sdk/dist/esm/client/streamableHttp.js')).href;
const {Client} = await import(clientModule);
const {StreamableHTTPClientTransport} = await import(httpModule);

const client = new Client({name: 'source-runtime-gateway-smoke', version: '0.1.0'}, {capabilities: {}});
const transport = new StreamableHTTPClientTransport(new URL(gatewayUrl));

function text(result) {
  return (result.content ?? []).filter((item) => item.type === 'text').map((item) => item.text).join('\n');
}

try {
  await client.connect(transport);
  const {tools} = await client.listTools();
  if (!tools.some((tool) => tool.name === 'list_pages')) throw new Error('list_pages tool missing through gateway');
  const pages = await client.callTool({name: 'list_pages', arguments: {}});
  if (pages.isError) throw new Error(`list_pages failed through gateway: ${text(pages)}`);
  console.log(`[PASS] gateway MCP tool discovery (${tools.length} tools)`);
  console.log(`[PASS] gateway list_pages: ${text(pages).slice(0, 300).replaceAll('\n', ' ')}`);
} finally {
  await client.close().catch(() => {});
}
