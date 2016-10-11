package MyApp::Rest::AuthorizerEnterer;

use Wing::Perl;
use Wing;
use Dancer;
use Ouch;
use MyApp::DB::Result::AuthorizerEnterer;
use Wing::Rest;

get '/api/authorizerenterer/:id' => sub {
    my $user = get_user_by_session_id();
    my $authents = site_db()->resultset('AuthorizerEnterer')->search({ id => params->{id} });
    return format_list($authents, current_user => $user); 
};

get '/api/authorizerenterer' => sub {
    my $user = get_user_by_session_id();
    my $search = { };
    my ($key, $lookup, $value);
    if ( my $auth = params->{authorizer} )
    {
	$search = { authorizer_id => $auth };
	$key = 'authorizer';
	$lookup = 'enterer';
	$value = $auth;
    }
    elsif ( my $ent = params->{enterer} )
    {
	$search = { enterer_id => $ent };
	$key = 'enterer';
	$lookup = 'authorizer';
	$value = $ent;
    }
    elsif ( params->{all} )
    {
	$search = { };
    }
    else
    {
	ouch(400, "You must specify one of the following parameters: 'authorizer', 'enterer', 'all'");
    }
    
    my $authents = site_db()->resultset('AuthorizerEnterer')->search($search);
    
    if ( $key )
    {
	my $dbh = site_db()->storage->dbh;

	my $quoted = $dbh->quote($value);
	
	my $sql = "
		SELECT ae.id, ae.${lookup}_id, u.real_name, u.person_no
		FROM authorizer_enterers as ae join users as u on u.id = ae.${lookup}_id
		WHERE ae.${key}_id = $quoted";
	
	my $result = $dbh->selectall_arrayref($sql, { Slice => {} });

	print STDERR "$sql\n\n";

	return $result;
    }

    
    return format_list($authents, current_user => $user); 
};

generate_crud('AuthorizerEnterer');
generate_all_relationships('AuthorizerEnterer');

1;
