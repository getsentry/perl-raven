#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

use Sentry::Raven;

local $ENV{SENTRY_DSN} = 'http://key:secret@somewhere.com:9000/foo/123';
my $raven = Sentry::Raven->new();

subtest 'message' => sub {
    my $event = $raven->_construct_message_event('mymessage', level => 'info');

    is($event->{message}, 'mymessage');
    is($event->{level}, 'info');
};

subtest 'exception' => sub {
    my $event = $raven->_construct_exception_event('OperationFailedException', 'Operation completed successfully', level => 'info');

    is($event->{level}, 'info');
    is_deeply(
        $event->{'sentry.interfaces.Exception'},
        {
            type    => 'OperationFailedException',
            value   => 'Operation completed successfully',
        },
    );
};

subtest 'request' => sub {
    my $event = $raven->_construct_request_event(
        'http://google.com',
        method       => 'GET',
        data         => { foo => 'bar' },
        query_string => 'foo=bar',
        cookies      => 'foo=bar',
        headers      => { 'Content-Type' => 'text/html' },
        env          => { REMOTE_ADDR => '192.168.0.1' },
        level        => 'info',
    );

    is($event->{level}, 'info');
    is_deeply(
        $event->{'sentry.interfaces.Http'},
        {
            url          => 'http://google.com',
            method       => 'GET',
            data         => { foo => 'bar' },
            query_string => 'foo=bar',
            cookies      => 'foo=bar',
            headers      => { 'Content-Type' => 'text/html' },
            env          => { REMOTE_ADDR => '192.168.0.1' },
        },
    );
};

subtest 'stacktrace' => sub {
    my $frames = [
        {
            filename     => 'filename1',
            function     => 'function1',
            module       => 'module1',
            lineno       => 10,
            colno        => 20,
            abs_path     => '/tmp/filename1',
            context_line => 'my $foo = "bar";',
            pre_context  => [ 'sub function1 {' ],
            post_context => [ 'print $foo' ],
            in_app       => 1,
            vars         => { foo => 'bar' },
        },
        {
            filename => 'my/file2.pl',
        },
    ];

    my $event = $raven->_construct_stacktrace_event($frames, level => 'info');

    is($event->{level}, 'info');
    is_deeply(
        $event->{'sentry.interfaces.Stacktrace'},
        { frames => $frames },
    );
};

subtest 'user' => sub {
    my $event = $raven->_construct_user_event( id => 'myid', username => 'myusername', email => 'my@email.com', level => 'info');

    is($event->{level}, 'info');
    is_deeply(
        $event->{'sentry.interfaces.User'},
        {
            id       => 'myid',
            username => 'myusername',
            email    => 'my@email.com',
        },
    );
};

done_testing();
