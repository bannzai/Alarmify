import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir, access } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const output = fileURLToPath(new URL('../../tmp/site/', import.meta.url));

/** 配信される HTML のリンクとアセットを、Pages の拡張子なし URL として検査する。 */
async function checkDirectory(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) await checkDirectory(path);
    else if (entry.name.endsWith('.html')) {
      const html = await readFile(path, 'utf8');
      assert.match(html, /<!doctype html>/i);
      for (const [, target] of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
        if (/^(https?:|mailto:)/.test(target)) continue;
        const url = new URL(target, `https://site.test/${path.slice(output.length)}`);
        let destination = resolve(output, `.${decodeURIComponent(url.pathname)}`);
        if (url.pathname.endsWith('/')) destination += '/index.html';
        else if (!/\.[a-z]+$/i.test(url.pathname)) destination += '.html';
        await assert.doesNotReject(access(destination), `${path}: ${target}`);
        if (url.hash) assert.ok((await readFile(destination, 'utf8')).includes(`id="${url.hash.slice(1)}"`), `${path}: ${target}`);
      }
    }
  }
}

test('全ページのリンク・アセット・ページ内アンカーが解決する', async () => {
  await checkDirectory(output);
});

test('API の表とコードが HTML になり、Markdown の原本が配信されない', async () => {
  assert.match(await readFile(resolve(output, 'api.html'), 'utf8'), /<table>/);
  assert.match(await readFile(resolve(output, 'api.html'), 'utf8'), /<pre><code/);
  await assert.rejects(access(resolve(output, 'api.md')));
  await access(resolve(output, '404.html'));
});
