use strict;
use warnings;
use Test::More;
use Unblock::HTTP1::Server;

{
    package Local::ImmediateAccept;
    sub new { bless { writes => [] }, $_[0] }
    sub unblock_send {
        my ($self, $wire) = @_;
        push @{ $self->{writes} }, $wire;
        return 1;
    }
    sub unblock_finish { return }
    sub unblock_abort { die $_[1] }
}

for my $with_end (0, 1) {
    my $host = Local::ImmediateAccept->new;
    my @events;
    my %args = (
        transport => $host,
        on_request => sub {
            my ($tx, $request) = @_;
            push @events, 'request:' . $request->target;
            $tx->on_finish(sub {
                push @events, 'finish:' . $request->target;
            });
            $tx->respond(status => 200, body => $request->target);
        },
    );
    if ($with_end) {
        $args{on_request_end} = sub {
            my ($tx, $request) = @_;
            push @events, 'end:' . $request->target;
        };
    }

    my $server = Unblock::HTTP1::Server->new(%args);
    my $wire =
        "GET /one HTTP/1.1\r\nHost: example.test\r\n\r\n" .
        "GET /two HTTP/1.1\r\nHost: example.test\r\n\r\n";
    is($server->input($wire), length($wire),
        'attached server consumes pipelined input');
    my @expected;
    for my $target ('/one', '/two') {
        push @expected, 'request:' . $target;
        push @expected, 'end:' . $target if $with_end;
        push @expected, 'finish:' . $target;
    }
    is_deeply(\@events, \@expected,
        'optional completion observer and terminal order preserved');
    my $output = join('', @{ $host->{writes} });
    is(scalar(() = $output =~ /HTTP\/1\.1 200 OK\r\n/g), 2,
        'both pipelined outputs accepted by host');
    like($output, qr/\r\n\r\n\/one/, 'first body retained');
    like($output, qr/\r\n\r\n\/two/, 'second body retained');
    ok(!$server->is_closed, 'keep-alive survives accepted outputs');
}

done_testing;
