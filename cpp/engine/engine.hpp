#pragma once

#include <string>
#include <vector>
#include <memory>
#include <functional>

namespace lmproxy {

struct ProxyRule {
  enum class Type {
    Redirect, // HTTP 307 redirect
    Route     // Cache peer transparent routing
  };
  Type type;
  std::string pattern; // domain (e.g. api.example.com) or regex
  std::string target;  // URL for redirect, host:port for route
};

struct ProxyConfig {
  std::string mode = "forward"; // "forward", "intercept", "custom"
  int port = 3128;
  std::string bindAddress = "127.0.0.1";
  bool sslBump = false;
  std::string caCertPath;
  std::string caKeyPath;
  std::string customConfigFile;
  int debugLevel = 0;
  bool foreground = true;

  // Traffic inspection & reverse engineering
  bool tap = false;
  std::string recordFile;

  // Traffic swapping & mocking
  std::vector<ProxyRule> rules;

  // Self executable path
  std::string exePath;
};

// Generates an ephemeral squid.conf configuration string and writes it to workDir/squid.conf
std::string prepare_squid_conf(const ProxyConfig &cfg, const std::string &workDir);

// Ensures CA certificate and private key exist for SSL bumping (generates self-signed if needed)
bool ensure_ca_certificate(const std::string &certPath, const std::string &keyPath);

// Initializes dynamic certificate database in dbDir
bool init_ssl_db(const std::string &dbDir);

// Runs the Squid proxy engine with the specified configuration.
int run_proxy_engine(const ProxyConfig &cfg);

// Forward declaration of Squid's main routine
int squid_main_entry(int argc, char **argv);

// Forward declaration of certgen helper entry
int certgen_main_entry(int argc, char **argv);

// Gets current executable path
std::string get_self_executable_path();

} // namespace lmproxy
