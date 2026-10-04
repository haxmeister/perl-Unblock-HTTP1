package Unblock::HTTP1;

use strict;
use warnings;

our $VERSION = '0.01';

require XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

1;

__END__

=head1 NAME

Unblock::HTTP1 - Portable non-blocking HTTP/1 protocol engine

=head1 SYNOPSIS

    use Uniform::HTTP::Request;
    use Unblock::HTTP1::Client;

    my $client = Unblock::HTTP1::Client->new;

    $client->request(
        Uniform::HTTP::Request->new(
            method    => 'GET',
            target    => '/',
            authority => 'example.com',
        ),
        on_response => sub {
            my ($tx, $response) = @_;
            print $response->status, "\n";
        },
    );

    $client->input($bytes_from_transport);

    while ($client->want_write) {
        my $bytes = $client->output;
        $transport->write($bytes);
    }

=head1 DESCRIPTION

Unblock::HTTP1 is a portable HTTP/1.0 and HTTP/1.1 protocol engine.

It handles parsing, serialization, message framing, streaming bodies,
persistent connections, informational responses, trailers, Upgrade, and
CONNECT.

It does not open sockets, perform DNS or TLS, choose an event loop, or manage
connection pools.

HTTP messages use L<Uniform::HTTP::Request> and
L<Uniform::HTTP::Response>.

See L<Unblock::HTTP1::Client>, L<Unblock::HTTP1::Server>, and
L<Unblock::HTTP1::Transaction>.

=head1 LICENSE

MIT License.

=cut
