# Used for permissions checking to make sure the current user has permission to access each row.
# applies to collections, occurrences, and reidentifications for read permissions, and to several
# other tables for read/write and write permissions.
#
# Relies on the access_level and release_date fields of the collection table.
#

package PBDB::Permissions;

use strict;
use Carp qw(carp);
use PBDB::Debug qw(dbg);
use PBDB::Constants qw(makeFormPostTag);

#session and date objcts
use fields qw(s dbt);

# Flags and constants
my $DEBUG = 0;

# **Note: Must pass the session variable when creating this object.
sub new {
	my $class = shift;
	my PBDB::Permissions $self = fields::new($class);

	my $s = shift;		# Session object
    my $dbt = shift;    # DBTransactionManager object

	$self->{'s'} = $s;
    $self->{'dbt'} = $dbt;
	
	unless (UNIVERSAL::isa($s,'PBDB::Session')) {
		carp ("Permissions must be created with valid Session object");
		return undef;
	}
	unless (UNIVERSAL::isa($dbt,'PBDB::DBTransactionManager')) {
		carp ("Permissions must be created with valid DBTransactionManager object");
		return undef;
	}
	
	return $self;
}

# rjp note: pass it the $sth, a reference to an array of data rows, 
# a limit number, and a reference to a scalar for the number of rows.
# 
# Produces an array of rows that this person has permissions to READ
sub getReadRows {
	my $self = shift;
	
	my $sth = shift;
	my $dataRows = shift;
	my $limit = shift;
	my $ofRows = shift;
	
	my $s = $self->{'s'};

	# Get today's date in the lexical comparison format
	my $now = $self->getDate ( );

    # Get a list of authorizers who have allowed you to edit their rows as if you own them
	# my %is_modifier_for = %{$self->getModifierList()};

	# Ensure they had rd_date in the result set
	my %requiredResults = ( );
	my @requiredFields = ("authorizer_no","access_level","rd_short","research_group");
	# NAME returns a reference to an array of field (column) names.
	my @fields = @{$sth->{NAME}};
	# Compare the database column names to the required fields
	foreach my $field ( @fields ) {
		foreach my $required ( @requiredFields ) {
			if ( $field eq $required ) { $requiredResults{$field} = 1; }
		}
	}

	my $required;
	
	foreach $required ( @requiredFields ) {
		if ( ! $requiredResults{$required} ) { 
		    print STDERR "Improperly formed SQL.  Must have field [$required]\n";
		}
	}

	# Check each row returned by the database for permission.
	while ( my $row = $sth->fetchrow_hashref ( ) ) {

		my $okToRead = "";			# Clear
		my $failedReason = "";		# Clear

		if ( $s->get("superuser") == 1 ) {
			# Superuser is omniscient
			$okToRead = "superuser";
		} elsif ( $s->get("authorizer_no") == $row->{'authorizer_no'} ) {
			# If it is your row, you can see it regardless of access_level
			$okToRead = "authorizer";
            # Also if this person has given you permission to edit his data, we can always access it
		# } elsif ( $is_modifier_for{$row->{'authorizer_no'}}) { 
		# } elsif ( $s->get("role") =~ /^auth|^ent|^stud/ ) {
		# 	$okToRead = "modifier";
		} elsif ( $row->{rd_short} > $now ) {
			# Future... must do checks
			# Access level overrides the release date

			# Determine the access level
			ACCESS: {
				# Public?
				if ( $row->{access_level} eq "the public" ) { $okToRead = "public access"; last; }
	
				# DB member?
				if ( $row->{access_level} =~ /database members/i ) {
					if ($s->get("authorizer_no")) {
						$okToRead = "db member"; 
					} else {
						$failedReason = "not db member";
					}
					last; 
				}
	
				# Group member?
				if ( $row->{access_level} eq "group members" ) {
					my $researchGroup = $row->{"research_group"};
					$researchGroup =~ tr/ /_/;
					if ( $s->get($researchGroup) ) { 
						$okToRead = "group member[$researchGroup]"; 
					} else {
						$failedReason = "not group member";
					}
					last; 
				}

				# Authorizer?
				if ( $row->{access_level} eq "authorizer only" ) {
					if ( $s->get("authorizer_no") == $row->{'authorizer_no'}) {
						$okToRead = "authorizer"; 
				#	} elsif ($is_modifier_for{$row->{'authorizer_no'}}) { 
					# } elsif ( $s->get("role") =~ /^auth|^ent|^stud/ ) {
					# 	$okToRead = "modifier"; 
					} else {
						$failedReason = "not authorizer";
					}
					last;
				}
			}
		} else {
			# Past... everything public
			$okToRead = "past record";
		}

		if ( $okToRead ) {
			# May see row
			dbg ( "okToRead [".$row->{collection_no}."]: ".$row->{rd_short}." > ".$now." $okToRead",2);

			# Stow away the limit of rows (for later...)
			if ( $$ofRows < $limit ) { push ( @{$dataRows}, $row ); }
			$$ofRows++;		# This is the number of rows they could see, not the limit
		} else {
			# May not see row
	 			dbg (	"<font color='red'>".
	 					"Not ok[".$row->{collection_no}."]: ".$row->{rd_short}." > ".$now.
	 					"</font>".
	 					" al: ".$row->{access_level}.
	 					" rg: ".$row->{research_group}.
	 					" you: ".$s->get("enterer_no").
	 					" aut: ".$s->get("authorizer_no").  
	 					" pb: ".$s->get("paleobotany").
	 					$failedReason ,2);
		}
	}
}

