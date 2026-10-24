// lmproxy: Squid's URL and HTTP/1 parsing engine as one statically linked,
// scriptable CLI. Host for the lmscript DSL plus small parse-* subcommands.
#include "proxy.hpp"
#include "dslvm.hpp"
#include "stdlib/string.hpp"
#include "stdlib/collections.hpp"
#include "schema_embedded.hpp"

#include <cctype>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#endif

namespace {
using dslvm::Args;
using dslvm::Value;

// ---- arenas for schema object handles ----
struct Host {
  std::vector<std::unique_ptr<lmproxy::Url>> urls;
  std::vector<std::unique_ptr<lmproxy::Message>> messages;
  dslvm::stdlib::Collections collections;
  template <class T>
  Value hold(std::vector<std::unique_ptr<T>> &arena, const char *type, T value) {
    if (arena.size() >= 65536)
      throw dslvm::Error(std::string(type) + " object limit exceeded (65536)");
    arena.push_back(std::make_unique<T>(std::move(value)));
    return Value::object(type, arena.back().get());
  }
};

template <class T> T *self(void *p) { return static_cast<T *>(p); }

lmproxy::Url *url_of(void *p, const char *who) {
  auto *u = self<lmproxy::Url>(p);
  if (!u) throw dslvm::Error(std::string(who) + ": stale Url handle");
  return u;
}
lmproxy::Message *msg_of(void *p, const char *who) {
  auto *m = self<lmproxy::Message>(p);
  if (!m) throw dslvm::Error(std::string(who) + ": stale Message handle");
  return m;
}

std::string read_file(const std::string &path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) throw dslvm::Error("cannot read " + path);
  std::ostringstream data;
  data << in.rdbuf();
  if (in.bad()) throw dslvm::Error("cannot read " + path);
  return data.str();
}

// ---- JSON output for the plain parse-* subcommands ----
std::string json_escape(const std::string &s) {
  std::string out;
  for (unsigned char c : s) {
    switch (c) {
    case '"': out += "\\\""; break;
    case '\\': out += "\\\\"; break;
    case '\n': out += "\\n"; break;
    case '\r': out += "\\r"; break;
    case '\t': out += "\\t"; break;
    default:
      if (c < 0x20) {
        char buf[8];
        std::snprintf(buf, sizeof buf, "\\u%04x", c);
        out += buf;
      } else out += static_cast<char>(c);
    }
  }
  return out;
}
std::string json_string(const std::string &s) { return "\"" + json_escape(s) + "\""; }

std::string url_json(const lmproxy::Url &u) {
  std::ostringstream j;
  j << "{\"valid\":" << (u.valid ? "true" : "false");
  if (u.valid) {
    j << ",\"scheme\":" << json_string(u.scheme)
      << ",\"host\":" << json_string(u.host)
      << ",\"host_is_ip\":" << (u.hostIsIp ? "true" : "false")
      << ",\"userinfo\":" << json_string(u.userinfo)
      << ",\"port\":" << (u.port ? std::to_string(*u.port) : "0")
      << ",\"path\":" << json_string(u.path);
  }
  if (!u.error.empty()) j << ",\"error\":" << json_string(u.error);
  j << "}";
  return j.str();
}

std::string message_json(const lmproxy::Message &m) {
  std::ostringstream j;
  j << "{\"kind\":" << json_string(m.kind)
    << ",\"complete\":" << (m.complete ? "true" : "false")
    << ",\"version\":\"HTTP/" << m.versionMajor << "." << m.versionMinor << "\"";
  if (m.kind == "request")
    j << ",\"method\":" << json_string(m.method) << ",\"target\":" << json_string(m.target);
  else
    j << ",\"status\":" << m.status << ",\"reason\":" << json_string(m.reason);
  j << ",\"headers\":{";
  bool first = true;
  for (const auto &name : lmproxy::header_names(m.headers)) {
    if (!first) j << ",";
    first = false;
    j << json_string(name) << ":" << json_string(lmproxy::header_get(m.headers, name));
  }
  j << "}";
  if (!m.error.empty()) j << ",\"error\":" << json_string(m.error);
  j << "}";
  return j.str();
}

