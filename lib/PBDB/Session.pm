package PBDB::Session;

use strict;
use Digest::MD5;
use URI::Escape;
# use CGI::Cookie;
use PBDB::Constants qw($WRITE_URL $IP_MAIN $IP_BACKUP makeAnchor);
use Dancer ();


# start_login_session ( session_id, enterer_no, authorizer_no, login_role )
# 
# This is called from User.pm (MyApp/DB/Result/User.pm) when a login session is initiated.  The
# code from here has been moved to 'new' below.

sub start_login_session {
    
    my ($class, $session_id, $enterer_no, $authorizer_no, $login_role) = @_;
    
    # print STDERR "session_id = $session_id\n";
    # print STDERR "authorizer_no = $authorizer_no\n";
    # print STDERR "enterer_no = $enterer_no\n";
    # print STDERR "login_role = $login_role\n";
    
    # my $dbh = PBDB::DBConnection::connect();
    
    # unless ( $session_id && $session_id =~ qr{ ^ [0-9A-F-]+ $ }xs )
    # {
    # 	die "Error: invalid session_id\n";
    # }
    
    # unless ( $enterer_no && $enterer_no =~ qr{ ^ [0-9]+ $ }xs )
    # {
    # 	die "Error: invalid enterer_no\n";
    # }
    
    # unless ( $authorizer_no && $authorizer_no =~ qr{ ^ [0-9]+ $ }xs )
    # {
    # 	die "Error: invalid authorizer_no\n";
    # }
    
    # unless ( $login_role && $login_role =~ qr{ ^ (?: authorizer | enterer | student | guest ) $ }xs )
    # {
    # 	die "Error: invalid role\n";
    # }
    
    # my $quoted_id = $dbh->quote($session_id);
    # my $quoted_role = $dbh->quote($login_role);
    
    # my $sql = "
    # 	REPLACE INTO session_data (session_id, authorizer_no, enterer_no, role, record_date)
    # 	VALUES ($quoted_id, $authorizer_no, $enterer_no, $quoted_role, now())";
    
    # my $result = $dbh->do($sql);
    
    # $sql = "
    # 	UPDATE session_data as s join person as pa on pa.person_no = authorizer_no
    # 		join person as pe on pe.person_no = enterer_no
    # 	SET s.authorizer = pa.name,
    # 	    s.enterer = pe.name,
    # 	    s.superuser = pe.superuser,
    # 	    s.roles = s.role
    # 	WHERE session_id = $quoted_id";
    
    # $result = $dbh->do($sql);
    
    # my $a = 1;	# we can stop here when debugging
}


# end_login_session ( session_id )
# 
# This is called from User.pm (MyApp/DB/Result/User.pm) when a user logs out.  Their entry in the
# PBDB session table is removed.

sub end_login_session {
    
    my ($class, $session_id) = @_;
    
    return unless $session_id;
    
    my $dbh = PBDB::DBConnection::connect();
    
    my $quoted_id = $dbh->quote($session_id);
    
    my $sql = "DELETE FROM session_data WHERE session_id = $quoted_id";
    
    my $result = $dbh->do($sql);
    
    my $a = 1;	# we can stop here when debugging
}


# new ( dbt, session_id, authorizer_no, enterer_no, role, is_admin )
# 
# This is called from Classic.pm at the start of processing a request.  We need to check for the
# existence of a record in session_data corresponding to the given session_id, and if it is there
# make sure it is still valid.  The 'authorizer_no', 'role' and 'superuser' fields must be
# updated, in case any of these have changed since the last request.  If no valid session record
# is found, one must be created.

