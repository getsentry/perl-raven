#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

SKIP: {
    skip 'Skipping release tests', 1 unless $ENV{RELEASE_TESTING};

    require Test::Perl::Critic;

    Test::Perl::Critic->import(
        -verbose    => 10,
        -severity   => 'gentle',
        -force      => 0,
    );

    all_critic_ok();
}

done_testing() unless $ENV{RELEASE_TESTING};
