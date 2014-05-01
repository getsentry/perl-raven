use strict;
use warnings;

use Test::More tests => 5;

BEGIN { use_ok( 'Sentry::Raven' ); }

local $ENV{SENTRY_DSN} = 'http://key:secret@somewhere.com:9000/foo/123';
my $raven = Sentry::Raven->new();

my $event = $raven->_generate_message_event('mymessage', level => 'mylevel');

is($event->{message}, 'mymessage');
is($event->{level}, 'mylevel');

$event = $raven->_generate_exception_event('OperationFailedException', 'Operation compelted successfully', level => 'mylevel');

is($event->{level}, 'mylevel');
is_deeply(
    $event->{'sentry.interfaces.Exception'},
    {
        type    => 'OperationFailedException',
        value   => 'Operation compelted successfully',
    },
);
