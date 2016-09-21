
use Dancer;

use Wing;




post '/login' => sub {
    
    print STDERR "NEW LOGIN\n";
    return template 'account/login', { error_message => 'You must specify a username or email address.'} unless params->{login};
    return template 'account/login', { error_message => 'You must specify a password.'} unless params->{password};
    my $username = params->{login};
    my $password = params->{password};
    my $user = Wing->db->resultset('User')->search({email => $username },{rows=>1})->single;
    unless (defined $user)
    {
        $user = Wing->db->resultset('User')->search({username => $username },{rows=>1})->single;
    }
    
    return template 'account/login', { error_message => 'User not found.'} unless defined $user;
    # validate password
    if (! $user->is_password_valid($password)) {
	return template 'account/login', { error_message => 'Password incorrect.'};
    }
    if ( my $error_message = $user->check_login(params) ) {
	return template 'account/login', { error_message => $error_message };
    }
    return login($user);
};


sub login {
    my ($user) = @_;
    my $session = $user->start_session({ api_key_id => Wing->config->get('default_api_key'), ip_address => request->remote_address });
    set_cookie session_id   => $session->id,
                expires     => '+5y',
                http_only   => 0,
                path        => '/';
    if (params->{sso_id}) {
        my $cookie = cookies->{sso_id};
        my $sso_id = $cookie->value if defined $cookie;
        $sso_id ||= params->{sso_id};
        my $sso = Wing::SSO->new(id => $sso_id, db => Wing->db());
        $sso->user_id($user->id);
        $sso->store;
        if ($sso->has_requested_permissions) {
            return redirect $sso->redirect;
        }
        else {
            return redirect '/sso/authorize?sso_id='.$sso->id;
        }
    }
    my $cookie = cookies->{redirect_after};
    my $uri = $cookie->value if defined $cookie;
    $uri ||= params->{redirect_after} || '/classic';
    return redirect $uri;
};



