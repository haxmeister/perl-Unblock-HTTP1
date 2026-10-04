use strict;
use warnings;
use ExtUtils::MakeMaker;

my %prereq = (
    'Carp'          => 0,
    'Config'        => 0,
    'Scalar::Util'  => 0,
    'Uniform::HTTP' => '0.04',
    'XSLoader'      => 0,
);

my %makefile = (
    NAME             => 'Unblock::HTTP1',
    VERSION_FROM     => 'lib/Unblock/HTTP1.pm',
    ABSTRACT_FROM    => 'lib/Unblock/HTTP1.pm',
    AUTHOR           => 'Joshua S. Day <HAX@cpan.org>',
    LICENSE          => 'mit',
    MIN_PERL_VERSION => '5.016',
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    PREREQ_PM => \%prereq,
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

if (eval { ExtUtils::MakeMaker->VERSION('6.64'); 1 }) {
    $makefile{TEST_REQUIRES} = {
        'Test::More' => 0,
    };
} else {
    # Older MakeMaker does not understand TEST_REQUIRES. Keep installation
    # compatible by falling back to the traditional runtime prerequisite.
    $makefile{PREREQ_PM}{'Test::More'} = 0;
}

WriteMakefile(%makefile);
