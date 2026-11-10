/**
 * audit-gate — npm-audit wrapper with an explicit, justified advisory allow-list.
 *
 * WHY THIS EXISTS (RT-088, review roku__devops, wave w14): this repo carries a
 * real npm toolchain surface — package.json, package-lock.json and three CI
 * jobs that run `npm ci` — and had NO audit leg anywhere (grep across
 * .github/workflows measured zero hits at 131df6b289, the bare `npm audit`
 * command included). The estate pattern (phlix-website d096ab9a, ported from
 * phlix-windows-client 74fc744/bb9276d) is a DOCUMENTED ALLOW-LIST: the audit
 * passes only while the reported advisory-id set is a subset of
 * ALLOWED_ADVISORIES below, and turns red the moment ANY other advisory
 * appears — at any severity, strictly stronger than the bare
 * `npm audit --audit-level=moderate` step it would replace, which silently
 * passed sub-threshold findings.
 *
 * THE MEASURED TRUTH ABOUT THE SEVEN ALLOWED IDS (all numbers from this lane,
 * 2026-11-10, NPM_CONFIG_USERCONFIG=/dev/null npm 12): every flagged package
 * hangs under brs@0.45.0 ALONE —
 *
 *   brs@0.45.0
 *   ├── decompress@4.2.1              (4 advisories, 2 critical)
 *   ├─┬ nanomatch@1.2.13
 *   │ └─┬ snapdragon@0.8.2
 *   │   └─┬ source-map-resolve@0.5.3
 *   │     └── decode-uri-component@0.2.2   (2 advisories, 1 high)
 *   └── uuid@8.3.2                    (1 advisory)
 *
 * and brs@0.45.0 is the FINAL release the upstream ever published (registry
 * version list verified 2026-11-10 — the project was superseded by the
 * brighterscript package that already sits in devDependencies). There is no
 * in-range clear for any of the seven: `npm update decode-uri-component
 * source-map-resolve --package-lock-only` produced a BYTE-IDENTICAL lockfile
 * (measured this lane — the diff of the sorted package map is empty), because
 * 0.2.2 is the newest 0.2.x ever published and 0.5.3 the newest 0.5.x. npm's
 * own remediation for the rest is a semver-major DOWNGRADE of brs to 0.39.0 —
 * rejected: 0.39 predates interpreter behaviour this battery depends on, and
 * replacing the test engine to appease the audit is backwards. A cross-major
 * override (uuid ^8→11, decode-uri-component ^0.2→0.5, decompress→none-exists)
 * is rejected under the estate S430 discipline: overrides only when a parent
 * range blocks resolution, never majors forced across an unaudited API
 * boundary — and there is no patched decompress release to override TO
 * (4.2.1 is the newest version ever published AND inside every flagged range).
 *
 * REACH: all seven chains sit in dev tooling only. The Roku app itself is
 * BrightScript source; `make package` zips .brs/.xml/.png through the distro
 * zip tool — no artifact on the device ever contains bytes from this tree.
 * None of these parsers handles untrusted input at runtime: decompress only
 * runs if brs extracts an archive (no workflow does), the decoder only parses
 * percent-escapes inside source-map comments of this repo's own toolchain
 * output, and uuid's flagged surface is buffer-bounds handling for callers
 * that pass an output buffer.
 *
 * ANTI-NEUTERING LAW:
 * A silent gate is worse than no gate. The script distinguishes "audit clean"
 * from "audit broken": unparseable JSON, an unrecognized report shape, a
 * failed spawn, or a nonzero npm exit that reports ZERO advisories all exit
 * with EXIT_STRUCTURE_ERROR (2) — never 0. Unknown advisories exit
 * EXIT_VIOLATION (1). `--self-test` executes the whole decision table without
 * spawning npm (the same fixtures the mirror test file drives).
 *
 * Exit codes: 0 pass (clean or allowed-only) · 1 allow-list violation ·
 * 2 audit itself failed (structural — the verdict is unusable, not "clean").
 */

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const EXIT_OK = 0;
export const EXIT_VIOLATION = 1;
export const EXIT_STRUCTURE_ERROR = 2;

