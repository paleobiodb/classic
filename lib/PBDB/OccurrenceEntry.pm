# includes entry functions extracted from Collection.pm JA 4.6.13

package PBDB::OccurrenceEntry;
use strict;

use PBDB::Debug qw(dbg);
use URI::Escape;    
use Carp qw(carp croak);
use PBDB::Constants qw($COLLECTIONS $OCCURRENCES $WRITE_URL makeAnchor makeFormPostTag);


sub displayOccurrenceAddEdit {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $dbh = $dbt->dbh;
    my $output = '';
    
    # Grab the collection name for display purposes JA 1.10.02
    
    my $collection_no = $q->param('collection_no');
    
    my $sql = "SELECT collection_name FROM collections WHERE collection_no=$collection_no";
    
    my ($collection_name) = $dbh->selectrow_array($sql);
    
    # get the occurrences right away because we need to make sure there
    #  aren't too many to be displayed
    $sql = "SELECT * FROM occurrences WHERE collection_no=$collection_no ORDER BY occurrence_no ASC";
    my $sth = $dbh->prepare( $sql ) || die ( "$sql<hr>$!" );
    $sth->execute();
    
    my $p = PBDB::Permissions->new($s,$dbt);
    my @all_data = $p->getReadWriteRowsForEdit($sth);
    
    # first check to see if there are too many rows to display, in which
    #  case display links going to different batches of occurrences and
    #  then bomb out JA 26.7.04
    # don't do this if the user already has gone through one of those
    #  links, so rows_to_display has a useable value
    
    if ( $#all_data > 49 && $q->param("rows_to_display") !~ / to / )
    {
	$output .= "<center><p class=\"pageTitle\">Please select the rows you wish to edit</p></center>\n\n";
	$output .= "<center>\n";
	$output .= "<table><tr><td>\n";
	$output .= "<ul>\n";
	
        my ($startofblock,$endofblock);
	
	for my $rowset ( 1..100 )
	{
	    $endofblock = $rowset * 50;
	    $startofblock = $endofblock - 49;
	    
	    if ( $#all_data >= $endofblock )
	    {
		$output .= "<li>" . makeAnchor("displayOccurrenceAddEdit", "collection_no=$collection_no&rows_to_display=$startofblock+to+$endofblock", "Rows <b>$startofblock</b> to <b>$endofblock</b>");
	    }
	    
	    if ( $#all_data < $endofblock + 50 )
	    {
		$startofblock = $endofblock + 1;
		$endofblock = $#all_data + 1;
		$output .= "<li>" . makeAnchor("displayOccurrenceAddEdit", "collection_no=$collection_no&rows_to_display=$startofblock+to+$endofblock", "Rows <b>$startofblock</b> to <b>$endofblock</b>");
		last;
	    }
	}
	
	$output .= "</ul>\n\n";
	$output .= "</td></tr></table>\n";
	$output .= "</center>\n";
	return $output;
    }
    
    # Otherwise, display the rows indicated by "rows_to_display", or else all of them.
    
    my $firstrow = 0;
    my $lastrow = $#all_data;
    
    if ( $q->param("rows_to_display") =~ / to / )	{
	($firstrow,$lastrow) = split / to /,$q->param("rows_to_display");
	$firstrow--;
	$lastrow--;
    }
    
    my %pref = $s->getPreferences();
    
    $output .= <<END_HEADER;
<script src="/public/classic_js/check_occurrences.js"></script>

<form name="occurrenceList" method="post" action="$WRITE_URL" onSubmit='return checkForm();'>
<input name="action" value="processEditOccurrences" type=hidden>
<input name="list_collection_no" value="$collection_no" type=hidden>
<input name="check_status" type="hidden">

END_HEADER
    
    my @optional = ('subgenera','genus_and_species_only','abundances','plant_organs');
    
    my $header_vars = {
		       'collection_no'=>$collection_no,
		       'collection_name'=>$collection_name
		      };
    
    $header_vars->{$_} = $pref{$_} for (@optional);
    $header_vars->{collection_number} = '[' . makeAnchor("displayCollectionForm", "collection_no=$collection_no", $collection_no) . ']';
    $output .= $hbo->populateHTML('occurrence_header_row', $header_vars);
    
    # main loop
    # each record is represented as a hash
    
    my $gray_counter = 0;
    
    foreach my $all_data_index ($firstrow..$lastrow)
    {
    	my $occ_row = $all_data[$all_data_index];
	
	# This essentially empty reid_no is necessary as 'padding' so that
	# any actual reid number (see while loop below) will line up with 
	# its row in the form, and ALL rows (reids or not) will be processed
	# properly by processEditOccurrences(), below.
	
        $occ_row->{'reid_no'} = '0';
        formatOccurrenceTaxonName($occ_row);
	
        # Copy over optional fields;
        $occ_row->{$_} = $pref{$_} for (@optional);
	
        # Read Only
        my $occ_read_only = ($occ_row->{'writeable'} == 0) ? "all" : ""; 
	
        $occ_row->{'darkList'} = ($occ_read_only eq 'all' && $gray_counter%2 == 0) ? "darkList" : "";
	$occ_row->{reference_link} = makeAnchor("displayReference", 
						"type=view&reference_no=$occ_row->{reference_no}", "view")
	    if $occ_row->{reference_no};
	
        $output .= $hbo->populateHTML("occurrence_edit_row", $occ_row, [$occ_read_only]);
	
        my @reid_rows;
	
        my $sql = "SELECT * FROM reidentifications WHERE occurrence_no=" .  $occ_row->{'occurrence_no'};
	
        @reid_rows = @{$dbt->getData($sql)};
	
        foreach my $re_row (@reid_rows)
	{
            formatOccurrenceTaxonName($re_row);
            # Copy over optional fields;
            $re_row->{$_} = $pref{$_} for (@optional);

            # Read Only
            my $re_read_only = $occ_read_only;
            $re_row->{'darkList'} = $occ_row->{'darkList'};
	    $re_row->{reference_link} = makeAnchor("displayReference", "type=view&reference_no=$re_row->{reference_no}", "view")
		if $re_row->{reference_no};
            
            $output .= $hbo->populateHTML("reid_edit_row", $re_row, [$re_read_only]);
        }
	
        $gray_counter++;
    }
    
    # Extra rows for adding new occurrences
    
    my $blank = {'collection_no'=>$collection_no,
		 'reference_no'=>$s->get('reference_no'),
		 'occurrence_no'=>-1,
		 'taxon_name'=>$pref{'species_name'}
		};
    
    if ( $blank->{'species_name'} eq " " )	{
	$blank->{'species_name'} = "";
    }
    
    # Copy over optional fields;
    $blank->{$_} = $pref{$_} for (@optional,'species_name');
    
    # Figure out the number of blanks to print
    my $blanks = $pref{'blanks'} || 10;
    
    for ( my $i = 0; $i<$blanks ; $i++)
    {
	$output .= $hbo->populateHTML("occurrence_entry_row", $blank);
    }

    $output .= "</table><br>\n";
    $output .= "<p>Delete entries by erasing the taxon name.</p>\n";
    $output .= qq|<center><p><input type=submit value="Save changes">|;
    $output .= " to collection ${collection_no}'s taxonomic list</p></center>\n";
    $output .= "</div>\n\n</form>\n\n";
    
    return $output;
} 


# JA 5.7.07
sub formatOccurrenceTaxonName {
    
    my ($occ_row) = @_;
    
    my $taxon_name;
    
    my $genus_name = $occ_row->{genus_name} || '*Missing genus*';
    my $species_name = $occ_row->{species_name} || '*Missing species*';
    
    if ( $occ_row->{genus_reso} )
    {
        if ( $occ_row->{genus_reso} eq '"' )
	{
	    $taxon_name = "\"$genus_name\"";
        }
	
	elsif ( $occ_row->{genus_reso} eq 'informal' )
	{
	    $taxon_name = "<$genus_name>";
	}
	
	else
	{
            $taxon_name = "$occ_row->{genus_reso} $genus_name";
        }
    }
    
    else
    {
	$taxon_name = $genus_name;
    }
    
    if ( $occ_row->{subgenus_name} )
    {
        if ( $occ_row->{subgenus_reso} )
	{
            if ( $occ_row->{subgenus_reso} eq '"' )
	    {
		$taxon_name .= " (\"$occ_row->{subgenus_name}\")";
            }
	    
	    elsif ( $occ_row->{subgenus_reso} eq 'informal' )
	    {
                $taxon_name .= " (<$occ_row->{subgenus_name}>)";
            }
	    
	    else
	    {
                $taxon_name .= " $occ_row->{subgenus_reso} ($occ_row->{subgenus_name})";
            }
        }
	
	else
	{
	    $taxon_name .= " ($occ_row->{subgenus_name})";
	}
    }
    
    if ( $occ_row->{species_reso} )
    {
        if ( $occ_row->{species_reso} eq '"' )
	{
	    $taxon_name .= " \"$species_name\"";
        }
	
	elsif ( $occ_row->{species_reso} eq 'informal' )
	{
	    $taxon_name .= " <$species_name>";
        }
	
	else
	{
            $taxon_name .= " $occ_row->{species_reso} $species_name";
        }
    }
    
    else
    {
	$taxon_name .= " $species_name";
    }
    
    if ( $occ_row->{subspecies_name} )
    {
	if ( $occ_row->{subspecies_reso} )
	{
	    if ( $occ_row->{subspecies_reso} eq '"' )
	    {
		$taxon_name .= " \"$occ_row->{subspecies_name}\"";
	    }
	    
	    elsif ( $occ_row->{subspecies_reso} eq 'informal' )
	    {
		$taxon_name .= " <$occ_row->{subspecies_name}>";
	    }
	    
	    else
	    {
		$taxon_name .= " $occ_row->{subspecies_reso} $occ_row->{subspecies_name}";
	    }
	}
	
	else
	{
	    $taxon_name .= " $occ_row->{subspecies_name}";
	}
    }
    
    $occ_row->{taxon_name} = $taxon_name;
    
    return ($occ_row);
}


sub displayOccurrenceListForm	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my %vars;
    my $collection_no = $q->param('collection_no');
    my $sql = "(SELECT o.genus_reso,o.genus_name,o.species_reso,o.species_name FROM occurrences o LEFT JOIN reidentifications r ON o.occurrence_no=r.occurrence_no WHERE o.collection_no=$collection_no AND r.reid_no IS NULL) UNION (SELECT r.genus_reso,r.genus_name,r.species_reso,r.species_name FROM occurrences o LEFT JOIN reidentifications r ON o.occurrence_no=r.occurrence_no WHERE o.collection_no=$collection_no AND r.most_recent='YES') ORDER BY genus_name,species_name";
    my @occs = @{$dbt->getData($sql)};

    if ( @occs )
    {
	$vars{'old_occurrences'} = "You can only add occurrences with this form. The existing ones are: ";
	my @ids;
	for my $o ( @occs )
	{
	    $o->{'genus_reso'} =~ s/informal|"//;
	    $o->{'species_reso'} =~ s/informal|"//;
	    my ($gr,$gn,$sr,$sn) = ($o->{'genus_reso'},$o->{'genus_name'},$o->{'species_reso'},$o->{'species_name'});
	    
	    my $id = $gn;
	    if ( $gr )	{
		$id = $gr." ".$id;
	    }
	    if ( $sr )	{
		$id .= " ".$sr;
	    }
	    $id .= " ".$sn;
	    if ( $sn !~ /indet\./ )	{
		$id = "<i>".$id."</i>";
	    }
	    push @ids , $id;
	}
	$vars{'old_occurrences'} .= join(', ',@ids);
    }
    
    $sql = "SELECT collection_name FROM $COLLECTIONS WHERE collection_no=$collection_no";
    $vars{'collection_name'} = ${$dbt->getData($sql)}[0]->{'collection_name'};
    
    $vars{collection_no} = $collection_no;
    $vars{'collection_no_field'} = 'collection_no';
    $vars{'collection_no_field2'} = 'collection_no';
    $vars{'list_collection_no'} = $collection_no;
    $vars{'reference_no'} = $s->get('reference_no');
    my $output = $hbo->populateHTML('occurrence_list_form',\%vars);
    
    return $output;
}


sub displayOccsForReID {
    
    my ($q, $s, $dbt, $hbo, $collNos) = @_;
    
    my $dbh = $dbt->dbh;
    
    my $collection_no = $q->numeric_param('collection_no');
    my $taxon_name = $q->param('taxon_name');
    my $where = "";
    
    # my $collNos = shift;
    my @colls;
    
    if ($collNos)
    {
	@colls = @{$collNos};
    }
    
    my $printCollDetails = 0;
    
    my $output = $hbo->populateHTML('js_occurrence_checkform');
    
    my $pageNo = $q->param('page_no');
    
    if ( ! $pageNo )
    { 
	$pageNo = 1;
    }
    
    my $current_session_ref = $s->get("reference_no");
    my $ref = PBDB::Reference::getReference($dbt,$current_session_ref);
    
    my $formatted_primary = PBDB::Reference::formatLongRef($ref);
    my $refString = "<b>" . makeAnchor("displayReference", "reference_no=$current_session_ref", "$current_session_ref") . "</b> $formatted_primary<br>";
    
    # Build the SQL
    
    my (@where1, @where2);
    my $printCollectionDetails = 0;
    
    # Don't build it directly from the genus_name or species_name, let dispalyCollResults
    # DO that for us and pass in a set of collection_nos, for consistency, then filter at the end
    
    if (! @colls && $q->numeric_param('collection_no'))
    {
	push @colls , $q->numeric_param('collection_no');
    }
    
    if (@colls)
    {
	$printCollectionDetails = 1;
	push @where1, "o.collection_no IN (".join(',',@colls).")";
	push @where2, "o.collection_no IN (".join(',',@colls).")";
	
	my ($genus,$subgenus,$species,$subspecies) = PBDB::Taxon::splitTaxon($q->param('taxon_name'));
	
	if ( $genus )
	{
	    my $names = $dbh->quote($genus);
	    if ($subgenus)
	    {
		$names .= ", ".$dbh->quote($subgenus);
	    }
	    push @where1, "(o.genus_name IN ($names) OR o.subgenus_name IN ($names))";
	    push @where2, "(re.genus_name IN ($names) OR re.subgenus_name IN ($names))";
	}
	
	push @where1, "o.species_name LIKE " . $dbh->quote($species) if $species;
	push @where1, "o.subspecies_name LIKE " . $dbh->quote($subspecies) if $subspecies;
	
	push @where2, "re.species_name LIKE " . $dbh->quote($species) if $species;
	push @where2, "re.subspecies_name LIKE " . $dbh->quote($subspecies) if $subspecies;
    }
    
    else
    {
	push @where1, "0=1";
	push @where2, "0=1";
    }
    
    # some occs are out of primary key order, so order them JA 26.6.04
    
    my $sql = "(SELECT o.* FROM occurrences as o WHERE " . join(" AND ",@where1) . "\nUNION\n" .
	"SELECT o.* FROM occurrences as o join reidentifications as re using (occurrence_no)
	WHERE " . join(" AND ",@where2) . ")";
    
    my $sortby = $q->param('sort_occs_by');
    
    if ( $sortby && $sortby =~ /^\w+$/ )
    {
	$sql .= " ORDER BY $sortby";
	if ( $q->param('sort_occs_order') eq "desc" )
	{
	    $sql .= " DESC";
	}
    }
    
    my $limit = 1 + 10 * $pageNo;
    $sql .= " LIMIT $limit";
    
    dbg("$sql<br>");
    my @results = @{$dbt->getData($sql)};
    
    my $rowCount = 0;
    my %pref = $s->getPreferences();
    my @optional = ('subgenera','genus_and_species_only','abundances','plant_organs','species_name');
    
    if ( @results )
    {
        my $header_vars = {
            'ref_string'=>$refString,
            'search_taxon_name'=>$taxon_name,
            'list_collection_no'=>$collection_no
        };
        
	$header_vars->{$_} = $pref{$_} for (@optional);
	$output .= $hbo->populateHTML('reid_header_row', $header_vars);
	
	splice @results , 0 , ( $pageNo - 1 ) * 10;
	
        foreach my $row ( @results )
	{
            my $html = "";
            # If we have 11 rows, skip the last one; and we need a next button
            $rowCount++;
            last if $rowCount > 10;

            # Print occurrence row and reid input row
            $html .= "<tr>\n";
            $html .= "    <td align=\"left\" style=\"padding-top: 0.5em;\">".$row->{"genus_reso"};
            $html .= " ".$row->{"genus_name"};
	    
            if ($pref{'subgenera'} eq "yes")
	    {
                $html .= " ".$row->{"subgenus_reso"};
                $html .= " ".$row->{"subgenus_name"};
            }
	    
            $html .= " " . $row->{"species_reso"};
            $html .= " " . $row->{"species_name"};
	    
	    if ( $row->{subspecies_name} )
	    {
		$html .= " " . $row->{subspecies_reso};
		$html .= " " . $row->{subspecies_name};
	    }
	    
	    $html . "</td>\n";
            $html .= " <td>". $row->{"comments"} . "</td>\n";
	    
            if ($pref{'plant_organs'} eq "yes")
	    {
                $html .= "    <td>" . $row->{"plant_organ"} . "</td>\n";
                $html .= "    <td>" . $row->{"plant_organ2"} . "</td>\n";
            }
	    
            $html .= "</tr>";
	    
            if ($current_session_ref == $row->{'reference_no'})
	    {
                $html .= "<tr><td colspan=20><i>The current reference is the same as the original reference, so this taxon may not be reidentified.</i></td></tr>";
            }
	    
	    else
	    {
                my $vars = {
                    'collection_no'=>$row->{'collection_no'},
                    'occurrence_no'=>$row->{'occurrence_no'},
                    'reference_no'=>$current_session_ref
                };
                $vars->{$_} = $pref{$_} for (@optional);
                $html .= $hbo->populateHTML('reid_entry_row',$vars);
            }

            # print other reids for the same occurrence

            $html .= "<tr><td colspan=100>";
            my ($table,$classification) = PBDB::CollectionEntry::getReidHTMLTableByOccNum($dbt,$hbo,$s,$row->{'occurrence_no'}, 0);
            $html .= "<table>".$table."</table>";
            $html .= "</td></tr>\n";
            #$sth2->finish();
            
            my $ref = PBDB::Reference::getReference($dbt,$row->{'reference_no'});
            my $formatted_primary = PBDB::Reference::formatShortRef($ref);
            my $refString = '<b>' . makeAnchor("displayReference", "reference_no=$row->{reference_no}", "$row->{reference_no}") . "</b>&nbsp;$formatted_primary";

            $html .= "<tr><td colspan=20 class=\"verysmall\" style=\"padding-bottom: 0.75em;\">Original reference: $refString<br>\n";
            # Print the collections details
            if ( $printCollectionDetails )
	    {
                my $sql = "SELECT collection_name,state,country,formation,period_max FROM collections WHERE collection_no=" . $row->{'collection_no'};
                my $sth = $dbh->prepare( $sql ) || die ( "$sql<hr>$!" );
                $sth->execute();
                my %collRow = %{$sth->fetchrow_hashref()};
                $html .= "Collection:";
                my $details = makeAnchor("basicCollectionSearch", "collection_no=$row->{'collection_no'}", "$row->{'collection_no'}") . " " . $collRow{'collection_name'};
		
                if ($collRow{'state'} && $collRow{'country'} eq "United States")
		{
                     $details .= " - " . $collRow{'state'};
		 }
		
                if ($collRow{'country'})
		{
                    $details .= " - " . $collRow{'country'};
                }
		
                if ($collRow{'formation'})
		{
                    $details .= " - " . $collRow{'formation'} . " Formation";
                }
		
                if ($collRow{'period_max'})
		{
                    $details .= " - " . $collRow{'period_max'};
                }
		
                $html .= "$details </td>";
                $html .= "</tr>";
                $sth->finish();
            }
        
            #$html .= "<tr><td colspan=100><hr width=100%></td></tr>";
	    
            if ($rowCount % 2 == 1)
	    {
                $html =~ s/<tr/<tr class=\"darkList\"/g;
            }
	    
	    else
	    {
                $html =~ s/<tr/<tr class=\"lightList\"/g;
            }
	    
            $output .= $html;
        }
    }
    
    $output .= "</table>\n";
    $pageNo++;
    
    if ($rowCount > 0)
    {
	$output .= qq|<center><p><input type=submit value="Save reidentifications"></center></p>\n|;
	$output .= qq|<input type="hidden" name="page_no" value="$pageNo">\n|;
	$output .= qq|<input type="hidden" name="sort_occs_by" value="|;
	$output .= $q->param('sort_occs_by') . "\">\n";
	$output .= qq|<input type="hidden" name="sort_occs_order" value="|;
	$output .= $q->param('sort_occs_order') . "\">\n";
    }
    
    else
    {
	$output .= "<center><p class=\"pageTitle\">Sorry! No matches were found</p></center>\n";
	$output .= "<p align=center>Please " . makeAnchor("displayReIDCollsAndOccsSearchForm", "", "try again") . " with different search terms</p>\n";
    }
    
    $output .= "</form>\n";
    $output .= "\n<table border=0 width=100%>\n<tr>\n";
    
    # Print prev and next  links as appropriate
    
    # Next link
    
    if ( $rowCount > 10 )
    {
        my $localsort_occs_by=$q->param('sort_occs_by');
        my $localsort_occs_order=$q->param('sort_occs_order');
	$output .= "<td align=center>";
	$output .= "<b>" . makeAnchor("displayCollResults", "type=reid&taxon_name=$taxon_name&collection_no=$collection_no&sort_occs_by=$localsort_occs_by&sort_occs_order=$localsort_occs_order&page_no=$pageNo", "Skip to the next 10 occurrences") . "</b>";
	$output .= "</td></tr>\n";
	$output .= "<tr><td class=small align=center><i>Warning: if you go to the next page without saving, your changes will be lost</i></td>\n";
    }
    
    $output .= "</tr>\n</table><p>\n";
    
    return $output;
}


# This function now handles inserting/updating occurrences, as well as inserting/updating reids
# Rewritten PS to be a bit clearer, handle deletions of occurrences, and use DBTransationManager
# for consistency/simplicity.

# Rewritten MM 2024-07-30

sub processEditOccurrences {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $dbh = $dbt->dbh;
    my $output = '';
    
    # list of the number of rows to possibly update.
    my @rowTokens;
    
    # parse freeform all-in-one-textarea lists passed in by
    #  displayOccurrenceListForm JA 19-20.5.09
    my $collection_no = $q->numeric_param('collection_no');
    my $reference_no = $q->numeric_param('reference_no');
    
    if ( ref $collection_no eq 'ARRAY' )
    {
	$collection_no = $collection_no->[0];
    }
    
    if ( ref $reference_no eq 'ARRAY' )
    {
	$reference_no = $reference_no->[0];
    }
    
    # If the submitted form is the "add_edit_occurrence" form.
    
    if ( $q->param('row_token') )
    {
	@rowTokens = $q->param('row_token');
    }
    
    # If the submitted form is the "occurrence_list" form.
    
    elsif ( $q->param('taxon_list') )
    {
	my @lines = split /[\n\r]+/, $q->param('taxon_list');
	
	my (@names,@comments,@colls,@refs,@occs,@reids);
	
	for my $l ( 0..$#lines )
	{
	    if ( $lines[$l] !~ /[A-Za-z0-9]/ )	{
		next;
	    }
	    if ( $lines[$l] =~ /^[\*#\/]/ && $#names == $#comments + 1 )	{
		$lines[$l] =~ s/^[\*#\/]//g;
		push @comments , $lines[$l];
	    } elsif ( $lines[$l] =~ /^[\*#\/]/ )	{
		$lines[$l] =~ s/^[\*#\/]//;
		$comments[$#comments] .= "\n".$lines[$l];
	    } else	{
		push @names , $lines[$l];
		while ( $#names > $#comments + 1 )	{
		    push @comments , "";
		}
	    }
	}
	
	push @colls , $collection_no foreach @names;
	push @refs , $reference_no foreach @names;
	push @rowTokens , "row_token" foreach @names;
	push @occs , -1 foreach @names;
	push @reids , -1 foreach @names;
	
	$q->param('taxon_name' => @names);
	$q->param('comments' => @comments);
	$q->param(collection_no => @colls);
	$q->param('reference_no' => @refs);
	$q->param(occurrence_no => @occs);
	$q->param('reid_no' => @reids);
    }
    
    else
    {
	return "<h2>This action is invalid.</h2>";
    }
    
    # Get the names of all the fields coming in from the form.
    my @param_names = $q->param();
    
    # list of required fields
    my @errors;
    my @warnings;
    my @occurrences;
    my @occurrences_to_delete;
    my @matrix;
    
    my (@genera, @subgenera, @species, @subspecies, @latin_names);
    
    # loop over all rows submitted from the form
    
    for (my $i = 0; $i < @rowTokens; $i++)
    {
        # Flatten the table into a single row, for easy manipulation
        my %fields;
	
        foreach my $param (@param_names)
	{
            my @vars = $q->param($param);
            if (scalar(@vars) == 1) {
                $fields{$param} = $vars[0];
            } else {
                $fields{$param} = $vars[$i];
            }
        }
	
        my $rowno = $i + 1;

        # Extract the genus, subgenus, and species names and resos
        #  JA 5.7.07
	# Rewritten by MM 2024-08-09 - now includes subspecies
	
        if ( $fields{taxon_name} )
	{
            my $name = $fields{taxon_name};
	    
	    # Check for n. gen., n. sp., etc.  These have an unambiguous meaning
	    # wherever they occur. Removing them may leave extra spaces in the
	    # name.
	    
	    if ( $name =~ /(.*)n[.] gen[.](.*)/ )
	    {
		$fields{genus_reso} = "n. gen.";
		$name = "$1 $2";
	    }
	    
	    if ( $name =~ /(.*)n[.] subgen[.](.*)/ )
	    {
		$fields{subgenus_reso} = "n. subgen.";
		$name = "$1 $2";
	    }
	    
	    if ( $name =~ /(.*)n[.] sp[.](.*)/ )
	    {
		$fields{species_reso} = "n. sp.";
		$name = "$1 $2";
	    }
	    
	    if ( $name =~ /(.*)n[.] subsp[.](.*)/ )
	    {
		$fields{subspecies_reso} = "n. subsp.";
		$name = "$1 $2";
	    }
	    
	    # Now deconstruct the name component by component, using the same
	    # rules as the Javascript form checker.
	    
	    # Start with the genus and any qualifier that may precede it.
	    
	    if ( $name =~ /^\s*([?]|aff[.]|cf[.]|ex gr[.]|sensu lato)\s+(.*)/ )
	    {
		$fields{genus_reso} = $1;
		$name = $2;
	    }
	    
	    if ( $name =~ /^\s*<(.*?)>\s+(.*)/ )
	    {
		$fields{genus_reso} = 'informal';
		$fields{genus_name} = $1;
		$name = $2;
	    }
	    
	    elsif ( $name =~ /^\s*("?)([A-Za-z]+)("?)\s*(.*)/ )
	    {
		$fields{genus_reso} = $1 || '';
		$fields{genus_name} = $2;
		$name = $4;
		
		unless ( $1 eq $3 )
		{
		    push @errors, "Invalid name '$fields{taxon_name}': mismatched &quot; on genus";
		    next;
		}
	    }
	    
	    else
	    {
		push @errors, "Invalid name '$fields{taxon_name}': could not resolve genus";
		next;
	    }
	    
	    if ( $fields{genus_name} && $fields{genus_reso} ne 'informal' &&
		 $fields{genus_name} !~ /^[A-Z][a-z]+$/ )
	    {
		push @errors, "Invalid name '$fields{genus_name}': bad capitalization on genus";
	    }
	    
	    # Continue with a possible subgenus and preceding qualifier.
	    
	    if ( $name =~ /^([?]|aff[.]|cf[.]|ex gr[.]|sensu lato)\s+([(].*)/ )
	    {
		$fields{subgenus_reso} = $1;
		$name = $2;
	    }
	    
	    if ( $name =~ /^[(]<(.*?)>[)]\s+(.*)/ )
	    {
		$fields{subgenus_reso} = 'informal';
		$fields{subgenus_name} = $1;
		$name = $2;
	    }
	    
	    elsif ( $name =~ /^[(]("?)([A-Za-z]+)("?)[)]\s+(.*)/ )
	    {
		$fields{subgenus_reso} = $1 || '';
		$fields{subgenus_name} = $2;
		$name = $4;
		
		unless ( $1 eq $3 )
		{
		    push @errors, "Invalid name '$fields{taxon_name}': mismatched &quot; on subgenus";
		    next;
		}
	    }
	    
	    elsif ( $name =~ /[(]/ )
	    {
		push @errors, "Invalid name '$fields{taxon_name}': could not resolve subgenus";
		next;
	    }
	    
	    else
	    {
		$fields{subgenus_name} ||= '';
		$fields{subgenus_reso} ||= '';
	    }
	    
	    if ( $fields{subgenus_name} && $fields{subgenus_reso} ne 'informal' &&
		 $fields{subgenus_name} !~ /^[A-Z][a-z]+$/ )
	    {
		push @errors, "invalid name '$fields{taxon_name}': bad capitalization on subgenus";
	    }
	    
	    # Continue with a species name and any qualifier that may precede it.
	    
	    if ( $name =~ /^([?]|aff[.]|cf[.]|ex gr[.]|sensu lato)\s+(.*)/ )
	    {
		$fields{species_reso} = $1;
		$name = $2;
	    }
	    
	    if ( $name =~ /^<(.*?)>(.*)/ )
	    {
		$fields{species_reso} = 'informal';
		$fields{species_name} = $1;
		$name = $2;
	    }
	    
	    elsif ( $name =~ /^("?)([A-Za-z]+[.]?)("?)(.*)/ )
	    {
		$fields{species_reso} = $1 || '';
		$fields{species_name} = $2;
		$name = $4;
		
		unless ( $1 eq $3 )
		{
		    push @errors, "Invalid name '$fields{taxon_name}': mismatched &quot; on species";
		}
	    }
	    
	    elsif ( $fields{species_reso} && ! $fields{species_name}  )
	    {
		push @errors, "Invalid name '$fields{taxon_name}': could not resolve species";
		next;
	    }
	    
	    else
	    {
		$fields{species_reso} ||= '';
		$fields{species_name} ||= '';
	    }
	    
	    if ( $fields{species_name} && $fields{species_reso} ne 'informal' )
	    {
		if ( $fields{species_name} =~ /[.]$/ )
		{
		    if ( $fields{species_name} !~ /^(?:sp|spp|indet)[.]$/ )
		    {
			push @errors, "Invalid name '$fields{taxon_name}': " . 
			    "'$fields{species_name}' is not valid";
			next;
		    }
		}
		
		elsif ( $fields{species_name} !~ /^[a-z]+$/ )
		{
		    push @errors, "Invalid name '$fields{taxon_name}': bad capitalization on species";
		    next;
		}
	    }
	    
	    # Finish with a possible subspecies name and any qualifier that may precede it.
	    
	    if ( $name =~ /^\s+([?]|aff[.]|cf[.]|ex gr[.]|sensu lato)(.*)/ )
	    {
		$fields{subspecies_reso} = $1;
		$name = $2;
	    }
	    
	    if ( $name =~ /^\s+<(.*?)>(.*)/ )
	    {
		$fields{subspecies_reso} = 'informal';
		$fields{subspecies_name} = $1;
		$name = $2;
	    }
	    
	    elsif ( $name =~ /^\s+("?)([A-Za-z]+[.]?)("?)(.*)/ )
	    {
		$fields{subspecies_reso} = $1 || '';
		$fields{subspecies_name} = $2;
		$name = $4;
		
		unless ( $1 eq $3 )
		{
		    push @errors, "Invalid name '$fields{taxon_name}': mismatched &quot; on subspecies";
		}
	    }
	    
	    elsif ( $name && ! $fields{species_name} )
	    {
		push @errors, "Invalid name '$fields{taxon_name}': could not resolve species";
		next;
	    }
	    
	    elsif ( $fields{subspecies_reso} )
	    {
		push @errors, "Invalid name '$fields{taxon_name}': could not resolve subspecies";
		next;
	    }
	    
	    elsif ( $name )
	    {
		push @errors, "Invalid name '$fields{taxon_name}': could not parse '$name'";
		next;
	    }
	    
	    else
	    {
		$fields{subspecies_reso} ||= '';
		$fields{subspecies_name} ||= '';
	    }
	    
	    if ( $fields{subspecies_name} && $fields{subspecies_reso} ne 'informal' )
	    {
		if ( $fields{subspecies_name} =~ /[.]$/ )
		{
		    if ( $fields{subspecies_name} !~ /^(?:subsp|subspp|indet)[.]$/ )
		    {
			push @errors, "Invalid name '$fields{taxon_name}': " . 
			    "'$fields{subspecies_name}' is not valid";
			next;
		    }
		}
		
		elsif ( $fields{subspecies_name} !~ /^[a-z]+$/ )
		{
		    push @errors, "Invalid name '$fields{taxon_name}': bad capitalization on subspecies";
		    next;
		}
	    }
	    
	    # Now put the name back together again.
	    
            push @genera, $fields{genus_name};
            push @subgenera, $fields{subgenus_name};
            push @species, $fields{species_name};
	    push @subspecies, $fields{subspecies_name};
	    
	    $fields{latin_name} = '';
	    
	    # We can only resolve a taxonomic name if neither the genus nor the
	    # subgenus are informal. If the species is informal or is indet.
	    # etc. then the taxonomic name will stop with the first component or
	    # the subgenus.
	    
	    if ( $fields{genus_reso} ne 'informal' )
	    {
		$fields{latin_name} = $fields{genus_name};
		
		if ( $fields{subgenus_name} )
		{
		    $fields{latin_name} .= " ($fields{subgenus_name})";
		}
		
		if ( $fields{species_name} =~ /^[a-z]+$/ && 
		     $fields{species_reso} ne 'informal' )
		{
		    $fields{latin_name} .= " $fields{species_name}";
		    
		    if ( $fields{subspecies_name} =~ /^[a-z]+$/ && 
			 $fields{subspecies_reso} ne 'informal' )
		    {
			$fields{latin_name} .= " $fields{subspecies_name}";
		    }
		}
		
		push @latin_names, $fields{latin_name};
	    }
        }
	
	$matrix[$i] = \%fields;
	
	# end of first pass
    }
    
    # If any errors were found, don't process the list. Instead, throw up a
    # bulleted list of error messages with a link to go back to the occurrence
    # list and re-edit.  This should not actually happen, because the javascript
    # function in check_occurrences.js should catch bad names before they are
    # submitted.  But something might slip through.
    
    if ( @errors )
    {
	$output .= "<div class=\"errorMessage\"><ul>\n";
	
	foreach my $msg ( @errors )
	{
	    $output .= "<li>$msg</li>\n";
	}
	
	$output .= "</ul></div>\n";
	
	$output .= "<div style=\"text-align: center\"><form>\n";
	$output .= "<button onclick=\"history.back()\">Go back and edit the list</button>\n";
	$output .= "</form></div>\n";
	
	return $output;
    }
    
    # Check for duplicates JA 2.4.08
    # this section replaces the old occurrence-by-occurrence check that
    #  used checkDuplicates; it's much faster and uses more lenient
    #  criteria because isolated duplicates are handled by the JavaScript
    # Rewritten by MM 2024-08-09
    
    my $quoted_no = $dbh->quote($collection_no);
    
    my $sql = "	SELECT genus_reso, genus_name, subgenus_reso, subgenus_name, 
		    species_reso, species_name, subspecies_reso, subspecies_name, taxon_no
		FROM $OCCURRENCES WHERE collection_no = " . $quoted_no;
    
    my @occrefs = @{$dbt->getData($sql)};
    
    my %taxon_no;
    
    if ( $#occrefs > 0 )
    {
	my $newrows = 0;
	my $dupes = 0;
	my %check_row;
	
	for (my $i = 0; $i < @rowTokens; $i++)
	{
	    if ( $matrix[$i]{genus_name} =~ /^[A-Z][a-z]+$/ && $matrix[$i]{occurrence_no} == -1 )
	    {
		my $check_name = join('|', $matrix[$i]{genus_reso}, $matrix[$i]{genus_name},
				      $matrix[$i]{subgenus_reso}, $matrix[$i]{subgenus_name},
				      $matrix[$i]{species_reso}, $matrix[$i]{species_name},
				      $matrix[$i]{subspecies_reso}, $matrix[$i]{subspecies_name});
		
		$check_row{$check_name}++;
		$newrows++;
	    }
	}
	
	if ( $newrows > 0 )
	{
	    for my $occ ( @occrefs )
	    {
		my $check_name = join('|', $occ->{genus_reso}, $occ->{genus_name},
				      $occ->{subgenus_reso}, $occ->{subgenus_name},
				      $occ->{species_reso}, $occ->{species_name},
				      $occ->{subspecies_reso}, $occ->{subspecies_name});
		
		if ( $check_row{$check_name} > 0 )
		{
		    $dupes++;
		}
	    }
	    
	    if ( $newrows == $dupes && $newrows == 1 )
	    {
		push @warnings, "Nothing was entered or updated because " . 
		    "the new occurrence was a duplicate";
		@rowTokens = ();
	    }
	    
	    elsif ( $newrows == $dupes )
	    {
		push @warnings , "Nothing was entered or updated because " . 
		    "all the new records were duplicates";
		@rowTokens = ();
	    }
	    
	    elsif ( $dupes >= 3 )
	    {
		push @warnings , "Nothing was entered or updated because " . 
		    "there were too many duplicate entries";
		@rowTokens = ();
	    }
	}
	
	# while we're at it, store the taxon_no JA 20.7.08
	# do this here and not earlier because taxon_no is not
	# stored in the entry form
	
	for my $occ ( @occrefs )
	{
	    if ( $occ->{taxon_no} > 0 && $occ->{genus_reso} ne 'informal' &&
		 $occ->{subgenus_reso} ne 'informal' )
	    {
		my $latin_name = $occ->{genus_name};
		
		if ( $occ->{subgenus_name} =~ /^[A-Z][a-z]+$/ )
		{
		    $latin_name .= " ($occ->{subgenus_name})";
		}
		
		if ( $occ->{species_name} =~ /^[a-z]$/ && 
		     $occ->{species_reso} ne 'informal' )
		{
		    $latin_name .= " $occ->{species_name}";
		    
		    if ( $occ->{subspecies_name} =~ /^[a-z]$/ && 
			 $occ->{subspecies_reso} ne 'informal' )
		    {
			$latin_name .= " $occ->{subspecies_name}";
		    }
		}
		
		$taxon_no{$latin_name} = $occ->{'taxon_no'};
	    }
	}
    }
    
    # Get as many taxon numbers as possible at once JA 2.4.08
    # this greatly speeds things up because we now only need to use
    #  getBestClassification as a last resort
    
    # Rewritten by MM 2024-08-11. We only search on names that don't already
    # have a taxon number.
    
    my @filtered_names = grep { ! $taxon_no{$_} } @latin_names;
    
    my $name_string = join "','", @filtered_names;
    
    $sql = "	SELECT taxon_name, taxon_no, count(*) c FROM authorities
		WHERE taxon_name IN ('$name_string') GROUP BY taxon_name";
    
    my @taxonrefs = @{$dbt->getData($sql)};
    
    for my $tr ( @taxonrefs )
    {
	if ( $tr->{'c'} == 1 )	{
	    $taxon_no{$tr->{'taxon_name'}} = $tr->{'taxon_no'};
	} elsif ( $tr->{'c'} > 1 )	{
	    $taxon_no{$tr->{'taxon_name'}} = -1;
	}
    }
    
    # finally, check for n. sp. resos that appear to be duplicates and
    #  insert a type_locality number if there's no problem JA 14-15.12.08
    # this is not 100% because it will miss cases where a species was
    #  entered with "n. sp." using two different combinations
    # a couple of (fast harmless) checks in the section section are
    #  repeated here for simplicity
    
    my (@to_check, %dupe_colls);
    
    for (my $i = 0; $i < @rowTokens; $i++)
    {
	if ( $matrix[$i]{genus_name} eq "" && $matrix[$i]{occurrence_no} < 1 )
	{
	    next;
	}
        
	if ( $matrix[$i]{reference_no} !~ /^\d+$/ || $matrix[$i]{collection_no} !~ /^\d+$/ )
	{
	    next;
	}
	
	# guess the taxon no by trying to find a single match for the name
	#  in the authorities table JA 1.4.04
	# see Reclassify.pm for a similar operation
	# only do this for non-informal taxa
	# done here and not in the last pass because we need the taxon_nos
	
	my $latin_name = $matrix[$i]{latin_name};
	
	if ( $taxon_no{$latin_name} > 0 )
	{
	    $matrix[$i]{taxon_no} = $taxon_no{$latin_name};
	}
	
	elsif ( $taxon_no{$latin_name} eq "" )
	{
	    $matrix[$i]{taxon_no} = PBDB::Taxon::getBestClassification($dbt, $matrix[$i]);
	}
	
	else
	{
	    $matrix[$i]{taxon_no} = 0;
	}
	
	if ( $matrix[$i]{taxon_no} > 0 && $matrix[$i]{species_reso} eq "n. sp." )
	{
	    push @to_check , $matrix[$i]{taxon_no};
	}
    }
    
    if ( @to_check )
    {
	# pre-processing is faster than a join
	$sql = "SELECT taxon_no,taxon_name,type_locality FROM authorities WHERE taxon_no IN (".join(',',@to_check).") AND taxon_rank='species'";
	my @species = @{$dbt->getData($sql)};
	
	if ( @species )
	{
	    @to_check = ();
	    
	    push @to_check , $_->{taxon_no} foreach @species;
	    $sql = "(SELECT taxon_no,collection_no FROM occurrences WHERE collection_no!=$collection_no AND taxon_no in (".join(',',@to_check).") AND species_reso='n. sp.') UNION (SELECT taxon_no,collection_no FROM reidentifications WHERE collection_no!=$collection_no AND taxon_no in (".join(',',@to_check).") AND species_reso='n. sp.')";
	    
	    my @dupe_refs = @{$dbt->getData($sql)};
	    
	    if ( @dupe_refs )
	    {
		$dupe_colls{$_->{taxon_no}} .= ", ".$_->{collection_no} foreach @dupe_refs;
		for (my $i = 0;$i < @rowTokens; $i++)
		{
		    my %fields = %{$matrix[$i]};
		    if ( ! $dupe_colls{$fields{taxon_no}} || ! $fields{taxon_no} )
		    {
			next;
		    }
		    
		    $dupe_colls{$fields{taxon_no}} =~ s/^, //;
		    
		    if ( $dupe_colls{$fields{taxon_no}} =~ /^[0-9]+$/ )
		    {
                        # jpjenk-question
			push @warnings, "<a href=\"$WRITE_URL?a=displayAuthorityForm&amp;taxon_no=$fields{taxon_no}\"><i>$fields{genus_name} $fields{species_name}</i></a> has already been marked as new in collection $dupe_colls{$fields{taxon_no}}, so it won't be recorded as such in this one";
		    }
		    
		    elsif ( $dupe_colls{$fields{taxon_no}} =~ /, [0-9]/ )
		    {
			$dupe_colls{$fields{taxon_no}} =~ s/(, )([0-9]*)$/ and $2/;
			push @warnings, "<i>$fields{genus_name} $fields{species_name}</i> has already been marked as new in collections $dupe_colls{$fields{taxon_no}}, so it won't be recorded as such in this one";
		    }
		}
	    }
	    
	    my @to_update;
	    
	    for my $s ( @species )
	    {
		if ( ! $dupe_colls{$s->{taxon_no}} && $s->{type_locality} < 1 )
		{
		    push @to_update , $s->{taxon_no};
		}
		
		elsif ( ! $dupe_colls{$s->{taxon_no}} && $s->{type_locality} > 0 && $s->{type_locality} != $collection_no )
		{
                    # jpjenk-question
		    push @warnings, "The type locality of <a href=\"$WRITE_URL?a=displayAuthorityForm&amp;taxon_no=$s->{taxon_no}\"><i>$s->{taxon_name}</i></a> has already been marked as new in collection $s->{type_locality}, which seems incorrect";
		}
	    }
	    
	    if ( @to_update )
	    {
		$sql = "UPDATE authorities SET type_locality=$collection_no,modified=modified WHERE taxon_no IN (".join(',',@to_update).")";
		$dbh->do($sql);
		PBDB::Taxon::propagateAuthorityInfo($dbt,$_) foreach @to_update;
	    }
	}
    }
    
    # last pass, update/insert loop
    
    for (my $i = 0;$i < @rowTokens; $i++)
    {
	my %fields = %{$matrix[$i]};
	my $rowno = $i + 1;
	
	if ( $fields{genus_name} eq "" && $fields{occurrence_no} < 1 )
	{
		next;
	}
	
	# check that all required fields have a non empty value
	
        if ( $fields{reference_no} !~ /^\d+$/ && $fields{genus} =~ /[A-Za-z]/ )
	{
            push @warnings, "There is no reference number for row $rowno, so it was skipped";
            next; 
        }
	
        if ( $fields{collection_no} !~ /^\d+$/ )
	{
            push @warnings, "There is no collection number for row $rowno, so it was skipped";
            next; 
        }
	
	my $taxon_name = PBDB::CollectionEntry::formatOccurrenceTaxonName(\%fields);

        if ($fields{genus_name} =~ /^\s*$/)
	{
            if ($fields{occurrence_no} =~ /^\d+$/ && $fields{reid_no} != -1)
	    {
                # THIS IS AN UPDATE: CASE 1 or CASE 3. We will be deleting this record, 
                # Do nothing for now since this is handled below;
            }
	    
	    else
	    {
                # THIS IS AN INSERT: CASE 2 or CASE 4. Just do nothing, this is a empty row
                next;  
            }
        }
	
	else
	{
            if (!PBDB::Validation::validOccurrenceGenus($fields{genus_reso},
							$fields{genus_name}))
	    {
                push @warnings, "The genus ($fields{genus_name}) in row $rowno is blank " . 
		    "or improperly formatted, so it was skipped";
                next; 
            }
            
	    if ($fields{subgenus_name} !~ /^\s*$/ && 
		!PBDB::Validation::validOccurrenceGenus($fields{subgenus_reso},
							$fields{subgenus_name}))
	    {
                push @warnings, "The subgenus ($fields{subgenus_name}) in row $rowno is " . 
		    "improperly formatted, so it was skipped";
                next; 
            }
            
	    if ($fields{species_name} =~ /^\s*$/ || 
		!PBDB::Validation::validOccurrenceSpecies($fields{species_reso},
							  $fields{species_name}))
	    {
                push @warnings, "The species ($fields{species_name}) in row $rowno is blank " . 
		    "or improperly formatted, so it was skipped";
                next; 
            }
	    
	    if ($fields{subspecies_name} !~ /^\s*$/ && 
		!PBDB::Validation::validOccurrenceSpecies($fields{subspecies_reso}, 
							  $fields{subspecies_name}))
	    {
		push @warnings, "The subspecies ($fields{subspecies_name}) in row $rowno is " . 
		    "blank or imporperly formatted, so it was skipped";
		next;
	    }
        }
	
        if ($fields{occurrence_no} =~ /^\d+$/ && $fields{occurrence_no} > 0 &&
            (($fields{reid_no} =~ /^\d+$/ && $fields{reid_no} > 0) || ($fields{reid_no} == -1)))
	{
            # We're either updating or inserting a reidentification
	    
            my $sql = "SELECT reference_no FROM $OCCURRENCES 
			WHERE occurrence_no=$fields{occurrence_no}";
            my $occurrence_reference_no = ${$dbt->getData($sql)}[0]->{reference_no};
	    
            if ($fields{reference_no} == $occurrence_reference_no)
	    {
                push @warnings, "The occurrence of taxon $taxon_name in row $rowno and its " . 
		    "reidentification have the same reference number";
                next;
            }
	    
            # don't insert a new reID using a ref already used to reID this
            # occurrence 
	    
            if ( $fields{reid_no} == -1 )
	    {
                my $sql = "SELECT reference_no FROM reidentifications 
			WHERE occurrence_no=$fields{occurrence_no}";
                my @reidrows = @{$dbt->getData($sql)};
                my $isduplicate;
		
                for my $reidrow ( @reidrows )
		{
                    if ($fields{reference_no} == $reidrow->{reference_no})
		    {
                        push @warnings, "This reference already has been used to reidentify " . 
			    "the occurrence of taxon $taxon_name in row $rowno";
                       $isduplicate++;
                       next;
                    }
                }
		
                if ( $isduplicate > 0 )
		{
                   next;
                }
            }
        }
        
	# CASE 1: UPDATE REID
	
        if ($fields{reid_no} =~ /^\d+$/ && $fields{reid_no} > 0 &&
            $fields{occurrence_no} =~ /^\d+$/ && $fields{occurrence_no} > 0)
	{
            # CASE 1a: Delete record
            if ($fields{genus_name} =~ /^\s*$/)
	    {
                $dbt->deleteRecord($s,'reidentifications','reid_no',$fields{reid_no});
            }
            
	    # CASE 1b: Update record
            else
	    {
                # ugly hack: make sure taxon_no doesn't change unless
                #  genus_name or species_name did JA 1.4.04
		
                my $old_row = ${$dbt->getData("SELECT * FROM reidentifications
						WHERE reid_no=$fields{reid_no}")}[0];
		
                die ("no reid for $fields{reid_no}") if (!$old_row);
		
		$old_row->{subgenus_name} ||= '';
		$old_row->{species_name} ||= '';
		$old_row->{subspecies_name} ||= '';
		
                if ($old_row->{genus_name} eq $fields{genus_name} &&
                    $old_row->{subgenus_name} eq $fields{subgenus_name} &&
                    $old_row->{species_name} eq $fields{species_name} &&
		    $old_row->{subspecies_name} eq $fields{subspecies_name})
		{
                    delete $fields{taxon_no};
                }
		
                $dbt->updateRecord($s,'reidentifications','reid_no',$fields{reid_no},\%fields);
		
                if ($old_row->{reference_no} != $fields{reference_no})
		{
                    dbg("calling setSecondaryRef (updating ReID)<br>");
                    unless(PBDB::CollectionEntry::isRefPrimaryOrSecondary($dbt, 
									  $fields{collection_no}, 
									  $fields{reference_no}))
		    {
			PBDB::CollectionEntry::setSecondaryRef($dbt,$fields{collection_no},
							       $fields{reference_no});
                    }
                }
            }
	    
            setMostRecentReID($dbt, $fields{occurrence_no});
	    
            push @occurrences, $fields{occurrence_no};
        }
	
	# CASE 2: NEW REID
	
	elsif ($fields{occurrence_no} =~ /^\d+$/ && $fields{occurrence_no} > 0 && 
               $fields{reid_no} == -1)
	{
            # Check for duplicates
	    
            my @keys = ("genus_reso", "genus_name", "subgenus_reso", "subgenus_name",
			"species_reso", "species_name", "subspecies_reso", "subspecies_name", 
			"occurrence_no");
	    
            my %vars = map{$_,$dbh->quote($_)} @fields{@keys};
	    
            my $dupe_id = $dbt->checkDuplicates("reidentifications", \%vars);

            if ( $dupe_id )
	    {
                push @warnings, "Row ". ($i + 1) ." may be a duplicate";
            }
            
	    delete $fields{reid_no};
	    
	    $dbt->insertRecord($s,'reidentifications',\%fields);
	    
            unless(PBDB::CollectionEntry::isRefPrimaryOrSecondary($dbt, $fields{collection_no}, 
								  $fields{reference_no}))
	    {
		PBDB::CollectionEntry::setSecondaryRef($dbt,$fields{collection_no}, 
						       $fields{reference_no});
            }
	    
            setMostRecentReID($dbt, $fields{occurrence_no});
            push @occurrences, $fields{occurrence_no};
        }
	
	# CASE 3: UPDATE OCCURRENCE
	
	elsif($fields{occurrence_no} =~ /^\d+$/ && $fields{occurrence_no} > 0)
	{
            # CASE 3a: Delete record
	    
            if ($fields{genus_name} =~ /^\s*$/)
	    {
                # We push this onto an array for later processing because we
                # can't delete an occurrence With reids attached to it, so we
                # want to let any reids be deleted first 
		
                my $old_row = ${$dbt->getData("SELECT * FROM $OCCURRENCES 
						WHERE occurrence_no=$fields{occurrence_no}")}[0];
		
                push @occurrences_to_delete, [$fields{occurrence_no},
					      PBDB::CollectionEntry::formatOccurrenceTaxonName($old_row),
					      $i];
            }
	    
            # CASE 3b: Update record
	    
            else
	    {
                # ugly hack: make sure taxon_no doesn't change unless
                #  genus_name or species_name did JA 1.4.04
		
                my $old_row = ${$dbt->getData("SELECT * FROM $OCCURRENCES 
						WHERE occurrence_no=$fields{occurrence_no}")}[0];
		
                die ("no reid for $fields{reid_no}") if (!$old_row);
		
		$old_row->{subgenus_name} ||= '';
		$old_row->{species_name} ||= '';
		$old_row->{subspecies_name} ||= '';
		
                if ($old_row->{genus_name} eq $fields{genus_name} &&
                    $old_row->{subgenus_name} eq $fields{subgenus_name} &&
                    $old_row->{species_name} eq $fields{species_name} &&
		    $old_row->{subspecies_name} eq $fields{subspecies_name})
		{
                    delete $fields{taxon_no};
                }
		
                $dbt->updateRecord($s,$OCCURRENCES,"occurrence_no",$fields{occurrence_no},\%fields);
		
                if($old_row->{reference_no} != $fields{reference_no})
		{
                    dbg("calling setSecondaryRef (updating occurrence)<br>");
                    unless(PBDB::CollectionEntry::isRefPrimaryOrSecondary($dbt, $fields{collection_no}, 
									  $fields{reference_no}))
		    {
			PBDB::CollectionEntry::setSecondaryRef($dbt,$fields{collection_no}, 
							       $fields{reference_no});
                    }
                }
            }
	    
            push @occurrences, $fields{occurrence_no};    
	}
	
        # CASE 4: NEW OCCURRENCE
	
        elsif ($fields{occurrence_no} == -1)
	{
            # previously, a check here for duplicates generated error
            #  messages but (1) was incredibly slow and (2) apparently
            #  didn't work, so there is now a batch check above instead
	    
	    delete $fields{occurrence_no}; delete $fields{reid_no};
	    
            my ($result, $occurrence_no) = $dbt->insertRecord($s,$OCCURRENCES,\%fields);
            
	    if ($result && $occurrence_no =~ /^\d+$/)
	    {
                push @occurrences, $occurrence_no;
            }
	    
            unless(PBDB::CollectionEntry::isRefPrimaryOrSecondary($dbt, $fields{collection_no}, 
								  $fields{reference_no}))
	    {
		PBDB::CollectionEntry::setSecondaryRef($dbt,$fields{collection_no}, 
						       $fields{reference_no});
            }
        }
    }
    
    # Now handle the actual deletion
    
    foreach my $o (@occurrences_to_delete)
    {
        my ($occurrence_no,$taxon_name,$line_no) = @{$o};
	
        my $sql = "SELECT COUNT(*) c FROM reidentifications WHERE occurrence_no=$occurrence_no";
	
        my $reid_cnt = ${$dbt->getData($sql)}[0]->{c};
	
        $sql = "SELECT COUNT(*) c FROM specimens WHERE occurrence_no=$occurrence_no";
	
        my $measure_cnt = ${$dbt->getData($sql)}[0]->{c};
	
        if ($reid_cnt)
	{
            push @warnings, "'$taxon_name' on line $line_no can't be deleted because there are reidentifications based on it";
        }
	
        if ($measure_cnt)
	{
            push @warnings, "'$taxon_name' on line $line_no can't be deleted because there are measurements based on it";
        }
	
        if ($reid_cnt == 0 && $measure_cnt == 0)
	{
            $dbt->deleteRecord($s,$OCCURRENCES,"occurrence_no",$occurrence_no);
        }
    }
    
    $output .= qq|<div align="center"><p class="large" style="margin-bottom: 1.5em;">|;
    $sql = "SELECT collection_name AS coll FROM collections WHERE collection_no=$collection_no";
    $output .= ${$dbt->getData($sql)}[0]->{coll};
    $output .= "</p></div>\n\n";
    
    # Links to re-edit, etc
    
    my $links = "<div align=\"center\" style=\"padding-top: 1em;\">";
    
    if ($q->param('form_source') eq 'new_reids_form')
    {
        # suppress link if there is clearly nothing more to reidentify
        #  JA 3.8.07
        # this won't work if exactly ten occurrences have been displayed
	
        if ( $#rowTokens < 9 )
	{
            my $localtaxon_name = uri_escape_utf8($q->param('search_taxon_name') // '');
            my $localcoll_no = uri_escape_utf8($q->numeric_param("list_collection_no") // '');
            my $localpage_no = uri_escape_utf8($q->param('page_no') // '');
            $links .= makeAnchor("displayCollResults", "type=reid&taxon_name=$localtaxon_name&collection_no=$localcoll_no&page_no=$localpage_no") . "<nobr>Reidentify next 10 occurrences</nobr> - ";
        }
	
        $links .= makeAnchor("displayReIDCollsAndOccsSearchForm", "", "<nobr>Reidentify different occurrences</nobr>");
    }
    
    else
    {
        if ($q->param('list_collection_no'))
	{
            my $collection_no = $q->numeric_param("list_collection_no");
            $links .= makeAnchor("displayOccurrenceAddEdit", "collection_no=$collection_no", "<nobr>Edit this taxonomic list</nobr>") . " - ";
            $links .= makeAnchor("displayOccurrenceListForm", "collection_no=$collection_no", "Paste in more names") . " - ";
            $links .= makeAnchor("startStartReclassifyOccurrences", "collection_no=$collection_no", "<nobr>Reclassify these IDs</nobr>") . " - ";
            $links .= makeAnchor("displayCollectionForm", "collection_no=$collection_no", "<nobr>Edit the collection record</nobr>") . "<br>";
        }
	
        $links .= makeAnchor("displaySearchCollsForAdd", "type=add", "Add") . " or ";
        $links .= makeAnchor("displaySearchColls", "type=edit", "edit another collection") . " - </nobr>";
        $links .= makeAnchor("displaySearchColls", "type=edit_occurrence", "Add/edit");
        $links .= makeAnchor("displaySearchColls", "type=occurrence_list", "paste in") . ", or ";
        $links .= makeAnchor("displayReIDCollsAndOccsSearchForm", "", "reidentify IDs for a different collection") . "</nobr>";
    }
    
    $links .= "</div><br>";
    
    # for identifying unrecognized (new to the db) genus/species names.  these
    # are the new taxon names that the user is trying to enter, do this before
    # insert 
    
    my @new_genera = PBDB::TypoChecker::newTaxonNames($dbt,\@genera,'genus_name');
    my @new_subgenera = PBDB::TypoChecker::newTaxonNames($dbt,\@subgenera,'subgenus_name');
    my @new_species = PBDB::TypoChecker::newTaxonNames($dbt,\@species,'species_name');
    my @new_subspecies = PBDB::TypoChecker::newTaxonNames($dbt,\@subspecies, 'subspecies_name');
    
    $output .= qq|<div style="padding-left: 1em; padding-right: 1em;>"|;
    
    my $return;
    
    if ($q->param('list_collection_no'))
    {
        my $collection_no = $q->numeric_param("list_collection_no");
        my $coll = ${$dbt->getData("SELECT collection_no,reference_no FROM $COLLECTIONS 
					WHERE collection_no=$collection_no")}[0];
    	$return = PBDB::CollectionEntry::buildTaxonomicList($dbt,$hbo,$s,
							    {collection_no=>$collection_no, 
							     hide_reference_no=>$coll->{reference_no},
							     new_genera=>\@new_genera,
							     new_subgenera=>\@new_subgenera,
							     new_species=>\@new_species,
							     do_reclassify=>1,
							     warnings=>\@warnings,
							     save_links=>$links });
    }
    
    else
    {
    	$return = PBDB::CollectionEntry::buildTaxonomicList($dbt,$hbo,$s,
							    {occurrence_list=>\@occurrences, 
							     new_genera=>\@new_genera, 
							     new_subgenera=>\@new_subgenera,
							     new_species=>\@new_species,
							     do_reclassify=>1,
							     warnings=>\@warnings,
							     save_links=>$links });
    }
    
    if ( ! $return )
    {
        $output .= $links;
    }
    
    else
    {
        $output .= $return;
    }
    
    $output .= "\n</div>\n<br>\n";
    
    return $output;
}


# Marks the most_recent field in the reidentifications table to YES for the most recent reid for
# an occurrence, and marks all not-most-recent to NO.  Needed for collections search for Map and such
# PS 8/15/2005

sub setMostRecentReID {
    
    my ($dbt, $occurrence_no) = @_;
    
    my $dbh = $dbt->dbh;
    
    if ($occurrence_no =~ /^\d+$/) {
        my $sql = "SELECT re.* FROM reidentifications re, refs r WHERE r.reference_no=re.reference_no AND re.occurrence_no=".$occurrence_no." ORDER BY r.pubyr DESC, re.reid_no DESC";
        my @results = @{$dbt->getData($sql)};
        if ($results[0]->{'reid_no'}>0) {
            $sql = "UPDATE reidentifications SET modified=modified, most_recent='YES' WHERE reid_no=".$results[0]->{'reid_no'};
            my $result = $dbh->do($sql);
            dbg("set most recent: $sql");
            if (!$result) {
                carp "Error setting most recent reid to YES for reid_no=$results[0]->{reid_no}";
            } else	{
                $sql = "UPDATE occurrences SET modified=modified, reid_no=".$results[0]->{'reid_no'}." WHERE occurrence_no=".$occurrence_no;
                my $result = $dbh->do($sql);
            }
                
            my @older_reids;
            for(my $i=1;$i<scalar(@results);$i++) {
                push @older_reids, $results[$i]->{'reid_no'};
            }
            if (@older_reids) {
                $sql = "UPDATE reidentifications SET modified=modified, most_recent='NO' WHERE reid_no IN (".join(",",@older_reids).")";
                $result = $dbh->do($sql);
                dbg("set not most recent: $sql");
                if (!$result) {
                    carp "Error setting most recent reid to NO for reid_no IN (".join(",",@older_reids).")"; 
                }
            }
        }
    }
}

1;

