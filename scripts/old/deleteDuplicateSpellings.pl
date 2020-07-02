#!/opt/local/bin/perl

# JA 30.5.13
# removes duplicates created by a just-fixed bug in Opinion.pm

use lib '../cgi-bin';
use DBI;
use DBConnection;
use DBTransactionManager;
use Session;

my $dbt = new DBTransactionManager;
my $s = Session->new($dbt);
my $dbh = $dbt->dbh;

my $sql = "select count(*) c,a.taxon_no,a.taxon_rank,a.taxon_name from (select enterer_no,created,taxon_name,taxon_rank,taxon_no from authorities order by taxon_no asc) a,taxa_tree_cache t where a.taxon_no=t.taxon_no group by taxon_name,taxon_rank,lft having c>=2 order by created";
my @goods = sort { $a->{taxon_rank}.$a->{taxon_name} cmp $b->{taxon_rank}.$b->{taxon_name} } @{$dbt->getData($sql)};

my $sql = "select count(*) c,a.taxon_no,a.taxon_rank,a.taxon_name from (select enterer_no,created,taxon_name,taxon_rank,taxon_no from authorities order by taxon_no desc) a,taxa_tree_cache t where a.taxon_no=t.taxon_no group by taxon_name,taxon_rank,lft having c>=2 order by created";
my @bads = sort { $a->{taxon_rank}.$a->{taxon_name} cmp $b->{taxon_rank}.$b->{taxon_name} } @{$dbt->getData($sql)};

for my $i ( 0..$#goods )	{

	my ($good_taxon_no,$bad_taxon_no) = ($goods[$i]->{taxon_no},$bads[$i]->{taxon_no});
print "$good_taxon_no $goods[$i]->{taxon_rank} $goods[$i]->{taxon_name} = $bad_taxon_no $bads[$i]->{taxon_rank} $bads[$i]->{taxon_name}\n";

	my $sql = "update taxa_tree_cache set spelling_no=$good_taxon_no where spelling_no=$bad_taxon_no";
	nuke($sql);

	$sql = "update taxa_tree_cache set synonym_no=$good_taxon_no where synonym_no=$bad_taxon_no";
	nuke($sql);

	$sql = "update occurrences set modified=modified,taxon_no=$good_taxon_no where taxon_no=$bad_taxon_no";
	nuke($sql);

	$sql = "update reidentifications set modified=modified,taxon_no=$good_taxon_no where taxon_no=$bad_taxon_no";
	nuke($sql);

	$sql = "update ecotaph set modified=modified,taxon_no=$good_taxon_no where taxon_no=$bad_taxon_no";
	nuke($sql);

	$sql = "update opinions set modified=modified,child_no=$good_taxon_no where child_no=$bad_taxon_no";
	nuke($sql);

	$sql = "update opinions set modified=modified,child_spelling_no=$good_taxon_no where child_spelling_no=$bad_taxon_no";
	nuke($sql);

	$sql = "update opinions set modified=modified,parent_no=$good_taxon_no where parent_no=$bad_taxon_no";
	nuke($sql);

	$sql = "update opinions set modified=modified,parent_spelling_no=$good_taxon_no where parent_spelling_no=$bad_taxon_no";
	nuke($sql);

	$sql = "delete from taxa_tree_cache where taxon_no=$bad_taxon_no";
	nuke($sql);

	$sql = "delete from authorities where taxon_no=$bad_taxon_no";
	nuke($sql);
}

sub nuke	{
	my $sql = shift;
	my $sth = $dbh->prepare($sql);
	my $result = $sth->execute();
}


