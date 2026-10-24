#pragma once
// lmproxy wrapper over the Squid URL and HTTP/1 parsing engine.
//
// This is the only lmproxy-authored code that includes Squid headers. It
// keeps all squid.h fallout in one translation unit pair; the CLI host
// (main.cpp) talks to this plain interface only.

#include <optional>
#include <string>
#include <vector>

namespace lmproxy {

struct Url {
  std::string original;
  std::string scheme;
  std::string host;
  bool hostIsIp = false;
  std::string userinfo;
  std::optional<int> port;
  std::string path; // path including query, as Squid parses it
  bool valid = false;
  std::string error;
  bool has_explicit_port = false;
};

struct Message {
  std::string kind; // "request" or "response"
  int versionMajor = 0;
  int versionMinor = 0;
  // request-line:
  std::string method;
  std::string target;
  // status-line:
  int status = 0;
  std::string reason;
  // mime header block (raw, excluding the first line):
  std::string headers;
  bool complete = false; // first line + header block parsed
  std::string error;
};

// Parse one absolute URL the way Squid's AnyP::Uri::parse does. Never throws:
// syntax problems land in Url::error.
Url parse_url(const std::string &text);

// Parse an HTTP/1.x request message prefix (request-line + mime headers).
// Feeding more bytes than the headers block is fine; they are ignored.
Message parse_request(const std::string &raw);

// Parse an HTTP/1.x response message prefix (status-line + mime headers).
Message parse_response(const std::string &raw);

// Case-insensitive lookup of one header in a raw mime header block
// (CRLF-separated "Name: value" lines, no obs-fold). Empty string when absent.
std::string header_get(const std::string &rawBlock, const std::string &name);

// Distinct header field names, in order of first appearance, case preserved.
std::vector<std::string> header_names(const std::string &rawBlock);

// RFC 1738/3986 percent-decoding and -encoding of the unreserved set.
std::string percent_decode(const std::string &text);
std::string percent_encode(const std::string &text);

// Squid runtime bits the subset needs but that upstream initializes in
// daemon startup (debug streams, the Config global, ...). Called once
// from main() before any parsing happens.
void squid_init();

} // namespace lmproxy
