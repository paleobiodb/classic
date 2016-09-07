package MyApp::Rest::Classic;

use Wing::Perl;
use Wing;
use Dancer;
use Ouch;
use Wing::Rest;

get '/api/classic' => sub {
    ##remove the eval for data accessible only by registered users
    my $user = eval { get_user_by_session_id() };
    my $classics = site_db()->resultset('Classic')->search({
        -or => {
            'me.name' => { like => '%'.params->{query}.'%'}, 
            #'me.description' => { like => '%'.params->{query}.'%'}, # pretty damn slow, suggest using a real search engine rather than a database
        }
    }, {
        order_by => { -desc => 'me.date_created' }
    });
    return format_list($classics, current_user => $user); 
};

generate_crud('Classic');
generate_all_relationships('Classic');

1;
