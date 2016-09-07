#!/usr/bin/env perl
use lib '/data/MyApp/lib', '/data/Wing/lib';

use Dancer;
use MyApp::Web;
# use Plack::Builder;

# my $env = shift;
# $env->{'psgix.harakiri'} = 1;

    # my $request = Dancer::Request->new();
    
    # $DB::single = 1;
    
    if ( $ARGV[0] =~ /^get$|^post$/i )
    {
	set apphandler => 'Debug';
	set logger => 'console';
	set show_errors => 0;
    }
    
dance;
