#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

TODO: {
    local $TODO = 'unimplemented features';

    # http://sentry.readthedocs.org/en/latest/developer/client/#scrubbing-data
    ok(undef, 'supports scrubbing callbacks');

    ok(undef, 'figure out why the =over lists are not indented (and look like junk on search.cpan)');
}

done_testing();
