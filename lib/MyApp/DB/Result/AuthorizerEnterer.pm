package MyApp::DB::Result::AuthorizerEnterer;

use Moose;
use Wing::Perl;


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
