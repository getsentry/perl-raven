package Sentry::Raven;

use 5.008;
use strict;
use warnings;
use Moo;
use MooX::Types::MooseLike::Base qw/ ArrayRef HashRef Int Str Maybe /;

our $VERSION = '1.05';

use Data::Dump 'dump';
use DateTime;
use Devel::StackTrace;
use English '-no_match_vars';
use File::Basename 'basename';
use HTTP::Request::Common 'POST';
use HTTP::Status ':constants';
use JSON::XS;
use LWP::UserAgent;
use Sys::Hostname;
use URI;
use UUID::Tiny ':std';

# constants from server-side sentry code
use constant {
    MAX_CULPRIT               =>  200,
    MAX_MESSAGE               => 2048,

    MAX_EXCEPTION_TYPE        =>  128,
    MAX_EXCEPTION_VALUE       =>  256,

    MAX_HTTP_QUERY_STRING     => 1024,
    MAX_HTTP_DATA             => 2048,

    MAX_QUERY_ENGINE          =>  128,
    MAX_QUERY_QUERY           => 1024,

    MAX_STACKTRACE_FILENAME   =>  256,
    MAX_STACKTRACE_PACKAGE    =>  256,
    MAX_STACKTRACE_SUBROUTUNE =>  256,

    MAX_USER_EMAIL            =>  128,
    MAX_USER_ID               =>  128,
    MAX_USER_USERNAME         =>  128,
};

# self-imposed constants
use constant {
    MAX_HTTP_COOKIES          => 1024,
    MAX_HTTP_URL              => 1024,

    MAX_STACKTRACE_VARS       => 1024,
};

=head1 NAME

Sentry::Raven - A perl sentry client

=head1 VERSION

Version 1.00

=head1 SYNOPSIS

  my $raven = Sentry::Raven->new( sentry_dsn => 'http://<publickey>:<secretkey>@app.getsentry.com/<projectid>' );

  # capture all errors
  $raven->capture_errors( sub {
      ..do something here..
  } );

  # capture an individual event
  $raven->capture_message('The sky is falling');

  # annotate an event with context
  $raven->capture_message(
    'The sky is falling',
    Sentry::Raven->exception_context('SkyException', 'falling'),
  );

=head1 DESCRIPTION

This module implements the recommended raven interface for posting events to a sentry service.

=head1 CONSTRUCTOR

=head2 my $raven = Sentry::Raven->new( %options, %context )

Create a new sentry interface object.  It accepts the following named options:

=over

=item C<< sentry_dsn => 'http://<publickey>:<secretkey>@app.getsentry.com/<projectid>' >>

The DSN for your sentry service.  Get this from the client configuration page for your project.

=item C<< timeout => 5 >>

Do not wait longer than this number of seconds when attempting to send an event.

=item C<< release => 'ec899ea' >>

Track the version of your application in Sentry.

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
    default => 7,
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

has valid_interfaces => (
    is      => 'ro',
    isa     => ArrayRef[Str],
    default => sub { [qw/
        sentry.interfaces.Exception sentry.interfaces.Http
        sentry.interfaces.Stacktrace sentry.interfaces.User
        sentry.interfaces.Query
    /] },
);

has context => (
    is      => 'rw',
    isa     => HashRef[],
    default => sub { { } },
);

has processors => (
    is      => 'rw',
    isa     => ArrayRef[],
    default => sub { [] },
);

has encoding => (
    is      => 'rw',
    isa     => Str,
    default => 'gzip',
);

has release => (
    is      => 'ro',
    isa     => Maybe[Str],
);

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;

    my $sentry_dsn = $ENV{SENTRY_DSN} || $args{sentry_dsn}
        or die "must pass sentry_dsn or set SENTRY_DSN envirionment variable\n";

    delete($args{sentry_dsn});

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

    my $timeout = delete($args{timeout});
    my $ua_obj = delete($args{ua_obj});
    my $processors = delete($args{processors}) || [];
    my $encoding = delete($args{encoding});
    my $release = delete($args{release});

    return $class->$orig(
        post_url   => $post_url,
        public_key => $public_key,
        secret_key => $secret_key,
        context    => \%args,
        processors => $processors,
        release    => $release,

        (defined($encoding) ? (encoding => $encoding) : ()),
        (defined($timeout) ? (timeout => $timeout) : ()),
        (defined($ua_obj) ? (ua_obj => $ua_obj) : ()),
    );
};