sub new {
    
    my ($class, $dbt, $session_id, $authorizer_no, $enterer_no, $role, $is_admin) = @_;
    my $dbh = $dbt->dbh;
    my $self;
    
    $is_admin ||= 0;
    
    # If we don't have a Wing session identifier, or if we don't have an enterer_no value
    # indicating a logged-in user, then there is no need to add anything to session_data.  We just
    # create a record that specifies the role of "guest", which is not able to do anything except
    # browse.
    
    unless ( $session_id && $enterer_no && $enterer_no =~ /^\d+$/ )
    {
	my $s = { dbt => $dbt,
		  session_id => ($session_id || ''),
		  role => 'guest',
		  roles => 'guest',
		  authorizer_no => 0,
		  enterer_no => 0,
		};
	
	# print STDERR "SESSION: guest\n";
	
	return bless $s;
    }
    
    # Otherwise, we need to see if there is an existing record in the 'session_data' table.  If
    # so, we fetch it.  We are currently using only some of the fields in this table.  The
    # 'authorizer_no', 'authorizer', 'enterer' and 'superuser' fields of the session record are
    # set using information that comes from Wing.
    
    my $quoted_id = $dbh->quote($session_id);
    my $sql = "	SELECT session_id, enterer_no, queue, reference_no, marine_invertebrate, micropaleontology,
			paleobotany, taphonomy, vertebrate, authorizer, enterer
		FROM session_data WHERE session_id = $quoted_id";
    
    my ($session_record) = $dbh->selectrow_hashref( $sql, { Slice => { } } );
    
    # If there is not an existing record, then we must make one.  Some of the fields are fetched
    # from the 'person' table corresponding to the authorizer.
    
    unless ( $session_record )
    {
	my $quoted_role = $dbh->quote($role);
	
	my $sql = "
		INSERT INTO session_data (session_id, enterer_no, authorizer_no, role, superuser)
		VALUES ($quoted_id, $enterer_no, $authorizer_no, $quoted_role, $is_admin)";
	
	$dbh->do($sql);
	
	$sql = "UPDATE session_data JOIN person as auth on auth.person_no = session_data.authorizer_no
			JOIN person as ent on ent.person_no = session_data.enterer_no
		SET session_data.authorizer = auth.name, session_data.enterer = ent.name";
	
	$dbh->do($sql);
	
	$sql = "SELECT research_group FROM person WHERE person_no = $enterer_no";
	my ($group_list) = $dbh->selectrow_array($sql);
	
	# Try to set the field of the session record corresponding to each research group we
	# found, but wrap it in an eval so that any errors are ignored.  This whole system of
	# fixed research group field names is terrible and needs to be replaced anyway.
	
	foreach my $group ( split qr{,}, $group_list )
	{
	    next unless $group;
	    
	    $sql = "UPDATE session_data SET $group = 1 WHERE session_id = $quoted_id";
	    
	    eval {
		$dbh->do($sql);
	    };
	}
	
	# Fill in the rest of the fields to their defaults.
	
	$session_record = { session_id => $session_id,
			    enterer_no => $enterer_no,
			    reference_no => 0,
			    queue => '' };
	
	# print STDERR "SESSION: new\n";
    }
    
    else
    {
	# print STDERR "SESSION: found\n";
    }
    
    # Fill in 'dbt' using the parameter we were passed.
    
    $session_record->{dbt} = $dbt;
    
    # Now fill in the data we get from Wing.
    
    $session_record->{authorizer_no} = $authorizer_no || 0;
    $session_record->{role} = $role || 'guest';
    $session_record->{superuser} = $is_admin || 0;
    
    # Make sure that 'role' is 'guest' unless we have a nonzero authorizer_no.
    
    $session_record->{role} = 'guest' unless $authorizer_no;
    
    return bless $session_record;
}


# sub new {

#     my ($class, $dbt, $session_id, $authorizer_no, $enterer_no, $role, $is_admin) = @_;
#     my $dbh = $dbt->dbh;
#     my $self;
    
#     if ($session_id) {
	
# 	my $quoted_id = $dbh->quote($session_id);
# 	# Ensure their session_id corresponds to a valid database entry
# 	my $sql = "SELECT * FROM session_data WHERE session_id=$quoted_id LIMIT 1";
# 	my $sth = $dbh->prepare( $sql ) || die ( "$sql<hr>$!" );
# 	# execute returns number of rows affected for NON-select statements
# 	# and true/false (success) for select statements.
# 	$sth->execute();
#         my $rs = $sth->fetchrow_hashref();
	
# 	if ( $authorizer_no && $rs && $rs->{authorizer_no} && $rs->{authorizer_no} ne $authorizer_no )
# 	{
# 	    # print STDERR "UPDATING SESSION authorizer_no = $authorizer_no\n";
	    
# 	    $rs->{authorizer_no} = $authorizer_no;
	    
# 	    my ($authorizer_name) = $dbh->selectrow_array("SELECT real_name FROM pbdb_wing.users WHERE person_no = $authorizer_no");
	    
# 	    $rs->{authorizer} = $authorizer_name || 'unknown';
	    
# 	    my $quoted_name = $dbh->quote($rs->{authorizer});
	    
# 	    $dbh->do("UPDATE pbdb.session_data SET authorizer_no = $authorizer_no, authorizer = $quoted_name
# 			WHERE session_id = $quoted_id");
# 	}
	
