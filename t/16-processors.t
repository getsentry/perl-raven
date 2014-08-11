#!/usr/bin/env perl -T

use strict;
use warnings;

use Test::More;

use Sentry::Raven;
use Sentry::Raven::Processor::RemoveStackVariables;
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
my $raven = Sentry::Raven->new(
    ua_obj   => $ua,
    encoding => 'text',
);

subtest 'processor accessors' => sub {
    $raven->add_processors('Sentry::Raven::Processor::P1', 'Sentry::Raven::Processor::P2');

    is_deeply(
        $raven->processors(),
        ['Sentry::Raven::Processor::P1', 'Sentry::Raven::Processor::P2'],
    );

    $raven->clear_processors();

    is_deeply($raven->processors(), []);
};

subtest 'processes events' => sub {
    $raven->clear_processors();
    $raven->add_processors('ReverseMessage');
    $raven->capture_message('HELO');

    my $event = $raven->json_obj()->decode($ua->last_http_request_sent()->content());
    is($event->{message}, 'OLEH');
};


subtest 'remove stack variables' => sub {
    $raven->clear_processors();
    $raven->add_processors('Sentry::Raven::Processor::RemoveStackVariables');

    my $frames = [
        {
            filename     => 'filename1',
            lineno       => 10,
            vars         => { 1 => 10, 2 => 20 },
        },
        {
            filename     => 'filename2',
            lineno       => 20,
            vars         => { 1 => 100, 2 => 200 },
        },
    ];

    $raven->capture_stacktrace($frames);

    delete($frames->[$_]->{vars}) for 0..1;

    my $event = $raven->json_obj()->decode($ua->last_http_request_sent()->content());
    is_deeply($event->{'sentry.interfaces.Stacktrace'}->{frames}, $frames);
};

done_testing();

package ReverseMessage;

use strict;
use warnings;

sub process {
    my ($class, $event) = @_;
    $event->{message} = reverse($event->{message});
    return $event;
};
