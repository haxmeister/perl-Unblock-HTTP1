use strict;
use warnings;
use Test::More;

use Uniform::HTTP::Request;
use Uniform::HTTP::Response;
use Unblock::HTTP1::Client;
use Unblock::HTTP1::Server;

my $server = Unblock::HTTP1::Server->new(
    on_request => sub {
        my ($tx) = @_;
        $tx->send_informational(Uniform::HTTP::Response->new(
            status => 103,
            headers => [ [ Link => '</style.css>; rel=preload' ] ],
        ));
        $tx->respond(Uniform::HTTP::Response->new(status => 200, body => 'ok'));
    },
);

my @status;
my $client = Unblock::HTTP1::Client->new;
$client->request(
    Uniform::HTTP::Request->new(
        method => 'GET', target => '/', authority => 'example.test',
    ),
    on_informational => sub { push @status, $_[1]->status },
    on_response => sub { push @status, $_[1]->status },
    on_error => sub { die "client error: $_[1]" },
);
$server->input($client->output);
$client->input($server->output);
is_deeply(\@status, [103, 200], 'informational response precedes final response');

done_testing;
