# Uniform::HTTP fast path

Unblock::HTTP1 uses Uniform::HTTP as its public request and response model.

Uniform::HTTP 0.06 provides the sanctioned native FastPath ABI that Unblock needs for
performance-sensitive protocol work. Unblock uses it for:

- constructing canonical Uniform request and response objects from HTTP/1 data
  that the native parser has already validated;
- constructing fresh canonical responses from validated application fields;
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

`Transaction->respond(status => ..., body => ...)` validates ordinary byte
fields in XS and creates a real `Uniform::HTTP::Response` through
`uhttp_native_from_validated`, from Uniform's installed C header. Ordered
headers and trailers are copied; each response owns its data. There is no
cache or alternative response class.

Invalid fields fall back to Uniform's public constructor for its usual errors.
UTF-8, magical values and uncommon container shapes also use that constructor.
The native probe does not invoke tied or overloaded code. More than 32 headers
or trailers uses the general constructor; this internal optimization threshold
does not impose an application limit. Explicit response objects retain their
existing path. HTTP/1 framing checks still happen in the serialization planner.

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
