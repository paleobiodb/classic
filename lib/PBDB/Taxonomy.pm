# 
# Paleobiology Database -- Taxonomy.pm
# 
# This module contains routines for fetching taxonomic information from the database.
# 

package PBDB::Taxonomy;

use strict;

use PBDB::DBTransactionManager;
use PBDB::Constants qw($TAXA_TREE_CACHE);

use Data::Dumper qw(Dumper);
use Carp qw(carp);

use Exporter qw(import);

our (@EXPORT_OK) = qw(getOriginalCombination getTaxa getTaxonNos getContainerTaxon
		      getClassification getAllClassification 
		      getMostRecentSpelling getCachedSpellingNo isMisspelling getAllSpellings
		      getSeniorSynonym getJuniorSynonyms getAllSynonyms
		      getParent getParents getClassOrderFamily
		      getChildren getImmediateChildren getTypeTaxonList
		      disusedNames nomenChildren splitTaxon validTaxonName
		      getBestClassification computeMatchLevel);

our $DEBUG = 0;

sub getOriginalCombination {
    
    my ($dbt, $taxon_no, $restrict_to_ref) = @_;
    
    my $dbh = $dbt->dbh;
    
    return unless $taxon_no && $taxon_no =~ /^\d+$/;
    
    # If $restrict_to_ref is given, it must be a reference_no value. Return the original
    # combination according to this reference only.
    
    my $restr = '';
    
    if ( $restrict_to_ref )
    {
	$restr = " AND o.reference_no = $restrict_to_ref";
    }
    
    # Look for an opinion that links the specified taxon as child_spelling_no to a
    # different taxon as child_no. This other taxon is almost always the original
    # combination.
    
    my $sql =  "SELECT DISTINCT o.child_no FROM opinions as o
		WHERE o.child_spelling_no = $taxon_no and o.child_no <> o.child_spelling_no
		AND (o.status_old is null or o.status_old <> 'ignore') $restr";
    
    my ($orig_no) = $dbh->selectrow_array($sql);
    
    # If we find one, repeat the query using $orig_no just in case there is a chain. We
    # can skip this if $restrict_to_ref was specified, because each reference should give
    # only a single child_no for each child_spelling_no.
    
    my $guard = 0;
    
    while ( $orig_no && ! $restrict_to_ref && $guard++ < 10 )
    {
	$sql = "SELECT DISTINCT o.child_no FROM opinions as o
		WHERE o.child_spelling_no = $orig_no and o.child_no <> o.child_spelling_no
		and o.child_no <> $taxon_no
		and (o.status_old is null or o.status_old <> 'ignore')";
	
	my ($child_no) = $dbh->selectrow_array($sql);
	
	if ( $child_no )
	{
	    $orig_no = $child_no;
	}
	
	else
	{
	    last;
	}
    }
    
    # If we cannot find an original combination in the opinions table, check that the
    # taxon is present in the authorities table. If it is found, then it is its own
    # original combination. Otherwise, return undef.
    
    unless ( $orig_no )
    {
	$sql = "SELECT taxon_no FROM authorities WHERE taxon_no = $taxon_no";
	
	($orig_no) = $dbh->selectrow_array($sql);
    }
    
    return $orig_no;
    
    # The following two queries are no longer used after the taxonomy rewrite by Michael
    # McClennen, 2023-06-17.
    
    # unless ( @results )
    # {
    # 	$sql = "SELECT DISTINCT o.child_no FROM opinions as o
    # 		WHERE o.child_no = $taxon_no
    # 		AND (o.status_old is null or o.status_old <> 'ignore') $restr";
	
    # 	@results = @{$dbt->getData($sql)};
    # }
    
    # unless ( @results )
    # {
    # 	$sql = "SELECT DISTINCT o.parent_no AS child_no FROM opinions as o
    # 		WHERE o.parent_spelling_no = $taxon_no
    # 		AND (o.status_old is null or o.status_old <> 'ignore') $restr";
	
    # 	@results = @{$dbt->getData($sql)};
    # }
}


# getClassification ( dbt, taxon_no )
# 
# Return the classification opinion for the specified taxon from taxa_tree_cache.

sub getClassification {
    
    my ($dbt, $taxon_no) = @_;
    
    return unless $taxon_no;
    
    my $dbh = $dbt->dbh;
    
    my $sql = "SELECT o.opinion_no, o.status, o.spelling_reason, o.figures, o.pages,
		coalesce(co.orig_no, o.child_spelling_no) as child_no, o.child_spelling_no,
		coalesce(po.orig_no, o.parent_spelling_no) as parent_no, o.parent_spelling_no,
		o.reference_no, o.ref_has_opinion, o.phylogenetic_status,
		if(o.pubyr != '', o.pubyr, r.pubyr) as pubyr,
		if(o.pubyr != '', o.author1last, r.author1last) as author1last,
	        if(o.pubyr != '', o.author2last, r.author2last) as author2last,
		if(o.pubyr != '', o.otherauthors, r.otherauthors) as otherauthors
	FROM $TAXA_TREE_CACHE as t join opinions as o using (opinion_no)
		join refs as r using (reference_no)
		left join auth_orig as co on co.taxon_no = o.child_spelling_no
		left join auth_orig as po on po.taxon_no = o.parent_spelling_no
	WHERE t.taxon_no=$taxon_no";
    
    if ( my $result = $dbh->selectrow_hashref($sql) )
    {
	return $result;
    }
    
    else
    {
	return getAllClassification($dbt, $taxon_no);
    }
}


# getAllClassification ( dbt, orig_no, options )
# 
# Return all classification opinions for the specified taxon. Include classification
# opinions for other spelling variants except for misspellings, and from junior synonyms.
# 
# Accepted options include:
# 
# reference_no      Only return opinions from the specified reference.
# 
# no_synonyms       Do not return opinions for junior synonyms.
# 
# no_nomens         Do not return opinions whose status is nomen dubium, etc.
# 
# If this function is called in scalar context, return just the most recent and reliable
# classification opinion. 

sub getAllClassification {
    
    my ($dbt, $orig_no, $options) = @_;
    
    # Query for classification opinions on this taxon according to the specified options.
    # Rank them in order of reliability, publication year, and most recently added.
    
    # Unless we are asked not to consider synonyms, look for opinions on junior synonyms
    # as well.
    
    my @synonyms = $orig_no;
    
    unless ( $options->{no_synonyms} || $options->{reference_no} )
    {
        push @synonyms, getJuniorSynonyms($dbt, $orig_no, "equal");
    }
    
    my $synonyms = join("','", @synonyms);
    
    my $sql = "SELECT a.taxon_name, a.taxon_rank, o.status, o.spelling_reason, o.figures, o.pages,
		coalesce(co.orig_no, o.child_spelling_no) as child_no, o.child_spelling_no,
		coalesce(po.orig_no, o.parent_spelling_no) as parent_no, o.parent_spelling_no,
		o.opinion_no, o.reference_no, o.ref_has_opinion, o.phylogenetic_status,
                if(o.pubyr != '', o.pubyr, r.pubyr) as pubyr,
		if(o.pubyr != '', o.author1last, r.author1last) as author1last,
		if(o.pubyr != '', o.author2last, r.author2last) as author2last,
		if(o.pubyr != '', o.otherauthors, r.otherauthors) as otherauthors,
                if((o.basis != '' AND o.basis IS NOT NULL), CASE o.basis
			WHEN 'second hand' THEN 1
			WHEN 'stated without evidence' THEN 2
			WHEN 'implied' THEN 2
			WHEN 'stated with evidence' THEN 3 ELSE 2 END, 
		    if(r.reference_no = 6930, 0, if(ref_has_opinion IS NULL, 2, CASE r.basis
			WHEN 'second hand' THEN 1
			WHEN 'stated without evidence' THEN 2
			WHEN 'stated with evidence' THEN 3
			ELSE 2 END))) as reliability_index
	FROM opinions o
		left join auth_orig as co on co.taxon_no = o.child_spelling_no
		left join auth_orig as po on po.taxon_no = o.parent_spelling_no
		left join authorities as a on a.taxon_no = o.child_spelling_no
		left join refs as r on r.reference_no = o.reference_no
	WHERE coalesce(co.orig_no, o.child_spelling_no) in ('$synonyms') 
	    and coalesce(po.orig_no, o.parent_spelling_no) not in ('$synonyms')
	    and (o.status like '%nomen%' or o.parent_no > 0)
            and o.status not in ('misspelling of','homonym of')
            and (co.orig_no=$orig_no or
		    (o.status='belongs to' and a.taxon_rank NOT IN ('species','subspecies')))";
    
    # The last clause guarantees that a synonymy opinion on a synonym is
    #  not chosen JA 14.6.07
    # combinations of species are irrelevant because a species must be
    #  directly assigned to its current genus regardless of what is said
    #  about junior synonyms, or something is really wrong JA 19.6.07
    
    if ($options->{reference_no})
    {
        $sql .= " AND o.reference_no=$options->{reference_no} AND o.ref_has_opinion='YES'";
    }
    
    if ($options->{no_nomens})
    {
        $sql .= " AND o.status NOT LIKE '%nomen%'";
    }
    
    $sql .= "\n	ORDER BY reliability_index DESC, pubyr DESC, opinion_no DESC";
    
    my @rows;
    
    my $dbh = $dbt->{dbh};
    
    my $result = $dbh->selectall_arrayref($sql, { Slice => { } });
    
    push @rows, @$result if ref $result eq 'ARRAY';
    
    # The following doesn't seem very important, so I am removing it:  MM 2023.05.18
    
    # # one publication may have yielded two opinions if it classified two
    # #  taxa currently considered to be synonyms, and there is no way I can
    # #  figure out to deal with this in SQL, so we need to remove duplicates
    # #  after the fact JA 16.6.07
    # my %on_child_no = ();
    # for my $r ( @rows )	{
    #     if ( $r->{'child_no'} == $orig_no )	{
    #         $on_child_no{$r->{'author1last'}." ".$r->{'author2last'}." ".$r->{'otherauthors'}." ".$r->{'pubyr'}}++;
    #     }
    # }
    # my @cleanrows = ();
    # for my $r ( @rows )	{
    #     if ( $r->{'child_no'} == $orig_no || ! $on_child_no{$r->{'author1last'}." ".$r->{'author2last'}." ".$r->{'otherauthors'}." ".$r->{'pubyr'}} )	{
    #         push @cleanrows , $r;
    #     }
    # }
    # @rows = @cleanrows;
    
    # If this function is called in list context, return the entire result set.
    
    if ( wantarray )
    {
	return @rows;
    }
    
    # Otherwise return the first opinion, which will be the one ranked highest by
    # reliability and publication year.
    
    else
    {
	return $rows[0];
    }
}


# greatly simplified this function 22.1.09 JA
# before opinion_no was stashed in taxa_tree_cache it replicated much of
#  getMostRecentClassification by finding the most recent parent opinion

