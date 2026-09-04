#!/usr/bin/env node
/**
 * S280 — roku client route gate (the BrightScript mirror of mobile's
 * `src/api/test/routeManifest.gate.test.ts`).
 *
 * WHAT IT PINS: every URL phlix-roku-client can put on the wire is tuple-exact
 * against the VENDORED phlix-server route manifest
 * (`tests/fixtures/server-route-manifest.json`, a byte-for-byte copy of
 * `@phlix/contracts` `dist/server-route-manifest.json`). The expected set is
 * derived from the SERVER side only — a check derived from its subject
 * self-adjusts and passes every defect it exists to catch, which is exactly
 * why S264/S276/S279 shipped in three repos before anyone pinned anything.
 *
 * MATCHING IS EXACT, NEVER SUBSTRING: segment-wise against the server
 * templates, where `{param}` spans exactly ONE path segment — so
 * `/api/v1/media/{id}` can never absorb `/api/v1/media/{id}/markers`
 * (sibling-wildcard absorption).
 *
 * NON-VACUITY: the exact scanned-site count, the per-file counts, and the
 * provenance sha are pinned in CHECK COUNTS below. Add a request site without
 * it being served and this exits 1 naming it; change coverage and the counts
 * move; run `--self-test` to see the planted-unserved URL go RED on demand.
 *
 * RUN:  node tests/scripts/verify-route-manifest.mjs [--self-test] [--quiet]
 * CI:   `make validate-routes` (wired into .github/workflows/test.yml).
 *
 * @copyright 2026 Joe Huss <detain@interserver.net>
 * @license MIT
 */

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const MANIFEST_FILE = path.join(REPO, 'tests', 'fixtures', 'server-route-manifest.json');
const QUIET = process.argv.includes('--quiet');
const SELF_TEST = process.argv.includes('--self-test');

const PROVENANCE_SHA = '4b620f59152ccc04e0ec365f3a91c2d8fab885c0';
const TOTAL_TUPLES = 400;

/**
 * Sites the scanner DELIBERATELY does not check against the server manifest,
 * each with an enforced reason. Every entry is triple-guarded:
 *  1. the gate does not fail on it (it targets a different registry/transport),
 *  2. the path is asserted ABSENT from the server manifest — if the server
 *     ever registers it, this reds and the partition must be re-drawn,
 *  3. the count and file are pinned so a silent new exception cannot appear.
 */
const PARTITIONED = [
  {
    file: 'source/lib/ApiClient.brs',
    method: 'GET',
    path: '/api/v1/me/servers',
    reason:
      'getMyServers() targets the HUB origin (its own docblock: "Exists ONLY on a hub; a DIRECT server has no such route") — hub registry, not server ROUTE_MANIFEST',
  },
];

/**
 * Raw-transport sites checked OUTSIDE the /api/v1 concat rule (the rule is
 * baked into ApiClient.sendRaw, so these bypass it and match the manifest by
 * their bare path).
 */
const RAW_SITES = [
  {
    file: 'source/lib/ApiClient.brs',
    method: 'GET',
    path: '/health',
    via: 'probeHealth() builds m.baseUrl + "/health" directly (public unauthenticated probe, registered at the server root)',
  },
];

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  process.exitCode = 1;
}

// ── manifest load + provenance ───────────────────────────────────────────────
if (!existsSync(MANIFEST_FILE)) {
  fail(`vendored manifest missing at ${path.relative(REPO, MANIFEST_FILE)}`);
  process.exit(1);
}
const manifest = JSON.parse(readFileSync(MANIFEST_FILE, 'utf8'));
if (manifest.provenance?.serverSha !== PROVENANCE_SHA) {
  fail(
    `vendored manifest provenance sha is ${manifest.provenance?.serverSha}, expected ${PROVENANCE_SHA} ` +
      `(re-vendor byte-for-byte from @phlix/contracts dist/server-route-manifest.json)`,
  );
}
if (manifest.routes?.length !== TOTAL_TUPLES || manifest.provenance?.total !== TOTAL_TUPLES) {
  fail(`vendored manifest has ${manifest.routes?.length} routes, expected ${TOTAL_TUPLES}`);
  process.exit(1);
}

const ROUTES = manifest.routes;

function isParamSegment(segment) {
  return /^\{[^{}]*\}$/.test(segment);
}

/**
 * Segment-EXACT serve test: equal segment counts; a server `{param}` covers a
 * client segment of any kind (literal or `{param}`); two literals must be
 * equal; a client `{param}` is NEVER matched by a server literal (the
 * interpolated value varies at run time). No substring, no prefix, ever.
 */
