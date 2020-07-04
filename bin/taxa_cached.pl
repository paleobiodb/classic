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
use POSIX qw(setsid);
use Getopt::Long;

# PBDB modules
use PBDB::DBTransactionManager;
use PBDB::TaxaCache;

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

my $DEBUG = 1;
my $POLL_TIME = 2;
my $dbt = new PBDB::DBTransactionManager();
my $dbh = $dbt->dbh;

$taxa_cached::sync_time = PBDB::TaxaCache::getSyncTime($dbt);
$taxa_cached::in_update = 0;
$taxa_cached::time_to_die = 0;

print "Starting daemon at ";
system("date");

while(1) {
    doUpdate();
    if ($taxa_cached::time_to_die) {
        print "got termination signal, dying\n" if ($DEBUG);
        exit 0;
    }
    sleep($POLL_TIME);
}

sub doUpdate {
    if ($taxa_cached::in_update) {
        print "already being updated\n" if ($DEBUG);
        return;
    } else {
        $taxa_cached::in_update = 1;
    }
    my %to_update = ();
    my $sql = "SELECT DISTINCT o.child_no,r.modified FROM refs r, opinions o WHERE r.reference_no=o.reference_no AND r.modified > '$taxa_cached::sync_time'";
    print $sql."\n" if ($DEBUG > 1);
    my $rows = $dbt->getData($sql);
    foreach my $row (@$rows) {
        $to_update{$row->{'child_no'}} = $row->{'modified'};
    }
    my $sql = "SELECT DISTINCT o.child_no,o.modified FROM opinions o WHERE o.modified > '$taxa_cached::sync_time'";
    print $sql."\n" if ($DEBUG > 1);
    $rows = $dbt->getData($sql);
    foreach my $row (@$rows) {
        if ($to_update{$row->{'child_no'}}) {
            if ($row->{'modified'} ge $to_update{$row->{'child_no'}}) {
                $to_update{$row->{'child_no'}} = $row->{'modified'};
            }
        } else {
            $to_update{$row->{'child_no'}} = $row->{'modified'};
        }
    }
    my @taxon_nos = sort {$to_update{$a} cmp $to_update{$b}} keys %to_update;
    print "running: found ".scalar(@taxon_nos)." to update\n" if $DEBUG and scalar(@taxon_nos);
    for(my $i = 0;$i< @taxon_nos;$i++) {
        my $taxon_no = $taxon_nos[$i];
        my $ts = $to_update{$taxon_no};
        print "updating $taxon_no:$ts\n" if ($DEBUG);
        PBDB::TaxaCache::updateCache($dbt,$taxon_no);
        my $ts = $to_update{$taxon_no};

        my $next_ts = undef;
        if (($i+1) < @taxon_nos) {
            $next_ts = $to_update{$taxon_nos[$i+1]};
        }

        # If the next record was updated in the same second as current, wait on
        # updating the tc_sync table
        unless ($next_ts && $next_ts eq $ts) {
            PBDB::TaxaCache::setSyncTime($dbt,$ts);
            $taxa_cached::sync_time = $ts;
            print "new sync time $taxa_cached::sync_time\n" if ($DEBUG);
        }
    }
    $taxa_cached::in_update = 0;
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
