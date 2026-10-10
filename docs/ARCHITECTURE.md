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

The transport can be an event loop, framework adapter, blocking socket,
in-memory test harness, or any other reliable ordered byte stream.

## Byte boundary

Incoming bytes use:

    $engine->input($bytes);

The preferred output path uses a weakly referenced host attached at
Client/Server construction. The engine calls the host's unblock_send($bytes)
when wire output is produced. There is no polling or manual output pump.

The host must fully accept each offered buffer into its own output queue.
Its return value reports congestion; resume_output() notifies the engine
when the host can accept more output. unblock_finish() is graceful after
queued bytes, while unblock_abort($reason) is fatal.

The original manual interface remains available WITHOUT an attached host:

    while ($engine->want_write) {
        my $bytes = $engine->output;
        ...
    }

want_read() says whether the engine is still accepting HTTP bytes. input_eof()
is an explicit read-side event; a complete request may still receive a
delayed response after EOF. Some response bodies use EOF as a delimiter.
The host cannot own both automatic output and manual output drains.

## Messages

Requests and responses are Uniform::HTTP 0.06 objects.

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

The XS backend is intentionally independent of transports and event loops. It
does not know about file descriptors, readiness APIs, watcher objects, or
framework-specific native consumer interfaces.

The optional NativeABI exposes the same receive engine to native transports
through borrowed contiguous input windows. The host retains ownership of the
window and Unblock reports the consumed prefix. Parser state and HTTP lifecycle
remain in this distribution; a framework bridge only moves bytes and maps the
ABI result to its own read/pause/switch behavior.

Native integrations discover the ABI through definition(),
native_include_dir(), header_path(), and c_header(). The installed public
header is the same declaration compiled by the HTTP/1 XS implementation.
Consumers validate both ABI version and structure size before using the
operations table.

The native receive path constructs exact canonical Uniform requests and
responses directly from validated parser byte spans through the Uniform::HTTP
0.06 native FastPath header. The final message owns its copied Perl storage; no
parser pointer or transport buffer is retained by the message.

Portable HTTP parsing and framing optimizations belong here. Transport-specific
bridges belong in adapters outside the protocol engine.

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

When a response Transfer-Encoding ends in `chunked`, Unblock owns that final
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

The vendored decoder carries a small local resource-limit patch. It counts the
total bytes spent on chunk extensions across a message and rejects the framing
when max_chunk_extension_size is exceeded. The default is 16384 bytes; zero
means unlimited. This keeps the extension limit in the native framing path
instead of adding a second Perl parser.

When outgoing trailer fields are already known when the message head is
planned, Unblock adds their names to Trailer automatically. If a streaming
producer will add trailer names only after the head has been sent, the caller
should predeclare those names in Trailer. The application remains responsible
for choosing fields whose definitions permit trailer use.

## Streaming and backpressure

A Transaction with stream_body => 1 accepts body chunks through write() and
finishes with end().

The common transaction lifecycle vocabulary is state(), error(), is_complete(),
is_cancelled(), is_error(), and is_terminal().

write() accepts the supplied bytes. Its boolean return reports whether
either the host has announced congestion or the engine output queue has
crossed the cooperative high-water mark. After resume_output() clears host
congestion and the queue drains below the low-water mark, on_drain fires.

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

input() and input_eof() are not recursively callable from an engine callback
or host unblock_send callback. output() is manual-mode only and cannot run
recursively from an engine callback. HTTP application callbacks may queue
response data or body data through the Transaction API. A host send callback
must not recursively generate HTTP output.

## Performance direction

Correct portable semantics come first, but the architecture does not cap
optimization there. The native parser already keeps lexical parsing in C.
Additional work should move into XS only when same-run benchmarks justify it,
without changing the public API or coupling the engine to a transport.