// Exact GHSA ids the gate tolerates, each with the justification CI prints on
// every run. Subset semantics: ANY advisory id missing here reddens the gate.
export const ALLOWED_ADVISORIES = new Map([
  [
    'GHSA-mp2f-45pm-3cg9',
    {
      package: 'decompress',
      justification:
        'dev-chain-only (brs@0.45.0 -> decompress@4.2.1; brs is the device-free ' +
        'headless BrightScript interpreter that runs the CI unit battery, nothing ' +
        'of this chain reaches the device — the sideload zip is BrightScript source ' +
        'packed by make package/distro zip). The flaw is archive extraction creating ' +
        'files/links outside the target directory; decompress only executes when brs ' +
        'is asked to unpack an archive, which no build, test or release path in this ' +
        'repo ever does. NO patched release exists anywhere: the advisory range is ' +
        '<=4.2.1 and 4.2.1 is the newest version ever published (npm view decompress ' +
        'version, verified 2026-11-10), while brs declares ^4.2.1 — every installable ' +
        'version is the flagged one. npm\'s suggested remediation is a semver-major ' +
        'downgrade of brs to 0.39.0 (rejected — regression theater: 0.39 predates ' +
        'interpreter behaviour this battery depends on, and brs is superseded upstream, ' +
        '0.45.0 being its FINAL release). UPSTREAM WATCH (the removal plan): a ' +
        'decompress 4.2.2+ backport would clear `npm update decompress` inside the ' +
        'existing ^4.2.1 declaration — then REMOVE this entry, its justification, and ' +
        'the mp2f fixture in tests/audit-gate.test.mjs. Re-verify advisory status by ' +
        '2027-02-10: https://github.com/advisories/GHSA-mp2f-45pm-3cg9',
    },
  ],
  [
    'GHSA-hrh2-vp3x-79xf',
    {
      package: 'decompress',
      justification:
        'dev-chain-only, same brs@0.45.0 -> decompress@4.2.1 custody as GHSA-mp2f ' +
        'above. This one is the @xhmikosr/decompress-family path-traversal-via-' +
        'symlink-chain advisory npm mirrors onto the decompress install; the flagged ' +
        'range is again <=4.2.1 with 4.2.1 the newest-ever version, so no in-range ' +
        'update exists and the archive-extraction code path is never exercised by any ' +
        'workflow here (nothing feeds brs an archive to unpack). Cross-major override ' +
        'impossible: there is no patched target to override TO. Removal plan and ' +
        're-verify date identical to the mp2f entry. Re-verify by 2027-02-10: ' +
        'https://github.com/advisories/GHSA-hrh2-vp3x-79xf',
    },
  ],
  [
    'GHSA-h39j-r5qq-r9mm',
    {
      package: 'decompress',
      justification:
        'dev-chain-only, same custody. Zip Slip (arbitrary file write via archive ' +
        'entry names) inside decompress@4.2.1 — <=4.2.1 flagged, newest-ever is ' +
        'flagged, extraction path unreachable from any build/test/release leg of ' +
        'this repo (brs loads .brs sources straight from the checked-out tree). ' +
        'Removal plan and re-verify identical to the mp2f entry. Re-verify by ' +
        '2027-02-10: https://github.com/advisories/GHSA-h39j-r5qq-r9mm',
    },
  ],
  [
    'GHSA-jwp9-9v96-94mx',
    {
      package: 'decompress',
      justification:
        'dev-chain-only, same custody. Arbitrary hardlink creation during archive ' +
        'extraction, <=4.2.1, same newest-ever-flagged arithmetic; the extraction ' +
        'entry point is never reached from this repo\'s workflows. Removal plan and ' +
        're-verify identical to the mp2f entry. Re-verify by 2027-02-10: ' +
        'https://github.com/advisories/GHSA-jwp9-9v96-94mx',
    },
  ],
  [
    'GHSA-vcc3-ghjq-m6fr',
    {
      package: 'decode-uri-component',
      justification:
        'dev-chain-only (brs@0.45.0 -> nanomatch@1.2.13 -> snapdragon@0.8.2 -> ' +
        'source-map-resolve@0.5.3 -> decode-uri-component@0.2.2; the decoder only ' +
        'parses percent-escapes inside source-map comments produced by THIS repo\'s ' +
        'own toolchain, never hostile input, and nothing ships). The advisory flags ' +
        '<=0.4.2; 0.2.2 is the newest 0.2.x ever published (registry version list ' +
        'verified 2026-11-10 — the 0.2 line ends there), and source-map-resolve ' +
        'declares ^0.2.0, so every version reachable through the parent is flagged. ' +
        '`npm update decode-uri-component --package-lock-only` moved ZERO bytes ' +
        '(measured this lane). A cross-major override to 0.5.1 was rejected: S430 ' +
        'discipline, and brs is superseded upstream so its chain cannot be re-audited. ' +
        'UPSTREAM WATCH: a patched 0.2.x backport (none listed as of 2026-11-10) would ' +
        'clear inside the existing ^0.2.0 declaration — REMOVE this entry, its ' +
        'justification, and the vcc3 fixture in tests/audit-gate.test.mjs. Re-verify ' +
        'by 2027-02-10: https://github.com/advisories/GHSA-vcc3-ghjq-m6fr',
    },
  ],
  [
    'GHSA-qr28-fpjm-wq7f',
    {
      package: 'decode-uri-component',
      justification:
        'dev-chain-only, same custody as vcc3. The quadratic-replacement DoS flags ' +
        '<=0.5.0 — so even the published 0.5.0 stays flagged and the decoder under ' +
        '^0.2.0 cannot reach the 0.5.1 patch (same zero-byte `npm update ' +
        '--package-lock-only` measurement, same S430 override refusal). Removal ' +
        'plan mirrors vcc3: a 0.2.x backport or an upstream re-pin of ' +
        'source-map-resolve. Re-verify by 2027-02-10: ' +
        'https://github.com/advisories/GHSA-qr28-fpjm-wq7f',
    },
  ],
  [
    'GHSA-w5hq-g745-h8pq',
    {
      package: 'uuid',
      justification:
        'dev-chain-only (brs@0.45.0 -> uuid@8.3.2; uuid backs identifier generation ' +
        'inside the headless test interpreter only — the Roku binary contains no ' +
        'JavaScript). The flagged surface is a missing output-buffer bounds check in ' +
        'v3/v5/v6 when the CALLER supplies a buf argument; first_patched_version is ' +
        '11.1.1, two semver-majors above the ^8.3.0 declaration (8.3.2 is the newest ' +
        '8.x ever published, verified 2026-11-10), so no in-range update exists and a ' +
        'forced override onto an abandoned upstream (brs final release 0.45.0) is ' +
        'rejected under S430. UPSTREAM WATCH: the moment brs is replaced or forked ' +
        'with a modern uuid (or a never-listed 8.3.3 backport ships), REMOVE this ' +
        'entry, its justification, and the w5hq fixture in tests/audit-gate.test.mjs. ' +
        'Re-verify by 2027-02-10: https://github.com/advisories/GHSA-w5hq-g745-h8pq',
    },
  ],
]);

