
use strict;

package PBDB::Constants;
use base 'Exporter';
use FindBin;

our @EXPORT_OK = qw(%CONFIG $WRITE_URL $APP_DIR $DATA_URL $TEST_DATA_URL $GDD_URL
		    $INTERVAL_URL $RANGE_URL
		    $HTML_DIR $DATA_DIR $WEBAPP_DIR $WEBAPP_PATH $MESSAGE_FILE
		    $CGI_DEBUG %DEBUG_USERID $LOG_REQUESTS
		    $MAIN_DATABASE $WING_DATABASE $TAXA_TREE_CACHE $TAXON_TREES
		    $COLLECTIONS $COLLECTION_NO $OCCURRENCES $OCCURRENCE_NO
		    makeURL makeATag makeObTag makeAnchor makeObAnchor makePageAnchor 
		    makeAnchorWithAttrs makeObAnchorWA makeFormPostTag);

# Configuration settings

our %CONFIG;

our $APP_DIR = "/data/MyApp";

&read_config();

our $WRITE_URL		= '/classic';
our $DATA_URL		= $CONFIG{DATA_URL} || '';
our $TEST_DATA_URL	= $CONFIG{TEST_DATA_URL} || $DATA_URL;
our $GDD_URL		= $CONFIG{GDD_URL} || '';
our $INTERVAL_URL	= '/classic/displayTimescale?interval=';
our $RANGE_URL		= '/classic/displayTimescale?range=';
our $HTML_DIR		= $CONFIG{HTML_DIR} || $APP_DIR;
our $DATA_DIR		= $CONFIG{DATA_DIR} || "$APP_DIR/data";
our $WEBAPP_DIR		= $CONFIG{WEBAPP_DIR} || "$APP_DIR/resources";
our $WEBAPP_PATH	= $CONFIG{WEBAPP_PATH} || "/resources";
our $MESSAGE_FILE	= $CONFIG{MESSAGE_FILE} || '';
our $CGI_DEBUG		= $CONFIG{CGI_DEBUG} || '';
our $LOG_REQUESTS	= $CONFIG{LOG_REQUESTS} || '';
our $TAXA_TREE_CACHE	= $CONFIG{TAXA_TREE_CACHE} || 'taxa_tree_cache';
our $TAXON_TREES	= $CONFIG{TAXON_TREES} || 'taxon_trees';
our $MAIN_DATABASE	= $CONFIG{MAIN_DATABASE} || 'pbdb';
our $WING_DATABASE	= $CONFIG{WING_DATABASE} || 'pbdb_wing';

our $COLLECTIONS	= 'collections';
our $COLLECTION_NO	= 'collection_no';
our $OCCURRENCES	= 'occurrences';
our $OCCURRENCE_NO	= 'occurrence_no';

our %DEBUG_USERID;

if ( $CONFIG{DEBUG_USER} )
{
    foreach my $id ( split /\s*,\s*/, $CONFIG{DEBUG_USER} )
    {
	$DEBUG_USERID{$id} = 1 if $id > 0;
    }
}

$CONFIG{LOG_REQUESTS} = 1 if $ENV{LOG_REQUESTS};
$CONFIG{PROFILE_REQUESTS} = 1 if $ENV{PROFILE_REQUESTS};
$CONFIG{PROFILE_THRESHOLD} = $ENV{PROFILE_THRESHOLD} if $ENV{PROFILE_THRESHOLD};


sub read_config {
    
    # my $base_dir = $FindBin::RealBin;
    
    # $base_dir =~ s/\/(upload|cgi-bin|scripts|html)(\/.*)*$/\/config/;
    # $base_dir =~ s{ /bin | /scripts }{}xs;
    # $PBDB::Constants::APP_DIR = $base_dir;
    # $PBDB::Constants::APP_DIR =~ s/\/config$//;
    
    my $filename = "$APP_DIR/pbdb.conf";
    
    open my $cf, '<', $filename or die "Can not open $filename\n";
    
    while (my $line = readline($cf))
    {
        chomp($line);
	
        if ($line =~ /^\s*(\w+)\s*=\s*(.*)$/)
	{
            $CONFIG{uc($1)} = $2; 
        }
    }
    
    close $cf;
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


# Generate a standard HTML 'a' tag.

sub makeATag {

    my ($action, $params) = @_;
    
    my $url = makeURL($action, $params);
    return qq{<a href="$url">};
}


# Generate an obfuscated tag that crawler bots can't recognize

sub makeObTag {
    
    my ($action, $params) = @_;
    
    return qq{<a onmouseover="setHref(this, '$action', '$params')" class="mockLink">};
}


# Generate a standard HTML hyperlink.

sub makeAnchor {
    
    my ($action, $params, $content) = @_;
    
    $content //= "";
    my $url = makeURL($action, $params);
    return qq{<a href="$url">$content</a>};
}


# Generate an obfuscated hyperlink that crawler bots can't recognize

sub makeObAnchor {
    
    my ($action, $params, $content) = @_;
    
    $content //= "";
    return qq{<a onmouseover="setHref(this, '$action', '$params')" class="mockLink">$content</a>};
}


# Generate a standard HTML hyperlink to a specified page on this site.

sub makePageAnchor {

    my ($page, $content) = @_;

    $content //= "";
    my $url = "$WRITE_URL?page=$page";
    return qq{<a href="$url">$content</a>};
}


# Generate a standard HTML hyperlink with attributes.

sub makeAnchorWithAttrs {

    my ($action, $params, $attrs, $content) = @_;
    
    $content //= "";
    my $url = makeURL($action, $params);
    return qq{<a href="$url" $attrs>$content</a>};
}


# Generate an obfuscated hyperlink (with attributes) that crawler bots can't
# recognize. 

sub makeObAnchorWA {

    my ($action, $params, $attrs, $content) = @_;
    
    $content //= "";
    return qq{<a onmouseover="setHref(this, '$action', '$params')" $attrs class="mockLink">$content</a>};
}


# Make a form tag with the 'post' method.

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
