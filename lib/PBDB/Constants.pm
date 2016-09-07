
use strict;

package PBDB::Constants;
use base 'Exporter';
use FindBin;

our @EXPORT_OK = qw($READ_URL $WRITE_URL $INTERVAL_URL $HOST_URL $HTML_DIR $DATA_DIR $SQL_DB $DB_TYPE $DB_USER $DB_SOCKET $DB_PASSWD $IS_FOSSIL_RECORD $TAXA_TREE_CACHE $TAXA_LIST_CACHE $IP_MAIN $IP_BACKUP $DB $PAGE_TOP $PAGE_BOTTOM $COLLECTIONS $COLLECTION_NO $OCCURRENCES $OCCURRENCE_NO $ALLOW_LOGIN $CGI_DEBUG $ADMIN_EMAIL $APP_DIR $MESSAGE_FILE);  # symbols to export on request

# general constants
$PBDB::Constants::conf = read_conf();
my $conf = $PBDB::Constants::conf;

$PBDB::Constants::HOST_URL        = $conf->{'HOST_URL'};
$PBDB::Constants::DATA_URL	    = $conf->{'DATA_URL'};
$PBDB::Constants::HTML_DIR        = $conf->{'HTML_DIR'};
$PBDB::Constants::DATA_DIR        = $conf->{'DATA_DIR'};
$PBDB::Constants::DB_SOCKET       = $conf->{'DB_SOCKET'};
$PBDB::Constants::DB_PASSWD       = $conf->{'DB_PASSWD'};
$PBDB::Constants::DB_USER	    = $conf->{'DB_USER'} || 'pbdbuser';
$PBDB::Constants::ALLOW_LOGIN	    = $conf->{'ALLOW_LOGIN'};
$PBDB::Constants::CGI_DEBUG	    = $conf->{'CGI_DEBUG'};
$PBDB::Constants::ADMIN_EMAIL	    = $conf->{'ADMIN_EMAIL'};
$PBDB::Constants::IP_MAIN         = '137.111.92.50';
$PBDB::Constants::IP_BACKUP       = '137.111.92.50';
$PBDB::Constants::MESSAGE_FILE    = $conf->{'MESSAGE_FILE'};

$PBDB::Constants::IS_FOSSIL_RECORD = $conf->{'IS_FOSSIL_RECORD'};

$PBDB::Constants::TAXA_TREE_CACHE = 'taxa_tree_cache';
$PBDB::Constants::TAXA_LIST_CACHE = 'taxa_list_cache';
$PBDB::Constants::READ_URL = 'classic';
$PBDB::Constants::WRITE_URL = 'classic';

$PBDB::Constants::DB = 'pbdb';
$PBDB::Constants::SQL_DB = 'pbdb';
$PBDB::Constants::DB_TYPE = '';
$PBDB::Constants::PAGE_TOP = 'std_page_top';
$PBDB::Constants::PAGE_BOTTOM = 'std_page_bottom';
$PBDB::Constants::COLLECTIONS = 'collections';
$PBDB::Constants::COLLECTION_NO = 'collection_no';
$PBDB::Constants::OCCURRENCES = 'occurrences';
$PBDB::Constants::OCCURRENCE_NO = 'occurrence_no';
if ( $ENV{'HTTP_USER_AGENT'} =~ /Mobile/i && $ENV{'HTTP_USER_AGENT'} !~ /iPad/i )	{
    $PBDB::Constants::PAGE_TOP = 'mobile_top';
    $PBDB::Constants::PAGE_BOTTOM = 'mobile_bottom';
}

$PBDB::Constants::INTERVAL_URL = $conf->{INTERVAL_URL} || '';

sub read_conf {
    my $base_dir = $FindBin::RealBin;
    # $base_dir =~ s/\/(upload|cgi-bin|scripts|html)(\/.*)*$/\/config/;
    $base_dir =~ s/\/bin//;
    $PBDB::Constants::APP_DIR = $base_dir;
    # $PBDB::Constants::APP_DIR =~ s/\/config$//;
    my $filename = "$base_dir/pbdb.conf";
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

1;
