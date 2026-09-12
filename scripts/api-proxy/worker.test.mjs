import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildOriginRequest } from './worker.js';

test('ホスト名だけを転送先に差し替え、パス・クエリ・メソッド・ヘッダー・ボディを保つ', async () => {
  const forwarded = buildOriginRequest(
    new Request('https://api.signalarm.app/v1/alarms?dry_run=1', {
      method: 'POST',
      headers: { authorization: 'Bearer alm_test', 'content-type': 'application/json' },
      body: '{"fire_in":60,"title":"Deploy finished"}',
    }),
    'https://alarmsapi-320409781062.asia-northeast1.run.app',
  );
  assert.equal(forwarded.url, 'https://alarmsapi-320409781062.asia-northeast1.run.app/v1/alarms?dry_run=1');
  assert.equal(forwarded.method, 'POST');
  assert.equal(forwarded.headers.get('authorization'), 'Bearer alm_test');
  assert.equal(forwarded.headers.get('content-type'), 'application/json');
  assert.equal(await forwarded.text(), '{"fire_in":60,"title":"Deploy finished"}');
});

test('DELETE /v1/alarms/{id} のパスもそのまま転送する', () => {
  assert.equal(
    buildOriginRequest(new Request('https://api.signalarm.app/v1/alarms/3b0e0c6e', { method: 'DELETE' }), 'https://origin.example').url,
    'https://origin.example/v1/alarms/3b0e0c6e',
  );
});