#         if($rs) {
#             # Store some values (for later)
#             foreach my $field ( keys %{$rs} ) {
#                 $self->{$field} = $rs->{$field};
#             }
#             # These are used in lots of places (anywhere with a 'Me' button), convenient to create here
#             my $authorizer_reversed = $rs->{'authorizer'};
#             $authorizer_reversed =~ s/^\s*([^\s]+)\s+([^\s]+)\s*$/$2, $1/;
#             my $enterer_reversed = $rs->{'enterer'};
#             $enterer_reversed =~ s/^\s*([^\s]+)\s+([^\s]+)\s*$/$2, $1/;
#             $self->{'authorizer_reversed'} = $authorizer_reversed;
#             $self->{'enterer_reversed'} = $enterer_reversed;    
# 	    $self->{role} = $rs->{role};
#             # Update the person data
#             # We don't bother for bristol mirror 
#             if ($ENV{'SERVER_ADDR'} eq $IP_MAIN ||
#                 $ENV{'SERVER_ADDR'} eq $IP_BACKUP) {
#                 my $sql = "UPDATE person SET last_action=NOW() WHERE person_no=$self->{enterer_no}";
#                 $dbh->do( $sql ) || die ( "$sql<HR>$!" );
#             }

#             # now update the session_data record to the current time
#             $sql = "UPDATE session_data SET record_date=NULL WHERE session_id=".$dbh->quote($session_id);
#             $dbh->do($sql);
#             $self->{'logged_in'} = 1;
#         } else {
#             $self->{'logged_in'} = 0;
#         }
# 	} else {
#         $self->{'logged_in'} = 0;
#     }
    
#     $self->{role} = $role;
#     $self->{superuser} = $is_admin ? 1 : 0;
    
#     $self->{'dbt'} = $dbt;
#     bless $self, $class;
#     return $self;
# }


# Processes the login from the submitted authorizer/enterer names.
# Creates a session_data table row if the login is valid.
#
# modified by rjp, 3/2004.
# sub processLogin {
# 	my $self = shift;
# 	my $authorizer  = shift;
#     my $enterer = shift;
#     my $password = shift;

#     my $dbt = $self->{'dbt'};
#     my $dbh = $dbt->dbh;
    
# 	my $valid = 0;


# 	# First do some housekeeping
# 	# This cleans out ALL records in session_data older than 48 hours.
# 	$self->houseCleaning( $dbh );


# 	# We want them to specify both an authorizer and an enterer
# 	# otherwise kick them out to the public site.
# 	if (!$authorizer || !$enterer || !$password) {
# 		return '';
# 	}

# 	# also check that both names exist in the database.
# 	if (! Person::checkName($dbt,$enterer) || ! Person::checkName($dbt,$authorizer)) {
# 		return '';
# 	}

#     my ($sql,@results,$authorizer_row,$enterer_row);
# 	# Get info from database on this authorizer.
# 	$sql =	"SELECT * FROM person WHERE name=".$dbh->quote($authorizer);
# 	@results =@{$dbt->getData($sql)};
# 	$authorizer_row  = $results[0];

# 	# Get info from database on this enterer.
# 	$sql =	"SELECT * FROM person WHERE name=".$dbh->quote($enterer);
# 	@results =@{$dbt->getData($sql)};
# 	$enterer_row  = $results[0];

# 	# find highest-level role JA 20.1.09
# 	# note that we are defaulting to lowest-level in cases where role
# 	#  is unknown, which is only true for people added before the
# 	#  student and technician categories were separated
# 	$enterer_row->{'roles'} = $enterer_row->{'role'};
# 	if ( $enterer_row->{'role'} =~ /authorizer/ )	{
# 		$enterer_row->{'role'} = "authorizer";
# 	} elsif ( $enterer_row->{'role'} =~ /technician/ )	{
# 		$enterer_row->{'role'} = "technician";
# 	} elsif ( $enterer_row->{'role'} =~ /student/ )	{
# 		$enterer_row->{'role'} = "student";
# 	} else	{
# 		$enterer_row->{'role'} = "limited";
# 	}
	

# 	if ($authorizer_row) {
# 		# Check the password
# 		my $db_password = $authorizer_row->{'password'};
# 		my $plaintext = $authorizer_row->{'plaintext'};
# 		if ( $enterer_row->{'password'} ne "" )	{
# 			$db_password = $enterer_row->{'password'};
# 		}
# 		if ( $enterer_row->{'plaintext'} ne "" )	{
# 			$plaintext = $enterer_row->{'plaintext'};
# 		}

