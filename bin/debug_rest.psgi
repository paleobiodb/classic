#!/usr/bin/env perl
use lib '/data/MyApp/lib', '/data/Wing/lib';

use Dancer;
use MyApp::Rest;
use Plack::Builder;

# my $env = shift;
# $env->{'psgix.harakiri'} = 1;

    # my $request = Dancer::Request->new();
    
$DB::single = 1;
$DB::deep = 500;
    
if ( $ARGV[0] =~ /^get$|^post$|^put$|^delete$/i )
{
    set apphandler => 'Debug';
    set logger => 'console';
    set show_errors => 0;
    
    # if ( defined $ARGV[2] && $ARGV[2] =~ /cookie=([^&]+)/ )
    # {
    # 	param session_id => $1;
    # }
}

# else
# {
#     die "You must run this with a first argument of GET or POST\n";
# }

# $DB::single = 1;

dance;
