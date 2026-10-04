# HTTP/1 parity status

This file tracks the protocol behavior that Unblock::HTTP1 must own before
Linux::Event::HTTP delegates its HTTP/1 engine to this distribution.

The goal is protocol parity, not source-code parity. Linux::Event-specific
socket, TLS, event-loop, and live-object transition code does not belong here.

## Implemented protocol behavior

### Parsing and framing

- HTTP/1.0 and HTTP/1.1 request and response semantics.
- Higher HTTP/1 minor versions preserve their received version while using
  HTTP/1.1 semantics.
- Case-sensitive HTTP method semantics.
- Exact request-target bytes.
- Origin-form, absolute-form, CONNECT authority-form, and OPTIONS asterisk-form
  request-target validation.
- HTTP/1.1 absolute-form Host generation for senders and request-target
  authority precedence for receivers without rewriting raw Host bytes.
- Explicit Uniform scheme/authority metadata from absolute-form and CONNECT
  request targets.
- Ordered duplicate header fields.
- Configurable head and header-count limits.
- Content-Length request and response framing.
- Identical repeated or comma-combined request Content-Length values.
- Conflicting and overflowing Content-Length rejection.
- Numerically equivalent Content-Length spellings are normalized consistently.
- Transfer-Encoding plus Content-Length rejection.
- Strict request chunked-coding rules.
- HTTP/1.0 Transfer-Encoding and TE sender rejection.
- Outgoing TE syntax, qvalue, Connection: TE, and implicit-chunked rules.
- Server response transfer codings are limited to positive TE negotiation from
  the request; chunked remains implicitly acceptable.
- Response framing with preceding transfer codings and non-chunked final
  transfer codings on both receive and send paths.
- Final chunked framing is removed on receive and added on send while earlier
  transfer-coded body bytes remain opaque to the engine.
- Obsolete folded request fields rejected.
- HTTP/1.1 Host requirements and persistence rules.
- HTTP/1.0 keep-alive rules.
- Byte-by-byte fragmented input.
- Pipelined server request boundary preservation.

### Bodies and trailers

- Incremental fixed-length request and response bodies.
- Incremental chunked request and response bodies.
- Chunk extensions accepted by the parser backend with a configurable
  cumulative extension-byte budget.
- Empty streaming writes do not emit a terminating chunk.
- Trailer fields remain separate from initial headers.
- Ordered trailer fields are stored in Uniform::HTTP.
- Known outgoing trailer names are announced automatically with Trailer.
- Framing fields are rejected from trailer sections.
- Close-delimited client response bodies complete only at transport EOF.
- Truncated fixed and chunked responses fail at EOF.

### Message semantics

- Uniform::HTTP 0.04 request and response objects.
- Initial received metadata freezes after parsing.
- Received messages become complete and frozen at their framing boundary.
- HEAD responses suppress content while preserving representation framing
  metadata.
- 1xx and 204 body restrictions.
- 304 framing metadata is not interpreted as message content.
- 205 cannot contain content but uses normal HTTP/1 zero-content framing.
- Informational responses are separate Uniform response objects.
- Invalid informational framing is rejected before application delivery.
- Expect: 100-continue is emitted before HTTP/1.1 request-body delivery.
- Unsupported HTTP/1.1 Expect values receive 417 before application dispatch.
- HTTP/1.0 expectations are ignored and HTTP/1.0 clients never receive 1xx.
- Non-101 informational responses must use the dedicated informational API.

### Connection semantics

- HTTP/1.1 persistence by default.
- HTTP/1.0 closes by default and can opt into keep-alive.
- Unknown-length HTTP/1.0 streaming responses are close-delimited.
- Client requests are queued serially; pipelining is never enabled silently.
- A non-reusable response fails queued requests instead of serializing them.
- Bytes beyond a completed final client response are never treated as a queued
  response on the non-pipelining client connection.
- Explicit cancellation of a partial response closes the connection without
  converting cancellation into a protocol error.
- An early final response retires an unfinished streaming request body and
  makes the connection non-reusable.
- Cooperative high-water and low-water output backpressure.

### Upgrade and CONNECT

