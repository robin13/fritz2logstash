#!/usr/bin/env perl
# ABSTRACT: FritzBox bandwidth data to one-document-per line json documents for processing by 
use strict;
use warnings;
use YAML;
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
    'password=s',
    'host=s',
    'output=s',
    'loglevel=s',
    );

my %fb_params = map{ $_ => $params{$_} }
    grep{ $params{$_} } 
    qw/loglevel password host/;
if( $params{loglevel} ){
    $logger->level( $params{loglevel} );
}
    
my $fb = WebService::FritzBox->new( %fb_params );
open( my $fh, '>>', $params{output} ) or die( $! );

while( 1 ) {
    try{
        my $document = $fb->bandwidth();
        $document->{'@timestamp'} = _es_timestamp();
        print $fh '' . encode_json( $document ) . "\n";
        $fh->flush();
        $logger->debug( Dump( $document ) ) if $logger->is_debug;
    }catch{
        WARN( $_ );
        $fb = WebService::FritzBox->new( %fb_params );
    };
    sleep( 5 );
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

fritzbox-bandwidth-logger.pl

=head1 SYNOPSIS

fritzbox-bandwidth-logger.pl --password 123456 --output /var/log/fritzbox-bandwidth.log

=head1 DESCRIPTION

Writes JSON logs of fritzbox bandwidth usage.

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