# 		# First try the plain text version
# 		if ( $plaintext && $plaintext eq $password) {
# 			$valid = 1; 
# 			# If that worked but there is still an old encrypted password,
# 			#   zorch that version to make sure it is never used again
# 			#   JA 12.6.02
# 			if ($db_password ne "")	{
# 				$sql =	"UPDATE person SET password='' WHERE person_no = ".$authorizer_row->{'person_no'};
# 				$dbh->do( $sql ) || die ( "$sql<HR>$!" );
# 			}
# 		# If that didn't work and there is no plain text password,
# 		#   try the old encrypted password
# 		} elsif ($plaintext eq "") {
# 			# Legacy: Test the encrypted password
# 			# For encrypted passwords
# 			my $salt = substr ( $db_password, 0, 2);
# 			my $encryptedPassword = crypt ( $password, $salt );

# 			if ( $db_password eq $encryptedPassword ) {
# 				$valid = 1; 
# 				# Mysteriously collect their plaintext password
# 				$sql =	"UPDATE person SET password='',plaintext=".$dbh->quote($password).
# 						" WHERE person_no = ".$authorizer_row->{person_no};
# 				$dbh->do( $sql ) || die ( "$sql<HR>$!" );
# 			}
# 		}

# 		# If valid, do some stuff
# 		if ( $valid ) {
# 		    my $session_id = $self->buildSessionID();

# #             my $cookie = new CGI::Cookie(
# #                 -name    => 'session_id',
# #                 -value   => $session_id, 
# #                 -expires => '+1y',
# #                 -path    => "/",
# #                 -secure  => 0);

# 			# Store the session id (for later)
# 			$self->{session_id} = $session_id;

# 			# Are they superuser?
# 			my $superuser = 0;
# 			if ( $authorizer_row->{'superuser'} && 
#                  $authorizer_row->{'role'} =~ /authorizer/ && 
#                  $authorizer eq $enterer) {
#                  $superuser = 1; 
#             }

# 			# Insert all of the session data into a row in the session_data table
# 			# so we will still have access to it the next time the user tries to do something.
#             my %row = ('session_id'=>$session_id,
#                        'authorizer'=>$authorizer_row->{'name'},
#                        'authorizer_no'=>$authorizer_row->{'person_no'},
#                        'enterer'=>$enterer_row->{'name'},
#                        'enterer_no'=>$enterer_row->{'person_no'},
#                        'role'=>$enterer_row->{'role'},
#                        'roles'=>$enterer_row->{'roles'},
#                        'superuser'=>$superuser,
#                        'marine_invertebrate'=>$authorizer_row->{'marine_invertebrate'}, 
#                        'micropaleontology'=>$authorizer_row->{'micropaleontology'},
#                        'paleobotany'=>$authorizer_row->{'paleobotany'},
#                        'taphonomy'=>$authorizer_row->{'taphonomy'},
#                        'vertebrate'=>$authorizer_row->{'vertebrate'});

#             # Copy to the session objet
#             while (my ($k,$v) = each %row) {
#                 $self->{$k} = $v;
#             }
           
#             my $keys = join(",",keys(%row));
#             my $values = join(",",map { $dbh->quote($_) } values(%row));
            
# 			$sql =	"INSERT INTO session_data ($keys) VALUES ($values)";
# 			$dbh->do( $sql ) || die ( "$sql<HR>$!" );
	
# 		#	return $cookie;
# 		}
# 	}
# 	return "";
# }


# Handles the Guest login.  No password required.
# Anyone who passes through this routine becomes guest.
# sub processGuestLogin {
# 	my $self = shift;
#     my $dbt = $self->{'dbt'};
#     my $dbh = $dbt->dbh;
#     my $name = shift;

#     my $session_id = $self->buildSessionID();

# #     my $cookie = new CGI::Cookie(
# #         -name    => 'session_id',
# #         -value   => $session_id
# #         -expires => '+1y',
# #         -domain  => '',
# #         -path    => "/",
# #         -secure  => 0);

#     # Store the session id (for later)
#     $self->{session_id} = $session_id;

#     # The research groups are stored so as not to do many db lookups
#     $self->{enterer_no} = 0;
#     $self->{enterer} = $name;
#     $self->{authorizer_no} = 0;
#     $self->{authorizer} = $name;
    
#     # Insert all of the session data into a row in the session_data table
#     # so we will still have access to it the next time the user tries to do something.
#     #
#     my %row = ('session_id'=>$session_id,
#                'authorizer'=>$self->{'authorizer'},
#                'authorizer_no'=>$self->{'authorizer_no'},
#                'enterer'=>$self->{'enterer'},
#                'enterer_no'=>$self->{'enterer_no'});
   
