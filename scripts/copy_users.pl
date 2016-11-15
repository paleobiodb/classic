#!/opt/local/bin/perl
#
# The purpose of this script is to initialize the Wing user table from the
# PBDB table 'person'. It is designed to be idempotent, in other words, that
# if run more than once it has no additional effect.
# 
# This script also fills in the Wing table in which the authorizer/enterer
# relationship is stored.
# 
# Author: Michael McClennen
# Updated: 11-12-2016.

use lib '/data/MyApp/lib', '/data/Wing/lib';

use Wing::Perl;
use Wing;
use Encode;

use MyApp::DB::Result::User;
use MyApp::DB::Result::AuthEnt;

use PBDB::DBConnection;


# Declare necessary variables.

my %USERNAME_UNIQ;
my %EMAIL_UNIQ;
my @SKIP_PERSON_NO;
my @DUPLICATE_PERSON_NO;
my @CORRECT_PERSON_NO;
my %PERSON_NAME;

my %COUNTRY_CODE;
my %BAD_COUNTRY_NAME;

my $PBDB_USERLIST;
my %IS_ENTERER_FOR;

my $EMAIL_SUFFIX = 1;

# Open the log file, and print a header.

open LOGFILE, ">&STDOUT";
binmode LOGFILE, ":bytes";

&log_header;


# Start by establishing a connection to the database.  This is done using the
# database connection information in the PBDB configuration file 'pbdb.conf'.

my $dbh = PBDB::DBConnection->connect();


# Grab all entries from the PBDB 'person' table.

&read_person_table($dbh);


# Grab all country names and codes from the PBDB 'country_map' table.

&read_country_table($dbh);


# Grab all distinct authorizer/enterer pairs from the PBDB core tables.  We
# will use this to initialize the Wing authorizer/enterer relationship.

&read_authent_pairs($dbh);


# Use DBIx::Class to create objects that we can use to add rows to the Wing
# tables corresponding to classes 'User' and 'Authent'.  This is done using the
# database connection information in the Wing configuration file 'etc/wing.conf'.

my $wing_userlist = Wing->db->resultset('User');
my $wing_authents = Wing->db->resultset('AuthEnt');


# Go through the PBDB user records once, and keep track of the name
# corresponding to each person_no.

foreach  my $pbdb_user ( @$PBDB_USERLIST )
{
    $PERSON_NAME{$pbdb_user->{person_no}} = $pbdb_user->{name};
}


# Then go through the list again, copying each user over to the Wing side.
# Skip any record whose person_no value already appears in the Wing user
# table.

