use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use JSON::PP ();
use Time::HiRes qw(clock_gettime CLOCK_PROCESS_CPUTIME_ID);
use Unblock::HTTP1::Server;
use Unblock::HTTP1::_Native;
use Uniform::HTTP::Response;

# An independent engine workload: no framework, sockets or response cache.
{
    package ResponseBenchSink;
    sub unblock_send { ++$_[0]{writes}; $_[0]{bytes} += length($_[1]); 1 }
    sub unblock_finish { die 'unexpected connection close' }
    sub unblock_abort { die $_[1] }
}
my ($requests, $warmup, $headers, $body_bytes) = (100000, 1000, 1, 32);
my ($input, $mode, $json) = ('native', 'fields', undef);
GetOptions('requests=i' => \$requests, 'warmup=i' => \$warmup,
    'headers=i' => \$headers, 'body-bytes=i' => \$body_bytes,
    'input=s' => \$input, 'mode=s' => \$mode, 'json=s' => \$json) or die 'bad options';
die 'invalid options' unless $requests > 0 && $warmup >= 0 && $headers >= 0
    && $body_bytes >= 0 && $input =~ /\A(?:native|perl)\z/
    && $mode =~ /\A(?:fields|object)\z/;
my @fields = (status => 200, body => 'x' x $body_bytes);
push @fields, headers => [map { ['X-Bench', "value-$_"] } 1 .. $headers] if $headers;
my $sink = bless {writes => 0, bytes => 0}, 'ResponseBenchSink';
my $server = Unblock::HTTP1::Server->new(transport => $sink,
    on_request => $mode eq 'fields'
        ? sub { $_[0]->respond(@fields) }
        : sub { $_[0]->respond(Uniform::HTTP::Response->new(@fields)) });
my $wire = "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n";
my $driver = $input eq 'native'
    ? Unblock::HTTP1::_Native::BorrowedDriver->new($server) : undef;
my $run = $driver ? sub {
    my ($status, $used) = $driver->feed($wire);
    die 'incomplete native input' unless $status == 0 && $used == length($wire);
} : sub { $server->input($wire) };
$run->() for 1 .. $warmup;
my $start = clock_gettime(CLOCK_PROCESS_CPUTIME_ID);
$run->() for 1 .. $requests;
my $cpu = clock_gettime(CLOCK_PROCESS_CPUTIME_ID) - $start;
die 'missing responses' unless $sink->{writes} == $warmup + $requests;
my $result = {requests => $requests, warmup => $warmup, input => $input,
    mode => $mode, headers => $headers, body_bytes => $body_bytes,
    cpu_seconds => $cpu, cpu_us_per_request => $cpu * 1e6 / $requests,
    perl => "$^V", http1 => $Unblock::HTTP1::VERSION,
    uniform => $Uniform::HTTP::Response::VERSION,
    transaction_source => $INC{'Unblock/HTTP1/Transaction.pm'},
    writes => $sink->{writes}, bytes => $sink->{bytes}};
printf "%s %s headers=%d %.3f CPU us/request\n", $input, $mode, $headers,
    $result->{cpu_us_per_request};
if (defined $json) {
    open my $fh, '>', $json or die "$json: $!";
    print {$fh} JSON::PP->new->canonical->pretty->encode($result);
    close $fh or die "$json: $!";
}
