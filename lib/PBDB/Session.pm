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
    
    # Actually, we no longer need to do anything in this routine.
    
    my $a = 1;	# we can stop here when debugging
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
    
    my ($class, $dbt, $session_id, $user_id, $authorizer_no, $enterer_no, $role, $is_admin) = @_;
    my $dbh = $dbt->dbh;
    my $self;
    
    $is_admin ||= 0;
    
    my $result;
    
    # Make sure the role is 'guest' unless the user has an authorizer_no.
    
    $role = 'guest' unless $authorizer_no;    
    
    # If we don't have a Wing session identifier, then there is no need to add anything to
    # session_data.  We just create a record that specifies the role of "guest", which is not able
    # to do anything except browse.
    
    unless ( $session_id )
    {
    	my $s = { dbt => $dbt,
    		  session_id => '',
		  user_id => '',
    		  role => 'guest',
    		  roles => 'guest',
    		  authorizer_no => 0,
    		  enterer_no => 0,
    		};
	
	# 	print STDERR "SESSION: not logged in\n";
	
    	return bless $s;
    }
    
    # We first need to see if there is an existing record in the 'session_data' table.  If
    # so, we fetch it.  We are currently using only some of the fields in this table.  The
    # 'authorizer_no', 'authorizer', 'enterer' and 'superuser' fields of the session record are
    # set using information that comes from Wing.
    
    my $quoted_id = $dbh->quote($session_id);
    my $sql = "	SELECT session_id, user_id, queue, authorizer_no, enterer_no, reference_no,
			marine_invertebrate, micropaleontology,	paleobotany, taphonomy, vertebrate
		FROM session_data WHERE session_id = $quoted_id";
    
    my ($session_record) = $dbh->selectrow_hashref( $sql, { Slice => { } } );
    
    # If there is already a record in the 'session_data' table, check that the values match the
    # authorization information we have gotten from Wing.
    
    if ( $session_record )
    {
	if ( ! $session_record->{user_id} || $session_record->{user_id} ne $user_id )
	{
	    my $quoted_user = $dbh->quote($user_id);
	    
	    $sql = "
		UPDATE session_data SET user_id = $quoted_user
		WHERE session_id = $quoted_id";
	    
	    $result = $dbh->do($sql);
	}
	
	# If either the enterer_no or the authorizer_no do not match, update the session_data
	# entry. This probably means that the user is using the Wing facility for becoming another
	# user for testing purposes.
	
	if ( $enterer_no && $session_record->{enterer_no} ne $enterer_no )
	{
	    my $quoted_enterer = $dbh->quote($enterer_no);
	    
	    $sql = "
		UPDATE session_data SET enterer_no = $quoted_enterer
		WHERE session_id = $quoted_id";
	    
	    $result = $dbh->do($sql);
	}
	
	# Same with the authorizer_no. This may also happen if the user switched from one to
	# another of their available authorizers.
	
	if ( $authorizer_no && $session_record->{authorizer_no} ne $authorizer_no )
	{
	    my $quoted_authorizer = $dbh->quote($authorizer_no);
	    
	    $sql = "
		UPDATE session_data SET authorizer_no = $quoted_authorizer
		WHERE session_id = $quoted_id";
	    
	    $result = $dbh->do($sql);
	}
    }
    
    # If there is not an existing record, then we must make one.  Some of the fields are fetched
    # from the 'person' table corresponding to the authorizer.
    
    else
    {
	my $quoted_role = $dbh->quote($role);
	my $quoted_user = $dbh->quote($user_id || '');
	my $quoted_enterer = $dbh->quote($enterer_no || 0);
	my $quoted_authorizer = $dbh->quote($authorizer_no || 0);
	my $quoted_admin = $dbh->quote($is_admin || 0);
	
	my $sql = "
		INSERT INTO session_data (session_id, user_id, enterer_no, authorizer_no, role, superuser)
		VALUES ($quoted_id, $quoted_user, $quoted_enterer, $quoted_authorizer, $quoted_role, $quoted_admin)";
	
	$dbh->do($sql);
	
	# $sql = "UPDATE session_data JOIN person as auth on auth.person_no = session_data.authorizer_no
	# 		JOIN person as ent on ent.person_no = session_data.enterer_no
	# 	SET session_data.authorizer = auth.name, session_data.enterer = ent.name";
	
	# $dbh->do($sql);
	
	# Create a session record with these values.
	
	$session_record = { session_id => $session_id,
			    user_id => $user_id,
			    reference_no => 0,
			    queue => '' };
	
	# Try to set the field of the session record corresponding to each research group we
	# found, but wrap it in an eval so that any errors are ignored.  This whole system of
	# fixed research group field names is terrible and needs to be replaced anyway.
	
	if ( $enterer_no )
	{
	    $sql = "SELECT research_group FROM person WHERE person_no = $quoted_enterer";
	    my ($group_list) = $dbh->selectrow_array($sql);
	    
	    foreach my $group ( split qr{,}, $group_list )
	    {
		next unless $group;
		
		$session_record->{$group} = 1;
		
		$sql = "UPDATE session_data SET $group = 1 WHERE session_id = $quoted_id";
		
		eval {
		    $dbh->do($sql);
		};
	    }
	}
	
	# print STDERR "SESSION: new\n";
    }
    
    # Fill in 'dbt' using the parameter we were passed.
    
    $session_record->{dbt} = $dbt;
    
    # Now fill in the data we get from Wing.
    
    $session_record->{user_id} = $user_id;
    $session_record->{enterer_no} = $enterer_no || 0;
    $session_record->{authorizer_no} = $authorizer_no || 0;
    $session_record->{role} = $role || 'guest';
    $session_record->{superuser} = $is_admin || 0;
    
    return bless $session_record;
}



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
    my ($session, $key) = @_;
    
    # If the key is found in the session record, return its value.
    
    if ( defined $session->{$key} )
    {
	return $session->{$key};
    }
    
    # If the variable is 'authorizer', 'enterer', 'authorizer_reversed', or 'enterer_reversed', we
    # may need to look up this information.
    
    elsif ( $key eq 'authorizer' || $key eq 'enterer' )
    {
	my $dbh = $session->{dbt}->dbh;
	my $person_no = $dbh->quote($session->{$key . '_no'});
	
	my ($name) = $dbh->selectrow_array("SELECT name FROM person WHERE person_no = $person_no");
	
	$session->{$key} = $name if $name;
	return $name;
    }
    
    elsif ( $key eq 'authorizer_reversed' || $key eq 'enterer_reversed' )
    {
	my $dbh = $session->{dbt}->dbh;
	
	my $selector = $key;
	$selector =~ s/_reversed/_no/;
	my $person_no = $dbh->quote($session->{$selector});
	
	my ($name) = $dbh->selectrow_array("SELECT reversed_name FROM person WHERE person_no = $person_no");
	
	$session->{$key} = $name if $name;
	return $name;
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

sub isGuest {
    my $self = shift;
    return $self->{session_id} ? 1 : 0;
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
