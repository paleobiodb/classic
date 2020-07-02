# JA 6-7.8.11 (while at IGC!)
# super-basic rebuild of taxa_tree_cache that works entirely off of TaxonInfo
#  functions meant to update the table one record at a time

$CACHE = 'taxa_tree_cache_quick';

use lib "../cgi-bin";
use DBConnection;
use DBTransactionManager;
use TaxonInfo;

my $dbh = DBConnection::connect();
my $dbt = new DBTransactionManager($dbh);

$|=1;

my @taxa = @{$dbt->getData('SELECT taxon_no FROM authorities')};
printf "%d taxa\n",$#taxa+1;

# first build up a blank table

my $result = $dbh->do("DROP TABLE IF EXISTS $CACHE");
$result = $dbh->do("CREATE TABLE $CACHE (taxon_no int(10) unsigned NOT NULL default '0',lft int(10) unsigned NOT NULL default '0',rgt int(10) unsigned NOT NULL default '0', spelling_no int(10) unsigned NOT NULL default '0', synonym_no int(10) unsigned NOT NULL default '0', opinion_no int(10) unsigned NOT NULL default '0', max_interval_no int(10) unsigned NOT NULL default '0', min_interval_no int(10) unsigned NOT NULL default '0', mass float default NULL, PRIMARY KEY  (taxon_no), KEY lft (lft), KEY rgt (rgt), KEY synonym_no (synonym_no), KEY opinion_no (opinion_no)) TYPE=MyISAM");

# the table is almost completely blank at this point
my (%spellings,%spellingOf);
for my $t ( @taxa )	{
#last;
	$dbh->do("INSERT INTO $CACHE(taxon_no,synonym_no,spelling_no) VALUES($t->{taxon_no},$t->{taxon_no},$t->{taxon_no})");
	$orig = TaxonInfo::getOriginalCombination($dbt,$t->{taxon_no});
	push @{$spellings{$orig}} , $t->{taxon_no};
	$spellingOf{$t->{taxon_no}} = $orig;
}
my @origs = keys %spellings;

printf "%d original combinations\n",$#origs+1;

# reset the opinion_no, spelling_no, and synonym_no values
for my $o ( keys %spellings )	{
#last;
	TaxonInfo::getMostRecentClassification($dbt,$o,{'recompute'=>'yes','cache'=>$CACHE});
}
print "done setting opinions\n";

my %children;
push @{$children{$spellingOf{$_->{parent_no}}}} , $spellingOf{$_->{child_no}} foreach @{$dbt->getData("SELECT child_no,parent_no FROM opinions o,$CACHE t WHERE o.opinion_no=t.opinion_no AND (child_no=spelling_no OR child_spelling_no=spelling_no) GROUP BY o.opinion_no")};

# special handling for taxa classified using "borrowed" opinions on synonyms
push @{$children{$spellingOf{$_->{parent_no}}}} , $spellingOf{$_->{taxon_no}} foreach @{$dbt->getData("SELECT taxon_no,parent_no FROM opinions o,$CACHE t WHERE o.opinion_no=t.opinion_no AND child_no!=taxon_no AND child_spelling_no!=taxon_no AND taxon_no=spelling_no")};

# now create the actual classification
# only run this on original combinations
my @roots = map { $spellingOf{$_->{taxon_no}} } @{$dbt->getData("SELECT taxon_no FROM $CACHE WHERE opinion_no=0 AND taxon_no=spelling_no")};
push @roots , map { $spellingOf{$_->{taxon_no}} } @{$dbt->getData("SELECT taxon_no FROM $CACHE t,opinions o WHERE t.opinion_no=o.opinion_no AND parent_no=0 AND taxon_no=spelling_no")};

printf "%d root parents\n",$#roots+1;

$dbh->do("UPDATE $CACHE SET lft=0,rgt=0");
my (%lft,%rgt,$lftrgt);
for my $r ( @roots )	{
	print "\rP $r\t$lftrgt";
	$lftrgt++;
	$lft{$r} = $lftrgt;
	insertChild($_) foreach @{$children{$r}};
	$lftrgt++;
	$rgt{$r} = $lftrgt;
	$lft{$_} = $lft{$r} foreach @{$spellings{$spellingOf{$r}}};
	$rgt{$_} = $rgt{$r} foreach @{$spellings{$spellingOf{$r}}};
	$dbh->do("UPDATE $CACHE SET lft=$lft{$r},rgt=$rgt{$r} WHERE taxon_no IN (".join(',',@{$spellings{$spellingOf{$r}}}).")");
}

sub insertChild	{
	my $child = shift;
	if ( $lft{$child} > 0 )	{
		return;
	}
	$lftrgt++;
	$lft{$child} = $lftrgt;
	insertChild($_) foreach @{$children{$child}};
	# close off the branch for this child after all its children
	#  have been dealt with
	$lftrgt++;
	$rgt{$child} = $lftrgt;
	# bind all spellings of this group (careful!)
	$lft{$_} = $lft{$child} foreach @{$spellings{$spellingOf{$child}}};
	$rgt{$_} = $rgt{$child} foreach @{$spellings{$spellingOf{$child}}};
	$dbh->do("UPDATE $CACHE SET lft=$lft{$child},rgt=$rgt{$child} WHERE taxon_no IN (".join(',',@{$spellings{$spellingOf{$child}}}).")");
}

exit;


