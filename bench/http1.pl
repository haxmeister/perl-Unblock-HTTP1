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
my $response_exchange_wire = $response_wire . 'hello';

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

my $body_size = 4096;
my $body = 'x' x $body_size;
my $chunk = 'x' x 1024;

my $fixed_request = Uniform::HTTP::Request->new(
    method    => 'POST',
    target    => '/fixed',
    authority => 'example.test',
    body      => $body,
);

my $fixed_response = Uniform::HTTP::Response->new(
    status => 200,
    body   => $body,
);

my $fixed_request_explicit = Uniform::HTTP::Request->new(
    method    => 'POST',
    target    => '/fixed',
    authority => 'example.test',
    headers   => [ [ 'Content-Length' => $body_size ] ],
    body      => $body,
);

my $fixed_response_explicit = Uniform::HTTP::Response->new(
    status  => 200,
    headers => [ [ 'Content-Length' => $body_size ] ],
    body    => $body,
);

my $stream_request = Uniform::HTTP::Request->new(
    method    => 'POST',
    target    => '/chunked',
    authority => 'example.test',
);

my $stream_response = Uniform::HTTP::Response->new(status => 200);

my $reuse_get_server = Unblock::HTTP1::Server->new(
    on_request => sub {
        $_[0]->respond($response);
    },
);
my $reuse_get_client = Unblock::HTTP1::Client->new;

my $server_cycle = Unblock::HTTP1::Server->new(
    on_request => sub {
        $_[0]->respond($response);
    },
);
my $client_cycle = Unblock::HTTP1::Client->new;

my $borrowed_server_cycle = Unblock::HTTP1::Server->new(
    on_request => sub {
        $_[0]->respond($response);
    },
);
my $borrowed_server_driver =
    Unblock::HTTP1::_Native::BorrowedDriver->new($borrowed_server_cycle);

my $reuse_fixed_request_bytes = 0;
my $reuse_fixed_response_bytes = 0;
my $reuse_fixed_server = Unblock::HTTP1::Server->new(
    on_request => sub { },
    on_body => sub {
        $reuse_fixed_request_bytes += length $_[2];
    },
    on_request_end => sub {
        $_[0]->respond($fixed_response);
    },
);
my $reuse_fixed_client = Unblock::HTTP1::Client->new;
my $reuse_fixed_on_body = sub {
    $reuse_fixed_response_bytes += length $_[2];
};

