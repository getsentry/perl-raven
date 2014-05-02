#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

TODO: {
    local $TODO = 'unimplemented features';

    ok(undef, 'new() accepts the same arguments as capture_* and uses them as defaults');

    # http://sentry.readthedocs.org/en/latest/developer/client/#scrubbing-data
    ok(undef, 'supports scrubbing callbacks');

    # http://sentry.readthedocs.org/en/latest/developer/interfaces/
    ok(undef, 'supports request interface');
    ok(undef, 'supports user interface');
    ok(undef, 'supports stacktrace interface');
    ok(undef, 'supports template interface');
}

done_testing();
