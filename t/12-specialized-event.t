#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

use Sentry::Raven;

local $ENV{SENTRY_DSN} = 'http://key:secret@somewhere.com:9000/foo/123';
my $raven = Sentry::Raven->new();

subtest 'message' => sub {
    my $event = $raven->_generate_event(message => 'mymessage', level => 'info');

    is($event->{message}, 'mymessage');
    is($event->{level}, 'info');
};

subtest 'exception' => sub {
    my $event = $raven->_generate_event(level => 'info');
    $event = $raven->_add_exception_to_event($event, 'OperationFailedException', 'Operation completed successfully');

    is($event->{level}, 'info');
    is_deeply(
        $event->{'sentry.interfaces.Exception'},
        {
            type    => 'OperationFailedException',
            value   => 'Operation completed successfully',
        },
    );
};

done_testing();