# JA 30.6.11
# stripped-down rewrite of getReadRows intended to check a single record
# lots of recycled structure/variable naming in case getReadRows is ever
#  simplified to draw from this function
# WARNING: no check for required fields, I'm in a rush
# so, make sure to retrieve rd_short like this:
#  DATE_FORMAT(release_date, '%Y%m%d') AS rd_short
sub readPermission	{

	my $self = shift;
	# you must pass in an object with SELECT data for one collection
	my $row = shift;
	my $s = $self->{'s'};
	my $now = $self->getDate ( );
	# my %is_modifier_for = %{$self->getModifierList()};
	my ($okToRead,$failedReason);
	my $group = $row->{'research_group'};
	$group =~ s/ /_/g;
	
	if ( $s->get("superuser") == 1 ) {
	    $okToRead = "superuser";
	} elsif ( $row->{rd_short} < $now )	{
		$okToRead = "past record";
	} elsif ( $row->{access_level} eq "the public" ) {
	    $okToRead = "public";
	} elsif ( $row->{access_level} =~ /database members/i && $s->get("authorizer_no") ) {
	    $okToRead = "db member";
	} elsif ( $row->{access_level} =~ /group members/i && $s->get($group) )	{
	    $okToRead = "group member[$group]";
	} elsif ( $row->{access_level} =~ /authorizer/i ) {
	    $okToRead = 'authorizer' if $s->get("authorizer_no") == $row->{authorizer_no};
	}    
	# } elsif ( $s->get("authorizer_no") == $row->{'authorizer_no'} )	{
	# 	$okToRead = "authorizer";
	# } elsif ( $is_modifier_for{$row->{'authorizer_no'}} )	{
	return $okToRead;

}

# This function is deprecated PS 09/26/2006 - People can view stuff they can't
# write to, but an error message will pop up if they can't edit it
# Produces an array of rows that this person has permissions to WRITE
sub getWriteRows {
	my $self = shift;
	my $sth = shift;
	my $dataRows = shift;
	my $limit = shift;
	my $ofRows = shift;
	
	my $s = $self->{'s'};

	# my %is_modifier_for = %{$self->getModifierList()};

	while ( my $row = $sth->fetchrow_hashref() ) {

        return;
		my $okToWrite = "";				# Clear
		my $failedReason = "";			# Clear

		if ( $s->get("superuser") ) {
			# Superuser is omnicient
			$okToWrite = "superuser";
		} elsif ( $s->get("authorizer_no") eq $row->{'authorizer_no'} ) {
			# If it is your row, you can see it regardless of access_level
			$okToWrite = "you own it"; 
		# if the person has given you modifier priviledges, also could
		# } elsif ($is_modifier_for{$row->{'authorizer_no'}}) { 
		} elsif ( $s->get("role") =~ /^auth|^ent|^stud/ ) {
			$okToWrite = "you have modification privileges"; 
		} else {
			$failedReason = "not your row";
		}

		if ( $okToWrite ) {
			# May see row
			dbg ( "okToWrite [".$row->{collection_no}."]: $okToWrite" ,2);

			# Stow away the limit of rows (for later...)
			if ( $$ofRows < $limit ) { push ( @{$dataRows}, $row ); }
			$$ofRows++;		# This is the number of rows they could see, not the limit
		} else {
			# May not see row
	 			dbg ("<font color='red'>".
	 					"Not ok[".$row->{collection_no}."]: ".
	 					"</font>".
	 					" you: ".$s->get("enterer").
	 					" aut: ".$s->get("authorizer").  
	 					$failedReason ,2);
		}
	}
}

