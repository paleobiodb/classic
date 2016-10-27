package MyApp::DB::Result::AuthEnt;

use Moose;
use Wing::Perl;
use Ouch;



extends 'Wing::DB::Result';
with 'Wing::Role::Result::Field';

__PACKAGE__->wing_fields(
    authorizer_no => {
	view		=> 'public',
	edit		=> 'required',
	dbic		=> { data_type => 'int' },
    });

__PACKAGE__->wing_fields(
    enterer_no => {
	view		=> 'public',
	edit		=> 'unique',
	unique_qualifiers => ['authorizer_no'],
	dbic		=> { data_type => 'int' },
    });


__PACKAGE__->wing_finalize_class( table_name => 'authents' );

__PACKAGE__->belongs_to(authorizer => 'MyApp::DB::Result::User', {'foreign.person_no' => 'self.authorizer_no'});

__PACKAGE__->belongs_to(enterer => 'MyApp::DB::Result::User', {'foreign.person_no' => 'self.enterer_no'});


sub can_edit {
    my ($self, $current_user) = @_;
    
    my $authorizer_no = $self->authorizer_no;
    my $person_no = $current_user->person_no;
    my $role = $current_user->role;
    
    return 1 if $current_user->is_admin;
    
    ouch(450, "You must be an authorizer.")
	unless $role && $role eq 'authorizer';
    
    ouch(450, "Insufficient privileges for this authorizer.")
	unless $authorizer_no && $person_no && $authorizer_no eq $person_no;
    
    return 1;
};


sub verify_posted_params {
    my ($self, $params, $current_user) = @_;
    
    my $authorizer_no = $params->{authorizer_no};
    my $enterer_no = $params->{enterer_no};
    
    my $users = Wing->db->resultset('User');
    
    unless ( $authorizer_no =~ /^\d+$/ )
    {
	ouch(400, "Invalid authorizer_no.");
    }
    
    my $authorizer = $users->search( { person_no => $authorizer_no } )->single;
    
    unless ( $authorizer && $authorizer->role eq 'authorizer' )
    {
	ouch(400, "Invalid authorizer_no.");
    }
    
    unless ( $enterer_no =~ /^\d+$/ && $enterer_no ne $authorizer_no && 
	     $users->search( { person_no => $enterer_no } )->single )
    {
	ouch(400, "Invalid enterer_no.");
    }
    
    unless ( $current_user )
    {
	ouch(450, "You must be logged in.");
    }
    
    $self->authorizer_no($authorizer_no);
    
    $self->can_edit($current_user);
};

    
# around verify_creation_params => sub {
#     my ($orig, $self, $params, $current_user) = @_;
    
#     my $authorizer_no = $params->{authorizer_no};
#     my $person_no = $current_user->person_no;
#     my $role = $current_user->role;
    
#     ouch(450, "You must be an authorizer.")
# 	unless $role && $role eq 'authorizer';
    
#     ouch(450, "Insufficient privileges for this authorizer.")
# 	unless $current_user->is_admin || $authorizer_no && $person_no && $authorizer_no eq $person_no;
    
#     $orig->($self, $params, $current_user);
# };


around describe => sub {
    my ($orig, $self, %options) = @_;
    my $out = $orig->($self, %options);
    $out->{user} = $self->enterer->describe;
    return $out;
};

1;
