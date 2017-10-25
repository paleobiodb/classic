#!/opt/local/bin/perl

use lib '/data/MyApp/lib', '/data/Wing/lib';

use Wing::Perl;
use Wing;
use Encode;
# use MyApp::DB::Result::User;


my ($person_no, $password) = @ARGV;

my $wing_userlist = Wing->db->resultset('User');

my ($user) = $wing_userlist->search( { person_no => $person_no } );

unless ( $user )
{
    print "User $person_no not found.\n";
    exit(1);
}

$user->encrypt_and_set_password($password);

my $real_name = $user->real_name;

print "Password for '$real_name' set to '$password'\n";
