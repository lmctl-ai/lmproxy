cmake_minimum_required(VERSION 3.24)
project(lmproxy VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

option(LMPROXY_FULL_STATIC "Link glibc statically too (off per policy: glibc stays dynamic)" OFF)
set(LMPROXY_HOST_SCHEMA "${CMAKE_CURRENT_SOURCE_DIR}/schema/lmproxy.host.json")

# ---- OpenSSL (Static) -------------------------------------------------------
set(OPENSSL_USE_STATIC_LIBS TRUE)
find_package(OpenSSL REQUIRED)
if(NOT OPENSSL_ROOT_DIR AND DEFINED OPENSSL_INCLUDE_DIR)
  get_filename_component(OPENSSL_ROOT_DIR "${OPENSSL_INCLUDE_DIR}/.." ABSOLUTE)
endif()

# ---- Full Squid Engine (Static Convenience Libraries) -----------------------
set(SQUID_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/squid")
set(SQUID_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/squid-build")
set(SQUID_ENGINE_LIB "${SQUID_BUILD_DIR}/src/libsquid_objects.a")

# Ensure the embedded Squid engine static libraries are configured and compiled
message(STATUS "Configuring and building embedded Squid engine...")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    "BUILD_DIR=${SQUID_BUILD_DIR}"
    "SOURCE_DIR=${SQUID_ROOT}"
    "OPENSSL_ROOT_DIR=${OPENSSL_ROOT_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/scripts/build-squid.sh"
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  RESULT_VARIABLE SQUID_BUILD_RESULT
)
if(NOT SQUID_BUILD_RESULT EQUAL 0)
  message(FATAL_ERROR "Failed to build embedded Squid engine (exit code: ${SQUID_BUILD_RESULT})")
endif()

# ---- embedded DSL schema ----------------------------------------------------
set(SCHEMA_JSON "${CMAKE_CURRENT_SOURCE_DIR}/schema/lmproxy.dsl.json")
# Keep the exact host bytes; standard declarations are compiler built-ins.
configure_file("${LMPROXY_HOST_SCHEMA}" "${SCHEMA_JSON}" COPYONLY)
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
  cpp/engine/config.cpp
  cpp/engine/engine.cpp
  "${GENERATED_SCHEMA}"
)
add_dependencies(lmproxy lmproxy_schema)

target_include_directories(lmproxy PRIVATE
  cpp
  cpp/engine
  "${SQUID_BUILD_DIR}/include"
  "${SQUID_ROOT}/include"
  "${SQUID_ROOT}/lib"
  "${SQUID_ROOT}/src"
  "${SQUID_ROOT}"
  "${GENERATED_DIR}"
  ${OPENSSL_INCLUDE_DIR}
)
target_compile_definitions(lmproxy PRIVATE HAVE_CONFIG_H LMPROXY_VERSION="${PROJECT_VERSION}")
target_compile_options(lmproxy PRIVATE -Wall -Wextra)

# Gather static convenience libraries from staged Squid engine
file(GLOB_RECURSE ALL_SQUID_A "${SQUID_BUILD_DIR}/*.a")
set(SQUID_STATIC_LIBS "")
foreach(a_file ${ALL_SQUID_A})
  get_filename_component(a_name "${a_file}" NAME)
  if(NOT "${a_name}" STREQUAL "libcompatsquid.a" AND NOT "${a_name}" STREQUAL "libsquid_objects.a")
    list(APPEND SQUID_STATIC_LIBS "${a_file}")
  endif()
endforeach()

if(APPLE)
  target_link_libraries(lmproxy PRIVATE
    "-Wl,-force_load,${SQUID_ENGINE_LIB}"
    ${SQUID_STATIC_LIBS}
    "${SQUID_BUILD_DIR}/compat/.libs/libcompatsquid.a"
    OpenSSL::SSL
    OpenSSL::Crypto
    "-framework CoreFoundation"
    "-framework Security"
    z
    resolv
  )
else()
  target_link_libraries(lmproxy PRIVATE
    -Wl,--whole-archive "${SQUID_ENGINE_LIB}" -Wl,--no-whole-archive
    -Wl,--start-group
    ${SQUID_STATIC_LIBS}
    "${SQUID_BUILD_DIR}/compat/.libs/libcompatsquid.a"
    -Wl,--end-group
    OpenSSL::SSL
    OpenSSL::Crypto
    crypt
    atomic
    pthread
    dl
    rt
    m
  )
  if((CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang") AND NOT APPLE)
    target_link_options(lmproxy PRIVATE -static-libstdc++ -static-libgcc)
    if(LMPROXY_FULL_STATIC)
      target_link_options(lmproxy PRIVATE -static)
    endif()
  endif()
endif()
