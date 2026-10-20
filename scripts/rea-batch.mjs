// One owned REA MCP session. A JSON plan contains explicit read-only tool calls.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '../.tools/node_modules/@modelcontextprotocol/client/dist/index.mjs';
import { StdioClientTransport } from '../.tools/node_modules/@modelcontextprotocol/client/dist/stdio.mjs';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [path.join(root, '.tools/node_modules/rea-agents/scripts/rea.mjs'), 'mcp'],
  env: Object.fromEntries(Object.entries(process.env).filter(([,v]) => typeof v === 'string')),
  stderr: 'pipe',
});
const client = new Client({name: 'ac8-readonly-research', version: '0.1.0'});
const evidence = path.join(root, 'evidence');
fs.mkdirSync(evidence, {recursive: true});
const stderr = fs.createWriteStream(path.join(evidence, 'rea-mcp-stderr.log'), {flags: 'a'});
let opened = false;
try {
  await client.connect(transport);
  transport.stderr?.on('data', chunk => stderr.write(chunk));
  const list = await client.listTools();
  fs.writeFileSync(path.join(evidence, 'rea-tool-schemas.json'), JSON.stringify(list, null, 2));
  console.log(`Connected to REA; ${list.tools.length} tools advertised.`);
  if (process.argv[2]) {
    const plan = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
    const allowed = new Set(['open_binary','binary_overview','binary_session','search_strings','search_procedures','list_procedures','xrefs','procedure_pseudo_code','analyze_function','read_bytes','address_to_file_offset']);
    for (const step of plan) {
      if (!allowed.has(step.name)) throw new Error(`Not in read-only allowlist: ${step.name}`);
      if (!/^[a-zA-Z0-9_-]+$/.test(step.output)) throw new Error('Unsafe output filename');
      console.log(`Starting ${step.name} (${step.output})`);
      let result;
      try {
        result = await client.callTool({name: step.name, arguments: step.arguments ?? {}}, {timeout: 400000});
      } catch (error) {
        fs.writeFileSync(path.join(evidence, `${step.output}-error.json`), JSON.stringify({name:error.name,message:error.message,code:error.code,data:error.data}, null, 2));
        throw error;
      }
      fs.writeFileSync(path.join(evidence, `${step.output}.json`), JSON.stringify(result, null, 2));
      if (result.isError) throw new Error(`REA reported error; inspect ${step.output}.json`);
      if (step.name === 'open_binary') opened = true;
      console.log(`Saved ${step.output}.json`);
    }
  }
} finally {
  if (opened) {
    try { await client.callTool({name:'close_binary', arguments:{}}, {timeout:30000}); }
    catch (e) { console.error(`Close warning: ${e.message}`); }
  }
  await client.close();
  stderr.end();
}
