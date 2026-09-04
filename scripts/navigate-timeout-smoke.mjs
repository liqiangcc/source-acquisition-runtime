#!/usr/bin/env node
import http from 'node:http';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const root = process.env.SOURCE_MCP_ROOT ?? '/opt/source-acquisition-runtime/chrome-devtools-mcp';
const gatewayUrl = process.env.SOURCE_MCP_GATEWAY_URL ?? 'http://127.0.0.1:8765/chrome-devtools/mcp';
const clientModule = pathToFileURL(path.join(root, 'node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js')).href;
const httpModule = pathToFileURL(path.join(root, 'node_modules/@modelcontextprotocol/sdk/dist/esm/client/streamableHttp.js')).href;
const {Client} = await import(clientModule);
const {StreamableHTTPClientTransport} = await import(httpModule);

const client = new Client({name: 'source-runtime-navigate-timeout-smoke', version: '0.1.0'}, {capabilities: {}});
const transport = new StreamableHTTPClientTransport(new URL(gatewayUrl));
let createdPageId;
let server;

function text(result) {
  return (result.content ?? []).filter((item) => item.type === 'text').map((item) => item.text).join('\n');
}

function pageIds(output) {
  return new Set(output.split('\n').map((line) => line.match(/^(\d+):/)?.[1]).filter(Boolean).map(Number));
}

try {
  server = http.createServer((req, res) => {
    if (req.url !== '/slow') {
      res.writeHead(404, {'content-type': 'text/plain'});
      res.end('not found');
      return;
    }
    res.writeHead(200, {'content-type': 'text/html; charset=utf-8'});
    res.write('<!doctype html><html><head><title>navigate timeout smoke</title></head><body>target reached');
    const finish = setTimeout(() => res.end('</body></html>'), 4000);
    finish.unref();
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('failed to bind local slow server');
  const targetUrl = `http://127.0.0.1:${address.port}/slow`;

  await client.connect(transport);
  const {tools} = await client.listTools();
  for (const required of ['list_pages', 'new_page', 'navigate_page', 'close_page']) {
    if (!tools.some((tool) => tool.name === required)) throw new Error(`${required} tool missing through gateway`);
  }

  const before = pageIds(text(await client.callTool({name: 'list_pages', arguments: {}})));
  const opened = await client.callTool({name: 'new_page', arguments: {url: 'about:blank', background: true}});
  if (opened.isError) throw new Error(`new_page failed: ${text(opened)}`);
  const afterOpenText = text(await client.callTool({name: 'list_pages', arguments: {}}));
  createdPageId = [...pageIds(afterOpenText)].find((id) => !before.has(id));
  if (!createdPageId) throw new Error('could not identify smoke-test page');

  const started = Date.now();
  const nav = await client.callTool({
    name: 'navigate_page',
    arguments: {pageId: createdPageId, type: 'url', url: targetUrl, timeout: 1000},
  });
  const elapsed = Date.now() - started;
  const navText = text(nav);

  if (!navText.includes('Navigation reached the requested URL, but load completion timed out')) {
    throw new Error(`navigate_page did not return verified timeout partial-success: ${navText.slice(0, 500)}`);
  }
  if (navText.includes('Unable to navigate in the selected page')) {
    throw new Error('navigate_page still reports reached-target timeout as failure');
  }

  const afterNavText = text(await client.callTool({name: 'list_pages', arguments: {}}));
  const currentLine = afterNavText.split('\n').find((line) => line.startsWith(`${createdPageId}:`)) ?? '';
  if (!currentLine.includes(targetUrl)) {
    throw new Error('page URL did not reach the slow target after timeout');
  }

  console.log(`[PASS] navigate_page timeout classified as reached-target partial success (${elapsed} ms)`);
  console.log('[PASS] final page URL equals requested slow target');
} finally {
  if (createdPageId) {
    await client.callTool({name: 'close_page', arguments: {pageId: createdPageId}}).catch(() => {});
  }
  await client.close().catch(() => {});
  if (server) {
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(resolve));
  }
}
