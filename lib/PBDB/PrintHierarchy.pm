
package PBDB::PrintHierarchy;

use PBDB::TaxonInfo;
use PBDB::Reference;
use PBDB::Constants qw($TAXA_TREE_CACHE $TAXON_TREES makeAnchor makeFormPostTag);
use strict;

use JSON;



our %shortranks = ( "subspecies" => "","species" => "",
	 "subgenus" => "Subg.", "genus" => "G.", "subtribe" => "Subtr.",
	 "tribe" => "Tr.", "subfamily" => "Subfm.", "family" => "Fm.",
	 "superfamily" => "Superfm.", "infraorder" => "Infraor.",
	 "suborder" => "Subor.", "order" => "Or.", "superorder" => "Superor.",
	 "infraclass" => "Infracl.", "subclass" => "Subcl.", "class" => "Cl.",
	 "superclass" => "Supercl.", "subphylum" => "Subph.",
	 "phylum" => "Ph.");


sub classificationForm	{
	my $hbo = shift;
	my $s = shift;
	my $error = shift;
	my $ref_list = shift;
	my %refno;
	$refno{'current_ref'} = $s->get('reference_no');
	if ( $s->get('enterer_no') > 0 )	{
		$refno{'not_guest'} = 1;
	}
	if ( $error )	{
		$refno{'error_message'} = "<p style=\"margin-top: -0.2em; margin-bottom: 1em;\"><i>\n".$error;
		$refno{'error_message'} .= ( ! $ref_list ) ? "<br>Please search again</i></p>" : "</i></p>\n";
		$refno{'ref_list'} = $ref_list;
	}
	return $hbo->populateHTML('classify_form',\%refno);
}

