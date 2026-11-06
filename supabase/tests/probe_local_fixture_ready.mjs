// Test runtime only. No credentials or cloud endpoint; runner verifies data_directory.
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(fileURLToPath(new URL('../.temp/p011_pg_runtime/package.json', import.meta.url)));
const { Client } = require('pg');
const client = new Client({ host: '127.0.0.1', port: 55439, user: 'postgres', database: 'postgres', connectionTimeoutMillis: 500 });
try {
  await client.connect();
  const result = await client.query('show data_directory');
  const expected = fileURLToPath(new URL('../.temp/p011_native_data', import.meta.url));
  if (resolve(result.rows[0].data_directory).toLowerCase() !== resolve(expected).toLowerCase()) {
    throw new Error('Wrong fixture data directory');
  }
  process.exitCode = 0;
} catch {
  process.exitCode = 1;
} finally {
  await client.end().catch(() => {});
}
