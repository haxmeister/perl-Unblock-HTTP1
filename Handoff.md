# ACTIVE Stage B completion-only server callbacks - 2026-10-26

Validation follow-through: top-level Unblock::HTTP integration
https://github.com/haxmeister/perl-Unblock-HTTP/actions/runs/40440089986
SUCCESS on pinned HTTP1 feature source; H1-only and full
published H2/H3/WebSocket suites PASS. Real H3 WebSocket tests
t/35 and t/36 run and PASS with corrected OPENSSL_CONF.
Independent engine A/B:
https://github.com/haxmeister/perl-Linux-Event-HTTP/actions/runs/40440056191
SUCCESS, native 53.60/53.36 baseline vs 50.03/50.39 trial
CPU us/request; portable 69.75/69.11 vs 66.57/67.56.
Socket throughput remains only marginally different.
No promotion to main/release.

Branch feature/completion-only-callback from released main source
16acac763ad2f158c4c0ac91f2df3df5e6b72284. No main merge,
version bump, tag or release. This is independent of the earlier
feature/shared-server-lifecycle-cost experiment.

Framework-neutral production change 6c199994693c2754ca9db2666c12b76cd091a80a:
Unblock::HTTP1::Server now accepts on_request_end alone instead of
requiring a dummy on_request header observer. When on_request exists,
all existing early callback behavior is unchanged. When absent,
the engine still constructs and validates a canonical Uniform request,
handles full body/streams, then invokes on_request_end normally.
Public POD and graceful drain description updated at b1ef13bf.

New t/58-completion-only.t covers partial POST body, complete frozen
canonical object, two pipelined GET responses, existing dual callback
order and rejection of neither callback; MANIFEST updated.
Validation run:
https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/40439812469
ALL FOUR cross-platform test lanes PASS (Ubuntu Perl 5.16/latest,
macOS, Windows). Framework adapter examples:
https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/40439812702
PASS.

This feature intentionally extends the lower engine's generic callback
contract. It is useful to any full-body-only application, not tailored
to Linux::Event. Its high-level consumer is separately developed on
Unblock::HTTP feature/completion-only-callback. Do not merge/release
without coordinating the upper dependency floor and a public version bump.
Real-socket first A/B was inconclusive; Stage B remains OPEN.

---

# MAIN 0.13 DOCUMENTATION AND RELEASE METADATA AUDIT - 2026-10-25

The maintainer authorized direct edits on main to complete a thorough,
simple release documentation review. Source audit commit:
6db73ae937784e3db4ff52180727f35e96ba3b7b.
No production engine behavior, public API, NativeABI version, or dependency
floor changed. The source candidate is 0.13; there was NO tag, GitHub
release, or CPAN/PAUSE upload.

Completed: Server drain has its own POD section and short README, cookbook,
and integration guidance; Client POD now lists on_data and on_finish; release
notes and Changes no longer ship prepublication instructions; protocol status
mentions draining. Makefile.PL explicitly excludes the private _Engine,
_Native, and _Wire modules from PAUSE indexing. All 85 tracked files were
accounted for by MANIFEST and MANIFEST.SKIP, with no missing/stale entries.

All five workflows on audited source commit PASSED:
- Cross-platform source tests, POD, distcheck/disttest (including Perl 5.16):
  https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/40259176579
- IO::Async, AnyEvent, Linux::Event framework examples:
  https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/40259176575
- Linux::Event embedding benchmark smoke:
  https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/40259176616
- Embedding diagnostic:
  https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/40259176573
- General serialization benchmark:
  https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/40259176539

Release documentation and source CI are ready for maintainer publication.
No public release action was taken in this audit.

---

# MAIN RELEASE-PREPARED: perl-Unblock-HTTP1 0.13 - 2026-10-25

The maintainer explicitly authorized moving the completed, tested
feature branch to main with its new distribution version.
Main was fast-forward merged to production/test source 091e2744b84c0233a050d0643366128f29e38f47.
All tagged/CPAN versions remain as previously published:
**NO new tag, GitHub release, PAUSE/CPAN upload or public publication**.
The candidate is on main, not yet publicly released.
Test evidence:
- https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/40236143626
- https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/40236143628
Release notes are in docs/RELEASE-0.13.md. This main handoff
supersedes historical "main must remain untouched" restrictions
below; it does not authorize public publication without an explicit
subsequent request. Native protocol ABI numbers are unchanged.

