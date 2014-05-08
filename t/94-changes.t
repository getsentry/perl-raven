#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

SKIP: {
    skip 'Skipping release tests', 1 unless $ENV{RELEASE_TESTING};

    eval "use Test::CPAN::Changes::ReallyStrict";
    changes_ok();
}

done_testing();
