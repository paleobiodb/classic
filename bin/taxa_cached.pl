#!/usr/bin/env perl
#
# This script provides necessary functionality for the Paleobiology Database. It must be
# run as a daemon. It checks for database updates of taxa and/or opinions, and adjusts the
# taxonomic hierarchy to match. It uses the two database tables 'tc_mutex' and 'tc_sync' to
# coordinate this activity and make sure that only a single thread is working at any given
# time.
#
# Updated by Michael McClennen for the CCI environment, 2020-07-01. Added command-line options
# to specify a log file and which userid and groupid to run as.


package taxa_cached;

# use FindBin qw($Bin);
# use lib ($Bin."/../cgi-bin");

use strict;	

use lib 'lib';

# CPAN modules

use Class::Date qw(date localdate gmdate now);
use POSIX qw(setsid strftime);
use Getopt::Long;

# PBDB modules

use PBDB::DBTransactionManager;
use PBDB::TaxaCache qw(getSyncTime setSyncTime updateCache updateEntanglement $DEBUG);

our ($time_to_die) = 0;

BEGIN {
    $SIG{'HUP'}  = \&doUpdate;
    $SIG{'USR1'} = \&doUpdate;
    $SIG{'USR2'} = \&doUpdate;
    $SIG{'INT'}  = sub { $taxa_cached::time_to_die = 1;};
    $SIG{'KILL'} = sub { $taxa_cached::time_to_die = 1;};
    $SIG{'QUIT'} = sub { $taxa_cached::time_to_die = 1;};
    $SIG{'TERM'} = sub { $taxa_cached::time_to_die = 1;};
}

# Start by parsing options.

my ($opt_user, $opt_group, $opt_logfile);

GetOptions( "user=s" => \$opt_user,
	    "group=s" => \$opt_group,
	    "log=s" => \$opt_logfile );

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

# The argument 'log' specifies that output should be written to the specified file.

if ( $opt_logfile )
{
    open(STDOUT, ">>", $opt_logfile);
    open(STDERR, ">>&STDOUT");
}

#daemonize();

my $DEBUG_LOOP = 0;

my $POLL_TIME = 2;

my $dbt = new PBDB::DBTransactionManager();
my $dbh = $dbt->dbh;

print "Starting daemon at " . strftime('%c', localtime) . "\n";

# Unless the auth_orig table exists, create it.

my ($check_table) = $dbh->selectrow_array("SHOW TABLES LIKE 'auth_orig'");

unless ( $check_table )
{
    my $sql = "CREATE TABLE IF NOT EXISTS auth_orig (
		`taxon_no` int unsigned not null,
		`orig_no` int unsigned not null,
		UNIQUE KEY (`taxon_no`),
		KEY (`orig_no`)) Engine=InnoDB";
    
    my $result = $dbh->do($sql);
    
    my $a = 1; # we can stop here when debugging
}

# Go into a loop, checking for updates every $POLL_TIME seconds.

while ( 1 ) 
{
    doUpdate();
    
    if ($time_to_die)
    {
	print "Stopping daemon on receipt of termination signal at " . strftime('%c', localtime) . "\n";
        exit 0;
    }
    
    sleep($POLL_TIME);
}


# doUpdate ( )
# 
# Check for references and opinions that were added or modified since the last
# sync time.  If any are found, update the corresponding taxa.

