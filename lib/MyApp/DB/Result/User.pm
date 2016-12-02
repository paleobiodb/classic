package MyApp::DB::Result::User;

use Moose;
use Wing::Perl;
use Data::Dumper;
use Ouch;
use Carp qw(confess cluck);
# use Dancer ':syntax';

extends 'Wing::DB::Result';
with 'Wing::Role::Result::User';
with 'Wing::Role::Result::Trendy';
with 'Wing::Role::Result::Child';
with 'Wing::Role::Result::Cousin';
#with 'Wing::Role::Result::PrivilegeField';

has login_authorizer_no => ( is => 'rw' );
has login_role => ( is => 'rw' );

#__PACKAGE__->wing_privilege_fields(
#    supervisor              => {},
#);

__PACKAGE__->wing_fields(
      person_no => {
        dbic            => { data_type => 'int', is_nullable => 1 },
        view            => 'public',
	indexed		=> 1,
      },
      authorizer_no => {
	dbic		=> { data_type => 'int', is_nullable => 1 },
	view		=> 'private',
	edit		=> 'postable',
      },
      first_name => {
        dbic            => { data_type => 'varchar(80)', is_nullable => 0 },
        view            => 'public',
        edit            => 'required',
      },
      middle_name => {
	dbic		=> { data_type => 'varchar(80)', is_nullable => 0 },
	view		=> 'public',
	edit		=> 'postable',
      },
      last_name => {
	dbic		=> { data_type => 'varchar(80)', is_nullable => 0 },
	view		=> 'public',
	edit		=> 'required',
	indexed		=> 1,
      },
      country => {
	dbic		=> { data_type => 'char(2)', is_nullable => 0 },
	view		=> 'private',
	edit		=> 'postable',
	indexed		=> 1,
      },
      institution => {
	dbic		=> { data_type => 'varchar(80)', is_nullable => 0 },
	view		=> 'public',
	edit		=> 'required',
      },
      orcid => {
	dbic		=> { data_type => 'varchar(19)', is_nullable => 0 },
	view		=> 'public',
	edit		=> 'postable',
      },
      role => {
	dbic		=> { data_type => 'enum("guest", "authorizer", "enterer", "student")', is_nullable => 0 },
	options		=> ['guest', 'authorizer', 'enterer', 'student'],
	view		=> 'public',
	edit		=> 'admin',
	default_value	=> 'guest',
	indxeded	=> 1,
      },
      contributor_status => {
	dbic		=> { data_type => 'enum("active", "disabled", "deceased")', is_nullable => 0 },
	options		=> ['active', 'disabled', 'deceased'],
	view		=> 'private',
	edit		=> 'admin',
	default_value	=> 'active',
      },
);

__PACKAGE__->wing_datetime_field(
      last_pwchange  => { 
	view => 'private',
      }
);

__PACKAGE__->wing_children(
    authorizer_enterers => {
	view		=> 'public',
	edit		=> 'postable',
	related_class	=> 'MyApp::DB::Result::AuthorizerEnterer',
	related_id	=> 'authorizer_id',
    },
);

__PACKAGE__->wing_children(
    enterer_authorizers => {
	view		=> 'public',
	related_class	=> 'MyApp::DB::Result::AuthorizerEnterer',
	related_id	=> 'enterer_id',
    },
);

__PACKAGE__->wing_cousins(
    registered_enterers => {
	view		=> 'private',
	edit		=> 'postable',
	related_link	=> 'authorizer_enterers',
	related_cousin	=> 'enterer',
    },
);

__PACKAGE__->wing_cousins(
    registered_authorizers => {
	view		=> 'private',
	related_link	=> 'enterer_authorizers',
	related_cousin	=> 'authorizer',
    },
);

__PACKAGE__->wing_finalize_class( table_name => 'users');

__PACKAGE__->has_many(enterers => 'MyApp::DB::Result::AuthEnt', {'foreign.authorizer_no' => 'self.person_no'});

