#!/usr/bin/env node
/*
 * Headless unit-test harness for the Phlix Roku client (M-ROKU-15 cure).
 *
 * For the life of this repo the .test.brs suites under tests/unit were "green
 * on paper, never executed": no CI job, no local runner, and the assertTrue/
 * assertEqual/assertNotEqual* helpers they call were defined NOWHERE (a
 * rooibos-era fiction). This harness ends that: it executes the pure-logic
 * suites off-device with the `brs` BrightScript interpreter (a devDependency),
 * one interpreter run per test, and fails loudly on assertion failures and
 * runtime crashes.
 *
 * Design notes:
 *   - `brs.execute(files, {root})` executes files sequentially in one global
 *     scope and registers each function when its declaration statement runs,
 *     so load order is: assertion prelude -> resolved source deps (closure)
 *     -> suite file -> generated dispatcher (declared, then called last).
 *   - Source dependency files are resolved by symbol: every global function/
 *     sub declared under source/lib and source is indexed, and the closure of
 *     what a suite references (plus what those files reference) is loaded.
 *   - Suites needing live devices, scene-graph nodes, sockets, or task hosts
 *     are NOT silently dropped: they are listed in EXCLUDED with a concrete
 *     reason and a pointer to the leg that covers the same laws on-device
 *     (scripts/verify-runtime.sh). Silent absence was the original sin.
 *
 * Usage:  node tests/scripts/run-headless-unit.mjs [--suite Name] [--list]
 * Exit:   0 all allow-listed suites fully green; 1 any FAIL/CRASH; 2 usage.
 */
import fs from "fs";
import os from "os";
import path from "path";
import { createRequire } from "module";

const require = createRequire(import.meta.url);

const REPO = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..", "..");

function loadBrs() {
    const candidates = [];
    if (process.env.BRS_MODULE) candidates.push(path.resolve(process.env.BRS_MODULE));
    candidates.push("brs");
    for (const c of candidates) {
        try { return require(c); } catch (e) { /* next candidate */ }
    }
    console.error("brs interpreter not resolvable (npm ci; or BRS_MODULE=/path/to/brs). Tried: " + candidates.join(", "));
    process.exit(1);
}

// --- suite allow-list -------------------------------------------------------
// Every entry must be green before it is admitted; removals need a reason.
const ALLOWED = [
    "SyncPlayProtocol", "TranslateWithParams", "ApiEnvelope", "SyncPlayErrors",
    "Utilities", "Utilities2", "CaptionsMode", "SkipButton", "SleepTimer",
    "ContentIdGuard", "Discovery", "RedirectCustody", "Theme", "Storage",
    "HubRelayOriginLaw", "WireGuard", "AuthManager", "ApiClient",
    "AppContext", "PhlixApp", "SyncPlayManager", "SyncPlayWsTls",
];
// Suites kept off the headless list and why (measured, not assumed — each
// entry was run and its crash reason recorded in the W-min91 fixlog).
const EXCLUDED = {
    Storage: "brs gap: whole suite drives Storage()'s function-object state (Storage.brs:78 'non-iterable' crash x4) — device idiom, brs cannot carry properties on function objects",
    ApiClient: "brs gap: every test constructs through ApiClient() which attaches state to the function object (Storage.brs:78 crash x7, same class as the Storage suite)",
    AppContext: "brs gap: AppContext() function-object state (Storage.brs:78 crash x10, same class)",
    Theme: "not brs-fixable: the suite drives Theme()/theme constants that exist NOWHERE in source/ or components/ (grep-verified) — rooibos-era fiction; the tests never ran anywhere, device included. Delete-or-rebuild is follow-up work (disclosed in W-min91 fixlog)",
};

