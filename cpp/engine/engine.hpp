#pragma once

#include <string>
#include <vector>
#include <memory>
#include <functional>

namespace lmproxy {

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
};

// Generates an ephemeral squid.conf configuration string and writes it to workDir/squid.conf
std::string prepare_squid_conf(const ProxyConfig &cfg, const std::string &workDir);

// Ensures CA certificate and private key exist for SSL bumping (generates self-signed if needed)
bool ensure_ca_certificate(const std::string &certPath, const std::string &keyPath);

// Runs the Squid proxy engine with the specified configuration.
// Runs the event loop until SIGINT/SIGTERM.
int run_proxy_engine(const ProxyConfig &cfg);

// Forward declaration of Squid's main routine
int squid_main_entry(int argc, char **argv);

} // namespace lmproxy