####
## getReadWriteRows($self, $sth)
#
#	description:	Returns ALL rows of data for the given query, and
#			includes a hash key with each row that tells whether
#			the row is readable or writeable.
#
#	arguments:	$sth - statement handle for executed query
#
#	returns:	array of hash refs of data; one hash reference
#			per row of data, including a key 'writeable'
#			that is boolean for read/write permissions on the row. 
####
sub getReadWriteRowsForEdit{
	my $self = shift;
	my $sth = shift;

	my $s = $self->{'s'};
	
	# for returning data
	my @results = ();

	# my %is_modifier_for = %{$self->getModifierList()};

	while ( my $row = $sth->fetchrow_hashref() ) {

		my $okToWrite = "";	# Clear
		my $failedReason = "";	# Clear

		if ( $s->get("superuser") ) {
			# Superuser is omnicient
			$okToWrite = "superuser";
		} elsif ( $s->get("authorizer_no") eq $row->{authorizer_no} ) { 
			# Your row: you can see it regardless of access_level
			$okToWrite = "you own it"; 
		# } elsif ($is_modifier_for{$row->{'authorizer_no'}}) { 
		} elsif ( $s->get("role") =~ /^auth|^ent|^stud/ ) {
			# if the person has given you modifier priviledges, also could
			$okToWrite = "you have modification privileges"; 
		} else {
			$failedReason = "not your row";
		}

		if($okToWrite eq ""){ $row->{'writeable'} = 0; }
		else{ $row->{'writeable'} = 1; }

		# return all data
	        push (@results, $row);

		if ( $okToWrite ) {
		    # May see row
		    dbg( "okToWrite [".$row->{collection_no}."]: $okToWrite" ,2);

		} else {
			# May not see row
	 		dbg("<font color='red'>".
	 			"Not ok[".$row->{collection_no}."]: ".
	 			"</font>".
	 			" entr: ".$s->get("enterer_no").
	 			" aut: ".$s->get("authorizer_no").  
	 			$failedReason ,2);
		}
	}
	return @results;
}

# Returns the day, month, and year
sub getDate {
	my $self = shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	return sprintf ( "%4d%02d%02d",  $year+1900, $mon+1, $mday );
}

# This returns a hashref where the keys are all the people who have let
# the authorizer edit their data. PS 08/30/2005
sub getModifierList {
    my $self = shift;
    my $s = $self->{'s'};
    my $dbt = $self->{'dbt'};

    my $sql = "SELECT authorizer_no FROM permissions WHERE modifier_no=".int($s->get('authorizer_no'));
    my @results = @{$dbt->getData($sql)};
    my %is_modifier_for = ();
    foreach my $row (@results) {
        $is_modifier_for{$row->{'authorizer_no'}} = 1;
    }
    return \%is_modifier_for;
}

