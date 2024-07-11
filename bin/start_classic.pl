#!/usr/bin/env perl
#
# This script is designed to be the entry point for the 'classic' service container in
# the dockerized version of the Paleobiology Database. It starts three separate daemons:
# 
#   - the main web application (web.psgi)
#   - the associated data service (rest.psgi)
#   - the taxonomy processing daemonn (taxa_cached.pl)
#
# These three together provide all necessary functionality for the Classic interface to
# the Paleobiology Database.
#
# I have chosen to run all three of these separate services in a single container because they use
# a common codebase and all are necessary for the Classic service. The first incarnation of this
# project ran them in separate containers, but I judged that the added complexity was unnecessary.
# Despite the fact that Docker standard practice is to run each service in its own container, in
# this case it makes the most sense to combine them.
#
# Author: Michael McClennen
# Created: 2020-07-02

use strict;

use YAML::Any qw(LoadFile);

# The following variables can be changed if the main directory is ever moved.

my ($MAIN_DIR) = '/data/MyApp';
my ($WING_DIR) = '/data/Wing';

# Set the necessary environment variables

$ENV{WING_HOME} = $WING_DIR;
$ENV{WING_APP} = $MAIN_DIR;
$ENV{WING_CONFIG} = "$MAIN_DIR/etc/wing.conf";
$ENV{PATH} = "$WING_DIR/bin:$ENV{PATH}";
$ENV{ANY_MOOSE} = 'Moose';

# Read the main configuration file, and supply defaults for any missing entries. Throw an
# exception if the configuration file is not found, which will prevent the container from starting
# up.

my $config = LoadFile("$MAIN_DIR/config.yml") || die "Could not read $MAIN_DIR/config.yml: $!\n";

my $ww = $config->{web_workers} || 5;
my $rw = $config->{rest_workers} || 2;

my $web_log = $config->{web_log} || 'classic_access.log';
my $rest_log = $config->{rest_log} || 'classic_rest.log';
my $error_log = $config->{main_log} || 'classic_error.log';
my $taxa_log = $config->{taxa_cached_log} || 'taxa_cached.log';

# my $process_uid = $config->{process_uid};

my $run_as = '';

# I have decided against running the sub-processes under a different uid. They should just run as
# root, like any other Docker process.

# # If we are running as root, then all of the processes we spawn should run as www-data instead.
# # In this case, make sure that all of the log files exist and have the proper ownership.

# if ( $< == 0 )
# {
#     my $process_username = 'www-data';
#     my $dummy;
#     my $uid;
#     my $gid;
    
#     if ( $process_uid )
#     {
# 	($process_username, $dummy, $uid, $gid) = getpwuid(
    
#     my ($dummy, $dummy, $uid, $gid) = getpwnam('www-data');
    
#     if ( $process_uid && $uid ne $process_uid )
#     {
# 	system("groupmod -g $process_uid www-data");
# 	system("usermod -u $process_uid -g $process_uid www-data");

# 	$uid = $process_uid;
# 	$gid = $process_uid;
#     }
    
#     if ( $uid && $gid )
#     {
# 	print STDOUT "Switching uid to www-data\n";
	
# 	$run_as = "--user $uid --group $gid;
	
# 	foreach my $logfile ( $web_log, $rest_log, $error_log, $taxa_log )
# 	{
# 	    my $filename = "/data/MyApp/logs/$logfile";
# 	    open (my $out1, ">>", $filename) || print STDOUT "ERROR: could not open $filename: $!\n";
# 	    close $out1;
# 	    chown($uid, $gid, $filename) || print STDOUT "ERROR: could not chown $filename: $!\n";
# 	}
#     }
    
#     else
#     {
# 	print STDOUT "ERROR: getpwnam('www-data'): $!\n";
#     }
# }

# Do a final check before starting: try to run the main web app, and make sure it actually
# produces useful output. If this fails, we would like to know it immediately rather than
# continually spawning failed processes.

print STDOUT "Checking that the web application runs properly...\n";

my $precheck = `perl bin/debug_web.psgi GET /classic/`;

unless ( $precheck && $precheck =~ qr{DOCTYPE html}m )
{
    print STDOUT "The application debug_web.psgi was not able to run successfully, terminating container.\n";
    exit;
}

print STDOUT "Passed.\n";

# Establish signal handlers to kill the child processes if we receive a QUIT, INT, or TERM signal.

$SIG{INT} = sub { &kill_classic('INT') };
$SIG{QUIT} = sub { &kill_classic('QUIT') };
$SIG{TERM} = sub { &kill_classic('TERM') };

# If we get here, there is a good chance that everything is fine. So start all three sub-services.

system("start_server --port 6000 --pid-file=classic_rest.pid -- starman --workers $rw $run_as --access-log=logs/$rest_log --preload-app bin/rest.psgi &");
system("start_server --port 6001 --pid-file=classic_web.pid -- starman --workers $ww $run_as --access-log=logs/$web_log --preload-app bin/web.psgi &");

unless ( $condif->{no_taxa_cached} )
{
    system("start_server --interval=10 --pid-file=taxa_cached.pid --log-file=logs/$taxa_log -- bin/taxa_cached.pl $run_as &");
}

print STDOUT "Started all services.\n";

while ( 1 )
{
    sleep(3600);
}


# The following subroutine will kill the three separate services started by this script.

sub kill_classic {

    my ($signame) = @_;
    
    my $rest_pid = `cat classic_rest.pid`;
    chomp $rest_pid;

    my $web_pid = `cat classic_web.pid`;
    chomp $web_pid;

    my $cached_pid = `cat taxa_cached.pid`;
    chomp $cached_pid;
    
    print STDERR "Shutting down on receipt of signal $signame...\n";

    print STDERR "Killing process $rest_pid\n";
    kill('TERM', $rest_pid) if $rest_pid;

    print STDERR "Killing process $web_pid\n";
    kill('TERM', $web_pid) if $web_pid;

    print STDERR "Killing process $cached_pid\n";
    kill('TERM', $cached_pid) if $cached_pid;

    exit;
}

