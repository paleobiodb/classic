#!/usr/bin/env perl

# written 1/2004 by rjp
# provides a global way to connect to the database.
# replaces older connection.pl file which made use of global variables including the password.

package PBDB::DBConnection;
use strict;
use DBI;
use PBDB::Constants qw(%CONFIG);
# return a handle to the database (often called $dbh)

sub connect {
    
    my $dsn;
    my $DB_DRIVER = $CONFIG{DB_DRIVER} || "mysql";
    my $MAIN_DB = $CONFIG{MAIN_DATABASE} || "pbdb";
    my $DB_SOCKET = $CONFIG{DB_SOCKET};
    my $DB_CONNECTION = $CONFIG{DB_CONNECTION};
    my $DB_USER = $CONFIG{DB_USER} || "pbdbuser";
    my $DB_PASSWD = $CONFIG{DB_PASSWD};

    if ( $DB_SOCKET )
    {
        $dsn = "DBI:$DB_DRIVER:database=$MAIN_DB;" .
	    "host=localhost;mysql_socket=$DB_SOCKET;mysql_enable_utf8=1";
    }
    
    elsif ( $DB_CONNECTION )
    {
        $dsn = "DBI:$DB_DRIVER:database=$MAIN_DB;$DB_CONNECTION;mysql_enable_utf8=1";
    }
    
    else
    {
        die "You must specify either DB_SOCKET or DB_CONNECTION in the file 'pbdb.conf'\n";
    }
    
    my $connection;
    
    unless ( $DB_PASSWD )
    {
        $DB_PASSWD = `cat /home/paleodbpasswd/passwd`;
        chomp($DB_PASSWD);  #remove the newline!  Very important!
	die "You must specify a database password.\n";
    }
    
    $connection = DBI->connect($dsn, $DB_USER, $DB_PASSWD, {RaiseError=>1}) ||
	die "Could not connect to database '$dsn' with username '$DB_USER'\n";

    $connection->{mysql_enable_utf8} = 1;
    return $connection;
}


1;

