## Unblock::HTTP1 0.12 feature-branch release candidate (2026-10-21)

The maintainer has now requested coordinated bumped versions and release
preparation. All indexed literal package versions are updated to 0.12 on
feature/unified-receive-lifecycle; dynamic NativeABI/_Native versions
continue to use the parent package version. Changelog covers the
verified receive/lifecycle and attached-output fixes. A fresh full CI
and release tarball/version-index audit are required on this commit.
No main updates, GitHub tags or releases, or CPAN uploads yet.

# Receive body and lifecycle implementation checkpoint

Updated: 2026-10-17
Repository: haxmeister/perl-Unblock-HTTP1
Branch: feature/unified-receive-lifecycle
Status: receive/lifecycle implementation passes full CI; not a release candidate.

The maintainer explicitly authorized changes to HTTP1, HTTP2, HTTP3 and
perl-Unblock-HTTP. Do not modify main, merge, or release. The user confirmed publication of these
feature branches and coordinated CI on 2026-10-17. Publication is authorized.
The agreed contract is in perl-Unblock-HTTP/docs/ENGINE-CONTRACTS.md.

## Implemented

- Bounded buffered reception and per-transaction on_data streaming selection.
- Client request options on_data and on_finish; server registration at headers.
- Exactly-once terminal notification after completion/error callbacks; terminal
  observer exceptions are ignored. Cancellation is distinct from an error.
- The same native engine transaction and Uniform message are retained.
- Buffered data is installed before completion/freeze; failed buffers are freed.
- Bodyless messages already frozen at headers carry an empty body string at
  construction. Public native ABI layouts/discovery paths are unchanged.
- Default receive modes remain H1/H2 stream, H3 buffered; buffer cap is 64 MiB.


## Validation

Full local suite passes: 36 files, 320 top-level tests/subtests.
This includes 24 new subtests with portable/native parity, fixed/chunked/empty
bodies, overflow, truncation, and callback cancellation/exception ordering.

No performance or zero-copy improvement is claimed. Version numbers are
unchanged; this is a coordinated development branch, not a CPAN release.

## Attached output acceptance before terminal completion (2026-10-17)

Coordinated upper hard-output-limit CI 39086673892 exposed a real H1
completion ordering issue, while H2 passed: when a 2 MiB buffered
response is assembled during input(), the H1 transaction calls
on_finish(state=complete) before the attached host has accepted the
actual output. LinuxEvent immediately rejects the output due to
max_pending_bytes=4096 and reports a fatal structured output_limit,
but H1 cannot change the already-dispatched terminal callback.
The client does NOT receive a complete response, and H2 marks error.

Approved contract: on_finish exactly once after terminal state; a
failed host send is an error, not successful local output acceptance.
A stream write returning false due ordinary congestion remains accepted,
whereas a fatal host error aborts without replay. We will defer attached
H1 completion only until all engine output belonging to that response
is transferred to the host's unblock_send(), not until network delivery.
Manual output() engines retain their existing application completion
timing. Preserve H1 pipelining, native borrowed input, switching and
reentrant callbacks. No aliases or ABI changes.

Plan: guard Server::_retire_if_done when attached output remains;
perform deferred retirement after the transport successfully accepts
queued bytes, including after resume_output. Add standalone tests for
synchronous rejecting host and a normal accepted-but-blocked host and
pipelined requests, run full H1 CI; then pin the verified H1 feature
source SHA in upper workflow and validate real hard-cap H1/H2 test.
Implementation and validation:
- Server.pm now queues locally completed attached Transactions while the
  output bytes remain in the engine. Pipelined HTTP/1 output is still
  coalesced; _transport_sync commits queued terminal callbacks only
  after the complete batch has been accepted by unblock_send(). A
  thrown host send fails every pending Transaction before on_finish.
  A false host return remains successful acceptance plus congestion.
- A first naive transport-retirement gate failed old
  t/50-embedding-api.t subtests for graceful close and coalescing.
  It was replaced rather than weakening those regressions. Pipelining,
  manual output and graceful close retain the original behavior.
- New t/53-attached-output-completion.t covers rejecting hosts,
  accepted-but-blocked whole writes, pipelining order/coalescing, and
  unchanged manual mode. MANIFEST updated. No ABI layout change.
- Production source: 783e2a951dafac2756ba2c3cf34ea35fc043de6f.
  H1 full matrix run 39087355734 PASS on Linux Perl 5.16/latest,
  macOS/latest and Windows Strawberry 5.40. Linux latest reports
  37 files/324 checks, and distribution tests also PASS.
  Framework example CI 39087355806 PASS.
- Subsequent H1 edits are documentation/this handoff only, and
  upper integration pins the verified production source commit.
  The upper hard-cap regression must pass separately before claiming
  the coordinated boundary verified.

No main, merge, tag, release, version bump, or unrelated dependency edits.

## Resume

1. Check git status/branch and inspect the diff; main must remain unchanged.
2. Local source/POD review and focused tests are complete; inspect the recorded
   validation limits before continuing with CI.
