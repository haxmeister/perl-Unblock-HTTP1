# Integrating Unblock::HTTP1 with an event loop

Unblock::HTTP1 has no required transport interface. An adapter only moves bytes
and reports EOF.

## Read path

When the transport receives bytes:

    $http->input($bytes);

Continue reading while $http->want_read.

If want_read becomes false because is_switched is true, stop feeding bytes to
the HTTP engine and hand take_remainder() to the next protocol.

If the transport reaches EOF:

    $http->input_eof;

Do not translate EOF into an empty input() call.

## Write path

Whenever the engine has bytes:

    while ($http->want_write) {
        my $bytes = $http->output;
        $transport->write($bytes);
    }

An adapter with a small write window can use output($maximum).

The engine's on_drain callback concerns the Unblock output queue. A transport
may have an additional high-water mark of its own.

## Timers

Unblock::HTTP1 does not create timers. Header deadlines, idle timeouts, connect
timeouts, keep-alive expiration, and application deadlines belong to the host.
The host can call close($reason) when one expires.

## TLS

TLS is outside the engine. Feed decrypted application bytes into Unblock and
send Unblock output through the TLS transport.

## Linux::Event

A basic Linux::Event adapter uses the same byte methods as any other host.
That public-byte adapter is the correctness reference.

A later optimized adapter may bridge Linux::Event's native Stream consumer ABI
only when end-to-end measurements justify it. The bridge must remain an
optimization rather than a second HTTP/1 implementation.

See LINUX_EVENT_BRIDGE.md for the detailed integration contract.