# RELEASE PREPARATION - Unblock::HTTP1 0.13 (2026-10-25)

Maintainer instructed fast-forward main merge, version bump and release
preparation for this completed framework-neutral integration feature.
No tag, GitHub release or PAUSE/CPAN upload authorized.
Candidate includes Server->drain, canonical native simple-response
serialization, output ownership and validated bodyless request
optimization; retain public input ABI v1.
See docs/RELEASE-0.13.md. Public module versions and t/01-version.t
are now 0.13, with original 0.12 tagged release remaining unchanged.
Run CI and audit disttest/version metadata before main merge.
Dependency downstream Unblock::HTTP 0.03 and Linux::Event::HTTP rebuild
must require published HTTP1 >=0.13 after coordinated publication.

# ACTIVE Stage B bodyless request optimization — 2026-10-25

Current authorized feature branch: feature/linux-event-integration
Production optimization commit 4d19f59196481ae4460207c5b22c5125fdbfe186.
Dedicated regression + MANIFEST: a90cfef10ca7eccde941493eaf9ffa520309f271.
Main untouched at 826fb5733daac62d9f5b51538dffbe1dc189c6d9.
No merge, tag, version bump or release.

For Server->_complete_request() when request_body_mode is 'none',
the portable Unblock::HTTP1::_Wire trusted FastPath and the native
HTTP1.xs uhttp_native_from_validated input both ALREADY construct a
complete, frozen empty-body Uniform::HTTP::Request. Skip redundant
Transaction->_finish_receive() (including body_is_mutable()) and the
Request mark_complete()/freeze() calls for these validated bodyless
requests; set tx receive_done directly. All body-bearing and
streamed requests continue their original general lifecycle.

New t/57-bodyless-completion.t checks two pipelined bodyless GETs
and one buffered POST on one connection: precise Uniform complete/
mutable/body state, receive_done, three independent 200 outputs,
terminal notifications exactly once and persistent transport. All
standalone test workflow 40156227917 PASS Linux Perl 5.16/latest,
macOS/latest, Windows Strawberry 5.40. Framework examples workflow
40156227919 PASS, including Linux::Event smoke. Before the test-only
commit, source workflow 40155745915 also PASS cross-platform.

Real Linux::Event::HTTP root all-seven-Perl-lane CI 40155946839 PASS
with exact 4d19f59 implementation and all H1/H2/H3/WebSocket tests.
Paired socket-free engine (GET -> 32-byte response) before vs after:
- CI 40155785500: 24.390/23.010 to 22.020/21.606 CPU us/iteration.
- CI 40155946839: 35.912/33.475 to 31.665/32.547 CPU us/iteration.
About 7.5–8% lower median CPU within each CI run. Do not average
absolute timings across separately provisioned runners.

ROOT Stage B STILL FAILS its end-to-end throughput gate. On the same
CI host in 40155946839, original Linux::Event::HTTP main baseline
GET/32, 100 sockets, depth 1, 10000 requests and 1000 warmup:
legacy 49,591/49,085 req/s against rebuilt 24,906/24,602 req/s
(two repeats per run, order legacy/rebuilt/rebuilt/legacy).
Rebuilt remains ~50% of legacy despite the engine improvement.
The measured root server CPU is ~41.3 us/request vs legacy ~22.1.
Raw measurements and methodology in root:
bench/results/unblock-stage-b/20261025-bodyless.json.

Next scope: isolate canonical Uniform Response creation versus
remaining _drive/_transaction_respond state cost, without bypassing
response validation or adding wrappers/duplicate engine layers.
Do not make changes to Uniform::HTTP, Linux::Event core or other
repos without separate authorization. Keep Stage C h2spec 11 failures,
Stage F cleanup deferred and no release until gates are satisfied.

---

# ACTIVE: Linux::Event integration development

Updated: 2026-10-24 (America/Chicago)
Branch: feature/linux-event-integration

The user explicitly authorized these upstream changes from the Linux::Event::HTTP
reconstruction chat. Main, releases, tags and version numbers must remain
unchanged. On 2026-10-24 the user authorized feature-branch pushes as needed.
Main still requires permission. This feature branch is now published.
Earlier release instructions below remain historical.