- HTTP/1 Upgrade offer and response validation.
- Upgrade requires HTTP/1.1 and Connection: Upgrade.
- Selected Upgrade protocols must have been offered by the request.
- Upgrade request and response body/framing restrictions.
- CONNECT authority-form target validation.
- CONNECT Host must identify the authority target host; its port may be omitted.
- CONNECT request body/framing restrictions, while tolerating an explicit
  Content-Length of zero.
- Successful CONNECT response restrictions on the server.
- A client ignores Content-Length and Transfer-Encoding received on a
  successful CONNECT response as required by HTTP/1.
- Non-2xx CONNECT remains ordinary HTTP and the connection can be reused.
- 101 and successful CONNECT stop HTTP parsing at the exact head boundary.
- Bytes already read after a protocol switch are preserved by
  take_remainder().

## Intentionally outside Unblock::HTTP1

These are useful HTTP features, but they are not HTTP/1 connection-engine
framing responsibilities:

- socket creation and connection establishment
- DNS
- TLS and certificate policy
- ALPN and HTTP version selection
- event-loop readiness
- connection pools
- origin selection
- redirect policy
- cookie jars
- authentication policy
- proxy selection and proxy configuration
- retry policy
- request replay policy
- WebSocket framing
- tunnel protocol implementation
- Linux::Event Stream reblessing or native consumer installation

Linux::Event::HTTP can continue to own those responsibilities while delegating
HTTP/1 bytes and message boundaries to Unblock::HTTP1.

## Validation completed before Linux::Event integration

The portable engine now has:

- cross-platform CI on Linux, macOS, and Windows, including Perl 5.16;
- dedicated lifecycle and callback reentrancy regressions;
- standalone benchmarks for parsing and serialization;
- complete small GET, fixed-length body, and chunked streaming exchanges;
- persistent-connection, client-only, and server-only lifecycle benchmarks;
- focused regressions proving coalesced fixed-length fast paths preserve the
  same message lifecycle and bytes as fragmented input.

## Performance findings

Current standalone measurements show:

- native request and response parsing is already much faster than complete
  transaction processing and is not the primary portable bottleneck;
- Transaction allocation is inexpensive relative to message construction and
  protocol lifecycle work;
- ordinary buffered HTTP/1.1 request and response planners are about four times
  faster than their full validation-path controls in same-run CI measurements;
- response receive framing analysis is small enough that moving it to XS is not
  currently justified;
- benchmark-only trusted Uniform construction is roughly four times faster than
  public constructor materialization for both parsed requests and parsed
  responses in current same-run CI measurements;
- the trusted-construction result is symmetric across request and response
  objects, making repeated Uniform validation the clearest remaining
  receive-side cost;
- protected server and Transaction callback dispatch benchmarks above one
  million calls per second, and completion/freeze transitions are faster still,
  so callback safety and message-finalization method calls are not useful
  optimization targets;
- connection object reuse changes standalone throughput much less than the
  per-message lifecycle, so optimization should remain focused on transaction
  work rather than engine construction.

Absolute benchmark rates vary with the CI runner. Same-run ratios are the
useful development signal.

## Ready for Linux::Event integration

The portable HTTP/1 engine has completed its planned protocol-parity,
cross-platform, security-hardening, and benchmark passes.

The direct receive-path comparison with Linux::Event::HTTP is complete. It
shows that native parsing is already fast and that repeated Uniform message
construction is the clearest remaining receive-side cost. No additional XS
migration is currently justified by the standalone measurements.

The Linux::Event adapter contract is defined in docs/LINUX_EVENT_BRIDGE.md.
The canonical integration should use the public byte API first. A native
Stream-consumer bridge remains optional and should only be added if end-to-end
Linux::Event integration benchmarks show that byte movement or adapter dispatch
is material.

Two items remain outside this repository's portable protocol work:

1. Decide separately whether the measured trusted-construction opportunity
   justifies a sanctioned Uniform::HTTP API change. Unblock::HTTP1 is correct
   without that optimization and must not depend on undocumented Uniform object
   layout.
2. Integrate Linux::Event::HTTP against the public Unblock::HTTP1 engine and
   rerun its HTTP/1 suite and end-to-end benchmarks in that repository.

The cross-platform test and benchmark workflows on main should remain green
while those integration steps proceed.
