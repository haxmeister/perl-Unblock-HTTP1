#!/usr/bin/env perl
use strict;
use warnings;

use IO::Async::Listener;
use IO::Async::Loop;
use Unblock::HTTP1::Server;

# ADAPTER CODE: this class is the framework's normal stream object.
# It owns HTTP protocol state. HTTP retains only a weak reference back to it.
{
    package Local::HTTPStream;
    use parent 'IO::Async::Stream';

    sub attach_http {
        my ($self, $on_request) = @_;
        $self->configure(
            close_on_read_eof => 0,
            on_read => sub {
                my ($stream, $bufref, $eof) = @_;
                if (length $$bufref) {
                    my $bytes = $$bufref;
                    $$bufref = '';
                    $stream->{http1}->input($bytes);
                }
                $stream->{http1}->input_eof
                    if $eof && !$stream->{http1}->is_closed
                    && !$stream->{http1}->is_switched;
                return 0;
            },
            on_read_error => sub {
                my ($stream, $error) = @_;
                $stream->{http1}->transport_error("read error: $error");
            },
            on_write_error => sub {
                my ($stream, $error) = @_;
                $stream->{http1}->transport_error("write error: $error");
            },
        );
        $self->{http1} = Unblock::HTTP1::Server->new(
            transport => $self,
            on_request => $on_request,
        );
        return $self;
    }

    sub unblock_send {
        my ($self, $bytes) = @_;
        $self->write($bytes);
        return; # IO::Async owns the full output queue.
    }

    sub unblock_finish { $_[0]->close_when_empty; return }
    sub unblock_abort  { $_[0]->close_now; return }
}

# APPLICATION CODE: no HTTP parsing, output pumping, or Uniform constructors.
my $on_request = sub {
    my ($tx, $request) = @_;
    $tx->respond(
        status  => 200,
        headers => [ [ 'Content-Type' => 'text/plain' ] ],
        body    => "hello from IO::Async\n",
    );
};

my $port = shift || 8080;
die "usage: $0 [PORT]\n"
    unless $port =~ /\A[0-9]+\z/ && $port >= 1 && $port <= 65535;

my $loop = IO::Async::Loop->new;
my $listener = IO::Async::Listener->new(
    handle_class => 'Local::HTTPStream',
    on_accept => sub {
        my ($listener, $stream) = @_;
        $stream->attach_http($on_request);
        $loop->add($stream);
    },
);
$loop->add($listener);
$listener->listen(service => $port, socktype => 'stream')->get;
print "listening on port $port\n";
$loop->run;