Latest milestone: output ownership / retained-Transaction memory.
- Server and Client transfer serialized wire bytes out of send_plan into the
  engine output queue. Retaining a completed Transaction preserves its real
  Uniform message without retaining a second serialized payload.
- Empty output batches use copy-on-write scalar assignment; appends still
  coalesce in order. Streaming framing state remains available.
- t/56-output-ownership.t covers congested server pipelines, queued client
  uploads, canonical body retention, and caller mutation after stream writes.
- Full suite passes on Perl 5.38.2 threaded and 5.44.0 non-threaded:
  40 files / 349 top-level tests. Linux HTTP both input paths pass on both.
- Linux HTTP bench/run-unblock-retention.pl holds 256 distinct 256 KiB bodies
  per process. Three samples: server median RSS delta 133444 -> 67896 KiB;
  client 133448 -> 67644 KiB. This is retained memory, not peak RSS.
  The original throughput gap remains open; no release-performance claim.
- This milestone's remote CI is pending publication. The green CI links below
  refer to the previous implementation, not this change.

Native canonical simple-response serialization and public Server drain are implemented. The full suite passes on Perl 5.38.2 threaded and 5.44.0 non-threaded: 39 files / 346 top-level tests. make disttest also passes on 5.38. The new drain tests cover native/portable partial bodies, pipelined suffix exclusion, congestion, idle/manual mode and synchronous host teardown; serializer parity includes framing fallbacks and thread cloning. Native ABI v1 is unchanged. Complex framing/subclasses retain the general path. No Uniform or Linux::Event source changes.

Published implementation: 1eb332872257087bb13ccde0f74f235c353d6e67.
The GitHub API publication preserves the exact tested local tree
857abcc6ec222b24a3a03d183c15875a2866ea9f (formerly local 4cf27f4).
Full CI PASS: Linux Perl 5.16/latest, macOS/latest and Windows/5.40;
POD, Linux-current distcheck/disttest and optional framework examples pass.
- https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/40105783566
- https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/40105783602

The coordinating checkout is Linux::Event::HTTP feature/unblock-http-rebuild.
Keep that handoff current with verified commits and dependency pins.

---

# MAIN-BRANCH RELEASE HANDOFF: Unblock::HTTP1 0.12
Updated: 2026-10-21 (post-release confirmation)
Repository: https://github.com/haxmeister/perl-Unblock-HTTP1
Current branch: main
Integrated development branch: feature/unified-receive-lifecycle
Fast-forward merge checkpoint: a976f169cd06ecc4cadab74dad1e281b42f57c4b

## Published release: Unblock::HTTP1 v0.12

Status: RELEASED. On 2026-10-21 (America/Chicago), the maintainer
confirmed publication of Unblock::HTTP1 v0.12 to both GitHub and CPAN.

GitHub independently verified:
- Published release: https://github.com/haxmeister/perl-Unblock-HTTP1/releases/tag/v0.12
- Tag: refs/tags/v0.12, pointing to
  b0a4ecd4a57816da0f319b2f459fdbd52063c435
- GitHub release published 2026-10-22 03:07:16 UTC.

CPAN publication was confirmed by the maintainer; independent PAUSE /
MetaCPAN indexing was not yet verifiable at this check (public search
results still reflected the earlier version). If CPAN indexing status
is important, inspect the PAUSE indexer report or check live MetaCPAN
after its update. Do not mistake cached search results for an upload
failure.

No new release, tag, version bump or additional release audit is pending
for this HTTP1 distribution. The prepublication audit below is retained
as history; the next coordinated distribution can now use HTTP1 >= 0.12.

## 2026-10-21 standalone v0.12 release audit (completed before publication)

The HTTP1-only release audit has now examined the merged main-branch
candidate. The last source/documentation audit commit is
4b3f3595f9cbb6672fd741f77e0950beab4ed900 (the Handoff-only commit
recording this audit is not a runtime or packaging change).

Checks:
- All six public module versions are 0.12 (HTTP1, Client, Server,
  Transaction, Integration, NativeABI). The internal _Native version
  inherits the root package version. NativeABI input ABI remains 1 and
  its structure, result codes, public header and discovery are unchanged.
- Makefile.PL keeps minimum Perl 5.16 and Uniform::HTTP 0.06; there is
  no required event framework. The shipped public header is installed.
