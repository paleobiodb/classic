#!/opt/local/bin/perl
# 
# Add student accounts
# 

use lib "../cgi-bin";
use DBConnection;
use DBTransactionManager;
use Getopt::Std;

my $dbh = DBConnection::connect();

my ($sql, $result);
my $person_no = 1000;

foreach my $letter (A..Z)
{
    $person_no++;
    
    $sql = qq{	REPLACE INTO person (person_no, name, reversed_name, first_name, last_name, institution,
			is_authorizer, role, active, plaintext)
		VALUES ($person_no, "$letter. Authorizer", "Authorizer, $letter.", "$letter.", "Authorizer", 
			"PBDB Workshop", 1, "authorizer", 1, "workshop2013")};
    
    $result = $dbh->do($sql);
}


foreach my $letter (A..Z)
{
    $person_no++;
    
    $sql = qq{	REPLACE INTO person (person_no, name, reversed_name, first_name, last_name, institution,
			is_authorizer, role, active, plaintext)
		VALUES ($person_no, "$letter. Student", "Student, $letter.", "$letter.", "Student", 
			"PBDB Workshop", 0, "student", 1, "workshop2013")};
    
    $result = $dbh->do($sql);
}