#     my $keys = join(",",keys(%row));
#     my $values = join(",",map { $dbh->quote($_) } values(%row));
    
#     my $sql = "INSERT INTO session_data ($keys) VALUES ($values)";
#     $dbh->do( $sql ) || die ( "$sql<HR>$!" );

# 	#return $cookie;
# }

# sub buildSessionID {
#   my $self = shift;
#   my $md5 = Digest::MD5->new();
#   my $remote = $ENV{REMOTE_ADDR} . $ENV{REMOTE_PORT};
#   # Concatenates args: epoch, this interpreter PID, $remote (above)
#   # returned as base 64 encoded string
#   my $id = $md5->md5_base64(time, $$, $remote);
#   # replace + with -, / with _, and = with .
#   $id =~ tr|+/=|-_.|;
#   return $id;
# }

# Cleans stale entries from the session_data table.
# 48 hours is the current time considered
sub houseCleaning {
	my $self = shift;
    my $dbh = $self->{'dbt'}->dbh;

	# COULD ALSO USE 'DATE_SUB'
	my $sql = 	"DELETE FROM session_data ".
			" WHERE record_date < DATE_ADD( now(), INTERVAL -2 DAY)";
	$dbh->do( $sql ) || die ( "$sql<HR>$!" );

	# COULD ALSO USE 'DATE_SUB'
	# Nix the Guest users @ 1 day
	$sql = 	"DELETE FROM session_data ".
			" WHERE record_date < DATE_ADD( now(), INTERVAL -1 DAY) ".
			"	AND authorizer = 'Guest' ";
	$dbh->do( $sql ) || die ( "$sql<HR>$!" );
	1;
}

# Sets the reference_no
sub setReferenceNo {
    my ($self,$reference_no) = @_;
	my $dbh = $self->{'dbt'}->dbh;

	if ($reference_no =~ /^\d+$/) {
		my $sql =	"UPDATE session_data ".
				"	SET reference_no = $reference_no ".
				" WHERE session_id = ".$dbh->quote($self->get("session_id"));
		$dbh->do( $sql ) || die ( "$sql<HR>$!" );

		# Update our reference_no
		$self->{reference_no} = $reference_no;
	}
}

# A destination is used for procedural requests.  For 
# example, when requesting a ReID and you need to select
# a reference first.
sub enqueue {
    
    my ($self, $request_string, $action) = @_;
    
    if ( $action )
    {
	$request_string ||= '';
	$request_string .= "&" if $request_string;
	$request_string .= "a=$action";
    }
    
    return unless $request_string && $self->{session_id};
    
    my $dbh = $self->{dbt}->dbh;
    my $quoted_id = $dbh->quote($self->{session_id});
    
    # If an action is specified, join that to the query string
    
    # print STDERR "ENQUEUE = $request_string\n";
    
    # Add the request string to the current contents of the queue, if any.
    
    if ( $request_string )
    {
	if ( $self->{queue} )
	{
	    return if $self->{queue} eq $request_string;
	    
	    if ( $self->{queue} =~ qr{ ^ ( [^|]+ ) [|] }xs )
	    {
		return if $1 eq $request_string;
	    }
	    
	    $request_string .= "|$self->{queue}";
	}
	
	my $quoted_queue = $dbh->quote($request_string);
	
	my $sql = "UPDATE session_data SET queue=$quoted_queue WHERE session_id=$quoted_id";
	
	$dbh->do($sql);
    }
    
    # Store that in the session table
    
    # my $current_contents = "";
    
    # # Get the current contents
    # my $sql =	"SELECT queue ".
    # 			"  FROM session_data ".
    # 			" WHERE session_id = ".$dbh->quote($self->get("session_id"));
    # my $sth = $dbh->prepare( $sql ) || die ( "$sql<hr>$!" );
    # $sth->execute();

    # 	if ( $sth->rows ) {
    # 		my $rs = $sth->fetchrow_hashref ( );
    # 		$current_contents = $rs->{queue};
    # 	} 
    # 	$sth->finish();

    # 	# If there was something, tack it on the front of the queue
    # 	if ( $current_contents ) { $queue = $queue."|".$current_contents; }

    # 	$sql =	"UPDATE session_data ".
    # 			" SET queue=".$dbh->quote($queue) .
    # 			" WHERE session_id=".$dbh->quote($self->get("session_id"));
    # 	$dbh->do( $sql ) || die ( "$sql<HR>$!" );
}


