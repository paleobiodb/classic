package MyApp::DB::Result::User;

use Moose;
use Wing::Perl;
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
	view		=> 'public',
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
	options		=> ['guest', 'student', 'enterer', 'authorizer'],
	view		=> 'public',
	indxeded	=> 1,
      },
);

__PACKAGE__->wing_children(
    authorizer_enterers => {
	view		=> 'private',
	edit		=> 'postable',
	related_class	=> 'MyApp::DB::Result::AuthorizerEnterer',
	related_id	=> 'authorizer_id',
    },
);

__PACKAGE__->wing_children(
    enterer_authorizers => {
	view		=> 'private',
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

after delete => sub {
    my $self = shift;
    $self->log_trend('users_deleted', 1, $self->username.' / '.$self->id);
};

after insert => sub {
    my $self = shift;
    $self->log_trend('users_created', 1, $self->username.' / '.$self->id);
};

# Check to make sure that the person logging in is either an authorizer or administrator,
# or if they are an enterer that they have entered a valid authorizer name.

around check_login => sub {
    
    my ($orig, $self, $params) = @_;
    
    if ( $self->role =~ /authorizer/ )
    {
	$self->login_role('authorizer');
	$self->login_authorizer_no($self->person_no);
	return 0;
    }
    
    elsif ( $self->role =~ /admin/ )
    {
	$self->login_role('guest');
	$self->login_authorizer_no(0);
	return 0;
    }
    
    elsif ( $self->role =~ /enterer/ )
    {
	my $authorizer_name = $params->{'authorizer'};
	print STDERR "authorizer = $authorizer_name\n";
	return "Enterer login is not yet enabled";
    }
    
    else
    {
	return "You must be an administrator to log in";
    }
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
    
    my ($self, $session) = @_;
    
    PBDB::Session->end_login_session($session->id);
};

__PACKAGE__->wing_finalize_class( table_name => 'users');


no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);


package MyApp::DB::Result::AuthorizerEnterer;

use Moose;

extends 'Wing::DB::Result';
with 'Wing::Role::Result::Parent';

__PACKAGE__->wing_parents(
    authorizer => {
	view		=> 'public',
	edit		=> 'required',
	related_class	=> 'MyApp::DB::Result::User',
    },
    enterer => {
	view		=> 'public',
	edit		=> 'required',
	related_class	=> 'MyApp::DB::Result::User',
    },
);

__PACKAGE__->wing_finalize_class( table_name => 'authorizer_enterers' );

1;
