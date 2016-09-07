

use strict;

package PBDB;

# CPAN modules
use CGI qw(escapeHTML);
use URI::Escape;
use Text::CSV_XS;
use CGI::Carp qw(fatalsToBrowser);
use Class::Date qw(date localdate gmdate now);
use POSIX qw(ceil floor);
use DBI;

# PBDB modules
use PBDB::HTMLBuilder;
use PBDB::DBConnection;
use PBDB::DBTransactionManager;
use PBDB::Session;

# Autoloaded libs
use PBDB::Person;
use PBDB::PBDBUtil;
use PBDB::Permissions;
use PBDB::Reclassify;
use PBDB::Reference;
use PBDB::ReferenceEntry;  # slated for removal

use PBDB::Collection;
use PBDB::CollectionEntry;  # slated for removal
use PBDB::TaxonInfo;
use PBDB::TimeLookup;
use PBDB::Ecology;
#use Images;
use PBDB::Measurement;
use PBDB::MeasurementEntry;  # slated for removal
use PBDB::TaxaCache;
use PBDB::TypoChecker;
#use FossilRecord;
# use Cladogram;
use PBDB::Review;
use PBDB::NexusfileWeb;  # slated for removal

# god awful Poling modules
use PBDB::Taxon;  # slated for removal
use PBDB::Opinion;  # slated for removal
use PBDB::Validation;
use PBDB::Debug qw(dbg);
use PBDB::Constants qw($WRITE_URL $HOST_URL $HTML_DIR $DATA_DIR $IS_FOSSIL_RECORD $TAXA_TREE_CACHE $DB $PAGE_TOP $PAGE_BOTTOM $COLLECTIONS $COLLECTION_NO $OCCURRENCES $OCCURRENCE_NO $CGI_DEBUG $ALLOW_LOGIN);



# Handle one request

sub pbdb_request {
    
    
    
    
}


# Create the CGI, Session, and some other objects.
my $q = new CGI;

# Make a Transaction Manager object
my $dbt = new PBDB::DBTransactionManager();

# Make the session object
my $s = new PBDB::Session($dbt,$q->cookie('session_id'));

