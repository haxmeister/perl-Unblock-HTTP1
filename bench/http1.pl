use strict;
use warnings;

use Benchmark qw(cmpthese);
use Config;

use Uniform::HTTP::Request;
use Uniform::HTTP::Response;
use Unblock::HTTP1::Client;
use Unblock::HTTP1::Server;
use Unblock::HTTP1::_Native;
use Unblock::HTTP1::_Wire;

my $seconds = @ARGV ? shift @ARGV : 3;
die "usage: $0 [seconds]\n"
    unless defined($seconds) && $seconds =~ /\A[1-9][0-9]*\z/ && !@ARGV;

my $request_wire =
    "GET /hello?x=1 HTTP/1.1\r\n" .
    "Host: example.test\r\n" .
    "User-Agent: Unblock-Benchmark\r\n" .
    "Accept: */*\r\n" .
    "\r\n";

my $response_wire =
    "HTTP/1.1 200 OK\r\n" .
    "Content-Type: text/plain\r\n" .
    "Content-Length: 5\r\n" .
    "\r\n";

my $request = Uniform::HTTP::Request->new(
    method  => 'GET',
    target  => '/hello?x=1',
    headers => [
        [ Host => 'example.test' ],
        [ 'User-Agent' => 'Unblock-Benchmark' ],
        [ Accept => '*/*' ],
    ],
);

my $response = Uniform::HTTP::Response->new(
    status  => 200,
    headers => [ [ 'Content-Type' => 'text/plain' ] ],
    body    => 'hello',
);

print "Unblock::HTTP1 $Unblock::HTTP1::VERSION benchmark\n";
print "Perl $] ($Config{archname})\n";
print "picohttpparser ", Unblock::HTTP1::_Native->pico_version, "\n";
print "approximately $seconds CPU seconds per case\n\n";

cmpthese(
    -$seconds,
    {
        parse_request => sub {
            my $head = Unblock::HTTP1::_Native->parse_request_head($request_wire);
            die "parse failure" unless $head && $head->{ok};
        },
        parse_response => sub {
            my $head = Unblock::HTTP1::_Native->parse_response_head($response_wire);
            die "parse failure" unless $head && $head->{ok};
        },
        serialize_request => sub {
            my $plan = Unblock::HTTP1::_Wire::request_plan($request);
            die "serialize failure" unless length $plan->{wire};
        },
        serialize_response => sub {
            my $plan = Unblock::HTTP1::_Wire::response_plan($request, $response);
            die "serialize failure" unless length $plan->{wire};
        },
        loopback_get => sub {
            my $server = Unblock::HTTP1::Server->new(
                on_request => sub {
                    my ($tx) = @_;
                    $tx->respond(Uniform::HTTP::Response->new(
                        status => 200,
                        body   => 'hello',
                    ));
                },
            );
            my $client = Unblock::HTTP1::Client->new;
            my $tx = $client->request($request);
            $server->input($client->output);
            $client->input($server->output);
            die "exchange failure" unless $tx->is_complete;
        },
    },
);
