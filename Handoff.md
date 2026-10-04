# Unblock::HTTP1 handoff

Repository: haxmeister/perl-Unblock-HTTP1

## Current release prep

Version 0.03 is prepared on top of the transport-neutral native receive work.

The native input ABI is optional. The ordinary `input($bytes)` API remains
the portable correctness path.

Native XS transports can pass borrowed contiguous input windows through
`Unblock::HTTP1::NativeABI`. The caller retains ownership and receives the
permanently consumed prefix.

## Uniform::HTTP

Version 0.03 requires Uniform::HTTP 0.06.

Unblock compiles Uniform's header-only native FastPath as part of its own XS.
Uniform::HTTP itself remains pure Perl.

Validated picohttpparser spans are used to construct exact canonical
Uniform::HTTP objects directly:

- server receive constructs Uniform::HTTP::Request
- client receive constructs Uniform::HTTP::Response
- informational responses use the same native construction path
- portable parsing and construction remain available as fallback behavior

The final Uniform object owns copied Perl storage. No borrowed transport or
parser pointer is retained.

## Native ABI behavior

ABI version: 1

Result codes:

- 0: input accepted
- 1: more contiguous bytes required
- 3: HTTP connection closed
- 4: protocol switched

Incomplete request or response heads report zero consumed bytes so the host can
retain the prefix and append more data.

For 101 and successful CONNECT handoff, only HTTP bytes are consumed. Bytes for
the next protocol remain owned by the host.

Chunked decoding still copies into writable scratch because picohttpparser's
chunk decoder mutates its input.

## Architecture

Do not move transport-specific behavior into Unblock::HTTP1.

The ABI must remain independent of:

- file descriptors
- epoll or other readiness APIs
- Linux::Event
- socket ownership
- framework stream classes

HTTP parsing, validation, framing, and lifecycle stay in Unblock::HTTP1.
Adapters only move bytes and translate native ABI results to their transport.

## Release checks

Before releasing 0.03:

- full test matrix must pass on Linux Perl 5.16/current, macOS, and Windows
- distribution distcheck/disttest must pass
- standalone native/portable benchmarks must pass
- Linux::Event comparison diagnostic must pass
- verify MANIFEST does not include this Handoff.md
- merge the feature branch to main only after those checks are green
