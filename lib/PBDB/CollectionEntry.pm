# includes entry functions extracted from Collection.pm JA 4.6.13

package PBDB::CollectionEntry;
use strict;

use lib '/data/MyApp/lib/PBData';
use TableDefs qw($INTERVAL_DATA);
use PBDB::PBDBUtil;
use PBDB::Taxon;
use PBDB::TaxonInfo;
use PBDB::Map;
use PBDB::Collection;
use PBDB::TaxaCache;
use PBDB::Person;
use PBDB::Permissions;
use PBDB::Reference;
use PBDB::ReferenceEntry;
use PBDB::Reclassify;
use Class::Date qw(now date);
use PBDB::Debug qw(dbg);
use URI::Escape;    
use PBDB::Constants qw($INTERVAL_URL $TAXA_TREE_CACHE $COLLECTIONS makeAnchor makeFormPostTag);

use IntervalBase qw(int_defined int_name int_bounds int_correlation interval_nos_by_age);
use POSIX qw(floor);

use TableDefs qw($COLL_MATRIX $COUNTRY_MAP $COLL_LOC $INTERVAL_DATA);

# this is a shell function that will have to be replaced with something new
#  because PBDB::Collection::getCollections is going with Fossilworks JA 4.6.13
sub getCollections	{
	my $dbt = $_[0];
	my $s = $_[1];
	my $dbh = $dbt->dbh;
	my %options = %{$_[2]};
	my @fields = @{$_[3]};
	return (PBDB::Collection::getCollections($dbt,$s,\%options,\@fields));
}

# JA 4.6.13
# this is actually a near-complete rewrite of PBDB::Collection::getClassOrderFamily
#  that uses a simpler algorithm and exists strictly to enable the detangling
#  of the codebases
# it's expecting a prefabricated array of objects including the parent names,
#  numbers, and ranks
sub getClassOrderFamily	{
	my ($dbt,$rowref_ref,$class_array_ref) = @_;
	my $rowref;
	if ( $rowref_ref )	{
		$rowref = ${$rowref_ref};
	}
	my @class_array = @{$class_array_ref};
	if ( $#class_array == 0 )	{
		return $rowref;
	}
	for my $t ( @class_array )	{
		if ( $t->{taxon_rank} =~ /^(class|order|family|common_name)$/ )	{
			my $rank = $t->{taxon_rank};
			$rowref->{$rank} = $t->{taxon_name};
			$rowref->{$rank."_no"} = $t->{taxon_no};
		}
	}
	return $rowref;
}

# This is a multi step process: 
# First populate our page variables with prefs, these have the lowest priority
# TBD CHeck for reerence no
sub displayCollectionForm {
    my ($dbt,$q,$s,$hbo) = @_;
    my $dbh = $dbt->dbh;
    my $output = '';

    my $isNewEntry = $q->numeric_param('collection_no') ? 0 : 1;
    my $reSubmission = ($q->param('action') =~ /processCollectionForm/) ? 1 : 0;

    # First check to nake sure they have a reference no for new entries
    my $session_ref = $s->get('reference_no');
    if ($isNewEntry) {
        if (!$session_ref) {
            $s->enqueue_action('displayColectionForm', $q);
            return PBDB::displaySearchRefs($q, $s, $dbt, $hbo, "<center>Please choose a reference first</center>" );
        }  
    }

    # First get all three sources of data: form submision (%form), prefs (%prefs), and database (%row)
    my %vars = ();

    my %row = ();
    if (!$isNewEntry) {
        my $collection_no = $q->numeric_param('collection_no');
        my $sql = "SELECT * FROM collections WHERE collection_no=$collection_no";
        my $c_row = ${$dbt->getData($sql)}[0] or die "invalid collection no";
        %row = %{$c_row};
    }
    my %prefs =  $s->getPreferences();
    my %form = $q->Vars();


    if ($reSubmission) {
        %vars = %form;
    } if ($isNewEntry && $q->numeric_param('prefill_collection_no')) {
        my $collection_no = $q->numeric_param('prefill_collection_no');
        my $sql = "SELECT * FROM collections WHERE collection_no=$collection_no";
        my $row = ${$dbt->getData($sql)}[0] or die "invalid collection no";
        foreach my $field (keys(%$row)) {
            if ($field =~ /^(authorizer|enterer|modifier|authorizer_no|enterer_no|modifier_no|created|modified|collection_no)/) {
                delete $row->{$field};
            }
        }
        %vars = %$row;
        $vars{'reference_no'} = $s->get('reference_no');
    } elsif ($isNewEntry) {
        %vars = %prefs; 
        # carry over the lat/long coordinates the user entered while doing
        #  the mandatory collection search JA 6.4.04
        my @coordfields = ("latdeg","latmin","latsec","latdec","latdir","lngdeg","lngmin","lngsec","lngdec","lngdir");
        foreach my $cf (@coordfields) {
            $vars{$cf} = $form{$cf};
        }
        $vars{'reference_no'} = $s->get('reference_no');
    } else {
        %vars = %row;
    }

    ($vars{'sharealike'},$vars{'noderivs'},$vars{'noncommercial'}) = ('','Y','Y');
    if ( $vars{'license'} =~ /SA/ )	{
        $vars{'sharealike'} = 'Y';
    }
    if ( $vars{'license'} !~ /ND/ )	{
        $vars{'noderivs'} = '';
    }
    if ( $vars{'license'} !~ /NC/ )	{
        $vars{'noncommercial'} = '';
    }
    
    # always carry over optional fields
    $vars{'taphonomy'} = $prefs{'taphonomy'};
    $vars{'use_primary'} = $q->param('use_primary');

    my $ref = PBDB::Reference::getReference($dbt,$vars{'reference_no'});
    my $formatted_primary = PBDB::Reference::formatLongRef($ref);

    $vars{'ref_string'} = '<table cellspacing="0" cellpadding="2" width="100%"><tr>'.
    "<td valign=\"top\">" . makeAnchor("app/refs", "#display=$vars{reference_no}", "$vars{'reference_no'}") . ".</b>&nbsp;</td>".
    "<td valign=\"top\"><span class=red>$ref->{project_name} $ref->{project_ref_no}</span></td>".
    "<td>$formatted_primary</td>".
    "</tr></table>";      

    if (!$isNewEntry) {
        my $collection_no = $row{'collection_no'};
        # We need to take some additional steps for an edit
        # my $p = PBDB::Permissions->new($s,$dbt);
        # my $can_modify = $p->getModifierList();
        # $can_modify->{$s->get('authorizer_no')} = 1;
        # unless ($can_modify->{$row{'authorizer_no'}} || $s->isSuperUser) {
	unless ( $s->get('role') =~ /^auth|^ent|^stud/ || $s->isSuperUser ) {
            # my $authorizer = PBDB::Person::getPersonName($dbt,$row{'authorizer_no'});
            # return "<p class=\"warning\">You may not edit this collection because you are not on the editing permission list of the authorizer ($authorizer)<br>" . makeAnchor("displaySearchColls&type=edit", "<b>Edit another collection</b>");
	    return "<p class=\"warning\">You may not edit this collection because you are not a database contributor.</p>";
        }

        # translate the release date field to populate the pulldown
        # I'm not sure if we never did this at all, or if something got
        #  broken at some point, but it was causing big problems JA 10.5.07

        if ( date($vars{'created'}) != date($vars{'release_date'}) )	{
            $vars{'release_date'} = getReleaseString($vars{'created'},$vars{'release_date'});
        }

        # Secondary refs, followed by current ref
        my @secondary_refs = PBDB::ReferenceEntry::getSecondaryRefs($dbt,$collection_no);
        if (@secondary_refs) {
            my $table = '<table cellspacing="0" cellpadding="2" width="100%">';
            for(my $i=0;$i < @secondary_refs;$i++) {
                my $sr = $secondary_refs[$i];
                my $ref = PBDB::Reference::getReference($dbt,$sr);
                my $formatted_secondary = PBDB::Reference::formatLongRef($ref);
                my $class = ($i % 2 == 0) ? 'class="darkList"' : '';
                $table .= "<tr $class>".
                  "<td valign=\"top\"><input type=\"radio\" name=\"secondary_reference_no\" value=\"$sr\">".
                  "</td><td valign=\"top\" style=\"text-indent: -1em; padding-left: 2em;\"><b>$sr</b> ".
                  "$formatted_secondary <span style=\"color: red;\">$ref->{project_name} $ref->{project_ref_no}</span>";
                if(refIsDeleteable($dbt,$collection_no,$sr)) {
                    $table .= " <nobr>&nbsp;<input type=\"checkbox\" name=\"delete_ref\" value=$sr> remove<nobr>";
                }
                $table .= "</td></tr>";
            }
            $table .= "</table>";
            $vars{'secondary_reference_string'} = $table;
        }   

        # Check if current session ref is at all associated with the collection
        # If not, list it beneath the sec. refs. (with radio button for selecting
        # as the primary ref, as with the secondary refs below).
        if ($session_ref) {
            unless(isRefPrimaryOrSecondary($dbt,$collection_no,$session_ref)){
                my $ref = PBDB::Reference::getReference($dbt,$session_ref);
                my $sr = PBDB::Reference::formatLongRef($ref);
                my $table = '<table cellspacing="0" cellpadding="2" width="100%">'
                          . "<tr class=\"darkList\"><td valign=top><input type=radio name=secondary_reference_no value=$session_ref></td>";
                $table .= "<td valign=top><b>$ref->{reference_no}</b></td>";
                $table .= "<td>$sr</td></tr>";
                # Now, set up the current session ref to be added as a secondary even
                # if it's not picked as a primary (it's currently neither).
                $table .= "<tr class=\"darkList\"><td></td><td colspan=2><input type=checkbox name=add_session_ref value=\"YES\"> Add session reference as secondary reference</td></tr>\n";
                $table .= "</table>";
                $vars{'session_reference_string'} = $table;
            }
        }
    }

    # Get back the names for these
	if ( $vars{'max_interval_no'} )	{
		my $sql = "SELECT eml_interval,interval_name FROM intervals WHERE interval_no=".$vars{'max_interval_no'};
        my $interval = ${$dbt->getData($sql)}[0];
		$vars{'eml_max_interval'} = $interval->{eml_interval};
		$vars{'max_interval'} = $interval->{interval_name};
	}
	if ( $vars{'min_interval_no'} )	{
		my $sql = "SELECT eml_interval,interval_name FROM intervals WHERE interval_no=".$vars{'min_interval_no'};
        my $interval = ${$dbt->getData($sql)}[0];
		$vars{'eml_min_interval'} = $interval->{eml_interval};
		$vars{'min_interval'} = $interval->{interval_name};
	}

    $ref = PBDB::Reference::getReference($dbt,$vars{'reference_no'});
    $formatted_primary = PBDB::Reference::formatLongRef($ref);

    $output .= PBDB::PBDBUtil::printIntervalsJava($dbt);

    if ($isNewEntry) {
        $vars{'page_title'} =  "Collection entry form";
        $vars{'page_submit_button'} = '<input type=submit name="enter_button" value="Enter collection and exit">';
    } else {
        $vars{'page_title'} =  "Collection number ".$vars{'collection_no'};
        $vars{'page_submit_button'} = '<input type=submit name="edit_button" value="Edit collection and exit">';
        if ( $vars{'art_whole_bodies'} || $vars{'disart_assoc_maj_elems'} || $vars{'disassoc_maj_elems'} || $vars{'disassoc_minor_elems'} )	{
            $vars{'elements'} = 1;
        }
    }

    # Output the main part of the page
    $output .= $hbo->populateHTML("collection_form", \%vars);
    
    return $output;
}