sub enqueue_action {
    
    my ($self, $action, $request) = @_;
    
    return unless $action;
    
    my $action_string = "a=$action";
    
    if ( ref $request eq 'PBDB::Request' )
    {
	my (%params) = $request->Vars;
	
	foreach my $name ( keys %params )
	{
	    next if $name eq 'action' || $name eq 'a';
	    my $value = $params{$name};
	    
	    if ( ref $value eq 'ARRAY' )
	    {
		$value = join(',', @$value);
	    }
	    
	    next unless defined $value && $value ne '';
	    
	    $action_string .= "&$name=$value";
	}
    }
    
    elsif ( defined $request && ! ref $request && $request ne '' )
    {
	$action_string .= "&$request";
    }
    
    my $dbh = $self->{dbt}->dbh;
    my $quoted_id = $dbh->quote($self->{session_id});
    
    if ( $self->{queue} )
    {
	return if $self->{queue} eq $action_string;
	
	if ( $self->{queue} =~ qr{ ^ ( [^|]+ ) [|] }xs )
	{
	    return if $1 eq $action_string;
	}
	    
	$action_string .= "|$self->{queue}";
    }
    
    my $quoted_queue = $dbh->quote($action_string);
    
    my $sql = "UPDATE session_data SET queue=$quoted_queue WHERE session_id=$quoted_id";
    
    $dbh->do($sql);
}


sub dequeue {
    
    my ($self) = @_;
    
    # print STDERR "QUEUE = $self->{queue}\n";
    
    if ( $self->{queue} eq '' )
    {
	return ( );
    }
    
    my $dbh = $self->{dbt}->dbh;
    my $quoted_id = $dbh->quote($self->{session_id});	
    
    if ( $self->{queue} =~ qr{ ^ ( [^|]* ) [|] (.*) }xs )
    {
	my $entry = $1;
	
	my $rest = $dbh->quote($2);
	my $quoted_rest = $dbh->quote($rest);
	
	my $sql = "UPDATE session_data SET queue=$quoted_rest WHERE session_id=$quoted_id";
	
	$dbh->do($sql);
	
	$self->{queue} = $rest;
	return parse_queue_entry($entry);
    }

    else
    {
	my $sql = "UPDATE session_data SET queue='' WHERE session_id=$quoted_id";
	
	$dbh->do($sql);
	
	my $entry = $self->{queue};
	$self->{queue} = '';
	
	return parse_queue_entry($entry);
    }
}


sub parse_queue_entry {
    
    my ($entry) = @_;
    
    my %hash;
    my @params = split /&/, $entry;
    
    foreach my $param ( @params )
    {
	my ($name, $value) = split /=/, $param;
	
	if ( $value )
	{
	    $hash{$name} = uri_unescape($value);
	}
    }
    
    return %hash;
}


# Pulls an action off the queue
# sub unqueue {
# 	my $self = shift;
# 	my $dbh = $self->{'dbt'}->dbh;

# 	my $sql =	"SELECT queue ".
# 			"  FROM session_data ".
# 			" WHERE session_id = ".$dbh->quote($self->get("session_id"));
#     my $sth = $dbh->prepare( $sql ) || die ( "$sql<hr>$!" );
#     $sth->execute();
# 	my $rs = $sth->fetchrow_hashref();
# 	$sth->finish();
# 	my $queue = $rs->{queue};

# 	my %hash = ();
# 	if ( $queue ) {

# 		# Split into separate commands
# 		my @entries = split ( /\|/, $queue );
# 		my $entry = shift ( @entries );

# 		# Write the rest out
# 		$queue = join ( "|", @entries );
# 		$sql =	"UPDATE session_data ".
# 				"	SET queue=".$dbh->quote($queue).
# 				" WHERE session_id=".$dbh->quote($self->{'session_id'});
# 		$dbh->do( $sql ) || die ( "$sql<HR>$!" );

# 		# Parse the entry.  Since it is any valid URL, use the CGI routine.
# 		# print STDERR "$entry\n";
# 		# my $cgi = CGI->new ( $entry );

# 		# # Return it as a hash
# 		# my @names = $cgi->param();
# 		# foreach my $field ( @names ) {
# 		# 	$hash{$field} = $cgi->param($field);
# 		# }
		
# 		my @params = split /&/, $entry;
		
# 		foreach my $p ( @params )
# 		{
# 		    if ( $p =~ /([^=])+=(.*)/ )
# 		    {
# 			$hash{$1} = $2;
# 		    }
		    
