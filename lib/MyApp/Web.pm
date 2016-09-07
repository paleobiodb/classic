package MyApp::Web;

use Dancer;
# your modules here
use Wing::Template; ## Should be the LAST hook added for processing templates.
use Wing::Web::Account;
use Wing::Web::Admin::User;
use Wing::Web::Admin::Wingman;
use Wing::Web::Admin::Trends;
use MyApp::Web::Classic;
use Wing::Web::NotFound;

# use PBDB::Main;

1;
