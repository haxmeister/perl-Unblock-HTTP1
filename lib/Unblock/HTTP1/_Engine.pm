package Unblock::HTTP1::_Engine;

use strict;
use warnings;
use Carp qw(croak);
use utf8 ();

sub _init_engine {
    my ($self, %option) = @_;
    my %known = map { $_ => 1 } qw(
        max_head_size
        max_headers
        max_chunk_extension_size
        high_water
        low_water
    );
    for my $key (sort keys %option) {
        croak "new(): unknown option '$key'" unless $known{$key};
    }
    $self->{max_head_size} = exists $option{max_head_size} ? $option{max_head_size} : 65_536;
    $self->{max_headers} = exists $option{max_headers} ? $option{max_headers} : 100;
    $self->{max_chunk_extension_size} = exists $option{max_chunk_extension_size}
        ? $option{max_chunk_extension_size} : 16_384;
    $self->{high_water} = exists $option{high_water} ? $option{high_water} : 65_536;
    $self->{low_water} = exists $option{low_water} ? $option{low_water} : 32_768;
    for my $key (qw(max_head_size max_headers max_chunk_extension_size high_water low_water)) {
        croak "new(): $key must be a non-negative integer"
            unless defined($self->{$key}) && !ref($self->{$key}) && $self->{$key} =~ /\A[0-9]+\z/;
    }
    croak 'new(): max_head_size must be positive' unless $self->{max_head_size} > 0;
    croak 'new(): max_headers must be between 1 and 256'
        unless $self->{max_headers} >= 1 && $self->{max_headers} <= 256;
    croak 'new(): low_water must not exceed high_water'
        if $self->{low_water} > $self->{high_water};
    $self->{input} = '';
    $self->{output} = '';
    $self->{closed} = 0;
    $self->{switched} = 0;
    $self->{remainder} = '';
    $self->{driving} = 0;
    $self->{eof} = 0;
    return $self;
}

sub is_closed { $_[0]{closed} ? 1 : 0 }
sub is_switched { $_[0]{switched} ? 1 : 0 }
sub want_read { !$_[0]{closed} && !$_[0]{switched} ? 1 : 0 }
sub want_write { length($_[0]{output}) ? 1 : 0 }

sub input {
    my ($self, $bytes) = @_;
    croak 'input(): bytes must be a scalar' if ref($bytes);
    $bytes = '' unless defined $bytes;
    my $copy = "$bytes";
    croak 'input(): bytes must be a byte string' unless utf8::downgrade($copy, 1);
    return 0 unless length $copy;
    croak 'input(): cannot be called recursively from an engine callback' if $self->{driving};
    if ($self->{switched}) {
        $self->{remainder} .= $copy;
        return length $copy;
    }
    croak 'input(): connection is closed' if $self->{closed};
    $self->{input} .= $copy;
    local $self->{driving} = 1;
    $self->_drive;
    return length $copy;
}

sub input_eof {
    my ($self) = @_;
    return $self if $self->{eof};
    croak 'input_eof(): cannot be called recursively from an engine callback' if $self->{driving};
    $self->{eof} = 1;
    local $self->{driving} = 1;
    $self->_on_eof;
    return $self;
}

sub output {
    my ($self, $max) = @_;
    croak 'output(): cannot be called recursively from an engine callback' if $self->{driving};
    return '' unless length $self->{output};
    my $take = length $self->{output};
    if (defined $max) {
        croak 'output(): maximum must be a positive integer'
            unless !ref($max) && $max =~ /\A[0-9]+\z/ && $max > 0;
        $take = $max if $max < $take;
    }
    my $bytes = substr($self->{output}, 0, $take, '');
    $self->_after_output;
    return $bytes;
}

sub take_remainder {
    my ($self) = @_;
    croak 'take_remainder(): HTTP/1 connection has not switched protocols'
        unless $self->{switched};
    my $bytes = $self->{remainder};
    $self->{remainder} = '';
    return $bytes;
}

sub close {
    my ($self, $error) = @_;
    return $self if $self->{closed};
    $self->{closed} = 1;
    $self->_fail_all(defined($error) && length($error) ? "$error" : 'HTTP/1 connection closed');
    return $self;
}

sub _queue_output {
    my ($self, $bytes) = @_;
    return unless defined $bytes && length $bytes;
    $self->{output} .= $bytes;
    return;
}

sub _mark_switched {
    my ($self) = @_;
    return if $self->{switched};
    $self->{switched} = 1;
    $self->{remainder} .= $self->{input};
    $self->{input} = '';
    return;
}

sub _after_output {
    my ($self) = @_;
    $self->_maybe_drain if length($self->{output}) <= $self->{low_water};
    return;
}

sub _stream_ok {
    my ($self) = @_;
    return length($self->{output}) < $self->{high_water} ? 1 : 0;
}

sub _maybe_drain { return }
sub _fail_all { return }

1;
