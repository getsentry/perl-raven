package Sentry::Raven;

use 5.008;
use strict;
use Moo;
use MooX::Types::MooseLike::Base qw/ ArrayRef HashRef Int Str /;

our $VERSION = '0.02';

use DateTime;
use English '-no_match_vars';
use HTTP::Status ':constants';
use JSON::XS;
use LWP::UserAgent;
use Sys::Hostname;
use URI;
use UUID::Tiny ':std';

=head1 NAME

Sentry::Raven - A perl sentry client

=head1 VERSION

Version 0.02

=head1 SYNOPSIS

  my $raven = Sentry::Raven->new( sentry_dsn => 'http://<publickey>:<secretkey>@app.getsentry.com/<projectid>' );

  # capture all errors
  $raven->capture_errors( sub {
      ..do something here..
  } );

  # capture an individual event
  $raven->capture_message('The sky is falling');

=head1 DESCRIPTION

This module implements the recommended raven interface for posting events to a sentry service.

=head1 CONSTRUCTOR

=head2 my $raven = Sentry::Raven->new( %options )

Create a new sentry interface object.  It accepts the following named options:

=over 4

=item I<sentry_dsn =E<gt> C<'http://<publickeyE<gt>:<secretkeyE<gt>@app.getsentry.com/<projectidE<gt>'>>

The DSN for your sentry service.  Get this from the client configuration page for your project.

=item I<timeout =E<gt> 5>

Do not wait longer than this number of seconds when attempting to send an event.

=back

=cut

has [qw/ post_url public_key secret_key /] => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has sentry_version => (
    is      => 'ro',
    isa     => Int,
    default => 3,
);

has timeout => (
    is      => 'ro',
    isa     => Int,
    default => 5,
);

has json_obj => (
    is      => 'ro',
    builder => '_build_json_obj',
    lazy    => 1,
);

has ua_obj => (
    is      => 'ro',
    builder => '_build_ua_obj',
    lazy    => 1,
);

has valid_levels => (
    is      => 'ro',
    isa     => ArrayRef[Str],
    default => sub { [qw/ fatal error warning info debug /] },
);

has options => (
    is      => 'ro',
    isa     => HashRef[],
    default => sub { { } },
);

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;

    my $sentry_dsn = $ENV{SENTRY_DSN} || $args{sentry_dsn}
        or die "must pass sentry_dsn or set SENTRY_DSN envirionment variable\n";

    my $uri = URI->new($sentry_dsn);

    die "unable to parse sentry dsn: $sentry_dsn\n"
        unless defined($uri) && $uri->can('userinfo');

    die "unable to parse public and secret keys from: $sentry_dsn\n"
        unless defined($uri->userinfo()) && $uri->userinfo() =~ m/:/;

    my @path = split(m{/}, $uri->path());
    my ($public_key, $secret_key) = $uri->userinfo() =~ m/(.*):(.*)/;
    my $project_id = pop(@path);

    my $post_url =
        $uri->scheme().'://'.$uri->host().':'.$uri->port() .
        join('/', @path).'/api/'.$project_id.'/store/'
    ;

    return $class->$orig(
        post_url   => $post_url,
        public_key => $public_key,
        secret_key => $secret_key,
        options    => \%args,

        (defined($args{timeout}) ? (timeout => $args{timeout}) : ()),
        (defined($args{ua_obj})  ? (ua_obj  => $args{ua_obj})  : ()),
    );
};

=head1 ERROR HANDLERS

These methods are designed to capture events and handle them automatically.

=head2 $raven->capture_errors( $subref, %options )

Execute the $subref and report any exceptions (die) back to the sentry service.  This automatically includes a stacktrace.  This requires C<$SIG{__DIE__}> so be careful not to override it in subsequent code or error reporting will be impacted.

=cut

sub capture_errors {
    my ($self, $subref, %options) = @_;

    local $SIG{__DIE__} = sub {
        my ($message) = @_;
        chomp($message);

        my @frames;
        my $depth = 1;
        while (my @frame = caller($depth++)) {
            push @frames, {
                module   => $frame[0],
                filename => $frame[1],
                lineno   => $frame[2],
                function => $frame[3],
            };
        }
        @frames = reverse @frames;

        my $event = $self->_generate_event(
            %options,
            message => $message,
            culprit => $PROGRAM_NAME,
        );

        $event = $self->_add_exception_to_event($event, 'Die', $message);
        $event = $self->_add_stacktrace_to_event($event, \@frames);

        $self->_post_event($event);
    };

    return $subref->();
};