// The severity floor is deliberately irrelevant to the verdict — the JSON
// report below carries every advisory regardless of level and decide() reddens
// on ANY un-allowlisted id — but the flag keeps npm's own exit code aligned
// with the bare step this replaces.
const AUDIT_ARGS = ['audit', '--json', '--audit-level=moderate'];
const MAX_BUFFER_BYTES = 64 * 1024 * 1024;

export class AuditGateError extends Error {}

/** Run the real `npm audit --json` the way the estate gates run it. */
export function runAudit() {
  const result = spawnSync('npm', AUDIT_ARGS, {
    encoding: 'utf8',
    maxBuffer: MAX_BUFFER_BYTES,
    shell: process.platform === 'win32',
  });
  return {
    exitCode: result.status ?? -1,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    spawnError: result.error ?? null,
  };
}

// GHSA ids are case-insensitive by spec. Extraction preserves the reported
// case for display; allow-list matching is case-insensitive (decide() below
// lowercases both sides).
function ghsaFromUrl(url) {
  const match = typeof url === 'string' ? /\/(GHSA-[0-9a-z]+(-[0-9a-z]+){2,3})$/i.exec(url) : null;
  return match ? match[1] : null;
}

function advisoryIdOf(via) {
  const fromUrl = ghsaFromUrl(via.url);
  if (fromUrl) return fromUrl;
  if (typeof via.github_advisory_id === 'string' && /^GHSA-/i.test(via.github_advisory_id)) {
    return via.github_advisory_id;
  }
  throw new AuditGateError(
    `advisory entry carries no resolvable GHSA id (url=${JSON.stringify(via.url ?? null)}); ` +
      `refusing to certify an unnamed advisory — ${JSON.stringify(via).slice(0, 200)}`,
  );
}

