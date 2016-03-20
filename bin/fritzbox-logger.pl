#!/usr/bin/env perl
# ABSTRACT: FritzBox bandwidth data to one-document-per line json documents for processing by 
use strict;
use warnings;
use YAML qw/Dump DumpFile LoadFile/;
use Getopt::Long;
use WebService::FritzBox;
use Time::HiRes qw/time/;
use JSON;
use POSIX qw/strftime/;
use Log::Log4perl qw/:easy/;
BEGIN { Log::Log4perl->easy_init() };
use Try::Tiny;
my $logger = get_logger();
my %params;
GetOptions( \%params,
    'config=s',
    'loglevel=s',
    );

if( not $params{config} or not -f $params{config} ){
    die( "Config not defined or does not exist\n" );
}
my $config = LoadFile( $params{config} );
my $loglevel = $params{loglevel} || $config->{loglevel} || 'WARN';
$logger->level( $loglevel );

my %fb_params = map{ $_ => $config->{$_} }
    grep{ $config->{$_} } 
    qw/username password host/;
$fb_params{loglevel} = $loglevel;
    
my $fb = WebService::FritzBox->new( %fb_params );
open( my $fh, '>>', $config->{output} ) or die( $! );

while( 1 ) {
    try{
        DEBUG( "Getting bandwidth" );
        my $document = $fb->bandwidth();
        $document->{'@timestamp'} = _es_timestamp();
        $document->{sub_type}   = 'bandwidth';
        print $fh '' . encode_json( $document ) . "\n";
        
        DEBUG( "Getting syslog" );
        my @events = $fb->syslog(
            last_timestamp => $config->{last_timestamp}
            );
        foreach my $event( sort{ $a->{timestamp} <=> $b->{timestamp} } @events ){
            my $document =  {
                '@timestamp'=> _es_timestamp( $event->{timestamp} ), 
                'message'   => $event->{message},
                'sub_type'  => 'syslog',
            };
            print $fh '' . encode_json( $document ) . "\n";
        }
        $fh->flush();
        $config->{last_timestamp} = $events[0]->{timestamp} if( scalar( @events ) > 0 );
        DumpFile( $params{config}, $config );
    }catch{
        WARN( $_ );
        $fb = WebService::FritzBox->new( %fb_params );
    };
    DEBUG( "Sleeping..." );
    sleep( 10 );
}
close $fh;
exit;

sub _es_timestamp {
    my $timestamp = $_[0] || time();
    my $milliseconds = ( $timestamp * 1000 ) % 1000;
    return strftime( "%Y-%m-%dT%H:%M:%S", gmtime( $timestamp ) ) . sprintf( ".%03uZ", $milliseconds );
}


exit( 0 );

=head1 NAME

fritzbox-syslog-logger.pl

=head1 SYNOPSIS

fritzbox-syslog-logger.pl --password 123456 --output /var/log/fritzbox-bandwidth.log

=head1 DESCRIPTION

Writes JSON logs of fritzbox syslog

=head1 OPTIONS

=over 4

=item --password

Your fritzbox password

=item --output

The file to write the output to

=item --loglevel

Loglevel to run at (TRACE,DEBUG,INFO,WARN,ERROR)

=item --host

Host to connect to.  Default: fritz.box

=back

=head1 COPYRIGHT

Copyright 2015, Robin Clarke

=head1 AUTHOR

Robin Clarke C<perl@robinclarke.net>

=cut

