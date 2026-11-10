/**
 * audit-gate mirror tests (RT-088 era, wave w14).
 *
 * These drive scripts/audit-gate.mjs's PURE decision layer — they never spawn
 * npm (importing the module has no side effects; only `node scripts/audit-gate.mjs`
 * execs an audit). The point is the ANTI-NEUTERING mirror: every exit-code
 * law the gate claims (0 clean/allowed-only · 1 un-listed advisory ·
 * 2 broken-structural) must hold exactly, and the allow-list must stay the
 * seven-id exact set with per-entry justifications — the same drift class the
 * phlix-website/phlix-windows gates pin for their families.
 *
 * Run: node --test tests/audit-gate.test.mjs
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ALLOWED_ADVISORIES,
  EXIT_OK,
  EXIT_VIOLATION,
  EXIT_STRUCTURE_ERROR,
  SELF_TEST_SCENARIOS,
  collectAdvisoryIds,
  decide,
  runSelfTest,
} from '../scripts/audit-gate.mjs';

const SEVEN_IDS = [
  'GHSA-h39j-r5qq-r9mm',
  'GHSA-hrh2-vp3x-79xf',
  'GHSA-jwp9-9v96-94mx',
  'GHSA-mp2f-45pm-3cg9',
  'GHSA-qr28-fpjm-wq7f',
  'GHSA-vcc3-ghjq-m6fr',
  'GHSA-w5hq-g745-h8pq',
];

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

test('the allow-list is exactly the seven justified brs-subtree ids', () => {
  assert.deepEqual([...ALLOWED_ADVISORIES.keys()].sort(), SEVEN_IDS);
});

test('every entry carries its package, a real justification and a re-verify date', () => {
  for (const [id, entry] of ALLOWED_ADVISORIES) {
    assert.match(id, /^GHSA-[0-9a-z]{4}-[0-9a-z]{4}-[0-9a-z]{4}$/, id);
    assert.ok(typeof entry.package === 'string' && entry.package.length > 0, id);
    assert.ok(entry.justification.length > 200, `${id} justification is thin`);
    assert.match(entry.justification, /[Rr]e-verify.*2027-02-10/, `${id} lost its re-verify date`);
    assert.match(entry.justification, /REMOVE this entry|[Rr]emoval plan/, `${id} lost its removal plan`);
  }
});

test('the flagged packages are exactly the three dev-chain names', () => {
  const pkgs = [...new Set([...ALLOWED_ADVISORIES.values()].map((e) => e.package))].sort();
  assert.deepEqual(pkgs, ['decode-uri-component', 'decompress', 'uuid']);
});

test('decision table: every scenario verdict is exact', () => {
  for (const scenario of SELF_TEST_SCENARIOS) {
    const verdict = decide(scenario.input);
    assert.equal(verdict.code, scenario.expect.code, scenario.name);
    assert.equal(verdict.allowed.length, scenario.expect.allowedCount, scenario.name);
    assert.equal(verdict.unknown.length, scenario.expect.unknownCount, scenario.name);
    assert.equal(verdict.clean, scenario.expect.clean, scenario.name);
  }
});

test('anti-neuter mirror: an un-listed advisory reddens the gate even beside a full allow-list', () => {
  const verdict = decide({
    exitCode: 1,
    stdout: reportWith([...SEVEN_IDS, 'GHSA-9999-9999-9999']),
  });
  assert.equal(verdict.code, EXIT_VIOLATION);
  assert.deepEqual(verdict.unknown, ['GHSA-9999-9999-9999']);
  assert.equal(verdict.allowed.length, 7);
});

test('anti-neuter mirror: a broken audit reporting zero advisories never exits green', () => {
  const verdict = decide({ exitCode: 1, stdout: reportWith([]) });
  assert.equal(verdict.code, EXIT_STRUCTURE_ERROR);
});

test('anti-neuter mirror: unparseable and unrecognized shapes exit structural', () => {
  assert.equal(decide({ exitCode: 0, stdout: '{' }).code, EXIT_STRUCTURE_ERROR);
  assert.equal(decide({ exitCode: 0, stdout: '[1,2,3]' }).code, EXIT_STRUCTURE_ERROR);
  assert.equal(decide({ exitCode: 0, stdout: JSON.stringify({ nope: 1 }) }).code, EXIT_STRUCTURE_ERROR);
});

test('collectAdvisoryIds reads v3 vulnerabilities and legacy v2 advisories shapes', () => {
  assert.deepEqual([...collectAdvisoryIds(reportWith([SEVEN_IDS[0]]))], [SEVEN_IDS[0]]);
  const legacy = JSON.stringify({
    advisories: { a: { url: 'https://github.com/advisories/GHSA-1111-1111-1111' }, b: { github_advisory_id: 'GHSA-2222-2222-2222' } },
  });
  assert.deepEqual([...collectAdvisoryIds(legacy)].sort(), ['GHSA-1111-1111-1111', 'GHSA-2222-2222-2222']);
  assert.throws(() => collectAdvisoryIds('nope'), /unparseable/);
  assert.throws(() => collectAdvisoryIds(JSON.stringify({ via: [] })), /unrecognized/);
  // unnamed advisory = structural refusal, never silently skipped
  assert.throws(
    () => collectAdvisoryIds(JSON.stringify({ vulnerabilities: { x: { via: [{ title: 'nameless' }] } } })),
    /no resolvable GHSA id/,
  );
});

test('the shipped --self-test runner exits OK on the embedded table', () => {
  assert.equal(runSelfTest(), EXIT_OK);
});
