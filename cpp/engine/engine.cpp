#include "engine.hpp"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>
#include <unistd.h>
#include <sys/stat.h>

// Declared in Squid's src/main.cc:
extern int SquidMain(int argc, char **argv);

namespace lmproxy {

int squid_main_entry(int argc, char **argv) {
  return SquidMain(argc, argv);
}

int run_proxy_engine(const ProxyConfig &cfg) {
  // Create a working temporary directory for ephemeral config, pid, and certs
  char tmpDirTemplate[] = "/tmp/lmproxy-run-XXXXXX";
  char *workDir = mkdtemp(tmpDirTemplate);
  if (!workDir) {
    std::cerr << "Failed to create temporary working directory\n";
    return 1;
  }

  std::string confPath;
  try {
    confPath = prepare_squid_conf(cfg, workDir);
  } catch (const std::exception &e) {
    std::cerr << "Configuration error: " << e.what() << "\n";
    return 1;
  }

  std::vector<std::string> args = {
    "lmproxy",
    "-f", confPath,
    "-N" // Run in foreground (no daemon fork)
  };

  if (cfg.debugLevel > 0) {
    args.push_back("-d");
    args.push_back(std::to_string(cfg.debugLevel));
  }

  // Convert to argv
  std::vector<char *> c_args;
  c_args.reserve(args.size() + 1);
  for (auto &arg : args) {
    c_args.push_back(const_cast<char *>(arg.c_str()));
  }
  c_args.push_back(nullptr);

  std::cout << "lmproxy starting " << cfg.mode << " proxy on "
            << cfg.bindAddress << ":" << cfg.port
            << (cfg.sslBump ? " with SSL-bump" : "") << "...\n";

  int ret = squid_main_entry(static_cast<int>(args.size()), c_args.data());

  return ret;
}

} // namespace lmproxy