=head1 METHODS

These methods are for generating individual events.

=head2 $raven->capture_message( $message, %options )

Post a string message to the sentry service.  Returns the event id.

=cut

sub capture_message {
    my ($self, $message, %options) = @_;
    my $event = $self->_generate_event(message => $message, %options);
    return $self->_post_event($event);
};

=head2 $raven->capture_exception( $exception_type, $exception_value, %options )

Post an exception type and value to the sentry service.  Returns the event id.

=cut

sub capture_exception {
    my ($self, $type, $value, %options) = @_;
    my $event = $self->_add_exception_to_event($self->_generate_event(%options), $type, $value);
    return $self->_post_event($event);
};

sub _add_exception_to_event {
    my ($self, $event, $type, $value) = @_;

    $event->{'sentry.interfaces.Exception'} = {
        type  => $type,
        value => $value,
    };

    return $event;
};

=head2 $raven->capture_request( $url, %request_options, %options )

Post a web url request to the sentry service.  Returns the event id.

C<%options> can contain:

=over

=item I<method =E<gt> 'GET'>

=item I<data =E<gt> { $key =E<gt> $value }>

=item I<query_string =E<gt> 'foo=bar'>

=item I<cookies =E<gt> 'foo=bar'>

=item I<headers =E<gt> { 'Content-Type' =E<gt> 'text/html' }>

=item I<C<env> =E<gt> { REMOTE_ADDR =E<gt> '192.168.0.1' }>

=back

=cut

sub capture_request {
    my ($self, $url, %options) = @_;
    my $event = $self->_add_request_to_event($self->_generate_event(%options), $url, %options);
    return $self->_post_event($event);
};

sub _add_request_to_event {
    my ($self, $event, $url, %options) = @_;

    $event->{'sentry.interfaces.Http'} = {
        url          => $url,
        method       => $options{method},
        data         => $options{data},
        query_string => $options{query_string},
        cookies      => $options{cookies},
        headers      => $options{headers},
        env          => $options{env},
    };

    return $event;
};

=head2 $raven->capture_stacktrace( $frames, %options )

Post a stacktrace to the sentry service.  Returns the event id.

C<$frames> is an arrayref of hashrefs with each hashref representing a single frame.

    my $frames = [
        {
            filename => 'my/file1.pl',
            function => 'function1',
            vars     => { foo => 'bar' },
            lineno   => 10,
        },
        {
            filename => 'my/file2.pl',
            function => 'function2',
            vars     => { bar => 'baz' },
            lineno   => 20,
        },
    ];

The first frame should be the oldest frame.  Frames must contain at least one of C<filename>, C<function>, or C<module>.  These additional attributes are also supported:

=over

=item I<filename =E<gt> $file_name>

=item I<function =E<gt> $function_name>

=item I<module =E<gt> $module_name>

=item I<C<lineno> =E<gt> $line_number>

=item I<C<colno> =E<gt> $column_number>

=item I<abs_path =E<gt> $absolute_path_file_name>

=item I<context_line =E<gt> $line_of_code>

=item I<pre_context =E<gt> [ $previous_line1, $previous_line2 ]>

=item I<post_context =E<gt> [ $next_line1, $next_line2 ]>

=item I<in_app =E<gt> $one_if_not_external_library>

=item I<vars =E<gt> { $variable_name =E<gt> $variable_value }>

=back

=cut

sub capture_stacktrace {
    my ($self, $frames, %options) = @_;
    my $event = $self->_add_stacktrace_to_event($self->_generate_event(%options), $frames);
    return $self->_post_event($event);
};

sub _add_stacktrace_to_event {
    my ($self, $event, $frames) = @_;

    $event->{'sentry.interfaces.Stacktrace'} = {
        frames => $frames,
    };

    return $event;
};

sub _post_event {
    my ($self, $event) = @_;

    my ($response_code, $content);

    eval {
        my $event_json = $self->json_obj()->encode( $event );

        $self->ua_obj()->timeout($self->timeout());

        my $response = $self->ua_obj()->post(
            $self->post_url(),
            'X-Sentry-Auth' => $self->_generate_auth_header(),
            Content         => $event_json,
        );

        $response_code = $response->code();
        $content = $response->content();
    };

    warn "$EVAL_ERROR\n" if $EVAL_ERROR;

    if (defined($response_code) && $response_code == HTTP_OK) {
        return $self->json_obj()->decode($content)->{id};
    } else {
        return;
    }
}

