package Unblock::HTTP1::_Wire;

use strict;
use warnings;
use Carp qw(croak);
use utf8 ();

my %REASON = (
    100 => 'Continue', 101 => 'Switching Protocols', 103 => 'Early Hints',
    200 => 'OK', 201 => 'Created', 202 => 'Accepted', 204 => 'No Content',
    205 => 'Reset Content', 206 => 'Partial Content',
    300 => 'Multiple Choices', 301 => 'Moved Permanently', 302 => 'Found',
    303 => 'See Other', 304 => 'Not Modified', 307 => 'Temporary Redirect',
    308 => 'Permanent Redirect', 400 => 'Bad Request', 401 => 'Unauthorized',
    403 => 'Forbidden', 404 => 'Not Found', 405 => 'Method Not Allowed',
    408 => 'Request Timeout', 409 => 'Conflict', 410 => 'Gone',
    411 => 'Length Required', 413 => 'Content Too Large', 414 => 'URI Too Long',
    415 => 'Unsupported Media Type', 417 => 'Expectation Failed',
    421 => 'Misdirected Request', 422 => 'Unprocessable Content',
    426 => 'Upgrade Required', 428 => 'Precondition Required',
    429 => 'Too Many Requests', 431 => 'Request Header Fields Too Large',
    451 => 'Unavailable For Legal Reasons', 500 => 'Internal Server Error',
    501 => 'Not Implemented', 502 => 'Bad Gateway', 503 => 'Service Unavailable',
    504 => 'Gateway Timeout', 505 => 'HTTP Version Not Supported',
);

sub _bytes {
    my ($label, $value) = @_;
    croak "$label must be a defined scalar byte string"
        if !defined($value) || ref($value);
    my $copy = "$value";
    croak "$label must be a byte string" unless utf8::downgrade($copy, 1);
    return $copy;
}

sub _lc {
    my ($value) = @_;
    $value =~ tr/A-Z/a-z/;
    return $value;
}

sub _fields {
    my ($message, $section) = @_;
    my $count_method = $section eq 'trailer' ? 'trailer_count' : 'header_count';
    my $name_method  = $section eq 'trailer' ? 'trailer_name' : 'header_name';
    my $value_method = $section eq 'trailer' ? 'trailer_value' : 'header_value';
    my $count = $message->$count_method();
    croak "$section fields are unavailable" unless defined $count;
    my @fields;
    for my $i (0 .. $count - 1) {
        push @fields, [
            _bytes("$section name", $message->$name_method($i)),
            _bytes("$section value", $message->$value_method($i)),
        ];
    }
    return \@fields;
}

sub _values {
    my ($fields, $wanted) = @_;
    my $key = _lc($wanted);
    return [ map { $_->[1] } grep { _lc($_->[0]) eq $key } @$fields ];
}

sub _connection_tokens {
    my ($fields) = @_;
    my %seen;
    for my $value (@{ _values($fields, 'Connection') }) {
        for my $member (split /,/, $value, -1) {
            $member =~ s/\A[ \t]+//;
            $member =~ s/[ \t]+\z//;
            next unless length $member;
            $seen{ _lc($member) } = 1;
        }
    }
    return \%seen;
}

sub _content_length {
    my ($fields) = @_;
    my @numbers;
    for my $value (@{ _values($fields, 'Content-Length') }) {
        for my $member (split /,/, $value, -1) {
            $member =~ s/\A[ \t]+//;
            $member =~ s/[ \t]+\z//;
            croak 'invalid Content-Length' unless $member =~ /\A[0-9]+\z/;
            push @numbers, $member;
        }
    }
    return undef unless @numbers;
    my $first = $numbers[0];
    for my $number (@numbers) {
        croak 'conflicting Content-Length fields' if $number ne $first;
    }
    return 0 + $first;
}