# JA 27.2.12
# complete rewrite of most of this module
sub classify {

    my ($dbt,$hbo,$s,$q) = @_;
    
    my $output = '
<script src="/public/classic_js/included_taxa.js" language="JavaScript" type="text/javascript"></script>
';
    my $dbh = $dbt->dbh;

    # First unpack the parameters.
    
    my $taxon_no = $q->numeric_param('taxon_no');
    my $reference_no = $q->numeric_param('reference_no');

    if ( $q->numeric_param('parent_no') )
    {
	$taxon_no = $q->numeric_param('parent_no');
    }
    
    # If something like "Jones 1984" was submitted, find the matching reference with the most
    # opinions. Assume they are not looking for junior authors
    
    if ( $q->param('citation') )
    {
	my ($auth,$year) = split / /,$q->param('citation');
	
	if ( $year < 1700 || $year > 2100 )
	{
	    return classificationForm($hbo, $s, 'The publication year is misformatted');
	}

	my $quoted_auth = $dbh->quote($auth);
	my $quoted_year = $dbh->quote($year);
	my $sql = "SELECT reference_no,author1init,author1last,author2init,author2last,otherauthors,pubyr,reftitle,pubtitle,pubvol,firstpage,lastpage FROM refs WHERE author1last=$quoted_auth AND pubyr=$quoted_year ORDER BY author1last DESC,author2last DESC,pubyr DESC";
	my @refs = @{$dbt->getData($sql)};

	if ( @refs == 1 )
	{
	    $reference_no = $refs[0]->{'reference_no'};
	}

	elsif ( @refs > 1 )
	{
	    my @ref_list;
	    push @ref_list , "<p class=\"verysmall\" style=\"margin-left: 2em; margin-right: 0.5em; text-indent: -1em; text-align: left; margin-bottom: -0.8em;\">".PBDB::Reference::formatLongRef($_)." (ref ".$_->{'reference_no'}.")</p>\n" foreach @refs;
	    return classificationForm($hbo, $s, 'The following matches were found',join('',@ref_list)."<div style=\"height: 1em;\"></div>");
	}
    }

    # my $fields = "t.taxon_no,taxon_name,taxon_rank,common_name,extant,status,IF (ref_is_authority='YES',r.author1last,a.author1last) author1last,IF (ref_is_authority='YES',r.author2last,a.author2last) author2last,IF (ref_is_authority='YES',r.otherauthors,a.otherauthors) otherauthors,IF (ref_is_authority='YES',r.pubyr,a.pubyr) pubyr,lft,rgt";

    my (@taxa,@parents,%children,$title);
    
    # References require special handling because they may classify multiple taxa and because
    # parent-child relations are drawn directly from opinions instead of taxa_tree_cache.
    
    if ( ! $taxon_no && $reference_no )
    {
	my $sql = "SELECT child_spelling_no,parent_spelling_no FROM opinions WHERE reference_no=".$reference_no." AND ref_has_opinion='YES'";
	my @opinions = @{$dbt->getData($sql)};
	
	# If there are opinions associated with the specified reference, then display the
	# corresponding taxonomic hierarchy.

	if ( @opinions )
	{
	    $sql = "SELECT * FROM refs WHERE reference_no=".$reference_no;
	    $title = "Classification of " . PBDB::TaxonInfo::formatShortAuthor( ${$dbt->getData($sql)}[0] );
	    
	    $output .= displayIncludedTaxa($dbt, 'reference_no', $reference_no, $title);
	    return $output;
	}

	# Otherwise, let the user know that there is nothing to display.
	
	else
	{
	    return classificationForm($hbo, $s, 'No newly expressed taxonomic opinions are tied to this reference');
	}

	# Old deprecated code

	# my $sql = "SELECT child_spelling_no,parent_spelling_no FROM opinions WHERE reference_no=".$reference_no." AND ref_has_opinion='YES'";
	# my @opinions = @{$dbt->getData($sql)};
	# if ( ! @opinions )
	# {
	#     return classificationForm($hbo, $s, 'No newly expressed taxonomic opinions are tied to this reference');
	# }
	# my %isChild;
	# $isChild{$_->{'child_spelling_no'}}++ foreach @opinions;
	# $sql = "SELECT $fields FROM authorities a,$TAXA_TREE_CACHE t,opinions o,refs r WHERE o.reference_no=$reference_no AND ref_has_opinion='YES' AND child_spelling_no=a.taxon_no AND a.taxon_no=t.taxon_no AND a.reference_no=r.reference_no";
	# @taxa = @{$dbt->getData($sql)};
	# # some parents may be completely unclassified
	# my $non_opinion_fields = $fields;
	# $non_opinion_fields =~ s/,status//;
	# $sql = "SELECT $fields FROM authorities a,$TAXA_TREE_CACHE t,opinions o,refs r WHERE o.reference_no=$reference_no AND ref_has_opinion='YES' AND parent_spelling_no=a.taxon_no AND a.taxon_no=t.taxon_no AND a.reference_no=r.reference_no AND parent_spelling_no NOT IN (".join(',',keys %isChild).") GROUP BY parent_spelling_no";
	# push @taxa , @{$dbt->getData($sql)};
	# my %parent;
	# $parent{$_->{'child_spelling_no'}} = $_->{'parent_spelling_no'} foreach @opinions;
	# for my $i ( 0..$#taxa )	{
	#     push @{$children{$parent{$taxa[$i]->{'taxon_no'}}}} , $taxa[$i];
	#     if ( ! $parent{$taxa[$i]->{'taxon_no'}} )	{
	# 	push @parents , $taxa[$i];
	#     }
	# }
	# $sql = "SELECT * FROM refs WHERE reference_no=".$reference_no;
	# $title = PBDB::TaxonInfo::formatShortAuthor( ${$dbt->getData($sql)}[0] );	
    }
    
    # If a common name is given, try to get the corresponding taxon_no.
    
    elsif ( ! $taxon_no && $q->param('common_name') )
    {
	my $common = $q->param('common_name');
	my $sql = "SELECT a.taxon_no FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND common_name='".$common."' ORDER BY rgt-lft DESC LIMIT 1";
	$taxon_no = ${$dbt->getData($sql)}[0]->{'taxon_no'};
	if ( ! $taxon_no && $common =~ /s$/ )	{
	    $common =~ s/s$//;
	    $sql = "SELECT a.taxon_no FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND common_name='".$common."' ORDER BY rgt-lft DESC LIMIT 1";
	    $taxon_no = ${$dbt->getData($sql)}[0]->{'taxon_no'};
	}
    }
    
    # If a taxonomic name is given, try to get the corresponding taxon_no.
    
    elsif ( ! $taxon_no && $q->param('taxon_name') )
    {
	my $quoted_name = $dbh->quote($q->param('taxon_name'));
	my $sql = "SELECT a.taxon_no FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND taxon_name=$quoted_name ORDER BY rgt-lft DESC LIMIT 1";
	$taxon_no = ${$dbt->getData($sql)}[0]->{'taxon_no'};
    }
    
    # If we got a taxon_no value (by any of these means) then display the taxonomic hierarchy
    # rooted at that taxon.
    
    if ( $taxon_no )
    {
	my $sql = "SELECT taxon_name, taxon_rank FROM authorities WHERE taxon_no=$taxon_no";
	my ($taxon) = @{$dbt->getData($sql)};
	$title = "Classification of the " . $taxon->{'taxon_rank'} . " " . PBDB::TaxonInfo::italicize($taxon);
	$title =~ s/unranked //;
	
	$output .= displayIncludedTaxa($dbt, 'taxon_no', $taxon_no, $title);
	return $output
    }
    
    # Otherwise, let the user know that nothing matched.
    
    else
    {
	if ( ! $q->param('boxes_only') )
	{
	    return classificationForm($hbo, $s, 'Nothing matched the search term');
	}

	return;
    }
    
    # # grab all children of the parent taxon
    # if ( $taxon_no )	{
    # 	my $sql = "SELECT lft,rgt FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND a.taxon_no=".$taxon_no;
    # 	my $range = ${$dbt->getData($sql)}[0];
    # 	if ( $range->{'lft'} + 1 == $range->{'rgt'} )	{
    # 	    if ( ! $q->param('boxes_only') )	{
    # 		return classificationForm($hbo, $s, 'Nothing is classified within this taxon');
    # 	    }
    # 	    return;
    # 	} elsif ( $range->{rgt} - $range->{lft} > 1000000 ) {
    # 	    return "<p><i>A full classification of the subtaxa is too large to display here</i></p>\n";
    # 	}
	
    # 	$sql = "SELECT $fields FROM authorities a,$TAXA_TREE_CACHE t,opinions o,refs r WHERE a.taxon_no=t.taxon_no AND t.opinion_no=o.opinion_no AND a.reference_no=r.reference_no AND t.taxon_no=t.spelling_no AND lft>=".$range->{'lft'}." AND lft<=".$range->{'rgt'}." ORDER BY lft";
    # 	@taxa = @{$dbt->getData($sql)};
    # 	$title = "the ".$taxa[0]->{'taxon_rank'}." ".PBDB::TaxonInfo::italicize( $taxa[0] );
    # 	$title =~ s/unranked //;
	
    # 	push @parents , $taxa[0];
    # 	for my $i ( 1..$#taxa )	{
    # 	    my $isChild = 0;
    # 	    for my $pre ( reverse 0..$i-1 )	{
    # 		if ( $taxa[$pre]->{'rgt'} > $taxa[$i]->{'lft'} )	{
    # 		    push @{$children{$taxa[$pre]->{'taxon_no'}}} , $taxa[$i];
    # 		    $isChild++;
    # 		    last;
    # 		}
    # 	    }
    # 	    if ( $isChild == 0 )	{
    # 		push @parents , $taxa[$i];
    # 	    }
    # 	}
    # }
    
    # 	# put valid and invalid children in separate arrays
    # 	my (%valids,%invalids);
    # 	for my $t ( @taxa )	{
    # 		for my $c ( @{$children{$t->{'taxon_no'}}} )	{
    # 			if ( $c->{'status'} =~ /belongs/ && ( $c->{'lft'} + 1 < $c->{'rgt'} || $c->{'taxon_rank'} =~ /species|genus/ || $reference_no > 0 ) )	{
    # 				$c->{'status'} =~ s/belongs to/valid/;
    # 				push @{$valids{$t->{'taxon_no'}}} , $c;
    # 			} else	{
    # 				$c->{'status'} =~ s/ (of|by)//;
    # 				$c->{'status'} =~ s/subjective //;
    # 				$c->{'status'} =~ s/belongs to/empty/;
    # 				push @{$invalids{$t->{'taxon_no'}}} , $c;
    # 			}
    # 		}
    # 		if ( $valids{$t->{'taxon_no'}} )	{
    # 			@{$valids{$t->{'taxon_no'}}} = sort { $a->{'taxon_name'} cmp $b->{'taxon_name'} } @{$valids{$t->{'taxon_no'}}};
    # 		}
    # 	}
    
    # $output .= $hbo->populateHTML('js_classification');
    # if ( ! $q->param('boxes_only') )	{
    # 	$output .= "<center><p class=\"pageTitle\">Classification of $title</p></center>\n\n";
    # }
    
    # $output .= "<div class=\"verysmall\" style=\"width: 50em; margin-left: auto; margin-right: auto;\">\n\n";
    
    # # Create an object to keep track of taxon counts across recursive invocations of
    # # &traverse. 
    
    # my $counts = { children => \%children,
    # 		   valids => \%valids,
    # 		   invalids => \%invalids,
    # 		   at_level => undef,
    # 		   max_depth => 0,
    # 		   shown_depth => 0,
    # 		   sum_children => 0 };
    
    # # don't display every name, only the top-level ones
    
    # for my $p ( @parents )	
    # {
    # 	$counts->{at_level} = [ ];
    # 	$counts->{shown_depth} = 9999;
    # 	$counts->{sum_children} = 0;
	
    # 	traverse( $counts, $p, 1 );
	
    # 	for my $i ( 1..9 )
    # 	{
    # 	    $counts->{sum_children} += $counts->{at_level}[$i];
    # 	    if ( $counts->{sum_children} >= 10 && $i > 1 )
    # 	    {
    # 		$counts->{shown_depth} = $i;
    # 		if ( $counts->{sum_children} <= 30 )	{
    # 		    $counts->{shown_depth} = $i + 1;
    # 		}
    # 		last;
    # 	    }
    # 	}
	
    # 	$output .= printBox( $counts, $p, 1 );
    # }
    
    # $output .= "\n</div>\n\n";
    
    # if ( ! $q->param('boxes_only') )	{
    # 	$output .= makeFormPostTag('doDownloadTaxonomy');
    # 	$output .= qq|<input type="hidden" name="action" value="displayDownloadTaxonomyResults">\n|;
    # 	if ( $taxon_no ) {
    # 	    $output .= qq|<input type="hidden" name="taxon_no" value="$taxon_no">\n|;
    # 	}
    # 	if ( $reference_no ) {
    # 	    $output .= qq|<input type="hidden" name="reference_no" value="$reference_no">\n|;
    # 	}
    # 	$output .= "</form>\n";
    # 	return $output;
    # }
    
    # return $#taxa + 1;
}


