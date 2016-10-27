package MyApp::DB::Result::User;

use Moose;
use Wing::Perl;
use Data::Dumper;
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
        edit            => 'postable',
      },
      middle_name => {
	dbic		=> { data_type => 'varchar(80)', is_nullable => 0 },
	view		=> 'public',
	edit		=> 'postable',
      },
      last_name => {
	dbic		=> { data_type => 'varchar(80)', is_nullable => 0 },
	view		=> 'public',
	edit		=> 'postable',
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
	edit		=> 'postable',
      },
      role => {
	dbic		=> { data_type => 'varchar(80)', is_nullable => 0 },
	options		=> ['guest', 'student', 'enterer', 'authorizer', 'technician'],
	view		=> 'public',
	indxeded	=> 1,
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

after verify_posted_params => sub {
    
    my ($self, $params) = @_;
    
    if ( $params->{real_authorizer_no} )
    {
	my $person_no = $self->get_column('person_no');
	
    }
    
    my $a = 1;
    
    # need to construct real_name from first_name, middle_name, last_name
};

around describe => sub {
    my ($orig, $self, %options) = @_;
    my $dbh = Wing::db->storage->dbh;
    my $out = $orig->($self, %options);
    
    my $role = $self->get_column('role');
    my $person_no = $self->get_column('person_no');
    my $authorizer_no = $self->get_column('authorizer_no');
    
    $out->{real_authorizer_no} = $authorizer_no;
    
    if ( ! $authorizer_no && $role eq 'authorizer' )
    {
    	$out->{real_authorizer_no} = $person_no;
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


no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);


1;