sub getMostRecentSpelling {
    
    my ($dbt, $orig_no, $options) = @_;
    
    $options ||= { };
    
    return unless $orig_no && $orig_no =~ /^\d+$/;
    return if ($options->{reference_no} eq '0');
    
    my $dbh = $dbt->dbh;
    
    my ($sql, $spelling_no, $opinion_no, $reason);
    
    if ( $options->{'reference_no'} )
    {
        $sql = "SELECT child_spelling_no FROM opinions as o join auth_orig as ao
			on ao.taxon_no = o.child_spelling_no
		WHERE o.reference_no=$options->{reference_no} and o.ref_has_opinion='YES'
		    and ao.orig_no='$orig_no'";
	
	($spelling_no) = $dbh->selectrow_array($sql);
    }
    
    else
    {
        $sql = "SELECT spelling_no, opinion_no FROM $TAXA_TREE_CACHE as t
		WHERE taxon_no=$orig_no";
	
	($spelling_no, $opinion_no) = $dbh->selectrow_array($sql);
	
        # currently only used by PBDB::CollectionEntry::getSynonymName, so it doesn't
        #  need to work in combination with reference_no
	
        if ( $options->{'get_spelling_reason'} )
	{
            $sql = "SELECT spelling_reason FROM opinions WHERE opinion_no='$opinion_no'";
	    
	    ($reason) = $dbh->selectrow_array($sql);
        }
    }
    
    $spelling_no ||= $orig_no;		# If we can't find the taxon anywhere,
                                        # guess that $orig_no is the correct
                                        # spelling.
    
    $sql = "SELECT a2.taxon_name as original_name, a.taxon_no, a.taxon_name, 
		a.common_name, a.taxon_rank, a.discussion, a.discussed_by, 
		a.type_locality, a.enterer_no
	    FROM authorities as a, authorities as a2
	    WHERE a.taxon_no=$spelling_no AND a2.taxon_no=$orig_no";
    
    my $result = $dbh->selectall_arrayref($sql, { Slice => { } });
    
    if ( ref $result eq 'ARRAY' )
    {
        if ( $options->{get_spelling_reason} )
	{
	    $result->[0]{spelling_reason} = $reason;
	}
	
	return $result->[0];
    }
    
    else
    {
        my $taxon = getTaxa($dbt,{'taxon_no'=>$orig_no});
        $taxon->{'spelling_reason'} = "original spelling";
        return $taxon;
    }
}


sub getCachedSpellingNo {
    
    my ($dbt, $taxon_no) = @_;
    
    return unless $taxon_no && $taxon_no =~ /^\d+$/;
    
    my $dbh = $dbt->dbh;
    
    my $quoted = $dbh->quote($taxon_no);
    
    my $sql = "SELECT spelling_no FROM $TAXA_TREE_CACHE WHERE taxon_no = $quoted";
    
    my ($spelling_no) = $dbh->selectrow_array($sql);
    
    $spelling_no ||= $taxon_no;
    
    return $spelling_no;
}


sub isMisspelling {
    my ($dbt,$taxon_no) = @_;
    my $answer = 0;
    my $sql = "SELECT count(*) cnt FROM opinions WHERE child_spelling_no='$taxon_no'
		AND status='misspelling of'";
    my $row = ${$dbt->getData($sql)}[0];
    return $row->{'cnt'};
}

# PS, used to be selectMostRecentParentOpinion, changed to this to simplify code 
# PS, changed from getMostRecentParentOpinion to _getMostRecentParentOpinion, to denote
# this is an interval function not to be called directly.  call getMostRecentClassification
# or getMostRecentSpelling instead, depending on whats wanted.  Because
# of lapsus calami (misspelling of) cases, these functions will differ occassionally, since a lapsus is a 
# special case that affects the spelling but doesn't affect the classification
# and consolidate bug fixes 04/20/2005


# Small utility function, added 01/06/2005
# Lump_ranks will cause taxa with the same name but diff rank (same taxa) to only pass
# back one taxon_no (it doesn't really matter which)
sub getTaxonNos {
    my ($dbt,$name,$rank,$lump_ranks,$author,$year,$type_body_part,$preservation) = @_;
    my @taxon_nos = ();
    if ( $dbt && ( $name || $author || $year || $type_body_part || $preservation ) )  {
        my $dbh = $dbt->dbh;
        my $sql;
        $sql = "SELECT a.taxon_no FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no";
        if ( $author || $year )	{
            $sql = "SELECT a.taxon_no FROM authorities a,$TAXA_TREE_CACHE t,refs r WHERE a.taxon_no=t.taxon_no AND a.reference_no=r.reference_no ";
        }
        if ( $name )	{
            #$sql .= " AND (a.taxon_name LIKE ".$dbh->quote($name)." OR a.common_name LIKE ".$dbh->quote($name).")";
        }
	
	if ( $name )
	{
	    my $quoted_name = $dbh->quote($name);
	    $sql .= " AND (a.taxon_name LIKE $quoted_name OR a.common_name LIKE $quoted_name)";
	}
	
	if ( $rank )
	{
	    my $quoted_rank = $dbh->quote($rank);
	    $sql .= " AND taxon_rank=$quoted_rank";
	}
	
	if ( $author )
	{
	    my $quoted_author = $dbh->quote($author);
	    $sql .= " AND ((ref_is_authority='Y' AND (r.author1last=$quoted_author OR r.author2last=$quoted_author)) OR (ref_is_authority='' AND (a.author1last=$quoted_author OR a.author2last=$quoted_author)))";
	}
	
	if ( $year )
	{
	    my $quoted_year = $dbh->quote($year);
	    $sql .= " AND ((ref_is_authority='Y' AND r.pubyr=$quoted_year) OR (ref_is_authority='' AND a.pubyr=$quoted_year))";
	}
	
	if ( $type_body_part )
	{
	    $sql .= " AND type_body_part=".$dbh->quote($type_body_part);
	}
	
	if ( $preservation )
	{
	    $sql .= " AND preservation=".$dbh->quote($preservation);
	}
	
        if ($lump_ranks) {
            $sql .= " GROUP BY t.lft,t.rgt";
        }
        $sql .= " ORDER BY cast(t.rgt as signed)-cast(t.lft as signed) DESC";
        my @results = @{$dbt->getData($sql)};
        push @taxon_nos, $_->{'taxon_no'} for @results;
    }
    return @taxon_nos;
}

# Now a large centralized function, PS 5/3/2006
# @taxa_rows = getTaxa($dbt,\%options,\@fields)
# Pass it a $dbt object first, a hashref of options, an arrayref of fields. See examples.
# arrayref of fields is optional, default fields returned at taxon_no,taxon_name,taxon_rank
# arrayref of fields can all be values ['*'] and ['all'] to get all fields. Note that is fields
# requested are any of the pubyr or author fields (author1init, etc) then this function will
# do a join with the references table automatically and pull the data from the ref if it is the
# authority for you. So no need to hit the refs table separately afterwords; 
#
# Returns a array of hashrefs, like getData
#
# valid options: 
#  reference_no - Get taxa with reference_no as their reference
#  taxon_no - Get taxon with taxon-no
#  taxon_name - Get all taxa with taxon_name
#  taxon_rank - Restrict search to certain ranks
#  authorizer_no - restrict to authorizeer
#  match_subgenera - the taxon_name can either match the genus or subgenus.  Note taht
#    this is very slow since it has to do a full table scan
#  pubyr - Match the pubyr
#  authorlast - Match against author1last, author2last, and otherauthors
#  created - get records created before or after a date
#  created_before_after: whether to get records created before or after the created date.  Valid values
#  are 'before' and 'after'.  Default is 'after'
#
# Example usage: 
#   Example 1: get all taxa attached to a reference. fields returned are taxon_no,taxon_name,taxon_rank
#     @results = getTaxa($dbt,{'reference_no'=>345}); 
#     my $first_taxon_name = $results[0]->{taxon_name}
#   Example 2: get all records named chelonia, and transparently include pub info (author1last, pubyr, etc) directly in the records
#     even if that pub. info is stored in the reference and ref_is_authority=YES
#     @results = getTaxa($dbt,{'taxon_name'=>'Chelonia'},['taxon_name','taxon_rank','author1last','author2last','pubyr');  
#   Example 3: get all records where the genus or subgenus is Clymene, get all fields
#     my %options;
#     $options{taxon_name}='Clymene';
#     $options{match_subgenera}=1;
#     @results = getTaxa($dbt,\%options,['*']);
#   Example 4: get record where taxon_no is 555.  Note that we don't pass back an array, he get the (first) hash record directly
#     $taxon = getTaxa($dbt,'taxon_no'=>555);

sub getTaxa {
    my $dbt = shift;
    my $options = shift;
    my $fields = shift;
    my $dbh = $dbt->dbh;

    if ( $options->{'ignore_common_name'} )	{
        $options->{'common_name'} = "";
    }

    my $join_refs = 0;
    my @where = ();
    if ($options->{'taxon_no'}) {
        push @where, "a.taxon_no=".int($options->{'taxon_no'});
    } else {
        if ($options->{'common_name'}) {
            push @where, "common_name=".$dbh->quote($options->{'common_name'});
        }
        if ($options->{'taxon_rank'}) {
            push @where, "taxon_rank=".$dbh->quote($options->{'taxon_rank'});
        }
        if ($options->{'reference_no'}) {
            push @where, "a.reference_no=".int($options->{'reference_no'});
        }
        if ($options->{'authorizer_no'}) {
            push @where, "a.authorizer_no=".int($options->{'authorizer_no'});
        }
        if ($options->{'created'}) {
            my $sign = ($options->{'created_before_after'} eq 'before') ? '<=' : '>=';
            push @where, "a.created $sign ".$dbh->quote($options->{'created'});
        }
        if ($options->{'pubyr'}) {
            my $pubyr = $dbh->quote($options->{'pubyr'});
            push @where,"((a.ref_is_authority NOT LIKE 'YES' AND a.pubyr LIKE $pubyr) OR (a.ref_is_authority LIKE 'YES' AND r.pubyr LIKE $pubyr))";
            $join_refs = 1;
        }
        if ($options->{'author'}) {
            my $author = $dbh->quote($options->{'author'});
            my $authorWild = $dbh->quote('%'.$options->{'author'}.'%');
            push @where,"((a.ref_is_authority NOT LIKE 'YES' AND (a.author1last LIKE $author OR a.author2last LIKE $author OR a.otherauthors LIKE $authorWild)) OR".
                        "(a.ref_is_authority LIKE 'YES' AND (r.author1last LIKE $author OR r.author2last LIKE $author OR r.otherauthors LIKE $authorWild)))";
            $join_refs = 1;
        }
    }

    my @fields;
    if ($fields) {
        @fields = @$fields;
        if  ($fields[0] =~ /\*|all/) {
            @fields = ('taxon_no','reference_no','taxon_rank','taxon_name','common_name','type_taxon_no','type_specimen','museum','catalog_number','type_body_part','part_details','type_locality','extant','preservation','form_taxon','ref_is_authority','author1init','author1last','author2init','author2last','otherauthors','pubyr','pages','figures','comments','discussion');
        }
        foreach my $f (@fields) {
            if ($f =~ /^author(1|2)(last|init)$|otherauthors|pubyr$/) {
                $f = "IF (a.ref_is_authority LIKE 'YES',r.$f,a.$f) $f";
                $join_refs = 1;
            } else {
                $f = "a.$f";
            }
        }
    } else {
        @fields = ('a.taxon_no','a.taxon_name','a.common_name','a.taxon_rank');
    }
    if ($options->{'remove_rank_change'})	{
        push @fields , 'spelling_no';
    }
    my $base_sql = "SELECT ".join(",",@fields)." FROM authorities a";
    if ($join_refs) {
        $base_sql .= " LEFT JOIN refs r ON a.reference_no=r.reference_no";
    }

    # finally rewrote this function to take advantage of taxa_tree_cache
    #  when this option is used JA 7.5.13
    # note that the old code returned the original combination, but users will
    #  want the current combination in most cases instead
    if ($options->{'remove_rank_change'})	{
        $base_sql .= " LEFT JOIN $TAXA_TREE_CACHE t ON a.taxon_no=t.taxon_no";
    }

    my @results = ();
    if ($options->{'match_subgenera'} && $options->{'taxon_name'}) {
        my ($genus,$subgenus,$species,$subspecies) = splitTaxon($options->{'taxon_name'});
        my $species_sql = "";
        if ($species =~ /[a-z]/) {
            $species_sql .= " $species";
        }
        if ($subspecies =~ /[a-z]/) {
            $species_sql .= " $subspecies";
        }
        my $taxon1_sql;
	my $quoted_name = $dbh->quote($options->{taxon_name});
        if ($options->{'ignore_common_name'})	{
            $taxon1_sql = "(taxon_name LIKE $quoted_name)";
        } else	{
            $taxon1_sql = "(taxon_name LIKE $quoted_name OR common_name LIKE $quoted_name)";
        }
        
        my $sql = "($base_sql WHERE ".join(" AND ",@where,$taxon1_sql).")";
        if ($subgenus) {
            # Only exact matches for now, may have to rethink this
	    my $quoted = $dbh->quote("$subgenus$species_sql");
            my $taxon3_sql = "taxon_name LIKE $quoted";
            $sql .= " UNION ";
            $sql .= "($base_sql WHERE ".join(" AND ",@where,$taxon3_sql).")";
        } else {
            $sql .= " UNION ";
            my $taxon2_sql = "taxon_name LIKE '% ($genus)$species_sql'";
            $sql .= "($base_sql WHERE ".join(" AND ",@where,$taxon2_sql).")";
        }
        if ($options->{'remove_rank_change'})	{
            $sql = "SELECT * FROM ($sql) x GROUP BY spelling_no";
        }
        @results = @{$dbt->getData($sql)};
    } else {
        if ($options->{'taxon_name'}) {
	    my $quoted_name = $dbh->quote($options->{'taxon_name'});
            if ($options->{'ignore_common_name'})	{
                push @where,"(a.taxon_name LIKE $quoted_name)";
            } else	{
                push @where,"(a.taxon_name LIKE $quoted_name OR a.common_name LIKE $quoted_name)";
            }
        }
        if (@where) {
            my $sql = $base_sql." WHERE ".join(" AND ",@where); 
            if ($options->{'remove_rank_change'})	{
                $sql = "SELECT * FROM ($sql) x GROUP BY spelling_no";
            }
            $sql .= " ORDER BY taxon_name" if ($options->{'reference_no'});
            @results = @{$dbt->getData($sql)};
        }
    }

    if (wantarray) {
        return @results;
    } else {
        return $results[0];
    }
}