sub _trim {
    my ($string, $length) = @_;
    return defined($string)
        ? substr($string, 0, $length)
        : undef;
}

=head1 ERROR HANDLERS

These methods are designed to capture events and handle them automatically.

=head2 $raven->capture_errors( $subref, %context )

Execute the $subref and report any exceptions (die) back to the sentry service.  If it is unable to submit an event (capture_message return undef), it will die and include the event details in the die message.  This automatically includes a stacktrace unless C<$SIG{__DIE__}> has been overridden in subsequent code.

=cut

sub capture_errors {
    my ($self, $subref, %context) = @_;

    my $wantarray = wantarray();

    my ($stacktrace, @retval);
    eval {
        local $SIG{__DIE__} = sub { $stacktrace = Devel::StackTrace->new(skip_frames => 1) };

        if ($wantarray) {
            @retval = $subref->();
        } else {
            $retval[0] = $subref->();
        }
    };

    my $eval_error = $EVAL_ERROR;

    if ($eval_error) {
        my $message = $eval_error;
        chomp($message);

        my %stacktrace_context = $stacktrace
            ? $self->stacktrace_context(
                $self->_get_frames_from_devel_stacktrace($stacktrace),
            )
            : ();

        %context = (
            culprit => $PROGRAM_NAME,
            %context,
            $self->exception_context($message),
            %stacktrace_context,
        );

        my $event_id = $self->capture_message($message, %context);

        if (!defined($event_id)) {
            die "failed to submit event to sentry service:\n" . dump($self->_construct_message_event($message, %context));
        }
    }

    return $wantarray ? @retval : $retval[0];
};

sub _get_frames_from_devel_stacktrace {
    my ($self, $stacktrace) = @_;

    my @frames = map {
        my $frame = $_;
        {
            abs_path => _trim($frame->filename(), MAX_STACKTRACE_FILENAME),
            filename => _trim(basename($frame->filename()), MAX_STACKTRACE_FILENAME),
            function => _trim($frame->subroutine(), MAX_STACKTRACE_SUBROUTUNE),
            lineno   => $frame->line(),
            module   => _trim($frame->package(), MAX_STACKTRACE_PACKAGE),
            vars     => {
                '@_' => [
                    map { _trim(dump($_), MAX_STACKTRACE_VARS) } $frame->args(),
                ],
            },
        }
    } $stacktrace->frames();

    # Devel::Stacktrace::Frame's subroutine() and args() describe what's being called by the current frame,
    # whereas Sentry expects function and vars to describe the current frame.
    for my $i (0..$#frames) {
        my $frame = $frames[$i];
        my $parent = $frames[$i + 1] // {};
        @$frame{'function', 'vars'} = @$parent{'function', 'vars'};
    }

    return [ reverse(@frames) ];
}

=head1 METHODS

These methods are for generating individual events.

=head2 $raven->capture_message( $message, %context )

Post a string message to the sentry service.  Returns the event id.

=cut

sub capture_message {
    my ($self, $message, %context) = @_;
    return $self->_post_event($self->_construct_message_event($message, %context));
}

sub _construct_message_event {
    my ($self, $message, %context) = @_;
    return $self->_construct_event(message => $message, %context);
}

=head2 $raven->capture_exception( $exception_value, %exception_context, %context )

Post an exception type and value to the sentry service.  Returns the event id.

C<%exception_context> can contain:

=over

=item C<< type => $type >>

=back

=cut

sub capture_exception {
    my ($self, $value, %context) = @_;
    return $self->_post_event($self->_construct_exception_event($value, %context));
};

sub _construct_exception_event {
    my ($self, $value, %context) = @_;
    return $self->_construct_event(
        %context,
        $self->exception_context($value, %context),
    );
};

=head2 $raven->capture_request( $url, %request_context, %context )

Post a web url request to the sentry service.  Returns the event id.

C<%request_context> can contain:

=over

=item C<< method => 'GET' >>