# 		    elsif ( $p )
# 		    {
# 			$hash{$1} = 1;
# 		    }
# 		}
		
# 		# Save entire line in case we want it
# 		$hash{'queue'} = $queue;
# 	} 

# 	return %hash;
# }

sub clearQueue {
    
    my ($self) = @_;
    
    return unless $self->{queue} && $self->{session_id};
    
    $self->{queue} = undef;
    
    my $dbh = $self->{dbt}->dbh;
    my $quoted_id = $dbh->quote($self->{session_id});
    
    my $sql = "UPDATE session_data SET queue = NULL WHERE session_id=$quoted_id";
    $dbh->do($sql);
}


# Gets a variable from memory
sub get {
	my $self = shift;
	my $key = shift;

	return $self->{$key};
}

# Is the current user superuser?  This is true
# if the authorizer is alroy and the enterer is alroy.  
sub isSuperUser {
	my $self = shift;
    return $self->{'superuser'};
}


# Tells if we are are logged in and a valid database member
sub isDBMember {
    my $self = shift;
    return 1 if $self->{role} eq 'authorizer' || $self->{role} eq 'enterer' || $self->{role} eq 'student';
    return;
}

sub isGuest {
    my $self = shift;
    return (!$self->isDBMember());
}

sub isLoggedIn {
    my $self = shift;
    return $self->{session_id} ? 1 : 0;
}

# Display the preferences page JA 25.6.02
sub displayPreferencesPage {
    my ($dbt,$q,$s,$hbo) = @_;
    my $dbh = $dbt->dbh;
	my $select = "";
	my $destination = $q->param("destination");

	$s->enqueue_action($destination);

	my %pref = $s->getPreferences();

	my ($setFieldNames,$cleanSetFieldNames,$shownFormParts) = $s->getPrefFields();
	# Populate the form
	my @rowData;
	my @fieldNames = @{$setFieldNames};
	push @fieldNames , @{$shownFormParts};
	for my $f (@fieldNames)	{
		if ($pref{$f} ne "")	{
			push @rowData,$pref{$f};
		}
		else	{
			push @rowData,"";
		}
	}

    # Show the preferences entry page
    return $hbo->populateHTML('preferences', \@rowData, \@fieldNames);
}

# Get the current preferences JA 25.6.02
sub getPreferences	{
    my ($self,$person_no) = @_;
    if (!$person_no) {
        $person_no = $self->{enterer_no};
    }
    my $dbt = $self->{dbt};
    my $dbh = $dbt->dbh;

	my %pref;

	my $sql = "SELECT preferences FROM person WHERE person_no=".int($person_no);

	my $sth = $dbh->prepare( $sql ) || die ( "$sql<hr>$!" );
	$sth->execute();
	my @row = $sth->fetchrow_array();
	$sth->finish();
	my @prefvals = split / -:- /,$row[0];
	for my $p (@prefvals)	{
		if ($p =~ /=/)	{
			my ($a,$b) = split /=/,$p,2;
			$pref{$a} = $b;
		}
		else	{
			$pref{$p} = "yes";
		}
	}
	return %pref;
}

# Made a separate function JA 29.6.02
sub getPrefFields	{
    my ($self) = @_;
	# translations of fields in database tables, where needed
	my %cleanSetFieldNames = ("blanks" => "blank occurrence rows",
		"research_group" => "research group",
		"latdeg" => "latitude", "lngdeg" => "longitude",
		"geogscale" => "geographic resolution",
		"max_interval" => "time interval",
		"stratscale" => "stratigraphic resolution",
		"lithology1" => "primary lithology",
		"environment" => "paleoenvironment",
		"collection_type" => "collection purpose",
		"assembl_comps" => "assemblage components",
		"pres_mode" => "preservation mode",
		"coll_meth" => "collection type",
		"geogcomments" => "location details",
		"stratcomments" => "stratigraphic comments",
		"lithdescript" => "complete lithology description" );
	# list of fields in tables
	my @setFieldNames = ("blanks", "research_group", "license", "country", "state",
			"latdeg", "latdir", "lngdeg", "lngdir", "geogscale",
			"max_interval",
			"formation", "stratscale", "lithology1", "environment",
			"collection_type", "assembl_comps", "pres_mode", "coll_meth",
		# occurrence fields
			"species_name",
		# comments fields
			"geogcomments", "stratcomments", "lithdescript");
	for my $fn (@setFieldNames)	{
		if ($cleanSetFieldNames{$fn} eq "")	{
			my $cleanFN = $fn;
			$cleanFN =~ s/_/ /g;
			$cleanSetFieldNames{$fn} = $cleanFN;
		}
	}
	# options concerning display of forms, not individual fields
	my @shownFormParts = ("collection_search", "editable_collection_no",
		"genus_and_species_only", "taphonomy", "subgenera", "abundances",
		"plant_organs");
	return (\@setFieldNames,\%cleanSetFieldNames,\@shownFormParts);

}

