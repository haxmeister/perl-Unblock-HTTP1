use strict;
use warnings;
use Time::HiRes qw(clock_gettime CLOCK_PROCESS_CPUTIME_ID);
use Unblock::HTTP1::Server;
use Unblock::HTTP1::_Native;

my $mode = shift // 'native';
my $count = shift // 20_000;
die "usage: $0 native|portable [count]\n"
    unless ($mode eq 'native' || $mode eq 'portable')
        && $count =~ /\A[1-9][0-9]*\z/ && !@ARGV;

{
    package Local::AcceptAll;
    sub new { bless { writes => 0 }, $_[0] }
    sub unblock_send {
        $_[0]{writes}++;
        return 1;
    }
    sub unblock_finish { return }
    sub unblock_abort { die $_[1] }
}

my $host = Local::AcceptAll->new;
my $server = Unblock::HTTP1::Server->new(
    transport => $host,
    on_request => sub {
        $_[0]->respond(status => 200, body => 'ok');
    },
);
my $driver = $mode eq 'native'
    ? Unblock::HTTP1::_Native::BorrowedDriver->new($server)
    : undef;
my $wire = "GET / HTTP/1.1\r\nHost: example.test\r\n\r\n";
my $feed = $driver
    ? sub {
        my ($status, $consumed) = $driver->feed($wire);
        die "borrowed feed failed" unless $status == 0 && $consumed == length($wire);
    }
    : sub {
        my $consumed = $server->input($wire);
        die "portable feed failed" unless $consumed == length($wire);
    };

$feed->() for 1 .. 500;
my @samples;
for (1 .. 3) {
    my $start = clock_gettime(CLOCK_PROCESS_CPUTIME_ID());
    $feed->() for 1 .. $count;
    my $elapsed = clock_gettime(CLOCK_PROCESS_CPUTIME_ID()) - $start;
    push @samples, $elapsed * 1_000_000 / $count;
}
die 'missing responses' unless $host->{writes} == 500 + 3 * $count;
my @ordered = sort { $a <=> $b } @samples;
printf "mode=%s cpu_us_per_request median=%.4f samples=%s version=%s\n",
    $mode, $ordered[1],
    join(',', map { sprintf('%.4f', $_) } @samples),
    $Unblock::HTTP1::Server::VERSION;
