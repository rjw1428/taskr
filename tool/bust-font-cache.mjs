// Appends ?v=<content hash> to every font in build/web/assets/FontManifest.json.
//
// From a1a64c7 to a76a173 hosting served fonts with
// `max-age=31536000, immutable`, so a browser that loaded the app then keeps
// that build's icon-tree-shaken fonts for a year without ever revalidating —
// new icons (the gear, the thumbtack) render blank in that browser while
// incognito is fine. No header change reaches those entries; only a new URL
// does. Flutter fetches each font at `assets/<asset>` verbatim, the query
// survives, and hosting ignores it when serving. Hashing the content keeps
// the URL stable until the font actually changes.
//
// deploy-web.sh runs this after the build.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const assets = join(process.argv[2] ?? 'build/web', 'assets');
const manifestPath = join(assets, 'FontManifest.json');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));

for (const family of manifest) {
  for (const font of family.fonts) {
    const path = font.asset.split('?')[0];
    const hash = createHash('sha256').update(readFileSync(join(assets, path))).digest('hex').slice(0, 12);
    font.asset = `${path}?v=${hash}`;
  }
}

writeFileSync(manifestPath, JSON.stringify(manifest));
