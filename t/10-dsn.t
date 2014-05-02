#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

use English '-no_match_vars';
use Sentry::Raven;

my $dsn = 'http://key:secret@somewhere.com:9000/foo/123';

is(Sentry::Raven->new(sentry_dsn => $dsn)->post_url(), 'http://somewhere.com:9000/foo/api/123/store/');

{
    local $ENV{SENTRY_DSN} = $dsn;
    is(Sentry::Raven->new()->post_url(), 'http://somewhere.com:9000/foo/api/123/store/');
}

eval { Sentry::Raven->new() };
is($EVAL_ERROR, "must pass sentry_dsn or set SENTRY_DSN envirionment variable\n");

eval { Sentry::Raven->new(sentry_dsn => 'not a uri') };
is($EVAL_ERROR, "unable to parse sentry dsn: not a uri\n");

eval { Sentry::Raven->new(sentry_dsn => 'http://missing.userinfo.com') };
is($EVAL_ERROR, "unable to parse public and secret keys from: http://missing.userinfo.com\n");

done_testing();
