'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/lib/Utilities.brs

' copyright 2026 Joe Huss
'


' ===========================================
' Utility Functions for Roku
' Helper functions used throughout the app
' ===========================================

' Format seconds to time string (HH:MM:SS or MM:SS)
function FormatTime(seconds as Float) as String
    hours = Int(seconds / 3600)
    minutes = Int((seconds mod 3600) / 60)
    secs = Int(seconds mod 60)

    if hours > 0 then
        return str(hours).trim() + ":" + Right("0" + str(minutes).Trim(), 2) + ":" + Right("0" + str(secs).Trim(), 2)
    else
        return str(minutes).Trim() + ":" + Right("0" + str(secs).Trim(), 2)
    end if
end function

' Format a UNIX epoch timestamp (seconds) as a short local "M/D H:MM" wall-clock
' string for guide/recording captions. Distinct from FormatTime (a DURATION
' formatter). roDateTime.FromSeconds takes an Integer; UNIX seconds fit in 32-bit
' until 2038 so Int() is safe (unlike 100ns ticks - see SecondsToTicks).
function FormatUnixTime(seconds as Double) as String
    if seconds <= 0 then return ""
    dt = CreateObject("roDateTime")
    dt.FromSeconds(Int(seconds))
    dt.ToLocalTime()
    minute = str(dt.GetMinutes()).trim()
    if Len(minute) < 2 then minute = "0" + minute
    return str(dt.GetMonth()).trim() + "/" + str(dt.GetDayOfMonth()).trim() + " " + str(dt.GetHours()).trim() + ":" + minute
end function

' Parse a time string to seconds
function ParseTime(timeString as String) as Float
    parts = timeString.split(":")
    if parts.Count() = 3 then
        return Val(parts[0]) * 3600 + Val(parts[1]) * 60 + Val(parts[2])
    else if parts.Count() = 2 then
        return Val(parts[0]) * 60 + Val(parts[1])
    end if
    return 0
end function

' Truncate string with ellipsis
function TruncateString(str as String, maxLength as Integer) as String
    if str.Len() > maxLength then
        return Left(str, maxLength - 3) + "..."
    end if
    return str
end function

' Validate URL format
function IsValidUrl(url as String) as Boolean
    if url <> invalid and url <> "" then
        if LCase(Left(url, 7)) = "http://" or LCase(Left(url, 8)) = "https://" then
            return true
        end if
    end if
    return false
end function

' Reduce any URL-shaped string to its bare lowercase HOST (authority minus
' port; an IPv6 literal keeps its brackets: "[::1]:8096/x" -> "[::1]").
' Scheme-less input works (the Connect screen infers BEFORE a scheme exists).
' Returns "" for an empty authority, an unclosed bracket or a userinfo-
' bearing host ("user@evil" is never a server name we trust a class for).
' THE single host parser behind every connect-class predicate - the scheme
' inference, the M-ROKU-15 cleartext-consent gate and the redirect custody
' law all read hosts through here (CHECK48 R3 pins the delegation).
function HostOfUrl(url as String) as String
    if url = invalid then return ""
    u = LCase(url.Trim())
    if u = "" then return ""
    schemeSep = Instr(1, u, "://")
    if schemeSep > 0 then u = Mid(u, schemeSep + 3)

    cut = Len(u)
    for i = 1 to Len(u)
        c = Mid(u, i, 1)
        if c = "/" or c = "?" or c = "#" then
            cut = i - 1
            exit for
        end if
    end for
    u = Left(u, cut)
    if u = "" then return ""
    if Instr(1, u, "@") > 0 then return ""

    if Left(u, 1) = "[" then
        close = Instr(1, u, "]")
        if close = 0 then return ""
        return Left(u, close)
    end if

    colon = Instr(1, u, ":")
    if colon > 0 then
        ' Two or more colons can only be an unbracketed IPv6 literal without
        ' a port (a host:port authority carries exactly one). Cutting at the
        ' FIRST colon would blank the address, so the literal passes through
        ' — the Connect screen's scheme-less input includes '::1' shapes.
        if Instr(colon + 1, u, ":") > 0 then return u
        u = Left(u, colon - 1)
    end if
    return u
end function

