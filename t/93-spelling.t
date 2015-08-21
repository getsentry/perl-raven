#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

SKIP: {
    skip 'Skipping release tests', 1 unless $ENV{RELEASE_TESTING};

    require Test::Spellunker;
    Test::Spellunker->import();
    all_pod_files_spelling_ok();
}

done_testing();