__PACKAGE__->has_many(authorizers => 'MyApp::DB::Result::AuthEnt', {'foreign.enterer_no' => 'self.person_no'});



after delete => sub {
    my $self = shift;
    $self->log_trend('users_deleted', 1, $self->username.' / '.$self->id);
};

after insert => sub {
    my $self = shift;
    $self->log_trend('users_created', 1, $self->username.' / '.$self->id);
};

around start_session => sub {
    
    my ($orig, $self, $options) = @_;
    
    my $session = $orig->($self, $options);
    
    # Generate a PBDB session record using the login parameters, provided that $authorizer_no is
    # not zero or empty.  In the latter case, the person logging in will have no PBDB privileges
    # but will have Wing administrator privileges.
    
    my $session_id = $session->id;
    my $enterer_no = $session->user->person_no;
    my $authorizer_no = $self->login_authorizer_no;
    my $login_role = $self->login_role;
    
    if ( $authorizer_no )
    {
	PBDB::Session->start_login_session($session_id, $enterer_no, $authorizer_no, $login_role);
    }
    
    # Return Wing session reference.
    
    return $session;
};

before end_session => sub {
    
    my ($self) = @_;
    my $session = $self->current_session;
    PBDB::Session->end_login_session($session->id);
};


# Do a bunch of checks before creating a new user.

