use ExtUtils::MakeMaker;

WriteMakefile(
    NAME            => 'Sentry::Raven',
    PREREQ_PM       => {
        'DateTime'          => 0,
        'HTTP::Request'     => 0,
        'HTTP::Status'      => 0,
        'JSON::XS'          => 0,
        'LWP::UserAgent'    => 0,
        'Moose'             => 0,
        'Sys::Hostname'     => 0,
        'URI'               => 0,
        'UUID::Tiny'        => 0,
    },
    # TEST_REQUIRES   => {
    #     'HTTP::Response'        => 0,
    #     'Test::LWP::UserAgent'  => 0,
    #     'Test::More'            => 0,
    # },
    VERSION_FROM    => 'lib/Sentry/Raven.pm',
);