=item C<< data => 'foo=bar' >>

=item C<< query_string => 'foo=bar' >>

=item C<< cookies => 'foo=bar' >>

=item C<< headers => { 'Content-Type' => 'text/html' } >>

=item C<< env => { REMOTE_ADDR => '192.168.0.1' } >>

=back

=cut

sub capture_request {
    my ($self, $url, %context) = @_;
    return $self->_post_event($self->_construct_request_event($url, %context));
};

sub _construct_request_event {
    my ($self, $url, %context) = @_;

    return $self->_construct_event(
        %context,
        $self->request_context($url, %context),
    );
};

=head2 $raven->capture_stacktrace( $frames, %context )

Post a stacktrace to the sentry service.  Returns the event id.

C<$frames> can be either a Devel::StackTrace object, or an arrayref of hashrefs with each hashref representing a single frame.

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

=item C<< filename => $file_name >>

=item C<< function => $function_name >>

=item C<< module => $module_name >>

=item C<< lineno => $line_number >>

=item C<< colno => $column_number >>

=item C<< abs_path => $absolute_path_file_name >>

=item C<< context_line => $line_of_code >>

=item C<< pre_context => [ $previous_line1, $previous_line2 ] >>

=item C<< post_context => [ $next_line1, $next_line2 ] >>

=item C<< in_app => $one_if_not_external_library >>

=item C<< vars => { $variable_name => $variable_value } >>

=back

=cut

sub capture_stacktrace {
    my ($self, $frames, %context) = @_;
    return $self->_post_event($self->_construct_stacktrace_event($frames, %context));
};

sub _construct_stacktrace_event {
    my ($self, $frames, %context) = @_;

    return $self->_construct_event(
        %context,
        $self->stacktrace_context($frames),
    );
};

=head2 $raven->capture_user( %user_context, %context )

Post a user to the sentry service.  Returns the event id.

C<%user_context> can contain:

=over

=item C<< id => $unique_id' >>

=item C<< username => $username' >>

=item C<< email => $email' >>

=back

=cut

sub capture_user {
    my ($self, %context) = @_;
    return $self->_post_event($self->_construct_user_event(%context));
};

sub _construct_user_event {
    my ($self, %context) = @_;

    return $self->_construct_event(
        %context,
        $self->user_context(%context),
    );
};

=head2 $raven->capture_query( $query, %query_context, %context )

Post a query to the sentry service.  Returns the event id.

C<%query_context> can contain:

=over

=item C<< engine => $engine' >>

=back

=cut

sub capture_query {
    my ($self, $query, %context) = @_;
    return $self->_post_event($self->_construct_query_event($query, %context));
};

sub _construct_query_event {
    my ($self, $query, %context) = @_;

    return $self->_construct_event(
        %context,
        $self->query_context($query, %context),
    );
};

sub _post_event {
    my ($self, $event) = @_;

    $event = $self->_process_event($event);

    my ($response, $response_code, $response_content);

    eval {
        my $event_json = $self->json_obj()->encode( $event );

        $self->ua_obj()->timeout($self->timeout());

        my $request = POST(
            $self->post_url(),
            'X-Sentry-Auth'    => $self->_generate_auth_header(),
            Content            => $event_json,
        );
        $request->encode( $self->encoding() );
        $response = $self->ua_obj()->request($request);

        $response_code = $response->code();
        $response_content = $response->content();
    };

    warn "$EVAL_ERROR\n" if $EVAL_ERROR;

    if (defined($response_code) && $response_code == HTTP_OK) {
        return $self->json_obj()->decode($response_content)->{id};
    } else {
        if ($response) {
            warn "Unsuccessful Response Posting Sentry Event:\n"._trim($response->as_string(), 1000)."\n";
        }
        return;
    }
}

sub _process_event {
    my ($self, $event) = @_;

    foreach my $processor (@{$self->processors()}) {
        my $processed_event = $processor->process($event);
        if ($processed_event) {
            $event = $processed_event;
        } else {
            die "processor $processor did not return an event";
        }
    }

    return $event;
}

sub _generate_id {
    (my $uuid = create_uuid_as_string(UUID_V4)) =~ s/-//g;
    return $uuid;
}

