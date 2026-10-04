use strict;
use warnings;

use Benchmark qw(cmpthese);
use Config;

use Uniform::HTTP::Request;
use Unblock::HTTP1;
use Unblock::HTTP1::_Native;

eval {
    require Linux::Event::HTTP::_HTTP1;
    1;
} or die "Linux::Event::HTTP::_HTTP1 is required for this development benchmark\n$@";

my $seconds = @ARGV ? shift @ARGV : 3;
die "usage: $0 [seconds]\n"
    unless defined($seconds) && $seconds =~ /\A[1-9][0-9]*\z/ && !@ARGV;

my $wire =
    "GET /api/resource?x=1 HTTP/1.1\r\n" .
    "Host: example.test\r\n" .
    "User-Agent: HTTP1-Comparison\r\n" .
    "Accept: */*\r\n" .
    "Connection: keep-alive\r\n" .
    "\r\n";

my $head = Unblock::HTTP1::_Native->parse_request_head($wire, 0, 100);
die "Unblock setup parse failed\n" unless $head && $head->{ok};

print "HTTP/1 receive-path comparison\n";
print "Perl $] ($Config{archname})\n";
print "Unblock::HTTP1 $Unblock::HTTP1::VERSION\n";
print "Linux::Event::HTTP::_HTTP1 $Linux::Event::HTTP::_HTTP1::VERSION\n";
print "approximately $seconds CPU seconds per case\n\n";

print "The public-object cases are the useful cross-engine comparison.\n";
print "The native cases expose different internal contracts and are diagnostic only.\n\n";

cmpthese(
    -$seconds,
    {
        unblock_native_head => sub {
            my $parsed = Unblock::HTTP1::_Native->parse_request_head(
                $wire, 0, 100,
            );
            die "Unblock parse failure" unless $parsed && $parsed->{ok};
        },
        unblock_public_request => sub {
            my $parsed = Unblock::HTTP1::_Native->parse_request_head(
                $wire, 0, 100,
            );
            die "Unblock parse failure" unless $parsed && $parsed->{ok};
            my $request = Uniform::HTTP::Request->new(
                method  => $parsed->{method},
                target  => $parsed->{target},
                version => $parsed->{version},
                headers => $parsed->{headers},
            );
            $request->freeze;
            die "Unblock object failure"
                unless $request->method eq 'GET';
        },
        unblock_common_access => sub {
            my $parsed = Unblock::HTTP1::_Native->parse_request_head(
                $wire, 0, 100,
            );
            die "Unblock parse failure" unless $parsed && $parsed->{ok};
            my $request = Uniform::HTTP::Request->new(
                method  => $parsed->{method},
                target  => $parsed->{target},
                version => $parsed->{version},
                headers => $parsed->{headers},
            );
            $request->freeze;
            die "Unblock access failure"
                unless $request->method eq 'GET'
                    && $request->target eq '/api/resource?x=1'
                    && ($request->header('Host') || '') eq 'example.test';
        },
        unblock_object_from_head => sub {
            my $request = Uniform::HTTP::Request->new(
                method  => $head->{method},
                target  => $head->{target},
                version => $head->{version},
                headers => $head->{headers},
            );
            $request->freeze;
            die "Unblock construction failure"
                unless $request->method eq 'GET';
        },
        linux_native_request => sub {
            my $request = Linux::Event::HTTP::_HTTP1->parse_request(
                $wire, 0, 100,
            );
            die "Linux::Event::HTTP parse failure" unless $request;
        },
        linux_common_access => sub {
            my $request = Linux::Event::HTTP::_HTTP1->parse_request(
                $wire, 0, 100,
            );
            die "Linux::Event::HTTP parse failure" unless $request;
            die "Linux::Event::HTTP access failure"
                unless $request->method eq 'GET'
                    && $request->target eq '/api/resource?x=1'
                    && ($request->header('Host') || '') eq 'example.test';
        },
    },
);