' True for hosts whose cleartext http:// is the LAN/loopback/link-local class
' the README's connect section promises ("LAN/loopback hosts, https://
' otherwise"): RFC1918 dotted quads (10/8, 172.16-31, 192.168/16), loopback
' (127/8, localhost, [::1]/::1) and link-local (169.254/16). The R4.7 law is
' preserved verbatim: RFC1918 range checks apply ONLY to numeric dotted
' quads, so a hostname like "10th-street.example.com" never reads as private.
' Single source for BOTH the NormalizeServerUrl inference and the M-ROKU-15
' cleartext-consent gate - CHECK48 R3 pins the delegation.
function IsPrivateHostAddress(host as String) as Boolean
    if host = invalid then return false
    h = LCase(host.Trim())
    if h = "" then return false
    if h = "localhost" then return true
    if h = "::1" or h = "[::1]" then return true

    parts = h.Split(".")
    if parts.Count() <> 4 then return false
    for each p in parts
        ' Len check + digit check: each part must be 1-3 digits
        if Len(p) < 1 or Len(p) > 3 then return false
        for i = 1 to Len(p)
            c = Mid(p, i, 1)
            if c < "0" or c > "9" then return false
        end for
    end for

    if parts[0] = "10" then return true
    if parts[0] = "127" then return true
    if parts[0] = "169" and parts[1] = "254" then return true
    if parts[0] = "192" and parts[1] = "168" then return true
    if parts[0] = "172" then
        octet = 0
        for i = 1 to Len(parts[1])
            octet = octet * 10 + Asc(Mid(parts[1], i, 1)) - 48
        end for
        if octet >= 16 and octet <= 31 then return true
    end if
    return false
end function

' Normalize a raw server/hub URL typed on the Connect screen into a bare origin
' ApiClient can consume (ApiClient builds {baseUrl} + "/api/v1" + path). Trims
' surrounding whitespace; keeps an explicit http://|https:// scheme; otherwise
' infers the scheme from the host through the single-source IsPrivateHostAddress
' predicate (LAN/loopback/link-local hosts -> http://, everything else ->
' https://); finally strips a single trailing "/". Guards invalid/empty -> "".
' A typed http:// to a NON-private host survives normalization by design - the
' M-ROKU-15 consent gate in ConnectScene makes that class LOUD before it is
' ever persisted.
' @param raw String - the user-entered URL (may be invalid)
' @return String - the normalized bare origin (empty string when nothing usable)
function NormalizeServerUrl(raw as String) as String
    if raw = invalid then return ""

    url = raw.Trim()
    if url = "" then return ""

    lower = LCase(url)
    if Left(lower, 7) = "http://" or Left(lower, 8) = "https://" then
        ' Explicit scheme - keep as typed (the cleartext class of a remote
        ' http:// is gated at PERSIST time in ConnectScene, not here).
    else
        if IsPrivateHostAddress(HostOfUrl(lower)) then
            url = "http://" + url
        else
            url = "https://" + url
        end if
    end if

    ' Strip a single trailing slash so ApiClient's "/api/v1" concat stays clean.
    if Len(url) > 0 and Right(url, 1) = "/" then
        url = Left(url, Len(url) - 1)
    end if

    return url
end function

' =============================================================================
' M-ROKU-04 — honest transport-failure taxonomy.
'
' A failing roUrlTransfer reports WHY through roUrlEvent.GetFailureReason()
' (a curl reason string). Before this cure the connect path collapsed every
' status-0 failure into "connect" or "timeout" based on a flag that only says
' the async call started, and PhlixApp then mislabelled "no token yet" as
' "Unable to reach server. Please check your network." Users were blamed for
' a network they were not standing next to.
'
' The law (CHECK34 in scripts/verify-runtime.sh pins the triangle):
'   ClassifyUrlFailure returns EXACTLY the buckets
'       bad_url | dns | refused | tls | timeout | unreachable | redirect_refused
'   (redirect_refused is M-ROKU-15's client-minted custody bucket - curl's own
'   "Maximum (N) redirects followed" text and our refused-hop fail texts both
'   land on it; it carries its message like every curl-sourced bucket),
'   every bucket has exactly one catalog message,
'       connect_err_<bucket> in locale/<any>/strings.json (CHECK21 parity),
'   and TranslateTransportReason is THE single literal Translate ladder
'   mapping bucket -> message. A new bucket cannot dodge the catalog.
' =============================================================================

' Map one roUrlTransfer transport failure onto a closed reason bucket.
' @param failReason String|invalid - roUrlEvent.GetFailureReason() (curl text,
'        matched by keyword because the exact strings are firmware-owned), or
'        the client-minted custody text an ApiClient send site produced when
'        IT refused to follow a redirect (M-ROKU-15)
' @param started Boolean - whether the async transfer ever started; false
'        means roUrlTransfer itself rejected the URL (malformed/unparseable)
' @return String - one of bad_url|dns|refused|tls|timeout|unreachable|redirect_refused
function ClassifyUrlFailure(failReason as String, started as Boolean) as String
    if not started then return "bad_url"
    lower = ""
    if failReason <> invalid then lower = LCase(failReason)
    if Instr(1, lower, "resolve") > 0 then return "dns"
    ' M-ROKU-15 custody bucket - checked BEFORE the "refused" arm on purpose:
    ' our refusal texts ("unsafe redirect refused ...") contain the word
    ' "refused", and the honest user story is the custody stop, not a
    ' connection refusal. Also catches curl's own redirect-cap text.
    if Instr(1, lower, "redirect") > 0 then return "redirect_refused"
    if Instr(1, lower, "couldn't connect") > 0 or Instr(1, lower, "could not connect") > 0 or Instr(1, lower, "refused") > 0 then return "refused"
    if Instr(1, lower, "ssl") > 0 or Instr(1, lower, "certificate") > 0 or Instr(1, lower, "tls") > 0 then return "tls"
    if Instr(1, lower, "timed out") > 0 or Instr(1, lower, "timeout") > 0 then return "timeout"
    return "unreachable"
end function

' True when a reason string is one of the transport buckets above (as opposed
' to an HTTP/server verdict such as session_invalid or no_session).
function IsTransportReason(reason as String) as Boolean
    if reason = invalid then return false
    return reason = "bad_url" or reason = "dns" or reason = "refused" or reason = "tls" or reason = "timeout" or reason = "unreachable" or reason = "redirect_refused"
end function

' The ONE bucket -> user-message ladder (literal Translate calls so CHECKs
' 20/34 keep the anti-typo / raw-key-echo guarantee total across it).
' Unknown reasons fall to the honest generic bucket message.
function TranslateTransportReason(reason as String) as String
    if reason = "dns" then return Translate("connect_err_dns")
    if reason = "refused" then return Translate("connect_err_refused")
    if reason = "tls" then return Translate("connect_err_tls")
    if reason = "timeout" then return Translate("connect_err_timeout")
    if reason = "bad_url" then return Translate("connect_err_bad_url")
    if reason = "redirect_refused" then return Translate("connect_err_redirect_refused")
    return Translate("connect_err_unreachable")
end function

' =============================================================================
' M-ROKU-15 — CREDENTIAL CUSTODY LEAVES (review roku__exploiter M4)
'
' The Connect/pair flow lets the USER choose the server origin (typed URL,
' prefill, "Connect anyway" after a failed probe) and then ships an
' UNENCRYPTED login password plus every Bearer token there. Two custody laws
' live as pure leaves here so the unit suite and CHECK48 can pin them from
' one source:
'   1. CLEARTTEXT CONSENT: ServerUrlUsesCleartextToRemoteHost gates the
'      single server_url persist site in ConnectScene - a cleartext http://
'      origin to a host that is NOT the LAN/loopback/link-local class needs
'      the user's explicit LOUD OK first (the review's "this server will
'      receive your password unencrypted" dialog). LAN http stays silent; it
'      is the documented normal.
'   2. REDIRECT CUSTODY: ApiClient's credentialed send sites disable the
'      firmware's auto-follow and walk 3xx ONLY through these leaves -
'      ResolveRedirectTarget absolutizes a Location, IsCredentialSafeRedirect
'      Hop admits same-origin hops plus the one safe non-identical class (the
'      same-host http->https 443 upgrade), and RedirectHopLimit caps the
'      chain. Every refusal surfaces as the redirect_refused bucket with its
'      cataloged sentence - credentials never ride to a different host, and
'      never ride DOWN to cleartext.
' =============================================================================

' True when a (normalized, scheme-bearing) server URL is cleartext http://
' to a host OUTSIDE the LAN/loopback/link-local class - the exact shape where
' the login password and every later Bearer request cross a sniffable path.
' Scheme-less input returns false: the ConnectScene persist choke is only
' ever reached with NormalizeServerUrl output (which guarantees a scheme).
function ServerUrlUsesCleartextToRemoteHost(url as String) as Boolean
    if url = invalid then return false
    u = LCase(url.Trim())
    if Left(u, 7) <> "http://" then return false
    return not IsPrivateHostAddress(HostOfUrl(u))
end function

' =============================================================================
' MEDIA LANE TLS-BOUNDARY LAW (MJ-19, review roku__secnet item 19)
' =============================================================================

' True when a server-supplied media URL may ride the Video/Audio node from the
' given API origin. The signed stream URL carries the media token and reveals
' viewing intent the moment the TV issues the GET: on an https origin, an
' http:// target would carry that signed URL ACROSS the TLS boundary in
' cleartext - the repo's own plaintext-origin doctrine (SyncPlayWsRefused
' ForOrigin, M-ROKU-14) names the scheme mismatch itself as the exploitable
' class, and browsers enforce the same mixed-content rule. Refusing costs
' playback only on servers that answer with mixed content (a misconfiguration
' class); an http origin keeps http media - the REST lane is already cleartext
' there, so the media GET adds no NEW exposure. Root-relative paths ride the
' origin's own scheme, so they can never cross the boundary: admissible. Any
' other absolute shape must name a parseable http(s) origin - OriginOfUrl
' returns "" for file://, data://, userinfo games, bracket-less-broken hosts
' and non-numeric ports, and this law refuses exactly those. Accepts ANY
' wire shape defensively (the CHECK43 law: hostile untyped text never reaches
' a String operation ungated): non-String, invalid and blank return false.
' Pure: two values in, boolean out.
function IsStreamUrlAdmissible(originUrl as String, streamUrl as String) as Boolean
    if streamUrl = invalid then return false
    if type(streamUrl) <> "String" then return false
    s = LCase(streamUrl.Trim())
    if s = "" then return false
    if Left(s, 1) = "/" then return true
    if OriginOfUrl(s) = "" then return false
    if originUrl <> invalid and type(originUrl) = "String" then
        if Left(LCase(originUrl.Trim()), 8) = "https://" and Left(s, 7) = "http://" then
            return false
        end if
    end if
    return true
end function

' =============================================================================
' IMAGE LANE ADMISSIBILITY (ROK-14 / ROK-36)
' =============================================================================

' True when a server-supplied IMAGE url may ride a Poster/Image/ContentNode
' uri from the given API origin. Image GETs carry no token but reveal viewing
' habits and, on an https origin, an http:// target is the same mixed-content
' downgrade the media lane refuses; foreign-shape strings (file://, data://,
' userinfo games) are refused too. The package's own pkg:/ assets are always
' admissible (the placeholder arm). Everything else delegates to
' IsStreamUrlAdmissible so the two lanes share one scheme/origin law.
' Accepts ANY wire shape (non-String, blank -> false). Pure.
function IsImageUrlAdmissible(originUrl as Dynamic, imageUrl as Dynamic) as Boolean
    if imageUrl = invalid then return false
    if type(imageUrl) <> "String" and type(imageUrl) <> "roString" then return false
    s = LCase(imageUrl.Trim())
    if s = "" then return false
    if Left(s, 5) = "pkg:/" then return true
    o = ""
    if originUrl <> invalid and (type(originUrl) = "String" or type(originUrl) = "roString") then o = originUrl
    return IsStreamUrlAdmissible(o, imageUrl)
end function

' The admissible url or the pkg:/ placeholder: the single degrade arm every
' image-lane site routes through. Callers pass GetServerUrl() as the origin (kept out of this
' file: Utilities.brs is compiled into scopes that lack AppContext).
function SafeImageUrl(originUrl as Dynamic, imageUrl as Dynamic) as String
    if IsImageUrlAdmissible(originUrl, imageUrl) then return imageUrl
    return "pkg:/images/placeholder.png"
end function

' Manual redirect-hop budget for the send sites (CHECK48 pins the literal).
function RedirectHopLimit() as Integer
    return 3
end function

' One or many: the concurrent-stream limit line, singular when the budget
' allows exactly one stream, plural otherwise (RT-032 - the "(s)"-slashed
' English is retired). The count is normalized through Int() and the key
' choice is section-qualified, both per the MembersCountText precedent
' (SyncPlayScene.brs); ApplyNamedTokens fills the same {count} slot either
' way. Int() truncates non-integers, mirroring the precedent exactly.
' CHECK48 R3 / CHECK93 R3 / CHECK94 R4 hold the catalog half; the headless
' law is asserted in tests/unit/Utilities.test.brs.
function ConcurrentStreamLimitText(n as Object) as String
    count = Int(n)
    if count = 1 then
        return TranslateWithParams("parentalcontrols_current_limit_one", { count: count })
    end if
    return TranslateWithParams("parentalcontrols_current_limit", { count: count })
end function

' Ceiling in bytes for ANY API response body this client parses (RT-034,
' review roku__exploiter #8: the send sites fed an unbounded-length 2xx body
' straight into ParseJSON). Honest scope: roUrlEvent carries the FULL body
' already - the firmware buffered the transfer before the completion event
' fires - so this cap does not limit the network; it bounds OUR work after
' the fact: the GetString() BrightString copy and the ParseJSON object tree
' (materially larger than the wire bytes on hostile input). 32 MiB sits far
' above any legitimate envelope this client consumes; the live hostile path
' is the hub mode, where a relayed peer can steer a response (AppContext
' proxies arbitrary peers). CHECK48 R3 pins the two leaves; the literal is
' pinned by tests/unit/RedirectCustody.test.brs (RedirectHopLimit's
' existence-pin/value-pin split, mirrored exactly).
function ResponseBodyByteCap() as Integer
    return 33554432
end function

' True when EITHER informed arm says the body breaches the cap: the
' advertised Content-Length (the pre-materialization gate - refuses the
' GetString/ParseJSON work when the header already told us) or the actual
' string length after the read (the deciding arm - a chunked or lying
' Content-Length only meets reality after materialization). A blind arm
' passes the -1 unknown sentinel, the SAME convention ifUrlEvent
' GetContentLength answers when no header arrived; -1 never breaches a
' positive cap, so an uninformed arm can only decline, never convict
' (fail-safe). Typed Integer formals are load-bearing twice over: brs
' refuses `<>` comparisons on Object formals outright ("comparing
' non-primitive values", probe-measured at this lane), and brs Int()
' coerces through float32 - above 2^24 it LOSES precision (Int(33554433)
' measured to return 33554430) - so no Int() round-trip may guard this
' comparison; the values travel at full integer width.
function ResponseBodyExceedsCap(contentLength as Integer, bodyLength as Integer) as Boolean
    cap = ResponseBodyByteCap()
    return contentLength > cap or bodyLength > cap
end function

' Canonical lowercase origin "scheme://host[:port]" of a URL, DEFAULT ports
' folded (http://h:80 -> http://h, https://h:443 -> https://h) so a hop that
' merely spells the default is still same-origin. "" for anything non-http(s),
' hostless, userinfo-bearing, bracket-less-broken or with a non-numeric port -
' every malformed shape the custody law must REFUSE.
function OriginOfUrl(url as String) as String
    if url = invalid then return ""
    u = LCase(url.Trim())
    schemeSep = Instr(1, u, "://")
    if schemeSep = 0 then return ""
    scheme = Left(u, schemeSep - 1)
    if scheme <> "http" and scheme <> "https" then return ""

    rest = Mid(u, schemeSep + 3)
    cut = Len(rest)
    for i = 1 to Len(rest)
        c = Mid(rest, i, 1)
        if c = "/" or c = "?" or c = "#" then
            cut = i - 1
            exit for
        end if
    end for
    rest = Left(rest, cut)
    if rest = "" then return ""
    if Instr(1, rest, "@") > 0 then return ""

    host = rest
    port = ""
    if Left(rest, 1) = "[" then
        close = Instr(1, rest, "]")
        if close = 0 then return ""
        host = Left(rest, close)
        ' Mid() is 1-based on the device: the text AFTER the bracket starts at
        ' close + 1, and the port digits start at after[2] (after ':' ).
        ' The former close / 1 off-by-one pair made EVERY bracketed IPv6
        ' origin return "" on the device (and in brs, which is 1-based too) —
        ' found only because the M-ROKU-15 headless harness executed these
        ' tests for the first time.
        after = Mid(rest, close + 1)
        if Len(after) > 0 then
            if Left(after, 1) <> ":" then return ""
            port = Mid(after, 2)
        end if
    else
        colon = Instr(1, rest, ":")
        if colon > 0 then
            host = Left(rest, colon - 1)
            port = Mid(rest, colon + 1)
        end if
    end if
    if host = "" then return ""
    if port <> "" then
        for i = 1 to Len(port)
            c = Mid(port, i, 1)
            if c < "0" or c > "9" then return ""
        end for
        if (scheme = "http" and port = "80") or (scheme = "https" and port = "443") then port = ""
    end if

    if port <> "" then return scheme + "://" + host + ":" + port
    return scheme + "://" + host
end function

' The redirect hop law. SAFE (true) only when:
'   - the origins are IDENTICAL (same scheme, host and effective port) - the
'     trailing-slash / path-rewrite class the server itself may emit; or
'   - it is the same HOST moving from cleartext http to https on the STANDARD
'     TLS port (http://h -> https://h, both default ports after folding): the
'     commonest legit redirect on the web (an nginx 80->443 301), identical
'     machine, credentials MOVE TO ENCRYPTION - custody strictly improves.
' Everything else REFUSES: cross-host, any port change, https->http
' DOWNGRADE, non-http schemes, malformed targets. A refused hop means the
' Bearer token / login password stops HERE - it is never re-sent.
function IsCredentialSafeRedirectHop(fromUrl as String, toUrl as String) as Boolean
    fromOrigin = OriginOfUrl(fromUrl)
    destOrigin = OriginOfUrl(toUrl)
    if fromOrigin = "" or destOrigin = "" then return false
    if fromOrigin = destOrigin then return true
    if Left(fromOrigin, 7) = "http://" and Left(destOrigin, 8) = "https://" then
        if Mid(fromOrigin, 8) = Mid(destOrigin, 9) then return true
    end if
    return false
end function

' Absolutize a redirect Location against the URL that produced it: absolute
' http(s) passes through; protocol-relative "//host/p" rides the source
' scheme; "/p" and bare relative forms ride the source ORIGIN. A CR/LF/NUL
' bearing value is malformed (a header fragment must never reach a re-issued
' request line) and a userinfo-bearing absolute is refused by OriginOfUrl
' downstream. @return String - absolute URL, or "" when unusable.
function ResolveRedirectTarget(fromUrl as String, location as String) as String
    if location = invalid then return ""
    loc = location.Trim()
    if loc = "" then return ""
    if Instr(1, loc, Chr(13)) > 0 or Instr(1, loc, Chr(10)) > 0 or Instr(1, loc, Chr(0)) > 0 then return ""

    lower = LCase(loc)
    if Left(lower, 7) = "http://" or Left(lower, 8) = "https://" then return loc

    origin = OriginOfUrl(fromUrl)
    if origin = "" then return ""
    if Left(loc, 2) = "//" then
        sep = Instr(1, origin, "://")
        return Left(origin, sep - 1) + ":" + loc
    end if
    if Left(loc, 1) = "/" then return origin + loc
    return origin + "/" + loc
end function

' Reduce an SSDP LOCATION URL (e.g. http://192.168.1.5:8096/dlna/description.xml)
' to the connectable origin (http://192.168.1.5:8096). Rejects anything without
' an http(s) scheme and any value carrying userinfo - an SSDP answer is
' LAN-influenced input, so this is a parse boundary, not a trim helper.
' @return String - "scheme://host[:port]" or "" when the value is unusable
function ExtractServerOrigin(location as String) as String
    if location = invalid then return ""
    u = location.Trim()
    if u = "" then return ""
    lower = LCase(u)
    if Left(lower, 7) <> "http://" and Left(lower, 8) <> "https://" then return ""
    schemeSep = Instr(1, u, "://")
    scheme = Left(lower, schemeSep - 1)
    rest = Mid(u, schemeSep + 3)
    pathSep = Instr(1, rest, "/")
    if pathSep > 0 then rest = Left(rest, pathSep - 1)
    querySep = Instr(1, rest, "?")
    if querySep > 0 then rest = Left(rest, querySep - 1)
    fragmentSep = Instr(1, rest, "#")
    if fragmentSep > 0 then rest = Left(rest, fragmentSep - 1)
    if rest = "" then return ""
    if Instr(1, rest, "@") > 0 then return ""
    return scheme + "://" + rest
end function

' Accept only an SSDP search RESPONSE (M-ROKU-04 r2; moved out of
' components/DiscoveryTask.brs so the unit tests can reach it - pure parsing
' belongs in global scope, CHECK37 R5 pins this home). An "HTTP/1.x 200"
' status line (NOTIFYs and foreign M-SEARCH floods on the same port are
' datagrams we must not parse as answers - the server's own client applies
' the same discriminator), naming us as Phlix, whose LOCATION reduces to a
' usable origin via ExtractServerOrigin.
' @param raw String - one received datagram's ASCII text
' @return String - the origin, or "" when this datagram is not a keeper.
function ParseSsdpResponse(raw as String) as String
    if raw = invalid then return ""
    if raw = "" then return ""
    if Left(raw, 4) <> "HTTP" then return ""
    if Instr(1, raw, " 200") = 0 then return ""

    location = ""
    isPhlix = false
    lines = raw.Split(Chr(10))
    for each line in lines
        value = line
        if Len(value) > 0 and Mid(value, Len(value), 1) = Chr(13) then
            value = Left(value, Len(value) - 1)
        end if
        ' Header lines are "Name: value". A datagram read to its length can
        ' carry trailing NUL bytes from the sender's padding - such lines
        ' match no prefix and are inert. AA member lookup is
        ' case-insensitive; the Left/UCase prefix tests keep header casing
        ' irrelevant by design.
        upper = UCase(Left(value, 9))
        if upper = "LOCATION:" then
            location = Mid(value, 10).Trim()
        else if UCase(Left(value, 4)) = "USN:" then
            if Instr(1, UCase(value), "PHLIXSERVER") > 0 then isPhlix = true
        else if UCase(Left(value, 7)) = "SERVER:" then
            if Instr(1, value, "Phlix/") > 0 then isPhlix = true
        end if
    end for

    if not isPhlix then return ""
    return ExtractServerOrigin(location)
end function

' True when a parsed /health JSON body indicates a reachable Phlix host. The body
' is {status:"ok", service, version, ...}; we accept it when status="ok" OR a
' "version" key is present. NEVER compare a possibly-numeric field with "" - read
' status (a string, safe to compare) and only DoesExist("version"). Guards invalid.
' @param json Object - the parsed /health body (may be invalid)
' @return Boolean - true when the body looks like a healthy Phlix host
function HealthOk(json as Object) as Boolean
    if json = invalid then return false
    if type(json) <> "roAssociativeArray" then return false

    if json.DoesExist("status") and json.status <> invalid then
        s = json.status
        if (type(s) = "String" or type(s) = "roString") and s = "ok" then return true
    end if

    if json.DoesExist("version") then return true

    return false
end function

' Get file extension from URL
function GetFileExtension(url as String) as String
    parts = url.Split("/")
    if parts.Count() > 0 then
        filename = parts[parts.Count() - 1]
        extParts = filename.Split(".")
        if extParts.Count() > 1 then
            return LCase(extParts[extParts.Count() - 1])
        end if
    end if
    return ""
end function

' Determine the Roku StreamFormat token for a container extension.
' RT-105 [review roku__crossfe M2]: the old mapping emitted "mov", "mpegts"
' and "webm" - none of which are accepted values in Roku's content-metadata
' StreamFormat table (valid: mp4, hls, dash, ism, mkv/mka/mks, mp3, wma) - and
' its trailing `return "mp4"` claimed mp4 for EVERYTHING. The invalid branches
' were masked by the derivation never seeing an extension (signer-minted
' /media/{uuid}/stream URLs contain no dot); both layers are wrong together.
' Contract now: a known container answers its platform-valid token (mov/m4v
' fold onto mp4 per the table's note); ts/mpegts, webm, and every unknown or
' empty input answer "" - the honest "no observable container" sentinel.
' Callers MUST treat "" as "claim nothing": PlayerScene routes it straight to
' the transcode lane rather than probing a fabricated mp4.
function GetStreamFormat(container as String) as String
    ext = LCase(container)
    if ext = "mp4" or ext = "m4v" or ext = "mov" then
        return "mp4"
    else if ext = "mkv" or ext = "mka" or ext = "mks" then
        return "mkv"
    else if ext = "m3u8" then
        return "hls"
    else if ext = "mp3" then
        return "mp3"
    else if ext = "wma" then
        return "wma"
    end if
    return ""
end function

' Escape string for display
function EscapeString(str as String) as String
    return str.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("""", "&quot;")
end function

' Unescape string from display
function UnescapeString(str as String) as String
    return str.Replace("&lt;", "<").Replace("&gt;", ">").Replace("&quot;", """").Replace("&amp;", "&")
end function

' Create content node with poster info
function CreatePosterContent(item as Object) as Object
    content = CreateObject("roSGNode", "ContentNode")

    if item.DoesExist("id") then content.id = item.id
    if item.DoesExist("name") then content.Title = item.name
    if item.DoesExist("sortName") then content.ShortDescriptionLine1 = item.sortName
    if item.DoesExist("overview") then content.Description = item.overview
    if item.DoesExist("thumb") then content.HDPosterUrl = item.thumb
    if item.DoesExist("parentThumb") then content.HDPosterUrl = item.parentThumb
    if item.DoesExist("type") then content.Type = item.type

    return content
end function

' R5: Lazy image loader — defers HDPosterUrl assignment until item is near visible area
' Usage: Call SetLazyPosterUrl(contentNode, item, "poster_url") after creating each content item
' This stores the URL in a _lazyPosterUrl field instead of setting HDPosterUrl directly
sub SetLazyPosterUrl(contentNode as Object, item as Object, urlField as String)
    ' Store the URL for later instead of loading immediately
    if item.DoesExist(urlField) and item.lookup(urlField) <> invalid and item.lookup(urlField) <> "" then
        contentNode._lazyPosterUrl = item.lookup(urlField)
    else
        contentNode._lazyPosterUrl = "pkg:/images/placeholder.png"
    end if
    ' Don't set HDPosterUrl yet — wait until item is actually visible
end sub

' R5: Activate lazy image — call when item comes into visible range
' Call SetLazyPosterUrl first, then call this to actually load the image
sub ActivateLazyPosterUrl(contentNode as Object)
    if contentNode <> invalid and type(contentNode) = "roSGNode" then
        if contentNode.doesExist("_lazyPosterUrl") then
            url = contentNode.lookup("_lazyPosterUrl")
            if url <> invalid and url <> "" then
                contentNode.HDPosterUrl = url
            end if
        end if
    end if
end sub

' R5: Clear lazy image — call when item goes out of visible range to free memory
sub ClearLazyPosterUrl(contentNode as Object)
    if contentNode <> invalid and type(contentNode) = "roSGNode" then
        contentNode.HDPosterUrl = ""
    end if
end sub

' Generate random ID
function GenerateRandomId() as String
    return str(Rnd(999999999)).trim() + "-" + str(Rnd(999999999)).trim()
end function

' Join an array of strings with a separator (BrightScript roArray has no join).
' @param parts Object - array of String values
' @param sep String - the separator
' @return String - the joined result
function JoinStrings(parts as Object, sep as String) as String
    result = ""
    if parts = invalid then return result
    for i = 0 to parts.Count() - 1
        if i > 0 then result = result + sep
        result = result + parts[i]
    end for
    return result
end function

' Convert a byte (0-255) to a 2-character uppercase hex string.
' Used by UrlEncode for percent-encoding.
' @param n Integer - byte value (0-255)
' @return String - 2-character hex string (e.g., "20" for space)
function ByteToHex(n as Integer) as String
    hexDigits = "0123456789ABCDEF"
    hi = (n \ 16) mod 16
    lo = n mod 16
    return Mid(hexDigits, hi + 1, 1) + Mid(hexDigits, lo + 1, 1)
end function

' [W13L3 RT-041, review roku__secnet #5] The repo's UTF-8 law in ONE place:
' a Unicode code point -> its 1..4 UTF-8 byte values (roArray of Integers).
' Mid()/Asc() yield code points (the platform string law this repo's
' UrlEncode has always relied on — its 65536+ arm presumes values beyond a
' UTF-16 unit), so supplementary code points take the 4-byte form here.
' Consumers: UrlEncode percent-escapes these bytes; SyncPlayPasswordHash
' pushes them into the roByteArray the SPEC §4 digest runs over. A
' code point < 128 yields the single identity byte (ASCII is its own UTF-8).
' @param code Integer - the Unicode code point
' @return Object - roArray of Integer byte values (always 1..4 entries)
function Utf8BytesForCodePoint(code as Integer) as Object
    bytes = []
    if code < 128 then
        ' 1-byte: 0xxxxxxx (identity)
        bytes.Push(code)
    else if code < 2048 then
        ' 2-byte UTF-8: 110xxxxx 10xxxxxx
        bytes.Push(192 + (code \ 64))
        bytes.Push(128 + (code mod 64))
    else if code < 65536 then
        ' 3-byte UTF-8: 1110xxxx 10xxxxxx 10xxxxxx
        bytes.Push(224 + (code \ 4096))
        bytes.Push(128 + ((code \ 64) mod 64))
        bytes.Push(128 + (code mod 64))
    else
        ' 4-byte UTF-8: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
        bytes.Push(240 + (code \ 262144))
        bytes.Push(128 + ((code \ 4096) mod 64))
        bytes.Push(128 + ((code \ 64) mod 64))
        bytes.Push(128 + (code mod 64))
    end if
    return bytes
end function

' [W14L1 fold-in RT-041, review roku__secnet #5 via REVIEW-w13L3roku Minor 1]
' The whole-string leg of the UTF-8 law: every character's code point through
' Utf8BytesForCodePoint, concatenated - a pure String -> roArray(Integer) fold
' (invalid/empty give an empty array). SyncPlayPasswordHash pushes exactly
' these bytes into the roByteArray the SPEC §4 digest runs over, and UrlEncode
' percent-escapes the same law character by character. Before this extraction
' the join-password digest carried the loop inline: M-041A (an input-encoding
' regression - e.g. a raw FromAsciiString-style byte loop) shipped HEADLESS
' GREEN at w13L3 because the roEVPDigest leg stops every headless call short
' of the loop, leaving the byte law with zero automated conviction. The
' extraction makes the byte sequence itself headless-testable (a truth-vector
' pin in Utilities2) and gives the gate a call-site law to pin: the digest
' body must route through this function (Check 99 R2).
' @param text String - the raw string (invalid tolerated -> empty array)
' @return Object - roArray of Integer UTF-8 byte values, in order
function Utf8BytesFromString(text as String) as Object
    bytes = []
    if text = invalid or text = "" then return bytes
    for i = 1 to Len(text)
        for each b in Utf8BytesForCodePoint(Asc(Mid(text, i, 1)))
            bytes.Push(b)
        end for
    end for
    return bytes
end function

' URL-encode a string (percent-encode according to RFC 3986).
' roUrlTransfer.Escape() does not exist in the Roku SDK (verified against ROKU_SDK_12+).
' RFC 3986 unreserved characters: A-Z a-z 0-9 - . _ ~
' Everything else gets percent-encoded. % is encoded first to prevent double-encoding.
' Non-ASCII characters are encoded as UTF-8 bytes, then each byte is percent-encoded.
' Lives in Utilities so any component that includes Utilities + ApiClient can resolve it.
' @param str String - the raw value
' @return String - the encoded value
function UrlEncode(str as String) as String
    result = ""
    if str = invalid then return result

    for i = 1 to Len(str)
        c = Mid(str, i, 1)
        code = Asc(c)

        ' RFC 3986 unreserved characters pass through unchanged:
        ' A-Z (65-90), a-z (97-122), 0-9 (48-57), - (45), . (46), _ (95), ~ (126)
        if (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code = 45 or code = 46 or code = 95 or code = 126 then
            result = result + c
        else
            ' Encode % first to prevent double-encoding of other percent-encoded values
            if code = 37 then
                ' Percent sign - encode first
                result = result + "%25"
            else if code >= 128 then
                ' Non-ASCII: encode as UTF-8 bytes, then percent-encode each
                ' byte. The byte math is the shared Utf8BytesForCodePoint law
                ' [W13L3 RT-041] — one expression of UTF-8 for the whole repo.
                for each b in Utf8BytesForCodePoint(code)
                    result = result + "%" + ByteToHex(b)
                end for
            else
                ' All other characters (including space, &, =, ?, /, :, #, [, ], etc.)
                result = result + "%" + ByteToHex(code)
            end if
        end if
    end for
    return result
end function

' Convert seconds (Float) to 100ns ticks (LongInteger). Double math (52-bit mantissa) keeps
' large values exact; the LongInteger return coerces the truncation. Float*1e7 would lose
' precision AND a 32-bit Int() overflows past ~214s.
function SecondsToTicks(seconds as Double) as LongInteger
    return seconds * 10000000.0
end function

' Show a SceneGraph Dialog node attached to the given scene.
' Supports two shapes:
'   - Info dialog: one button ("OK") — just dismisses.
'   - Retry dialog: two buttons ("Retry", "Cancel") — callback is called with
'     button index (0 = Retry, 1 = Cancel) so the caller can retry the failed op.
' @param scene Object - the scene to attach the dialog to (m.top of the scene)
' @param title String - dialog title
' @param message String - dialog message
' @param buttons Object - optional array of button labels (default ["OK"])
' @param callback Function - optional(buttonIndex as Integer) callback for retry dialogs
sub ShowErrorDialog(scene as Object, title as String, message as String, buttons = ["OK"] as Object, callback = invalid as Function)
    if scene = invalid then return
    if buttons = invalid or (type(buttons) = "roArray" and buttons.Count() = 0) then buttons = ["OK"]

    ' Track the currently-focused node so we can restore it when the dialog closes.
    ' R3.1: Without this, focus is lost on dismiss → remote becomes unresponsive.
    previousFocus = invalid
    for each child in scene.GetChildren(-1, 0)
        if child.IsInFocusChain() then
            previousFocus = child
            exit for
        end if
    end for

    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = title
    dialog.message = message
    dialog.buttons = buttons

    ' Store callback on the dialog node so observers can invoke it.
    if callback <> invalid then
        dialog.observeField("buttonSelected", "OnDialogButtonSelected")
        dialog.callback = callback
    end if

    ' R3.1: Store previous focus on the dialog for restoration on dismiss.
    dialog.previousFocus = previousFocus

    dialog.observeField("wasClosed", "OnDialogClosed")
    scene.dialog = dialog
end sub

' Observer handler for dialog buttonSelected — fires when user presses a button.
' Invokes the stored callback with the button index, then closes and restores focus.
sub OnDialogButtonSelected(event as Object)
    dialog = event.GetNode()
    index = event.GetData()
    if dialog.callback <> invalid then
        dialog.callback(index)
    end if
    dialog.Close = true
    ' R3.1: Restore focus to the previously-focused node if it's not already focused.
    if dialog.previousFocus <> invalid and not dialog.previousFocus.IsInFocusChain() then
        dialog.previousFocus.SetFocus(true)
    end if
end sub

' Observer handler for dialog wasClosed — fires when user dismisses via Back.
' Closes the dialog (if not already closing) and restores focus to the previous node.
sub OnDialogClosed(event as Object)
    dialog = event.GetNode()
    ' wasClosed fires after any button press too; guard to avoid double-close.
    if dialog.Close <> true then
        dialog.Close = true
    end if
    ' R3.1: Restore focus to the previously-focused node if it's not already focused.
    if dialog.previousFocus <> invalid and not dialog.previousFocus.IsInFocusChain() then
        dialog.previousFocus.SetFocus(true)
    end if
end sub

' Coerce a media-item's numeric sort key to an Integer, mapping invalid/missing
' to a large sentinel so unsorted/null values sort LAST and deterministically.
' @param item Object - a media-item assocarray (may be invalid)
' @param key String - the assoc key to read (e.g. "season_number")
' @return Integer - the value, or 999999 when invalid/missing/non-numeric
function SortKeyValue(item as Object, key as String) as Integer
    if item = invalid then return 999999
    if not item.DoesExist(key) then return 999999
    value = item[key]
    if value = invalid then return 999999
    ' Coerce; non-numeric assoc values box to 0, which is acceptable for ints.
    return Int(value)
end function

' Non-mutating insertion sort of an array of media-item assocarrays by
' season_number then episode_number. Invalid/missing numbers sort last (sentinel
' 999999). N is small (seasons/episodes per parent), so O(n^2) insertion sort is
' clear, deterministic, and avoids roArray.SortBy's missing-key quirks. Returns a
' NEW array; the input is not modified.
' @param items Object - array of media-item assocarrays (may be invalid)
' @return Object - a new sorted array (empty array when input is invalid)
function SortByEpisodeOrder(items as Object) as Object
    if items = invalid then return []

    ' Build a sort-key array: { sortKey: number, item: assocarray }
    ' Key = season*100000 + episode so season takes precedence.
    decorated = []
    for each item in items
        s = SortKeyValue(item, "season_number")
        e = SortKeyValue(item, "episode_number")
        decorated.Push({ sortKey: s * 100000 + e, item: item })
    end for

    ' ArraySort is O(n log n) merge sort; sort by sortKey ascending.
    decorated.SortBy("sortKey", "asc")

    ' Extract the sorted items back out.
    result = []
    for each d in decorated
        result.Push(d.item)
    end for
    return result
end function

' Build a one-line caption for an episode list row. When episode_number is
' present: "E<n>. <episode_title or name>"; otherwise just the name. Guards every
' invalid/missing field.
' @param item Object - an episode media-item assocarray (may be invalid)
' @return String - the caption (empty string when item is invalid)
function EpisodeCaption(item as Object) as String
    if item = invalid then return ""

    title = ""
    if item.DoesExist("episode_title") and item.episode_title <> invalid and item.episode_title <> "" then
        title = item.episode_title
    else if item.DoesExist("name") and item.name <> invalid then
        title = item.name
    end if

    if item.DoesExist("episode_number") and item.episode_number <> invalid then
        return "E" + str(Int(item.episode_number)).trim() + ". " + title
    end if

    return title
end function

' Flatten a RAW album-track row (from /music/albums/{name}) into the flat shape
' the music UI consumes: {id,name,artist,track_number,disc_number,duration_secs}.
' The interesting fields live under metadata.* on raw rows; read top-level first,
' then metadata fallback. metadata may arrive as a non-assoc string, so only read
' its keys when it is an roAssociativeArray (mirrors HomeScene.ContinuePosterUrl).
' The raw row's top-level `id` IS the playable media_item id. Guards invalid.
' @param raw Object - a raw media-item row (may be invalid)
' @return Object - the flattened track assocarray (sentinel {} when raw invalid)
function NormalizeAlbumTrack(raw as Object) as Object
    track = { id: "", name: "", artist: "", track_number: 0, disc_number: 0, duration_secs: 0 }
    if raw = invalid then return track

    ' Pull the optional metadata sub-object (only when it parsed to an assoc).
    meta = invalid
    if raw.DoesExist("metadata") and raw.metadata <> invalid then
        if type(raw.metadata) = "roAssociativeArray" then meta = raw.metadata
    end if

    ' id is always top-level on the raw row.
    if raw.DoesExist("id") and raw.id <> invalid then track.id = raw.id

    ' name = metadata.title -> top-level name -> "".
    if meta <> invalid and meta.DoesExist("title") and meta.title <> invalid and meta.title <> "" then
        track.name = meta.title
    else if raw.DoesExist("name") and raw.name <> invalid then
        track.name = raw.name
    end if

    ' artist: top-level then metadata.
    if raw.DoesExist("artist") and raw.artist <> invalid then
        track.artist = raw.artist
    else if meta <> invalid and meta.DoesExist("artist") and meta.artist <> invalid then
        track.artist = meta.artist
    end if

    ' track_number / disc_number: top-level then metadata; default 0.
    if raw.DoesExist("track_number") and raw.track_number <> invalid then
        track.track_number = Int(raw.track_number)
    else if meta <> invalid and meta.DoesExist("track_number") and meta.track_number <> invalid then
        track.track_number = Int(meta.track_number)
    end if

    if raw.DoesExist("disc_number") and raw.disc_number <> invalid then
        track.disc_number = Int(raw.disc_number)
    else if meta <> invalid and meta.DoesExist("disc_number") and meta.disc_number <> invalid then
        track.disc_number = Int(meta.disc_number)
    end if

    ' duration_secs: top-level then metadata; default 0.
    if raw.DoesExist("duration_secs") and raw.duration_secs <> invalid then
        track.duration_secs = Int(raw.duration_secs)
    else if meta <> invalid and meta.DoesExist("duration_secs") and meta.duration_secs <> invalid then
        track.duration_secs = Int(meta.duration_secs)
    end if

    return track
end function

' Flatten a RAW collection-item row (from GET /collections/{id}) into the shape
' the grid + type-routing consume: {id,name,type,poster_url,overview,year}.
' Collection items are NOT MediaItemShaper-shaped: id/name/type are top-level but
' poster_url/overview/year live under metadata.* (mirrors NormalizeAlbumTrack /
' ContinuePosterUrl). metadata MAY arrive as a non-assoc string, so only read its
' keys when it is an roAssociativeArray. `type` stays top-level so series ->
' SeriesScene / season -> SeasonScene routing still works. Reads top-level first
' then metadata fallback (defensive; raw rows have these only under metadata).
' RT-092 lift law: id/name/type/overview pass through TextOrEmpty (real strings
' untouched; every other decoded shape answers the "" sentinel); year is gated
' with IsBoxedNumber and stored as the NATIVE member (numeric or invalid).
' Guards invalid AND malformed shape.
' @param raw Object - a raw collection-item row (may be invalid)
' @return Object - the normalized item (sentinel with empty strings when invalid)
function NormalizeCollectionItem(raw as Object) as Object
    item = { id: "", name: "", type: "", poster_url: "", overview: "", year: invalid }
    if raw = invalid then return item

    meta = invalid
    if raw.DoesExist("metadata") and raw.metadata <> invalid then
        if type(raw.metadata) = "roAssociativeArray" then meta = raw.metadata
    end if

    ' RT-092 [review roku__exploiter #1]: id/name/type cross into typed String
    ' fields downstream (ContentNode.Title/id, roSGLabel.text) and into the
    ' ShowSeries/ShowSeason String formals. The old `<> invalid` guard only
    ' screened invalid - a boxed number or assocarray from wire drift passed
    ' straight through and crashed the write. TextOrEmpty keeps byte-identical
    ' behavior for real strings and answers "" for every malformed shape.
    item.id = TextOrEmpty(raw.id)
    item.name = TextOrEmpty(raw.name)
    item.type = TextOrEmpty(raw.type)

    ' poster_url: top-level (defensive) then metadata.
    if raw.DoesExist("poster_url") and raw.poster_url <> invalid and raw.poster_url <> "" then
        item.poster_url = raw.poster_url
    else if meta <> invalid and meta.DoesExist("poster_url") and meta.poster_url <> invalid and meta.poster_url <> "" then
        item.poster_url = meta.poster_url
    end if

    ' overview: top-level then metadata. RT-092: same lift law as id/name/type —
    ' item.overview crosses into Description/text String fields downstream, and
    ' the old `<> invalid` guard waved a boxed number straight through to the
    ' write that crashes.
    overviewText = TextOrEmpty(raw.overview)
    if overviewText = "" and meta <> invalid then overviewText = TextOrEmpty(meta.overview)
    item.overview = overviewText

    ' year: top-level then metadata. RT-092 same family — item.year reaches
    ' Int(item.year) in CollectionScene's grid builder, and Int() on a boxed
    ' String/AssocArray raises exactly the class this choke exists to stop.
    ' Guard the shape then store the NATIVE member (a lift helper would re-wrap
    ' it into an object brs cannot compare); non-numeric stays invalid, which
    ' is the declared "no year" sentinel.
    if raw.DoesExist("year") and IsBoxedNumber(raw.year) then
        item.year = raw.year
    else if meta <> invalid and meta.DoesExist("year") and IsBoxedNumber(meta.year) then
        item.year = meta.year
    end if

    return item
end function

' Non-mutating insertion sort of a (normalized) track array by disc_number then
' track_number. Invalid/missing numbers sort LAST (sentinel 999999) so unnumbered
' tracks sink to the end. Mirrors SortByEpisodeOrder. Returns a NEW array; the
' input is not modified. Guards non-array input -> [].
' @param tracks Object - array of normalized track assocarrays (may be invalid)
' @return Object - a new sorted array (empty array when input is invalid)
function SortByTrackOrder(tracks as Object) as Object
    if tracks = invalid then return []

    ' Build a sort-key array: { sortKey: number, track: assocarray }
    ' Key = disc*100000 + track so disc takes precedence.
    ' SortKeyValue returns 999999 for invalid/missing, which sorts last.
    decorated = []
    for each track in tracks
        d = SortKeyValue(track, "disc_number")
        t = SortKeyValue(track, "track_number")
        if d = 0 then d = 999999
        if t = 0 then t = 999999
        decorated.Push({ sortKey: d * 100000 + t, track: track })
    end for

    ' ArraySort is O(n log n) merge sort; sort by sortKey ascending.
    decorated.SortBy("sortKey", "asc")

    ' Extract the sorted tracks back out.
    result = []
    for each d in decorated
        result.Push(d.track)
    end for
    return result
end function

' Build a one-line caption for a track list row: "<track_number>. <name>" when
' track_number>0 else just <name>; appends "  (mm:ss)" via FormatTime when
' duration_secs>0. Guards invalid.
' @param track Object - a normalized track assocarray (may be invalid)
' @return String - the caption (empty string when track is invalid)
function TrackCaption(track as Object) as String
    if track = invalid then return ""

    name = ""
    if track.DoesExist("name") and track.name <> invalid then name = track.name

    caption = name
    if track.DoesExist("track_number") and track.track_number <> invalid and Int(track.track_number) > 0 then
        caption = str(Int(track.track_number)).trim() + ". " + name
    end if

    if track.DoesExist("duration_secs") and track.duration_secs <> invalid and Int(track.duration_secs) > 0 then
        caption = caption + "  (" + FormatTime(track.duration_secs) + ")"
    end if

    return caption
end function

' Build a one-line caption for an album list row: "<name> — <artist>" plus
' " (<year>)" when a year is present. Guards every invalid/missing field.
' @param album Object - an album assocarray (may be invalid)
' @return String - the caption (empty string when album is invalid)
function AlbumCaption(album as Object) as String
    if album = invalid then return ""

    name = ""
    if album.DoesExist("name") and album.name <> invalid then name = album.name

    caption = name
    if album.DoesExist("artist") and album.artist <> invalid and album.artist <> "" then
        caption = caption + " — " + album.artist
    end if

    if album.DoesExist("year") and album.year <> invalid then
        yearStr = str(Int(album.year)).trim()
        if yearStr <> "0" then caption = caption + " (" + yearStr + ")"
    end if

    return caption
end function

' Build the label for a photo album: its date ("YYYY-MM-DD"), mapping the
' server sentinel "Unknown" (and invalid/empty) -> "Undated". Guards invalid.
' @param album Object - a photo-album assocarray (may be invalid)
' @return String - the album date label, or "Undated"
function PhotoAlbumCaption(album as Object) as String
    if album = invalid then return Translate("utilities_photo_album_undated")

    date = ""
    if album.DoesExist("date") and album.date <> invalid then date = album.date

    if date = "" or date = "Unknown" then return Translate("utilities_photo_album_undated")

    return date
end function

' Build a multi-line EXIF summary (Chr(10)-joined) from whichever metadata fields
' are present, skipping absent fields so there are no empty/"invalid" lines.
' Lines (each emitted ONLY when its source is present):
'   Camera     = camera_make + " " + camera_model (emit if either present)
'   Lens       = lens
'   Settings   = aperture, shutter_speed, focal_length, "ISO "+iso joined by "  •  "
'   Dimensions = width + " × " + height (only when BOTH are valid Ints > 0)
'   Date       = date_taken_formatted (fallback date_taken_year)
'   GPS        = gps_display (already "lat, lng" formatted)
' metadata MAY arrive as a non-assoc, so only read keys when it is an
' roAssociativeArray (mirrors NormalizeAlbumTrack / ContinuePosterUrl). Pure; NO
' node access. Returns "" when exif is invalid/non-assoc/empty (caller shows a
' "No photo info" placeholder).
' @param exif Object - a photo metadata assocarray (may be invalid)
' @return String - the multi-line summary (empty string when nothing present)
function FormatExifSummary(exif as Object) as String
    if exif = invalid then return ""
    if type(exif) <> "roAssociativeArray" then return ""

    lines = []

    ' Camera: camera_make + camera_model (emit if either present).
    make = ""
    if exif.DoesExist("camera_make") and exif.camera_make <> invalid and exif.camera_make <> "" then
        make = exif.camera_make
    end if
    model = ""
    if exif.DoesExist("camera_model") and exif.camera_model <> invalid and exif.camera_model <> "" then
        model = exif.camera_model
    end if
    if make <> "" or model <> "" then
        camera = make
        if make <> "" and model <> "" then
            camera = make + " " + model
        else if model <> "" then
            camera = model
        end if
        lines.Push(camera)
    end if

    ' Lens.
    if exif.DoesExist("lens") and exif.lens <> invalid and exif.lens <> "" then
        lines.Push(exif.lens)
    end if

    ' Settings: aperture • shutter_speed • focal_length • "ISO "+iso.
    settings = []
    if exif.DoesExist("aperture") and exif.aperture <> invalid and exif.aperture <> "" then
        settings.Push(exif.aperture)
    end if
    if exif.DoesExist("shutter_speed") and exif.shutter_speed <> invalid and exif.shutter_speed <> "" then
        settings.Push(exif.shutter_speed)
    end if
    if exif.DoesExist("focal_length") and exif.focal_length <> invalid and exif.focal_length <> "" then
        settings.Push(exif.focal_length)
    end if
    if exif.DoesExist("iso") and exif.iso <> invalid then
        isoVal = Int(exif.iso)
        if isoVal > 0 then settings.Push(Translate("utilities_iso_prefix") + str(isoVal).trim())
    end if
    if settings.Count() > 0 then
        lines.Push(JoinStrings(settings, "  •  "))
    end if

    ' Dimensions: width × height (emit only when BOTH are valid Ints > 0).
    if exif.DoesExist("width") and exif.width <> invalid and exif.DoesExist("height") and exif.height <> invalid then
        w = Int(exif.width)
        h = Int(exif.height)
        if w > 0 and h > 0 then
            lines.Push(str(w).trim() + " × " + str(h).trim())
        end if
    end if

    ' Date: date_taken_formatted -> date_taken_year. The year may arrive as a
    ' String ("YYYY") or an Integer, so branch on type — comparing an Integer
    ' with "" raises a runtime type-mismatch (would crash the viewer render).
    if exif.DoesExist("date_taken_formatted") and exif.date_taken_formatted <> invalid and exif.date_taken_formatted <> "" then
        lines.Push(exif.date_taken_formatted)
    else if exif.DoesExist("date_taken_year") and exif.date_taken_year <> invalid then
        yearValue = exif.date_taken_year
        if type(yearValue) = "String" or type(yearValue) = "roString" then
            if yearValue <> "" then lines.Push(yearValue)
        else
            yearInt = Int(yearValue)
            if yearInt > 0 then lines.Push(str(yearInt).trim())
        end if
    end if

    ' GPS: gps_display (already "lat, lng" formatted).
    if exif.DoesExist("gps_display") and exif.gps_display <> invalid and exif.gps_display <> "" then
        lines.Push(exif.gps_display)
    end if

    if lines.Count() = 0 then return ""

    return JoinStrings(lines, Chr(10))
end function

' ===========================================
' M-ROKU-12 (review roku__exploiter M1): HOSTILE-INPUT LAW FOR WIRE TEXT
'
' A server body is attacker-influenced data, not trusted text. The wire
' contract says {error: string} / {message: string}, but a hostile server
' (or, on http://, any LAN injector) can answer {"error":{"code":1}} or
' {"error":123} instead. BrightScript then raises a runtime type mismatch
' the FIRST time that value meets a String operation - "=" / "<>" against
' "", lcase/instr/Left/Trim, string concatenation, or a non-String value
' passed into an `as String` parameter/sink. On scenes that runs on the
' render thread: the channel dies mid-login. On tasks it bricks the task.
'
' LAW: every server-controlled value (result.data.*, env.error, resp.error,
' body.message ...) must pass through SafeErrorMessage() BEFORE any
' comparison, concatenation, or typed sink. Non-String values are a
' contract violation and degrade to the caller's typed fallback - they are
' NEVER stringified or partially rendered. This mirrors the estate
' hostile-input posture (parse-don't-validate at the boundary, fail to the
' honest generic) and the console WS-ingest sweep precedent.
' ===========================================

' Display cap for wire-sourced text (CHECK43 pins the literal). Roku Labels
' are single-pane chrome: a multi-kilobyte "error" is hostile noise, not
' information; truncating keeps the dialog honest and bounded.
function WireErrorMessageMax() as Integer
    return 300
end function

' Remove ASCII control characters (codes < 32 plus 127) from text.
' Roku renders plain text - there is no ANSI escape class here - but
' control bytes inside a Label string are display garbage (CR/LF break the
' single-line chrome, NUL truncates silently on some firmware), so wire
' text is normalized BEFORE length-capping is trusted. O(n) over an
' already-cap-bounded string.
function StripWireControlChars(text as String) as String
    out = ""
    for i = 1 to Len(text)
        code = Asc(Mid(text, i, 1))
        if code >= 32 and code <> 127 then
            out = out + Mid(text, i, 1)
        end if
    end for
    return out
end function

' THE wire-text guard: returns value as a safe, displayable String, or
' fallbackMessage when value is not a non-empty String after normalization.
' Order is deliberate: type-guard first (never touch non-String), then
' length-cap BEFORE the O(n) strip loop (a 10MB hostile string must not
' cost 10M iterations), then control-strip, then trim, then emptiness.
' @param value Object - anything read off the wire (typed Object on purpose:
'        a `as String` parameter would itself raise before the guard runs)
' @param fallbackMessage String - generic text for the non-String case
' @return String - never invalid, never non-String, never > WireErrorMessageMax()
function SafeErrorMessage(value as Object, fallbackMessage as String) as String
    t = type(value)
    if t <> "roString" and t <> "String" then return fallbackMessage

    text = value
    maxLen = WireErrorMessageMax()
    if Len(text) > maxLen then
        text = Left(text, maxLen - 1) + "…"
    end if
    text = StripWireControlChars(text).Trim()

    if text = "" then return fallbackMessage
    return text
end function

' R3.2: Get user-friendly error message, falling back to generic message for HTTP codes.
' M-ROKU-12: the parameter is deliberately Object-typed now - callers may hand
' it a raw wire value, and a non-String reaching the legacy `apiError = ""`
' compare was itself part of the M1 crash class. Everything below operates on
' the SafeErrorMessage-normalized string.
function GetErrorMessage(apiError as Object) as String
    safeError = SafeErrorMessage(apiError, "")
    if safeError = "" then return Translate("utilities_err_generic")
    if left(safeError, 5) = "http_" then
        ' Generic HTTP error codes - use friendly messages
        code = right(safeError, len(safeError) - 5)
        if code = "401" then return Translate("utilities_err_unauthorized")
        if code = "403" then return Translate("utilities_err_forbidden")
        if code = "404" then return Translate("utilities_err_not_found")
        if code = "500" then return Translate("utilities_err_server")
        if code = "502" or code = "503" then return Translate("utilities_err_unavailable")
        return Translate("utilities_err_generic")
    end if
    ' M-ROKU-03 (review roku__webux): the former default arm echoed the raw
    ' wire string straight into spoken dialogs ("if len(safeError) > 0 then
    ' return safeError"). Server prose is not user copy. Transport-reason
    ' codes (the connect buckets minted client-side) get their cataloged
    ' friendly translation; anything else is printed for diagnostics and
    ' replaced by the generic caption.
    if len(safeError) > 0 then
        if IsTransportReason(safeError) then return TranslateTransportReason(safeError)
        ' MN-22: even the capped diagnostic keeps content out of the log.
        print "GetErrorMessage suppressed wire detail (" + Str(Len(safeError)).Trim() + " chars)"
    end if
    return Translate("utilities_err_generic")
end function

' ===========================================
' M-ROKU-13 (review roku__exploiter M2): CANONICAL CONTENT-ID SHAPE GUARD
'
' A mediaId reaching the play machinery is UNTRUSTED input: it arrives from a
' hub-relay WS frame over a PLAINTEXT socket (components/HubCommandTask.brs —
' roStreamSocket carries no TLS, so a hostile hub OR any LAN injector can push
' {type:"pending_command",command:"play_media",media_id:"..."}) and from ECP /
' Roku-Search deep-link launch args (source/main.brs). Before this guard the
' relay path checked only invalid/"" and the deep-link path only rejected "&"
' plus non-printables — so "/ ? = # ." and spaces survived into ApiClient's
' "/media/" + itemId raw concatenation: the TV then issues the victim's
' Bearer-authenticated request against an attacker-shaped path.
'
' LAW: every contentId/mediaId that may reach a path interpolation, a fetch,
' or Play MUST pass IsSafeContentId() at its entry and at the play choke
' (components/PhlixApp.brs ProcessDeepLink). The server's own ids are UUIDs
' (CHAR(36)); nothing legitimate needs the rejected bytes, so the policy is a
' pure allowlist — no escaping, no encoding guesses. This mirrors the estate
' parse-don't-validate posture and the M-ROKU-12 guard-family idiom.
' ===========================================

' Length cap for a content id (CHECK45 pins the literal). Roku's deep-link
' contract allows up to 255 chars; the length gate runs BEFORE the per-byte
' allowlist loop so a megabyte hostile string cannot cost megabyte iterations.
function ContentIdMaxLen() as Integer
    return 255
end function

' The canonical content-id guard. Returns true only when contentId is a
' String whose TRIMMED form is 1..ContentIdMaxLen() bytes of [A-Za-z0-9_-] —
' exactly the character space server item ids (UUIDs) and every catalogued
' partner id occupy. '/' '?' '#' '&' '=' '%' space ':' and all control/high
' bytes are rejected, so a passing value is safe to embed in a URL path
' segment verbatim.
' CONTRACT: the value is validated in its trimmed form; call sites must use
' the Trim()-ed value for any request built from a passing id (the play choke
' does). A non-String (hostile JSON shape: number, AA, list) is a contract
' violation and returns false — never stringified.
' @param contentId Dynamic - the raw id from a WS frame or launch arg
' @return Boolean - true only when the id is safe for a path segment
function IsSafeContentId(contentId as Dynamic) as Boolean
    if contentId = invalid then return false
    t = type(contentId)
    if t <> "roString" and t <> "String" then return false

    trimmed = contentId.Trim()
    if trimmed = "" then return false

    maxLen = ContentIdMaxLen()
    if Len(trimmed) > maxLen then return false

    for i = 1 to Len(trimmed)
        c = Asc(Mid(trimmed, i, 1))
        ' [0-9A-Za-z_-] only: 45 '-', 48-57 '0'-'9', 65-90 'A'-'Z',
        ' 95 '_', 97-122 'a'-'z'. Anything else (incl. every URL delimiter)
        ' fails the shape law. (Single line: BrightScript has no `_`
        ' continuation operator — bsc parses it as an identifier.)
        ok = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c = 45 or c = 95
        if not ok then return false
    end for
    return true
end function

' MN-22 (review roku__secnet): bounded SHAPE test for wire error codes.
' Log lines may echo text that passes this gate - anything longer than 64
' chars or carrying a character outside the snake-case code alphabet is
' message-sized payload and gets a count, never content (SyncPlayTask's
' error arm shares this predicate with the GetErrorMessage detail sink).
function IsErrorCodeToken(value as String) as Boolean
    if Len(value) < 1 or Len(value) > 64 then return false
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"
    for i = 0 to Len(value) - 1
        if InStr(allowed, Mid(value, i + 1, 1)) = 0 then return false
    end for
    return true
end function

' True when the user assocarray is flagged admin. is_admin arrives from JSON as a
' TINYINT Integer (1/0) but may be a Boolean; both coerce via Int() (Int(true)=1,
' Int(false)=0). Only Int()-coerce numeric/boolean types — Int() on a String can
' raise, so guard the type first. Guards invalid/missing -> false.
' @param user Object - a user assocarray (may be invalid)
' @return Boolean - true only when is_admin is truthy (1 / true)
function IsAdminUser(user as Object) as Boolean
    if user = invalid then return false
    if not user.DoesExist("is_admin") then return false
    v = user.is_admin
    if v = invalid then return false

    t = type(v)
    if t = "Boolean" or t = "roBoolean" then
        return v
    else if t = "Integer" or t = "roInt" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then
        return (Int(v) = 1)
    end if

    return false
end function

' Truthy test for a bool-or-numeric (TINYINT) flag under container[key]. Mirrors
' IsAdminUser's type-guard (a numeric <> "" compare CRASHES). Returns false when
' missing/invalid/non-bool-non-numeric.
' @param container Object - assocarray that may hold the flag (may be invalid)
' @param key String - the flag key
' @return Boolean - true only when container[key] is truthy (1 / true)
function IsTruthyFlag(container as Object, key as String) as Boolean
    if container = invalid then return false
    if type(container) <> "roAssociativeArray" then return false
    if not container.DoesExist(key) then return false
    v = container[key]
    if v = invalid then return false
    t = type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    if t = "Integer" or t = "roInt" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then return (Int(v) = 1)
    return false
end function

' ============================================================
' RT-092 [review roku__exploiter #1] — boxed-type lifts
' ============================================================
' DecodeJson hands back native boxed values: an unquoted JSON number arrives
' as roInteger/roLongInteger/roDouble (the headless brs interpreter reports
' the intrinsic names Integer/LongInteger/Double for the same shape), a quoted
' string as roString/String, a flag as roBoolean. A boxed number written into
' a typed String field (roSGLabel.text, ContentNode.Title), fed to the `+`
' operator, or used as an arithmetic operand CRASHES at runtime (Type
' Mismatch) — and the guards that let it through were always `<> invalid`
' checks, which never screened for the shape that actually slips. IsTruthyFlag
' above legislates the boolean/numeric compare side of the family;
' HomeScene.ContinueWatchPercent carries the exemplar numeric gate. These
' helpers generalize that exemplar: IsBoxedNumber is the shape predicate and
' TextOrEmpty is the String-field choke. Callers pair the predicate with the
' NATIVE member (guard `if IsBoxedNumber(x.field)` then read x.field directly)
' rather than a lift helper — a boxed return re-wraps the value into an object
' the headless brs interpreter refuses to compare to an integer literal, while
' a native member read straight off the assocarray survives arithmetic and
' ordered compares on both device and brs. Check 100 pins each cohort site by
' name.

' Type-set predicate: is this a boxed numeric (both ro* and intrinsic names)?
' @param value Dynamic - any decoded-wire shape (may be invalid)
' @return Boolean - true only for the numeric family
function IsBoxedNumber(value as Dynamic) as Boolean
    if value = invalid then return false
    t = type(value)
    return t = "Integer" or t = "roInt" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble"
end function

' Lift for a typed String field (roSGLabel.text, ContentNode.Title) or a
' plus-concat operand. A real string passes through untouched — good wire
' rows keep byte-identical behavior. Anything else (boxed number, Boolean,
' Array, AssocArray, invalid) becomes "": the field shows nothing, which is
' neither a crash nor a lie about the content.
' @param value Dynamic - the raw decoded field (may be invalid / any shape)
' @return String - the value when a String, else ""
function TextOrEmpty(value as Dynamic) as String
    if value = invalid then return ""
    t = type(value)
    if t = "String" or t = "roString" then return value
    return ""
end function

' The playable leaf members of the server's `media_items.type` ENUM - the types
' that actually resolve to a video/audio stream, so the only ones worth offering
' a Play button for.
'
' The full ENUM is:
'   movie, series, season, episode, track, music, album, artist, video, audio,
'   book, photo, audiobook
'
' Excluded on purpose: series/season/album/artist/music are CONTAINERS (they
' drill down to children, they have no stream of their own), and book/photo
' carry no video or audio track at all.
'
' Keep this in sync with the server-side allowlist if the ENUM ever grows - an
' unknown type is treated as NOT playable, so a new type silently loses its Play
' button until it is added here (safe default: no dead button).
' @return Object - roArray of canonical lowercase type strings
function PlayableTypes() as Object
    return ["movie", "episode", "video", "audio", "track", "audiobook"]
end function

' Is this a playable leaf type? Comparison is case-insensitive on a defensive
' copy - a non-string `itemType` would CRASH a bare `=` compare against a string
' (same type-guard rationale as IsTruthyFlag).
' @param itemType Dynamic - the raw item type (may be invalid / non-string)
' @return Boolean - true only for a member of PlayableTypes()
function IsPlayableType(itemType as Dynamic) as Boolean
    if itemType = invalid then return false
    t = type(itemType)
    if t <> "String" and t <> "roString" then return false

    needle = LCase(itemType.Trim())
    if needle = "" then return false

    for each candidate in PlayableTypes()
        if candidate = needle then return true
    end for
    return false
end function

' Convenience wrapper: is THIS item playable? Guards the container and the
' missing/invalid `type` key so callers stay one-liners.
' @param item Object - a media item assocarray (may be invalid)
' @return Boolean - true only when item.type is a playable leaf type
function IsPlayableItem(item as Object) as Boolean
    if item = invalid then return false
    if type(item) <> "roAssociativeArray" then return false
    if not item.DoesExist("type") then return false
    return IsPlayableType(item.type)
end function

' Map a content-rating int (0-6) to its label. Out-of-range -> "UNRATED".
' (0=G,1=PG,2=PG-13,3=R,4=NC-17,5=X,6=UNRATED.)
' @param n Integer - the rating int
' @return String - the label
function RatingLabel(n as Integer) as String
    if n < 0 or n > 6 then return Translate("utilities_rating_unrated")
    labels = ["utilities_rating_g", "utilities_rating_pg", "utilities_rating_pg13", "utilities_rating_r", "utilities_rating_nc17", "utilities_rating_x", "utilities_rating_unrated"]
    return Translate(labels[n])
end function

' ===========================================
' R7.12: i18n support (wiring completed in the key-resolution fix)
' Uses function-property pattern (like DeviceInfoData) to cache locale strings.
'
' KEY CONVENTION: the catalog nests BARE keys under sections
' ("settings": {"button_cancel": "Cancel"}), while every call site passes the
' FLATTENED, section-prefixed form ("settings_button_cancel"). The loader
' flattens "<section>_<bareKey>" -> value once at parse time so the dominant
' call-site style resolves with zero call-site churn. To add a string: nest the
' bare key under its section in locale/<tag>/strings.json and call
' Translate("<section>_<bareKey>").
' ===========================================

' Flatten a parsed catalog into a single-level "<section>_<bareKey>" lookup
' table. "_metadata" is skipped. String leaves only: a non-string value
' (array/object under a section) is SKIPPED, because Translate() returns
' `as String` and receiving a non-string would type-crash on device — the
' skip lets the documented raw-key fallback happen instead. Check 20 rejects
' such leaves in CI, so this guard is defense-in-depth, not an invitation.
' Pure: returns a new assocarray; raw is never mutated.
' @param raw Object|invalid - parsed catalog (sections of bare-key assocarrays)
' @return Object - roAssociativeArray of flattened keys to string values
function FlattenLocaleCatalog(raw as Object) as Object
    flat = CreateObject("roAssociativeArray")
    if raw = invalid then return flat
    for each section in raw.getKeysAsArray()
        if section <> "_metadata"
            sectionData = raw[section]
            if type(sectionData) = "roAssociativeArray"
                for each bareKey in sectionData.getKeysAsArray()
                    leaf = sectionData[bareKey]
                    if type(leaf) = "String" or type(leaf) = "roString"
                        flat[section + "_" + bareKey] = leaf
                    end if
                end for
            end if
        end if
    end for
    return flat
end function

' Build the bare-key lookup table for Translate()'s legacy step 2 (ROK-27):
' bareKey -> value, first section in raw.Keys() order wins, string leaves only,
' "_metadata" skipped. Precomputed once at load so a flat-table miss costs one
' hash lookup instead of a 32-section probe. Pure: raw is never mutated.
' @param raw Object|invalid - parsed catalog
' @return Object - roAssociativeArray of bare keys to string values
function BuildBareLocaleIndex(raw as Object) as Object
    bare = CreateObject("roAssociativeArray")
    if raw = invalid then return bare
    for each section in raw.Keys()
        if section <> "_metadata"
            sectionData = raw[section]
            if type(sectionData) = "roAssociativeArray"
                for each bareKey in sectionData.Keys()
                    leaf = sectionData[bareKey]
                    if (type(leaf) = "String" or type(leaf) = "roString") and not bare.doesExist(bareKey)
                        bare[bareKey] = leaf
                    end if
                end for
            end if
        end if
    end for
    return bare
end function

' Load locale strings from the bundled JSON catalog (called at app startup via
' AppContext.InitLocale; Translate retries lazily until it succeeds).
'
' MOUNT: direct pkg:/ read. The former "locale://..." URL requires the
' locale=/country_code= manifest keys that mount that protocol; this channel's
' manifest never declared them, so roFileSystem.Exists() was always false and
' the catalog silently never loaded. pkg:/ needs no manifest wiring. NOTE: the
' locale/ tree must stay in the package zip (see Makefile `package` target and
' bsconfig.json "files") or these paths do not exist on device.
'
' SELECTION: roAppInfo.GetCurrentLocale() picks locale/<tag>/strings.json when
' it exists and has content. Firmware varies between "en-US" and "en_US", so
' the tag is normalized to underscores before folder resolution. ReadAsciiFile
' returns "" for BOTH missing and empty files, so an empty/whitespace-only
' device catalog counts as missing. Fallback: the base locale en_US.
sub LoadLocaleStrings()
    ' Cached on the function object itself
    if LoadLocaleStrings._loaded = true then return

    base = "pkg:/locale/en_US/strings.json"
    data = invalid

    appInfo = CreateObject("roAppInfo")
    if appInfo <> invalid
        tag = appInfo.GetCurrentLocale()
        if tag <> invalid and tag.Trim() <> ""
            candidate = "pkg:/locale/" + tag.Trim().Replace("-", "_") + "/strings.json"
            if candidate <> base
                deviceData = ReadAsciiFile(candidate)
                if deviceData <> invalid and deviceData.Trim() <> "" then data = deviceData
            end if
        end if
    end if

    if data = invalid then data = ReadAsciiFile(base)
    if data = invalid or data.Trim() = "" then return
    raw = ParseJson(data)
    if raw = invalid then return

    LoadLocaleStrings._raw = raw
    LoadLocaleStrings._cache = FlattenLocaleCatalog(raw)
    LoadLocaleStrings._bare = BuildBareLocaleIndex(raw)
    LoadLocaleStrings._loaded = true
end sub

' Translate a string key using the loaded locale.
' Resolution order (first hit wins):
'   1. exact match in the flattened "<section>_<bareKey>" table — the call-site
'      convention every scene uses ("settings_button_cancel")
'   2. precomputed bare-key index (was a nested probe raw[section][key]) — legacy support for bare-key callers
'   3. return the key unchanged — graceful fallback that renders visibly
'      broken instead of silently wrong, and keeps Translate total.
' Only string-typed catalog values are returned; a non-string leaf (a shape
' Check 20 rejects in CI) falls through steps 1-2 to the raw-key return.
' @param key String - the translation key
' @return String - the translated string, or the key if not found
function Translate(key as String) as String
    if LoadLocaleStrings._loaded <> true then LoadLocaleStrings()
    if LoadLocaleStrings._loaded <> true then return key

    cache = LoadLocaleStrings._cache
    if cache <> invalid and cache.doesExist(key) then
        flatResult = cache.lookup(key)
        if flatResult <> invalid then return flatResult
    end if

    ' MN-18 / ROK-27: legacy bare-key callers resolve via the index precomputed
    ' at load (every shipped section, "_metadata" skipped, string leaves only,
    ' first section in Keys() order wins) - O(1) instead of a per-miss probe.
    bare = LoadLocaleStrings._bare
    if bare <> invalid and bare.doesExist(key) then
        bareResult = bare.lookup(key)
        if bareResult <> invalid then return bareResult
    end if
    return key
end function

' ===========================================
' TOKEN SUBSTITUTION (i18n {placeholder} family)
'
' Some catalog values carry {name} placeholders ("Logged in as: {email}").
' Concatenating the value at the call site renders the literal braces on the
' TV and hard-codes the token's POSITION in the English sentence - a locale
' that moves the value inside the phrase cannot express it. The law: every
' token-bearing catalog value is consumed through TranslateWithParams, which
' substitutes each placeholder BY NAME (position-free), generalizing the
' MembersCountText {count} Replace exemplar from PR #86/#87. Check 24 in
' scripts/verify-runtime.sh enforces the law (raw-Translate rejection, dead-
' copy detection, param-completeness against the catalog token set).
' ===========================================

' Pure token-substitution core: replace every "{name}" in TEXT with the
' rendered value of PARAMS[name]. Total by construction:
'   - unknown tokens (name not in TEXT) are simply no-ops
'   - tokens whose value has no display form (invalid, arrays, objects) stay
'     visible in the output - the same fail-loud brace rendering as a missing
'     key, never a silently erased slot
'   - invalid/non-associative-array params return TEXT unchanged
' No catalog, no globals, no mutation: same inputs, same output.
' @param text String - the (already localized) line carrying {name} tokens
' @param params Object - roAssociativeArray of token name -> value
' @return String - TEXT with every renderable named token substituted
function ApplyNamedTokens(text as String, params as Object) as String
    if params = invalid then return text
    if type(params) <> "roAssociativeArray" then return text
    result = text
    for each token in params
        rendered = TokenValueText(params[token])
        if rendered <> invalid then
            result = result.Replace("{" + token + "}", rendered)
        end if
    end for
    return result
end function

' Render one placeholder value to display text, or return invalid when the
' value has no sane text form (caller then leaves the token visible).
' Strings pass through; booleans render "true"/"false"; integers and floats
' render sign-free via the repo's str().trim() idiom; anything else is
' rejected as invalid.
' @param value - the raw parameter value (dynamic by law: see the body note)
' @return Object - String when renderable, invalid otherwise
function TokenValueText(value) as Object
    ' Contract (tests/unit/TranslateWithParams.test.brs pins the whole table):
    ' strings pass through, booleans render true/false, numerics render
    ' sign-free via the str().trim() idiom, and everything else — invalid,
    ' associative arrays, lists — is REJECTED with invalid so
    ' ApplyNamedTokens leaves the token visible (fail-loud) instead of
    ' swallowing it or crashing the render thread.
    '
    ' The parameter is DYNAMIC (untyped) deliberately: brs 0.45 boxes a
    ' Boolean passed into an 'as Object' formal into a wrapper whose if-context
    ' truthiness is false for BOTH true and false (measured: tv5(true) and
    ' tv5(false) both took the else arm; same function untyped coerces
    ' correctly). On the device 'as Object' and dynamic both accept any value,
    ' so untyping is behavior-neutral on hardware and the only shape this
    ' interpreter can evaluate honestly.
    if value = invalid then return invalid
    t = type(value)
    if t = "String" or t = "roString" then return value
    ' The boxed names mirror the unboxed device forms (a value stored in an
    ' associative-array slot can surface either shape depending on runtime).
    if t = "Boolean" or t = "roBoolean" then
        if value then return "true"
        return "false"
    end if
    if t = "Integer" or t = "roInt" or t = "LongInteger" or t = "roLongInt" then return str(value).trim()
    if t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then return str(value).trim()
    return invalid
end function

' Translate KEY, then substitute its {name} tokens position-free from PARAMS.
' The single consumption path for every token-bearing catalog value (law above
' and Check 24). Degradation is total: invalid params behave like plain
' Translate(key), so no call site can crash on a missing dictionary.
' @param key String - the translation key
' @param params Object - roAssociativeArray of token name -> value
' @return String - the localized line with every renderable token substituted
function TranslateWithParams(key as String, params as Object) as String
    return ApplyNamedTokens(Translate(key), params)
end function
' ===========================================
' CAPTIONS MODE VOCABULARY (R6.5 / settings dialog)
'
' Doctrine: localized text is NOT the wire value. roDeviceInfo.SetCaptionsMode()
' and Video.globalCaptionMode accept only the platform's fixed WIRE strings;
' feeding them translated button labels silently mis-sets captions on every
' non-English locale (the defect this family closes). WIRE values go to the OS,
' DISPLAY labels go to the eye - bound by index, never by string equality.
' PlayerScene renders its caption list FROM this function (review #91 retired
' its local copies of the array), so the wire bytes have exactly one source.
' ===========================================

' The four platform captions modes per
' https://developer.roku.com/dev/docs/video (globalCaptionMode field):
'   "On"            captions always on
'   "Off"           captions always off
'   "Instant replay" on only during instant replay
'   "When mute"     on only when volume is muted (Roku TVs only)
' These bytes go to the OS, never to the eye: DO NOT translate them.
' Pure: returns a fresh array; callers must not mutate module state through it.
' @return Object - roArray of 4 wire strings, index-parallel with CaptionsModeLabels()
function GetCaptionsModeWireValues() as Object
    return ["On", "Off", "Instant replay", "When mute"]
end function

' Localized display labels for the same four modes, in the exact order of
' GetCaptionsModeWireValues(). Literal Translate() calls keep Check 20's
' catalog-resolution coverage on these keys.
' @return Object - roArray of 4 localized label strings
function CaptionsModeLabels() as Object
    return [Translate("settings_button_caption_on"), Translate("settings_button_caption_off"), Translate("settings_button_caption_instant_replay"), Translate("settings_button_caption_when_mute")]
end function

' Map a captions WIRE value to its localized display label. "" is the
' documented system-level-off reading of roDeviceInfo.GetCaptionsMode()
' (mirrors PlayerScene R6.5 start-up normalisation) and renders as the
' "Off" label; any unrecognized value passes through unchanged so it stays
' visible for debugging instead of silently lying.
' @param wireMode String - value from roDeviceInfo.GetCaptionsMode()
' @return String - localized label, or the input itself when unknown
function CaptionsModeLabel(wireMode as String) as String
    wire = GetCaptionsModeWireValues()
    labels = CaptionsModeLabels()
    mode = wireMode
    if mode = "" then mode = "Off"
    for i = 0 to wire.count() - 1
        if wire[i] = mode then return labels[i]
    end for
    return mode
end function
' ===========================================
' W5 THIN-CLIENT ERROR LOCALISATION (syncplay_error frames)
'
' Doctrine: error-code-first. The stable error_code on a server frame selects
' the catalog string; the server's English message is only a debug fallback for
' codes this build does not recognize. Server text NEVER overrides a resolved
' code.
'
' MAPPING LAW (single source of truth, mirrored by Check 22 in
' scripts/verify-runtime.sh):
'   wire     = msg.error_code, else msg.code, else ""   (read in SyncPlayTask)
'   key      = "errors_" + LCase(wire) with "." and "-" replaced by "_"
'   invalid/non-string/empty wire -> "errors_fallback"
' Deterministic for both code families the server emits:
'   legacy SCREAMING: NOT_IN_GROUP            -> errors_not_in_group
'   dotted registry:  syncplay.group_full     -> errors_syncplay_group_full
' Unknown future codes miss the catalog, Translate echoes the key, and the
' resolver falls through to the server message - forward compatible by design.
'
' CENSUS SPLIT (wire-honesty redesign, 2026-09-25):
' The wire census SyncPlayKnownErrorCodes() is a SUPERSET of what the CURRENT
' server build emits: census ⊇ emitted, and every census member that is NOT
' (yet) emitted must be DECLARED in SyncPlayReservedErrorCodes(). Check 22
' pins the census by content equality against {emitted-verified ∪
' declared-reserved}, so an undeclared future code cannot ride in on a count
' bump. Post-flip split (promoted per the #90 law: reserved -> emitted only
' with fresh server evidence at a pinned origin):
'   emitted-verified: 20 codes (19 at the 9b2394ee flip + queue_limit_
'     exceeded promoted W-min92 on 7baa398a evidence), read off
'     phlix-server origin/master
'     9b2394eea631739dff8f6e039d50f910c4304d97 (PR #798 twin flip) plus the
'     pre-flip record e0e010b07c7f4cc21baf10d9a945bac24edab45c:
'       9 legacy SCREAMING still emitted at 9b2394ee (src/Session/SyncPlay/
'         SyncPlayManager.php sendError / 'error_code' literals +
'         src/Server/WebSocket/MessageHandler.php :156/:189/:213)
'       4 dotted registry twins (:621/:702/:741/:745, sent via the
'         $result['error_code'] ?? wraps at :1588/:1627)
'       3 dotted twins PROMOTED by the flip: syncplay.create_failed /
'         join_failed / leave_failed (sendError literals at :1588/:1627/:1659)
'       3 legacy SCREAMING emitted ONLY by pre-flip servers: CREATE_FAILED /
'         JOIN_FAILED / LEAVE_FAILED (live at e0e010b0; retired from current
'         emits at 9b2394ee - comment-only there). They STAY in the census and
'         catalogs so old servers keep resolving - the dual map's whole
'         point; a family retires only when its servers do.
'   declared-reserved: EMPTY. The flip consumed the only reservation
'     (phlix-contracts error registry, dist/error-codes.json). The function
'     and Check 22's reserved legs stay ARMED: the next flip-pending code
'     must be declared there BEFORE it may enter the census - declaration,
'     not discovery.
' TWIN-FLIP RECORD: 2026-09-25, phlix-server PR #798 @ 9b2394ee switched the
' group create/join/leave failure wraps from SCREAMING to the dotted registry
' forms. Both shapes normalize (law) onto distinct, fully-populated catalog
' keys, so the census and the seven catalogs are byte-stable across the flip
' - only this split moved.
' ===========================================

' Canonical client-reachable syncplay wire codes: the 20 emitted-verified
' codes (9 current + 3 pre-flip-only legacy SCREAMING + 8 dotted registry
' twins — the eighth, syncplay.queue_limit_exceeded, promoted W-min92 on the
' live emission evidence recorded at its push site, read off phlix-server
' origin/master sendError literals,
' pre-flip record e0e010b0) UNION the codes declared in
' SyncPlayReservedErrorCodes() (none since the 2026-09-25 twin flip) = 20.
' Every element MUST have a matching errors_<law(key)> entry in ALL seven
' locale catalogs - Check 22 enforces the en_US side by CONTENT equality
' against that split (the guard law: silent fallback must not hide a missing
' translation, and an undeclared future code must not ride in on a count
' bump) and Check 21 pins cross-locale key parity from the catalogs themselves.
' Pure: returns a fresh array; callers must not mutate module state through it.
' @return Object - roArray of 20 code strings as they appear on the wire
'         (current servers or pre-flip servers)
function SyncPlayKnownErrorCodes() as Object
    codes = []
    codes.push("NOT_AUTHENTICATED")
    codes.push("NOT_IN_GROUP")
    codes.push("NOT_HOST")
    codes.push("UNKNOWN_MESSAGE")
    codes.push("HANDLER_ERROR")
    codes.push("PROTOCOL_VERSION_MISMATCH")
    codes.push("INVALID_NEW_HOST")
    codes.push("MEMBER_NOT_FOUND")
    codes.push("SAME_HOST")
    ' Pre-flip-only legacy trio: emitted ONLY by pre-9b2394ee servers, kept so
    ' old servers resolve (their dotted twins below carry current servers).
    codes.push("CREATE_FAILED")
    codes.push("JOIN_FAILED")
    codes.push("LEAVE_FAILED")
    codes.push("syncplay.group_limit_reached")
    codes.push("syncplay.group_not_found")
    codes.push("syncplay.invalid_password")
    codes.push("syncplay.group_full")
    ' Flip-promoted dotted twins - emitted-verified since phlix-server
    ' 9b2394ee (PR #798, 2026-09-25). Paired with the SCREAMING trio above,
    ' which pre-flip servers still speak: the dual map retires only when
    ' that server family does.
    codes.push("syncplay.create_failed")
    codes.push("syncplay.join_failed")
    codes.push("syncplay.leave_failed")
    ' Promoted W-min92 on live emission evidence: phlix-server 7baa398a emits
    ' syncplay.queue_limit_exceeded on queue overflow (sendError at
    ' SyncPlayManager.php:1254 on current master; contracts v0.5.3 registry
    ' row 8). Declaration preceded the census entry in the contracts union;
    ' the wire change has landed, so this is a promotion, not a reservation.
    ' NOTE for future editors: never place a double quote inside this body —
    ' Checks 22/23 extract members by pairing quoted strings across the raw
    ' function text (no comment masking), so one unbalanced quote here turns
    ' every following push into a false census member.
    codes.push("syncplay.queue_limit_exceeded")
    return codes
end function

' The census members a future server flip is expected to introduce, declared
' in advance of the wire change. EMPTY since 2026-09-25: the only reservation
' this client ever held - the dotted create/join/leave twins registered in the
' phlix-contracts error registry (v0.5.1, dist/error-codes.json) - was
' promoted to emitted-verified when phlix-server PR #798 @ 9b2394ee landed the
' twin flip (sendError literals at SyncPlayManager.php:1588/1627/1659).
' Kept - deliberately NOT collapsed - because the law it carries is
' structural: declaration, not discovery. Check 22 still pins this set by
' content (exactly the empty set today), requires every member to live in the
' wire census, and forbids SCREAMING/"local." shapes - so the NEXT
' flip-pending code must be DECLARED here before it may enter the census, and
' the two sets still cannot drift: census == emitted-verified ∪ reserved.
' Collapsing the split would disarm that gate until someone re-minted it.
' Pure: returns a fresh array; callers must not mutate module state through it.
' @return Object - roArray of dotted registry codes, empty today (when
'         non-empty: never SCREAMING, never "local.")
function SyncPlayReservedErrorCodes() as Object
    codes = []
    return codes
end function

' Apply the MAPPING LAW above: wire error_code -> flat "errors_*" catalog key.
' Total function: any input shape (invalid, number, empty, padded) parses into
' exactly one of {errors_<normalized>, errors_fallback}.
' @param code Object - raw error_code/code value from the frame
' @return String - flat Translate() key
function SyncPlayErrorCodeToKey(code as Object) as String
    if code = invalid then return "errors_fallback"
    tp = type(code)
    if tp <> "String" and tp <> "roString" then return "errors_fallback"
    raw = code.Trim()
    if raw = "" then return "errors_fallback"
    normalized = LCase(raw).Replace(".", "_").Replace("-", "_")
    return "errors_" + normalized
end function

' Resolve the user-facing text for one syncplay_error frame.
' Priority (first hit wins):
'   1. recognized code -> its catalog entry in the active locale
'   2. unrecognized/absent code + non-empty server message -> that message
'   3. errors_fallback catalog entry (generic localized line)
'   4. "" - catalog entirely unavailable; the caller supplies its own
'      last-resort literal so this function never renders a raw key.
' Pure apart from Translate()'s cached catalog load; no global mutation.
' @param code Object - wire error_code (or legacy code) value
' @param serverMessage String - frame "message" text, may be ""
' @return String - localized (or debug-fallback) user-facing text
function LocalizeSyncPlayError(code as Object, serverMessage as String) as String
    key = SyncPlayErrorCodeToKey(code)
    if key <> "errors_fallback"
        text = Translate(key)
        if text <> key then return text
    end if
    if serverMessage <> "" then return serverMessage
    fallback = Translate("errors_fallback")
    if fallback <> "errors_fallback" then return fallback
    return ""
end function

' ===========================================
' CLIENT-GENERATED ERROR FAMILY (local.*) - NEVER WIRE CODES
'
' The setup failures in components/SyncPlayTask.brs (config/host/socket/
' connect/handshake-accept) and the REST-path failures in components/
' SyncPlayScene.brs (create/join/leave/invalid) are produced ON THIS DEVICE
' and ride no frame.
' They are not "unrecognized server codes", so they must not squat in the
' wire census SyncPlayKnownErrorCodes() (Check 22 pins that list by content
' to exactly the 20 emitted-verified wire codes - 17 current + 3
' pre-flip-only legacy - plus any declared-reserved flip-pending codes
' (none today), and that honesty is the point).
'
' DEAD-PATH NOTE (M-ROKU-26, Check 56): the SyncPlayScene.brs sites named above
' are retained but not instantiated - that half of the family currently never
' fires on a device (only the SyncPlayTask half does). The census law still
' scans components/, so the registry (and its rule that these literals never
' regress to raw display strings) stays complete for a room revival; wiring the
' scene must re-cut the README §6 retention note in the same commit.
'
' They DO reuse the W5 MAPPING LAW verbatim (SyncPlayErrorCodeToKey) under a
' reserved "local." mint prefix: law("local.connect_failed") =
' "errors_local_connect_failed", so the catalog keeps ONE errors registry
' and the resolver keeps ONE normalization. The `local.` prefix can never be
' produced by the server registry (domains are SCREAMING legacy or dotted
' namespaces like syncplay.*), so provenance is carried by the census, not
' by the key shape.
'
' SEPARATION LAW (mirrored by Check 23 in scripts/verify-runtime.sh):
'   1. every SyncPlayLocalErrorCodes() entry matches local.<snake_name>
'   2. no SyncPlayKnownErrorCodes() entry starts with "local."
'   3. the two families never normalize onto one catalog key
'   4. every errors_local_* key in en_US is a member of the local census,
'      and every errors_* key belongs to wire OR fallback OR local
'      (bidirectional registry - nothing unaccounted may squat)
'   5. EmitError call sites pass census codes, never raw display literals
' ===========================================

' Canonical client-generated error codes (SyncPlayTask setup + SyncPlayScene
' REST paths). Every element MUST resolve to an errors_<law(key)> entry in
' ALL seven locale catalogs - Check 23 enforces the en_US side plus the
' separation law, Check 21 pins cross-locale parity.
' Pure: returns a fresh array; callers must not mutate module state through it.
' @return Object - roArray of "local.*" code strings (never wire values)
function SyncPlayLocalErrorCodes() as Object
    codes = []
    codes.push("local.no_config")
    codes.push("local.no_host")
    codes.push("local.socket_unavailable")
    codes.push("local.connect_failed")
    codes.push("local.connect_timeout")
    codes.push("local.ws_accept_invalid")
    codes.push("local.room_create_failed")
    codes.push("local.room_join_failed")
    codes.push("local.room_leave_failed")
    codes.push("local.invalid_room")
    return codes
end function

' Resolve the user-facing line for one client-generated local.* code.
' Unlike LocalizeSyncPlayError (wire frames - a "" return lets the caller's
' last-resort literal speak), this resolver NEVER returns empty and never
' needs an English literal argument: the string was minted here, so the
' priority is catalog hit -> errors_fallback line -> raw key echo. A fully
' dead catalog rendering the key is VISIBLE breakage, which beats a blank
' status label (the task thread has no other channel to report through).
' @param code Object - "local.*" code string
' @return String - non-empty user-facing text in the device language
function LocalizeSyncPlayLocalError(code as Object) as String
    key = SyncPlayErrorCodeToKey(code)
    text = Translate(key)
    if text <> key then return text
    fallback = Translate("errors_fallback")
    if fallback <> "errors_fallback" then return fallback
    return key
end function

' ===========================================
' SYNCPLAY PLAINTEXT-ORIGIN LAW (M-ROKU-14, review roku__exploiter M3)
' ===========================================

' True when the connected server origin is TLS (https://) and the plaintext
' :8097 SyncPlay dial MUST therefore be refused. The dial rides roStreamSocket
' — plaintext TCP, no TLS (wss:// is impossible on this transport). On an
' https origin the account JWT was established over TLS; replaying it verbatim
' in a cleartext bearer-subprotocol handshake lets a passive LAN sniffer
' capture the MAIN ACCOUNT credential — the mismatch itself is the exploitable
' class, so we refuse instead of silently downgrading. http:// origins keep
' connecting: the REST lane is already cleartext there, so the dial adds no
' NEW exposure class (credential custody on http lanes is a separate estate
' concern, not this choke). Pure: string in, boolean out. "" / invalid /
' scheme-less input returns false — the caller's existing origin guards speak
' for those shapes.
' @param serverUrl String - the connected server origin (GetServerUrl())
' @return Boolean - true ONLY for an https:// origin
function SyncPlayWsRefusedForOrigin(serverUrl as String) as Boolean
    if serverUrl = invalid then return false
    s = LCase(serverUrl.Trim())
    if s = "" then return false
    return Left(s, 8) = "https://"
end function

' ===========================================
' JOIN-DIGEST CUSTODY (MJ-2, review roku__casualgamer deferred item)
' ===========================================

' True when s is EXACTLY the canonical password_hash shape phlix-server
' demands (SyncPlayManager::joinGroup + GroupState::isCanonicalPasswordHash):
' 64 chars, every one a LOWERCASE hex digit. The server refuses a present-but-
' non-canonical digest (SPEC §4 "refused, never coerced"), so the client gates
' the same way BEFORE the frame leaves the device: a malformed digest is
' dropped, never sent. Pure string logic - unit-pinnable headless. The scan
' keeps the SyncPlayProtocol.IsHex40 range-compare idiom so the repo's two
' canonical-hex gates stay ONE byte-pinned shape (the ranges are ASCII-
' ordered, so the compares ARE the test - identically on brs and firmware).
' Asc() itself is real BrightScript: bsc models it, brs implements it, and
' IsPrivateIpRange/UrlEncode/StripWireControlChars/IsSafeContentId above all
' call it live. Check 94 R2's Asc( ban is SHAPE custody for this body only -
' it has never been a platform-impossibility claim (the era prose that said
' so was false; corrected in the CHANGELOG's 2026-11-04 entry).
function IsCanonicalPasswordHash(s as String) as Boolean
    if s = invalid then return false
    if s.Len() <> 64 then return false
    for i = 1 to 64
        c = Mid(s, i, 1)
        if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f")) then return false
    end for
    return true
end function

' The SPEC §4 password_hash a joiner presents for a password-protected group:
' unsalted SHA-256 of the password, lowercase hex, 64 chars. The plaintext
' NEVER rides the WebSocket (SPEC: "New clients MUST NOT send password on the
' WebSocket") and never leaves this function. The platform digest is
' roEVPDigest - the SAME component SyncPlayProtocol.VerifyHandshakeAccept
' already relies on (Setup returns 0 on success, Process returns HEX), just
' pinned to "sha256". Every failure mode (no component, Setup refusal, junk
' shape) returns "" and the CALLER must fail closed: this is a device that
' cannot prove it knows the gate, so the protected join is refused, never
' attempted with a forged/absent digest. Empty input returns "" (a blank
' password is not a gate; the caller only hashes a non-empty one).
'
' [W13L3 RT-041, review roku__secnet #5] The digest runs over the raw UTF-8
' BYTES of the password, matching the server's group gate, which hashes the
' request body's bytes (PHP strings are byte strings): fromAsciiString
' ASCII-folded every code point >= 128, so a non-ASCII password digested to
' a value the server could never reproduce - the join failed for the correct
' password. The bytes now come from the shared Utf8BytesForCodePoint law.
' No trim: a leading/trailing space is password material (estate parity -
' mobile sha256.ts hashes the raw string; the gate compares the hash of what
' the host typed).
function SyncPlayPasswordHash(plain as String) as String
    if plain = invalid or plain = "" then return ""
    evp = CreateObject("roEVPDigest")
    if evp = invalid then return ""
    if evp.Setup("sha256") <> 0 then return ""
    src = CreateObject("roByteArray")
    if src = invalid then return ""
    ' [W14L1 RT-041 fold-in] The byte law now routes through the extracted
    ' pure Utf8BytesFromString (see its header): the digest and the headless
    ' truth-vector tests exercise the SAME function, so the input-encoding
    ' law the inline loop used to hide behind is pinned on every battery run.
    for each b in Utf8BytesFromString(plain)
        src.Push(b)
    end for
    hexStr = evp.Process(src)
    if hexStr = invalid then return ""
    ' The firmware returns the hex upper-cased (the IsHex40 sibling pinned this
    ' shape in the handshake path); canonical form is lowercase.
    h = LCase(hexStr.Trim())
    if not IsCanonicalPasswordHash(h) then return ""
    return h
end function

' ===========================================
' HUB RELAY PLAINTEXT-ORIGIN LAW (M-ROKU-23, review roku__secnet M2)
' ===========================================

' True when the configured hub origin is TLS (https://) and the plaintext
' :8804 hub-relay command consumer MUST therefore be refused. The consumer
' socket is roStreamSocket — plaintext TCP, no TLS — and its handshake carries
' a hub MINTED relay token (Authorization: Bearer) that lets whoever holds it
' push "Alexa, play X" commands into the user's session. Behind an https hub
' that token was established over TLS; replaying it across a cleartext socket
' to the same identity lets a passive path sniffer capture a live credential
' AND inject playback — the scheme mismatch itself is the exploitable class,
' so we refuse instead of silently downgrading (the SyncPlayWsRefusedForOrigin
' doctrine of M-ROKU-14, applied to the hub relay leg). The wss arm via
' roSecureSocket is DEFERRED with disclosure, NOT declared impossible: the
' managed hub front-end already routes GET /syncplay/ to the relay worker
' (phlix-hub docs/websockets.md), so `wss://<hub-domain>/syncplay/{server_id}`
' exists server-side today; the client leg awaits on-device verification of
' roSecureSocket's surface (the estate's platform-API verification floor —
' see edbbd8a's law on the :8097 leg). http:// / scheme-less legacy origins
' keep dialling 8804 exactly as before: their REST lane is already cleartext,
' so the dial adds no NEW exposure class. Pure: string in, boolean out.
' Globals LCase/Left do the comparison — the OFF-LIMITS ban is scoped to the
' member forms .Mid/.Lower (ifStringOps indices are 0-based; .Lower() is no
' Roku string member at all; see the M-ROKU-23 fixlog Observations). The
' body's only member call, .Trim(), is a legitimate ifStringOps member.
' @param hubUrl String - the persisted hub origin (GetServerUrl())
' @return Boolean - true ONLY for an https:// origin
function HubRelayCleartextRefusedForOrigin(hubUrl as String) as Boolean
    if hubUrl = invalid then return false
    s = LCase(hubUrl.Trim())
    if s = "" then return false
    return Left(s, 8) = "https://"
end function