/** Parse npm audit JSON (v3 `vulnerabilities`, legacy v2 `advisories`) into a Set of GHSA ids. */
export function collectAdvisoryIds(stdout) {
  let report;
  try {
    report = JSON.parse(stdout);
  } catch {
    throw new AuditGateError(
      `npm audit --json produced unparseable output: ${JSON.stringify(String(stdout).slice(0, 300))}`,
    );
  }
  if (report === null || typeof report !== 'object') {
    throw new AuditGateError(
      `npm audit --json produced a non-object report: ${JSON.stringify(report).slice(0, 200)}`,
    );
  }

  const ids = new Set();
  if (report.vulnerabilities && typeof report.vulnerabilities === 'object') {
    for (const node of Object.values(report.vulnerabilities)) {
      for (const via of node?.via ?? []) {
        // v3 (and npm 12's auditReportVersion 2 variant that still carries a
        // `vulnerabilities` map): `via` strings name affected dependents;
        // objects ARE the advisories.
        if (typeof via === 'object' && via !== null) ids.add(advisoryIdOf(via));
      }
    }
    return ids;
  }
  if (report.advisories && typeof report.advisories === 'object') {
    for (const advisory of Object.values(report.advisories)) {
      if (advisory && typeof advisory === 'object') ids.add(advisoryIdOf(advisory));
    }
    return ids;
  }
  throw new AuditGateError(
    'unrecognized npm audit JSON shape (no `vulnerabilities`/`advisories` key) — ' +
      `refusing to guess at an audit we cannot read: keys=[${Object.keys(report).join(',')}]`,
  );
}

/**
 * Pure decision: audit-run facts in, gate verdict out.
 * Returns { code, clean, allowed[], unknown[], problems[] }.
 */
export function decide({ exitCode, stdout, spawnError = null }) {
  if (spawnError) {
    return {
      code: EXIT_STRUCTURE_ERROR,
      clean: false,
      allowed: [],
      unknown: [],
      problems: [`npm audit could not be executed: ${spawnError.message}`],
    };
  }

  let ids;
  try {
    ids = collectAdvisoryIds(stdout);
  } catch (error) {
    return {
      code: EXIT_STRUCTURE_ERROR,
      clean: false,
      allowed: [],
      unknown: [],
      problems: [
        error instanceof AuditGateError ? error.message : `audit parse failed: ${error.message}`,
      ],
    };
  }

  const canonicalKeyByLowerId = new Map(
    [...ALLOWED_ADVISORIES.keys()].map((key) => [key.toLowerCase(), key]),
  );
  const allowed = [...ids]
    .filter((id) => canonicalKeyByLowerId.has(id.toLowerCase()))
    .map((id) => canonicalKeyByLowerId.get(id.toLowerCase()))
    .sort();
  const unknown = [...ids].filter((id) => !canonicalKeyByLowerId.has(id.toLowerCase())).sort();
  const problems = [];
  if (unknown.length > 0) {
    problems.push(
      `${unknown.length} advisory id(s) are NOT on the allow-list: ${unknown.join(', ')} — ` +
        'fix the dependency (preferred) or justify a deliberate, reviewed ALLOWED_ADVISORIES entry.',
    );
  }
  // Anti-neutering: nonzero exit with nothing allow-listable means the audit
  // command itself failed — an unread verdict is never a green verdict.
  if (exitCode !== 0 && ids.size === 0) {
    problems.push(
      `npm audit exited ${exitCode} while reporting ZERO advisories — the audit command failed; ` +
        'refusing to treat a broken audit as a clean one.',
    );
  }
  if (problems.length > 0) {
    return {
      code: unknown.length > 0 ? EXIT_VIOLATION : EXIT_STRUCTURE_ERROR,
      clean: false,
      allowed,
      unknown,
      problems,
    };
  }
  return { code: EXIT_OK, clean: exitCode === 0 && ids.size === 0, allowed, unknown, problems };
}

/** npm-audit-JSON v3 report fixture carrying exactly the given id set. */
function reportWith(ids) {
  const vulnerabilities = {};
  for (const [i, id] of ids.entries()) {
    vulnerabilities[`pkg${i}`] = {
      name: `pkg${i}`,
      severity: 'moderate',
      via: [{ source: 1, url: `https://github.com/advisories/${id}`, severity: 'moderate', range: '<=9' }],
      effects: [],
      range: '<=9',
    };
  }
  return JSON.stringify({ auditReportVersion: 2, vulnerabilities });
}

