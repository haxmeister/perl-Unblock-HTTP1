use strict;
use warnings;
use Test::More;
use Unblock::HTTP1::Server;

my @completed;
my $server = Unblock::HTTP1::Server->new(
    receive_body => 'buffered',
    on_request_end => sub {
        my ($tx, $request) = @_;
        push @completed, [
            $request->target, $request->body,
            $request->is_complete, $request->is_mutable,
        ];
        $tx->respond(status => 200, body => $request->target);
    },
);
my $head = "POST /split HTTP/1.1\r\nHost: example.test\r\nContent-Length: 4\r\n\r\n";
$server->input($head . 'ab');
is_deeply(\@completed, [], 'completion-only handler waits for request body');
$server->input('cd');
is_deeply(\@completed, [ ['/split', 'abcd', 1, 0] ],
    'completion-only handler sees validated frozen full request');
my $wire = $server->output;
like($wire, qr/HTTP\/1\.1 200 OK\r\n/, 'complete request response serialized');
like($wire, qr/\r\n\r\n\/split\z/, 'complete response body written');

my $batch =
    "GET /first HTTP/1.1\r\nHost: example.test\r\n\r\n" .
    "GET /second HTTP/1.1\r\nHost: example.test\r\n\r\n";
$server->input($batch);
is_deeply(\@completed,
    [
        ['/split', 'abcd', 1, 0],
        ['/first', '', 1, 0],
        ['/second', '', 1, 0],
    ],
    'pipelined bodyless requests each complete once without a header handler',
);
$wire = $server->output;
is(scalar(() = $wire =~ /HTTP\/1\.1 200 OK\r\n/g), 2,
    'pipelined completion-only responses serialized');
ok(!$server->is_closed, 'connection remains reusable');

my @events;
my $both = Unblock::HTTP1::Server->new(
    on_request => sub { push @events, 'headers' },
    on_request_end => sub {
        push @events, 'complete';
        $_[0]->respond(status => 200, body => '');
    },
);
$both->input("GET / HTTP/1.1\r\nHost: example.test\r\n\r\n");
is_deeply(\@events, ['headers', 'complete'],
    'explicit header and completion callbacks retain order');

ok(!eval { Unblock::HTTP1::Server->new(); 1 },
    'server without either request callback is still rejected');
like($@, qr/on_request or on_request_end callback is required/,
    'missing request callback explains requirement');

done_testing;
