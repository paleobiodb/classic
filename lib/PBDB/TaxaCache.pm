#
# This module updates the table 'taxa_tree_cache' to reflect changes in the set of active
# opinion and authority records. The taxa_tree_cache holds a modified preorder
# traversal tree of the taxonomic names in the PBDB.
#
# PS 09/22/2005
#

package PBDB::TaxaCache;

use strict;

use PBDB::Taxonomy qw(getOriginalCombination getSeniorSynonym
		      getClassification getAllClassification 
		      getAllSpellings getCachedSpellingNo);

use PBDB::Constants qw($TAXA_TREE_CACHE);

use Carp qw(carp);

use feature 'say';

use Exporter qw(import);

our @EXPORT_OK = qw($DEBUG getSyncTime setSyncTime updateCache updateOrig
		    addTaxaCacheRow);

our ($DEBUG);


# our ($logfh);


# BEGIN {
#     open($logfh, '>>', "logs/taxa_cached.log") || 
# 	die "ERROR: could not open taxa_cached.log: $!\n";
    
#     $logfh->autoflush(1);
# }


# my %opinions;
# my %allchildren;
# my %spellings;
# my %processed;


# The following two routines get and set the last synchronization time of
# taxa_tree_cache with the opinions and refs tables.

sub getSyncTime {
    
    my ($dbh) = @_;
    
    my ($time) = $dbh->selectrow_array("SELECT sync_time FROM tc_sync WHERE sync_id=1");
    
    return $time;
}


sub setSyncTime {
    
    my ($dbh, $time) = @_;
    
    my $sql = "REPLACE INTO tc_sync (sync_id, sync_time) VALUES (1, '$time')";
    
    $dbh->do($sql); 
}


# updateOrig ( dbt, taxon_no )
# 
# Check the orig_no for the specified taxon according to the opinions. If it has
# changed, record the change in auth_orig and authorities.

sub updateOrig {
    
    my ($dbt, $taxon_no) = @_;
    
    my $dbh = $dbt->dbh;
    my $orig_no;
    
    if ( $taxon_no =~ /^\d+$/ && $taxon_no > 0 )
    {
	$orig_no = getOriginalCombination($dbt, $taxon_no);
    }
    
    else
    {
	return;
    }
    
    my $sql;
    my $result;
    my $updateList = 0;
    
    # Get the current orig_no for this taxon, and see it if it has changed.
    
    $sql = "SELECT orig_no FROM auth_orig WHERE taxon_no=$taxon_no";
    
    my ($check_orig) = $dbh->selectrow_array($sql);
    
    # If there is an existing orig_no for this taxon that is different from the one
    # computed above, update it.
    
    if ( $check_orig && $orig_no ne $check_orig )
    {
	$sql = "UPDATE auth_orig SET orig_no=$orig_no WHERE taxon_no=$taxon_no";
	
	$result = $dbh->do($sql);
	
	say "Updating orig_no for $taxon_no to $orig_no (result=$result)" if $DEBUG;
    }
    
    # If there isn't an existing orig_no, set it now.
    
    elsif ( ! $check_orig )
    {
	$sql = "REPLACE INTO auth_orig (taxon_no, orig_no)
		VALUES ($taxon_no, $orig_no)";
	
	$result = $dbh->do($sql);
	
	say "Creating orig_no for $taxon_no as $orig_no (result=$result)" if $DEBUG;
    }
    
    # If the authorities record needs to be changed, update that too.
    
    $sql = "SELECT orig_no FROM authorities WHERE taxon_no=$taxon_no";
    
    my ($from_auth) = $dbh->selectrow_array($sql);
    
    unless ( $from_auth && $orig_no eq $from_auth )
    {
	$sql = "UPDATE authorities SET orig_no=$orig_no, modified=modified
		WHERE taxon_no=$taxon_no";
	
	$result = $dbh->do($sql);
	
	say "Updating authority record for $taxon_no (result=$result)" if $DEBUG;
    }
}


