# Unblock::HTTP1 0.13 - release preparation

Status: source candidate prepared from
`feature/linux-event-integration`; do not create a release/tag/CPAN
upload until the maintainer separately authorizes publication.

## Scope

- Framework-neutral `Server->drain()` stops new HTTP/1 request admission,
  allows the active request and accepted output to finish, and preserves
  backpressure/EOF ordering. No event-loop dependency is introduced.
- Native simple-response serialization retains canonical Uniform messages,
  with complex cases and subclasses using their existing general path.
- Output ownership avoids duplicate serialized-byte retention.
- Bodyless requests avoid redundant receive/freeze work after validated
  complete, immutable Uniform Requests have already been created.

## Compatibility and dependencies

- Distribution / public-module version: 0.13.
- The native borrowed-input ABI remains at version **1**, with no layout
  or header contract change.
- Minimum Perl remains 5.16; Uniform::HTTP >= 0.06.
- Still independent of Linux::Event, IO::Async, AnyEvent or other loops.
- The 0.12 release does not contain `Server->drain()`.
  Consumers requiring graceful drain must depend on >= 0.13 once
  published (an unreleased feature checkout is not a CPAN requirement).

## Verification gates

- Standalone source tests for Linux Perl 5.16/latest, macOS/latest,
  and Windows Perl 5.40 (test.yml).
- Framework examples tests, including AnyEvent, IO::Async and optional
  Linux::Event hosting (framework-examples.yml).
- POD, distcheck and make disttest, and packaged public header discovery.
- Static version check t/01-version.t; confirmed NativeABI version 1.
- Release tarball/PAUSE metadata inspection before uploading.
- Coordinated Linux::Event::HTTP regressions must remain green.

There are no framework-specific performance modes or deviations from
canonical Uniform::HTTP messages in this update.

This document is a release-preparation record, **not** a claim that
version 0.13 has been published.
