use strict;
use warnings;

package FailingRaven;
use Moose;
extends 'Sentry::Raven';

sub json_obj { die }


package Main;

use Test::More;

use Sentry::Raven;

local $ENV{SENTRY_DSN} = 'http://key:secret@somewhere.com:9000/foo/123';
my $failing_raven = FailingRaven->new();

is($failing_raven->_post_event("{ 'foo': 'bar' }"), undef);

done_testing();