3. Feature branch is published, tree verified and full CI passed (see below).
4. Coordinate remaining H3/unified verification using the upper handoff.
5. Update upper-layer CI pins to the published engine commits and run live
   Unblock::HTTP integration. Upper Server now maps on_headers to engine
   on_request and application on_request to engine on_request_end.
6. Preserve frequent handoff updates. WebSocket, transaction_class, pause/resume,
   and client pooling are later milestones; no changes to Net::QUIC authorized.

## Historical handoff (superseded)

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

## 2026-10-10: Embedding API merged and 0.11 audit in progress

The user authorized merging the accepted feature into main and starting a
release audit. Pull request #3 merged feature/engine-embedding-api on main at
9529b6472d3fe69841fbbeabc31df9fbbdbd71a8.

Integration:
- Added examples/linux-event-server.pl. Its Example::HTTPStream subclass owns
  Unblock::HTTP1::Server, uses weak callback capture and native Linux::Event
  on_data, on_eof, on_error, on_drain callbacks, and implements the three
  unblock_* host operations through write, end and close. A separate
  application subclass implements on_http_request.
- The Linux::Event subclass is constructed by the standard Listener stream
  recipe. It checks for a terminal write failure before returning the
  Linux::Event write backpressure result.
- Added the example to MANIFEST, README, cookbook and integration guides.
  Linux::Event is optional and Linux-only, not a Makefile.PL prerequisite.
- Added a dedicated Linux::Event v0.117 smoke job alongside IO::Async and
  AnyEvent smoke jobs. All three succeeded on feature head e46ab472.
- A first smoke exposed a misplaced lexical weaken import. This was fixed
  before merging; the latest feature head smoke passed.

Release audit work on main:
- Set public distribution/module versions to 0.11 (HTTP1, Client, Server,
  Transaction and Integration); NativeABI derives its version from HTTP1.
- Expanded t/00-load.t and t/01-version.t to cover Integration.
- Added 0.11 Changes entry and refreshed README/installed perldoc.
- Kept existing native ABI v1, public native header and Uniform::HTTP 0.06
  minimum; no mandatory framework dependencies were added.
- Benchmark-embedding now uses released v0.10 as its baseline, not main.
- CI tests validate Perl 5.16/latest Linux, macOS, Windows, POD, distcheck,
  disttest and optional live framework examples.
- Handoff.md remains excluded from the CPAN distribution.

No 0.11 tag, GitHub release, or CPAN upload has been made.
Review latest main CI after final audit edits. Performance benchmarks on hosted
runners are provisional; the portable engine fast path remains available.


## 2026-10-10: Final v0.11 release audit

The user requested a thorough release audit on main. No release, tag, or CPAN
upload has been authorized yet. The most recent published tag remains v0.10.

Audit scope:
- Public 0.11 Perl module versions: Unblock::HTTP1, Client, Server,
  Transaction, Integration; NativeABI inherits the distribution version.
- Native borrowed-input ABI remains version 1 and retains the v1 public
  installed header, without changes to its layout or operations.
- Makefile.PL still requires Perl 5.16 and Uniform::HTTP 0.06. IO::Async,
  AnyEvent, and Linux::Event are optional integration-example dependencies.
- MANIFEST contains all public modules, shipped header, cookbook, integration
  documentation, five runnable examples, and regression tests t/50 and t/51.
- MANIFEST.SKIP excludes Handoff.md and internal/unshipped development docs.
- README, root POD, Client/Server/Transaction/Integration POD, cookbook, and
  Changes have been reviewed for the new attached transport API.
- Main test workflow checks Linux 5.16, Linux latest, macOS, Windows, public
  POD syntax, distcheck and disttest. Framework examples workflow smoke-tests
  IO::Async/AnyEvent client/server pairs and Linux::Event server with curl.

Fixes applied during this audit:
- Clarified server-specific input_eof() and client-specific EOF response
  framing language in their respective POD sections.
- Reworded the README version requirement so it remains correct at release.
- Added a t/01-version.t assertion distinguishing distribution version 0.11
  from native input ABI v1.
- Removed the redundant Scalar::Util import from the AnyEvent example.
- No parser, serialization, lifecycle, XS, or native ABI semantics changed.

Before publishing, check the final test and framework-examples workflow runs
on the current main HEAD; earlier audit revisions were green on all supported
platforms. The v0.10/manual versus v0.11/manual-and-attached benchmark recorded
a small but nonzero regression on a shared GitHub runner; use controlled
repeat runs before presenting definitive performance numbers. There is no
evidence that an ABI version bump would be warranted by the new embedding API.

## Verified feature publication

Source commit: 82dfc4bf691001aff50f96bb7a92e6fce3fbb229
Full CI: https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/39058702399
PASS on Linux Perl 5.16/latest, macOS latest, Windows Strawberry 5.40.
Distribution/POD checks passed.
Additional framework examples CI: https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/39058702329
PASS. Upper CI pins the tested source commit; subsequent handoff-only updates
do not require changing that pin. Main remains unchanged.

The coordinated ordinary Server milestone is verified. H3 full suite
39059118633 and upper live integration 39059172525 passed. Consult
perl-Unblock-HTTP/Handoff.md for the next design milestone.