before verify_creation_params => sub {
    
    my ($self, $params, $current_user) = @_;
    
    # print STDERR "VERIFY_CREATION_PARAMS\n";
    
    # Generate real_name from first_name, middle_name, and last_name.  Do some basic checks on all
    # of these fields.
    
    $params->{first_name} = ucfirst $params->{first_name} if $params->{first_name};
    
    my $first_name = $params->{first_name};
    
    ouch(400, "First name is required") unless $first_name;
    ouch(400, "First name must include at least one letter") unless $first_name =~ /\w/;
    
    if ( $first_name =~ /([@"()#%^*{}\[\]<>?;])/ )
    {
	ouch(400, "Invalid character '$1' in first name");
    }
    
    $params->{last_name} = ucfirst $params->{last_name} if $params->{last_name};
    
    my $last_name = $params->{last_name};
    
    ouch(400, "Last name is required") unless $last_name;
    ouch(400, "Last name must include at least one letter") unless $last_name =~ /\w/i;
    
    $params->{middle_name} = ucfirst $params->{middle_name} if $params->{middle_name};
    
    my $middle_name = $params->{middle_name} || '';
    
    if ( $middle_name )
    {
	$middle_name = $params->{middle_name} = "$middle_name." if $middle_name =~ qr{ ^ \w $ }xsi;
	
	ouch(400, "Middle name must include at least one letter") unless $middle_name =~ /\w/i;
    }
    
    my $real_name = $first_name;
    $real_name .= " $middle_name" if $middle_name;
    $real_name .= " $last_name";
    
    $params->{real_name} = $real_name;
    $params->{name_check_done} = 1;
    
    # Construct a username from first_name, last_name.  Add a numeric suffix if necessary for
    # uniqueness.
    
    my $username = make_username($params->{first_name}, '', $params->{last_name});
    
    my $basename = $username;
    my $suffix = '1';
    
    my $schema = Wing->db;
    
    my $found_user = $schema->resultset('User')->search({username => $username },{rows=>1})->single;
    
    while ( $found_user )
    {
	$username = $basename . $suffix++;
	
	$found_user = $schema->resultset('User')->search({username => $username },{rows=>1})->single;
	
	ouch(400, "Try a different name.") if $found_user && $suffix > 9;
    }
    
    $params->{username} = $username;
    
    # Set default for use_as_display_name
    
    $params->{use_as_display_name} = 'real_name';
    
    # Set default for role
    
    $params->{role} = 'guest';
    
    # Make sure that e-mail, institution, and password are set.
    
    ouch(400, "Institution is required.") unless $params->{institution};
    ouch(400, "Email is required.") unless $params->{email};
    
    unless ( $params->{password} )
    {
	ouch(400, "Password is required!") unless $params->{password1};
	ouch(400, "Repeat your password to make sure you know what you typed.") unless $params->{password2};
	ouch(442, "The passwords you typed do not match.") unless $params->{password1} eq $params->{password2};
    }
    
    # Indicate that we should be checking the CAPTCHA code, *AFTER* all other checks are
    # done. This means we have to put it off until verify_posted_params is called.
    
    $params->{check_captcha} = 1;
};


# The following checks are done when creating a new user or updating a user record.  Some of them
# are skipped on create, signaled by the 'name_check_done' flag, because they would be redundant
# to checks already done under 'verify_creation_params'.  If the 'check_captcha' flag is set (it
# would be set by 'verify_creation_params' above) then do that check as the very last thing.  We
# do this so that the user isn't asked for the CAPTCHA code untill we have verified that all the
# rest of their field values are correct.

before verify_posted_params => sub {

    my ($self, $params, $current_user) = @_;
    
    # print STDERR "VERIFY_POSTED_PARAMS\n";
    
    # If an ORCID was specified, make sure it has the appropriate syntax.
    
    my $orcid = $params->{orcid};
    
    ouch(400, "Invalid ORCID") if defined $orcid && $orcid ne '' &&
	$orcid !~ qr{ ^ \d\d\d\d - \d\d\d\d - \d\d\d\d - \d\d\d[\dX] $ }xs;
    
    # If at least one name parameter was specified, we need to check its value and re-compute
    # real_name. But we skip this check if it was already done in &verify_creation_params.
    
    if ( ! $params->{name_check_done} &&
	 ( defined $params->{first_name} ||
	   defined $params->{last_name} ||
	   defined $params->{middle_name} ) )
    {
	my $first_name = $params->{first_name};
	my $middle_name = $params->{middle_name};
	my $last_name = $params->{last_name};
	
	if ( defined $first_name )
	{
	    $first_name = $params->{first_name} = ucfirst $first_name;
	    
	    ouch(400, "First name is required") if $first_name eq '';
	    ouch(400, "First name must include at least one letter") unless $first_name =~ /\w/;
	    ouch(400, "Invalid character '$1' in first name") if
		$first_name =~ /([@"()#%^*{}\[\]<>?;])/;
	}
	
	else
	{
	    $first_name = $self->first_name;
	}
	
	if ( defined $middle_name )
	{
	    $middle_name = $params->{middle_name} = ucfirst $middle_name;
	    $middle_name = $params->{middle_name} = "$middle_name." if $middle_name =~ qr{ ^ \w $ }xsi;
	    
	    ouch(400, "Middle name must include at least one letter") unless $middle_name eq '' ||
		$middle_name =~ /\w/i;
	    ouch(400, "Invalid character '$1' in middle name") if
		$middle_name =~ /([@"()#%^*{}\[\]<>?;])/;
	}
	
	else
	{
	    $middle_name = $self->middle_name;
	}
	
	if ( defined $last_name )
	{
	    $last_name = $params->{last_name} = ucfirst $last_name;
	    
	    ouch(400, "Last name is required") unless $last_name;
	    ouch(400, "Last name must include at least one letter") unless $last_name =~ /\w/i;
	    ouch(400, "Invalid character '$1' in last name") if
		$last_name =~ /([@"()#%^*{}\[\]<>?;])/;
	}
	
	else
	{
	    $last_name = $self->last_name;
	}
	
	# Now re-build real_name using the new values.
	
	my $real_name = $first_name;
	$real_name .= " $middle_name" if $middle_name;
	$real_name .= " $last_name";
	
	$params->{real_name} = $real_name;
    }
    
    # If the 'check_captcha" flag has been set, do the check now.  We do it here instead of in
    # &verify_creation_params so that it follows all other checks.
    
    if ( $params->{check_captcha} )
    {
	unless ( $params->{verify_text} )
	{
	    ouch(400, "Please enter the code letters from the image.");
	}
	
	unless ( MyApp::Web::verify_captcha($params->{verify_text}) )
	{
	    ouch(400, "Incorrect code letters. Please try again.");
	}
    }
};


sub make_username {
    
    my ($first, $middle, $last) = @_;

    my $username = $first;
    $username .= $middle if $middle;
    $username .= $last;

    $username = lc $username;
    $username =~ s/[^\w]//g;

    return $username;
}


# Whenever a user record is updated, we need to check if it has a person_no value.  If so, then we
# update the corresponding record in the table 'pbdb.person'.

around update => sub {
    
    my ($orig, $self) = @_;
    
    my $person_no = $self->person_no;
    my $name_changed = $self->is_column_changed('real_name');
    my $inst_changed = $self->is_column_changed('institution');
    
    $orig->($self);
    
    return unless $person_no;
    
    # print STDERR "AFTER UPDATE\n";
    
    my $dbh = Wing::db->storage->dbh;
    
    if ( $name_changed )
    {
	# print STDERR "UPDATE NAME\n";
	
	my $sql = "
		UPDATE pbdb.person join users as u using (person_no)
		SET person.first_name = u.first_name,
		    person.middle = u.middle_name,
		    person.last_name = u.last_name,
		    person.name = concat(left(u.first_name,1), '. ', u.last_name),
		    person.reversed_name = concat(u.last_name, ', ', left(u.first_name, 1), '.')
		WHERE person_no = $person_no";
	
	$dbh->do($sql);
    }
    
    if ( $inst_changed )
    {
	# print STDERR "UPDATE INSTITUTION\n";
	
	my $sql = "
		UPDATE pbdb.person join users as u using (person_no)
		SET person.institution = u.institution
		WHERE person_no = $person_no";
	
	$dbh->do($sql);
    }
};


around describe => sub {
    my ($orig, $self, %options) = @_;
    my $dbh = Wing::db->storage->dbh;
    my $out = $orig->($self, %options);
    
    my $role = $self->get_column('role');
    my $person_no = $self->get_column('person_no');
    my $authorizer_no = $self->get_column('authorizer_no');
    
    # $out->{real_authorizer_no} = $authorizer_no;
    
    # if ( ! $authorizer_no && $role eq 'authorizer' )
    # {
    # 	$out->{real_authorizer_no} = $person_no;
    # }
    
    if ( $authorizer_no )
    {
	my ($authorizer_name) = $dbh->selectrow_array("
		SELECT real_name FROM pbdb_wing.users
		WHERE person_no = $authorizer_no LIMIT 1");
	
	$out->{authorizer_name} = $authorizer_name;
    }
    
    # my $quoted = $dbh->quote($out->{id});
    
    # my $sql = "
    # 		SELECT ae.id, ae.authorizer_id, u.real_name, u.person_no
    # 		FROM authorizer_enterers as ae join users as u on u.id = ae.authorizer_id
    # 		WHERE ae.enterer_id = $quoted";
    
    # my $authorizers = $dbh->selectall_arrayref($sql, { Slice => {} }) || [ ];
    
    # $Data::Dumper::Maxlevels = 3;
    # print STDERR Dumper($self);
    
    # foreach my $k ( keys %$self )
    # {
    # 	print STDERR "$k = $self->{$k}\n";
    # }
    
    # my $this_record = $self->{_column_data};
    
    # if ( $this_record->{role} eq 'authorizer' )
    # {
    # 	# print STDERR "IS AUTHORIZER\n";
    # 	unshift @$authorizers, { real_name => $this_record->{real_name},
    # 				 person_no => $this_record->{person_no},
    # 				 authorizer_id => $this_record->{id},
    # 			         default => 1 };
    # }

    # else
    # {
    # 	print STDERR "ROLE = '$role'\n";
    # }
    
    # $out->{authorizers} = $authorizers;
    return $out;
};


around field_options => sub {
    my ($orig, $self, %options) = @_;
    
    my $options_hash = $orig->($self, %options);
    
    my $dbh = Wing::db->storage->dbh;
    my $person_no = $self->get_column('person_no');
    my $quoted = $dbh->quote($person_no);
    my $role = $self->get_column('role');
    
    my $sql = "
		SELECT ae.id, ae.authorizer_no, u.real_name
		FROM authents as ae join users as u on u.person_no = ae.authorizer_no
		WHERE ae.enterer_no = $quoted";
    
    my ($authorizers) = $dbh->selectall_arrayref($sql, { Slice => {} }) || [ ];
    
    my (@auth_list, %auth_labels);
    
    if ( $role && $role eq 'authorizer' )
    {
	push @auth_list, $person_no;
	$auth_labels{$person_no} = 'Myself';
    }
    
    if ( ref $authorizers eq 'ARRAY' && @$authorizers )
    {
	foreach my $a ( @$authorizers )
	{
	    push @auth_list, $a->{authorizer_no};
	    $auth_labels{$a->{authorizer_no}} = $a->{real_name};
	}
    }
    
    $options_hash->{_authorizer_no} = \%auth_labels;
    $options_hash->{authorizer_no} = \@auth_list;
    
    return $options_hash;
};


sub is_authorizer {

    my ($self);
    
    return 1 if $self->role =~ /authorizer/;
    return;
}


sub make_person_no {
    
    my ($self) = @_;
    
    if ( my $person_no = $self->person_no )
    {
	return $person_no;
    }
    
    my $dbh = Wing::db->storage->dbh;
    
    my $first_init = substr($self->first_name, 0, 1);
    my $last_name = $self->last_name;
    my $name_quoted = $dbh->quote("$first_init. $last_name");
    my $reversed_quoted = $dbh->quote("$last_name, $first_init.");
    my $first_quoted = $dbh->quote($self->first_name);
    my $middle_quoted = $dbh->quote($self->middle_name);
    my $last_quoted = $dbh->quote($self->last_name);
    my $inst_quoted = $dbh->quote($self->institution);
    my $email_quoted = $dbh->quote($self->email);
    my $is_authorizer = $self->role eq 'authorizer' ? '1' : '0';
    my $role_quoted = $dbh->quote($self->role);
    my $id_quoted = $dbh->quote($self->id || 'xxx');
    
    my $sql = " INSERT INTO pbdb.person (name, reversed_name, first_name, middle,
			last_name, institution, email, is_authorizer, role)
		VALUES ($name_quoted, $reversed_quoted, $first_quoted, $middle_quoted, $last_quoted,
			$inst_quoted, $email_quoted, $is_authorizer, $role_quoted)";

    unless ( $dbh->do($sql) )
    {
	ouch(500, "Error: could not create person record");
    }
    
    my $person_no = $dbh->{mysql_insertid};
    
    $sql = "	UPDATE users SET person_no = $person_no
		WHERE id = $id_quoted";

    unless ( $dbh->do($sql) )
    {
	ouch(500, "Error: could not set person_no");
    }
    
    return $person_no;
}


sub set_role {
    
    my ($self, $new_role) = @_;

    return if $self->role eq 'authorizer';
    
    return unless $new_role eq 'enterer' || $new_role eq 'student';

    my $dbh = Wing::db->storage->dbh;
    my $quoted_role = $dbh->quote($new_role);
    my $quoted_id = $dbh->quote($self->id || 'xxx');
    
    my $sql = "	UPDATE users SET role = $quoted_role WHERE id = $quoted_id";

    $dbh->do($sql);

    $sql = "	UPDATE pbdb.person JOIN users using (person_no)
		SET pbdb.person.role = $quoted_role
		WHERE users.id = $quoted_id";
    
    $dbh->do($sql);

    print STDERR "$sql\n";
}


after encrypt_and_set_password => sub {
    my ($self) = @_;

    $self->last_pwchange(DateTime->now);
};

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);


1;
