package MyApp::DB::Result::User;

use Moose;
use Wing::Perl;
extends 'Wing::DB::Result';
with 'Wing::Role::Result::User';
with 'Wing::Role::Result::Trendy';
#with 'Wing::Role::Result::PrivilegeField';

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

	# Log in to PBDB classic:

	my $person_no = $session->user->person_foo;
	
	# Return session reference.
	
	return $session;
};

__PACKAGE__->wing_finalize_class( table_name => 'users');


no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 0);

