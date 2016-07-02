#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

use Sentry::Raven;
use Sys::Hostname;
use UUID::Tiny ':std';

local $ENV{SENTRY_DSN} = 'http://key:secret@somewhere.com:9000/foo/123';
my $raven = Sentry::Raven->new();

subtest 'defaults' => sub {

    is($raven->encoding, 'gzip');
    is($raven->encoding('base64'), 'base64');
    is($raven->encoding, 'base64');

    my $event = $raven->_construct_event();

    is($event->{level}, 'error');
    is($event->{logger}, 'root');
    is($event->{platform}, 'perl');
    is($event->{culprit}, undef);
    is($event->{message}, undef);
    is($event->{release}, undef);

    is_deeply($event->{extra}, {});
    is_deeply($event->{tags}, {});
    is_deeply($event->{fingerprint}, ['{{ default }}']);

    ok(string_to_uuid($event->{event_id}));
    like($event->{timestamp}, qr/^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d$/);
    is($event->{server_name}, hostname());
};

subtest 'modifying defaults' => sub {
    my $raven = Sentry::Raven->new(
        level       => 'warning',
        logger      => 'mylogger',
        platform    => 'myplatform',
        culprit     => 'myculprit',
        message     => 'mymessage',
        encoding    => 'base64',
        release     => 'ec899ea',

        extra       => {
            key1    => 'value1',
            key2    => 'value2',
        },
        tags        => {
            tag1    => 'value1',
            tag2    => 'value2',
        },
        fingerprint => [
            'new',
            'fingerprint',
        ],

        event_id    => 'myeventid',
        timestamp   => 'mytimestamp',
        server_name => 'myservername',
    );

    is($raven->encoding, 'base64');

    my $event = $raven->_construct_event();

    is($event->{level}, 'warning');
    is($event->{logger}, 'mylogger');
    is($event->{platform}, 'myplatform');
    is($event->{culprit}, 'myculprit');
    is($event->{message}, 'mymessage');
    is($event->{release}, 'ec899ea');

    is_deeply(
        $event->{extra},
        {
            key1    => 'value1',
            key2    => 'value2',
        },
    );

    is_deeply(
        $event->{tags},
        {
            tag1    => 'value1',
            tag2    => 'value2',
        },
    );

    is_deeply(
        $event->{fingerprint},
        [
            'new',
            'fingerprint',
        ],
    );

    is($event->{event_id}, 'myeventid');
    is($event->{timestamp}, 'mytimestamp');
    is($event->{server_name}, 'myservername');


    $raven->add_context(
        level  => 'error',
        logger => 'yourlogger',
    );

    $event = $raven->_construct_event();

    is($event->{level}, 'error');
    is($event->{logger}, 'yourlogger');


    my %context = $raven->get_context();

    is($context{level}, 'error');
    is($context{logger}, 'yourlogger');


    $raven->clear_context();

    %context = $raven->get_context();

    is($context{level}, undef);
    is($context{logger}, undef);


    $raven->add_context(tags => { a => 1, b => 2 });
    $raven->merge_tags(a => 10, c => 30);

    is_deeply(
        $raven->context()->{tags},
        {
            a => 10,
            b => 2,
            c => 30,
        },
    );


    $raven->add_context(extra => { a => 1, b => 2 });
    $raven->merge_extra(a => 10, c => 30);

    is_deeply(
        $raven->context()->{extra},
        {
            a => 10,
            b => 2,
            c => 30,
        },
    );
};

subtest 'overriding defaults' => sub {
    my $event = $raven->_construct_event(
        level       => 'warning',
        logger      => 'mylogger',
        platform    => 'myplatform',
        culprit     => 'myculprit',
        message     => 'mymessage',

        extra       => {
            key1    => 'value1',
            key2    => 'value2',
        },
        tags        => {
            tag1    => 'value1',
            tag2    => 'value2',
        },
        fingerprint => [
            'new',
            'fingerprint',
        ],

        event_id    => 'myeventid',
        timestamp   => 'mytimestamp',
        server_name => 'myservername',
    );

    is($event->{level}, 'warning');
    is($event->{logger}, 'mylogger');
    is($event->{platform}, 'myplatform');
    is($event->{culprit}, 'myculprit');
    is($event->{message}, 'mymessage');

    is_deeply(
        $event->{extra},
        {
            key1    => 'value1',
            key2    => 'value2',
        },
    );

    is_deeply(
        $event->{tags},
        {
            tag1    => 'value1',
            tag2    => 'value2',
        },
    );

    is_deeply(
        $event->{fingerprint},
        [
            'new',
            'fingerprint',
        ],
    );

    is($event->{event_id}, 'myeventid');
    is($event->{timestamp}, 'mytimestamp');
    is($event->{server_name}, 'myservername');
};

subtest 'overriding modified defaults' => sub {
    my $raven = Sentry::Raven->new(
        level       => 'warning',
        extra       => {
            key1    => 'value1',
        },
        tags        => {
            tag1    => 'value1',
        },
        fingerprint => [
            'value1',
        ],
    );

    my $event = $raven->_construct_event(
        level       => 'fatal',

        extra       => {
            key2    => 'value2',
        },
        tags        => {
            tag2    => 'value2',
        },
        fingerprint => [
            'value2',
        ],
    );

    is($event->{level}, 'fatal');

    is_deeply(
        $event->{extra},
        {
            key1    => 'value1',
            key2    => 'value2',
        },
    );

    is_deeply(
        $event->{tags},
        {
            tag1    => 'value1',
            tag2    => 'value2',
        },
    );

    is_deeply(
        $event->{fingerprint},
        [
            'value2',
        ],
    );
};

subtest 'invalid context' => sub {
    my $warn_message;
    local $SIG{__WARN__} = sub { $warn_message = $_[0] };

    my $event = $raven->_construct_event(
        level => 'not-a-level',
    );

    is($event->{level}, 'error');
    is($warn_message, "unknown level: not-a-level\n");
};

done_testing();
