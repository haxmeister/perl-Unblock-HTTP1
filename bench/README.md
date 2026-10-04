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

The benchmark separates native parsing, Perl-side serialization planning, and a
complete in-memory client/server exchange. This is intentional: an optimization
should be aimed at the layer that measurements identify as expensive.

Do not use these numbers as network server requests-per-second claims. There is
no socket, TLS, DNS, event loop, scheduler, or kernel I/O in these cases.

The useful comparison before Linux::Event integration is:

1. native request-head parsing;
2. native response-head parsing;
3. request serialization;
4. response serialization;
5. complete small GET exchange.

After the standalone engine is stable, compare the same operations with the
current Linux::Event::HTTP HTTP/1 implementation and use profiles to decide
which additional serialization or state transitions are worth moving into XS.
