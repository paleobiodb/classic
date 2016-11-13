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


sub verify_creation_params {
    
    my ($self, $params, $current_user) = @_;
    
    unless ( $current_user )
    {
	ouch(450, "You must be logged in.");
    }
    
    my $authorizer_no = $params->{authorizer_no};
    my $enterer_no = $params->{enterer_no};
    my $enterer_id = $params->{enterer_id};
    my $role = $params->{role};
    
    my $users = Wing->db->resultset('User');
    
    unless ( $authorizer_no && $authorizer_no =~ /^\d+$/ )
    {
	ouch(400, "Invalid authorizer_no.");
    }
    
    my $authorizer = $users->search( { person_no => $authorizer_no } )->single;
    
    unless ( $authorizer && $authorizer->role eq 'authorizer' )
    {
	ouch(400, "Not an authorizer.");
    }
    
    my $enterer;

    if ( defined $enterer_no && $enterer_no ne '' )
    {
	unless ( $enterer_no =~ /^\d+$/ && $enterer_no ne $authorizer_no )
	{
	    ouch(400, "Invalid enterer_no.");
	}
	
	$enterer = $users->search( { person_no => $enterer_no } )->single;
	
	unless ( $enterer )
	{
	    ouch(400, "Enterer not found.");
	}
    }

    elsif ( defined $enterer_id && $enterer_id ne '' )
    {
	$enterer = $users->search( { id => $enterer_id } )->single;
	
	unless ( $enterer && $enterer_id ne $authorizer->id )
	{
	    ouch(400, "Enterer not found.");
	}
    }

    else
    {
	ouch(400, "Enterer id or number required.");
    }

    if ( $role )
    {
	ouch(400, "Role must be 'enterer' or 'student'.") unless $role eq 'enterer' || $role eq 'student';
    }

    # print STDERR "ENTERER ID = " . $enterer->id . "\n";
    
    my $enterer_role = $enterer->role;
    my $enterer_person_no = $enterer->person_no;
    
    # If the "enterer" is already an authorizer, leave their role alone.
    # Otherwise, set it to the specified value.
    
    if ( $enterer_role eq 'disabled' )
    {
	ouch(400, "That user is disabled.");
    }
    
    elsif ( $enterer_role ne 'authorizer' )
    {
	$enterer->set_role($role || 'enterer');
    }
    
    unless ( $enterer_person_no )
    {
	$enterer_person_no = $enterer->make_person_no;

	ouch(400, "Could not create a person_no value") unless $enterer_person_no;
    }
    
    $self->authorizer_no($authorizer_no);
    $self->enterer_no($enterer_person_no);
    
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
