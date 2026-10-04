# Unblock::HTTP1 architecture

## Purpose

Unblock::HTTP1 is the reusable HTTP/1 protocol engine.

    application or HTTP policy
              |
              v
         Unblock::HTTP1
              |
              v
     transport chosen by caller

The transport can be Linux::Event, IO::Async, AnyEvent, Mojo, a blocking
socket, an in-memory test harness, or any other reliable ordered byte stream.

## Byte boundary

Incoming bytes use:

    $engine->input($bytes);

Outgoing bytes use:

    while ($engine->want_write) {
        my $bytes = $engine->output;
        ...
    }

want_read() says whether the engine is still accepting HTTP bytes. input_eof()
is an explicit transport event because a legal HTTP/1 response can use
connection close as its message-body delimiter.

## Messages

Requests and responses are Uniform::HTTP 0.04 objects.

Received request metadata maps directly from method, exact request-target,
HTTP/1 version, ordered header fields, and ordered trailer fields. Unblock does
not infer Uniform scheme or authority from transport state or Host.

When the request-target itself carries routing metadata, Unblock exposes those
bytes through Uniform as well: absolute-form supplies its explicit scheme and
authority, while CONNECT authority-form supplies authority. The raw Host field
remains unchanged. In particular, an absolute-form target takes routing
precedence over a mismatched Host without destroying the received header bytes.

When sending an HTTP/1.1 request, an absent Host field can be synthesized from
explicit Uniform authority metadata on the wire. This sender mapping does not
mutate the Uniform object.

Received initial metadata is frozen after the head parses. Body streaming is
external to Uniform. Trailers remain mutable until the framing end, then the
message is marked complete and fully frozen.

## Native boundary

picohttpparser is an internal parsing backend. It handles hot lexical work,
while Unblock owns HTTP semantics and connection state.

The XS backend is intentionally independent of Linux::Event. It does not know
about file descriptors, epoll, Stream objects, watcher callbacks, or the
Linux::Event native consumer ABI.

Portable HTTP parsing and framing optimizations belong here. An optional
Linux::Event transport bridge belongs in Linux::Event::HTTP.

## Request framing

The parser enforces security-sensitive rules before application delivery:

- HTTP/1.0 and HTTP/1.1 semantics are implemented;
- higher HTTP/1 minor versions retain their wire version but use HTTP/1.1
  semantics for interoperability;
- obsolete folded fields are rejected;
- HTTP/1.1 has exactly one Host field;
- conflicting Content-Length values are rejected;
- Transfer-Encoding and Content-Length cannot be combined;
- chunked must be the final chunk coding;
- outgoing TE is validated as HTTP/1.1 hop-by-hop negotiation and gains
  Connection: TE automatically when needed;
- TE never advertises chunked explicitly, because chunked is implicitly
  acceptable in HTTP/1.1;
- unsupported transfer codings are rejected;
- configured head and field-count limits are finite.

These rules are below framework policy because every caller needs the same
request-smuggling defenses.

## Response framing

The client determines the response body boundary from both the request method
and response metadata.

No response body is consumed for HEAD, informational responses, 204, 205, 304,
101, or successful CONNECT. Other final responses use Transfer-Encoding, then Content-Length, then
connection close.

When a response Transfer-Encoding ends in C<chunked>, Unblock owns that final
chunk framing. Earlier transfer codings remain encoded in the body bytes. When
the final transfer coding is not chunked, EOF delimits the message and the
connection is not reusable. The same rule applies when serializing responses:
caller-supplied body bytes are assumed to have any earlier transfer codings
already applied, and Unblock adds only a final chunked layer when required.
Unblock does not automatically encode or decode transfer codings such as gzip.

A server only originates a non-chunked transfer coding when the request
advertised that coding with a positive TE quality value and protected the TE
field with Connection: TE. Chunked itself needs no TE advertisement.

Transfer-Encoding plus Content-Length is rejected as ambiguous. input_eof()
completes only a close-delimited body.

## Chunked bodies and trailers

picohttpparser's chunk decoder is configured to stop at the zero chunk before
it consumes trailer fields. Unblock then parses the trailer section as a real
HTTP field block and places those fields in the Uniform trailer section.

When outgoing trailer fields are already known when the message head is
planned, Unblock adds their names to Trailer automatically. If a streaming
producer will add trailer names only after the head has been sent, the caller
should predeclare those names in Trailer. The application remains responsible
for choosing fields whose definitions permit trailer use.

This intentionally improves on the old Linux::Event::HTTP native path, which
could consume chunk trailers without exposing them.

## Streaming and backpressure

A Transaction with stream_body => 1 accepts body chunks through write() and
finishes with end().

write() accepts the supplied bytes. Its boolean return reports whether the
engine output queue is below the cooperative high-water mark. When a blocked
queue falls below the low-water mark, on_drain fires.

## Request ordering

The initial Client queues requests serially and does not silently enable
HTTP/1 pipelining.

The Server safely retains already-read pipelined request bytes while the
current exchange is active and parses the next request only when the prior
transaction retires.

## Informational responses

Each informational response is its own complete Uniform Response object.
Non-101 1xx responses are delivered through on_informational. 101 is different
because it changes the protocol owning the connection.

## Protocol switch boundary

A 101 response and successful CONNECT terminate HTTP parsing on the live
connection. The engine completes normal HTTP message lifecycle first, then
enters switched state. Already-read bytes beyond the HTTP boundary move to a
remainder buffer:

    $engine->is_switched;
    my $tail = $engine->take_remainder;

This avoids losing same-read WebSocket or tunnel bytes and does not require the
next protocol to use any particular class model.

## Reentrancy

input(), input_eof(), and output() are not recursively callable from an engine
callback. Application callbacks may queue response data or body data through
the Transaction API.

## Linux::Event integration

Linux::Event::HTTP should eventually own only Linux-specific surrounding
policy and transport adaptation: Stream/listener creation, TLS/ALPN, readiness,
connection pooling, redirects, cookies, authentication, proxy policy, protocol
selection, and live Stream transition.

It should not reimplement HTTP/1 parsing, framing, chunk decoding, trailers,
persistence rules, or switch-boundary detection.

## Performance direction

Correct portable semantics come first, but the architecture does not cap
optimization there. The native parser already keeps lexical parsing in C.
After behavior is stable, serialization and common receive transitions can
move further into XS without changing the public API. Linux::Event can then
add a direct native Stream-consumer bridge as an adapter optimization.