# updateCache ( dbt, taxon_no )
# 
# This will do its best to synchronize taxa_tree_cache with the opinions table
# This function should be called whenever a new opinion is added into the database, whether
# its from Taxon.pm or Opinion.pm.  Its smart enough not to move stuff around if it doesn't have
# to.  The code is broken into two main sections.  The first section combines any alternate
# spellings that have with the original combination, and the second section deals with the
# the taxon changing parents and thus shifting its left and right values.
#
# IMPORTANT
# this function is only ever called by /../scripts/taxa_cached.pl, which
#  runs continously, so you need to kill it and restart it to debug (JA)

sub updateCache {
    
    my ($dbt, $taxon_no) = @_;
    
    my $dbh = $dbt->dbh;
    my $orig_no;
    
    my ($sql, $result);
    
    # If we have a valid $taxon_no, grab the orig_no from the auth_orig table.
    # We can assume this is valid, because updateOrig should have been
    # called on this taxon first.
    
    if ( $taxon_no =~ /^\d+$/ && $taxon_no > 0 )
    {
	$sql = "SELECT orig_no FROM auth_orig WHERE taxon_no=$taxon_no";
	
	($orig_no) = $dbh->selectrow_array($sql);
    }
    
    # Ignore any call with an invalid $taxon_no argument.
    
    else
    {
	return;
    }
    
    # Retrieve all opinions for this taxon, including opinions on junior
    # synonyms.
    
    my @opinions = getAllClassification($dbt, $orig_no);
    
    my $mrpo = $opinions[0];
    
    # Retrieve all spellings for this taxon.
    
    my @spellings = getAllSpellings($dbt, $orig_no);
    
    # Determine the spelling_no, synonym_no, and opinion_no.
    
    my $spelling_no = $orig_no;
    my $synonym_no = $orig_no;
    my $opinion_no = 0;
    
    if ( @opinions )
    {
	$opinion_no = $opinions[0]{opinion_no};
	
	my $genus = $opinions[0]{taxon_name};
	my $species;
	
	if ( $opinions[0]{taxon_rank} =~ /species/ )
	{
	    ($genus, $species) = split / /,$opinions[0]{taxon_name};
	}
	
	# find a valid spelling if you can
	# have to make sure the opinion isn't on a synonym JA 28.8.11
	
	for my $r ( @opinions )
	{
	    if ( $r->{spelling_reason} ne "misspelling" && 
		 $opinions[0]{taxon_rank} eq $r->{taxon_rank} && 
		 ( $r->{taxon_rank} !~ /species/ || $r->{taxon_name} =~ /$genus / ) && 
		 $opinions[0]{child_no} == $r->{child_no} )
	    {
		$synonym_no = $r->{child_spelling_no};
		$spelling_no = $r->{child_spelling_no};
		last;
	    }
	}
	
	if ( $opinions[0]{status} ne "belongs to" && $opinions[0]{parent_no} > 0 )
	{
	    $synonym_no = $opinions[0]{parent_spelling_no};
	}
	
	# if the belongs to opinion has been borrowed from a junior synonym, we need
	# to figure out the correct spelling default to child_no because there may
	# be no opinion at all on it JA 9.3.09
	
	if ( $opinions[0]{child_no} != $taxon_no )
	{
	    $spelling_no = $taxon_no;
	    
	    for my $i ( 1..$#opinions )
	    {
		if ( $opinions[$i]{child_no} == $taxon_no && 
		     $opinions[$i]{status} ne "misspelling of" && 
		     $opinions[$i]{spelling_reason} ne "misspelling" )
		{
		    $spelling_no = $opinions[$i]{child_spelling_no};
		    last;
		}
	    }
        
	    # if the name is valid, the synonym_no must also be fixed
        
	    if ( $synonym_no != $opinions[0]{parent_spelling_no} )
	    {
		$synonym_no = $spelling_no;
	    }
	}
    }
    
    # If the senior synonym itself has a senior synonym, fetch it now.
    
    my $senior_synonym_no = getSeniorSynonym($dbt, $synonym_no);
    
    $synonym_no = getCachedSpellingNo($dbt, $senior_synonym_no) || $synonym_no;
    
    # If there isn't already a row in taxa_tree_cache for this taxon, add it now.
    
    $sql = "SELECT taxon_no FROM $TAXA_TREE_CACHE WHERE taxon_no=$orig_no";
    
    my ($has_row) = $dbh->selectrow_array($sql);
    
    # # Start a new transaction.
    
    # unless ( $dbh->begin_work )
    # {
    # 	$messages .= "AutoCommit was already off\n";
    # 	warn "AutoCommit was already off";
    # }
    
    unless ( $has_row )
    {
	addTaxaCacheRow($dbt, $orig_no, $spelling_no, $synonym_no, $opinion_no);
    }
    
    # Update the rows corresponding to all spellings to match the new
    # information. Any which are missing (i.e. which correspond to newly added
    # spellings) will be created below.
    
    my $spellings = join("','", $orig_no, @spellings);
    
    $sql = "UPDATE $TAXA_TREE_CACHE SET spelling_no=$spelling_no, synonym_no=$synonym_no, opinion_no=$opinion_no WHERE taxon_no in ('$spellings')";
    
    $result = $dbh->do($sql);
    
    print STDOUT "$sql : result=$result\n" if $DEBUG;
    
    # Now retrieve the new/updated row.
    
    $sql = "SELECT taxon_no, lft, rgt, spelling_no, synonym_no
	    FROM $TAXA_TREE_CACHE WHERE taxon_no='$orig_no'";
    
    my $cache_row = $dbh->selectrow_hashref($sql);
    
    # First section: combine any new spellings that have been added into the
    # original combination, and add cache rows for them.
    
    my @upd_rows = ();
    
    foreach my $spelling_no (@spellings)
    {
	my $sql = "SELECT taxon_no,lft,rgt,spelling_no,synonym_no
		FROM $TAXA_TREE_CACHE WHERE taxon_no=$spelling_no";
	
	my $spelling_row = $dbh->selectrow_hashref($sql);
	
	unless ( $spelling_row )
	{
	    $spelling_row = addTaxaCacheRow($dbt, $spelling_no, 
					    $spelling_no, $synonym_no, $opinion_no);
	}
	
	# If a spelling no hasn't been combined yet, combine it now
	
	if ($spelling_row->{lft} != $cache_row->{lft})
	{
	    my $lft = $spelling_row->{lft};
	    my $rft = $spelling_row->{rgt};
	    
	    # if the alternate spelling had children (not too likely), get a list of them
	    
	    if ( $rft - $lft > 2 )
	    {
		$sql = "SELECT taxon_no FROM $TAXA_TREE_CACHE
			WHERE lft between $lft and $rft
			ORDER BY lft, (taxon_no != spelling_no)";
		
		my $children = $dbh->selectcol_arrayref($sql);
		
		if ( ref $children eq 'ARRAY' )
		{
		    foreach my $child_no ( @$children )
		    {
			moveChildren($dbt, $child_no, $orig_no);
		    }
		}
	    }
	    
	    # Refresh the cache row from the db since it may have been changed above
	    
	    $sql = "SELECT taxon_no,lft,rgt,spelling_no,synonym_no FROM $TAXA_TREE_CACHE WHERE taxon_no=$orig_no";
	    $cache_row = $dbh->selectrow_hashref($sql);
	    
	    $sql = "SELECT taxon_no,lft,rgt,spelling_no,synonym_no FROM $TAXA_TREE_CACHE WHERE taxon_no=$spelling_no";
	    $spelling_row = $dbh->selectrow_hashref($sql);
	    
	    # Combine the spellings
	    
	    if ( $spelling_row->{lft} > 0 )
	    {
		$sql = "UPDATE $TAXA_TREE_CACHE SET lft=$cache_row->{lft},rgt=$cache_row->{rgt} WHERE lft=$spelling_row->{lft}";
		
		$result = $dbh->do($sql);
		
		print STDOUT "Combining spellings $spelling_no with $orig_no: " .
		    "$sql : result=$result\n" if $DEBUG;
	    }
	}
    }
    
    # If 'lft' is not 0, then we need to update all of the entries that share
    # the same 'lft' value.
    
    if ( $cache_row->{lft} > 0 )
    {
	$sql = "UPDATE $TAXA_TREE_CACHE SET spelling_no=$spelling_no WHERE lft=$cache_row->{lft}"; 
	
	$result = $dbh->do($sql);
	
	print STDOUT "Updating spelling with $spelling_no: $sql : result=$result\n" if $DEBUG;
	
	# Change it so the senior synonym no points to the senior synonym's most correct name
	# for this taxa and any of ITs junior synonyms
	
	$sql = "UPDATE $TAXA_TREE_CACHE SET synonym_no=$synonym_no WHERE lft=$cache_row->{lft} OR (lft >= $cache_row->{lft} AND rgt <= $cache_row->{rgt} AND synonym_no=$cache_row->{synonym_no})"; 
	
	$result = $dbh->do($sql);
	
	print STDOUT "Updating synonym with $synonym_no: $sql : result=$result\n" if $DEBUG;
    }
    
    # Second section: Now we check if the parents have been changed by a recent
    # opinion, and only update it if that is the case
    
    $sql = "SELECT spelling_no as parent_no FROM $TAXA_TREE_CACHE WHERE lft < $cache_row->{lft} AND rgt > $cache_row->{rgt} ORDER BY lft DESC LIMIT 1";
    
    # BUG: may be multiple parents, compare most recent spelling:
    
    my $row = $dbh->selectrow_hashref($sql);
    my $new_parent_no = ($mrpo && $mrpo->{parent_no}) ? $mrpo->{parent_no} : 0;
    
    if ($new_parent_no)
    {
	# Compare most recent spellings of the names, for consistency
	my $new_parent_no = getCachedSpellingNo($dbt,$new_parent_no) || $new_parent_no;
    }
    
    my $old_parent_no = ($row && $row->{parent_no}) ? $row->{parent_no} : 0;
    
    if ($new_parent_no != $old_parent_no)
    {
	print STDOUT "Parents have been changed: new parent $new_parent_no\n" if $DEBUG;
	
	if ($cache_row)
	{
	    moveChildren($dbt,$cache_row->{taxon_no},$new_parent_no);
	}
	
	else
	{
	    print STDOUT "Missing child_no from $TAXA_TREE_CACHE: child_no=$orig_no\n";
	}
    }
    
    else
    {
	print STDOUT "Parents are the same: $new_parent_no\n" 
	    if $DEBUG > 1;
    }
    
    # $done_commit = 1;
    
    # unless ( $dbh->commit )
    # {
    #     $messages .= "ERROR: commit failed!\n";
    #     warn "ERROR: commit failed!";
    # }
    
}


# addTaxaCacheRow ( dbt, taxon_no )
# 
# Add a new taxonomic name to taxa_tree_cache that doesn't currently  belong
# anywhere.  Should be called when creating a new authority (Taxon.pm)  and
# Opinion.pm (when creating a new spelling on fly)

sub addTaxaCacheRow {
    
    my ($dbt, $taxon_no, $spelling_no, $synonym_no, $opinion_no) = @_;
    
    # The spelling_no and synonym_no default to the value of $taxon_no, while
    # opinion_no defaults to zero.
    
    $spelling_no ||= $taxon_no;
    $synonym_no ||= $taxon_no;
    $opinion_no ||= 0;
    
    my $dbh = $dbt->dbh;
    
    # Set $lft and $rgt to just past the current maximum.
    
    my $sql = "SELECT max(rgt) FROM $TAXA_TREE_CACHE";
    
    my ($max) = $dbh->selectrow_array($sql);
    
    my $lft = $max + 1; 
    my $rgt = $max + 2; 
    
    $sql = "INSERT IGNORE INTO $TAXA_TREE_CACHE 
		(taxon_no, lft, rgt, spelling_no, synonym_no, opinion_no)
		VALUES ($taxon_no, $lft, $rgt, $spelling_no, $synonym_no, $opinion_no)";
    
    my $result = $dbh->do($sql);
    
    print STDOUT "Adding cache row: $sql : result=$result\n" if $DEBUG;
    
    # Add a row to auth_orig if there isn't already one.
    
    $sql = "INSERT IGNORE INTO auth_orig (taxon_no, orig_no) VALUES ($taxon_no, $taxon_no)";
    
    $result = $dbh->do($sql);
    
    print STDOUT "$sql : result=$result\n" if $DEBUG;
    
    # Now select the new row and return it.
    
    $sql = "SELECT * FROM $TAXA_TREE_CACHE WHERE taxon_no=$taxon_no";
    
    my $row = $dbh->selectrow_hashref($sql);
    
    return $row;
}


# This is a utility function that moves a block of children in the taxa_tree_cache from
# their old parent to their new parent.  We specify the lft and rgt values of the 
# children we want ot move rather than just passing in the child_no to make this function
# a bit more flexible (it can move blocks of children and their descendents instead of 
# just one child).  The general steps are:
#   * Create a new open space where we're going to be moving the children
#   * Add the difference between the old location and new location to the children
#     so all their values get adjusted to be in the new spot
#   * Remove the old "vacuum" where the children used to be

sub moveChildren {
    
    my ($dbt, $child_no, $parent_no) = @_;
    my $dbh = $dbt->dbh;
    
    my $sql;
    my $p_row;
    my $c_row;
    
    if ($parent_no) {
        $sql = "SELECT lft,rgt,spelling_no FROM $TAXA_TREE_CACHE WHERE taxon_no=$parent_no";
        $p_row = ${$dbt->getData($sql)}[0];
        if (!$p_row) {
            $p_row = addTaxaCacheRow($dbt,$parent_no);
        }
    }
    
    $sql = "SELECT lft,rgt,spelling_no FROM $TAXA_TREE_CACHE WHERE taxon_no=$child_no";
    $c_row = ${$dbt->getData($sql)}[0];
    if (!$c_row) {
        return;
    }
    my $lft = $c_row->{lft};
    my $rgt = $c_row->{rgt};

    if ($parent_no && $c_row->{lft} == $p_row->{lft})
    {
	print STDOUT "moveChildren skipped, child and parent appear to be the same\n" if $DEBUG;
	return;
    }
    
    # if PARENT && PARENT.RGT BTWN LFT AND RGT
    # If a loop occurs (the insertion point where we're going to move the child is IN the child itself
    # then we have some special logic: Move to the end so it has no parents, then move the child to 
    # the parent, so we avoid loops
    # this is actually a little more complicated: once you move the parent
    #  to outer space and the child into it, you have to move the parent back,
    #  which you can set off by messing with the modified date of the parent's
    #  most recent parent opinion
    # this does not result in endless looping because getJuniorSynonyms,
    #  getSeniorSynonym, and getClassification are all now able
    #  to resolve such conflicts JA 14-15.6.07
    
    if ($parent_no && $p_row->{lft} > $c_row->{lft} && $p_row->{rgt} < $c_row->{rgt})
    {
        print STDOUT "Loop found, moving parent $parent_no to 0\n" if $DEBUG;
        moveChildren($dbt,$parent_no,0);
        # my $popinion = getAllClassification($dbt, $parent_no, { no_synonyms => 1 });
        # $sql = "UPDATE opinions SET modified=now() WHERE opinion_no=" . $popinion->{opinion_no};
        # $dbh->do($sql);
        $sql = "SELECT lft,rgt,spelling_no FROM $TAXA_TREE_CACHE WHERE taxon_no=$parent_no";
        $p_row = ${$dbt->getData($sql)}[0];
        if (!$p_row) { return; }
        $sql = "SELECT lft,rgt,spelling_no FROM $TAXA_TREE_CACHE WHERE taxon_no=$child_no";
        $c_row = ${$dbt->getData($sql)}[0];
        if (!$c_row) { return; }
        
        $lft = $c_row->{lft};
        $rgt = $c_row->{rgt};
        #print "End dealing w/loop\n" if ($DEBUG);
    }

    my $child_tree_size = 1+$rgt-$lft;
    
    print STDOUT "moveChildren called: child_no $child_no lft $lft rgt $rgt parent $parent_no\n" 
	if $DEBUG;
    
    # Find out where we're going to insert the new child. Just add it as the last child of the parent,
    # or put it at the very end if there is no parent
    
    my ($parent_lft, $parent_rgt, $child_lft, $child_rgt, $insert_point);
    
    if ($parent_no)
    {
	$parent_lft = $p_row->{lft};
        $parent_rgt = $p_row->{rgt};
	$insert_point = $parent_rgt + 1;

        # Now add a space at the location of the new nodes will be and
        $sql = "UPDATE $TAXA_TREE_CACHE
		SET lft=if(lft > $parent_rgt, lft + $child_tree_size, lft),
		    rgt=if(rgt >= $parent_rgt, rgt + $child_tree_size, rgt)";
        $dbh->do($sql);
        print STDOUT "moveChildren: create new spot at $insert_point: $sql\n" if $DEBUG;
	
	$child_lft  = ($parent_rgt <= $lft) ? $lft + $child_tree_size : $lft;
	$child_rgt = ($parent_rgt <= $rgt) ? $rgt + $child_tree_size : $rgt;
    }
    
    else
    {
        $sql = "SELECT max(rgt) m FROM $TAXA_TREE_CACHE";
        my $sth = $dbh->prepare($sql);
        $sth->execute();
        my $row = $sth->fetchrow_arrayref();
        $insert_point = $row->[0] + 1;
        print STDOUT "moveChildren: create spot at end, blank parent, $insert_point\n" if $DEBUG;
	
	$child_lft = $lft;
	$child_rgt = $rgt;
    }
    
    # The child's lft and rgt values may be been just been adjusted by the update ran above, so
    # adjust accordingly
    # Adjust their lft and rgt values accordingly by adding/subtracting the difference between where the
    # children and are where we're moving them
    
    my $diff = abs($insert_point - $child_lft);
    my $sign = ($insert_point < $child_lft) ? "-" : "+";
    
    if ( $child_lft > 0 )
    {
	$sql = "UPDATE $TAXA_TREE_CACHE SET lft=lft $sign $diff, rgt=rgt $sign $diff WHERE lft BETWEEN $child_lft AND $child_rgt";
	print STDOUT "moveChildren: move to new spot: $sql\n" if $DEBUG;
	$dbh->do($sql);
	
	# Now shift everything down into the old space thats now vacant We
	# actually don't have to do this, since it is of no consequence to
	# leave a gap in the tree sequence.
	
	#$sql = "UPDATE $TAXA_TREE_CACHE SET lft=IF(lft > $child_lft,lft-$child_tree_size,lft),rgt=IF(rgt > $child_lft,rgt-$child_tree_size,rgt)";
	#print "moveChildren: remove old spot: $sql\n" if ($DEBUG);
	#$dbh->do($sql);
    }
    
    else
    {
	$sql = "UPDATE $TAXA_TREE_CACHE SET lft=$insert_point, rgt=$insert_point WHERE taxon_no=$child_no";
	print STDOUT "moveChildren: move to new spot: $sql\n" if $DEBUG;
	$dbh->do($sql);
    }
    # Think about this some more
    # Pass back where we moved them to
    my $new_lft = $insert_point;
    my $new_rgt = $insert_point+$child_tree_size-1;
    return ($new_lft,$new_rgt);
}

# sub getMetaData {
    
#     my ($dbt,$taxon_no,$spelling_no,$synonym_no) = @_;
    
#     my $orig_no = getOriginalCombination($dbt, $taxon_no);
#     my $last_op = getClassification($dbt, $orig_no);
    
#     my $invalid_reason = 'valid';
#     my $nomen_parent_no = 0;
    
#     if ($synonym_no != $spelling_no || ($last_op && $last_op->{status} !~ /belongs to/))
#     {
#         if ($last_op->{status} =~ /nomen/)
# 	{
#             my $last_parent_op = getAllClassification($dbt, $orig_no, { exclude_nomen => 1 }); 
#             $nomen_parent_no = $last_parent_op->{parent_no} || "0";
#         } 
        
# 	$invalid_reason = $last_op->{status};
#     } 
    
#     elsif ($taxon_no != $spelling_no)
#     {
#         $invalid_reason = $last_op->{spelling_reason};
#     }
    
#     return ($invalid_reason,$nomen_parent_no);
# }

1;
