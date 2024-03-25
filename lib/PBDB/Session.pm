package PBDB::Session;

use strict;
use Digest::MD5;
use URI::Escape;
# use CGI::Cookie;
use PBDB::Constants qw(makeAnchor);
use Dancer qw(error);

# new ( dbt, session_id, authorizer_no, enterer_no, role, is_admin )
# 
# This is called from Classic.pm at the start of processing a request.  We need to check for the
# existence of a record in session_data corresponding to the given session_id, and if it is there
# make sure it is still valid.  The 'authorizer_no', 'role' and 'superuser' fields must be
# updated, in case any of these have changed since the last request.  If no valid session record
# is found, one must be created.

sub new {
    
    my ($class, $dbt, $wing_session, $remote_addr) = @_;
    
    # If we don't have a Wing login session, then the user hasn't logged in. So we create and
    # return a record that specifies the role of "anonymous", which is not able to do anything
    # except browse.
    
    unless ( $wing_session )
    {
	return anonymous_session($dbt);
    }
    
    # Otherwise, get the session id from the Wing session record. We will either retrieve the
    # corresponding session record from the 'session_data' table, or else create a new one.
    
    my $session_id = $wing_session->id;
    my $session_user = $wing_session->user;
    
    my $dbh = $dbt->dbh;
    my $quoted_id = $dbh->quote($session_id);
    my $sql = "	SELECT s.*, timestampdiff(day,s.record_date,now()) as days_old, a.real_name as authorizer_name
		FROM session_data as s left join pbdb_wing.users as a on a.person_no = s.authorizer_no
		WHERE session_id = $quoted_id";
    
    my ($session_record) = $dbh->selectrow_hashref( $sql, { Slice => { } } );
    
    # If there is already a record in the 'session_data' table, use it as the basis for the
    # session record.
    
    if ( $session_record )
    {
	# If for some reason the pbdb session record does not have the same user id as wing
	# session record, return an anonymous session record. This should not actually ever
	# happen, and if it does it means something has gone wrong.
	
	unless ( $session_record->{user_id} && $session_user->id eq $session_record->{user_id} )
	{
	    error('Wing session and PBDB session have different values for user_id');
	    return anonymous_session($dbt);
	}
	
	# If the record_date on the login session is more than expire_days days ago, then too much
	# time has elapsed since the last activity on this session. Redirect to the login page.
	
	if ( $session_record->{days_old} && $session_record->{expire_days} &&
	     $session_record->{days_old} >= $session_record->{expire_days} )
	{
	    $wing_session->end;
	    return error_session($dbt, 'expired');
	}
	
	# If the password_hash value in the session record is different from the current one for
	# the user, that means that the user changed their password and this session should be
	# treated as expired. The password_hash field is not otherwise needed.
	
	if ( $session_record->{password_hash} && $session_record->{password_hash} ne $session_user->password )
	{
	    $wing_session->end;
	    return error_session($dbt, 'pwchange');
	}
	
	delete $session_record->{password_hash};
	
	# If the superuser value does not match, also expire this login session. Redirect to the
	# login page.

	if ( $session_record->{superuser} && ! $session_user->get_column('admin') )
	{
	    $wing_session->end;
	    return error_session($dbt, 'admin');
	}
	
	# If the authorizer_no does not match, update the session_data entry. This may happen if
	# the user switched from one to another of their available authorizers.
	
	my $authorizer_no = $session_user->get_column('authorizer_no') || 0;
	
	if ( $authorizer_no ne $session_record->{authorizer_no} )
	{
	    my $quoted_authorizer = $dbh->quote($authorizer_no);
	    
	    $sql = "
		UPDATE session_data SET authorizer_no = $quoted_authorizer
		WHERE session_id = $quoted_id";
	    
	    my $result = $dbh->do($sql);

	    my $a = 1; # we can stop here when debugging
	}
	
	# Otherwise, just do a dummy update so that record_date is updated.
	
	else
	{
	    $dbh->do("UPDATE session_data SET record_date = now() WHERE session_id = $quoted_id");
	}
	
	# Make sure the role is 'guest' unless the user has an authorizer_no.
	
	$session_record->{role} = 'guest' unless $authorizer_no;
    }
    
    # If there is not an existing record, then make one using the information passed to us by
    # wing.
    
    else
    {
	my $user_id = $session_user->get_column('id');
	my $password_hash = $session_user->get_column('password');
	my $role = $session_user->get_column('role');
	my $expire_days = $wing_session->expire_days || 1;
	my $enterer_no = $session_user->get_column('person_no') || 0;
	my $authorizer_no = $session_user->get_column('authorizer_no') || 0;
	my $superuser = $session_user->get_column('admin') || 0;
	
	my $quoted_user = $dbh->quote($user_id);
	my $quoted_pw = $dbh->quote($password_hash);
	my $quoted_ip = $dbh->quote($remote_addr);
	my $quoted_role = $dbh->quote($role);
	my $quoted_exp = $dbh->quote($expire_days);
	my $quoted_ent = $dbh->quote($enterer_no);
	my $quoted_auth = $dbh->quote($authorizer_no);
	my $quoted_sup = $dbh->quote($superuser);
	
	my $sql = "
		INSERT INTO session_data (session_id, user_id, password_hash, ip_address, role,
		    expire_days, superuser, enterer_no, authorizer_no)
		VALUES ($quoted_id, $quoted_user, $quoted_pw, $quoted_ip, $quoted_role,
		    $quoted_exp, $quoted_sup, $quoted_ent, $quoted_auth)";
	
	$dbh->do($sql);
	
	# Create a session record with these values.
	
	$session_record = { session_id => $session_id,
			    user_id => $user_id,
			    ip_address => $remote_addr,
			    role => $role,
			    superuser => $superuser,
			    authorizer_no => $authorizer_no,
			    enterer_no => $enterer_no };
	
	# Take some time to delete stale records from the session_data cache. But wrap this in an
	# eval so it doesn't cause the database to fail if this statement fails for some reason.
	
	$sql = "DELETE FROM session_data WHERE timestampdiff(day,record_date,now()) > expire_days";
	
	eval {
	    $dbh->do($sql);
	};
    }
    
    # Add a few defaults.

    $session_record->{queue} //= '';
    $session_record->{reference_no} //= 0;
    
    # Fill in 'dbt' using the parameter we were passed.
    
    $session_record->{dbt} = $dbt;
    
    return bless $session_record;
}


