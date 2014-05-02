package Sentry::Raven;

use 5.008;
use Moose;

our $VERSION = '0.01';

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

=head1 SYNOPSYS

  my $raven = Sentry::Raven->new(sentry_dsn => 'http://<publickey>:<secretkey>@app.getsentry.com/<projectid>' );
  $raven->capture_message('The sky is falling');

=head1 DESCRIPTION

=head1 METHODS

=head2 my $raven = Sentry::Raven->new( %options )

Create a new sentry interface object.  It accepts the following named options:

=over 4

=item I<sentry_dsn =E<gt> C<'http://<publickeyE<gt>:<secretkeyE<gt>@app.getsentry.com/<projectidE<gt>'>>

The DSN for your sentry service.  Get this from the client configuration page for your project.

=item I<timeout =E<gt> 5>

Do not wait longer than this number of seconds when attempting to send an event.

=back

=cut

has [qw/ scheme host port path public_key secret_key project_id /] => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has sentry_version => (
    is      => 'ro',
    isa     => 'Int',
    default => 3,
);

has timeout => (
    is      => 'ro',
    isa     => 'Int',
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
    isa     => 'ArrayRef[Str]',
    default => sub { [qw/ fatal error warning info debug /] },
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

    my @path = split('/', $uri->path());
    my ($public_key, $secret_key) = $uri->userinfo() =~ m/(.*):(.*)/;
    my $project_id = pop(@path);

    return $class->$orig(
        host       => $uri->host(),
        path       => join('/', @path),
        port       => $uri->port(),
        scheme     => $uri->scheme(),
        public_key => $public_key,
        secret_key => $secret_key,
        project_id => $project_id,

        (defined($args{timeout}) ? (timeout => $args{timeout}) : ()),
        (defined($args{ua_obj})  ? (ua_obj  => $args{ua_obj})  : ()),
    );
};


=head2 $raven->capture_message( $message, %options )

Post a string message to the sentry service.  Returns the event id.

=cut

sub capture_message {
    my ($self, $message, %options) = @_;
    $self->_post_event($self->_generate_message_event($message, %options));
};

sub _generate_message_event {
    my ($self, $message, %options) = @_;
    return $self->_generate_event(message => $message, %options);
};

=head2 $raven->capture_exception( $exception_type, $exception_value, %options )

Post an exception type and value to the sentry service.  Returns the event id.

=cut

sub capture_exception {
    my ($self, $type, $value, %options) = @_;
    $self->_post_event($self->_generate_exception_event($type, $value, %options));
};

sub _generate_exception_event {
    my ($self, $type, $value, %options) = @_;

    my $event = $self->_generate_event(%options);

    $event->{'sentry.interfaces.Exception'} = {
        type  => $type,
        value => $value,
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
            $self->_post_url(),
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
        event_id    => $options{event_id}    || _generate_id(),
        timestamp   => $options{timestamp}   || DateTime->now()->iso8601(),
        logger      => $options{logger}      || 'root',
        server_name => $options{server_name} || hostname(),
        platform    => $options{platform}    || 'perl',

        message     => $options{message},
        culprit     => $options{culprit},
        extra       => $options{extra}       || {},
        tags        => $options{tags}        || {},

        level       => $self->_validate_level($options{level}) || 'error',
    };
}

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

sub _post_url {
    my ($self) = @_;

    return
        $self->scheme().'://'.$self->host().':'.$self->port() .
        $self->path().'/api/'.$self->project_id().'/store/';
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

=head1 STANDARD OPTIONS

These options can be passed to all of the C<capture_*> methods.

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

The creator of an event.  Defaults to current user.

=item I<platform =E<gt> 'perl'>

The platform (language) in which an event occurred.  Defaults to C<perl>.

=item I<server_name =E<gt> 'localhost.example.com'>

The hostname on which an event occurred.  Defaults to the system hostname.

=item I<tags =E<gt> { key1 =E<gt> 'val1, ... }>

Arbitrary key value pairs with tags for categorizing an event.  Defaults to C<{}>.

=item I<timestamp =E<gt> '1970-01-01T00:00:00'>

Timestamp of an event.  ISO 8601 format.  Defaults to the current time.  Invalid values may be discarded silently.

=back

=head1 ENVIRONMENT

=over 4

=item SENTRY_DSN

A default DSN to be used if sentry_dsn is not passed to c<new>.

=back

=cut

1;
