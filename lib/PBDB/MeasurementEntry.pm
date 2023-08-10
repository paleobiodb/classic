# includes entry functions extracted from Measurement.pm JA 4.6.13

package PBDB::MeasurementEntry;

use PBDB::Taxonomy qw(getTaxa getChildren getAllSynonyms getAllSpellings);
use PBDB::Reference qw(formatShortRef formatLongRef);
use PBDB::Debug;
use PBDB::PBDBUtil qw(getMostRecentReIDforOCC);
use PBDB::Constants qw($TAXA_TREE_CACHE makeAnchor makeAnchorWithAttrs makeFormPostTag);

use strict;

# written by PS 6/22/2005 - 6/24/2005
# Handle display and processing of form to enter measurements for specimens

my @specimen_fields   =('specimens_measured','specimen_coverage','specimen_id','specimen_side','sex','specimen_part','measurement_source','magnification','is_type','comments');
my @measurement_types =('mass','length','width','height','circumference','diagonal','diameter','inflation','d13C','d18O');
my @measurement_fields=('average','median','min','max','error','error_unit');

#
# Displays a list of potential specimens from the search.  
#
sub submitSpecimenSearch {
    my  ($dbt,$hbo,$q,$s) = @_;
    my $dbh = $dbt->dbh;
    my $output = '';
    
    if ( ! $q->param('taxon_name') && ! $q->param('comment') && ! int($q->numeric_param('collection_no')) ) {
        my %vars = { errors => "You must enter a taxonomic name, comment, or collection number" };
	return $hbo->populateHTML('search_specimen_form', \%vars);
    }
    
    # Grab the data from the database, filtering by either taxon_name and/or collection_no
    my $sql1 = "SELECT c.collection_no, c.collection_name, IF(c.country IN ('Canada','United States'),c.state,c.country) place, i.interval_name max,IF(min_interval_no>0,i2.interval_name,'') min,o.occurrence_no,o.genus_reso o_genus_reso,o.genus_name o_genus_name,o.species_reso o_species_reso,o.species_name o_species_name,o.comments o_comments, '' re_genus_reso,'' re_genus_name,'' re_species_reso,'' re_species_name,'' re_comments, count(DISTINCT specimen_no) cnt FROM (occurrences o, collections c, intervals i) LEFT JOIN specimens s ON o.occurrence_no=s.occurrence_no LEFT JOIN intervals i2 ON c.min_interval_no=i2.interval_no LEFT JOIN reidentifications re ON o.occurrence_no=re.occurrence_no WHERE o.collection_no=c.collection_no AND c.max_interval_no=i.interval_no AND re.reid_no IS NULL ";
    my $sql2 = "SELECT c.collection_no, c.collection_name, IF(c.country IN ('Canada','United States'),c.state,c.country) place, i.interval_name max,IF(min_interval_no>0,i2.interval_name,'') min,o.occurrence_no,o.genus_reso o_genus_reso,o.genus_name o_genus_name,o.species_reso o_species_reso,o.species_name o_species_name,o.comments o_comments, re.genus_reso re_genus_reso,re.genus_name re_genus_name,re.species_reso re_species_reso,re.species_name re_species_name,re.comments re_comments, count(DISTINCT specimen_no) cnt FROM (reidentifications re, occurrences o, collections c, intervals i) LEFT JOIN specimens s ON o.occurrence_no=s.occurrence_no LEFT JOIN intervals i2 ON c.min_interval_no=i2.interval_no WHERE re.occurrence_no=o.occurrence_no AND o.collection_no=c.collection_no AND c.max_interval_no=i.interval_no AND most_recent='YES' ";

    my $where = "";
    my (@taxa,@results,$taxon_nos);
    
    if ( my $taxon_name = $q->param('taxon_name'))
    {
	my $quoted = $dbh->quote($taxon_name);
	
        if ( $q->param('match_type') =~ /exact|combinations only/ )	{
            my $sql = "SELECT taxon_no FROM authorities WHERE taxon_name=$quoted";
            @taxa = @{$dbt->getData($sql)};
        } else	{
            @taxa = getTaxa($dbt,{'taxon_name'=>$taxon_name, 'match_subgenera'=>1});
        }
    } 
    if (@taxa) {
        my (@taxon_nos,%all_taxa);
        if ( $q->param('match_type') !~ /exact/ )	{
            foreach (@taxa) {
                if ($_->{'taxon_rank'} =~ /species|genus/) {
                    @taxon_nos = getChildren($dbt,$_->{'taxon_no'});
                    @all_taxa{@taxon_nos} = ();
                } else {
                    if ( $q->param('match_type') !~ /combinations only/ )	{
                        @taxon_nos = getAllSynonyms($dbt,$_->{'taxon_no'});
                    } else	{
                        @taxon_nos = getAllSpellings($dbt,$_->{'taxon_no'});
                    }
                    @all_taxa{@taxon_nos} = ();
                    @all_taxa{$_->{'taxon_no'}} = 1; 
                }
            }
            @taxon_nos = keys %all_taxa;
        } else	{
            push @taxon_nos , $_->{'taxon_no'} foreach @taxa;
        }
        $taxon_nos = join(",",@taxon_nos);
        $sql1 .= " AND o.taxon_no IN ($taxon_nos)";
        $sql2 .= " AND re.taxon_no IN ($taxon_nos)";
    } elsif ($q->param('taxon_name')) {
        my @taxon_bits = split(/\s+/,$q->param('taxon_name'));
        $sql1 .= " AND o.genus_name LIKE ".$dbh->quote($taxon_bits[0]);
        $sql2 .= " AND re.genus_name LIKE ".$dbh->quote($taxon_bits[0]);
        if (scalar(@taxon_bits) > 1) {
            $sql1 .= " AND o.species_name LIKE ".$dbh->quote($taxon_bits[1]);
            $sql2 .= " AND re.species_name LIKE ".$dbh->quote($taxon_bits[1]);
        }
    }
    
    if ( $q->param('get_occurrences') !~ /^no/i )
    {
        if ( my $comment_selector = $q->param('comment'))
	{
	    my $quoted = $dbh->quote('%' . $comment_selector . '%');
            $sql1 .= " AND o.comments LIKE $quoted";
            $sql2 .= " AND (o.comments LIKE $quoted OR re.comments LIKE $quoted)";
        }
	
        if ( my $collection_no = $q->numeric_param('collection_no')) {
            $sql1 .= " AND o.collection_no=$collection_no";
            $sql2 .= " AND o.collection_no=$collection_no";
        }
	
        $sql1 .= " GROUP BY o.occurrence_no";
        $sql2 .= " GROUP BY o.occurrence_no";
        my $sql = "($sql1) UNION ($sql2) ORDER BY collection_no";
	
        @results = @{$dbt->getData($sql)};
    }

    # if we only have a taxon_name, get taxa not tied to any occurrence as well
    my @results_taxa_only;
    if ($taxon_nos && !$q->numeric_param('collection_no')) {
        my $sql = "SELECT a.taxon_no,a.taxon_rank,a.taxon_name, count(DISTINCT specimen_no) cnt FROM authorities a LEFT JOIN specimens s ON s.taxon_no=a.taxon_no WHERE a.taxon_no IN ($taxon_nos) GROUP BY a.taxon_no ORDER by a.taxon_name";
        @results_taxa_only = @{$dbt->getData($sql)};
    }

    if (scalar(@results) == 0 && $q->numeric_param('collection_no')) {
	my %vars = { errors => "Occurrences of this taxon could not be found" };
	return $hbo->populateHTML('search_specimen_form', \%vars);
    } elsif (scalar(@results) == 1 && $q->numeric_param('collection_no')) {
        $q->param('occurrence_no'=>$results[0]->{'occurrence_no'});
        $output .= displaySpecimenList($dbt,$hbo,$q,$s);
    } elsif (scalar(@results) == 0 && scalar(@results_taxa_only) == 1) {
        $q->param('taxon_no'=>$results_taxa_only[0]->{'taxon_no'});
        $output .= displaySpecimenList($dbt,$hbo,$q,$s);
    } elsif (scalar(@results) == 0 && scalar(@results_taxa_only) == 0) {
        my %vars = { errors => "Occurrences or taxa matching these search terms could not be found" };
	return $hbo->populateHTML('search_specimen_form', \%vars);
    } else {
        my ($things,$collection_header,$knownUnknown) = ('occurrences and names','Collection','unknown');
        if( $q->param('get_occurrences') =~ /^no/i )	{
            $things = "taxonomic names";
            $collection_header = "";
            $knownUnknown = "";
        }
        $output .= qq|<center><p class="pageTitle" style="font-size: 1.2em;">Matching $things</p></center>\n|;
	$output .= makeFormPostTag();
	$output .= qq |<input type="hidden\" name="action" value="displaySpecimenList">
        <div align="center" class="small" style="margin: 1em;">
        <table cellspacing="0" cellpadding="6" style="border: 1px solid lightgray;">
        <tr><th><span style="margin-right: 1em">Occurrence</span></th><th>$collection_header</th><th>Measurements</th></tr>
|;
        my $last_collection_no = -1;
        my %coll_names = ();
        $coll_names{$_->{'collection_name'}} = 1 for (@results);
        my $coll_count = scalar(keys(%coll_names));
        my $class = (scalar($coll_count) > 0) ? '' : 'class="darkList"';
        sub reso	{
            my $reso = shift;
            my $quote;
            if ( $reso eq '"' )	{
                $quote = '"';
            } else	{
                $reso .= " ";
            }
            return ($reso,$quote);
        }
        foreach my $row (@results) {
            my $specimens = ($row->{'cnt'} >= 1) ? $row->{'cnt'} : 'none';
            my $taxon_name;
            my ($reso,$quote) = reso($row->{'o_genus_reso'});
            my ($reso2,$quote2) = reso($row->{'o_species_reso'});
            if ( $reso eq '"' && $reso2 eq '"' )	{
                $quote = "";
                $reso2 = "";
            }
            $taxon_name = $reso.$row->{'o_genus_name'}.$quote." ".$reso2.$row->{'o_species_name'}.$quote2;
            if ($row->{re_genus_name}) {
                my ($reso,$quote) = reso($row->{'re_genus_reso'});
                my ($reso2,$quote2) = reso($row->{'re_species_reso'});
                if ( $reso eq '"' && $reso2 eq '"' )	{
                    $quote = "";
                    $reso2 = "";
                }
                $taxon_name .= "<br>\n&nbsp;= ".$reso.$row->{'re_genus_name'}.$quote." ".$reso2.$row->{'re_species_name'}.$quote2;
            }
            my $comments;
            if ( $row->{'o_comments'} || $row->{'re_comments'} )	{
                $comments = "<br>\n<div class=\"verysmall\" style=\"width: 20em; white-space: normal;\">$row->{'o_comments'}";
                if ( $row->{'o_comments'} && $row->{'re_comments'} )	{
                    $comments .= "/".$row->{'re_comments'};
                } elsif ( $row->{'re_comments'} )	{
                    $comments .= $row->{'re_comments'};
                }
                $comments .= "</div>\n";
            }
            if ($last_collection_no != $row->{'collection_no'}) {
                $class = ($class eq '') ? $class='class="darkList"' : '';
            }
            $output .= "<tr $class><td><span class=\"small\"><nobr>" . makeAnchor("displaySpecimenList", "occurrence_no=$row->{occurrence_no}", "$taxon_name") . " $comments</nobr></span></td>";
            if ($last_collection_no != $row->{'collection_no'}) {
                $last_collection_no = $row->{'collection_no'};
                my $interval = $row->{max};
                if ( $row->{min} )	{
                    $interval .= " - ".$row->{min};
                }
                $output .= "<td><span class=\"small\" style=\"margin-right: 1em;\">" . makeAnchor("displayCollectionDetails", "collection_no=$row->{collection_no}", "$row->{collection_name}") . "</span><br><span class=\"verysmall\">$row->{collection_no}: $interval, $row->{place}</span></td>";
            } else {
                $output .= "<td></td>";
            }
            $output .= "<td align=\"center\">$specimens</td></tr>";
        }
        foreach my $row (@results_taxa_only) {
            $class = ($class eq '') ? $class='class="darkList"' : '';
            my $specimens = ($row->{'cnt'} >= 1) ? $row->{'cnt'} : 'none';
            my $taxon_name;
            if ($row->{'taxon_rank'} =~ /species/) {
                $taxon_name = $row->{'taxon_name'};
            } elsif ($row->{'taxon_rank'} =~ /genus/) {
                $taxon_name = $row->{'taxon_name'}." sp.";
            } else {
                $taxon_name = $row->{'taxon_name'}." indet.";
            }
            $output .= "<tr $class><td>" . makeAnchor("displaySpecimenList", "taxon_no=$row->{taxon_no}", "$taxon_name") . "</td><td>$knownUnknown</td><td align=\"center\">$specimens</td></tr>";

        }
        $output .= qq|</table>
</div>
</form>
|;
    }
    
    return $output;
}

