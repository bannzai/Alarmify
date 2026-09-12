import { cp, mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { resolve, dirname, relative, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { marked } from 'marked';

const root = fileURLToPath(new URL('../../', import.meta.url));
const source = resolve(root, 'docs');
// 一時成果物だけを配信し、Markdown 原本を公開物へ混ぜないため。
const output = resolve(root, 'tmp/site');

/** 文書の見出しを HTML の属性と title に安全に埋め込む。 */
function escapeHTML(text) {
  return text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

/** 信頼済みのリポジトリ内 Markdown を、既存の拡張子なしリンクを保つ HTML にする。 */
async function buildDirectory(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) {
      await buildDirectory(path);
    } else if (entry.isFile() && ['.md', '.html', '.png', '.css'].includes(extname(path))) {
      const destination = resolve(output, relative(source, path).replace(/\.md$/, '.html'));
      await mkdir(dirname(destination), { recursive: true });
      if (extname(path) !== '.md') {
        await cp(path, destination);
        continue;
      }
      const markdown = await readFile(path, 'utf8');
      const title = markdown.match(/^# (.+)$/m)?.[1];
      if (!title) throw new Error(`見出しがありません: ${path}`);
      const prefix = '../'.repeat(relative(source, directory).split('/').filter(Boolean).length) || './';
      await writeFile(destination, `<!doctype html>
<html lang="${entry.name.endsWith('-ja.md') ? 'ja' : 'en'}">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHTML(title)} | Signalarm</title><link rel="icon" href="${prefix}icon.png">
<link rel="stylesheet" href="${prefix}document.css"></head>
<body><header><a href="${prefix}">Signalarm</a><nav><a href="${prefix}api">API</a><a href="${prefix}recipes/">連携レシピ</a></nav></header>
<main>${marked.parse(markdown)}</main><footer><a href="${prefix}#support">サポート・お問い合わせ</a></footer></body></html>\n`);
    }
  }
}

await mkdir(output, { recursive: true });
// 削除された原本の古い HTML を再配信しないよう、成果物を別の一時ディレクトリへ退避する。
if ((await readdir(output)).length) {
  const { rename } = await import('node:fs/promises');
  await rename(output, `${output}-previous-${Date.now()}`);
  await mkdir(output, { recursive: true });
}
await buildDirectory(source);
await writeFile(resolve(output, '404.html'), '<!doctype html><html lang="ja"><meta charset="utf-8"><title>ページが見つかりません | Signalarm</title><h1>ページが見つかりません</h1><a href="/">Signalarm に戻る</a></html>\n');
console.log(`静的サイトを生成しました: ${output}`);