// Per-test brs interpreter gaps: the test or the code it drives uses a
// construct brs does not implement the way the device does. Each entry cites
// the MEASURED construct (crash line or boxed-shape detail from the run log);
// EXCLUSION_CHECKS below re-verifies the ones with a checkable shape.
const EXCLUDED_TESTS = {
    SyncPlayProtocol: {
        TestSyncPlayProtocolNewWebSocketKey: "brs gap: CreateObject(\"roByteArray\") returns invalid — product SyncPlayProtocol.brs:295 .Push crashes (measured)",
        TestSyncPlayProtocolNewWebSocketKeyUniqueness: "brs gap: roByteArray invalid — same product :295 .Push path",
        TestSyncPlayProtocolBuildClientFrameEmpty: "brs gap: roByteArray invalid in BuildClientFrame .Push",
        TestSyncPlayProtocolBuildCloseFrame: "brs gap: roByteArray invalid in BuildClientFrame .Push",
        TestSyncPlayProtocolBuildPongFrame: "brs gap: roByteArray invalid in BuildClientFrame .Push",
        TestSyncPlayProtocolBuildHandshakeRequest: "brs gap: roByteArray invalid in BuildHandshakeRequest .Push path",
        TestSyncPlayProtocolBuildHandshakeRequestWithBearerOffer: "brs gap: roByteArray invalid in BuildHandshakeRequest .Push path",
        TestSyncPlayProtocolBuildTextFrame: "brs gap: roByteArray invalid — FromAsciiString at SyncPlayProtocol.brs:151",
        TestSyncPlayProtocolRemainderBuffer: "brs gap: TEST-side CreateObject(\"roByteArray\") .Push at test:297",
        TestSyncPlayProtocolRemainderBufferWithInvalid: "brs gap: TEST-side roByteArray .Count at test:312 after invalid CreateObject",
        TestSyncPlayProtocolXorByte: "brs gap: 'not' on integers unsupported (brs 'not' is logical-only, device is bitwise); device-correct product body verified via functionBody check (no roByteArray inside)",
        TestSyncPlayProtocolHandshakeAcceptedInvalid: "brs gap: brs refuses invalid for an 'as String' formal (device coerces); product guards invalid separately — typed-param strictness differs",
        TestSyncPlayProtocolDecodeInvalidInput: "brs gap: same invalid-to-typed-String-param strictness as HandshakeAcceptedInvalid",
    },
    TranslateWithParams: {
        TestTranslateWithParamsEqualsTranslateOnDegradedParams: "brs gap: Translate() -> LoadLocaleStrings._loaded function-object state (Utilities.brs:1462) — brs cannot carry properties on function objects",
        TestTranslateWithParamsNeverCrashesOnUnknownKey: "brs gap: same LoadLocaleStrings._loaded function-object state through Translate",
        TestTranslateWithParamsKnownCodeNeverEmpty: "brs gap: same LoadLocaleStrings._loaded function-object state through Translate",
    },
    Utilities2: {
        TestNormalizeServerUrlInvalid: "brs gap: brs refuses invalid for an 'as String' formal (NormalizeServerUrl, Utilities.brs:160) — the device coerces invalid to '' and the product guard answers",
        TestUrlEncodeInvalid: "brs gap: same invalid-to-typed-String-formal strictness (UrlEncode)",
        TestPhotoAlbumCaptionInvalid: "brs gap: PhotoAlbumCaption -> Translate -> LoadLocaleStrings function-object state (Utilities.brs:1462)",
        TestPhotoAlbumCaptionUnknown: "brs gap: same LoadLocaleStrings function-object state through Translate",
        TestPhotoAlbumCaptionEmpty: "brs gap: same LoadLocaleStrings function-object state through Translate",
        TestRatingLabelValid: "brs gap: same LoadLocaleStrings function-object state through Translate",
        TestRatingLabelOutOfRange: "brs gap: same LoadLocaleStrings function-object state through Translate",
    },
    CaptionsMode: {
        TestCaptionsModeLabelsAreIndexParallel: "brs gap: CaptionsModeLabels -> Translate -> LoadLocaleStrings function-object state (Utilities.brs:1462)",
        TestCaptionsModeLabelMapsWireToLocalizedLabel: "brs gap: same LoadLocaleStrings function-object state through Translate",
        TestCaptionsModeLabelNormalizesSystemOff: "brs gap: same LoadLocaleStrings function-object state through Translate",
        TestCaptionsModeLabelPassesUnknownThrough: "brs gap: same LoadLocaleStrings function-object state through Translate",
    },
    SyncPlayErrors: {
        TestLocalizeSyncPlayErrorUnknownCodeUsesServerMessage: "brs gap: LocalizeSyncPlayError -> Translate -> LoadLocaleStrings function-object state (Utilities.brs:1462)",
        TestLocalizeSyncPlayErrorKnownCodeNeverEmpty: "brs gap: same LoadLocaleStrings function-object state through Translate",
        TestLocalizeSyncPlayLocalErrorNeverEmpty: "brs gap: same LoadLocaleStrings function-object state through Translate",
    },
    ContentIdGuard: {
        TestIsSafeContentIdRejectsNulByte: "brs gap: Chr(0) collapses to the empty string in brs (measured Len(Chr(0))=0), so the NUL the device embeds cannot be built here",
    },
    RedirectCustody: {
        TestResolveRedirectTargetShapes: "brs gap: Chr(0) collapses to \"\" in brs (measured Len(Chr(0))=0) — ResolveRedirectTarget's injection guard Instr(1,loc,Chr(0)) then fires on EVERY input here; the device sees a real NUL and the guard is inert on clean URLs (law unchanged)",
    },
    Discovery: {
        TestClassifyUrlFailureUnreachableIsTheHonestDefault: "brs gap: brs refuses invalid for a typed formal (ClassifyUrlFailure) — device coerces; measured signature rejection",
        TestExtractServerOriginRejectsForeignSchemes: "brs gap: same invalid-to-typed-formal strictness (ExtractServerOrigin)",
        TestParseSsdpResponseRejectsGarbage: "brs gap: same invalid-to-typed-formal strictness (ParseSsdpResponse)",
    },
    AuthManager: {
        TestAuthManagerInit: "brs gap: AuthManager drives Storage()'s function-object state (Storage.brs:78 crash) — device idiom, brs cannot carry properties on function objects",
        TestAuthManagerCheckAuthWithValidApi: "brs gap: same Storage function-object state class",
        TestAuthManagerLogout: "brs gap: same Storage function-object state class",
        TestAuthManagerLogoutWithApi: "brs gap: same Storage function-object state class",
        TestAuthManagerGetCurrentUser: "brs gap: same Storage function-object state class",
        TestAuthManagerGetCurrentUserAfterLogin: "brs gap: same Storage function-object state class",
    },
    SyncPlayManager: {
        TestSyncPlayManagerInit: "brs gap: SyncPlayManager drives Storage()'s function-object state (Storage.brs:78 crash) — device idiom, brs cannot carry properties on function objects",
        TestSyncPlayManagerGetGroupsWithNonArrayResult: "brs gap: same Storage function-object state class",
        TestSyncPlayManagerLeaveGroupWithNoSession: "brs gap: same Storage function-object state class",
        TestSyncPlayManagerIsInGroup: "brs gap: same Storage function-object state class",
        TestSyncPlayManagerIsHostWhenNoSession: "brs gap: same Storage function-object state class",
        TestSyncPlayManagerGetGroupIdWhenNoSession: "brs gap: same Storage function-object state class",
        TestSyncPlayManagerGetSessionIdWhenNoSession: "brs gap: same Storage function-object state class",
        TestSyncPlayManagerGetServerUrlWhenNoSession: "brs gap: same Storage function-object state class",
        TestSyncPlayManagerGetGroupNameWhenNoSession: "brs gap: same Storage function-object state class",
        TestSyncPlayManagerGetMemberCountWhenNoSession: "brs gap: same Storage function-object state class",
        TestSyncPlayManagerBuildWsPartsWithNoSession: "brs gap: same Storage function-object state class",
        TestSyncPlayManagerUpdateFromGroupStateWithNoSession: "brs gap: same Storage function-object state class",
    },
};

