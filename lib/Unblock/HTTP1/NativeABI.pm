package Unblock::HTTP1::NativeABI;

use strict;
use warnings;

use Unblock::HTTP1 ();
use Unblock::HTTP1::_Native ();

our $VERSION = $Unblock::HTTP1::VERSION;

use constant ABI_VERSION   => 1;
use constant INPUT_OK      => 0;
use constant INPUT_MORE    => 1;
use constant INPUT_CLOSED  => 3;
use constant INPUT_SWITCH  => 4;

sub c_header {
    return <<'END_C_HEADER';
#ifndef UNBLOCK_HTTP1_INPUT_ABI_H
#define UNBLOCK_HTTP1_INPUT_ABI_H

#include "EXTERN.h"
#include "perl.h"
#include <stddef.h>
#include <stdint.h>

#define UB_HTTP1_INPUT_ABI_VERSION 1U

#define UB_HTTP1_INPUT_OK     0
#define UB_HTTP1_INPUT_MORE   1
#define UB_HTTP1_INPUT_CLOSED 3
#define UB_HTTP1_INPUT_SWITCH 4

typedef struct ub_http1_input_ops_v1_s {
    uint32_t abi_version;
    size_t struct_size;
    const char *name;

    void *(*create)(pTHX_ SV *engine);

    int (*input)(
        pTHX_
        void *context,
        const char *data,
        size_t length,
        size_t *consumed
    );

    int (*eof)(pTHX_ void *context);

    void (*destroy)(pTHX_ void *context);
} ub_http1_input_ops_v1;

#endif
END_C_HEADER
}

sub definition {
    return {
        provider           => \&Unblock::HTTP1::_Native::_borrowed_input_operations_address,
        abi_version        => ABI_VERSION,
        operations_address =>
            Unblock::HTTP1::_Native::_borrowed_input_operations_address(),
    };
}

1;

__END__

=head1 NAME

Unblock::HTTP1::NativeABI - Borrowed native input ABI for Unblock::HTTP1

=head1 DESCRIPTION

This module exposes the optional native input ABI used by event frameworks and
other XS transports.

The ordinary C<input()> API remains the portable interface. Native integrations
may instead pass a borrowed C buffer directly to the HTTP engine.

The input buffer remains owned by the caller. Unblock::HTTP1 may inspect it
only during the input call and never retains the pointer after that call
returns.

=head1 DEFINITION

    my $definition = Unblock::HTTP1::NativeABI::definition();

The returned hash contains:

    provider
    abi_version
    operations_address

C<provider> keeps the XS provider loaded and can be called again to obtain the
current operations address. C<abi_version> is currently 1.

=head1 C ABI

C<c_header()> returns the ABI version 1 C declaration. Build-time adapters may
write this text to a generated header rather than carrying a private copy of
the ABI layout.

The operations table contains C<abi_version>, C<struct_size>, C<name>,
C<create>, C<input>, C<eof>, and C<destroy>. Consumers must check both the ABI
version and structure size before dereferencing operations.

C<create> receives the Unblock::HTTP1 Client or Server object and returns one
connection-local native context. Keep that context for the lifetime of the
HTTP connection instead of creating it for every read.

=head1 INPUT RESULTS

ABI version 1 uses these result codes:

    INPUT_OK       0
    INPUT_MORE     1
    INPUT_CLOSED   3
    INPUT_SWITCH   4

C<INPUT_MORE> means the unconsumed tail must be retained by the host and
presented again with more contiguous bytes.

C<INPUT_SWITCH> means HTTP parsing has ended. The unconsumed tail belongs to
the protocol that takes ownership after HTTP.

=head1 LIFETIME

The native C input operation receives:

    const char *data
    size_t length
    size_t *consumed

C<data> is borrowed. It must remain readable until the operation returns.
Unblock::HTTP1 reports the permanently consumed prefix through C<consumed>.

The host may release or reuse the input storage immediately after the call has
returned, subject to preserving any unconsumed tail required by C<INPUT_MORE>
or C<INPUT_SWITCH>.

=head1 FALLBACK

The native ABI is an optimization. A framework that does not use XS, cannot
consume ABI version 1, or chooses not to use the fast path should continue to
call C<input()>.

=cut