# Keep going until we hit a belongs to, recombined, corrected as, or nomen *
# relationship. Note that invalid subgroup is technically not a synonym, but
# treated computationally the same 

sub getSeniorSynonym {
    
    my ($dbt, $taxon_no, $options) = @_;
    
    $options ||= { };
    
    my %seen = ();
    my $status;
    my $synonym_no = $taxon_no;
    
    $options->{no_synonyms} = 1;
    
    # Limit this to 10 iterations, in case we have some weird loop
    
    for (my $i=0;$i<10;$i++)
    {
        my $parent = getAllClassification($dbt, $synonym_no, $options);
	
        last if (!$parent || !$parent->{'child_no'});
        if ($seen{$parent->{'child_no'}}) {
            # If we have a loop, disambiguate using last entered
            # JA: the code to use the reliability/pubyr data instead was
            #  written by PS and then commented out, possibly because of a
            #  conflict elsewhere, but these data should be used instead
            #  14.6.07
            #my @rows = sort {$b->{'opinion_no'} <=> $a->{'opinion_no'}} values %seen;
            my @rows = sort {$b->{'reliability_index'} <=> $a->{'reliability_index'} || 
                             $b->{'pubyr'} <=> $a->{'pubyr'} || 
                             $b->{'opinion_no'} <=> $a->{'opinion_no'}} values %seen;
            $synonym_no = $rows[0]->{'parent_no'};
            last;
        } else {
            $seen{$parent->{'child_no'}} = $parent;
            if ($parent->{'status'} =~ /synonym|replaced|subgroup|nomen/ && $parent->{'parent_no'} > 0)	{
                $synonym_no = $parent->{'parent_no'};
                $status = $parent->{'status'};
            } else {
                last;
            }
        } 
    }
    
    # Return the synonym_no and optionally the status as well.
    
    if ( $options->{status} )
    {
        return ($synonym_no, $status);
    }
    
    else
    {
        return $synonym_no;
    }
}

# They may potentialy be chained, so keep going till we're done. Use a queue
# isntead of recursion to simplify things slightly and original combination must
# be passed in. Use a hash to keep track to avoid duplicate and recursion Note
# that invalid subgroup is technically not a synoym, but treated computationally
# the same

sub getJuniorSynonyms {
    
    my ($dbt, $t, $rank) = @_;

    my %seen_syn = ();
    my $senior;
    my $recent = getAllClassification($dbt, $t, { no_synonyms => 1 } );
    
    if ( $recent->{status} =~ /synonym|replaced|subgroup|nomen/ && $recent->{parent_no} > 0 )
    {
	$senior = $recent->{'parent_no'};
    }
    
    my @queue = ();
    push @queue, $t;
    
    for (my $i = 0; $i<50; $i++)
    {
	my $taxon_no = pop(@queue) || last;
	
	my $sql = "SELECT DISTINCT child_no
		    FROM opinions WHERE parent_no=$taxon_no AND child_no != parent_no";
	
	my @results = @{$dbt->getData($sql)};
	
	foreach my $row (@results)
	{
	    my $parent = getAllClassification($dbt, $row->{'child_no'}, { no_synonyms => 1 });
	    
	    if ($parent->{'parent_no'} == $taxon_no && 
		( $parent->{'status'} =~ /synonym|replaced/ || 
		  ( $rank ne "equal" && $parent->{'status'} =~ /subgroup|nomen/ ) ) && 
		$parent->{'child_no'} != $t)
	    {
		if (!$seen_syn{$row->{'child_no'}})
		{
		    # the most recent opinion on the focal taxon could be that
		    # it is a synonym of its synonym if this opinion has
		    # priority, then the focal taxon is the legitimate synonym
		    
		    if ( $row->{'child_no'} == $senior && $parent->{'parent_no'} == $t && 
			 $t != $senior && 
			 ( $recent->{'reliability_index'} > $parent->{'reliability_index'} ||
			   ( $recent->{'reliability_index'} == $parent->{'reliability_index'} && 
			     $recent->{'pubyr'} > $parent->{'pubyr'} ) ) )
		    {
			next;
		    }
                    
		    push @queue, $row->{'child_no'};
		}
		
		$seen_syn{$row->{'child_no'}} = 1;
	    }
	}
    }
    
    return (keys %seen_syn);
}


# Get all recombinations and corrections a taxon_no could be, but not junior synonyms
# Assume that the taxon_no passed in is already an original combination

sub getAllSpellings {
    
    my ($dbt, @taxon_nos) = @_;
    
    my $dbh = $dbt->dbh;
    
    my $list = join("','", @taxon_nos);
    
    my $sql = "SELECT DISTINCT child_spelling_no as sp FROM opinions WHERE child_no in ('$list')
	       UNION SELECT DISTINCT taxon_no as sp FROM auth_orig WHERE orig_no in ('$list')
	       UNION SELECT taxon_no as sp FROM authorities WHERE taxon_no in ('$list')";
    
    my $results = $dbh->selectcol_arrayref($sql);
    
    if ( $results && @$results )
    {
	return @$results;
    }
    
    else
    {
	return @taxon_nos;
    }
}


# sub getAllSpellings {
    
#     my ($dbt, @taxon_nos) = @_;
    
#     my %all;
    
#     for (@taxon_nos)
#     {
#         $all{int($_)} = 1 if int($_);
#     }

#     if (%all)
#     {
#         my $sql = "SELECT DISTINCT child_spelling_no FROM opinions WHERE child_no IN (".join(",",keys %all).")";
#         my @results = @{$dbt->getData($sql)};
#         $all{$_->{'child_spelling_no'}} = 1 for @results;

#         $sql = "SELECT DISTINCT child_no FROM opinions WHERE child_spelling_no IN (".join(",",keys %all).")";
#         @results = @{$dbt->getData($sql)};
#         $all{$_->{'child_no'}} = 1 for @results;

#         # Bug fix: bad records with multiple original combinations
#         $sql = "SELECT DISTINCT child_spelling_no FROM opinions WHERE child_no IN (".join(",",keys(%all)).")";
#         @results = @{$dbt->getData($sql)};
#         $all{$_->{'child_spelling_no'}} = 1 for @results;

#         $sql = "SELECT DISTINCT parent_spelling_no FROM opinions WHERE status='misspelling of' AND child_no IN (".join(",",keys %all).")";
#         @results = @{$dbt->getData($sql)};
#         $all{$_->{'parent_spelling_no'}} = 1 for @results;
#     }
#     delete $all{''};
#     delete $all{'0'};
#     return keys %all;
# }

# Get all synonyms/recombinations and corrections a taxon_no could be
# Assume that the taxon_no passed in is already an original combination
sub getAllSynonyms {
    
    my ($dbt, $taxon_no) = @_;
    
    if ($taxon_no)
    {
        $taxon_no = getSeniorSynonym($dbt,$taxon_no); 
        my @js = getJuniorSynonyms($dbt,$taxon_no); 
        return getAllSpellings($dbt,@js,$taxon_no);
    }
    
    else
    {
        return ();
    }
}


# Given a list of taxa, determine the minimal taxon which contains them all.
# The argument may be a list of either taxon_no values or Taxon objects.

sub getContainerTaxon {
    
    my ($dbt, $taxa_list) = @_;
    
    my $dbh = $dbt->{dbh};
    my $sql;
    
    return unless ref $taxa_list eq 'ARRAY';
    
    my (%found, %top, $no_infinite_loop, $root_reached);
    
    # First go through the given list and determine the initial set of taxa.
    # These may either be taxon_no values (positive integers) or Taxon objects
    # with a taxon_no or orig_no field.  In any case, put each taxon_no into %top.
    
    foreach my $t (@$taxa_list)
    {
	if ( ref $t ) {
	    $top{$t->{taxon_no}} = 1 if $t->{taxon_no} > 0;
	    $top{$t->{orig_no}} = 1 if $t->{orig_no} > 0 and not $t->{taxon_no} > 0;
	} elsif ( $t > 0 ) {
	    $top{$t} = 1;
	}
    }
    
    # Now determine the parent of every taxon in %top.  Replace the contents
    # of %top with the subset of these parents whose own parents we don't yet
    # know.  Repeat until %top has fewer than two members.
    
    while ( keys %top > 1 and $no_infinite_loop < 60 )
    {
	$no_infinite_loop++;
	my $top_list = join(',', keys %top);
	
	$sql = "SELECT t.taxon_no, o.parent_spelling_no as parent_no
		FROM taxa_tree_cache as t JOIN opinions as o using (opinion_no)
		WHERE taxon_no in ($top_list) and o.parent_spelling_no > 0 and
			o.parent_spelling_no <> t.taxon_no
		GROUP BY t.taxon_no";
	
	my $results = $dbh->selectall_arrayref($sql, { Slice => {} });
	
	last unless ref $results and @$results;
	
	%top = ();
	
	# Remember all of the parent/child results.  If any of the parents is
	# taxon #1, 'Eukaryota', then note that we have reached the root of
	# the tree.
	
	foreach my $row (@$results)
	{
	    $found{$row->{taxon_no}} = $row->{parent_no};
	    $root_reached = 1 if $row->{parent_no} == 1;
	}
	
	# Now, for each parent whose own parent we don't know, put it into the
	# new iteration of %top.
	
	foreach my $row (@$results)
	{
	    unless ( exists $found{$row->{parent_no}} )
	    {
		$found{$row->{parent_no}} = 0;
		$top{$row->{parent_no}} = 1;
	    }
	}
	
	my $a = 1;	# we can stop here when debugging
    }
    
    # If we could not determine a single taxon that contains all of the input
    # taxa, and we never reached the root of the tree at any point, return 0.
    
    unless ( scalar(keys %top) == 1 or $root_reached )
    {
	return 0;
    }
    
    # Otherwise, we have a result.  But the single taxon we have found so
    # far might not be the minimal one, so we need to chain back through the
    # %found array until we find a taxon for which we have more than one
    # child.
    
    # If we reached the root of the taxon tree at any point, start there with
    # taxon 1, 'Eukaryota'.  Otherwise, we know that %top must have exactly
    # one key and so we start there.
    
    my ($top) = $root_reached ? 1 : keys %top;
    my ($child_count, $child);
    
    do
    {
	$child_count = 0;
	
	foreach my $t_no (keys %found)
	{
	    if ( $found{$t_no} == $top )
	    {
		$child_count++;
		$child = $t_no;
	    }
	}
	
	$top = $child if $child_count == 1;
    }
    while ($child_count == 1);
    
    # Now we have the minimal container taxon.  Return its senior synonym.
    
    return getSeniorSynonym($dbt, $top);
}


