package MyApp::DB::Result::User;

use Moose;
use Wing::Perl;
use Data::Dumper;
use Ouch;
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

before verify_creation_params => sub {
    
    my ($self, $params, $current_user) = @_;
    
    # check orcid
    
    my $orcid = $params->{orcid};
    
    ouch(400, "Invalid ORCID") if defined $orcid && $orcid ne '' &&
	$orcid !~ qr{ ^ \d\d\d\d - \d\d\d\d - \d\d\d\d - \d\d\d\d $ }xsi;

    # need to construct real_name from first_name, middle_name, last_name

    my $real_name = $params->{first_name};
    
    ouch(400, "First name must include at least one letter") unless $real_name =~ /[a-z]/i;
    
    my $middle_name = $params->{middle_name} || '';
    
    if ( $middle_name )
    {
	$real_name .= " $middle_name";
	$real_name .= "." if $middle_name =~ qr{ ^ [a-z] $ }xsi;

	ouch(400, "Middle name must include at least one letter") unless $middle_name =~ /[a-z]/i;
    }
    
    $real_name .= " " . $params->{last_name};
    
    ouch(400, "Last name must include at least one letter") unless $params->{last_name} =~ /[a-z]/i;
    
    $params->{real_name} = $real_name;
    
    # need to construct username from first_name, last_name
    
    my $username = make_username($params->{first_name}, '', $params->{last_name});
    
    my $mi = substr($params->{middle_name}, 0, 1);
    my $basename = $username;
    my $suffix = '1';
    
    # push @usernames, make_username($params->{first_name}, $mi, $params->{last_name}) if $mi;
    
    my $schema = Wing->db;
    my $found_user;
    
    $found_user = $schema->resultset('User')->search({username => $username },{rows=>1})->single;
    
    while ( $found_user )
    {
	$username = $basename . $suffix++;
	
	$found_user = $schema->resultset('User')->search({username => $username },{rows=>1})->single;
	
	ouch(400, "Try a different name.") if $found_user && $suffix > 9;
    }
    
    $params->{username} = $username;
    
    # set default for use_as_display_name

    $params->{use_as_display_name} = 'real_name';

    # set default for role

    $params->{role} = 'guest';
    
    # check CAPTCHA
    
    unless ( MyApp::Web::verify_captcha($params->{verify_text}) )
    {
	ouch(400, "Invalid code. Please try again.");
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

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);


1;