sub _transfer_encoding {
    my ($fields) = @_;
    my @codings;
    for my $value (@{ _values($fields, 'Transfer-Encoding') }) {
        for my $member (split /,/, $value, -1) {
            $member =~ s/\A[ \t]+//;
            $member =~ s/[ \t]+\z//;
            croak 'invalid Transfer-Encoding' unless length $member;
            my ($token, $tail) = $member =~ /\A([^; \t]+)(.*)\z/;
            croak 'invalid Transfer-Encoding' unless defined $token;
            push @codings, [ _lc($token), $tail ];
        }
    }
    return [] unless @codings;
    croak 'unsupported HTTP/1 transfer coding'
        if @codings != 1 || $codings[0][0] ne 'chunked' || length($codings[0][1]);
    return ['chunked'];
}

sub _replace_or_add {
    my ($fields, $name, $value) = @_;
    my $key = _lc($name);
    my @out;
    my $inserted = 0;
    for my $field (@$fields) {
        if (_lc($field->[0]) eq $key) {
            if (!$inserted) {
                push @out, [ $name, "$value" ];
                $inserted = 1;
            }
            next;
        }
        push @out, [ @$field ];
    }
    push @out, [ $name, "$value" ] unless $inserted;
    return \@out;
}

sub _serialize_fields {
    my ($fields) = @_;
    my $wire = '';
    for my $field (@$fields) {
        $wire .= $field->[0] . ': ' . $field->[1] . "\r\n";
    }
    return $wire;
}

sub _version {
    my ($message, $default) = @_;
    my $version = $message->version;
    $version = $default unless defined $version;
    croak 'HTTP/1 version must be 1.0 or 1.1'
        unless $version eq '1.0' || $version eq '1.1';
    return $version;
}

sub request_plan {
    my ($request, %option) = @_;
    croak 'request does not implement the Uniform HTTP request contract'
        unless ref($request) && $request->can('method') && $request->can('target')
            && $request->can('header_count') && $request->can('has_buffered_body');
    croak 'HTTP/1 cannot directly encode Uniform Extended CONNECT protocol metadata'
        if $request->can('protocol') && defined $request->protocol;

    my $stream_body = $option{stream_body} ? 1 : 0;
    my $version = _version($request, '1.1');
    my $method = _bytes('request method', $request->method);
    my $target = _bytes('request target', $request->target);
    my $fields = _fields($request, 'header');
    my $body = $request->has_buffered_body ? _bytes('request body', $request->body) : undef;
    croak 'stream_body cannot be combined with a buffered request body'
        if $stream_body && defined $body;

    my $host = _values($fields, 'Host');
    croak 'HTTP/1 request must not contain multiple Host fields' if @$host > 1;
    if (!@$host && $version eq '1.1') {
        my $authority = $request->can('authority') ? $request->authority : undef;
        croak 'HTTP/1.1 request requires Host or Uniform authority metadata'
            unless defined $authority;
        $fields = [ @$fields, [ 'Host', _bytes('request authority', $authority) ] ];
    }

    my $cl = _content_length($fields);
    my $te = _transfer_encoding($fields);
    croak 'request cannot contain both Transfer-Encoding and Content-Length'
        if @$te && defined $cl;

    my $trailers = _fields($request, 'trailer');
    my $has_trailers = @$trailers ? 1 : 0;
    my ($mode, $remaining);

    if ($has_trailers) {
        croak 'HTTP/1.0 cannot send trailer fields' if $version eq '1.0';
        croak 'trailers cannot be combined with Content-Length' if defined $cl;
        $fields = _replace_or_add($fields, 'Transfer-Encoding', 'chunked');
        $mode = 'chunked';
    } elsif (@$te) {
        croak 'HTTP/1.0 does not support chunked transfer coding' if $version eq '1.0';
        $mode = 'chunked';
    } elsif (defined $cl) {
        $mode = 'content-length';
        $remaining = $cl;
        croak 'request Content-Length does not match buffered body length'
            if defined($body) && length($body) != $cl;
    } elsif ($stream_body) {
        croak 'streaming HTTP/1.0 request body requires Content-Length'
            if $version eq '1.0';
        $fields = [ @$fields, [ 'Transfer-Encoding', 'chunked' ] ];
        $mode = 'chunked';
    } elsif (defined $body) {
        $fields = [ @$fields, [ 'Content-Length', length($body) ] ];
        $mode = 'content-length';
        $remaining = length($body);
    } else {
        $mode = 'none';
    }

    my $wire = $method . ' ' . $target . ' HTTP/' . $version . "\r\n"
        . _serialize_fields($fields) . "\r\n";

    if (defined $body) {
        $wire .= $mode eq 'chunked'
            ? chunk($body) . final_chunk($trailers)
            : $body;
        $remaining = 0 if defined $remaining;
    } elsif (!$stream_body && $mode eq 'chunked') {
        $wire .= final_chunk($trailers);
    }

    my $tokens = _connection_tokens($fields);
    my $keep_alive = $tokens->{close} ? 0
        : $version eq '1.1' ? 1
        : $tokens->{'keep-alive'} ? 1 : 0;

    return {
        wire           => $wire,
        version        => $version,
        mode           => $mode,
        remaining      => $remaining,
        stream_body    => $stream_body,
        trailers       => $trailers,
        keep_alive     => $keep_alive,
        body_finalized => $stream_body ? 0 : 1,
    };
}

