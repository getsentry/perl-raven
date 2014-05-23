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

subtest 'request' => sub {
    my $event = $raven->_generate_event(level => 'info');
    $event = $raven->_add_request_to_event(
        $event,
        'http://google.com',
        method       => 'GET',
        data         => { foo => 'bar' },
        query_string => 'foo=bar',
        cookies      => 'foo=bar',
        headers      => { 'Content-Type' => 'text/html' },
        env          => { REMOTE_ADDR => '192.168.0.1' },
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

    my $event = $raven->_generate_event(level => 'info');
    $event = $raven->_add_stacktrace_to_event($event, $frames);

    is($event->{level}, 'info');
    is_deeply(
        $event->{'sentry.interfaces.Stacktrace'},
        { frames => $frames },
    );
};

done_testing();