function served(method, clientPath) {
  const clientSegments = clientPath.split('/');
  return ROUTES.some(
    ([verb, template]) => {
      if (verb !== method) return false;
      const serverSegments = template.split('/');
      if (serverSegments.length !== clientSegments.length) return false;
      return serverSegments.every(
        (seg, i) => isParamSegment(seg) || (!isParamSegment(clientSegments[i]) && seg === clientSegments[i]),
      );
    },
  );
}

// ── source scan ──────────────────────────────────────────────────────────────

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    const full = path.join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (entry.endsWith('.brs')) out.push(full);
  }
  return out;
}

/**
 * Build a `[VERB, /api/v1/...]` site from one `m.request("VERB", expr` /
 * `m.sendRaw("VERB", expr` call. The path expr is a BrightScript concat
 * expression: string literals joined with `+`; every non-literal part
 * (variable, `UrlEncode(x)`, `m.sessionId`, `str(n).trim()`) is ONE path
 * segment. Trailing junk from the call syntax is cut at the body object.
 */
/** Drop the trailing `, body)` of a request call so only the path expr remains. */
function cutToPathExpr(expr) {
  let trimmed = expr.trim();
  const bodyCut = trimmed.search(/,\s*(invalid|\{|[a-zA-Z_])/);
  if (bodyCut !== -1) trimmed = trimmed.slice(0, bodyCut);
  return trimmed.trim();
}

function siteFromCall(verb, expr) {
  let trimmed = cutToPathExpr(expr);
  let tmpl = '';
  for (const rawPart of trimmed.split('+')) {
    const part = rawPart.trim();
    if (part === '') continue;
    const literal = part.match(/^"([^"]*)"$/);
    if (literal) {
      tmpl += literal[1];
    } else {
      const seg = /\?|&/.test(part) || /^query/i.test(part) ? '' : '/{P}';
      if (seg && !tmpl.endsWith('/')) tmpl += seg;
      else if (seg) tmpl += seg.slice(1);
    }
  }
  tmpl = tmpl.split('?')[0];
  if (tmpl.length > 1) tmpl = tmpl.replace(/\/+$/, '');
  // A path may not START interpolated: `/api/v1/{P}` would match a whole
  // family of real templates and read as served without ever being registered
  // as such — fail loudly instead of green-by-accident.
  if (!tmpl.startsWith('/') || /^\/\{P\}/.test(tmpl)) return null;
  return { method: verb, path: `/api/v1${tmpl}` };
}

