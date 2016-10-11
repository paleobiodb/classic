package MyApp::DB::Result::AuthEnt;

use Moose;
use Wing::Perl;



extends 'Wing::DB::Result';
with 'Wing::Role::Result::Field';

__PACKAGE__->wing_fields(
    authorizer_no => {
	view		=> 'public',
	edit		=> 'required',
	dbic		=> { data_type => 'int' },
    },
    enterer_no => {
	view		=> 'public',
	edit		=> 'required',
	dbic		=> { data_type => 'int' },
    },
);

__PACKAGE__->wing_finalize_class( table_name => 'authents' );

1;
