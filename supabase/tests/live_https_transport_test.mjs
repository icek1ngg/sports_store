import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import https from 'node:https';
import { after, test } from 'node:test';

import {
  closeLiveTransport,
  createLiveResponse,
  liveFetch,
} from './live_https_transport.mjs';

after(closeLiveTransport);

test('HTTP 200 preserves JSON bytes and response headers', async () => {
  const response = createLiveResponse(
    { statusCode: 200, headers: { 'content-type': 'application/json' } },
    [Buffer.from('{"message":"Đã '), Buffer.from('đăng xuất"}')],
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), 'application/json');
  assert.deepEqual(await response.json(), { message: 'Đã đăng xuất' });
});

for (const statusCode of [204, 205, 304]) {
  test(`HTTP ${statusCode} produces a bodyless Fetch response`, async () => {
    const response = createLiveResponse({ statusCode, headers: {} }, []);

    assert.equal(response.status, statusCode);
    assert.equal(response.body, null);
    assert.equal(await response.text(), '');
  });
}

test('response construction errors reject liveFetch instead of escaping an event', async (t) => {
  t.mock.method(https, 'request', (_url, _options, onResponse) => {
    const request = new EventEmitter();
    request.end = () => queueMicrotask(() => {
      const response = new EventEmitter();
      response.statusCode = 0;
      response.headers = {};
      onResponse(response);
      response.emit('end');
    });
    return request;
  });

  await assert.rejects(liveFetch('https://example.invalid'), RangeError);
});

test('request network failures reject liveFetch with the original error', async (t) => {
  const failure = new Error('Isolated request socket failure');
  t.mock.method(https, 'request', () => {
    const request = new EventEmitter();
    request.end = () => queueMicrotask(() => request.emit('error', failure));
    return request;
  });

  await assert.rejects(liveFetch('https://example.invalid'), (error) => error === failure);
});