# The following function appears to be grossly over-complicated. As far as I can tell, we
# simply need to look for an opinion from the specified reference which mentions child_no
# as the type taxon. MM 6/27/2023

# This function returns an array of potential higher taxa for which the focal taxon can be
# a type.  The array is an array of hash refs with the following keys: taxon_no,
# taxon_name, taxon_rank, type_taxon_no, type_taxon_name, type_taxon_rank

sub getTypeTaxonList {
    
    my ($dbt, $type_taxon_no, $reference_no) = @_;
    
    my $dbh = $dbt->dbh;
    
    my $focal_taxon = getTaxa($dbt,{'taxon_no'=>$type_taxon_no});
    
    my $focal_rank = ''; $focal_rank = $focal_taxon->{taxon_rank} if $focal_taxon;
    
    # my $parents = getClassificationHash($dbt,'all',[$type_taxon_no],'array',$reference_no);
    
    # This array holds possible higher taxa this taxon can be a type taxon for
    # Note the reference_no passed to get_classification_hash - parents must be linked by opinions from
    # the same reference as the reference_no of the opinion which is currently being inserted/edited
    
    # my @parents = @{$parents->{$type_taxon_no}}; # is an array ref
    
    my @parents = getParents($type_taxon_no);

# JA: we need not just potential parents, but all immediate parents that ever
#  have been proposed, so also hit the opinion table directly 17.6.07
    
    my @parent_nos = map { $_ && $_->{taxon_no} } @parents;
    
    # for my $p ( @parents )	{
    #     push @parent_nos , $p->{'taxon_no'};
    # }
    
    # my $sql = "SELECT a.taxon_no, a.taxon_rank, a.taxon_name FROM authorities a,opinions
    # 		o WHERE child_no=". $focal_taxon->{taxon_no} ." AND taxon_rank!='".
    # 		$focal_taxon->{'taxon_rank'} ."' AND parent_no=taxon_no"; 
    
    my $sql =  "SELECT a.taxon_no, a.taxon_rank, a.taxon_name
		FROM authorities as a join opinions as o on a.taxon_no = o.parent_no
		WHERE child_no='$type_taxon_no' and taxon_rank != '$focal_rank'";
    
    if ( @parent_nos )
    {
        $sql .= " and parent_no not in (". join(',',@parent_nos) .")";
    }
    
    $sql .= " GROUP BY parent_no";
    
    push @parents , @{$dbt->getData($sql)};
    
    if ($focal_taxon->{'taxon_rank'} =~ /species/) {
        # A species may be a type for genus/subgenus only
        my @lower;
        for my $p ( @parents ) {
            if ($p->{'taxon_rank'} =~ /species|genus|subgenus/)        {
                push @lower , $p;
            }
       }
        @parents = @lower;
    } else {
        # A higher order taxon may be a type for subtribe/tribe/family/subfamily/superfamily only
        # Don't know about unranked clade, leave it for now
        my $i = 0;
        for($i=0;$i<scalar(@parents);$i++) {
            last if ($parents[$i]->{'taxon_rank'} !~ /tribe|family|unranked clade/);
        }
        splice(@parents,$i);
    }
    # This sets values in the hashes for the type_taxon_no, type_taxon_name, and type_taxon_rank
    # in addition to the taxon_no, taxon_name, taxon_rank of the parent
    foreach my  $parent (@parents) {
        my $parent_taxon = getTaxa($dbt,{'taxon_no'=>$parent->{'taxon_no'}},['taxon_no','type_taxon_no','authorizer_no']);
        $parent->{'authorizer_no'} = $parent_taxon->{'authorizer_no'};
        $parent->{'type_taxon_no'} = $parent_taxon->{'type_taxon_no'};
        if ($parent->{'type_taxon_no'}) {
            my $type_taxon = getTaxa($dbt,{'taxon_no'=>$parent->{'type_taxon_no'}});
            $parent->{'type_taxon_name'} = $type_taxon->{'taxon_name'};
            $parent->{'type_taxon_rank'} = $type_taxon->{'taxon_rank'};
        }
    }

    return @parents;
}



# Returns (higher) order taxonomic names that are no longer considered valid (disused)
# These higher order names must be the most recent spelling of the most senior
# synonym, since that's what the taxa_list_cache stores.  Taxonomic names
# that don't fall into this category aren't even valid in the first place
# so there is no point in passing them in.
# This is figured out algorithmically.  If a higher order name used to have
# children assinged into it but now no longer does, then its considered "disused"
# You may pass in a scalar (taxon_no) or a reference to an array of scalars (array of taxon_nos)
# as the sole argument and the program will figure out what you're doing
# Returns a hash reference where they keys are equal all the taxon_nos that 
# it considered no longer valid

# PS wrote this function to return higher taxa that had ever had any subtaxa
#  at any rank but no longer do, but we only need higher taxa that don't
#  currently include genera or species of any kind, so I have rewritten
#  it drastically JA 12.9.08
sub disusedNames {
    my $dbt = shift;
    my $arg = shift;
    my @taxon_nos = ();
    if (UNIVERSAL::isa($arg,'ARRAY')) {
        @taxon_nos = @$arg;
    } else {
        @taxon_nos = ($arg);
    }

    my %disused = ();

    if (@taxon_nos) {
        my ($sql,@parents,@children,@ranges,%used);

        my $taxon_nos_sql = join(",",map{int($_)} @taxon_nos);

        $sql = "SELECT lft,rgt,a.taxon_no taxon_no FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND a.taxon_no IN ($taxon_nos_sql)";
        @parents = @{$dbt->getData($sql)};

        for my $p ( @parents )	{
            if ( $p->{lft} == $p->{rgt} - 1 )	{
                $disused{$p->{taxon_no}} = 1;
            } else	{
                push @ranges , "(lft>".$p->{lft}." AND rgt<".$p->{rgt}.")";
            }
        }
        if ( ! @ranges )	{
            return \%disused;
        }

$sql = "SELECT lft,rgt FROM authorities a,$TAXA_TREE_CACHE t WHERE taxon_rank in ('genus','subgenus','species') AND a.taxon_no=t.taxon_no AND (" . join(' OR ',@ranges) . ")";
        @children = @{$dbt->getData($sql)};
        for my $p ( @parents )	{
            for my $c ( @children )	{
                if ( $c->{lft} > $p->{lft} && $c->{rgt} < $p->{rgt} )	{
                    $used{$p->{taxon_no}} = 1;
                    last;
                }
            }
        }
        for my $p ( @parents )	{
            if ( ! $used{$p->{taxon_no}} )	{
                $disused{$p->{taxon_no}} = 1;
            }
        }

    }

    return \%disused;

}

# This will get orphaned nomen * children for a list of a taxon_nos or a single taxon_no passed in.
# returns a hash reference where the keys are parent_nos and the values are arrays of child taxon objects
# The child taxon objects are just hashrefs where the hashes have the following keys:
# taxon_no,taxon_name,taxon_rank,status.  Status is nomen dubium etc, and rest of the fields are standard.
# JA: this function eventually will become obsolete because nomen ... opinions
#  are supposed to record parent_no from now on 31.8.07
# JA: it is currently used only in DownloadTaxonomy.pm
sub nomenChildren {
    my $dbt = shift;
    my $arg = shift;
    my @taxon_nos = ();
    if (UNIVERSAL::isa($arg,'ARRAY')) {
        @taxon_nos = @$arg;
    } else {
        @taxon_nos = ($arg);
    }

    my %nomen = ();
    if (@taxon_nos) {
        my $sql = "SELECT DISTINCT o2.child_no,o1.parent_no FROM opinions o1, opinions o2 WHERE o1.child_no=o2.child_no AND o2.parent_no=0 AND o2.status LIKE '%nomen%' AND o1.parent_no IN (".join(",",@taxon_nos).")";
        my @results = @{$dbt->getData($sql)};
        foreach my $row (@results) {
            my $mrpo = getClassification($dbt,$row->{'child_no'});
            if ($mrpo->{'status'} =~ /nomen/) {
                #print "child $row->{child_no} IS NOMEN<BR>";
                # This will get the most recent parent opinion where it is not classified as a %nomen%
                my $mrpo_no_nomen = getAllClassification($dbt, $row->{'child_no'},
							 { exclude_nomen => 1 });
                if ($mrpo_no_nomen->{'parent_no'} == $row->{'parent_no'}) {
                    #print "child $row->{child_no} LAST PARENT IS PARENT $row->{parent_no} <BR>";
                    my $taxon = getTaxa($dbt,{'taxon_no'=>$row->{'child_no'}});
                    $taxon->{'status'} = $mrpo->{'status'};
                    push @{$nomen{$mrpo_no_nomen->{'parent_no'}}}, $taxon;
                } else {
                    #print "child $row->{child_no} LAST PARENT IS NOT PARENT $row->{parent_no} BUT $mrpo_no_nomen->{parent_no}<BR>";
                }
            }
        }
    }
    return \%nomen;
}


# # Travel up the classification tree
# # Rewritten 01/11/2004 PS. Function is much more flexible, can do full upward classification of any 
# # of the taxon rank's, with caching to keep things fast for large arrays of input data. 
# #   * Use a upside-down tree data structure internally
# #  Arguments:
# #   * 0th arg: $dbt object
# #   * 1st arg: comma separated list of the ranks you want,i.e(class,order,family) 
# #              OR keyword 'parent' => gets first parent of taxon passed in 
# #              OR keyword 'all' => get full classification (not imp'd yet, not used yet);
# #   * 2nd arg: Takes an array of taxon names or numbers
# #   * 3rd arg: What to return: will either be comma-separated taxon_nos (numbers), taxon_names (names), or an ordered array ref hashes (array)(like $dbt->getData returns)
# #   * 4th arg: Restrict the search to a certain reference_no.  This is used by the type_taxon part of the Opinions scripts, so
# #              an authority can be a type taxon for multiple possible higher taxa (off the same ref).
# #  Return:
# #   * Returns a hash whose key is input (no or name), value is comma-separated lists
# #     * Each comma separated list is in the same order as the '$ranks' (1nd arg)input variable was in

# sub getClassificationHash {
    
#     my $dbt = shift;
#     my $ranks = shift; #all OR parent OR comma sep'd ranks i.e. 'class,order,family'
#     my $taxon_names_or_nos = shift;
#     my $return_type = shift || 'names'; #names OR numbers OR array;
#     my $ref_restrict = shift;
    
    
#     my @taxon_names_or_nos = @{$taxon_names_or_nos};
#     $ranks =~ s/\s+//g; #NO whitespace
#     my @ranks = split(',', $ranks);
#     my %rank_hash = ();
   
#     my %link_cache = (); #for speeding up 
#     my %link_head = (); #our master upside-down tree. imagine a table of pointers to linked lists, 
#                         #except the lists converge into each other as we climb up the hierarchy

