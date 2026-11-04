# Examples

Self-running lmcode programs, one per scenario. Each runs its block on the `lmproxy` host with `run_lmcode`:

```sh
PATH=$PWD/build:$PATH lmscript examples/parse-url.lms
```

- `parse-url.lms` — parse several URLs and print their components
- `inspect-request.lms` — parse an embedded HTTP/1.1 request, print first line and headers
- `inspect-response.lms` — parse an embedded HTTP/1.1 response, chase its Location header
- `percent-encoding.lms` — percent-decode and re-encode a URL path

`./test.sh` type-checks every source and runs its pinned bytecode fixture as part of the suite.