#  * User submits completed collection entry form
#  * System commits data to database and thanks the nice user
#    (or displays an error message if something goes terribly wrong)
sub processCollectionForm {
    
    my ($dbt,$q,$s,$hbo) = @_;
    my $dbh = $dbt->dbh;
    my $output = '';

	my $reference_no = $q->numeric_param("reference_no");
	my $secondary = $q->numeric_param('secondary_reference_no');

	my $collection_no = $q->param('collection_no');

	my $isNewEntry = ($collection_no > 0) ? 0 : 1;
    
	# If a radio button was checked, we're changing a secondary to the primary
	if ($secondary)	{
		$q->param(reference_no => $secondary);
	}

	# there are three license checkboxes so users understand what they
	#  are doing, so combine the data JA 20.11.12
	my $license = 'CC BY';
	#$license .= ( $q->param('noncommercial') ) ? '-NC' : '';
	#$license .= ( $q->param('noderivs') ) ? '-ND' : '';
	#$license .= ( $q->param('sharealike') ) ? '-SA' : '';
	$q->param('license' => $license);

	# change interval names into numbers by querying the intervals table
	# JA 11-12.7.03
    
    my ($max_int_no, $min_int_no, $max_early, $min_early);
    
    if ( my $max_interval = $q->param('max_interval') )
    {
	my $quoted = $dbh->quote($max_interval);
	my $sql = "SELECT interval_no, early_age, late_age
		FROM intervals as i left join interval_data as id using (interval_no)
		WHERE i.interval_name=$quoted";
	
	if ( my $eml_max = $q->param('eml_max_interval') ) {
	    my $quoted = $dbh->quote($eml_max);
	    $sql .= " AND i.eml_interval=$quoted";
	} else {
	    $sql .= " AND i.eml_interval=''";
	}
	
	my $imax = ${$dbt->getData($sql)}[0];
	# $q->param(max_interval_no => $imax->{interval_no});
	$max_int_no = $imax->{interval_no};
	$max_early = $imax->{early_age};
    }
    
    if ( my $min_interval = $q->param('min_interval') )
    {
	my $quoted = $dbh->quote($min_interval);
	my $sql = "SELECT interval_no, early_age, late_age
		FROM intervals as i left join interval_data as id using (interval_no)
		WHERE i.interval_name=$quoted";
	
	if ( my $eml_min = $q->param('eml_min_interval') ) {
	    my $quoted = $dbh->quote($eml_min);
	    $sql .= " AND eml_interval=$quoted";
	} else	{
	    $sql .= " AND eml_interval=''";
	}
	
	my $imin = ${$dbt->getData($sql)}[0];
	# $q->param(min_interval_no => $imin->{interval_no});
	$min_int_no = $imin->{interval_no};
	$min_early = $imin->{early_age};
    } else {
	# $q->param(min_interval_no => 0);
	$min_int_no = 0;
    }
    
    # If the intervals are in the wrong order, we should swap them.
    
    if ( $max_early && $min_early && $max_early < $min_early )
    {
	my $temp = $max_int_no;
	$max_int_no = $min_int_no;
	$min_int_no = $temp;
    }
    
    $q->param(max_interval_no => $max_int_no);
    $q->param(min_interval_no => $min_int_no);
    
    # bomb out if no such interval exists JA 28.7.03
    if ( $q->numeric_param('max_interval_no') < 1 )	{
	return "<center><p>You can't enter an unknown time interval name</p>\n<p>Please go back, check the time scales, and enter a valid name</p></center>";
    }
    
    unless($q->param('fossilsfrom1')) {
      $q->param(fossilsfrom1=>'');
    }
    unless($q->param('fossilsfrom2')) {
      $q->param(fossilsfrom2=>'');
    }


    if ( $output = validateCollectionForm($dbt,$q,$s) )
    {
	return $output;
    }
	
        #set paleolat, paleolng if we can PS 11/07/2004
        my ($paleolat, $paleolng, $pid);
        if ($q->param('lngdeg') >= 0 && $q->param('lngdeg') =~ /\d+/ &&
            $q->param('latdeg') >= 0 && $q->param('latdeg') =~ /\d+/)
        {
            my ($f_latdeg, $f_lngdeg) = ($q->param('latdeg'), $q->param('lngdeg') );
            if ($q->param('lngmin') =~ /\d+/ && $q->param('lngmin') >= 0 && $q->param('lngmin') < 60)  {
                $f_lngdeg += $q->param('lngmin')/60 + $q->param('lngsec')/3600;
            } elsif ($q->param('lngdec') =~ /^\d+$/ ) {
                $f_lngdeg .= ".".$q->param('lngdec');
            }
            if ($q->param('latmin') =~ /\d+/ && $q->param('latmin') >= 0 && $q->param('latmin') < 60)  {
                $f_latdeg += $q->param('latmin')/60 + $q->param('latsec')/3600;
            } elsif ($q->param('latdec') =~ /^\d+$/) {
                $f_latdeg .= ".".$q->param('latdec');
            }
            dbg("f_lngdeg $f_lngdeg f_latdeg $f_latdeg");
            if ($q->param('lngdir') =~ /West/)  {
                    $f_lngdeg = $f_lngdeg * -1;
            }
            if ($q->param('latdir') =~ /South/) {
                    $f_latdeg = $f_latdeg * -1;
            }
            # oh by the way, set type float lat and lng fields JA 26.11.11
            # one step on the way to ditching the old lat/long fields...
            $q->param('lat' => $f_latdeg);
            $q->param('lng' => $f_lngdeg);
            # set precision based on the latitude fields, assuming that the
            #  longitude fields are consistent JA 26.11.11
            if ( $q->param('latsec') =~ /[0-9]/ )	{
                $q->param('latlng_precision' => 'seconds');
            } elsif ( $q->param('latmin') =~ /[0-9]/ )	{
                $q->param('latlng_precision' => 'minutes');
            } elsif ( length($q->param('latdec')) > 0 && length($q->param('latdec')) < 9 )	{
                $q->param('latlng_precision' => length($q->param('latdec')));
            } elsif ( length($q->param('latdec')) > 0 )	{
                $q->param('latlng_precision' => 8);
            } else	{
                $q->param('latlng_precision' => 'degrees');
            }

            my $max_interval_no = ($q->numeric_param('max_interval_no')) ? $q->numeric_param('max_interval_no') : 0;
            my $min_interval_no = ($q->numeric_param('min_interval_no')) ? $q->numeric_param('min_interval_no') : 0;
            ($paleolng, $paleolat, $pid) = getPaleoCoords($dbt,$q,$max_interval_no,$min_interval_no,$f_lngdeg,$f_latdeg);
            dbg("have paleocoords paleolat: $paleolat paleolng $paleolng");
            if ($paleolat ne "" && $paleolng ne "") {
                $q->param("paleolng"=>$paleolng);
                $q->param("paleolat"=>$paleolat);
                $q->param("plate"=>$pid);
            }
        }


        # figure out the release date, enterer, and authorizer
        my $created = now();
        if (!$isNewEntry) {
            my $sql = "SELECT created FROM $COLLECTIONS WHERE collection_no=$collection_no";
            my $row = ${$dbt->getData($sql)}[0];
            die "Could not fetch collection $collection_no from the database" unless $row;
            $created = $row->{created};
        }
        my $release_date = getReleaseDate($created, $q->param('release_date'));
        $q->param('release_date'=>$release_date);

        # Now final checking
        my %vars = $q->Vars;

        my ($dupe,$matches) = (0,0);
        if ($isNewEntry) {
            $dupe = $dbt->checkDuplicates($COLLECTIONS,\%vars);
#          $matches = $dbt->checkNearMatch($COLLECTIONS,'collection_no',$q,99,"something=something?");
        }

        if ($dupe) {
            $collection_no = $dupe;
        } elsif ($matches) {
            # Nothing to do, page generation and form processing handled
            # in the checkNearMatch function
        } else {
            if ($isNewEntry) {
                my ($status,$coll_id) = $dbt->insertRecord($s,$COLLECTIONS, \%vars);
                $collection_no = $coll_id;
            } else {
                my $status = $dbt->updateRecord($s,$COLLECTIONS,'collection_no',$collection_no,\%vars);
            }
	    
	    # After we insert or update, we need to copy this information to the
	    # coll_matrix (collection matrix) table.
	    
	    my $dbh = $dbt->dbh;
	    my $qno = $dbh->quote($collection_no);
	    my $sql = "REPLACE INTO $COLL_MATRIX
		       (collection_no, lng, lat, loc, cc,
			protected, early_age, late_age,
			early_int_no, late_int_no, environment,
			reference_no, access_level)
		SELECT c.collection_no, c.lng, c.lat,
			if(c.lng is null or c.lat is null, point(1000.0, 1000.0), point(c.lng, c.lat)), 
			map.cc, cl.protected,
			if(ei.early_age > li.late_age, ei.early_age, li.late_age),
			if(ei.early_age > li.late_age, li.late_age, ei.early_age),
			c.max_interval_no, if(c.min_interval_no > 0, c.min_interval_no, 
									c.max_interval_no),
			c.environment,
			c.reference_no,
			case c.access_level
				when 'database members' then if(c.release_date < now(), 0, 1)
				when 'research group' then if(c.release_date < now(), 0, 2)
				when 'authorizer only' then if(c.release_date < now(), 0, 2)
				else 0
			end
		FROM collections as c
			LEFT JOIN $COLL_LOC as cl using (collection_no)
			LEFT JOIN $COUNTRY_MAP as map on map.name = c.country
			LEFT JOIN $INTERVAL_DATA as ei on ei.interval_no = c.max_interval_no
			LEFT JOIN $INTERVAL_DATA as li on li.interval_no = 
				if(c.min_interval_no > 0, c.min_interval_no, c.max_interval_no)
		WHERE collection_no = $qno";
	    
	    $dbh->do($sql);
	    
	    $sql = "UPDATE $COLL_MATRIX as m JOIN
			(SELECT collection_no, count(*) as n_occs
			FROM occurrences GROUP BY collection_no) as sum using (collection_no)
		    SET m.n_occs = sum.n_occs WHERE collection_no = $qno";
	    
	    $dbh->do($sql);
        }

	# if numerical dates were entered, set the best-matching interval no
	my $ma;
	if ( $q->param('direct_ma') > 0 )	{
		my $no = setMaIntervalNo($dbt,$dbh,$collection_no,$q->param('direct_ma'),$q->param('direct_ma_unit'),$q->param('direct_ma'),$q->param('direct_ma_unit'));
	}
	elsif ( $q->param('max_ma') > 0 || $q->param('min_ma')> 0 )	{
		my $no = setMaIntervalNo($dbt,$dbh,$collection_no,$q->param('max_ma'),$q->param('max_ma_unit'),$q->param('min_ma'),$q->param('min_ma_unit'));
	} else	{
		setMaIntervalNo($dbt,$dbh,$collection_no);
	}
	
	# Make sure that the primary ref is in the "secondary references"
	# table (which should now list all references).
	
	setSecondaryRef($dbt, $collection_no, $reference_no);
	
        # If the current session ref isn't being made the primary, and it's not
        # currently a secondary, add it as a secondary ref for the collection 
        # (this query param doesn't show up if session ref is already a 2ndary.)
        if($q->param('add_session_ref') eq 'YES'){
            my $session_ref = $s->get("reference_no");
            if($session_ref != $secondary) {
                setSecondaryRef($dbt, $collection_no, $session_ref);
            }
        }
        # Delete secondary ref associations
        my @refs_to_delete = $q->param("delete_ref");
        dbg("secondary ref associations to delete: @refs_to_delete<br>");
        if(scalar @refs_to_delete > 0){
            foreach my $ref_no (@refs_to_delete){
                # check if any occurrences with this ref are tied to the collection
                if(refIsDeleteable($dbt, $collection_no, $ref_no)){
                    # removes secondary_refs association between the numbers.
                    dbg("removing secondary ref association (col,ref): $collection_no, $ref_no<br>");
                    deleteRefAssociation($dbt, $collection_no, $ref_no);
                }
            }
        }

        my $verb = ($isNewEntry) ? "added" : "updated";
        $output .= "<center><p class=\"pageTitle\" style=\"margin-bottom: -0.5em;\"><font color='red'>Collection record $verb</font></p><p class=\"medium\"><i>Do not press the back button!</i></p></center>";

	my $coll;
       	my ($colls_ref) = getCollections($dbt,$s,{collection_no=>$collection_no},['authorizer','enterer','modifier','*']);
       	$coll = $colls_ref->[0];

        if ($coll) {
            
            # If the viewer is the authorizer (or it's me), display the record with edit buttons
            my $links = '<p><div align="center"><table><tr><td>';
            # my $p = PBDB::Permissions->new($s,$dbt);
            # my $can_modify = $p->getModifierList();
            # $can_modify->{$s->get('authorizer_no')} = 1;
            
            # if ($can_modify->{$coll->{'authorizer_no'}} || $s->isSuperUser) {
	    if ( $s->get('role') =~ /^auth|^ent|^stud/ || $s->isSuperUser ) {
                $links .= "<li>" . makeAnchor("displayCollectionForm", "collection_no=$collection_no", "Edit this collection") . "- </li>";
            }
            $links .= "<li>" . makeAnchor("displayCollectionForm", "prefill_collection_no=$collection_no", "Add a collection copied from this one") . "- </li>";
            if ($isNewEntry) {
                $links .= "<li>" . makeAnchor("displaySearchCollsForAdd", "type=add", "Add another collection with the same reference") . "- </li>";
            } else {
                $links .= "<li>" . makeAnchor("displaySearchCollsForAdd", "type=add", "Add a collection with the same reference") . "- </li>";
                $links .= "<li>" . makeAnchor("displaySearchColls", "type=edit", "Edit another collection with the same reference") . "- </li>";
                $links .= "<li>" . makeAnchor("displaySearchColls", "type=edit&use_primary=yes", "Edit another collection using its own reference") . "- </li>";
            }
            $links .= "<li>" . makeAnchor("displayOccurrenceAddEdit", "collection_no=$collection_no", "Edit taxonomic list") . "- </li>";
            $links .= "<li>" . makeAnchor("displayOccurrenceListForm", "collection_no=$collection_no", "Paste in taxonomic list") . "- </li>";
            $links .= "<li>" . makeAnchor("displayCollResults", "type=occurrence_table&reference_no=$coll->{reference_no}", "Edit occurrence table for collections from the same reference") . "- </li>";
            if ( $s->get('role') =~ /authorizer|student|technician/ )	{
                $links .= "<li>" . makeAnchor("displayOccsForReID", "collection_no=$collection_no", "Reidentify taxa") . "- </li>";
            }
            $links .= "</td></tr></table></div></p>";

            $coll->{'collection_links'} = $links;

            $output .= displayCollectionDetailsPage($dbt,$hbo,$q,$s,$coll);
        }
	
    return $output;
}

# Set the release date
# originally written by Ederer; made a separate function by JA 26.6.02
sub getReleaseDate	{
	my ($createdDate,$releaseDateString) = @_;
	my $releaseDate = date($createdDate);

	if ( $releaseDateString eq 'three months')	{
		$releaseDate = $releaseDate+'3M';
	} elsif ( $releaseDateString eq 'six months')	{
		$releaseDate = $releaseDate+'6M';
	} elsif ( $releaseDateString eq 'one year')	{
		$releaseDate = $releaseDate+'1Y';
	} elsif ( $releaseDateString eq 'two years') {
		$releaseDate = $releaseDate+'2Y';
	} elsif ( $releaseDateString eq 'three years')	{
		$releaseDate = $releaseDate+'3Y';
	} elsif ( $releaseDateString eq 'four years')	{
        	$releaseDate = $releaseDate+'4Y';
	} elsif ( $releaseDateString eq 'five years')	{
		$releaseDate = $releaseDate+'5Y';
	}
	# Else immediate release
	return $releaseDate;
}

sub getReleaseString	{
	my ($created_date,$releaseDate) = @_;
	my $createdDate = date($created_date);
	my $releaseDate = date($releaseDate);
	my $releaseDateString = "immediate";

	if ( $releaseDate > $createdDate+'1M' && $releaseDate <= $createdDate+'3M' )	{
		$releaseDateString = 'three months';
	} elsif ( $releaseDate <= $createdDate+'6M' )	{
		$releaseDateString = 'six months';
	} elsif ( $releaseDate <= $createdDate+'1Y' )	{
		$releaseDateString = 'one year';
	} elsif ( $releaseDate <= $createdDate+'2Y' )	{
		$releaseDateString = 'two years';
	} elsif ( $releaseDate <= $createdDate+'3Y' )	{
		$releaseDateString = 'three years';
        } elsif ( $releaseDate <= $createdDate+'4Y' )	{
		$releaseDateString = 'four years';
	} elsif ( $releaseDate <= $createdDate+'5Y' )	{
		$releaseDateString = 'five years';
	}
	# Else immediate release
	return $releaseDateString;
}

# Make this more thorough in the future
sub validateCollectionForm {
	my ($dbt,$q,$s) = @_;
	my $output = '';
	
	unless($q->param('check_status') eq 'done')
	{
	    $output .= "<center><p>Something went wrong, and the database could not be updated.  Please notify the database administrator.</p></center>\n";
	    $output .= "<br>\n";
	    return $output;
	}
	
	unless($q->param('max_interval'))
	{
	    $output .= "<center><p>The time interval field is required!</p>\n<p>Please go back and specify the time interval for this collection</p></center>\n";
	    $output .= "<br>\n";
	    return $output;
	}
	
	return;
}