sub doUpdate {
    
    my ($sql, %update_taxon, %update_entanglement);
    
    my $update_time = strftime('%c', localtime);
    
    my $last_timestamp;
    my $queue_not_empty;
    
    # For any opinion associated with a recently modified reference, if that
    # opinion does not specify a basis then update its child taxon just in case
    # the basis specified in the reference has changed.
    
    my $sync_time = getSyncTime($dbh);
    
    $sql = "SELECT DISTINCT o.child_no, o.child_spelling_no, r.modified
		FROM opinions as o join refs as r using (reference_no)
		WHERE r.modified > '$sync_time' and (o.basis is null or o.basis = '')";
    
    print "$sql\n" if $DEBUG_LOOP;
    
    my $rows = $dbt->getData($sql);
    
    foreach my $row (@$rows)
    {
	if ( $row->{child_no} )
	{
	    $update_taxon{$row->{child_no}} = $row->{modified};
	}
	
	if ( ! $last_timestamp || $row->{modified} gt $last_timestamp )
	{
	    $last_timestamp = $row->{modified};
	}
    }
    
    # The child taxon of each recently modified opinion will be updated, and the
    # child_spelling_no taxon of each recently modified opinion will be checked
    # for entanglement.
    
    $sql = "SELECT DISTINCT o.child_no, o.child_spelling_no, o.modified
		FROM opinions as o WHERE o.modified > '$sync_time'";
    
    print "$sql\n" if $DEBUG_LOOP;
    
    $rows = $dbh->selectall_arrayref($sql, { Slice => { } });
    
    foreach my $row (@$rows)
    {
	if ( $row->{child_no} && $update_taxon{$row->{child_no}} )
	{
	    $update_taxon{$row->{child_no}} = $row->{modified} if
		$row->{modified} gt $update_taxon{$row->{child_no}};
	}
	
	elsif ( $row->{child_no} )
	{
	    $update_taxon{$row->{child_no}} = $row->{modified};
	}
	
	if ( $row->{child_spelling_no} )
	{
	    $update_entanglement{$row->{child_spelling_no}} = 1;
	}
	
	if ( ! $last_timestamp || $row->{modified} gt $last_timestamp )
	{
	    $last_timestamp = $row->{modified};
	}
    }
    
    # If we found something, update the sync time.
    
    if ( %update_taxon )
    {
	setSyncTime($dbh, $last_timestamp);
	print "New sync time: $last_timestamp\n" if $DEBUG;
    }
    
    # Otherwise, return immediately and wait for the next poll.
    
    else
    {
	return;
    }
    
    # # original Schroeter comment: This table doesn't have any rows in it - it
    # # acts as a mutex so writes to the taxa_tree_cache table will be serialized,
    # # which is important to prevent corruption.  Note reads can still happen
    # # concurrently with the writes, but any additional writes beyond the first
    # # will block on this mutex Don't respect mutexes more than 1 minute old,
    # # this script shouldn't execute for more than about 15 seconds
    
    # my $had_to_wait;
    
    # while (1)
    # {
    #     if ( @{$dbt->getData("SELECT * FROM tc_mutex WHERE created > NOW() - INTERVAL 1 minute")} )
    # 	{
    # 	    $had_to_wait = 1;
    #         sleep(1);
    #     }
	
    # 	else
    # 	{
    #         $dbh->do("INSERT INTO tc_mutex (mutex_id,created) VALUES ($$,NOW())");
    # 	    print "Acquired lock at $update_time after waiting\n" if $had_to_wait;
    #         last;
    #     }
    # }
    
    # Sort the list of taxa to update according to the modification
    # timestamp on the opinion or reference (whichever is later).
    
    my @taxon_nos = sort {$update_taxon{$a} cmp $update_taxon{$b}} keys %update_taxon;
    
    print "Found " . scalar(@taxon_nos) . " taxa to update at $update_time\n";
    
    # If we have any taxa from the child_spelling_no field of modified opinions,
    # check them for entanglement unless they will be taken care of below.
    
    foreach my $child_spelling_no ( keys %update_entanglement )
    {
	unless ( $update_taxon{$child_spelling_no} )
	{
	    print "Updating entanglement for $child_spelling_no:\n" if $DEBUG;;
	    
	    eval {
		updateEntanglement($dbt, $child_spelling_no);
	    };
	    
	    if ( $@ )
	    {
		print "EXCEPTION from updateEntanglement: $@\n";
	    }
	}
    }
    
    # For each taxon to be updated, update its entanglement first and
    # then update taxa_tree_cache. If an exception occurs, report it.
    # If the exception occurred in updateCache, commit any work that
    # was done.
    
    foreach my $taxon_no ( @taxon_nos )
    {
        print "Updating $taxon_no:\n" if $DEBUG > 1;
	
	eval {
	    updateEntanglement($dbt, $taxon_no) unless $update_entanglement{$taxon_no};
	};
	
	if ( $@ )
	{
	    print "EXCEPTION from updateEntanglement: $@\n";
	}
	
	eval {
	    updateCache($dbt, $taxon_no);
	};
	
	if ( $@ )
	{
	    print "EXCEPTION from updateCache: $@\n";
	    $dbh->do("COMMIT");
	}
    }
    
    # # Release the lock.
    
    # $dbh->do("DELETE FROM tc_mutex");
}


sub daemonize {
    chdir '/'                 or die "Can't chdir to /: $!";
    #open STDOUT, '>>/home/peters/testd.log' or die "Can't write to log: $!";
    #open STDERR, '>>/home/peters/testd_err.log' or die "Can't write to errlog: $!";
    open STDIN, '/dev/null'   or die "Can't read /dev/null: $!";
#    open STDOUT, '>>/dev/null' or die "Can't write to /dev/null: $!";
#    open STDERR, '>>/dev/null' or die "Can't write to /dev/null: $!";
    defined(my $pid = fork)   or die "Can't fork: $!";
    exit if $pid;
    setsid()                    or die "Can't start a new session: $!";
    umask 0;
}