sub response_receive_plan {
    my ($request, $head) = @_;
    my $fields = $head->{headers};
    my $status = $head->{status};
    my $method = $request->method;
    my $cl = _content_length($fields);
    my $te = _transfer_encoding($fields);
    croak 'response contains both Transfer-Encoding and Content-Length'
        if @$te && defined $cl;

    my $switch = ($status == 101 || ($method eq 'CONNECT' && $status >= 200 && $status < 300)) ? 1 : 0;
    my $body_forbidden = $switch || $method eq 'HEAD'
        || ($status >= 100 && $status < 200)
        || $status == 204 || $status == 205 || $status == 304;

    my $mode = 'none';
    my $remaining;
    if (!$body_forbidden) {
        if (@$te) {
            $mode = 'chunked';
        } elsif (defined $cl) {
            $mode = 'content-length';
            $remaining = $cl;
        } else {
            $mode = 'close';
        }
    }

    my $tokens = _connection_tokens($fields);
    my $keep_alive = $tokens->{close} ? 0
        : $head->{version} eq '1.1' ? 1
        : $tokens->{'keep-alive'} ? 1 : 0;
    $keep_alive = 0 if $mode eq 'close' || $switch;

    return {
        mode       => $mode,
        remaining  => $remaining,
        switch     => $switch,
        keep_alive => $keep_alive,
    };
}

