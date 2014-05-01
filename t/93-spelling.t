use strict;
use warnings;

use Test::More;

SKIP: {
    skip 'Skipping release tests', 1 unless $ENV{RELEASE_TESTING};

    eval "use Test::Spellunker;";
    all_pod_files_spelling_ok();
}

done_testing();
