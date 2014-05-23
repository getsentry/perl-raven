#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

SKIP: {
    skip 'Skipping release tests', 1 unless $ENV{RELEASE_TESTING};

    eval "use Test::Pod::Coverage;";
    all_pod_coverage_ok({ trustme => [qr/UUID_V4/, qr/BUILDARGS/] });
}

done_testing();
