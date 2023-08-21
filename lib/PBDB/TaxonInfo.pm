# 
# Paleobiology Database -- TaxonInfo.pm
# 
# This module contains routines for displaying the details about a taxon.
# 

package PBDB::TaxonInfo;

use strict;

use PBDB::Taxonomy qw(getOriginalCombination getMostRecentSpelling getAllSpellings
		      getClassification getAllClassification getImmediateChildren
		      getParents getParent getClassOrderFamily
		      getChildren getTaxa getTaxonNos
		      getSeniorSynonym getJuniorSynonyms getAllSynonyms
		      disusedNames splitTaxon getBestClassification computeMatchLevel);

use PBDB::Taxon qw(guessTaxonRank formatTaxon);
use PBDB::Collection;
use PBDB::CollectionEntry;
use PBDB::Reference qw(formatShortRef formatLongRef);
use PBDB::PrintHierarchy;
use PBDB::Ecology;
use PBDB::EcologyEntry;
#use Images;
use PBDB::Measurement qw(getMeasurements getMeasurementTable getMassEstimates);
use PBDB::Debug qw(dbg);
use PBDB::PBDBUtil qw(checkForBot);
use PBDB::Constants qw($INTERVAL_URL $GDD_URL $HTML_DIR $TAXA_TREE_CACHE 
		       makeATag makeAnchor makePageAnchor makeAnchorWithAttrs makeURL);


# JA: fixed this 21.10.04
sub searchForm {
	my $hbo = shift;
	my $q = shift;
	my $search_again = (shift or 0);

	my $page_title = "Taxonomic name search form"; 
    
	if ($search_again)	{
		$page_title = "<p class=\"medium\">No results found (please search again)</p>";
	}
	my @ranks = $hbo->getList('taxon_rank');
	shift @ranks;
	my $rank_select = "<select name=\"taxon_rank\"><option>".join('</option><option>',@ranks)."</option></select>\n";
	$rank_select =~ s/>species</ selected>species</;
	return $hbo->populateHTML('search_taxoninfo_form' , [$page_title,'',$rank_select], ['page_title','page_subtitle','taxon_rank_select']);
}

# This is the front end for displayTaxonInfoResults - always use this instead if you want to 
# call from another script.  Can pass it a taxon_no or a taxon_name
sub checkTaxonInfo {
    my ($q, $s, $dbt, $hbo) = @_;

    my $dbh = $dbt->dbh;
    my $output = '';
    
	if ( ! $q->param('taxon_name') && ! $q->param('museum') && $q->param('search_again') )	{
		my $name = $q->param('search_again');
		$q->param('taxon_name' => $name);
	}

    if (!$q->param("taxon_no") && !$q->param("taxon_name") && !$q->param("common_name") && !$q->param("author") && !$q->param("pubyr") && !$q->param("museum")) {
        return searchForm($hbo, $q, 1); # param for not printing header with form
    }

    if ($q->numeric_param('taxon_no')) {
        # If we have is a taxon_no, use that:
        return displayTaxonInfoResults($dbt,$s,$q,$hbo);
    } elsif (!$q->param('taxon_name') && !($q->param('common_name')) && !($q->param('pubyr')) && !$q->param('author') && !$q->param('museum')) {
        return searchForm($hbo,$q);
    } else {
        my @results;
        if ( my $museum = $q->param('museum') )
	{
	    my $quoted = $dbh->quote($museum);
            my $sql = "SELECT a.taxon_no FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND museum=$quoted GROUP BY taxon_no";
            my @nos = map { $_->{'taxon_no'} } @{$dbt->getData($sql)};
            $q->param('taxa' => join(',',@nos));
        }
        if ( $q->param('taxa') )	{
            my $morewhere;
            if ( $q->param('author') )	{
                my $author = $q->param('author');
                my $init;
                # if initials are supplied there must be an exact match on them because
                #  you can always leave them out if you want a vague match
                # up to three initials can be parsed
                if ( $author =~ /^[A-Z]( |\.|[A-Z](\.|) |[A-Z](\.|)[A-Z](\.|) )/ )	{
                    $author =~ s/(\.)([A-Z])/$2/g;
                    $author =~ s/^([A-Z])([A-Z])([A-Z])/$1 $2 $3/;
                    $author =~ s/^([A-Z])([A-Z])/$1 $2/;
                    $author =~ s/([A-Z])( )/$1. /g;
                    ($init,$author) = split / /,$author,2;
                    while ( $author =~ /^[A-Z]\. / )	{
                        my $init2;
                        ($init2,$author) = split / /,$author,2;
                        $init .= " ".$init2;
                    }
		    
		    my $quoted_init = $dbh->quote($init);
		    my $quoted_author = $dbh->quote($author);
		    
                    $morewhere .= " AND ((((a.author1init=$quoted_init AND a.author1last=$quoted_author) OR (a.author2init=$quoted_init AND a.author2last=$quoted_author)) AND ref_is_authority='') OR (((r.author1init=$quoted_init AND r.author1last=$quoted_author) OR (r.author2init=$quoted_init AND r.author2last=$quoted_author)) AND ref_is_authority='YES'))";
                } else	{
 		    my $quoted_author = $dbh->quote($author);
		    $morewhere .= " AND (((a.author1last=$quoted_author OR a.author2last=$quoted_author) AND ref_is_authority='') OR ((r.author1last=$quoted_author OR r.author2last=$quoted_author) AND ref_is_authority='YES'))";
                }
            }
            if ( my $pubyr = $q->param('pubyr') )
	    {
		my $quoted_pubyr = $dbh->quote($pubyr);
                $morewhere .= " AND ((a.pubyr=$quoted_pubyr AND ref_is_authority='') OR (r.pubyr=$quoted_pubyr AND ref_is_authority='YES'))";
            }
            my $sql = "SELECT a.*,IF (ref_is_authority='YES',r.author1last,a.author1last) author1last,IF (ref_is_authority='YES',r.author2last,a.author2last) author2last,IF (ref_is_authority='YES',r.otherauthors,a.otherauthors) otherauthors,IF (ref_is_authority='YES',r.pubyr,a.pubyr) pubyr,pages,figures,ref_is_authority,a.reference_no FROM authorities a,refs r WHERE a.reference_no=r.reference_no AND taxon_no IN (".join(',',$q->param('taxa')).") $morewhere";
            @results = @{$dbt->getData($sql)};
            # still might bomb if author and/or pubyr were submitted
            if ( ! @results )	{
                return searchForm($hbo, $q, 1); # param for not printing header with form
            }
        } else	{
            my $temp = $q->param('taxon_name');
            $temp =~ s/ sp\.//;
            $temp =~ s/\./%/g;
            $q->param('taxon_name' => $temp);
            my $options = {'match_subgenera'=>1,'remove_rank_change'=>1};
            foreach ('taxon_name','common_name','author','pubyr') {
                if ($q->param($_)) {
                    $options->{$_} = $q->param($_);
                }
            }
            @results = getTaxa($dbt,$options,['taxon_no','taxon_rank','taxon_name','common_name','author1last','author2last','otherauthors','pubyr','pages','figures','comments','discussion']);
        }

        if(scalar @results < 1 && $q->param('taxon_name'))	{
            # If nothing from authorities, go to occs + reids
            my ($genus,$subgenus,$species,$subspecies) = splitTaxon($q->param('taxon_name'));
            my $where = "WHERE genus_name LIKE ".$dbh->quote($genus);
            if ($subgenus) {
                $where .= " AND subgenus_name LIKE ".$dbh->quote($subgenus);
            }
            if ($species) {
                $where .= " AND species_name LIKE ".$dbh->quote($species);
            }
            my $sql = "(SELECT genus_name FROM occurrences $where GROUP BY genus_name)".
                   " UNION ".
                   "(SELECT genus_name FROM reidentifications $where GROUP BY genus_name)";
            my @occs = @{$dbt->getData($sql)};
            if (scalar(@occs) >= 1) {
                #my $taxon_name = $genera[0]->{'genus_name'};
                #if ($species) {
                #    $taxon_name .= " $species";
                #}    
                #$q->param('taxon_name'=>$taxon_name);
                return displayTaxonInfoResults($dbt,$s,$q,$hbo);
            } else {
                # If nothing, print out an error message
                my $output = searchForm($hbo, $q, 1); # param for not printing header with form
                if($s->isDBMember() && $s->get('role') =~ /authorizer|student|technician/) {
		    my $link = makeURL('submitTaxonSearch', "goal=authority&amp;taxon_name=".$q->param('taxon_name'));
                    $output .= "<center><p><a href=\"$link\"><b>Add taxonomic information</b></a></center>";
		}
		return $output;
             }
        } elsif(scalar @results < 1 && ! $q->param('taxon_name'))	{
            my $output = searchForm($hbo, $q, 1); # param for not printing header with form
            if($s->isDBMember() && $s->get('role') =~ /authorizer|student|technician/) {
		my $link = makeURL('submitTaxonSearch', "goal=authority&amp;taxon_name=".$q->param('taxon_name'));
                $output .= "<center><p><a href=\"$link\"><b>Add taxonomic information</b></a></center>";
            }
	    return $output;
        } elsif(scalar @results == 1)	{
            $q->param('taxon_no'=>$results[0]->{'taxon_no'});
            return displayTaxonInfoResults($dbt,$s,$q,$hbo);
        } else	{
            return listTaxonChoices($dbt,$hbo,\@results);
        }
    }
}

# By the time we're here, we're gone through checkTaxonInfo and one of these scenarios has happened
#   1: taxon_no is set: taxon is in the authorities table
#   2: taxon_name is set: NOT in the authorities table, but in the occs/reids table
# If neither is set, bomb out, we shouldn't be here
#   entered_name could also be set, for link display purposes. entered_name may not correspond 
#   to taxon_no, depending on if we follow a synonym or go to an original combination

