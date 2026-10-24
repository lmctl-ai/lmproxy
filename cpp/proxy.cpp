#include "proxy.hpp"

#include "squid.h"
#include "anyp/Uri.h"
#include "http/one/RequestParser.h"
#include "http/one/ResponseParser.h"
#include "http/RequestMethod.h"
#include "SquidConfig.h"
#include "rfc1738.h"

namespace lmproxy {

Url parse_url(const std::string &text) {
  Url out;
  out.original = text;
  try {
    AnyP::Uri uri;
    const SBuf input(text.c_str(), text.size());
    // Host-less inputs (relative references, asterisk-form) are reported as
    // invalid by the host() check below; Uri::parse needs a method for its
    // method-specific scheme handling, CONNECT and OPTIONS aside GET is the
    // least surprising.
    if (!uri.parse(HttpRequestMethod(Http::METHOD_GET), input))
      throw TextException("invalid URI", Here());
    out.scheme = uri.getScheme().image().c_str();
    out.host = uri.host();
    out.hostIsIp = uri.hostIsNumeric() != 0;
    // The host field is the address; brackets belong to URL serialization.
    if (out.hostIsIp && out.host.size() >= 2 && out.host.front() == '[' && out.host.back() == ']')
      out.host = out.host.substr(1, out.host.size() - 2);
    out.userinfo.assign(uri.userInfo().rawContent(), uri.userInfo().length());
    const auto scheme_end = text.find("://");
    if (scheme_end != std::string::npos) {
      const auto start = scheme_end + 3;
      const auto end = text.find_first_of("/?#", start);
      auto authority = text.substr(start, end == std::string::npos ? end : end - start);
      const auto user_end = authority.rfind('@');
      if (user_end != std::string::npos) authority.erase(0, user_end + 1);
      if (!authority.empty() && authority.front() == '[') {
        const auto close = authority.find(']');
        out.has_explicit_port = close != std::string::npos && close + 1 < authority.size() && authority[close + 1] == ':';
      } else out.has_explicit_port = authority.find(':') != std::string::npos;
    }
    if (const auto port = uri.port())
      out.port = static_cast<int>(*port);
    const auto p = uri.path();
    out.path.assign(p.rawContent(), p.length());
    out.valid = !out.host.empty();
    if (!out.valid)
      out.error = "no host in URL";
  } catch (const std::exception &e) {
    out.valid = false;
    out.error = e.what();
  } catch (...) {
    out.valid = false;
    out.error = "parse failure";
  }
  return out;
}

namespace {
// Feed raw bytes to an Http1 parser, reporting the first syntax problem as
// the Message error. parsers throw InsufficientInput on partial lines and
// set parseStatusCode for syntax errors.
template <class Parser, class Fill>
Message parse_message(const std::string &raw, const char *kind, Fill fill) {
  Message out;
  out.kind = kind;
  try {
    Parser parser;
    parser.parse(SBuf(raw.c_str(), raw.size()));
    fill(parser, out);
    out.versionMajor = parser.messageProtocol().major;
    out.versionMinor = parser.messageProtocol().minor;
    const auto block = parser.mimeHeader();
    out.headers.assign(block.rawContent(), block.length());
    out.complete = true;
  } catch (const std::exception &e) {
    out.error = e.what();
  } catch (...) {
    out.error = "parse failure";
  }
  return out;
}
} // namespace

Message parse_request(const std::string &raw) {
  return parse_message<Http1::RequestParser>(raw, "request", [](auto &parser, Message &out) {
    const SBuf method = parser.method().image();
    out.method.assign(method.rawContent(), method.length());
    const auto uri = parser.requestUri();
    out.target.assign(uri.rawContent(), uri.length());
  });
}

Message parse_response(const std::string &raw) {
  return parse_message<Http1::ResponseParser>(raw, "response", [](auto &parser, Message &out) {
    out.status = static_cast<int>(parser.messageStatus());
    const auto reason = parser.reasonPhrase();
    out.reason.assign(reason.rawContent(), reason.length());
  });
}

std::string header_get(const std::string &rawBlock, const std::string &name) {
  const std::string wanted = name;
  size_t pos = 0;
  while (pos < rawBlock.size()) {
    const size_t eol = rawBlock.find("\n", pos);
    const std::string line = rawBlock.substr(pos, eol == std::string::npos ? std::string::npos : eol - pos);
    pos = eol == std::string::npos ? rawBlock.size() : eol + 1;
    if (line.empty() || line.front() == ' ' || line.front() == '\t')
      continue; // block terminator or obs-fold: not supported, skip
    const size_t colon = line.find(':');
    if (colon == std::string::npos)
      continue;
    std::string field = line.substr(0, colon);
    while (!field.empty() && (field.back() == '\r' || field.back() == ' ' || field.back() == '\t'))
      field.pop_back();
    if (field.size() != wanted.size())
      continue;
    bool same = true;
    for (size_t i = 0; i < field.size(); ++i)
      same = same && std::tolower(static_cast<unsigned char>(field[i])) == std::tolower(static_cast<unsigned char>(wanted[i]));
    if (!same)
      continue;
    std::string value = line.substr(colon + 1);
    while (!value.empty() && (value.front() == ' ' || value.front() == '\t'))
      value.erase(value.begin());
    while (!value.empty() && (value.back() == '\r' || value.back() == ' ' || value.back() == '\t'))
      value.pop_back();
    return value;
  }
  return "";
}

std::vector<std::string> header_names(const std::string &rawBlock) {
  std::vector<std::string> names;
  size_t pos = 0;
  while (pos < rawBlock.size()) {
    const size_t eol = rawBlock.find("\n", pos);
    const std::string line = rawBlock.substr(pos, eol == std::string::npos ? std::string::npos : eol - pos);
    pos = eol == std::string::npos ? rawBlock.size() : eol + 1;
    if (line.empty() || line.front() == ' ' || line.front() == '\t')
      continue;
    const size_t colon = line.find(':');
    if (colon == std::string::npos)
      continue;
    std::string field = line.substr(0, colon);
    while (!field.empty() && (field.back() == '\r' || field.back() == ' ' || field.back() == '\t'))
      field.pop_back();
    bool seen = false;
    for (const auto &n : names)
      seen = seen || n.size() == field.size();
    if (!seen)
      names.push_back(field);
  }
  return names;
}

std::string percent_decode(const std::string &text) {
  // rfc1738_unescape unescapes in place.
  std::vector<char> buf(text.begin(), text.end());
  buf.push_back('\0');
  rfc1738_unescape(buf.data());
  return buf.data();
}

std::string percent_encode(const std::string &text) {
  char *tmp = rfc1738_escape(text.c_str());
  std::string out = tmp ? tmp : "";
  xfree(tmp);
  return out;
}

void squid_init() {
  // Upstream initializes memory pools, debug streams and the Config global
  // during daemon startup (cache_cf.cc applies the cf.data.pre defaults).
  // The lmproxy subset relies on default-constructed globals except for the
  // header-size limits, which the HTTP/1 parser enforces while grabbing the
  // MIME block (a zero limit would reject every message).
  Config.maxRequestHeaderSize = 64 * 1024; // request_header_max_size default
  Config.maxReplyHeaderSize = 64 * 1024;   // reply_header_max_size default
}

} // namespace lmproxy
