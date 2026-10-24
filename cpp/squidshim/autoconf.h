/* Minimal hand-written autoconf.h for the lmproxy Squid subset.
 *
 * Upstream Squid generates this header with GNU autoconf. lmproxy compiles a
 * small, curated subset of Squid sources (URL and HTTP/1 parsing) inside a
 * plain CMake build, so this file stands in for the generated one. It targets
 * POSIX systems (Linux, macOS, *BSD) with a C++17 compiler; the macros below
 * mirror what upstream configure detects on those hosts, pruned to what the
 * lmproxy subset actually tests.
 */

#ifndef LMPROXY_SQUID_AUTOCONF_H
#define LMPROXY_SQUID_AUTOCONF_H

/* Host type (informational) */
#define CONFIG_HOST_TYPE "lmproxy-portable"

/* Headers available on all supported hosts */
#define HAVE_ALLOCA 1
#define HAVE_ALLOCA_H 1
#define HAVE_ARPA_INET_H 1
#define HAVE_ARPA_TELNET_H 1
#define HAVE_ASSERT_H 1
#define HAVE_CTYPE_H 1
#define HAVE_DIRENT_H 1
#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_GETOPT_H 1
#define HAVE_GRP_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_MEMORY_H 1
#define HAVE_NETDB_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_NETINET_TCP_H 1
#define HAVE_NET_IF_H 1
#define HAVE_POLL_H 1
#define HAVE_PWD_H 1
#define HAVE_SIGNAL_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDDEF_H 1
#define HAVE_STDARG_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_IOCTL_H 1
#define HAVE_SYS_PARAM_H 1
#define HAVE_SYS_POLL_H 1
#define HAVE_SYS_RESOURCE_H 1
#define HAVE_SYS_SELECT_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_UIO_H 1
#define HAVE_SYS_UN_H 1
#define HAVE_SYS_WAIT_H 1
#define HAVE_TIME_H 1
#define HAVE_UNISTD_H 1

/* Functions available on all supported hosts */
#define HAVE_FD_MASK 1
#define HAVE_GETPAGESIZE 1
#define HAVE_GETTIMEOFDAY 1
#define HAVE_INET_ATON 1
#define HAVE_INET_NTOP 1
#define HAVE_INET_PTON 1
#define HAVE_LOCALTIME_R 1
#define HAVE_MEMMOVE 1
#define HAVE_MEMRCHR 1
#define HAVE_MEMSET 1
#define HAVE_MKTIME 1
#define HAVE_MODE_T 1
#define HAVE_SNPRINTF 1
#define HAVE_SRANDOM 1
#define HAVE_STRCASECMP 1
#define HAVE_STRERROR 1
#define HAVE_STRLCAT 1
#define HAVE_STRLCPY 1
#define HAVE_STRNCASECMP 1
#define HAVE_STRSEP 1
#define HAVE_STRTOLL 1
#define HAVE_SYSLOG 1
#define HAVE_TIMEGM 1
#define HAVE_VSNPRINTF 1

/* Types */
#define HAVE_IN_ADDR_T 1
#define HAVE_INTTYPES_H 1
#define HAVE_SOCKLEN_T 1
#define HAVE_STRUCT_ADDRINFO 1
#define HAVE_STRUCT_IN6_ADDR 1
#define HAVE_STRUCT_IN_ADDR 1
#define HAVE_STRUCT_RUSAGE 1
#define HAVE_STRUCT_SOCKADDR_IN6 1
#define HAVE_STRUCT_SOCKADDR_IN 1
#define HAVE_STRUCT_SOCKADDR_STORAGE 1
#define HAVE_STRUCT_TIMEVAL 1
#define HAVE_STRUCT_TM_TM_GMTOFF 1
#define HAVE_UINT16_T 1
#define HAVE_UINT32_T 1
#define HAVE_UINT64_T 1
#define HAVE_UINT8_T 1
#define HAVE_UINTPTR_T 1

/* Sizes (LP64 and LLP64 both give these for the integer types we use) */
#define SIZEOF_CHAR 1
#define SIZEOF_INT 4
#define SIZEOF_LONG 8
#define SIZEOF_LONG_LONG 8
#define SIZEOF_SHORT 2
#define SIZEOF_SIZE_T 8
#define SIZEOF_SSIZE_T 8
#define SIZEOF_VOIDP 8

/* Features the lmproxy subset deliberately disables */
#define FOLLOW_X_FORWARDED_FOR 0
#define USE_HTTP_VIOLATIONS 0
/* select() is the only portable event loop the subset needs */
#define USE_SELECT 1
/* #undef USE_POLL */
/* #undef USE_KQUEUE */
/* #undef USE_EPOLL */
/* #undef HAVE_OPENSSL */
/* #undef HAVE_LIBPCRE */
/* #undef HAVE_LIBSASL */
/* #undef HAVE_SYSTEMD */
/* #undef USE_ADAPTATION */
/* #undef USE_ANY_ACL */
/* #undef USE_AUTH */
/* #undef USE_DELAY_POOLS */
/* #undef USE_ECAP */
/* #undef USE_ICAP */
/* #undef USE_SNMP */

/* libtool-style module loading is not used by the subset */
/* #undef USE_DL_DLOPEN */

/* Misc defines squid headers expect */
#define SQUID_USE_EPOLL 0
#define SQUID_USE_KQUEUE 0
#define SQUID_USE_SELECT 1
#define DEFAULT_FD_SETSIZE 1024

#endif /* LMPROXY_SQUID_AUTOCONF_H */
