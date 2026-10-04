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


sub _trim {
    my ($value) = @_;
    $value =~ s/\A[ \t]+//;
    $value =~ s/[ \t]+\z//;
    return $value;
}

sub _authority_form {
    my ($target) = @_;
    $target = _bytes('CONNECT target', $target);

    my ($host, $port);
    if ($target =~ /\A(\[[^\]\s]+\]):([0-9]+)\z/) {
        ($host, $port) = ($1, $2);
    } elsif ($target =~ /\A([^:\s\/?#@]+):([0-9]+)\z/) {
        ($host, $port) = ($1, $2);
    } else {
        croak 'CONNECT target must be an authority-form host:port';
    }

    croak 'CONNECT target port must be between 1 and 65535'
        if $port < 1 || $port > 65_535;
    return "$host:$port";
}

sub _upgrade_tokens {
    my ($where, $fields) = @_;
    my @token;
    for my $value (@{ _values($fields, 'Upgrade') }) {
        for my $member (split /,/, $value, -1) {
            $member = _trim($member);
            croak "invalid $where Upgrade field value"
                if $member eq ''
                || $member !~ /\A[!#\$%&'*+\-.^_\x60|~0-9A-Za-z]+(?:\/[!#\$%&'*+\-.^_\x60|~0-9A-Za-z]+)?\z/;
            push @token, _lc($member);
        }
    }
    return \@token;
}

sub _validate_connect_request {
    my ($request, $fields, $version, $body, $stream_body, $trailers) = @_;
    return unless uc($request->method) eq 'CONNECT';

    croak 'CONNECT requires HTTP/1.1' unless $version eq '1.1';
    croak 'CONNECT cannot use a streaming request body' if $stream_body;
    croak 'CONNECT request must not contain a buffered body' if defined $body;
    croak 'CONNECT request must not contain trailers' if $trailers && @$trailers;
    croak 'CONNECT request must not contain Content-Length'
        if @{ _values($fields, 'Content-Length') };
    croak 'CONNECT request must not contain Transfer-Encoding'
        if @{ _values($fields, 'Transfer-Encoding') };

    my $authority = _authority_form($request->target);
    my $host = _values($fields, 'Host');
    croak 'CONNECT requires exactly one Host field' unless @$host == 1;
    croak 'CONNECT Host must match the authority-form request target'
        if _lc(_trim($host->[0])) ne _lc($authority);
    return;
}

sub _validate_upgrade_request {
    my ($request, $fields, $version) = @_;
    croak 'HTTP/1 Upgrade requires HTTP/1.1' unless $version eq '1.1';

    my $connection = _connection_tokens($fields);
    croak 'HTTP/1 Upgrade request requires Connection: Upgrade'
        unless $connection->{upgrade};
    croak 'HTTP/1 Upgrade request cannot combine Connection: close with Upgrade'
        if $connection->{close};

    my $offered = _upgrade_tokens('request', $fields);
    croak 'HTTP/1 Upgrade request requires an Upgrade field' unless @$offered;

    my $cl = _content_length($fields);
    croak 'HTTP/1 Upgrade request body must be empty'
        if defined($cl) && $cl != 0;
    croak 'HTTP/1 Upgrade request cannot use Transfer-Encoding'
        if @{ _values($fields, 'Transfer-Encoding') };
    croak 'HTTP/1 Upgrade request body must be empty'
        if $request->has_buffered_body
            && defined($request->body) && length($request->body);
    return $offered;
}

sub _validate_upgrade_response {
    my ($request, $request_fields, $response_fields, $response_version) = @_;
    croak 'HTTP/1 Upgrade response must use HTTP/1.1'
        unless $response_version eq '1.1';

    my $offered = _validate_upgrade_request(
        $request, $request_fields, $request->version || '1.1',
    );

    croak 'HTTP/1 Upgrade response cannot contain Content-Length'
        if @{ _values($response_fields, 'Content-Length') };
    croak 'HTTP/1 Upgrade response cannot contain Transfer-Encoding'
        if @{ _values($response_fields, 'Transfer-Encoding') };

    my $connection = _connection_tokens($response_fields);
    croak 'HTTP/1 Upgrade response requires Connection: Upgrade'
        unless $connection->{upgrade};
    croak 'HTTP/1 Upgrade response cannot combine Connection: close with Upgrade'
        if $connection->{close};

    my $selected = _upgrade_tokens('response', $response_fields);
    croak 'HTTP/1 Upgrade response must select a protocol' unless @$selected;
    my %offered = map { $_ => 1 } @$offered;
    for my $protocol (@$selected) {
        croak "HTTP/1 Upgrade response selected protocol not offered by request: $protocol"
            unless $offered{$protocol};
    }
    return;
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

    _validate_connect_request(
        $request, $fields, $version, $body, $stream_body, $trailers,
    );

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

    if (uc($method) eq 'CONNECT' && $status >= 200 && $status < 300) {
        croak 'HTTP/1 CONNECT successful response must use HTTP/1.1'
            unless $head->{version} eq '1.1';
        return {
            mode       => 'none',
            remaining  => undef,
            switch     => 1,
            keep_alive => 0,
        };
    }

    if ($status == 101) {
        _validate_upgrade_response(
            $request,
            _fields($request, 'header'),
            $fields,
            $head->{version},
        );
        return {
            mode       => 'none',
            remaining  => undef,
            switch     => 1,
            keep_alive => 0,
        };
    }

    my $tokens = _connection_tokens($fields);
    my $keep_alive = $tokens->{close} ? 0
        : $head->{version} eq '1.1' ? 1
        : $tokens->{'keep-alive'} ? 1 : 0;

    # HEAD and 304 never carry HTTP content. Content-Length and
    # Transfer-Encoding, when present, describe the corresponding selected
    # representation rather than framing bytes on this message.
    if (uc($method) eq 'HEAD' || $status == 304) {
        return {
            mode       => 'none',
            remaining  => undef,
            switch     => 0,
            keep_alive => $keep_alive,
        };
    }

    my $cl = _content_length($fields);
    my $te = _transfer_encoding($fields);
    croak 'response contains both Transfer-Encoding and Content-Length'
        if @$te && defined $cl;

    my $body_forbidden = ($status >= 100 && $status < 200)
        || $status == 204 || $status == 205;

    croak '1xx and 204 responses must not contain Content-Length'
        if (($status >= 100 && $status < 200) || $status == 204) && defined $cl;
    croak '205 response Content-Length must be zero'
        if $status == 205 && defined($cl) && $cl != 0;
    croak 'bodyless response must not contain Transfer-Encoding'
        if $body_forbidden && @$te;

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

    $keep_alive = 0 if $mode eq 'close';

    return {
        mode       => $mode,
        remaining  => $remaining,
        switch     => 0,
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
    my $connect_switch = uc($method) eq 'CONNECT'
        && $status >= 200 && $status < 300 ? 1 : 0;
    my $upgrade_switch = $status == 101 ? 1 : 0;
    my $switch = $connect_switch || $upgrade_switch ? 1 : 0;
    my $body_forbidden = $switch || ($status >= 100 && $status < 200)
        || $status == 204 || $status == 205 || $status == 304;
    my $head_only = $method eq 'HEAD' ? 1 : 0;

    if ($connect_switch) {
        _validate_connect_request(
            $request,
            _fields($request, 'header'),
            $request_version,
            undef,
            0,
            [],
        );
        croak 'successful CONNECT response must not contain a buffered body'
            if defined $body;
        croak 'successful CONNECT response cannot stream a body' if $stream_body;
        croak 'successful CONNECT response must not contain trailers' if @$trailers;
    }

    croak 'protocol-switch responses cannot carry a body or trailers'
        if $upgrade_switch && (defined($body) || $stream_body || @$trailers);
    croak 'this response status cannot carry a body or trailers'
        if $body_forbidden && !$switch
            && ((defined($body) && length($body)) || $stream_body || @$trailers);

    my $cl = _content_length($fields);
    my $metadata_only_framing = $head_only || $status == 304 ? 1 : 0;
    my $raw_te = _values($fields, 'Transfer-Encoding');
    my $te = $metadata_only_framing
        ? (@$raw_te ? [ 'metadata-only' ] : [])
        : _transfer_encoding($fields);
    croak 'response cannot contain both Transfer-Encoding and Content-Length'
        if !$connect_switch && @$te && defined $cl;

    if ($connect_switch) {
        croak 'successful CONNECT response must not contain Content-Length'
            if defined $cl;
        croak 'successful CONNECT response must not contain Transfer-Encoding'
            if @$te;
        my $connection = _connection_tokens($fields);
        croak 'successful CONNECT response cannot request Connection: close'
            if $connection->{close};
    }

    if ($upgrade_switch) {
        my $response_connection = _connection_tokens($fields);
        if (!$response_connection->{upgrade}
            && !@{ _values($fields, 'Connection') }) {
            $fields = [ @$fields, [ 'Connection', 'Upgrade' ] ];
        }
        _validate_upgrade_response(
            $request,
            _fields($request, 'header'),
            $fields,
            $request_version,
        );
    }

    my ($mode, $remaining, $close_after) = ('none', undef, 0);
    if ($body_forbidden) {
        croak '1xx and 204 responses must not contain Content-Length'
            if (($status >= 100 && $status < 200) || $status == 204) && defined $cl;
        croak '205 response Content-Length must be zero'
            if $status == 205 && defined($cl) && $cl != 0;
        croak 'bodyless response must not contain Transfer-Encoding'
            if $status != 304 && @$te;
        croak 'HTTP/1.0 cannot send Transfer-Encoding metadata'
            if $status == 304 && @$te && $request_version eq '1.0';
    } elsif ($head_only) {
        croak 'HEAD response cannot stream a body' if $stream_body;
        croak 'HEAD response cannot carry trailer fields' if @$trailers;
        croak 'HTTP/1.0 cannot send Transfer-Encoding metadata'
            if @$te && $request_version eq '1.0';
        if (!defined $cl && !@$te && defined $body) {
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
