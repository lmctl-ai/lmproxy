cmake_minimum_required(VERSION 3.24)
project(lmproxy VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

option(LMPROXY_FULL_STATIC "Link the complete executable statically" ON)

# ---- vendored Squid subset -------------------------------------------------
# third_party/squid is git-ignored and synced by scripts/sync-squid.sh, pinned
# by squid.lock. Only the URL/HTTP-1 parsing subset is compiled; hub globals
# upstream defines in daemon-only translation units live in cpp/squidshim/.
set(SQUID_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/squid")

# Curated Squid sources (see THIRD_PARTY_NOTICES.md). Extend only with sources
# the lmproxy wrapper actually pulls in; keep the closure small on purpose.
set(SQUID_SOURCES
  # URL parsing
  src/anyp/Uri.cc
  src/anyp/UriScheme.cc
  src/anyp/ProtocolType.cc
  src/anyp/Host.cc
  # HTTP/1 message first-line + tokenizer parsing
  src/http/one/Parser.cc
  src/http/one/RequestParser.cc
  src/http/one/ResponseParser.cc
  src/http/one/Tokenizer.cc
  src/http/RequestMethod.cc
  src/http/MethodType.cc
  src/http/StatusCode.cc
  # tokenizer core
  src/parser/Tokenizer.cc
  src/parser/BinaryTokenizer.cc
  # SBuf and its support
  src/sbuf/SBuf.cc
  src/sbuf/MemBlob.cc
  src/sbuf/Algorithms.cc
  # base utilities
  src/base/CharacterSet.cc
  src/base/TextException.cc
  src/base/InstanceId.cc
  src/base/Here.cc
  src/base/IoManip.cc
  # IP address container used by Uri hosts
  src/ip/Address.cc
  src/ip/tools.cc
  # percent-encoding (rfc1738) and small C utilities
  lib/rfc1738.c
  compat/xalloc.cc
  compat/xstring.cc
  compat/assert.cc
  compat/compat.cc
  # macOS lacks GNU memrchr; upstream supplies the guarded portable fallback.
  compat/memrchr.cc
  # memory allocation (minimal, non-pool implementation)
  src/mem/minimal.cc
  # header-block terminator scan used by the HTTP/1 parser
  src/mime_header.cc
  # SBuf destruct-time statistics
  src/sbuf/Stats.cc
  # Raw debug-printing helper
  src/base/Raw.cc
  # Assure/ReportAndThrow support
  src/base/Assure.cc
)
list(TRANSFORM SQUID_SOURCES PREPEND "${SQUID_ROOT}/")

# ---- embedded DSL schema ----------------------------------------------------
set(SCHEMA_JSON "${CMAKE_CURRENT_SOURCE_DIR}/schema/lmproxy.dsl.json")
set(GENERATED_DIR "${CMAKE_BINARY_DIR}/generated")
set(GENERATED_SCHEMA "${GENERATED_DIR}/schema_embedded.hpp")
add_custom_command(
  OUTPUT "${GENERATED_SCHEMA}"
  COMMAND "${CMAKE_COMMAND}"
    -DINPUT="${SCHEMA_JSON}"
    -DOUTPUT="${GENERATED_SCHEMA}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/embed_schema.cmake"
  DEPENDS "${SCHEMA_JSON}" "${CMAKE_CURRENT_SOURCE_DIR}/cmake/embed_schema.cmake"
  COMMENT "Embedding schema/lmproxy.dsl.json"
)
add_custom_target(lmproxy_schema DEPENDS "${GENERATED_SCHEMA}")

add_executable(lmproxy
  cpp/main.cpp
  cpp/proxy.cpp
  cpp/squidshim/stubs.cc
  ${SQUID_SOURCES}
  "${GENERATED_SCHEMA}"
)
add_dependencies(lmproxy lmproxy_schema)

# cpp/squidshim/ (our autoconf.h stand-in and stubs) shadows upstream include/
# and must come first; otherwise the include layout mirrors the squid build.
target_include_directories(lmproxy PRIVATE
  cpp/squidshim
  cpp
  "${SQUID_ROOT}/include"
  "${SQUID_ROOT}/lib"
  "${SQUID_ROOT}/src"
  "${SQUID_ROOT}"
  "${GENERATED_DIR}"
)
target_compile_definitions(lmproxy PRIVATE HAVE_CONFIG_H)
# Squid sources are third-party: silence their warnings, keep ours strict.
set_source_files_properties(${SQUID_SOURCES} PROPERTIES
  COMPILE_OPTIONS "-w"
)
# squid's compat/debug.h defines a GNU named-variadic macro; GCC cannot
# pragma-control the pedantic warning it triggers, so silence it just for
# the TUs that include squid headers.
set_source_files_properties(cpp/proxy.cpp cpp/squidshim/stubs.cc PROPERTIES
  COMPILE_OPTIONS "-Wno-variadic-macros"
)
target_compile_options(lmproxy PRIVATE -Wall -Wextra -Wpedantic)
target_compile_definitions(lmproxy PRIVATE LMPROXY_VERSION="${PROJECT_VERSION}")

# Static linking: no runtime dependency beyond the OS C library.
# ("Clang" also matches AppleClang; macOS has no -static/-static-libstdc++.)
if((CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang") AND NOT APPLE)
  target_link_options(lmproxy PRIVATE -static-libstdc++ -static-libgcc)
  if(LMPROXY_FULL_STATIC)
    target_link_options(lmproxy PRIVATE -static)
  endif()
endif()
