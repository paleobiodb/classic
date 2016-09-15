
use lib '/data/MyApp/lib', '/data/Wing/lib';

use Wing::Perl;
use Wing;
use Encode;
# use MyApp::DB::Result::User;


use PBDB::DBConnection;


my $dbh = PBDB::DBConnection->connect();


my $sql = "SELECT * from person";

my ($pbdb_userlist) = $dbh->selectall_arrayref($sql, { Slice => {} });

unless ( $pbdb_userlist && ref $pbdb_userlist eq 'ARRAY' )
{
    die "Could not load user table.\n";
}

my $wing_userlist = Wing->db->resultset('User');

# $sql = "SELECT email FROM pbdb_wing.users WHERE email like 'unknown%'";

# my ($unknown_emails) = $dbh->selectcol_arrayref($sql);

# my $unknown_email_count = 1;

# foreach my $e ( @$unknown_emails )
# {
#     if ( $e =~ /unknown(\d+)/ )
#     {
# 	my $count = $1;
	
# 	if ( $unknown_email_count <= $count )
# 	{
# 	    $unknown_email_count = $count + 1;
# 	}
#     }
# }

# print STDERR "UNKNOWN_EMAIL_COUNT = $unknown_email_count\n";

my %KEY;

foreach my $pbdb_user ( @$pbdb_userlist )
{
    my $person_no = $pbdb_user->{person_no};
    my $first_name = decode_utf8( $pbdb_user->{first_name} ) || '';
    my $last_name = decode_utf8( $pbdb_user->{last_name} ) || '';
    my $middle_name = decode_utf8( $pbdb_user->{middle} ) || '';
    my $country = decode_utf8( $pbdb_user->{country} ) || '';
    my $institution = decode_utf8( $pbdb_user->{institution} ) || '';
    my $password = decode_utf8( $pbdb_user->{plaintext} || '_bad_password_' );
    my $email = $pbdb_user->{email} || '';
    my $role = 'guest';
    
    my $new_username = lc ( $first_name . $last_name );
    
    if ( $KEY{$new_username} )
    {
	print STDERR "SKIPPING DUPLICATE USERNAME $new_username (person_no = $person_no)\n";
	next;
    }
    
    $KEY{$new_username} = 1;
    
    if ( my ($wu) = $wing_userlist->search( { person_no => $pbdb_user->{person_no} } ) )
    {
	next;
    }
    
    if ( $pbdb_user->{role} =~ /auth/ )
    {
	$role = 'authorizer';
    }
    
    elsif ( $pbdb_user->{role} =~ /enter/ )
    {
	$role = 'enterer';
    }
    
    elsif ( $pbdb_user->{role} =~ /stud/ )
    {
	$role = 'student';
    }
    
    elsif ( $pbdb_user->{role} =~ /tech/ )
    {
	$role = 'technician';
    }
    
    print STDERR "person_no = $pbdb_user->{person_no}\n";
    
    my $wing_user = $wing_userlist->new({});
    
    $wing_user->username($new_username);
    $wing_user->first_name($first_name);
    $wing_user->middle_name($middle_name);
    $wing_user->last_name($last_name);
    $wing_user->person_no($pbdb_user->{person_no});
    $wing_user->email($email);
    $wing_user->encrypt_and_set_password($password);
    $wing_user->country($pbdb_user->{country} || '');
    $wing_user->institution($pbdb_user->{institution} || '');
    $wing_user->role($role);
    
    $wing_user->insert;
}





# If you do not know your user’s password, but it is either an MD5 password hash, or a Bcrypt password hash, then you can replace the encrypt_and_set_password line with:

# $user->password($password_hash_goes_here);
# $self->password_type('md5'); # or 'bcrypt'