// --- symbol index -----------------------------------------------------------
function declNames(src) {
    const names = [];
    const re = /^\s*(?:function|sub)\s+([A-Za-z_][A-Za-z0-9_]*)/im;
    for (const line of src.split(/\r?\n/)) {
        const m = line.match(re);
        if (m) names.push(m[1].toLowerCase());
    }
    return names;
}

function buildIndex() {
    const index = new Map(); // lowercase name -> absolute file
    const files = [];
    for (const dir of ["source/lib", "source"]) {
        const full = path.join(REPO, dir);
        if (!fs.existsSync(full)) continue;
        const walk = (d) => {
            for (const e of fs.readdirSync(d, { withFileTypes: true })) {
                const p = path.join(d, e.name);
                if (e.isDirectory()) walk(p);
                else if (e.name.endsWith(".brs")) files.push(p);
            }
        };
        walk(full);
    }
    // Deeper dirs first so the more specific module wins ties (none today).
    for (const f of files.sort().reverse()) {
        for (const name of declNames(fs.readFileSync(f, "utf8"))) {
            if (!index.has(name)) index.set(name, f);
        }
    }
    return { index, files };
}

function referencedNames(src) {
    const names = new Set();
    const re = /(?<![.\w])([A-Za-z_][A-Za-z0-9_]*)\s*\(/gim;
    let m;
    while ((m = re.exec(src))) names.add(m[1].toLowerCase());
    return names;
}

// BrightScript's own stdlib keywords that the closure walker must not chase.
const BUILTINS = new Set([
    "if", "for", "while", "function", "sub", "print", "return", "end", "then", "else",
    "each", "type", "lcase", "ucase", "left", "right", "instr", "str", "val", "int",
    "fix", "abs", "sqr", "mid", "len", "asc", "chr", "string", "join", "split",
    "parsejson", "encodejson", "createdate", "createtime", "getglobalaa",
    "createobject", "run", "stop", "sleep", "getversion", "messagebox",
]);

function closureOf(seeds, index) {
    const queue = [...seeds];
    const files = new Set();
    const missing = [];
    const seen = new Set();
    while (queue.length) {
        const name = queue.shift();
        if (seen.has(name) || BUILTINS.has(name)) continue;
        seen.add(name);
        const file = index.get(name);
        if (!file) { missing.push(name); continue; }
        if (!files.has(file)) {
            files.add(file);
            for (const ref of referencedNames(fs.readFileSync(file, "utf8"))) queue.push(ref);
        }
    }
    return { files: [...files], missing: missing.filter((n) => !BUILTINS.has(n)) };
}

// --- prelude ----------------------------------------------------------------
const PRELUDE = `
sub __brsHdrFail(msg)
    g = GetGlobalAA()
    g.hdr_fails = g.hdr_fails + 1
    print "HDR-FAIL " + msg
end sub
sub assertTrue(cond, msg = "")
    if not cond then __brsHdrFail("assertTrue: " + msg)
end sub
sub assertFalse(cond, msg = "")
    if cond then __brsHdrFail("assertFalse: " + msg)
end sub
function ToCompareText(v as dynamic) as String
    if v = invalid then return "invalid"
    t = type(v)
    if t = "roArray" or t = "roAssociativeArray" or t = "array" then
        return EncodeJSON(v)
    end if
    if t = "Boolean" then
        if v then return "true"
        return "false"
    end if
    return v + ""
end function
sub assertEqual(actual, expected, msg = "", note = "")
    if actual <> expected then
        print "HDR-DETAIL actual=[" + ToCompareText(actual) + "] expected=[" + ToCompareText(expected) + "] " + note
        __brsHdrFail("assertEqual: " + msg)
    end if
end sub
sub assertNotEqual(actual, expected, msg = "")
    if actual = expected then __brsHdrFail("assertNotEqual: " + msg)
end sub
' Device-faithful RIGHT (measured brs defect): brs implements Right(s, n) as
' Mid(s, len(s) - n) — off by one — so Right("01", 2) yields "0" here while
' the Roku device yields "01". Every zero-pad idiom in this repo
' (Right("0" + str(x).trim(), 2)) hits the defect exactly when the value is
' one digit. Declaring the function in-program shadows the builtin (probed),
' restoring device semantics for the run.
function Right(s as String, n as Integer) as String
    if n >= Len(s) then return s
    return Mid(s, Len(s) - n + 1)
end function
`;

// --- execution --------------------------------------------------------------
// Finds a top-level function/sub (BrightScript names are case-insensitive) in
// a source string and returns its body; "" when no definition exists. The
// exclusion self-check uses it so a brs-gap exclusion can only stand while the
// construct it MEASURED is still the one in the product code.
function functionBody(src, name) {
    const lines = src.split(/\r?\n/);
    // Top-level `function name(` / `sub name(` AND object-member `name: function`.
    const open = new RegExp("^\\s*(?:(?:function|sub)\\s+" + name + "\\b|" + name + ":\\s*(?:function|sub)\\b)", "i");
    const close = new RegExp("^\\s*end\\s+(function|sub)\\s*$", "i");
    for (let i = 0; i < lines.length; i++) {
        if (!open.test(lines[i])) continue;
        const body = [];
        for (let j = i + 1; j < lines.length && !close.test(lines[j]); j++) body.push(lines[j]);
        return body.join("\n");
    }
    return "";
}
(function selfCheckFunctionBody() {
    const sample = "function Foo()\n    x = Foo._s\nend function\nsub Bar()\nend sub\nobj = {\n    Baz: function()\n        y = 1\n    end function\n}\n";
    if (!/Foo\._s/.test(functionBody(sample, "foo"))) throw new Error("harness self-check: functionBody broken");
    if (!/y = 1/.test(functionBody(sample, "baz"))) throw new Error("harness self-check: functionBody misses AA-member form");
    if (functionBody(sample, "Missing") !== "") throw new Error("harness self-check: functionBody false-positive");
})();

// Each brs-gap exclusion must still describe the measured construct when the
// suite runs. If the product code changes such that the cited reason no longer
// explains the failure, the stale exclusion aborts the run (fail-loud, like
// every CHECK leg in scripts/verify-runtime.sh).
const EXCLUSION_CHECKS = {
    "SyncPlayProtocol::XorByte": (load) => {
        const body = functionBody(load("XorByte"), "XorByte");
        if (!body) throw new Error("exclusion check: XorByte definition not found");
        if (!/\bnot\b/i.test(body)) {
            throw new Error("exclusion stale: product XorByte body no longer uses 'not' — re-admit the test");
        }
        if (/roByteArray/i.test(body)) {
            throw new Error("exclusion mislabeled: XorByte body contains a roByteArray use, not a 'not' gap");
        }
    },
};

const testRe = /^\s*sub\s+(Test[A-Za-z0-9_]*)/im;

function extractTests(src) {
    const names = [];
    for (const line of src.split(/\r?\n/)) {
        const m = line.match(testRe);
        if (m) names.push(m[1]);
    }
    return names;
}

async function main() {
    const argv = process.argv.slice(2);
    let only = null;
    if (argv.includes("--list")) {
        for (const s of ALLOWED) console.log("allowed " + s);
        for (const [s, why] of Object.entries(EXCLUDED)) console.log("excluded " + s + " — " + why);
        return 0;
    }
    if (argv.includes("--suite")) {
        only = argv[argv.indexOf("--suite") + 1];
        if (!only) { console.error("--suite needs a name"); return 2; }
    }
    const brs = loadBrs();
    const { index, files: sourceFiles } = buildIndex();
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "brs-unit-"));
    fs.writeFileSync(path.join(tmp, "manifest"), "title=BrsUnit\nmajor_version=0\nminor_version=0\nbuild_version=0\n");
    const preludePath = path.join(tmp, "__prelude.brs");
    fs.writeFileSync(preludePath, PRELUDE);

    // Stale exclusion gate before anything runs: a cited brs gap must still be
    // the construct in the product source, or the run aborts (fail-loud).
    for (const [key, check] of Object.entries(EXCLUSION_CHECKS)) {
        const [s] = key.split("::");
        const load = (fn) => {
            const f = index.get(fn.toLowerCase());
            if (f) return fs.readFileSync(f, "utf8");
            // AA-member declarations (XorByte lives inside the protocol object).
            for (const sf of sourceFiles) {
                const txt = fs.readFileSync(sf, "utf8");
                if (functionBody(txt, fn)) return txt;
            }
            return "";
        };
        try {
            check(load);
        } catch (e) {
            console.error("EXCLUSION CHECK FAILED [" + key + "]: " + (e && e.message ? e.message : e));
            fs.rmSync(tmp, { recursive: true, force: true });
            return 1;
        }
    }

    let total = 0, failed = 0, excluded = 0;
    const unitDir = path.join(REPO, "tests", "unit");
    const suites = (only ? [only] : ALLOWED).map((s) => {
        const file = path.join(unitDir, s + ".test.brs");
        if (!fs.existsSync(file)) { console.error("no such suite: " + s + " (" + file + ")"); process.exit(2); }
        return { s, file };
    });

    for (const { s, file } of suites) {
        if (EXCLUDED[s]) { console.log("EXCLUDED " + s + " — " + EXCLUDED[s]); continue; }
        const src = fs.readFileSync(file, "utf8");
        const tests = extractTests(src);
        const seeds = [...referencedNames(src)].filter((n) => index.has(n));
        const { files: deps, missing } = closureOf(seeds, index);
        // Never load the dispatcher's own name or assert helpers as deps.
        const programBase = [preludePath, ...deps, file];
        let suiteFails = 0;
        for (const t of tests) {
            const tReason = (EXCLUDED_TESTS[s] || {})[t];
            if (tReason) { excluded += 1; console.log("EXCLUDE " + s + "::" + t + " — " + tReason); continue; }
            total += 1;
            const dispatch = path.join(tmp, "__dispatch.brs");
            fs.writeFileSync(dispatch,
                "sub __Dispatch()\n    g = GetGlobalAA()\n    if g.doesExist(\"hdr_fails\") = false then g.addReplace(\"hdr_fails\", 0)\n    before = g.hdr_fails\n    " + t + "()\n    if g.hdr_fails = before then print \"HDR-OK " + s + "::" + t + "\" else print \"HDR-BAD " + s + "::" + t + "\"\nend sub\n__Dispatch()\n");
            let out = "";
            const collect = { write: (msg) => { out += msg; } };
            try {
                await brs.execute([...programBase, dispatch], { root: tmp, stdout: collect, stderr: collect });
            } catch (e) {
                const msgs = e && e.messages ? e.messages.join("\n") : String((e && e.message) || e);
                out += msgs;
            }
            const crashed = /HDR-BAD/.test(out) || !/HDR-OK /.test(out);
            if (crashed) {
                failed += 1; suiteFails += 1;
                console.log("FAIL " + s + "::" + t);
                console.log(out.split(/\r?\n/).filter((l) => l.includes("HDR-") || l.includes("):")).slice(0, 6).map((l) => "     " + l).join("\n"));
            } else if (process.env.HEADLESS_UNIT_VERBOSE) {
                console.log("ok   " + s + "::" + t);
            }
        }
        const note = missing.length ? " (unresolved refs: " + missing.slice(0, 4).join(",") + (missing.length > 4 ? ",…" : "") + ")" : "";
        console.log(suiteFails === 0 ? "PASS " + s + " (" + tests.length + " tests)" + note
                                      : "SUITE " + s + ": " + suiteFails + "/" + tests.length + note);
    }
    fs.rmSync(tmp, { recursive: true, force: true });
    console.log("HEADLESS-UNIT total=" + total + " failed=" + failed + " excluded=" + excluded);
    return failed === 0 ? 0 : 1;
}

main().then((rc) => { process.exitCode = rc; }).catch((e) => { console.error(e); process.exitCode = 1; });