#
# Displays a list of specimens associated with a specific occurrence.  If there are no specimens
# currently associated with the occurrence, just go directly to the add occurrence form, otherwise
# give them an option to edit an old one, or add a new set of measurements
#
sub displaySpecimenList {
    my ($dbt,$hbo,$q,$s,$called_from,$more_links) = @_;

    my $output = '';
    
    # We need a taxon_no passed in, cause taxon_name is ambiguous
	if ( ! $q->numeric_param('occurrence_no') && ! $q->numeric_param('taxon_no')) {
	    my %vars = { errors => "There is no occurrence or classification of this taxon" };
	    return $hbo->populateHTML('search_specimen_form', \%vars);
	}
    
    my (@results,$taxon_name,$extant,$collection);
    if ($q->numeric_param('occurrence_no')) {
        @results = getMeasurements($dbt,$q->numeric_param('occurrence_no'));
        my $sql = "SELECT collection_no,genus_name,species_name,occurrence_no FROM occurrences WHERE occurrence_no=".$q->numeric_param("occurrence_no");
        my $row = ${$dbt->getData($sql)}[0];
        if (!$row) {
	    my %vars = { errors => "An error has occurred, could not find occurrence in database" };
	    return $hbo->populateHTML('search_specimen_form', \%vars);
        }
        $collection = "(collection $row->{collection_no})";
        my $reid_row = getMostRecentReIDforOcc($dbt,$row->{'occurrence_no'},1);
        if ($reid_row) {
            $taxon_name = $reid_row->{'genus_name'}." ".$reid_row->{'species_name'};
        } else {
            $taxon_name = $row->{'genus_name'}." ".$row->{'species_name'};
        }
    } else {
        my $sql = "";
        my $taxon_no = $q->numeric_param('taxon_no');
        my $base_sql = "SELECT r.author1last,r.author2last,r.otherauthors,r.pubyr,s.*,m.*,s.taxon_no FROM refs r,specimens s, measurements m";
        if ($q->param('types_only')) {
            $sql = "($base_sql FROM specimens s, measurements m WHERE s.specimen_no=m.specimen_no AND s.taxon_no=$taxon_no AND s.is_type='holotype')"
                 . " UNION "
                 . "($base_sql, occurrences o LEFT JOIN reidentifications re ON o.occurrence_no=re.occurrence_no WHERE s.occurrence_no=o.occurrence_no AND s.specimen_no=m.specimen_no AND o.taxon_no=$taxon_no AND re.reid_no IS NULL AND s.is_type='holotype')"
                 . " UNION "
                 . "($base_sql, reidentifications re WHERE s.occurrence_no=o.occurrence_no AND o.occurrence_no=re.occurrence_no AND s.specimen_no=m.specimen_no AND re.taxon_no=$taxon_no AND re.most_recent='YES' AND s.is_type='holotype')"
        } else {
            $sql = "$base_sql WHERE r.reference_no=s.reference_no AND s.specimen_no=m.specimen_no AND s.taxon_no=$taxon_no";
        }
        @results = @{$dbt->getData($sql)};

        my $taxon = getTaxa($dbt,{'taxon_no'=>$q->numeric_param('taxon_no')},['taxon_rank','taxon_name','extant']);
        if ($taxon->{'taxon_rank'} =~ /species/) {
            $taxon_name = $taxon->{'taxon_name'};
        } elsif ($taxon->{'taxon_rank'} =~ /genus/) {
            $taxon_name = $taxon->{'taxon_name'}." sp.";
        } else {
            $taxon_name = $taxon->{'taxon_name'}." indet.";
        }
        $extant = $taxon->{'extant'};
    }
    
    $output .= qq|<center><div class="pageTitle" style="padding-top: 0.5em;"><span class="verysmall">$taxon_name $collection</span></div></center>
<center>
<div class="displayPanel verysmall" align="center" style="width: 40em; margin-top: 1em; padding-top: 1em;">
  $more_links
  <div class="displayPanelContent">
|;
    
    $output .= makeFormPostTag('specimenList');
    $output .= "<input type=hidden name=\"action\" value=\"populateMeasurementForm\">\n";
    $output .= <<HIDDEN_FIELDS;
<input type=hidden name="delete_specimen_no" value="">
<input type=hidden name="delete_specimen_id" value="">
HIDDEN_FIELDS
    
    if ($q->param('types_only')) {
        $output .= "<input type=hidden name=\"types_only\" value=\"".$q->param('types_only')."\">";
    }
    if ($q->numeric_param('occurrence_no')) {
        $output .= "<input type=hidden name=\"occurrence_no\" value=\"".$q->numeric_param('occurrence_no')."\">";
    } else {
        $output .= "<input type=hidden name=\"taxon_no\" value=\"".$q->numeric_param('taxon_no')."\">";
    }
    # default value
    $output .= "<input type=hidden name=\"specimen_no\" value=\"-2\">";
    $output .= <<END_SCRIPT;

<script language="JavaScript" type="text/javascript">
<!--
function submitForm ( )
{
  document.specimenList.submit() ;
}
-->

// This function must be called with either occurrence_no or taxon_no <> 0.
// It asks the user for confirmation before firing off the submission.

function deleteMeasurement ( specimen_id, specimen_no )
{
    if ( ! confirm("Delete specimen '" + specimen_id + "'?") )
    {
	return;	
    }
    
    document.specimenList.elements["action"].value = "deleteSpecimen";
    document.specimenList.elements["delete_specimen_no"].value = specimen_no;
    document.specimenList.elements["delete_specimen_id"].value = specimen_id;
    document.specimenList.submit();
}
</script>
END_SCRIPT
    
    # If an error occurred, display it.
    
    if ( $s->{error_msg} )
    {
	$output .= qq{<div class="warningBox"><p>$s->{error_msg}</p></div>\n};
    }
    
    # now create a table of choices

    my (%specimens,%types,%parts,$specimen_ids,$sexes);
    foreach my $row (@results) {
        $specimens{$row->{specimen_no}}{$row->{measurement_type}} = $row->{average};
        for my $field ( 'specimens_measured','specimen_part','author1last','author2last','otherauthors','pubyr' )	{
            $specimens{$row->{specimen_no}}{$field} = $row->{$field};
        }
        if ( $row->{specimen_id} )	{
            $specimens{$row->{specimen_no}}{'specimen_id'} = $row->{specimen_id};
            $specimens{$row->{specimen_no}}{'specimen_id'} .= ( $row->{sex} eq "female" ) ? ' (&#9792;)' : "";
            $specimens{$row->{specimen_no}}{'specimen_id'} .= ( $row->{sex} eq "male" ) ? ' (&#9794;)' : "";
            $specimen_ids++;
        } elsif ( $row->{sex} )	{
            $specimens{$row->{specimen_no}}{'specimen_id'} = ( $row->{sex} eq "female" ) ? '&#9792;' : "";
            $specimens{$row->{specimen_no}}{'specimen_id'} .= ( $row->{sex} eq "male" ) ? ' &#9794;' : "";
        }
        if ( $row->{sex} )	{
            $sexes++;
        }
        $types{$row->{measurement_type}}++;
        $parts{$row->{specimen_part}}++ if ($row->{specimen_part});
    }

    my $specimen_count = scalar(keys(%specimens));

    if ($specimen_count == 0)	{
        if ($q->numeric_param('occurrence_no')) {
            $output .= "<p class=\"small\">There are no measurements for this occurrence yet</p>\n";
        } else {
            $output .= "<p class=\"small\">There are no measurements for $taxon_name yet</p>\n";
        }
    }

    $output .= "<table style=\"margin-top: 0em;\">\n";

    # always give them an option to create a new measurement as well
    if ( $q->numeric_param('occurrence_no') )	{
            my $occurrence_no = $q->numeric_param('occurrence_no');
            $output .= "<tr><td align=\"center\"><span class=\"measurementBullet\">" . makeAnchor("populateMeasurementForm", "occurrence_no=$occurrence_no&specimen_no=-1", "[select]  ") . "</span></td>";
        } else	{
            my $taxon_no = $q->numeric_param('taxon_no');
            $output .= "<tr><td align=\"center\"><span class=\"measurementBullet\">" . makeAnchor("populateMeasurementForm", "taxon_no=$taxon_no&specimen_no=-1", "[select]  ") . "</span></td>";
        }
    $output .= "<br><td colspan=\"6\">&nbsp;Add one new record (full form)</td></tr>\n";
    $output .= "<tr><td align=\"center\">-- or --</tr></td>";
    $output .= qq|<tr><td align="center" valign="top"><a href="javascript:submitForm('')"><div class="measurementBullet" style="position: relative; margin-top: -0.1em;">[select]  </div></td>|;

    # anyone working on a large paper will enter the same type and source value
    #  almost every time, so grab the last one
    my (%checked,@part_values,$part_value,%part_used,%selected,@last_entries);

    if ( my $reference_no = $s->get('reference_no') )
    {
	my $sql = "SELECT occurrence_no,taxon_no,specimen_id,specimen_part,is_type,measurement_source,measurement_type FROM specimens s,measurements m WHERE s.specimen_no=m.specimen_no AND reference_no=$reference_no ORDER BY s.specimen_no DESC LIMIT 100";
	@last_entries = @{$dbt->getData($sql)};
    }
    my ($old_records,$id);
    for my $entry ( @last_entries )	{
        if ( $entry->{occurrence_no} != $last_entries[0]->{occurrence_no} || $entry->{taxon_no} != $last_entries[0]->{taxon_no} || $entry->{specimen_id} ne $last_entries[0]->{specimen_id} )	{
            last;
        }
        $old_records++;
        # a non-numeric ID may be a repeated bare museum code or what have you
        $id = ( $entry->{specimen_id} !~ /[0-9]/ ) ? $entry->{specimen_id} : "";
        $part_used{$entry->{specimen_part}}++;
        if ( $part_used{$entry->{specimen_part}} == 1 )	{
           unshift @part_values , $entry->{specimen_part};
        }
        $checked{$entry->{measurement_type}} = "checked";
    }
    $old_records--;
    $old_records = ( $old_records < 2 ) ? 10 : $old_records;

    # likewise, the same number of parts per taxon or occurrence may be
    #  entered every time
    $output .= "<td colspan=\"6\" valign=\"top\">&nbsp;Add <input type=\"text\" name=\"specimens_measured\" value=\"$old_records\" size=3>new records with:<br>";

    $checked{'length'} = ( ! %checked ) ? "checked" : $checked{'length'};
    my $defaults = $last_entries[0];
    $selected{$defaults->{'is_type'}} = "selected";
    $selected{$defaults->{'measurement_source'}} = "selected";
    $part_value = 'value="'.join(', ',@part_values).'"';

    $output .= qq|
  <div style=\"padding-left: 2em; padding-bottom: 1em;\">
  default specimen #: <input name="default_no" size="26" value="$id"><br>
  default side and sex:
  <select name="default_side">
  <option value=""></option>
  <option value="left">left</option>
  <option value="right">right</option>
  <option value="upper left">upper left</option>
  <option value="upper right">upper right</option>
  <option value="lower left">lower left</option>
  <option value="lower right">lower right</option>
  <option value="left?">left?</option>
  <option value="right?">right?</option>
  <option value="dorsal">dorsal</option>
  <option value="ventral">ventral</option>
  <option value="both">both</option>
  </select>
  <select name="default_sex"><option></option><option>female</option><option>male</option><option>both</option></select><br>
  default part: <input type="text" name="default_part" size="10" $part_value><br>
  sample size: <input type="text" name="N" size="10"><br>
  measurements:
  <input type="checkbox" name="length" $checked{'length'}> length 
  <input type="checkbox" name="width" $checked{'width'}> width
  <input type="checkbox" name="height" $checked{'height'}> height<br>
  <input type="checkbox" name="circumference" style="margin-left: 2em;" $checked{'circumference'}> circumference
  <input type="checkbox" name="diagonal" $checked{'diagonal'}> diagonal
  <input type="checkbox" name="diameter" $checked{'diameter'}> diameter<br>
|;
    if ( $extant =~ /y/i )	{
      $output .= qq|
  <input type="checkbox" name="mass" style="margin-left: 2em;" $checked{'mass'}> mass\n|;
    }
    $output .= qq|
  <input type="checkbox" name="d13C" style="margin-left: 2em;" $checked{'d13C'} > &delta;<sup>13</sup>C
  <input type="checkbox" name="d18O" style="margin-left: 2em;" $checked{'d18O'}> &delta;<sup>18</sup>O<br>
  default type:
  <select name="default_type">
  <option value="no">no</option>
  <option value="holotype" $selected{'holotype'}>holotype</option>
  <option value="paratype" $selected{'paratype'}>paratype</option>
  </select><br>
  default source:
  <select name="default_source">
  <option value=""></option>
  <option value="text" $selected{'text'}>text</option>
  <option value="table" $selected{'table'}>table</option>
  <option value="picture" $selected{'picture'}>picture</option>
  <option value="graph" $selected{'graph'}>graph</option>
  <option value="direct" $checked{'direct'}>direct</option>
  </select>
  <br>default magnification: <input name="default_magnification" size="10"><br>
  comments: <input type="text" name="default_comments" size="36"><br>
  </div>
</td></tr>
</table>
</div>
</div>
</center>
|;


    if ($specimen_count > 0) {
$output .= qq|<center>
<div class="displayPanel verysmall" align="center" style="width: 40em; margin-top: 2em; padding-top: 1em; padding-bottom: 1em;">
<table class="verysmall" cellspacing="4">
<tr><td></td><td colspan="5" class="verylarge" style="padding-bottom: 0.5em;">Existing measurements</td></tr>
<tr>
<th></th>
|;
        if ( $specimen_ids > 0 )	{
            $output .= "<th align=\"left\">specimen #</th>";
        } elsif ( $sexes > 0 )	{
            $output .= "<th align=\"left\">sex</th>";
        }
        $output .= "<th align=\"left\">part</th>" if (%parts);
        $output .= "<th>count</th>";
        foreach my $type (@measurement_types) {
            if ($types{$type}) {
                $output .= "<th>$type</th>";
            }
        }
        if ( $q->numeric_param('occurrence_no') == 0 )	{
            $output .= "<th>reference</th>";
        }
        $output .= "</tr>\n";
    }

    my $types_only;
    $types_only = "types_only=$q->param('types_only')" if ($q->param('types_only'));
    # fixed order for mammal teeth
    my @teeth = ("P1","P2","P3","P4","M1","M2","M3","M4","p1","p2","p3","p4","m1","m2","m3","m4");
    my %tooth;
    for my $t ( 0..$#teeth )	{
        $tooth{$teeth[$t]} = $t;
    }
    foreach my $specimen_no (sort {$tooth{$specimens{$a}->{specimen_part}} <=> $tooth{$specimens{$b}->{specimen_part}} || $a <=> $b} keys %specimens) {
        my $row = $specimens{$specimen_no};
	my $id = $row->{specimen_id} // '';
	$specimen_no //= 0;
        $output .= "<tr>\n";
        if ( $q->numeric_param('occurrence_no') )
	{
	    my $occurrence_no = $q->numeric_param('occurrence_no') || 0;
            $output .= qq|<td align="center">|;
	    $output .= qq|<a onClick="deleteMeasurement('$id', $specimen_no)">delete</a>&nbsp;|;
	    $output .= makeAnchor("populateMeasurementForm", "occurrence_no=$occurrence_no&specimen_no=$specimen_no", "edit") . "</td>";
        } else	{
	    my $taxon_no = $q->numeric_param('taxon_no') || 0;
            $output .= qq|<td align="center">|;
	    $output .= qq|<a onClick="deleteMeasurement('$id', $specimen_no)">delete</a>&nbsp;|;
	    $output .= makeAnchor("populateMeasurementForm", "taxon_no=$taxon_no&specimen_no=$specimen_no", "edit") . "</td>";
        }
        if ( $specimen_ids > 0 || $sexes > 0 )	{
            $output .= qq|<td>$row->{specimen_id}</td>|;
        }
        $output .= qq|<td align="left">$row->{specimen_part}</td>| if (%parts);
        $output .= qq|<td align="center">$row->{specimens_measured}</td>|;
        foreach my $type (@measurement_types) {
            if ($types{$type}) {
                $output .= "<td align=\"center\">$row->{$type}</td>";
            }
        }
        my $auth = formatShortRef($row);
        $auth =~ s/ and / & /;
        $output .= "<td>$auth</td>\n";
        $output .= "</tr>";
    }
    if ($specimen_count > 0) {
        $output .= "</table>\n</div>\n</center>\n";
    }
    
    return $output;
}

