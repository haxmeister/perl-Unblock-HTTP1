use strict;
use warnings;

use Benchmark qw(cmpthese);
use Config;

use Uniform::HTTP::Request;
use Uniform::HTTP::Response;
use Unblock::HTTP1;
use Unblock::HTTP1::_Wire;

my $seconds = @ARGV ? shift @ARGV : 2;
die "usage: $0 [seconds]\n"
    unless defined($seconds) && $seconds =~ /\A[1-9][0-9]*\z/ && !@ARGV;

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

my $request_fields = Unblock::HTTP1::_Wire::_fields($request, 'header');
my $response_fields = Unblock::HTTP1::_Wire::_fields($response, 'header');

print "Unblock::HTTP1 $Unblock::HTTP1::VERSION serialization diagnostic\n";
print "Perl $] ($Config{archname})\n";
print "approximately $seconds CPU seconds per case\n\n";

cmpthese(
    -$seconds,
    {
        request_fields => sub {
            my $fields = Unblock::HTTP1::_Wire::_fields($request, 'header');
            die unless @$fields == 3;
        },
        response_fields => sub {
            my $fields = Unblock::HTTP1::_Wire::_fields($response, 'header');
            die unless @$fields == 1;
        },
        request_validate => sub {
            my $cl = Unblock::HTTP1::_Wire::_content_length($request_fields);
            my $te = Unblock::HTTP1::_Wire::_transfer_encoding($request_fields);
            my $connection = Unblock::HTTP1::_Wire::_connection_tokens($request_fields);
            die if defined($cl) || @$te || $connection->{close};
        },
        response_validate => sub {
            my $cl = Unblock::HTTP1::_Wire::_content_length($response_fields);
            my $te = Unblock::HTTP1::_Wire::_transfer_encoding($response_fields);
            die if defined($cl) || @$te;
        },
        request_assemble => sub {
            my $wire =
                "GET /hello?x=1 HTTP/1.1\r\n" .
                "Host: example.test\r\n" .
                "User-Agent: Unblock-Benchmark\r\n" .
                "Accept: */*\r\n\r\n";
            die unless length($wire) == 108;
        },
        response_assemble => sub {
            my $wire =
                "HTTP/1.1 200 OK\r\n" .
                "Content-Type: text/plain\r\n" .
                "Content-Length: 5\r\n\r\nhello";
            die unless length($wire) == 69;
        },
        request_plan => sub {
            my $plan = Unblock::HTTP1::_Wire::request_plan($request);
            die unless length $plan->{wire};
        },
        response_plan => sub {
            my $plan = Unblock::HTTP1::_Wire::response_plan($request, $response);
            die unless length $plan->{wire};
        },
        request_new => sub {
            my $value = Uniform::HTTP::Request->new(
                method => 'GET',
                target => '/hello?x=1',
                headers => [
                    [ Host => 'example.test' ],
                    [ 'User-Agent' => 'Unblock-Benchmark' ],
                    [ Accept => '*/*' ],
                ],
            );
            die unless $value->method eq 'GET';
        },
        response_new => sub {
            my $value = Uniform::HTTP::Response->new(
                status => 200,
                headers => [ [ 'Content-Type' => 'text/plain' ] ],
                body => 'hello',
            );
            die unless $value->status == 200;
        },
    },
);
