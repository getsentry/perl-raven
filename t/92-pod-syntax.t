#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

SKIP: {
    skip 'Skipping release tests', 1 unless $ENV{RELEASE_TESTING};

    require Test::Pod;
    Test::Pod->import();
    all_pod_files_ok();
}

done_testing();
