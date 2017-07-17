# 
# PBDB::WebApp - A module for displaying web applications as individual HTML pages under the
# PBDB Classic framework.
# 

package PBDB::WebApp;

use Encode qw(decode_utf8);
use HTML::Entities qw(encode_entities);
use PBDB::Constants qw($WEBAPP_DIR $WEBAPP_PATH $DATA_URL $TEST_DATA_URL $READ_URL);

use base 'PBDB::HTMLBuilder';


sub new {

    my ($class, $app_name, $q, $s, $dbt, $hbo) = @_;
    
    # First check to make sure that the named page is actually there. If $app_name does not
    # contain a '/', then use the string as both the directory name and the file name.
    
    my ($main_filename, $app_path, $common_path);
    
    if ( $app_name =~ qr{ ^ ([^/]+) / }xs )
    {
	$main_filename = "$WEBAPP_DIR/${app_name}/$1.html";
	$app_path = "$WEBAPP_PATH/$1";
    }
    
    else
    {
	$main_filename = "$WEBAPP_DIR/${app_name}/${app_name}.html";
	$app_path = "$WEBAPP_PATH/$app_name";
    }
    
    $common_path = "$WEBAPP_PATH/common";
    
    # If the main HTML file is not found, return false.
    
    unless ( -e $main_filename )
    {
	return undef;
    }
    
    # Otherwise, get the contents of the main file.
    
    open my $fh,"<$main_filename" or die "cannot open main web app page '$main_filename': $!\n";
    my $txt = decode_utf8(join("",<$fh>));
    
    # Now look for settings in the top few lines of the file.
    
    my $top_chars = substr($txt, 0, 1000);
    
    my %settings = ( $top_chars =~ /([A-Z_]+) = ([^;\n]+)/xg );
    
    # Otherwise, create a new object and use it to save the parameters.
    
    my $new = {
	       app_name => $app_name,
	       main_filename => $main_filename,
	       app_path => $app_path,
	       common_path => $common_path,
	       hbo => $hbo,
	       q => $q,
	       s => $s,
	       dbt => $dbt,
	       txt => $txt,
	       settings => \%settings,
	      };
    
    return bless $new;
}


sub requires_login {
    
    my ($app) = @_;
    
    return $app->{settings}{REQUIRES_LOGIN};
}


sub generateBasePage {
    
    my ($app) = @_;
    
    # First substitute variable values for references.
    
    my $s = $app->{s};
    my %vars;
    
    $vars{'is_contributor'} = $s->isDBMember() ? 1 : 0;
    $vars{'authorizer_me'} = $s->get("authorizer");
    $vars{'enterer_me'} = $s->get("enterer");
    $vars{'data_url'} = $DATA_URL;
    $vars{'test_data_url'} = $TEST_DATA_URL || $DATA_URL;
    $vars{'classic_url'} = $READ_URL;
    $vars{'app_resources'} = $app->{app_path};
    $vars{'common_resources'} = $app->{common_path};
    
    $app->{txt} =~ s/%%(\w+)%%/$vars{$1}/gse;
    
    return $app->{txt};
}

1;
