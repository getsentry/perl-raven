#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

use File::Slurp;
use File::Spec;
use Sentry::Raven;
use Devel::StackTrace;

local $ENV{SENTRY_DSN} = 'http://key:secret@somewhere.com:9000/foo/123';
my $raven = Sentry::Raven->new();

my $trace;
a(1,"x");

my @file_lines = read_file(File::Spec->catfile('t', '21-stacktrace-failures.t'));
chomp(@file_lines);

my $frames = [
    {
        abs_path     => File::Spec->catfile('t', '21-stacktrace-failures.t'),
        filename     => '21-stacktrace-failures.t',
        function     => undef,
        lineno       => 17,
        module       => 'main',
        vars         => undef,
        context_line => $file_lines[ 16 ],
        pre_context  => [ @file_lines[ 11 .. 15 ] ],
        post_context => [ @file_lines [ 17 .. 21 ] ],
    },
    {
        abs_path => '/bad/path/NoSuchFileEver.pm',
        filename => 'NoSuchFileEver.pm',
        function => 'main::a',
        lineno   => 127,
        module   => 'main',
        vars     => {
            '@_' => ['1','"x"'],
        },
    },
];

my $context = $raven->_construct_stacktrace_event($trace)->{'sentry.interfaces.Stacktrace'};

is_deeply(
    $context,
    { frames => $frames },
);

done_testing;

# line 127 "/bad/path/NoSuchFileEver.pm"
sub a { $trace = Devel::StackTrace->new() }
