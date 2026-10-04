# Uniform::HTTP fast path

Unblock::HTTP1 uses Uniform::HTTP as its public request and response model.

Uniform::HTTP 0.05 provides the sanctioned FastPath ABI that Unblock needs for
performance-sensitive protocol work. Unblock uses it in two places:

- constructing canonical Uniform request and response objects from HTTP/1 data
  that the native parser has already validated;
- reading canonical Uniform objects during serialization without repeatedly
  calling field-access methods or copying ordered header and trailer arrays.

## Receive path

The native HTTP/1 parser validates wire syntax and framing before Uniform
objects are created.

For canonical received messages, Unblock builds a FastPath ABI view and calls:

- `Uniform::HTTP::FastPath::request_from_validated`
- `Uniform::HTTP::FastPath::response_from_validated`

This avoids repeating generic Uniform validation and adopts the fresh ordered
header array produced by the parser.

Unblock remains responsible for HTTP/1-specific rules such as Host handling,
Content-Length, Transfer-Encoding, CONNECT, Upgrade, persistence, and message
framing.

## Send path

For exact canonical `Uniform::HTTP::Request` and
`Uniform::HTTP::Response` objects, Unblock obtains one FastPath view for each
serialization plan.

The planner reads method, target, status, version, body state, headers, and
trailers from that fixed-layout view. Header and trailer arrays are borrowed
read-only.

Any operation that needs to change outgoing fields first creates new Perl
arrays. Borrowed Uniform storage is never modified.

## Portable fallback

FastPath is optional by design.

Uniform subclasses, adapters, and other objects implementing the portable
Uniform contract do not use the canonical fast path. They continue through the
existing method-based serializer.

This keeps Unblock::HTTP1 framework-neutral while allowing canonical
Uniform::HTTP objects to recover most of the avoidable object-boundary cost.

## Safety rules

Unblock::HTTP1 must not:

- bless hashes directly into Uniform classes;
- depend on Uniform's private object layout;
- modify borrowed FastPath header or trailer arrays;
- use trusted construction for values that have not already been validated;
- move generic Uniform object knowledge into HTTP/1 XS.

The ABI version is checked by Uniform::HTTP::FastPath. Incompatible future
layouts must use a new FastPath ABI version.
