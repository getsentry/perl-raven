use strict;
use warnings;

package FailingRaven;
use Moose;
extends 'Sentry::Raven';

sub json_obj { die "something is super wrong" }


package Main;

use Test::More;

use Sentry::Raven;

local $ENV{SENTRY_DSN} = 'http://key:secret@somewhere.com:9000/foo/123';
my $failing_raven = FailingRaven->new();

my $warn_message;
local $SIG{__WARN__} = sub { $warn_message = $_[0] };

is($failing_raven->_post_event("{ 'foo': 'bar' }"), undef);
like($warn_message, qr/something is super wrong/);

done_testing();
