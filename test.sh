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
  { grep -n -B 3 -A 4 "error:" "$WORK/build.log" >&2 || true; tail -30 "$WORK/build.log" >&2; fail "cmake build ($BUILD_DIR)"; }
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
cmp schema/lmproxy.host.json schema/lmproxy.dsl.json || fail "generated schema differs from host-only input"
python3 scripts/merge-std.py --host-only schema/lmproxy.dsl.json "$WORK/host-only-schema.json"
cmp schema/lmproxy.dsl.json "$WORK/host-only-schema.json" || fail "embedded schema still declares standard members"
"$HOST" --dsl-signatures >"$WORK/registry-signatures.txt"
"$LMSCRIPT" --dsl-signatures cpp/std/lmcode-std.schema.json >"$WORK/standard-signatures.txt"
python3 - "$WORK" <<'PYHOST'
from pathlib import Path
import sys
work=Path(sys.argv[1])
registry=set((work/'registry-signatures.txt').read_text().splitlines())
standard=set((work/'standard-signatures.txt').read_text().splitlines())
assert len(standard)==72, len(standard)
(work/'host-signatures.txt').write_bytes(''.join(line+'\n' for line in sorted(registry-standard)).encode('utf-8'))
PYHOST
diff -u <("$LMSCRIPT" --dsl-signatures schema/lmproxy.dsl.json --without-std) "$WORK/host-signatures.txt" || fail "host-only registry/compiler signatures differ"
ok "typed registry signatures match compiler schema signatures (full and --without-std)"

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
let fpath = "$WORK/std-file.txt";
file_write(fpath, "alpha\n");
file_append(fpath, "beta");
if (!file_exists(fpath) || file_read(fpath) != "alpha\nbeta") { println("bad"); }
let lines = file_lines(fpath);
if (lines.len() != 2 || lines.at(0) != "alpha" || lines.at(1) != "beta") { println("bad"); }
println("done");
end _dsl_
savedsl(p, "$WORK/bad-usage.dslb");
EOF
"$LMSCRIPT" "$WORK/bad-usage.lms" "$WORK/bad-usage.dslb" >/dev/null || fail "bad-usage compile"
out="$("$HOST" --dsl "$WORK/bad-usage.dslb")"
grep -q '^done$' <<<"$out" || fail "StrList/percent/flags/file_* checks failed: $out"
ok "StrList.at/len, Url flags, percent_decode, and std file_* behave"

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