function scan() {
  const sites = [];
  const files = walk(path.join(REPO, 'source')).concat(walk(path.join(REPO, 'components')));
  const callRe = /\.request\(\s*"(GET|POST|PUT|PATCH|DELETE)"\s*,\s*(.+)$|\.sendRaw\(\s*"(GET|POST|PUT|PATCH|DELETE)"\s*,\s*(.+)$/;
  for (const file of files) {
    const rel = path.relative(REPO, file).split(path.sep).join('/');
    const lines = readFileSync(file, 'utf8').split('\n');
    lines.forEach((raw, i) => {
      const line = raw.trim();
      if (line.startsWith("'")) return; // BrightScript comment line
      const m = line.match(callRe);
      if (!m) return;
      const verb = m[1] ?? m[3];
      let expr = cutToPathExpr((m[2] ?? m[4]).trim());
      // Variable-path sites (facets / letter-index / admin users / ApiTask
      // cache paths): resolve the assignment chain backwards within the
      // enclosing function.
      if (/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(expr)) {
        expr = resolvePathChain(lines, i, expr);
        // resolvePathChain returns the raw expr string; re-cut for safety.
        if (typeof expr === 'string') expr = cutToPathExpr(expr);
        if (expr === null) {
          fail(`${rel}:${i + 1} — CHECK ROUTES: m.request path variable with no resolvable assignment`);
          return;
        }
      }
      const site = siteFromCall(verb, expr);
      if (!site) {
        fail(`${rel}:${i + 1} — CHECK ROUTES: could not parse path expression: ${expr}`);
        return;
      }
      site.file = rel;
      site.line = i + 1;
      sites.push(site);
    });
  }
  return sites;
}

function resolvePathChain(lines, callIndex, varName = 'path') {
  const assignments = [];
  const initRe = new RegExp(`^${varName}\\s*=\\s*(.+)$`);
  const appendRe = new RegExp(`^${varName}\\s*=\\s*${varName}\\s*\\+\\s*(.+)$`);
  for (let j = callIndex - 1; j >= 0 && j > callIndex - 60; j--) {
    const l = lines[j].trim();
    if (/^(function|sub|end function|end sub)\b/.test(l)) break;
    const appended = l.match(appendRe);
    const direct = appended ? null : l.match(initRe);
    if (appended) assignments.unshift({ kind: 'append', expr: appended[1] });
    else if (direct) {
      assignments.unshift({ kind: 'init', expr: direct[1] });
      break;
    }
  }
  if (assignments.length === 0) return null;
  const init = assignments[0];
  if (init.kind !== 'init') return null;
  let expr = init.expr;
  for (const step of assignments.slice(1)) {
    if (step.kind !== 'append') return null;
    expr += ' + ' + step.expr;
  }
  return expr;
}

// ── the gate ─────────────────────────────────────────────────────────────────

/**
 * Site counts at merge time. If this moves, either the client grew/shrank its
 * HTTP surface (legit: update WITH the serve check passing) or the scanner went
 * blind on a new call shape (NOT legit: find out why before touching numbers).
 */
const CHECK_COUNTS = {
  totalSites: 91,
  perFile: { 'source/lib/ApiClient.brs': 83, 'components/ApiTask.brs': 8 },
};

function selfTest() {
  const planted = { method: 'GET', path: '/api/v1/s280-planted-probe/{P}' };
  if (served(planted.method, planted.path)) {
    console.error('SELFTEST FAIL: planted unserved URL was reported SERVED — the matcher self-adjusts.');
    process.exit(1);
  }
  const absorbed = { method: 'GET', path: '/api/v1/media/{P}/markers/m-1/extra' };
  if (served(absorbed.method, absorbed.path)) {
    console.error('SELFTEST FAIL: a deeper path was absorbed by a shorter template — substring leak.');
    process.exit(1);
  }
  const real = { method: 'GET', path: '/api/v1/syncplay/groups' };
  if (!served(real.method, real.path)) {
    console.error('SELFTEST FAIL: a genuinely served route did not match — the gate is blind.');
    process.exit(1);
  }
  console.log('self-test: planted-unserved RED + sibling-absence RED + served GREEN — gate is falsifiable.');
  return;
}

if (SELF_TEST) {
  selfTest();
  process.exit(0);
}

const sites = scan();

const unserved = sites.filter(
  (s) => !PARTITIONED.some((p) => p.method === s.method && p.path === s.path) && !served(s.method, s.path),
);

// Partition integrity: every exception must STILL be unserved on the server.
for (const p of PARTITIONED) {
  if (served(p.method, p.path)) {
    fail(
      `PARTITION STALE: ${p.method} ${p.path} is now REGISTERED server-side (${p.reason}) — ` +
        'pull it out of PARTITIONED and let the gate check it properly',
    );
  }
}
// Raw sites: the bare path must be a real server route (they bypass /api/v1).
for (const r of RAW_SITES) {
  if (!served(r.method, r.path)) {
    fail(`RAW SITE UNSERVED: ${r.method} ${r.path} — ${r.via}`);
  }
}

const perFile = {};
for (const s of sites) perFile[s.file] = (perFile[s.file] ?? 0) + 1;
if (sites.length !== CHECK_COUNTS.totalSites) {
  fail(
    `COVERAGE MOVED: scanned ${sites.length} request sites, pinned ${CHECK_COUNTS.totalSites} — ` +
      'update only with the reason in the commit message (S280 AC: partial coverage must not read as full)',
  );
}
if (JSON.stringify(perFile) !== JSON.stringify(CHECK_COUNTS.perFile)) {
  fail(`COVERAGE MOVED per file: got ${JSON.stringify(perFile)}, pinned ${JSON.stringify(CHECK_COUNTS.perFile)}`);
}

if (!QUIET) {
  const tuples = new Set(sites.map((s) => `${s.method} ${s.path}`));
  console.log(
    `[S280 route gate] roku: ${sites.length} request sites / ${tuples.size} distinct [method, pathTemplate] tuples ` +
      `across ${Object.keys(perFile).length} modules — tuple-exact against the vendored ${TOTAL_TUPLES}-route manifest @ ${PROVENANCE_SHA}`,
  );
  for (const [file, count] of Object.entries(perFile).sort()) console.log(`  ${file}: ${count}`);
  console.log(`  partitioned: ${PARTITIONED.length} (hub-addressed) · raw-transport: ${RAW_SITES.length} (GET /health)`);
}

for (const u of unserved) {
  console.error(`  ${u.file}:${u.line} — CHECK ROUTES: ${u.method} ${u.path} is NOT in the vendored server manifest (planted or drifted URL)`);
}
if (unserved.length > 0) {
  fail(`CHECK ROUTES: ${unserved.length} unserved URL(s) — the client calls what the server never registered (S280 defect class)`);
  process.exit(1);
}
if (!QUIET) console.log('  ✓ all issued routes tuple-exact served');
