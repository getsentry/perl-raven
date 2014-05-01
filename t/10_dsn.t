use strict;
use warnings;

use Test::More tests => 20;

use English '-no_match_vars';

BEGIN { use_ok( 'Sentry::Raven' ); }

my $dsn = 'http://key:secret@somewhere.com:9000/foo/123';

test_dsn(Sentry::Raven->new(sentry_dsn => $dsn));

{
    local $ENV{SENTRY_DSN} = $dsn;
    test_dsn(Sentry::Raven->new());
}

eval { Sentry::Raven->new() };
is($EVAL_ERROR, "must pass sentry_dsn or set SENTRY_DSN envirionment variable\n");

eval { Sentry::Raven->new(sentry_dsn => 'not a uri') };
is($EVAL_ERROR, "unable to parse sentry dsn: not a uri\n");

eval { Sentry::Raven->new(sentry_dsn => 'http://missing.userinfo.com') };
is($EVAL_ERROR, "unable to parse public and secret keys from: http://missing.userinfo.com\n");

exit;

sub test_dsn {
    my $raven = shift;

    is($raven->scheme(), 'http');
    is($raven->host(), 'somewhere.com');
    is($raven->port(), 9000);
    is($raven->path(), '/foo'),
    is($raven->public_key(), 'key');
    is($raven->secret_key(), 'secret');
    is($raven->project_id(), 123);

    is($raven->_post_url(), 'http://somewhere.com:9000/foo/api/123/store/');
}
