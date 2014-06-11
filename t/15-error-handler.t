#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

use English '-no_match_vars';
use HTTP::Response;
use Sentry::Raven;
use Test::LWP::UserAgent;

my $ua = Test::LWP::UserAgent->new();
$ua->map_response(
    qr//,
    HTTP::Response->new(
        '200',
        undef,
        undef,
        '{ "id": "some-uuid-string" }',
    ),
);

local $ENV{SENTRY_DSN} = 'http://key:secret@somewhere.com:9000/foo/123';
my $raven = Sentry::Raven->new(ua_obj => $ua);

sub a { b() }
sub b { c() }
sub c { die "it was not meant to be" }

$raven->capture_errors(
    sub { a() },
    level => 'fatal',
);

my $request = $ua->last_http_request_sent();
my $json = $request->content();
my $event = $raven->json_obj()->decode($json);

subtest 'event' => sub {
    is($event->{level}, 'fatal');
    is($event->{culprit}, 't/15-error-handler.t');
    like($event->{message}, qr/it was not meant to be/);
};

subtest 'exception' => sub {
    like($event->{'sentry.interfaces.Exception'}->{value}, qr/it was not meant to be/);
};

subtest 'stacktrace' => sub {
    my @frames = @{ $event->{'sentry.interfaces.Stacktrace'}->{frames} };

    is(scalar(@frames), 6);

    is($frames[-1]->{function}, 'main::c');
    is($frames[-1]->{module}, 'main');
    is($frames[-1]->{filename}, 't/15-error-handler.t');
    is($frames[-1]->{lineno}, 28);
};

subtest 'dies when unable to submit event' => sub {
    my $failing_ua = Test::LWP::UserAgent->new();
    $failing_ua->map_response(
        qr//,
        HTTP::Response->new(
            '500',
        ),
    );

    eval {
        Sentry::Raven->new(ua_obj => $failing_ua)->capture_errors( sub { a() } );
    };

    my $eval_error = $EVAL_ERROR;

    like($eval_error, qr/failed to submit event to sentry service/);
    like($eval_error, qr/"level" => "error"/);
};

done_testing();
