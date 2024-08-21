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
use Dancer qw(debug error);

use base 'PBDB::HTMLBuilder';


sub new {

    my ($class, $app_name, $file_name, $q, $s, $dbt, $hbo) = @_;
    
    # First check to make sure that the named page is actually there.
    
    my $main_filename;
    
    # If two name components are given, the second one specifies the main page file. If the file
    # does not exist in the application directory, return false.
    
    if ( $file_name )
    {
	$main_filename = "$WEBAPP_DIR/$app_name/${file_name}.html";
	return undef unless -e $main_filename;
    }
    
    # If only one component is given, see if a file called main.html exists in the application
    # directory. If so, use that.
    
    elsif ( -e "$WEBAPP_DIR/$app_name/main.html" )
    {
	$main_filename = "$WEBAPP_DIR/$app_name/main.html";
    }
    
    # Otherwise, if a file called $app_name.html exists in the application directory, use that.
    
    elsif ( -e "$WEBAPP_DIR/$app_name/${app_name}.html" )
    {
	$main_filename = "$WEBAPP_DIR/$app_name/${app_name}.html";
    }

    # Otherwise, return false.

    else
    {
	return undef;
    }
    
    # If the main HTML file is not readable, return an error object.
    
    unless ( -r $main_filename )
    {
	return { unreadable => 1 };
    }
    
    # Otherwise, get the contents of the main file.
    
    open my $fh, "<:encoding(UTF-8)", $main_filename or
	die "cannot open main web app page '$main_filename': $!\n";
    
    my $txt = join("",<$fh>);
    
    close $fh;

    # If the main file is empty, add a message to that effect.

    unless ( $txt =~ /[a-zA-Z]/ )
    {
	$txt = "<p>MAIN APPLICATION FILE IS EMPTY.</p>";
    }
    
    # Now look for settings in the top few lines of the file.
    
    my $top_chars = substr($txt, 0, 1000);
    
    my %settings = ( $top_chars =~ /([A-Z_]+) \s* = \s* (.*?) (?:[;\n]|\s+-->)/xg );
    
    # If we have any errors, save them now.
    
    my @errors;
    
    foreach my $k ( keys %settings )
    {
	unless ( $k eq 'REQUIRES_LOGIN' || $k eq 'REQUIRES_MEMBER' ||
		 $k eq 'PAGE_TITLE' )
	{
	    push @errors, "Unknown setting '$k'";
	}
    }
    
    # Otherwise, create a new object and use it to save the parameters.
    
    my $new = {
	       app_name => $app_name,
	       main_filename => $main_filename,
	       app_path => "$WEBAPP_PATH/$app_name",
	       common_path => "$WEBAPP_PATH/common",
	       app_dir => "$WEBAPP_DIR/$app_name",
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


sub page_title {
    
    my ($app) = @_;
    
    return $app->{settings}{PAGE_TITLE};
}


# generateBasePage ( )
#
# Generate the HTML page for this application. The process starts with the application source text
# that was read when the application object was created. Any string of the form %%something%%
# is substituted with the corresponding variable, and any string of the form [[filename]] is
# substituted with the contents of the corresponding file from the application directory.

sub generateBasePage {
    
    my ($app) = @_;
    
    # Then substitute included files. We repeat this check until no substitution is carried out,
    # a maximum of 5 times. This allows included files to themselves contain inclusions.
    
    my $count = 0;	# Prevents endless substitution loops.
    
    while ( $app->{txt} =~ s/ \[ \[ ( \w [^\[\]]{0,255} ) \]? \]? / $app->insert_file($1) /xge )
    {
	if ( ++$count >= 5 )
	{
	    push @{$app->{error_list}}, "Unterminated series of file includes";
	    last;
	}
    }
    
    # Then substitute variable values.
    
    my %vars = ( data_url => $DATA_URL,
		 test_data_url => $TEST_DATA_URL || $DATA_URL,
		 classic_url => $WRITE_URL,
		 referer => Dancer::request->referer,
		 app_components => $app->{app_path},
		 common_components => $app->{common_path} );
    
    $app->{txt} =~ s/ %% ( [ \w \[ \] ]+ ) %% / $app->substitute_value(\%vars, $1) /xge;
    
    # If one of the substitutions was %%errors%%, then substitute it now after everything else has
    # been done.

    if ( $app->{show_errors} )
    {
	my $error_string = '';
	
	if ( ref $app->{error_list} eq 'ARRAY' && @{$app->{error_list}} )
	{
	    $error_string = "<div align='left'><b>ERRORS:<ul><li>" .
		join("\n<li>", @{$app->{error_list}}) .
		"\n</ul></b></div>\n";
	}
	
	$app->{txt} =~ s/%%errors%%/$error_string/xge;
    }
    
    # Return the result.
    
    return $app->{txt};
}


# substitute_value ( vars, key )
# 
# Return text to be substituted into the application source, corresponding to the specified
# key. The $vars parameter is a reference to a hash of variable values.

my %key_map = ( user_name => 'real_name',
		user_first => 'first_name',
		user_middle => 'middle_name',
		user_last => 'last_name',
		user_email => 'email',
		user_institution => 'institution',
		user_orcid => 'orcid' );

sub substitute_value {

    my ($app, $vars, $key) = @_;
    
    # We preserve '%%errors%%' so that it can be substituted at the very end.
    
    if ( $key eq 'errors' )
    {
	$app->{show_errors} = 1;
	return '%%errors%%';
    }
    
    # If the requested value is in the array, just return it.
    
    elsif ( defined $vars->{$key} )
    {
	return $vars->{$key};
    }
    
    # Otherwise, call the appropriate method to obtain it.
    
    my $s = $app->{s};
    my $q = $app->{q};
    
    if ( $key eq 'app_resources' )
    {
	return $vars->{app_components};
    }

    elsif ( $key eq 'common_resources' )
    {
	return $vars->{common_components};
    }
    
    elsif ( $key eq 'is_contributor' || $key eq 'is_member' )
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
    
    elsif ( $key eq 'enterer_name' || $key eq 'enterer_reversed' ||
	    $key eq 'authorizer_name' || $key eq 'authorizer_reversed' )
    {
	return $s->get($key);
    }
    
    elsif ( $key eq 'user_name' || $key eq 'user_email' ||
	    $key eq 'user_first' || $key eq 'user_last' || $key eq 'user_middle' ||
	    $key eq 'user_institution' || $key eq 'user_orcid' )
    {
	$app->{user_info} ||= $s->user_info;
	
	return $app->{user_info}{$key_map{$key}} || '';
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

    elsif ( $key =~ qr{ ^ param \[ (\w+) \] }xs )
    {
	my $value = $q->param($1);

	if ( defined $value )
	{
	    return "'$value'";
	}

	else
	{
	    return "undefined";
	}
    }

    elsif ( $key eq 'params' )
    {
	my $paramstring = '{ ';
	my $sep = '';
	
	if ( ref $q->{params} eq 'HASH' )
	{
	    foreach $key ( keys %{$q->{params}} )
	    {
		my $value = $q->param($key);
		$paramstring .= "$sep'$key': '$value'";
		$sep = ', ';
	    }
	}

	$paramstring .= ' }';

	return $paramstring;
    }
    
    # If we get here, then the variable does not exist.
    
    push @{$app->{error_list}}, "Bad variable '$key'";
    return '%%' . $key . '%%';
}


# insert_file ( filename )
#
# Return the contents of the specified filename in the application directory. If the file is not
# found or not readable, return an error message to be inserted in its place.

sub insert_file {
    
    my ($app, $insert_filename) = @_;
    
    # If the argument doesn't contain at least one alphabetic character, return the empty string.
    
    unless ( $insert_filename =~ /[a-zA-Z]/ )
    {
	return "";
    }
    
    # Otherwise, use the specified argument as the file name. If the file exists in the
    # application directory, return its contents.
    
    my $insert_pathname = $app->{app_dir} . '/' . $insert_filename;
    
    if ( -e $insert_pathname )
    {
	if ( open my $fh, "<:encoding(UTF-8)", $insert_pathname )
	{
	    return join("",<$fh>);
	}

	else
	{
	    error("Could not open insert file '$insert_pathname': $!");
	    my $display_name = encode_entities($insert_filename);
	    return "<p><b>Inserted file &quot;${display_name}&quot; could not be opened.</b></p>";
	}
    }
    
    else
    {
	error("Could not open insert file '$insert_pathname': not found");
	my $display_name = encode_entities($insert_filename);
	return "<p><b>INSERTED FILE &quot;${display_name}&quot; was not found.</b></p>";
    }
}

1;
