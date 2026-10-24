// Stubs for Squid "hub" symbols the lmproxy subset references but that
// upstream defines in daemon-oriented translation units pulling in large
// parts of the proxy (config parsing, event loops, storage, ...). Keep each
// stub minimal and faithful to the upstream declaration.
//
// If a stub ever needs real behavior, prefer compiling the upstream source
// over growing this file.

#include "squid.h"

#include "debug/Stream.h"
#include "helper/ChildConfig.h"
#include "HttpHeader.h"
#include "HttpRequest.h"
#include "SquidConfig.h"

// Defined upstream in src/String.cc together with the legacy String class.
// The lmproxy subset needs only these two predicates.
int
stringHasWhitespace(const char *s)
{
  if (!s)
    return 0;
  for (; *s; ++s) {
    if (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n')
      return 1;
  }
  return 0;
}

int
stringHasCntl(const char *s)
{
  if (!s)
    return 0;
  for (; *s; ++s) {
    const auto c = static_cast<unsigned char>(*s);
    if (c < 0x20 && *s != '\t' || c == 0x7f)
      return 1;
  }
  return 0;
}

// Defined upstream in src/debug.cc, which pulls in the daemon's logging and
// cache_log machinery. lmproxy never enables debugging, so the debug stream
// is a discarded buffer.
int Debug::Levels[MAX_DEBUG_SECTIONS];

std::ostringstream &
Debug::Start(const int, const int)
{
  static std::ostringstream sink;
  return sink;
}

void
Debug::Finish()
{}

std::ostream &
Debug::Extra(std::ostream &os)
{
  return os;
}

// Also defined in src/debug.cc; Raw::print() consults the active context.
Debug::Context *Debug::Current = nullptr;

// Defined upstream in src/helper/ChildConfig.cc, whose translation unit
// includes the daemon config parser. Only the default construction of
// Config's member is needed here; mirrors the upstream ctor exactly.
Helper::ChildConfig::ChildConfig():
  n_max(0),
  n_startup(0),
  n_idle(1),
  concurrency(0),
  n_running(0),
  n_active(0),
  queue_size(0),
  onPersistentOverload(actDie),
  defaultQueueSize(true)
{}

// Defined upstream in src/globals.cc alongside the full daemon configuration.
// Uri.cc consults a few Config.* members while parsing; zero-initialized
// defaults preserve upstream behavior for the subset.
SquidConfig Config;

// Referenced only by Uri.cc's urlCheckRequest()/urlCanonicalFakeHttps(), which
// the lmproxy subset never calls. Faithful no-op stand-ins so the linker is
// satisfied without dragging in HttpHeader.cc and HttpRequest.cc.
int64_t
HttpHeader::getInt64(Http::HdrType) const
{
  return -1;
}

char *
HttpRequest::canonicalCleanUrl() const
{
  return nullptr;
}