sub error_session {

    my ($dbt, $reason) = @_;

    my $s = { dbt => $dbt,
	      session_id => '',
	      user_id => '',
	      role => 'anonymous',
	      reason => $reason,
	      authorizer_no => 0,
	      enterer_no => 0 };

    return bless $s;
}


sub anonymous_session {

    my ($dbt) = @_;
    
    my $s = { dbt => $dbt,
	      session_id => '',
	      user_id => '',
	      role => 'anonymous',
	      authorizer_no => 0,
	      enterer_no => 0 };
    
    return bless $s;
}


# Return the user information for the current session. If something goes wrong, print an error
# message and return an empty hash.

sub user_info {
    
    my ($s) = @_;

    my $user_info = { };
    
    eval {
	my $dbh = $s->{dbt}->dbh;
	my $quoted_id = $dbh->quote($s->{session_id});
	my $sql = "
		SELECT u.real_name, u.first_name, u.last_name, u.middle_name, u.username,
			u.email, u.institution, u.orcid
		FROM session_data as s left join pbdb_wing.users as u on u.id = s.user_id
		WHERE session_id = $quoted_id";
	
	($user_info) = $dbh->selectrow_hashref( $sql, { Slice => { } } );
    };
    
    if ( $@ )
    {
	print STDERR "Error querying user info: $@\n";
    }
    
    return $user_info;
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
    my ($session, $key) = @_;
    
    # If the key is found in the session record, return its value.
    
    if ( defined $session->{$key} )
    {
	return $session->{$key};
    }
    
    # If the variable is 'authorizer', 'enterer', 'authorizer_reversed', or 'enterer_reversed', we
    # may need to look up this information.
    
    elsif ( $key eq 'enterer' || $key eq 'enterer_name' || $key eq 'enterer_reversed' )
    {
	my $dbh = $session->{dbt}->dbh;
	my $enterer_no = $session->{enterer_no};
	
	if ( $enterer_no && $enterer_no =~ /^\d+$/ )
	{
	    my ($name, $reversed) = $dbh->selectrow_array("SELECT name, reversed_name FROM person WHERE person_no = $enterer_no");
	    
	    $session->{enterer} = $name;
	    $session->{enterer_name} = $name;
	    $session->{enterer_reversed} = $reversed;
	}
	
	else
	{
	    $session->{enterer} = $session->{enterer_name} = $session->{enterer_reversed} = '';
	}
	
	return $session->{$key};
    }
    
    elsif ( $key eq 'authorizer' || $key eq 'authorizer_name' || $key eq 'authorizer_reversed' )
    {
	my $dbh = $session->{dbt}->dbh;
	my $authorizer_no = $session->{authorizer_no};
	
	if ( $authorizer_no && $authorizer_no =~ /^\d+$/ )
	{
	    my ($name, $reversed) = $dbh->selectrow_array("SELECT name, reversed_name FROM person WHERE person_no = $authorizer_no");
	    
	    $session->{authorizer} = $name;
	    $session->{authorizer_name} = $name;
	    $session->{authorizer_reversed} = $reversed;
	}
	
	else
	{
	    $session->{authorizer} = $session->{authorizer_name} = $session->{authorizer_reversed} = '';
	}
	
	return $session->{$key};
    }
    
    elsif ( $key eq 'user_name' || $key eq 'user_reversed' )
    {
	my $dbh = $session->{dbt}->dbh;
	my $user_id = $dbh->quote($session->{user_id} || 'xxx');
	
	my ($name, $first, $last, $middle) = $dbh->selectrow_array("
		SELECT real_name, first_name, last_name, middle_name FROM pbdb_wing.users WHERE id = $user_id");
	
	$session->{user_name} = $name;
	$session->{user_reversed} = "$last, $first";
	$session->{user_reversed} .= " $middle" if $middle;
	
	return $session->{$key};
    }
    
    # Otherwise, just return the undefined value.
    
    else
    {
	return;
    }
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
    no warnings 'uninitialized';
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
