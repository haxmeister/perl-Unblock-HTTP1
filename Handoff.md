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

## 2026-10-09/10: Implementation on feature/engine-embedding-api

The approved independent HTTP1 embedding contract is implemented on this
feature branch. Do not merge or release until explicitly requested.

Application-facing changes:
- Transaction->respond(status => ..., body => ...) and
  send_informational(status => ...) build canonical Uniform responses.
- Client->request(method => ..., target => ..., authority => ...) builds
  canonical Uniform requests; callback fields stay transaction options.
- Passing canonical Uniform Request/Response objects still works.

Framework-facing changes:
- Client->new(transport => $host) and Server->new(transport => $host).
- The engine holds a weak host reference; no mandatory framework packages.
- The host implements unblock_send($bytes), unblock_finish(), and
  unblock_abort($reason).
- unblock_send returns true/false/undef only after full acceptance; a false
  return means congestion. resume_output() signals renewed host capacity.
- Input methods are input($bytes), input_eof, transport_error($reason).
- Output automatically flushes, including delayed responses produced outside
  the read callback.
- Manual output()/want_write() remains for no-host mode; output() croaks
  when a host is attached.
- Graceful host finish waits for all internal bytes to transfer into the
  host queue. Fatal errors use immediate abort.
- The server preserves a pending response after EOF if the full request
  was already received. An unfinished request still errors at EOF.
- Server on_switch callback waits until the outgoing handshake has been
  accepted by the host; remainder handling is preserved.
- Native borrowed head input now flushes attached output after the engine
  drive scope has unwound. ABI v1 header and semantics were not changed.

Tests:
- t/50-embedding-api.t: host reference lifetime, output ownership,
  named-fields construction, delayed response/EOF, pipelines,
  backpressure, graceful close, fatal send errors, recursion,
  Upgrade/CONNECT callback ordering, and validation.
- t/51-embedding-native.t: borrowed server and client input and native
  upgrade tail with attached host output.
- Existing protocol, native, Uniform, framing and lifecycle tests retained.
- test.yml checks Integration.pm POD syntax.
- .github/workflows/framework-examples.yml installs optional IO::Async and
  AnyEvent in CI and runs the complete example server/client pairs.
- .github/workflows/benchmark-embedding.yml compares one-runner main manual,
  feature manual, and feature attached host paths.
- bench/embedding-overhead.pl implements that controlled in-memory workload.

Documentation:
- Reworked README, root POD, Client/Server/Transaction POD and
  docs/INTEGRATION.md, plus docs/COOKBOOK.md.
- Added installed lib/Unblock/HTTP1/Integration.pm.
- Runnable IO::Async Stream-subclass and AnyEvent Handle-subclass examples,
  both server and client, with adapter and application code delineated.
- MANIFEST includes installed guide, examples, cookbook and tests.
- Handoff.md is excluded by MANIFEST.SKIP and remains repo-only.

CI/progress:
- Cross-platform test matrix and framework examples have reported passing
  results on intermediate implementation commits after native and AnyEvent
  corrections. Confirm the *latest* head run again before any merge.
- Measured runs show feature manual near main manual throughput, with attached
  host dispatch adding a small but nonzero cost (roughly 4-7% vs main in
  representative loaded CI runs). Avoid claiming a zero-cost adapter.
- Repeat benchmarks on an idle, fixed host before drawing fine-grained
  performance conclusions.
- No versions were bumped, no releases tagged, and main was untouched.

## 2026-10-09: Approved IO::Async example simplification

The user approved removing the attach_http() initialization step and reducing
application nesting in the IO::Async examples.

- examples/io-async-server.pl now subclasses IO::Async::Stream with new()
  creating its Unblock::HTTP1::Server using transport => $self. The on_read,
  on_read_error and on_write_error events are subclass methods. The application
  defines $on_request separately. Listener on_accept first constructs a
  My::HTTPStream from the socket and then adds it to the loop; it does not
  nest callback definitions or object construction inside $loop->add().
- examples/io-async-client.pl follows the same constructor-owned engine
  pattern without attach_http(). HTTP callbacks are defined at application
  level, and the connected stream is separately constructed and added.
- docs/COOKBOOK.md describes the simplified construction.
- No changes to the engine API were needed; the weak transport contract is
  unchanged. Optional framework examples remain covered by framework-examples
  CI. Verify the latest push run before a merge or release.

- Follow-up cleanup: all four standalone IO::Async/AnyEvent example files
  now use ordinary package declarations with an explicit package main before
  application code. No unnecessary braces or artificial indentation around
  package definitions. Engine and callback APIs are unchanged.