sub _generate_id {
    (my $uuid = create_uuid_as_string(UUID_V4)) =~ s/-//g;
    return $uuid;
}

sub _generate_event {
    my ($self, %options) = @_;

    return {
        event_id    => $options{event_id}    || $self->options()->{event_id}    || _generate_id(),
        timestamp   => $options{timestamp}   || $self->options()->{timestamp}   || DateTime->now()->iso8601(),
        logger      => $options{logger}      || $self->options()->{logger}      || 'root',
        server_name => $options{server_name} || $self->options()->{server_name} || hostname(),
        platform    => $options{platform}    || $self->options()->{platform}    || 'perl',

        message     => $options{message}     || $self->options()->{message},
        culprit     => $options{culprit}     || $self->options()->{culprit},

        extra       => $self->_merge_hashrefs($self->options()->{extra}, $options{extra}),
        tags        => $self->_merge_hashrefs($self->options()->{tags}, $options{tags}),

        level       => $self->_validate_level($options{level}) || $self->options()->{level} || 'error',
    };
}

sub _merge_hashrefs {
    my ($self, $hash1, $hash2) = @_;

    return {
        ($hash1 ? %{ $hash1 } : ()),
        ($hash2 ? %{ $hash2 } : ()),
    };
};

sub _validate_level {
    my ($self, $level) = @_;

    return unless defined($level);

    my %level_hash = map { $_ => 1 } @{ $self->valid_levels() };

    if (exists($level_hash{$level})) {
        return $level;
    } else {
        warn "unknown level: $level\n";
        return;
    }
};

sub _generate_auth_header {
    my ($self) = @_;

    my %fields = (
        sentry_version   => $self->sentry_version(),
        sentry_client    => "raven-perl/$VERSION",
        sentry_timestamp => time(),

        sentry_key       => $self->public_key(),
        sentry_secret    => $self->secret_key(),
    );

    return 'Sentry ' . join(', ', map { $_ . '=' . $fields{$_} } sort keys %fields);
}

sub _build_json_obj { JSON::XS->new()->utf8(1)->pretty(1)->allow_nonref(1) }
sub _build_ua_obj { LWP::UserAgent->new() }

=head1 EVENT ANNOTATORS

These methods are for annotating events by adding additional items, such as stack traces or HTTP requests.

=head1 STANDARD OPTIONS

These options can be passed to all methods accepting %options.  Passing these options to the constructor overrides defaults.

=over 4

=item I<culprit =E<gt> 'Some::Software'>

The source of the event.  Defaults to C<undef>.

=item I<event_id =E<gt> C<'534188f7c1ff4ff280c2e1206c9e0548'>>

The unique identifier string for an event, usually UUID v4.  Max 32 characters.  Defaults to a new unique UUID for each event.  Invalid ids may be discarded silently.

=item I<extra =E<gt> { key1 =E<gt> 'val1', ... }>

Arbitrary key value pairs with extra information about an event.  Defaults to C<{}>.

=item I<level =E<gt> 'error'>

Event level of an event.  Acceptable values are C<fatal>, C<error>, C<warning>, C<info>, and C<debug>.  Defaults to C<error>.

=item I<logger =E<gt> 'root'>

The creator of an event.  Defaults to 'root'.

=item I<platform =E<gt> 'perl'>

The platform (language) in which an event occurred.  Defaults to C<perl>.

=item I<server_name =E<gt> 'localhost.example.com'>

The hostname on which an event occurred.  Defaults to the system hostname.

=item I<tags =E<gt> { key1 =E<gt> 'val1, ... }>

Arbitrary key value pairs with tags for categorizing an event.  Defaults to C<{}>.

=item I<timestamp =E<gt> '1970-01-01T00:00:00'>

Timestamp of an event.  ISO 8601 format.  Defaults to the current time.  Invalid values may be discarded silently.

=back

=head1 CONFIGURATION AND ENVIRONMENT

=over 4

=item SENTRY_DSN=C<http://<publickeyE<gt>:<secretkeyE<gt>@app.getsentry.com/<projectidE<gt>>

A default DSN to be used if sentry_dsn is not passed to c<new>.

=back

=head1 LICENSE

Copyright (C) 2014 by Rentrak Corporation

The full text of this license can be found in the LICENSE file included with this module.

=cut

1;
