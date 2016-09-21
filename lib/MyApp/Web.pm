package MyApp::Web;

use Dancer;
# your modules here
use PBDB::Classic;
# use MyApp::Web::Override;
use Ouch;

use Wing;
use Wing::Dancer;
use Wing::Template; ## Should be the LAST hook added for processing templates.
use MyApp::Web::Account;
use Wing::Web::Account;
use Wing::Web::Admin::User;
use Wing::Web::Admin::Wingman;
use Wing::Web::Admin::Trends;
use Wing::Web::NotFound;



1;