// ---- DSL registry: the schema implementation ----
void register_host(dslvm::Registry &reg, Host &host) {
  reg.context("proxy", "Proxy");
  dslvm::stdlib::register_string(reg);
  dslvm::stdlib::register_collections(reg, host.collections);

  reg.function("println", {"string"}, "void", [](Args &args) {
    std::cout << args[0].s << "\n";
    return Value::none();
  });
  reg.function("parse_url", {"string"}, "Url", [&host](Args &args) {
    return host.hold(host.urls, "Url", lmproxy::parse_url(args[0].s));
  });
  reg.function("parse_request", {"string"}, "Message", [&host](Args &args) {
    return host.hold(host.messages, "Message", lmproxy::parse_request(args[0].s));
  });
  reg.function("parse_response", {"string"}, "Message", [&host](Args &args) {
    return host.hold(host.messages, "Message", lmproxy::parse_response(args[0].s));
  });
  reg.function("percent_decode", {"string"}, "string", [](Args &args) {
    return Value::string(lmproxy::percent_decode(args[0].s));
  });
  reg.function("percent_encode", {"string"}, "string", [](Args &args) {
    return Value::string(lmproxy::percent_encode(args[0].s));
  });

  // The "proxy" context object (type Proxy) exposes the same entry points as
  // methods: the DSL compiler resolves proxy.parse_url(...) as a method call
  // on the context object, not a free function call.
  reg.method("Proxy", "parse_url", {"string"}, "Url", [&host](void *, Args &args) {
    return host.hold(host.urls, "Url", lmproxy::parse_url(args[0].s));
  });
  reg.method("Proxy", "parse_request", {"string"}, "Message", [&host](void *, Args &args) {
    return host.hold(host.messages, "Message", lmproxy::parse_request(args[0].s));
  });
  reg.method("Proxy", "parse_response", {"string"}, "Message", [&host](void *, Args &args) {
    return host.hold(host.messages, "Message", lmproxy::parse_response(args[0].s));
  });
  reg.method("Proxy", "percent_decode", {"string"}, "string", [](void *, Args &args) {
    return Value::string(lmproxy::percent_decode(args[0].s));
  });
  reg.method("Proxy", "percent_encode", {"string"}, "string", [](void *, Args &args) {
    return Value::string(lmproxy::percent_encode(args[0].s));
  });

  const auto url_method = [&reg](const char *name, auto impl) {
    reg.method("Url", name, {}, "string", [name, impl](void *s, Args &) {
      return Value::string(impl(url_of(s, name)));
    });
  };
  url_method("raw", [](const lmproxy::Url *u) { return u->original; });
  url_method("scheme", [](const lmproxy::Url *u) { return u->scheme; });
  url_method("host", [](const lmproxy::Url *u) { return u->host; });
  url_method("userinfo", [](const lmproxy::Url *u) { return u->userinfo; });
  url_method("path", [](const lmproxy::Url *u) { return u->path; });
  url_method("error", [](const lmproxy::Url *u) { return u->error; });
  reg.method("Url", "host_is_ip", {}, "bool", [](void *s, Args &) {
    return Value::boolean(url_of(s, "host_is_ip")->hostIsIp);
  });
  reg.method("Url", "port", {}, "int", [](void *s, Args &) {
    const auto *u = url_of(s, "port");
    return Value::integer(u->port ? *u->port : 0);
  });
  reg.method("Url", "has_port", {}, "bool", [](void *s, Args &) {
    return Value::boolean(url_of(s, "has_port")->has_explicit_port);
  });
  reg.method("Url", "valid", {}, "bool", [](void *s, Args &) {
    return Value::boolean(url_of(s, "valid")->valid);
  });

  const auto msg_method = [&reg](const char *name, auto impl) {
    reg.method("Message", name, {}, "string", [name, impl](void *s, Args &) {
      return Value::string(impl(msg_of(s, name)));
    });
  };
  msg_method("kind", [](const lmproxy::Message *m) { return m->kind; });
  msg_method("method", [](const lmproxy::Message *m) { return m->method; });
  msg_method("target", [](const lmproxy::Message *m) { return m->target; });
  msg_method("reason", [](const lmproxy::Message *m) { return m->reason; });
  msg_method("error", [](const lmproxy::Message *m) { return m->error; });
  msg_method("version", [](const lmproxy::Message *m) {
    return "HTTP/" + std::to_string(m->versionMajor) + "." + std::to_string(m->versionMinor);
  });
  reg.method("Message", "status", {}, "int", [](void *s, Args &) {
    return Value::integer(msg_of(s, "status")->status);
  });
  reg.method("Message", "complete", {}, "bool", [](void *s, Args &) {
    return Value::boolean(msg_of(s, "complete")->complete);
  });
  reg.method("Message", "header", {"string"}, "string", [](void *s, Args &args) {
    return Value::string(lmproxy::header_get(msg_of(s, "header")->headers, args[0].s));
  });
  reg.method("Message", "header_count", {}, "int", [](void *s, Args &) {
    return Value::integer(static_cast<int64_t>(lmproxy::header_names(msg_of(s, "header_count")->headers).size()));
  });
  reg.method("Message", "header_names", {}, "StrList", [&host](void *s, Args &) {
    return Value::object("StrList", host.collections.make_str_list(lmproxy::header_names(msg_of(s, "header_names")->headers)));
  });


}

