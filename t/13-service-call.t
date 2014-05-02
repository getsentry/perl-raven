#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

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

my $event_id = $raven->capture_message('HELO');
my $request = $ua->last_http_request_sent();


is(
    $ua->last_http_request_sent()->method(),
    'POST',
);

is(
    $event_id,
    'some-uuid-string',
);

like(
    $request->header('x-sentry-auth'),
    qr{^Sentry sentry_client=raven-perl/[\d.]+, sentry_key=key, sentry_secret=secret, sentry_timestamp=\d+, sentry_version=\d+$},
);

is($ua->last_useragent()->timeout(), 5);

$raven = Sentry::Raven->new(ua_obj => $ua, timeout => 10);
$raven->capture_message('HELO');

is($ua->last_useragent()->timeout(), 10);

done_testing();