#     my $highest_level = 21;
#     my %taxon_rank_order = ('superkingdom'=>0,'kingdom'=>1,'subkingdom'=>2,'superphylum'=>3,'phylum'=>4,'subphylum'=>5,'superclass'=>6,'class'=>7,'subclass'=>8,'infraclass'=>9,'superorder'=>10,'order'=>11,'suborder'=>12,'infraorder'=>13,'superfamily'=>14,'family'=>15,'subfamily'=>16,'tribe'=>17,'subtribe'=>18,'genus'=>19,'subgenus'=>20,'species'=>21,'subspecies'=>22);
#     # this gets the 'min' number, or highest we climb
#     if ($ranks[0] eq 'parent') {
#         $highest_level = 0;
#     } else {
#         foreach (@ranks) {
#             if ($taxon_rank_order{$_} && $taxon_rank_order{$_} < $highest_level) {
#                 $highest_level = $taxon_rank_order{$_};
#             }
#             if ($taxon_rank_order{$_}) {
#                 $rank_hash{$_} = 1;
#             }    
#         }
#     }

#     #dbg("get_classification_hash called");
#     #dbg('ranks'.Dumper(@ranks));
#     #dbg('highest_level'.$highest_level);
#     #dbg('return_type'.$return_type);
#     #dbg('taxon names or nos'.Dumper(@taxon_names_or_nos));

#     foreach my $hash_key (@taxon_names_or_nos){
#         my ($taxon_no, $taxon_name, $parent_no, $child_no, $child_spelling_no);
       
#         # We're using taxon_nos as input
#         if ($hash_key =~ /^\d+$/) {
#             $taxon_no = $hash_key;
#         # We're using taxon_names as input    
#         } else {    
#             my @taxon_nos = getTaxonNos($dbt, $hash_key);

#             # If the name is ambiguous (multiple authorities entries), taxon_no/child_no are undef so nothing gets set
#             if (scalar(@taxon_nos) == 1) {
#                 $taxon_no = $taxon_nos[0];
#             }    
#             $taxon_name = $hash_key;
#         }
        
#         if ($taxon_no) {
#             # Get original combination so we can move upward in the tree
#             $taxon_no = getOriginalCombination($dbt, $taxon_no);
#         }

#         $child_no = $taxon_no;
        
#         my $loopcount = 0;
#         my $sql;

#         # start the link with child_no;
#         my $link = {};
#         $link_head{$hash_key} = $link;
#         my %visits = ();
#         my $found_parent = 0;

#         #if ($child_no == 14513) {
#         #    $DEBUG = 1;
#         #}

#         # Bug fix: prevent a senior synonym from being considered a parent
	
#         $child_no = getSeniorSynonym($dbt, $child_no, { reference_no => $ref_restrict });
	
#         # prime the pump 
	
#         my $parent_row = getAllClassification($dbt, $child_no, {reference_no => $ref_restrict});
	
#         if ($DEBUG) { print STDERR "Start:".Dumper($parent_row)."<br>"; }
	
#         my $status = $parent_row->{'status'};
#         $child_no = $parent_row->{'parent_no'};
	
#         #if ($child_no == 14505) {
#         #    $DEBUG = 1;
#         #}

#         # Loop at least once, but as long as it takes to get full classification
#         for(my $i=0;$child_no && !$found_parent;$i++) {
#             #hasn't been necessary yet, but just in case
#             if ($i >= 100) { my $msg = "Infinite loop for $child_no in get_classification_hash";carp $msg; last;} 

#             # bail if we have a loop
#             $visits{$child_no}++;
#             last if ($visits{$child_no} > 1);

#             # A belongs to, rank changed as, corrected as, OR recombined as  - If the previous iterations status
#             # was one of these values, then we're found a valid parent (classification wise), so we can terminate
#             # at the end of this loop (after we've added the parent into the tree)
#             if ($status =~ /^(?:bel|ran|cor|rec)/o && $ranks[0] eq 'parent') {
#                 $found_parent = 1;
#             }

#             # Belongs to should always point to original combination
#             $parent_row = getAllClassification($dbt, $child_no, {reference_no => $ref_restrict});
	    
#             if ($DEBUG) { print STDERR "Loop:".Dumper($parent_row)."<br>"; }
	    
#             # No parent was found. This means we're at end of classification, althought
#             # we don't break out of the loop till the end of adding the node since we
#             # need to add the current child still
#             my ($taxon_rank);
#             if ($parent_row) {
#                 my $taxon= getMostRecentSpelling($dbt, $child_no,
# 						 { reference_no => $ref_restrict });
#                 $parent_no  = $parent_row->{'parent_no'};
#                 $status = $parent_row->{'status'};
#                 $child_spelling_no = $taxon->{'taxon_no'};
#                 $taxon_name = $taxon->{'taxon_name'};
#                 $taxon_rank = $taxon->{'taxon_rank'};
#             } else {
#                 $parent_no=0;
#                 $child_spelling_no=$child_no;
#                 my $taxon = getTaxa($dbt, {'taxon_no'=>$child_no});
#                 $taxon_name=$taxon->{'taxon_name'};
#                 $taxon_rank=$taxon->{'taxon_rank'};
#                 $status = "";
#             }

#             # bail because we've already climbed up this part o' the tree and its cached
#             if ($parent_no && exists $link_cache{$parent_no}) {
#                 $link->{'taxon_no'} = $child_no;
#                 $link->{'taxon_name'} = $taxon_name;
#                 $link->{'taxon_rank'} = $taxon_rank;
#                 $link->{'taxon_spelling_no'} = $child_spelling_no;
#                 $link->{'next_link'} = $link_cache{$parent_no};
#                 if ($DEBUG) { print STDERR "Found cache for $parent_no:".Dumper($link)."<br>";}
#                 last;
#             # populate this link, then set the link to be the next_link, climbing one up the tree
#             } else {
#                 # Synonyms are tricky: We don't add the child (junior?) synonym onto the chain, only the parent
#                 # Thus the child synonyms get their node values replace by the parent, with the old child data being
#                 # saved into a "synonyms" field (an array of nodes)
#                 if ($DEBUG) { print STDERR "Traverse $parent_no:".Dumper($link)."<br>";}
#                 if ($status =~ /^(?:replaced|subjective|objective|invalid)/o) {
#                     if ($DEBUG) { print STDERR "Synonym node<br>";}
#                     my %node = (
#                         'taxon_no'=>$child_no,
#                         'taxon_name'=>$taxon_name,
#                         'taxon_rank'=>$taxon_rank,
#                         'taxon_spelling_no'=>$child_spelling_no
#                     );
#                     push @{$link->{'synonyms'}}, \%node;
#                     $link_cache{$child_no} = $link;
#                 } else {
#                     if ($DEBUG) { print STDERR "Reg. node<br>";}
#                     if (exists $rank_hash{$taxon_rank} || $ranks[0] eq 'parent' || $ranks[0] eq 'all') {
#                         my $next_link = {};
#                         $link->{'taxon_no'} = $child_no;
#                         $link->{'taxon_name'} = $taxon_name;
#                         $link->{'taxon_rank'} = $taxon_rank;
#                         $link->{'taxon_spelling_no'} = $child_spelling_no;
#                         $link->{'next_link'}=$next_link;
#                         if ($DEBUG) { print STDERR Dumper($link)."<br>";}
#                         $link_cache{$child_no} = $link;
#                         $link = $next_link;
#                     }
#                 }
#             }

#             # bail if we've reached the maximum possible rank
#             last if($ranks[0] ne 'all' && ($taxon_rank && $taxon_rank_order{$taxon_rank} && 
#                     $taxon_rank_order{$taxon_rank} <= $highest_level));

#             # end of classification
#             last if (!$parent_row);
            
#             # bail if its a junk nomem * relationship
#             last if ($status =~ /^nomen/);

#             # set this var to set up next loop
#             $child_no = $parent_no;
#         }
#     }

#     # flatten the linked list before passing it back, either into:
#     #  return_type is numbers : comma separated taxon_nos, in order
#     #  return_type is names   : comma separated taxon_names, in order
#     #  return_type is array   : array reference to array of hashes, in order.  
#     while(my ($hash_key, $link) = each(%link_head)) {
#         my %list= ();
#         my %visits = ();
#         my $list_ordered;
#         if ($return_type eq 'array') {
#             $list_ordered = [];
#         } else {
#             $list_ordered = '';
#         }
#         # Flatten out data, but first prepare it all
#         if ($ranks[0] eq 'parent') {
#             if ($return_type eq 'array') {
#                 push @$list_ordered,$link;
#             } elsif ($return_type eq 'names') {
#                 $list_ordered .= ','.$link->{'taxon_name'};
#             } else {
#                 $list_ordered .= ','.$link->{'taxon_spelling_no'};
#             }
#         } else {
#             while (%$link) {
#                 # Loop prevention by marking where we've been
#                 if (exists $visits{$link->{'taxon_no'}}) { 
#                     last; 
#                 } else {
#                     $visits{$link->{'taxon_no'}} = 1;
#                 }
#                 if ($return_type eq 'array') {
#                     push @$list_ordered,$link;
#                 } elsif ($return_type eq 'names') {
#                     $list{$link->{'taxon_rank'}} = $link->{'taxon_name'}; 
#                 } else {
#                     $list{$link->{'taxon_rank'}} = $link->{'taxon_spelling_no'}; 
#                 }
#                 my $link_next = $link->{'next_link'};
#                 #delete $link->{'next_link'}; # delete this to make Data::Dumper output look nice 
#                 $link = $link_next;
#             }
#             # The output list will be in the same order as the input list
#             # by looping over this array
#             if ($return_type ne 'array') {
#                 foreach my $rank (@ranks) {
#                     $list_ordered .= ','.$list{$rank};
#                 }
#             }
#         }
#         if ($return_type ne 'array') {
#             $list_ordered =~ s/^,//g;
#         }
#         $link_head{$hash_key} = $list_ordered;
#     }


#     return \%link_head;
#}


# Returns an ordered array of ancestors for a given taxon_no. Doesn't return synonyms of those ancestors 
#  b/c that functionality not needed anywhere
# return type may be:
#   array_full - an array of hashrefs, in order by lowest to highest class. Hash ref has following keys:
#       taxon_no (integer), taxon_name (string), spellings (arrayref to array of same) synonyms (arrayref to array of same)
#   array - *default* - an array of taxon_nos, in order from lowest to higher class
#   rank xxxx - returns taxon resolved to a specific rank

# Nowhere in the remaining Classic code is this routine called with any return type
# except 'array_full'. MM 2023-07-02