# displayIncludedTaxa ( dbt, type, argument, title )
# 
# This routine is intended to be called from either checkTaxonInfo or classify. It displays the
# taxonomic hierarchy associated with either a particular taxon_no or a particular reference_no.
# The argument $type must be either 'taxon_no' or 'reference_no', and $argument must contain the
# corresponding value.
#
# If $title is specified, include its value as a title preceding the rest of the output.

sub displayIncludedTaxa {
    
    my ($dbt, $type, $arg_no, $title) = @_;
    
    my $output = '';
    
    my $fields = "a.taxon_no, a.taxon_name, a.taxon_rank, a.common_name, a.extant, o.status, if(ref_is_authority='YES',r.author1last,a.author1last) as author1last, if(ref_is_authority='YES',r.author2last,a.author2last) as author2last, if(ref_is_authority='YES',r.otherauthors,a.otherauthors) as otherauthors, if(ref_is_authority='YES',r.pubyr,a.pubyr) as pubyr, t.lft, t.rgt";
    
    my (@taxa, @parents, %children, $sql);
    
    # If we are given a reference_no argument, then get all of the opinions in the corresponding
    # reference and display them in a hierarchy.
    
    if ( $type eq 'reference_no' )
    {
	my $reference_no = $arg_no;
	
	# First grab all of the taxa that are the subject (child) of opinions associated with this
	# reference.
	
	$sql = "SELECT $fields, o.parent_spelling_no
		FROM opinions as o join authorities as a on a.taxon_no = o.child_spelling_no
			join $TAXA_TREE_CACHE as t on t.taxon_no = a.taxon_no
			join refs as r on r.reference_no = a.reference_no
		WHERE o.reference_no = $reference_no and ref_has_opinion = 'YES'";
	
	@taxa = @{$dbt->getData($sql)};
	
	# Then grab all of the parent taxa that are not themselves classified by this reference.
	
	$sql = "SELECT $fields
		FROM opinions as o join authorities as a on a.taxon_no = o.parent_spelling_no
			join $TAXA_TREE_CACHE as t on t.taxon_no = a.taxon_no
			join refs as r on r.reference_no = a.reference_no
		WHERE o.reference_no = $reference_no AND ref_has_opinion='YES' and
			o.parent_spelling_no <> 
			ALL (SELECT o.child_spelling_no FROM opinions as o
			     WHERE o.reference_no = $reference_no AND ref_has_opinion='YES')
		GROUP BY o.parent_spelling_no";
	
	push @taxa, @{$dbt->getData($sql)};
	
	# Now install the parent-child relationships into %children.
	
	foreach my $taxon ( @taxa )
	{
	    if ( my $parent_no = $taxon->{parent_spelling_no} )
	    {
		push @{$children{$parent_no}}, $taxon;
	    }

	    else
	    {
		push @parents, $taxon;
	    }
	}
    }

    # Otherwise we have a taxon_no value, so display the hierarchy composed of the close children
    # of the specified taxon. If this taxon has many subtaxa, we do our query on taxon_trees
    # rather than taxa_tree_cache because the newer table contains a 'depth' field. It is probably
    # okay to rely on that, but we are going to execute this inside an eval because there are no
    # other places in the classic code where taxon_trees is referred to and it would be a good
    # idea to be able to run classic on a database without that table.

    elsif ( $type eq 'taxon_no' )
    {
	my $taxon_no = $arg_no;
	
	eval {
	    
	    my $sql = "SELECT orig_no, min_rank, lft, rgt-lft as 'range'
		FROM $TAXON_TREES as t join authorities as a using (orig_no)
		WHERE a.taxon_no = $taxon_no";
	    
	    my $result = ${$dbt->getData($sql)}[0];
	    
	    # If we don't get a result, fall back to taxa_tree_cache.
	    
	    return unless $result && $result->{lft};
	    
	    # Also fall back to taxa_tree_cache for any taxon whose rank is family or below, and those
	    # whose lft-rgt range does not exceed 100000. This will allow newly added low ranking taxa
	    # to be displayed. (Any taxa added since the last table rebuild will be in taxa_tree_cache
	    # but not in taxon_trees).
	    
	    return unless $result->{min_rank} > 9 && $result->{rank} <= 23 || $result->{range} > 100000;
	    
	    $sql = "SELECT $fields
		FROM authorities as a join $TAXON_TREES as t on a.taxon_no = t.spelling_no
			join refs as r using (reference_no)
			join opinions as o using (opinion_no)
			join $TAXON_TREES as base on t.lft between base.lft and base.rgt
		WHERE base.orig_no = $result->{orig_no} and t.depth < base.depth + 6
		ORDER BY t.lft";
	    
	    @taxa = @{$dbt->getData($sql)};
	};
	
	# If we didn't get any taxa from taxon_trees, check the range and classification in
	# taxa_tree_cache.
	
	unless ( @taxa )
	{    
	    my $sql = "SELECT lft, rgt-lft as 'range', opinion_no FROM $TAXA_TREE_CACHE WHERE taxon_no = $taxon_no";
	    
	    my $result = ${$dbt->getData($sql)}[0];
	    
	    # If the taxon has no lft value, or if we get no result at all, we don't know anything about
	    # its subtaxa.
	    
	    unless ( $result && $result->{lft} )
	    {
		return "<p><i>No information on subtaxa.</i></p>";
	    }
	    
	    # If the range is too large, we have to punt because the query would otherwise take too
	    # long. But we use a wider range than above because the taxon-adding process expands the range
	    # of many taxa.
	    
	    if ( $result && $result->{range} > 300000 )
	    {
		return "<p><i>A full classification of the subtaxa is too large to display here</i></p>\n";
	    }
	    
	    # If the range is not too large, query using taxa_tree_cache.
	    
	    $sql = "SELECT $fields
		FROM authorities as a join $TAXA_TREE_CACHE as t using (taxon_no)
			join refs as r using (reference_no)
			join opinions as o using (opinion_no)
			join $TAXA_TREE_CACHE as base on t.lft between base.lft and base.rgt
		WHERE base.taxon_no = $taxon_no and t.taxon_no = t.spelling_no
		ORDER BY lft";
	    
	    @taxa = @{$dbt->getData($sql)};
	}
	
	# However we got them, collect up the entries into a hierarchy.
	
	push @parents, $taxa[0];
	
	for my $i ( 1..$#taxa )
	{
	    my $isChild = 0;
	    for my $pre ( reverse 0..$i-1 )
	    {
		if ( $taxa[$pre]->{rgt} > $taxa[$i]->{lft} )
		{
		    push @{$children{$taxa[$pre]->{taxon_no}}}, $taxa[$i];
		    $isChild++;
		    last;
		}
	    }
	    if ( $isChild == 0 )
	    {
		push @parents, $taxa[$i];
	    }
	}
    }
    
    # Put valid and invalid children in separate arrays.
    
    my (%valids, %invalids);
    
    foreach my $t ( @taxa )
    {
	for my $c ( @{$children{$t->{'taxon_no'}}} )
	{
	    if ( $c->{status} =~ /belongs/ &&
		 ( $c->{lft} + 1 < $c->{rgt} || $c->{taxon_rank} =~ /species|genus/ ) )
	    {
		$c->{status} =~ s/belongs to/valid/;
		push @{$valids{$t->{taxon_no}}}, $c;
	    }
	    
	    else
	    {
		$c->{status} =~ s/ (of|by)//;
		$c->{status} =~ s/subjective //;
		$c->{status} =~ s/belongs to/empty/;
		push @{$invalids{$t->{taxon_no}}}, $c;
	    }
	}
	
	if ( $valids{$t->{taxon_no}} )
	{
	    @{$valids{$t->{taxon_no}}} = sort { $a->{taxon_name} cmp $b->{taxon_name} } @{$valids{$t->{taxon_no}}};
	}
    }
    
    # If we were given a title, add it now.
    
    if ( $title )
    {
	$output .= "<center><p class=\"pageTitle\">$title</p></center>\n\n";
    }
    
    # Put the rest of the output inside a <div>.
    
    $output .= "<div class=\"verysmall\" style=\"width: 50em; margin-left: auto; margin-right: auto;\">\n\n";
    
    # Create an object to keep track of taxon counts across recursive invocations of
    # &traverse. 
    
    my $counts = { children => \%children,
		   valids => \%valids,
		   invalids => \%invalids,
		   at_level => undef,
		   max_depth => 0,
		   shown_depth => 0,
		   sum_children => 0,
		   box_hierarchy => { },
		 };
    
    # don't display every name, only the top-level ones
    
    for my $p ( @parents )
    {
	$counts->{at_level} = [ ];
	$counts->{shown_depth} = 9999;
	$counts->{sum_children} = 0;
	
	traverse( $counts, $p, 1 );
	
	for my $i ( 1..9 )
	{
	    $counts->{sum_children} += $counts->{at_level}[$i];
	    if ( $counts->{sum_children} >= 10 && $i > 1 )
	    {
		$counts->{shown_depth} = $i;
		if ( $counts->{sum_children} <= 30 )	{
		    $counts->{shown_depth} = $i + 1;
		}
		last;
	    }
	}
	
	$output .= printBox( $counts, $p, 1 );
    }
    
    $output .= "\n</div>\n\n";

    # Now add the box hierarchy in JSON form.

    $output .= qq|<script language="JavaScript" type="text/javascript">\n|;
    $output .= "var box_hierarchy = {\n";
    
    foreach my $key ( keys %{$counts->{box_hierarchy}} )
    {
	if ( ref $counts->{box_hierarchy}{$key} eq 'ARRAY' && @{$counts->{box_hierarchy}{$key}} )
	{
	    $output .= "  \"$key\": [";
	    $output .= join(',', map("'$_'", @{$counts->{box_hierarchy}{$key}}));
	    $output .= "],\n";
	}
    }
    
    $output =~ s/,$//; # take out improper last comma
    $output .= "};\n</script>\n\n";
    
    return $output;
}


# traverse ( )
# 
# Recursively count children and terminals.

sub traverse {
    
    my ($counts, $taxon, $depth) = @_;
    
    my $taxon_no = $taxon->{taxon_no};
    return unless $taxon_no;
    
    if ( $depth > $counts->{max_depth} )
    {
	$counts->{max_depth} = $depth;
    }
    
    $counts->{at_level}[$depth] += scalar( @{$counts->{children}{$taxon_no}} );
    
    foreach my $t ( @{$counts->{valids}{$taxon_no}} )
    {
	traverse( $counts, $t, $depth+1 );
    }
    
    return;
}


# printBox ( )
#
# Recursively print boxes including taxon names and subtaxa.

sub printBox {
    my ($counts, $taxon, $depth) = @_;
    my $output = '';
    
    my $taxon_no = $taxon->{taxon_no};
    my @children;
    
    foreach my $t ( @{$counts->{valids}{$taxon_no}} )
    {
	push @children, "t$t->{taxon_no}" if $t->{taxon_no};
    }
    
    if ( $counts->{invalids}{$taxon_no} )
    {
	push @children, "t${taxon_no}bad";
    }
    
    $counts->{box_hierarchy}{"t$taxon_no"} = \@children;
    
    my $list = join(',',\@children);
    
    my $extant = ( $taxon->{'extant'} !~ /y/i ) ? "&dagger;" : "";
    my $taxoninfo = PBDB::TaxonInfo::italicize($taxon);
    my $rank = $shortranks{$taxon->{'taxon_rank'}} // 'Unr.';
    my $name = "$rank $extant" . makeAnchor("checkTaxonInfo", "taxon_no=$taxon_no&is_real_user=1", $taxoninfo);

    $name .= " ".PBDB::TaxonInfo::formatShortAuthor($taxon) if $taxon->{'author1last'};
    $name .= " [".$taxon->{'common_name'}."]" if $taxon->{'common_name'};
    
    my $class = ( $depth <= $counts->{shown_depth} ) ? 'shownClassBox' : 'hiddenClassBox';
    my $style = ( $depth == 1 ) ? ' style="border-left: 0px; margin-bottom: 0.8em; "' : '';
    
    $output .= qq|  <div id="t$taxon_no" id="classBox" class="$class"$style> |;
    
    my $firstMargin = ( $depth <= $counts->{shown_depth} ) ? "0em" : "0em";
    
    if ( @children )
    {
	$output .= qq|    <div id="n$taxon_no" class="classTaxon" style="margin-bottom: $firstMargin;" onClick="showHide('t$taxon_no');">|;
    }
    
    else	{
	$output .= qq|    <div id="n$taxon_no" class="classTaxon">|;
    }
    
    $output .= "$name</div>\n";
    
    if ( $depth == 1 )
    {
	$output .= qq|    <div id="top$taxon_no" class="classHotCorner" style="font-size: 1em;"><span onClick="showAll('top$taxon_no');">show all</span> \| <span onClick="collapseChildren('t$taxon_no');">hide all</span></div>|;
    }
    
    elsif ( $depth > 1 && $depth < $counts->{shown_depth} && @children )
    {
	$output .= qq|    <div id="hot$taxon_no" class="classHotCorner" style="font-size: 1em;" onClick="showHide('t$taxon_no');">hide</div>|;
    }
    
    elsif ( $depth > 1 && @children )
    {
	$output .= qq|    <div id="hot$taxon_no" class="classHotCorner" style="font-size: 1em;" onClick="showHide('t$taxon_no');">+</div>|;
    }
    
    foreach my $t ( @{$counts->{valids}{$taxon_no}} )
    {
	$output .= printBox( $counts, $t, $depth+1 );
    }
    
    if ( $counts->{invalids}{$taxon_no} )
    {
	my $class = ( $depth + 1 <= $counts->{shown_depth} ) ? 'shownClassBox' : 'hiddenClassBox';
	$output .= qq|  <div id="t${taxon_no}bad" class="$class">|;
	
	@{$counts->{invalids}{$taxon_no}} = sort { $a->{'taxon_name'} cmp $b->{'taxon_name'} } @{$counts->{invalids}{$taxon_no}};

	my @badList;
	push @badList , PBDB::TaxonInfo::italicize($_)." ".PBDB::TaxonInfo::formatShortAuthor($_)." [".$_->{'status'}."]" foreach @{$counts->{invalids}{$taxon_no}};
	my $marginTop = ( $list ) ? "0.5em" : "0.5em;";
	
	$output .= "Invalid names: ".join(', ',@badList)."</div>\n";
    }
    
    $output .= "  </div>\n";
    
    return $output;
}


1;
