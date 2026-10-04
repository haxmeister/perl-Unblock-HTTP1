use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Unblock::HTTP1',
    VERSION_FROM     => 'lib/Unblock/HTTP1.pm',
    ABSTRACT_FROM    => 'lib/Unblock/HTTP1.pm',
    AUTHOR           => 'Joshua S. Day <HAX@cpan.org>',
    LICENSE          => 'mit',
    MIN_PERL_VERSION => '5.016',
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    PREREQ_PM => {
        'Carp'          => 0,
        'Scalar::Util'  => 0,
        'Uniform::HTTP' => '0.04',
        'XSLoader'      => 0,
    },
    TEST_REQUIRES => {
        'Test::More' => 0,
    },
    XS => { 'HTTP1.xs' => 'HTTP1.c' },
    clean => { FILES => 'HTTP1.c' },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            homepage => 'https://github.com/haxmeister/perl-Unblock-HTTP1',
            repository => {
                type => 'git',
                url  => 'https://github.com/haxmeister/perl-Unblock-HTTP1.git',
                web  => 'https://github.com/haxmeister/perl-Unblock-HTTP1',
            },
            bugtracker => {
                web => 'https://github.com/haxmeister/perl-Unblock-HTTP1/issues',
            },
        },
    },
);
