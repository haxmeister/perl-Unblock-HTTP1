use strict;
use warnings;
use Test::More;

use Uniform::HTTP::Request;
use Uniform::HTTP::Response;
use Unblock::HTTP1::Client;
use Unblock::HTTP1::Server;
use Unblock::HTTP1::_Wire;

subtest 'ordinary buffered request uses correct HTTP/1.1 framing' => sub {
    my $request = Uniform::HTTP::Request->new(
        method    => 'POST',
        target    => '/upload',
        authority => 'example.test',
        headers   => [ [ 'X-Test', 'one' ] ],
        body      => 'abc',
    );

    my $plan = Unblock::HTTP1::_Wire::request_plan($request);

    is(
        $plan->{wire},
        "POST /upload HTTP/1.1\r\n" .
        "X-Test: one\r\n" .
        "Host: example.test\r\n" .
        "Content-Length: 3\r\n" .
        "\r\n" .
        "abc",
        'buffered request gets Host and Content-Length exactly once',
    );
    is($plan->{mode}, 'content-length', 'buffered request reports fixed framing');
    is($plan->{remaining}, 0, 'buffered request body is already finalized');
    ok($plan->{keep_alive}, 'ordinary HTTP/1.1 request remains persistent');

    my $empty = Uniform::HTTP::Request->new(
        method    => 'POST',
        target    => '/empty',
        authority => 'example.test',
        body      => '',
    );
    my $empty_plan = Unblock::HTTP1::_Wire::request_plan($empty);
    like(
        $empty_plan->{wire},
        qr/\r\nContent-Length: 0\r\n\r\n\z/,
        'explicit empty buffered body retains Content-Length zero',
    );
};

sub server_events {
    my (@part) = @_;
    my @event;

    my $server = Unblock::HTTP1::Server->new(
        on_request => sub {
            my ($tx, $request) = @_;
            push @event, [
                request => $request->is_complete ? 1 : 0,
                $request->initial_is_mutable ? 1 : 0,
            ];
        },
        on_body => sub {
            my ($tx, $request, $bytes) = @_;
            push @event, [
                body => $bytes,
                $request->is_complete ? 1 : 0,
            ];
        },
        on_request_end => sub {
            my ($tx, $request) = @_;
            push @event, [
                end => $request->is_complete ? 1 : 0,
                $request->initial_is_mutable ? 1 : 0,
            ];
            $tx->respond(
                Uniform::HTTP::Response->new(status => 200, body => 'ok')
            );
        },
    );

    $server->input($_) for @part;
    return (\@event, $server->output);
}

subtest 'coalesced fixed request matches fragmented request lifecycle' => sub {
    my $head =
        "POST / HTTP/1.1\r\n" .
        "Host: example.test\r\n" .
        "Content-Length: 3\r\n" .
        "\r\n";

    my ($coalesced, $coalesced_wire) = server_events($head . 'abc');
    my ($fragmented, $fragmented_wire) = server_events($head . 'a', 'bc');

    is_deeply(
        $coalesced,
        [
            [ request => 0, 0 ],
            [ body => 'abc', 0 ],
            [ end => 1, 0 ],
        ],
        'coalesced fixed request preserves callback lifecycle',
    );
    is_deeply(
        $fragmented,
        $coalesced,
        'fragmented fixed request exposes the same callback lifecycle',
    );
    is($fragmented_wire, $coalesced_wire,
        'coalesced and fragmented requests produce identical response wire');
};

sub client_events {
    my (@part) = @_;
    my @event;

    my $client = Unblock::HTTP1::Client->new;
    my $tx = $client->request(
        Uniform::HTTP::Request->new(
            method  => 'GET',
            target  => '/',
            headers => [ [ Host => 'example.test' ] ],
        ),
        on_response => sub {
            my ($tx, $response) = @_;
            push @event, [
                response => $response->is_complete ? 1 : 0,
                $response->initial_is_mutable ? 1 : 0,
            ];
        },
        on_body => sub {
            my ($tx, $response, $bytes) = @_;
            push @event, [
                body => $bytes,
                $response->is_complete ? 1 : 0,
            ];
        },
        on_complete => sub {
            my ($tx) = @_;
            my $response = $tx->response;
            push @event, [
                complete => $response->is_complete ? 1 : 0,
                $response->initial_is_mutable ? 1 : 0,
            ];
        },
    );
    $client->output;

    $client->input($_) for @part;
    return (\@event, $tx);
}

subtest 'coalesced fixed response matches fragmented response lifecycle' => sub {
    my $head =
        "HTTP/1.1 200 OK\r\n" .
        "Content-Length: 3\r\n" .
        "\r\n";

    my ($coalesced, $coalesced_tx) = client_events($head . 'abc');
    my ($fragmented, $fragmented_tx) = client_events($head . 'a', 'bc');

    is_deeply(
        $coalesced,
        [
            [ response => 0, 0 ],
            [ body => 'abc', 0 ],
            [ complete => 1, 0 ],
        ],
        'coalesced fixed response preserves callback lifecycle',
    );
    is_deeply(
        $fragmented,
        $coalesced,
        'fragmented fixed response exposes the same callback lifecycle',
    );
    ok($coalesced_tx->is_complete, 'coalesced response transaction completes');
    ok($fragmented_tx->is_complete, 'fragmented response transaction completes');
};

done_testing;