# PS 08/30/2005
# The "Buddy" list - provide a list of people who have permission to edit the authorizor's collections/occurrences/etc
# And give options to add and delete from the list
sub displayPermissionListForm {
    my ($dbt,$q,$s,$hbo) = @_;
    my $output = '';
    
    # First make sure they're logged in
    my $authorizer_no = int($s->get('authorizer_no'));
    if (!$authorizer_no) {
        return "<div class=\"errorMessage\">ERROR: you must be logged in to view this page</div>";
    }


    # First provide a form to add new authoriziers to the list

    my @authorizers = @{PBDB::Person::listOfAuthorizers($dbt,1)};
    my $authList = join(",", map {'"'.PBDB::Person::reverseName($_->{'name'}).'"'} @authorizers);


    my $working_group_values = ['','decapod','divergence','GCP','marine_invertebrate','micropaleontology','PACED','paleobotany','taphonomy','vertebrate'];
    my $working_group_names =  ['','decapod','divergence','GCP','marine invertebrate','micropaleontology','PACED','paleobotany','taphonomy','vertebrate'];
    my $working_group_select = $hbo->htmlSelect('working_group',$working_group_names,$working_group_values);

    $output .= qq|<div align="center">|;
    $output .= qq|<p class="pageTitle" style="padding-top: 0.5em; padding-bottom: 0.5em;">Editing permission list</p>\n\n|;
   
    # Form for designating heir:
    my $sql = "SELECT p2.name heir FROM person p1 LEFT JOIN person p2 ON p1.heir_no=p2.person_no WHERE p1.person_no=$authorizer_no";
    my @results  = @{$dbt->getData($sql)};
    my $heir_reversed = "";
    if (@results) {
        $heir_reversed = PBDB::Person::reverseName($results[0]->{'heir'});
    }
    $output .= qq|<div class="displayPanel" align="left">\n|;
    $output .= qq|<span class="displayPanelHeader medium">Designated heir</span>\n|;
    $output .= qq|<div class="displayPanelContent" align="center">\n|;
    $output .= makeFormPostTag();
    $output .= qq|<input type="hidden" name="action" value="submitHeir">|;
    $output .= qq|<table cellpadding=0 cellspacing=3>|;
    $output .= qq|<tr><td>Designate who will manage your data <br>if you leave the database: </td><td><input type="text" name="heir_reversed" value="$heir_reversed" onKeyUp="doComplete(event,this,authorizerNames())"> <input type="submit" name="submit_heir" value="Go"></td></tr>|;
    $output .= qq|</table>|;
    $output .= qq|</form>|;



    # javascript for autocompletion
    my $javaScript = qq|<SCRIPT language="JavaScript" type="text/javascript">
                        function authorizerNames() {
                            var names = new Array($authList);
                            return names;
                        } 
                        </SCRIPT>|;
    $output .= $javaScript;    

    my @persons = ($authorizer_no);

    $sql = "SELECT person_no FROM person WHERE active=0 AND heir_no=$authorizer_no";
    @results = @{$dbt->getData($sql)};
    foreach my $row (@results) {
        push @persons,$row->{'person_no'};
    }

    # Now get a list of people who have permission to edit my data and display it
    foreach my $person_no (@persons) {
        my $sql = "SELECT p.name modifier_name, pm.modifier_no FROM person p, permissions pm WHERE p.person_no=pm.modifier_no AND pm.authorizer_no=$person_no ORDER BY p.last_name, p.first_name";
        my @results = @{$dbt->getData($sql)};
        # Now list authorizers already on the editing permissions list and give a chance to delete them
        my ($owner1,$owner2);
        if ($person_no == $authorizer_no) {
            $owner1 = "your list";
            $owner2 = "my data";
        } else {
            my $sql = "SELECT name FROM person  WHERE person_no=$person_no";
            my $person = ${$dbt->getData($sql)}[0]->{'name'};
            my $epithet = "'s";
            if ($person =~ /s$/) {
                $epithet = "'";
            }
            $owner1 = $person.$epithet." list";
            $owner2 = $person.$epithet." data";
        }
        # Form for adding people to permission list
        $output .= qq|</div>\n</div>\n\n<div class="displayPanel" align="left">\n|;
        $output .= qq|<span class="displayPanelHeader medium">Permitted modifiers</span>\n|;
        $output .= qq|<div class="displayPanelContent" align="center">\n|;
        $output .= makeFormPostTag();
        $output .= qq|<input type="hidden" name="action" value="submitPermissionList">|;
        $output .= qq|<input type="hidden" name="submit_type" value="add">|;
        $output .= qq|<input type="hidden" name="action_for" value="$person_no">|;
        $output .= qq|<table cellpadding=0 cellspacing=3>|;
        $output .= qq|<tr><td>Add an authorizer to $owner1: </td><td><input type="text" name="authorizer_reversed" onKeyUp="doComplete(event,this,authorizerNames())"> <input type="submit" name="submit_authorizer" value="Go"></td></tr>|;
        $output .= qq|<tr><td> ... <i> or </i> add all authorizers from a working group: </td><td>$working_group_select <input type="submit" name="submit_working_group" value="Go"></td></tr>|;
        $output .= qq|</table>|;
        $output .= qq|</form>|;

        $output .= makeFormPostTag();
        $output .= qq|<input type="hidden" name="action" value="submitPermissionList">|;
        $output .= qq|<input type="hidden" name="action_for" value="$person_no">|;
        $output .= qq|<input type="hidden" name="submit_type" value="delete">|;
        $output .= qq|<table cellpadding=0 cellspacing=2>|;
        $output .= qq|<tr><td colspan=2 align="center">The following people may edit $owner2:</td></tr>|;
        $output .= qq|<tr><td colspan=2 align="center">&nbsp;</td></tr>|;
        if (@results) {
            my $midpoint = int((scalar(@results) + 1)/2); # have two columns
            for(my $i=0;$i<$midpoint;$i++) {
                my $row1 = $results[$i];
                my $row2 = $results[$i+$midpoint];
                $output .= qq|<tr><td><input type="checkbox" name="modifier_no" value="$row1->{modifier_no}"> $row1->{modifier_name}</td>|;
                if ($row2) {
                    $output .= qq|<td><input type="checkbox" name="modifier_no" value="$row2->{modifier_no}"> $row2->{modifier_name}</td>|;
                }
                $output .= qq|</tr>|;
            }
            $output .= qq|<tr><td colspan=2 align="center">&nbsp;</td></tr>|;
            $output .= qq|<tr><td colspan=2 align="center"><input type="submit" name="submit" value="Delete checked"> &nbsp;&nbsp;</td></tr>|;
        } else {
            $output .= "<tr><td><i>No one else may currently edit $owner2</i></td></tr>";
        }
        $output .= qq|</table></form>|;
    }
    # print the people who have put this person on their permission list,
    #  just so they know JA 28.8.06
    $sql = "SELECT p.name authorizer_name, pm.authorizer_no FROM person p, permissions pm WHERE p.person_no=pm.authorizer_no AND pm.modifier_no=$authorizer_no ORDER BY p.last_name, p.first_name";
    @results = @{$dbt->getData($sql)};
    if (@results) {
        $output .= qq|</div>\n</div>\n\n<div class="displayPanel" align="left">\n|;
        $output .= qq|<span class="displayPanelHeader medium">Permitted authorizers</span>\n|;
        $output .= qq|<div class="displayPanelContent" align="center">\n|;
        $output .= qq|<p>The following people have allowed you to edit their data:</p>\n|;
        $output .= qq|<table cellpadding=0 cellspacing=2 style="padding-bottom: 1em;">|;
        my $midpoint = int((scalar(@results) + 1)/2); # have two columns
        for(my $i=0;$i<$midpoint;$i++) {
            my $row1 = $results[$i];
            my $row2 = $results[$i+$midpoint];
            $output .= "<tr><td style=\"padding-right: 2em;\">$row1->{authorizer_name}</td>\n";
            if ($row2) {
                $output .= "<td>$row2->{authorizer_name}</td>\n";
            }
            $output .= "</tr>\n";
        }
        $output .= qq|</table>\n|;
    }
    $output .= qq|</div>\n|;
    $output .= qq|</div>\n|;
    $output .= qq|</div>\n|;
    
    return $output;
}   