foreach my $pbdb_user ( @$PBDB_USERLIST )
{
    my $person_no = $pbdb_user->{person_no};
    my $email = $pbdb_user->{email} || '';
    
    # $email = decode_utf8($email);
    
    if ( my ($wu) = $wing_userlist->search( { person_no => $person_no } ) )
    {
	push @SKIP_PERSON_NO, $person_no;
	$EMAIL_UNIQ{$email} = $person_no;
	next;
    }
    
    # Grab all relevant fields from the PBDB user record.  Each of the
    # following might contain non-ASCII text, so must be encoded into UTF-8
    # before being stored in the Wing user table.
    
    my $first_name = $pbdb_user->{first_name} || '';
    my $last_name = $pbdb_user->{last_name} || '';
    my $middle_name = $pbdb_user->{middle} || '';
    my $institution = $pbdb_user->{institution} || 'none given';
    my $password = $pbdb_user->{plaintext} || '_bad_password_';
    
    # $first_name = decode_utf8($first_name);
    # $last_name = decode_utf8($last_name);
    # $middle_name = decode_utf8($middle_name);
    # $institution = decode_utf8($institution);
    # $password = decode_utf8($password);
    
    # The following fields do not need to be decoded.
    
    my $country_name = $pbdb_user->{country} || '';
    my $is_admin = $pbdb_user->{superuser} ? 1 : 0;
    my $last_login = $pbdb_user->{last_action};
    my $role;
    my ($current_authorizer_no, $current_authorizer_name);
    
    # Construct a new username for each person, by concatenating their first
    # and last name in lowercase.  If duplicates are found, add a unique numeric
    # suffix.
    
    my $new_username = lc ( $first_name . $last_name );
    
    if ( $USERNAME_UNIQ{$new_username} )
    {
	my $suffix = 1;
	
	while ( $USERNAME_UNIQ{$new_username . $suffix} )
	{
	    $suffix++;
	}
	
	$new_username .= $suffix;
    }
    
    $USERNAME_UNIQ{$new_username} = 1;
    
    # Create real_name from first_name, middle_name, and last_name.
    
    my $real_name = $first_name;
    $real_name .= " $middle_name" if $middle_name;
    $real_name .= " $last_name";
    
    # If the PBDB user record has no e-mail, make up a dummy one.
    
    unless ( $email && $email =~ /.+@.+[.].+/ )
    {
	$email = "bad_email$EMAIL_SUFFIX\@bad_email.com";
	$EMAIL_SUFFIX++;
    }
    
    # Check for e-mail uniqueness.  If we find an account whose e-mail is the
    # same as a previous one, check the number of occurrences which that
    # account has entered.  If it is zero, then skip.
    
    if ( $EMAIL_UNIQ{$email} )
    {
	my $sql = "SELECT count(*) FROM occurrences WHERE enterer_no = $person_no";

	my ($count) = $dbh->selectrow_array($sql);
	my $prev_person_no = $EMAIL_UNIQ{$email};
	
	if ( $count == 0 )
	{
	    push @DUPLICATE_PERSON_NO, "$person_no ($PERSON_NAME{$person_no}) => $prev_person_no ($PERSON_NAME{$prev_person_no})";
	    next;
	}
	
	else
	{
	    push @CORRECT_PERSON_NO, "$prev_person_no ($PERSON_NAME{$prev_person_no}) => $person_no ($PERSON_NAME{$person_no})";
	    next;
	}
    }
    
    $EMAIL_UNIQ{$email} = $person_no;
    
    # If the user's PBDB role contains 'authorizer', then their new role will
    # be 'authorizer'.  Any other roles (i.e. 'officer') will be discarded.
    
    if ( $pbdb_user->{role} =~ /auth/ )
    {
	$role = 'authorizer';
    }

    # If the user's PBDB role contains 'limited', then their new role will be
    # 'student'.
    
    elsif ( $pbdb_user->{role} =~ /limited/ )
    {
	$role = 'student';
    }
    
    # Everyone else will have the role 'enterer'.
    
    else
    {
	$role = 'enterer';
    }
    
    # Turn country names into country codes.

    my $country;
    
    if ( $country_name )
    {
	unless ( $country = $COUNTRY_CODE{$country_name} || '' )
	{
	    $BAD_COUNTRY_NAME{$country_name} = 1;
	}
    }
    
    $country ||= '';
    
    # For each authorizer that is recorded for this user as an enterer in the
    # PBDB database, add an AuthEnt object to the Wing database.  This has to
    # be done before adding the user record, so that we can select one of them
    # as the "current authorizer".
    
    my $authorizer_list = '';
    
    if ( my $authorizers = $IS_ENTERER_FOR{$person_no} )
    {
	my @authorizer_list = keys %$authorizers;
	my ($most_recent_date);
	
	foreach my $authorizer_no ( @authorizer_list )
	{
	    add_authent_pair($wing_authents, $authorizer_no, $person_no);
	    
	    my $recent_date = $authorizers->{$authorizer_no};
	    
	    if ( ! $most_recent_date || $recent_date gt $most_recent_date )
	    {
		$most_recent_date = $recent_date;
		$current_authorizer_no = $authorizer_no;
	    }
	}
	
	$authorizer_list = join(', ', map { $PERSON_NAME{$_} } @authorizer_list);
    }
    
    # Create a new Wing object of class 'User', and set its fields according
    # to the values we read in above.  Each field that might contain non-ASCII
    # data must be re-encoded in UTF-8.
    
    # $new_username = encode_utf8($new_username);
    # $real_name = encode_utf8($real_name);
    # $first_name = encode_utf8($first_name);
    # $middle_name = encode_utf8($middle_name);
    # $last_name = encode_utf8($last_name);
    # $email = encode_utf8($email);
    # $password = encode_utf8($password);
    # $institution = encode_utf8($institution);
    
    my $wing_user = $wing_userlist->new({});
    
    $wing_user->username($new_username);
    $wing_user->real_name($real_name);
    $wing_user->first_name($first_name);
    $wing_user->middle_name($middle_name);
    $wing_user->last_name($last_name);
    $wing_user->email($email);
    $wing_user->encrypt_and_set_password($password);
    $wing_user->country($country);
    $wing_user->institution($institution);
    $wing_user->person_no($person_no);
    $wing_user->role($role);
    $wing_user->contributor_status('active');
    $wing_user->use_as_display_name('real_name');
    $wing_user->admin($is_admin);
    $wing_user->last_login($last_login);
    
    if ( $role eq 'authorizer' )
    {
	$wing_user->authorizer_no($person_no);
	$current_authorizer_name = 'self';
    }
    
    elsif ( $current_authorizer_no )
    {
	$wing_user->authorizer_no($current_authorizer_no);
	$current_authorizer_name = $PERSON_NAME{$current_authorizer_no};
    }
    
    else
    {
	$current_authorizer_name = 'nobody';
    }
    
    $wing_user->insert;
    
    # Write out a log entry with all of this information.
    
    my $co = $country ? " ($country)" : "";
    my $ad = $is_admin ? " ADMIN" : "";
    
    print LOGFILE "User: $new_username => $person_no\n";
    print LOGFILE "    Name: $first_name / $middle_name / $last_name\n";
    print LOGFILE "    Email: $email\n";
    print LOGFILE "    Institution: $institution$co\n";
    print LOGFILE "    Role: $role$ad\n";
    print LOGFILE "    Authorizer: $current_authorizer_name ($authorizer_list)\n";
    print LOGFILE "\n";
}


