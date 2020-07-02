
use Dancer;

use Wing;
use Wing::Web;



post '/login' => sub {
    
    return template 'account/login', { error_message => 'You must specify a username or email address.'} unless params->{login};
    return template 'account/login', { error_message => 'You must specify a password.'} unless params->{password};
    
    my $username = params->{login};
    my $password = params->{password};
    my $schema = Wing->db;
    
    my $user = $schema->resultset('User')->search({username => $username },{rows=>1})->single;
    
    unless ( defined $user )
    {
	my @results = $schema->resultset('User')->search({email => $username });

	if ( @results == 1 )
	{
	    $user = $results[0];
	}

	elsif ( @results > 1 )
	{
	    return template 'account/login', { error_message => 'Email is not unique.' };
	}
    }
    
    unless ( defined $user )
    {
	$user = find_user($username);
	
	if ( !defined $user || $user eq 'NONE' )
	{
	    return template 'account/login', { error_message => 'User not found.'};
	}
	
	elsif ( $user eq 'MULTIPLE' )
	{
	    return template 'account/login', { error_message => 'User name is ambiguous.' };
	}
    }
    
    # validate password
    if (! $user->is_password_valid($password)) {
	return template 'account/login', { error_message => 'Password incorrect.'};
    }
    
    # check for a valid authorizer and make sure that the account is not disabled.
    
    my $authorizer_no = $user->get_column('authorizer_no');
    my $person_no = $user->get_column('person_no');
    my $role = $user->get_column('role');
    my $status = $user->get_column('contributor_status');
    
    if ( $status ne 'active' )
    {
	ouch(403, "This account is disabled.");
    }
    
    if ( $authorizer_no && $person_no )
    {
	if ( $authorizer_no ne $person_no )
	{
	    my $dbh = $schema->storage->dbh;
	    
	    my ($check_no) = $dbh->selectrow_array("
		SELECT authorizer_no FROM authents WHERE authorizer_no = $authorizer_no
			and enterer_no = $person_no");
	    
	    if ( $check_no )
	    {
		$user->login_role('enterer');
		$user->login_authorizer_no($authorizer_no);
		return login($user);
	    }
	}
	
	elsif ( $role eq 'authorizer' )
	{
	    $user->login_role('authorizer');
	    $user->login_authorizer_no($authorizer_no);
	    return login($user);
	}
    }

    elsif ( $role eq 'authorizer' )
    {
	$user->set_column('authorizer_no', $person_no);
	$user->login_role('authorizer');
	$user->login_authorizer_no($person_no);
	return login($user);
    }
    
    elsif ( ($role eq 'enterer' || $role eq 'student') && $person_no )
    {
	my $dbh = $schema->storage->dbh;
	
	my ($authorizer_no) = $dbh->selectrow_array("SELECT authorizer_no FROM authents WHERE enterer_no = $person_no LIMIT 1");
	
	if ( $authorizer_no )
	{
	    $user->set_column('authorizer_no', $authorizer_no);
	    $user->login_role($role);
	    $user->login_authorizer_no($authorizer_no);
	    return login($user);
	}
	
	else
	{
	    ouch(403, "You must be assigned to an authorizer before you can log in.");
	}
    }
    
    $user->login_role('guest');
    $user->login_authorizer_no(0);
    return login($user);
    
    # if ( my $auth_name = params->{authorizer} )
    # {
    # 	my $auth = find_user($auth_name);
	
    # 	if ( !defined $auth || $auth eq 'NONE' )
    # 	{
    # 	    return template 'account/login', { error_message => 'Authorizer not found.' };
    # 	}

    # 	elsif ( $auth eq 'MULTIPLE' )
    # 	{
    # 	    return template 'account/login', { error_message => 'Authorizer is ambiguous.' };
    # 	}

    # 	unless ( authorizer_ok($user, $auth) )
    # 	{
    # 	    return template 'account/login', { error_message => 'You do not have permission from that authorizer.' };
    # 	}
	
    # 	$user->login_role('enterer');
    # 	$user->login_authorizer_no($auth->person_no);
    # 	return login($user);
    # }
    
    # elsif ( $user->role =~ /authorizer/ )
    # {
    # 	$user->login_role('authorizer');
    # 	$user->login_authorizer_no($user->person_no);
    # 	return login($user);
    # }
    
    # elsif ( $user->role =~ /admin/ )
    # {
    # 	$user->login_role('guest');
    # 	$user->login_authorizer_no(0);
    # 	return login($user);
    # }
    
};


post '/account/reset-password' => sub {
    return template 'account/reset-password', {error_message => 'You must supply an email address or username.'} unless params->{login};
    
    my $login = params->{login};
    my $schema = site_db();
    my $user = $schema->resultset('User')->search({username => $login},{rows=>1})->single;
    
    unless (defined $user)
    {
	my @results = $schema->resultset('User')->search({email => $login });
	
	if ( @results == 1 )
	{
	    $user = $results[0];
	}
	
	elsif ( @results > 1 )
	{
	    return template 'account/reset-password', { error_message => 'Email is not unique.' };
	}
	
        # $user = site_db()->resultset('User')->search({email => $login},{rows=>1})->single;
        # return template 'account/reset-password', {error_message => 'User not found.'} unless defined $user;
    }
    
    unless ( defined $user )
    {
	$user = find_user($login);
	
	if ( !defined $user || $user eq 'NONE' )
	{
	    return template 'account/reset-password', { error_message => 'User not found.'};
	}
	
	elsif ( $user eq 'MULTIPLE' )
	{
	    return template 'account/reset-password', { error_message => 'User name is ambiguous.' };
	}
    }
    
    # If we have an e-mail address for this user, send a password-reset message.  Otherwise,
    # there's nothing we can do.
    
    if ($user->email) {
        my $code = $user->generate_password_reset_code();
        $user->send_templated_email(
            'reset_password',
            {
                code        => $code,
            }
        );
        return redirect '/account/reset-password-code';
    }
    
    return template 'account/reset-password', {error_message => 'That account has no email address associated with it.'};
};


sub find_user {
    
    my ($name) = @_;

    my ($first, $last);
    
    if ( $name =~ qr{ ([^,]+) , \s* (.*) }xs )
    {
	$last = $1;
	$first = $2;
	
	$first =~ s/[.]*$/%/;
	
	my (@results) = Wing->db->resultset('User')->search({first_name => { -like => $first }, last_name => { -like => $last } });
	
	if ( @results == 1 )
	{
	    return $results[0];
	}
	
	elsif ( @results == 0 )
	{
	    return 'NONE';
	}

	else
	{
	    return 'MULTIPLE';
	}
    }
    
    elsif ( $name =~ qr{ (\w+) (?: [.] \s* | \s+ ) (.*) }xs )
    {
	$first = $1;
	$last = $2;
	
	my (@results) = Wing->db->resultset('User')->search({first_name => { -like => "$first%" }, last_name => { -like => $last } });
	
	if ( @results == 1 )
	{
	    return $results[0];
	}
	
	elsif ( @results == 0 )
	{
	    return 'NONE';
	}

	else
	{
	    return 'MULTIPLE';
	}
    }
    
    else
    {
	my (@results) = Wing->db->resultset('User')->search({last_name => $name });
	
	if ( @results == 1 )
	{
	    return $results[0];
	}
	
	elsif ( @results == 0 )
	{
	    return 'NONE';
	}

	else
	{
	    return 'MULTIPLE';
	}
    }
};


sub login {
    
    my ($user) = @_;
    
    my $session = $user->start_session({ api_key_id => Wing->config->get('default_api_key'), ip_address => request->remote_address });
    set_cookie session_id   => $session->id,
                expires     => '+5y',
                http_only   => 0,
                path        => '/';
    
    if (params->{app})
    {
	return redirect "/classic/app/" . params->{app};
    }
    
    elsif (params->{action})
    {
	return redirect "/classic/" . params->{action};
    }
    
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
}


sub authorizer_ok {

    my ($user, $authorizer) = @_;
    
    my @auth_list = $user->registered_authorizers();

    foreach my $a (@auth_list)
    {
	if ( $authorizer->person_no eq $a->person_no )
	{
	    return 1;
	}
    }

    return;
}


get '/account/enterers' => sub {
    my $user = get_user_by_session_id();
    template 'account/enterers', { current_user => $user, };
};

our (@CAPTCHA_IMAGE);

BEGIN {
    opendir my $imgdir, "/data/MyApp/captcha/images"; 
    my @allimgfiles = readdir $imgdir;
    
    foreach my $imgfile (@allimgfiles)
    {
	next unless $imgfile =~ /\.gif$/;
	push @CAPTCHA_IMAGE, $imgfile;
    }
}

get '/account/captcha.gif' => sub {
    
    my $random_choice = int rand ( scalar(@CAPTCHA_IMAGE) );
    my $image_name = $CAPTCHA_IMAGE[$random_choice];
    my $remote_addr = request->remote_address || request->env->{REMOTE_ADDR};
    my $image_data;
    
    content_type 'image/gif';
    
    open(TMPFILE, ">", "/data/MyApp/captcha/temp/$remote_addr") || die "could not open file '$remote_addr': $!";
    print TMPFILE $image_name;
    close TMPFILE;
    chmod 07777, "/data/MyApp/captcha/temp/$remote_addr";
    
    open(IMGFILE, "<", "/data/MyApp/captcha/images/$image_name") || die "could not open file '$image_name': $!";
    sysread(IMGFILE, $image_data, 100000);
    
    return $image_data;
};


sub verify_captcha {
    
    my ($verify_text) = @_;
    
    my $remote_addr = request->remote_address || request->env->{REMOTE_ADDR};
    
    open(TMPFILE, "<", "/data/MyApp/captcha/temp/$remote_addr") || die "could not open file '$remote_addr': $!";
    my ($image_name) = <TMPFILE>;    
    close TMPFILE;
    
    if ( $image_name =~ / ^ $verify_text\.gif $/xsi )
    {
	# print STDERR "VERIFIED $verify_text MATCHES $image_name\n";
	return 1;
    }
    
    # print STDERR "REJECTED $verify_text DOES NOT MATCH $image_name\n";
    return 0;
};

1;