sub _construct_event {
    my ($self, %context) = @_;

    my $event = {
        event_id    => $context{event_id}    || $self->context()->{event_id}    || _generate_id(),
        timestamp   => $context{timestamp}   || $self->context()->{timestamp}   || DateTime->now()->iso8601(),
        logger      => $context{logger}      || $self->context()->{logger}      || 'root',
        server_name => $context{server_name} || $self->context()->{server_name} || hostname(),
        platform    => $context{platform}    || $self->context()->{platform}    || 'perl',
        release     => $self->release,

        message     => $context{message}     || $self->context()->{message},
        culprit     => $context{culprit}     || $self->context()->{culprit},

        extra       => $self->_merge_hashrefs($self->context()->{extra}, $context{extra}),
        tags        => $self->_merge_hashrefs($self->context()->{tags}, $context{tags}),
        fingerprint => $context{fingerprint} || $self->context()->{fingerprint} || ['{{ default }}'],

        level       => $self->_validate_level($context{level}) || $self->context()->{level} || 'error',
    };

    $event->{message} = _trim($event->{message}, MAX_MESSAGE);
    $event->{culprit} = _trim($event->{culprit}, MAX_CULPRIT);

    foreach my $interface (@{ $self->valid_interfaces() }) {
        $event->{$interface} = $context{$interface}
            if $context{$interface};
    }

    return $event;
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
sub _build_ua_obj {
    return LWP::UserAgent->new(
        keep_alive => 1,
    );
}

=head1 EVENT CONTEXT

These methods are for annotating events with additional context, such as stack traces or HTTP requests.  Simply pass their output to any other method accepting C<%context>.  They accept all of the same arguments as their C<capture_*> counterparts.

  $raven->capture_message(
    'The sky is falling',
    Sentry::Raven->exception_context('falling', type => 'SkyException'),
  );

=head2 Sentry::Raven->exception_context( $value, %exception_context )

=cut

sub exception_context {
    my ($class, $value, %exception_context) = @_;

    return (
        'sentry.interfaces.Exception' => {
            value => _trim($value, MAX_EXCEPTION_VALUE),
            type  => _trim($exception_context{type}, MAX_EXCEPTION_TYPE),
        }
    );
};

=head2 Sentry::Raven->request_context( $url, %request_context )

=cut

sub request_context {
    my ($class, $url, %context) = @_;

    return (
        'sentry.interfaces.Http' => {
            url          => _trim($url, MAX_HTTP_URL),
            method       => $context{method},
            data         => _trim($context{data}, MAX_HTTP_DATA),
            query_string => _trim($context{query_string}, MAX_HTTP_QUERY_STRING),
            cookies      => _trim($context{cookies}, MAX_HTTP_COOKIES),
            headers      => $context{headers},
            env          => $context{env},
        }
    );
};

=head2 Sentry::Raven->stacktrace_context( $frames )

=cut

sub stacktrace_context {
    my ($class, $frames) = @_;

    eval {
        $frames = $class->_get_frames_from_devel_stacktrace($frames)
            if $frames->isa('Devel::StackTrace');
    };

    return (
        'sentry.interfaces.Stacktrace' => {
            frames => $frames,
        }
    );
};

=head2 Sentry::Raven->user_context( %user_context )

=cut

sub user_context {
    my ($class, %user_context) = @_;

    return (
        'sentry.interfaces.User' => {
            email    => _trim($user_context{email}, MAX_USER_EMAIL),
            id       => _trim($user_context{id}, MAX_USER_ID),
            username => _trim($user_context{username}, MAX_USER_USERNAME),
        }
    );
};

=head2 Sentry::Raven->query_context( $query, %query_context )

=cut

sub query_context {
    my ($class, $query, %query_context) = @_;

    return (
        'sentry.interfaces.Query' => {
            query  => _trim($query, MAX_QUERY_QUERY),
            engine => _trim($query_context{engine}, MAX_QUERY_ENGINE),
        }
    );
};

=pod

The default context can be modified with the following accessors:

=head2 my %context = $raven->get_context();

=cut

sub get_context {
    my ($self) = @_;
    return %{ $self->context() };
};

=head2 $raven->add_context( %context )

=cut

sub add_context {
    my ($self, %context) = @_;
    $self->context()->{$_} = $context{$_}
        for keys %context;
};

=head2 $raven->merge_tags( %tags )

Merge additional tags into any existing tags in the current context.

=cut

sub merge_tags {
    my ($self, %tags) = @_;
    $self->context()->{tags} = $self->_merge_hashrefs($self->context()->{tags}, \%tags);
};

=head2 $raven->merge_extra( %tags )

Merge additional extra into any existing extra in the current context.

=cut

sub merge_extra {
    my ($self, %extra) = @_;
    $self->context()->{extra} = $self->_merge_hashrefs($self->context()->{extra}, \%extra);
};

=head2 $raven->clear_context()

=cut

sub clear_context {
    my ($self) = @_;
    $self->context({});
};

=head1 EVENT PROCESSORS

Processors are a mechanism for modifying events after they are generated but before they are posted to the sentry service.  They are useful for scrubbing sensitive data, such as passwords, as well as adding additional context.  If the processor fails (dies or returns undef), the failure will be passed to the caller.

See L<Sentry::Raven::Processor> for information on creating new processors.

Available processors:

=over

=item L<Sentry::Raven::Processor::RemoveStackVariables>

=back

=head2 $raven->add_processors( [ Sentry::Raven::Processor::RemoveStackVariables, ... ] )

=cut

sub add_processors {
    my ($self, @processors) = @_;
    push @{ $self->processors() }, @processors;
};

=head2 $raven->clear_processors( [ Sentry::Raven::Processor::RemoveStackVariables, ... ] )

=cut

sub clear_processors {
    my ($self) = @_;
    $self->processors([]);
};

=head1 STANDARD OPTIONS

These options can be passed to all methods accepting %context.  Passing context to the constructor overrides defaults.

=over

=item C<< culprit => 'Some::Software' >>

The source of the event.  Defaults to C<undef>.

=item C<< event_id => '534188f7c1ff4ff280c2e1206c9e0548' >>

The unique identifier string for an event, usually UUID v4.  Max 32 characters.  Defaults to a new unique UUID for each event.  Invalid ids may be discarded silently.

=item C<< extra => { key1 => 'val1', ... } >>

Arbitrary key value pairs with extra information about an event.  Defaults to C<{}>.

=item C<< level => 'error' >>

Event level of an event.  Acceptable values are C<fatal>, C<error>, C<warning>, C<info>, and C<debug>.  Defaults to C<error>.

=item C<< logger => 'root' >>

The creator of an event.  Defaults to 'root'.

=item C<< platform => 'perl' >>

The platform (language) in which an event occurred.  Defaults to C<perl>.

=item C<< processors => [ Sentry::Raven::Processor::RemoveStackVariables, ... ] >>

A set or processors to be applied to events before they are posted.  See L<Sentry::Raven::Processor> for more information.  This can only be set during construction and not on other methods accepting %context.

=item C<< server_name => 'localhost.example.com' >>

The hostname on which an event occurred.  Defaults to the system hostname.

=item C<< tags => { key1 => 'val1, ... } >>

Arbitrary key value pairs with tags for categorizing an event.  Defaults to C<{}>.

=item C<< fingerprint => [ 'val1', 'val2', ... } >>

Array of strings used to control how events aggregate in the sentry web interface. The string C<'{{ default }}'> has special meaning when used as the first value; it indicates that sentry should use the default aggregation method in addition to any others specified (useful for fine-grained aggregation). Defaults to C<['{{ default }}']>.

=item C<< timestamp => '1970-01-01T00:00:00' >>

Timestamp of an event.  ISO 8601 format.  Defaults to the current time.  Invalid values may be discarded silently.

=back

=head1 CONFIGURATION AND ENVIRONMENT

=over

=item SENTRY_DSN=C<< http://<publickey>:<secretkey>@app.getsentry.com/<projectid> >>

A default DSN to be used if sentry_dsn is not passed to c<new>.

=back

=head1 LICENSE

Copyright (C) 2014 by Rentrak Corporation

The full text of this license can be found in the LICENSE file included with this module.

=cut

1;
