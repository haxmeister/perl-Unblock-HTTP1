use strict;
use warnings;
use Test::More;
use Scalar::Util qw(dualvar refaddr);
use Config;
use Uniform::HTTP::Response;
use Unblock::HTTP1::Server;
use Unblock::HTTP1::_Native;

sub construct {
    my ($fields) = @_;
    return Unblock::HTTP1::_Native::_response_from_fields($fields)
        || Uniform::HTTP::Response->new(%$fields);
}

sub snapshot {
    my ($r) = @_;
    return [ref($r), (map { $r->$_() } qw(status reason version body
        has_buffered_body is_complete is_mutable initial_is_mutable
        body_is_mutable trailers_are_mutable)),
        [map { [$r->header_name($_), $r->header_value($_)] } 0 .. $r->header_count - 1],
        [map { [$r->trailer_name($_), $r->trailer_value($_)] } 0 .. $r->trailer_count - 1]];
}

my @ordinary = (
    {status => 200},
    {status => '000200', body => ''},
    {status => 599, body => "a\0b\xff", reason => "custom\t\xff", version => '01.001'},
    {status => 103, reason => undef, version => undef},
    {status => 200, headers => [['Set-Cookie', 'a=1'], ['sEt-CoOkIe', 'b=2']],
        trailers => [['X-End', "\t ok \xff"]], body => 123},
    {status => 204, headers => [], trailers => []},
);
for my $fields (@ordinary) {
    my $native = Unblock::HTTP1::_Native::_response_from_fields($fields);
    ok($native, 'ordinary fields use the native constructor');
    is_deeply(snapshot($native), snapshot(Uniform::HTTP::Response->new(%$fields)),
        'canonical public state matches Uniform constructor');
}

my $utf8 = "\xff";
utf8::upgrade($utf8);
my @fallback = (
    {status => 200, body => $utf8},
    {status => 200, headers => [['X-Byte', $utf8]]},
    {status => dualvar(201, '200')},
    {status => 200, headers => [map { ['X-N', "$_"] } 1 .. 33]},
    {status => 200, trailers => [map { ['X-N', "$_"] } 1 .. 33]},
);
for my $fields (@fallback) {
    ok(!defined Unblock::HTTP1::_Native::_response_from_fields($fields),
        'unusual input requests the existing constructor');
    is_deeply(snapshot(construct($fields)), snapshot(Uniform::HTTP::Response->new(%$fields)),
        'fallback retains Uniform semantics');
}

my @invalid = (
    {}, {status => 200, typo => 1},
    map { {status => $_} } (undef, [], '', 99, 600, -200, '2e2', '200 ', '200.0', '9' x 100),
);
push @invalid,
    (map { {status => 200, body => $_} } undef, [], "\x{100}"),
    (map { {status => 200, version => $_} } '', '.1', '1.', '1.2.3', "1\n", []),
    (map { {status => 200, headers => $_} } undef, {}, [[]], [['X']], [['X','y','z']], [['','y']], [['X Y','y']], [['X',undef]]),
    {status => 200, trailers => [['X', "a\rb"]]},
    {status => 200, reason => "a\nb"};
for my $fields (@invalid) {
    ok(!defined Unblock::HTTP1::_Native::_response_from_fields($fields),
        'invalid fields never enter the trusted Uniform constructor');
    my ($ordinary_error, $fast_error);
    eval { Uniform::HTTP::Response->new(%$fields) }; $ordinary_error = $@;
    eval { construct($fields) }; $fast_error = $@;
    s/ at .*//s for $ordinary_error, $fast_error;
    ok(length($ordinary_error), 'Uniform rejects invalid fields');
    is($fast_error, $ordinary_error, 'fallback preserves the validation error');
}

subtest 'every byte in fields and reason has matching validation' => sub {
    for my $slot (qw(name value reason)) {
        for my $byte (0 .. 255) {
            my %fields = (status => 200);
            if ($slot eq 'reason') { $fields{reason} = chr($byte) }
            else { $fields{headers} = [[$slot eq 'name' ? chr($byte) : 'X',
                $slot eq 'value' ? chr($byte) : 'ok']] }
            my $expected = eval { Uniform::HTTP::Response->new(%fields) };
            my $actual = eval { construct(\%fields) };
            is(!!$actual, !!$expected, "$slot byte $byte accepted identically");
            is_deeply(snapshot($actual), snapshot($expected), 'same canonical state') if $expected;
        }
    }
};

{
    package CountingScalar;
    sub TIESCALAR { bless { value => $_[1], fetches => 0 }, $_[0] }
    sub FETCH { ++$_[0]{fetches}; $_[0]{value} }
    package CountingArray;
    sub TIEARRAY { bless { fetches => 0 }, $_[0] }
    sub FETCHSIZE { ++$_[0]{fetches}; 1 }
    sub FETCH { ++$_[0]{fetches}; ['X', 'yes'] }
}
my %magic = (status => 200, headers => [['X', 'yes']]);
my $scalar = tie $magic{headers}[0][1], 'CountingScalar', 'yes';
ok(!defined Unblock::HTTP1::_Native::_response_from_fields(\%magic), 'tied field falls back');
is($scalar->{fetches}, 0, 'native probe never reads tied scalar');
is(construct(\%magic)->header('X'), 'yes', 'ordinary path handles tied scalar');
my @tied;
my $array = tie @tied, 'CountingArray';
ok(!defined Unblock::HTTP1::_Native::_response_from_fields({status => 200, headers => \@tied}),
    'tied array falls back');
is($array->{fetches}, 0, 'native probe never reads tied array');
is(construct({status => 200, headers => \@tied})->header('X'), 'yes', 'tied array still supported');

my $body = 'original';
my $headers = [['X', 'original']];
my $first = construct({status => 200, body => $body, headers => $headers});
my $second = construct({status => 200, body => $body, headers => $headers});
$body = 'changed';
$headers->[0][1] = 'changed';
$first->header('X', 'first');
$first->body('first');
is($second->body, 'original', 'fresh canonical bodies own their bytes');
is($second->header('X'), 'original', 'fresh canonical headers are independent');
isnt(refaddr($first), refaddr($second), 'responses are never cached');
$second->freeze;
ok(!eval { $second->body('changed'); 1 }, 'normal Uniform immutability applies');

subtest 'real transaction retains canonical response and ordinary output rules' => sub {
    my @tx;
    my $server = Unblock::HTTP1::Server->new(on_request => sub {
        my ($tx) = @_;
        push @tx, $tx;
        $tx->respond(status => 200, headers => [['X-Test', 'yes']], body => 'ok');
    });
    $server->input("GET / HTTP/1.1\r\nHost: test\r\n\r\n" x 2);
    my $output = $server->output;
    is(scalar @tx, 2, 'both pipelined transactions delivered');
    for my $tx (@tx) {
        isa_ok($tx->response, 'Uniform::HTTP::Response');
        is($tx->response->body, 'ok', 'retained response body remains accessible');
        ok($tx->is_complete, 'normal transaction completion');
    }
    is(scalar(() = $output =~ /Content-Length: 2\r\n/g), 2, 'both responses framed');
    isnt(refaddr($tx[0]->response), refaddr($tx[1]->response), 'separate responses per transaction');
};

SKIP: {
    skip 'Perl without ithreads', 1 unless $Config{useithreads};
    require threads;
    is(threads->create(sub { construct({status => 200, body => 'child'})->body })->join,
        'child', 'canonical API initializes in cloned interpreter');
}
done_testing;