# JA 15.11.10
# records the narrowest interval that includes the direct Ma values entered on the collection form
# it's useful to know this because the enterer may have put in interval names that are either more
#  broad than necessary or in outright conflict with the numerical values
sub setMaIntervalNo	{
	my ($dbt,$dbh,$coll,$max,$max_unit,$min,$min_unit) = @_;
	my $sql;
	if ( $max < $min || ! $max || ! $min )	{
		$sql = "UPDATE collections SET modified=modified,ma_interval_no=NULL WHERE collection_no=$coll";
		$dbh->do($sql);
		return 0;
	}

	# units matter! JA 25.3.11
	if ( $max_unit =~ /ka/i )	{
		$max /= 1000;
	} elsif ( $max_unit =~ /ybp/i )	{
		$max /= 1000000;
	}
	if ( $min_unit =~ /ka/i )	{
		$min /= 1000;
	} elsif ( $min_unit =~ /ybp/i )	{
		$min /= 1000000;
	}

	# users will want a stage name if possible
	$sql = "SELECT interval_no FROM interval_lookup WHERE base_age>$max AND top_age<$min AND stage_no>0 ORDER BY base_age-top_age";
	my $no = ${$dbt->getData($sql)}[0]->{'interval_no'};
	if ( $no == 0 )	{
		$sql = "SELECT interval_no FROM interval_lookup WHERE base_age>$max AND top_age<$min AND subepoch_no>0 ORDER BY base_age-top_age";
		$no = ${$dbt->getData($sql)}[0]->{'interval_no'};
	}
	if ( $no == 0 )	{
		$sql = "SELECT interval_no FROM interval_lookup WHERE base_age>$max AND top_age<$min AND epoch_no>0 ORDER BY base_age-top_age";
		$no = ${$dbt->getData($sql)}[0]->{'interval_no'};
	}
	if ( $no == 0 )	{
		$sql = "SELECT interval_no FROM interval_lookup WHERE base_age>$max AND top_age<$min ORDER BY base_age-top_age";
		$no = ${$dbt->getData($sql)}[0]->{'interval_no'};
	}
	if ( $no > 0 )	{
		$sql = "UPDATE collections SET modified=modified,ma_interval_no=$no WHERE collection_no=$coll";
		$dbh->do($sql);
		return 1;
	} else	{
		$sql = "UPDATE collections SET modified=modified,ma_interval_no=NULL WHERE collection_no=$coll";
		$dbh->do($sql);
		return 0;
	}
}


# JA 5-6.4.04
# compose the SQL to find collections of a certain age within 100 km of
#  a coordinate (required when the user wants to add a collection)
sub processCollectionsSearchForAdd	{
    
    my ($q, $s, $dbt, $hbo) = @_;

    my $dbh = $dbt->dbh;
    return if PBDB::PBDBUtil::checkForBot();
    
    #require Map;
    
    # some generally useful trig stuff needed by processCollectionsSearchForAdd
    my $PI = 3.14159265;
    
    my $sql;
    
    # get a list of interval numbers that fall in the geological period
    
    my @intervals;
    
    if ( int_defined($q->param('period_max')) )
    {
	my ($b_age, $t_age) = int_bounds($q->param('period_max'));
	
	@intervals = interval_nos_by_age($b_age, $t_age);
    }
    
    else
    {
	my $period_name = $q->param('period_max');
	return "Unknown period '$period_name' in processCollectionsSearchForAdd\n";
    }
    
    $sql = "SELECT c.collection_no, c.collection_aka, c.authorizer_no, p1.name authorizer, c.collection_name, c.access_level, c.research_group, c.release_date, DATE_FORMAT(release_date, '%Y%m%d') rd_short, c.country, c.state, c.latdeg, c.latmin, c.latsec, c.latdec, c.latdir, c.lngdeg, c.lngmin, c.lngsec, c.lngdec, c.lngdir, c.max_interval_no, c.min_interval_no, c.reference_no FROM collections c LEFT JOIN person p1 ON p1.person_no = c.authorizer_no WHERE ";
    $sql .= "c.max_interval_no IN (" . join(',', @intervals) . ") AND ";
    
    # convert the submitted lat/long values
    my ($lat,$lng);
    
    ($lat) = $q->param('latdec') ne '' ?
	PBDB::CollectionEntry::fromDecDeg($q->param('latdeg'), $q->param('latdec')) :
	  PBDB::CollectionEntry::fromMinSec($q->param('latdeg'),$q->param('latmin'),$q->param('latsec'));
    
    ($lng) = $q->param('lngdec') ne '' ?
	PBDB::CollectionEntry::fromDecDeg($q->param('lngdeg'),$q->param('lngdec')) :
	  PBDB::CollectionEntry::fromMinSec($q->param('lngdeg'),$q->param('lngmin'),$q->param('lngsec'));
    
    # west and south are negative
    if ( $q->param('latdir') =~ /S/ )	{
	$lat = "-".$lat;
    }
    if ( $q->param('lngdir') =~ /W/ )	{
	$lng = "-".$lng;
    }
    my $mylat = $lat;
    my $mylng = $lng;
    
    # convert the coordinates to decimal values
    # maximum latitude is center point plus 100 km, etc.
    # longitude is a little tricky because we have to deal with cosines
    # it's important to use floor instead of int because they round off
    #  negative numbers differently
    my $maxlat = floor($lat + 100 / 111);
    my $minlat = floor($lat - 100 / 111);
    my $maxlng = floor($lng + ( (100 / 111) / cos($lat * $PI / 180) ) );
    my $minlng = floor($lng - ( (100 / 111) / cos($lat * $PI / 180) ) );
    
    # create an inlist of lat/long degree values for hitting the
    #  collections table
    
    # reset the limits if you go "north" of the north pole etc.
    # note that we don't have to get complicated with resetting, say,
    #  the minlat when you limit maxlat because there will always be
    #  enough padding
    # if you're too close to lat 0 or lng 0 there's no problem because
    #  you'll just repeat some values like 1 or 2 in the inlist, but we
    #  do need to prevent looking in just one hemisphere
    # if you have a "wraparound" like this you need to look in both
    #  hemispheres anyway, so don't add a latdir= or lngdir= clause
    if ( $maxlat >= 90 )	{
	$maxlat = 89;
    } elsif ( $minlat <= -90 )	{
	$minlat = -89;
    } elsif ( ( $maxlat > 0 && $minlat > 0 ) || ( $maxlat < 0 && $minlat < 0 ) )	{
	my $latdir = $dbh->quote($q->param('latdir'));
	$sql .= "c.latdir=$latdir AND ";
    }
    if ( $maxlng >= 180 )	{
	$maxlng = 179;
    } elsif ( $minlng <= -180 )	{
	$minlng = -179;
    } elsif ( ( $maxlng > 0 && $minlng > 0 ) || ( $maxlng < 0 && $minlng < 0 ) )	{
	my $lngdir = $dbh->quote($q->param('lngdir'));
	$sql .= "c.lngdir=$lngdir AND ";
    }
    
    my $inlist;
    for my $l ($minlat..$maxlat)	{
	$inlist .= abs($l) . ",";
    }
    $inlist =~ s/,$//;
    $sql .= "c.latdeg IN (" . $inlist . ") AND ";
    
    $inlist = "";
    for my $l ($minlng..$maxlng)	{
	$inlist .= abs($l) . ",";
    }
    $inlist =~ s/,$//;
    $sql .= "c.lngdeg IN (" . $inlist . ")";
    my $sortby = $q->param('sortby');
    if ($sortby eq 'collection_no') {
	$sql .= " ORDER BY c.collection_no";
    } elsif ($sortby =~ /^(collection_name|inventory_name)$/) {
	$sql .= " ORDER BY c.$sortby";
    }
    
    my @dataRows = ();
    
    my $sth = $dbt->dbh->prepare($sql);
    $sth->execute();
    my $p = PBDB::Permissions->new ($s,$dbt);
    my $limit = 10000000;
    my $ofRows = 0;
    $p->getReadRows ( $sth, \@dataRows, $limit, \$ofRows );
    
    # make sure collections really are within 100 km of the submitted
    #  lat/long coordinate JA 6.4.04
    my @tempDataRows;
    
    # have to recompute this
    for my $dr (@dataRows)	{
        my ($lat,$lng);
        # compute the coordinate
        $lat = $dr->{'latdeg'};
        $lng = $dr->{'lngdeg'};
        if ( $dr->{'latmin'} )	{
            $lat = $lat + ( $dr->{'latmin'} / 60 ) + ( $dr->{'latsec'} / 3600 );
        } else	{
            $lat = $lat . "." . $dr->{'latdec'};
        }
	
        if ( $dr->{'lngmin'} )	{
            $lng = $lng + ( $dr->{'lngmin'} / 60 ) + ( $dr->{'lngsec'} / 3600 );
        } else	{
            $lng = $lng . "." . $dr->{'lngdec'};
        }
	
        # west and south are negative
        if ( $dr->{'latdir'} =~ /S/ )	{
            $lat = $lat * -1;
        }
        if ( $dr->{'lngdir'} =~ /W/ )	{
            $lng = $lng * -1;
        }
	
        # if the points are less than 100 km apart, save
        #  the collection
        my $distance = 111 * PBDB::CollectionEntry::GCD($mylat,$lat,abs($mylng-$lng));
        if ( $distance < 100 )	{
            $dr->{'distance'} = $distance;
            push @tempDataRows, $dr;
        } 
    }
    
    if ($q->param('sortby') eq 'distance')	{
	@tempDataRows = sort {$a->{'distance'} <=> $b->{'distance'}  ||
				  $a->{'collection_no'} <=> $b->{'collection_no'}} @tempDataRows;
    }
    
    return (\@tempDataRows,scalar(@tempDataRows));
}


#  * User selects a collection from the displayed list
#  * System displays selected collection
sub displayCollectionDetails {
    
    my ($dbt,$q,$s,$hbo) = @_;
    my $dbh = $dbt->dbh;
    
	# previously displayed a collection, but this function is only now
	#  used for entry results display, so bots shouldn't see anything
	#  JA 4.6.13
	if ( PBDB::PBDBUtil::checkForBot() )	{
		return;
	}
	
	my $collection_no = $q->numeric_param('collection_no');

    # Handles the meat of displaying information about the colleciton
    # Separated out so it can be reused in enter/edit collection confirmation forms
    # PS 2/19/2006
    if ($collection_no !~ /^\d+$/) {
        return PBDB::Debug::printErrors(["Invalid collection number $collection_no"]);
    }

	# grab the entire person table and work with a lookup hash because
	#  person is tiny JA 2.10.09
	my %name = %{PBDB::PBDBUtil::getPersonLookup($dbt)};

	my $sql = "SELECT * FROM collections WHERE collection_no=" . $collection_no;
	my @rs = @{$dbt->getData($sql)};
	my $coll = $rs[0];
	$coll->{authorizer} = $name{$coll->{authorizer_no}};
	$coll->{enterer} = $name{$coll->{enterer_no}};
	$coll->{modifier} = $name{$coll->{modifier_no}};
	if (!$coll ) {
	    return PBDB::Debug::printErrors(["No collection with collection number $collection_no"]);
	}
    
    my $pcsql = "SELECT paleo_lat, paleo_lng FROM paleocoords WHERE
		 collection_no=$collection_no AND model='Wright2013' AND selector='mid'";
    
    my $dbh = $dbt->dbh;
    
    ($coll->{paleo_lat}, $coll->{paleo_lng}) = $dbh->selectrow_array($pcsql);
    
    $coll = formatCoordinate($s,$coll);
    
    my $page_vars = {};
    if ( $coll->{'research_group'} =~ /ETE/ && $q->param('guest') eq '' )	{
        $page_vars->{ete_banner} = "<div style=\"padding-left: 0em; padding-right: 2em; float: left;\"><a href=\"http://www.mnh.si.edu/ETE\"><img alt=\"ETE\" src=\"/public/bannerimages/ete_logo.jpg\"></a></div>";
    }
    
    # Handle display of taxonomic list now
    # don't even let bots see the lists because they will index the taxon
    #  pages returned by TaxonInfo anyway JA 2.10.09
    my $taxa_list = buildTaxonomicList($dbt,$hbo,$s,{'collection_no'=>$coll->{'collection_no'},'hide_reference_no'=>$coll->{'reference_no'}});
    $coll->{'taxa_list'} = $taxa_list;

    my $links = "<div class=\"verysmall\">";

    # Links at bottom
    if ($s->isDBMember()) {
        $links .= '<p><div align="center">';
        # my $p = PBDB::Permissions->new($s,$dbt);
        # my $can_modify = $p->getModifierList();
        # $can_modify->{$s->get('authorizer_no')} = 1;

        # if ($can_modify->{$coll->{'authorizer_no'}} || $s->isSuperUser) {  
	if ( $s->get('role') =~ /^auth|^ent|^stud/ || $s->isSuperUser ) {
            $links .= makeAnchor("displayCollectionForm", "collection_no=$collection_no", "Edit collection") . " - ";
        }
        $links .=  makeAnchor("displayCollectionForm", "prefill_collection_no=$collection_no", "Add a collection copied from this one");
        $links .= "</div></p>";
    }
    $links .= "</div>\n";

    $coll->{'collection_links'} = $links;

    return displayCollectionDetailsPage($dbt,$hbo,$q,$s,$coll);
}

# split out of displayCollectionDetails JA 6.11.09
sub formatCoordinate	{

    my ($s,$coll) = @_;

    # if the user is not logged in, round off the degrees
    # DO NOT mess with this routine, because Joe Public must not be
    #  able to locate a collection in the field and pillage it
    # JA 10.5.07
    if ( ! $s->isDBMember() )	{
        if ( ! $coll->{'lngdec'} && $coll->{'lngmin'} )	{
            $coll->{'lngdec'} = ( $coll->{'lngmin'} / 60 ) + ( $coll->{'lngsec'}  / 3600 );
        } else	{
            $coll->{'lngdec'} = "0." . $coll->{'lngdec'};
        }
        if ( ! $coll->{'latdec'} && $coll->{'latmin'} )	{
            $coll->{'latdec'} = ( $coll->{'latmin'} / 60 ) + ( $coll->{'latsec'}  / 3600 );
        } else	{
            $coll->{'latdec'} = "0." . $coll->{'latdec'};
        }
        $coll->{'lngdec'} = int ( ( $coll->{'lngdec'} + 0.05 ) * 10 );
        $coll->{'latdec'} = int ( ( $coll->{'latdec'} + 0.05 ) * 10 );
        if ( $coll->{'lngdec'} == 10 )	{
            $coll->{'lngdeg'}++;
            $coll->{'lngdec'} = 0;
        }
        if ( $coll->{'latdec'} == 10 )	{
            $coll->{'latdeg'}++;
            $coll->{'latdec'} = 0;
        }
        $coll->{'lngmin'} = '';
        $coll->{'lngsec'} = '';
        $coll->{'latmin'} = '';
        $coll->{'latsec'} = '';
        $coll->{'geogcomments'} = '';
    }
    
    if ( defined $coll->{paleo_lat} && defined $coll->{paleo_lng} )
    {
	$coll->{paleolatdir} = "North, ";
	if ( $coll->{paleo_lat} < 0 )	{
	    $coll->{paleolatdir} = "South, ";
	}
	$coll->{paleolngdir} = "East";
	if ( $coll->{paleo_lng} < 0 )	{
	    $coll->{paleolngdir} = "West";
	}
	$coll->{paleolat} = sprintf "%.1f&deg;",abs($coll->{paleo_lat});
	$coll->{paleolng} = sprintf "%.1f&deg;",abs($coll->{paleo_lng});
    }
    
    else
    {
	$coll->{paleolat} = undef;
	$coll->{paleolng} = undef;
    }
    
    return $coll;
}