void print_schema_summary(const dslvm::Registry &reg) {
  for (const auto &line : reg.signatures()) std::cout << line << "\n";
}
} // namespace

int main(int argc, char **argv) {
#ifdef _WIN32
  _setmode(_fileno(stdout), _O_BINARY);
  _setmode(_fileno(stderr), _O_BINARY);
#endif
  lmproxy::squid_init();
  Host host;
  dslvm::Registry reg;
  register_host(reg, host);
  const std::string usage =
      "usage: lmproxy --version | --dsl-schema [--json] | --dsl-signatures\n"
      "       lmproxy parse-url URL [URL ...]\n"
      "       lmproxy parse-request FILE\n"
      "       lmproxy parse-response FILE\n"
      "       lmproxy --dsl FILE [FILE ...]\n";
  if (argc == 2 && std::string(argv[1]) == "--version") {
    std::cout << "lmproxy " LMPROXY_VERSION "\n";
    return std::cout ? 0 : 4;
  }
  if (argc >= 2 && std::string(argv[1]) == "--dsl-schema") {
    if (argc == 2) {
      print_schema_summary(reg);
      return std::cout ? 0 : 4;
    }
    if (argc == 3 && std::string(argv[2]) == "--json") {
      std::cout.write(reinterpret_cast<const char *>(lmproxy::embedded_schema),
                      static_cast<std::streamsize>(lmproxy::embedded_schema_size));
      return std::cout ? 0 : 4;
    }
    std::cerr << usage;
    return 2;
  }
  if (argc == 2 && std::string(argv[1]) == "--dsl-signatures") {
    for (const auto &signature : reg.signatures()) std::cout << signature << "\n";
    return 0;
  }
  if (argc >= 3 && std::string(argv[1]) == "parse-url") {
    for (int i = 2; i < argc; ++i)
      std::cout << url_json(lmproxy::parse_url(argv[i])) << "\n";
    return std::cout ? 0 : 4;
  }
  if (argc == 3 && (std::string(argv[1]) == "parse-request" || std::string(argv[1]) == "parse-response")) {
    std::string raw;
    const std::string path = argv[2];
    if (path == "-") {
      std::ostringstream data;
      data << std::cin.rdbuf();
      raw = data.str();
    } else {
      try { raw = read_file(path); }
      catch (const dslvm::Error &e) { std::cerr << e.what() << "\n"; return 3; }
    }
    const auto m = std::string(argv[1]) == "parse-request" ? lmproxy::parse_request(raw)
                                                           : lmproxy::parse_response(raw);
    std::cout << message_json(m) << "\n";
    return std::cout ? 0 : 4;
  }
  if (argc >= 3 && std::string(argv[1]) == "--dsl") {
    for (int i = 2; i < argc; ++i) {
      if (std::string(argv[i]).empty() || std::string(argv[i]).rfind("--", 0) == 0) {
        std::cerr << usage;
        return 2;
      }
    }
    const std::string schema(reinterpret_cast<const char *>(lmproxy::embedded_schema),
                             lmproxy::embedded_schema_size);
    dslvm::Context context;
    context.set("proxy", &host);
    std::vector<dslvm::Program> programs;
    for (int i = 2; i < argc; ++i) {
      try {
        programs.push_back(dslvm::Program::load(dslvm::read_file(argv[i]), schema, reg));
      } catch (const dslvm::Error &error) {
        return dslvm::report_error("load", error);
      }
    }
    for (const auto &program : programs) {
      try {
        host.collections.reset();
        program.run(context, reg);
      } catch (const dslvm::Error &error) {
        return dslvm::report_error("run", error);
      }
      dslvm::report_ok();
    }
    return 0;
  }
  std::cerr << usage;
  return 2;
}