# --- forward proxy mode test ---
python3 -c "
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
class H(SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', '20')
        self.end_headers()
        self.wfile.write(b'HELLO_FROM_UPSTREAM\n')
    def log_message(self, *args): pass
httpd = ThreadingHTTPServer(('127.0.0.1', 0), H)
print(httpd.server_address[1], flush=True)
httpd.serve_forever()
" > "$WORK/upstream_port.txt" 2>&1 &
UPSTREAM_PID=$!

while [ ! -s "$WORK/upstream_port.txt" ]; do sleep 0.05; done
UPSTREAM_PORT="$(cat "$WORK/upstream_port.txt")"

PROXY_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')"
"$HOST" forward --port "$PROXY_PORT" --bind 127.0.0.1 >"$WORK/proxy.log" 2>&1 &
PROXY_PID=$!

for i in {1..50}; do
  if python3 -c "import socket; s = socket.create_connection(('127.0.0.1', int('$PROXY_PORT')), timeout=0.1); s.close()" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

curl_out="$(curl -s -x "http://127.0.0.1:$PROXY_PORT" "http://127.0.0.1:$UPSTREAM_PORT/" || true)"
kill -TERM "$PROXY_PID" 2>/dev/null || true
kill -TERM "$UPSTREAM_PID" 2>/dev/null || true
sleep 0.5
kill -9 "$PROXY_PID" 2>/dev/null || true
kill -9 "$UPSTREAM_PID" 2>/dev/null || true
wait "$PROXY_PID" 2>/dev/null || true
wait "$UPSTREAM_PID" 2>/dev/null || true

[ "$(echo "$curl_out" | tr -d '\r\n')" = "HELLO_FROM_UPSTREAM" ] || fail "forward proxy response mismatch: got '$curl_out'"
ok "forward proxy mode routes traffic to upstream"

# --- SSL-bump CA generation and intercept proxy test ---
INTERCEPT_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')"
"$HOST" intercept --port "$INTERCEPT_PORT" --ssl-bump >"$WORK/intercept.log" 2>&1 &
INTERCEPT_PID=$!
for i in {1..50}; do
  if python3 -c "import socket; s = socket.create_connection(('127.0.0.1', int('$INTERCEPT_PORT')), timeout=0.1); s.close()" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
kill -TERM "$INTERCEPT_PID" 2>/dev/null || true
sleep 0.5
kill -9 "$INTERCEPT_PID" 2>/dev/null || true
wait "$INTERCEPT_PID" 2>/dev/null || true
ok "intercept proxy mode with SSL-bump configuration"

# --- certgen embedded helper ---
"$HOST" certgen -v | grep -q "security_file_certgen" || fail "certgen helper version print"
ok "embedded certgen helper responds"

# --- traffic tap, record, route, and redirect test ---
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        if self.path == '/destination':
            self.wfile.write(b'SWAPPED_OK\n')
        elif self.path == '/routed':
            self.wfile.write(b'ROUTED_OK\n')
        else:
            self.wfile.write(b'ORIGINAL_OK\n')
    def log_message(self, *args): pass
httpd = HTTPServer(('127.0.0.1', 0), H)
print(httpd.server_address[1], flush=True)
httpd.serve_forever()
" > "$WORK/mock_port.txt" 2>&1 &
MOCK_PID=$!
while [ ! -s "$WORK/mock_port.txt" ]; do sleep 0.05; done
MOCK_PORT="$(cat "$WORK/mock_port.txt")"

PROXY_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')"
"$HOST" forward --port "$PROXY_PORT" --bind 127.0.0.1 \
  --tap --record "$WORK/rec.jsonl" \
  --redirect "/swap=http://127.0.0.1:$MOCK_PORT/destination" \
  --route "/routed=127.0.0.1:$MOCK_PORT" \
  >"$WORK/proxy_rules.log" 2>&1 &
PROXY_PID=$!

for i in {1..50}; do
  if python3 -c "import socket; s = socket.create_connection(('127.0.0.1', int('$PROXY_PORT')), timeout=0.1); s.close()" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

r_orig="$(curl -s -x "http://127.0.0.1:$PROXY_PORT" "http://127.0.0.1:$MOCK_PORT/orig")"
[ "$r_orig" = "ORIGINAL_OK" ] || fail "plain pass-through mismatch: $r_orig"

r_swap="$(curl -s -L -x "http://127.0.0.1:$PROXY_PORT" "http://127.0.0.1:$MOCK_PORT/swap")"
[ "$r_swap" = "SWAPPED_OK" ] || fail "redirect swap mismatch: $r_swap"

r_route="$(curl -s -x "http://127.0.0.1:$PROXY_PORT" "http://non-existent-domain.internal/routed")"
[ "$r_route" = "ROUTED_OK" ] || fail "backend route mismatch: $r_route"

kill -TERM "$PROXY_PID" 2>/dev/null || true
kill -TERM "$MOCK_PID" 2>/dev/null || true
wait "$PROXY_PID" 2>/dev/null || true
wait "$MOCK_PID" 2>/dev/null || true

[ -s "$WORK/rec.jsonl" ] || fail "empty jsonl recording"
grep -q '"method":"GET"' "$WORK/rec.jsonl" || fail "missing GET in jsonl record"
ok "traffic tap, record, route, and redirect in forward proxy mode"

# --- HTTPS SSL-bump end-to-end interception and swap ---
openssl req -new -newkey rsa:2048 -days 1 -nodes -x509 -keyout "$WORK/testca.key" -out "$WORK/testca.crt" -subj "/CN=LMProxy Test CA" 2>/dev/null
openssl req -new -newkey rsa:2048 -nodes -keyout "$WORK/server.key" -out "$WORK/server.csr" -subj "/CN=localhost" 2>/dev/null
openssl x509 -req -in "$WORK/server.csr" -CA "$WORK/testca.crt" -CAkey "$WORK/testca.key" -CAcreateserial -out "$WORK/server.crt" -days 1 2>/dev/null

python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading, ssl

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        if self.path == '/destination':
            self.wfile.write(b'HTTPS_SWAPPED_OK\n')
        else:
            self.wfile.write(b'HTTPS_ORIGINAL_OK\n')
    def log_message(self, *args): pass

http_dest = HTTPServer(('127.0.0.1', 0), H)
dest_port = http_dest.server_address[1]
threading.Thread(target=http_dest.serve_forever, daemon=True).start()

https_srv = HTTPServer(('127.0.0.1', 0), H)
ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ssl_ctx.load_cert_chain('$WORK/server.crt', '$WORK/server.key')
https_srv.socket = ssl_ctx.wrap_socket(https_srv.socket, server_side=True)
origin_port = https_srv.server_address[1]
threading.Thread(target=https_srv.serve_forever, daemon=True).start()

print(f'{dest_port} {origin_port}', flush=True)
threading.Event().wait()
" > "$WORK/ssl_ports.txt" 2>&1 &
SRV_PID=$!
while [ ! -s "$WORK/ssl_ports.txt" ]; do sleep 0.05; done
read -r DEST_PORT ORIGIN_PORT < "$WORK/ssl_ports.txt"

HTTPS_PROXY_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()')"
"$HOST" forward --port "$HTTPS_PROXY_PORT" --bind 127.0.0.1 \
  --ssl-bump --ca-cert "$WORK/testca.crt" --ca-key "$WORK/testca.key" \
  --redirect "/swap=http://127.0.0.1:$DEST_PORT/destination" \
  >"$WORK/https_proxy.log" 2>&1 &
PROXY_PID=$!

for i in {1..50}; do
  if python3 -c "import socket; s = socket.create_connection(('127.0.0.1', int('$HTTPS_PROXY_PORT')), timeout=0.1); s.close()" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

r_https_orig="$(curl -s -x "http://127.0.0.1:$HTTPS_PROXY_PORT" --cacert "$WORK/testca.crt" "https://localhost:$ORIGIN_PORT/orig")"
[ "$r_https_orig" = "HTTPS_ORIGINAL_OK" ] || fail "HTTPS origin passthrough mismatch: $r_https_orig"

r_https_swap="$(curl -s -L -x "http://127.0.0.1:$HTTPS_PROXY_PORT" --cacert "$WORK/testca.crt" "https://localhost:$ORIGIN_PORT/swap")"
[ "$r_https_swap" = "HTTPS_SWAPPED_OK" ] || fail "HTTPS redirect swap mismatch: $r_https_swap"

kill -TERM "$PROXY_PID" 2>/dev/null || true
kill -TERM "$SRV_PID" 2>/dev/null || true
wait "$PROXY_PID" 2>/dev/null || true
wait "$SRV_PID" 2>/dev/null || true
ok "HTTPS SSL-bump end-to-end interception and swap with dynamic certificate generation"

case "$UNAME_S" in
  Linux)
    if [ "${LMPROXY_FULL_STATIC:-OFF}" = "ON" ]; then
      LDD_OUT="$(ldd "$HOST" 2>&1 || true)"
      [[ "$LDD_OUT" == *'not a dynamic executable'* ]] || fail "host is not fully static: $LDD_OUT"
      ok "host is fully static ($(stat_size "$HOST") bytes, ldd clean)"
    else
      if command -v readelf >/dev/null 2>&1; then
        needed="$(readelf -d "$HOST" | sed -n 's/.*(NEEDED).*Shared library: \[\(.*\)\]/\1/p')"
      else
        needed="$(ldd "$HOST" | awk '/=>/ {print $1} !/=>/ && /ld-linux/ {sub(/^[[:space:]]*/, ""); sub(/[[:space:]].*/, ""); print $0}' | xargs -n1 basename)"
      fi
      [ -n "$needed" ] || fail "expected dynamic glibc linkage on Linux, found no NEEDED entries"
      bad="$(printf '%s\n' "$needed" | grep -v -E '^(libc\.so\.6|libm\.so\.6|libpthread\.so\.0|libdl\.so\.2|librt\.so\.1|ld-linux.*)' || true)"
      [ -z "$bad" ] || fail "disallowed Linux dynamic libraries: $bad"
      ok "Linux binary links only dynamic glibc (${needed//$'\n'/ })"
    fi
    ;;
  Darwin)
    BAD_LIBS="$(otool -L "$HOST" | tail -n +2 | awk '{print $1}' | grep -v '^/usr/lib/\|^/System/Library/' || true)"
    [ -z "$BAD_LIBS" ] || fail "host links non-system libraries: $BAD_LIBS"
    ok "host links only system libraries ($(stat_size "$HOST") bytes, otool -L clean)"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    ok "Windows host ($HOST)"
    ;;
esac

echo "PASS: $pass checks"
