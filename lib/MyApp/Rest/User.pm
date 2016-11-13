package MyApp::Rest::User;

use Wing::Perl;
use Dancer;
use Ouch;
use Wing::Rest;


get '/api/user/contributor' => sub {
    my $user = get_user_by_session_id();
    my $users = site_db()->resultset('User')->search({ -or => {
        username    => { like => '%'.(params->{query} || '').'%'}, 
        email       => { like => '%'.(params->{query} || '').'%'},
        real_name   => { like => '%'.(params->{query} || '').'%'},
    }, person_no => { ">" => 0 } }, {order_by => 'username'});
    return format_list($users, current_user => $user); 
};


get '/api/user/:id/enterers' => sub {
    my $current_user = get_user_by_session_id();
    my $user = fetch_object('User');	# or fetch_object('User', param('id'));
    
    # $user->can_view($current_user);
    
    # my $enterers = $user->enterers->search_related('enterer');
	#search(undef, {prefetch => 'enterer'});
    my $enterers = $user->enterers->search(undef, {prefetch => 'enterer'});
    return format_list($enterers, current_user => $user);
};

1;