sub getParents {
    
    my ($dbt, $taxon_no) = @_;
    
    # returns data needed to tell if (say) a species' current combination
    #  includes (1) a valid genus name (parent_spelling_no=parent_synonym_no)
    #  that is (2) spelt correctly (opinion_parent_no=parent_spelling_no)
    # JA 19.12.08
    
    # if ($return_type =~ /immediate/) {
    #     my ($return_type,$parent_rank) = split / /,$return_type;
    #     my $sql = "select t.taxon_no taxon_no,parent_spelling_no opinion_parent_no,t2.spelling_no parent_spelling_no,t2.synonym_no parent_synonym_no,a.taxon_name parent_name,a.taxon_rank parent_rank FROM $TAXA_TREE_CACHE t,$TAXA_TREE_CACHE t2,authorities a,opinions o WHERE t.opinion_no=o.opinion_no AND parent_no=t2.taxon_no AND t2.synonym_no=a.taxon_no AND a.taxon_rank='$parent_rank' AND t.taxon_no IN (".join(',',@$taxon_nos_ref).")";
    #     my @results = @{$dbt->getData($sql)};
    #     $hash{$_->{'taxon_no'}} = $_ foreach @results;
    #     return \%hash;
    # }
    
    # my $rank;
    # if ($return_type =~ /rank (\w+)/) {
    #     $rank = $dbt->dbh->quote($1);
    # }
    
    if ( $taxon_no =~ /^(\d+)/ )
    {
	$taxon_no = $1;
    }
    
    else
    {
	return;
    }
    
        # if ($rank) {
        #     # my $sql = "SELECT a.taxon_no,a.taxon_name,a.taxon_rank,a.extant
        #     # FROM $TAXA_LIST_CACHE l, $TAXA_TREE_CACHE t, authorities a WHERE
        #     # t.taxon_no=l.parent_no AND a.taxon_no=l.parent_no AND
        #     # l.child_no=$taxon_no AND a.taxon_rank=$rank ORDER BY t.lft
        #     # DESC";
	#     my $sql = "SELECT a.taxon_no,a.taxon_name,a.taxon_rank,a.extant FROM $TAXA_TREE_CACHE as t join $TAXA_TREE_CACHE as base on t.lft <= base.lft and t.rgt >= base.rgt, authorities a WHERE a.taxon_no=t.taxon_no AND t.taxon_no = t.synonym_no and base.taxon_no=$taxon_no AND a.taxon_rank=$rank and base.lft > 0 AND base.rgt >= base.lft ORDER BY t.lft DESC";
        #     my @results = @{$dbt->getData($sql)};
        #     $hash{$taxon_no} = $results[0];
        # } elsif ($return_type eq 'array_full') {
            # my $sql = "SELECT
            # a.taxon_no,a.taxon_name,a.taxon_rank,a.common_name,a.extant, IF
            # (a.pubyr IS NOT NULL AND a.pubyr != '' AND a.pubyr != '0000',
            # a.pubyr, IF (a.ref_is_authority='YES', r.pubyr, '')) pubyr FROM
            # $TAXA_LIST_CACHE l, $TAXA_TREE_CACHE t, authorities a,refs r
            # WHERE t.taxon_no=l.parent_no AND a.taxon_no=l.parent_no AND
            # l.child_no=$taxon_no AND a.reference_no=r.reference_no ORDER BY
            # t.lft DESC";
	    
            # $hash{$taxon_no} = $dbt->getData($sql);
    #     } else {
    #         my $sql = "SELECT t.taxon_no FROM $TAXA_TREE_CACHE as t JOIN $TAXA_TREE_CACHE as base on t.lft <= base.lft and t.rgt >= base.rgt WHERE base.taxon_no=$taxon_no AND base.lft > 0 AND base.rgt >= base.lft AND t.taxon_no = t.synonym_no ORDER BY t.lft DESC";
    #         my @taxon_nos = map {$_->{'taxon_no'}} @{$dbt->getData($sql)};
    #         $hash{$taxon_no} = \@taxon_nos;
    #     }
    # }
    
    my $sql = "
	SELECT a.taxon_no, a.taxon_name, a.taxon_rank, a.common_name, a.extant,
	       if(a.pubyr is not null and a.pubyr != '' and a.pubyr != '0000', a.pubyr, 
		  if(a.ref_is_authority='YES', r.pubyr, '')) as pubyr
	FROM $TAXA_TREE_CACHE as t
		join authorities as a using (taxon_no)
		join refs as r using (reference_no)
		join $TAXA_TREE_CACHE as base on t.lft <= base.lft and t.rgt >= base.rgt
	WHERE base.taxon_no = $taxon_no and base.lft > 0 and base.rgt >= base.lft
		and t.taxon_no = t.synonym_no
	ORDER BY t.lft desc";
    
    my $dbh = $dbt->dbh;
    
    my $result = $dbh->selectall_arrayref($sql, { Slice => { } });
    
    if ( ref $result eq 'ARRAY' )
    {
	return $result->@*;
    }
    
    else
    {
	return;
    }
}


sub getClassOrderFamily	{
    
    my ($dbt, $rowref, $class_ref) = @_;
    
    my $cof = { $rowref->%* } if ref $rowref eq 'HASH';
    
    return $cof unless ref $class_ref eq 'ARRAY' && $class_ref->@*;
    
    my $top_rank = $class_ref->$#*;
    my $above_family = 0;
    
    # Run through the classification list from low rank to high, in order to identify the
    # common name and family.
    
    for my $i ( 0..$top_rank )
    {
	my $t = $class_ref->[$i];
	
	# Stop if we reach one of the ranks listed here.
	
	if ( $t->{taxon_rank} =~ /superclass|phylum|kingdom/ )
	{
	    $top_rank = $i;
	    last;
	}
	
	# Use the first common name we find.
	
	if ( ! $cof->{common_name} && $t->{common_name} )
	{
	    $cof->{common_name} = $t->{common_name};
	}
	
	# Use the first family name we find.
	
	if ( ( $t->{taxon_rank} eq "family" || $t->{taxon_name} =~ /idae$/ ) && ! $t->{family} )
	{
	    $cof->{family} = $t->{taxon_name};
	    $cof->{family_no} = $t->{taxon_no};
	}
	
	if ( $t->{taxon_rank} =~ /family|tribe|genus|species/ && $t->{taxon_rank} ne "superfamily" )
	{
	    $above_family = $i + 1;
	}
    }
    
    # we need to know which parents have ever been ranked as either a class
    #  or an order
    
    my (@other_parent_nos, %wasClass, %wasntClass, %wasOrder, %wasntOrder);
    
    # first mark names currently ranked at these levels
    
    foreach my $i ( $above_family..$top_rank )
    {
	my $t = $class_ref->[$i];
	my $taxon_no = $t->{taxon_no};
	
	if ( $t->{taxon_rank} eq 'class' )
	{
	    $wasClass{$taxon_no} = 9999;
	}
	
	elsif ( $t->{taxon_rank} eq 'order' )
	{
	    $wasOrder{$taxon_no} = 9999;
	}
	
	elsif ( $taxon_no )
	{
	    push @other_parent_nos, $taxon_no;
	}
    }
    
    # find other names previously ranked at these levels
    
    if ( @other_parent_nos )
    {
	my $parent_list = join ',', @other_parent_nos;
	
	my $sql = "
	    SELECT taxon_rank, spelling_no as parent_no, count(*) as c
		FROM $TAXA_TREE_CACHE as t
			join opinions as o on o.child_no = t.taxon_no
			join authorities as a on a.taxon_no = o.child_spelling_no
		WHERE t.spelling_no in ($parent_list)
	    UNION SELECT taxon_rank, spelling_no as parent_no, count(*) as c
		FROM $TAXA_TREE_CACHE as t
			join auth_orig as ao on ao.orig_no = t.taxon_no
			join opinions as o on o.child_spelling_no = ao.taxon_no
			join authorities as a on a.taxon_no = o.child_spelling_no
		WHERE t.spelling_no in ($parent_list)
		GROUP BY taxon_rank, child_spelling_no";
	
	# my $sql = "SELECT taxon_rank,spelling_no as parent_no,count(*) c FROM
	# authorities a,opinions o,$TAXA_TREE_CACHE t WHERE a.taxon_no=child_spelling_no
	# AND child_no=t.taxon_no AND spelling_no IN (".join(',',@other_parent_nos).")
	# GROUP BY taxon_rank,child_spelling_no";
	
	foreach my $p ( @{$dbt->getData($sql)} )
	{
	    if ( $p->{taxon_rank} eq "class" )
	    {
		$wasClass{$p->{parent_no}} += $p->{c};
	    }
	    
	    else
	    {
		$wasntClass{$p->{parent_no}} += $p->{c};
	    }
	    
	    if ( $p->{taxon_rank} eq "order" )
	    {
		$wasOrder{$p->{parent_no}} += $p->{c};
	    } 
	    
	    else
	    {
		$wasntOrder{$p->{parent_no}} += $p->{c};
	    }
	}
    }
    
    # find the oldest parent most frequently ranked an order
    # use publication year as a tie breaker
    
    my ($maxyr, $mostoften, $above_order) = ('', -9999, 0);
    
    foreach my $i ( $above_family..$top_rank )
    {
	my $t = $class_ref->[$i];
	my $taxon_no = $t->{taxon_no};
	
	if ( $wasClass{$taxon_no} > 0 || $t->{taxon_rank} =~ /phylum|kingdom/ )
	{
	    last;
	}
	
	if ( ( $wasOrder{$taxon_no} - $wasntOrder{$taxon_no} > $mostoften && 
	       $wasOrder{$taxon_no} > 0 ) || 
	     ( $wasOrder{$taxon_no} - $wasntOrder{$taxon_no} == $mostoften && 
	       $wasOrder{$taxon_no} > 0 && (! $maxyr || $t->{pubyr} < $maxyr ) ) )
	{
	    $mostoften = $wasOrder{$taxon_no} - $wasntOrder{$taxon_no};
	    $maxyr = $t->{pubyr};
	    $cof->{order} = $t->{taxon_name};
	    $cof->{order_no} = $taxon_no;
	    $above_order = $i + 1;
	}
    }
    
    # if that fails then none of the parents have ever been orders,
    #  so use the oldest name between the levels of family and
    #  at-least-once class
    
    unless ( $cof->{order_no} )
    {
	for my $i ( $above_family..$top_rank )
	{
	    my $t = $class_ref->[$i];
	    my $taxon_no = $t->{taxon_no};
	    
	    if ( ! $maxyr || $t->{pubyr} < $maxyr )
	    {
		$maxyr = $t->{pubyr};
		$cof->{order} = $t->{taxon_name};
		$cof->{order_no} = $taxon_no;
		$above_order = $i + 1;
	    }
	}
    }
    
    # find the oldest parent ever ranked as a class
    
    ($maxyr,$mostoften) = ('',-9999);
    
    foreach my $i ( $above_order..$top_rank )
    {
	my $t = $class_ref->[$i];
	my $taxon_no = $t->{taxon_no};
	
	if ( ( $wasClass{$taxon_no} - $wasntClass{$taxon_no} > $mostoften && 
	       $wasClass{$taxon_no} > 0 ) || 
	     ( $wasClass{$taxon_no} - $wasntClass{$taxon_no} == $mostoften && 
	       $wasClass{$taxon_no} > 0 && ( !$maxyr || $t->{pubyr} < $maxyr ) ) )
	{
	    $mostoften = $wasClass{$taxon_no} - $wasntClass{$taxon_no};
	    $maxyr = $t->{pubyr};
	    $cof->{class} = $t->{taxon_name};
	    $cof->{class_no} = $taxon_no;
	}
    }
    
    # otherwise we're really in trouble, so use the oldest name available
    
    if ( $cof->{class_no} == 0 )
    {
	my $start = $above_order || $above_family || 0;
	my $end = $class_ref->$#*;
	
	for my $i ( $start..$end )
	{
	    my $t = $class_ref->[$i];
	    my $taxon_no = $t->{taxon_no};
	    
	    last if $t->{taxon_rank} =~ /kingdom|phylum/;
	    
	    if ( ! $maxyr || $t->{pubyr} < $maxyr )
	    {
		$maxyr = $t->{pubyr};
		$cof->{class} = $t->{taxon_name};
		$cof->{class_no} = $taxon_no;
	    }
	}
    }
    
    return $cof;
}


# Simplified version of the above function which just returns the most senior name of the most immediate
# parent, as a hashref

sub getParent {
    
    my ($dbt, $taxon_no, $taxon_rank) = @_;
    
    my $dbh = $dbt->dbh;
    
    my $rank_filter = '';
    
    if ( $taxon_rank )
    {
	$rank_filter = "and a.taxon_rank = " . $dbh->quote($taxon_rank);
    }
    
    my $sql = "
	SELECT a.taxon_no, a.taxon_name, a.taxon_rank
	FROM $TAXA_TREE_CACHE as t
		join authorities as a using (taxon_no)
		join $TAXA_TREE_CACHE as base on t.lft <= base.lft and t.rgt >= base.rgt
	WHERE base.taxon_no = $taxon_no and base.lft > 0 AND base.rgt >= base.lft
		and t.taxon_no = t.synonym_no $rank_filter
	ORDER BY t.lft DESC LIMIT 1";
    
    my $dbh = $dbt->dbh;
    
    my $result = $dbh->selectrow_hashref($sql);
    
    return $result;
}


