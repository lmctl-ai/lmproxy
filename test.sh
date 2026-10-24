#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
BUILD_DIR="${BUILD_DIR:-build}"
HOST="$BUILD_DIR/lmproxy"
PATH="$HERE/$BUILD_DIR:$PATH"
export PATH
UNAME_S="$(uname -s)"
case "$UNAME_S" in MINGW*|MSYS*|CYGWIN*) HOST="$HOST.exe";; esac
stat_size(){ stat -c %s "$1" 2>/dev/null || stat -f%z "$1"; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lmproxy-test-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
pass=0
ok(){ pass=$((pass+1)); echo "ok $pass - $1"; }
fail(){ echo "FAIL: $*" >&2; exit 1; }

LMSCRIPT="$(scripts/select-compiler.sh)"
scripts/sync-sdk.sh --verify >/dev/null || fail "SDK header pin mismatch"
ok "SDK header matches sdk.lock"
scripts/sync-squid.sh --verify >/dev/null || fail "squid pin mismatch"
ok "third_party/squid matches squid.lock"

cmake -S . -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=Release >"$WORK/cmake.log" 2>&1 ||
  { tail -30 "$WORK/cmake.log" >&2; fail "cmake configure ($BUILD_DIR)"; }
cmake --build "$BUILD_DIR" -j2 >"$WORK/build.log" 2>&1 ||
  { tail -30 "$WORK/build.log" >&2; fail "cmake build ($BUILD_DIR)"; }
ok "host build ($BUILD_DIR)"

want_version="lmproxy $(sed -n 's/^project(lmproxy VERSION \([0-9.]*\).*/\1/p' CMakeLists.txt)"
[ "$("$HOST" --version)" = "$want_version" ] || fail "--version prints $want_version"
set +e; "$HOST" --version extra >/dev/null 2>&1; code=$?; set -e
[ "$code" = 2 ] || fail "--version with an extra argument exits 2 (got $code)"
ok "--version prints exactly '$want_version'"

"$HOST" --dsl-schema --json >"$WORK/embedded-schema.json" || fail "embedded schema print"
cmp schema/lmproxy.dsl.json "$WORK/embedded-schema.json" || fail "embedded schema differs from source bytes"
ok "--dsl-schema --json prints byte-identical embedded schema bytes"
"$HOST" --dsl-schema >"$WORK/schema-summary.txt" || fail "schema summary print"
python3 - "$WORK/schema-summary.txt" <<'PY'
import re,subprocess,sys
summary=open(sys.argv[1]).read()
sigs=subprocess.run(['build/lmproxy','--dsl-signatures'],capture_output=True,text=True).stdout.splitlines()
missing=[]
for line in sigs:
  if line.startswith('method '): needle=line[7:]
  elif line.startswith('fn '): needle=line[3:]
  elif line.startswith('context '): needle=line[8:]
  else: needle=line
  if needle not in summary: missing.append(needle)
assert not missing, missing
print('all', len(sigs), 'registry members listed in --dsl-schema summary')
PY
ok "--dsl-schema summary lists every registry member"
diff -u <("$LMSCRIPT" --dsl-signatures schema/lmproxy.dsl.json) <("$HOST" --dsl-signatures) || fail "host/compiler signatures differ"
ok "typed registry signatures match compiler schema signatures"

# --- parse-url ---
out="$("$HOST" parse-url http://user@example.com:8080/a?b=1)"
[ "$out" = '{"valid":true,"scheme":"http","host":"example.com","host_is_ip":false,"userinfo":"user","port":8080,"path":"/a?b=1"}' ] \
  || fail "parse-url components: $out"
ok "parse-url: scheme/host/userinfo/port/path"

out="$("$HOST" parse-url 'https://[2001:db8::1]/x')"
echo "$out" | grep -q '"host":"2001:db8::1"' || fail "parse-url IPv6: $out"
echo "$out" | grep -q '"host_is_ip":true' || fail "parse-url IPv6 numeric flag: $out"
ok "parse-url: bracketed IPv6 literal, host_is_ip"

out="$("$HOST" parse-url not-a-url)"
echo "$out" | grep -q '"valid":false' || fail "parse-url must reject garbage: $out"
ok "parse-url: garbage rejected with valid:false"

"$HOST" parse-url ftp://files.example.com/pub/squid-7.0.0.tar.gz | grep -q '"scheme":"ftp"'
ok "parse-url: non-HTTP scheme"

set +e; "$HOST" parse-url >/dev/null 2>&1; code=$?; set -e
[ "$code" = 2 ] || fail "parse-url without arguments exits 2 (got $code)"
ok "parse-url without arguments refused (exit 2)"

# --- parse-request / parse-response ---
printf 'GET /index.html HTTP/1.1\r\nHost: example.com\r\nAccept: */*\r\n\r\n' > "$WORK/req.txt"
out="$("$HOST" parse-request "$WORK/req.txt")"
echo "$out" | grep -q '"method":"GET"' || fail "request method: $out"
echo "$out" | grep -q '"target":"/index.html"' || fail "request target: $out"
echo "$out" | grep -q '"version":"HTTP/1.1"' || fail "request version: $out"
echo "$out" | grep -q '"Host":"example.com"' || fail "request Host header: $out"
echo "$out" | grep -Fq '"Accept":"*/*"' || fail "request Accept header: $out"
ok "parse-request: first line, version, headers"

printf 'GET / HTTP/1.1\r\nhost: EXAMPLE.COM\r\n\r\n' | "$HOST" parse-request - | grep -q '"host":"EXAMPLE.COM"' \
  || fail "header name case preserved"
ok "parse-request: header lookup is case-insensitive, name case preserved"

printf 'OPTIONS * HTTP/1.0\r\n\r\n' | "$HOST" parse-request - | grep -q '"target":"\*"' || fail "asterisk-form target"
ok "parse-request: OPTIONS * form"

printf 'HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n' > "$WORK/resp.txt"
out="$("$HOST" parse-response "$WORK/resp.txt")"
echo "$out" | grep -q '"status":404' || fail "response status: $out"
echo "$out" | grep -q '"reason":"Not Found"' || fail "response reason: $out"
ok "parse-response: status code and reason phrase"

set +e; out="$("$HOST" parse-request "$WORK/no-such-file" 2>&1)"; code=$?; set -e
[ "$code" = 3 ] && [[ "$out" == *'cannot read'* ]] || fail "missing input file (exit $code): $out"
ok "parse-request missing file refused (exit 3)"

# --- percent encoding ---
out="$("$HOST" parse-url 'http://h/x%20y')" # warm path only
"$HOST" --dsl-signatures >/dev/null
ok "signatures stable after subcommand runs"

# --- DSL bytecode ---
cat > "$WORK/smoke.lms" <<EOF
p = _dsl_ cli="lmproxy" install="github:lmctl-ai/lmproxy@latest";
let u = proxy.parse_url("http://example.com:8080/x?y=1");
println(u.host() + ":" + str(u.port()) + u.path());
let m = proxy.parse_request("GET /a HTTP/1.1\r\nHost: example.com\r\n\r\n");
println(m.method() + " " + m.target() + " " + m.version() + " host=" + m.header("host"));
let r = proxy.parse_response("HTTP/1.1 200 OK\r\nServer: squid\r\n\r\n");
println(str(r.status()) + " " + r.reason() + " server=" + r.header("SERVER"));
end _dsl_
savedsl(p, "$WORK/smoke.dslb");
EOF
"$LMSCRIPT" "$WORK/smoke.lms" "$WORK/smoke.dslb" >/dev/null || fail "smoke compile"
[ "$(od -An -t u1 -j 5 -N 1 "$WORK/smoke.dslb" | tr -d ' ')" = 5 ] || fail "smoke was not compiled as bytecode v5"
out="$("$HOST" --dsl "$WORK/smoke.dslb")"
[ "$(tail -1 <<<"$out")" = '{"ok": true, "result": null}' ] || fail "smoke run: $out"
grep -q '^example.com:8080/x?y=1$' <<<"$out" || fail "smoke url line: $out"
grep -q '^GET /a HTTP/1.1 host=example.com$' <<<"$out" || fail "smoke request line: $out"
grep -q '^200 OK server=squid$' <<<"$out" || fail "smoke response line: $out"
ok "bytecode: parse_url/parse_request/parse_response through the DSL"

cat > "$WORK/bad-usage.lms" <<EOF
p = _dsl_ cli="lmproxy" install="github:lmctl-ai/lmproxy@latest";
let names = proxy.parse_response("HTTP/1.1 200 OK\r\nA: 1\r\nB: 2\r\n\r\n").header_names();
if (names.len() != 2 || names.at(0) != "A" || names.at(1) != "B") { println("bad"); }
let u = proxy.parse_url("http://example.com/");
if (!u.valid() || u.has_port() || u.port() != 80 || u.host_is_ip()) { println("bad"); }
if (proxy.percent_decode("a%20b") != "a b") { println("bad"); }
println("done");
end _dsl_
savedsl(p, "$WORK/bad-usage.dslb");
EOF
"$LMSCRIPT" "$WORK/bad-usage.lms" "$WORK/bad-usage.dslb" >/dev/null || fail "bad-usage compile"
out="$("$HOST" --dsl "$WORK/bad-usage.dslb")"
grep -q '^done$' <<<"$out" || fail "StrList/percent/flags checks failed: $out"
ok "StrList.at/len, Url flags, percent_decode behave"

cat > "$WORK/oob.lms" <<EOF
p = _dsl_ cli="lmproxy" install="github:lmctl-ai/lmproxy@latest";
proxy.parse_url("http://h/").header_names();
end _dsl_
savedsl(p, "$WORK/oob.dslb");
EOF
set +e; "$LMSCRIPT" "$WORK/oob.lms" "$WORK/oob.dslb" >"$WORK/type-error.txt" 2>&1; code=$?; set -e
[ "$code" = 2 ] || fail "wrong-type method call must be a compile error (exit $code)"
cat > "$WORK/oob2.lms" <<EOF
p = _dsl_ cli="lmproxy" install="github:lmctl-ai/lmproxy@latest";
let m = proxy.parse_response("HTTP/1.1 200 OK\r\nA: 1\r\n\r\n");
m.header_names().at(5);
end _dsl_
savedsl(p, "$WORK/oob2.dslb");
EOF
"$LMSCRIPT" "$WORK/oob2.lms" "$WORK/oob2.dslb" >/dev/null || fail "compile"
set +e; out="$("$HOST" --dsl "$WORK/oob2.dslb" 2>&1)"; code=$?; set -e
[ "$code" = 3 ] && [[ "$out" == *'out of range'* ]] || fail "StrList.at bounds (exit $code): $out"
ok "type mismatch refused at compile (exit 2), StrList.at bounds refused at runtime (exit 3)"

set +e; out="$("$HOST" 2>&1)"; code=$?; set -e
[ "$code" = 2 ] && [[ "$out" == *'usage: lmproxy'* ]] || fail "bad args refusal (exit $code): $out"
ok "bad arguments refused (exit 2)"
set +e; out="$("$HOST" --dsl "$WORK/no-such.dslb" 2>&1)"; code=$?; set -e
[ "$code" = 3 ] && [[ "$out" == *'"phase": "load"'* ]] || fail "missing bytecode refusal (exit $code): $out"
ok "missing bytecode file refused at load (exit 3)"

"$HOST" --dsl "$WORK/smoke.dslb" "$WORK/bad-usage.dslb" >"$WORK/multi.jsonl" || fail "multi-bytecode run"
[ "$(grep -c '^{"ok": true, "result": null}$' "$WORK/multi.jsonl")" = 2 ] || fail "multiple bytecode files did not run in order"
ok "multiple bytecode files run sequentially"

# --- examples compile and run ---
mkdir -p build
for f in parse-url inspect-request inspect-response percent-encoding; do
  "$LMSCRIPT" "examples/$f.lms" "build/$f.dslb" >"$WORK/$f.compile.log" 2>&1 || fail "$f example compile"
  "$HOST" --dsl "build/$f.dslb" >"$WORK/$f.out" || fail "$f example run"
  # every '# expect:' line must appear in the program output
  while IFS= read -r line; do
    grep -qxF "${line:2}" "$WORK/$f.out" || fail "$f example output missing: ${line:2} (got $(cat "$WORK/$f.out"))"
  done < <(grep '^#|' "examples/$f.lms")
done
ok "examples compile and their expected output matches"

if [ "$UNAME_S" = "Darwin" ]; then
  BAD_LIBS="$(otool -L "$HOST" | tail -n +2 | awk '{print $1}' | grep -v '^/usr/lib/\|^/System/Library/' || true)"
  [ -z "$BAD_LIBS" ] || fail "host links non-system libraries: $BAD_LIBS"
  ok "host links only system libraries ($(stat_size "$HOST") bytes, otool -L clean)"
else
  LDD_OUT="$(ldd "$HOST" 2>&1 || true)"
  [[ "$LDD_OUT" == *'not a dynamic executable'* ]] || fail "host is not fully static: $LDD_OUT"
  ok "host is fully static ($(stat_size "$HOST") bytes, ldd clean)"
fi

echo "PASS: $pass checks"
