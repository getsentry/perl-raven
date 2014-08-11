package Sentry::Raven::Processor::RemoveStackVariables;

use 5.008;
use strict;
use warnings;

=head1 NAME

Sentry::Raven::Processor::RemoveStackVariables - Remove stack variables from stack traces in events

=head1 SYNOPSIS

  use Sentry::Raven;
  use Sentry::Raven::Processor::RemoveStackVariables;

  my $raven = Sentry::Raven->new(
    processors => [ Sentry::Raven::Processor::RemoveStackVariables ],
  );

=head1 DESCRIPTION

This processor removes variables from stack traces before they are posted to the sentry service.  This prevents sensitive values from being exposed, such as passwords or credit card numbers.

=head1 METHODS

=head2 my $processed_event = Sentry::Raven::Processor::RemoveStackVariables->process( $event )

Process an event.

=cut

sub process {
    my ($class, $event) = @_;
    if ($event->{'sentry.interfaces.Stacktrace'}) {
        my $num_frames = scalar(@{$event->{'sentry.interfaces.Stacktrace'}->{frames}});
        delete($event->{'sentry.interfaces.Stacktrace'}->{frames}->[$_]->{vars}) for 0..($num_frames-1);
    }
    return $event;
}

1;