# Returns the immediate descendants of a taxon.

sub getImmediateChildren {
    
    my ($dbt, $taxon_no) = @_;
    
    return unless defined $taxon_no && $taxon_no > 0;
    
    my $dbh = $dbt->dbh;
    
    # First get the senior synonym. If no result is found, that means $taxon_no is not a
    # valid taxon number. 
    
    my $sql = "SELECT synonym_no FROM $TAXA_TREE_CACHE WHERE taxon_no=" . $dbh->quote($taxon_no);
    
    my ($synonym_no) = $dbh->selectrow_array($sql);
    
    if ( $synonym_no )
    {
	my ($lft, $rgt) = $dbh->selectrow_array("
		SELECT lft, rgt FROM $TAXA_TREE_CACHE WHERE taxon_no=$synonym_no");
	
	# Get a list of junior synonyms, if any.
	
	my $synonym_list = $synonym_no;
	
	$sql = "SELECT taxon_no FROM $TAXA_TREE_CACHE WHERE synonym_no=$synonym_no";
	
	my $synonym_result = $dbh->selectcol_arrayref($sql);
	
	if ( ref $synonym_result eq 'ARRAY' && $synonym_result->@* )
	{
	    $synonym_list = join(',', $synonym_result->@*);
	}
	
	my $child_list = $synonym_no;
	
	$sql = "SELECT DISTINCT child_no,child_spelling_no
		FROM opinions WHERE parent_no IN ($synonym_list)";
	
	my $child_result = $dbh->selectcol_arrayref($sql, { Columns => [1, 2] });
	
	if ( ref $child_result eq 'ARRAY' && $child_result->@* )
	{
	    $child_list = join(',', $synonym_no, $child_result->@*);
	}
	
        # Ordering is very important.  The ORDER BY tc2.lft makes sure results are
        # returned in hieracharical order, so we can build the tree in one pass below The
        # (tc2.taxon_no != tc2.spelling_no) term ensures the most recent name always comes
        # first (this simplfies later algorithm) use between and both values so we'll use
        # a key for a smaller tree;
	
        $sql = "SELECT tc.taxon_no, a1.type_taxon_no, a1.taxon_rank, a1.taxon_name, 
			tc.spelling_no, tc.lft, tc.rgt, tc.synonym_no
                FROM $TAXA_TREE_CACHE as tc join authorities as a1 using (taxon_no)
		WHERE tc.lft BETWEEN $lft AND $rgt
			and tc.synonym_no in ($child_list)
		ORDER BY tc.lft, (tc.taxon_no != tc.spelling_no)";
	
        my @results = @{$dbt->getData($sql)};
	
        my $root = shift @results;
	
        $root->{'children'}  = [];
        $root->{'synonyms'}  = [];
        $root->{'spellings'} = [];
	
        my @parents = ($root);
        my %p_lookup = ($root->{taxon_no}=>$root);
	
        foreach my $row (@results)
	{
	    last unless @parents;
	    
            # if (!@parents) {
            #     last;
            # }
	    
            my $p = $parents[0];
	    
            if ($row->{synonym_no} == $row->{taxon_no})
	    {
                $p_lookup{$row->{taxon_no}} = $row;
            }
	    
            if ($row->{'lft'} == $p->{'lft'})
	    {
                # This is a correction/recombination/rank change
                push @{$p->{'spellings'}},$row;
#                print "New spelling of parent $p->{taxon_name}: $row->{taxon_name}\n";
            }
	    
	    else
	    {
                $row->{'children'}  = [];
                $row->{'synonyms'}  = [];
                $row->{'spellings'} = [];

                while ($row->{'rgt'} > $p->{'rgt'}) {
                    shift @parents;
                    last if (!@parents);
                    $p = $parents[0];
                }
		
                if ($row->{'synonym_no'} != $row->{'spelling_no'})
		{
                    my $ss = $p_lookup{$row->{synonym_no}};
                    push @{$ss->{synonyms}}, $row;

                    #push @{$p->{'synonyms'}},$row;
#                    print "New synonym of parent $p->{taxon_name}: $row->{taxon_name}\n";
                }
		
		else
		{
                    push @{$p->{'children'}},$row;
#                    print "New child of parent $p->{taxon_name}: $row->{taxon_name}\n";
                }
                
		unshift @parents, $row;
            }
        }
	
        # Now go through and sort stuff in tree
	
        my @nodes_to_sort = ($root);
	
        while ( @nodes_to_sort )
	{
            my $node = shift @nodes_to_sort;
            my @children = sort {$a->{'taxon_name'} cmp $b->{'taxon_name'}} @{$node->{'children'}};
            $node->{'children'} = \@children;
            unshift @nodes_to_sort,@children;
        }
	
	return @results;
    }
    
    else
    {
	return;
    }
}


# Returns all the descendents of a taxon in various forms.  
#  return_type may be:
#    tree - a sorted tree structure, returns the root note (TREE_NODE datastructure, described below)
#       TREE_NODE is a hash with the following keys:
#       TREE_NODE: hash: { 
#           'taxon_no'=> integer, taxon_no of most current name
#           'taxon_name'=> most current name of taxon
#           'children'=> ref to array of TREE_NODEs
#           'synonyms'=> ref to array of TREE_NODEs
#           'spellings'=> ref to array of TREE_NODEs 
#       }
#    array - *default* - an array of taxon_nos, in no particular order

sub getChildren {
    
    my ($dbt, $taxon_no, $return_type, $no_senior_syn, $exclude_list) = @_;
    
    # The option $no_senior_syn exists for updateCache above, nasty bug if this
    # isn't set since senior synonyms children will be moved to junior synonym
    # if we do the resolution!
    
    return unless defined $taxon_no && $taxon_no > 0;
    
    my $dbh = $dbt->dbh;
    
    # First get the senior synonym
    
    unless ($no_senior_syn)
    {
	my $sql = "SELECT synonym_no FROM $TAXA_TREE_CACHE WHERE taxon_no=$taxon_no";
	
	my ($synonym_no) = $dbh->selectrow_array($sql);
	
	$taxon_no = $synonym_no || $taxon_no;
    }
    
    my $sql = "SELECT lft,rgt,synonym_no FROM $TAXA_TREE_CACHE WHERE taxon_no=$taxon_no";
    my $root_vals = ${$dbt->getData($sql)}[0];
    return unless $root_vals;
    my $lft = $root_vals->{'lft'};
    my $rgt = $root_vals->{'rgt'};
    my $synonym_no = $root_vals->{'synonym_no'};
    
    # If lft = 0, then there are no children so return just the taxon itself.
    
    unless ( defined $lft && $lft > 0 )
    {
	if ( $return_type eq 'tree' || $return_type eq 'immediate_children' )
	{
	    my $sql = "SELECT tc.taxon_no, a1.type_taxon_no, a1.taxon_rank, a1.taxon_name, tc.spelling_no, tc.lft, tc.rgt, tc.synonym_no "
                    . " FROM $TAXA_TREE_CACHE tc, authorities a1"
                    . " WHERE a1.taxon_no=tc.taxon_no"
                    . " AND tc.taxon_no = $taxon_no";
	    
	    my @results = @{$dbt->getData($sql)};
	    splice(@results,1);
	    $results[0]{children} = [];
	    $results[0]{synonyms} = [];
	    $results[0]{spellings} = [];
	}
	
	else
	{
	    return ($taxon_no);
	}
    }
    
    # Otherwise, get a list of all children.
    
    my @exclude = ();
    if (ref $exclude_list eq 'ARRAY' && @$exclude_list) {
        my $excluded = join(",",map {int} @$exclude_list);
        my $sql = "SELECT lft,rgt FROM $TAXA_TREE_CACHE WHERE taxon_no IN ($excluded)";
        foreach my $row (@{$dbt->getData($sql)}) {
            if ($row->{'lft'} > $lft && $row->{'rgt'} < $rgt) {
                push @exclude, [$row->{'lft'},$row->{'rgt'}];
            }
        }
    }

    if ($return_type eq 'tree' || $return_type eq 'immediate_children') {
        my $child_nos;
        if ($return_type eq 'immediate_children') {
            my $sql = "SELECT taxon_no FROM $TAXA_TREE_CACHE WHERE synonym_no=$synonym_no";
            my $synonym_nos = join(",",-1,map {$_->{'taxon_no'}} @{$dbt->getData($sql)});
            $sql = "SELECT DISTINCT child_no,child_spelling_no FROM opinions WHERE parent_no IN ($synonym_nos)";
            $child_nos = join(",",-1,map {($_->{'child_no'},$_->{'child_spelling_no'})} @{$dbt->getData($sql)});
        }
        # Ordering is very important. 
        # The ORDER BY tc2.lft makes sure results are returned in hieracharical order, so we can build the tree in one pass below
        # The (tc2.taxon_no != tc2.spelling_no) term ensures the most recent name always comes first (this simplfies later algorithm)
        # use between and both values so we'll use a key for a smaller tree;
        my $sql = "SELECT tc.taxon_no, a1.type_taxon_no, a1.taxon_rank, a1.taxon_name, tc.spelling_no, tc.lft, tc.rgt, tc.synonym_no "
                . " FROM $TAXA_TREE_CACHE tc, authorities a1"
                . " WHERE a1.taxon_no=tc.taxon_no"
                . " AND (tc.lft BETWEEN $lft AND $rgt)";
              # . " AND (tc.rgt BETWEEN $lft AND $rgt)";
        foreach my $exclude (@exclude) {
            $sql .= " AND (tc.lft NOT BETWEEN $exclude->[0] AND $exclude->[1])";
            $sql .= " AND (tc.rgt NOT BETWEEN $exclude->[0] AND $exclude->[1])";
        }
        if ($return_type eq 'immediate_children') {
             $sql .= " AND tc.synonym_no IN ($synonym_no,$child_nos)"
        }
        $sql .= " ORDER BY tc.lft, (tc.taxon_no != tc.spelling_no)";
        my @results = @{$dbt->getData($sql)};

        my $root = shift @results;
        $root->{'children'}  = [];
        $root->{'synonyms'}  = [];
        $root->{'spellings'} = [];
        my @parents = ($root);
        my %p_lookup = ($root->{taxon_no}=>$root);
        foreach my $row (@results) {
            if (!@parents) {
                last;
            }
            my $p = $parents[0];

            if ($row->{synonym_no} == $row->{taxon_no}) {
                $p_lookup{$row->{taxon_no}} = $row;
            }

            if ($row->{'lft'} == $p->{'lft'}) {
                # This is a correction/recombination/rank change
                push @{$p->{'spellings'}},$row;
#                print "New spelling of parent $p->{taxon_name}: $row->{taxon_name}\n";
            } else {
                $row->{'children'}  = [];
                $row->{'synonyms'}  = [];
                $row->{'spellings'} = [];

                while ($row->{'rgt'} > $p->{'rgt'}) {
                    shift @parents;
                    last if (!@parents);
                    $p = $parents[0];
                }
                if ($row->{'synonym_no'} != $row->{'spelling_no'}) {
                    my $ss = $p_lookup{$row->{synonym_no}};
                    push @{$ss->{synonyms}}, $row;

                    #push @{$p->{'synonyms'}},$row;
#                    print "New synonym of parent $p->{taxon_name}: $row->{taxon_name}\n";
                } else {
                    push @{$p->{'children'}},$row;
#                    print "New child of parent $p->{taxon_name}: $row->{taxon_name}\n";
                }
                unshift @parents, $row;
            }
        }

        # Now go through and sort stuff in tree
        my @nodes_to_sort = ($root);
        while(@nodes_to_sort) {
            my $node = shift @nodes_to_sort;
            my @children = sort {$a->{'taxon_name'} cmp $b->{'taxon_name'}} @{$node->{'children'}};
            $node->{'children'} = \@children;
            unshift @nodes_to_sort,@children;
        }
        if ($return_type eq 'immediate_children') {
            my @all_children = ();
            push @all_children, @{$root->{children}};
            foreach my $row (@{$root->{synonyms}}) {
                push @all_children, @{$row->{'children'}};
            }
            return @all_children;
        } else {
            return $root;
        }
    } else {
        # use between and both values so we'll use a key for a smaller tree;
        my $sql = "SELECT tc.taxon_no FROM $TAXA_TREE_CACHE tc WHERE "
                . "tc.lft BETWEEN $lft AND $rgt "
                . "AND tc.rgt BETWEEN $lft AND $rgt";  
        foreach my $exclude (@exclude) {
            $sql .= " AND (tc.lft NOT BETWEEN $exclude->[0] AND $exclude->[1])";
            $sql .= " AND (tc.rgt NOT BETWEEN $exclude->[0] AND $exclude->[1])";
        }
        #my $sql = "SELECT l.child_no FROM $TAXA_LIST_CACHE l WHERE l.parent_no=$taxon_no";
        my @taxon_nos = map {$_->{'taxon_no'}} @{$dbt->getData($sql)};
        return @taxon_nos;
    }
}


sub splitTaxon {
    my $name = shift;
    my ($genus,$subgenus,$species,$subspecies) = ("","","","");
  
    if ($name =~ /^([A-Z][a-z]+)(?:\s\(([A-Z][a-z]+)\))?(?:\s([a-z.]+))?(?:\s([a-z.]+))?/) {
        $genus = $1 if ($1);
        $subgenus = $2 if ($2);
        $species = $3 if ($3);
        $subspecies = $4 if ($4);
    }

    if (!$genus && $name) {
        # Loose match, capitalization doesn't matter. The % is a wildcard symbol
        if ($name =~ /^([a-z%]+)(?:\s\(([a-z%]+)\))?(?:\s([a-z.]+))?(?:\s([a-z.]+))?/) {
            $genus = $1 if ($1);
            $subgenus = $2 if ($2);
            $species = $3 if ($3);
            $subspecies = $4 if ($4);
        }
    }
    
    return ($genus,$subgenus,$species,$subspecies);
}


sub validTaxonName {
    my $taxon = shift;

    if ($taxon =~ /^([A-Z%]|% )([a-z%]+)( [a-z%]+){0,2}$/)	{
        return 1;
    } elsif ($taxon =~ /[()]/)	{
        if ($taxon =~ /^[A-Z][a-z]+ \([A-Z][a-z]+\)( [a-z]+){0,2}$/) {
            return 1;
        }
    } else	{
        if ($taxon =~ /^[A-Z][a-z]+( [a-z]+){0,2}$/) {
            return 1;
        }
    }

    return 0;
}  

# This function will determine get the best taxon_no for a taxon.  Can pass in either 
# 6 arguments, or 1 argument thats a hashref to an occurrence or reid database row 

sub getBestClassification {
    
    my $dbt = shift;
    my ($genus_reso,$genus_name,$subgenus_reso,$subgenus_name,$species_reso,$species_name);
    if (scalar(@_) == 1) {
        $genus_reso    = $_[0]->{'genus_reso'} || "";
        $genus_name    = $_[0]->{'genus_name'} || "";
        $subgenus_reso = $_[0]->{'subgenus_reso'} || "";
        $subgenus_name = $_[0]->{'subgenus_name'} || "";
        $species_reso  = $_[0]->{'species_reso'} || "";
        $species_name  = $_[0]->{'species_name'} || "";
    } else {
        ($genus_reso,$genus_name,$subgenus_reso,$subgenus_name,$species_reso,$species_name) = @_;
    }
    my $dbh = $dbt->dbh;
    my @matches = ();

    if ( $genus_reso !~ /informal/ && $genus_name) {
        my $species_sql = "";
        if ($species_reso  !~ /informal/ && $species_name =~ /^[a-z]+$/ && $species_name !~ /^sp(\.)?$|^indet(\.)?$/) {
	    my $quoted = $dbh->quote("% $species_name");
            $species_sql = "AND ((taxon_rank='species' and taxon_name like $quoted) or taxon_rank != 'species')";
        }
	my $quoted2 = $dbh->quote("$genus_name%");
	my $quoted3 = $dbh->quote("% ($genus_name)");
	my $quoted4 = $dbh->quote("$subgenus_name%");
	my $quoted5 = $dbh->quote("% ($subgenus_name)");
        my $sql = "(SELECT taxon_no,taxon_name,taxon_rank FROM authorities WHERE taxon_name LIKE $quoted2 $species_sql)";
        $sql .= " UNION ";
        $sql .= "(SELECT taxon_no,taxon_name,taxon_rank FROM authorities WHERE taxon_rank='subgenus' AND taxon_name LIKE $quoted3)";
        if ($subgenus_reso !~ /informal/ && $subgenus_name) {
            $sql .= " UNION ";
            $sql .= "(SELECT taxon_no,taxon_name,taxon_rank FROM authorities WHERE taxon_name LIKE $quoted4 $species_sql)";
            $sql .= " UNION ";
            $sql .= "(SELECT taxon_no,taxon_name,taxon_rank FROM authorities WHERE taxon_rank='subgenus' AND taxon_name LIKE $quoted5)";
        }

        #print "Trying to match $genus_name ($subgenus_name) $species_name\n";
#        print $sql,"\n";
        my @results = @{$dbt->getData($sql)};

        my @more_results = ();
        # Do this query separetly cause it needs to do a full table scan and is SLOW
        foreach my $row (@results) {
            my ($taxon_genus,$taxon_subgenus,$taxon_species) = splitTaxon($row->{'taxon_name'});
            if ($taxon_subgenus && $genus_name eq $taxon_subgenus && $genus_name ne $taxon_genus) {
                my $last_sql = "SELECT taxon_no,taxon_name,taxon_rank FROM authorities WHERE taxon_name LIKE '% ($taxon_subgenus) %' AND taxon_rank='species'";
#                print "Querying for more results because only genus didn't match but subgenus (w/g) did matched up with $row->{taxon_name}\n";
#                print $last_sql,"\n";
                @more_results = @{$dbt->getData($last_sql)};
                last;
            }
            if ($taxon_subgenus && $subgenus_name eq $taxon_subgenus && $genus_name ne $taxon_subgenus) {
                my $last_sql = "SELECT taxon_no,taxon_name,taxon_rank FROM authorities WHERE taxon_name LIKE '% ($taxon_subgenus) %' and taxon_rank='species'";
#                print "Querying for more results because only genus didn't match but subgenus (w/subg) did matched up with $row->{taxon_name}\n";
#                print $last_sql,"\n";
                @more_results = @{$dbt->getData($last_sql)};
                last;
            }
        }                     

        foreach my $row (@results,@more_results) {
            my ($taxon_genus,$taxon_subgenus,$taxon_species,$taxon_subspecies) = splitTaxon($row->{'taxon_name'});
            if (!$taxon_subspecies) {
                my $match_level = computeMatchLevel($genus_name,$subgenus_name,$species_name,$taxon_genus,$taxon_subgenus,$taxon_species);
                if ($match_level > 0) {
                    $row->{'match_level'} = $match_level;
                    push @matches, $row;
#                    print "MATCH found at $match_level for matching occ $genus_name $subgenus_name $species_name to taxon $row->{taxon_name}\n";
                }
            }
        }
    }

    @matches = sort {$b->{'match_level'} <=> $a->{'match_level'}} @matches;

    if (wantarray) {
        # If the user requests a array, then return all matches that are in the same class.  The classes are
        #  30: exact match, no need to return any others
        #  20-29: species level match
        #  10-19: genus level match
        if (@matches) {
            my $best_match_class = int($matches[0]->{'match_level'}/10);
            my @matches_in_class;
            foreach my $row (@matches) {
                my $match_class = int($row->{'match_level'}/10);
                if ($match_class >= $best_match_class) {
                    push @matches_in_class, $row;
                }
            }
            return @matches_in_class;
        } else {
            return ();
        }
    } else {
        # If the user requests a scalar, only return the best match, if it is not a homonym
        if (scalar(@matches) > 1) {
            if ($matches[0]->{'taxon_name'} eq $matches[1]->{'taxon_name'}) {
                # matches are homonyms - if they're the same taxon thats been reranked, return
                # the original.
                my $orig0 = getOriginalCombination($dbt,$matches[0]->{'taxon_no'});
                my $orig1 = getOriginalCombination($dbt,$matches[1]->{'taxon_no'});
                if ($orig0 == $orig1) {
                    if ($matches[0]->{taxon_no} == $orig0) {
                        return $orig0;
                    } elsif ($matches[1]->{taxon_no} == $orig1) {
                        return $orig1;
                    } else {
                        return $matches[0]->{taxon_no};
                    }
                } else {
                    # homonym and not a reranking - return a 0
                    return 0;
                }
            } else {
                # Not a homonym, just some stray subgenus match or something still return the best
                return $matches[0]->{'taxon_no'};
            }
            return $matches[0]->{'taxon_no'}; # Dead code
        } elsif (scalar(@matches) == 1) {
            return $matches[0]->{'taxon_no'};
        } else {
            return 0;
        }
    }
}


# This function takes two taxonomic names -- one from the occurrences/reids
# table and one from the authorities table (broken down in genus (g), 
# subgenus (sg) and species (s) components -- use splitTaxonName to
# do this for entries from the authorities table) and compares
# How closely they match up.  The higher the number, the better the
# match.
# 
# < 30 but > 20 = species level match
# < 20 but > 10 = genus/subgenus level match
# 0 = no match
sub computeMatchLevel {
    my ($occ_g,$occ_sg,$occ_sp,$taxon_g,$taxon_sg,$taxon_sp) = @_;

    my $match_level = 0;
    return 0 if ($occ_g eq '' || $taxon_g eq '');

    if ($taxon_sp) {
        if ($occ_g eq $taxon_g && 
            $occ_sg eq $taxon_sg && 
            $occ_sp eq $taxon_sp) {
            $match_level = 30; # Exact match
        } elsif ($occ_g eq $taxon_g && 
                 $occ_sp && $taxon_sp && $occ_sp eq $taxon_sp) {
            $match_level = 28; # Genus and species match, next best thing
        } elsif ($occ_g eq $taxon_sg && 
                 $occ_sp && $taxon_sp && $occ_sp eq $taxon_sp) {
            $match_level = 27; # The authorities subgenus being used a genus
        } elsif ($occ_sg eq $taxon_g && 
                 $occ_sp && $taxon_sp && $occ_sp eq $taxon_sp) {
            $match_level = 26; # The authorities genus being used as a subgenus
        } elsif ($occ_sg && $taxon_sg && $occ_sg eq $taxon_sg && 
                 $occ_sp && $taxon_sp && $occ_sp eq $taxon_sp) {
            $match_level = 25; # Genus don't match, but subgenus/species does, pretty weak
        } 
    } elsif ($taxon_sg) {
        if ($occ_g eq $taxon_g  &&
            $occ_sg eq $taxon_sg) {
            $match_level = 19; # Genus and subgenus match
        } elsif ($occ_g eq $taxon_sg) {
            $match_level = 17; # The authorities subgenus being used a genus
        } elsif ($occ_sg eq $taxon_g) {
            $match_level = 16; # The authorities genus being used as a subgenus
        } elsif ($occ_sg eq $taxon_sg) {
            $match_level = 14; # Subgenera match up but genera don't, very junky
        }
    } else {
        if ($occ_g eq $taxon_g) {
            $match_level = 18; # Genus matches at least
        } elsif ($occ_sg eq $taxon_g) {
            $match_level = 15; # The authorities genus being used as a subgenus
        }
    }
    return $match_level;
}



1;