# Now print some information about skipped entries.

if ( @SKIP_PERSON_NO )
{
    my $skip_list = join(', ', @SKIP_PERSON_NO);

    print LOGFILE "SKIPPED (person_no) BECAUSE ALREADY IN TABLE:\n\n$skip_list\n\n";
}


if ( @CORRECT_PERSON_NO )
{
    my $skip_list = join(', ', @CORRECT_PERSON_NO);

    print LOGFILE "UPDATE THE FOLLOWING person_no VALUES:\n\n$skip_list\n\n";
}


if ( @DUPLICATE_PERSON_NO )
{
    my $skip_list = join(', ', @DUPLICATE_PERSON_NO);

    print LOGFILE "SKIPPED (person_no) BECAUSE DUPLICATES ANOTHER ACCOUNT:\n\n$skip_list\n\n";
}


if ( %BAD_COUNTRY_NAME )
{
    my $bad_list = join(', ', keys %BAD_COUNTRY_NAME);

    print LOGFILE "THE FOLLOWING BAD COUNTRY NAMES WERE SKIPPED:\n\n$bad_list\n\n";
}


&log_footer;

exit;



# The following routines read data into memory from the PBDB

sub read_person_table {

    my ($dbh) = @_;
    
    my $sql = "SELECT * from person";
    
    $PBDB_USERLIST = $dbh->selectall_arrayref($sql, { Slice => {} });
    
    unless ( ref $PBDB_USERLIST eq 'ARRAY' )
    {
	die "ERROR: Could not load PBDB 'person' table.\n";
    }
}


sub read_country_table {

    my ($dbh) = @_;
    
    my $sql = "SELECT cc, name FROM country_map";
    
    my ($pbdb_countrylist) = $dbh->selectall_arrayref($sql, { Slice => {} } );
    
    unless ( ref $pbdb_countrylist eq 'ARRAY' )
    {
	warn "WARNING: Could not load PBDB 'country_map' table.\n";
	return;
    }
    
    foreach my $record ( @$pbdb_countrylist )
    {
	$COUNTRY_CODE{$record->{name}} = $record->{cc};
    }
}


sub read_authent_pairs {
    
    my ($dbh) = @_;

    read_authent_table($dbh, 'collections');
    read_authent_table($dbh, 'occurrences');
    read_authent_table($dbh, 'authorities');
    read_authent_table($dbh, 'opinions');
    read_authent_table($dbh, 'refs');
}


sub read_authent_table {

    my ($dbh, $table_name) = @_;

    my $sql = " SELECT distinct authorizer_no, enterer_no, t.created 
		FROM $table_name as t JOIN person as p on p.person_no = t.authorizer_no
		WHERE t.authorizer_no <> t.enterer_no and p.role rlike 'authorizer'";
    
    my ($pbdb_authents) = $dbh->selectall_arrayref($sql, { Slice => {} } );
    
    unless ( ref $pbdb_authents eq 'ARRAY' )
    {
	warn "WARNING: Could not load authorizer/enterers from '$table_name'";
	return;
    }
    
    foreach my $record ( @$pbdb_authents )
    {
	my $authorizer_no = $record->{authorizer_no};
	my $enterer_no = $record->{enterer_no};
	my $date_created = $record->{created};

	my $prev_date = $IS_ENTERER_FOR{$enterer_no}{$authorizer_no};
	
	if ( ! $prev_date || $date_created gt $prev_date )
	{
	    $IS_ENTERER_FOR{$enterer_no}{$authorizer_no} = $date_created;
	}
    }
}


# The following routines add data to Wing.

sub add_authent_pair {
    
    my ($wing_authents, $authorizer_no, $enterer_no) = @_;
    
    $wing_authents->find_or_create( { authorizer_no => $authorizer_no,
				      enterer_no => $enterer_no } );
    
    # my $authent_pair = $wing_authents->new({});
    
    # $authent_pair->authorizer_no($authorizer_no);
    # $authent_pair->enterer_no($person_no);
    
    # $authent_pair->insert;
}


# The following routines are used to write out the header and footer of the output.

sub log_header {
    
    my $TIMESTAMP = gmtime;
    
    print LOGFILE "========================================================================\n";
    print LOGFILE "PBDB user table import\nStart time: $TIMESTAMP\n\n";
}


sub log_footer {

    my $TIMESTAMP = gmtime;

    print LOGFILE "End time: $TIMESTAMP\n";
    print LOGFILE "========================================================================\n";
}


# The following routine is used for diagnostic purposes only.

sub printchars {
    my $name = shift;
    my $out = '';
    foreach my $a (0..length($name)-1)
    {
	my $c = substr($name, $a, 1);
	$out .= "$c " . ord($c) . "\n";
    }
    
    return $out;
}


    

# If you do not know your user’s password, but it is either an MD5 password hash, or a Bcrypt password hash, then you can replace the encrypt_and_set_password line with:

# $user->password($password_hash_goes_here);
# $self->password_type('md5'); # or 'bcrypt'
