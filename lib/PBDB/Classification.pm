# 
# Paleobiology Database
# 
# Classification subroutines.


package PBDB::Classification;

use strict;

use PBDB::Taxonomy qw(getClassification getAllClassification getOriginalCombination
		      getTaxa getTaxonNos getSeniorSynonym getMostRecentSpelling);
use Data::Dumper qw(Dumper);
use PBDB::Debug qw(dbg);

my $DEBUG = 0;

# Pass in a taxon_no and this function returns all taxa that are  a part of that taxon_no, recursively
# This function isn't meant to be called itself but is a recursive utility function for taxonomic_search
# deprecated, see taxonomic_search. moved here from PBDBUtil.pm
sub new_search_recurse {
    # Start with a taxon_name:
    my $dbt = shift;
    my $passed = shift;
    my $parent_no = shift;
    my $parent_child_spelling_no = shift;
	$passed->{$parent_no} = 1 if ($parent_no);
	$passed->{$parent_child_spelling_no} = 1 if ($parent_child_spelling_no);
    return if (!$parent_no);

    # Get the children. Second bit is for lapsus opinions
    my $sql = "SELECT DISTINCT child_no FROM opinions WHERE parent_no=$parent_no AND child_no != parent_no";
    my $dbh = $dbt->dbh;
    
    my $child_nos = $dbh->selectcol_arrayref($sql);
    
    #my $debug_msg = "";
    if($child_nos && @$child_nos > 0)
    {
        # Validate all the children
        foreach my $child_no (@$child_nos)
	{
	    # Don't revisit same child. Avoids loops in data structure, and speeds things up
            if (exists $passed->{$child_no})
	    {
		next;    
            }
            # (the taxon_nos in %$passed will always be original combinations since orig.
            # combs always have all the belongs to links) 
	    my $child_orig = getOriginalCombination($child_no);
            my $parent_row = getClassification($dbt, $child_orig);
	    
            if($parent_row->{'parent_no'} == $parent_no)
	    {
                my $sql = "SELECT DISTINCT child_spelling_no FROM opinions WHERE child_no=$child->{'child_no'}";
                my @results = @{$dbt->getData($sql)}; 
                foreach my $row (@results) {
                    if ($row->{'child_spelling_no'}) {
                        $passed->{$row->{'child_spelling_no'}}=1;
                    }
                }
                $sql = "SELECT DISTINCT parent_spelling_no FROM opinions WHERE child_no=$child->{'child_no'} AND status='misspelling of'";
                @results = @{$dbt->getData($sql)}; 
                foreach my $row (@results) {
                    if ($row->{'parent_spelling_no'}) {
                        $passed->{$row->{'parent_spelling_no'}}=1;
                    }
                }
                undef @results;
                new_search_recurse($dbt,$passed,$child->{'child_no'},$child->{'child_spelling_no'});
            } 
        }
    } 
}

##
# Recursively find all taxon_nos or genus names belonging to a taxon
# deprecated PS 10/10/2005 - use TaxaCache::getChildren instead
##
sub taxonomic_search{
	my $dbt = shift;
	my $taxon_name_or_no = (shift or "");
    my $taxon_no;

    # We need to resolve it to be a taxon_no or we're done    
    if ($taxon_name_or_no =~ /^\d+$/) {
        $taxon_no = $taxon_name_or_no;
    } else {
        my @taxon_nos = PBDB::TaxonInfo::getTaxonNos($dbt, $taxon_name_or_no);
        if (scalar(@taxon_nos) == 1) {
            $taxon_no = $taxon_nos[0];
        }       
    }
    if (!$taxon_no) {
        return wantarray ? (-1) : "-1"; # bad... ambiguous name or none
    }
    # Make sure its an original combination
    $taxon_no = PBDB::TaxonInfo::getOriginalCombination($dbt, $taxon_no);

    my $passed = {};
    
    # get alternate spellings of focal taxon. all alternate spellings of
    # children will be found by the new_search_recurse function
    my $sql = "SELECT child_spelling_no FROM opinions WHERE child_no=$taxon_no";
    my @results = @{$dbt->getData($sql)};
    foreach my $row (@results) {
        if ($row->{'child_spelling_no'}) {
            $passed->{$row->{'child_spelling_no'}} = 1;
        }
    }
    $sql = "SELECT DISTINCT parent_spelling_no FROM opinions WHERE child_no=$taxon_no AND status='misspelling of'";
    @results = @{$dbt->getData($sql)}; 
    foreach my $row (@results) {
        if ($row->{'parent_spelling_no'}) {
            $passed->{$row->{'parent_spelling_no'}}=1;
        }
    }

    # get all its children
	new_search_recurse($dbt,$passed,$taxon_no);

    return (wantarray) ? keys(%$passed) : join(', ', keys(%$passed));
}