sub response_plan {
    my ($request, $response, %option) = @_;
    croak 'response does not implement the Uniform HTTP response contract'
        unless ref($response) && $response->can('status')
            && $response->can('header_count') && $response->can('has_buffered_body');

    my $stream_body = $option{stream_body} ? 1 : 0;
    my $request_version = $request->version || '1.1';
    croak 'request version is not HTTP/1.0 or HTTP/1.1'
        unless $request_version eq '1.0' || $request_version eq '1.1';
    if (defined $response->version && $response->version ne $request_version) {
        croak 'response version conflicts with the HTTP/1 request version';
    }

    my $status = $response->status;
    my $reason = defined($response->reason) ? _bytes('response reason', $response->reason)
        : ($REASON{$status} || '');
    my $fields = _fields($response, 'header');
    my $trailers = _fields($response, 'trailer');
    my $body = $response->has_buffered_body ? _bytes('response body', $response->body) : undef;
    croak 'stream_body cannot be combined with a buffered response body'
        if $stream_body && defined $body;

    my $method = $request->method;
    my $switch = ($status == 101 || ($method eq 'CONNECT' && $status >= 200 && $status < 300)) ? 1 : 0;
    my $body_forbidden = $switch || ($status >= 100 && $status < 200)
        || $status == 204 || $status == 205 || $status == 304;
    my $head_only = $method eq 'HEAD' ? 1 : 0;

    croak 'protocol-switch responses cannot carry a body or trailers'
        if $switch && ((defined($body) && length($body)) || $stream_body || @$trailers);
    croak 'this response status cannot carry a body or trailers'
        if $body_forbidden && !$switch
            && ((defined($body) && length($body)) || $stream_body || @$trailers);

    my $cl = _content_length($fields);
    my $te = _transfer_encoding($fields);
    croak 'response cannot contain both Transfer-Encoding and Content-Length'
        if @$te && defined $cl;

    my ($mode, $remaining, $close_after) = ('none', undef, 0);
    if ($body_forbidden) {
        croak '1xx and 204 responses must not contain Content-Length'
            if (($status >= 100 && $status < 200) || $status == 204) && defined $cl;
        croak '205 response Content-Length must be zero'
            if $status == 205 && defined($cl) && $cl != 0;
        croak 'bodyless response must not contain Transfer-Encoding' if @$te;
    } elsif ($head_only) {
        croak 'HEAD response must not use Transfer-Encoding for a body' if @$te;
        if (!defined $cl && defined $body) {
            $fields = [ @$fields, [ 'Content-Length', length($body) ] ];
        }
    } elsif (@$trailers) {
        croak 'HTTP/1.0 cannot send trailer fields' if $request_version eq '1.0';
        croak 'trailers cannot be combined with Content-Length' if defined $cl;
        $fields = _replace_or_add($fields, 'Transfer-Encoding', 'chunked');
        $mode = 'chunked';
    } elsif (@$te) {
        croak 'HTTP/1.0 does not support chunked transfer coding' if $request_version eq '1.0';
        $mode = 'chunked';
    } elsif (defined $cl) {
        $mode = 'content-length';
        $remaining = $cl;
        croak 'response Content-Length does not match buffered body length'
            if defined($body) && length($body) != $cl;
    } elsif ($stream_body) {
        if ($request_version eq '1.1') {
            $fields = [ @$fields, [ 'Transfer-Encoding', 'chunked' ] ];
            $mode = 'chunked';
        } else {
            $mode = 'close';
            $close_after = 1;
        }
    } else {
        my $length = defined($body) ? length($body) : 0;
        $fields = [ @$fields, [ 'Content-Length', $length ] ];
        $mode = 'content-length';
        $remaining = $length;
    }

    my $request_tokens = _connection_tokens(_fields($request, 'header'));
    my $response_tokens = _connection_tokens($fields);
    my $request_keep = $request_tokens->{close} ? 0
        : $request_version eq '1.1' ? 1
        : $request_tokens->{'keep-alive'} ? 1 : 0;
    my $keep_alive = $request_keep && !$response_tokens->{close} && !$close_after && !$switch;
    if (!$keep_alive && !$switch && !$response_tokens->{close}) {
        $fields = [ @$fields, [ 'Connection', 'close' ] ];
    } elsif ($keep_alive && $request_version eq '1.0' && !$response_tokens->{'keep-alive'}) {
        $fields = [ @$fields, [ 'Connection', 'keep-alive' ] ];
    }

    my $wire = 'HTTP/' . $request_version . ' ' . sprintf('%03d', $status)
        . ' ' . $reason . "\r\n" . _serialize_fields($fields) . "\r\n";

    if (!$head_only && !$body_forbidden && defined $body) {
        $wire .= $mode eq 'chunked'
            ? chunk($body) . final_chunk($trailers)
            : $body;
        $remaining = 0 if defined $remaining;
    } elsif (!$head_only && !$body_forbidden && !$stream_body && $mode eq 'chunked') {
        $wire .= final_chunk($trailers);
    }

    return {
        wire           => $wire,
        version        => $request_version,
        mode           => $mode,
        remaining      => $remaining,
        stream_body    => $stream_body,
        trailers       => $trailers,
        keep_alive     => $keep_alive,
        close_after    => $close_after,
        switch         => $switch,
        body_finalized => $stream_body ? 0 : 1,
    };
}

sub chunk {
    my ($bytes) = @_;
    $bytes = _bytes('body chunk', $bytes);
    return '' unless length $bytes;
    return sprintf('%X', length($bytes)) . "\r\n" . $bytes . "\r\n";
}

sub final_chunk {
    my ($trailers) = @_;
    $trailers ||= [];
    my $wire = "0\r\n";
    for my $field (@$trailers) {
        my $key = _lc($field->[0]);
        croak 'framing fields are forbidden in HTTP/1 trailers'
            if $key eq 'content-length' || $key eq 'transfer-encoding'
                || $key eq 'host' || $key eq 'connection' || $key eq 'trailer';
        $wire .= $field->[0] . ': ' . $field->[1] . "\r\n";
    }
    return $wire . "\r\n";
}

1;
