# Linux::Event integration boundary

This document defines how Linux::Event::HTTP should bind to Unblock::HTTP1
without making Linux-specific behavior part of the portable engine.

It is an integration contract, not an implementation in this repository.

## Canonical adapter

The canonical adapter uses only the public byte API:

    $http->input($bytes);
    $http->input_eof;

    while ($http->want_write) {
        my $bytes = $http->output;
        $stream->write($bytes);
    }

This path is the correctness reference. Any optimized Linux::Event bridge must
produce the same protocol behavior as this adapter.

## Read ownership

Linux::Event owns the Stream and readiness lifecycle.

When readable bytes arrive:

1. feed those bytes to Unblock::HTTP1;
2. let Unblock parse and advance HTTP state;
3. drain any generated HTTP output;
4. stop HTTP reads when want_read becomes false.

Unblock does not call epoll, pause or resume a Stream, or change Linux::Event
watchers.

## EOF and errors

A clean transport EOF must call input_eof(). An empty input() call is not EOF.

Transport failures, timeout policy, TLS failures, or host shutdown remain
Linux::Event responsibilities. The adapter may call:

    $http->close($reason);

to terminate the protocol engine consistently.

## Write ownership

Unblock owns only its protocol output queue.

Linux::Event owns the transport write queue and its own backpressure. An adapter
may use output($maximum) to move only as many bytes as the transport currently
wants.

Unblock on_drain means the Unblock output queue fell below its configured
low-water mark. It does not mean the Linux::Event Stream write buffer is empty.

## Upgrade and CONNECT transition

A 101 response or successful CONNECT causes Unblock to enter switched state.

The adapter must then:

1. stop feeding HTTP bytes;
2. call take_remainder();
3. transition the live Linux::Event Stream to the next protocol consumer;
4. deliver the preserved remainder to that consumer exactly once;
5. resume normal Stream reads under the new protocol.

No bytes after the HTTP boundary may be dropped, duplicated, reparsed as HTTP,
or retained by the old HTTP adapter.

This preserves the existing Linux::Event transition_to() design while keeping
the protocol-switch decision inside the reusable HTTP engine.

## TLS and ALPN

TLS remains outside Unblock::HTTP1.

For HTTP/1 over TLS, Linux::Event feeds decrypted application bytes into the
same adapter. ALPN selection happens before the HTTP/1 engine is selected.

A later transition from TLS negotiation to HTTP/1 therefore changes the
transport consumer, not the Unblock public API.

## Native Stream-consumer optimization

The first Linux::Event integration should use the canonical public byte API.

A direct native Stream-consumer bridge should be added only if integration
benchmarks show that the adapter copy or Perl dispatch is a material cost after
the current Unblock optimizations.

If such a bridge is added, it must:

- live in Linux::Event::HTTP or another Linux-specific adapter layer;
- treat Linux::Event's raw consumer window as borrowed input;
- preserve the same framing, callbacks, Uniform objects, errors, and switch
  boundaries as the canonical adapter;
- never bypass Unblock protocol rules;
- never depend on undocumented Uniform object layout;
- preserve post-switch bytes exactly;
- remain optional so Unblock::HTTP1 is still usable on non-Linux systems and
  with other event loops.

The bridge may optimize byte movement. It must not become a second HTTP/1
implementation.

## Performance acceptance

Compare the canonical Linux::Event adapter and any native bridge using the same
request/response workloads.

A native bridge is justified only by measured end-to-end improvement. Parser
microbenchmarks alone are not enough because current measurements already show
that native parsing is much faster than complete transaction processing.

## Repository boundary

This repository should contain the portable engine, tests, benchmark contracts,
and integration requirements.

Linux::Event-specific implementation code belongs in Linux::Event::HTTP.