my $reuse_chunked_request_bytes = 0;
my $reuse_chunked_response_bytes = 0;
my $reuse_chunked_server = Unblock::HTTP1::Server->new(
    on_request => sub { },
    on_body => sub {
        $reuse_chunked_request_bytes += length $_[2];
    },
    on_request_end => sub {
        my ($tx) = @_;
        $tx->respond($stream_response, stream_body => 1);
        $tx->write($chunk) for 1 .. 3;
        $tx->end($chunk);
    },
);
my $reuse_chunked_client = Unblock::HTTP1::Client->new;
my $reuse_chunked_on_body = sub {
    $reuse_chunked_response_bytes += length $_[2];
};

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
        serialize_request_4k => sub {
            my $plan = Unblock::HTTP1::_Wire::request_plan($fixed_request);
            die "fixed request serialize failure"
                unless length($plan->{wire}) > $body_size
                    && $plan->{mode} eq 'content-length';
        },
        serialize_response_4k => sub {
            my $plan = Unblock::HTTP1::_Wire::response_plan(
                $fixed_request,
                $fixed_response,
            );
            die "fixed response serialize failure"
                unless length($plan->{wire}) > $body_size
                    && $plan->{mode} eq 'content-length';
        },
        serialize_request_4k_full => sub {
            my $plan = Unblock::HTTP1::_Wire::request_plan(
                $fixed_request_explicit,
            );
            die "full fixed request serialize failure"
                unless length($plan->{wire}) > $body_size
                    && $plan->{mode} eq 'content-length';
        },
        serialize_response_4k_full => sub {
            my $plan = Unblock::HTTP1::_Wire::response_plan(
                $fixed_request,
                $fixed_response_explicit,
            );
            die "full fixed response serialize failure"
                unless length($plan->{wire}) > $body_size
                    && $plan->{mode} eq 'content-length';
        },
        server_get_cycle => sub {
            $server_cycle->input($request_wire);
            my $wire = $server_cycle->output;
            die "server cycle failure"
                unless $wire =~ /\AHTTP\/1\.1 200 OK\r\n/;
        },
        server_get_borrowed => sub {
            my ($status, $consumed) =
                $borrowed_server_driver->feed($request_wire);
            die "borrowed server cycle failure"
                unless $status == 0 && $consumed == length($request_wire);
            my $wire = $borrowed_server_cycle->output;
            die "borrowed server output failure"
                unless $wire =~ /\AHTTP\/1\.1 200 OK\r\n/;
        },
        client_get_cycle => sub {
            my $tx = $client_cycle->request($request);
            $client_cycle->output;
            $client_cycle->input($response_exchange_wire);
            die "client cycle failure" unless $tx->is_complete;
        },
        reuse_get => sub {
            my $tx = $reuse_get_client->request($request);
            $reuse_get_server->input($reuse_get_client->output);
            $reuse_get_client->input($reuse_get_server->output);
            die "reused GET exchange failure" unless $tx->is_complete;
        },
        reuse_fixed_4k => sub {
            $reuse_fixed_request_bytes = 0;
            $reuse_fixed_response_bytes = 0;
            my $tx = $reuse_fixed_client->request(
                $fixed_request,
                on_body => $reuse_fixed_on_body,
            );
            $reuse_fixed_server->input($reuse_fixed_client->output);
            $reuse_fixed_client->input($reuse_fixed_server->output);
            die "reused fixed exchange failure"
                unless $tx->is_complete
                    && $reuse_fixed_request_bytes == $body_size
                    && $reuse_fixed_response_bytes == $body_size;
        },
        reuse_chunked_4k => sub {
            $reuse_chunked_request_bytes = 0;
            $reuse_chunked_response_bytes = 0;
            my $tx = $reuse_chunked_client->request(
                $stream_request,
                stream_body => 1,
                on_body => $reuse_chunked_on_body,
            );

            my $wire = $reuse_chunked_client->output;
            for (1 .. 3) {
                $tx->write($chunk);
                $wire .= $reuse_chunked_client->output;
            }
            $tx->end($chunk);
            $wire .= $reuse_chunked_client->output;

            $reuse_chunked_server->input($wire);
            $reuse_chunked_client->input($reuse_chunked_server->output);
            die "reused chunked exchange failure"
                unless $tx->is_complete
                    && $reuse_chunked_request_bytes == $body_size
                    && $reuse_chunked_response_bytes == $body_size;
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
        loopback_fixed_4k => sub {
            my $request_bytes = 0;
            my $response_bytes = 0;
            my $server = Unblock::HTTP1::Server->new(
                on_request => sub { },
                on_body => sub {
                    $request_bytes += length $_[2];
                },
                on_request_end => sub {
                    $_[0]->respond($fixed_response);
                },
            );
            my $client = Unblock::HTTP1::Client->new;
            my $tx = $client->request(
                $fixed_request,
                on_body => sub {
                    $response_bytes += length $_[2];
                },
            );
            $server->input($client->output);
            $client->input($server->output);
            die "fixed exchange failure"
                unless $tx->is_complete
                    && $request_bytes == $body_size
                    && $response_bytes == $body_size;
        },
        loopback_chunked_4k => sub {
            my $request_bytes = 0;
            my $response_bytes = 0;
            my $server = Unblock::HTTP1::Server->new(
                on_request => sub { },
                on_body => sub {
                    $request_bytes += length $_[2];
                },
                on_request_end => sub {
                    my ($tx) = @_;
                    $tx->respond(
                        Uniform::HTTP::Response->new(status => 200),
                        stream_body => 1,
                    );
                    $tx->write($chunk) for 1 .. 3;
                    $tx->end($chunk);
                },
            );
            my $client = Unblock::HTTP1::Client->new;
            my $tx = $client->request(
                $stream_request,
                stream_body => 1,
                on_body => sub {
                    $response_bytes += length $_[2];
                },
            );

            my $wire = $client->output;
            for (1 .. 3) {
                $tx->write($chunk);
                $wire .= $client->output;
            }
            $tx->end($chunk);
            $wire .= $client->output;

            $server->input($wire);
            $client->input($server->output);
            die "chunked exchange failure"
                unless $tx->is_complete
                    && $request_bytes == $body_size
                    && $response_bytes == $body_size;
        },
    },
);