# This handles form submission from displayPermissionListForm
# Basically only two types of operations: add and delete
# Both should be pretty straightforward
sub submitPermissionList {
    my ($dbt,$q,$s,$hbo) = @_;
    my $dbh = $dbt->dbh;
    # First make sure they're logged in
    my $authorizer_no = int($s->get('authorizer_no'));
    if (!$authorizer_no) {
        return "<div class=\"errorMessage\">ERROR: you must be logged in to view this page</div>";
    }

    my $action_for = $q->param('action_for');

    # A person can set permissions for himself, as well as all inactive members thats have designated him as the heir
    my $sql = "SELECT person_no FROM person WHERE active=0 AND heir_no=$authorizer_no";
    my @results = @{$dbt->getData($sql)};
    my  %can_set_list_for = ();
    $can_set_list_for{$authorizer_no} = 1;
    foreach my $row (@results) {
        $can_set_list_for{$row->{'person_no'}} = 1;
    }  

    if (!$can_set_list_for{$action_for}) {
        return "<div class=\"errorMessage\">ERROR: can't set the permission list for that person</div>";
    }
    

    if ($q->param('submit_type') eq 'add') {
        if ($q->param('submit_authorizer')) {
        # reverse the name if it's reversed, but don't if it's in standard order
        #  JA 30.8.06
            if ($q->param("authorizer_reversed") !~ /(, ).*\.$/ ) {
                $q->param("authorizer_reversed" => PBDB::Person::reverseName($q->param("authorizer_reversed")));
            }
            my $sql = "SELECT person_no FROM person WHERE name LIKE ".$dbh->quote(PBDB::Person::reverseName($q->param('authorizer_reversed')));
            my $row = ${$dbt->getData($sql)}[0];
            if ($row) {
                if ($row->{'person_no'} != $action_for) {
                    # Note: the IGNORE just causes mysql to not throw an error when inserting a dupe
                    $sql = "INSERT IGNORE INTO permissions (authorizer_no,modifier_no) VALUES ($action_for,$row->{person_no})";
                    dbg("Inserting into permission list: ".$sql);
                    $dbh->do($sql);
                }
            }
        } elsif ($q->param('submit_working_group') && $q->param('working_group')) {
            my $working_group = $q->param('working_group');
            $working_group =~ s/[^a-zA-Z_]//g;
            my $sql = "SELECT person_no FROM person WHERE research_group like '%$working_group%'";
            my @persons = @{$dbt->getData($sql)};
            foreach my $row (@persons) {
                if ($row->{'person_no'} != $action_for) {
                    # Note: the IGNORE just causes mysql to not throw an error when inserting a dupe
                    $sql = "INSERT IGNORE INTO permissions (authorizer_no,modifier_no) VALUES ($action_for,$row->{person_no})";
                    dbg("Inserting into permission list: ".$sql);
                    $dbh->do($sql);
                }
            }
        }
    } elsif ($q->param('submit_type') eq 'delete') {
        my @modifiers = $q->numeric_param('modifier_no');
        foreach my $modifier_no (@modifiers) {
            my $sql = "DELETE FROM permissions WHERE authorizer_no=$action_for AND modifier_no=$modifier_no";
            dbg("Deleting from permission list: ".$sql);
            $dbh->do($sql);
        }

    }

    return displayPermissionListForm($dbt,$q,$s,$hbo);
}   

