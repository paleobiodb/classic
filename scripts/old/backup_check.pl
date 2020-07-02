#!/usr/bin/env perl
#
# Check that the daily backup file was properly created for today.


chdir "/Volumes/backups/dailybackups";

my $pbdb_time = -M "pbdb-latest.gz";
my $wing_time = -M "pbdb-wing-latest.gz";
my $core_time = -M "pbdb-core.gz";

my $pbdb_size = -s "pbdb-latest.gz";
my $wing_size = -s "pbdb-wing-latest.gz";
my $core_size = -s "pbdb-core.gz";

if ( $pbdb_time > 1 || $wing_time > 1 || $core_time > 1 )
{
    my $pbdb_days = int($pbdb_time);
    my $wing_days = int($wing_time);
    my $core_days = int($core_time);
    
    print "WARNING: Some backup files were not created today\n";
    print "-------------------------------------------------\n";
    print "pbdb-latest.gz: $pbdb_days days late\n" if $pbdb_time > 1;
    print "pbdb-wing-latest.gz: $wing_days days late\n" if $wing_time > 1;
    print "pbdb-core.gz: $core_days days late\n" if $core_time > 1;
}

elsif ( $pbdb_size < 300000000 || $wing_size < 500000 || $core_size < 100000000 )
{
    my $pbdb_kb = sprintf("%.1f", $pbdb_size / 1024);
    my $wing_kb = sprintf("%.1f", $wing_size / 1024);
    my $core_kb = sprintf("%.1f", $core_size / 1024);
    
    print "WARNING: Some backup files are suspiciously small\n";
    print "-------------------------------------------------\n";
    print "pbdb-latest.gz: $pbdb_kb KB\n";
    print "pbdb-wing-latest.gz: $wing_kb KB\n";
    print "pbdb-core.gz: $core_kb KB\n";
}

else
{
    print "All PBDB backup files were created today.\n";
}

