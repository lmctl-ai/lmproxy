# Examples

Runnable lmscript programs, one per scenario. Each compiles to bytecode and
runs against the `lmproxy` host:

```sh
lmscript examples/parse-url.lms build/parse-url.dslb
lmproxy --lmcode build/parse-url.dslb
```

The `install="github:lmctl-ai/lmproxy@latest"` line in each script pins the
host CLI the same way lmscript resolves any other tool.

- `parse-url.lms` — parse several URLs and print their components
- `inspect-request.lms` — parse an embedded HTTP/1.1 request, print first line and headers
- `inspect-response.lms` — parse an embedded HTTP/1.1 response, chase its Location header
- `percent-encoding.lms` — percent-decode and re-encode a URL path

`./test.sh` compiles and runs every example as part of the check suite.