sub populateMeasurementForm {
    my ($dbt,$hbo,$q,$s) = @_;
    my $dbh = $dbt->dbh;

    my $output = '';
    
    # We need a taxon_no passed in, cause taxon_name is ambiguous
    if ( ! $q->numeric_param('occurrence_no') && ! $q->numeric_param('taxon_no')) {
        return displaySpecimenList($dbt,$hbo,$q,$s);
    }
    
	# get the taxon's name
    my ($taxon_name,$old_field,$old_no,$collection,$extant);
    if ($q->numeric_param('occurrence_no')) {
        $old_field = "occurrence_no";
        $old_no = $q->numeric_param('occurrence_no');
        my $sql = "SELECT c.collection_name, o.collection_no, o.genus_name, o.species_name, o.occurrence_no, o.taxon_no FROM collections c, occurrences o WHERE c.collection_no=o.collection_no AND o.occurrence_no=".$q->numeric_param('occurrence_no');
        my $row = ${$dbt->getData($sql)}[0];

        my $reid_row = getMostRecentReIDforOcc($dbt,$row->{'occurrence_no'},1);
        if ($reid_row) {
            $taxon_name = $reid_row->{'genus_name'}." ".$reid_row->{'species_name'};
        } else {
            $taxon_name = $row->{'genus_name'}." ".$row->{'species_name'};
        }  

        $collection = "($row->{'collection_name'})";

        if (!$row || !$taxon_name || !$collection) {
	    return displaySpecimenList($dbt,$hbo,$q,$s);
            # push my @error , "The occurrence of this taxon could not be found";
            # print "<center><p>".PBDB::Debug::printWarnings(\@error)."</p></center>\n";
            # return;
        }
    } else {
        $old_field = "taxon_no";
        $old_no = $q->numeric_param('taxon_no');
        my $taxon = getTaxa($dbt,{'taxon_no'=>$q->numeric_param('taxon_no')},['taxon_rank','taxon_name','extant']);
        if ($taxon->{'taxon_rank'} =~ /species/) {
            $taxon_name = $taxon->{'taxon_name'};
        } elsif ($taxon->{'taxon_rank'} =~ /genus/) {
            $taxon_name = $taxon->{'taxon_name'}." sp.";
        } else {
            $taxon_name = $taxon->{'taxon_name'}." indet.";
        }
        # check for extant taxa only if there is no occurrence because
        #  occurrences are only of fossils, in principle
        if ($taxon->{'extant'} =~ /yes/i) {
            $extant = "yes";
        }
    }

    # prepare fields to be used in the form ahead
    my @values = ();
    my @fields = ();

    # new entry
    if ($q->numeric_param('specimen_no') < 0) {
        # users can only choose length and width position values right
        #  now because there's nothing to say about anything else
        #  JA 12.6.12
        my $sql = "SELECT measurement_type,position FROM specimens s,measurements m WHERE s.specimen_no=m.specimen_no AND position IS NOT NULL AND enterer_no=".$s->get('enterer_no')." AND measurement_type IN ('length','width') ORDER BY measurement_no ASC";
        my %last_position;
        $last_position{$_->{'measurement_type'}} = $_->{'position'} foreach @{$dbt->getData($sql)};
        if (!$s->get('reference_no')) {
            # Make them choose a reference first
            $s->enqueue('populateMeasurementForm', $q);
            PBDB::displaySearchRefs($q, $s, $dbt, $hbo, "Please choose a reference before adding specimen measurement data",1);
            return;
        } else {
            if ($q->numeric_param('specimen_no') == -1) {
                my @specimen_fields = ('taxon_no','specimens_measured','specimen_coverage','specimen_id','specimen_side','specimen_part','sex','measurement_source','magnification','is_type','comments');
                # get the data from the last record of this taxon entered
                #  JA 10.5.07
                # whoops, everything should come instead from the last record
                #  entered from the current ref JA 13.4.12
                my $fieldstring = "s.".join(',s.',@specimen_fields);
                $fieldstring =~ s/is_type/is_type AS specimen_is_type/;
                my $sql = "SELECT $fieldstring,average AS last_average FROM specimens s,measurements m WHERE s.specimen_no=m.specimen_no AND reference_no=".$s->get('reference_no')." ORDER BY s.specimen_no DESC";
                my $row = ${$dbt->getData($sql)}[0];
                # but if that fails, at least the part might be recoverable
                if ( ! $row )	{
                    $sql = "SELECT specimen_part FROM specimens WHERE $old_field=$old_no ORDER BY specimen_no DESC";
                    $row = ${$dbt->getData($sql)}[0];
                }
                # comments are usually taxon-specific
                elsif ( $q->numeric_param('taxon_no') != $row->{'taxon_no'} )	{
                    $row->{'comments'} = "";
                }
                if ( $row->{'specimen_part'} ne "body" )	{
                    push @fields,'length_position';
                    push @values,$last_position{'length'};
                    push @fields,'width_position';
                    push @values,$last_position{'width'};
                }
                push @fields,$_ for @specimen_fields;
                s/is_type/specimen_is_type/ foreach @fields;
                if ( ! $row->{'specimens_measured'} )	{
                    $row->{'specimens_measured'} = 1;
                }
                for my $f ( @specimen_fields )	{
                    push @values,  $row->{$f};
                }
                foreach my $type (@measurement_types) {
                    foreach my $f (@measurement_fields) {
                        push @fields, $type."_".$f;
                        if ( $row->{$f} )	{
                            push @values, $row->{$f};
                        } else	{
                            push @values, '';
                        }
                    }
                }
                if ( $extant eq "yes" )	{
                    push @fields, "mass_unit";
                    push @values , ( $row->{'last_average'} >= 100 ) ? "kg" : "g";
                }

                my $sql = "SELECT author1init,author1last,author2init,author2last,pubyr,reftitle,pubtitle,pubvol,firstpage,lastpage FROM refs WHERE reference_no=".$s->get('reference_no');
                my $ref = ${$dbt->getData($sql)}[0];

	        push @fields,('reference','occurrence_no','taxon_no','reference_no','specimen_no','taxon_name','collection','types_only');
	        push @values,(formatLongRef($ref),$q->numeric_param('occurrence_no'),$q->numeric_param('taxon_no'),$s->get('reference_no'),'-1',$taxon_name,$collection,$q->numeric_param('types_only'));
	        return $hbo->populateHTML('specimen_measurement_form_general', \@values, \@fields);
            } elsif ($q->numeric_param('specimen_no') == -2) {
                if ( $q->param('length') )	{
                    push @fields,'length_position';
                    push @values,$last_position{'length'};
                }
                if ( $q->param('width') )	{
                    push @fields,'width_position';
                    push @values,$last_position{'width'};
                }
		push (@fields,'occurrence_no','taxon_no','reference_no','specimen_no','taxon_name','collection','specimen_coverage');
		push (@values,int($q->param('occurrence_no')),$q->numeric_param('taxon_no'),$s->get('reference_no'),'-1',$taxon_name,$collection,'');
		my ($column_names,$inputs);
		if ( $q->param('N') > 0 )	{
			$column_names = qq|<th><span class="small">N</span></th>|;
			$inputs = qq|  <td><input type="text" name="specimens_measured" value="|.$q->param('N').qq|" size="3" class="tiny"></td>\n|;
		} else	{
			$inputs = qq|  <input type="hidden" name="specimens_measured" value="1">\n|;
		}
		for my $c ( 'mass','length','height','width','circumference','diagonal','diameter','d13C','d18O')	{
			if ( $q->param($c) )	{
				my $cn = $c;
				if ( $c !~ /13C|18O/ )	{
					my @c = split //,$c;
					$c[0] =~ tr/[a-z]/[A-Z]/;
					$cn = join('',@c);
				}
				$cn =~ s/Circumference/Circumf./;
				$cn =~ s/Mass/Mass (g)/;
				$cn =~ s/d13C/&delta;<sup>13<\/sup>C/;
				$cn =~ s/d18O/&delta;<sup>18<\/sup>O/;
				my $average = $c."_average";
				$column_names .= qq|<th><span class="small">$cn</span></th>|;
				$inputs .= qq|  <td><input type="text" name="$average" size=7 class="tiny"></td>
|;
			}
		}
                my $table_rows = "";
                my @default_parts = split /, /,$q->param('default_part');
                my $s = 0;
                for (1..$q->param('specimens_measured')) {
                    $s = ( $s > $#default_parts ) ? 0 : $s;
                    $table_rows .= $hbo->populateHTML('specimen_measurement_form_row',[$q->numeric_param('default_no'),$inputs,$q->param('default_side'),$q->param('default_sex'),$default_parts[$s],$q->param('default_type'),$q->param('default_source'),$q->param('default_magnification'),$q->param('default_comments')],['specimen_id','inputs','specimen_side','sex','specimen_part','specimen_is_type','measurement_source','magnification','comments']);
                    $s++;
                }
                push @fields,('column_names','table_rows');
                push @values,($column_names,$table_rows);
	        return $hbo->populateHTML('specimen_measurement_form_individual', \@values, \@fields);
            }
        }
    } elsif ( my $specimen_no = $q->numeric_param('specimen_no') ) {
        # query the specimen table for the old data
        my $sql = "SELECT * FROM specimens WHERE specimen_no=$specimen_no";
        my $row = ${$dbt->getData($sql)}[0];

        #Query the measurements table for the old data
        $sql = "SELECT * FROM measurements WHERE specimen_no=$specimen_no";
        my @measurements = @{$dbt->getData($sql)};

        # Get the measurement data. types can be "length","width",etc. fields can be "average","max","min",etc.
        my %m_table = (); # Measurement table, only used right below
        $m_table{$_->{'measurement_type'}} = $_ for @measurements;

        # add mass_unit to force display of mass fields and convert
        #  high g values to kg 
        if ( $extant eq "yes" ) {
            push @fields, "mass_unit";
            if ( $m_table{'mass'}{'average'} >= 100 ) {
                push @values , "kg";
                foreach my $f (@measurement_fields) {
                    if ( $m_table{'mass'}{$f} > 0) {
                        $m_table{'mass'}{$f} /= 1000;
                    } 
                } 
            } else {
                push @values , "g";
            }
        }

        for my $type (@measurement_types) {
            for my $f (@measurement_fields) {
                push @fields, $type."_".$f;
                if (exists $m_table{$type}) {
                    push @values, $m_table{$type}{$f};
                } else {
                    push @values, '';
                }
            }
        }
        # special handling needed because only length and width have meaningful
        #  values and _position isn't/shouldn't be in @measurement_fields
        # JA 12.6.12
        for my $type ( 'length','width' )	{
            if ( $m_table{$type}{'position'} )	{
                push @fields , $type."_position";
                push @values , $m_table{$type}{'position'};
            }
        }
        
	for my $field ( @specimen_fields )	{
		push @fields,$field;
		if ( $row->{$field} )	{
			push @values, $row->{$field};
		} else {
			push @values, '';
		}
	}
        # This is an edit, use fields from the DB
        push @fields, 'specimen_is_type';
        if ($row->{'is_type'} eq 'holotype') {
            push @values, 'holotype';
        } elsif ($row->{'is_type'} eq 'some paratypes') {
            push @values, 'some paratypes';
        } elsif ($row->{'is_type'} eq 'paratype') {
            push @values, 'paratype';
        } else {
            push @values, 'no';
        }      

        my $sql = "SELECT author1init,author1last,author2init,author2last,pubyr,reftitle,pubtitle,pubvol,firstpage,lastpage FROM refs WHERE reference_no=".$row->{'reference_no'};
        my $ref = ${$dbt->getData($sql)}[0];

        # if the refs don't agree, the user might want to switch the record to the
        #  current ref
        if ( $row->{'reference_no'} != $s->get('reference_no') )	{
            push @fields , 'switch_to_ref';
            push @values , '<br><div style="margin-top: 0.5em;"><input type="checkbox" name="switch_ref" value="'.$s->get('reference_no').'"> switch this data record to your current reference ('.$s->get('reference_no').')'."</div>\n";
        }

        # allow users to swap records between occurrences or from general
        #  taxon-specific records to particular occurrences
	# exact match on genus and species is required to avoid printing tons of
	#  irrelevant records
	my ($g,$s) = split / /,$taxon_name;
	my $quoted_g = $dbh->quote($g);
	my $quoted_s = $dbh->quote($s);
	my $sql = "(SELECT collection_name,occurrence_no FROM collections c,occurrences o WHERE c.collection_no=o.collection_no AND genus_name='$g' AND species_name='$s') UNION (SELECT collection_name,occurrence_no FROM collections c,reidentifications r WHERE c.collection_no=r.collection_no AND genus_name=$quoted_g AND species_name=$quoted_s) ORDER BY collection_name";
       	my @colls = @{$dbt->getData($sql)};
	if ( @colls )	{
		push @fields , 'occurrences';
		my $occ_list = "<div style=\"margin-top: 0.5em;\">... and/or switch this record to ";
		if ( $#colls == 0 )	{
			$occ_list .= "<input type=\"checkbox\" name=\"switch_occ\" value=\"$colls[0]->{'occurrence_no'}\">$colls[0]->{'collection_name'}<br>\n";
		} elsif ( $#colls <= 9 )	{
			$occ_list .= "one of the following collections:<br>";
			$occ_list .= "<input type=\"radio\" name=\"switch_occ\" value=\"$_->{'occurrence_no'}\" style=\"margin-left: 3em;\">$_->{'collection_name'}<br>\n" foreach @colls;
		} else	{
			$occ_list .= "collection number <input name=\"switch_coll\" size=6>\n<input type=\"hidden\" name=genus_name value=\"$g\">\n<input type=\"hidden\" name=species_name value=\"$s\">\n";
		}
		$occ_list .= "</div>\n";
		push @values , $occ_list;
	}

        # some additional fields not from the form row
	    push (@fields, 'reference','occurrence_no','taxon_no','reference_no','specimen_no','taxon_name','collection','types_only');
	    push (@values, sprintf("%s",formatLongRef($ref)),$q->numeric_param('occurrence_no'),$q->numeric_param('taxon_no'),int($row->{'reference_no'}),$row->{'specimen_no'},$taxon_name,$collection,$q->numeric_param('types_only'));
	    return $hbo->populateHTML('specimen_measurement_form_general', \@values, \@fields);
    }

}

sub processMeasurementForm	{
    my ($dbt,$hbo,$q,$s) = @_;
    my $dbh = $dbt->dbh;
    my $output = '';
    
    # We need a taxon_no passed in, cause taxon_name is ambiguous
    if ( ! $q->numeric_param('occurrence_no') && ! $q->numeric_param('taxon_no')) {
        # push my @error , "";
        return "<center><p>There is no matching taxon or occurrence</p></center>\n";
        # return;
    }

    my $taxon_no = $q->numeric_param('taxon_no');

    # get the taxon's name
    my ($taxon_name,$collection,$newcoll,$badcoll);
    if ($q->numeric_param('occurrence_no')) {
        my $sql = "SELECT o.taxon_no, o.collection_no, o.genus_name, o.species_name, o.occurrence_no FROM occurrences o WHERE o.occurrence_no=".$q->numeric_param('occurrence_no');
        my $row = ${$dbt->getData($sql)}[0];
        $taxon_no = $row->{'taxon_no'};
        $sql = "SELECT taxon_no FROM reidentifications WHERE occurrence_no=".$row->{'occurrence_no'}." AND most_recent='YES'";
        my $reid_taxon = ${$dbt->getData($sql)}[0]->{'taxon_no'};
        if ( $reid_taxon > 0 )	{
            $taxon_no = $reid_taxon;
        }

        my $reid_row = getMostRecentReIDforOcc($dbt,$row->{'occurrence_no'},1);
        if ($reid_row) {
            $taxon_name = $reid_row->{'genus_name'}." ".$reid_row->{'species_name'};
        } else {
            $taxon_name = $row->{'genus_name'}." ".$row->{'species_name'};
        }

        $collection = " in collection $row->{'collection_no'}";

        if (!$row || !$taxon_name || !$collection) {
            return "<center><p>The occurrence of this taxon could not be found</p></center>\n";
        }
    } else {
        my $taxon = PBDB::TaxonInfo::getTaxa($dbt,{'taxon_no'=>$q->numeric_param('taxon_no')});
        if ($taxon->{'taxon_rank'} =~ /species/) {
            $taxon_name = $taxon->{'taxon_name'};
        } elsif ($taxon->{'taxon_rank'} =~ /genus/) {
            $taxon_name = $taxon->{'taxon_name'}." sp.";
        } else {
            $taxon_name = $taxon->{'taxon_name'}." indet.";
        } 
    } 


    my @specimen_ids = $q->param('specimen_id');
    my @param_list = $q->param();

    my ($updated_row_count,$inserted_row_count);
    for(my $i=0;$i<scalar(@specimen_ids);$i++) {
        my %fields = ();

        # This is the part where we rearrange the data into a flat single dimensional
        # hash that contains all the data from single row.  i.e. if $i = 3, the hash
        # will contain the length,width etc from row 3, as well as the intransients like occurrence_no
        foreach my $param (@param_list) {
            my @vars = $q->param($param);
            if (scalar(@vars) == 1) {
                $fields{$param} = $vars[0];
            } else {
                $fields{$param} = $vars[$i];
            }
        }

        # make sure at least one of these fields is set
        my $averages;
        for my $dim ( @measurement_types )	{
            if ( $fields{$dim.'_average'} > 0 )	{
                $averages++;
            } else	{
                $fields{$dim.'_average'} =~ s/[^0-9\.]//g;
            }
        }
        if ( $averages == 0 )	{
            next;
        }

        # kg values have to be rescaled as grams
        if ($fields{'mass_average'} > 0 && $fields{'mass_unit'} eq "kg") {
            for my $f ( @measurement_fields )	{
                $fields{'mass_'.$f} *= 1000;
            }
        }

        # if ecotaph no exists, update the record
        if ($fields{'specimen_is_type'} =~ /holotype/) {
            $fields{'is_type'} = 'holotype';
        } elsif ($fields{'specimen_is_type'} =~ /paratypes/) {
            $fields{'is_type'} = 'some paratypes';
        } elsif ($fields{'specimen_is_type'} =~ /paratype/) {
            $fields{'is_type'} = 'paratype';
        } else {
            $fields{'is_type'} = '';
        }

        # whoops JA 3.6.12
        $fields{'specimen_id'} =~ s/'/\'/;
        $fields{'comments'} =~ s/'/\'/;

        my $specimen_no;

        # prevent duplication by resubmission of form for "new" specimen
        #  JA 21.12.10
        # this is pretty conservative...
        # made less conservative by requiring matches on the comments and
	#  all measurements when there is no specimen ID JA 7-8.9.11
        # and even less conservative (whoops) by requiring a taxon_no or
        #  occurrence_no match even when specimen_id is known JA 1.3.12
        # don't forget sex JA 2.5.12
        my $sex = ( $fields{'sex'} =~ /male/i ) ? "'".$fields{'sex'}."'" : "NULL";
        if ( $fields{'specimen_no'} <= 0 && $fields{'specimen_id'} =~ /[A-Za-z0-9]/ )	{
            my $sql = "SELECT specimen_no FROM specimens WHERE ((taxon_no=".$fields{'taxon_no'}." AND taxon_no>0) OR (occurrence_no=".$fields{'occurrence_no'}." AND occurrence_no>0)) AND specimen_id='".$fields{'specimen_id'}."' AND specimen_id IS NOT NULL AND BINARY specimen_part='".$fields{'specimen_part'}."' AND sex=$sex LIMIT 1";
            $fields{'specimen_no'} = ${$dbt->getData($sql)}[0]->{'specimen_no'};
        } elsif ( $fields{'specimen_no'} <= 0 )	{
            my $sql = "SELECT m.specimen_no,m.measurement_type,m.average,comments FROM specimens s,measurements m WHERE s.specimen_no=m.specimen_no AND ((specimen_id IS NULL AND taxon_no=".$fields{'taxon_no'}." AND taxon_no>0) OR (specimen_id IS NULL AND occurrence_no=".$fields{'occurrence_no'}." AND occurrence_no>0)) AND BINARY specimen_part='".$fields{'specimen_part'}."' AND sex=$sex LIMIT 1";
            my $match = ${$dbt->getData($sql)}[0];
            # preliminary match
            $fields{'specimen_no'} = $match->{'specimen_no'};
            # bomb out if there is any mismatch involving key fields
            if ( $fields{'comments'} ne $match->{'comments'} )	{
                delete $fields{'specimen_no'};
            }
            for my $type ( @measurement_types )	{
                if ( $fields{$type."_average"} != $match->{'average'} && $fields{$type."_average"} > 0 && $match->{'average'} > 0 && $type eq $match->{'measurement_type'} )	{
                    delete $fields{'specimen_no'};
                    last;
                }
            }
        }

        if ( $fields{'specimen_no'} > 0 )	{
            delete $fields{'taxon_no'}; # keys, never update these
            delete $fields{'occurrence_no'}; # keys, never update thse
            if ( $q->param('switch_ref') > 0 )	{
                $fields{'reference_no'} = $q->param('switch_ref');
            }
            if ( $q->param('switch_occ') > 0 )	{
                $fields{'occurrence_no'} = $q->param('switch_occ');
                $fields{'taxon_no'} = undef;
            } elsif ( $q->param('switch_coll') > 0 )	{
		my $switch_coll = $q->numeric_param('switch_coll');
		my $quoted_genus = $dbh->quote($q->param('genus_name'));
		my $quoted_species = $dbh->quote($q->param('species_name'));
                my $sql = "SELECT occurrence_no FROM occurrences WHERE collection_no=$switch_coll AND genus_name=$quoted_genus AND species_name=$quoted_species";
                $fields{'occurrence_no'} = ${$dbt->getData($sql)}[0]->{'occurrence_no'};
                # the user might have screwed up the collection number...
                if ( $fields{'occurrence_no'} == 0 )	{
                    delete $fields{'occurrence_no'};
                } else	{
                    $fields{'taxon_no'} = undef;
		}
            }
            if ( $fields{'occurrence_no'} > 0 )	{
                my $sql = "SELECT collection_name FROM collections c,occurrences o WHERE c.collection_no=o.collection_no AND occurrence_no=".$fields{'occurrence_no'};
                $newcoll = ${$dbt->getData($sql)}[0]->{'collection_name'};
            } elsif ( $q->param('switch_coll') > 0 )	{
		my $switch_coll = $q->numeric_param('switch_coll');
                my $sql = "SELECT collection_name FROM collections c WHERE collection_no=$switch_coll";
                $badcoll = ${$dbt->getData($sql)}[0]->{'collection_name'};
            }
            my $result = $dbt->updateRecord($s,'specimens','specimen_no',$fields{'specimen_no'},\%fields);
            $specimen_no = $fields{specimen_no};

            if ($result) {
                my $sql = "SELECT * FROM measurements WHERE specimen_no=".int($fields{'specimen_no'});
                my @measurements = @{$dbt->getData($sql)};

                my %in_db= (); # Find rows from DB
                $in_db{$_->{'measurement_type'}} = $_ foreach @measurements;

                my %in_cgi = (); # Find rows from filled out form
                foreach my $type (@measurement_types) {
                    foreach my $f (grep(!/error_unit/,@measurement_fields)) {
                        if ($fields{$type."_".$f}) {
                            $in_cgi{$type}{$f} = $fields{$type."_".$f};
                        } 
                    }
                }
                # check to see if the user is simply trying to switch
                #  measurement types on a single record JA 20.5.12
                my @dbs = keys %in_db;
                my @cgis = keys %in_cgi;
                if ( $#dbs == 0 && $#cgis == 0 && $q->param('full_form') =~ /y/i && $dbs[0] ne $cgis[0] )	{
                    $in_db{$cgis[0]} = $in_db{$dbs[0]};
                    $in_cgi{$cgis[0]}{'measurement_type'} = $cgis[0];
                    delete $in_db{$dbs[0]};
                }

                foreach my $type (@measurement_types)	{
                    # if the record exists in both the form and db, update
                    if ($in_db{$type} && $in_cgi{$type}) {
                        foreach my $f (grep(!/error_unit/,@measurement_fields)) {
                            if (!$in_cgi{$type}{$f}) {
                                $in_cgi{$type}{$f} = "";
                            }
                            if ($fields{'magnification'} =~ /^[0-9.]+$/) {
                                if ($in_cgi{$type}{$f}) {
                                    $in_cgi{$type}{'real_'.$f} = $in_cgi{$type}{$f} / $fields{'magnification'};
                                } else {
                                    $in_cgi{$type}{'real_'.$f} = "";
                                }
                            } else {
                                $in_cgi{$type}{'real_'.$f} = $in_cgi{$type}{$f};
                            }
                        }
                        if ( $in_cgi{$type}{'real_error'} )	{
                            $in_cgi{$type}{'error_unit'} = $fields{$type."_error_unit"};
                        }
                        if ( $type eq "length" && $q->param('length_position') )	{
                            $in_cgi{$type}{'position'} = $q->param('length_position');
                        } elsif ( $type eq "width" && $q->param('width_position') )	{
                            $in_cgi{$type}{'position'} = $q->param('width_position');
                        }
                        $dbt->updateRecord($s,'measurements','measurement_no',$in_db{$type}{'measurement_no'},$in_cgi{$type});
                        $updated_row_count++;
                    # if the user submitted a full form and the specimen ID plus
                    #  part plus type is gone it must have been erased by hand,
                    #  so delete it
                    } elsif ( $in_db{$type} && $q->param('full_form') =~ /y/i )	{
                        my $sql = "DELETE FROM measurements WHERE measurement_no=".$in_db{$type}{'measurement_no'} . " LIMIT 1";
                        $dbh->do($sql);
                    # otherwise do nothing because the user isn't actually
                    #  editing the specimen's existing measurements
                    } elsif ( $in_db{$type} )	{
                    # if it's in the form and not the DB, add it
                    } elsif ( $in_cgi{$type} )	{
                        foreach my $f (grep(!/error_unit/,@measurement_fields)) {
                            if ($fields{'magnification'} =~ /^[0-9.]+$/) {
                                $in_cgi{$type}{'real_'.$f} = $in_cgi{$type}{$f}/$fields{'magnification'};
                            } else {
                                $in_cgi{$type}{'real_'.$f} = $in_cgi{$type}{$f};
                            }
                        }
                        $in_cgi{$type}{'measurement_type'} = $type;
                        $in_cgi{$type}{'specimen_no'} = $fields{'specimen_no'};
                        if ( $in_cgi{$type}{'real_error'} )	{
                            $in_cgi{$type}{'error_unit'} = $fields{$type."_error_unit"};
                        }
                        $dbt->insertRecord($s,'measurements',$in_cgi{$type});
                    }
                }

            } else {
                return "<center><p>Error updating database table row, please contact support</p></center>";
            }
        } else {
            # Set the reference_no
            $fields{'reference_no'} = $s->get('reference_no');
            # Make sure one of these gets set to NULL
            if ($q->numeric_param('occurrence_no')) {
                $fields{'taxon_no'} = undef;
            } else {
                $fields{'occurrence_no'} = undef;
            }
            my $result;
            ($result,$specimen_no) = $dbt->insertRecord($s,'specimens',\%fields);

            if ($result) {
                # Get the measurement data. types can be "length","width",etc. fields can be "average","max","min",etc.
                my %m_table = (); # Measurement table, only used right below
                foreach my $type (@measurement_types) {
                    foreach my $f (grep(!/error_unit/,@measurement_fields)) {
                        if ($fields{$type."_".$f}) {
                            $m_table{$type}{$f} = $fields{$type."_".$f};
                        } 
                    }
                }

                # Now insert a row into the measurements table for each type of measurement
                while(my($type,$row)=each %m_table) {
                    foreach my $f (grep(!/error_unit/,@measurement_fields)) {
                        next if (!$row->{$f});
                        if ($fields{'magnification'} =~ /^[0-9.]+$/) {
                            $row->{'real_'.$f} = $row->{$f}/$fields{'magnification'}; 
                        } else {
                            $row->{'real_'.$f} = $row->{$f};
                        }
                    }
                    $row->{'measurement_type'} = $type;
                    $row->{'specimen_no'} = $specimen_no;
                    $row->{'error_unit'}=$fields{$type."_error_unit"};
                    if ( $type eq "length" && $q->param('length_position') )	{
                        $row->{'position'} = $q->param('length_position');
                    } elsif ( $type eq "width" && $q->param('width_position') )	{
                        $row->{'position'} = $q->param('width_position');
                    }
                    $dbt->insertRecord($s,'measurements',$row);
                }

                $inserted_row_count++;
            } else {
                return "<center><p>Error inserting database table row, please contact support</p></center>";
            }
        }
        if ($specimen_no) {
            syncWithAuthorities($dbt,$s,$hbo,$specimen_no);
        }
    }

    if ( $updated_row_count > 0 )	{
        #$output .= "<center><p class=\"pageTitle\">$taxon_name$collection (revised data)</p></center>\n";
    } elsif ( $inserted_row_count > 0 )	{
        #$output .= "<center><p class=\"pageTitle\">$taxon_name$collection (new data)</p></center>\n";
    }

    if ( $q->param('switch_occ') > 0 || $q->param('switch_coll') > 0 )	{
        if ( $newcoll )	{
            $output .= "<div style=\"width: 32em; margin-left: auto; margin-right: auto; text-indent: -1em;\"><p class=\"verysmall\">The data record you updated has been switched successfully to $newcoll. You can search for it by clicking the 'another collection' link.</p></div>\n";
        } elsif ( $badcoll )	{
            $output .= "<div style=\"width: 32em; margin-left: auto; margin-right: auto; text-indent: -1em;\"><p class=\"verysmall\">The data record was not switched because $taxon_name is not present in $badcoll. Try entering a different collection number.</p></div>\n";
        }
    }

	my $more_links = "<div class=\"verysmall\" style=\"margin-bottom: 0.5em;\">add/edit a measurement of " . makeAnchor("displaySpecimenSearchForm", "", "another taxon");
	# if ( $collection_no > 0 )	{
	# 	$more_links .= " or " . makeAnchor("submitSpecimenSearch", "collection_no=$collection_no", "another occurrence in this collection") . "<br>";
	# }
	$more_links .= " or another " . makeAnchor("submitSpecimenSearch", "taxon_name=$taxon_name", "occurrence") . " of $taxon_name, or</div>
";
	$output .= displaySpecimenList($dbt,$hbo,$q,$s,'processMeasurementForm',$more_links);
	if ($q->numeric_param('occurrence_no')) {
		my ($temp,$collection_no) = split / /,$collection;
		$collection_no =~ s/\)//;
	}
	$output .= qq|
</table>
</div>
</div>
</center>
|;

    return $output;
    
    # a block of code here that used to cache body mass estimates was removed
    #  by JA 4.6.13
    # it wasn't needed because nothing in the system actually used the values

}


