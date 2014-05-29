#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

TODO: {
    local $TODO = 'unimplemented features';

    # http://sentry.readthedocs.org/en/latest/developer/client/#scrubbing-data
    ok(undef, 'supports scrubbing callbacks');

    # http://raven.readthedocs.org/en/latest/usage.html#adding-context
    ok(undef, 'supports updating default context after construction');

    ok(undef, 'mason handler');

    ok(undef, 'add LWP::Protocol::https to suggested packages');
}

done_testing();
