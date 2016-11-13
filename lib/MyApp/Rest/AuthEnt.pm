package MyApp::Rest::AuthEnt;

use Wing::Perl;
use Wing;
use Dancer;
use Ouch;
use Wing::Rest;


# generate_crud('AuthEnt');

generate_options('AuthEnt');
generate_read('AuthEnt');
generate_delete('AuthEnt');
generate_create('AuthEnt');

1;