# This handles form submission from displayPermissionListForm
# Basically only two types of operations: add and delete
# Both should be pretty straightforward
sub submitHeir {
    my ($dbt,$q,$s,$hbo) = @_;
    my $dbh = $dbt->dbh;
    my $output = '';
    
    # First make sure they're logged in
    my $authorizer_no = int($s->get('authorizer_no'));
    if (!$authorizer_no) {
        return "<div class=\"errorMessage\">ERROR: you must be logged in to do this</div>";
    }

    # reverse the name if it's reversed, but don't if it's in standard order
    #  JA 30.8.06
    if ($q->param("heir_reversed") !~ /(, ).*\.$/ ) {
        $q->param("heir_reversed" => PBDB::Person::reverseName($q->param("heir_reversed")));
    }

    if ($q->param("heir_reversed")) {
        my $sql = "SELECT person_no FROM person WHERE name LIKE ".$dbh->quote(PBDB::Person::reverseName($q->param('heir_reversed')));
        my $row = ${$dbt->getData($sql)}[0];
        if ($row) {
            # Note: the IGNORE just causes mysql to not throw an error when inserting a dupe
            $sql = "UPDATE person SET heir_no=$row->{'person_no'} WHERE person_no=$authorizer_no";
            dbg("Updating heir: ".$sql);
            my $return = $dbh->do($sql);
            if ($return) {
                my ($last,$init) = split(/,/,$q->param('heir_reversed'));
                $output .= "<div class=\"warning\">Your future data manager has been set to $init $last</div>";
            } else {
                $output .= "<div class=\"errorMessage\">ERROR: could update database, please submit a bug report</div>";
            }
        } else {
            $output .= "<div class=\"errorMessage\">ERROR: could not set your future data manager, ".$q->param("heir_reversed"). " not found in the database</div>";
        }
    } else {
        # Note: the IGNORE just causes mysql to not throw an error when inserting a dupe
        my $sql = "UPDATE person SET heir_no=0 WHERE person_no=$authorizer_no";
        dbg("Updating heir: ".$sql);
        my $return = $dbh->do($sql);
        if ($return) {
            $output .= "<div class=\"warning\">Your future data manager has been set to no one</div>";
        } else {
            $output .= "<div class=\"errorMessage\">ERROR: could not update database, please submit a bug report</div>";
        }
    }

    $output .= displayPermissionListForm($dbt,$q,$s,$hbo);
    
    return $output;
}   


# # This only shown for internal errors
# sub htmlError {
# 	my $self = shift;
#     my $message = shift;

#     print $message;
#     exit 1;
# }

1;
