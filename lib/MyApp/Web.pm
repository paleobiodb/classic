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


# hook before_error_init => sub {
#     my $error = shift;
#     my $code = $error->code;
#     my $message = $error->message;
#     my $exception = $error->exception;
#     print STDERR "ERROR $code: $message ($exception)\n";
# };

1;
