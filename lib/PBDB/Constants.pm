
use strict;

package PBDB::Constants;
use base 'Exporter';
use FindBin;

our @EXPORT_OK = qw($WRITE_URL $DATA_URL $TEST_DATA_URL $GDD_URL $INTERVAL_URL $HTML_DIR $DATA_DIR
		    $APP_DIR $WEBAPP_DIR $WEBAPP_PATH $MESSAGE_FILE
		    $SQL_DB $DB_USER $DB_SOCKET $DB_CONNECTION $DB_PASSWD
		    $TAXA_TREE_CACHE $TAXON_TREES
		    $COLLECTIONS $COLLECTION_NO $OCCURRENCES $OCCURRENCE_NO
		    $ALLOW_LOGIN $CGI_DEBUG $DEBUG_USER %DEBUG_USERID $ADMIN_EMAIL
		    makeURL makeATag makeAnchor makePageAnchor makeAnchorWithAttrs makeFormPostTag);

our($WRITE_URL) = '/classic';
our($APP_DIR) = '/data/MyApp';

# BEGIN {
#     $PBDB::Constants::Cl
#     $PBDB::Constants::APP_DIR = '/data/MyApp';
# }

# general constants
$PBDB::Constants::conf = read_conf();
my $conf = $PBDB::Constants::conf;

$PBDB::Constants::DATA_URL	  = $conf->{'DATA_URL'};
$PBDB::Constants::GDD_URL	  = $conf->{'GDD_URL'};
$PBDB::Constants::TEST_DATA_URL   = $conf->{'TEST_DATA_URL'};
$PBDB::Constants::HTML_DIR        = $conf->{'HTML_DIR'};
$PBDB::Constants::DATA_DIR        = $conf->{'DATA_DIR'};
$PBDB::Constants::WEBAPP_DIR	  = $conf->{'WEBAPP_DIR'} || "$APP_DIR/resources";
$PBDB::Constants::WEBAPP_PATH	  = $conf->{'WEBAPP_PATH'} || "/resources";
$PBDB::Constants::DB_SOCKET       = $conf->{'DB_SOCKET'};
$PBDB::Constants::DB_CONNECTION	  = $conf->{'DB_CONNECTION'};
$PBDB::Constants::DB_PASSWD       = $conf->{'DB_PASSWD'};
$PBDB::Constants::DB_USER	  = $conf->{'DB_USER'} || 'pbdbuser';
$PBDB::Constants::ALLOW_LOGIN	  = $conf->{'ALLOW_LOGIN'};
$PBDB::Constants::CGI_DEBUG	  = $conf->{'CGI_DEBUG'};
our ($DEBUG_USER)		  = $conf->{'DEBUG_USER'};
$PBDB::Constants::ADMIN_EMAIL	  = $conf->{'ADMIN_EMAIL'};
$PBDB::Constants::MESSAGE_FILE    = $conf->{'MESSAGE_FILE'} || '';

$PBDB::Constants::TAXA_TREE_CACHE = 'taxa_tree_cache';
$PBDB::Constants::TAXON_TREES = 'taxon_trees';
# $PBDB::Constants::TAXA_LIST_CACHE = 'taxa_list_cache';

$PBDB::Constants::SQL_DB = 'pbdb';
$PBDB::Constants::COLLECTIONS = 'collections';
$PBDB::Constants::COLLECTION_NO = 'collection_no';
$PBDB::Constants::OCCURRENCES = 'occurrences';
$PBDB::Constants::OCCURRENCE_NO = 'occurrence_no';
$PBDB::Constants::INTERVAL_URL = $conf->{INTERVAL_URL} || '';

$PBDB::Constants::WRITE_URL	  = '/classic';

our (%DEBUG_USERID);

if ( $DEBUG_USER )
{
    foreach my $id ( split /\s*,\s*/, $DEBUG_USER )
    {
	$DEBUG_USERID{$id} = 1 if $id > 0;
    }
}

sub read_conf {
    # my $base_dir = $FindBin::RealBin;
    
    # $base_dir =~ s/\/(upload|cgi-bin|scripts|html)(\/.*)*$/\/config/;
    # $base_dir =~ s{ /bin | /scripts }{}xs;
    # $PBDB::Constants::APP_DIR = $base_dir;
    # $PBDB::Constants::APP_DIR =~ s/\/config$//;
    my $filename = "$APP_DIR/pbdb.conf";
    my $cf;
    open $cf, "<$filename" or die "Can not open $filename\n";
    my %conf = ();
    while(my $line = readline($cf)) {
        chomp($line);
        if ($line =~ /^\s*(\w+)\s*=\s*(.*)$/) {
            $conf{uc($1)} = $2; 
        }
    }
    return \%conf;
}


# Convenience routines for generating URLs for internal links

sub makeURL {

    my ($action, $params) = @_;
    
    if ( $params )
    {
	return "$WRITE_URL/$action?$params";
    }
    
    else
    {
	return "$WRITE_URL/$action";
    }
}


sub makeATag {

    my ($action, $params) = @_;
    
    my $url = makeURL($action, $params);
    return qq{<a href="$url">};
}


sub makeAnchor {
    
    my ($action, $params, $content) = @_;
    
    $content //= "";
    my $url = makeURL($action, $params);
    return qq{<a href="$url">$content</a>};
}


sub makePageAnchor {

    my ($page, $content) = @_;

    $content //= "";
    my $url = "$WRITE_URL?page=$page";
    return qq{<a href="$url">$content</a>};
}


sub makeAnchorWithAttrs {

    my ($action, $params, $attrs, $content) = @_;
    
    $content //= "";
    my $url = makeURL($action, $params);
    return qq{<a href="$url" $attrs>$content</a>};
}


sub makeFormPostTag {

    my ($form_name) = @_;

    if ( $form_name )
    {
	return "<form name=\"$form_name\" action=\"$WRITE_URL\" method=\"post\">\n";
    }

    else
    {
	return "<form action=\"$WRITE_URL\" method=\"post\">\n";
    }
}

1;
