#!/usr/bin/env perl
#
# This script provides necessary functionality for the Paleobiology Database. It
# must be run as a daemon. It checks for database updates of taxa and/or
# opinions, and adjusts the taxonomic hierarchy to match. It the database table
# 'tc_sync' to coordinate this activity and make sure that only a single thread
# is working at any given time.
# 
# Updated by Michael McClennen for the CCI environment, 2020-07-01. Added command-line options
# to specify a log file and which userid and groupid to run as.
# 
# Rewritten by Michael McClennen as part of a rewrite of the taxonomy code, 2023-09-23.


package taxa_cached;

# use FindBin qw($Bin);
# use lib ($Bin."/../cgi-bin");

use strict;	

use lib 'lib';

use feature 'say';

# CPAN modules

use Class::Date qw(date localdate gmdate now);
use POSIX qw(setsid strftime);
use Getopt::Long;

# PBDB modules

use PBDB::DBTransactionManager;
use PBDB::TaxaCache qw(getSyncTime setSyncTime updateCache updateOrig $DEBUG);

our ($time_to_die) = 0;

BEGIN {
    $SIG{'HUP'}  = sub { $taxa_cached::time_to_die = 1; };
    $SIG{'USR1'} = sub { $taxa_cached::time_to_die = 1; };
    $SIG{'USR2'} = sub { $taxa_cached::time_to_die = 1; };
    $SIG{'INT'}  = sub { $taxa_cached::time_to_die = 1; };
    $SIG{'KILL'} = sub { $taxa_cached::time_to_die = 1; };
    $SIG{'QUIT'} = sub { $taxa_cached::time_to_die = 1; };
    $SIG{'TERM'} = sub { $taxa_cached::time_to_die = 1; };
}

# Start by parsing options.

my ($opt_user, $opt_group, $opt_logfile);

GetOptions( "user=s" => \$opt_user,
	    "group=s" => \$opt_group,
	    "log-file=s" => \$opt_logfile );

# The arguments 'user' and 'group' specify a real and effective user and group for this process to
# become. These arguments are ignored unless the effective userid starts out as 0. We have to set
# the group first, because the operation is not permitted unless we start out as root.

if ( $opt_group && $> == 0 )
{
    my ($groupid, $dummy);
    
    if ( $opt_group =~ /^\d+$/ )
    {
	$groupid = $opt_group;
    }
    
    else
    {
	($dummy, $dummy, $groupid) = getgrnam($opt_group);
	die "Unknown group '$groupid': $!\n" unless $groupid;
    }
    
    if ( $groupid )
    {
	$( = $groupid;
	$) = $groupid;
	die "Could not change groupid to $opt_group: $!\n" unless $( == $groupid;
    }
}

if ( $opt_user && $> == 0 )
{
    my ($userid, $dummy);
    
    if ( $opt_user =~ /^\d+$/ )
    {
	$userid = $opt_user;
    }

    else
    {
	($dummy, $dummy, $userid) = getpwnam($opt_user);
	die "Unknown user '$userid': $!\n" unless $userid;
    }
    
    if ( $userid )
    {
	$> = $userid;
	$< = $userid;
	die "Could not change userid to $userid: $!\n" unless $< == $userid;
    }
}

# The option --log-file specifies that output should be written to the specified file.

if ( $opt_logfile )
{
    open(STDOUT, ">>", $opt_logfile);
    open(STDERR, ">>&STDOUT");
    STDOUT->autoflush(1);
}

#daemonize();

$DEBUG = 1;

my $DEBUG_LOOP = 0;

my $POLL_INTERVAL = 2;

my $dbt = new PBDB::DBTransactionManager();
my $dbh = $dbt->dbh;

print "Starting daemon at " . strftime('%c', localtime) . "\n";

# There should only be one process running this code at a time. Acquire a lock,
# or else exit.
    
my ($lock) = $dbh->selectrow_array("SELECT get_lock('taxa_cached', 0)");

unless ( $lock )
{
    say "There is already a taxa_cached thread running.";
    exit;
}

# Unless the auth_orig table exists, create it.

my ($check_table) = $dbh->selectrow_array("SHOW TABLES LIKE 'auth_orig'");

unless ( $check_table )
{
    my $sql = "CREATE TABLE IF NOT EXISTS auth_orig (
		`taxon_no` int unsigned not null,
		`orig_no` int unsigned not null,
		`modified` timestamp default current_timestamp on update current_timestamp,
		UNIQUE KEY (`taxon_no`),
		KEY (`orig_no`)) Engine=InnoDB";
    
    my $result = $dbh->do($sql);
    
    my $a = 1; # we can stop here when debugging
}

