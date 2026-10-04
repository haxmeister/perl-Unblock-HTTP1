use strict;
use warnings;
use Test::More;

use Unblock::HTTP1;
use Unblock::HTTP1::_Native;

my $head = Unblock::HTTP1::_Native->parse_request_head(
    "POST /upload HTTP/1.1\r\n" .
    "Host: example.test\r\n" .
    "Content-Length: 5\r\n\r\nhello"
);
ok($head->{ok}, 'request head parses');
is($head->{version}, '1.1', 'request version retained');
is($head->{method}, 'POST', 'method retained');
is($head->{target}, '/upload', 'target retained');
is($head->{body_mode}, 'content-length', 'content-length framing detected');
is($head->{content_length}, 5, 'content length retained');
ok($head->{keep_alive}, 'HTTP/1.1 persistent by default');

my $bad_version = Unblock::HTTP1::_Native->parse_request_head(
    "GET / HTTP/1.2\r\nHost: example.test\r\n\r\n"
);
ok(!$bad_version->{ok}, 'unsupported HTTP/1 version rejected');
is($bad_version->{status}, 505, 'unsupported request version maps to 505');

my $ambiguous = Unblock::HTTP1::_Native->parse_request_head(
    "POST / HTTP/1.1\r\nHost: example.test\r\n" .
    "Content-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\n"
);
ok(!$ambiguous->{ok}, 'TE plus CL rejected');
is($ambiguous->{status}, 400, 'ambiguous request framing maps to 400');

my $response = Unblock::HTTP1::_Native->parse_response_head(
    "HTTP/1.1 200 OK\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2\r\n\r\nbody"
);
ok($response->{ok}, 'response head parses');
is($response->{status}, 200, 'response status retained');
is_deeply(
    $response->{headers},
    [ [ 'Set-Cookie', 'a=1' ], [ 'Set-Cookie', 'b=2' ] ],
    'duplicate response headers remain ordered and separate',
);

my $decoder = Unblock::HTTP1::_Native::Chunked->new;
my ($done, $decoded, $left) = $decoder->feed(
    "4\r\nWiki\r\n0\r\nX-End: yes\r\n\r\nNEXT", 1
);
ok($done, 'chunked decoder stops at zero chunk');
is($decoded, 'Wiki', 'chunked payload decoded');
is($left, "X-End: yes\r\n\r\nNEXT", 'trailer block remains visible to engine');

for my $bad_chunk (
    "4\nWiki\r\n0\r\n\r\n",
    "4\r\nWiki\n0\r\n\r\n",
    "0\n\r\n",
) {
    my $strict = Unblock::HTTP1::_Native::Chunked->new;
    my $ok = eval {
        $strict->feed($bad_chunk, 1);
        1;
    };
    ok(!$ok, 'bare-LF chunk framing is rejected');
    like($@, qr/malformed HTTP\/1 chunked body/,
        'chunk framing error is explicit');
}

my $trailers = Unblock::HTTP1::_Native->parse_trailers($left);
ok($trailers->{ok}, 'trailer block parses separately');
is_deeply($trailers->{headers}, [ [ 'X-End', 'yes' ] ], 'trailer field retained');
is(substr($left, $trailers->{consumed}), 'NEXT', 'post-message bytes remain after trailers');

done_testing;