# Gets the childen of a taxon, sorted/output in various fashions
# Algorithmically, this behaves more or less identically to taxonomic_search,
# except its slower since it can potentially return much more data and is much more flexible
# Data is kept track of internally in a tree format. Additional data is kept track of as well
#  -- Alternate spellings get stored in a "spellings" field
#  -- Synonyms get stored in a "synonyms" field
# Separated 01/19/2004 PS. 
# Moved here from PBDBUtil
#  Inputs:
#   * 1st arg: $dbt
#   * 2nd arg: taxon name or taxon number
#   * 3th arg: what we want the data to look like. possible values are:
#       tree: a tree-like data structure, more general and the format used internally
#       sort_hierarchical: an array sorted in hierarchical fashion, suitable for PrintHierarchy.pm
#       sort_alphabetical: an array sorted in alphabetical fashion, suitable for TaxonInfo.pm or Confidence.pm
#   * 4nd arg: max depth: no of iterations to go down
# 
#  Outputs: an array of hash (record) refs
#    See 'my %new_node = ...' line below for what the hash looks like
sub getChildren {
    my $dbt = shift; 
    my $taxon_no = int(shift);
    my $return_type = (shift || "sort_hierarchical");
    my $max_depth = (shift || 999);
    my $restrict_to_ref = (shift || undef);

    if (!$taxon_no) {
        return undef; # bad... ambiguous name or none
    } 
    
    # described above, return'd vars
    my $orig_no = getOriginalCombination($dbt, $taxon_no, $restrict_to_ref);
    my $ss_no = getSeniorSynonym($dbt, $orig_no, { reference_no => $restrict_to_ref });
    my $tree_root = createNode($dbt,$ss_no, $restrict_to_ref, 0);

    # The sorted records are sorted in a hierarchical fashion suitable for passing to printHierachy
    my @sorted_records = ();
    getChildrenRecurse($dbt, $tree_root, $max_depth, 1, \@sorted_records, 0, $restrict_to_ref);
    #pop (@sorted_records); # get rid of the head
   
    if ($return_type eq 'tree') {
        return $tree_root;
    } elsif ($return_type eq 'sort_alphabetical') {
        @sorted_records = sort {$a->{'taxon_name'} cmp $b->{'taxon_name'}} @sorted_records;
        return \@sorted_records;
    } else { # default 'sort_hierarchical'
        return \@sorted_records;
    }
   
}

sub getChildrenRecurse { 
    my $dbt = shift;
    my $node = shift;
    my $max_depth = shift;
    my $depth = shift;
    my $sorted_records = shift;
    my $parent_is_synonym = (shift || 0);
    my $ref_restrict = (shift || undef);
    
    return if (!$node->{'orig_no'});

    # find all children of this parent, do a join so we can do an order by on it
    my $sql = "SELECT DISTINCT child_no FROM opinions o, authorities a WHERE o.child_spelling_no=a.taxon_no AND o.parent_no=$node->{orig_no} AND o.child_no != o.parent_no ORDER BY a.taxon_name";
    my @children = @{$dbt->getData($sql)};
    
    # Create the children and add them into the children array
    foreach my $row (@children) {
        # (the taxon_nos will always be original combinations since orig. combs always have all the belongs to links)
        # go back up and check each child's parent(s)
        my $orig_no = $row->{'child_no'};
        my $parent_row = getAllClassification($dbt, $orig_no, {reference_no => $ref_restrict});
	
        if ($parent_row->{'parent_no'}==$node->{'orig_no'}) {

            # Create the node for the new child - note its taxon_no is always the original combination,
            # but its name/rank are from the corrected name/recombined name
            my $new_node = createNode($dbt, $orig_no,$ref_restrict,$depth);
          
            # Populate the new node and place it in its right place
            if ( $parent_row->{'status'} =~ /^(?:belongs)/o ) {
                return if ($max_depth && $depth > $max_depth);
                # Hierarchical sort, in depth first order
                push @$sorted_records, $new_node if (!$parent_is_synonym);
                getChildrenRecurse($dbt,$new_node,$max_depth,$depth+1,$sorted_records,0,$ref_restrict);
                push @{$node->{'children'}}, $new_node;
            } elsif ($parent_row->{'status'} =~ /^(?:subjective|objective|replaced|invalid subgroup)/o) {
                getChildrenRecurse($dbt,$new_node,$max_depth,$depth,$sorted_records,1,$ref_restrict);
                push @{$node->{'synonyms'}}, $new_node;
            }
        }
    }

    # if (0) {
    # print "synonyms for $node->{taxon_name}:";
    # print "$_->{taxon_name} " for (@{$node->{'synonyms'}}); 
    # print "\n<br>";
    # print "spellings for $node->{taxon_name}:";
    # print "$_->{taxon_name} " for (@{$node->{'spellings'}}); 
    # print "\n<br>";
    # print "children for $node->{taxon_name}:";
    # print "$_->{taxon_name} " for (@{$node->{'children'}}); 
    # print "\n<br>";
    # }
}

sub createNode {
    
    my ($dbt,$orig_no,$ref_restrict,$depth) = @_;
    
    my $taxon = getMostRecentSpelling($dbt, $orig_no, { reference_no => $ref_restrict });
    
    my $new_node = {'orig_no'=>$orig_no,
                    'taxon_no'=>$taxon->{'taxon_no'},
                    'taxon_name'=>$taxon->{'taxon_name'},
                    'taxon_rank'=>$taxon->{'taxon_rank'},
                    'depth'=>$depth,
                    'children'=>[],
                    'synonyms'=>[]};

    # Get alternate spellings
    my $sql = "(SELECT DISTINCT a.taxon_no, a.taxon_name, a.taxon_rank FROM opinions o, authorities a".
              " WHERE o.child_spelling_no=a.taxon_no".
              " AND o.child_no = $orig_no".
              " AND o.child_spelling_no != $taxon->{taxon_no})".
              " UNION ".
              "(SELECT DISTINCT a.taxon_no, a.taxon_name, a.taxon_rank FROM opinions o, authorities a".
              " WHERE o.parent_spelling_no=a.taxon_no".
              " AND o.child_no = $orig_no".
              " AND o.status='misspelling of')".
              " ORDER BY taxon_name"; 

    $new_node->{spellings} = $dbt->getData($sql);
    return $new_node;
}


1;
