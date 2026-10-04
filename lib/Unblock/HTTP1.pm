package Unblock::HTTP1;

use strict;
use warnings;

our $VERSION = '0.001';

require XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

1;

__END__

=head1 NAME

Unblock::HTTP1 - Event-loop neutral HTTP/1 protocol engine

=head1 SYNOPSIS

    use Uniform::HTTP::Request;
    use Unblock::HTTP1::Client;

    my $client = Unblock::HTTP1::Client->new;
    my $tx = $client->request(
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
    my $wire = $client->output while $client->want_write;

=head1 DESCRIPTION

Unblock::HTTP1 is a non-blocking HTTP/1.0 and HTTP/1.1 protocol engine.
It owns HTTP parsing, framing, serialization, message lifecycle, and protocol
switch boundaries. It does not own sockets, TLS, DNS, an event loop, or
connection policy.

The public HTTP message objects are L<Uniform::HTTP::Request> and
L<Uniform::HTTP::Response>.

See L<Unblock::HTTP1::Client> and L<Unblock::HTTP1::Server>.

=head1 LICENSE

MIT License.

=cut
