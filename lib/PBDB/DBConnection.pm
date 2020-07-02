#!/usr/bin/env perl

# written 1/2004 by rjp
# provides a global way to connect to the database.
# replaces older connection.pl file which made use of global variables including the password.

package PBDB::DBConnection;
use strict;
use DBI;
use PBDB::Constants qw($SQL_DB $DB_USER $DB_SOCKET $DB_CONNECTION $DB_PASSWD);
# return a handle to the database (often called $dbh)

sub connect {
    my $driver =   "mysql";
    
    my $dsn;
    if ( $DB_SOCKET )	{
        $dsn = "DBI:$driver:database=$SQL_DB;host=localhost;mysql_socket=$DB_SOCKET;mysql_enable_utf8=1";
    } elsif ( $DB_CONNECTION )	{
        $dsn = "DBI:$driver:database=$SQL_DB;$DB_CONNECTION;mysql_enable_utf8=1";
    } else	{
        die("Database connection information not found.");
    }
    
    my $connection;
    if ( $DB_PASSWD )	{
        $connection = DBI->connect($dsn, $DB_USER, $DB_PASSWD, {RaiseError=>1});
    } else	{
        my $password = `cat /home/paleodbpasswd/passwd`;
        chomp($password);  #remove the newline!  Very important!
        $connection = DBI->connect($dsn, $DB_USER, $password, {RaiseError=>1});
    }
    if (!$connection) {
        die("Could not connect to database");
    } else {
	$connection->{mysql_enable_utf8} = 1;
        return $connection;
    }
}


1;

