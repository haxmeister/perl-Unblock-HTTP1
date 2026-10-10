use strict;
use warnings;

use Time::HiRes qw(time);
use Uniform::HTTP::Response;
use Unblock::HTTP1::Server;

my $mode = shift || 'manual';
my $iterations = shift || 100_000;
die "usage: $0 [manual|attached] [iterations]\n"
    unless ($mode eq 'manual' || $mode eq 'attached')
    && $iterations =~ /\A[1-9][0-9]*\z/ && !@ARGV;

{
    package Local::BenchmarkHost;
    sub new { bless { bytes => 0 }, $_[0] }
    sub unblock_send {
        my ($self, $bytes) = @_;
        $self->{bytes} += length $bytes;
        return;
    }
    sub unblock_finish { return }
    sub unblock_abort { die $_[1] }
}

my $request_wire =
    "GET /bench HTTP/1.1\r\nHost: example.test\r\n\r\n";
my $response = Uniform::HTTP::Response->new(
    status => 200, body => 'hello',
);
my $host = $mode eq 'attached' ? Local::BenchmarkHost->new : undef;
my $server = Unblock::HTTP1::Server->new(
    ($host ? (transport => $host) : ()),
    on_request => sub { $_[0]->respond($response) },
);

# Warm up the serializer and the parser before the timed loop.
for (1 .. 1000) {
    $server->input($request_wire);
    $server->output if $mode eq 'manual';
}

my $start = time;
for (1 .. $iterations) {
    $server->input($request_wire);
    $server->output if $mode eq 'manual';
}
my $elapsed = time - $start;
printf "mode=%s requests=%d elapsed=%.6f req_per_sec=%.0f\n",
    $mode, $iterations, $elapsed, $iterations / $elapsed;