/** Decision-table fixtures run by --self-test and by the mirror test file. */
export const SELF_TEST_SCENARIOS = [
  {
    name: 'clean-audit-exits-0',
    input: { exitCode: 0, stdout: reportWith([]) },
    expect: { code: EXIT_OK, allowedCount: 0, unknownCount: 0, clean: true },
  },
  {
    name: 'allowed-only-exits-0',
    input: { exitCode: 1, stdout: reportWith([...ALLOWED_ADVISORIES.keys()]) },
    expect: { code: EXIT_OK, allowedCount: 7, unknownCount: 0, clean: false },
  },
  {
    name: 'unknown-id-exits-1',
    input: { exitCode: 1, stdout: reportWith([...ALLOWED_ADVISORIES.keys(), 'GHSA-0000-0000-0000']) },
    expect: { code: EXIT_VIOLATION, allowedCount: 7, unknownCount: 1, clean: false },
  },
  {
    name: 'bare-unknown-exits-1',
    input: { exitCode: 1, stdout: reportWith(['GHSA-zzzz-zzzz-zzzz']) },
    expect: { code: EXIT_VIOLATION, allowedCount: 0, unknownCount: 1, clean: false },
  },
  {
    name: 'unparseable-exits-2',
    input: { exitCode: 0, stdout: 'not json at all' },
    expect: { code: EXIT_STRUCTURE_ERROR, allowedCount: 0, unknownCount: 0, clean: false },
  },
  {
    name: 'unrecognized-shape-exits-2',
    input: { exitCode: 1, stdout: JSON.stringify({ somethingElse: true }) },
    expect: { code: EXIT_STRUCTURE_ERROR, allowedCount: 0, unknownCount: 0, clean: false },
  },
  {
    name: 'broken-audit-zero-advisories-exits-2',
    input: { exitCode: 1, stdout: reportWith([]) },
    expect: { code: EXIT_STRUCTURE_ERROR, allowedCount: 0, unknownCount: 0, clean: false },
  },
  {
    name: 'spawn-failure-exits-2',
    input: { exitCode: -1, stdout: '', spawnError: { message: 'ENOENT npm' } },
    expect: { code: EXIT_STRUCTURE_ERROR, allowedCount: 0, unknownCount: 0, clean: false },
  },
  {
    name: 'case-insensitive-allow-matching',
    input: { exitCode: 1, stdout: reportWith([...ALLOWED_ADVISORIES.keys()].map((id) => id.toLowerCase())) },
    expect: { code: EXIT_OK, allowedCount: 7, unknownCount: 0, clean: false },
  },
  {
    name: 'legacy-v2-advisories-shape-parses',
    input: {
      exitCode: 1,
      stdout: JSON.stringify({ advisories: { a: { url: 'https://github.com/advisories/GHSA-zzzz-zzzz-zzzz' } } }),
    },
    expect: { code: EXIT_VIOLATION, allowedCount: 0, unknownCount: 1, clean: false },
  },
];

export function runSelfTest() {
  let failures = 0;
  for (const scenario of SELF_TEST_SCENARIOS) {
    const verdict = decide(scenario.input);
    const ok =
      verdict.code === scenario.expect.code &&
      verdict.allowed.length === scenario.expect.allowedCount &&
      verdict.unknown.length === scenario.expect.unknownCount &&
      verdict.clean === scenario.expect.clean;
    if (ok) {
      console.log(`audit-gate self-test: PASS ${scenario.name} (exit ${verdict.code})`);
    } else {
      failures += 1;
      console.error(
        `audit-gate self-test: FAIL ${scenario.name} — got code=${verdict.code} ` +
          `allowed=${verdict.allowed.length} unknown=${verdict.unknown.length} clean=${verdict.clean}, ` +
          `expected code=${scenario.expect.code} allowed=${scenario.expect.allowedCount} ` +
          `unknown=${scenario.expect.unknownCount} clean=${scenario.expect.clean}`,
      );
    }
  }
  if (failures > 0) {
    console.error(`audit-gate self-test: ${failures} scenario(s) failed — the gate itself is broken`);
    return EXIT_STRUCTURE_ERROR;
  }
  console.log(
    `audit-gate self-test: PASS — ${SELF_TEST_SCENARIOS.length} scenarios, every verdict exact ` +
      `(allow-list carries ${ALLOWED_ADVISORIES.size} ids)`,
  );
  return EXIT_OK;
}

export function main(argv) {
  if (argv.includes('--self-test')) return runSelfTest();
  const audit = runAudit();
  const verdict = decide(audit);

  for (const id of verdict.allowed) {
    const entry = ALLOWED_ADVISORIES.get(id);
    console.log(`audit-gate: ALLOWED ${id} (${entry.package}) — ${entry.justification}`);
  }
  for (const problem of verdict.problems) {
    console.error(`audit-gate: ${problem}`);
  }
  if (verdict.code === EXIT_OK) {
    console.log(
      verdict.clean
        ? 'audit-gate: PASS — npm audit clean (0 advisories, exit 0)'
        : `audit-gate: PASS — ${verdict.allowed.length} advisory id(s) reported, every one allow-listed (npm audit exit ${audit.exitCode})`,
    );
  }
  return verdict.code;
}

// Main guard: importing this module (tests/audit-gate.test.mjs does) never
// execs an audit — only `node scripts/audit-gate.mjs` (or --self-test) does.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
