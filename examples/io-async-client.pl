#!/usr/bin/env perl
use strict;
use warnings;

use IO::Async::Loop;
use Unblock::HTTP1::Client;

# ADAPTER CODE: the framework Stream itself carries HTTP.
{
    package Local::HTTPClientStream;
    use parent 'IO::Async::Stream';

    sub attach_http {
        my ($self) = @_;
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
        $self->{http1} = Unblock::HTTP1::Client->new(transport => $self);
        return $self;
    }
    sub unblock_send {
        my ($self, $bytes) = @_;
        $self->write($bytes);
        return;
    }
    sub unblock_finish { $_[0]->close_when_empty; return }
    sub unblock_abort  { $_[0]->close_now; return }
}

my $port = shift || 8080;
die "usage: $0 [PORT]\n"
    unless $port =~ /\A[0-9]+\z/ && $port >= 1 && $port <= 65535;

my $loop = IO::Async::Loop->new;
$loop->connect(
    host => '127.0.0.1',
    service => $port,
    socktype => 'stream',
    on_connected => sub {
        my ($socket) = @_;
        my $stream = Local::HTTPClientStream->new(handle => $socket);
        $stream->attach_http;
        $loop->add($stream);

        # APPLICATION CODE: this is an ordinary HTTP request.
        $stream->{http1}->request(
            method => 'GET',
            target => '/',
            authority => '127.0.0.1:' . $port,
            on_response => sub {
                my ($tx, $response) = @_;
                print "HTTP status: ", $response->status, "\n";
            },
            on_body => sub {
                my ($tx, $response, $bytes) = @_;
                print $bytes;
            },
            on_complete => sub { $loop->stop },
            on_error => sub { die "HTTP request failed: $_[1]\n" },
        );
    },
    on_connect_error => sub {
        my ($operation, $error) = @_;
        die "$operation failed: $error\n";
    },
    on_resolve_error => sub { die "resolve failed: $_[-1]\n" },
);
$loop->run;