- MANIFEST has 66 entries, every entry exists in the repository, and
  Handoff.md, development docs, benchmarks and workflows remain excluded
  under MANIFEST.SKIP.
- Changes has the 2026-10-21 v0.12 entry; t/01-version.t checks
  public version 0.12 separately from native input ABI version 1.
- The earlier runtime candidate a976f169cd06ecc4cadab74dad1e281b42f57c4b
  passed standalone Linux (Perl 5.16/current), macOS, Windows, public
  POD, distcheck, disttest, and optional IO::Async/AnyEvent/Linux::Event
  framework CI: runs 39700380828 and 39700380936.
- Release documentation-only corrections committed to main:
  7cfa967b19169e145712caba43837143a95a1a77 corrected the stale
  README feature-branch and 0.11 version notices and documented receive
  modes; 4b3f3595f9cbb6672fd741f77e0950beab4ed900 expanded the
  installed Integration POD for on_data/on_finish and buffered receive.
  The README candidate passed standalone and framework CI in runs
  39713640585 and 39713640577. The final Integration-POD candidate
  passed framework CI in run 39713826617. The standalone full matrix,
  including Linux Perl 5.16/current, macOS, Windows, POD, distcheck and
  disttest, passed in run 39713826625. This source/documentation candidate
  has completed release-audit CI successfully.

No HTTP parser, transaction lifecycle, native XS, ABI, dependency or
test behavior has been altered during the standalone release audit.
At the time of this prepublication audit, v0.11 was still the latest
public release. This historical release gate has since been completed;
see "Published release" above.

## Instructions for the next HTTP1-only conversation

The maintainer authorized the feature-branch merge and version 0.12
release; both are now complete. The standalone audit passed before
publication. See the published-release summary above. The historical
restrictions and release-prep to-do items below were superseded by the
completed 0.12 release.

## Implemented architecture and contracts

Unblock::HTTP1 remains a standalone, event-loop-agnostic HTTP/1.1 engine.
It does NOT embed a Linux::Event adapter or depend on the unified upper
Unblock::HTTP layer. The coordinated update supports the upper unified
Client/Server API while remaining directly useful to framework integrators.
- Bounded buffered-body reception and per-Transaction streamed on_data
  reception, selected at the caller boundary; a 64 MiB default cap.
- on_finish exactly once after completed, error, or cancellation,
  preserving distinction between cancellation and a protocol error.
- Original engine Transaction and Uniform::HTTP objects are retained;
  no duplicate parser or unnecessary body materialization.
- Bodyless, chunked, fixed-length, truncated and overflow cases tested
  for native/portable paths; callback error ordering specified.
- Host-attached transport ownership/backpressure and ordered response
  delivery: a completed transaction cannot be reported as finished before
  the attached host accepts its output.
- HTTP/1.1 Upgrade and native borrowed-input remainder remain safe for
  host-controlled WebSocket consumer handoff; adapter authors transfer
  unconsumed bytes exactly once. The engine must NOT depend on
  Unblock::WebSocket or Linux::Event.
- NativeABI public header and discovery contract are preserved.

## Verified CI and next actions

Version-bumped current MAIN source (pre-handoff a976f169...)
passed BOTH workflows:
- Standalone cross-platform suite:
  https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/39694114939
- Optional framework examples:
  https://github.com/haxmeister/perl-Unblock-HTTP1/actions/runs/39694114991
Both PASS. Earlier CI failed only a stale t/01-version.t check expecting
0.11, which has been corrected on MAIN. The new Handoff-only commit
does not alter production/test logic.

Next in this HTTP1-specific chat: verify HEAD/main, README, Changes,
Makefile.PL, MANIFEST, test version assertions, exported module versions,
NativeABI header/install path, release dependencies and POD/synopsis.
Build and test a clean 0.12 tarball (disttest) from main, checking that
PAUSE will index every package version properly. Add release notes as
needed without breaking the coordinated unified API. Once approved,
publish/tag 0.12 to GitHub/CPAN and verify its index. No additional
profiling sweep or new framework adapter is part of this release.
The higher-level Unblock::HTTP 0.02 requires HTTP1 >= 0.12 and must be
published only after the required lower distributions are available.

## Historical development records (kept for detail; above is authoritative)

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
