# Unblock::HTTP1 benchmarks

These are development benchmarks, not correctness tests.

Build the distribution first:

    perl Makefile.PL
    make

Then run:

    perl -Mblib bench/http1.pl

An optional integer argument selects the approximate number of CPU seconds per
case:

    perl -Mblib bench/http1.pl 5

The benchmark separates native parsing, Perl-side serialization planning, and
complete in-memory client/server exchanges. It includes a small GET, a 4 KiB
fixed-length request/response exchange, and a 4 KiB chunked streaming exchange.
Persistent-connection variants separate per-connection setup from per-request
cost. Client-only and server-only cycles further separate the two halves of an
exchange.

Buffered 4 KiB request and response planning also has explicit Content-Length
control cases. The controls deliberately take the complete validation path,
while ordinary messages can take the common fast path. Compare those cases
within the same benchmark run because CI runner speed varies between runs.

This is intentional: an optimization should be aimed at the layer that
measurements identify as expensive.

Do not use these numbers as network server requests-per-second claims. There is
no socket, TLS, DNS, event loop, scheduler, or kernel I/O in these cases.

The useful standalone comparison is:

1. native request-head parsing;
2. native response-head parsing;
3. request serialization;
4. response serialization;
5. complete small GET exchange;
6. complete 4 KiB fixed-length request/response exchange;
7. complete 4 KiB chunked streaming request/response exchange;
8. persistent-connection versions of the complete exchanges;
9. client-only and server-only HTTP/1 cycles;
10. common-path versus full-planner buffered serialization.

The cross-engine comparison benchmark also measures receive-side Uniform object
materialization. Its trusted-shape cases are diagnostics only: they estimate
the ceiling of a future sanctioned trusted-construction API and deliberately
must not be used by production engine code. See docs/TRUSTED_UNIFORM.md.

Use cross-engine comparisons and profiles only to identify portable engine
costs. Framework-specific integration decisions belong to the consuming
project.
