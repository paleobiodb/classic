#!/usr/local/bin/perl
##!/usr/bin/env perl
 
# Paleobiology Database Web server
# 
# This program reads configuration information from the file 'config.yml' and
# then launches the 'starman' web server to provide a set of web server processes for the
# Paleobiology Database.
# 
# The relevant configuration parameters are:
# 
# web_port - port on which to listen
# web_workers - how many active data service processes to maintain
# 



use strict;

use Dancer ':script';


my $PORT = config->{web_port}|| 6001;
my $WORKERS = config->{web_workers} || 2;
my $ACCESS_LOG = config->{web_access_log} || 'access_log';

unless ( $ACCESS_LOG =~ qr{/} )
{
    $ACCESS_LOG = "logs/$ACCESS_LOG";
}

my $pid_file;

open($pid_file, ">", "logs/wing_web.pid");
print $pid_file $$;
close $pid_file;

$ENV{WING_CONFIG} = "/data/MyApp/etc/wing.conf";
$ENV{WING_HOME} = "/data/Wing";

exec('/usr/local/bin/starman', 
     '--listen', ":$PORT", '--workers', $WORKERS, '--access-log', $ACCESS_LOG, 
     '--preload-app', 'bin/web.psgi')
    
    or die "Could not run program /usr/local/bin/starman: $!";







