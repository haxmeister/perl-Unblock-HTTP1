use strict;
use warnings;

use Benchmark qw(cmpthese);
use Config;

use Uniform::HTTP::Request;
use Uniform::HTTP::Response;
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

my $response_wire =
    "HTTP/1.1 200 OK\r\n" .
    "Content-Type: text/plain\r\n" .
    "Content-Length: 5\r\n" .
    "\r\n";
my $response_head = Unblock::HTTP1::_Native->parse_response_head(
    $response_wire, 0, 100,
);
die "Unblock response setup parse failed\n"
    unless $response_head && $response_head->{ok};

sub trusted_uniform_request {
    my ($parsed) = @_;
    return bless {
        version           => $parsed->{version},
        headers           => $parsed->{headers},
        trailers          => [],
        initial_frozen    => 1,
        trailers_frozen   => 1,
        body              => undef,
        has_buffered_body => 0,
        complete          => 1,
        mutable           => 0,
        method            => $parsed->{method},
        target            => $parsed->{target},
        scheme            => undef,
        authority         => undef,
        protocol          => undef,
    }, 'Uniform::HTTP::Request';
}

sub trusted_uniform_response {
    my ($parsed) = @_;
    return bless {
        version           => $parsed->{version},
        headers           => $parsed->{headers},
        trailers          => [],
        initial_frozen    => 1,
        trailers_frozen   => 0,
        body              => undef,
        has_buffered_body => 0,
        complete          => 0,
        mutable           => 1,
        status            => $parsed->{status},
        reason            => $parsed->{reason},
    }, 'Uniform::HTTP::Response';
}

print "HTTP/1 receive-path comparison\n";
print "Perl $] ($Config{archname})\n";
print "Unblock::HTTP1 $Unblock::HTTP1::VERSION\n";
print "Linux::Event::HTTP::_HTTP1 $Linux::Event::HTTP::_HTTP1::VERSION\n";
print "approximately $seconds CPU seconds per case\n\n";

print "The public-object cases are the useful cross-engine comparison.\n";
print "The native cases expose different internal contracts and are diagnostic only.\n";
print "The trusted-shape case is diagnostic only and deliberately bypasses the\n";
print "documented Uniform constructor to estimate the value of a sanctioned\n";
print "trusted-parser construction API. It is not production code.\n\n";

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
        unblock_trusted_shape => sub {
            my $parsed = Unblock::HTTP1::_Native->parse_request_head(
                $wire, 0, 100,
            );
            die "Unblock parse failure" unless $parsed && $parsed->{ok};
            my $request = trusted_uniform_request($parsed);
            die "trusted-shape access failure"
                unless $request->method eq 'GET'
                    && $request->target eq '/api/resource?x=1'
                    && ($request->header('Host') || '') eq 'example.test';
        },
        unblock_public_response => sub {
            my $parsed = Unblock::HTTP1::_Native->parse_response_head(
                $response_wire, 0, 100,
            );
            die "Unblock response parse failure"
                unless $parsed && $parsed->{ok};
            my $response = Uniform::HTTP::Response->new(
                status  => $parsed->{status},
                reason  => $parsed->{reason},
                version => $parsed->{version},
                headers => $parsed->{headers},
            );
            $response->mark_incomplete->freeze_initial;
            die "Unblock response object failure"
                unless $response->status == 200
                    && ($response->header('Content-Type') || '') eq 'text/plain';
        },
        unblock_response_from_head => sub {
            my $response = Uniform::HTTP::Response->new(
                status  => $response_head->{status},
                reason  => $response_head->{reason},
                version => $response_head->{version},
                headers => $response_head->{headers},
            );
            $response->mark_incomplete->freeze_initial;
            die "Unblock response construction failure"
                unless $response->status == 200;
        },
        unblock_trusted_response => sub {
            my $parsed = Unblock::HTTP1::_Native->parse_response_head(
                $response_wire, 0, 100,
            );
            die "Unblock response parse failure"
                unless $parsed && $parsed->{ok};
            my $response = trusted_uniform_response($parsed);
            die "trusted response access failure"
                unless $response->status == 200
                    && ($response->header('Content-Type') || '') eq 'text/plain';
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
