# Invocation envelope and run_lmcode (2026-11-04)

The current compiler (lmscript 0.2.460) writes no bytecode files and has no compileDsl library API, so the pinned .dslb fixtures and scripts/compile-lmcode-fixture.mjs are gone. A script runs a block with r = run_lmcode(p): lmscript compiles it into a private program file, starts lmproxy --lmcode FILE and reads one terminal frame back. r is that envelope (r.ok, r.result, r.phase, r.code, r.message), so a failure is data and a script must check r.ok. What a block prints with println goes to lmscript's stdout; it is not in r.

Host side (cpp/main.cpp, SDK lmcode-cpp 93bddf1): --lmcode builds one InvocationResults. Every file loads first; each slot is selected, run and completed in order; the first failure stops the run; write_frame prints the single frame. Exit codes: 0 success; 2 cli (usage or invalid metadata, with a frame; usage text also on stderr); 3 load or run, including a missing program file; 4 application or output failure. The other subcommands (parse-*, forward, intercept, run, certgen) keep their own output.

Dry mode comes only from invocation metadata (run_lmcode under lmscript --dry-run). A dry invocation loads every program and runs none. There is no --dry-run host flag.

Tests: test.sh puts a shim named lmproxy first on PATH. It runs the fresh build, records the exit code and keeps each private program file. Examples and fixtures run through lmscript; the v6 header and raw-schema-hash check and the multi-file and load-before-run checks use those files with the host called directly. The shim is a sh script because CI has no Windows job for this host.
