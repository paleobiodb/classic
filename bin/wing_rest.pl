#!/usr/bin/env perl

# Paleobiology Database Data Service
# 
# This program reads configuration information from the file 'config.yml' and
# then launches the 'starman' web server to provide a data service for the
# Paleobiology Database.
# 
# The relevant configuration parameters are:
# 
# port - port on which to listen
# workers - how many active data service processes to maintain
# 



use strict;

use Dancer ':script';


my $PORT = config->{rest_port}|| 6000;
my $WORKERS = config->{rest_workers} || 2;
my $ACCESS_LOG = config->{rest_access_log} || 'rest_log';

unless ( $ACCESS_LOG =~ qr{/} )
{
    $ACCESS_LOG = "logs/$ACCESS_LOG";
}

my $pid_file;

open($pid_file, ">", "logs/wing_rest.pid");
print $pid_file $$;
close $pid_file;

$ENV{WING_CONFIG} = "/data/MyApp/etc/wing.conf";
$ENV{WING_HOME} = "/data/Wing";

exec('starman', 
     '--listen', ":$PORT", '--workers', $WORKERS, '--access-log', $ACCESS_LOG, 
     '--preload-app', 'bin/rest.psgi')
    
    or die "Could not run program /usr/local/bin/starman: $!";







