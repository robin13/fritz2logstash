#!/usr/bin/env perl
# ABSTRACT: FritzBox bandwidth data to one-document-per line json documents for processing by 
use strict;
use warnings;
use YAML qw/Dump DumpFile LoadFile/;
use Getopt::Long;
use WebService::FritzBox;
use Class::Date qw/date/;
use Time::HiRes qw/time/;
use Digest::SHA1 qw/sha1_hex/;
use JSON;
use POSIX qw/strftime/;
use Log::Log4perl qw/:easy/;
use HTML::TreeBuilder;
use Encode qw/encode_utf8 encode decode is_utf8/;
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

foreach( qw/password output/ ){
    if( not $params{$_} ){
        die( "Required parameter not defined: $_\n" );
    }
}

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
        DEBUG( "Getting syslog" );
        my $document = $fb->get( path => '/system/syslog.lua' );
        my $tree = HTML::TreeBuilder->new();
        $tree->parse_content( $document->decoded_content );
        my @results = $tree->look_down( '_tag', 'div', sub{ $_[0]->attr( 'class' ) and $_[0]->attr( 'class' ) eq 'scroll_area' } );
        my @rows = $results[0]->look_down( '_tag', 'tr' );
        ROW:
        foreach my $row ( @rows ) {
            my @cols = $row->look_down( '_tag', 'td' );
            my( $day, $month, $year ) = split( '\.', $cols[0]->as_text_trimmed );
            $year = '20' . $year;
            my( $hour, $minute, $second ) = split( ':', $cols[1]->as_text_trimmed );
            my $timestamp = Class::Date->new( [ $year, $month, $day, $hour, $minute, $second ] );
            #my $text = encode_utf8( $cols[2]->as_text_trimmed );
            my $text =  $cols[2]->as_text_trimmed;
            my $row_string = sprintf "%s %s", $timestamp->string, $text;

            my $document = {
                '@timestamp' => _es_timestamp( $timestamp->epoch ),
                'message'   => $text,
            };
            $logger->trace( Dump( $document ) ) if $logger->is_trace;
            print $fh '' . encode_json( $document ) . "\n";
        }
        $fh->flush();
        DEBUG( "Deleting old entries" );
        my $response = $fb->post( path => '/system/syslog.lua', content => 'delete=1' );
    }catch{
        WARN( $_ );
        $fb = WebService::FritzBox->new( %fb_params );
    };
    DEBUG( "Sleeping..." );
    sleep( 60 );
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