# deleteSpecimen ( )
# 
# MM 04.04.14 Delete the specimen selected by the parameters, along with all
# measurements that have been entered for it.  If an error occurs, return the
# appropriate message as a string.

sub deleteSpecimen {

    my ($dbt, $hbo, $q, $s) = @_;
    
    my $dbh = $dbt->{dbh};
    my $specimen_no = $q->numeric_param('delete_specimen_no') + 0;
    my $specimen_id = $q->param('delete_specimen_id') || '';
    my ($sql, $result);
    
    # First check permissions.
    
    my ($specimen_authorizer_no, $specimen_enterer_no) = $dbh->selectrow_array("
	SELECT authorizer_no, enterer_no FROM specimens
	WHERE specimen_no = $specimen_no");
    
    my $authorizer_no = $s->{authorizer_no};
    my $enterer_no = $s->{enterer_no};
    
    unless ( $specimen_enterer_no == $enterer_no || $specimen_authorizer_no == $authorizer_no )
    {
	return "You do not have permission to delete the specimen '$specimen_id'.";
    }
    
    # If we get here, then we have permission.  Start by deleting all measurements.
    
    $sql = "DELETE FROM measurements WHERE specimen_no = $specimen_no";
    
    $result = $dbh->do($sql);
    
    # Then delete the specimen record itself.
    
    $sql = "DELETE FROM specimens WHERE specimen_no = $specimen_no";
    
    $result = $dbh->do($sql);
    
    # Return an empty result, indicating no error.
    
    return;
}


# rewrote this heavily JA 10.8.07
# all authorities data manually entered before that point are suspect
sub syncWithAuthorities {
    my ($dbt,$s,$hbo,$specimen_no) = @_;

    my $sql = "SELECT s.taxon_no,specimens_measured,specimen_id,specimen_part,magnification,is_type,type_specimen,type_body_part,part_details FROM specimens s,authorities a WHERE specimen_no=$specimen_no AND s.taxon_no=a.taxon_no";
    my $row = ${$dbt->getData($sql)}[0];
    my %fields;

    # bomb out if the specimens data don't clearly pertain to the type or
    #  the authorities table has complete data already
    # we don't want to mess around if there's conflict, because (for example)
    #  the type specimen per se may include additional body parts on top of
    #  the one that has been measured
    if ( ! $row || $row->{'taxon_no'} < 1 || $row->{'specimens_measured'} != 1 || $row->{'is_type'} ne "holotype" || ( $row->{'magnification'} && $row->{'magnification'} != 1 ) || ( $row->{'type_specimen'} && $row->{'type_body_part'} && $row->{'part_details'} ) )	{
        return;
    } else	{
        my $taxon_no = $row->{'taxon_no'};
        my %generic_parts = ();
        foreach my $p ($hbo->getList('type_body_part'))	{
            $generic_parts{$p} = 1;
        }
        if ( $row->{'specimen_part'} )	{
            if ( $generic_parts{$row->{'specimen_part'}} && ! $row->{'type_body_part'} ) {
                $fields{'type_body_part'} = $row->{'specimen_part'};
            } elsif ( ! $row->{'part_details'} )	{
                $fields{'part_details'} = $row->{'specimen_part'};
            }
        }
        if ( ! $row->{'type_specimen'} )	{
            $fields{'type_specimen'} = $row->{'specimen_id'};
        }
        $dbt->updateRecord($s,'authorities','taxon_no',$taxon_no,\%fields);
    }
}

# simple special-purpose function only used by displaySpecimenList that
#  exists strictly to enable disentangling of Fossilworks JA 4.6.13
sub getMeasurements	{
    my ($dbt,$occurrence_no) = @_;
    my $dbh = $dbt->dbh;

    my @fields = ('s.*','m.*');
    my @tables = ('specimens s','measurements m');

    my $sql1 = "SELECT ".join(',',@fields).",o.taxon_no FROM ".join(', ',@tables).", occurrences o";
    my $sql2 = "SELECT ".join(',',@fields).",re.taxon_no FROM ".join(', ',@tables).", occurrences o, reidentifications re";

    $sql1 .= " LEFT JOIN reidentifications re ON re.occurrence_no=o.occurrence_no WHERE s.occurrence_no=o.occurrence_no AND s.specimen_no=m.specimen_no AND re.reid_no IS NULL";
    $sql2 .= " WHERE s.occurrence_no=o.occurrence_no AND s.specimen_no=m.specimen_no AND re.occurrence_no=o.occurrence_no AND re.most_recent='YES'";

    $sql1 .= " AND o.occurrence_no=".int($occurrence_no);
    $sql2 .= " AND o.occurrence_no=".int($occurrence_no);
    my $sql = "($sql1) UNION ($sql2)";

    return @{$dbt->getData($sql)};
}

1;