# Set new preferences JA 25.6.02
sub setPreferences	{
    my ($dbt,$q,$s,$hbo) = @_;
    my $dbh_r = $dbt->dbh;

    my $output = qq|<center><p class="large">Your current preferences</center>
<table align=center cellpadding=4 width="80%">
<tr><td>Displayed sections</td><td>Prefilled values</td></tr>
|;

	# assembl_comps: separate with commas
	my @formVals = $q->param('assembl_comps');
	# Zorch first cell (always a null value for some reason)
	shift @formVals;
	my $numSetValues = @formVals;
	if ( $numSetValues ) {
		$q->param(assembl_comps => join(',', @formVals) );
	}

	my ($setFieldNames,$cleanSetFieldNames,$shownFormParts) = $s->getPrefFields();
    my $pref_sql = "";
	for my $i (0..$#{$setFieldNames})	{
		my $f = ${$setFieldNames}[$i];
 		if ( $q->param($f))	{
			my $val = $q->param($f);
 			$pref_sql .= " -:- $f=".$val;
		}
	}

	if ($q->param("latdir"))	{
		$q->param(latdeg => $q->param("latdeg") . " " . $q->param("latdir") );
	}
	if ($q->param("lngdir"))	{
		$q->param(lngdeg => $q->param("lngdeg") . " " . $q->param("lngdir") );
	}

	$output .= "<tr><td valign=\"top\" width=\"33%\" class=\"verysmall\">\n";
	for my $f (@{$shownFormParts})	{
		my $cleanName = $f;
		$cleanName =~ s/_/ /g;
 		if ( $q->param($f) )	{
 			$pref_sql .= " -:- " . $f;
			$output .= "<i>Show</i> $cleanName<br>\n";
 		} else	{
			$output .= "<i>Do not show</i> $cleanName<br>\n";
		}
	}
	# Are any comments stored?
	my $commentsStored;
	for my $i (0..$#{$setFieldNames})	{
		my $f = ${$setFieldNames}[$i];
		if ($q->param($f) && $f =~ /comm/)	{
			$commentsStored = 1;
		}
	}

	$output .= "</td>\n<td valign=\"top\" width=\"33%\" class=\"verysmall\">\n";
	for my $i (0..$#{$setFieldNames})	{
		my $f = ${$setFieldNames}[$i];
		if ($f =~ /^geogcomments$/)	{
			$output .= "</td></tr>\n<tr><td align=\"left\" colspan=3>\n";
			if ($commentsStored)	{
				$output .= "<p class='medium'>Comment fields</p>\n";
 			}
 		}
		elsif ($f =~ /mapsize/)	{
			$output .= qq|</td></tr>
<tr><td valign="top">Map view</td></tr>
<tr><td valign="top" class="verysmall">
|;
		}
		elsif ($f =~ /(formation)|(coastlinecolor)/)	{
			$output .= "</td><td valign=\"top\" width=\"33%\" class=\"verysmall\">\n";
		}
 		if ( $q->param($f) && $f !~ /^eml/ && $f !~ /^l..dir$/)	{
			my @letts = split //,${$cleanSetFieldNames}{$f};
			$letts[0] =~ tr/[a-z]/[A-Z]/;
			$output .= join '',@letts , " = <i>" . $q->param($f) . "</i><br>\n";
 		}
	}
	$output .= "</td></tr></table>\n";
	$pref_sql =~ s/^ -:- //;

    my $enterer_no = $s->get('enterer_no');
    if ($enterer_no) {
     	my $sql = "UPDATE person SET preferences=".$dbh_r->quote($pref_sql)." WHERE person_no=$enterer_no";
        my $result = $dbh_r->do($sql);

	    $output .= "<p>\n<center>" . makeAnchor("displayPreferencesPage", "", "Edit these preferences") . "</center>\n";
    	my %continue = $s->dequeue();
	    if($continue{action}){
		    $output .= "<center><p>\n" . makeAnchor("$continue{action}", "", "<b>Continue</b>") . "<p></center>\n";
	    }
    }
    
    return $output;
}

1;