# Unless the check_opinions table exists, create it.

($check_table) = $dbh->selectrow_array("SHOW TABLES LIKE 'check_opinions'");

unless ( $check_table )
{
    my $sql = "CREATE TABLE IF NOT EXISTS check_opinions (
		`opinion_no` int unsigned not null,
		`child_no` int unsigned not null,
		`child_spelling_no` int unsigned not null,
		`modifier_no` int unsigned not null default '0',
		`modified` timestamp default current_timestamp,
		KEY (`modified`)) Engine=InnoDB";
    
    my $result = $dbh->do($sql);
    
    my $a = 1;	# we can stop here when debugging
}

# Go into a loop, checking for updates every $POLL_INTERVAL seconds.

while ( ! $time_to_die ) 
{
    my ($mutex) = $dbh->selectrow_array("SELECT get_lock('taxa_cache_mutex', 0)");
    
    if ( $mutex )
    {
	doUpdate();
	
	$dbh->do("DO release_lock('taxa_cache_mutex')");
    }
    
    sleep($POLL_INTERVAL);
}

($lock) = $dbh->do("DO release_lock('taxa_cached')");

print "Stopping daemon on receipt of termination signal at " . strftime('%c', localtime) . "\n";
exit 0;


# doUpdate ( )
# 
# Check for references and opinions that were added or modified since the last
# sync time.  If any are found, update the corresponding taxa.

sub doUpdate {
    
    my ($sql, $rows, @update_taxon, %uniq_taxon);
    
    my ($current_time) = $dbh->selectrow_array("SELECT current_timestamp");
    
    my ($previous_sync) = getSyncTime($dbh);
    
    # The child taxon of each recently modified opinion will be updated, and the
    # child_spelling_no taxon of each recently modified opinion will be checked
    # for entanglement.
    
    $sql = "SELECT distinct opinion_no, child_no, child_spelling_no, modified
	    FROM opinions
	    WHERE modified >= '$previous_sync' and modified < '$current_time'
	    UNION SELECT distinct opinion_no, child_no, child_spelling_no, modified
	    FROM check_opinions
	    WHERE modified >= '$previous_sync' and modified < '$current_time'
	    ORDER BY modified";
    
    say "$sql\n" if $DEBUG_LOOP;
    
    $rows = $dbh->selectall_arrayref($sql, { Slice => { } });
    
    foreach my $row (@$rows)
    {
	my $opinion_no = $row->{opinion_no};
	my $child_no = $row->{child_no};
	my $spelling_no = $row->{child_spelling_no};
	
	say "Found for update: opinion $opinion_no, child=$child_no, spelling=$spelling_no";
	
	if ( $child_no && ! $uniq_taxon{$child_no} )
	{
	    push @update_taxon, $child_no;
	    $uniq_taxon{$child_no} = 1;
	}
	
	if ( $spelling_no && ! $uniq_taxon{$spelling_no} )
	{
	    push @update_taxon, $spelling_no;
	    $uniq_taxon{$spelling_no} = 1;
	}
    }
    
    # Unless we found something to update, we are done.
    
    unless ( @update_taxon )
    {
	return;
    }
    
    # For each taxon to be updated, check its orig_no first and then
    # update taxa_tree_cache. If an exception occurs, report it. If
    # the exception occurred in updateCache, commit any work that was
    # done.
    
    foreach my $taxon_no ( @update_taxon )
    {
        say "Updating $taxon_no" if $DEBUG;
	
	eval {
	    updateOrig($dbt, $taxon_no);
	};
	
	if ( $@ )
	{
	    say "EXCEPTION from updateOrig: $@";
	}
	
	eval {
	    updateCache($dbt, $taxon_no);
	};
	
	if ( $@ )
	{
	    say "EXCEPTION from updateCache: $@";
	    # $dbh->do("COMMIT");
	}
    }
    
    # Update the synchronization time.
    
    setSyncTime($dbh, $current_time);
    say "New sync time: $current_time" if $DEBUG;
}


# sub daemonize {
#     chdir '/'                 or die "Can't chdir to /: $!";
#     open STDIN, '/dev/null'   or die "Can't read /dev/null: $!";
#     defined(my $pid = fork)   or die "Can't fork: $!";
#     exit if $pid;
#     setsid()                    or die "Can't start a new session: $!";
#     umask 0;
# }
