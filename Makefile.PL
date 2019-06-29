use ExtUtils::MakeMaker;

WriteMakefile1(
    NAME                => 'Sentry::Raven',
    ABSTRACT_FROM       => 'lib/Sentry/Raven.pm',
    VERSION_FROM        => 'lib/Sentry/Raven.pm',
    MIN_PERL_VERSION    => '5.008',
    AUTHOR              => 'Matt Harrington',
    LICENSE             => 'mit',

    PREREQ_PM           => {
        'Data::Dump'                   => 0,
        'Devel::StackTrace'            => 0,
        'English'                      => 0,
        'File::Basename'               => 0,
        'HTTP::Request::Common'        => 0,
        'HTTP::Status'                 => 0,
        'JSON::XS'                     => 0,
        'LWP::Protocol::https'         => 0,
        'LWP::UserAgent'               => 0,
        'Moo'                          => 0,
        'MooX::Types::MooseLike::Base' => 0,
        'Sys::Hostname'                => 0,
        'Time::Piece'                  => 0,
        'URI'                          => 0,
        'UUID::Tiny'                   => 0,
    },

    TEST_REQUIRES       => {
        'File::Spec'                        => 0,
        'HTTP::Response'                    => 0,
        'IO::Uncompress::Gunzip'            => 0,
        'Test::CPAN::Changes::ReallyStrict' => 0,
        'Test::LWP::UserAgent'              => 0,
        'Test::More'                        => '0.88',
        'Test::Perl::Critic'                => '1.03',
        'Test::Warn'                        => '0.30',
    },

    META_MERGE          => {
        'meta-spec' => {
            version => '2',
            url     => 'http://search.cpan.org/perldoc?CPAN::Meta::Spec',
        },

        homepage    => 'https://github.com/getsentry/perl-raven',
        resources   => {
            repository => {
                type => 'git',
                url  => 'git@github.com:getsentry/perl-raven.git',
                web  => 'https://github.com/getsentry/perl-raven',
            },
        },
    },
);


sub WriteMakefile1 {   # Cribbed from eumm-upgrade by Alexandr Ciornii
  my %params = @_;
  my $eumm_version = $ExtUtils::MakeMaker::VERSION;
  $eumm_version = eval $eumm_version;

  if ($params{TEST_REQUIRES} and $eumm_version < 6.6303) {
      $params{BUILD_REQUIRES}={ %{$params{BUILD_REQUIRES} || {}} , %{$params{TEST_REQUIRES}} };
      delete $params{TEST_REQUIRES};
  }
  if ($params{BUILD_REQUIRES} and $eumm_version < 6.5503) {
      #EUMM 6.5502 has problems with BUILD_REQUIRES
      $params{PREREQ_PM}={ %{$params{PREREQ_PM} || {}} , %{$params{BUILD_REQUIRES}} };
      delete $params{BUILD_REQUIRES};
  }
  delete $params{CONFIGURE_REQUIRES} if $eumm_version < 6.52;
  delete $params{MIN_PERL_VERSION} if $eumm_version < 6.48;
  delete $params{META_MERGE} if $eumm_version < 6.46;
  delete $params{META_ADD} if $eumm_version < 6.46;
  delete $params{LICENSE} if $eumm_version < 6.31;
  delete $params{AUTHOR} if $] < 5.005;
  delete $params{ABSTRACT_FROM} if $] < 5.005;
  delete $params{BINARY_LOCATION} if $] < 5.005;

  WriteMakefile(%params);
}
