# Unblock::HTTP1 handoff

Repository: haxmeister/perl-Unblock-HTTP1

## Release prep

Main is now the 0.10 API-harmonized code.

Version 0.10 aligns the common public HTTP vocabulary with Unblock::HTTP2 and
Unblock::HTTP3 without adding compatibility aliases or a shared base
distribution.

## Transaction API

HTTP/1 uses the common application methods:

- `respond()`
- `write()`
- `end()`
- `send_informational()`

Version 0.10 adds `Transaction->error()`.

The common lifecycle vocabulary is:

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

Native discovery is parallel with HTTP/2:

- `definition()`
- `native_include_dir()`
- `header_path()`
- `c_header()`

`definition()` reports the provider, ABI version, structure size, and
operations address.

The installed public header is:

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

## Release audit

Completed:

- 0.10 versions are consistent across public modules
- Changes has a dated 0.10 release entry
- README and public POD use the harmonized API vocabulary
- NativeABI discovery matches the common H1/H2 discovery surface
- the public NativeABI header is in MANIFEST and installed through Makefile.PL
- HTTP1.xs uses the installed public ABI declaration
- lifecycle and NativeABI discovery tests were added
- active source and current docs contain no stale 0.03 API references
- active source and current docs contain no old `inform()` API
- current documentation uses Uniform::HTTP 0.06
- Handoff.md remains outside the CPAN MANIFEST

GitHub Actions release validation is green on run #358 for main commit
9e190b186bbdbf10864d97977d2a561ef66955c9.

Passed:

- Linux current Perl build and full test suite
- Linux Perl 5.16 build and full test suite
- macOS current Perl build and full test suite
- Windows Strawberry Perl 5.40 build and full test suite
- POD syntax checks on every platform
- distcheck on Linux current Perl
- disttest of the generated distribution tarball on Linux current Perl
- NativeABI installed-header checks exercised by the full test suite

Optional before release:

- rerun the HTTP1 standalone benchmarks
- rerun the Linux::Event comparison diagnostic

## 2026-10-09: Engine embedding API investigation

Development branch: `feature/engine-embedding-api`, created at main commit
`29e44035fd8c295b1ecc8059c7a20cc3fff54ac1`.

Scope is Unblock::HTTP1 alone. Main and
`feature/easy-adapter-api` are not to be merged or changed automatically.

The released 0.10 Client/Server API uses `input()`, `input_eof()`,
`want_write()`, and `output()`. Transactions already expose
`respond()`, `write()`, `end()`, `send_informational()`, and lifecycle
accessors. The input-side NativeABI v1 and Uniform::HTTP 0.06 native fast
path must stay intact.

The older experiment is 96 commits ahead of main and contains:
- Named-fields construction in Transaction->respond(), informational
  responses, and Client->request().
- Optional transport write/close dispatch, transport backpressure and
  drain(), EOF/error helpers, and delayed response output.
- Examples and test files t/50 and t/51.

Architectural issues to address before selective reuse:
- Avoid transport/framework connection ownership cycles. In particular,
  a framework object that owns HTTP must not also be strongly owned by HTTP.
- Define *full acceptance* of outgoing bytes and distinguish congestion
  from partial/rejected writes.
- Distinguish graceful close after queued output from fatal abort.
- Protect output delivery from callback reentrancy.
- Guarantee handshake output ordering relative to on_switch and remainder
  handoff, including native borrowed-input delivery.
- Clarify EOF and half-close behavior while a delayed response is pending.
- Retain manual output/native interfaces without permitting mixed ownership.
- Examples should favor framework-native integration classes rather than
  making applications build ad-hoc transport wrappers.

Phase 1 investigation completed. The proposed compact host/embedding
contract and any breaking changes are awaiting user approval.
No engine code has yet been changed, and no tests have yet been run.
Handoff.md is repository-only and must remain outside MANIFEST.
