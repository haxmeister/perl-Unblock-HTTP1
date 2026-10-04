# Trusted Uniform construction requirements

Unblock::HTTP1 uses Uniform::HTTP as its public message model. That boundary is
intentional and should remain the normal application-facing API.

The native HTTP/1 parser already validates wire syntax before message
construction. Development benchmarks show that rebuilding those parser-validated
values through the ordinary public Uniform constructors costs substantially more
than parsing the HTTP head itself.

This document records the requirements for a possible future trusted
construction interface. It does not define or implement that interface.

## Why this exists

The ordinary Uniform constructors must continue to validate arbitrary
application input. Unblock cannot simply disable those checks globally.

A protocol implementation has a different input contract:

1. bytes arrive from the wire;
2. the protocol parser validates method/status syntax, version syntax, field
   names, field values, and framing rules;
3. those already validated values are materialized as Uniform objects.

Repeating generic syntax validation in step 3 is measurable overhead.

The benchmark-only trusted-shape cases in bench/compare-linux-event.pl bypass
the public constructor only to estimate the possible ceiling. They are not
production code and must not be copied into the engine.

## Required properties

Any future trusted construction API must:

- live in Uniform::HTTP, not in Unblock::HTTP1;
- be explicitly intended for protocol implementations and adapters;
- preserve the ordinary Uniform::HTTP::Request and Uniform::HTTP::Response
  object types;
- preserve duplicate fields, field order, original field-name spelling, and
  exact value bytes;
- accept only byte strings already validated by the caller;
- avoid repeating generic field-name and field-value syntax validation;
- preserve normal Uniform lifecycle semantics;
- support ownership transfer of freshly parsed header/trailer arrays without
  requiring unnecessary deep copies;
- remain independent of HTTP/1, HTTP/2, HTTP/3, Linux::Event, and any event
  loop;
- fail clearly when its trusted-input contract is violated by the caller;
- remain an implementation detail for protocol engines rather than a shortcut
  recommended to applications.

## Request state needed by Unblock::HTTP1

For a received request, trusted construction must be able to set:

- method
- exact request target
- HTTP version
- ordered headers
- optional scheme, authority, and protocol metadata
- initial metadata frozen immediately after parsing
- complete/frozen state for requests with no body
- incomplete state for requests whose body or trailers are still arriving

The protocol engine remains responsible for deciding whether the message is
complete. Uniform should not infer HTTP/1 framing from Content-Length or
Transfer-Encoding.

## Response state needed by Unblock::HTTP1

For a received response, trusted construction must be able to set:

- status
- exact reason phrase when present
- HTTP version
- ordered headers
- initial metadata frozen immediately after parsing
- incomplete state while body or trailers are still arriving
- later completion and full freeze through the normal Uniform lifecycle API

Uniform should not infer HEAD, CONNECT, 1xx, 204, 205, 304, or
close-delimited semantics. Those remain protocol-engine responsibilities.

## Ownership

The native parser creates fresh Perl scalars and a fresh ordered header array
for each parsed message. A useful trusted API should be able to take ownership
of those values rather than validate and deep-copy them again.

That ownership contract must be explicit. Callers must not mutate arrays or
field pairs after transferring them to Uniform.

## What Unblock::HTTP1 must not do

Unblock::HTTP1 must not:

- bless hashes directly into Uniform classes in production;
- depend on undocumented Uniform object layout;
- monkey-patch Uniform classes;
- introduce an Unblock-specific competing message type;
- expose a public bypass that lets arbitrary application values skip Uniform
  validation;
- move this optimization into HTTP/1 XS merely to hide the same object-layout
  coupling there.

Until Uniform provides a sanctioned interface, the engine should continue to
use the public constructors even though the benchmark shows measurable cost.

## Decision point

A Uniform change is justified only if same-run benchmarks continue to show a
large gain after the standalone Unblock fast paths are exhausted.

Current diagnostics show that trusted request construction can be several
times faster than public constructor materialization. The response diagnostic
exists to verify that the same conclusion applies symmetrically before any
cross-distribution API change is proposed.
