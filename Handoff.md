# Unblock::HTTP1 handoff

Repository: haxmeister/perl-Unblock-HTTP1

## Current work

Branch: `api-harmonization-0.10`

Version 0.10 harmonizes the public HTTP/1 API vocabulary with the current
Unblock::HTTP2 and Unblock::HTTP3 conventions.

The change is intentionally clean. No compatibility aliases are being added.

## Transaction API

HTTP/1 already had the common application methods:

- `respond()`
- `write()`
- `end()`
- `send_informational()`

Version 0.10 adds `Transaction->error()`.

The common lifecycle vocabulary is now:

- `state()`
- `error()`
- `is_complete()`
- `is_cancelled()`
- `is_error()`
- `is_terminal()`

Cancellation remains distinct from failure and does not manufacture an error
string.

## Native ABI

The optional native ABI remains borrowed-input focused. The ordinary
`input($bytes)` API remains the portable correctness path.

Native discovery is now parallel with HTTP/2:

- `definition()`
- `native_include_dir()`
- `header_path()`
- `c_header()`

`definition()` reports the provider, ABI version, structure size, and
operations address.

The public header is:

`Unblock/HTTP1/NativeABI/unblock_http1_native_abi.h`

HTTP1.xs compiles against that same header. The former duplicate C ABI
declaration has been removed.

ABI version remains 1. The layout and result codes are unchanged:

- 0: input accepted
- 1: more contiguous bytes required
- 3: HTTP connection closed
- 4: protocol switched

HTTP/1 does not add HTTP/2 native output operations merely for symmetry.

## Uniform::HTTP

Version 0.10 requires Uniform::HTTP 0.06.

Unblock compiles Uniform's native FastPath header as part of its own XS.
Uniform::HTTP itself remains pure Perl.

Validated picohttpparser spans construct exact canonical Uniform::HTTP objects
directly on the native receive path. Portable construction remains available
for subclasses and adapters.

## Validation

Before merging this branch to main:

- verify the complete test suite
- verify POD syntax
- verify distcheck and disttest
- verify the public NativeABI header is installed
- verify the version-consistency and lifecycle tests
- verify no stale 0.03 API documentation remains
- verify MANIFEST does not include Handoff.md
