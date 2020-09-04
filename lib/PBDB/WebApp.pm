# 
# PBDB::WebApp - A module for displaying web applications as individual HTML pages under the
# PBDB Classic framework.
# 

package PBDB::WebApp;

use lib '/data/MyApp/lib/PBData';

use Encode qw(decode_utf8);
use HTML::Entities qw(encode_entities);
use PBDB::Constants qw($WEBAPP_DIR $WEBAPP_PATH $DATA_URL $TEST_DATA_URL $WRITE_URL);

use ExternalIdent qw(generate_identifier);

use base 'PBDB::HTMLBuilder';


sub new {

    my ($class, $app_name, $file_name, $q, $s, $dbt, $hbo) = @_;
    
    # First check to make sure that the named page is actually there. If $app_name does not
    # contain a '/', then use the string as both the directory name and the file name.
    
    my ($main_filename, $app_path, $common_path);
    
    if ( $file_name )
    {
	$main_filename = "$WEBAPP_DIR/$app_name/$file_name.html";
	$app_path = "$WEBAPP_PATH/$app_name";
    }
    
    else
    {
	$main_filename = "$WEBAPP_DIR/$app_name/${app_name}.html";
	$app_path = "$WEBAPP_PATH/$app_name";
    }
    
    $common_path = "$WEBAPP_PATH/common";
    
    # If the main HTML file is not found, return false.

    # print STDERR "WEBAPP FILENAME: $main_filename\n";
    
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
    
    # If we have any errors, save them now.
    
    my @errors;
    
    foreach my $k ( keys %settings )
    {
	unless ( $k eq 'REQUIRES_LOGIN' || $k eq 'REQUIRES_MEMBER' )
	{
	    push @errors, "Unknown setting '$k'";
	}
    }
    
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
	       error_list => \@errors,
	       settings => \%settings,
	      };
    
    return bless $new;
}


sub requires_login {
    
    my ($app) = @_;
    
    return $app->{settings}{REQUIRES_LOGIN};
}


sub requires_member {

    my ($app) = @_;

    return $app->{settings}{REQUIRES_MEMBER};
}


sub generateBasePage {
    
    my ($app) = @_;
    
    # First substitute variable values for references.
    
    my %vars = ( data_url => $DATA_URL,
		 test_data_url => $TEST_DATA_URL || $DATA_URL,
		 classic_url => $WRITE_URL,
		 app_resources => $app->{app_path},
		 common_resources => $app->{common_path} );
    
    $app->{txt} =~ s/%%(\w+)%%/$app->substitute_value(\%vars, $1)/gse;
    
    return $app->{txt};
}


sub substitute_value {

    my ($app, $vars, $key) = @_;
    
    # If the requested value is in the array, just return it.
    
    if ( defined $vars->{$key} )
    {
	return $vars->{$key};
    }
    
    # Otherwise, call the appropriate method to obtain it.
    
    my $s = $app->{s};
    
    if ( $key eq 'is_contributor' || $key eq 'is_member' )
    {
	return $s->isDBMember() ? 1 : 0;
    }
    
    elsif ( $key eq 'is_loggedin' )
    {
	return $s->isLoggedIn() ? 1 : 0;
    }
    
    elsif ( $key eq 'is_admin' )
    {
	return $s->isSuperUser() ? 1 : 0;
    }
    
    elsif ( $key eq 'user_role' )
    {
	return $s->get('role');
    }
    
    elsif ( $key eq 'user_name' || $key eq 'user_reversed' ||
	    $key eq 'enterer_name' || $key eq 'enterer_reversed' ||
	    $key eq 'authorizer_name' || $key eq 'authorizer_reversed' )
    {
	return $s->get($key);
    }
    
    elsif ( $key eq 'authorizer_id' || $key eq 'enterer_id' )
    {
	my $session_field = $key; $session_field =~ s/_id/_no/;
	my $person_no = $s->get($session_field);
	
	if ( $person_no )
	{
	    $vars->{$key} = generate_identifier('PRS', $person_no);
	}
	
	else
	{
	    $vars->{$key} = '';
	}
	
	return $vars->{$key};
    }
    
    # If we generated any errors in this process, report them.
    
    elsif ( $key eq 'errors' )
    {
	if ( ref $app->{error_list} eq 'ARRAY' )
	{
	    my $error_string = join('; ', @{$app->{error_list}});
	    return $error_string;
	}
	
	else
	{
	    return '';
	}
    }
    
    # If we get here, then the variable does not exist.
    
    else
    {
	push @{$app->{error_list}}, "Bad variable '$key'";
	return '%%' . $key . '%%';
    }
}

1;