# JA 25.5.11
sub fromMinSec	{
	my ($deg,$min,$sec) = @_;
	$deg =~ s/[^0-9]//g;
	$min =~ s/[^0-9]//g;
	$sec =~ s/[^0-9]//g;
	my $dec = $deg + $min/60 + $sec/3600;
	my $format = "minutes";
	if ( $sec ne "" )	{
		$format = "seconds";
	}
	return ($dec,$format);
}

sub fromDecDeg {
    
    my ($deg, $frac) = @_;
    
    $deg =~ s/[^0-9]//g;
    $frac =~ s/[^0-9]//g;

    my $dec = "$deg.$frac";
    return ($dec);
}

# JA 25.5.11
sub toMinSec	{
	my ($deg,$dec) = split /\./,$_[0];
	$dec = ".".$dec;
	my $min = int($dec * 60);
	my $sec = int($dec *3600 - $min * 60);
	return ($deg,$min,$sec);
}

sub displayCollectionDetailsPage {
    my ($dbt,$hbo,$q,$s,$row) = @_;
    my $dbh = $dbt->dbh;
    my $collection_no = $row->{'collection_no'};
    return if (!$collection_no);

    # Get the reference
    if ($row->{'reference_no'}) {
        $row->{'reference_string'} = '';
        my $ref = PBDB::Reference::getReference($dbt,$row->{'reference_no'});
        my $formatted_primary = PBDB::Reference::formatLongRef($ref);
        $row->{'reference_string'} = '<table cellspacing="0" cellpadding="2" width="100%"><tr>'.
            "<td valign=\"top\">" . makeAnchor("app/refs", "#display=$row->{reference_no}", "$row->{'reference_no'}") . ".</a></td>".
            "<td valign=\"top\"><span class=red>$ref->{project_name} $ref->{project_ref_no}</span></td>".
            "<td>$formatted_primary</td>".
            "</tr></table>";
        
        $row->{'secondary_reference_string'} = '';
        my @secondary_refs = PBDB::ReferenceEntry::getSecondaryRefs($dbt,$collection_no);
        if (@secondary_refs) {
            my $table = "";
            $table .= '<table cellspacing="0" cellpadding="2" width="100%">';
            for(my $i=0;$i < @secondary_refs;$i++) {
                my $sr = $secondary_refs[$i];
                my $ref = PBDB::Reference::getReference($dbt,$sr);
                my $formatted_secondary = PBDB::Reference::formatLongRef($ref);
                my $class = ($i % 2 == 0) ? 'class="darkList"' : '';
                $table .= "<tr $class>".
                    "<td valign=\"top\">" . makeAnchor("app/refs", "#display=$sr", "$sr") . "</a></td>".
                    "<td valign=\"top\"><span class=red>$ref->{project_name} $ref->{project_ref_no}</span></td>".
                    "<td>$formatted_secondary</td>".
                    "</tr>";
            }
            $table .= "</table>";
            $row->{'secondary_reference_string'} = $table;
        }
    }


        my $sql;

	# Get any subset collections JA 25.6.02
	$sql = "SELECT collection_no FROM collections where collection_subset=" . $collection_no;
	my $sth = $dbh->prepare( $sql ) || die ( "$sql<hr>$!" );
    $sth->execute();
    my @subrowrefs = @{$sth->fetchall_arrayref()};
    $sth->finish();
    my @links = ();
    foreach my $ref (@subrowrefs)	{
      push @links, makeAnchor("displayCollectionDetails", "collection_no=$ref->[0]", "$ref->[0]");
    }
    my $subString = join(", ",@links);
    $row->{'subset_string'} = $subString;

    my $sql1 = "SELECT DISTINCT authorizer_no, enterer_no, modifier_no FROM occurrences WHERE collection_no=" . $collection_no;
    my $sql2 = "SELECT DISTINCT authorizer_no, enterer_no, modifier_no FROM reidentifications WHERE collection_no=" . $collection_no;
    my @names = (@{$dbt->getData($sql1)},@{$dbt->getData($sql2)});
    my %lookup = %{PBDB::PBDBUtil::getPersonLookup($dbt)};
    if (@names) {
        my %unique_auth = ();
        my %unique_ent = ();
        my %unique_mod = ();
        foreach (@names) {
            $unique_auth{$lookup{$_->{'authorizer_no'}}}++;
            $unique_ent{$lookup{$_->{'enterer_no'}}}++;
            $unique_mod{$lookup{$_->{'modifier_no'}}}++ if ($_->{'modifier'});
        }
        delete $unique_auth{$row->{'authorizer'}};
        delete $unique_ent{$row->{'enterer'}};
        delete $unique_mod{$row->{'modifier'}};
        $row->{'authorizer'} .= ", $_" for (keys %unique_auth);
        $row->{'enterer'} .= ", $_" for (keys %unique_ent);
        $row->{'modifier'} .= ", $_" for (keys %unique_mod);
        # many collections have no modifier, so the initial comma needs to be
        #  stripped off
        $row->{'modifier'} =~ s/^, //;
    }

    # Added by MM 2024-07-17
    
    $row->{interval} = 'unknown';
    
    if ( $row->{max_interval_no} )
    {
	no warnings 'uninitialized';
	
	my ($b_age, $t_age) = int_bounds($row->{max_interval_no});
	my ($dummy);
	
	if ( my $max_name = int_name($row->{max_interval_no}) )
	{
	    $row->{interval} = qq|<a target="_blank" href="$INTERVAL_URL$row->{max_interval_no}">|;
	    $row->{interval} .= $max_name;
	    $row->{interval} .= "</a>";
	}
	
	$row->{period} = int_name(int_correlation($row->{max_interval_no}, 'period_no'));
	$row->{epoch} = int_name(int_correlation($row->{max_interval_no}, 'epoch_no'));
	$row->{stage} = int_name(int_correlation($row->{max_interval_no}, 'stage_no'));
	$row->{ten_my_bin} = int_correlation($row->{max_interval_no}, 'ten_my_bin');
	
	if ( $row->{min_interval_no} && $row->{min_interval_no} ne $row->{max_interval_no} )
	{
	    ($dummy, $t_age) = int_bounds($row->{min_interval_no});
	    
	    if ( my $min_name = int_name($row->{min_interval_no}) )
	    {
		$row->{interval} .= ' - ';
		$row->{interval} .= qq|<a target="_blank" href="$INTERVAL_URL$row->{min_interval_no}">|;
		$row->{interval} .= $min_name;
		$row->{interval} .= "</a>";
	    }
	    
	    my $min_period = int_name(int_correlation($row->{min_interval_no}, 'period_no'));
	    my $min_epoch = int_name(int_correlation($row->{min_interval_no}, 'epoch_no'));
	    my $min_stage = int_name(int_correlation($row->{min_interval_no}, 'stage_no'));
	    my $min_bin = int_correlation($row->{min_interval_no}, 'ten_my_bin');
	    
	    if ( $min_period && $row->{period} && $min_period ne $row->{period} )
	    {
		$row->{period} .= " - $min_period";
	    }
	    
	    if ( $min_epoch && $row->{epoch} && $min_epoch ne $row->{epoch} )
	    {
		$row->{epoch} .= " - $min_epoch";
	    }
	    
	    if ( $min_stage && $row->{stage} && $min_stage ne $row->{stage} )
	    {
		$row->{stage} .= " - $min_stage";
	    }
	    
	    if ( $min_bin && $row->{ten_my_bin} && $min_bin ne $row->{ten_my_bin} )
	    {
		$row->{ten_my_bin} .= " - $min_bin";
	    }
	}
	
	if ( defined $b_age && $b_age ne '' && defined $t_age && $t_age ne '' )
	{
	    $row->{age_range} = "$b_age - $t_age m.y. ago";
	}
	
	else
	{
	    $row->{age_range} = "bad intervals";
	}
    }
    
    else
    {
	$row->{age_range} = "unknown";
    }
    
	# get the max/min interval names
	# $row->{'interval'} = '';
	# if ( $row->{'max_interval_no'} ) {
	# 	$sql = "SELECT eml_interval,interval_name FROM intervals WHERE interval_no=" . $row->{'max_interval_no'};
        # my $max_row = ${$dbt->getData($sql)}[0];
        # $row->{'interval'} .= qq|<a href="$INTERVAL_URL$row->{max_interval_no}">|; #old FossilWorks stuff
        # $row->{'interval'} .= $max_row->{'eml_interval'}." " if ($max_row->{'eml_interval'});
        # $row->{'interval'} .= $max_row->{'interval_name'};
        # $row->{'interval'} .= '</a>';
	# } 

	# if ( $row->{'min_interval_no'}) {
	# 	$sql = "SELECT eml_interval,interval_name FROM intervals WHERE interval_no=" . $row->{'min_interval_no'};
        # my $min_row = ${$dbt->getData($sql)}[0];
        # $row->{'interval'} .= " - ";
        # $row->{'interval'} .= qq|<a href="$INTERVAL_URL$row->{min_interval_no}">|; #old FossilWorks stuff
        # $row->{'interval'} .= $min_row->{'eml_interval'}." " if ($min_row->{'eml_interval'});
        # $row->{'interval'} .= $min_row->{'interval_name'};
        # $row->{'interval'} .= '</a>';

        # if (!$row->{'max_interval_no'}) {
        #     $row->{'interval'} .= " <span class=small>(minimum)</span>";
        # }
	# } 
    
    my $time_place = $row->{'collection_name'}.": ";
    $time_place .= "$row->{interval}";
    if ($row->{'state'} && $row->{country} eq "United States") {
        $time_place .= ", $row->{state}";
    } elsif ($row->{'country'}) {
        $time_place .= ", $row->{country}";
    }
    if ( $row->{'collectors'} || $row->{'collection_dates'} ) {
        $time_place .= "<br><small>collected ";
        if ( $row->{'collectors'} ) {
            my $collectors = $row->{'collectors'};
            $time_place .= " by " .$collectors . " ";
        }
        if ( $row->{'collection_dates'} ) {
            my $years = $row->{'collection_dates'};
            $years =~ s/[A-Za-z\.]//g;
            $years =~ s/\b[0-9]([0-9]|)\b//g;
            $years =~ s/^( |),//;
            $time_place .= $years;
        }
        $time_place .= "</small>";
    }
    $row->{'collection_name'} = $time_place;
    
    # my @intervals = ();
    # push @intervals, $row->{'max_interval_no'} if ($row->{'max_interval_no'});
    # push @intervals, $row->{'min_interval_no'} if ($row->{'min_interval_no'} && $row->{'min_interval_no'} != $row->{'max_interval_no'});
    # my $max_lookup;
    # my $min_lookup;
    # if (@intervals) { 
    #     my $t = new PBDB::TimeLookup($dbt);
    #     my $lookup = $t->lookupIntervals(\@intervals);
    #     $max_lookup = $lookup->{$row->{'max_interval_no'}};
    #     if ($row->{'min_interval_no'}) { 
    #         $min_lookup = $lookup->{$row->{'min_interval_no'}};
    #     } else {
    #         $min_lookup=$max_lookup;
    #     }
    # }
    # if ($max_lookup->{'base_age'} && $min_lookup->{'top_age'}) {
    #     my @boundaries = ($max_lookup->{'base_age'},$max_lookup->{'top_age'},$min_lookup->{'base_age'},$min_lookup->{'top_age'});
    #     @boundaries = sort {$b <=> $a} @boundaries;
    #     # Get rid of extra trailing zeros
    #     $boundaries[0] =~ s/(\.0|[1-9])(0)*$/$1/;
    #     $boundaries[-1] =~ s/(\.0|[1-9])(0)*$/$1/;
    #     $row->{'age_range'} = $boundaries[0]." - ".$boundaries[-1]." m.y. ago";
    # } else {
    #     $row->{'age_range'} = "";
    # }
    
    # if ( $row->{max_interval_no} > 0 || $row->{min_interval_no} > 0 )
    # {
    # 	my ($early_age, $late_age) = lookupAgeRange($dbh, $row->{max_interval_no}, $row->{min_interval_no});
    # 	$row->{age_range} = "$early_age - $late_age m.y. ago";
    # }
    # else
    # {
    # 	$row->{age_range} = "unknown";
    # }
    
    if ( $row->{'direct_ma'} )	{
        $row->{'age_estimate'} .= $row->{'direct_ma'};
        if ( $row->{'direct_ma_error'} )	{
            $row->{'age_estimate'} .= " &plusmn; " . $row->{'direct_ma_error'};
        }
        $row->{'age_estimate'} .= " ".$row->{'direct_ma_unit'}." (" . $row->{'direct_ma_method'} . ")";
    }
    my $link;
    my $endlink;
    if ( $row->{'max_ma'} )	{
        if ( ! $row->{'min_ma'} )	{
            $row->{'age_estimate'} .= "maximum ";
        }
        $row->{'age_estimate'} .= $row->{'max_ma'};
        if ( $row->{'max_ma_error'} )	{
            $row->{'age_estimate'} .= " &plusmn; " . $row->{'max_ma_error'};
        }
        if ( $row->{'min_ma'} && $row->{'max_ma_method'} ne $row->{'min_ma_method'} )	{
            $row->{'age_estimate'} .= " ".$row->{'max_ma_unit'}." ($link" . $row->{'max_ma_method'} . "$endlink)";
        }
    }
    if ( $row->{'min_ma'} && ( ! $row->{'max_ma'} || $row->{'min_ma'} ne $row->{'max_ma'} || $row->{'min_ma_method'} ne $row->{'max_ma_method'} ) )	{
        if ( ! $row->{'max_ma'} )	{
            $row->{'age_estimate'} .= "minimum ";
        } else	{
            $row->{'age_estimate'} .= " to ";
        }
        $row->{'age_estimate'} .= $row->{'min_ma'};
        if ( $row->{'min_ma_error'} )	{
            $row->{'age_estimate'} .= " &plusmn; " . $row->{'min_ma_error'};
        }
        $row->{'age_estimate'} .= " ".$row->{'min_ma_unit'}." ($link" . $row->{'min_ma_method'} . "$endlink)";
    } elsif ( $row->{'age_estimate'} && $row->{'max_ma_method'} ne "" )	{
        $row->{'age_estimate'} .= " ".$row->{'max_ma_unit'}." ($link" . $row->{'max_ma_method'} . "$endlink)";
    }
    
    # foreach my $term ("period","epoch","stage") {
    #     $row->{$term} = "";
    #     if ($max_lookup->{$term."_name"} &&
    #         $max_lookup->{$term."_name"} eq $min_lookup->{$term."_name"}) {
    #         $row->{$term} = $max_lookup->{$term."_name"};
    #     }
    # }
    # if ($max_lookup->{"ten_my_bin"} &&
    #     $max_lookup->{"ten_my_bin"} eq $min_lookup->{"ten_my_bin"}) {
    #     $row->{"ten_my_bin"} = $max_lookup->{"ten_my_bin"};
    # } else {
    #     $row->{"ten_my_bin"} = "";
    # }
    
    $row->{"zone_type"} =~ s/(^.)/\u$1/;

	# check whether we have period/epoch/locage/intage max AND/OR min:
    # if ($s->isDBMember()) {
        foreach my $term ("epoch","intage","locage","period"){
            $row->{'legacy_'.$term} = '';
            if ($row->{$term."_max"}) {
                if ($row->{'eml'.$term.'_max'}) {
                    $row->{'legacy_'.$term} .= $row->{'eml'.$term.'_max'}." ";
                }
                $row->{'legacy_'.$term} .= $row->{$term."_max"};
            }
            if ($row->{$term."_min"}) {
                if ($row->{$term."_max"}) {
                    $row->{'legacy_'.$term} .= " - ";
                }
                if ($row->{'eml'.$term.'_min'}) {
                    $row->{'legacy_'.$term} .= $row->{'eml'.$term.'_min'}." ";
                }
                $row->{'legacy_'.$term} .= $row->{$term."_min"};
                if (!$row->{$term."_max"}) {
                    $row->{'legacy_'.$term} .= " <span class=small>(minimum)</span>";
                }
            }
        }
    # }
    if ($row->{'legacy_period'} eq $row->{'period'}) {
        $row->{'legacy_period'} = '';
    }
    if ($row->{'legacy_epoch'} eq $row->{'epoch'}) {
        $row->{'legacy_epoch'} = '';
    }
    if ($row->{'legacy_locage'} eq $row->{'stage'}) {
        $row->{'legacy_locage'} = '';
    }
    if ($row->{'legacy_intage'} eq $row->{'stage'}) {
        $row->{'legacy_intage'} = '';
    }
    if ($row->{'legacy_epoch'} ||
        $row->{'legacy_period'} ||
        $row->{'legacy_intage'} ||
        $row->{'legacy_locage'}) {
        $row->{'legacy_message'} = 1;
    } else {
        $row->{'legacy_message'} = '';
    }

    if ($row->{'interval'} eq $row->{'period'} ||
        $row->{'interval'} eq $row->{'epoch'} ||
        $row->{'interval'} eq $row->{'stage'}) {
        $row->{'interval'} = '';
    }


    if ($row->{'collection_subset'}) {
        $row->{'collection_subset'} =  makeAnchor("displayCollectionDetails", "collection_no=$row->{collection_subset}", "$row->{collection_subset}");
    }

    if ($row->{'regionalsection'}) {
    	my $escaped = uri_escape_utf8($row->{regionalsection} // '');
        $row->{'regionalsection'} = makeAnchor("displayStratTaxaForm", "taxon_resolution=species&skip_taxon_list=YES&input_type=regional&input=$escaped", $row->{regionalsection});
    }

    if ($row->{'localsection'}) {
    	my $escaped = uri_escape_utf8($row->{localsection} // '');
        $row->{'localsection'} = makeAnchor("displayStratTaxaForm", "taxon_resolution=species&skip_taxon_list=YES&input_type=local&input=$escaped", "$row->{localsection}");
    }

    if ($row->{'member'}) {
    	my $escaped = uri_escape_utf8($row->{geological_group} // '');
    	my $escaped2 = uri_escape_utf8($row->{formation} // '');
    	my $escaped3 = uri_escape_utf8($row->{member} // '');
        $row->{'member'} = makeAnchor("displayStrata", "group_hint=$escaped&formation_hint=$escaped2&group_formation_member=$escaped3", "$row->{member}");
    }

    if ($row->{'formation'}) {
    	my $escaped = uri_escape_utf8($row->{geological_group} // '');
    	my $escaped2 = uri_escape_utf8($row->{formation} // '');
        $row->{'formation'} = makeAnchor("displayStrata", "group_hint=$escaped&group_formation_member=$escaped2", "$row->{formation}");
    }

    if ($row->{'geological_group'}) {
    	my $escaped = uri_escape_utf8($row->{geological_group} // '');
        $row->{'geological_group'} = makeAnchor("displayStrata", "group_formation_member=$escaped", "$row->{geological_group}");
    }
    
    if ( defined $row->{paleolat} || defined $row->{paleolng} )
    {
	$row->{paleolngdir} .= " (Wright 2013)";
    }
    
    $row->{'modified'} = date($row->{'modified'});

    # textarea values often have returns that need to be rendered
    #  as <br>s JA 20.8.06
    for my $r ( keys %$row )	{
        if ( $r !~ /taxa_list/ && $r =~ /comment/ )	{
            $row->{$r} =~ s/\n/<br>/g;
        }
    }
    return $hbo->populateHTML('collection_display_fields', $row);

} # end sub displayCollectionDetails()


# builds the list of occurrences shown in places such as the collections form
# must pass it the collection_no
# reference_no (optional or not?? - not sure).
#
# optional arguments:
#
# gnew_names	:	reference to array of new genus names the user is entering (from the form)
# subgnew_names	:	reference to array of new subgenus names the user is entering
# snew_names	:	reference to array of new species names the user is entering

sub buildTaxonomicList {
    
    my ($dbt,$hbo,$s,$options) = @_;
    
    my %options = ();
    
    if ($options)
    {
	%options = %{$options};
    }
    
    # dereference arrays.
    my @gnew_names = @{$options{'new_genera'}} if $options{new_genera};
    my @subgnew_names = @{$options{'new_subgenera'}} if $options{new_subgenera};
    my @snew_names = @{$options{'new_species'}} if $options{new_species};
    my @subsnew_names = @{$options{new_subspecies}} if $options{new_subspecies};
    
    my $new_found = 0;		# have we found new taxa?  (ie, not in the database)
    my $return = "";
    
    # This is the taxonomic list part
    # join with taxa_tree_cache because lft and rgt will be used to
    #  order the list JA 13.1.07
    
    my $treefields = ", lft, rgt";
    
    my $sqlstart = "SELECT abund_value, abund_unit, genus_name, genus_reso, subgenus_name, subgenus_reso, plant_organ, plant_organ2, species_name, species_reso, subspecies_name, subspecies_reso, comments, reference_no, occurrence_no, o.taxon_no taxon_no, collection_no";
    
    my $sqlmiddle = " FROM occurrences as o ";
    my $sqlend;
    
    if ($options{'collection_no'})
    {
	$sqlmiddle = " FROM occurrences o ";
	$sqlend .= "AND collection_no=$options{'collection_no'}";
    }
    
    elsif ($options{'occurrence_list'} && @{$options{'occurrence_list'}})
    {
	$sqlend .= "AND occurrence_no IN (".join(', ',@{$options{'occurrence_list'}}).") ORDER BY occurrence_no";
    }
    
    else
    {
	$sqlend = "";
    }
    
    my $sql = $sqlstart . ", lft, rgt" . $sqlmiddle . ", $TAXA_TREE_CACHE as t WHERE o.taxon_no=t.taxon_no " . $sqlend;
    my $sql2 = $sqlstart . $sqlmiddle . "WHERE taxon_no=0 " . $sqlend;
    
    my @warnings;
    
    if ($options{'warnings'})
    {
	@warnings = @{$options{'warnings'}};
    }
    
    dbg("buildTaxonomicList sql: $sql");
    
    my @rowrefs;
    
    if ($sql)
    {
	@rowrefs = @{$dbt->getData($sql)};
	push @rowrefs , @{$dbt->getData($sql2)};
    }
    
    if (@rowrefs)
    {
	my @grand_master_list = ();
	my $are_reclassifications = 0;
	
	# loop through each row returned by the query
	
	foreach my $rowref (@rowrefs)
	{
	    my $output = '';
	    my %classification = ();
	    
	    $rowref->{subgenus_name} ||= '';
	    $rowref->{species_name} ||= '';
	    $rowref->{subspecies_name} ||= '';
	    
	    # If we have specimens
	    
	    if ( $rowref->{'occurrence_no'} )
	    {
		my $sql_s = "SELECT count(*) c FROM specimens 
				WHERE occurrence_no=$rowref->{occurrence_no}";
		
		my $specimens_measured = ${$dbt->getData($sql_s)}[0]->{'c'};
		if ($specimens_measured)
		{
		    my $s = ($specimens_measured > 1) ? 's' : '';
		    $rowref->{comments} .= " (" . makeAnchor("displaySpecimenList", "occurrence_no=$rowref->{occurrence_no}", "$specimens_measured measurement$s") . ")";
		}
	    }
	    
	    # if the user submitted a form such as adding a new occurrence or 
	    # editing an existing occurrence, then we'll bold face any of the
	    # new taxa which we don't already have in the database.
            # Bad bug: rewriting the data directly here fucked up all kinds of operations
            # below which expect the taxonomic names to be pure, just set some flags
            # and have stuff interpret them below PS 2006
	    
	    # check for unrecognized genus names
	    
	    foreach my $nn (@gnew_names)
	    {
		if ( $rowref->{genus_name} eq $nn )
		{
		    $rowref->{new_genus_name} = 1;
		    $new_found++;
		}
	    }
	    
	    # check for unrecognized subgenus names
	    
	    foreach my $nn (@subgnew_names)
	    {
		if ( $rowref->{subgenus_name} eq $nn )
		{
		    $rowref->{new_subgenus_name} = 1;
		    $new_found++;
		}
	    }
	    
	    # check for unrecognized species names
	    
	    foreach my $nn (@snew_names)
	    {
		if ( $rowref->{species_name} eq $nn )
		{
		    $rowref->{new_species_name} = 1;
		    $new_found++;
		}
	    }
	    
	    # check for unrecognized subspecies names
	    
	    foreach my $nn (@subsnew_names)
	    {
		if ( $rowref->{subspecies_name} eq $nn )
		{
		    $rowref->{new_subspecies_name} = 1;
		    $new_found++;
		}
	    }
	    
	    # tack on the author and year if the taxon number exists
	    # JA 19.4.04
	    
	    if ( $rowref->{taxon_no} )
	    {
		my $taxon = PBDB::TaxonInfo::getTaxa($dbt,{'taxon_no'=>$rowref->{'taxon_no'}},
						     ['taxon_no','taxon_name','common_name',
						      'taxon_rank','author1last','author2last',
						      'otherauthors','pubyr','reference_no',
						      'ref_is_authority']);
		
		if ( $taxon->{'taxon_rank'} =~ /species/ || 
		     $rowref->{'species_name'} =~ /[.]$/ )
		{
		    my $orig_no = PBDB::TaxonInfo::getOriginalCombination($dbt,$taxon->{'taxon_no'});
		    my $is_recomb = ($orig_no == $taxon->{'taxon_no'}) ? 0 : 1;
		    
		    $rowref->{'authority'} = PBDB::Reference::formatShortRef($taxon,
							     'no_inits'=>1,
							     'link_id'=>$taxon->{'ref_is_authority'},
							     'is_recombination'=>$is_recomb);
		}
	    }
	    
	    my $formatted_reference = '';
	    
	    # if the occurrence's reference differs from the collection's, print it
	    
	    my $newrefno = $rowref->{'reference_no'};
	    
	    if ($newrefno != $options{'hide_reference_no'})
	    {
		$rowref->{reference_no} = PBDB::Reference::formatShortRef($dbt,$newrefno,
									  'no_inits'=>1,
									  'link_id'=>1);
	    }
	    
	    else
	    {
		$rowref->{reference_no} = '';
	    }
	    
	    # put all keys and values from the current occurrence into two separate
	    # arrays.
	    
	    $rowref->{'taxon_name'} = formatOccurrenceTaxonName($rowref);
	    $rowref->{'hide_collection_no'} = $options{'collection_no'};
	    
	    # get the most recent reidentification
	    
	    my $mostRecentReID;
	    
	    if ( $rowref->{'occurrence_no'} )
	    {
		$mostRecentReID = PBDB::PBDBUtil::getMostRecentReIDforOcc($dbt,
									  $rowref->{occurrence_no},1);
	    }
	    
	    # if the occurrence has been reidentified at least once
	    #  display the original and reidentifications.
	    
	    if ($mostRecentReID)
	    {
		# rjp, 1/2004, change this so it displays *all* reidentifications, not just
		# the last one.
                # JA 2.4.04: this was never implemented by Poling, who instead
                #  went renegade and wrote the entirely redundant
		#  HTMLFormattedTaxonomicList; the correct way to do it was
		#  to pass in $rowref->{occurrence_no} and isReidNo = 0
                #  instead of $mostRecentReID and isReidNo = 1
		
		my $show_collection = '';
		my ($table,$classification,$reid_are_reclassifications) = 
		    getReidHTMLTableByOccNum($dbt,$hbo,$s,$rowref->{occurrence_no}, 0, 
					     $options{'do_reclassify'});
		
		$are_reclassifications = 1 if ($reid_are_reclassifications);
		$rowref->{'class'} = $classification->{'class'}{'taxon_name'};
		$rowref->{'order'} = $classification->{'order'}{'taxon_name'};
		$rowref->{'family'} = $classification->{'family'}{'taxon_name'};
		$rowref->{'common_name'} = ($classification->{'common_name'}{'taxon_no'});
		
		if ( ! $rowref->{'class'} && ! $rowref->{'order'} && ! $rowref->{'family'} )
		{
		    if ( $options{'do_reclassify'} )
		    {
			$rowref->{'class'} = qq|<span style="color: red;">unclassified</span>|;
		    }
		    
		    else
		    {
			$rowref->{'class'} = "unclassified";
		    }
		}
		
		if ( $rowref->{'class'} && $rowref->{'order'} )
		{
		    $rowref->{'order'} = "- " . $rowref->{'order'};
		}
		
		if ( $rowref->{'family'} && ( $rowref->{'class'} || $rowref->{'order'} ) )
		{
		    $rowref->{'family'} = "- " . $rowref->{'family'};
		}
		
		$rowref->{'parents'} = $hbo->populateHTML("parent_display_row", $rowref);
		$output = qq|<tr><td colspan="5" style="border-top: 1px solid #E0E0E0;"></td></tr>|;
		$output .= $hbo->populateHTML("taxa_display_row", $rowref);
		$output .= $table;
		
		$rowref->{'class_no'}  = ($classification->{'class'}{'taxon_no'} or 100000000);
		$rowref->{'order_no'}  = ($classification->{'order'}{'taxon_no'} or 100000000);
		$rowref->{'family_no'} = ($classification->{'family'}{'taxon_no'} or 100000000);
		$rowref->{'lft'} = ($classification->{'lft'}{'taxon_no'} or 100000000);
		$rowref->{'rgt'} = ($classification->{'rgt'}{'taxon_no'} or 100000000);
	    }
	    
	    # otherwise this occurrence has never been reidentified
	    
	    else
	    {
		# If the taxonomic name of this occurrence is in the authorities table,
		# get its classification directly. Otherwise, if it is a subspecies, check
		# to see if the species is in the authorities table. If so, get the
		# classification using the species name.
		
		my $classify_taxon_no = $rowref->{taxon_no};
		my $count = 1;
		
		if ( ! $classify_taxon_no && $rowref->{subspecies_name} &&
		     $rowref->{species_reso} ne 'informal' )
		{
		    my $dbh = $dbt->dbh;
		    my $species_name = $dbh->quote("$rowref->{genus_name} $rowref->{species_name}");
		    
		    my $sql = "SELECT taxon_no, count(*) FROM authorities
			WHERE taxon_name = $species_name GROUP BY taxon_name";
		    
		    ($classify_taxon_no, $count) = $dbh->selectrow_array($sql);
		}
		
		if ( ! $classify_taxon_no && $rowref->{genus_reso} ne 'informal' )
		{
		    my $dbh = $dbt->dbh;
		    my $genus_name = $dbh->quote("$rowref->{genus_name}");
		    
		    my $sql = "SELECT taxon_no, count(*) FROM authorities
				WHERE taxon_name = $genus_name GROUP BY taxon_name";
		    
		    ($classify_taxon_no, $count) = $dbh->selectrow_array($sql);
		}
		
                if ( $classify_taxon_no && $count == 1 )
		{
                    # Get parents
		    my $class_hash = PBDB::TaxaCache::getParents($dbt,[$classify_taxon_no],
								 'array_full');
		    
                    my @class_array = @{$class_hash->{$classify_taxon_no}};
		    
                    # Get Self as well, in case we're a family indet.
		    
		    if ( $rowref->{taxon_no} )
		    {
			my $taxon = PBDB::TaxonInfo::getTaxa($dbt, {taxon_no => $rowref->{taxon_no}},
							     ['taxon_name','common_name',
							      'taxon_rank','pubyr']);
			unshift @class_array , $taxon;
			
			if ( $taxon->{taxon_name} eq $rowref->{taxon_name} )
			{
			    $rowref->{synonym_name} = getSynonymName($dbt, $rowref->{taxon_no},
								     $taxon->{taxon_name});
			}
		    }
		    
                    $rowref = getClassOrderFamily($dbt, \$rowref, \@class_array);
		    
                    if ( ! $rowref->{class} && ! $rowref->{order} && ! $rowref->{family} )
		    {
                        $rowref->{class} = "unclassified";
                    }
                }
		
		else
		{
                    if ($options{'do_reclassify'})
		    {
                        $rowref->{'show_classification_select'} = 1;
                        # Give these default values, don't want to pass in possibly undef values to any function or PERL might screw it up
                        my $taxon_name = $rowref->{genus_name}; 
                        $taxon_name .= " ($rowref->{subgenus_name})" if $rowref->{'subgenus_name'};
                        $taxon_name .= " $rowref->{species_name}";
			$taxon_name .= " $rowref->{subspecies_name}" if $rowref->{subspecies_name};
                        my @all_matches = PBDB::Taxon::getBestClassification($dbt,$rowref);
                        if (@all_matches)
			{
                            $are_reclassifications = 1;
                            $rowref->{'classification_select'} = PBDB::Reclassify::classificationSelect($dbt, $rowref->{occurrence_no},0,1,\@all_matches,$rowref->{'taxon_no'},$taxon_name);
                        }
                    }
                }
		
		$rowref->{'class_no'} ||= 100000000;
		$rowref->{'order_no'} ||= 100000000;
		$rowref->{'family_no'} ||= 100000000;
		$rowref->{'lft'} ||= 100000000;
		
		if ( ! $rowref->{'class'} && ! $rowref->{'order'} && ! $rowref->{'family'} )
		{
		    if ( $options{'do_reclassify'} )
		    {
			$rowref->{'class'} = qq|<span style="color: red;">unclassified</span>|;
		    }
		    
		    else
		    {
			$rowref->{'class'} = "unclassified";
		    }
		}
		
		if ( $rowref->{'class'} && $rowref->{'order'} )
		{
		    $rowref->{'order'} = "- " . $rowref->{'order'};
		}
		
		if ( $rowref->{'family'} && ( $rowref->{'class'} || $rowref->{'order'} ) )
		{
		    $rowref->{'family'} = "- " . $rowref->{'family'};
		}
		
		$rowref->{'parents'} = $hbo->populateHTML("parent_display_row", $rowref);
		
		$output = qq|<tr><td colspan="5" style="border-top: 1px solid #E0E0E0;"></td></tr>|;
		$output .= $hbo->populateHTML("taxa_display_row", $rowref);
	    }
	    
	    # Clean up abundance values (somewhat messy, but works, and better
	    #   here than in populateHTML) JA 10.6.02
	    
	    $output =~ s/(>1 specimen)s|(>1 individual)s|(>1 element)s|(>1 fragment)s/$1$2$3$4/g;
	    
	    $rowref->{'html'} = $output;
	    push(@grand_master_list, $rowref);
	}
	
	# Look at @grand_master_list to see every record has class_no, order_no,
	# family_no,  reference_no, abundance_unit and comments. 
	# If ALL records are missing any of those, don't print the header
	# for it.
	
	my ($class_nos, $order_nos, $family_nos, $common_names, $lft_nos,
	    $reference_nos, $abund_values, $comments) = (0,0,0,0,0,0,0);
	
	foreach my $row (@grand_master_list)
	{
	    $class_nos++ if($row->{class_no} && $row->{class_no} != 100000000);
	    $order_nos++ if($row->{order_no} && $row->{order_no} != 100000000);
	    $family_nos++ if($row->{family_no} && $row->{family_no} != 100000000);
	    $common_names++ if($row->{common_name});
	    $lft_nos++ if($row->{lft} && $row->{lft} != 100000000);
	    $reference_nos++ if($row->{reference_no} && $row->{reference_no} != $options{'hide_reference_no'});
	    $abund_values++ if($row->{abund_value});
	    $comments++ if($row->{comments});
	}
	
        if ($options{'collection_no'})
	{
            my $sql = "SELECT c.collection_name,c.country,c.state,concat(i1.eml_interval,' ',i1.interval_name) max_interval, concat(i2.eml_interval,' ',i2.interval_name) min_interval " 
                    . " FROM collections c "
                    . " LEFT JOIN intervals i1 ON c.max_interval_no=i1.interval_no"
                    . " LEFT JOIN intervals i2 ON c.min_interval_no=i2.interval_no"
                    . " WHERE c.collection_no=$options{'collection_no'}";
	    
            my $coll = ${$dbt->getData($sql)}[0];
	    
            # get the max/min interval names
	    
            my $time_place = $coll->{'collection_name'}.": ";
	    
            if ($coll->{'max_interval'} ne $coll->{'min_interval'} && $coll->{'min_interval'})
	    {
                $time_place .= "$coll->{max_interval} - $coll->{min_interval}";
            }
	    
	    else
	    {
                $time_place .= "$coll->{max_interval}";
            } 
            
	    if ($coll->{'state'} && $coll->{country} eq "United States")
	    {
                $time_place .= ", $coll->{state}";
            }
	    
	    elsif ($coll->{'country'})
	    {
                $time_place .= ", $coll->{country}";
            }
        }
	
        # Taxonomic list header
	
        $return = "<div class=\"displayPanel\" align=\"left\">\n" .
                  "  <span class=\"displayPanelHeader\">Taxonomic list</span>\n" .
                  "  <div class=\"displayPanelContent\">\n" ;
	
	if ($new_found)
	{
            push @warnings, "<center>Taxon names in <b>bold</b> are new to the occurrences table. Please make sure there aren't any typos. If there are, Do not press the back button; click the edit link below.</center>";
	}
        
	if  ($are_reclassifications)
	{
            push @warnings, "<center>Some taxa could not be classified because multiple versions of the names (such as homonyms) exist in the database.  Please choose which versions you mean and select \"Classify taxa.\"</center>";
        }
	
        if (@warnings)
	{
            $return .= "<div style=\"margin-left: auto; margin-right: auto; text-align: left;\">";
            $return .= PBDB::Debug::printWarnings(\@warnings);
            $return .= "<br>";
            $return .= "</div>";
        }
	
        if ($are_reclassifications)
	{
	    $return .= makeFormPostTag();
            $return .= "<input type=\"hidden\" name=\"action\" value=\"startProcessReclassifyForm\">\n"; 
            if ($options{collection_no})
	    {
                $return .= "<input type=\"hidden\" name=\"collection_no\" value=\"$options{collection_no}\">\n"; 
            }
        }
	
	$return .= "<table border=\"0\" cellpadding=\"0\" cellspacing=\"0\" class=\"tiny\"><tr>";
	
	# Sort:
	
        my @sorted = ();
	
        if ($options{'occurrence_list'} && @{$options{'occurrence_list'}})
	{
            # Should be sorted in SQL using the same criteria as was made to
            # build the occurrence list (in displayOccsForReID)  Right now this is by occurrence_no, which is being done in sql;
            @sorted = @grand_master_list;
        }
	
	else
	{
            # switched from sorting by taxon nos to sorting by lft rgt
            #  JA 13.1.07
            @sorted = sort{ $a->{lft} <=> $b->{lft} ||
                               $a->{rgt} <=> $b->{rgt} ||
                               $a->{occurrence_no} <=> $b->{occurrence_no} } @grand_master_list;
            #@sorted = sort{ $a->{class_no} <=> $b->{class_no} ||
            #                   $a->{order_no} <=> $b->{order_no} ||
            #                   $a->{family_no} <=> $b->{family_no} ||
            #                   $a->{occurrence_no} <=> $b->{occurrence_no} } @grand_master_list;
            unless ( $lft_nos == 0 )
	    {
		#unless($class_nos == 0 && $order_nos == 0 && $family_nos == 0 )
                # Now sort the ones that had no taxon_no by occ_no.
                my @occs_to_sort = ();
                while ( $sorted[-1]->{lft} == 100000000 )
		{
                    push(@occs_to_sort, pop @sorted);
                }
		
		# Put occs in order, AFTER the sorted occ with the closest smaller
		# number.  First check if our occ number is one greater than any 
		# existing sorted occ number.  If so, place after it.  If not, find
		# the distance between it and all other occs less than it and then
		# place it after the one with the smallest distance.
		
                while ( my $single = pop @occs_to_sort )
		{
                    my $slot_found = 0;
                    my @variances = ();
                    # First, look for the "easy out" at the endpoints.
                    # Beginning?
		    # HMM, if $single is less than $sorted[0] we don't want to put
		    # it at the front unless it's less than ALL $sorted[$x].
                    #if($single->{occurrence_no} < $sorted[0]->{occurrence_no} && 
                    #	$sorted[0]->{occurrence_no} - $single->{occurrence_no} == 1){
                    #	unshift @sorted, $single;
                    #}
                    # Can I just stick it at the end?
		    
                    if(($single->{occurrence_no} > $sorted[-1]->{occurrence_no}) &&
                       ($single->{occurrence_no} - $sorted[-1]->{occurrence_no} == 1))
		    {
                        push @sorted, $single;
                    }
		    
                    # Somewhere in the middle
		    
                    else
		    {
                        for(my $index = 0; $index < @sorted-1; $index++)
			{
                            if($single->{occurrence_no} > 
			       $sorted[$index]->{occurrence_no})
			    { 
                                # if we find a variance of 1, bingo!
                                if($single->{occurrence_no} -
				   $sorted[$index]->{occurrence_no} == 1)
				{
                                    splice @sorted, $index+1, 0, $single;
                                    $slot_found=1;
                                    last;
                                }
                                
				else
				{
                                    # store the (positive) variance
                                    push(@variances, $single->{occurrence_no}-$sorted[$index]->{occurrence_no});
                                }
                            }
			    
                            else
			    { # negative variance
                                push(@variances, 100000000);
                            }
                        }
			
                        # if we didn't find a variance of 1, place after smallest
                        # variance.
			
                        if(!$slot_found)
			{
                            # end variance:
                            if($sorted[-1]->{occurrence_no}-$single->{occurrence_no}>0)
			    {
                                push(@variances,$sorted[-1]->{occurrence_no}-$single->{occurrence_no});
                            }
			    
                            else
			    { # negative variance
                                push(@variances, 100000000);
                            }
			    
                            # insert where the variance is the least
			    
                            my $smallest = 100000000;
                            my $smallest_index = 0;
			    
                            for(my $counter=0; $counter<@variances; $counter++)
			    {
                                if($variances[$counter] < $smallest){
                                    $smallest = $variances[$counter];
                                    $smallest_index = $counter;
                                }
                            }
			    
                            # NOTE: besides inserting according to the position
                            # found above, this will insert an occ less than all other
                            # occ numbers at the very front of the list (the condition
                            # in the loop above will never be met, so $smallest_index
                            # will remain zero.
                            splice @sorted, $smallest_index+1, 0, $single;
                        }
                    }
                }
            }
        }
	
	my $sorted_html = '';
	my $rows = $#sorted + 2;
	$sorted_html .= qq|
<script language="JavaScript" type="text/javascript">
<!-- Begin

window.onload = hideName;

function addLink(link_id,link_action,taxon_name)	{
	if ( ! /href/.test( document.getElementById(link_id).innerHTML ) )	{
		document.getElementById(link_id).innerHTML = '<a href="?a=basicTaxonInfo' + link_action + '&amp;is_real_user=1">' + taxon_name + '</a>';
	}
}

function hideName()	{
	for (var rowNum=1; rowNum<$rows; rowNum++)	{
		document.getElementById('commonRow'+rowNum).style.visibility = 'hidden';
	}
}

function showName()	{
	document.getElementById('commonClick').style.visibility = 'hidden';
	var commonName = document.getElementsByName("commonName");
	for ( i = 0; i<= commonName.length; i++ )       {
		commonName[i].style.visibility = "visible";
	}
	for (var rowNum=1; rowNum<$rows; rowNum++)	{
		document.getElementById('commonRow'+rowNum).style.visibility = 'visible';
	}
}

-->
</script>
|;
	
	my $lastparents;
	
	for( my $index = 0; $index < @sorted; $index++ )
	{
	    # only the last row needs to have the rowNum inserted
	    my $rowNum = $index + 1;
	    my @parts = split /commonRow/,$sorted[$index]->{html};
	    $parts[$#parts] = $rowNum . $parts[$#parts];
	    $sorted[$index]->{html} = join 'commonRow',@parts;
	    
	    #            $sorted[$index]->{html} =~ s/<td align="center"><\/td>/<td>$sorted[$index]->{occurrence_no}<\/td>/; DEBUG
	    if ( $sorted[$index]->{'class'} . $sorted[$index]->{'order'} . $sorted[$index]->{'family'} ne $lastparents )
	    {
		$sorted_html .= $sorted[$index]->{'parents'};
		$lastparents = $sorted[$index]->{'class'} . $sorted[$index]->{'order'} . $sorted[$index]->{'family'};
	    }
	    
	    $sorted_html .= $sorted[$index]->{html};    
	}
	
	$return .= $sorted_html;
	
	$return .= qq|<tr><td colspan="5" align="right"><span onClick="showName();" id="commonClick" class="small">see common names</span></td>|;
	
	$return .= "</table>";
        
	if ($are_reclassifications)
	{
            $return .= "<br><input type=\"submit\" name=\"submit\" value=\"Classify taxa\">";
            $return .= "</form>"; 
        }
	
	$return .= "<div class=\"verysmall\">";
	$return .= '<p><div align="center">';
	
	if ( $options{'collection_no'} > 0 && ! $options{'save_links'} )
	{
	    # there used to be some links here to rarefyAbundances and
	    #  displayCollectionEcology but these are going with Fossilworks
	    #  4.6.13 JA
	    
	    if ($s->isDBMember())
	    {
		$return .= makeAnchor("displayOccurrenceAddEdit", "collection_no=$options{'collection_no'}", "Edit taxonomic list");
		if ( $s->get('role') =~ /authorizer|student|technician/ )	{
		    $return .= " - " . makeAnchor("displayOccsForReID", "collection_no=$options{'collection_no'}", "Reidentify taxa");
		}
	    }
	}
	
	elsif ($s->isDBMember())
	{
	    $return .= $options{'save_links'};
	}
	
	$return .= "</div></p>\n</div>\n";
	
        $return .= "</div>";
        $return .= "</div>";
    }
    
    else
    {
        if (@warnings)
	{
            $return .= "<div align=\"center\">";
            $return .= PBDB::Debug::printWarnings(\@warnings);
            $return .= "<br>";
            $return .= "</div>";
        }
    }
    
    # This replaces blank cells with blank cells that have no padding, so the don't take up
    # space - this way the comments field lines is indented correctly if theres a bunch of empty
    # class/order/family columns sort of an hack but works - PS
    $return =~ s/<td([^>]*?)>\s*<\/td>/<td$1 style=\"padding: 0\"><\/td>/g;
    #$return =~ s/<td(.*?)>\s*<\/td>/<td$1 style=\"padding: 0\"><\/td>/g;
	return $return;
} # end sub buildTaxonomicList()


sub formatOccurrenceTaxonName {
    
    my ($row) = @_;
    
    my $taxon_name = "";

    # Generate the link first
    
    my $link_id = $row->{'occurrence_no'};
    
    if ( $row->{'reid_no'} )
    {
        $link_id = "R" . $row->{'reid_no'};
    }
    
    my $link_action;
    
    if ( $row->{'taxon_no'} > 0 )
    {
        $link_action = $row->{'taxon_no'};
        $link_action = "&amp;taxon_no=" . uri_escape_utf8($link_action // '');
    }
    
    elsif ( $row->{'genus_name'} && $row->{'genus_reso'} ne 'informal' )
    {
        $link_action = $row->{'genus_name'};

        if ( $row->{'subgenus_name'} && $row->{'subgenus_reso'} ne 'informal' )
	{
            $link_action .= " ($row->{'subgenus_name'})";
        }
	
        if ( $row->{'species_name'} && $row->{'species_reso'} ne 'informal' && 
	     $row->{'species_name'} !~ /[.]$/ )
	{
            $link_action .= " $row->{'species_name'}";
        }
	
	if ( $row->{subspecies_name} && $row->{subspecies_reso} ne 'informal' &&
	     $row->{subspecies_name} !~ /[.]$/ )
	{
	    $link_action .= " $row->{subspecies_name}";
	}
	
        $link_action = "&amp;taxon_name=" . uri_escape_utf8($link_action // '');
    }
    
    # Genus
    
    my $genus_name = $row->{'genus_name'};
    
    if ($row->{'new_genus_name'})
    {
        $genus_name = "<b>".$genus_name."</b>";
    }
    
    # n. gen., n. subgen., n. sp. come afterwards
    # sensu lato always goes at the very end no matter what JA 3.3.07
    
    if ($row->{'genus_reso'} eq 'n. gen.' && $row->{'species_reso'} ne 'n. sp.')
    {
        $taxon_name .= "$genus_name n. gen.";
    }
    
    elsif ($row->{'genus_reso'} eq '"')
    {
        $taxon_name .= '"'.$genus_name;
        $taxon_name .= '"' unless ( $row->{'subgenus_reso'} eq '"' || 
				    $row->{'species_reso'} eq '"' ||
				    $row->{subspecies_reso} eq '"' );
    }
    
    elsif ($row->{'genus_reso'} && $row->{'genus_reso'} ne 'n. gen.' && 
	   $row->{'genus_reso'} ne 'sensu lato')
    {
        $taxon_name .= $row->{'genus_reso'}." ".$genus_name;
    }
    
    else
    {
        $taxon_name .= $genus_name;
    }
    
    # Subgenus
    
    if ($row->{'subgenus_name'})
    {
        my $subgenus_name = $row->{'subgenus_name'};
        if ($row->{'new_subgenus_name'}) {
            $subgenus_name = "<b>".$subgenus_name."</b>";
        }
        $taxon_name .= " (";
        if ($row->{'subgenus_reso'} eq 'n. subgen.') {
            $taxon_name .= "$subgenus_name n. subgen.";
        } elsif ($row->{'subgenus_reso'} eq '"') {
            $taxon_name .= '"' unless ($row->{'genus_reso'} eq '"');
            $taxon_name .= $subgenus_name;
            $taxon_name .= '"' unless ($row->{'species_reso'} eq '"' ||
				       $row->{subspecies_reso} eq '"');
        } elsif ($row->{'subgenus_reso'}) {
            $taxon_name .= $row->{'subgenus_reso'}." ".$subgenus_name;
        } else {
            $taxon_name .= $subgenus_name;
        }
        $taxon_name .= ")";
    }
    
    # Species
    
    $taxon_name .= " ";
    
    my $species_name = $row->{'species_name'};
    
    if ( $row->{'new_species_name'} )
    {
        $species_name = "<b>".$species_name."</b>";
    }
    
    if ( $row->{'species_reso'} eq '"' )
    {
        $taxon_name .= '"' unless $row->{'genus_reso'} eq '"' || $row->{'subgenus_reso'} eq '"';
        $taxon_name .= $species_name;
	$taxon_name .= '"' unless $row->{subspecies_reso} eq '';
    }
    
    elsif ($row->{'species_reso'} && $row->{'species_reso'} ne 'n. sp.' && 
	   $row->{'species_reso'} ne 'sensu lato')
    {
        $taxon_name .= $row->{'species_reso'}." ".$species_name;
    }
    
    else
    {
        $taxon_name .= $species_name;
    }
    
    # Subspecies
    
    my $subspecies_name = $row->{subspecies_name};
    
    if ( $row->{new_subspecies_name} )
    {
	$subspecies_name = "<b>$subspecies_name</b>";
    }
    
    if ( $row->{subspecies_reso} eq '"' )
    {
	$taxon_name .= ' ';
	$taxon_name .= '"' unless $row->{genus_reso} eq '"' || $row->{subgenus_reso} eq '"' ||
	    $row->{species_reso} eq '"';
	$taxon_name .= $subspecies_name;
	$taxon_name .= '"';
    }
    
    elsif ( $row->{subspecies_reso} && $row->{subspecies_reso} ne 'n. ssp.' &&
	    $row->{subspecies_reso} ne 'sensu lato' )
    {
	$taxon_name .= ' ' . $row->{subspecies_reso} . ' ' . $subspecies_name;
    }
    
    else
    {
	$taxon_name .= ' ' . $subspecies_name;
    }
    
    #if ($row->{'species_reso'} ne 'n. sp.' && $row->{'species_reso'}) {
    #    $taxon_name .= " ".$row->{'species_reso'};
    #}
    #$taxon_name .= " ".$row->{'species_name'};

    if ( $row->{species_name} !~ /[.]$/ && $row->{genus_reso} ne 'informal' )
    {
        $taxon_name = "<i>$taxon_name</i>";
    }
    
    if ($link_id)
    {
        $taxon_name =~ s/"/&quot;/g;
        $taxon_name = qq|<span class="mockLink" id="$link_id" onMouseOver="addLink('$link_id','$link_action','$taxon_name')">$taxon_name</span>|;
    }
    
    if ( $row->{genus_reso} eq 'sensu lato' || $row->{species_reso} eq 'sensu lato' ||
	 $row->{subspecies_reso} eq 'sensu lato' )
    {
        $taxon_name .= " sensu lato";
    }
    
    if ( $row->{'species_reso'} eq 'n. sp.' )
    {
        if ($row->{'genus_reso'} eq 'n. gen.')
	{
            $taxon_name .= " n. gen.,";
        }
	
        $taxon_name .= " n. sp.";
    }
    
    elsif ( $row->{subspecies_reso} eq 'n. ssp.' )
    {
	$taxon_name .= " n. ssp.";
    }
    
    if ($row->{'plant_organ'} && $row->{'plant_organ'} ne 'unassigned')
    {
        $taxon_name .= " $row->{plant_organ}";
    }
    
    if ($row->{'plant_organ2'} && $row->{'plant_organ2'} ne 'unassigned')
    {
        $taxon_name .= ", " if ($row->{'plant_organ'} && $row->{'plant_organ'} ne 'unassigned');
        $taxon_name .= " $row->{plant_organ2}";
    }
    
    return $taxon_name;
}

# This is pretty much just used in a couple places above
sub getSynonymName {
    my ($dbt,$taxon_no,$current_taxon_name) = @_;
    return "" unless $taxon_no;

    my $synonym_name = "";

    my $orig_no = PBDB::TaxonInfo::getOriginalCombination($dbt,$taxon_no);
    my ($ss_taxon_no,$status) = PBDB::TaxonInfo::getSeniorSynonym($dbt,$orig_no,'','yes');
    my $is_synonym = ($ss_taxon_no != $orig_no && $status =~ /synonym/) ? 1 : 0;
    my $is_spelling = 0;
    my $spelling_reason = "";

    my $spelling = PBDB::TaxonInfo::getMostRecentSpelling($dbt,$ss_taxon_no,{'get_spelling_reason'=>1});
    if ($spelling->{'taxon_no'} != $taxon_no && $current_taxon_name ne $spelling->{'taxon_name'}) {
        $is_spelling = 1;
        $spelling_reason = $spelling->{'spelling_reason'};
        $spelling_reason = 'original and current combination' if $spelling_reason eq 'original spelling';
        $spelling_reason = 'recombined as' if $spelling_reason eq 'recombination';
        $spelling_reason = 'corrected as' if $spelling_reason eq 'correction';
        $spelling_reason = 'spelled with current rank as' if $spelling_reason eq 'rank change';
        $spelling_reason = 'reassigned as' if $spelling_reason eq 'reassignment';
        if ( $status =~ /replaced|subgroup|nomen/ )	{
            $spelling_reason = $status;
            if ( $status =~ /nomen/ )	{
                $spelling_reason .= ' belonging to';
            }
        }
    }
    my $taxon_name = $spelling->{'taxon_name'};
    my $taxon_rank = $spelling->{'taxon_rank'};
    if ($is_synonym || $is_spelling) {
        if ($taxon_rank =~ /species|genus/) {
            $synonym_name = "<em>$taxon_name</em>";
        } else { 
            $synonym_name = $taxon_name;
        }
        $synonym_name =~ s/"/&quot;/g;
        if ($is_synonym) {
            $synonym_name = "synonym of <span class=\"mockLink\" id=\"syn$ss_taxon_no\" onMouseOver=\"addLink('syn$ss_taxon_no','&amp;taxon_no=$ss_taxon_no','$synonym_name')\">$synonym_name</span>";
        } else {
            $synonym_name = "$spelling_reason <span class=\"mockLink\" id=\"syn$ss_taxon_no\" onMouseOver=\"addLink('syn$ss_taxon_no','&amp;taxon_no=$ss_taxon_no','$synonym_name')\">$synonym_name</span>";
        }
    }
    return $synonym_name;
}


# Gets an HTML formatted table of reidentifications for a particular taxon
# pass it an occurrence number or reid_no
# the second parameter tells whether it's a reid_no (true) or occurrence_no (false).
sub getReidHTMLTableByOccNum {
    
    my ($dbt,$hbo,$s,$occNum,$isReidNo,$doReclassify) = @_;
    
    my $fieldName = $isReidNo ? 'reid_no' : 'occurrence_no';
    
    my $sql = "SELECT genus_reso, genus_name, subgenus_reso, subgenus_name, species_reso, 
		species_name, subspecies_reso, subspecies_name, plant_organ, 
		re.comments as comments, re.reference_no as reference_no, pubyr, taxon_no,
		occurrence_no, reid_no, collection_no 
	FROM reidentifications as re left join refs as r on re.reference_no=r.reference_no
	WHERE $fieldName = $occNum
	ORDER BY r.pubyr ASC, re.reid_no ASC";
    
    my @results = @{$dbt->getData($sql)};
    my $html = "";
    my $classification = {};
    my $are_reclassifications = 0;
    
    # We always get all of them PS
    foreach my $row ( @results )
    {
	$row->{'taxon_name'} = "&nbsp;&nbsp;&nbsp;&nbsp;= ".formatOccurrenceTaxonName($row);
        
	# format the reference (PM)
	$row->{'reference_no'} = PBDB::Reference::formatShortRef($dbt, $row->{'reference_no'},
								 no_inits => 1, link_id => 1);
	
	# get the taxonomic authority JA 19.4.04
	my $taxon;
	if ($row->{'taxon_no'})
	{
	    $taxon = PBDB::TaxonInfo::getTaxa($dbt,{'taxon_no'=>$row->{'taxon_no'}},
					      ['taxon_no','taxon_name','common_name','taxon_rank',
					       'author1last','author2last','otherauthors','pubyr',
					       'reference_no','ref_is_authority']);
	    
	    if ($taxon->{'taxon_rank'} =~ /species/ || $row->{'species_name'} =~ /^indet\.|^sp\./)
	    {
		$row->{'authority'} = PBDB::Reference::formatShortRef($taxon, no_inits => 1,
							      link_id => $taxon->{'ref_is_authority'});
	    }
	}
	
	# Classify this occurrence based on the most recent identification.
	
        if ( $row == $results[$#results] )
	{
	    # The taxonomic name of this reidentification is i the authorities table, get
	    # its classification directly. Otherwise, if it is a subspecies, check to see
	    # if the species is in the authorities table. If so, get the classification
	    # using the species name.
	    
	    my $classify_taxon_no = $row->{taxon_no};
	    my $count = 1;
	    
	    if ( ! $classify_taxon_no && $row->{subspecies_name} &&
		 $row->{species_reso} ne 'informal' )
	    {
		my $dbh = $dbt->dbh;
		my $species_name = $dbh->quote("$row->{genus_name} $row->{species_name}");
		
		my $sql = "SELECT taxon_no, count(*) FROM authorities
			WHERE taxon_name = $species_name GROUP BY taxon_name";
		
		($classify_taxon_no, $count) = $dbh->selectrow_array($sql);
	    }
	    
	    if ( ! $classify_taxon_no && $row->{genus_reso} ne 'informal' )
	    {
		my $dbh = $dbt->dbh;
		my $genus_name = $dbh->quote("$row->{genus_name}");
		
		my $sql = "SELECT taxon_no, count(*) FROM authorities
			WHERE taxon_name = $genus_name GROUP BY taxon_name";
		
		($classify_taxon_no, $count) = $dbh->selectrow_array($sql);
	    }
	    
            if ( $classify_taxon_no && $count == 1 )
	    {
                my $class_hash = PBDB::TaxaCache::getParents($dbt, [$classify_taxon_no], 'array_full');
                my @class_array = @{$class_hash->{$classify_taxon_no}};
		
		if ( $row->{taxon_no} )
		{
		    my $taxon = PBDB::TaxonInfo::getTaxa($dbt, {taxon_no=>$row->{taxon_no}},
							 ['taxon_name','taxon_rank','pubyr']);
		
		    unshift @class_array , $taxon;
		    
		    # Include the taxon itself in the classification, it my be a family and be an indet.

		    $classification->{$taxon->{taxon_rank}} = $taxon;
		    
		    if ( $taxon->{taxon_name} eq $row->{taxon_name} )
		    {
			$row->{synonym_name} = getSynonymName($dbt, $row->{taxon_no}, 
							      $taxon->{taxon_name});
		    }
		}
		
                $row = getClassOrderFamily($dbt,\$row,\@class_array);
		
		# row has the classification now, so stash it
		
		$classification->{class}{taxon_name} = $row->{class};
		$classification->{order}{taxon_name} = $row->{order};
		$classification->{family}{taxon_name} = $row->{family};
		
                # only $classification is being returned, so piggyback lft and
                #  rgt on it
                # I hate having to hit taxa_tree_cache with a separate SELECT,
                #  but you can't hit it until you already know there's a
                #  taxon_no you can use JA 23.1.07
                my $sql = "SELECT lft,rgt FROM $TAXA_TREE_CACHE WHERE taxon_no=$classify_taxon_no";
                my $lftrgtref = ${$dbt->getData($sql)}[0];
                $classification->{lft}{taxon_no} = $lftrgtref->{lft};
                $classification->{rgt}{taxon_no} = $lftrgtref->{rgt};
            }
	    
	    elsif ($doReclassify)
	    {
		$row->{'show_classification_select'} = 'YES';
		my $taxon_name = $row->{genus_name}; 
		$taxon_name .= " ($row->{subgenus_name})" if ($row->{subgenus_name});
		$taxon_name .= " $row->{species_name}";
		$taxon_name .= " $row->{subspecies_name}" if $row->{subspecies_name};
		
		if ( my @all_matches = PBDB::Taxon::getBestClassification($dbt,$row) )
		{
		    $are_reclassifications = 1;
		    $row->{'classification_select'} = 
			PBDB::Reclassify::classificationSelect($dbt, $row->{occurrence_no}, 
							       0, 1, \@all_matches, $row->{taxon_no}, 
							       $taxon_name);
		}
	    }
	}
	
	$row->{'hide_collection_no'} = 1;
	$html .= $hbo->populateHTML("taxa_display_row", $row);
    }
    
    return ($html,$classification,$are_reclassifications);
}

## sub getPaleoCoords
#	Description: Converts a set of floating point coordinates + min/max interval numbers.
#	             determines the age from the interval numbers and returns the paleocoords.
#	Arguments:   $dbh - database handle
#				 $dbt - database transaction object	
#				 $max_interval_no,$min_interval_no - max/min interval no
#				 $f_lngdeg, $f_latdeg - decimal lontitude and latitude
#	Returns:	 $paleolng, $paleolat - decimal paleo longitude and latitutde, or undefined
#                variables if a paleolng/lat can't be found 
#
##
sub getPaleoCoords {
    
    my ($dbt, $q, $max_interval_no, $min_interval_no, $f_lngdeg, $f_latdeg) = @_;
    
    my $dbh = $dbt->dbh;
    
    # If we weren't given at least one valid time interval, we cannot do the
    # computation.
    
    unless ( $max_interval_no > 0 || $min_interval_no )
    {
	return (0, 0, 0);
    }
    
    # Get early and late age boundaries, based on the time intervals.  If
    # $min_interval_no is not specified, it defaults to the same as
    # $max_interval_no.
    
    my ($sql, $result);
    
    my ($early_age, $late_age) = lookupAgeRange($dbh, $max_interval_no, $min_interval_no);
    
    #my $t = new PBDB::TimeLookup($dbt);
    #my @itvs; 
    #push @itvs, $max_interval_no if ($max_interval_no);
    #push @itvs, $min_interval_no if ($min_interval_no && $max_interval_no != $min_interval_no);
    #my $h = $t->lookupIntervals(\@itvs);
    
    my ($paleolat, $paleolng,$plng,$plat,$lngdeg,$latdeg,$pid); 
    if ($f_latdeg <= 90 && $f_latdeg >= -90  && $f_lngdeg <= 180 && $f_lngdeg >= -180 ) {
    #    my $colllowerbound =  $h->{$max_interval_no}{'base_age'};
    #    my $collupperbound;
    #    if ($min_interval_no)  {
    #        $collupperbound = $h->{$min_interval_no}{'top_age'};
    #    } else {        
    #        $collupperbound = $h->{$max_interval_no}{'top_age'};
    #    }
        my $collage = ( $early_age + $late_age ) / 2;
        $collage = int($collage+0.5);
        if ($collage <= 600 && $collage >= 0) {
            #dbg("collage $collage max_i $max_interval_no min_i $min_interval_no colllowerbound $colllowerbound collupperbound $collupperbound ");
	    
            # Get Map rotation information - needs maptime to be set (to collage)
            # rotx, roty, rotdeg get set by the function, needed by projectPoints below
            my $map_o = PBDB::Map->new($q, $dbt);
            $map_o->{maptime} = $collage;
            $map_o->readPlateIDs();
            $map_o->mapGetRotations();

            ($plng,$plat,$lngdeg,$latdeg,$pid) = $map_o->projectPoints($f_lngdeg,$f_latdeg);
            dbg("lngdeg: $lngdeg latdeg $latdeg");
            if ( $lngdeg !~ /NaN/ && $latdeg !~ /NaN/ )       {
                $paleolng = $lngdeg;
                $paleolat = $latdeg;
            } 
        }
    }

    dbg("Paleolng: $paleolng Paleolat $paleolat fx $f_lngdeg fy $f_latdeg plat $plat plng $plng pid $pid");
    return ($paleolng, $paleolat, $pid);
}


# lookupAgeRange ( dbh, interval_1, interval_2 )
# 
# Look up the early and late ages for the specified pair of interval_no
# values, and return the corresponding age range.  Note that they may be in
# either order, and one of them may be zero.

sub lookupAgeRange {
    
    my ($dbh, $interval_1, $interval_2) = @_;
    
    # Make sure that we have at least one good interval number.
    
    return (0, 0) unless $interval_1 > 0 || $interval_2 > 0;
    
    # If one of them is zero, it defaults to the other.
    
    $interval_2 ||= $interval_1;
    $interval_1 ||= $interval_2;
    
    # Make sure that the values are actually numbers.
    
    $interval_1 += 0;
    $interval_2 += 0;
    
    # Now look up the first one.
    
    my $sql = "SELECT early_age, late_age FROM $INTERVAL_DATA
	       WHERE interval_no = $interval_1";
    
    my ($early_age_1, $late_age_1) = $dbh->selectrow_array($sql);
    
    # If the second one is the same, we're done.
    
    if ( $interval_2 == $interval_1 )
    {
	return ($early_age_1, $late_age_1);
    }
    
    # Otherwise, look up the other one as well.  Return the earlier of the
    # early ages and the later of the late ages.
    
    $sql = "	SELECT early_age, late_age FROM $INTERVAL_DATA
		WHERE interval_no = $interval_2";
    
    my ($early_age_2, $late_age_2) = $dbh->selectrow_array($sql);
    
    return ($early_age_1 > $early_age_2 ? $early_age_1 : $early_age_2,
	    $late_age_1 < $late_age_2 ? $late_age_1 : $late_age_2);
}


## setSecondaryRef($dbt, $collection_no, $reference_no)
# 	Description:	Checks if reference_no is the primary reference or a 
#					secondary reference	for this collection.  If yes to either
#					of those, nothing is done, and the method returns.
#					If the ref exists in neither place, it is added as a
#					secondary reference for the collection.
#
#	Parameters:		$dbh			the database handle
#					$collection_no	the collection being added or edited or the
#									collection to which the occurrence or ReID
#									being added or edited belongs.
#					$reference_no	the reference for the occ, reid, or coll
#									being updated or inserted.	
#
#	Returns:		boolean for running to completion.	
##
sub setSecondaryRef{
	my $dbt = shift;
	my $collection_no = shift;
	my $reference_no = shift;

    unless ($collection_no =~ /^\d+$/ && $reference_no =~ /^\d+$/) {
        return;
    }

	return if(isRefPrimaryOrSecondary($dbt, $collection_no, $reference_no));

	# If we got this far, the ref is not associated with the collection,
	# so add it to the secondary_refs table.
	my $sql = "INSERT IGNORE INTO secondary_refs (collection_no, reference_no) ".
		   "VALUES ($collection_no, $reference_no)";
	my $undo_sql = "DELETE FROM secondary_refs WHERE collection_no = $collection_no AND reference_no = $reference_no";

    my $dbh_r = $dbt->dbh;
    my $return = $dbh_r->do($sql);
	dbg("ref $reference_no added as secondary for collection $collection_no");
	
	PBDB::DBTransactionManager::logEvent({ stmt => 'INSERT',
					 table => 'secondary_refs',
					 key => 'collection_no, reference_no',
					 keyval => "$collection_no, $reference_no",
					 sql => $sql,
					 undo_sql => $undo_sql });
	
	return 1;
}

## refIsDeleteable($dbt, $collection_no, $reference_no)
#
#	Description		determines whether a reference may be disassociated from
#					a collection based on whether the reference has any
#					occurrences tied to the collection
#
#	Parameters		$dbh			database handle
#					$collection_no	collection to which ref is tied
#					$reference_no	reference in question
#
#	Returns			boolean
#
##
sub refIsDeleteable {
	my $dbt = shift;
	my $collection_no = shift;
	my $reference_no = shift;

    unless ($collection_no =~ /^\d+$/ && $reference_no =~ /^\d+$/) {
        return;
    }
	
	my $sql = "SELECT count(occurrence_no) cnt FROM occurrences ".
			  "WHERE collection_no=$collection_no ".
			  "AND reference_no=$reference_no";
    my $cnt = ${$dbt->getData($sql)}[0]->{'cnt'};

	if($cnt >= 1){
		dbg("Reference $reference_no has $cnt occurrences and is not deletable");
		return 0;
	} else {
		dbg("Reference $reference_no has $cnt occurrences and is deletable");
		return 1;
	}
}

## deleteRefAssociation($dbt, $collection_no, $reference_no)
#
#	Description		Removes association between collection_no and reference_no
#					in the secondary_refs table.
#
#	Parameters		$dbh			database handle
#					$collection_no	collection to which ref is tied
#					$reference_no	reference in question
#
#	Returns			boolean
#
##
sub deleteRefAssociation {
	my $dbt = shift;
	my $collection_no = shift;
	my $reference_no = shift;

    unless ($collection_no =~ /^\d+$/ && $reference_no =~ /^\d+$/) {
        return;
    }

	my $sql = "DELETE FROM secondary_refs where collection_no=$collection_no AND reference_no=$reference_no";
    dbg("Deleting secondary ref association $reference_no from collection $collection_no");
    my $dbh_r = $dbt->dbh;
    my $return = $dbh_r->do($sql);
	
	my $undo_sql = "INSERT INTO secondary_refs (collection_no, reference_no) VALUES ($collection_no, $reference_no)";
	
	PBDB::DBTransactionManager::logEvent({ stmt => 'DELETE',
					 table => 'secondary_refs',
					 key => 'collection_no, reference_no',
					 keyval => "$collection_no, $reference_no",
					 sql => $sql,
					 undo_sql => $undo_sql });
	
	return 1;
}

## isRefPrimaryOrSecondary($dbt, $collection_no, $reference_no)
#
#	Description	Checks the collections and secondary_refs tables to see if
#				$reference_no is either the primary or secondary reference
#				for $collection
#
#	Parameters	$dbh			database handle
#				$collection_no	collection with which ref may be associated
#				$reference_no	reference to check for association.
#
#	Returns		positive value if association exists (1 for primary, 2 for
#				secondary), or zero if no association currently exists.
##	
sub isRefPrimaryOrSecondary{
	my $dbt = shift;
	my $collection_no = shift;
	my $reference_no = shift;

    my $dbh = $dbt->dbh;

	# First, see if the ref is the primary.
	my $sql = "SELECT reference_no from collections WHERE collection_no=$collection_no";

    my $sth = $dbh->prepare($sql);
    $sth->execute();
    my $result_hash = $sth->fetchrow_hashref();
    return 0 unless ref $result_hash;
    my %results = %$result_hash;
    $sth->finish();

	# If the ref is the primary, nothing need be done.
	if($results{reference_no} == $reference_no){
		dbg("ref $reference_no exists as primary for collection $collection_no");
		return 1;
	}

	# Next, see if the ref is listed as a secondary
	$sql = "SELECT reference_no from secondary_refs ".
			  "WHERE collection_no=$collection_no";

    $sth = $dbh->prepare($sql);
    $sth->execute();
    my @results = @{$sth->fetchall_arrayref({})};
    $sth->finish();

	# Check the refs for a match
	foreach my $ref (@results){
		if($ref->{reference_no} == $reference_no){
		    dbg("ref $reference_no exists as secondary for collection $collection_no");
			return 2;
		}
	}

	# If we got this far, the ref is neither primary nor secondary
	return 0;
}


my $PI = 3.14159265;

# returns great circle distance given two latitudes and a longitudinal offset
sub GCD { ( 180 / $PI ) * acos( ( sin($_[0]*$PI/180) * sin($_[1]*$PI/180) ) + ( cos($_[0]*$PI/180) * cos($_[1]*$PI/180) * cos($_[2]*$PI/180) ) ) }

sub acos {
    my $a;
    if ($_[0] > 1 || $_[0] < -1) {
        $a = 1;
    } else {
        $a = $_[0];
    }
    atan2( sqrt(1 - $a * $a), $a )
}

1;