sub displayTaxonInfoResults {
    
    my ($dbt,$s,$q,$hbo) = @_;
    
    my $dbh = $dbt->dbh;
    my $output = '';
    
    my $taxon_no = $q->numeric_param('taxon_no');
    my $taxon_name = $q->param('taxon_name');
    
    # if ( $taxon_no =~ /^(\d+)[^\d]/ )
    # {
    # 	$taxon_no = $1;
    # }
    
    my ($is_real_user,$not_bot) = (0,1);
    
    if ($q->request_method() eq 'POST' || $q->param('is_real_user') || $s->isDBMember())
    {
        $is_real_user = 1;
        $not_bot = 1;
    }
    
    if (PBDB::PBDBUtil::checkForBot())
    {
        $is_real_user = 0;
        $not_bot = 0;
    }
    
    # Get most recently used name of taxon
    
    my ($orig_no, $spelling_no);
    my ($common_name, $taxon_rank, $type_locality, $discussion, $discussant, $email);
    
    if ( $taxon_no )
    {
	$orig_no = getOriginalCombination($dbt, $taxon_no) ||
            return "<div align=\"center\">taxon number $taxon_no doesn't exist in the database</div>\n";
	
	# I am commenting out the call to getSeniorSynonym, so that info for the specified
	# taxon is displayed instead of its senior synonym. People can find the senior
	# synonym themselves if they wish. MM 2023-07-17 $taxon_no =
	# getSeniorSynonym($dbt,$orig_no);
	
        # This actually gets the most correct name
        my $taxon = getMostRecentSpelling($dbt,$taxon_no);
        
	$spelling_no = $taxon->{'taxon_no'};
        $taxon_name = $taxon->{'taxon_name'};
        $common_name = $taxon->{'common_name'};
        $taxon_rank = $taxon->{'taxon_rank'};
        $type_locality = $taxon->{'type_locality'};
        
	# discussion info needed below JA 8.9.11
        $discussion = $taxon->{'discussion'};
        
	# avoid a join in getMostRecentSpelling that all sorts of functions would invoke
	# incessantly
        if ( $taxon->{'discussed_by'} > 0 )
	{
            my $sql = "SELECT name AS discussant,email FROM person WHERE person_no=".$taxon->{'discussed_by'};
            my $person = ${$dbt->getData($sql)}[0];
            $discussant = $person->{'discussant'};
            $email = $person->{'email'};
        }
    }
    
    else
    {
        $taxon_name = $q->param('taxon_name');
    }
    
    # Get the sql IN list for a Higher taxon:
    my $in_list;
    my $quick = ! $is_real_user;
    
    if ($taxon_no)
    {
        my $sql = "SELECT count(*) as diff
		   FROM $TAXA_TREE_CACHE as t JOIN $TAXA_TREE_CACHE as base on t.lft between base.lft and base.rgt
		   WHERE base.taxon_no=$taxon_no";
        my ($diff) = $dbh->selectrow_array($sql);
	
        if ($diff > 100000)
	{
            $in_list = [-1];
        }
	
	else
	{
            my @in_list = getChildren($dbt,$taxon_no);
            $in_list=\@in_list;
        }
    }
    
    $output .= "<div>\n";
    
    my @modules_to_display = (1,2,3,4,5,6,7,8);
    
    if ( ! $not_bot )
    {
        @modules_to_display = (1,2);
    }
    
    my $display_name = $taxon_name;
    
    if ( $common_name =~ /[A-Za-z]/ )
    {
        $display_name .= " ($common_name)";
    } 
    
    if ($taxon_no && $common_name !~ /[A-Za-z]/)
    {
        my $mrpo = getClassification($dbt, $orig_no);
        my $last_status = $mrpo->{'status'};
	
	if ( $last_status =~ /nomen/ )
	{
	    $display_name .= " ($last_status)";
	}
	
	else
	{
	    my $sql = "SELECT count(*) FROM $TAXA_TREE_CACHE as base
			join $TAXA_TREE_CACHE as t on t.lft between base.lft and base.rgt
			join authorities as a on a.taxon_no = t.taxon_no
		       WHERE base.taxon_no = $taxon_no and 
			     taxon_rank in ('genus', 'subgenus', 'species', 'subspecies')";
	    
	    my ($used) = $dbh->selectrow_array($sql);
	    
	    unless ( $used )
	    {
		$display_name .= " (disused)";
	    }
	}
	
        # if ( $not_bot )
	# {
        #     my %disused;
        #     my $sql = "SELECT synonym_no FROM $TAXA_TREE_CACHE WHERE taxon_no=$taxon_no";
        #     my ($ss_no) = $dbh->selectrow_array($sql);
        #     if ($taxon_rank !~ /genus|species/) {
        #         %disused = %{disusedNames($dbt,$ss_no)};
        #     }
	    
        #     if ($disused{$ss_no}) {
        #         $display_name .= " (disused)";
        #     } elsif ($last_status =~ /nomen/) {
        #         $display_name .= " ($last_status)";
        #     }
        # }
    }
    
    $output .= '
<script src="/public/classic_js/included_taxa.js" language="JavaScript" type="text/javascript"></script>
<script src="/public/classic_js/taxoninfo.js" language="JavaScript" type="text/javascript"></script>
<script language="JavaScript" type="text/javascript">
var gddapp = new GDDTaxonInfoApp ( "' . $GDD_URL . '", "' . $taxon_name . '", "panel7", "gddapp" );
</script>

<div align="center">
  <table class="panelNavbar" cellpadding="0" cellspacing="0" border="0">
  <tr>
    <td id="tab1" class="tabOff" onClick="switchToPanel(1,8);">
      Basic info</td>
    <td id="tab2" class="tabOff" onClick="switchToPanel(2,8);">
      Taxonomic history</td>
    <td id="tab3" class="tabOff" onClick = "switchToPanel(3,8);">
      Classification</td>
    <td id="tab4" class="tabOff" onClick = "switchToPanel(4,8);">
      Included Taxa</td>
  </tr>
  <tr>
    <td id="tab5" class="tabOff" onClick="switchToPanel(5,8);">
      Morphology</td>
    <td id="tab6" class="tabOff" onClick = "switchToPanel(6,8);">
      Ecology and taphonomy</td>
    <td id="tab7" class="tabOff" onClick = "switchToPanel(7,8); gddapp.initApp();">
      External Literature Search</td>
    <td id="tab8" class="tabOff" onClick = "switchToPanel(8,8);">
      Age range and collections</td>
  </tr>
  </table>
</div>
';

    my ($htmlCOF,$htmlClassification);
    
    if ( $not_bot )
    {
        ($htmlCOF,$htmlClassification) = displayTaxonClassification($dbt, $orig_no, $taxon_name, $is_real_user);
    }
    
    $output .= qq|
<div align="center" style="margin-bottom: -1.5em;">
<p class="pageTitle" style="white-space: nowrap; margin-bottom: 0em;">$display_name</p>
<p class="medium">$htmlCOF</p>
</div>


|;

    
#     $output .= '<script language="JavaScript" type="text/javascript">
#     hideTabText(2);
#     hideTabText(3);
#     hideTabText(4);
#     hideTabText(5);
#     hideTabText(6);
#     hideTabText(7);
#     hideTabText(8);
# </script>';

    my %modules = ();
    $modules{$_} = 1 foreach @modules_to_display;
    
    my $htmlBasicInfo = displaySynonymyParagraph($dbt, $taxon_no, $orig_no, $is_real_user);
    
    my $htmlSynonyms = displayTaxonHistory($dbt, $orig_no, $is_real_user);
    
    # classification
    
    if($modules{1})
    {
        $output .= '<center>';
        $output .= '<div id="panel1" class="panel">';
        my $width = "52em;";
        if ( $htmlBasicInfo =~ /No taxon/ )
	{
            $width = "44em;";
        }
	
        #doThumbs($dbt,$in_list);
	
	# JA 5.9.11
	if ( $discussion )
	{
	    $discussion =~ s/(\[\[)([A-Za-z ]+|)(taxon )([0-9]+)(\|)/makeATag('basicTaxonInfo', "taxon_no=$4")/ge;
	    $discussion =~ s/(\[\[)([A-Za-z0-9\'\. ]+|)(ref )([0-9]+)(\|)/makeATag('displayReference', "reference_no=$4")/ge;
	    $discussion =~ s/(\[\[)([A-Za-z0-9\'"\.\-\(\) ]+|)(coll )([0-9]+)(\|)/makeATag('basicCollectionSearch', "collection_no=$4")/ge;
	    $discussion =~ s/\]\]/<\/a>/g;
	    $discussion =~ s/\n\n/<\/p>\n<p>/g;
	    
	    $email =~ s/\@/\' \+ \'\@\' \+ \'/;
	    
	    $output .= qq|<div align="center" class="small" style="margin-left: 1em; margin-top: 1em;">
<div style="width: $width;">
<div class="displayPanel" style="margin-bottom: 3em; padding-left: 1em; padding-top: -1em; padding-bottom: 1.5em; text-align: left;">
<span class="displayPanelHeader">Discussion</span>
<div align="center" class="small displayPanelContent" style="text-align: left;">
<p>$discussion</p>
|;

	    if ( $discussant ne "" )
	    {
		$output .= qq|<script language="JavaScript" type="text/javascript">
    <!-- Begin
    window.onload = showMailto;
    function showMailto( )      {
        document.getElementById('mailto').innerHTML = '<a href="' + 'mailto:' + '$email?subject=$taxon_name">$discussant</a>';
    }
    // End -->
</script>

<p class="verysmall">Send comments to <span id="mailto">me</span><p>
|;
	    }
	    
	    $output .= "</div></div></div></div>\n";
	}
	
        $output .= qq|<div align="center" class="small" style="margin-left: 1em; margin-top: 1em;">
<div style="width: $width;">
<div class="displayPanel" style="margin-top: -1em; margin-bottom: 2em; padding-left: 1em; text-align: left;">
<span class="displayPanelHeader">Taxonomy</span>
<div align="left" class="small displayPanelContent" style="padding-left: 1em; padding-bottom: 1em;">
|;
	
	$output .= $htmlBasicInfo;
	$output .= "</div>\n</div>\n\n";
	
        my $entered_name = $q->param('entered_name') || $q->param('taxon_name') || $taxon_name;
        my $entered_no = $q->numeric_param('entered_no') || $q->numeric_param('taxon_no');
        $output .= "<p>";
        $output .= "<div>";
        $output .= "<center>";
	
        $output .= displayRelatedTaxa($dbt, $orig_no, $spelling_no, $taxon_name, $is_real_user);
	$output .= "</center>\n";
        
	if($s->isDBMember() && $s->get('role') =~ /authorizer|student|technician/)
	{
            # Entered Taxon
            if ($entered_no) {
                $output .= makeATag("displayAuthorityForm", "taxon_no=$entered_no");
                $output .= "<b>Edit taxonomic data for $entered_name</b></a> - ";
            } else {
                $output .= makeATag("submitTaxonSearch", "goal=authority&amp;taxon_no=-1&amp;taxon_name=$entered_name");
                $output .= "<b>Enter taxonomic data for $entered_name</b></a> - ";
            }

            if ($entered_no) {
                $output .= makeATag("displayOpinionChoiceForm", "taxon_no=$entered_no");
		$output .= "<b>Edit taxonomic opinions about $entered_name</b></a> -<br> ";
                $output .= makeATag("startPopulateEcologyForm", "taxon_no=$taxon_no");
		$output .= "<b>Add/edit ecological/taphonomic data</b></a> - ";
            }
        }
	
        $output .= "</div>\n";
        $output .= "</p>";
        $output .= "</div>\n</div>\n</div>\n\n";
        $output .= '</center>';
    }

    # synonymy
    
    if($modules{2})
    {
        $output .= '<center>';
        $output .= qq|<div id="panel2" class="panel";">
<div align="center" class="small"">
|;
	if ( $htmlSynonyms )
	{
	    $output .= qq|<div class="displayPanel" style="margin-bottom: 2em; padding-top: -1em; width: 42em; text-align: left;">
<span class="displayPanelHeader">Synonyms</span>
<div align="center" class="small displayPanelContent">
|;
	    $output .= $htmlSynonyms;
	    $output .= "</div>\n</div>\n";
	}
	
    	$output .= displaySynonymyList($dbt, $orig_no);
	
        if ( $taxon_no )
	{
            $output .= "<p>Is something missing? ";
	    $output .= makePageAnchor('join_us', 'Join the Paleobiology Database');
	    $output .= " and enter the data</p>\n";
        }
	
	else
	{
            $output .= "<p>Please ";
	    $output .= makePageAnchor('join_us', 'join the Paleobiology Database');
	    $output .= " and enter some data</p>\n";
        }
	
        $output .= "</div>\n</div>\n</div>\n";
        $output .= '</center>';
    }
    
    if ($modules{3})
    {
        $output .= '<div id="panel3" class="panel">';
        $output .= '<div align="center">';
        $output .= $htmlClassification;
        $output .= "</div>\n</div>\n\n";
    }
    
    if ($modules{4})
    {
        $output .= '<div id="panel4" class="panel">';
        $output .= '<div align="center" class="small">';
	
	if ( $taxon_no )
	{
	    $output .= PBDB::PrintHierarchy::displayIncludedTaxa($dbt,'taxon_no', $orig_no);
	}
	
        $output .= "</div>\n";
        $output .= "</div>\n";
    }
    
    if ($modules{5})
    {
        $output .= '<div id="panel5" class="panel">';
        $output .= '<div align="center" class="small" "style="margin-top: -2em;">';
        $output .= displayDiagnoses($dbt, $taxon_no);
	
        unless ($quick)
	{
            $output .= displayMeasurements($dbt,$orig_no,$taxon_name,$in_list);
        }
	
        $output .= "</div>\n";
        $output .= "</div>\n";
    }
    
    if ($modules{6})
    {
        $output .= '<center>';
        $output .= '<div id="panel6" class="panel">';
        $output .= '<div align="center" clas="small">';
	
        unless ($quick)
	{
            $output .= displayEcology($dbt,$orig_no,$in_list);
        }
	
        $output .= "</div>\n";
        $output .= "</div>\n";
        $output .= '</center>';
    }
   
    my $collectionsSet;
    
    if ($is_real_user)
    {
        $collectionsSet = getCollectionsSet($dbt,$q,$s,$in_list,$taxon_name);
    }
    
    if ($modules{7})
    {
        $output .= '<center>';
        $output .= '<div id="panel7" class="panel">';
        # $output .= '<div align="center" style="margin-top: -1em;">';

        # if ($is_real_user) {
	#     eval {
	# 	displayMap($dbt,$q,$s,$collectionsSet);
	#     };
	#     if ( @$ )
	#     {
	# 	$output .= "<center><p>The map could not be displayed, because an error occurred.</p></center>\n";
	#     }
        # } else {
        #     $output .= qq|<form method="POST" action="">|;
        #     foreach my $f ($q->param()) {
        #         $output .= "<input type=\"hidden\" name=\"$f\" value=\"".$q->param($f)."\">\n";
        #     }
        #     $output .= "<input type=\"hidden\" name=\"show_panel\" value=\"7\">\n";
        #     $output .= "<input type=\"submit\" name=\"submit\" value=\"Show map\">";
        #     $output .= "</form>\n";
        # }
        # $output .= "</div>\n";
        $output .= "</div>\n";
        $output .= '</center>';
    }
    
    # collections
    
    if ($modules{8})
    {
        $output .= '<center>';
        $output .= '<div id="panel8" class="panel">';
	
        if ($is_real_user)
	{
	    $output .= doCollections($dbt, $s, $collectionsSet, $display_name, $orig_no, $in_list, '', $is_real_user, $type_locality);
        }
	
	else
	{
            $output .= '<div align="center">';
            $output .= qq|<form method="POST" action="">|;
            foreach my $f ($q->param()) {
                $output .= "<input type=\"hidden\" name=\"$f\" value=\"".$q->param($f)."\">\n";
            }
            $output .= "<input type=\"hidden\" name=\"show_panel\" value=\"8\">\n";
            $output .= "<input type=\"submit\" name=\"submit\" value=\"Show age range and collections\">";
            $output .= "</form>\n";
            $output .= "</div>\n";
        }
        $output .= "</div>\n";
        $output .= '</center>';
    }
    
    if ( ! $q->param('show_panel') )
    {
        $output .= "<script language=\"JavaScript\" type=\"text/javascript\">switchToPanel(1,8);</script>\n";
    }
    
    else
    {
        $output .= "<script language=\"JavaScript\" type=\"text/javascript\">switchToPanel(".$q->param('show_panel').",8);</script>\n";
    }
    
    $output .= "</div>"; # Ends div class="small" declared at start

    return $output;
}

# used only by displayTaxonInfoResults
sub getCollectionsSet {
    my ($dbt,$q,$s,$in_list,$taxon_name) = @_;

    my $fields = ['country','state','max_interval_no','min_interval_no','latdeg','latdec','latmin','latsec','latdir','lngdeg','lngdec','lngmin','lngsec','lngdir','seq_strat'];

    # Pull the colls from the DB;
    my %options = ();
    $options{'permission_type'} = 'read';
    $options{'calling_script'} = 'PBDB::TaxonInfo';
    if ($in_list && @$in_list) {
        $options{'taxon_list'} = $in_list;
    } elsif ($taxon_name) {
        $options{'taxon_name'} = $taxon_name;
    }
    
    # These fields passed from strata module,etc
    #foreach ('group_formation_member','formation','geological_group','member','taxon_name') {
    #    if (defined($q->param($_))) {
    #        $options{$_} = $q->param($_);
    #    }
    #}
    my ($dataRows) = PBDB::CollectionEntry::getCollections($dbt,$s,\%options,$fields);
    return $dataRows;
}

# # heavily rewriten to switch from using htmlTaxaTree to using classify
# #   JA 27.2.12
# sub doCladograms {
#     my ($dbt,$hbo,$q,$s,$taxon_no,$spelling_no,$taxon_name) = @_;

#     my $output = '';    
#     my $parent_no;
#     my $stepsup = 1;
#     if ( $taxon_no < 1 && $taxon_name =~ / / )	{
#         my ($genus,$subgenus,$species,$subspecies) = splitTaxon($taxon_name);
#         $parent_no = getBestClassification($dbt,'',$genus,'',$subgenus,'',$species);
#         $stepsup = 0;
#     } else	{
#         my $parent = getParent($dbt,$taxon_no);
#         $parent_no = $parent->{'taxon_no'};
#     }

#     my $html;
#     my @cladograms;
#     $output .= qq|<div class="displayPanel" align="left" style="width: 52em; margin-top: 0em; padding-top: 0em;">
#     <span class="displayPanelHeader" class="large">Classification of relatives</span>
# |;
#     if ( $parent_no )	{

#     # print a classification of the grandparent and its children down
#     #  three (or two) taxonomic levels (one below the focal taxon's)
#     # JA 23-24.11.08
# 	$output .= "<div class=\"displayPanelContent\">\n<div align=\"center\" class=\"medium\" style=\"padding-bottom: 1em;\"><i>\n\n";
#         $q->param('parent_no' => $parent_no);
#         $q->param('boxes_only' => 'YES');
#         my $subtaxa = PBDB::PrintHierarchy::classify($dbt,$hbo,$s,$q);
# 	if ( $subtaxa == 0 )	{
# 	}
# 	$output .= "</div></div>\n\n";

#         my $sql = "SELECT t2.taxon_no FROM $TAXA_TREE_CACHE t1, $TAXA_TREE_CACHE t2 WHERE t1.taxon_no IN ($taxon_no) AND t2.synonym_no=t1.synonym_no";
#         my @results = @{$dbt->getData($sql)};
#         my $parent_list = join(',',map {$_->{'taxon_no'}} @results);

#         my $sql = "(SELECT DISTINCT cladogram_no FROM cladograms c WHERE c.taxon_no IN ($parent_list))".
#               " UNION ".
#               "(SELECT DISTINCT cladogram_no FROM cladogram_nodes cn WHERE cn.taxon_no IN ($parent_list))";
#     	@cladograms = @{$dbt->getData($sql)};

#     } else	{
#         $output .= "<div class=\"displayPanelContent\">\n<div align=\"center\" class=\"medium\"><i>No data on relationships are available</i></div></div>";
#     }

#     $output .= "</div>\n\n";

#     $output .= qq|<div class="displayPanel" align="left" style="width: 52em; margin-top: 2em; padding-bottom: 1em;">
#     <span class="displayPanelHeader" class="large">Cladograms</span>
#         <div class="displayPanelContent">
# |;
#     if (@cladograms) {
#         $output .= "<div align=\"center\" style=\"margin-top: 1em;\">";
#         foreach my $row (@cladograms) {
#             my $cladogram_no = $row->{cladogram_no};
#             my ($pngname, $caption, $taxon_name) = Cladogram::drawCladogram($dbt,$cladogram_no);
#             if ($pngname) {
#                 $output .= qq|<img src="/public/cladograms/$pngname"><br>$caption<br><br>|;
#             }
#         }
#         $output .= "</div>";
#     } else {
#           $output .= "<div align=\"center\"><i>No cladograms are available</i></div>\n\n";
#     }
#     $output .= "</div>\n</div>\n\n";
#     return $output;
# } 


# age_range_format changes appearance html formatting of age/range information, used by the strata module
sub doCollections{
    my ($dbt,$s,$colls,$display_name,$taxon_no,$in_list,$age_range_format,$is_real_user,$type_locality) = @_;
    my $dbh = $dbt->dbh;
    my $output = '';
    
    if (!@$colls) {
        return qq|<div align="center">
<div class="displayPanel" align="left" style="width: 36em; margin-top: 0em; padding-bottom: 1em;">
<span class="displayPanelHeader" class="large">Collections</span>
<div class="displayPanelContent">
  <div align="center"><i>No collection or age range data are available</i></div>
</div>
</div>
</div>
|;
    }
    
    my @intervals = intervalData($dbt,$colls);
    my %interval_hash;
    $interval_hash{$_->{'interval_no'}} = $_ foreach @intervals;
    my ($lb,$ub,$max_no,$minfirst,$min_no) = getAgeRange($dbt,$colls);

    my $range = "";
    # simplified this because the users will understand the basic range,
    #  and it clutters the form JA 28.8.06
    my $max = ($max_no) ? $interval_hash{$max_no}->{interval_name} : "";
    my $min = ($min_no) ? $interval_hash{$min_no}->{interval_name} : ""; 
    if ($max ne $min && $min) {
        $range .= " base of the <a href=\"$INTERVAL_URL?a=displayInterval&interval_no=$max_no\">$max</a> to the top of the <a href=\"$INTERVAL_URL?a=displayInterval&interval_no=$min_no\">$min</a>";
    } else {
        $range .= " <a href=\"$INTERVAL_URL?a=displayInterval&interval_no=$max_no\">$max</a>";
    }
    $range .= " <i>or</i> $lb to $ub Ma";

    # need to know whether ANY of the included taxa are extant JA 15.12.06
    my $mincrownfirst;
    my %iscrown;
    my $extant;
    if ( $in_list && @$in_list )	{
        my $taxon_row = ${$dbt->getData("SELECT lft,synonym_no FROM $TAXA_TREE_CACHE WHERE taxon_no=$taxon_no")}[0];
        my $sql = "SELECT a.taxon_no taxon_no,extant,lft,rgt FROM authorities a,$TAXA_TREE_CACHE t WHERE synonym_no != $taxon_row->{synonym_no} AND lft != $taxon_row->{lft} AND a.taxon_no in (" . join (',',@$in_list) . ") AND a.taxon_no=t.taxon_no";
        my @children = @{$dbt->getData($sql)};
        my %maxlft;
        my %minrgt;
        for my $ch ( @children )	{
            if ( $ch->{'extant'} =~ /y/i )	{
                # for my $i ( $ch->{'lft'}..$ch->{'rgt'} )	{
                #     if ( $ch->{'lft'} > $maxlft{$i} )	{
                #         $maxlft{$i} = $ch->{'lft'};
                #     }
                #     if ( $ch->{'rgt'} < $minrgt{$i} || ! $minrgt{$i} )	{
                #         $minrgt{$i} = $ch->{'rgt'};
                #     }
                # }
		$extant = 1;
            }
        }
        # my $extant_list;
        # for my $ch ( @children )	{
        #     for my $i ( $ch->{'lft'}..$ch->{'rgt'} )	{
        #         if ( $ch->{'lft'} <= $maxlft{$i} && $ch->{'rgt'} >= $minrgt{$i} )	{
        #             $extant_list .= "$ch->{'taxon_no'},";
        #             # taxon actually is extant regardless of how it was
        #             #  marked, so make sure it is now marked correctly
        #             $ch->{'extant'} = "yes";
        #             last;
        #         }
        #     }
        # }
        # $extant_list =~ s/,$//;

        # if ( $extant_list =~ /[0-9]/ )	{

        #     $extant = 1;
	
	# if ( $extant ) {

        #     # extinct taxa also can be in the crown group, so figure out
        #     #  which taxa are subtaxa of extant groups
        #     my %has_extant_parent;
        #     for my $ch ( @children )	{
        #         if ( $ch->{'extant'} =~ /y/i )	{
        #             for my $i ( $ch->{'lft'}..$ch->{'rgt'} )	{
        #                 $has_extant_parent{$i}++;
        #             }
        #         }
        #     }
        #     my $crown_list;
        #     for my $ch ( @children )	{
        #         if ( $ch->{'extant'} =~ /y/i || $has_extant_parent{$ch->{'lft'}} && $has_extant_parent{$ch->{'rgt'}} )	{
        #             $crown_list .= "$ch->{'taxon_no'},";
        #         }
        #     }
        #     $crown_list =~ s/,$//;

        #     # get collections including the living immediate children
        #     # another annoying table hit!

        #     # Pull the colls from the DB;
        #     my %options = ();
        #     $options{'permission_type'} = 'read';
        #     $options{'calling_script'} = "TaxonInfo";
        #     $options{'taxon_list'} = $crown_list;
        #     my $fields = ["country", "state", "max_interval_no", "min_interval_no"];

        #     my ($dataRows,$ofRows) = PBDB::CollectionEntry::getCollections($dbt,$s,\%options,$fields);
        #     my ($lb,$ub,$max,$minfirst,$min) = getAgeRange($dbt,$dataRows);
        #     for my $coll ( @$dataRows )	{
        #         $iscrown{$coll->{'collection_no'}}++;
        #     }
        #     $mincrownfirst = $minfirst;
        # }
    }

    if ( $minfirst && $extant && $age_range_format ne 'for_strata_module' )	{
        $range = "<div class=\"small\" style=\"width: 40em; margin-left: 2em; margin-right: auto; text-align: left; white-space: nowrap;\">Maximum range based only on fossils: " . $range . "<br>\n";
        $minfirst =~ s/([0-9])0+$/$1/;
        $range .= "Minimum age of oldest fossil (stem group age): $minfirst Ma<br>\n";
        $mincrownfirst =~ s/([0-9])0+$/$1/;
        # $range .= "Minimum age of oldest fossil in any extant subgroup (crown group age): $mincrownfirst Ma<br>";
        # $range .= "<span class=\"verysmall\" style=\"padding-left: 2em;\"><i>Collections with crown group taxa are in <b>bold</b>.</i></span></div><br>\n";
	$range .= "</div><br>\n";
    } else	{
        $range = ":".$range;
    }

    $output .= qq|<div class="displayPanel" style="margin-top: 0em;">
<div class="displayPanelContent">
|;

    if ($age_range_format eq 'for_strata_module') {
        $output .= qq|Age range$range<br>
</div>
</div>
|;
    } else {
        $output .= "<div class=\"small\" style=\"margin-left: 2em; width: 90%; border-bottom: 1px solid lightgray;\"><p>Age range$range</p></div>\n";
    }

    
	# figure out which intervals are too vague to use to set limits on
	#  the joint upper and lower boundaries
	# "vague" means there's some other interval falling entirely within
	#  this one JA 26.1.05
    # Don't do it this way, not reliable
    # sort the collections by taxon name so the names can be printed just once
    #  per set of collections sharing the same taxon
    @{$colls} = sort { $a->{genera} cmp $b->{genera} } @{$colls};

	# Process the data:  group all the collection numbers with the same
	# time-place string together as a hash.
	my %time_place_coll = ();
    my (%time_interval,%lower_res,%upper_res,%max_interval_no);
    my %lastgenus = ();
    my %intervals = ();
	foreach my $row (@$colls) {
        my $max = $row->{'max_interval_no'};
        my $min = $row->{'min_interval_no'};
        if (!$min) {
            $min = $max;
        }
        my $res = "<span class=\"small\"><a href=\"$INTERVAL_URL?a=displayInterval&interval_no=$row->{max_interval_no}\">$interval_hash{$max}->{interval_name}</a>";
        if ( $max != $min ) {
            $res .= " - " . "<a href=\"$INTERVAL_URL?a=displayInterval&interval_no=$row->{min_interval_no}\">$interval_hash{$min}->{interval_name}</a>";
        }
        if ( $row->{"seq_strat"} =~ /glacial/ )	{
            $res .= " <span class=\"verysmall\">($row->{'seq_strat'})</span>";
        }
        $res .= "</span></td><td align=\"center\" valign=\"top\"><span class=\"small\"><nobr>";
        my $maxmin = $interval_hash{$max}->{base_age} . " - ";
        $maxmin =~ s/0+ / /;
        $maxmin =~ s/\. /.0 /;
        if ( $max == $min )	{
            $maxmin .= $interval_hash{$max}->{top_age};
        } else	{
            $maxmin .= $interval_hash{$min}->{top_age};
        }
        $maxmin =~ s/([0-9])(0+$)/$1/;
        $maxmin =~ s/\.$/.0/;
        $res .= $maxmin . "</nobr></span></td><td align=\"center\" valign=\"top\"><span class=\"small\">";

        $row->{"country"} =~ s/United States/USA/;
        $row->{"country"} =~ s/ /&nbsp;/;
        $res .= $row->{"country"};
        if($row->{"state"}){
            $row->{"state"} =~ s/ /&nbsp;/;
            $res .= " (" . $row->{"state"} . ")";
        }
        $res .= "</span>\n";

            my @letts = split //,$display_name;
            $row->{'genera'} =~ s/$display_name /$letts[0]\. /g;
            $row->{'genera'} =~ s/[A-Z]\. indet/$display_name indet/g;
	    if (exists $time_place_coll{$res})	{
                if ( $lastgenus{$res} ne $row->{'genera'} )	{
                    ${$time_place_coll{$res}}[$#{$time_place_coll{$res}}] .= ") ";
                    push(@{$time_place_coll{$res}}, $row->{'genera'} . " (" . $row->{'collection_no'} . "</a>");
                } else	{
                    push(@{$time_place_coll{$res}}, " " . $row->{'collection_no'} . "</a>");
                }
                $lastgenus{$res} = $row->{'genera'};
	    }
	    else	{
                $time_place_coll{$res}[0] = $row->{'genera'} . " (" . $row->{'collection_no'} . "</a>";
                $lastgenus{$res} = $row->{'genera'};

            # create a hash array where the keys are the time-place strings
            #  and each value is a number recording the min and max
            #  boundary estimates for the temporal bins JA 25.6.04
            # this is kind of tricky because we want bigger bins to come
            #  before the bins they include, so the second part of the
            #  number recording the upper boundary has to be reversed
            my $upper = $interval_hash{$max}->{top_age};
            $max_interval_no{$res} = $max;
            if ( $max != $min ) {
                $upper = $interval_hash{$min}->{top_age};
            }
            #if ( ! $toovague{$max." ".$min} && ! $seeninterval{$max." ".$min})	
            # WARNING: we're assuming upper boundary ages will never be
            #  greater than 999 million years
            my $lower = int($interval_hash{$max}->{base_age} * 1000);
            $upper = $upper * 1000;
            $upper = int(999000 - $upper);
            if ( $lower < 1000 )	{
                $lower = "000" . $lower;
            }
            elsif ( $lower < 10000 )	{
                $lower = "00" . $lower;
            }
            elsif ( $lower < 100000 )	{
                $lower = "0" . $lower;
            }
            my @glacials = ( "interglacial","glacial","early glacial","high glacial","late glacial" );
            for my $gl ( 0..$#glacials )	{
                if ( $row->{"seq_strat"} eq $glacials[$gl] )	{
                    $upper -= ( 1 + $gl );
                    last;
                }
            }
            $time_interval{$res} = $interval_hash{$max}->{interval_name};
            $time_interval{$res} .=  ( $max != $min ) ? " - ".$interval_hash{$min}->{interval_name} : "";
            $lower_res{$res} = $interval_hash{$max}->{base_age};
            $upper_res{$res} = $interval_hash{$min}->{top_age};
            $intervals{$max} = 1 if ($max);
            $intervals{$min} = 1 if ($min);
	    }
	}

	my @sorted = sort { $lower_res{$b} <=> $lower_res{$a} || $upper_res{$b} <=> $upper_res{$a} || $time_interval{$a} cmp $time_interval{$b} } keys %lower_res;

	# legacy: originally the sorting was just on the key
#	my @sorted = sort (keys %time_place_coll);

	if(scalar @sorted > 0){
	if ($age_range_format ne 'for_strata_module') {
		$output .= qq|<div class="small" style="margin-left: 2em; margin-bottom: -1em;"><p>Collections|;
	} else	{
		$output .= qq|
</div>
<div align="left" class="displayPanel">
<span class="displayPanelHeader">Collections</span>
<div class="displayPanelContent">
|;
	}
		my $collTxt = (scalar(@$colls)== 0) ? ": none found"
			: (scalar(@$colls) == 1) ? ": one only"
			: " (".scalar(@$colls)." total)";
		if ($age_range_format ne 'for_strata_module') {
			$output .= "$collTxt</p></div>\n";
		}
		if ( $#sorted <= 100 )	{
			$output .= "<br>\n";
		}

		$output .= "<table class=\"small\" style=\"margin-left: 2em; margin-right: 2em; margin-bottom: 2em;\">\n";
		if ( $#sorted > 100 )	{
			$output .= qq|<tr>
<td colspan="3"><p class=\"large\" style="padding-left: 1em;">Oldest occurrences</p>
</tr>|;
		}
		$output .= qq|<tr>
<th align="center">Time interval</th>
<th align="center">Ma</th>
<th align="center">Country or state</th>
<th align="left">Original ID and collection number</th></tr>
|;

	# overload rule: if there are more than 100 rows, print only the
	#  first and last 10 for an extinct taxon, and the oldest 20 for
	#   an extant taxon JA 6.5.07
		if ( $#sorted > 100 )	{
			my @temp = @sorted;
			if ( $extant == 0 )	{
				@sorted = splice @temp , 0 , 10;
				push @sorted , ( splice @temp , $#temp - 9 , 10 );
			} else	{
				@sorted = splice @temp , 0 , 20;
			}
		}
		my $row_color = 0;
		foreach my $key (@sorted){
			if($row_color % 2 == 0){
				$output .= "<tr class='darkList'>";
			} 
			else{
				$output .= "<tr>";
			}
			$output .= "<td align=\"center\" valign=\"top\">$key</td>".
                       " <td align=\"left\"><span class=\"small\">";
			foreach my $collection_no (@{$time_place_coll{$key}}){
				my $formatted_no = $collection_no;
                                my $no = $collection_no;
                                $no =~ s/[^0-9]//g;
				if ( $type_locality == $no )	{
					$formatted_no =~ s/([0-9])/type locality: $1/;
				}
				if ( $iscrown{$no} > 0 )	{
				    my $link = makeATag("basicCollectionSearch", "collection_no=$no&amp;is_real_user=$is_real_user");
				    $formatted_no =~ s/([0-9])/$link<b>$1<\/b>/;
				} else	{
				    my $link = makeATag("basicCollectionSearch", "collection_no=$no&amp;is_real_user=$is_real_user");
				    $formatted_no =~ s/([0-9])/${link}$1/;
				}
				$output .= $formatted_no;
			}
			$output .= ")";
			$output =~ s/([>\]]) \)/$1\)/;
			$output .= "</span></td></tr>\n";
			$row_color++;
			if ( $row_color == 10 && $output =~ /Oldest/ && $extant == 0 )	{
				$output .= qq|
<tr>
<td colspan="3"><p class="large" style="padding-top: 0.5em;">Youngest occurrences</p></td>
</tr>
<tr>
<th align="center">Time interval</th>
<th align="center">Ma</th>
<th align="center">Country or state</th>
<th align="left">PBDB collection number</th></tr>
|;
			}
		}
		$output .= "</table>";
	} 

	if ($age_range_format eq 'for_strata_module') {
		$output .= qq|
</div>
</div>
|;
	}

	$output .= qq|
</div>
</div>
|;

    return $output;
}

# JA 23.9.11
sub intervalData	{
	my ($dbt,$colls) = @_;
	my %is_no;
	$is_no{$_->{'max_interval_no'}}++ foreach @$colls;
	$is_no{$_->{'min_interval_no'}}++ foreach @$colls;
	delete $is_no{0};
	my $sql = "SELECT TRIM(CONCAT(i.eml_interval,' ',i.interval_name)) AS interval_name,i.interval_no,base_age,top_age FROM intervals i,interval_lookup l WHERE i.interval_no=l.interval_no AND i.interval_no IN (".join(',',keys %is_no).")";
	return @{$dbt->getData($sql)};
}

# JA 23.9.11
sub getAgeRange	{
	my ($dbt,$colls) = @_;
	my @coll_nos = map { $_ ->{'collection_no'} } @$colls;
	if ( ! @coll_nos )	{
		return;
	}

	# get the youngest base age of any collection including this taxon
	# ultimately, the range's top must be this young or younger
	my $sql = "SELECT base_age AS maxtop FROM collections,interval_lookup WHERE max_interval_no=interval_no AND collection_no IN (".join(',',@coll_nos).") ORDER BY base_age ASC";
	my $maxTop = ${$dbt->getData($sql)}[0]->{'maxtop'};

	# likewise the oldest top age
	# the range's base must be this old or older
	# the top is the top of the max_interval for collections having
	#  no separate max and min ages, but is the top of the min_interval
	#  for collections having different max and min ages
	my $sql = "SELECT top_age AS minbase FROM ((SELECT top_age FROM collections,interval_lookup WHERE min_interval_no=0 AND max_interval_no=interval_no AND collection_no IN (".join(',',@coll_nos).")) UNION (SELECT top_age FROM collections,interval_lookup WHERE min_interval_no>0 AND min_interval_no=interval_no AND collection_no IN (".join(',',@coll_nos)."))) AS ages ORDER BY top_age DESC";
	my $minBase = ${$dbt->getData($sql)}[0]->{'minbase'};

	# now get the range top
	# note that the range top is the top of some collection's min_interval
	$sql = "SELECT MAX(top_age) top FROM ((SELECT top_age FROM collections,interval_lookup WHERE min_interval_no=0 AND max_interval_no=interval_no AND collection_no IN (".join(',',@coll_nos).") AND top_age<$maxTop) UNION (SELECT top_age FROM collections,interval_lookup WHERE min_interval_no>0 AND min_interval_no=interval_no AND collection_no IN (".join(',',@coll_nos).") AND top_age<$maxTop)) AS tops";
	my $top = ${$dbt->getData($sql)}[0]->{'top'} || $maxTop;

	# and the range base
	$sql = "SELECT MIN(base_age) base FROM collections,interval_lookup WHERE max_interval_no=interval_no AND collection_no IN (".join(',',@coll_nos).") AND base_age>$minBase";
	my $base = ${$dbt->getData($sql)}[0]->{'base'} || $minBase;

	my (%is_max,%is_min);
	for my $c ( @$colls )	{
		$is_max{$c->{'max_interval_no'}}++;
		if ( $c->{'min_interval_no'} > 0 )	{
			$is_min{$c->{'min_interval_no'}}++;
		} else	{
			$is_min{$c->{'max_interval_no'}}++;
		}
	}

	# get the ID of the shortest interval whose base is equal to the
	#  range base and explicitly includes an occurrence
	$sql = "SELECT interval_no FROM interval_lookup WHERE interval_no IN (".join(',',keys %is_max).") AND base_age=$base ORDER BY top_age DESC LIMIT 1";
	my $oldest_interval_no = ${$dbt->getData($sql)}[0]->{'interval_no'};

	# ditto for the shortest interval defining the top
	# only the ID number is needed
	$sql = "SELECT interval_no FROM interval_lookup WHERE interval_no IN (".join(',',keys %is_min).") AND top_age=$top ORDER BY base_age ASC LIMIT 1";
	my $youngest_interval_no = ${$dbt->getData($sql)}[0]->{'interval_no'};

	return($base,$top,$oldest_interval_no,$minBase,$youngest_interval_no);
}


## displayTaxonClassification
#
# SEND IN GENUS OR HIGHER TO GENUS_NAME, ONLY SET SPECIES IF THERE'S A SPECIES.
##
sub displayTaxonClassification {
    
    my ($dbt,$orig_no,$taxon_name,$is_real_user) = @_;
    my $dbh = $dbt->dbh;
    
    my $output;
    
    # These variables will reflect the name as currently used
    my ($taxon_no,$taxon_rank) = (0,"");
    
    # the classification variables refer to the taxa derived from the taxon_no we're using for classification
    # purposes.  If we found an exact match in the authorities table this classification_no wil
    # be the same as the original combination taxon_no for an authority. If we passed in a Genus+species
    # type combo but only the genus is in the authorities table, the classification_no will refer
    # to the genus
    
    my ($classification_no, $classification_name, $classification_rank);
    my ($genus, $subgenus, $species, $subspecies);
    
    if ($orig_no)
    {
        my $taxon = getMostRecentSpelling($dbt,$orig_no);
	
        $taxon_no = $taxon->{'taxon_no'};    
        $taxon_name = $taxon->{'taxon_name'};    
        $taxon_rank = $taxon->{'taxon_rank'};    
	
        $classification_no = $taxon_no;
        $classification_name = $taxon_name;
        $classification_rank = $taxon_rank;
	
	($genus,$subgenus,$species,$subspecies) = splitTaxon($taxon_name);	
    }
    
    else
    {
        # Theres are some case where we might want to do upward classification when theres no taxon_no:
        #  The Genus+species isn't in authorities, but the genus is
        #  The exact taxa isn't in the authorities, but something close is (i.e. the Genus+species matches 
        #  The Subgenus+species of some taxon
        
	($genus,$subgenus,$species,$subspecies) = splitTaxon($taxon_name);
	
        $classification_no = getBestClassification($dbt,'',$genus,'',$subgenus,'',$species);
	
        if ($classification_no)
	{
            my $taxon = getTaxa($dbt,{'taxon_no'=>$classification_no});
            $classification_name = $taxon->{'taxon_name'};
            $classification_rank = $taxon->{'taxon_rank'};
        }
    }
    
    my ($c_genus,$c_subgenus,$c_species,$c_subspecies) = splitTaxon($classification_name);
    
    # Do the classification
    my @table_rows = ();
    my $cofHTML;
    
    # Now find the rank,name, and publication of all its parents
    
    if ( $classification_no )
    {
        my $orig_classification_no = getOriginalCombination($dbt,$classification_no);
	
        # my $parent_hash = getParents($dbt,[$orig_classification_no],'array_full');
        # my @parent_array = @{$parent_hash->{$orig_classification_no}};
	
	my @parent_array = getParents($dbt, $orig_classification_no);
	
        my $cof = getClassOrderFamily($dbt, undef, \@parent_array);
	
        if ( $cof->{'class'} || $cof->{'order'} || $cof->{'family'} )
	{
	    my @links;
	    
	    if ( $cof->{class} )
	    {
		push @links, makeAnchor('checkTaxonInfo', "taxon_no=$cof->{class_no}&is_real_user=1", $cof->{class});
	    }
	    
	    if ( $cof->{order} )
	    {
		push @links, makeAnchor('checkTaxonInfo', "taxon_no=$cof->{order_no}&is_real_user=1", $cof->{order});
	    }

	    if ( $cof->{family} )
	    {
		push @links, makeAnchor('checkTaxonInfo', "taxon_no=$cof->{family_no}&is_real_user=1", $cof->{family});
	    }

	    $cofHTML = join(' - ', @links);
        }

        if (@parent_array) {
            my ($subspecies_no,$species_no,$subgenus_no,$genus_no) = (0,0,0,0);
            # Set for focal taxon
            $subspecies_no = $taxon_no if ($taxon_rank eq 'subspecies');
            $species_no = $taxon_no if ($taxon_rank eq 'species');
            $subgenus_no = $taxon_no if ($taxon_rank eq 'subgenus');
            $genus_no = $taxon_no if ($taxon_rank eq 'genus');
            foreach my $row (@parent_array) {
                # Set for all possible higher taxa
                # Handle species/genus separately below.  The reason for this is the "loose" classification that
                # the PBDB does.  getBestClassification will find a proximate match if we can't
                # find an exact match in the database.  Because of this, some of the lower level names
                # (genus,subgenus,species,subspecies) may not match up exactly from what the user entered
                $subspecies_no = $row->{'taxon_no'} if ($row->{'taxon_rank'} eq 'subspecies');
                $species_no = $row->{'taxon_no'} if ($row->{'taxon_rank'} eq 'species');
                $subgenus_no = $row->{'taxon_no'} if ($row->{'taxon_rank'} eq 'subgenus');
                $genus_no = $row->{'taxon_no'} if ($row->{'taxon_rank'} eq 'genus');
             
                if ($row->{'taxon_rank'} !~ /species|genus/) {
                    push (@table_rows,[$row->{'taxon_rank'},$row->{'taxon_name'},$row->{'taxon_name'},$row->{'taxon_no'}]);
                }
                last if ($row->{'taxon_rank'} eq 'kingdom');
            }
            if ($genus_no) {
                unshift @table_rows, ['genus',$genus,$genus,$genus_no];
            } elsif ($classification_no) {
                unshift @table_rows, [$classification_rank,$classification_name,$classification_name,$classification_no];
            }
            if ($subgenus) {
                unshift @table_rows, ['subgenus',"$genus ($subgenus)",$subgenus,$subgenus_no];
            }
            if ($species) {
                my $species_name = "$genus $species";
                if ($subgenus) {
                    $species_name = "$genus ($subgenus) $species";
                } 
                unshift @table_rows, ['species',"$species_name",$species,$species_no];
            }
            if ($subspecies) {
                unshift @table_rows, ['subspecies',"$taxon_name",$subspecies,$subspecies_no];
            }

            #
            # Print out the table in the reverse order that we initially made it
            #
            # the html actually returned by the function
            $output =qq|
<div class="small displayPanel">
<div class="displayPanelContent">
<table><tr><td valign="top">
<table><tr valign="top"><th>Rank</th><th>Name</th><th>Author</th></tr>
|;
            my $class = '';
            for(my $i = scalar(@table_rows)-1;$i>=0;$i--) {
                if ( $i == int((scalar(@table_rows) - 2) / 2) )	{
                    $output .= "\n</td></tr></table>\n\n";
                    $output .= "\n</td><td valign=\"top\" style=\"width: 2em;\"></td><td valign=\"top\">\n\n";
                    $output .= "<table><tr valign=top><th>Rank</th><th>Name</th><th>Author</th></tr>";
                }
                $class = $class eq '' ? 'class="darkList"' : '';
                $output .= "<tr $class>";
                my($taxon_rank,$taxon_name,$show_name,$taxon_no) = @{$table_rows[$i]};
                if ($taxon_rank eq 'unranked clade') {
                    $taxon_rank = "&mdash;";
                }
                my $authority;
                if ($taxon_no) {
                    $authority = getTaxa($dbt,{'taxon_no'=>$taxon_no},['author1last','author2last','otherauthors','pubyr','reference_no','ref_is_authority']);
                }
                my $pub_info = formatShortRef($authority);
                if ($authority->{'ref_is_authority'} =~ /yes/i) {
                    $pub_info = makeAnchor("displayReference?reference_no=$authority->{reference_no}&amp;is_real_user=$is_real_user", $pub_info);
                }
                my $orig_no = getOriginalCombination($dbt,$taxon_no);
                if ($orig_no != $taxon_no) {
                    $pub_info = "(".$pub_info.")" if $pub_info !~ /^\s*$/;
                } 
                my $link;
                if ($taxon_no) {
                    $link = makeAnchor("checkTaxonInfo", "taxon_no=$taxon_no&amp;is_real_user=$is_real_user", $show_name);
                } else {
                    $link = makeAnchor("checkTaxonInfo", "taxon_name=$taxon_name&amp;is_real_user=$is_real_user", $show_name);
                }
                $output .= qq|<td align="center">$taxon_rank</td>|.
                           qq|<td align="center">$link</td>|.
                           qq|<td align="center" style="white-space: nowrap">$pub_info</td>|; 
                $output .= '</tr>';
            }
            $output .= "</table>";
            $output .= "</td></tr></table>\n\n";
            $output .= "<p class=\"small\" style=\"margin-left: 2em; margin-right: 2em; text-align: left;\">If no rank is listed, the taxon is considered an unranked clade in modern classifications. Ranks may be repeated or presented in the wrong order because authors working on different parts of the classification may disagree about how to rank taxa.</p>\n\n";
           
        } else {
            $output =qq|
<div class="small displayPanel" style="width: 42em;">
<div class="displayPanelContent">
<p><i>No classification data are available</i></p>
|;
        }
    } else {
        $output =qq|
<div class="small displayPanel" style="width: 42em;">
<div class="displayPanelContent">
<p><i>No classification data are available</i></p>
|;
    }

    $output .= "</div>\n</div>\n\n";

    return ($cofHTML,$output);
}

# Separated out from classification section PS 09/22/2005
sub displayRelatedTaxa {
    
    my ($dbt, $orig_no, $spelling_no, $taxon_name, $is_real_user) = @_;
    
    my $dbh = $dbt->dbh;
    
    my ($genus,$subgenus,$species,$subspecies) = splitTaxon($taxon_name);
    
    my $output = "";

    #
    # Begin getting sister/child taxa
    # PS 01/20/2004 - rewrite: Use getChildren function
    # First get the children
    #
    
    my $focal_taxon_no = $orig_no;
    my ($focal_taxon_rank,$parent_taxon_no);
    
    $focal_taxon_rank = guessTaxonRank($taxon_name);
    
    if (!$focal_taxon_rank && $orig_no)
    {
        my $taxon = getTaxa($dbt,{'taxon_no'=>$orig_no});
        $focal_taxon_rank = $taxon->{'taxon_rank'};
    } 
    
    if ($orig_no) {
        my $parent = getParent($dbt,$orig_no);
        if ($parent) {
            $parent_taxon_no = $parent->{'taxon_no'};
        }
    } else {
        my @bits = split(/ /,$taxon_name);
        pop @bits;
        my $taxon_parent = join(" ",@bits);
        my @parents = ();
        my $taxon_parent_rank = "";
        if ($taxon_parent) {
            $taxon_parent_rank = guessTaxonRank($taxon_parent);
            #$taxon_parent_rank = 'genus' if (!$taxon_parent_rank);
            @parents = getTaxa($dbt,{'taxon_name'=>$taxon_parent});
        }
       
        if ($taxon_parent && scalar(@parents) == 1) {
            $parent_taxon_no=getOriginalCombination($dbt,$parents[0]->{'taxon_no'});
        }
    }

    my @child_taxa_links;
    
    # This section generates links for children if we have a taxon_no (in authorities
    # table) 
    
    if ($focal_taxon_no)
    {
	my @children = getChildren($dbt,$focal_taxon_no,'immediate_children');
	
	# my @children = getImmediateChildren($dbt, $focal_taxon_no);
	
	#        my @syns = @{$tree->{'synonyms'}};
	#        foreach my $syn (@syns) {
	#            if ($syn->{'children'}) {
	#                push @children, @{$syn->{'children'}};
	#            }
	#        }
	
	@children = sort {$a->{'taxon_name'} cmp $b->{'taxon_name'}} @children;
	if (@children) {
	    my $sql = "SELECT type_taxon_no FROM authorities WHERE taxon_no=$focal_taxon_no";
	    my $type_taxon_no = ${$dbt->getData($sql)}[0]->{'type_taxon_no'};
	    foreach my $record (@children) {
		my (@syn_links, @synonyms);
		@synonyms = $record->{synonyms}->@* if ref $record->{synonyms} eq 'ARRAY';
		push @syn_links, $_->{'taxon_name'} for @synonyms;
		my $link = makeATag("checkTaxonInfo", "taxon_no=$record->{taxon_no}&amp;is_real_user=$is_real_user") . $record->{taxon_name};
		$link .= " (syn. ".join(", ",@syn_links).")" if @syn_links;
		$link .= "</a>";
		if ($type_taxon_no && $type_taxon_no == $record->{'taxon_no'}) {
		    $link .= " <small>(type $record->{taxon_rank})</small>";
		}
		push @child_taxa_links, $link;
	    }
	}
    }

    # Get sister taxa as well
    # PS 01/20/2004
    my @sister_taxa_links;
    # This section generates links for sister if we have a taxon_no (in authorities table)
    if ($parent_taxon_no)
    {
	my @sisters = getChildren($dbt,$parent_taxon_no,'immediate_children');
	
	# my @sisters = getImmediateChildren($dbt, $parent_taxon_no);
	
        @sisters = sort {$a->{'taxon_name'} cmp $b->{'taxon_name'}} @sisters;
	
        if (@sisters) 
	{
            foreach my $record (@sisters)
	    {
                next if ($record->{'taxon_no'} == $spelling_no);
                if ($focal_taxon_rank ne $record->{'taxon_rank'})
		{
#                    PBDB::PBDBUtil::debug(1,"rank mismatch $focal_taxon_rank -- $record->{taxon_rank} for sister $record->{taxon_name}");
                } 
		
		else
		{
                    my (@syn_links, @synonyms);
		    @synonyms = $record->{synonyms}->@* if ref $record->{synonyms} eq 'ARRAY';
                    push @syn_links, $_->{'taxon_name'} for @synonyms;
                    my $link = makeAnchor("checkTaxonInfo", "taxon_no=$record->{taxon_no}&amp;is_real_user=$is_real_user") . $record->{taxon_name};
                    $link .= " (syn. ".join(", ",@syn_links).")" if @syn_links;
                    $link .= "</a>";
                    push @sister_taxa_links, $link;
                }
            }
        }
    }
    # This generates links if all we have is occurrences records
    my (@possible_sister_taxa_links,@possible_child_taxa_links);
    if ($taxon_name) {
        my ($sql,$whereClause,@results);
        my ($genus,$subgenus,$species,$subspecies) = splitTaxon($taxon_name);
        my @names = ();
        if ($genus) {
            push @names, $dbh->quote($genus);
        }
        if ($subgenus) {
            push @names, $dbh->quote($subgenus);
        }
        if (@names) {
            my $genus_sql = "a.genus_name IN (".join(",",@names).")";
            my $subgenus_sql = " a.subgenus_name  IN (".join(",",@names).")";
            my ($occ_genus_no_sql,$reid_genus_no_sql) = ("","");
            #$occ_genus_no_sql = " OR a.taxon_no=$parents[0]->{taxon_no}" if (@parents);
            #$reid_genus_no_sql = " OR a.taxon_no=$parents[0]->{taxon_no}" if (@parents);
            # Note that the table aliased to "a" and "b" is switched up.  The table we want to dislay names for and do matches
            # against is "a" and the non-important table is "b"
            my $sql  = "(SELECT a.genus_name,a.subgenus_name,a.species_name,c.taxon_name FROM occurrences a LEFT JOIN reidentifications b ON a.occurrence_no=b.occurrence_no LEFT JOIN authorities c ON a.taxon_no=c.taxon_no WHERE b.reid_no IS NULL AND $genus_sql AND (a.species_reso IS NOT NULL AND a.species_reso NOT LIKE '%informal%'))";
            $sql .= " UNION ";
            $sql .= "(SELECT a.genus_name,a.subgenus_name,a.species_name,c.taxon_name FROM occurrences b, reidentifications a LEFT JOIN authorities c ON a.taxon_no=c.taxon_no WHERE a.occurrence_no=b.occurrence_no AND a.most_recent='YES' AND $genus_sql AND (a.species_reso IS NOT NULL AND a.species_reso NOT LIKE '%informal%'))";
            $sql .= " UNION ";
            $sql .= "(SELECT a.genus_name,a.subgenus_name,a.species_name,c.taxon_name FROM occurrences a LEFT JOIN reidentifications b ON a.occurrence_no=b.occurrence_no LEFT JOIN authorities c ON a.taxon_no=c.taxon_no WHERE b.reid_no IS NULL AND $subgenus_sql AND (a.species_reso IS NOT NULL AND a.species_reso NOT LIKE '%informal%'))";
            $sql .= " UNION ";
            $sql .= "(SELECT a.genus_name,a.subgenus_name,a.species_name,c.taxon_name FROM occurrences b, reidentifications a LEFT JOIN authorities c ON a.taxon_no=c.taxon_no WHERE a.occurrence_no=b.occurrence_no AND a.most_recent='YES' AND $subgenus_sql AND (a.species_reso IS NOT NULL AND a.species_reso NOT LIKE '%informal%'))";
            $sql .= " ORDER BY genus_name,subgenus_name,species_name";
            dbg("Get from occ table: $sql");
            @results = @{$dbt->getData($sql)};
            foreach my $row (@results) {
                next if ($row->{'species_name'} =~ /^sp(p)*\.|^indet\.|s\.\s*l\./);
                my ($g,$sg,$sp) = splitTaxon($row->{'taxon_name'});
                my $match_level = 0;
                if ($row->{'taxon_name'}) {
                    $match_level = computeMatchLevel($row->{'genus_name'},$row->{'subgenus_name'},$row->{'species_name'},$g,$sg,$sp);
                }
                if ($match_level < 20) { # For occs with only a genus level match, or worse
                    my $occ_name = $row->{'genus_name'};
                    if ($row->{'subgenus'}) {
                        $occ_name .= " ($row->{subgenus})";
                    }
                    $occ_name .= " ".$row->{'species_name'};
                    if ($species) {
                        if ($species ne $row->{'species_name'}) {
                            my $link = makeAnchor("checkTaxonInfo", "taxon_name=$occ_name&amp;is_real_user=$is_real_user", $occ_name);
                            push @possible_sister_taxa_links, $link;
                        }
                    } else {
                        my $link = makeAnchor("checkTaxonInfo", "taxon_name=$occ_name&amp;is_real_user=$is_real_user", $occ_name);
                        push @possible_child_taxa_links, $link;
                    }
                }
            }
        }
    }
   
    # Print em out
    my @letts = split //,$taxon_name;
    my $initial = $letts[0];
    if (@child_taxa_links) {
        my $rank = ($focal_taxon_rank eq 'species') ? 'Subspecies' :
                   ($focal_taxon_rank eq 'genus') ? 'Species' :
                                                    'Subtaxa';
$output .= qq|<div class="displayPanel" align="left" style="margin-bottom: 2em; padding-left: 1em; padding-bottom: 1em;">
  <span class="displayPanelHeader">$rank</span>
  <div class="displayPanelContent">
|;
        $_ =~ s/$taxon_name /$initial. /g foreach ( @child_taxa_links );
        $output .= join(", ",@child_taxa_links);
        $output .= qq|  </div>
</div>|;
    }

    if (@possible_child_taxa_links) {
$output .= qq|<div class="displayPanel" align="left" style="margin-bottom: 2em; padding-left: 1em; padding-bottom: 1em;">
  <span class="displayPanelHeader">Species lacking formal opinion data</span>
  <div class="displayPanelContent">
|;
        # the GROUP BY apparently fails if there are both occs and reIDs
        @possible_child_taxa_links = sort { $a cmp $b } @possible_child_taxa_links;
        $_ =~ s/>$taxon_name />$initial. /g foreach ( @possible_child_taxa_links );
        $_ =~ s/=$taxon_name /=$taxon_name\+/g foreach ( @possible_child_taxa_links );
        $output .= join(", ",@possible_child_taxa_links);
        $output .= qq|  </div>
</div>|;
    }

    if (@sister_taxa_links) {
        my $rank = ($focal_taxon_rank eq 'species') ? 'species' :
                   ($focal_taxon_rank eq 'genus') ? 'genera' :
                                                    'taxa';
$output .= qq|<div class="displayPanel" align="left" style="margin-bottom: 2em; padding-left: 1em; padding-bottom: 1em;">
  <span class="displayPanelHeader">Sister $rank</span>
  <div class="displayPanelContent">
|;
        $_ =~ s/$genus /$initial. /g foreach ( @sister_taxa_links );
        $output .= join(", ",@sister_taxa_links);
        $output .= qq|  </div>
</div>|;
    }
    
    if (@possible_sister_taxa_links) {
$output .= qq|<div class="displayPanel" align="left" style="margin-bottom: 2em; padding-left: 1em; padding-bottom: 1em;">
  <span class="displayPanelHeader">Sister species lacking formal opinion data</span>
  <div class="displayPanelContent">
|;
        $_ =~ s/>$genus />$initial. /g foreach ( @possible_sister_taxa_links );
        $output .= join(", ",@possible_sister_taxa_links);
        $output .= qq|  </div>
</div>|;
    }

    # if ($orig_no) {
    # 	$output .= "<p><b>" . makeAnchor("classify", "taxon_no=$orig_no", "View classification of included taxa") . "</b></p>\n";
	
    #     # $output .= '<p><b><a href=# onClick="javascript: document.doDownloadTaxonomy.submit()">Download authority and opinion data</a></b> - <b><a href=# onClick="javascript: document.doViewClassification.submit()">View classification of included taxa</a></b>';
    #     # $output .= "<form method=\"POST\" action=\"\" name=\"doDownloadTaxonomy\">";
    #     # $output .= '<input type="hidden" name="action" value="displayDownloadTaxonomyResults">';
    #     # $output .= '<input type="hidden" name="taxon_no" value="'.$orig_no.'">';
    #     # $output .= "</form>\n";
    #     # $output .= "<form method=\"POST\" action=\"\" name=\"doViewClassification\">";
    #     # $output .= '<input type="hidden" name="action" value="classify">';
    #     # $output .= '<input type="hidden" name="taxon_no" value="'.$orig_no.'">';
    #     # $output .= "</form>\n";
    # }
	return $output;
}

# updated by rjp, 1/22/2004
# gets paragraph displayed in places like the
# taxonomic history, for example, if you search for a particular taxon
# and then check the taxonomic history box at the left.

sub displaySynonymyParagraph {
    
    my ($dbt, $taxon_no, $orig_no, $is_real_user) = @_;
    
    return '' unless $orig_no;
    
    my %synmap1 = ('original spelling' => 'revalidated',
                   'recombination' => 'recombined as ',
		   'correction' => 'corrected as ',
		   'rank change' => 'reranked as ',
		   'reassigment' => 'reassigned as ',
		   'misspelling' => 'misspelled as ');
    
    my %synmap2 = ('belongs to' => 'revalidated ',
		   'replaced by' => 'replaced with ',
		   'nomen dubium' => 'considered a nomen dubium ',
		   'nomen nudum' => 'considered a nomen nudum ',
		   'nomen vanum' => 'considered a nomen vanum ',
		   'nomen oblitum' => 'considered a nomen oblitum ',
		   'homonym of' => ' considered a homonym of ',
		   'misspelling of' => 'misspelled as ',
		   'invalid subgroup of' => 'considered an invalid subgroup of ',
		   'subjective synonym of' => 'synonymized subjectively with ',
		   'objective synonym of' => 'synonymized objectively with ');
    my $text = "";
    
    my @results = getAllClassification($dbt, $orig_no, { no_synonyms => 1});
    
    my $best_opinion;
    
    if (@results)
    {
        # save the best opinion no
        $best_opinion = $results[0]->{opinion_no};
        # getAllClassification returns the opinions in reliability_index
        #  order, so now they need to be resorted based on pubyr
        @results = sort { $a->{pubyr} <=> $b->{pubyr} } @results;
    }
    
    # "Named by" part first:
    # Need to print out "[taxon_name] was named by [author] ([pubyr])".
    # - select taxon_name, author1last, pubyr, reference_no, comments from authorities
    
    my $taxon = getTaxa($dbt,{'taxon_no'=>$taxon_no},['taxon_no','taxon_name','taxon_rank','author1last','author2last','otherauthors','pubyr','reference_no','ref_is_authority','extant','preservation','form_taxon','type_taxon_no','type_specimen','type_body_part','part_details','type_locality','comments','discussion']);

	# Get ref info from refs if 'ref_is_authority' is set
	if ( ! $taxon->{'author1last'} )	{
		my $rank = $taxon->{taxon_rank};
		my $article = "a";
		if ( $rank =~ /^[aeiou]/ )	{
			$article = "an";
		}
		my $rankchanged;
		for my $row ( @results )	{
			if ( $row->{'spelling_reason'} =~ /rank/ )	{
			# rank was changed at some point
				$text .= makeAnchor("checkTaxonInfo", "taxon_no=$taxon->{taxon_no}&amp;is_real_user=$is_real_user", $taxon->{taxon_name}) .
				    " was named as $article $rank. ";
				$rankchanged++;
				last;
			}
		}
		# rank was never changed
		if ( ! $rankchanged )	{
			$text .= makeAnchor("checkTaxonInfo", "taxon_no=$taxon->{taxon_no}&amp;is_real_user=$is_real_user", $taxon->{taxon_name}) .
			    " is $article $rank. ";
		}
	} else	{
		$text .= "<i>" . makeAnchor("checkTaxonInfo", "taxon_no=$taxon->{taxon_no}&amp;is_real_user=$is_real_user", $taxon->{taxon_name}) . 
		    "</i> was named by ";
	        if ($taxon->{'ref_is_authority'}) {
			$text .= formatShortRef($taxon,'alt_pubyr'=>1,'show_comments'=>1,'link_id'=>1);
		} else {
			$text .= formatShortRef($taxon,'alt_pubyr'=>1,'show_comments'=>1);
		}
		$text .= ". ";
	}

    if ($taxon->{'extant'} =~ /y/i) {
        $text .= "It is extant. ";
    } elsif (! $taxon->{'preservation'} && $taxon->{'extant'} =~ /n/i) {
        $text .= "It is not extant. ";
    }

    if ($taxon->{'form_taxon'} =~ /y/i) {
            $text .= "It is considered to be a form taxon. ";
    }

    my @spellings = getAllSpellings($dbt,$taxon->{'taxon_no'});

    my ($typeInfo,$typeLocality) = printTypeInfo($dbt,join(',',@spellings),$taxon,$is_real_user,'checkTaxonInfo',1);
    $text .= $typeInfo;

    my $sql = "SELECT taxon_no,taxon_name,taxon_rank FROM authorities WHERE type_taxon_no IN (".join(",",@spellings).")";
    my @type_for = @{$dbt->getData($sql)};
    if (@type_for) {
        $text .= "It is the type $taxon->{'taxon_rank'} of ";
        foreach my $row (@type_for) {
            my $taxon_name = $row->{'taxon_name'};
            if ($row->{'taxon_rank'} =~ /genus|species/) {
                $taxon_name = "<i>".$taxon_name."</i>";
            }
            $text .= makeAnchor("checkTaxonInfo", "taxon_no=$row->{taxon_no}&amp;is_real_user=$is_real_user", $taxon_name) . ", ";
        }
        $text =~ s/, $/. /;
    }

   my %phyly = ();
    foreach my $row (@results) {
        if ($row->{'phylogenetic_status'}) {
            push @{$phyly{$row->{'phylogenetic_status'}}},$row;
        }
    }
    my @phyly_list = keys %phyly;
    if (@phyly_list) {
        my $para_text = " It was considered ";
        @phyly_list = sort {$phyly{$a}->[-1]->{'pubyr'} <=> $phyly{$b}->[-1]->{'pubyr'}} @phyly_list;
        foreach my $phylogenetic_status (@phyly_list) {
            $para_text .= " $phylogenetic_status by ";
            my $parent_block = $phyly{$phylogenetic_status};
            $para_text .= printReferenceList($parent_block,$best_opinion);
            $para_text .= ", ";
        }
        $para_text =~ s/, $/\./;
        my $last_comma = rindex($para_text,",");
        if ($last_comma >= 0) {
            substr($para_text,$last_comma,1," and ");
        }
        $text .= $para_text;
    }

    $text .= "<br><br>";


    # We want to group opinions together that have the same spelling/parent
    # We do this by creating a double array - $syns[$group_index][$child_index]
    # where all children having the same parent/spelling will have the same group index
    # the hashs %(syn|rc)_group_index keep track of what the $group_index is for each clump
    my (@syns,@nomens,%syn_group_index,%rc_group_index);
    my $list_revalidations = 0;
	# If something
	foreach my $row (@results) {
		# put all syn's referring to the same taxon_name together
        if ($row->{'status'} =~ /subgroup|synonym|homonym|replaced|misspell/) {
            if (!exists $syn_group_index{$row->{'parent_spelling_no'}}) {
                $syn_group_index{$row->{'parent_spelling_no'}} = scalar(@syns);
            }
            my $index = $syn_group_index{$row->{'parent_spelling_no'}};
            push @{$syns[$index]},$row;
            $list_revalidations = 1;
        } elsif ($row->{'status'} =~ /nomen/) {
	        # Combine all adjacent like status types @nomens
	        # (They're chronological: nomen, reval, reval, nomen, nomen, reval, etc.)
            my $index;
            if (!@nomens) {
                $index = 0;
            } elsif ($nomens[$#nomens][0]->{'status'} eq $row->{'status'}) {
                $index = $#nomens;
            } else {
                $index = scalar(@nomens);
            }
            push @{$nomens[$index]},$row;
            $list_revalidations = 1;
        } elsif ($row->{'status'} =~ /corr|rank|recomb/ || $row->{'spelling_reason'} =~ /^corr|^rank|^recomb|^reass/) {
            if (!exists $rc_group_index{$row->{'child_spelling_no'}}) {
                $rc_group_index{$row->{'child_spelling_no'}} = scalar(@syns);
            }
            my $index = $rc_group_index{$row->{'child_spelling_no'}};
            push @{$syns[$index]},$row;
            $list_revalidations = 1;
        } elsif (($row->{'status'} =~ /belongs/ && $list_revalidations && $row->{'spelling_reason'} !~ /^recomb|^corr|^rank|^reass/)) {
            # Belongs to's are only considered revalidations if they come
            # after a recombined as, synonym, or nomen *
            my $index;
            if (!@nomens) {
                $index = 0;
            } elsif ($nomens[$#nomens][0]->{'status'} eq $row->{'status'}) {
                $index = $#nomens;
            } else {
                $index = scalar(@nomens);
            }
            push @{$nomens[$index]},$row;
        }
	}
   
    # Now combine the synonyms and nomen/revalidation arrays, with the nomen/revalidation coming last
    my @synonyms = (@syns,@nomens);
	
	# Exception to above:  the most recent opinion should appear last. Splice it to the end
    if (@synonyms) {
        my $oldest_pubyr = 0;
        my $oldest_group = 0; 
        for(my $i=0;$i<scalar(@synonyms);$i++){
            my @group = @{$synonyms[$i]};
            if ($group[$#group]->{'pubyr'} > $oldest_pubyr) {
                $oldest_group = $i; 
                $oldest_pubyr = $group[$#group]->{'pubyr'};
            }
        }
        my $most_recent_group = splice(@synonyms,$oldest_group,1);
        push @synonyms,$most_recent_group;
    }
	
	# Loop through unique parent number from the opinions table.
	# Each parent number is a hash key whose value is an array ref of records.
    foreach my $group (@synonyms) {
        my $first_row = ${$group}[0];
        if ($first_row->{'status'} =~ /belongs/) {
            if ($first_row->{'spelling_reason'} eq 'rank change') {
                my $child = getTaxa($dbt,{'taxon_no'=>$first_row->{'child_no'}});
                my $spelling = getTaxa($dbt,{'taxon_no'=>$first_row->{'child_spelling_no'}});
                if ($child->{'taxon_rank'} =~ /genus/) {
		            $text .= "; it was reranked as ";
                } else {
                    $text .= "; it was reranked as the $spelling->{taxon_rank} ";
                }
            } elsif ( $synmap1{$first_row->{'spelling_reason'}} ne "revalidated" || $first_row ne ${$group}[0] ) {
		        $text .= "; it was ".$synmap1{$first_row->{'spelling_reason'}};
            }
        } else {
		    $text .= "; it was ".$synmap2{$first_row->{'status'}};
        }
        if ($first_row->{'status'} !~ /nomen/) {
            my $taxon_no;
            if ($first_row->{'status'} =~ /subgroup|synonym|replaced|homonym|misspelled/) {
                $taxon_no = $first_row->{'parent_spelling_no'};
            } elsif ($first_row->{'status'} =~ /misspell/) {
                $taxon_no = $first_row->{'child_spelling_no'};
            } elsif ($first_row->{'spelling_reason'} =~ /correct|recomb|rank|reass|missp/) {
                $taxon_no = $first_row->{'child_spelling_no'};
            }
            if ($taxon_no) {
                my $taxon = getTaxa($dbt,{'taxon_no'=>$taxon_no},['taxon_no','taxon_name','taxon_rank','author1last','author2last','otherauthors','pubyr']);
                if ($taxon->{'taxon_rank'} =~ /genus|species/) {
			        $text .= "<i>".$taxon->{'taxon_name'}."</i>";
                } else {
			        $text .= $taxon->{'taxon_name'};
                }
                if ($first_row->{'status'} eq 'homonym of') {
                    my $pub_info = formatShortRef($taxon);
                    $text .= ", $pub_info";
                }
            }
        }
            if ( $first_row->{'status'} !~ /belongs/ || $synmap1{$first_row->{'spelling_reason'}} ne "revalidated" || $first_row ne ${$group}[0] ) {
                if ($first_row->{'status'} eq 'misspelling of') {
                    $text .= " according to ";
                } else {
                    $text .= " by ";
                }
                $text .= printReferenceList($group,$best_opinion);
            }
	}
	if($text ne ""){
        if ($text !~ /\.\s*$/) {
            $text .= ".";
        }
        # Capitalize first it. 
		$text =~ s/;\s+it/It/;
	}

    my %parents = ();
    foreach my $row (@results) {
        if ($row->{'status'} =~ /belongs/) {
            if ($row->{'parent_spelling_no'}) { # Fix for bad opinions. See Asinus, Equus some of the horses
                push @{$parents{$row->{'parent_spelling_no'}}},$row;
            }
        }
    }
    $text =~ s/<br><br>\s*\.\s*$//i;
    my @parents_ordered = sort {$parents{$a}[-1]->{'pubyr'} <=> $parents{$b}[-1]->{'pubyr'} } keys %parents;
    if (@parents_ordered && $taxon->{'taxon_rank'} !~ /species/) {
        $text .= "<br><br>";
        #my $taxon_name = $taxon->{'taxon_name'};
        #if ($taxon->{'taxon_rank'} =~ /genus|species/) {
        #    $taxon_name = "<i>$taxon_name</i>";
        #}
        #$text .= makeAnchor("checkTaxonInfo", "taxon_no=$taxon->{taxon_no}&amp;is_real_user=$is_real_user", $taxon_name) . " was assigned ";
        $text .= "It was assigned";
        for(my $j=0;$j<@parents_ordered;$j++) {
            my $parent_no = $parents_ordered[$j];
            my $parent = getTaxa($dbt,{'taxon_no'=>$parent_no});
            my @parent_array = @{$parents{$parent_no}};
            $text .= " and " if ($j==$#parents_ordered && @parents_ordered > 1);
            my $parent_name = $parent->{'taxon_name'};
            if ($parent->{'taxon_rank'} =~ /genus|species/) {
                $parent_name = "<i>$parent_name</i>";
            }
            $text .= " to " . makeAnchor("checkTaxonInfo", "taxon_no=$parent->{taxon_no}&amp;is_real_user=$is_real_user", $parent_name) . " by ";
            $text .= printReferenceList(\@parent_array,$best_opinion);
            $text .= "; ";
        }
        $text =~ s/; $/\./;
    }
    
    return $text;

    # Only used in this function, just a simple utility to print out a formatted list of references
    sub printReferenceList {
        my @ref_array = @{$_[0]};
        my $best_opinion = $_[1];
        my $text = " ";
        foreach my $ref (@ref_array) {
            if ($ref->{'ref_has_opinion'} =~ /yes/i) {
                if ( $ref->{'opinion_no'} eq $best_opinion )	{
                    $text .= "<b>";
                }
                $text .= formatShortRef($ref,'alt_pubyr'=>1,'show_comments'=>1, 'link_id'=>1);
                if ( $ref->{'opinion_no'} eq $best_opinion )	{
                    $text .= "</b>";
                }
                $text .= ", ";
            } else {
                if ( $ref->{'opinion_no'} eq $best_opinion )	{
                    $text .= "<b>";
                }
                $text .= formatShortRef($ref,'alt_pubyr'=>1,'show_comments'=>1);
                if ( $ref->{'opinion_no'} eq $best_opinion )	{
                    $text .= "</b>";
                }
                $text .= ", ";
            }
        }
        $text =~ s/, $//;
        my $last_comma = rindex($text,",");
        if ($last_comma >= 0) {
            substr($text,$last_comma,1," and ");
        }
        
        return $text;
    }

}


# Handle the 'Taxonomic history' section

sub displayTaxonHistory {
    
    my ($dbt, $taxon_no, $is_real_user) = @_;
    
    my $output = "";  # html output...
    
    unless($taxon_no) {
	return "<p><i>No taxonomic data are available</i></p>";
    }
    
    # Surrounding table prevents display bug in firefox
    
    $output .= "<table><tr><td><ul>";
    
    my $orig_no = getOriginalCombination($dbt, $taxon_no);
    
    # Select all parents of the original combination whose status' are
    # either 'recombined as,' 'corrected as,' or 'rank changed as'
    
    my $sql = "SELECT DISTINCT(child_spelling_no), status FROM opinions WHERE child_no=$orig_no ";
    my @results = @{$dbt->getData($sql)};

	# Combine parent numbers from above for the next select below. If nothing
	# was returned from above, use the original combination number. Shouldn't be necessary but just in case
	my @parent_list = ();
    foreach my $rec (@results) {
        push(@parent_list,$rec->{'child_spelling_no'});
    }
    # don't forget th/ original (verified) here, either: the focal taxon	
    # should be one of its children so it will be included below.
    push(@parent_list, $orig_no);

	# Get alternate "original" combinations, usually lapsus calami type cases.  Shouldn't exist, 
    # exists cause of sort of buggy data.
	$sql = "SELECT DISTINCT child_no FROM opinions ".
		   "WHERE child_spelling_no IN (".join(',',@parent_list).") ".
		   "AND child_no != $orig_no";
	my @more_orig = map {$_->{'child_no'}} @{$dbt->getData($sql)};

    # Remove duplicates
    my %results_no_dupes;
    my @synonyms = getJuniorSynonyms($dbt,$orig_no);
    @results_no_dupes{@synonyms} = ();
    @results_no_dupes{@more_orig} = ();
    @results = keys %results_no_dupes;
	
	
    # # Print the info for the original combination of the passed in taxon first.
    # my $basicOutput = getSynonymyParagraph($dbt, $orig_no, $is_real_user);

	# Get synonymies for all of these original combinations
	my @paragraphs = ();
	foreach my $child (@results) {
		my $list_item = displaySynonymyParagraph($dbt, $child, $child, $is_real_user);
		push(@paragraphs, "<li style=\"padding-bottom: 1.5em;\">$list_item</li>\n") if($list_item ne "");
	}

	# Now alphabetize the rest:
	if ( @paragraphs )	{
		@paragraphs = sort {lc($a) cmp lc($b)} @paragraphs;
		foreach my $rec (@paragraphs) {
			$output .= $rec;
		}
	} else	{
		$output = "";
	}

	if ( $output !~ /<li/ )	{
		$output = "";
	} else	{
		$output .= "</ul></td></tr></table>";
	}
    
    # return ($basicOutput,$output);
    return $output;
}



# split out as a function 4.11.09
sub printTypeInfo	{

    my $dbt = shift;
    my $spellings = shift;
    my $taxon = shift;
    my $is_real_user = shift;
    my $taxonInfoGoal = shift;
    my $preface = shift;
    my $text;

    if ($taxon->{'taxon_rank'} =~ /species/) {
        if ( $taxon->{'type_specimen'} || $taxon->{'type_body_part'} || $taxon->{'part_details'} || $taxon->{'type_locality'} )	{
            if ($taxon->{'type_specimen'})	{
                if ( $preface )	{
                    $text .= "Its type specimen is ";
                }
                $text .= "$taxon->{type_specimen}";
                if ($taxon->{'type_body_part'}) {
                    my $an = ($taxon->{'type_body_part'} =~ /^[aeiou]/) ? "an" : "a";
                    $text .= ", " if ($taxon->{'type_specimen'});
                    if ( $taxon->{type_body_part} =~ /teeth|postcrania|vertebrae|limb elements|appendages|ossicles/ )	{
                        $an = "a set of";
                    }
                    $text .= "$an $taxon->{type_body_part}";
                }
                if ($taxon->{'part_details'}) {
                    $text .= " ($taxon->{part_details})";
                }
                $text .= ". ";
            }
            # don't report preservation for extant taxa
            if ($taxon->{'preservation'} && $taxon->{'extant'} !~ /y/i) {
                my %p = ("body (3D)" => "3D body fossil", "compression" => "compression fossil", "soft parts (3D)" => "3D fossil preserving soft parts", "soft parts (2D)" => "compression preserving soft parts", "amber" => "inclusion in amber", "cast" => "cast", "mold" => "mold", "impression" => "impression", "trace" => "trace fossil", "not a trace" => "not a trace fossil");
                my $preservation = $p{$taxon->{'preservation'}};
                if ($preservation =~ /^[aieou]/) {
                    $preservation = "an $preservation";
                } elsif ($preservation !~ /^not/ ) {
                    $preservation = "a $preservation";
                }
                if ($taxon->{'type_specimen'} && $taxon->{'type_body_part'})	{
                    $text =~ s/\. $/, /;
                    $text .= "and it is $preservation. ";
                } elsif ($taxon->{'type_specimen'})	{
                    $text =~ s/\. $/ /;
                    $text .= "and is $preservation. ";
                } else	{
                    $text .= "It is $preservation. ";
                }
            }
            if ($taxon->{'type_locality'} > 0)	{
                my $sql = "SELECT i.interval_name AS max,IF (min_interval_no>0,i2.interval_name,'') AS min,IF (country='United States',state,country) AS place,collection_name,formation,lithology1,fossilsfrom1,lithology2,fossilsfrom2,environment FROM collections c,intervals i,intervals i2 WHERE collection_no=".$taxon->{'type_locality'}." AND i.interval_no=max_interval_no AND (min_interval_no=0 OR i2.interval_no=min_interval_no)";
                my $coll_row = ${$dbt->getData($sql)}[0];
                $coll_row->{'lithology1'} =~ s/not reported//;
                my $strat = $coll_row->{'max'};
                if ( $coll_row->{'min'} )	{
                    $strat .= "/".$coll_row->{'min'};
                }
                my $fm = $coll_row->{'formation'};
                if ( $fm )	{
                    $fm = "the $fm Formation";
                }
                if ( $coll_row->{'fossilsfrom1'} eq "YES" && $coll_row->{'fossilsfrom2'} ne "YES" )	{
                    $coll_row->{'lithology2'} = "";
                } elsif ( $coll_row->{'fossilsfrom1'} ne "YES" && $coll_row->{'fossilsfrom2'} eq "YES" )	{
                    $coll_row->{'lithology1'} = "";
                }
                my $lith = $coll_row->{'lithology1'};
                if ( $coll_row->{'lithology2'} )	{
                    $lith .= "/" . $coll_row->{'lithology2'};
                }
                if ( ! $lith )	{
                    $lith = "horizon";
                }
                if ( $coll_row->{'environment'} )	{
                    if ( $strat =~ /^[AEIOU]/ )	{
                        $strat = "an ".$strat;
                    } else	{
                        $strat = "a ".$strat;
                    }
                    if ( $fm ) { $fm = "in $fm of"; } else { $fm = "in"; }
                    $lith = $coll_row->{'environment'}." ".$lith;
                } else	{
                    $strat = "the ".$strat." of ";
                }
                $lith =~ s/ indet\.//;
                $lith =~ s/"//g;
                $coll_row->{'place'} =~ s/,.*//;
                $coll_row->{'place'} =~ s/Libyan Arab Jamahiriya/Libya/;
                $coll_row->{'place'} =~ s/Syrian Arab Republic/Syria/;
                $coll_row->{'place'} =~ s/Lao People's Democratic Republic/Laos/;
                $coll_row->{'place'} =~ s/(United Kingdom|Russian Federation|Czech Republic|Netherlands|Dominican Republic|Bahamas|Philippines|Netherlands Antilles|United Arab Emirates|Marshall Islands|Congo|Seychelles)/the $1/;
                $text .= "Its type locality is ";
		$text .= makeAnchor("basicCollectionSearch", "collection_no=$taxon->{type_locality}&amp;is_real_user=$is_real_user", 
				    $coll_row->{'collection_name'});
		$text .= ", which is in $strat $lith $fm $coll_row->{'place'}. ";
            }
        }
    } else {
        my $sql = "SELECT taxon_no,type_taxon_no FROM authorities WHERE type_taxon_no != 0 AND taxon_no IN (".$spellings.")";
        my $tt_row = ${$dbt->getData($sql)}[0];
        if ($tt_row) {
            my $type_taxon = getTaxa($dbt,{'taxon_no'=>$tt_row->{'type_taxon_no'}});
            my $type_taxon_name = $type_taxon->{'taxon_name'};
            if ($type_taxon->{'taxon_rank'} =~ /genus|species/) {
                $type_taxon_name = "<i>".$type_taxon_name."</i>";
            }
            if ( $preface )	{
                $text .= "Its type is ";
            }
            $text .= makeAnchor("$taxonInfoGoal", "taxon_no=$type_taxon->{taxon_no}&amp;is_real_user=$is_real_user", $type_taxon_name) . ". ";  
        }
    }

    return ($text,$taxon->{'type_locality'});

}


# JA 1.8.03
sub displayEcology {
    
    my ($dbt, $taxon_no, $in_list) = @_;

    my $output = qq|<div class="small displayPanel" align="left" style="width: 46em; margin-top: 0em; padding-top: 1em; padding-bottom: 1em;">
<div align="center" class="displayPanelContent">
|;

    if (!defined $taxon_no || $taxon_no == 0 || $in_list->[0] == -1)
    {
	$output .= qq|<i>No ecological data are available</i>
</div>
</div>
|;
	return $output;
    }
    
    # get the field names from the ecotaph table
    
    my @ecotaphFields = $dbt->getTableColumns('ecotaph');
    
    # also get values for ancestors
    
    # my $class_hash = getParents($dbt,[$taxon_no],'array_full');
    
    my @parent_list = getParents($dbt, $taxon_no);
    my $class_hash = { $taxon_no => \@parent_list };
    
    my $eco_hash = PBDB::Ecology::getEcology($dbt,$class_hash,\@ecotaphFields,'get_basis');
    my $ecotaphVals = $eco_hash->{$taxon_no};

	if ( ! $ecotaphVals )	{
                $output .= qq|<i>No ecological data are available</i>
</div>
</div>
|;
		return $output;
	} else	{
        # Convert units for display
        foreach ('minimum_body_mass','maximum_body_mass','body_mass_estimate') {
            if ($ecotaphVals->{$_}) {
                if ($ecotaphVals->{$_} < 1) {
                    $ecotaphVals->{$_} = PBDB::EcologyEntry::kgToGrams($ecotaphVals->{$_});
                    $ecotaphVals->{$_} .= ' g';
                } else {
                    $ecotaphVals->{$_} .= ' kg';
                }
            }
        } 
        
        my @references = @{$ecotaphVals->{'references'}};     

        my @ranks = ('subspecies', 'species', 'subgenus', 'genus', 'subtribe', 'tribe', 'subfamily', 'family', 'superfamily', 'infraorder', 'suborder', 'order', 'superorder', 'infraclass', 'subclass', 'class', 'superclass', 'subphylum', 'phylum', 'superphylum', 'subkingdom', 'kingdom', 'superkingdom', 'unranked clade');
        my %rankToKey = ();
        foreach my $rank (@ranks) {
            my $rank_abbrev = $rank;
            $rank_abbrev =~ s/species/s/;
            $rank_abbrev =~ s/genus/g/;
            $rank_abbrev =~ s/tribe/t/;
            $rank_abbrev =~ s/family/f/;
            $rank_abbrev =~ s/order/o/;
            $rank_abbrev =~ s/class/c/;
            $rank_abbrev =~ s/phylum/p/;
            $rank_abbrev =~ s/kingdom/f/;
            $rank_abbrev =~ s/unranked clade/uc/;
            $rankToKey{$rank} = $rank_abbrev;
        }   
        my %all_ranks = ();

		$output .= "<table cellpadding=\"4\">";
        $output .= "<tr>";
		my $cols = 0;
		foreach my $i (0..$#ecotaphFields)	{
			my $name = $ecotaphFields[$i];
			my $nextname = $ecotaphFields[$i+1];
			my $n = $name;
			my @letts = split //,$n;
			$letts[0] =~ tr/[a-z]/[A-Z]/;
			$n = join '',@letts;
			$n =~ s/_/ /g;
			$n =~ s/Taxon e/E/;
			if ( $n =~ /1/ && $ecotaphVals->{$nextname} !~ /2/ )	{
				$n =~ s/1//;
			}
			$n =~ s/1$/&nbsp;1/g;
			$n =~ s/2$/&nbsp;2/g;
			if ( $ecotaphVals->{$name} && $name !~ /_no$/ )	{
				my $v = $ecotaphVals->{$name};
				my $rank = $ecotaphVals->{$name."basis"};
				$all_ranks{$rank} = 1; 
				$v =~ s/,/, /g;
				if ( $cols == 2 || $name =~ /^comments$/ || $name =~ /^created$/ || $name =~ /^size_value$/ || $name =~ /1$/ )	{
				 	$output .= "</tr>\n<tr>\n";
					$cols = 0;
				}
				$cols++;
				my $colspan = ($name =~ /comments/) ? "colspan=2" : "";
				my $rank_note = "<span class=\"superscript\">$rankToKey{$rank}</span>";
				if ($name =~ /created|modified/) {
					$rank_note = "";
				}
				$output .= "<td $colspan valign=\"top\"><table cellpadding=0 cellspacing=0 border=0><tr><td align=\"left\" valign=\"top\"><span class=\"fieldName\">$n:</span>&nbsp;</td><td valign=\"top\">${v}${rank_note}</td></tr></table></td> \n";
			}
		}
        $output .= "</tr>" if ( $cols > 0 );
        # now print out keys for superscripts above
        $output .= "<tr><td colspan=2>";
        my $html = "<span class=\"fieldName\">Source:</span> ";
        foreach my $rank (@ranks) {
            if ($all_ranks{$rank}) {
                $html .= "$rankToKey{$rank} = $rank, ";
            }
        }
        $html =~ s/, $//;
        $output .= $html;
        $output .= "</td></tr>"; 
        $output .= "<tr><td colspan=2><span class=\"fieldName\">";
        if (scalar(@references) == 1) {
            $output .= "Reference: ";
        } elsif (scalar(@references) > 1) {
            $output .= "References: ";
        }
        $output .= "</span>";
        for(my $i=0;$i<scalar(@references);$i++) {
            my $sql = "SELECT reference_no,author1last,author2last,otherauthors,pubyr FROM refs WHERE reference_no=$references[$i]";
            my $ref = ${$dbt->getData($sql)}[0];
            $references[$i] = formatShortRef($ref,'link_id'=>1);
        }
        $output .= join(", ",@references);
        $output .= "</td></tr>";
		$output .= "</table>\n";
	}

        $output .= "\n</div>\n</div>\n";
	return $output;

}

# PS 6/27/2005
sub displayMeasurements {
    my ($dbt,$taxon_no,$taxon_name,$in_list) = @_;

    # Specimen level data:
    my @specimens;
    my $specimen_count;
    if ($taxon_no) {
        my $t = getTaxa($dbt,{'taxon_no'=>$taxon_no});
        if ($t->{'taxon_rank'} =~ /genus|species/) {
            # If the rank is genus or lower we want the big aggregate list of all taxa
            @specimens = getMeasurements($dbt,{'taxon_list'=>$in_list,'get_global_specimens'=>1});
        } else {
            # If the rank is higher than genus, then that rank is too big to be meaningful.  
            # In that case we only want the taxon itself (and its synonyms and alternate names), not the big recursively generated list
            # i.e. If they entered Nasellaria, get Nasellaria indet., or Nasellaria sp. or whatever.
            # get alternate spellings of focal taxon. 
            my @small_in_list = getAllSynonyms($dbt,$taxon_no);
            @specimens = getMeasurements($dbt,{'taxon_list'=>\@small_in_list,'get_global_specimens'=>1});
        }
    } else {
        @specimens = getMeasurements($dbt,{'taxon_name'=>$taxon_name,'get_global_specimens'=>1});
        my ($genus,$subgenus,$species,$subspecies) = splitTaxon($taxon_name);
        my $is_species = ($species) ? 1 : 0;
        my $classification_no = getBestClassification($dbt,'',$genus,'',$subgenus,'',$species);
        if ($classification_no)	{
            my $taxon = getTaxa($dbt,{'taxon_no'=>$classification_no});
            $taxon_no = $taxon->{'taxon_no'};
        }
    }

    # Returns a triple index hash with index <part><dimension type><whats measured>
    #  Where part can be leg, valve, etc, dimension type can be length,width,height,circumference,diagonal,diameter,inflation 
    #   and whats measured can be average, min,max,median,error
    my $p_table_ref = getMeasurementTable(\@specimens);
    my %p_table = %{$p_table_ref};

    my $mass_string;

    my $str = qq|<div class="displayPanel" align="left" style="width: 36em;">
<span class="displayPanelHeader" class="large">Measurements</span>
<div align="center" class="displayPanelContent">
|;

    if (@specimens) {

        my %errorSeen = ();
        my %partHeader = ();
        $partHeader{'average'} = "mean";
        my $defaultError = "";
        for my $part ( keys %p_table )	{
	    next unless ref $p_table{$part} eq 'HASH';
            my %m_table = %{$p_table{$part}};
            foreach my $type (('length','width','height','circumference','diagonal','diameter','inflation')) {
                if (exists ($m_table{$type})) {
                    if ( $m_table{$type}{'min'} )	{
                        $partHeader{'min'} = "minimum";
                    }
                    if ( $m_table{$type}{'max'} )	{
                        $partHeader{'max'} = "maximum";
                    }
                    if ( $m_table{$type}{'median'} )	{
                        $partHeader{'median'} = "median";
                    }
                    if ( $m_table{$type}{'error_unit'} )	{
                        $partHeader{'error'} = "error";
                        $errorSeen{$m_table{$type}{'error_unit'}}++;
                        my @errors = keys %errorSeen;
                        if ( $#errors == 0 )	{
                            $m_table{$type}{'error_unit'} =~ s/^1 //;
                            $defaultError = $m_table{$type}{'error_unit'};
                        } else	{
                            $defaultError = "";
                        }
                    }
                }
            }
        }

        # estimate body mass if possible JA 18.7.07
        # code is here and not earlier because we need the parts list first
        my @m = getMassEstimates($dbt,$taxon_no,$p_table_ref);
        my @part_list = @{$m[0]};
        my @masses = @{$m[2]};
        my @eqns = @{$m[3]};
        my @refs = @{$m[4]};
        my $grandmean = $m[5];
        my $grandestimates = $m[6];

        for my $i ( 0..$#masses )	{
            my $reference = formatShortRef($dbt,$refs[$i],'no_inits'=>1,'link_id'=>1);
            $mass_string .= "<tr><td>&nbsp;";
            $mass_string .= formatMass($masses[$i]);
            $mass_string .= '</td>';
            $mass_string .= "<td><span class=\"small\">&nbsp;$eqns[$i]</span></td><td><span class=\"small\">$reference</span></td></tr>";
        }

        if ( $mass_string )	{
            if ( $#masses > 0 )	{
                $mass_string .= '<tr><td colspan="3">mean: '.formatMass( exp( $grandmean / $grandestimates ) )."</td></tr>\n";
            }
            $mass_string = qq|<div class="displayPanel" align="left" style="width: 36em; margin-bottom: 2em;">
<span class="displayPanelHeader" class="large">Body mass estimates</span>
<div align="center" class="displayPanelContent">
<table cellspacing="6"><tr><th align="center">estimate</th><th align="center">equation</th><th align="center">reference</th></tr>
$mass_string
</table>
</div>
</div>
|;
        }

        my $temp;
        my $spacing = "5px";
        if ( ! $partHeader{'min'} )	{
            $spacing = "8px";
        }
        $str .= "<table cellspacing=\"$spacing;\"><tr><th>part</th><th align=\"left\">N</th><th>$partHeader{'average'}</th><th>$partHeader{'min'}</th><th>$partHeader{'max'}</th><th>$partHeader{'median'}</th><th>$defaultError</th><th></th></tr>";
        for my $part ( @part_list )	{
            if ( ! $p_table{$part} )	{
                next;
            }
            my %m_table = %{$p_table{$part}};
            $temp++;

            foreach my $type (('length','width','height','circumference','diagonal','diameter','inflation')) {
                if (exists ($m_table{$type})) {
                    if ( $m_table{$type}{'average'} <= 0 )	{
                        next;
                    }
                    $str .= "<tr><td>$part $type</td>";
                    $str .= "<td>$m_table{specimens_measured}</td>";
                    foreach my $column (('average','min','max','median','error')) {
                        my $value = $m_table{$type}{$column};
                        if ( $value <= 0 && $partHeader{$column} ) {
                            $str .= "<td align=\"center\">-</td>";
                        } elsif ( ! $partHeader{$column} ) {
                            $str .= "<td align=\"center\"></td>";
                        } else {
                            if ( $value < 1 )	{
                                $value = sprintf("%.3f",$value);
                            } elsif ( $value < 10 )	{
                                $value = sprintf("%.2f",$value);
                            } else	{
                                $value = sprintf("%.1f",$value);
                            }
                            $str .= "<td align=\"center\">$value</td>";
                        }
                    }
                    $str .= qq|<td align="center" style="white-space: nowrap;">|;
                    if ( $m_table{$type}{'error'} && ! $defaultError ) {
                        $m_table{$type}{error_unit} =~ s/^1 //;
                        $str .= qq|$m_table{$type}{error_unit}|;
                    }
                    $str .= '</td></tr>';
                }
            }
        }
        $str .= "</table><br>\n";
    } else {
        $str .= "<div align=\"center\" style=\"padding-bottom: 1em;\"><i>No measurements are available</i>\n</div>\n";
    }
    $str .= qq|</div>
</div>
|;

    if ( $mass_string )	{
        $str = $mass_string . $str;
    }

    return $str;
}

# JA 7.12.10
sub formatMass	{
	my $mass = shift;
	if ( $mass < 1000 )	{
		$mass = sprintf "%.1f g",$mass;
	} elsif ( $mass < 10000 )	{
		$mass = sprintf "%.2f kg",$mass / 1000;
	} elsif ( $mass > 10000 && $mass < 1000000 )	{
		$mass = sprintf "%.1f kg",$mass / 1000;
	} elsif ( $mass < 10000000 )	{
		$mass = sprintf "%.2f tons",$mass / 1000000;
	} else	{
		$mass = sprintf "%.1f tons",$mass / 1000000;
	}
	return $mass;
}

sub displayDiagnoses {
    my ($dbt,$taxon_no) = @_;
    my $str = "";
    $str .= qq|<div class="displayPanel" align="left" style="width: 36em; margin-top: 2em; margin-bottom: 2em; padding-bottom: 1em;">
<span class="displayPanelHeader" class="large">Diagnosis</span>
<div class="displayPanelContent">
|;
    my @diagnoses = ();
    if ($taxon_no) {
        @diagnoses = getDiagnoses($dbt,$taxon_no);

        if (@diagnoses) {
            $str .= "<table cellspacing=5>\n";
            $str .= "<tr><th>Reference</th><th>Diagnosis</th></tr>\n";
            foreach my $row (@diagnoses) {
                $str .= "<tr><td valign=top><span style=\"white-space: nowrap\">$row->{reference}</span>";
                if ($row->{'is_synonym'}) {
                    if ($row->{'taxon_rank'} =~ /species|genus/) {
                        $str .= " (<i>$row->{taxon_name}</i>)";
                    } else {
                        $str .= " ($row->{taxon_name})";
                    }
                } 
                $row->{diagnosis} =~ s/\n/<br>/g;
                $str .= "</td><td>$row->{diagnosis}<td></tr>";
            }
            $str .= "</table>\n";
        } 
    } 
    if ( ! $taxon_no || ! @diagnoses ) {
        $str .= "<div align=\"center\"><i>No diagnoses are available</i></div>";
    }
    $str .= "\n</div>\n</div>\n";
    return $str;
}


# This will return all diagnoses for a particular taxon, for all its spellings, and
# for all its junior synonyms. The diagnoses are passed back as a sorted array of hashrefs ordered by
# pubyr of the opinion.  Each hashref has the following keys:
#  taxon_no: spelling_no for the opinion for which the diagnosis exists
#  reference: formated reference for the diagnosis
#  diagnosis: text of the diagnosis field
#  is_synonym: boolean denoting whether this is a 
#  taxon_name: spelling_name for the opinion fo rwhich the diagnosis exists
# Example usage:
#   $taxon = getTaxa($dbt,{'taxon_name'=>'Calippus'});
#   @diagnoses = getDiagnoses($dbt,$taxon->{taxon_no});
#   foreach $d (@diagnoses) {
#       print "$d->{reference}: $d->{diagnosis}";
#   }
sub getDiagnoses {
    my $dbt = shift;
    my $taxon_no = shift;
    $taxon_no = int($taxon_no);

    my @diagnoses = ();
    my %is_synonym = ();
    if ($taxon_no) {
        # Tricky part is the is_synonym, which will be set to a boolean if the taxon_no passed back is a 
        # synonym (either junior or senior, doesn't make that distiction) or not.  The spelling_no is the
        # most recently uses spelling for the current taxon, so this will be a constant for all the different
        # spellings of the current synonym, and different for all its synonyms
        my $sql = "SELECT t2.taxon_no,IF(t2.spelling_no = t1.spelling_no,0,1) is_synonym FROM $TAXA_TREE_CACHE t1, $TAXA_TREE_CACHE t2 WHERE t1.taxon_no=$taxon_no and t1.synonym_no=t2.synonym_no";
        my @results = @{$dbt->getData($sql)};
        my @children;
        foreach my $row (@results) {
            push @children, $row->{'taxon_no'};
            $is_synonym{$row->{'taxon_no'}} = $row->{'is_synonym'};
        }
        if (@children) {
            # Uses the taxa_tree_cache to get opinions for all various spellings, including synonyms
            $sql = "SELECT o.opinion_no,o.child_no, o.child_spelling_no, a.taxon_name, a.taxon_rank, o.diagnosis, o.ref_has_opinion,o.author1init,o.author1last,o.author2init,o.author2last,o.otherauthors,o.pubyr,o.reference_no FROM opinions o, authorities a WHERE o.child_spelling_no=a.taxon_no AND o.child_no IN (".join(",",@children).") AND o.diagnosis IS NOT NULL AND o.diagnosis != ''";
            my @results = @{$dbt->getData($sql)};
            foreach my $row (@results) {
                my $reference = "";
                my $pubyr = "";
                if ($row->{'ref_has_opinion'}) {
                    if ($row->{'reference_no'}) {
                        $sql = "SELECT author1init,author1last,author2init,author2last,otherauthors,pubyr,reference_no FROM refs WHERE reference_no=$row->{reference_no}";
                        my $refData = ${$dbt->getData($sql)}[0];
                        $reference = formatShortRef($refData,'link_id'=>1);
                        $pubyr = $refData->{'pubyr'};
                    }
                } else {
                    $reference = formatShortRef($row);
                    $pubyr = $row->{'pubyr'};
                }
                my %diagnosis = (
                    'taxon_no'  =>$row->{'child_spelling_no'},
                    'taxon_name'=>$row->{'taxon_name'},
                    'taxon_rank'=>$row->{'taxon_rank'},
                    'reference' =>$reference,
                    'pubyr'     =>$pubyr,
                    'opinion_no'=>$row->{'opinion_no'},
                    'diagnosis' =>$row->{'diagnosis'},
                    'is_synonym'=>$is_synonym{$row->{'child_no'}}
                );
                push @diagnoses, \%diagnosis;
            }
        }
    }
    @diagnoses = sort {if ($a->{'pubyr'} && $b->{'pubyr'}) {$a->{'pubyr'} <=> $b->{'pubyr'}}
                       else {$a->{'opinion_no'} <=> $b->{'opinion_no'}}} @diagnoses;
    return @diagnoses;
}


# JA 11-12,14.9.03
# rewritten and shortened 16.7.07 JA
# new version assumes you only ever want to know who named or classified the
#  taxon and its synonyms, and not who assigned something to one of them
sub displaySynonymyList	{
	my $dbt = shift;
    # taxon_no must be an original combination
	my $taxon_no = (shift or "");
	my $is_real_user = shift;
	my $output = "";

	$output .= qq|<div align="left" class="displayPanel" style="width: 42em; margin-top: 0em;">
<span class="displayPanelHeader" style="text-align: left;">Synonymy list</span>
<div align="center" class="small displayPanelContent" style="padding-top: 0em; padding-bottom: 1em;">
|;

	unless ($taxon_no) {
		$output .= "<div align=\"center\" style=\"padding-top: 0.75em;\"><i>No taxonomic opinions are available</i></div>";
		$output .= "</table>\n</div>\n</div>\n";
		return $output;
	}

	# Find synonyms
	my @syns = getJuniorSynonyms($dbt,$taxon_no);

	# Push the focal taxon onto the list as well
	push @syns, $taxon_no;

	my $syn_list = join(',',@syns);

	# get all opinions
	my $sql = "SELECT child_no,child_spelling_no,status,IF (ref_has_opinion='YES',r.author1last,o.author1last) author1last,IF (ref_has_opinion='YES',r.author2last,o.author2last) author2last,IF (ref_has_opinion='YES',r.otherauthors,o.otherauthors) otherauthors,IF (ref_has_opinion='YES',r.pubyr,o.pubyr) pubyr,pages,figures,ref_has_opinion,o.reference_no FROM opinions o,refs r WHERE o.reference_no=r.reference_no AND child_no IN ($syn_list)";
	my @opinionrefs = @{$dbt->getData($sql)};

	# a list of all spellings used is needed to get the names from the
	#  authorities table, which we have to hit anyway

	my %spelling_nos = ();
	my %orig_no = ();
	for my $or ( @opinionrefs )	{
		$spelling_nos{$or->{child_spelling_no}}++;
		$orig_no{$or->{child_spelling_no}} = $or->{child_no};
	}

	my $spelling_list = join(',',keys %spelling_nos);
	if ( ! $spelling_list )	{
		$output .= "<div align=\"center\" style=\"padding-top: 0.75em;\"><i>No taxonomic opinions are available</i></div>";
		$output .= "</table>\n</div>\n</div>\n";
		return $output;
	}

	# get all authority records, including those of variant spellings
	# recombinations will be used to format opinions, and will be
	#  trimmed out themselves later
	my $sql = "SELECT taxon_no,taxon_name,taxon_rank,IF (ref_is_authority='YES',r.author1last,a.author1last) author1last,IF (ref_is_authority='YES',r.author2last,a.author2last) author2last,IF (ref_is_authority='YES',r.otherauthors,a.otherauthors) otherauthors,IF (ref_is_authority='YES',r.pubyr,a.pubyr) pubyr,pages,figures,ref_is_authority,a.reference_no FROM authorities a,refs r WHERE a.reference_no=r.reference_no AND taxon_no IN ($spelling_list)";
	my @authorityrefs = @{$dbt->getData($sql)};

	# do some initial formatting and create a name lookup hash
	my %spelling = ();
	my %rank = ();
	my %synline = ();
	for my $ar ( @authorityrefs )	{
		$spelling{$ar->{taxon_no}} = $ar->{taxon_name};
		$rank{$ar->{taxon_no}} = $ar->{taxon_rank};
		if ( $ar->{taxon_no} == $orig_no{$ar->{taxon_no}} )	{
			my $synkey = buildSynLine($ar);
			$synline{$synkey}->{TAXON} = $ar->{taxon_name};
			$synline{$synkey}->{YEAR} = $ar->{pubyr};
			$synline{$synkey}->{AUTH} = $ar->{author1last} . " " . $ar->{author2last};
			$synline{$synkey}->{PAGES} = $ar->{pages};
		}
	}
	# go through the opinions only now that you have the names
	for my $or ( @opinionrefs )	{
		if ( $or->{status} =~ /belongs to/ )	{
			$or->{taxon_name} = $spelling{$or->{child_spelling_no}};
			$or->{taxon_rank} = $rank{$or->{child_spelling_no}};
			my $synkey = buildSynLine($or);
			$synline{$synkey}->{TAXON} = $or->{taxon_name};
			$synline{$synkey}->{YEAR} = $or->{pubyr};
			$synline{$synkey}->{AUTH} = $or->{author1last} . " " . $or->{author2last};
			$synline{$synkey}->{PAGES} = $or->{pages};
		}
	}

	
	sub buildSynLine	{
		my $refdata = shift;
		my $synkey = "";

		if ( $refdata->{pubyr} )	{
			$synkey = "<td valign=\"top\">" . $refdata->{pubyr} . "</d><td valign=\"top\">";
			if ( $refdata->{taxon_rank} =~ /genus|species/ )	{
 				$synkey .= "<i>";
			}
			$synkey .= $refdata->{taxon_name};
			if ( $refdata->{taxon_rank} =~ /genus|species/ )	{
 				$synkey .= "</i>";
			}
			$synkey .= " ";
			my $authorstring = $refdata->{author1last};;
			if ( $refdata->{otherauthors} )	{
				$authorstring .= " et al.";
			} elsif ( $refdata->{author2last} )	{
				$authorstring .= " and " . $refdata->{author2last};
			}
			if ( $refdata->{ref_is_authority} eq "YES" || $refdata->{ref_has_opinion} eq "YES" )	{
				$authorstring = makeAnchor("displayReference", "reference_no=$refdata->{reference_no}&amp;is_real_user=$is_real_user", 
							   $authorstring);
			}
			$synkey .= $authorstring;
		}
		if ( $refdata->{pages} )	{
			if ( $refdata->{pages} =~ /[ -]/ )	{
				$synkey .= " pp. " . $refdata->{pages};
			} else	{
				$synkey .= " p. " . $refdata->{pages};
			}
		}
		if ( $refdata->{figures} )	{
			if ( $refdata->{figures} =~ /[ -]/ )	{
				$synkey .= " figs. " . $refdata->{figures};
			} else	{
				$synkey .= " fig. " . $refdata->{figures};
			}
		}

		return $synkey;
	}

# sort the synonymy list by pubyr
	my @synlinekeys = sort { $synline{$a}->{YEAR} <=> $synline{$b}->{YEAR} || $synline{$a}->{AUTH} cmp $synline{$b}->{AUTH} || $synline{$a}->{PAGES} <=> $synline{$b}->{PAGES} || $synline{$a}->{TAXON} cmp $synline{$b}->{TAXON} } keys %synline;

# print each line of the synonymy list
	$output .= qq|<table cellspacing=5>
<tr><th>Year</th><td>Name and author</th></tr>
|;
	my $lastline;
	foreach my $synline ( @synlinekeys )	{
		if ( $synline{$synline}->{YEAR} . $synline{$synline}->{AUTH} . $synline{$synline}->{TAXON} ne $lastline )	{
			$output .= "<tr>$synline</td></tr>\n";
		}
		$lastline = $synline{$synline}->{YEAR} . $synline{$synline}->{AUTH} . $synline{$synline}->{TAXON};
	}
	$output .= "</table>\n</div>\n</div>\n";

    return $output;
}

# # JA 10.1.09
# sub beginFirstAppearance	{
# 	my ($hbo,$q,$error_message) = @_;
# 	return $hbo->populateHTML('first_appearance_form', [$error_message], ['error_message']);
# 	# if ( $error_message )	{
# 	# 	return;
# 	# }
# }

# # JA 10-13.1.09
# sub displayFirstAppearance	{
#     my ($q,$s,$dbt,$hbo) = @_;
    
#     my $dbh = $dbt->dbh;
#     # $|=1;
#     my $output = '';
# 	my ($sql,$field,$name);
# 	if ( $q->param('taxon_name') )	{
# 		if ( $q->param('taxon_name') !~ /^[A-Z][a-z]*(| )[a-z]*$/ )	{
# 			my $error_message = "The name '".$q->param('taxon_name')."' is formatted incorrectly.";
# 			beginFirstAppearance($hbo,$q,$error_message);
# 		}
# 		if ( $q->param('common_name') )	{
# 			my $error_message = "Please enter either a scientific or common name, not both.";
# 			beginFirstAppearance($hbo,$q,$error_message);
# 		}
# 		$field = "taxon_name";
# 		$name = $q->param('taxon_name');
# 	} elsif ( $q->param('common_name') )	{
# 		if ( $q->param('common_name') =~ /[^A-Za-z ]/ )	{
# 			my $error_message = "A common name can't include anything but letters.";
# 			beginFirstAppearance($hbo,$q,$error_message);
# 		}
# 		$field = "common_name";
# 		$name = $q->param('common_name');
# 	} else	{
# 		my $error_message = "No search term was entered.";
# 		beginFirstAppearance($hbo,$q,$error_message);
# 	}
# 	my $exclude;
# 	if ( $q->param('exclude') )	{
# 		my $names = $q->param('exclude');
# 		$names =~ s/[^A-Za-z]/ /g;
# 		$names =~ s/  / /g;
# 		$names =~ s/  / /g;
# 		$names =~ s/ /','/g;
# 		$sql = "SELECT a.taxon_no,a.taxon_name,lft,rgt FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_name IN ('".$names."') AND a.taxon_no=t.spelling_no GROUP BY lft,rgt ORDER BY lft";
# 		my @nos = @{$dbt->getData($sql)};
# 		$exclude .= " AND (rgt<$_->{'lft'} OR lft>$_->{'rgt'})" foreach @nos;
# 	}

# 	# it's overkill to use getChildren because the query is so simple
# 	my $quoted_name = $dbh->quote($name); 
# 	$sql  = "SELECT a.taxon_no,a.taxon_name,IF(a.ref_is_authority='YES',r.author1last,a.author1last) author1last,IF(a.ref_is_authority='YES',r.author2last,a.author2last) author2last,IF(a.ref_is_authority='YES',r.otherauthors,a.otherauthors) otherauthors,IF(a.ref_is_authority='YES',r.pubyr,a.pubyr) pubyr,a.taxon_rank,a.extant,a.preservation,lft,rgt FROM refs r,authorities a,authorities a2,$TAXA_TREE_CACHE t WHERE r.reference_no=a.reference_no AND a2.taxon_no=t.taxon_no AND a2.$field=$quoted_name AND a.taxon_no=t.synonym_no GROUP BY lft,rgt ORDER BY rgt-lft DESC";
# 	my @nos = @{$dbt->getData($sql)};

# 	if ( ! @nos )	{
# 		my $error_message = qq|The name "$name" is not in the system. Please try again.|;
# 		beginFirstAppearance($hbo,$q,$error_message);
# 	}
# 	$name = $nos[0]->{'taxon_name'};

# 	if ( $field eq "common_name" )	{
# 		$name = $nos[0]->{'taxon_name'}." (".$name.")";
# 	}
# 	my $authors = $nos[0]->{'author1last'};
# 	if ( $nos[0]->{'otherauthors'} )	{
# 		$authors .= " <i>et al.</i>";
# 	} elsif ( $nos[0]->{'author2last'} )	{
# 		$authors .= " and ".$nos[0]->{'author2last'};
# 	}
# 	$authors .= " ".$nos[0]->{'pubyr'};

# 	if ( $nos[0]->{'lft'} == $nos[0]->{'rgt'} - 1 && $nos[0]->{'taxon_rank'} !~ /genus|species/ )	{
# 		my $error_message = "$name $authors includes no classified subtaxa.";
# 		beginFirstAppearance($hbo,$q,$error_message);
# 	}
	
# 	# MAIN TABLE HITS

# 	$sql = "SELECT a.taxon_no,taxon_name,taxon_rank,extant,preservation,lft,rgt,synonym_no FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND lft>=".$nos[0]->{'lft'}." AND rgt<=".$nos[0]->{'rgt'}.$exclude." ORDER BY lft";
# 	my @allsubtaxa = @{$dbt->getData($sql)};
# 	my @subtaxa;

# 	if ( $q->param('taxonomic_precision') eq "any subtaxon" )	{
# 		$sql = "SELECT a.taxon_no,taxon_name,extant,preservation,lft,rgt FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND lft>".$nos[0]->{'lft'}." AND rgt<".$nos[0]->{'rgt'}.$exclude;
# 		@subtaxa = @{$dbt->getData($sql)};
# 	} elsif ( $q->param('taxonomic_precision') =~ /species|genus|family/ )	{
# 		my @ranks = ('subspecies','species');
# 		if ( $q->param('taxonomic_precision') =~ /genus or species/ )	{
# 			push @ranks , ('subgenus','genus');
# 		} elsif ( $q->param('taxonomic_precision') =~ /family/ )	{
# 			push @ranks , ('subgenus','genus','tribe','subfamily','family');
# 		}
# 		$sql = "SELECT a.taxon_no,taxon_name,type_locality,extant,preservation,lft,rgt FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND lft>".$nos[0]->{'lft'}." AND rgt<".$nos[0]->{'rgt'}.$exclude." AND taxon_rank IN ('".join("','",@ranks)."')";
# 		if ( $q->param('types_only') =~ /yes/i )	{
# 			$sql .= " AND type_locality>0";
# 		}
# 		if ( $q->param('type_body_part') )	{
# 			my $parts;
# 			if ( $q->param('type_body_part') =~ /multiple teeth/i )	{
# 				$parts = "'skeleton','partial skeleton','skull','partial skull','maxilla','mandible','teeth'";
# 			} elsif ( $q->param('type_body_part') =~ /skull/i )	{
# 				$parts = "'skeleton','partial skeleton','skull','partial skull'";
# 			} elsif ( $q->param('type_body_part') =~ /skeleton/i )	{
# 				$parts = "'skeleton','partial skeleton'";
# 			}
# 			$sql .= " AND type_body_part IN (".$parts.")";
# 		}
# 		@subtaxa = @{$dbt->getData($sql)};
# 	} else	{
# 		@subtaxa = @allsubtaxa;
# 	}

# 	# have to be sure the taxon wasn't marked not-"extant" even though
# 	#  it includes extant subtaxa
# 	my $extant = $nos[0]->{'extant'};
# 	if ( $extant !~ /yes/i )	{
# 		for my $t ( @allsubtaxa )	{
# 			if ( $t->{'extant'} =~ /yes/i )	{
# 				$extant = "yes";
# 				last;
# 			}
# 		}
# 	}

# 	# TRACE FOSSIL REMOVAL

# 	# this is a fast, elegant algorithm for determining simple
# 	#  inheritance of a value (preservation) from parent to child
# 	if ( $q->param('traces') !~ /yes/i )	{
# 		my %istrace;
# 		for my $i ( 0..$#allsubtaxa )	{
# 			my $s = $allsubtaxa[$i];
# 			if ( $s->{'preservation'} eq "trace" )	{
# 				$istrace{$s->{'taxon_no'}}++;
# 		# find parents by descending
# 		# overall parent is innocent until proven guilty
# 			} elsif ( ! $s->{'preservation'} && $s->{'lft'} >= $nos[0]->{'lft'} )	{
# 				my $j = $i-1;
# 			# first part means "not parent"
# 				while ( ( $allsubtaxa[$j]->{'rgt'} < $s->{'lft'} || ! $allsubtaxa[$j]->{'preservation'} ) && $j > 0 )	{
# 					$j--;
# 				}
# 				if ( $allsubtaxa[$j]->{'preservation'} eq "trace" )	{
# 					$istrace{$s->{'taxon_no'}}++;
# 				}
# 			}
# 		}
# 		my @nontraces;
# 		for my $s ( @subtaxa )	{
# 			if ( ! $istrace{$s->{'taxon_no'}} )	{
# 				push @nontraces , $s;
# 			}
# 		}
# 		@subtaxa = @nontraces;
# 	}

# 	# COLLECTION SEARCH

# 	my %options = ();
# 	if ( $q->param('types_only') =~ /yes/i )	{
# 		for my $s ( @subtaxa )	{
# 			if ( $s->{'type_locality'} > 0 ) { $options{'collection_list'} .= ",".$s->{'type_locality'}; }
# 		}
# 		$options{'collection_list'} =~ s/^,//;
# 		push @{$options{'species_reso'}} , "n. sp.";
# 	}

# 	my $fields = ['max_interval_no','min_interval_no','collection_no','collection_name','country','state','geogscale','formation','member','stratscale','lithification','minor_lithology','lithology1','lithification2','minor_lithology2','lithology2','environment'];

# 	if ( ! $q->param('Africa') || ! $q->param('Antarctica') || ! $q->param('Asia') || ! $q->param('Australia') || ! $q->param('Europe') || ! $q->param('North America') || ! $q->param('South America') )	{
# 		for my $c ( 'Africa','Antarctica','Asia','Australia','Europe','North America','South America' )	{
# 			if ( $q->param($c) )	{
# 				$options{'country'} .= ":".$c;
# 			}
# 		}
# 		$options{'country'} =~ s/^://;
# 	}

# 	my (@in_list);
# 	push @in_list , $_->{'taxon_no'} foreach @subtaxa;

# 	$options{'permission_type'} = 'read';
# 	$options{'taxon_list'} = \@in_list;
# 	$options{'geogscale'} = $q->param('geogscale');
# 	$options{'stratscale'} = $q->param('stratscale');
# 	if ( $q->param('minimum_age') > 0 )	{
# 		$options{'max_interval'} = 999;
# 		$options{'min_interval'} = $q->param('minimum_age');
# 	}

# 	my ($colls) = PBDB::Collection::getCollections($dbt,$s,\%options,$fields);
# 	if ( ! @$colls )	{
# 		my $error_message = "No occurrences of $name match the search criteria";
# 		beginFirstAppearance($hbo,$q,$error_message);
# 	}

# 	my @intervals = intervalData($dbt,$colls);
# 	my %interval_hash;
# 	$interval_hash{$_->{'interval_no'}} = $_ foreach @intervals;

# 	if ( $q->param('temporal_precision') )	{
# 		my @newcolls;
#         	for my $coll (@$colls) {
# 			if ( $interval_hash{$coll->{'max_interval_no'}}->{'base_age'} -  $interval_hash{$coll->{'max_interval_no'}}->{'top_age'} <= $q->param('temporal_precision') )	{
# 				push @newcolls , $coll;
# 			}
# 		}
# 		@$colls = @newcolls;
# 	}
# 	if ( ! @$colls )	{
# 		my $error_message = "No occurrences of $name have sufficiently precise age data";
# 		beginFirstAppearance($hbo,$q,$error_message);
# 	}
# 	my $ncoll = scalar(@$colls);

# 	$output .= "<div style=\"text-align: center\"><p class=\"medium pageTitle\">First appearance data for $name $authors</p></div>\n";
# 	$output .= "<div class=\"small\" style=\"padding-left: 2em; padding-right: 2em;  padding-bottom: 4em;\">\n";

# 	if ( $#nos == 1 )	{
# 		$output .= "<p class=\"small\">Warning: a different but smaller taxon in the system has the name $name.</p>";
# 	} elsif ( $#nos > 1 )	{
# 		$output .= "<p class=\"small\">Warning: $#nos smaller taxa in the system have the name $name.</p>";
# 	}

# 	$output .= "<div class=\"displayPanel\">\n<span class=\"displayPanelHeader\" style=\"font-size: 1.2em;\">Basic data</span>\n<div class=\"displayPanelContents\">\n";

# 	# CROWN GROUP CALCULATION

# 	if ( $extant =~ /yes/i )	{
# 		my $crown = findCrown(\@allsubtaxa);
# 		if ( $crown =~ /^[A-Z][a-z]*$/)	{
# 			my @params = $q->param();
# 			my $paramlist;
# 			for my $p ( $q->param() )	{
# 				if ( $q->param($p) && $p ne "taxon_name" && $p ne "common_name" )	{
# 					$paramlist .= "&amp;".$p."=".$q->param($p);
# 				}
# 			}
# 			$output .= "<p>The crown group of $name is <a href=\"$$$?taxon_name=$crown$paramlist\">$crown</a> (click to compute its first appearance)</p>\n";
# 		} elsif ( ! $crown )	{
# 			my $exclude = "";
# 			if ( $q->param('exclude') )	{
# 				$exclude = " other than the ones you excluded";
# 			}
# 			$output .= "<p><i>$name has no subtaxa marked in our system as extant$exclude, so its crown group cannot be determined</i></p>\n";
# 		} else	{
# 			$crown =~ s/(,)([A-Z][a-z ]*)$/ and $2/;
# 			$crown =~ s/,/, /g;
# 			$output .= "<p style=\"padding-left: 1em; text-indent: -1em;\"><i>$name is the immediate parent of the extant $crown, so it is itself a crown group</i></p>\n";
# 		}
# 	} else	{
# 		$output .= "<p><i>$name is entirely extinct, so it has no crown group</i></p>\n";
# 	}

# 	# AGE RANGE/CONFIDENCE INTERVAL CALCULATION

# 	my ($lb,$ub,$max_no,$minfirst,$min_no) = getAgeRange($dbt,$colls);
# 	my ($first_interval_top,@firsts,@rages,@ages,@gaps);
# 	my $TRIALS = int( 10000 / scalar(@$colls) );
#         for my $coll (@$colls) {
# 		my ($collmax,$collmin,$last_name) = ("","","");
# 		$collmax = $interval_hash{$coll->{'max_interval_no'}}->{'base_age'};
# 		# IMPORTANT: the collection's max age is truncated at the
# 		#   taxon's max first appearance
# 		if ( $collmax > $lb )	{
# 			$collmax = $lb;
# 		}
# 		if ( $coll->{'min_interval_no'} == 0 )	{
# 			$collmin = $interval_hash{$coll->{'max_interval_no'}}->{'top_age'};
# 			$last_name = $interval_hash{$coll->{'max_interval_no'}}->{'interval_name'};
# 		} else	{
# 			$collmin = $interval_hash{$coll->{'min_interval_no'}}->{'top_age'};
# 			$last_name = $interval_hash{$coll->{'min_interval_no'}}->{'interval_name'};
# 		}
# 		$coll->{'maximum Ma'} = $collmax;
# 		$coll->{'minimum Ma'} = $collmin;
# 		$coll->{'midpoint Ma'} = ( $collmax + $collmin ) / 2;
# 		if ( $minfirst == $collmin )	{
# 			if ( $coll->{'state'} && $coll->{'country'} eq "United States" )	{
# 				$coll->{'country'} = "US (".$coll->{'state'}.")";
# 			}
# 			$first_interval_top = $last_name;
# 			push @firsts , $coll;
# 		}
# 	# randomization to break ties and account for uncertainty in
# 	#  age estimates
# 		for my $t ( 1..$TRIALS )	{
# 			push @{$rages[$t]} , rand($collmax - $collmin) + $collmin;
# 		}
# 	}

# 	my $first_interval_base = $interval_hash{$max_no}->{interval_name};
# 	my $last_interval = $interval_hash{$min_no}->{interval_name};
# 	if ( $first_interval_base =~ /an$/ )	{
# 		$first_interval_base = "the ".$first_interval_base;
# 	}
# 	if ( $first_interval_top =~ /an$/ )	{
# 		$first_interval_top = "the ".$first_interval_top;
# 	}
# 	if ( $last_interval =~ /an$/ )	{
# 		$last_interval = "the ".$last_interval;
# 	}

# 	my $agerange = $lb - $ub;;
# 	if ( $q->param('minimum_age') > 0 )	{
# 		$agerange = $lb - $q->param('minimum_age');
# 	}
# 	for my $t ( 1..$TRIALS )	{
# 		@{$rages[$t]} = sort { $b <=> $a } @{$rages[$t]};
# 	}
# 	for my $i ( 0..$#{$rages[1]} )	{
# 		my $x = 0;
# 		for my $t ( 1..$TRIALS )	{
# 			$x += $rages[$t][$i];
# 		}
# 		push @ages , $x / $TRIALS;
# 	}
# 	for my $i ( 0..$#ages-1 )	{
# 		push @gaps , $ages[$i] - $ages[$i+1];
# 	}
# 	# shortest to longest
# 	@gaps = sort { $a <=> $b } @gaps;

# 	# AGE RANGE/CI OUTPUT

# 	if ( $options{'country'} )	{
# 		my $c = $options{'country'};
# 		$c =~ s/:/, /g;
# 		$c =~ s/(, )([A-Za-z ]*)$/ and $2/;
# 		$output .= "<p>Continents: $c</p>\n";
# 	}

# 	$output .= sprintf "<p>Maximum first appearance date: bottom of $first_interval_base (%.1f Ma)</p>\n",$lb;
# 	$output .= sprintf "<p>Minimum first appearance date: top of $first_interval_top (%.1f Ma)</p>\n",$minfirst;
# 	if ( $extant eq "no" )	{
# 		$output .= sprintf "<p>Minimum last appearance date: top of $last_interval (%.1f Ma)</p>\n",$ub;
# 	}
# 	$output .= "<p>Total number of collections: $ncoll</p>\n";
# 	$output .= sprintf "<p>Collections per Myr between %.1f and %.1f Ma: %.2f</p>\n",$lb,$lb - $agerange,$ncoll / $agerange;
# 	if ( $ncoll > 1 )	{
# 		$output .= sprintf "<p>Average gap between collections: %.2f Myr</p>\n",$agerange / ( $ncoll - 1 );
# 		$output .= sprintf "<p>Gap between two oldest collections: %.2f Myr</p>\n",$ages[0] - $ages[1];
# 	}

# 	$output .= "</div>\n</div>\n\n";

# 	# begin more-than-one collection calculations
# 	if ( $ncoll > 1 )	{
# 	$output .= "<div class=\"displayPanel\" style=\"margin-top: 2em;\">\n<span class=\"displayPanelHeader\" style=\"font-size: 1.2em;\">Confidence intervals on the first appearance</span>\n<div class=\"displayPanelContents\">\n";

# 	$output .= "<div style=\"margin-left: 1em;\">\n";

# 	$output .= sprintf "<p style=\"text-indent: -1em;\">Based on assuming continuous sampling (Strauss and Sadler 1987, 1989): 50%% = %.2f Ma, 90%% = %.2f Ma, 95%% = %.2f Ma, and 99%% = %.2f Ma<br>\n",Strauss(0.50),Strauss(0.90),Strauss(0.95),Strauss(0.99);

# 	$output .= sprintf "<p style=\"text-indent: -1em;\">Based on percentiles of gap sizes (Marshall 1994): 50%% = %s, 90%% = %s, 95%% = %s, and 99%% = %s<br>\n",percentile(0.50),percentile(0.90),percentile(0.95),percentile(0.99);

# 	$output .= sprintf "<p style=\"text-indent: -1em;\">Based on the oldest gap (Solow 2003): 50%% = %.2f Ma, 90%% = %.2f Ma, 95%% = %.2f Ma, and 99%% = %.2f Ma<br>\n",Solow(0.50),Solow(0.90),Solow(0.95),Solow(0.99);

# 	$output .= "<div id=\"note_link\" class=\"small\" style=\"margin-bottom: 1em; padding-left: 1em;\"><span class=\"mockLink\" onClick=\"document.getElementById('CI_note').style.display='inline'; document.getElementById('note_link').style.display='none';\"> > <i>Important: please read the explanatory notes.</span></i></div>\n";
# 	$output .= qq|<div id="CI_note" style="display: none;"><div class="small" style="margin-left: 1em; margin-right: 2em; background-color: ghostwhite;">
# <p style="margin-top: 0em;">All three confidence interval (CI) methods assume that there are no errors in identification, classification, temporal correlation, or time scale calibration. Our database is founded on published literature that often contains such errors, and we are not always able to correct them although (for example) we standardize taxonomy using synonymy tables. Our sampling of the literature is also variably complete, and it may not include all published early occurrences.</p>
# <p>The first CI two methods also assume that distribution of gap sizes does not change through time. The Strauss and Sadler method assumes more specifically that the gaps are randomly placed in time, so they follow a Dirichlet distribution. The percentile-based estimates assume nothing about the underlying distribution. They are computed by rank-ordering the N observed gaps and taking the average of the two gaps that span the percentile matching the appropriate CI (see Marshall 1994). These are gaps k and k + 1 where k < (1 - CI) N < k + 1. So, if there are 100 gaps then the 95% CI matches the 5th longest.</p>
# <p style="margin-bottom: 0em;">Intuitively, it might seem that percentiles underestimate the CIs when sample sizes are small. Marshall (1994) therefore proposed generating CIs on top of the nonparametric CIs. The CIs on CIs express the chance that 1 to k gaps are longer than 1 - CI' of all possible gaps, CI and CI' potentially being different (say, 50% and 5%). However, possible gaps are not of interest: one wants to know about a single real gap in the fossil record. The chance that 1 to k gaps are longer than this record is just k/N, the original CI. Therefore, CIs based on Marshall's method are not reported here.</p>
# <p>Solow's method has a computational problem: the size of the oldest gap cannot be computed when the oldest occurrences have the same range of age estimates (because they fall in the same geological time interval). To break ties, the point age estimate of each collection is randomized repeatedly within its age range to produce an average estimate of the oldest gap's size. The same randomization procedure is applied to all age estimates prior to computing the above-mentioned percentiles. The raw and randomized values are both reported in the download file.
# </p>
# </div></div></div>
# |;

# 	# TIME VS. GAP SIZE TEST

# 	# convert to ranks by manipulating an array of objects
# 	my @gapdata;
# 	for my $i ( 0..$#ages-1 )	{
# 		$gapdata[$i]->{'age'} = $ages[$i];
# 		$gapdata[$i]->{'gap'} = $ages[$i] - $ages[$i+1];
# 	}
# 	@gapdata = sort { $b->{'age'} <=> $a->{'age'} } @gapdata;
# 	for my $i ( 0..$#ages-1 )	{
# 		$gapdata[$i]->{'agerank'} = $i;
# 	}
# 	@gapdata = sort { $b->{'gap'} <=> $a->{'gap'} } @gapdata;
# 	for my $i ( 0..$#ages-1 )	{
# 		$gapdata[$i]->{'gaprank'} = $i;
# 	}

# 	my ($n,$mx,$my,$sx,$sy,$cov);
# 	$n = $#ages;
# 	if ( $n > 9 )	{
# 		for my $i ( 0..$#ages-1 )	{
# 			$mx += $gapdata[$i]->{'agerank'};
# 			$my += $gapdata[$i]->{'gaprank'};
# 		}
# 		$mx /= $n;
# 		$my /= $n;
# 		for my $i ( 0..$#ages-1 )	{
# 			$sx += ($gapdata[$i]->{'agerank'} - $mx)**2;
# 			$sy += ($gapdata[$i]->{'gaprank'} - $my)**2;
# 			$cov += ($gapdata[$i]->{'agerank'} - $mx) * ( $gapdata[$i]->{'gaprank'} - $my);
# 		}
# 		$sx = sqrt( $sx / ( $n - 1 ) );
# 		$sy = sqrt( $sy / ( $n - 1 ) );
# 		my $r = $cov / ( ( $n - 1 ) * $sx * $sy );
# 		my $t = $r / sqrt( ( 1 - $r**2 ) / ( $n - 2 ) );
# 	# for n > 9, the p < 0.001 critical values range from 3.291 to 4.587
# 		my ($direction,$size) = ("positive","small");
# 		if ( $r < 0 )	{
# 			$direction = "negative";
# 			$size = "large";
# 		}
# 		if ( $t > 3.291 )	{
# 			$output .= sprintf "<p style=\"padding-left: 1em; text-indent: -1em;\">WARNING: there is a very significant $direction rank-order correlation of %.3f between time in Myr and gap size, so the continuous sampling- and percentile-based confidence interval estimates are far too small (try setting a higher minimum age)</p>\n",$r;
# 	# and the p < 0.01 values range from 2.576 to 3.169
# 		} elsif ( $t > 2.576 )	{
# 			$output .= sprintf "<p style=\"padding-left: 1em; text-indent: -1em;\">WARNING: there is a significant $direction rank-order correlation of %.3f between time in Myr and gap size, so the continuous sampling- and percentile-based confidence interval estimates are too small (try setting a higher minimum age)</p>\n",$r;
# 	# and the p < 0.05 values range from 1.960 to 2.228
# 		} elsif ( $t > 1.960 )	{
# 			$output .= sprintf "<p style=\"padding-left: 1em; text-indent: -1em;\">WARNING: there is a $direction rank-order correlation of %.3f between time in Myr and gap size, so the continuous sampling- and percentile-based confidence interval estimates are probably too small (try setting a higher minimum age)</p>\n",$r;
# 		}
# 	}

# 	# CI COMPUTATIONS

# 	sub percentile	{
# 		my $c = shift;
# 		my $i = int($c * ( $#gaps + 1 ) );
# 		my $j = $i + 1;
# 		if ( $i == $c * ( $#gaps + 1 ) )	{
# 			$j = $i;
# 		}
# 		if ( $j > $#gaps )	{
# 			return "NA";
# 		}
# 		return sprintf "%.2f Ma",( $lb + ( $gaps[$i] + $gaps[$j] ) / 2 );
# 	}

# 	sub Strauss	{
# 		my $c = shift;
# 		return $lb * ( ( 1 - $c )**( -1 /( $ncoll - 1 ) ) );
# 	}

# 	sub Solow	{
# 		my $c = shift;
# 		return $lb + ( $c / ( 1 - $c ) ) * ( $ages[0] - $ages[1] );
# 	}

# # Bayesian CIs can computed using an equation related to Marshall's, but it yields CIs that are identical to percentiles converted from ranks.
# # Let t = the true gap in Myr between the oldest fossil and the actual first appearance, X = the overall distribution of possible gaps, Y = the observed gap size distribution, N = the number of observed gaps, and s = a possible percentile score of t within X.
# # We will evaluate only N equally spaced values of s between 0 and 100%.
# # We want the posterior probability that t is between the kth and k+1th values out of N for each value of k.
# # We will sum the probabilities to find the 50, 90, 95, and 99% CIs.
# # For each k we find the conditional probability Pk,i that exactly k out of N observations will be greater than t given that t's percentile score is closest to the ith s value, which is simply a binomial probability (see Marshall 1994).
# # Instead of summing across possible values of k, which would yield 1 for each value of i, we sum the conditionals across values of i (which by definition have equal priors) to produce a total tail probability for each k.
# # The grand total across all values of k is just N.
# # The posterior probability of each k is therefore its sum divided by N.
# # This method yields equal posteriors for all possible ranks, justifying transformation of ranks into percentiles.
# 	#BayesCI(10);
# 	sub BayesCI	{
# 		my $n = shift;

# 		my %fact = ();
# 		for my $i ( 1..$n )	{
# 			$fact{$i} = $fact{$i-1} + log( $i );
# 		}

# 		for my $k ( 0..int($n/1) )	{
# 			my $conditional = 0;
# 			for my $i ( 1..$n+1 )	{
# 				my $p = ( $i - 0.5 ) / ( $n + 1 );
# 				my $kp = $k * log( $p ) + ( $n - $k ) * log( 1 - $p );
# 				$kp += $fact{$n};
# 				$kp -= $fact{$k};
# 				$kp -= $fact{$n - $k};
# 				$conditional += exp( $kp );
# 			}
# 			my $posterior = $conditional / ( $n + 1 );
# 			#printf "$k %.3f<br>",$posterior;
# 		}
# 	}
# 	$output .= "</div>\n</div>\n\n";

# 	} # end more-than-one collection calculations

# 	# COLLECTION DATA OUTPUT

# 	$output .= "<div class=\"displayPanel\" style=\"margin-top: 2em;\">\n<span class=\"displayPanelHeader\" style=\"font-size: 1.2em;\">First occurrence details</span>\n<div class=\"displayPanelContents\">\n";

# 	# getCollections won't return multiple occurrences per collection, so...
# 	my @collnos;
# 	push @collnos , $_->{'collection_no'} foreach @$colls;
# 	my $reso = '';
# 	# not returning occurrences means that getCollections can't apply this
# 	#  filter consistently
# 	if ( $q->param('types_only') =~ /yes/i )	{
# 		$reso = " AND species_reso='n. sp.'";
# 	}
# 	$sql = "(SELECT r.taxon_no,taxon_name,taxon_rank,collection_no,occurrence_no,reid_no FROM reidentifications r,$TAXA_TREE_CACHE t,authorities a WHERE r.taxon_no=t.taxon_no AND t.taxon_no=a.taxon_no AND lft>=$nos[0]->{'lft'} AND rgt<=$nos[0]->{'rgt'} AND collection_no IN (".join(',',@collnos).") AND r.taxon_no IN (".join(',',@in_list).") AND most_recent='YES'$reso GROUP BY collection_no,r.taxon_no) UNION (SELECT o.taxon_no,taxon_name,taxon_rank,collection_no,occurrence_no,0 FROM occurrences o,$TAXA_TREE_CACHE t,authorities a WHERE o.taxon_no=t.taxon_no AND t.taxon_no=a.taxon_no AND lft>=$nos[0]->{'lft'} AND rgt<=$nos[0]->{'rgt'} AND collection_no IN (".join(',',@collnos).") AND o.taxon_no IN (".join(',',@in_list).")$reso GROUP BY collection_no,o.taxon_no)";
# 	my @occs = @{$dbt->getData($sql)};

# 	# impose synonymy mask, but only for taxa with occurrences JA 31.10.09
# 	my (%hasocc,%senior_name);
# 	$hasocc{$_->{taxon_no}}++ foreach @occs;
# 	$sql = "SELECT t.taxon_no,taxon_name FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=synonym_no AND t.taxon_no IN (" . join(',',keys %hasocc) . ")";
# 	$senior_name{$_->{'taxon_no'}} = $_->{'taxon_name'} foreach @{$dbt->getData($sql)};

# 	# print data to output file JA 17.1.09
# 	my $name = ($s->get("enterer")) ? $s->get("enterer") : "Guest";
# 	my $filename = PBDB::PBDBUtil::getFilename($name) . "-appearances.txt";;
# 	$output .= "<p><a href=\"/public/downloads/$filename\">Download the full data set</a></p>\n\n";
# 	open OUT , ">$HTML_DIR/public/downloads/$filename";
# 	@$colls = sort { $b->{'midpoint Ma'} <=> $a->{'midpoint Ma'} || $b->{'maximum Ma'} <=> $a->{'maximum Ma'} || $b->{'minimum Ma'} <=> $a->{'minimum Ma'} || $a->{'country'} cmp $b->{'country'} || $a->{'state'} cmp $b->{'state'} || $a->{'formation'} cmp $b->{'formation'} || $a->{'collection_name'} cmp $b->{'collection_name'} } @$colls;
# 	splice @$fields , 0 , 2 , ('maximum Ma','minimum Ma','midpoint Ma','randomized Ma','randomized gap','taxa');
# 	print OUT join("\t",@$fields),"\n";

# 	my %ids;
# 	$ids{$_->{'occurrence_no'}}++ foreach @occs;

# 	my %includes;
# 	for $_ ( @occs )	{
# 		if ( $ids{$_->{'occurrence_no'}} == 1 || $_->{'reid_no'} > 0 )	{	
# 			push @{$includes{$_->{'collection_no'}}} , $senior_name{$_->{'taxon_no'}};
# 		}
# 	}

# 	for my $i ( 0..scalar(@$colls)-1 )	{
# 		my $coll = $$colls[$i];
# 		$coll->{'randomized Ma'} = $ages[$i];
# 		if ( $i < scalar(@$colls) - 1 )	{
# 			$coll->{'randomized gap'} = $ages[$i] - $ages[$i+1];
# 		# this transform should standardized the gap sizes if indeed
# 		#  the sampling probability falls exponentially through time
# 		#  (which it generally does not do cleanly)
# 			#$coll->{'randomized gap'} = log((1/$coll->{'randomized gap'})*$ages[$i]);
# 		} else	{
# 			$coll->{'randomized gap'} = "NA";
# 		}
# 		my %seen;
# 		$seen{$_}++ foreach @{$includes{$coll->{'collection_no'}}};
# 		$coll->{'taxa'} = join(', ',keys %seen);
# 		$coll->{'taxa'} =~ s/  / /g;
# 		$coll->{'taxa'} =~ s/  / /g;
# 		$coll->{'taxa'} =~ s/^ //g;
# 		$coll->{'taxa'} =~ s/ $//g;
# 		$coll->{'taxa'} =~ s/ ,/,/g;
# 		for my $f ( @$fields )	{
# 			my $val = $coll->{$f};
# 			if ( $coll->{$f} =~ / / )	{
# 				$val = '"'.$val.'"';
# 			}
# 			if ( $f =~ /randomized/ && $coll->{$f} ne "NA" )	{
# 				printf OUT "%.3f",$coll->{$f};
# 			} elsif ( $coll->{$f} =~ /^[0-9]+(\.|)[0-9]*$/ && $f !~ /_no$/ )	{
# 				printf OUT "%.2f",$coll->{$f};
# 			} else	{
# 				print OUT "$val";
# 			}
# 			if ( $$fields[scalar(@$fields)-1] eq $f )	{
# 				print OUT "\n";
# 			} else	{
# 				print OUT "\t";
# 			}
# 		}
# 	}

# 	for my $o ( @occs )	{
# 		if ( $o->{'taxon_rank'} =~ /genus|species/ )	{
# 			$o->{'taxon_name'} = "<i>".$o->{'taxon_name'}."</i>";
# 		}
# 	}

# 	if ( $#firsts == 0 )	{
# 		if ( $firsts[0]->{'formation'} )	{
# 			$firsts[0]->{'formation'} .= " Formation ";
# 		}
# 		my $agerange = $interval_hash{$firsts[0]->{'max_interval_no'}}->{'interval_name'};
# 		if ( $firsts[0]->{'min_interval_no'} > 0 )	{
# 			$agerange .= " - ".$interval_hash{$firsts[0]->{'min_interval_no'}}->{'interval_name'};
# 		}
# 		my @includes;
# 		for my $o ( @occs )	{
# 			if ( $o->{'collection_no'} == $firsts[0]->{'collection_no'} && ( $ids{$o->{'occurrence_no'}} == 1 || $o->{'reid_no'} > 0 ) )	{
# 				push @includes , $o->{'taxon_name'};
# 			}
# 		}
# 		$output .= "<p style=\"padding-left: 1em; text-indent: -1em;\">The collection documenting the first appearance is ";
# 		$output .= makeAnchor("basicCollectionSearch", "collection_no=$firsts[0]{collection_no}", $firsts[0]{collection_name});
# 		$output .= " ($agerange $firsts[0]{formation} of $firsts[0]{country}: includes ".join(', ',@includes).")</p>\n";
# 	} else	{
# 		@firsts = sort { $a->{'collection_name'} cmp $b->{'collection_name'} } @firsts;
# 		$output .= "<p class=\"large\" style=\"margin-bottom: -1em;\">Collections including first appearances</p>\n";
# 		$output .= "<table cellpadding=\"0\" cellspacing=\"0\" style=\"padding: 1.5em;\">\n";
# 		my @fields = ('collection_no','collection_name','country','formation');
# 		$output .= "<tr valign=\"top\">\n";
# 		for my $f ( @fields )	{
# 			my $fn = $f;
# 			$fn =~ s/^[a-z]/\U$&/;
# 			$fn =~  s/_/ /g;
# 			$fn =~ s/ no$//;
# 			$output .= "<td><div style=\"padding: 0.5em;\">$fn</div></td>\n";
# 		}
# 		$output .= "<td style=\"padding: 0.5em;\">Age (Ma)</td>\n";
# 		$output .= "</tr>\n";
# 		my $i;
# 		for my $coll ( @firsts )	{
# 			$i++;
# 			my $classes = (($#firsts > 1) && ($i/2 > int($i/2))) ? qq|"small darkList"| : qq|"small"|;
# 			$output .= "<tr valign=\"top\" class=$classes style=\"padding: 3.5em;\">\n";
# 			my $collno = $coll->{'collection_no'};
# 			$coll->{'collection_no'} = "&nbsp;&nbsp;" .
# 			    makeAnchor("basicCollectionSearch", "collection_no=$coll->{collection_no}", $coll->{collection_no});
# 			if ( $coll->{'state'} && $coll->{'country'} eq "United States" )	{
# 				$coll->{'country'} = "US (".$coll->{'state'}.")";
# 			}
# 			if ( ! $coll->{'formation'} )	{
# 				$coll->{'formation'} = "-";
# 			}
# 			for my $f ( @fields )	{
# 				$output .= "<td style=\"padding: 0.5em;\">$coll->{$f}</td>\n";
# 			}
# 			$output .= sprintf "<td style=\"padding: 0.5em;\">%.1f to %.1f</td>\n",$interval_hash{$coll->{'max_interval_no'}}->{'base_age'},$interval_hash{$coll->{'max_interval_no'}}->{'top_age'};
# 			$output .= "</tr>\n";
# 			my @includes = ();
# 			for my $o ( @occs )	{
# 				if ( $o->{'collection_no'} == $collno && ( $ids{$o->{'occurrence_no'}} == 1 || $o->{'reid_no'} > 0 ) )	{
# 					push @includes , $o->{'taxon_name'};
# 				}
# 			}
# 			$output .= "<tr valign=\"top\" class=$classes><td></td><td style=\"padding-bottom: 0.5em;\" colspan=\"6\">includes ".join(', ',@includes)."</td></tr>\n";
# 		}
# 		$output .= "</table>\n\n";
# 	}
# 	$output .= "</div>\n</div>\n";

# 	$output .= "<div style=\"padding-left: 6em;\">";
# 	$output .= makeAnchor("beginFirstAppearance", "", "Search again") . " - ";
# 	$output .= makeAnchor("displayTaxonInfoResults", "taxon_no=$nos[0]{taxon_no}", "See more details about $name") . "</div>\n";
# 	$output .= "</div>\n";

# 	return $output;
# }

# JA 13.1.09
# fast simple algorithm for finding the crown group within any higher taxon
# the crown is the least nested taxon that has multiple direct, extant children
# sub findCrown	{

# 	$_ = shift;
# 	my @taxa = @{$_};
# 	@taxa = sort { $a->{'lft'} <=> $b->{'lft'} } @taxa;
# 	# there may be bogus variants of the overall group
# 	while ( $taxa[0]->{'taxon_no'} != $taxa[0]->{'synonym_no'} )	{
# 		shift @taxa;
# 	}

# 	# first pass: correctly mark all extant taxa
# 	my @ps = (0);
# 	my @isextant;
# 	# we assume taxon 0 is the overall group, so skip it
# 	for my $i ( 1..$#taxa )	{
# 		if ( $taxa[$i]->{'taxon_no'} == $taxa[$i]->{'synonym_no'} && ( $taxa[$i]->{'taxon_rank'} =~ /genus|species/ || $taxa[$i]->{'lft'} < $taxa[$i]->{'rgt'} - 1 ) )	{
# 			while ( $taxa[$ps[$#ps]]->{'rgt'} < $taxa[$i]->{'lft'} && @ps )	{
# 				pop @ps;
# 			}
# 			if ( $taxa[$i]->{'extant'} =~ /yes/i )	{
# 				$isextant[$i]++;
# 				$isextant[$_]++ foreach @ps;
# 			}
# 			push @ps , $i;
# 		}
# 	}

# 	# second pass: count extant immediate children of each taxon
# 	@ps = (0);
# 	my @children;
# 	for my $i ( 1..$#taxa )	{
# 		if ( $taxa[$i]->{'taxon_no'} == $taxa[$i]->{'synonym_no'} && ( $taxa[$i]->{'taxon_rank'} =~ /genus|species/ || $taxa[$i]->{'lft'} < $taxa[$i]->{'rgt'} - 1 ) )	{
# 			while ( $taxa[$ps[$#ps]]->{'rgt'} < $taxa[$i]->{'lft'} && @ps )	{
# 				pop @ps;
# 			}
# 			if ( $isextant[$i] > 0 )	{
# 				push @{$children[$ps[$#ps]]} , $i;
# 			}
# 			push @ps , $i;
# 		}
# 	}

# 	if ( $#{$children[0]} > 0 )	{
# 		my @names;
# 		@{$children[0]} = sort { $taxa[$a]->{'taxon_name'} cmp $taxa[$b]->{'taxon_name'} } @{$children[0]};
# 		push @names , $taxa[$_]->{'taxon_name'} foreach @{$children[0]};
# 		return join(',',@names);
# 	} elsif ( $#{$children[0]} < 0 )	{
# 		return "";
# 	} else	{
# 		my $t = ${$children[0]}[0];
# 		while ( $#{$children[$t]} == 0 )	{
# 			$t = ${$children[$t]}[0];
# 		}
# 		return $taxa[$t]->{'taxon_name'};
# 	}

# }


# JA 3-5.11.09
sub basicTaxonInfo {

    my ($q,$s,$dbt,$hbo) = @_;

    my $output = '';
    my $dbh = $dbt->dbh;
    
    my ($is_real_user,$not_bot) = (1,1);
    
    if (! $q->request_method() eq 'POST' && ! $q->param('is_real_user') && ! $s->isDBMember())
    {
	$is_real_user = 0;
	$not_bot = 0;
    }
    
    if (PBDB::PBDBUtil::checkForBot())
    {
	$is_real_user = 0;
	$not_bot = 0;
    }
    
    # if ( $is_real_user > 0 )	{
    # 	PBDB::logRequest($s,$q);
    # }
    
    # reuses some old checkTaxonInfo functionality JA 8.4.12
    if ( $q->param('match') =~ /all|random/i )
    {
	my @taxon_nos = @{getMatchingSubtaxa($dbt,$q,$s,$hbo)};
	if ( scalar @taxon_nos > 1 )	{
	    return listTaxonChoices($dbt,$hbo,\@taxon_nos,1);
	}
    }

    my $taxon_name = $q->param('taxon_name');
    
    if ( ! $taxon_name && $q->param('quick_search') )
    {
	$taxon_name = $q->param('quick_search');
    }
    
    elsif ( ! $taxon_name && $q->param('search_again') )
    {
	$taxon_name = $q->param('search_again');
    }
    
    elsif ( ! $taxon_name && $q->param('common_name') )
    {
	$taxon_name = $q->param('common_name');
    }
    
    $taxon_name =~ s/ sp(p|)\.$//;

    my $indent = 'style="padding-left: 1em; text-indent: -1em;"';
    
    # TRY TO GET TAXON NUMBER
    
    my $error;
    my $taxon_no;
    
    if ( $q->numeric_param('taxon_no') )
    {
	$taxon_no = $q->numeric_param('taxon_no');
	$taxon_no = getSeniorSynonym($dbt,$taxon_no); 
    }
    
    elsif ( $q->param('author') || $q->param('pubyr') || $q->param('type_body_part') || $q->param('preservation') )
    {
	my @taxon_nos = getTaxonNos($dbt,$taxon_name,'','',$q->param('author'),$q->param('pubyr'),$q->param('type_body_part'),$q->param('preservation'));
	
	if ( scalar @taxon_nos == 1 )
	{
	    $taxon_no = getSeniorSynonym($dbt,$taxon_nos[0]); 
	}
	
	elsif ( scalar @taxon_nos > 1 )
	{
	    $output .= listTaxonChoices($dbt,$hbo,\@taxon_nos,1);
	}
	
	else
	{
	    $error = "<center>Nothing matching your search is in the database. Please try again.</center>";
	    $taxon_name = "Failed search!";
	}
    }
    
    elsif ( $taxon_name )
    {
	$taxon_name =~ s/ sp\.//;
	$taxon_name =~ s/\./%/g;
	
	# used in preference to getTaxa because the query is dead simple
	my @taxon_nos = getTaxonNos($dbt,$taxon_name,'','',$q->param('author'),$q->param('pubyr'),$q->param('type_body_part'),$q->param('preservation'));
	
	# genus name might be salvageable
	if ( ! @taxon_nos && $taxon_name =~ /[a-z%] [a-z%]/i )
	{
	    my ($g,$s) = split / /,$taxon_name;
	    @taxon_nos = getTaxonNos($dbt,$g);
	}
	
	# if the name is misformatted it could only be a common name,
	#  so try that
	
	if ( ! @taxon_nos && $taxon_name !~ /^[A-za-z]* [A-Za-z]*$/ || $q->param('common_name') =~ /[A-Za-z]/ )
	{
	    my $name = $taxon_name;
	    $name =~ s/[^A-Za-z ]/%/g;
	    my $sql = "SELECT taxon_no FROM authorities WHERE common_name LIKE '".$name."'";
	    push @taxon_nos , ${$dbt->getData($sql)}[0]->{'taxon_no'};
	    if ( ! @taxon_nos )	{
		$error = "<center>WARNING: '".$taxon_name."' is not in the database. Please search again.</center>";
	    }
	}
	
	if ( $taxon_nos[0] eq "" )
	{
	    @taxon_nos = ();
	}
	
	# the name may be bona fide but completely unclassified, so
	#  see if it has occurrences
	
	my $occ;
	
	if ( ! @taxon_nos && $error eq "" )
	{
	    my ($g,$s) = split / /,$taxon_name;
	    my $name_clause = "genus_name='".$g."'";
	    my $name_clause = "(genus_name='".$g."' OR subgenus_name='".$g."')";
	    
	    if ( $s )
	    {
		$name_clause .= " AND species_name='".$s."'";
	    }
	    
	    my $sql = "SELECT count(*) c FROM occurrences WHERE $name_clause";
	    
	    $occ = ${$dbt->getData($sql)}[0];
	    
	    if ( ! $occ )
	    {
		$sql = "SELECT count(*) c FROM reidentifications WHERE $name_clause";
		$occ = ${$dbt->getData($sql)}[0];
	    }
	}
	
	if ( ! @taxon_nos && $q->param('last_taxon') > 0 && ! $occ )
	{
	    $taxon_no = $q->param('last_taxon');
	    $error = "<center>WARNING: '".$taxon_name."' is not in the database. Please search again.</center>";
	}
	
	elsif ( ! @taxon_nos && ! $occ )
	{
	    my $rank_clause = "AND taxon_rank='species'";
	    if ( $taxon_name !~ / / )
	    {
		$rank_clause = "AND taxon_rank!='species'";
	    }
	    
	    # first try matching only on consonants, which works
	    #  well for long names
	    my $wild = $taxon_name;
	    my $length = length($wild);
	    $wild =~ s/[aeiou]/%/g;
	    my $quoted_wild = $dbh->quote($wild);
	    my $sql = "SELECT a.taxon_no,taxon_name,taxon_rank FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND length(taxon_name)>=$length-1 AND length(taxon_name)<=$length+1 AND taxon_name LIKE $quoted_wild $rank_clause ORDER BY rgt-lft DESC";
	    my $guess = ${$dbt->getData($sql)}[0];
	    # now try first letter plus vowels
	    
	    if ( ! $guess )
	    {
		$wild = $taxon_name;
		$wild =~ s/[^A-Zaeiou]/%/g;
		my $quoted_wild = $dbh->quote($wild);
		$sql = "SELECT a.taxon_no,taxon_name,taxon_rank FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND length(taxon_name)>=$length-1 AND length(taxon_name)<=$length+1 AND taxon_name LIKE $quoted_wild $rank_clause ORDER BY rgt-lft DESC";
		$guess = ${$dbt->getData($sql)}[0];
	    }
	    
	    # we're desperate, so try whittling down the name
	    $wild = $taxon_name;
	    while ( ! $guess && length( $wild ) > 3 )
	    {
		$wild =~ s/.$//;
		my $quoted_wild = $dbh->quote($wild);
		$sql = "SELECT a.taxon_no,taxon_name,taxon_rank FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND taxon_name LIKE $quoted_wild $rank_clause ORDER BY rgt-lft DESC";
		$guess = ${$dbt->getData($sql)}[0];
	    }
	    
	    $taxon_no = $guess->{'taxon_no'};
	    $taxon_no = getSeniorSynonym($dbt,$taxon_no); 
	    $error = "<cneter>WARNING: '".$taxon_name."' is not in the database.</center>";
	    if ( $guess->{'taxon_name'} )
	    {
		$error .= italicize($guess)." seems like a plausible match.";
	    }
	}
	
	# getTaxonNos returns the "largest" taxon first if there are
	#  multiple matches, so use it
	
	if ( scalar @taxon_nos == 1 )
	{
	    $taxon_no = getSeniorSynonym($dbt,$taxon_nos[0]); 
	}
	
	elsif ( scalar @taxon_nos > 1 )
	{
	    $output .= listTaxonChoices($dbt,$hbo,\@taxon_nos,1);
	}
    }
    
    else
    { # this should never happen
	return "<p>You must enter a taxon name.</p>\n\n";
    }
    
    if ( $q->param('do_redirect') && $taxon_no && $taxon_no =~ /^\d+$/ )
    {
	return $taxon_no;
    }
    
    # PAGE TITLE ETC.

    my $authorfields = "if(ref_is_authority='YES',r.author1init,a.author1init) author1init,if(ref_is_authority='YES',r.author1last,a.author1last) author1last,if(ref_is_authority='YES',r.author2init,a.author2init) author2init,if(ref_is_authority='YES',r.author2last,a.author2last) author2last,if(ref_is_authority='YES',r.otherauthors,a.otherauthors) otherauthors,if(ref_is_authority='YES',r.pubyr,a.pubyr) pubyr,reftitle,pubtitle,pubvol,pubno,firstpage,lastpage";
    my $authorfields2 = "if(ref_has_opinion='YES',r.author1init,o.author1init) author1init,if(ref_has_opinion='YES',r.author1last,o.author1last) author1last,if(ref_has_opinion='YES',r.author2init,o.author2init) author2init,if(ref_has_opinion='YES',r.author2last,o.author2last) author2last,if(ref_has_opinion='YES',r.otherauthors,o.otherauthors) otherauthors,if(ref_has_opinion='YES',r.pubyr,o.pubyr) pubyr,reftitle,pubtitle,pubvol,pubno,firstpage,lastpage";

    my ($sql, $auth, @parent_list);
    
    if ( $taxon_no )
    {
	my $just_taxon_no;
	
	if ( $taxon_no =~ /^(\d+)/ )
	{
	    $just_taxon_no = $1;
	}
	
	else
	{
	    $just_taxon_no = 0;
	}
	
	$sql= "SELECT taxon_name,taxon_rank,common_name,extant,a.reference_no,ref_is_authority,$authorfields,type_specimen,type_body_part,part_details,type_locality,discussion,lft,rgt,IF(discussed_by>0,name,'') AS discussant,email FROM authorities a,refs r,$TAXA_TREE_CACHE t,person p WHERE a.reference_no=r.reference_no AND a.taxon_no=$just_taxon_no. AND a.taxon_no=t.taxon_no AND (discussed_by=person_no OR discussed_by IS NULL)";
	
	# print STDERR "SQL: $sql\n\n";
	$auth = ${$dbt->getData($sql)}[0];
	
	# $class_hash = getParents($dbt,[$taxon_no],'array_full');
	
	@parent_list = getParents($dbt, $taxon_no);
	
	unless ( $auth->{'common_name'} )
	{
	    foreach my $taxon ( @parent_list )
	    {
		if ( $taxon->{common_name} )
		{
		    $auth->{common_name} = $taxon->{common_name};
		    last;
		}
	    }
	}
	
	#     for my $i ( 0..$#class_array )	{
	# 	if ( $class_array[$i]->{'common_name'} )	{
	# 		$auth->{'common_name'} = $class_array[$i]->{'common_name'};
	# 		last;
	# 			}
    }
    
    my $page_title = ();
    $page_title->{'title'} = "Paleobiology Database: ";
    
    if ( $auth->{'taxon_name'} )
    {
	$page_title->{'title'} .= $auth->{'taxon_name'};
    }
    
    else
    {
	$page_title->{'title'} .= $taxon_name;
    }
	
    my $taxon = getMostRecentSpelling($dbt,$taxon_no);
    
    if ( $taxon->{'taxon_no'} != $taxon_no )
    {
	$taxon_no = $taxon->{'taxon_no'};
	$auth->{'taxon_name'} = $taxon->{'taxon_name'};
	$auth->{'taxon_rank'} = $taxon->{'taxon_rank'};
	$auth->{'common_name'} = $taxon->{'common_name'};
    }
    
    my $header;
    
    if ( $auth->{'extant'} !~ /yes/i && $taxon_no )
    {
	$header = "&dagger;";
    }
    
    if ( $auth->{'taxon_rank'} =~ /genus|species/ )
    {
	$header .= italicize($auth)." ";
    }
    
    elsif ( $taxon_no )
    {
	$header .= $auth->{'taxon_rank'}." ".$auth->{'taxon_name'}." ";
    }
    
    else
    {
	$header = $taxon_name;
    }
    
    my ($x,$y) = split //,$header,2;
    $x =~ tr/[a-z]/[A-Z]/;
    $header = $x.$y;
    $header =~ s/Unranked clade/Clade/;
    
    if ( $taxon_no )
    {
	my $author = formatShortAuthor($auth);
	if ( $auth->{'ref_is_authority'} =~ /y/i )	{
	    $author = makeAnchor("displayReference", "reference_no=$auth->{'reference_no'}&amp;is_real_user=$is_real_user", $author);
	}
	$header .= $author;
	if ( $auth->{'common_name'} )	{
	    $header .= " (".$auth->{'common_name'}.")";
	}
    }
    
    $output .= qq|<div align="center" class="medium" style="margin-left: 1em; margin-top: 3em;">
<div class="displayPanel" style="margin-top: -1em; margin-bottom: 2em; text-align: left; width: 54em;">
<span class="displayPanelHeader">$header</span>
<div align="left" class="small displayPanelContent" style="padding-left: 1em; padding-bottom: 1em;">
|;

    # CLASS/ORDER/FAMILY SECTION
    
    if ( $taxon_no )
    {
	# my $parent_hash = getParents($dbt,[$taxon_no],'array_full');
	my @parent_array = getParents($dbt, $taxon_no);
	
	my $cof = getClassOrderFamily($dbt, undef, \@parent_array);
	my @parent_links;
	
	for my $r ( 'class','order','family' )
	{
	    if ( $cof->{$r} )
	    {
		push @parent_links , makeAnchor("basicTaxonInfo", "taxon_no=" . $cof->{$r.'_no'}, $cof->{$r});
	    }
	}
	
	if ( @parent_links )
	{
	    $output .= "<p class=\"small\" style=\"margin-top: -0.25em; margin-bottom: 0.75em; margin-left: 1em;\">".join(' - ',@parent_links)."</p>\n\n";
	}
    }
	
    if ( $error )
    {
	$output .= "<p class=\"medium\"><i>$error</i></p>\n\n";
    }
	
    # VERBAL DISCUSSION
    # JA 5.9.11

    if ( $auth->{'discussion'} )
    {
	my $discussion = $auth->{'discussion'};
	$discussion =~ s/(\[\[)([A-Za-z ]+|)(taxon )([0-9]+)(\|)/makeATag("basicTaxonInfo", "taxon_no=$4")/ge;
	$discussion =~ s/(\[\[)([A-Za-z0-9\'\. ]+|)(ref )([0-9]+)(\|)/makeATag("displayReference", "reference_no=$4")/ge;
	$discussion =~ s/(\[\[)([A-Za-z0-9\'"\.\-\(\) ]+|)(coll )([0-9]+)(\|)/makeATag("basicCollectionSearch", "collection_no=$4")/ge;
	$discussion =~ s/\]\]/<\/a>/g;
	$discussion =~ s/\n\n/<\/p>\n<p>/g;
	$auth->{'email'} =~ s/\@/\' \+ \'\@\' \+ \'/;
	$output .= qq|<p style="margin-bottom: -0.5em; font-size: 1.0em;">$discussion</p>
|;
	if ( $auth->{discussant} ne "" )
	{
	    $output .= qq|<script language="JavaScript" type="text/javascript">
    <!-- Begin
    window.onload = showMailto;
    function showMailto( )	{
        document.getElementById('mailto').innerHTML = '<a href="' + 'mailto:' + '$auth->{email}?subject=$auth->{taxon_name}">$auth->{discussant}</a>';
    }
    // End -->
</script>

<p class="verysmall">Send comments to <span id="mailto"></span><p>
|;
	}
    }
	
    # IMAGE AND SYNONYM SECTIONS
	
    my @spellings = ($taxon_no);
    my (@bad_spellings,@all_spellings,@distinct_auths);
	
    if ( $taxon_no )
    {
	push @distinct_auths , $auth;
	$sql = "SELECT a.taxon_no,taxon_name,taxon_rank FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND synonym_no=$taxon_no AND spelling_no=synonym_no AND t.taxon_no!=spelling_no AND a.taxon_name!='".$auth->{'taxon_name'}."' ORDER BY taxon_name";
	my @spelling_refs = @{$dbt->getData($sql)};
	push @spellings , $_->{'taxon_no'} foreach @spelling_refs;
	$sql = "SELECT a.taxon_no,taxon_name,taxon_rank,status,$authorfields,type_specimen,type_body_part,part_details,type_locality,spelling_no FROM authorities a,$TAXA_TREE_CACHE t,opinions o,refs r WHERE a.taxon_no=t.taxon_no AND synonym_no=$taxon_no AND synonym_no!=spelling_no AND t.opinion_no=o.opinion_no AND a.reference_no=r.reference_no GROUP BY taxon_name,author1init,author1last,author2init,author2last,otherauthors,pubyr ORDER BY taxon_name";
	my @syn_refs = @{$dbt->getData($sql)};
	push @bad_spellings , $_->{'taxon_no'} foreach @syn_refs;
	@all_spellings = (@spellings,@bad_spellings);
	    
	for my $syn ( @syn_refs )
	{
	    if ( $syn->{'taxon_no'} == $syn->{'spelling_no'} )
	    {
		push @distinct_auths , $syn;
	    }
	}
	    
	$output .= "<div style=\"clear: both;\"></div>\n\n";
	    
	my $noun = "spelling";
	    
	if ( $auth->{'taxon_rank'} =~ /species/ )
	{
	    $noun = "combination";
	}
	    
	if ( $#spelling_refs == 0 )
	{
	    $output .= "<p>Alternative $noun: ".italicize($spelling_refs[0])."</p>\n\n";
	    # push @spellings , $spelling_refs[0]->{'taxon_no'};
	}
	    
	elsif ( $#spelling_refs > 0 )
	{
	    $output .= "<p $indent>Alternative ".$noun."s: ";
	    my @spelling_names;
	    push @spelling_names , italicize($_) foreach @spelling_refs;
	    $output .= join(', ',@spelling_names)."</p>\n\n";
	}
	    
	my ($synonyms,$nomens,$otherbads);
	    
	for my $s ( @syn_refs )
	{
	    if ( $s->{'status'} !~ /subjective/ )
	    {
		$s->{'note'} = $s->{'status'};
		$s->{'note'} =~ s/ of$//;
		$s->{'note'} =~ s/replaced by/replaced name/;
		$s->{'note'} = " [".$s->{'note'}."]";
		if ( $s->{'status'} =~ /synonym/ )
		{
		    $synonyms++;
		}
		elsif (  $s->{'status'} =~ /nomens/ )
		{
		    $nomens++;
		}
		else
		{
		    $otherbads++;
		}
	    }
	}
	    
	if ( $#syn_refs == 0 )
	{
	    $output .= "<p>Synonym: ".italicize($syn_refs[0])." ".formatShortAuthor($syn_refs[0]).$syn_refs[0]->{'note'}."</p>\n\n";
	}
	    
	elsif ( $#syn_refs == 0 )
	{
	    $output .= "<p>Indeterminate subtaxon: ".italicize($syn_refs[0])." ".formatShortAuthor($syn_refs[0]).$syn_refs[0]->{'note'}."</p>\n\n";
	}
	    
	elsif ( $#syn_refs == 0 )
	{
	    $output .= "<p>Invalid subtaxon: ".italicize($syn_refs[0])." ".formatShortAuthor($syn_refs[0]).$syn_refs[0]->{'note'}."</p>\n\n";
	}
	    
	elsif ( $#syn_refs > 0 )
	{
	    if ( $nomens + $otherbads == 0 )
	    {
		$output .= "<p $indent>Synonyms: ";
	    }
		
	    else
	    {
		$output .= "<p $indent>Invalid subtaxa: ";
	    }
		
	    my $list;
		
	    for my $s ( @syn_refs )
	    {
		$list .= italicize($s)." ".formatShortAuthor($s).$s->{'note'}.", ";
	    }
		
	    $list =~ s/  ,/,/;
	    $list =~ s/, $//;
	    $output .= "$list<p>\n\n";
	}
    }
	
    # FULL AUTHORITY REFERENCE
	
    if ( $auth->{'ref_is_authority'} =~ /y/i )
    {
	$output .= "<p $indent>Full reference: ".formatLongRef($auth)."</p>\n\n";
    }
	
    # PARENT SECTION
	
    my @sisters;
	
    if ( $taxon_no )
    {
	my $sql = "SELECT taxon_name,taxon_rank,a.taxon_no FROM authorities a,opinions o,$TAXA_TREE_CACHE t WHERE a.taxon_no=parent_spelling_no AND o.opinion_no=t.opinion_no AND t.taxon_no=$taxon_no";
	my $parent = ${$dbt->getData($sql)}[0];
	    
	if ( $parent )
	{
	    my $belongs = ( $auth->{'taxon_rank'} =~ /species/ ) ? "Belongs to" : "Parent taxon:";
	    $output .= "<p style=\"clear: left;\">$belongs ";
	    $output .= makeAnchor("basicTaxonInfo", "taxon_no=$parent->{taxon_no}", italicize($parent));
	    $sql = "SELECT r.reference_no,$authorfields2 FROM $TAXA_TREE_CACHE t,opinions o,refs r WHERE r.reference_no=o.reference_no AND t.opinion_no=o.opinion_no AND t.taxon_no=$taxon_no";
	    my $ref = ${$dbt->getData($sql)}[0];
	    $output .= " according to ".formatShortRef($ref,'link_id'=>1);
	    $output .= "</p>\n\n";
		
	    if ( $is_real_user > 0 )
	    {
		$sql =  "SELECT r.reference_no,r.author1last,r.author2last,r.otherauthors,r.pubyr FROM opinions o,$TAXA_TREE_CACHE t,refs r WHERE child_no=taxon_no AND synonym_no=$taxon_no AND o.reference_no=r.reference_no AND o.reference_no!=".$ref->{'reference_no'}." GROUP BY r.reference_no ORDER BY r.author1last,r.author2last,r.pubyr";
		    
		my @refs = @{$dbt->getData($sql)};
		    
		if ( @refs )
		{
		    $output .= "<p $indent>See also ";
		    my @formatted;
			
		    for my $r ( @refs )
		    {
			push @formatted , formatShortRef($r,'link_id'=>1);
		    }
			
		    my $lastref = pop @formatted;
			
		    if ( @formatted )
		    {
			$output .= join(', ',@formatted)." and ";
		    }
			
		    $output .= "$lastref</p>\n\n";
		}
		    
	    }
		
	    #push @sisters , $_ ? $_->{'taxon_no'} != $taxon_no : "" foreach @{getChildren($dbt,$parent->{'taxon_no'},'immediate_children')};
		
	    # my @temp = @{getChildren($dbt,$parent->{'taxon_no'},'immediate_children')};
			
	    my @temp = getChildren($dbt, $parent->{taxon_no}, 'immediate_children');
	    
	    for my $t ( @temp )
	    {
		if ( $t->{'taxon_no'} != $taxon_no )
		{
		    push @sisters, $t;
		}
	    }
		
	    # @sisters = @{getChildren($dbt,$parent->{'taxon_no'},'immediate_children')}; 
	}
	    
	    
	# SISTERS SECTION
	    
	if ( @sisters )
	{
	    if ( $#sisters == 0 )
	    {
		$output .= "<p style=\"clear: left;\">Sister taxon: ";
		$output .= makeAnchor("basicTaxonInfo", "taxon_no=$sisters[0]{taxon_no}", italicize($sisters[0]));
	    }
		
	    else
	    {
		$output .= "<p style=\"margin-left: 1em;\"><span style=\"margin-left: -1em; text-indent: -0.5em;\">Sister taxa: ";
		my $list;
		$list .= makeAnchor("basicTaxonInfo", "taxon_no=$_->{taxon_no}", italicize($_)) . ", " foreach @sisters;
		$list =~ s/, $//;
		$output .= $list;
	    }
	}
	    
	else
	{
	    $output .= "<p style=\"clear: left;\">Sister taxa: <i>none</i>";
	}
	    
	$output .= "</p>\n\n";
    }
	
    # CHILDREN SECTION
	
    if ( $taxon_no )
    {
	my @child_refs = getChildren($dbt,$taxon_no,'immediate_children');
	        
	if ( @child_refs || $auth->{'taxon_rank'} !~ /species/ )
	{
	    $output .= "<p style=\"margin-left: 1em;\"><span style=\"margin-left: -1em; text-indent: -0.5em;\">Subtaxa: ";
		
	    if ( @child_refs )
	    {
		my @child_nos;
		push @child_nos , $_->{'taxon_no'} foreach @child_refs;
		$sql = "SELECT taxon_no,taxon_name,taxon_rank FROM authorities WHERE taxon_no IN (".join(',',@child_nos).") ORDER BY taxon_name";
		my @child_names = @{$dbt->getData($sql)};
		my $list;
		$list .= makeAnchor("basicTaxonInfo", "taxon_no=$_->{taxon_no}", italicize($_)) . " " foreach @child_names;
		$list =~ s/, $//;
		$output .= $list;
		$output .= "</span></p>\n\n";
		$output .= qq|<p><a href=# onClick="javascript: document.doViewClassification.submit()">View classification</a></span></p>\n\n|;
		$output .= "\n<form method=\"POST\" action=\"\" name=\"doViewClassification\">";
		$output .= '<input type="hidden" name="action" value="classify">';
		$output .= '<input type="hidden" name="taxon_no" value="'.$taxon_no.'">';
		$output .= "</form>\n";
	    }
		
	    else
	    {
		$output .= "<i>none</i></span></p>\n\n";
	    }
	}
    }
	
    # TYPE SECTION

    my ($typeInfo,$typeLocality);
	
    if ( $taxon_no )
    {
	($typeInfo,$typeLocality) = printTypeInfo($dbt,join(',',@spellings),$auth,1,'basicTaxonInfo');
	    
	if ( $typeInfo )
	{
	    if ( $typeInfo !~ /\. [A-Za-z]/ )
	    {
		$typeInfo =~ s/[\.] //;
	    }
		
	    if ($auth->{'taxon_rank'} =~ /species/)
	    {
		if ( $#distinct_auths == 0 )
		{
		    $output .= "<p $indent>Type specimen: $typeInfo</p>\n\n";
		    # additional info for junior synonyms
		}
		    
		else
		{
		    $output .= "<p $indent>Type specimens:\n</p>\n<ul style=\"margin-top: -0.5em;\">";
		    $output .= "<li><i>$auth->{'taxon_name'}</i>: ".$typeInfo."</li>\n";
			
		    for my $i ( 1..$#distinct_auths )
		    {
			my ($synTypeInfo,$synTypeLocality) = printTypeInfo($dbt,join(',',@spellings),$distinct_auths[$i],1,'basicTaxonInfo');
			$output .= "<li><i>$distinct_auths[$i]->{'taxon_name'}</i>: ".$synTypeInfo."</li>\n";
		    }
			
		    $output .= "</ul>\n";
		}
	    }
		
	    else
	    {
		$output .= "<p $indent>Type: $typeInfo</p>\n\n";
	    }
	}
    }

    # ECOLOGY SECTION

    if ( $taxon_no )
    {
	my $class_hash = { $taxon_no => \@parent_list };
	    
	my $eco_hash = PBDB::Ecology::getEcology($dbt,$class_hash,['locomotion','life_habit','diet1','diet2'],'get_basis');
	my $ecotaphVals = $eco_hash->{$taxon_no};
	    
	if ( $ecotaphVals )
	{
	    $output .= "<p>Ecology:";
	    # it's really annoying how often this gets printed
	    $ecotaphVals->{'locomotion'} =~ s/actively mobile//;
		
	    for my $e ( 'locomotion','life_habit','diet1' )
	    {
		if ( $ecotaphVals->{$e} )
		{
		    $output .= " ".$ecotaphVals->{$e};
		}
	    }
		
	    if ( $ecotaphVals->{'diet1'} && $ecotaphVals->{'diet2'} )
	    {
		$output .= "-".$ecotaphVals->{'diet2'};
	    }
		
	    $output .= "</p>\n\n";
	}
    }
	
    # MEASUREMENT AND BODY MASS SECTIONS
    # JA 24.11.10
    # added body mass and simplified by calling getMassEstimates 9.12.10

    my @specimens;
    my $specimen_count;
	
    if ( $taxon_no && $auth->{'taxon_rank'} eq "species" )
    {
	@specimens = getMeasurements($dbt,{'taxon_list'=>\@all_spellings,'get_global_specimens'=>1});
	    
	if ( @specimens )
	{
	    my $p_table = getMeasurementTable(\@specimens);
	    my $orig = getOriginalCombination($dbt,$taxon_no);
	    my $ss = getSeniorSynonym($dbt,$orig);
	    my @m = getMassEstimates($dbt,$ss,$p_table,'skip area');
		
	    if ( @{$m[1]} )
	    {
		$output .= "<p $indent>Average measurements (in mm): ".join(', ',@{$m[1]});
		$output .= "</p>\n\n";
	    }
		
	    if ( $m[5] && $m[6] )
	    {
		my @eqns = @{$m[3]};
		s/^[A-Za-z]+ // foreach @eqns;
		my %perpart;
		$perpart{$_}++ foreach @eqns;
		@eqns = keys %perpart;
		@eqns = sort @eqns;
		    
		if ( $#eqns > 0 )
		{
		    $eqns[$#eqns] = "and ".$eqns[$#eqns];
		}
		    
		if ( $#eqns > 1 )
		{
		    $eqns[$_] .= "," foreach ( 0..$#eqns-1 );
		}
		    
		$output .= "<p $indent>Estimated body mass: ".formatMass( exp( $m[5]/$m[6] ) )." based on ".join(' ',@eqns);
		$output .= "</p>\n\n";
	    }
	}
    }

    # DISTRIBUTION SECTION

    my @occs;
	
    if ( $is_real_user > 0 && $auth->{'rgt'} - $auth->{'lft'} < 20000 )
    {
	# taxon_string is needed for maps and taxon_param for links
	my $taxon_string = $taxon_no;
	my $taxon_param = "taxon_no=".$taxon_no;
	    
	if ( ! $taxon_string )
	{
	    $taxon_string = $taxon_name;
	    $taxon_param = "taxon_name=".$taxon_name;
	}
	    
	$taxon_string =~ s/ /_/g;
	    
	my $collection_fields = "c.collection_no,collection_name,c.max_interval_no,c.min_interval_no,c.country,c.state";
	    
	if ( $taxon_no )
	{
	    $sql = "SELECT $collection_fields, count(distinct(o.collection_no)) as c,
				count(distinct(o.occurrence_no)) as o
			FROM collections as c join occurrences as o using (collection_no)
				join $TAXA_TREE_CACHE as t using (taxon_no)
				join $TAXA_TREE_CACHE as base on t.lft between base.lft and base.rgt
				left join reidentifications as re using (occurrence_no)
			WHERE base.taxon_no = $taxon_no and re.reid_no is null
			GROUP BY c.max_interval_no, c.min_interval_no, country, state
		  UNION SELECT $collection_fields, count(distinct(c.collection_no)) as c,
				count(distinct(re.occurrence_no)) as o
			FROM collections as c join reidentifications as re using (collection_no)
				join $TAXA_TREE_CACHE as t using (taxon_no)
				join $TAXA_TREE_CACHE as base on t.lft between base.lft and base.rgt
			WHERE base.taxon_no = $taxon_no and re.most_recent='YES'
			GROUP BY c.max_interval_no, c.min_interval_no, country, state";
		
	    # $sql = "SELECT child_no FROM $TAXA_LIST_CACHE t WHERE parent_no=$taxon_no";
	    # my @subtaxa = @{$dbt->getData($sql)};
	    # my @inlist;
	    # push @inlist , $_->{'child_no'} foreach @subtaxa;
	    # push @inlist , @spellings;
	    # $sql = "(SELECT $collection_fields,count(distinct(o.collection_no)) c,count(distinct(o.occurrence_no)) o FROM collections c,occurrences o LEFT JOIN reidentifications re ON o.occurrence_no=re.occurrence_no WHERE c.collection_no=o.collection_no AND o.taxon_no IN (".join(',',@inlist).") AND re.reid_no IS NULL GROUP BY c.max_interval_no,c.min_interval_no,country,state)";
	    # $sql .= " UNION (SELECT $collection_fields,count(distinct(c.collection_no)) c,count(distinct(re.occurrence_no)) o FROM collections c,reidentifications re WHERE c.collection_no=re.collection_no AND taxon_no IN (".join(',',@inlist).") AND re.most_recent='YES' GROUP BY c.max_interval_no,c.min_interval_no,country,state)";
	}
	    
	else
	{
	    my ($g,$s) = split / /,$taxon_name;
	    my $occ_clause = "(o.genus_name='".$g."' OR o.subgenus_name='".$g."')";
	    $occ_clause .= " AND o.species_name='".$s."'" if $s;

	    my $reid_clause = $occ_clause =~ s/o\./re\./gr;
		
	    $sql = "SELECT $collection_fields, count(distinct(c.collection_no)) as c,
				count(distinct(o.occurrence_no)) as o
			FROM collections as c join occurrences as o using (collection_no)
				left join reidentifications as re using (occurrence_no)
			WHERE $occ_clause AND re.reid_no is null
			GROUP BY c.max_interval_no, c.min_interval_no, country, state
		  UNION SELECT $collection_fields, count(distinct(c.collection_no)) as c,
				count(distinct(re.occurrence_no)) as o
			FROM collections as c join reidentifications as re using (collection_no)
			WHERE $reid_clause AND re.most_recent='YES'
			GROUP BY c.max_interval_no, c.min_interval_no, country, state";

	    # $sql = "(SELECT $collection_fields,count(distinct(c.collection_no)) c,count(distinct(o.occurrence_no)) o FROM collections c,occurrences o LEFT JOIN reidentifications re ON o.occurrence_no=re.occurrence_no WHERE c.collection_no=o.collection_no AND $name_clause AND re.reid_no IS NULL GROUP BY c.max_interval_no,c.min_interval_no,country,state)";
	    # $name_clause =~ s/o\./re\./g;
	    # $sql .= " UNION (SELECT $collection_fields,count(distinct(c.collection_no)) c,count(distinct(re.occurrence_no)) o FROM collections c,reidentifications re WHERE c.collection_no=re.collection_no AND $name_clause AND re.most_recent='YES' GROUP BY c.max_interval_no,c.min_interval_no,country,state)";
	}
	    
	@occs = @{$dbt->getData($sql)};
	    
	$sql = "SELECT l.interval_no,i1.interval_name period,i2.interval_name epoch,base_age base FROM interval_lookup l,intervals i1,intervals i2 WHERE period_no=i1.interval_no AND epoch_no=i2.interval_no";
	    
	my @intervals = @{$dbt->getData($sql)};
	    
	my (%epoch,%period,%own,%base);
	    
	for my $i ( @intervals )
	{
	    $epoch{$i->{'interval_no'}} = $i->{'epoch'};
	    $period{$i->{'interval_no'}} = $i->{'period'};
	    # it doesn't matter which subinterval is used
	    $base{$i->{'epoch'}} = $i->{'base'};
	    $base{$i->{'period'}} = $i->{'base'};
	}
	    
	$sql = "SELECT i.interval_no,interval_name own,base_age base FROM interval_lookup l,intervals i WHERE l.interval_no=i.interval_no";
	    
	my @intervals2 = @{$dbt->getData($sql)};
	    
	for my $i ( @intervals2 )
	{
	    $own{$i->{'interval_no'}} = $i->{'own'};
	    $base{$i->{'own'}} = $i->{'base'};
	}
	    
	$output .= "<p>Distribution:";
	    
	if ( $#occs == 0 && $occs[0]->{'c'} == 1 )
	{
	    my $o = $occs[0];
	    $output .= qq| found only at |;
	    $output .= makeATag("basicCollectionSearch", "collection_no=$o->{collection_no}") . $o->{'collection_name'};
		
	    if ( $typeLocality == 0 )
	    {
		my $place = ( $o->{'country'} =~ /United States|Canada/ ) ? $o->{'state'} : $o->{'country'};
		$place =~ s/United King/the United King/;
		my $time = ( $period{$o->{'max_interval_no'}} =~ /Paleogene|Neogene/ ) ? $epoch{$o->{'max_interval_no'}} : $period{$o->{'max_interval_no'}};
		$time .= ( $period{$o->{'min_interval_no'}} =~ /Paleogene|Neogene/ ) ? " to ".$epoch{$o->{'min_interval_no'}} : "";
		$output .= qq| ($time of $place)|;
	    }
		
	    $output .= "</p>\n\n";
	}
	    
	elsif ( @occs )
	{
	    my ($ctotal,$ototal,%bycountry,%bystate);
		
	    for my $o ( @occs )
	    {
		$ctotal += $o->{'c'};
		$ototal += $o->{'o'};
		    
		if ( $period{$o->{'max_interval_no'}} =~ /Paleogene|Neogene/ )
		{
		    if ( $epoch{$o->{'max_interval_no'}} eq $epoch{$o->{'min_interval_no'}} || 
			 $o->{'min_interval_no'} == 0 || ! $epoch{$o->{'min_interval_no'}} )
		    {
			$bycountry{$epoch{$o->{'max_interval_no'}}}{$o->{'country'}} += $o->{'c'};
			$bystate{$epoch{$o->{'max_interval_no'}}}{$o->{'country'}}{$o->{'state'}} += $o->{'c'};
		    }
			
		    else
		    {
			$bycountry{$epoch{$o->{'max_interval_no'}}." to ".$epoch{$o->{'min_interval_no'}}}{$o->{'country'}} += $o->{'c'};
			$bystate{$epoch{$o->{'max_interval_no'}}." to ".$epoch{$o->{'min_interval_no'}}}{$o->{'country'}}{$o->{'state'}} += $o->{'c'};
		    }
		}
		    
		elsif ( $period{$o->{'max_interval_no'}} )
		{
		    if ( $period{$o->{'max_interval_no'}} eq $period{$o->{'min_interval_no'}} || 
			 $o->{'min_interval_no'} == 0 || ! $period{$o->{'min_interval_no'}} )
		    {
			$bycountry{$period{$o->{'max_interval_no'}}}{$o->{'country'}} += $o->{'c'};
			$bystate{$period{$o->{'max_interval_no'}}}{$o->{'country'}}{$o->{'state'}} += $o->{'c'};
		    }
			
		    else
		    {
			$bycountry{$period{$o->{'max_interval_no'}}." to ".$period{$o->{'min_interval_no'}}}{$o->{'country'}} += $o->{'c'};
			$bystate{$period{$o->{'max_interval_no'}}." to ".$period{$o->{'min_interval_no'}}}{$o->{'country'}}{$o->{'state'}} += $o->{'c'};
		    }
		}
		    
		else
		{
		    $bycountry{$own{$o->{'max_interval_no'}}}{$o->{'country'}} += $o->{'c'};
		    $bystate{$own{$o->{'max_interval_no'}}}{$o->{'country'}}{$o->{'state'}} += $o->{'c'};
		}
	    }
		
	    my @intervals = keys %bycountry;
		
	    for my $i ( @intervals )
	    {
		if ( ! $base{$i} )
		{
		    my ($x,$y) = split / /,$i;
		    $base{$i} = $base{$x} - 0.01;
		}
	    }
		
	    @intervals = sort { $base{$a} <=> $base{$b} } @intervals;
		
	    $output .= "</p>\n\n";
	    $output .= "<div style=\"margin-left: 2em;\">\n";
	    my $printed;
		
	    for my $i ( @intervals )
	    {
		$output .= "<p $indent>&bull; $i of ";
		my @countries = keys %{$bycountry{$i}};
		@countries = sort @countries;
		my $list;
		    
		for my $c ( @countries )
		{
		    my @states = keys %{$bystate{$i}{$c}};
		    @states = sort @states;
			
		    for my $j ( 0..$#states )
		    {
			if ( ! $states[$j] )
			{
			    splice @states , $j , 1;
			    last;
			}
		    }
			
		    my ($max_interval,$min_interval) = split/ to /,$i;
		    my $country = $c;
		    my $shortcountry = $country;
		    $shortcountry =~ s/Libyan Arab Jamahiriya/Libya/;
		    $shortcountry =~ s/Syrian Arab Republic/Syria/;
		    $shortcountry =~ s/Lao People's Democratic Republic/Laos/;
		    $shortcountry =~ s/(United Kingdom|Russian Federation|Czech Republic|Netherlands|Dominican Republic|Bahamas|Philippines|Netherlands Antilles|United Arab Emirates|Marshall Islands|Congo|Seychelles)/the $1/;
		    $shortcountry =~ s/, .*//;
			
		    my $min_interval_where;
			
		    if ( $min_interval )
		    {
			$min_interval_where = "&amp;min_interval_no=$min_interval";
		    }
			
		    if ( $country !~ /United States|Canada/ || ! @states )
		    {
			$list .= makeAnchor("displayCollResults", "$taxon_param&amp;max_interval=$max_interval$min_interval_where&amp;country=$country&amp;is_real_user=$is_real_user&amp;basic=yes&amp;type=view&amp;match_subgenera=1", $shortcountry) . " (".$bycountry{$i}{$c};
		    }
			
		    else
		    {
			for my $j ( 0..$#states )
			{
			    $states[$j] = makeAnchor("displayCollResults", "$taxon_param&amp;max_interval=$max_interval$min_interval_where&amp;country=$country&amp;state=$states[$j]&amp;is_real_user=$is_real_user&amp;basic=yes&amp;type=view&amp;match_subgenera=1", $states[$j]);
			}
			    
			$list .= "$country ($bycountry{$i}{$c}";
			$list .= ": ".join(', ',@states);
		    }
			
		    $printed++;
			
		    if ( $printed == 1 && $bycountry{$i}{$c} == 1 )
		    {
			$list .= " collection";
		    }
			
		    elsif ( $printed == 1 && $bycountry{$i}{$c} > 1 )
		    {
			$list .= " collections";
		    }
			
		    $list .= "), ";
		}
		    
		$list =~ s/, $//;
		$output .= "$list</p>\n";
	    }
		
	    if ( $ctotal > 1 && $ctotal < $ototal )
	    {
		$output .= "<p>Total: $ctotal collections including $ototal occurrences</p>\n\n";
	    }
		
	    elsif ( $ctotal > 1 && $ctotal == $ototal )
	    {
		$output .= "<p>Total: $ctotal collections each including a single occurrence</p>\n\n";
	    }
		
	    $output .= "</div>\n\n";
		
	    # don't print anything for really big groups, users shouldn't
	    #  expect to see occurrences anyway JA 13.7.12
	}
	    
	elsif ( $auth->{'rgt'} - $auth->{'lft'} >= 20000 )
	{
	}
	    
	else
	{
	    if ( $auth->{'taxon_name'} )
	    {
		$output .= " <i>there are no occurrences of $auth->{'taxon_name'} in the database</i></p>\n\n";
	    }

	    else
	    {
		$output .= "</p>\n\n<p><i>There is no taxonomic or distributional information about '$taxon_name' in the database</i></p>\n\n";
	    }
	}
    }
        
    my $taxon_name = $taxon->{'taxon_name'};
    my $taxon_rank = $taxon->{'taxon_rank'};
	
    if ( $is_real_user > 0 && ( @occs || $taxon_no ) )
    {
	if ( $taxon_no )
	{
	    $output .= "<p>" . makeAnchor("checkTaxonInfo", "taxon_no=$taxon_no&amp;is_real_user=1", "Show more details") . "</p>\n\n";
	}
	    
	else
	{
	    $output .= "<p>" . makeAnchor("checkTaxonInfo", "taxon_name=$taxon_name&amp;is_real_user=1", "Show more details") . "</p>\n\n";
	}
	    
	if ( $s->isDBMember() && $taxon_no && $s->get('role') =~ /authorizer|student|technician/ )
	{
	    $output .= "<p>" . makeAnchor("displayAuthorityForm", "taxon_no=$taxon_no", "Edit " . italicize($auth)) . "</p>\n\n";
	    $output .= "<p>" . makeAnchor("displayOpinionChoiceForm", "taxon_no=$taxon_no", "Add/edit taxonomic opinions about " . italicize($auth)) . "</p>\n\n";
	}
	    
	if ( $taxon_rank eq "genus" || $taxon_rank eq "species" )
	{
	    $output .= '<hr><p><a href="http://epandda.org" target="_blank"><img src="https://epandda.org/img/epandda_logo_small.png" style="width: 50px;"></a>';
	    $output .= ' Specimen images are retrieved through the <a href="http://epandda.org" target="_blank">ePANDDA</a> API.</p>';
	    $output .= '<input type="button" id="getImages" name="getImages" value="Display Images">';
	    $output .= '<center><p class="fa-3x" id="running"><i class="fas fa-spinner fa-spin"></i><p></center>';
	    $output .= '<div id="instructions"><br>Click image to enlarge. Click <i class="fas fa-info-circle"></i> to access iDigBio record.</div>';
	    $output .= '<div class="img-with-text" id="images"></div>';
	    $output .= '<b><p id="result"></p></b>';
	}
    }
    
    $output .= "</div>\n</div>\n\n";
    
    $output .= qq|
<form method="POST" action="" onSubmit="return checkName(1,'search_again');">
<input type="hidden" name="action" value="basicTaxonInfo">
|;
    
    if ( $taxon_no )
    {
	$output .= qq|<input type="hidden" name="last_taxon" value="$taxon_no">
|;
    }

# $output .= qq|
# <span class="small">
# <input type="text" name="search_again" value="Search again" size="24" onFocus="textClear(search_again);" onBlur="textRestore(search_again);" style="font-size: 1.0em;">
# </span>
# </form>
# |;

    $output .= "<br>\n\n";
    $output .= "</div>\n\n";
    
    $output .= "<script src=\"//ajax.googleapis.com/ajax/libs/jquery/2.0.3/jquery.min.js\" type=\"text/javascript\"></script>";
    $output .= '<link rel="stylesheet" href="https://use.fontawesome.com/releases/v5.2.0/css/all.css" integrity="sha384-hWVjflwFxL6sNzntih27bfxkr27PmbbK/iSvJ+a4+0owXq79v+lsFkW54bOGbiDQ" crossorigin="anonymous">';
    
    $output .= qq|
          <script type=\"text/javascript\">

            \$('document').ready(function() {
              \$('#running').hide();
              \$('#instructions').hide();
            })

            \$('#getImages').on(\"click\", function() {
              \$('#running').show();
              if ('$taxon_rank' == 'genus') {
                var qualifier = 'genus:';
              } else {
                var qualifier = 'scientificname:';
              }
              \$.ajax( {
                url: "https://api.epandda.org/occurrences",
                dataType: "json",
                data: {
                  terms: qualifier + '$taxon_name',
                  mediaOnly: "1",
                  limit: "3000"
                }
              })
              .done (function (data) {
                \$('#running').hide();
                \$('#instructions').show();
                \$('#images').empty();
                if (data.mediaURLs.length == 0) {
                  \$('#result').text('No images found');
                } else {
                  var lastUri = null;
                  for (rec in data.mediaURLs) {
                    var infoLink = data.mediaURLs[rec].record;
                    for (link in data.mediaURLs[rec].media) {
                      var uri = data.mediaURLs[rec].media[link];
                      if (uri != null && uri != lastUri) {
                        \$('#images').append('<a target="_blank" href="' + uri + '"><img src="' + uri + '" style="padding: 2px 2px 2px 2px;width: 100px;"></a><a target="_blank" href="' + infoLink + '"><i class="fas fa-info-circle"></i></a>');
                        lastUri = uri;
                      }
                    }
                  }
                }
                });
              })
          </script>
          |;
	
    return $output;
}


# moved over from bridge.pl JA 8.4.12
# originally called randomTaxonInfo and then hijacked to also get all names in
#  a group if those are requested instead
# originally wrote this to only recover names tied to an occurrence; revised to
#   get all names in the group, period JA 20.3.11

sub getMatchingSubtaxa {
    
    my ($dbt,$q,$s,$hbo) = @_;
    
    return if PBDB::PBDBUtil::checkForBot();
    
    my $dbh = $dbt->dbh;
    my $sql;
    my $lft;
    my $rgt;
    
    if ( $q->param('taxon_name') =~ /^[A-Za-z]/ )	{
		my $sql = "SELECT lft,rgt FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND taxon_name=".$dbh->quote($q->param('taxon_name'))." ORDER BY rgt-lft DESC";
		my $taxref = ${$dbt->getData($sql)}[0];
		if ( $taxref )	{
			$lft = $taxref->{lft};
			$rgt = $taxref->{rgt};
		}
	} elsif ( $q->param('common_name') =~ /^[A-Za-z]/ )	{
		my $sql = "SELECT lft,rgt FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND common_name=".$dbh->quote($q->param('common_name'))." ORDER BY rgt-lft DESC";
		my $taxref = ${$dbt->getData($sql)}[0];
		if ( $taxref )	{
			$lft = $taxref->{lft};
			$rgt = $taxref->{rgt};
		}
	}
	my @trefs;
	if ( $lft > 0 && $rgt > 0 )	{
		# default is valid names only as currently spelled
		my $tables = "authorities a,$TAXA_TREE_CACHE t";
		my $join = "a.taxon_no=t.taxon_no AND t.taxon_no=synonym_no";
		if ( $q->param('author') =~ /^[A-Za-z]/ || $q->param('pubyr') > 1700 )	{
			$tables .= ",refs r";
			$join .= " AND a.reference_no=r.reference_no";
		}
		# invalid only
		if ( $q->param('taxon_rank') =~ /[a-z]/ && $q->param('validity') =~ /^invalid$/i )	{
				$join = "a.taxon_no=t.taxon_no AND t.taxon_no=spelling_no AND t.taxon_no!=synonym_no";
		# either one
		} elsif ( $q->param('taxon_rank') =~ /[a-z]/ && $q->param('validity') =~ /invalid/i )	{
				$join = "a.taxon_no=t.taxon_no AND t.taxon_no=spelling_no";
		}
		my $morewhere;
		if ( $q->param('author') =~ /^[A-Za-z]/ )	{
			my $author = $q->param('author');
			$author =~ s/[^A-Za-z '\-]//g;
			my $quoted_author = $dbh->quote($author);
			$morewhere .= " AND ((ref_is_authority='yes' AND (r.author1last=$quoted_author OR r.author2last=$quoted_author)) OR (ref_is_authority!='yes' AND (a.author1last=$quoted_author OR a.author2last=$quoted_author)))";
		}
		if ( $q->param('pubyr') > 1700 )	{
			my $pubyr = $q->param('pubyr');
			$pubyr =~ s/[^0-9]//g;
			my $quoted_pubyr = $dbh->quote($pubyr);
			$morewhere .= " AND ((ref_is_authority='yes' AND r.pubyr=$pubyr) OR (ref_is_authority!='yes' AND a.pubyr=$quoted_pubyr))";
		}
		if ( my $rank = $q->param('taxon_rank') )	{
		    my $quoted = $dbh->quote($rank);
		    $morewhere .= " AND taxon_rank=$quoted";
		} else	{
		    $morewhere .= " AND taxon_rank='species'";
		}
		if ( my $tbp = $q->param('type_body_part') )	{
		    my $quoted = $dbh->quote($tbp);
		    $morewhere = " AND type_body_part=$quoted";
		}
		if ( my $pres = $q->param('preservation') )	{
		    my $quoted = $dbh->quote($pres);
		    $morewhere .= " AND preservation=$quoted";
		}
		if ( $q->param('exclude_taxon') )	{
			$sql = "SELECT lft,rgt FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND taxon_name=".$dbh->quote($q->param('exclude_taxon'))." ORDER BY rgt-lft DESC";
			my $exclude = ${$dbt->getData($sql)}[0];
			$morewhere .= " AND (lft<".$exclude->{lft}." OR rgt>".$exclude->{rgt}.")";
		}
		$sql = "SELECT a.taxon_no FROM $tables WHERE $join AND (lft BETWEEN $lft AND $rgt) AND (rgt BETWEEN $lft AND $rgt) $morewhere";
		@trefs = @{$dbt->getData($sql)};
	}
	if ( $q->param('match') eq "all" )	{
		my @taxa;
		push @taxa , $_->{taxon_no} foreach @trefs;
		return \@taxa;
	}
	# otherwise select a taxon at random
	else	{
		@trefs = @{$dbt->getData("SELECT a.taxon_no FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND t.taxon_no=synonym_no AND taxon_rank IN ('species')")};
		my $x = int(rand($#trefs + 1));
		$q->param('taxon_no' => $trefs[$x]->{taxon_no});
		# infinite loops are bad
		$q->param('match' => '');
		return basicTaxonInfo($q,$s,$dbt,$hbo);
	}
}

# calved off from checkTaxonInfo JA 8.4.12
sub listTaxonChoices	{

    my ($dbt,$hbo,$data,$numbersOnly) = @_;
    my @results;
    my $output = '';
    
	if ( $numbersOnly == 0 )	{
		@results = @{$data};
	} else	{
		my $sql = "SELECT a.*,IF (ref_is_authority='YES',r.author1last,a.author1last) author1last,IF (ref_is_authority='YES',r.author2last,a.author2last) author2last,IF (ref_is_authority='YES',r.otherauthors,a.otherauthors) otherauthors,IF (ref_is_authority='YES',r.pubyr,a.pubyr) pubyr FROM authorities a,refs r WHERE a.reference_no=r.reference_no AND taxon_no IN (".join(',',@{$data}).")";
		@results = @{$dbt->getData($sql)};
	}
	@results = sort { $a->{taxon_name} cmp $b->{taxon_name} } @results;
	$output .= "<div align=\"center\"><p class=\"pageTitle\" style=\"margin-bottom: 0.5em;\">Please select a taxonomic name</p>\n";
	if ( scalar @results >= 10 )	{
		$output .= "<p class=\"small\">The total number of matches is ".scalar @results."</p>\n";
	} else	{
		$output .= "<br>\n";
	}
	$output .= qq|<div class="displayPanel" align="center" style="width: 36em; padding-top: 1.5em;">
<div class="displayPanelContent">
<table>
<tr>
|;

	my $classes = qq|"medium"|;
	for my $i ( 0..$#results )	{
		my $authorityLine = formatTaxon($dbt,$results[$i]);
		if ($#results > 2)	{
			$classes = ($i/2 == int($i/2)) ? qq|"small darkList"| : "small";
		}
		# the width term games browsers
		$output .= qq|<td class=$classes style="width: 1em; padding: 0.25em; padding-left: 1em; padding-right: 1em; white-space: nowrap;">&bull; |;
		$output .= makeAnchorWithAttrs("basicTaxonInfo", "taxon_no=$results[$i]->{taxon_no}", 'style="color: black;"', $authorityLine) . "</td>";
		$output .= "</tr>\n<tr>";
	}
	$output .= qq|</tr>
<tr><td align="center" colspan=3><br>
</td></tr></table></div>
</div>
</div>
|;
	if ( $numbersOnly > 0 )	{
		return;
	}

    return $output;
}

# JA 3.11.09
sub formatShortAuthor	{
	my $taxon = shift;
	my $authors = $taxon->{'author1last'};
	if ( $taxon->{'otherauthors'} =~ /[A-Z]/ )	{
		$authors .= " et al.";
	} elsif ( $taxon->{'author2last'} =~ /[A-Z]/ )	{
		$authors .= " and ".$taxon->{'author2last'};
	}
	$authors .= " ".$taxon->{'pubyr'};
	return $authors;
}

# JA 3.11.09
sub italicize	{
	my $taxon = shift;
	my $name = $taxon->{'taxon_name'};
	if ( $taxon->{'taxon_rank'} =~ /genus|species/ )	{
		$name = "<i>".$name."</i>";
	}
	return $name;
}


1;
