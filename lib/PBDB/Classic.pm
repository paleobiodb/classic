package PBDB;
use utf8;

use lib '/data/MyApp/lib/PBData';

use Dancer ':syntax';
use Wing::Perl;
use Ouch;
use Wing;
use Wing::Web;
use Wing::Dancer;
use Carp qw(carp croak);
use Data::Dumper;
use Encode;
# CPAN modules
use URI::Escape;
use Text::CSV_XS;
use HTML::Entities;
use Class::Date qw(date localdate gmdate now);
use DBI;

# PBDB modules
use PBDB::HTMLBuilder;
use PBDB::DBConnection;
use PBDB::DBTransactionManager;
use PBDB::Session;
# use PBDB::Report;

# Autoloaded libs
use PBDB::Person;
use PBDB::PBDBUtil;
use PBDB::Permissions;
use PBDB::Reclassify;
use PBDB::Reference;
use PBDB::ReferenceEntry;  # slated for removal

use PBDB::Collection;
use PBDB::CollectionEntry;  # slated for removal
use PBDB::TaxonInfo;
use PBDB::TimeLookup;
use PBDB::Ecology;
use PBDB::EcologyEntry;
#use Images;
use PBDB::Measurement;
use PBDB::MeasurementEntry;  # slated for removal
use PBDB::TaxaCache;
use PBDB::TypoChecker;
#use PBDB::FossilRecord;
#use PBDB::Cladogram;
use PBDB::Review;
use PBDB::NexusfileWeb;  # slated for removal
use PBDB::PrintHierarchy;
use PBDB::Timescales qw(collectionIntervalLabel);
use PBDB::Strata;
use PBDB::DownloadTaxonomy;
use PBDB::Download;
use PBDB::WebApp;

# god awful Poling modules
use PBDB::Taxon;  # slated for removal
use PBDB::Opinion;  # slated for removal
use PBDB::Validation;
use PBDB::Debug qw(dbg save_request log_request log_step profile_request profile_end_request);
use PBDB::Constants qw($WRITE_URL $DATA_URL $CGI_DEBUG %DEBUG_USERID %CONFIG $LOG_REQUESTS
		       $COLLECTIONS $COLLECTION_NO $OCCURRENCES $OCCURRENCE_NO 
		       makeAnchor);

use IntervalBase;
use ExternalIdent;
# use PBLogger;

our ($PAGE_TOP) = 'std_page_top';
our ($PAGE_BOTTOM) = 'std_page_bottom';


# my $logger = PBLogger->new;
my $logger;

get '/classic' => sub {

    my $action = param('page') ? 'page' : (param('a') || param('action') || 'menu');
    
    return classic_request($action);
};


get '/classic/' => sub {

    my $action = param('page') ? 'page' : (param('a') || param('action') || 'menu');
    
    return classic_request($action);
};


get '/classic/app/:webapp_name' => sub {

    return classic_request('webapp');
};


get '/classic/app/:webapp_name/:file_name' => sub {
    
    return classic_request('webapp');
};


get '/app/:webapp_name' => sub {
    
    return classic_request('webapp');
};


get '/app/:webapp_name/:file_name' => sub {
    
    return classic_request('webapp');
};


get '/classic/:path_action' => sub {
    
    return classic_request(params->{path_action});
};


get '/cgi-bin/bridge.pl' => sub {
    
    my $action = param('page') ? 'page' : (param('a') || param('action'));
    
    if ( $action eq 'login' )
    {
	redirect '/login', 301;
    }
    
    elsif ( $action )
    {
	my $uri = request->uri;
	$uri =~ s{^/cgi-bin/bridge.pl}{/classic/$action};
	
	redirect $uri, 301;
    }
    
    else
    {
	redirect "/classic", 301;
    }
};


post '/cgi-bin/bridge.pl' => sub {
    
    my $action = param('a') || param('action');
    
    if ( $action )
    {
	return classic_request(params->{path_action});
    }
    
    else
    {
	ouch(404, "Not found");
    }
};


post '/classic' => sub {
    
    my $action = param('action') || param('a') || 'bad_action';
    
    return classic_request($action);
};


post '/classic/:path_action' => sub {

    return classic_request(params->{path_action});
};


sub classic_request {

    my ($action) = @_;
    
    # $DB::single = 1;
    
    my ($starttime, $profile_out);
    
    if ( $action eq 'testerror' )
    {
	croak "Test error!!!";
    }
    
    # Log this request if $LOG_REQUESTS is true.
    
    if ( $CONFIG{LOG_REQUESTS} || $CONFIG{PROFILE_REQUESTS} )
    {
	$starttime = time;
	log_request($action, $starttime) if $CONFIG{LOG_REQUESTS};
	$profile_out = profile_request($action) if DB->can('enable_profile') ||
	    $CONFIG{PROFILE_REQUESTS};
    }
    
    # Get a database connection handle.
    
    my $dbt = PBDB::DBTransactionManager->new();
    
    # Determine the remote address from which this request came. If X-Real-IP is set, use
    # that. Otherwise, the remote address will just be a dummy one set up by docker. We have to
    # check for request->headers first, in case we are running for test or debugging purposes
    # from the command line and there are no headers.
    
    my $remote_addr;
    
    if ( request->headers )
    {
	$remote_addr = request->header('X-Real-IP') || request->env->{REMOTE_ADDR};
    }
    
    else
    {
	$remote_addr = request->env->{REMOTE_ADDR};
    }
    
    # Create a PBDB session record, starting with the info we get from Wing. This gives us info about
    # the user who made the request and about the current login session.
    
    my $wing_session = get_session();
    
    my $user = $wing_session ? $wing_session->user : undef;
    
    my $s = PBDB::Session->new($dbt, $wing_session, $remote_addr);
    
    # If the session was invalid, redirect to the login page. This may occur, for example, if too
    # long a period of time has elapsed since the last activity. It may also occur if the user
    # changed their password.
    
    if ( $s->{reason} )
    {
	return redirect "/login?reason=$s->{reason}", 303;
    }
    
    # If we have a logged-in user, save the user object as a variable so that the
    # before_error_render hook has access to it in case an exception is thrown.

    if ( $user )
    {
	var 'user' => $user;
    }
    
    # Create a PBDB request record. This tells us about the parameters of the current request.
    
    my $q = PBDB::Request->new(request->method, scalar(params), request->uri, cookies);
    
    # If we are not running under debug mode, and if the $CGI_DEBUG flag is on, then save this
    # request for later debugging.
    
    my $apphandler = config->{apphandler} || '';

    # print STDERR "CGI_DEBUG: $CGI_DEBUG\n";
    # print STDERR "apphandler: $apphandler\n";
    
    if ( $CGI_DEBUG && $apphandler && $apphandler ne 'Debug' )
    {
	if ( ! %DEBUG_USERID || $DEBUG_USERID{$s->{enterer_no}} )
	{
	    # print STDERR "Saving request\n";
	    save_request($q);
	}
    }

    # If this is a request from a mobile device, substitute a different page top and bottom.
    
    # if ( $ENV{'HTTP_USER_AGENT'} =~ /Mobile/i && $ENV{'HTTP_USER_AGENT'} !~ /iPad/i )	{
    # 	local $PAGE_TOP = 'mobile_top';
    # 	local $PAGE_BOTTOM = 'mobile_bottom';
    # }
    
    # Now start processing the request.
    
    if ( $action eq 'menu' )
    {
	$s->clearQueue();
    }
    
    # if ( $action eq 'basicCollectionSearch' ) { $action = 'displayCollResults'; $q->param('type'
    # => 'view'); $q->param('basic' => 'yes'); }
    # print STDERR "SESSION_ID = $session_id\n";
    # print STDERR $q->list_params;
    
    my $use_guest = (!$s->isDBMember()) ? 1 : 0;
    
    if ( $action eq 'home' )
    {
	$use_guest = 1;
	$action = 'menu';
    }
    
    my $hbo = PBDB::HTMLBuilder->new($dbt,$s,$use_guest,'');
    
    if ( param('redirectMain') )
    {
	return redirect '/classic', 303;
    }
    
    # Figure out reference number and name, if there is one saved for this session.
    
    my $reference_no = $s->{reference_no};
    my $reference_name = '';
    my $dbh = $dbt->{dbh};
    
    if ( $action =~ /^displayRefResults|^displaySearchRefs/ && params->{type} eq 'select' || 
         $action =~ /^selectReference|enterReferenceData/ && params->{reference_no} )
    {
	my ($data) = PBDB::Reference::getReferences($dbt,$q,$s,$hbo);
	
	if ( $data && @$data == 1 )
	{
	    $reference_no = $data->[0]{reference_no};
	    $s->setReferenceNo($reference_no);
	    
	    my %params = $s->dequeue();

	    if ( %params )
	    {	    
		$action = $q->reset_params(\%params);
	    }
	    
	    else
	    {
		$action = 'menu';
	    }
	}
    }
    
    elsif ( $action eq 'dequeue' )
    {
	my %params = $s->dequeue();
	$action = $q->reset_params(\%params);
    }
    
    elsif ( $action eq 'clearRef' )
    {
	$s->setReferenceNo(0);
	$reference_no = 0;
	$action = 'menu';
    }
    
    if ( $reference_no )
    {
	# print STDERR "REFERENCE_NO = $reference_no\n";
	
	my ($a1l, $a2l, $oa, $pubyr) = $dbh->selectrow_array("
		SELECT author1last, author2last, otherauthors, pubyr
		FROM refs WHERE reference_no = $reference_no");
	
	if ( $oa )
	{
	    $reference_name = "$a1l, et al. $pubyr";
	}
	
	elsif ( $a2l )
	{
	    $reference_name = "$a1l and $a2l $pubyr";
	}
	
	elsif ( $a1l )
	{
	    $reference_name = "$a1l $pubyr";
	}
	
	else
	{
	    $reference_name = 'ERROR';
	}
    }
    
    # Make sure we have cached interval data
    
    unless ( IntervalBase->cache_filled )
    {
	IntervalBase->cache_interval_data($dbt->dbh);
    }
    
    
#     if ( $q->path_info() =~ m{^/nexus/} ) {
# 	$action = 'getNexusFile';
#     } $DB::single = 1;
    
#     elsif ( $action ne 'processNexusUpload' and $action ne 'updateNexusFile' and $action ne 'getNexusFile' ) {
#         print $q->header(-type => "text/html", 
#                      -Cache_Control=>'no-cache',
#                      -expires =>"now" );
#     }

    $action =~ s/[^a-zA-Z0-9_]//g;
    
    my $action_sub = \&{"PBDB::$action"}; # Hack so use strict doesn't break
    
    my $vars = { pbdb_site => Wing->config->get('pbdb_site'),
	         options => MyApp::DB::Result::Classic->field_options };
    
    if ($user)
    {
        $vars->{current_user} = $user;
	$vars->{authorizer_no} = $s->{authorizer_no};
	$vars->{enterer_no} = $s->{enterer_no};
	$vars->{authorizer_name} = $s->{authorizer_name};
	$vars->{reference_name} = $reference_name;
	$vars->{reference_no} = $reference_no;
    }
    
    my $action_output;
    
    no warnings 'once';
    
    eval {
	$action_output = &$action_sub($q, $s, $dbt, $hbo);
    };
    
    my $endtime = time;
    
    if ( $@ )
    {
	error("MESSAGE: $@");
	
	log_step($action, 'EXCEPTION', $endtime, $starttime) if $CONFIG{LOG_REQUESTS};
	profile_end_request($profile_out, 0) if $profile_out;
	
	if ( $@ =~ /^Undefined subroutine.*$action/i )
	{
	    ouch 404, "Page not found", { path => request->path };
	}
	
	else
	{
	    die $@;
	}
    }
    
    elsif ( ! $action_output && ! $DB::OUT )
    {
	log_step($action, 'NO OUTPUT', $endtime, $starttime) if $CONFIG{LOG_REQUESTS};
	profile_end_request($profile_out, 0) if $profile_out;
	ouch 500, "No output was generated.", { path => request->path };
    }
    
    elsif ( $q->param('output_format') eq 'csv' )
    {
	my $response = Dancer::SharedData->response;
	$response->content_type('text/csv');
	
	return "\x{FEFF}" . $action_output;
    }
    
    else
    {
	$vars->{page_title} = $hbo->pageTitle || 'PBDB';
	
	my $output = template 'header_include', $vars;
	
	$output .= $action_output;
	
	$output .= template 'footer_include', { };
	
	log_step($action, 'DONE', time, $starttime) if $CONFIG{LOG_REQUESTS};
	profile_end_request($profile_out, $starttime, $q) if $profile_out;
	
	return $output;
    }
};


sub execAction {

    my ($q, $s, $dbt, $hbo, $action) = @_;
    
    my $action_sub = \&{"PBDB::$action"};
    my $return_output;
    
    eval {
	$return_output = &$action_sub($q, $s, $dbt, $hbo);
    };
    
    if ( $@ )
    {
	ouch 500, $@, { path => request->path };
    }

    return $return_output;
}


# Return a new object with the parameters of the current request, for use in cases where bad
# programming has led to the one generated in &classic_request above being altered.

sub freshParams {
    
    return PBDB::Request->new(request->method, scalar(params), request->uri, cookies);
}


# Generate an exception for test purposes

sub testException {

    die "Test Exception\n";
}


# Preferences

sub displayPreferencesPage {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    if (!$s->isDBMember()) {
	redirect '/login?reason=login', 303;
        # login( "Please log in first.");
        # return;
    }
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Session::displayPreferencesPage($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Preferences');
    
    return $output;
}

sub setPreferences {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    if (!$s->isDBMember()) {
	redirect '/login?reason=login', 303;
        # login( "Please log in first.");
        # return;
    }
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Session::setPreferences($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Preferences');
    
    return $output;
}

# displays the main menu page for the data enterers
sub menu	{
    
    my ($q, $s, $dbt, $hbo, $message) = @_;
    
    my ($package, $filename, $line) = caller;

    my $output = '';
    my %vars;
    $vars{'message'} = $message;
    
	# Clear Queue?  This is highest priority
	if ( $q->param("clear") ) {
		$s->clearQueue(); 
	} else {
	
		# QUEUE
		# See if there is something to do.  If so, do it first.
		my %queue = $s->dequeue();
		my $action = $queue{action} || $queue{a};
		if ( $action ) {
	
			# Set each parameter
			foreach my $parm ( keys %queue ) {
				$q->param($parm => $queue{$parm});
			}

	 		# Run the command
			return execAction($q, $s, $dbt, $hbo, $action);
		}
	}

	if ($s->isDBMember()) {
		$output = $hbo->stdIncludes($PAGE_TOP);
		unless ( $s->get('role') =~ /authorizer|enterer/ )
		{
			$vars{'limited'} = 1;
		}
		$output .= $hbo->populateHTML('menu',\%vars);
		$output .= $hbo->stdIncludes($PAGE_BOTTOM);
	} else	{
        	# if ($q->param('user') eq 'Contributor') {
		# 	login( "Please log in first.","menu" );
		# } else	{
		# 	menu($q, $s, $dbt, $hbo);
		# }
	    $output = $hbo->stdIncludes($PAGE_TOP);
	    $output .= $hbo->populateHTML('menu', \%vars);
	    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
	}
    
    $hbo->pageTitle('PBDB Main Menu');
    
    return $output;
}


sub displayDownloadForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
	my %vars = $q->Vars();
	$vars{'authorizer_me'} = $s->get("authorizer_reversed");
	$vars{'enterer_me'} = $s->get("authorizer_reversed");

	my $last;
	if ( $s->isDBMember() )	{
		$vars{'row_class_1a'} = '';
		$vars{'row_class_1b'} = ' class="lightGray"';
		my $dbh = $dbt->dbh;
		if ( $q->param('restore_defaults') )	{
			my $sql = "UPDATE person SET last_action=last_action,last_download=NULL WHERE person_no=".$s->get('enterer_no');
			$dbh->do($sql);
		} else	{
			$last = ${$dbt->getData("SELECT last_download FROM person WHERE person_no=".$s->get('enterer_no'))}[0]->{'last_download'};
			if ( $last )	{
				$vars{'has_defaults'} = 1;
				my @pairs = split '/',$last;
				for my $p ( @pairs )	{
					my ($k,$v) = split qr{=},$p;
					$vars{$k} = $v;
				}
			}
		}
	} else	{
		$vars{'row_class_1a'} = ' class="lightGray"';
		$vars{'row_class_1b'} = '';
	}

    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Person::makeAuthEntJavascript($dbt);
    $output .= $hbo->populateHTML('download_form',\%vars);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Download Form (old)');
    
    return $output;
}


sub displayDownloadGenerator {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
	my %vars = $q->Vars();
	$vars{'authorizer_me'} = $s->get("authorizer_reversed");
	$vars{'enterer_me'} = $s->get("authorizer_reversed");
	$vars{'data_url'} = $DATA_URL;
	
	my $last;
	if ( $s->isDBMember() )	{
		$vars{'row_class_1a'} = '';
		$vars{'row_class_1b'} = ' class="lightGray"';
		my $dbh = $dbt->dbh;
		if ( $q->param('restore_defaults') )	{
			my $sql = "UPDATE person SET last_action=last_action,last_download=NULL WHERE person_no=".$s->get('enterer_no');
			$dbh->do($sql);
		} else	{
			$last = ${$dbt->getData("SELECT last_download FROM person WHERE person_no=".$s->get('enterer_no'))}[0]->{'last_download'};
			if ( $last )	{
				$vars{'has_defaults'} = 1;
				my @pairs = split '/',$last;
				for my $p ( @pairs )	{
					my ($k,$v) = split qr{=},$p;
					$vars{$k} = $v;
				}
			}
		}
	} else	{
		$vars{'row_class_1a'} = ' class="lightGray"';
		$vars{'row_class_1b'} = '';
	}

    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Person::makeAuthEntJavascript($dbt);
    $output .= $hbo->populateSimple('download_generator',\%vars);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Download Generator');

    return $output;
}


sub webapp {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $app_name = $q->param('webapp_name');
    my $file_name = $q->param('file_name');
    
    unless ( $app_name )
    {
	ouch 404, 'Page Not Found', { path => request->path };
	return;
    }
    
    my $app = PBDB::WebApp->new($app_name, $file_name, $q, $s, $dbt, $hbo);
    
    unless ( $app )
    {
	ouch 404, 'Page Not Found', { path => request->path };
	return;
    }
    
    if ( $app->requires_member && ! $s->isDBMember() )
    {
	redirect "/login?app=$app_name&reason=login", 303;
    }

    if ( $app->requires_login && ! $s->isLoggedIn() )
    {
	$app_name .= "/$file_name" if $file_name;
	redirect "/login?app=$app_name&reason=login", 303;
    }
    
    my $output = $app->stdIncludes('app_page_top');
    $output .= PBDB::Person::makeAuthEntJavascript($dbt) if $app->{settings}{INCLUDE_AUTHENT};
    $output .= $app->generateBasePage();
    $output .= $app->stdIncludes('app_page_bottom');
    
    $hbo->{page_title} = $app->page_title || 'PBDB App';
    
    return $output;
}


sub displayBasicDownloadForm {
    
    my ($q, $s, $dbt, $hbo) = @_;

	my %vars = $q->Vars();
	my $last;
	if ( $s->get('enterer_no') > 0 )	{
		$last = ${$dbt->getData("SELECT last_download FROM person WHERE person_no=".$s->get('enterer_no'))}[0]->{'last_download'};
		my @pairs = split '/',$last;
		for my $p ( @pairs )	{
			my ($k,$v) = split qr{=},$p;
			$vars{$k} = $v;
		}
	    }
    
    my $output = $hbo->stdIncludes($PAGE_TOP );
    $output .= $hbo->populateHTML('basic_download_form',\%vars);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Download Form (old)');
    
    return $output;
}

sub displayDownloadResults {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    logRequest($s,$q);

    my $output = $hbo->stdIncludes( $PAGE_TOP );
    
    my $m = PBDB::Download->new($dbt,$q,$s,$hbo);
    $output .= $m->buildDownload( );
    
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Download Results');

    return $output;
}


sub displayReportForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output =$hbo->stdIncludes( $PAGE_TOP );
    $output .= $hbo->populateHTML('report_form');
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Report Form');
    
    return $output;
}

# sub displayReportResults {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
#     logRequest($s,$q);
    
#     my $output = $hbo->stdIncludes( $PAGE_TOP );
    
#     my $r = PBDB::Report->new($dbt,$q,$s);
#     $output .= $r->PBDB::Report::buildReport();
#     $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
#     return $output;
# }

# sub displayMostCommonTaxa	{
    
#     my ($q, $s, $dbt, $hbo, $dataRowsRef) = @_;
    
#     # my $dataRowsRef = shift;
    
#     logRequest($s,$q);
    
#     my $output = $hbo->stdIncludes( $PAGE_TOP );
    
#     my $r = PBDB::Report->new($dbt,$q,$s);
#     $output .= $r->findMostCommonTaxa($dataRowsRef);
    
#     $output .= $hbo->stdIncludes($PAGE_BOTTOM);

#     return $output;
# }

# sub displayCountForm	{
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
#     my $output = $hbo->stdIncludes( $PAGE_TOP );
#     $output .= PBDB::Person::makeAuthEntJavascript($dbt);
#     $output .= $hbo->populateHTML('taxon_count_form');
#     $output .= $hbo->stdIncludes($PAGE_BOTTOM);

#     return $output;
# }

# sub fastTaxonCount	{
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
#     return if PBDB::PBDBUtil::checkForBot();
#     logRequest($s,$q);
    
#     my $output = $hbo->stdIncludes( $PAGE_TOP );
#     $output .= PBDB::Report::fastTaxonCount($dbt,$q,$s,$hbo);
#     $output .= $hbo->stdIncludes($PAGE_BOTTOM);

#     return $output;
# }


# sub countNames	{
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
#     logRequest($s,$q);
    
#     my $output = $hbo->stdIncludes( $PAGE_TOP );
    
#     my $r = PBDB::Report->new($dbt,$q,$s);
#     $output .= $r->countNames();
#     $output .= $hbo->stdIncludes($PAGE_BOTTOM);

#     return $output;
# }


# Show a generic page
sub page {
    
    my ($q, $s, $dbt, $hbo, $page) = @_;
    
	# my $page = shift;
	if ( ! $page ) { 
		# Try the parameters
		$page = $q->param("page"); 
		if ( ! $page ) {
		    my $output = $hbo->stdIncludes($PAGE_TOP);
		    $output .= "<h2>page(): Unknown page...</h2>\n";
		    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
		    
		    return $output;
		}
	}

    # Spit out the HTML
    my $output = '';
    
    if ( $page !~ /\.eps$/ && $page !~ /\.gif$/ )	{
	$output .= $hbo->stdIncludes( $PAGE_TOP );
    }
    
    $output .= $hbo->populateHTML($page,[],[]);
    
    if ( $page !~ /\.eps$/ && $page !~ /\.gif$/ )	{
	$output .= $hbo->stdIncludes( $PAGE_BOTTOM );
    }
    
    return $output;
}

sub displaySearchRefs {
    
    my ($q, $s, $dbt, $hbo, $error) = @_;
    
    # my $error = shift;
    
    my $output = $hbo->stdIncludes( $PAGE_TOP );
    $output .= PBDB::Reference::displaySearchRefs($dbt,$q,$s,$hbo,$error);
    $output .= $hbo->stdIncludes( $PAGE_BOTTOM );
    
    $hbo->pageTitle('PBDB Reference Search');
    
    return $output;
}

sub selectReference {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    $s->setReferenceNo($q->numeric_param("reference_no") );
    return menu($q, $s, $dbt, $hbo );
}

sub enterReferenceData {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = '';
    
    unless ( $s->isLoggedIn() )
    {
	redirect '/login?reason=login', 303;
    }
    
    unless ( $s->isDBMember() )
    {
	$output .= $hbo->stdIncludes($PAGE_TOP);
	$output .= "<h2>You must be a database contributor to enter data.</h2>";
	$output .= $hbo->stdIncludes($PAGE_BOTTOM);
    }
    
    else
    {
	if ( my $reference_no = $q->numeric_param("reference_no") )
	{
	    $s->setReferenceNo($reference_no);
	}
	
	my $vars = { };
	
	$output .= $hbo->stdIncludes($PAGE_TOP);
	$output .= $hbo->populateHTML('enter_data', $vars);
	$output .= $hbo->stdIncludes($PAGE_BOTTOM);
    }
    
    $hbo->pageTitle('PBDB Enter Data');
    
    return $output;
}

# Wrapper to displayRefEdit
sub editCurrentRef {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $reference_no = $s->get("reference_no");
    
    if ( $reference_no ) 
    {
	$q->param("reference_no"=>$reference_no);
	return displayReferenceForm($q, $s, $dbt, $hbo);
    } 
    
    else 
    {
	$q->param("type"=>"edit");
	
        my $output = $hbo->stdIncludes( $PAGE_TOP );
	$output .= PBDB::Reference::displaySearchRefs($dbt,$q,$s,$hbo,"<center>Please choose a reference first</center>" );
        $output .= $hbo->stdIncludes( $PAGE_BOTTOM );
	
	$hbo->pageTitle('PBDB Bibliographic Reference Search');
	
	return $output;
    }
}

sub displayRefResults {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $type = $q->param('type');
    my $reference_no = $q->numeric_param('reference_no');
    
    # if ( $type eq 'select' && $reference_no && $reference_no > 0 )
    # {
    # 	$s->setReferenceNo($reference_no);
    # 	PBDB::menu($q, $s, $dbt, $hbo);
    # }
    
    logRequest($s,$q);
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Reference::displayRefResults($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Bibliographic Reference Results');
    
    return $output;
}

# sub getReferencesXML {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
#     logRequest($s,$q);
#     return PBDB::Reference::getReferencesXML($dbt,$q,$s,$hbo);
# }

sub getTitleWordOdds	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    logRequest($s,$q);
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Reference::getTitleWordOdds($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Title Word Odds');
    
    return $output;
}

sub displayReferenceForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    if (!$s->isDBMember()) {
	redirect '/login?reason=login', 303;
	# login( "Please log in first.");
	# return;
    }
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::ReferenceEntry::displayReferenceForm($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitleDefault('PBDB Enter Bibliographic Reference');
    
    return $output;
}

sub displayReference {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Reference::displayReference($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Bibliographic Reference');
    
    return $output;
}

sub processReferenceForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::ReferenceEntry::processReferenceForm($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Bibliographic Reference Saved');
    
    return $output;
}


# 7.11.09 JA
sub quickSearch	{
    
    my ($q, $s, $dbt, $hbo) = @_;

    my $dbh = $dbt->dbh;
    
    my $qs = $q->param('quick_search');
    $qs =~ s/\./%/g;
    $qs =~ s/\s+/ /g;
    $qs =~ s/ $//;
    $qs =~ s/^ //;
    
    $q->param('quick_search' => $qs);

    # print STDERR "qs: $qs\n";
    
    # Decide what to do based on the form of the quicksearch parameter.

    # 1) If it is either single number or an external identifier, then attempt to display the
    # corresponding entity. A single number is taken to be a collection identifier by default.
    
    my $ident = ExternalIdent::valid_identifier($qs, {}, 'ANY');
    
    if ( $ident && $ident->{value} )
    {
	my $num = $ident->{value}{num};
	my $type = $ident->{value}{type};
	
	if ( $type eq 'col' || $type eq 'unk' )
	{
	    $q->param("collection_no" => $num);
	    my $result = PBDB::Collection::basicCollectionSearch($dbt,$q,$s,$hbo);

	    if ( $result )
	    {
		$hbo->pageTitleDefault('PBDB Collection Results');
		
		return $hbo->stdIncludes($PAGE_TOP) . $result . $hbo->stdIncludes($PAGE_BOTTOM);
	    }
	}
	
	elsif ( $type eq 'txn' || $type eq 'var' )
	{
	    $q->param('taxon_no' => $num);
	    return redirect "/classic/basicTaxonInfo?taxon_no=$num", 303;
	    # my $result = PBDB::TaxonInfo::basicTaxonInfo($q, $s, $dbt, $hbo);
	    
	    # if ( $result )
	    # {
	    # 	return $hbo->stdIncludes($PAGE_TOP) . $result . $hbo->stdIncludes($PAGE_BOTTOM);
	    # }
	}
	
	# elsif ( $type eq 'opn' )
	# {
	    
	# }

	else
	{
	    my $output = $hbo->stdIncludes( $PAGE_TOP );
	    $output .= menu($q, $s, $dbt, $hbo, "<center>You must use the data service to retrieve information about '$qs'</center>");
	    $output .= $hbo->stdIncludes( $PAGE_BOTTOM );
	    
	    $hbo->pageTitle('PBDB Main Menu');
	    
	    return $output;
	}
    }

    # 2) If it looks like 'author year', search for a reference.
    
    elsif ( $qs =~ / ^ ( .* [a-zA-Z] .* ) \s+ (\d\d\d\d) $ /xs )
    {
	$q->param('name_pattern' => 'equals');
	$q->param('name' => $1);
	$q->param('year_relation' => 'in');
	$q->param('year' => $2);
	return displayRefResults($q, $s, $dbt, $hbo);
    }

    # 3) If it looks like a stratum, search for that.

    elsif ( $qs =~ / ^ ( .* [a-zA-Z] .* ) \s+ (group|grp|formation|fm|member|mbr) $ /xsi )
    {
	$q->param('collection_name' => $qs);
	my $result = PBDB::Collection::basicCollectionSearch($dbt,$q,$s,$hbo);
	
	if ( $result )
	{
	    $hbo->pageTitleDefault('PBDB Stratum Results');
	    
	    return $hbo->stdIncludes($PAGE_TOP) . $result . $hbo->stdIncludes($PAGE_BOTTOM);
	}
    }

    # 4) If it is quoted, assume it is a collection name.

    elsif ( $qs =~ / ^ " ( .* [a-zA-Z] .* ) " $ /xs )
    {
	$q->param('collection_name' => $1);
	my $result = PBDB::Collection::basicCollectionSearch($dbt,$q,$s,$hbo);
	
	if ( $result )
	{
	    $hbo->pageTitleDefault('PBDB Collection Results');
	    
	    return $hbo->stdIncludes($PAGE_TOP) . $result . $hbo->stdIncludes($PAGE_BOTTOM);
	}
   }
    
    # Otherwise, we need to differentiate between taxonomic names and collection names.

    else
    {
	# If it looks like a taxon name, check first to see if one can be found.
	
	if ( PBDB::Taxon::validTaxonName($qs) )
	{
	    my $quoted = $dbh->quote($qs);
	    my $sql = "SELECT taxon_no FROM authorities WHERE taxon_name = $quoted";
	    my $taxon = ${$dbt->getData($sql)}[0];
	    
	    if ( $taxon )
	    {
		$q->param('taxon_name' => $qs);
		return redirect "/classic/basicTaxonInfo?taxon_name=$qs", 303;
		# return basicTaxonInfo($q, $s, $dbt, $hbo);
	    }
	}
	
	# If we get here, that means we didn't find a matching taxon. So look for a collection.

	$q->param('collection_name' => $qs);
	my $result = PBDB::Collection::basicCollectionSearch($dbt,$q,$s,$hbo);
	
	if ( $result )
	{
	    $hbo->pageTitleDefault('PBDB Collection Results');
	    
	    return $hbo->stdIncludes($PAGE_TOP) . $result . $hbo->stdIncludes($PAGE_BOTTOM);
	}
    }
    
	# # case 1 or 2: search string cannot be a taxon name, so search elsewhere
	# my $nowDate = now();
	# my ($date,$time) = split / /,$nowDate;
	# my ($yyyy,$mm,$dd) = split /-/,$date,3;
	# if ( $qs =~ /[^A-Za-z% ]/ || $qs =~ / .* / )	{
	# # case 1: string looks like author/year, so try references
	# 	my @words = split / /,$qs;
	# 	if ( $words[$#words] =~ /^\d+$/ && $words[$#words] >= 1758 && $words[$#words] <= $yyyy )	{
	# 		$q->param('name_pattern' => 'equals');
	# 		$q->param('name' => $words[0]);
	# 		$q->param('year_relation' => 'in');
	# 		$q->param('year' => $words[$#words]);
	# 		return displayRefResults($q, $s, $dbt, $hbo);
	# 	}
	# # case 2: otherwise or if that fails, try collections
	# 	my $found = PBDB::Collection::basicCollectionSearch($dbt,$q,$s,$hbo);
	# 	return $found if $found;
	# # if basicCollectionSearch finds any match it should exit somehow before
	# #   this point, so try a common name search as a desperation measure
	# 	if ( $qs !~ /[^A-Za-z' ]/ )	{
	# 		return basicTaxonInfo($q,$s,$dbt,$hbo);
	# 	}
	# }
	# else	{
	# 	my $sql = "SELECT count(*) c FROM authorities WHERE taxon_name LIKE '".$qs."'";
    	# 	my $t = ${$dbt->getData($sql)}[0];
	# # case 3: string is formatted correctly and matches at least one name,
	# #  so search taxa only
	# 	if ( $t->{'c'} > 0 )	{
	# 		return basicTaxonInfo($q,$s,$dbt,$hbo);
	# 	}
	# # case 4: search is formatted correctly but does not directly match
	# #  any name, so first try collections and then try taxa again (which
	# #  will yield some kind of a match somehow)
	# 	else	{
	# 		my $found = PBDB::Collection::basicCollectionSearch($dbt,$q,$s,$hbo);
	# 		return $found if $found;
	# 		return basicTaxonInfo($q,$s,$dbt,$hbo);
	# 	    }
	# }

	# if we don't have any idea what they're driving at, send them home
	# this point should only ever be reached if nothing works whatsoever
	#  and no error message is returned by anything else, which is only
	#  ever likely to happen if basicTaxonInfo isn't called
    
    my $output = $hbo->stdIncludes( $PAGE_TOP );
    $output .= menu($q, $s, $dbt, $hbo, '<center>Your search failed to recover any data records</center>');
    $output .= $hbo->stdIncludes( $PAGE_BOTTOM );
    
    $hbo->pageTitle('PBDB Main Menu');
    
    return $output;
}


# 5.4.04 JA
# print the special search form used when you are adding a collection
# uses some code lifted from displaySearchColls
sub displaySearchCollsForAdd	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    

    if (!$s->isDBMember()) {
	redirect '/login?reason=login', 303;
	# login( "Please log in first.");
	# return;
    }
    
	# Have to have a reference #, unless we are just searching
	my $reference_no = $s->get("reference_no");
	if ( ! $reference_no ) {
	    # Come back here... requeue our option
	    $s->enqueue_action("displaySearchCollsForAdd");
	    $q->param('type' => 'select');
	    return displaySearchRefs($q, $s, $dbt, $hbo, "<center>Please choose a reference first</center>");
	}

	# Some prefilled variables like lat/lng/time term
	my %pref = $s->getPreferences();
	
	# Spit out the HTML
    my $output = $hbo->stdIncludes( $PAGE_TOP );
    $output .= $hbo->populateHTML('search_collections_for_add_form' , \%pref);
    $output .= $hbo->stdIncludes( $PAGE_BOTTOM );
    
    $hbo->pageTitle('PBDB Duplicate Collection Search');
    
    return $output;
}


sub displaySearchColls {
    
    my ($q, $s, $dbt, $hbo, $error) = @_;
    
    # Get the type, passed or on queue
    
    my $type = $q->param("type");
    
    unless ( $type )
    {
	my %queue = $s->dequeue();
	$type = $queue{type} || 'view';
    }
    
    # Have to have a reference #, unless we are just searching
    
    my $reference_no = $s->get("reference_no");
    
    if ( ! $reference_no && $type !~ /^(?:basic|analyze_abundance|view|edit|reclassify_occurrence|count_occurrences|most_common)$/)
    {
	# Come back here... requeue our option
	$s->enqueue_action("displaySearchColls", "type=$type");
	$q->param('type' => 'select');
	return displaySearchRefs($q, $s, $dbt, $hbo, "<center>Please choose a reference first</center>" );
    }
    
    # Show the "search collections" form
    
    my %vars = ();
    $vars{'enterer_me'} = $s->get('enterer_reversed');
    $vars{'action'} = "displayCollResults";
    $vars{'type'} = $type;
    $vars{'error'} = $error;
    
    $vars{'links'} = qq|
<p><span class="mockLink" onClick="javascript: document.collForm.submit();"><b>Search collections</b></span>
|;

    if ( $type eq "view" || ! $type )	{
	$vars{'links'} = qq|
<p><span class="mockLink" onClick="document.collForm.basic.value = 'yes'; document.collForm.submit();"><b>Search for basic info</b></span> -
<span class="mockLink" onClick="document.collForm.basic.value = ''; document.collForm.submit();"><b>Search for full details</b></span></p>
|;
    }
    
    elsif ($type eq 'occurrence_table')
    {
	$vars{'reference_no'} = $reference_no;
	$vars{'limit'} = 20;
    }
    
   # If there are errors, put them together into an HTML list.
    
    my $error_content;
    
    if ( ref $error eq 'ARRAY' )
    {
	my $error_content = "<ul>\n";
	
	foreach my $msg ( @$error )
	{
	    $error_content .= "<li>$msg</li>\n";
	}
	
	$error_content .= "</ul>\n";
	
	$vars{error} = $error_content;
    }
    
    elsif ( $error )
    {
	$vars{error} = "<ul><li>$error</li></ul>\n";
    }
    
    # Spit out the HTML

    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Person::makeAuthEntJavascript($dbt);
    $vars{'page_title'} = "Collection search form";
    # print PBDB::PBDBUtil::printIntervalsJava($dbt,1);
    $output .= $hbo->populateHTML('search_collections_form', \%vars);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Collection Search');
    
    return $output;
}

sub basicCollectionSearch	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Collection::basicCollectionSearch($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitleDefault('PBDB Collection Results');
    
    return $output;
}


# User submits completed collection search form
# System displays matching collection results
# Called during collections search, and by displayReIDForm() routine.
sub displayCollResults {
    
    my ($q, $s, $dbt, $hbo, $dataRows) = @_;
    
    my $output = '';
    
    # dataRows might be passed in by basicCollectionSearch
    # my $dataRows = shift;
    
    my $ofRows;
    if ( $dataRows && ref $dataRows eq 'ARRAY' )	{
	$ofRows = scalar(@$dataRows);
    }
    
    # return if PBDB::PBDBUtil::checkForBot();
    
    # if ( ! $s->get('enterer') && $q->param('type') eq "reclassify_occurrence" )    {
    # 	$output .= $hbo->stdIncludes( $PAGE_TOP );
    # 	$output .= "<center>\n<p class=\"pageTitle\">Sorry!</p>\n";
    # $output .= "<p>You can't reclassify occurrences unless you <a href=\"https://paleobiodb.org/account\">login</a> first.</p>\n</center>\n";
    # 	$output .= $hbo->stdIncludes($PAGE_BOTTOM);
    # 	return;
    # }
    
    logRequest($s,$q);
    
    my $limit = $q->param('limit') || 30 ;
    my $rowOffset = $q->param('rowOffset') || 0;
    
    # limit passed to permissions module
    my $perm_limit;
    
    # effectively don't limit the number of collections put into the
    #  initial set to examine when adding a new one
    
    if ( $q->param('type') eq "add" )
    {
	#		$perm_limit = 1000000;
	$perm_limit = $limit + $rowOffset;
    } 
    
    else
    {
	if ($q->param("type") =~ /occurrence_table|occurrence_list|count_occurrences|most_common/ ||
            $q->param('taxon_name') && ($q->param('type') eq "reid" ||
                                        $q->param('type') eq "reclassify_occurrence")) {
            # We're passing the collection_nos directly to the functions, so pass all of them                                            
	    $perm_limit = 1000000000;
	} else {
	    $perm_limit = $limit + $rowOffset;
	}
    }
    
    my $type = $q->param('type');
    
    $type = 'view' if $q->param('view');
    
    unless ( $type )
    {
	my %queue = $s->dequeue();		# Most of 'em are queued
	$type = $queue{type} || 'view';
    }
    
    my $exec_url = ($type =~ /view/) ? "" : $WRITE_URL;
    
    my $action = ($type eq "add") ? "displayCollectionDetails"
	       : ($type eq "edit") ? "displayCollectionForm"
	       : ($type eq "view") ? "displayCollectionDetails"
	       : ($type eq "edit_occurrence") ? "displayOccurrenceAddEdit"
	       : ($type eq "occurrence_list") ? "displayOccurrenceListForm"
#              : ($type eq "analyze_abundance") ? "rarefyAbundances"
	       : ($type eq "reid") ? "displayOccsForReID"
	       : ($type eq "reclassify_occurrence") ?  "startDisplayOccurrenceReclassify"
	       : ($type eq "most_common") ? "displayMostCommonTaxa"
	       : "displayCollectionDetails";

	# GET COLLECTIONS
	# Build the SQL
	# which function to use depends on whether the user is adding a collection
    my $sql;
    
    my ($errors,$warnings,$occRows) = ([],[],[]);
    
    if ( $q->param('type') eq "add" )
    {
	# you won't have an in list if you are adding
	($dataRows,$ofRows) = PBDB::CollectionEntry::processCollectionsSearchForAdd($q, $s, $dbt, $hbo);
	
	unless ( ref $dataRows )
	{
	    return displaySearchCollsForAdd($q, $s, $dbt, $hbo);
	}
    } 
    
    elsif ( ! $dataRows )
    {
	my %options = $q->Vars();
	
	my $fields = ["authorizer", "country", "state", "max_interval_no", "min_interval_no",
		      "collection_aka","collectors","collection_dates"];
	
	if ($type eq "reclassify_occurrence" || $type eq "reid")
	{
	    # Want to not get taxon_nos when reclassifying. Otherwise, if the
	    # taxon_no is set to zero, how will you find it?
	    $options{'no_authority_lookup'} = 1;
	    $options{'match_subgenera'} = 1;
	}
	
	$options{'limit'} = $perm_limit;
	
	# Do a looser match against old ids as well
	
	$options{'include_old_ids'} = 1;
	
	# Even if we have a match in the authorities table, still match against
	# the bare occurrences/reids  table
	
	$options{'include_occurrences'} = 1;
	
	if ($q->param("taxon_list"))
	{
	    my @in_list = split(/,/,$q->param('taxon_list'));
	    $options{'taxon_list'} = \@in_list if (@in_list);
	}
	
	if ($type eq "count_occurrences")
	{
	    $options{'count_occurrences'} = 1;
	}
	
	if ($type eq "most_common")
	{
	    $options{'include_old_ids'} = 0;
	}
	
	if ( $options{view} =~ /standard/ )
	{
	    $options{sortby} ||= 'collection_no';
	    $options{limit} ||= 30;
	}
	
	$options{'calling_script'} = "displayCollResults";
	
	($dataRows,$ofRows,$errors,$occRows) = 
	    PBDB::Collection::getCollections($dbt, $s, \%options, $fields);
	
	if ( ref $errors eq 'ARRAY' && @$errors )
	{
	    return displaySearchColls($q, $s, $dbt, $hbo, $errors);
	}
    }
    
    # DISPLAY MATCHING COLLECTIONS
    my @dataRows;
    
    if ( $dataRows && ref $dataRows eq 'ARRAY' )
    {
	@dataRows = @$dataRows;
    }
    
    my $displayRows = scalar(@dataRows);	# get number of rows to display
    
    if ( $type eq 'occurrence_table' && @dataRows)
    {
	my @colls = map {$_->{$COLLECTION_NO}} @dataRows;
	return displayOccurrenceTable($q, $s, $dbt, $hbo, \@colls);
    }
    
    elsif ( $type eq 'count_occurrences' && @dataRows)
    {
	return PBDB::Collection::countOccurrences($dbt,$hbo,\@dataRows,$occRows);
    }
    
    elsif ( $type eq 'most_common' && @dataRows)
    {
	return displayMostCommonTaxa(\@dataRows);
    }
    
    elsif ( $displayRows > 1  || ($displayRows == 1 && $type eq "add"))
    {
	# go right to the chase with ReIDs if a taxon_rank was specified
	if ($q->param('taxon_name') && ($q->param('type') eq "reid" ||
                                        $q->param('type') eq "reclassify_occurrence"))
	{
	    # get all collection #'s and call displayOccsForReID
	    my @colls;
	    
	    foreach my $row (@dataRows)
	    {
		push(@colls , $row->{$COLLECTION_NO});
	    }
	    
	    if ($q->param('type') eq 'reid')
	    {
		return displayOccsForReID($q, $s, $dbt, $hbo, \@colls);
	    }
	    
	    else
	    {
		return startDisplayOccurrenceReclassify($q,$s,$dbt,$hbo,\@colls);
	    }
	}
	
	$output .= $hbo->stdIncludes( $PAGE_TOP );
	
	# Display header link that says which collections we're currently viewing
	if (@$warnings) {
	    $output .= "<div align=\"center\">".PBDB::Debug::printWarnings($warnings)."</div>";
	}
	
	$output .= "<center>";
	
	if ($ofRows > 1)
	{
	    $output .= "<p class=\"pageTitle\">There are $ofRows matches\n";
	    
	    if ($ofRows > $limit)
	    {
		$output .= " - here are";
		
		if ($rowOffset > 0)
		{
		    $output .= " rows ".($rowOffset+1)." to ";
		    my $printRows = ($ofRows < $rowOffset + $limit) ? $ofRows : $rowOffset + $limit;
		    $output .= $printRows;
		}
		
		else
		{
		    $output .= " the first ";
		    my $printRows = ($ofRows < $rowOffset + $limit) ? $ofRows : $rowOffset + $limit;
		    $output .= $printRows;
		    $output .= " rows";
		}
	    }
	    
	    $output .= "</p>\n";
	}
	
	elsif ( $ofRows == 1 )
	{
	    $output .= "<p class=\"pageTitle\">There is exactly one match</p>\n";
	}
	
	else
	{
	    $output .= "<p class=\"pageTitle\">There are no matches</p>\n";
	}
	
	$output .= "</center>\n";
	
	$output .= qq|<div class="displayPanel" style="margin-left: auto; margin-right: auto; padding: 0.5em; padding-left: 1em;">
	<table class="small" border="0" cellpadding="4" cellspacing="0">|;

	# print columns header
	$output .= qq|<tr>
<th>Collection</th>
<th align=left>Authorizer</th>
<th align=left nowrap>Collection name</th>
<th align=left>Reference</th>
|;
	
	$output .= "<th align=left>Distance</th>\n" if ($type eq 'add');
	$output .= "</tr>\n\n";
	
        # Make non-editable links not highlighted  
        my ($p,%is_modifier_for); 
        if ($type eq 'edit') { 
            $p = PBDB::Permissions->new($s,$dbt);
            # %is_modifier_for = %{$p->getModifierList()};
        }

	# Loop through each data row of the result set
        my %seen_ref;
        my %seen_interval;
        
	for(my $count=$rowOffset;$count<scalar(@dataRows) && $count < $rowOffset+$limit;$count++)
	{
            my $dataRow = $dataRows[$count];
	    
	    # Get the reference_no of the row
	    
            my $reference;
	    
            if ($seen_ref{$dataRow->{'reference_no'}})
	    {
                $reference = $seen_ref{$dataRow->{'reference_no'}};
            }
	    
	    else
	    {
                my $sql = "SELECT reference_no,author1last,author2last,otherauthors,pubyr FROM refs WHERE reference_no=".$dataRow->{'reference_no'};
                my $ref = ${$dbt->getData($sql)}[0];
                # Build the reference string
                $reference = PBDB::Reference::formatShortRef($ref,'alt_pubyr'=>1, 'link_id'=>1);
                $seen_ref{$dataRow->{'reference_no'}} = $reference;
            }
	    
	    # Build a short descriptor of the collection's time place
	    # first part JA 7.8.03
	    
	    my $timeplace = '';
	    
	    if ( $dataRow->{max_interval_no} )
	    {
		$timeplace = PBDB::Timescales::collectionIntervalLabel($dataRow->{max_interval_no},
						     $dataRow->{min_interval_no});
		$timeplace .= " - ";
	    }
	    
            # if ($seen_interval{$dataRow->{'max_interval_no'}." ".$dataRow->{'min_interval_no'}}) {
            #     $timeplace = $seen_interval{$dataRow->{'max_interval_no'}." ".$dataRow->{'min_interval_no'}}." - ";
            # } elsif ( $dataRow->{'max_interval_no'} > 0 )	{
            #     my @intervals = ();
            #     push @intervals, $dataRow->{'max_interval_no'} if ($dataRow->{'max_interval_no'});
            #     push @intervals, $dataRow->{'min_interval_no'} if ($dataRow->{'min_interval_no'} && $dataRow->{'min_interval_no'} != $dataRow->{'max_interval_no'});
            #     my $max_lookup;
            #     my $min_lookup;
            #     if (@intervals) {
            #         my $t = new PBDB::TimeLookup($dbt);
            #         my $lookup = $t->lookupIntervals(\@intervals,['interval_name','ten_my_bin']);
            #         $max_lookup = $lookup->{$dataRow->{'max_interval_no'}};
            #         if ($dataRow->{'min_interval_no'} && $dataRow->{'min_interval_no'} != $dataRow->{'max_interval_no'}) {
            #             $min_lookup = $lookup->{$dataRow->{'min_interval_no'}};
            #         } 
            #     }
            #     $timeplace .= "<nobr>" . $max_lookup->{'interval_name'} . "</nobr>";
            #     if ($min_lookup) {
            #         $timeplace .= "/<nobr>" . $min_lookup->{'interval_name'} . "</nobr>"; 
            #     }
            #     if ($max_lookup->{'ten_my_bin'} && (!$min_lookup || $min_lookup->{'ten_my_bin'} eq $max_lookup->{'ten_my_bin'})) {
            #         $timeplace .= " - <nobr>$max_lookup->{'ten_my_bin'}</nobr> ";
            #     }
            #     $timeplace .= " - ";

            # }
			# $timeplace =~ s/\/(Lower|Upper)//g;

	    # rest of timeplace construction JA 20.8.02
	    if ( $dataRow->{"state"} && $dataRow->{"country"} eq "United States" )	{
		$timeplace .= $dataRow->{"state"};
	    } else	{
		$timeplace .= $dataRow->{"country"};
	    }
	    
	    # should it be a dark row, or a light row?  Alternate them...
	    if ( $count % 2 == 0 ) {
		$output .= "<tr class=\"darkList\">";
	    } else {
		$output .= "<tr>";
	    }
	    
            if ( $type ne 'edit' || 
		 $type eq 'edit' && ($s->get("superuser") ||
				     $s->get("role" =~ /^auth|^ent|^stud/)) )
				     # ($s->get('authorizer_no') && 
				     #  $s->get("authorizer_no") == $dataRow->{'authorizer_no'}) ||
				     # $is_modifier_for{$dataRow->{'authorizer_no'}}) )
	    {
                # This needs re-coding to make the html anchor work - jpjenk
                if ( $q->param('basic') =~ /yes/i && $type eq "view" || $q->param('view') =~ /standard/ )
		{
                    $output .= "<td align=center valign=top><a href=\"$exec_url?a=basicCollectionSearch&amp;$COLLECTION_NO=$dataRow->{$COLLECTION_NO}";
                }
		
		else
		{
                    $output .= "<td align=center valign=top><a href=\"$exec_url?a=$action&amp;$COLLECTION_NO=$dataRow->{$COLLECTION_NO}";
                }
		
                # for collection edit:
		
                if ( $q->param('use_primary') )
		{
                    $output .= "&use_primary=yes";
                }
                
                # These may be useful to displayOccsForReID
		
                if ( $q->param('genus_name') )
		{
                    $output .= "&genus_name=".$q->param('genus_name');
                }
                
                if( $q->param('species_name') )
		{
                    $output .= "&species_name=".$q->param('species_name');
                }
		
                if ( $q->param('occurrences_authorizer_no') )
		{
                    $output .= "&occurrences_authorizer_no=".$q->numeric_param('occurrences_authorizer_no');
                }
                
		$output .= "\">$dataRow->{$COLLECTION_NO}</a></td>";
		
            }
	    
	    else
	    {	
                # Don't link it if if we're in edit mode and we don't have permission
                $output .= "<td align=center valign=top>$dataRow->{$COLLECTION_NO}</td>";
            }
	    
            my $collection_names = $dataRow->{'collection_name'};
	    
            if ( $dataRow->{'collection_aka'} || $dataRow->{'collectors'} || 
		 $dataRow->{'collection_dates'} )
	    {
                $collection_names .= " (";
            }
	    
            if ( $dataRow->{'collection_aka'} )
	    {
                $collection_names .= "= $dataRow->{collection_aka}";
		
                if ( $dataRow->{'collectors'} || $dataRow->{'collection_dates'} )
		{
                    $collection_names .= " / ";
                }
            }
	    
            if ( $dataRow->{'collectors'} || $dataRow->{'collection_dates'} )
	    {
                $collection_names .= "coll.";
            }
            
	    if ( $dataRow->{'collectors'} )
	    {
                my $collectors = " ";
                $collectors .= $dataRow->{'collectors'};
                $collectors =~ s/ \(.*\)//g;
                $collectors =~ s/ and / \& /g;
                $collectors =~ s/(Dr\.)(Mr\.)(Prof\.)//g;
                $collectors =~ s/\b[A-Za-z]([A-Za-z\.]|)\b//g;
                $collectors =~ s/\.//g;
                $collection_names .= $collectors;
            }
	    
            if ( $dataRow->{'collection_dates'} )
	    {
                my $years = " ";
                $years .= $dataRow->{'collection_dates'};
                $years =~ s/[A-Za-z\.]//g;
                $years =~ s/([^\-]) \b[0-9]([0-9]|)\b/$1/g;
                $years =~ s/^( |),//;
                $collection_names .= $years;
            }
	    
            if ( $dataRow->{'collection_aka'} || $dataRow->{'collectors'} ||
		 $dataRow->{'collection_dates'} )
	    {
                $collection_names .= ")";
            }
	    
            if ( $dataRow->{'old_id'} )
	    {
                $timeplace .= " - old id";
            }
	    
            $output .= "<td valign=top nowrap>$dataRow->{authorizer}</td>\n";
            $output .= qq|<td valign="top" style="padding-left: 0.5em; text-indent: -0.5em;"><span style="padding-right: 1em;">${collection_names}</span> <span class="tiny"><i>${timeplace}</i></span></td>
|;
            $output .= "<td valign=top nowrap>$reference</td>\n";
            $output .= "<td valign=top align=center>".int($dataRow->{distance})." km </td>\n" if ($type eq 'add');
            $output .= "</tr>";
	}
	
	$output .= "</table>\n</div>\n";
    }
    
    # if only one row to display...
    
    elsif ( $displayRows == 1 )
    { 
	$q->param($COLLECTION_NO=>$dataRows[0]->{$COLLECTION_NO});
	
	if ( $q->param('basic') =~ /yes/i && $type eq "view" || $q->param('view') =~ /standard/ )
	{
	    my $output = $hbo->stdIncludes($PAGE_TOP);
	    $output .= PBDB::Collection::basicCollectionInfo($dbt,$q,$s,$hbo);
	    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
	    return $output;
	}
	
	# Do the action directly if there is only one row
	
	return execAction($q, $s, $dbt, $hbo, $action);
	
    }
    
    # If this is an add, and there are no matching results, display the
    # collection form.
    
    elsif ( $type eq "add" )
    {
	$hbo->pageTitle('PBDB Enter Collection');
	
	return displayCollectionForm($q, $s, $dbt, $hbo);
    }
    
    # Otherwise, there are no results, so display the search form again.
    
    else
    {
	my $error = "Your search produced no matches: please try again";
	return displaySearchColls($q, $s, $dbt, $hbo, $error);
    }
    
    ###
    # Display the footer links
    ###
    $output .= "<center><p>";

    # this q2  var is necessary because the processCollectionSearch
    # method alters the CGI object's internals above, and deletes some fields 
    # so, we create a new CGI object with everything intact
    my $q2 = PBDB::Request->new(request->method, scalar(params), request->uri);
    
    my @params = $q2->param;
    my $getString = "rowOffset=".($rowOffset+$limit);
    foreach my $param_key (@params) {
        if ($param_key ne "rowOffset") {
            if ($q2->param($param_key) ne "") {
                $getString .= "&".uri_escape_utf8($param_key // '')."=".uri_escape_utf8($q2->param($param_key) // '');
            }
        }
    }

    if (($rowOffset + $limit) < $ofRows) {
        my $numLeft;
        if (($rowOffset + $limit + $limit) > $ofRows) { 
            $numLeft = "the last " . ($ofRows - $rowOffset - $limit);
        } else {
            $numLeft = "the next " . $limit;
        }
        $output .= "<a href=\"$exec_url?$getString\"><b>View $numLeft matches</b></a> - ";
	
	my $getAll = $getString;
	$getAll =~ s/\browOffset=\d+&?//;
	$getAll =~ s/\blimit=\d+/limit=10000/;
	
	$output .= "<a href=\"$exec_url?$getAll\"><b>View all</b></a> - ";
    } 

	if ( $type eq "add" )	{
		$output .= makeAnchor("displaySearchCollsForAdd", "type=add", "Do another search");
	} else	{
		$output .= makeAnchor("displaySearchColls", "type=$type", "Do another search");
	}

    $output .= "</center></p>";
    # End footer links


	if ( $type eq "add" ) {
		$output .= qq|<form action="$exec_url">\n|;

		# stash the lat/long coordinates to be populated on the
		#  entry form JA 6.4.04
		my @coordfields = ("latdeg","latmin","latsec","latdec","latdir",
				"lngdeg","lngmin","lngsec","lngdec","lngdir");
		for my $cf (@coordfields)	{
			if ( $q->param($cf) )	{
				$output .= "<input type=\"hidden\" name=\"$cf\" value=\"";
				$output .= $q->param($cf) . "\">\n";
			}
		}

		$output .= qq|<input type="hidden" name="action" value="displayCollectionForm">
|;
		$output .= qq|<center>\n<input type=submit value="Add a new collection">|;
		$output .= "</center>\n</form>\n";
	}
		
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitleDefault('PBDB Collection Results');
    
    return $output;
} # end sub displayCollResults


sub displayCollectionForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    # Have to be logged in
    if (!$s->isDBMember()) {
	redirect '/login?reason=login', 303;
        # login("Please log in first.");
        # return;
    }

    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::CollectionEntry::displayCollectionForm($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitleDefault('PBDB Enter Collection');
    
    return $output;
}

sub processCollectionForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    if (!$s->isDBMember()) {
	redirect '/login?reason=login', 303;
        # login("Please log in first.");
        # return;
    }
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::CollectionEntry::processCollectionForm($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Collection Saved');
    
    return $output;
}

sub displayCollectionDetails {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    logRequest($s,$q);

    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::CollectionEntry::displayCollectionDetails($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Collection');
    
    return $output;
}

# sub rarefyAbundances {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
#     return if PBDB::PBDBUtil::checkForBot();
#     logRequest($s,$q);

#     my $output = $hbo->stdIncludes($PAGE_TOP);
#     $output .= PBDB::Collection::rarefyAbundances($dbt,$q,$s,$hbo);
#     $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
#     return $output;
# }

sub displayCollectionEcology	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
	return if PBDB::PBDBUtil::checkForBot();
	logRequest($s,$q);
	
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Collection::displayCollectionEcology($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Collection Ecology');
    
    return $output;
}

sub explainAEOestimate	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
	return if PBDB::PBDBUtil::checkForBot();
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Collection::explainAEOestimate($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_TOP);
    
    $hbo->pageTitle('PBDB AEO Estimate');
    
    return $output;
}

# PS 11/7/2005
#
# Generic opinions earch handling form.
# Flow of this is a little complicated
#
sub submitOpinionSearch {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    if ($q->param('taxon_name')) {
        $q->param('goal'=>'opinion');
        $output .= processTaxonSearch($q,$s,$dbt,$hbo);
    } else {
        $q->param('goal'=>'opinion');
        $output .= PBDB::Opinion::displayOpinionChoiceForm($q, $s, $dbt, $hbo);
    }
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitleDefault('PBDB Opinion Results');
    
    return $output;
}

# JA 17.8.02
#
# Generic authority search handling form, used as a front end for:
#  add/edit authority, add/edit opinion, add image, add ecology data, search by ref no
#
# Edited by rjp 1/22/2004, 2/18/2004, 3/2004
# Edited by PS 01/24/2004, accept reference_no instead of taxon_name optionally
#
sub submitTaxonSearch {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= processTaxonSearch($q, $s, $dbt, $hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitleDefault('PBDB Taxon Results');
    
    return $output;
}

sub processTaxonSearch {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = '';
    my $dbh = $dbt->dbh;
	# check for proper spacing of the taxon..
	my $errors = PBDB::Errors->new();
	$errors->setDisplayEndingMessage(0); 

    if ($q->param('taxon_name')) {
        if (! PBDB::Taxon::validTaxonName($q->param('taxon_name'))) {
            $errors->add("Ill-formed taxon name.  Check capitalization and spacing.");
        }
    }

    # Try to find this taxon in the authorities table
    
    my %options;
    if ($q->param('taxon_name')) {
        $options{'taxon_name'} = $q->param('taxon_name');
    } else {
        if ($q->param("authorizer_reversed")) {
            my $sql = "SELECT person_no FROM person WHERE name LIKE ".$dbh->quote(PBDB::Person::reverseName($q->param('authorizer_reversed')));
            my $authorizer_no = ${$dbt->getData($sql)}[0]->{'person_no'};
            if (!$authorizer_no) {
                $errors->add($q->param('authorizer_reversed')." is not a valid authorizer. Format like 'Sepkoski, J.'");
            } else {
                $options{'authorizer_no'} = $authorizer_no;
            }
        }
        if ($q->param('created_year')) {
            my ($yyyy,$mm,$dd) = ($q->param('created_year'),$q->param('created_month'),$q->param('created_day'));
            my $date = sprintf("%d-%02d-%02d 00:00:00",$yyyy,$mm,$dd);
            $options{'created'}=$date;
            $options{'created_before_after'}=$q->param('created_before_after');
        }
        $options{'author'} = $q->param('author');
        $options{'pubyr'} = $q->param('pubyr');
        $options{'reference_no'} = $q->numeric_param('reference_no');
    }
    if (keys %options == 0) {
        $errors->add("You must fill in at least one field");
    }

    if ($errors->count()) {
	$output = $hbo->stdIncludes($PAGE_TOP);
	$output .= $errors->errorMessage();
	$output .= $hbo->stdIncludes($PAGE_BOTTOM);
	return $output;
    }
    
    # Denormalize with the references table automatically
    $options{'get_reference'} = 1;
    # Also match against subgenera if the user didn't explicity state the genus
    $options{'match_subgenera'} = 1;

    # Schroeter originally didn't group variants with this option when users
    #  were looking for authority entries, but that's actually needless and
    #  confusing; should have changed it years ago... JA 7.5.13
    $options{'remove_rank_change'} = 1;
    
    my $goal = $q->param('goal');
    my $taxon_name = $q->param('taxon_name');
    my $next_action = 
          ($goal eq 'authority')  ? 'displayAuthorityForm' 
        : ($goal eq 'opinion')    ? 'displayOpinionChoiceForm'
        : ($goal eq 'cladogram')  ? 'displayCladogramChoiceForm'
#        : ($goal eq 'image')      ? 'displayLoadImageForm'
        : ($goal eq 'ecotaph')    ? 'startPopulateEcologyForm'
        : ($goal eq 'ecovert')    ? 'startPopulateEcologyForm'
        : croak("Unknown goal given in submit taxon search");
    
    if ( $goal eq 'authority' || $goal eq 'opinion' )	{
        $options{'ignore_common_name'} = "YES";
    }
    if ( ( $goal eq 'authority' || $goal eq 'opinion' ) && $q->param('taxon_name') =~ / \(.*\)/ )	{
        $options{'match_subgenera'} = "";
    }
    
    my @results = PBDB::TaxonInfo::getTaxa($dbt,\%options,['*']);
    # If there were no matches, present the new taxon entry form immediately
    # We're adding a new taxon
    if (scalar(@results) == 0) {
	$output = $hbo->stdIncludes($PAGE_TOP);
        if ($q->param('goal') eq 'authority') {
            # Try to see if theres any near matches already existing in the DB
            if ($q->param('taxon_name')) {
                my ($g,$sg,$sp) = PBDB::Taxon::splitTaxon($q->param('taxon_name'));
                my ($oldg,$oldsg,$oldsp);
                my @typoResults = ();
                unless ($q->param("skip_typo_check")) {
                # give a free pass if the name is "plausible" because its
                #  parts all exist in the authorities table JA 21.7.08
                # disaster could ensue if the parts are actually typos,
                #  but let's cross our fingers
                # perhaps getTaxa could be adapted for this purpose, but
                #  it's a pretty simple piece of code
		    my $quoted1 = $dbh->quote($g);
		    my $quoted2 = $dbh->quote("$g %");
		    my $quoted3 = $dbh->quote("% ($sg) %");
		    my $quoted4 = $dbh->quote("% sp");
		    
                    my $sql = "SELECT taxon_name tn FROM authorities WHERE taxon_name=$quoted1 OR taxon_name LIKE $quoted2 OR taxon_name LIKE $quoted3 OR taxon_name LIKE $quoted4";
                    my @partials = @{$dbt->getData($sql)};
                    for my $p ( @partials )	{
                        if ( $p->{tn} eq $g )	{
                            $oldg++;
                        }
                        if ( $p->{tn} =~ /^$g / )	{
                            $oldg++;
                        }
                        if ( $p->{tn} =~ / \($sg\) / )	{
                            $oldsg++;
                        }
                        if ( $p->{tn} =~ / $sp$/ )	{
                            $oldsp++;
                        }
                    }

                    if ( $oldg == 0 || ( $sg && $oldsg == 0 ) || $oldsp == 0 )	{
                        $sql = "SELECT count(*) c FROM occurrences WHERE genus_name LIKE ".$dbh->quote($g)." AND taxon_no>0";
                        if ($sg) {
                            $sql .= " AND subgenus_name LIKE ".$dbh->quote($sg);
                        }
                        if ($sp) {
                            $sql .= " AND species_name LIKE ".$dbh->quote($sp);
                        }
                        my $exists_in_occ = ${$dbt->getData($sql)}[0]->{c};
                        unless ($exists_in_occ) {
                            my @results = keys %{PBDB::TypoChecker::taxonTypoCheck($dbt,$q->param('taxon_name'),"",1)};
                            my ($g,$sg,$sp) = PBDB::Taxon::splitTaxon($q->param('taxon_name'));
                            foreach my $typo (@results) {
                                my ($t_g,$t_sg,$t_sp) = PBDB::Taxon::splitTaxon($typo);
                            # if the genus exists, we only want typos including
                            # it JA 16.3.11
                                if ( $oldg && $g ne $t_g )	{
                                    next;
                                }
                                if ($sp && !$t_sp) {
                                    $typo .= " $sp";
                                }
                                push @typoResults, $typo;
                            }
                        }
                    }
                }

                if (@typoResults) {
                    $output .= "<div align=\"center\">\n";
		    $output .= "<p class=\"pageTitle\" style=\"margin-bottom: 0.5em;\">'<i>" . $q->param('taxon_name') . "</i>' was not found</p>\n<br>\n";
                    $output .= "<div class=\"displayPanel medium\" style=\"width: 36em; padding: 1em;\">\n";
                    $output .= "<p><div align=\"left\"><ul>";
                    my $none = "None of the above";
                    if ( $#typoResults == 0 )	{
                        $none = "Not the one above";
                    }
                    foreach my $name (@typoResults) {
                        my @full_rows = PBDB::TaxonInfo::getTaxa($dbt,{'taxon_name'=>$name},['*']);
                        if (@full_rows) {
                            foreach my $full_row (@full_rows) {
                                my ($name,$authority) = PBDB::Taxon::formatTaxon($dbt,$full_row,'return_array'=>1);
                                $output .= "<li>" . makeAnchor("displayAuthorityForm", "taxon_no=$full_row->{taxon_no}", "$name") . " $authority</li>";
                            }
                        } else {
                            $output .= "<li>" . makeAnchor("displayAuthorityForm", "taxon_name=$name", "$name") . "</li>";
                        }
                    }
                    # route them to a genus form instead if the genus doesn't
                    #   exist JA 24.10.11
                    if ( $oldg == 0 && $sp )	{
                        $output .= "<li>" . makeAnchor("submitTaxonSearch", "goal=authority&taxon_name=$g&amp;skip_typo_check=1", "$none") . " - create a new record for this genus";
                    } else	{
                        my $localtaxon_name=uri_escape_utf8($q->param('taxon_name') // '');
                        $output .= "<li>" . makeAnchor("submitTaxonSearch", "goal=authority&taxon_name=$localtaxon_name&amp;skip_typo_check=1", "$none") . " - create a new taxon record";
                    }
                    $output .= "</ul>";
                    my $localtaxon_name=uri_escape_utf8($q->param('taxon_name') // '');
                    $output .= "<div align=left class=small style=\"width: 500\">";
                    $output .= "<p>The taxon '" . $q->param('taxon_name') . "' doesn't exist in the database.  However, some approximate matches were found and are listed above.  If none of the names above match, please enter a new taxon record.";
                    $output .= "</div></p>";
                    $output .= "</div>";
                    $output .= "</div>";
                }
	    	else {
                    if (!$s->get('reference_no')) {
                        $s->enqueue_action('submitTaxonSearch', $q);
			$q->param('type' => 'select');
                        return displaySearchRefs($q, $s, $dbt, $hbo,"<center>Please choose a reference before adding a new taxon</center>",1);
                    }
                    $q->param('taxon_no'=> -1);
                    return PBDB::Taxon::displayAuthorityForm($dbt, $hbo, $s, $q); # $$$$ print
                }
            } else {
                $output .= "<div align=\"center\"><p class=\"pageTitle\">No taxonomic names found</p></div>";
            }
        } else {
            # Try to see if theres any near matches already existing in the DB
            my @typoResults = ();
            if ($q->param('taxon_name')) {
                @typoResults = PBDB::TypoChecker::typoCheck($dbt,'authorities','taxon_name','taxon_no,taxon_name,taxon_rank','',$q->param('taxon_name'),1);
            }

            if (@typoResults) {
                $output .= "<div align=\"center\">";
    		    $output .= "<p class=\"pageTitle\" style=\"margin-bottom: 0.5em;\">'<i>" . $q->param('taxon_name') . "</i>' was not found</p>\n<br>\n";
                $output .= "<div class=\"displayPanel medium\" style=\"width: 36em; padding: 1em;\">\n";
                $output .= "<div align=\"left\"><ul>";
                foreach my $row (@typoResults) {
                    my $full_row = PBDB::TaxonInfo::getTaxa($dbt,{'taxon_no'=>$row->{'taxon_no'}},['*']);
                    my ($name,$authority) = PBDB::Taxon::formatTaxon($dbt,$full_row,'return_array'=>1);
		            my $localtaxon_name = uri_escape_utf8($full_row->{taxon_name} // '');
                    $output .= "<li>" . makeAnchor("$next_action", "goal=$goal&amp;taxon_name=$localtaxon_name&amp;taxon_no=$row->{taxon_no}", "$name") . "$authority</li>";
                }
                $output .= "</ul>";

                $output .= qq|<div align=left class="small">\n<p>|;
                if ( $#typoResults > 0 )	{
                    my $localtaxon_name=uri_escape_utf8($q->param('taxon_name') // '');
                    $output .= "The taxon '" . $q->param('taxon_name') . "' doesn't exist in the database.  However, some approximate matches were found and are listed above.  If none of them are what you're looking for, please " . makeAnchor("displayAuthorityForm", "taxon_no=-1&taxon_name=$localtaxon_name", "enter a new authority record") . " first.";
                } else	{
                    my $localtaxon_name=uri_escape_utf8($q->param('taxon_name') // '');
                    $output .= "The taxon '" . $q->param('taxon_name') . "' doesn't exist in the database.  However, an approximate match was found and is listed above.  If it is not what you are looking for, please " . makeAnchor("displayAuthorityForm", "taxon_no=-1&taxon_name=$localtaxon_name", "enter a new authority record") . " first.";
                }
                $output .= "</div></p>";
                $output .= "</div>";
                $output .= "</div>";
            } else {
                if ($q->param('taxon_name')) {
                    my $localtaxon_name=uri_escape_utf8($q->param('taxon_name') // '');
                    push my @errormessages , "The taxon '" . $q->param('taxon_name') . "' doesn't exist in the database.<br>Please " . makeAnchor("submitTaxonSearch", "goal=authority&taxon_name=$localtaxon_name", "<b>enter</b>") . " an authority record for this taxon first.";
                    $output .= "<div align=\"center\" class=\"large\">".PBDB::Debug::printWarnings(\@errormessages)."</div>";
                } else {
                    $output .= "<div align=\"center\" class=\"large\">No taxonomic names were found that match the search criteria.</div>";
                }
            }
        }

	$output .= $hbo->stdIncludes($PAGE_BOTTOM);
	return $output;
    # One match - good enough for most of these forms
    } elsif (scalar(@results) == 1 && $q->param('goal') eq 'authority') {
        $q->param("taxon_no"=>$results[0]->{'taxon_no'});
        $q->param('called_by'=> 'processTaxonSearch');
        return PBDB::Taxon::displayAuthorityForm($dbt, $hbo, $s, $q);	# $$$ print
    } elsif (scalar(@results) == 1 && $q->param('goal') eq 'cladogram') {
        $q->param("taxon_no"=>$results[0]->{'taxon_no'});
        return PBDB::Cladogram::displayCladogramChoiceForm($dbt,$q,$s,$hbo);
    } elsif (scalar(@results) == 1 && $q->param('goal') eq 'opinion') {
        $q->param("taxon_no"=>$results[0]->{'taxon_no'});
        return PBDB::Opinion::displayOpinionChoiceForm($q, $s, $dbt, $hbo);
    # } elsif (scalar(@results) == 1 && $q->param('goal') eq 'image') {
    #     $q->param('taxon_no'=>$results[0]->{'taxon_no'});
    #     Images::displayLoadImageForm($dbt,$q,$s); 
    } elsif (scalar(@results) == 1 && $q->param('goal') eq 'ecotaph') {
        $q->param('taxon_no'=>$results[0]->{'taxon_no'});
        return PBDB::EcologyEntry::populateEcologyForm($dbt, $hbo, $q, $s, $WRITE_URL);
    } elsif (scalar(@results) == 1 && $q->param('goal') eq 'ecovert') {
        $q->param('taxon_no'=>$results[0]->{'taxon_no'});
        return PBDB::EcologyEntry::populateEcologyForm($dbt, $hbo, $q, $s, $WRITE_URL);
	# We have more than one matches, or we have 1 match or more and we're adding an authority.
    # Present a list so the user can either pick the taxon,
    # or create a new taxon with the same name as an exisiting taxon
    } else	{
	$output = $hbo->stdIncludes($PAGE_TOP);
	$output .= "<div align=\"center\">\n";
        if ($q->param("taxon_name")) { 
	    $output .= "<p class=\"pageTitle\" style=\"margin-top: 1em;\">Which '<i>" . $q->param('taxon_name') . "</i>' do you mean?</p>\n<br>\n";
        } else {
	    if ( $s->isDBMember() )	{
		$output .= "<p class=\"pageTitle\">Select a taxon to edit</p>\n";
	    } else	{
		$output .= "<p class=\"pageTitle\">Taxonomic names from ".PBDB::Reference::formatShortRef($dbt,$q->numeric_param("reference_no"))."</p>\n";
	    }
        }
	
        # now create a table of choices
		$output .= "<div class=\"displayPanel medium\" style=\"width: 40em; padding: 1em; padding-right: 2em; margin-top: -1em;\">";
        $output .= "<div align=\"left\"><ul>\n";
        my $checked = (scalar(@results) == 1) ? "CHECKED" : "";
        foreach my $row (@results) {
            # Check the button if this is the first match, which forces
            #  users who want to create new taxa to check another button
            my ($name,$authority) = PBDB::Taxon::formatTaxon($dbt, $row,'return_array'=>1);
            if ( $s->isDBMember() )	{
                $output .= "<li>" . makeAnchor("$next_action", "goal=$goal&amp;taxon_name=$taxon_name&amp;taxon_no=$row->{taxon_no}", "$name") . " $authority</li>\n";
            } else	{
                $output .= "<li>$name$authority</li>\n";
            }
        }

        # always give them an option to create a new taxon as well
        if ($q->param('goal') eq 'authority' && $q->param('taxon_name')) {
	    my $localtext;
            if ( scalar(@results) == 1 )	{
                $localtext = "No, not the one above ";
            } else	{
                $localtext = "None of the above ";
            }
            $output .= "<li>" . makeAnchor("$next_action", "goal=$goal&amp;taxon_name=$taxon_name&amp;taxon_no=-1", "$localtext") . " - create a new taxon record</li>\n";
        }
        
		$output .= "</ul></div>";

        # we print out difference buttons for two cases:
        #  1: using a taxon name. give them an option to add a new taxon, so button is Submit
        #  2: this is from a reference_no. No option to add a new taxon, so button is Edit
        if ($q->param('goal') eq 'authority') {
            if ($q->param('taxon_name')) {
		$output .= "<p align=\"left\"><div class=\"verysmall\" style=\"margin-left: 2em; text-align: left;\">";
                $output .= "You have a choice because there may be multiple biological species<br>&nbsp;&nbsp;(e.g., a plant and an animal) with identical names.<br>\n";
		$output .= "Create a new taxon only if the old ones were named by different people in different papers.<br></div></p>\n";
            } else {
            }
        } else {
            $output .= "<p align=\"left\"><div class=\"verysmall\" style=\"margin-left: 2em; text-align: left;\">";
            $output .= "You have a choice because there may be multiple biological species<br>&nbsp;&nbsp;(e.g., a plant and an animal) with identical names.<br></div></p>\n";
        }
		$output .= "<p align=\"left\"><div class=\"verysmall\" style=\"margin-left: 2em; text-align: left;\">";
        if (!$q->param('reference_no')) {
		    $output .= "You may want to read the <a href=\"javascript:tipsPopup('/public/tips/taxonomy_FAQ.html')\">FAQ</a>.</div></p>\n";
        }
	
	$output .= "</div>\n</div>\n";
	$output .= $hbo->stdIncludes($PAGE_BOTTOM);
	
	$hbo->pageTitle('PBDB Taxon Results');
	
	return $output;
    }
}

##############
## Authority stuff

# startTaxonomy separated out into startAuthority and startOpinion 
# since they're really separate things but were incorrectly grouped
# together before.  For opinions, always pass the original combination and spelling number
# for authorities, just pass what the user types in
# PS 04/27/2004

# Called when the user clicks on the "Add/edit taxonomic name" or 
sub displayAuthorityTaxonSearchForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    if ($q->param('use_reference') eq 'new') {
        $s->setReferenceNo(0);
    }
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    my %vars = $q->Vars();
    $vars{'authorizer_me'} = $s->get('authorizer_reversed');

    $output .= PBDB::Person::makeAuthEntJavascript($dbt);

    $vars{'page_title'} = "Search for names to add or edit";
    $vars{'action'} = "submitTaxonSearch";
    $vars{'taxonomy_fields'} = "YES";
    $vars{'goal'} = "authority";

    $output .= $hbo->populateHTML('search_taxon_form', \%vars);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Authority Search');
    
    return $output;
}

# rjp, 3/2004
#
# The form to edit an authority
sub displayAuthorityForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    if ( $q->numeric_param('taxon_no') == -1) {
        if (!$s->get('reference_no')) {
            $s->enqueue_action('displayAuthorityForm');
	    $q->param('type' => 'select');
	    return displaySearchRefs($q, $s, $dbt, $hbo,"<center>You must choose a reference before adding a new taxon</center>" );
        }
    } 
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Taxon::displayAuthorityForm($dbt, $hbo, $s, $q);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitleDefault('PBDB Enter Authority');
    
    return $output;
}


sub submitAuthorityForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    unless ( $s && $s->{role} =~ qr{ ^ (?:authorizer|enterer) $ }xsi )
    {
	return menu($q, $s, $dbt, $hbo, "<span style=\"color: red\">Record not saved. You do not have authorization to edit taxonomy records.</span>");
    }
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Taxon::submitAuthorityForm($dbt,$hbo, $s, $q);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Authority Saved');
    
    return $output;
}

# sub displayClassificationTableForm {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
# 	if (!$s->isDBMember()) {
# 		login( "Please log in first.");
# 		return;
# 	} 
#     if (!$s->get('reference_no')) {
#         $s->enqueue_action('displayClassificationTableForm');
# 		displaySearchRefs($q, $s, $dbt, $hbo,"You must choose a reference before adding new taxa" );
# 		return;
# 	}
#     $output .= $hbo->stdIncludes($PAGE_TOP);
# 	PBDB::FossilRecord::displayClassificationTableForm($dbt, $hbo, $s, $q);	
#     $output .= $hbo->stdIncludes($PAGE_BOTTOM);
# }

# sub displayClassificationUploadForm {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
# 	if (!$s->isDBMember()) {
# 		login( "Please log in first.");
# 		return;
# 	} 
#     if (!$s->get('reference_no')) {
#         $s->enqueue_action('displayClassificationUploadForm');
# 		displaySearchRefs($q, $s, $dbt, $hbo,"You must choose a reference before adding new taxa" );
# 		return;
# 	}
#     $output .= $hbo->stdIncludes($PAGE_TOP);
# 	PBDB::FossilRecord::displayClassificationUploadForm($dbt, $hbo, $s, $q);	
#     $output .= $hbo->stdIncludes($PAGE_BOTTOM);
# }


# sub submitClassificationTableForm {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
# 	if (!$s->isDBMember()) {
# 		login( "Please log in first.");
# 		return;
# 	} 
#     $output .= $hbo->stdIncludes($PAGE_TOP);
# 	PBDB::FossilRecord::submitClassificationTableForm($dbt,$hbo, $s, $q);
#     $output .= $hbo->stdIncludes($PAGE_BOTTOM);
# }

# sub submitClassificationUploadForm {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
# 	if (!$s->isDBMember()) {
# 		login( "Please log in first.");
# 		return;
# 	} 
#     $output .= $hbo->stdIncludes($PAGE_TOP);
# 	PBDB::FossilRecord::submitClassificationUploadForm($dbt,$hbo, $s, $q);
#     $output .= $hbo->stdIncludes($PAGE_BOTTOM);
# }

## END Authority stuff
##############

##############
## Opinion stuff

# "Add/edit taxonomic opinion" link on the menu page. 
# Step 1 in our opinion editing process
sub displayOpinionSearchForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    if ($q->param('use_reference') eq 'new') {
        $s->setReferenceNo(0);
    }

    my $output = $hbo->stdIncludes($PAGE_TOP);
    my %vars = $q->Vars();
    $vars{'authorizer_me'} = $s->get('authorizer_reversed');
    $output .= PBDB::Person::makeAuthEntJavascript($dbt);

    $vars{'page_title'} = "Search for opinions to add or edit";
    $vars{'action'} = "submitOpinionSearch";
    $vars{'taxonomy_fields'} = "YES";

    $output .= $hbo->populateHTML('search_taxon_form', \%vars);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Opinion Search');
    
    return $output;
}

# PS 01/24/2004
# Changed from displayOpinionList to just be a stub for function in Opinion module
# Step 2 in our opinion editing process. now that we know the taxon, select an opinion
sub displayOpinionChoiceForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    if ($q->param('use_reference') eq 'new') {
        $s->setReferenceNo(0);
    }
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Opinion::displayOpinionChoiceForm($q, $s, $dbt, $hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Opinion Choice');
    
    return $output;
}

sub reviewOpinionsForm	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    if (!$s->isDBMember()) {
	redirect '/login?reason=login', 303;
	# login( "Please log in first.");
	# return;
    }
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Opinion::reviewOpinionsForm($dbt,$hbo,$s,$q);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Review Opinions');
    
    return $output;
}

sub reviewOpinions	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    if (!$s->isDBMember()) {
	redirect '/login?reason=login', 303;
	# login( "Please log in first.");
	# return;
    }

    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Opinion::reviewOpinions($dbt,$hbo,$s,$q);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Review Opinions');
    
    return $output;
}

# rjp, 3/2004
#
# Displays a form for users to add/enter opinions about a taxon.
# It grabs the taxon_no and opinion_no from the CGI object ($q).
sub displayOpinionForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    if ($q->numeric_param('opinion_no') != -1 && $q->param("opinion_no") !~ /^\d+$/) {
	my $output = $hbo->stdIncludes( $PAGE_TOP );
	$output .= menu($q, $s, $dbt, $hbo, "<center>You must specify an opinion number</center>");
	$output .= $hbo->stdIncludes( $PAGE_BOTTOM );
	
	return $output;
    }
    
    if ($q->numeric_param('opinion_no') == -1) {
        if (!$s->get('reference_no') || $q->param('use_reference') eq 'new') {
            # Set this to prevent endless loop
            $q->param('use_reference'=>'');
	    $q->param('type' => 'select');
            $s->enqueue_action('displayOpinionForm', $q); 
            return displaySearchRefs($q, $s, $dbt, $hbo,"<center>You must choose a reference before adding a new opinion</center>");
        }
    }
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Opinion::displayOpinionForm($dbt, $hbo, $s, $q);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitleDefault('PBDB Enter Opinion');
    
    return $output;
}

sub submitOpinionForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    unless ( $s && $s->{role} =~ qr{ ^ (?:authorizer|enterer) $ }xsi )
    {
	return menu($q, $s, $dbt, $hbo, "<span style=\"color: red\">Record not saved. You do not have authorization to edit opinion records.</span>");
    }
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Opinion::submitOpinionForm($dbt,$hbo, $s, $q);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Opinion Saved');
    
    return $output;
}

sub submitTypeTaxonSelect {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Taxon::submitTypeTaxonSelect($dbt, $s, $q);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Taxon Saved');
    
    return $output;
}

sub badNameForm	{
    
    my ($q, $s, $dbt, $hbo, $error) = @_;
    
    my %vars;
    # $vars{'error'} = $_[0];
    if ( $error )	{
	$vars{'error'} = '<p class="small" style="margin-left: 1em; margin-bottom: 1.5em; margin-top: 1em; text-indent: -1em;">' . $error . ". Please try again.</p>\n\n";
    }
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= $hbo->populateHTML('bad_name_form', \%vars);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

sub badNames	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Opinion::badNames($q, $s, $dbt, $hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

## END Opinion stuff
##############

##############
## Editing list stuff
sub displayPermissionListForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Permissions::displayPermissionListForm($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Permission List');
    
    return $output;
}

sub submitPermissionList {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Permissions::submitPermissionList($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Permission List Saved');
    
    return $output;
} 

sub submitHeir {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Permissions::submitHeir($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Heir Saved');
    
    return $output;
} 

##############
## Occurrence misspelling stuff

sub searchOccurrenceMisspellingForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    if (!$s->isDBMember()) {
        # have to be logged in
        # $s->enqueue_action("searchOccurrenceMisspellingForm" );
	redirect '/login?reason=login', 303;
        # login( "Please log in first." );
        # return;
    }
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::TypoChecker::searchOccurrenceMisspellingForm ($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Misspelling Search');

    return $output;
}

sub occurrenceMisspellingForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::TypoChecker::occurrenceMisspellingForm ($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Occurrence Misspelling');
    
    return $output;
}

sub submitOccurrenceMisspelling {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::TypoChecker::submitOccurrenceMisspelling($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Occurrence Saved');
    
    return $output;
}

## END occurrence misspelling stuff
##############

##############
## Reclassify stuff

sub startStartReclassifyOccurrences	{
    
    my ($q, $s, $dbt, $hbo) = @_;

    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Reclassify::startReclassifyOccurrences($q, $s, $dbt, $hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

sub startDisplayOccurrenceReclassify	{
    
    my ($q, $s, $dbt, $hbo, $colls) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Reclassify::displayOccurrenceReclassify($q, $s, $dbt, $hbo, $colls);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

sub startProcessReclassifyForm	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Reclassify::processReclassifyForm($q, $s, $dbt, $hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

## END Reclassify stuff
##############

##############
## Taxon Info Stuff


# sub downloadOSA {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
#     print $hbo->stdIncludes( $PAGE_TOP );
#     PBDB::OSA();
#     print $hbo->stdIncludes($PAGE_BOTTOM);
# }

sub beginTaxonInfo{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes( $PAGE_TOP );
    $output .= PBDB::TaxonInfo::searchForm($hbo, $q);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Taxon Search');
    
    return $output;
}

sub checkTaxonInfo {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    logRequest($s,$q);
    my $output =  $hbo->stdIncludes($PAGE_TOP);
    
    if ( $q->param('match') eq "all" )	{
        $q->param('taxa' => @{PBDB::TaxonInfo::getMatchingSubtaxa($dbt,$q,$s,$hbo)} );
        if ( ! $q->param('taxa') )	{
            $output .= PBDB::TaxonInfo::searchForm($hbo,$q,1);
        } else	{
            $output .= PBDB::TaxonInfo::checkTaxonInfo($q, $s, $dbt, $hbo);
        }
    } elsif ( $q->param('match') eq "random" )	{
        # infinite loops are bad
        $output .= PBDB::TaxonInfo::getMatchingSubtaxa($dbt,$q,$s,$hbo);
        $q->param('match' => '');
	$output .= PBDB::TaxonInfo::checkTaxonInfo($q, $s, $dbt, $hbo);
    } else {
	$output .= PBDB::TaxonInfo::checkTaxonInfo($q, $s, $dbt, $hbo);
    }
    
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Taxon');
    
    return $output;
}

sub displayTaxonInfoResults {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes( $PAGE_TOP );
    $output .= PBDB::TaxonInfo::displayTaxonInfoResults($dbt,$s,$q,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Taxon Detail');
    
    return $output;
}

# JA 3.11.09
sub basicTaxonInfo	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $result = PBDB::TaxonInfo::basicTaxonInfo($q,$s,$dbt,$hbo);
    
    if ( $result =~ /^\d+$/ )
    {
	redirect "/classic/basicTaxonInfo?taxon_no=$result", 303;
	return $result;
    }
    
    else
    {
	my $output = $hbo->stdIncludes( $PAGE_TOP );
	$output .= $result;
	$output .= $hbo->stdIncludes($PAGE_BOTTOM);
	
	$hbo->pageTitle('PBDB Taxon');
	
	return $output;
    }
}

## END Taxon Info Stuff
##############


sub displayTimescale {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output =  $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Timescales::displayTimescale($dbt, $hbo, $s, $q);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitleDefault('PBDB Timescale');
    
    return $output;
}



##############
## Ecology stuff
sub startStartEcologyTaphonomySearch{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $goal='ecotaph';
    my $page_title ='<center>Search for the taxon you want to describe</center>';

    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= $hbo->populateHTML('search_taxon_form',[$page_title,'submitTaxonSearch',$goal],['page_title','action','goal']);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Ecology/Taphonomy Search');
    
    return $output;
}

sub startStartEcologyVertebrateSearch{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $goal='ecovert';
    my $page_title ='<center>Search for the taxon you want to describe</center>';
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= $hbo->populateHTML('search_taxon_form',[$page_title,'submitTaxonSearch',$goal],['page_title','action','goal']);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Ecology/Taphonomy Search');

    return $output;
}

sub startPopulateEcologyForm	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::EcologyEntry::populateEcologyForm($dbt, $hbo, $q, $s, $WRITE_URL);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Enter Ecology/Taphonomy');
    
    return $output;
}
sub startProcessEcologyForm	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::EcologyEntry::processEcologyForm($dbt, $q, $s, $WRITE_URL);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Ecology/Taphonomy Saved');
    
    return $output;
}

## END Ecology stuff
##############

##############
## Specimen measurement stuff
sub displaySpecimenSearchForm	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    
    if (!$s->get('reference_no'))	{
	$s->enqueue_action('displaySpecimenSearchForm');
	$q->param('type' => 'select');
	return displaySearchRefs($q, $s, $dbt, $hbo,"<center>You must choose a reference before adding measurements</center>" );
    }

    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= $hbo->populateHTML('search_specimen_form',[],[]);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Specimen Search');
    
    return $output;
}

sub submitSpecimenSearch{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::MeasurementEntry::submitSpecimenSearch($dbt,$hbo,$q,$s,$WRITE_URL);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Specimen Results');
    
    return $output;
}

sub displaySpecimenList {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::MeasurementEntry::displaySpecimenList($dbt,$hbo,$q,$s,$WRITE_URL);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Specimen Results');
    
    return $output;
}

sub populateMeasurementForm{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output .= $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::MeasurementEntry::populateMeasurementForm($dbt,$hbo,$q,$s,$WRITE_URL);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitleDefault('PBDB Enter Measurements');
    
    return $output;
}

sub processMeasurementForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::MeasurementEntry::processMeasurementForm($dbt,$hbo,$q,$s,$WRITE_URL);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Measurements Saved');
    
    return $output;
}

sub deleteSpecimen {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $err_msg = PBDB::MeasurementEntry::deleteSpecimen($dbt, $hbo, $q, $s);
    if ( $err_msg )
    {
	$s->{error_msg} = $err_msg;
    }
    
    my $output .= $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::MeasurementEntry::displaySpecimenList($dbt,$hbo,$q,$s,$WRITE_URL);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Delete Specimen');
    
    return $output;
}

## END Specimen measurement stuff
##############



##############
## Strata stuff
sub displayStrata {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    logRequest($s,$q);

    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Strata::displayStrata($q,$s,$dbt,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Strata Results');
    
    return $output;
}

sub displaySearchStrataForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Strata::displaySearchStrataForm($q,$s,$dbt,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Strata Search');
    
    return $output;
}  

sub displaySearchStrataResults{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Strata::displaySearchStrataResults($q,$s,$dbt,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

## END Strata stuff
##############

##############
## Nexus file stuff

sub uploadNexusFile {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::NexusfileWeb::displayUploadPage($dbt, $hbo, $q, $s);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Upload Nexus File');
    
    return $output;
}


sub processNexusUpload {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    ouch(400, "This function is temporarily disabled");
    # PBDB::NexusfileWeb::processUpload($dbt, $hbo, $q, $s);
}


sub editNexusFile {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::NexusfileWeb::editFile($dbt, $hbo, $q, $s);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Edit Nexus File');
    
    return $output;
}


sub updateNexusFile {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::NexusfileWeb::processEdit($dbt, $hbo, $q, $s);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Nexus File Saved');
    
    return $output;
}


sub viewNexusFile {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::NexusfileWeb::viewFile($dbt, $hbo, $q, $s);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Nexus File');
    
    return $output;
}


sub nexusFileSearch {
    
    my ($q, $s, $dbt, $hbo) = @_;
     
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::NexusfileWeb::displaySearchPage($dbt, $hbo, $q, $s);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Nexus File Search');
    
    return $output;
}


sub processNexusSearch {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::NexusfileWeb::processSearch($dbt, $hbo, $q, $s);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Nexus File Results');
    
    return $output;
}


sub getNexusFile {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    return PBDB::NexusfileWeb::sendFile($dbt, $q, $s);
}


## END Nexus file stuff
##############

##############
## PrintHierarchy stuff
sub classificationForm	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    return if PBDB::PBDBUtil::checkForBot();
    logRequest($s,$q);
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::PrintHierarchy::classificationForm($hbo, $s);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Taxonomy Search');
    
    return $output;
}

sub classify	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    return if PBDB::PBDBUtil::checkForBot();

    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::PrintHierarchy::classify($dbt, $hbo, $s, $q);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Taxonomy Results');
    
    return $output;
}

## END PrintHierarchy stuff
##############

##############
## SanityCheck stuff
sub displaySanityForm	{
    
    my ($q, $s, $dbt, $hbo, $error_message) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= $hbo->populateHTML('sanity_check_form',$error_message);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Sanity Check');
    
    return $output;
}

sub startProcessSanityCheck	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    return if PBDB::PBDBUtil::checkForBot();
    logRequest($s,$q);
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= SanityCheck::processSanityCheck($q, $dbt, $hbo, $s);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Sanity Check Results');
    
    return $output;
}

## END SanityCheck stuff
##############

##############
## PAST stuff
# sub PASTQueryForm {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
#     require PAST;
#     print $hbo->stdIncludes($PAGE_TOP);
#     PAST::queryForm($dbt,$q,$hbo,$s);
#     print $hbo->stdIncludes($PAGE_BOTTOM);
# }
# sub PASTQuerySubmit {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
#     require PAST;
#     print $hbo->stdIncludes($PAGE_TOP);
#     PAST::querySubmit($dbt,$q,$hbo,$s);
#     print $hbo->stdIncludes($PAGE_BOTTOM);
# }
## End PAST stuff
##############


sub displayOccurrenceAddEdit {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $dbh = $dbt->dbh;
    my $output = '';
    
	# 1. Need to ensure they have a ref
	# 2. Need to get a collection
	
	# Have to be logged in
	if (!$s->isDBMember()) {
	    return login( "Please log in first.",'displayOccurrenceAddEdit');
	}
    
    if (! $s->get('reference_no')) {
	$s->enqueue_action('displayOccurrenceAddEdit', $q);
	$q->param('type' => 'select');
	return displaySearchRefs($q, $s, $dbt, $hbo,"<center>Please select a reference first</center>"); 
    } 
    
    my $collection_no = $q->param($COLLECTION_NO);
    # No collection no is passed in, search for one
    if ( ! $collection_no ) { 
	$q->param('type'=>'edit_occurrence');
	return displaySearchColls($q, $s, $dbt, $hbo);
    }
    
    # Grab the collection name for display purposes JA 1.10.02
	my $sql;
	$sql = "SELECT collection_name FROM collections WHERE collection_no=$collection_no";
	my $sth = $dbh->prepare( $sql ) || die ( "$sql<hr>$!" );
	$sth->execute();
	my ($collection_name) = $sth->fetchrow_array();
	$sth->finish();

	$output .= $hbo->stdIncludes( $PAGE_TOP );

	# get the occurrences right away because we need to make sure there
	#  aren't too many to be displayed
	$sql = "SELECT * FROM occurrences WHERE collection_no=$collection_no ORDER BY occurrence_no ASC";
	$sth = $dbh->prepare( $sql ) || die ( "$sql<hr>$!" );
	$sth->execute();

	my $p = PBDB::Permissions->new($s,$dbt);
	my @all_data = $p->getReadWriteRowsForEdit($sth);

	# first check to see if there are too many rows to display, in which
	#  case display links going to different batches of occurrences and
	#  then bomb out JA 26.7.04
	# don't do this if the user already has gone through one of those
	#  links, so rows_to_display has a useable value
	if ( $#all_data > 49 && $q->param("rows_to_display") !~ / to / )	{
		$output .= "<center><p class=\"pageTitle\">Please select the rows you wish to edit</p></center>\n\n";
		$output .= "<center>\n";
		$output .= "<table><tr><td>\n";
		$output .= "<ul>\n";
        my ($startofblock,$endofblock);
		for my $rowset ( 1..100 )	{
			$endofblock = $rowset * 50;
			$startofblock = $endofblock - 49;
			if ( $#all_data >= $endofblock )	{
				$output .= "<li>" . makeAnchor("displayOccurrenceAddEdit", "collection_no=$collection_no&rows_to_display=$startofblock+to+$endofblock", "Rows <b>$startofblock</b> to <b>$endofblock</b>");
			}
			if ( $#all_data < $endofblock + 50 )	{
				$startofblock = $endofblock + 1;
				$endofblock = $#all_data + 1;
				$output .= "<li>" . makeAnchor("displayOccurrenceAddEdit", "collection_no=$collection_no&rows_to_display=$startofblock+to+$endofblock", "Rows <b>$startofblock</b> to <b>$endofblock</b>");
				last;
			}
		}
		$output .= "</ul>\n\n";
		$output .= "</td></tr></table>\n";
		$output .= "</center>\n";
		$output .= $hbo->stdIncludes( $PAGE_BOTTOM );
		return $output;
	}

	# which rows should be displayed?
	my $firstrow = 0;
	my $lastrow = $#all_data;
	if ( $q->param("rows_to_display") =~ / to / )	{
		($firstrow,$lastrow) = split / to /,$q->param("rows_to_display");
		$firstrow--;
		$lastrow--;
	}

	my %pref = $s->getPreferences();
	$output .= $hbo->populateHTML('js_occurrence_checkform');

	$output .= qq|<form method=post action="$WRITE_URL" onSubmit='return checkForm();'>\n|;
	$output .= qq|<input name="action" value="processEditOccurrences" type=hidden>\n|;
	$output .= qq|<input name="list_collection_no" value="$collection_no" type=hidden>\n|;
	$output .= qq|<input name="check_status" type="hidden">\n|;
	
	my @optional = ('subgenera','genus_and_species_only','abundances','plant_organs');
	my $header_vars = {
		'collection_no'=>$collection_no,
		'collection_name'=>$collection_name
	};
	$header_vars->{$_} = $pref{$_} for (@optional);
	$header_vars->{collection_number} = '[' . makeAnchor("displayCollectionForm", "collection_no=$collection_no", $collection_no) . ']';
	$output .= $hbo->populateHTML('occurrence_header_row', $header_vars);

    # main loop
    # each record is represented as a hash
    my $gray_counter = 0;
    foreach my $all_data_index ($firstrow..$lastrow){
    	my $occ_row = $all_data[$all_data_index];
		# This essentially empty reid_no is necessary as 'padding' so that
		# any actual reid number (see while loop below) will line up with 
		# its row in the form, and ALL rows (reids or not) will be processed
		# properly by processEditOccurrences(), below.
        $occ_row->{'reid_no'} = '0';
        formatTaxonNameInput($occ_row);
	
        # Copy over optional fields;
        $occ_row->{$_} = $pref{$_} for (@optional);

        # Read Only
        my $occ_read_only = ($occ_row->{'writeable'} == 0) ? "all" : ""; 
        $occ_row->{'darkList'} = ($occ_read_only eq 'all' && $gray_counter%2 == 0) ? "darkList" : "";
        #    $output .= qq|<input type=hidden name="row_token" value="row_token">\n|;
	    $occ_row->{reference_link} = makeAnchor("displayReference", "type=view&reference_no=$occ_row->{reference_no}", "view")
	    if $occ_row->{reference_no};
        $output .= $hbo->populateHTML("occurrence_edit_row", $occ_row, [$occ_read_only]);
        my @reid_rows;
        my $sql = "SELECT * FROM reidentifications WHERE occurrence_no=" .  $occ_row->{'occurrence_no'};
        @reid_rows = @{$dbt->getData($sql)};
        foreach my $re_row (@reid_rows) {
            formatTaxonNameInput($re_row);
            # Copy over optional fields;
            $re_row->{$_} = $pref{$_} for (@optional);

            # Read Only
            my $re_read_only = $occ_read_only;
            $re_row->{'darkList'} = $occ_row->{'darkList'};
	    $re_row->{reference_link} = makeAnchor("displayReference", "type=view&reference_no=$re_row->{reference_no}", "view")
	    if $re_row->{reference_no};
            
            my $reidHTML = $hbo->populateHTML("reid_edit_row", $re_row, [$re_read_only]);
            # Strip away abundance widgets (crucial because reIDs never may
            #  have abundances) JA 30.7.02
#            $reidHTML =~ s/<td><input id="abund_value"(.*?)><\/td>/<td><input type=hidden name="abund_value"><\/td>/;
#            $reidHTML =~ s/<td><select id="abund_unit"(.*?)>(.*?)<\/select><\/td>/<td><input type=hidden name="abund_unit"><\/td>/;
#            $reidHTML =~ s/<td align=right><select name="genus_reso">/<td align=right><nobr><b>reID<\/b><select name="genus_reso">/;
#            $reidHTML =~ s/<td /<td class=tiny /g;
            # The first one needs to be " = (species ..."
#            $reidHTML =~ s/<div id="genus_reso">/<div class=tiny>= /;
#            $reidHTML =~ s//<input class=tiny /g;
#            $reidHTML =~ s/<select /<select class=tiny /g;
            $output .= $reidHTML;
        }
        $gray_counter++;
    }

	# Extra rows for adding
	my $blank;
	$blank = {
		'collection_no'=>$collection_no,
		'reference_no'=>$s->get('reference_no'),
		'occurrence_no'=>-1,
		'taxon_name'=>$pref{'species_name'}
	};
	if ( $blank->{'species_name'} eq " " )	{
		$blank->{'species_name'} = "";
	}
    

	# Copy over optional fields;
	$blank->{$_} = $pref{$_} for (@optional,'species_name');
        
	# Figure out the number of blanks to print
	my $blanks = $pref{'blanks'} || 10;

	for ( my $i = 0; $i<$blanks ; $i++) {
#		$output .= qq|<input type=hidden name="row_token" value="row_token">\n|;
		$output .= $hbo->populateHTML("occurrence_entry_row", $blank);
	}

	$output .= "</table><br>\n";
	$output .= "<p>Delete entries by erasing the taxon name.</p>\n";
	$output .= qq|<center><p><input type=submit value="Save changes">|;
	$output .= " to collection ${collection_no}'s taxonomic list</p></center>\n";
	$output .= "</div>\n\n</form>\n\n";

    $output .= $hbo->stdIncludes( $PAGE_BOTTOM );
    
    $hbo->pageTitleDefault('PBDB Enter Occurrence');
    
    return $output;
} 

# JA 5.7.07
sub formatTaxonNameInput	{
    
    my ($occ_row) = @_;
    
    if ( $occ_row->{'genus_reso'} )	{
        if ( $occ_row->{'genus_reso'} =~ /"/ )	{
            $occ_row->{'taxon_name'} = '"';
        } elsif ( $occ_row->{'genus_reso'} =~ /informal/ )	{
            $occ_row->{'taxon_name'} = '<';
        } else	{
            $occ_row->{'taxon_name'} = $occ_row->{'genus_reso'} . " ";
        }
    }
    $occ_row->{'taxon_name'} .=  $occ_row->{'genus_name'};
    if ( $occ_row->{'genus_reso'} =~ /"/ )	{
        $occ_row->{'taxon_name'} .= '"';
    } elsif ( $occ_row->{'genus_reso'} =~ /informal/ )	{
        $occ_row->{'taxon_name'} .= '>';
    }
    if ( $occ_row->{'subgenus_name'} )	{
        $occ_row->{'taxon_name'} .=  " ";
        if ( $occ_row->{'subgenus_reso'} )	{
            if ( $occ_row->{'subgenus_reso'} =~ /"/ )	{
                $occ_row->{'subgenus_name'} = '"' . $occ_row->{'subgenus_name'} . '"';
            } elsif ( $occ_row->{'subgenus_reso'} =~ /informal/ )	{
                $occ_row->{'subgenus_name'} = '<' . $occ_row->{'subgenus_name'} . '>';
            } else	{
                $occ_row->{'taxon_name'} .= $occ_row->{'subgenus_reso'} . " ";
            }
        }
        $occ_row->{'taxon_name'} .=  "(" . $occ_row->{'subgenus_name'} . ")";
    }
    $occ_row->{'taxon_name'} .=  " ";
    if ( $occ_row->{'species_reso'} )	{
        if ( $occ_row->{'species_reso'} =~ /"/ )	{
            $occ_row->{'species_name'} = '"' . $occ_row->{'species_name'};
        } elsif ( $occ_row->{'species_reso'} =~ /informal/ )	{
            $occ_row->{'species_name'} = '<' . $occ_row->{'species_name'};
        } else	{
            $occ_row->{'taxon_name'} .= $occ_row->{'species_reso'} . " ";
        }
    }
    $occ_row->{'taxon_name'} .=  $occ_row->{'species_name'};
    if ( $occ_row->{'species_reso'} =~ /"/ )	{
        $occ_row->{'taxon_name'} .= '"';
    } elsif ( $occ_row->{'species_reso'} =~ /informal/ )	{
        $occ_row->{'taxon_name'} .= '>';
    }

    return ($occ_row);
}

#
# Sanity checks/error checks?
# Hit enter, capture and do addrow
#
sub displayOccurrenceTable {
    
    my ($q, $s, $dbt, $hbo, $colls_ref) = @_;

    my $output = '';
    
    my @all_collections; @all_collections = @$colls_ref if ref $colls_ref eq 'ARRAY';
    # my @all_collections = @{$_[0]};
	# Have to be logged in
	if (!$s->isDBMember()) {
	    return login( "Please log in first.",'displayOccurrenceTable' );
	}
	# Have to have a reference #
	my $reference_no = $s->get("reference_no");
	if ( ! $reference_no ) {
	    $s->enqueue_action('displayOccurrenceTable');
	    $q->param('type' => 'select');
	    return displaySearchRefs($q, $s, $dbt, $hbo, "<center>Please choose a reference first</center>" );
	}	

    # Get modifier as well
    # my $p = new PBDB::Permissions($s,$dbt);
    # my $can_modify = $p->getModifierList();
    # $can_modify->{$s->get('authorizer_no')} = 1;

    my $lower_limit = int($q->param("offset")) || 0;
    my $limit = int($q->param("limit")) || 20;
    my $upper_limit = ($lower_limit + $limit);
    if ($upper_limit > @all_collections) {
        $upper_limit = @all_collections;
    }

    my @collections = map {int} @all_collections[$lower_limit .. ($upper_limit-1)];
    my @other_colls = ();
    if (0 < $lower_limit) {
        @other_colls = map {int} @all_collections[0 .. $lower_limit-1];
    }

    my %taxon_names = ();
    my %taxon_nos = ();

    my $sql = "SELECT 0 reid_no, o.occurrence_no, o.collection_no, o.reference_no, o.authorizer_no, p1.name authorizer, o.taxon_no, o.genus_reso,o.genus_name,o.subgenus_reso,o.subgenus_name,o.species_reso,o.species_name, o.abund_value, o.abund_unit FROM occurrences o LEFT JOIN person p1 ON p1.person_no=o.authorizer_no WHERE collection_no IN (".join(",",@collections).")";
    my @occs = @{$dbt->getData($sql)};

    if (@occs < @collections && @other_colls) {
        my $sql = "SELECT 0 reid_no, o.occurrence_no, o.collection_no, o.reference_no, o.authorizer_no, p1.name authorizer, o.taxon_no, o.genus_reso,o.genus_name,o.subgenus_reso,o.subgenus_name,o.species_reso,o.species_name, o.abund_value, o.abund_unit FROM occurrences o LEFT JOIN person p1 ON p1.person_no=o.authorizer_no WHERE collection_no IN (".join(",",@other_colls).")";
        push @occs, @{$dbt->getData($sql)};

    }    

    my %count_by_abund_unit;
    my %min_occ_no;
    foreach my $row (@occs) {
        my %hash = %$row;
        # Make sure the resos come last since we don't want that to affect hte sort below
        # DON'T change the ordering of taxon_key, this ordering has to match up with the javascript and split functions
        # throughout this whoel process
        my $taxon_key = join("-_",@hash{"genus_name","subgenus_name","species_name","genus_reso","subgenus_reso","species_reso"});
        $taxon_names{$taxon_key}{$row->{'collection_no'}} = $row;
        if (!$min_occ_no{$taxon_key} || $row->{occurrence_no} < $min_occ_no{$taxon_key}) {
            $min_occ_no{$taxon_key} = $row->{occurrence_no};
        }
        
        $taxon_nos{$taxon_key}{$row->{'taxon_no'}} = 1 if ($row->{'taxon_no'} > 0);
        $count_by_abund_unit{$row->{'abund_unit'}}++ if ($row->{'abund_unit'});
   }

    # This takes advantage of a bug in IE 6 in which absolutely positioned elements get treated
    # as fixed position elements when height:100% and overflow-y:auto are added to the body
    # Note that the browser can't be rendering in "quirks" mode so the doctype must be XHTML
    # (use a different header)
    my $extra_header = <<EOF;
<script src="/JavaScripts/occurrence_table.js" type="text/javascript" language="JavaScript"></script>
<style type="text/css">
body {
    margin:10px; 
    top:0px; 
    left:10px; 
    padding:0 0 0 0; 
    border:0; 
    height:100%; 
    overflow-y:auto; 
}
#occurrencesTableHeader {
    display:block; 
    top:0px; 
    left:10px; 
    position:fixed; 
    border-bottom:2px solid gray; 
    padding:0px; 
    text-align:center; 
    background-color:#FFFFFF;
    z-index: 9;
}
#occurrencesTableHeader th,#occurrencesTableHeader td {
    border-right: 1px solid gray;
    border-bottom: 1px solid gray; 
}
* html #occurrencesTableHeader {position:absolute;}
</style>
<!--[if lte IE 6]>
   <style type="text/css">
   /*<![CDATA[*/ 
html {overflow-x:auto; overflow-y:hidden;}
   /*]]>*/
   </style>
<![endif]-->
EOF
    $output .= $hbo->populateHTML('blank_page_top',{'extra_header'=>$extra_header});
    $output .= qq|<form method="post" action="$WRITE_URL" onSubmit="return handleSubmit();">|;
    $output .= '<input type="hidden" name="action" value="processOccurrenceTable" />';
    # this field is read by the javascript but not used otherwise
    $output .= qq|<input type="hidden" name="reference_no" value="$reference_no" />|;

    foreach my $collection_no (@collections) {
        $output .= qq|<input type="hidden" name="collection_nos" value="$collection_no" />\n|;
    }

    # Fixed position header
    # We're make an assumption here, that there will generally only be one abundance unit for the page
    # and everything gets synced to that one -- we prepopulate the form with that abundance unit, or if
    # where no abundance unit (a new sheet or only presences and not abundances records), then we
    # default to specimens
    my $selected_abund_unit = 'specimens';
    my $max_count = 1;
    while(my ($abund_unit,$count) = each %count_by_abund_unit) {
        if ($count > $max_count && $abund_unit) {
            $max_count = $count;
            $selected_abund_unit = $abund_unit;
        }
    }
    my $abund_select = $hbo->htmlSelect('abund_unit',$hbo->getKeysValues('abund_unit'),$selected_abund_unit,'class="small"');
    my $reference = "$reference_no (".PBDB::Reference::formatShortRef($dbt,$reference_no).")";
    $output .= '<div id="occurrencesTableHeader">';
    $output .= '<table border=0 cellpadding=0 cellspacing=0>'."\n";
    $output .= '<tr>';
    $output .= '<td valign="bottom"><div class="fixedLabel">'.
          qq|<div class="small" align="left">Please see the <a href="#" onClick="tipsPopup('/public/tips/occurrence_table_tips.html');">tip sheet</a></div><br />|.
          '<div align="left" style="height: 160px; overflow: hidden;" class="small">'.
          '<b>New cells:</b><br />'.
          '&nbsp;Reference: '.$reference."<br />".
          '&nbsp;Abund. unit: '.$abund_select."<br />".
          '<b>Current cell: </b><br />'.
          '<div id="cell_info"></div>'.
          '</div>'.
          '<input type="submit" name="submit" value="Submit table" /><br /><br />'.
          '</div></td>';
    foreach my $collection_no (@collections) {
        my $collection_name = encode_entities(generateCollectionLabel($dbt, $collection_no));
        $output .= '<td class="addBorders"><div class="fixedColumn">' . makeAnchor("basicCollectionSearch", "collection_no=$collection_no", "$collection_name") . "</div></td>";
            # qq|<a target="_blank" href="?a=basicCollectionSearch&amp;collection_no=$collection_no"><img border="0" src="/public/collection_labels/$collection_no.png" alt="$collection_name"/></a>|.
    }
    $output .= "</tr>\n";
    $output .= "</table></div>";

 
    $output .= '<div style="height: 236px">&nbsp;</div>';
    $output .= '<table border=0 cellpadding=0 cellspacing=0 id="occurrencesTable">'."\n";
    my @sorted_names;
    if ($q->param('taxa_order') eq 'alphabetical') {
        @sorted_names = sort keys %taxon_names;
    } else {
        @sorted_names = sort {$min_occ_no{$a} <=> $min_occ_no{$b}} keys %taxon_names;
    }
    for(my $i=0;$i<@sorted_names;$i++) {
        my $taxon_key = $sorted_names[$i];
        my @taxon_nos = (); 
        if (exists ($taxon_nos{$taxon_key})) {
            @taxon_nos = keys %{$taxon_nos{$taxon_key}} ;
        }
        my %hash = ();
        @hash{"genus_name","subgenus_name","species_name","genus_reso","subgenus_reso","species_reso"} = split("-_",$taxon_key);
        my $show_name = PBDB::CollectionEntry::formatOccurrenceTaxonName(\%hash);
        $show_name =~ s/<a href/<a target="_blank" href/;
        my $class = ($i % 2 == 0) ? 'class="darkList"' : '';
        $output .= '<tr '.$class.'><td class="fixedLabel"><div class="fixedLabel">'.
            $show_name.
            qq|<input type="hidden" name="row_num" value="$i" />|.
            qq|<input type="hidden" name="taxon_key_$i" value="|.encode_entities($taxon_key).qq|" />|;
        foreach my $taxon_no (@taxon_nos) {
           $output .= qq|<input type="hidden" name="taxon_no_$i" value="$taxon_no" />|; 
        }
        $output .= "</div></td>";
        $class = ($i % 2 == 0) ? 'fixedInputDark' : 'fixedInput';
        for (my $j=0;$j<@collections;$j++) {
            my $collection_no = $collections[$j];
            my $occ = $taxon_names{$taxon_key}{$collections[$j]};
            my ($abund_value,$abund_unit,$key_type,$key_value,$occ_reference_no,$readonly,$authorizer);
            $readonly = 0;
            if ($occ) {
                if ($occ->{'abund_value'}) {
                    $abund_value = $occ->{'abund_value'};
                } else {
                    $abund_value = "x";
                }
                if ($occ->{'reid_no'}) {
                    $key_type = "reid_no";
                    $key_value = "$occ->{reid_no}";
                } else {
                    $key_type = "occurrence_no";
                    $key_value = "$occ->{occurrence_no}";
                }
#                $abund_unit = $occ->{'abund_unit'};
                $occ_reference_no = $occ->{'reference_no'};
                # if (!$can_modify->{$occ->{'authorizer_no'}}) {
                #     $readonly = 1;
                # }
                $authorizer=$occ->{'authorizer'}
            } else {
#                $abund_unit = "DEFAULT";
                $key_type = "occurrence_no";
                $key_value = "-1";
                $occ_reference_no = $reference_no;
            }
          
            my $style="";
            my $editCellJS = "editCell($i,$collection_no); ";
            if ($readonly) {
                $style = 'style="color: red;"';
                $editCellJS = "";
            }
            my $esc_show_name = encode_entities($show_name);
            # The span is necessary to act as a container and prevent wrapping
            # The &nbsp; fixes a Safari bug where the onClick doesn't trigger unless the TD has somethiing in it

            $output .= qq|<td class="fixedColumn" onClick="cellInfo($i,$collection_no,$occ_reference_no,$readonly,'$authorizer');$editCellJS"><div class="fixedColumn"><span class="fixedSpan" id="dummy_${i}_${collection_no}" $style>$abund_value &nbsp;|;
            $output .= qq|<input type="hidden" id="abund_value_${i}_${collection_no}" name="abund_value_${i}_${collection_no}" size="4" value="$abund_value" class="$class" $style /></span>|;
            $output .= qq|<input type="hidden" id="${key_type}_${i}_${collection_no}" name="${key_type}_${i}_${collection_no}" value="$key_value"/>|;
            $output .= qq|</div></td>\n|;
                  
        }
        $output .= "</tr>\n";
    }
    $output .= "</table>";

    my %prefs = $s->getPreferences();
    # Can dynamically add rows using javascript that modified the DOM -- see occurrence_table.js
    $output .= "<table>";
    $output .= '<tr><th></th><th class="small">Genus</th>';
    if ($prefs{'subgenera'} || $prefs{'genus_and_species_only'}) {
        $output .= '<th></th><th class="small">Subgenus</th>';
    }
    $output .= '<th></th><th class="small">Species</th></tr>';
    $output .= "<tr>".
        '<td>'.$hbo->htmlSelect("genus_reso",$hbo->getKeysValues('genus_reso'),'','class="small"').'</td>'.
        '<td><input name="genus_name" class="small" /></td>';
    if ($prefs{'subgenera'} || $prefs{'genus_and_species_only'}) {
        $output .= '<td>'.$hbo->htmlSelect("subgenus_reso",$hbo->getKeysValues('subgenus_reso'),'','class="small"').'</td>'.
        '<td><input name="subgenus_name" class="small" /></td>';
    }
    $output .= '<td>'.$hbo->htmlSelect("species_reso",$hbo->getKeysValues('species_reso'),'','class="small"').'</td>'.
        '<td><input name="species_name" class="small" value="'.$prefs{species_name}.'" /></td>'.
        '</tr><tr>'.
        '<td colspan=6 align=right><input type="button" name="addRow" value="Add row" onClick="insertOccurrenceRow();" /></td>'.
        '</tr>';
    $output .= "</table>";

    $output .= "<br /><br />";

    $output .= '<div align="center"><div style="width: 640px">';
    if (@all_collections > @collections) {
        $output .= "<b>";
        $output .= "Showing collections ".($lower_limit + 1)." to $upper_limit of ".scalar(@all_collections).".";
        if (@all_collections > $upper_limit) {
            my $query = "offset=".($upper_limit);
            foreach my $p ($q->param()) {
                if ($p ne 'offset' &&  $p ne 'next_page_link') {
                    $query .= "&amp;$p=".$q->param($p);
                }
            }
            my $remaining = ($limit + $upper_limit >= @all_collections) ? (@all_collections - $upper_limit) : $limit;
            my $verb = ($limit + $upper_limit >= @all_collections) ? "last" : "next";
            if ($remaining > 1) {
                $remaining= "$remaining collections";
            } else {
                $remaining = "collection";
            }
            $output .= qq|<a href="$WRITE_URL?$query"> Get $verb $remaining</a>.|;

            # We save this so we can go to the next page easily on form submission
            my $next_page_link = uri_escape_utf8(qq|<b><a href="$WRITE_URL?$query"> Edit $verb $remaining</a></b>|);
            $output .= qq|<input type="hidden" name="next_page_link" value="$next_page_link">|;
        }
        $output .= "</b>";
    }
    $output .= '</div></div>';
    $output .= "</form>";
    $output .= "<br /><br />";

    $output .= $hbo->stdIncludes('blank_page_bottom');
    return $output;
}

# JA 19-20.5.09
sub displayOccurrenceListForm	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $dbh = $dbt->dbh;
    my $output = '';
    
    if (!$s->isDBMember()) {
	return login( "Please log in first." );
    }

    if (! $s->get('reference_no')) {
	$s->enqueue_action('displayOccurrenceListForm');
	$q->param('type' => 'select');
	return displaySearchRefs($q, $s, $dbt, $hbo,"<center>Please select a reference first</center>"); 
    }
    
	my %vars;
	my $collection_no = $q->param($COLLECTION_NO);
	my $sql = "(SELECT o.genus_reso,o.genus_name,o.species_reso,o.species_name FROM occurrences o LEFT JOIN reidentifications r ON o.occurrence_no=r.occurrence_no WHERE o.$COLLECTION_NO=$collection_no AND r.reid_no IS NULL) UNION (SELECT r.genus_reso,r.genus_name,r.species_reso,r.species_name FROM occurrences o LEFT JOIN reidentifications r ON o.occurrence_no=r.occurrence_no WHERE o.$COLLECTION_NO=$collection_no AND r.most_recent='YES') ORDER BY genus_name,species_name";
	my @occs = @{$dbt->getData($sql)};

	if ( @occs )	{
		$vars{'old_occurrences'} = "You can only add occurrences with this form. The existing ones are: ";
		my @ids;
		for my $o ( @occs )	{
			$o->{'genus_reso'} =~ s/informal|"//;
			$o->{'species_reso'} =~ s/informal|"//;
			my ($gr,$gn,$sr,$sn) = ($o->{'genus_reso'},$o->{'genus_name'},$o->{'species_reso'},$o->{'species_name'});

			my $id = $gn;
			if ( $gr )	{
				$id = $gr." ".$id;
			}
			if ( $sr )	{
				$id .= " ".$sr;
			}
			$id .= " ".$sn;
			if ( $sn !~ /indet\./ )	{
				$id = "<i>".$id."</i>";
			}
			push @ids , $id;
		}
		$vars{'old_occurrences'} .= join(', ',@ids);
	}

	$sql = "SELECT collection_name FROM $COLLECTIONS WHERE $COLLECTION_NO=$collection_no";
	$vars{'collection_name'} = ${$dbt->getData($sql)}[0]->{'collection_name'};

	$output .= $hbo->stdIncludes($PAGE_TOP);
	$output .= $hbo->populateHTML('js_occurrence_checkform');

	$output .= qq|<form method=post action="$WRITE_URL" onSubmit='return checkForm();'>\n|;
	$vars{$COLLECTION_NO} = $collection_no;
	$vars{'collection_no_field'} = $COLLECTION_NO;
	$vars{'collection_no_field2'} = $COLLECTION_NO;
	$vars{'list_collection_no'} = $collection_no;
	$vars{'reference_no'} = $s->get('reference_no');
	$output .= $hbo->populateHTML('occurrence_list_form',\%vars);
	$output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Enter Occurrence List');
    
    return $output;
}

sub processOccurrenceTable {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = '';
    
    if (!$s->isDBMember()) {
        return login( "Please log in first." );
    }
   
    my @row_tokens = $q->param('row_num');
    my @collections = $q->param('collection_nos');
    my $collection_list = join(",",@collections);
    my $global_abund_unit = $q->param("abund_unit");
    my $session_ref = $s->get('reference_no');
    
    if (!$global_abund_unit) {
        print STDERR "ERROR: no abund_unit specified"; # $$$ FIX!!!
        die;
    }
    if (!$session_ref) {
        print STDERR "ERROR: no session reference";	# $$$ FIX!!!
        die;
    }
    
    # my $p = new PBDB::Permissions($s,$dbt);
    # my $can_modify = $p->getModifierList();
    # $can_modify->{$s->get('authorizer_no')} = 1;

    $output .= $hbo->stdIncludes($PAGE_TOP);
    $output .= '<div align="center"><p class="pageTitle">Occurrence table entry results</p></div>';
    $output .= qq|<form method="post" action="$WRITE_URL">|;
    $output .= '<input type="hidden" name="action" value="startProcessReclassifyForm">';
    $output .= '<div align="center"><table cellpadding=3 cellspacing=0 border=0>';
    my $changed_rows = 0;
    my $seen_homonyms = 0;
    foreach my $i (@row_tokens) {
        my $taxon_key = $q->param("taxon_key_$i");
        my @taxon_nos = $q->param("taxon_no_$i");
        my ($genus_name,$subgenus_name,$species_name,$genus_reso,$subgenus_reso,$species_reso) = split("-_",$taxon_key);
        my (@deleted,@updated,@inserted,@uneditable);
        my $total_occs = 0;
        
        my $taxon_no;
        my @homonyms = ();
        my $manual_resolve_homonyms = 0;
        if (@taxon_nos == 1) {
            # If taxon_nos == 1: good to go. Note that taxon_nos is derived from what actually exists already in the DB,
            #  so if theres a homonym but only one version of the name is used it'll just reuse that name.  Likewise
            $taxon_no = $taxon_nos[0];
        } elsif (@taxon_nos > 1) {
            # If taxon_nos > 1: then there are multiple versions of the same
            # name in the sheet. It would be bad to overwrite any taxons classification arbitrarily
            # so we have a link for the user to manually classify that taxon by setting $manual_resolve_homonyms
            #  non-homonyms may have no taxon_no set if its a new entry - do a lookup in that case.
            @homonyms= @taxon_nos;
            $manual_resolve_homonyms = 1;
        } elsif (@taxon_nos == 0) {
            # If taxon_nos < 1: This can be because the taxon is new or because there are multiple versions of the
            # name, none of which have been classified.  Give an option to classify if homonyms exist
            $taxon_no = PBDB::Taxon::getBestClassification($dbt,$genus_reso,$genus_name,$subgenus_reso,$subgenus_name,$species_reso,$species_name);
            if (!$taxon_no) {
                my @matches = PBDB::Taxon::getBestClassification($dbt,$genus_reso,$genus_name,$subgenus_reso,$subgenus_name,$species_reso,$species_name);
                if (@matches) {
                    @homonyms = map {$_->{'taxon_no'}} @matches;
                    $seen_homonyms++;
                } # Else doesn't exist in the DB
            }
        }
        my @occurrences = ();
        foreach my $collection_no (@collections) {
            my $abund_value = $q->param("abund_value_${i}_${collection_no}");
            my $abund_unit = $global_abund_unit;
            my $primary_key_value = $q->param("occurrence_no_${i}_${collection_no}");
            my $primary_key = "occurrence_no";
            my $table = 'occurrences';
            if ($primary_key !~ /^occurrence_no$|^reid_no$/) {
                $output .= "ERROR: invalid primary key type";
                next;
            }

            my $in_form = ($abund_value !~ /^\s*$/) ? 1 : 0;
            my $in_db = ($primary_key_value > 0) ? 1 : 0;

            if (lc($abund_value) eq 'x') {
                $abund_value = '';
                $abund_unit = '';
            } 
            
            my $db_row;
            if ($in_db) {
                my $sql = "SELECT * FROM $table WHERE $primary_key=$primary_key_value";
                $db_row = ${$dbt->getData($sql)}[0];
                if (!$db_row) {
                    die "Can't find db row $table.$primary_key=$primary_key_value";
                }
            }

            my %record = (
                'collection_no'=>$collection_no,
                'abund_value'=>$abund_value,
                'abund_unit'=>$abund_unit,
                'genus_reso'=>$genus_reso,
                'genus_name'=>$genus_name,
                'subgenus_reso'=>$subgenus_reso,
                'subgenus_name'=>$subgenus_name,
                'species_reso'=>$species_reso,
                'species_name'=>$species_name
            );
            if ($taxon_no) {
                $record{'taxon_no'} = $taxon_no;
            }

            if (!$in_db) {
                $record{'reference_no'} = $session_ref;
            }

            if ($in_db) {
                my $authorizer_no = $db_row->{'authorizer_no'};
                # unless ($can_modify->{$authorizer_no}) {
                #     push @uneditable,$collection_no;
                #     $total_occs++;
                #     next;
                # }
            }
        
            if ($in_form && $in_db) {
                # Do an update
                my $result = $dbt->updateRecord($s,$table,$primary_key,$primary_key_value,\%record);
                if ($result > 0) { 
                    push @updated,$collection_no; 
                }
                push @occurrences, $primary_key_value;
                $total_occs++;
            } elsif ($in_form && !$in_db) {
                # Do an insert
                my ($result,$occurrence_no) = $dbt->insertRecord($s,$table,\%record);
                push @inserted,$collection_no; 
                if ($result) {
                    push @occurrences, $occurrence_no;
                }
                $total_occs++;
                # Add secondary ref
                PBDB::CollectionEntry::setSecondaryRef($dbt,$collection_no,$session_ref);
            } elsif (!$in_form && $in_db) {
                # Do a delete
                $dbt->deleteRecord($s,$table,$primary_key,$primary_key_value);
                push @deleted,$collection_no; 
            } 
        }

        my $taxon_name = PBDB::CollectionEntry::formatOccurrenceTaxonName({
            'genus_name'=>$genus_name,
            'genus_reso'=>$genus_reso,
            'subgenus_name'=>$subgenus_reso,
            'subgenus_reso'=>$subgenus_name,
            'species_reso'=>$species_reso,
            'species_name'=>$species_name
        });
        
        my $classification_select = "";
        if ( @homonyms) {
            if ($manual_resolve_homonyms) {
            } else {
                my @taxon_nos = ("0+unclassified");
                my @descriptions = ("leave unclassified");
                foreach my $taxon_no (@homonyms) {
                    my $t = PBDB::TaxonInfo::getTaxa($dbt,{'taxon_no'=>$taxon_no},['taxon_no','taxon_rank','taxon_name','author1last','author2last','otherauthors','pubyr']);
                    my $authority = PBDB::Taxon::formatTaxon($dbt,$t);
                    push @descriptions, $authority; 
                    push @taxon_nos, $taxon_no."+".$authority;
                }
                $classification_select .= qq|<input type="hidden" name="occurrence_list" value="|.join(",",@occurrences).qq|">|;
                $classification_select .= qq|<input type="hidden" name="old_taxon_no" value="0">|;
                $classification_select .= qq|<input type="hidden" name="occurrence_description" value="|.encode_entities($taxon_name).qq|">|;
                $classification_select .= $hbo->htmlSelect('taxon_no',\@descriptions,\@taxon_nos);
            }
        }
        if (@inserted || @updated || @deleted || !$total_occs || $classification_select || $manual_resolve_homonyms) {
            my $row = "<tr><td>$taxon_name</td><td>$classification_select</td><td>";
            if (@inserted) {
                my $s = (@inserted == 1) ? "" : "s";
                $row .= "Added to ".scalar(@inserted)." collection$s. "; 
            }
            if (@updated) {
                my $s = (@updated == 1) ? "" : "s";
                $row .= "Updated in ".scalar(@updated)." collection$s. ";
            }
            if (@deleted) {
                my $s = (@deleted == 1) ? "" : "s";
                $row .= "Removed from ".scalar(@deleted)." collection$s. ";
            }
            if (!$total_occs) {
                if (@deleted) {
                    $row .= "All occurrences of this taxon were removed. ";
                } else {
                    $row .= "No occurrences of this taxon were entered. ";
                }
            } 
            if ($manual_resolve_homonyms) {
                my $simple_taxon_name = $genus_name;
                $simple_taxon_name .= " ($subgenus_name)" if ($subgenus_name);
                $simple_taxon_name .= " ".$species_name;
                $row .= "Multiple versions of this name exist and must be " . makeAnchor("startDisplayOccurrenceReclassify", "collection_list=$collection_list&taxon_name=$simple_taxon_name", "manually classified");
            }
            $row .= "</td></tr>";
            $output .= $row;
            $changed_rows++;
        }
    }
    if (!$changed_rows) {
        $output .= "<tr><td>No rows were changed</td></tr>";
    }
    if ($seen_homonyms) {
        $output .= qq|<tr><td colspan="3" align="center"><br><input type="submit" name="submit" value="Classify taxa"></td></tr>|;
        $output .= qq|<tr><td colspan="3">|.PBDB::Debug::printWarnings(['Multiple versions of some names exist in the database.  Please select the version wanted and choose "Classify taxa"']).qq|</td></tr>|;
    }
    $output .= "</table>";
    $output .= "</div>";
    $output .= "</form>";
    $output .= '<div align="center"><p>';
    $output .= makeAnchor("displaySearchColls", "type=occurrence_table", "Edit more occurrences");
    if ($q->param('next_page_link')) {
        $output .= " - ".uri_unescape($q->param("next_page_link"));
    }
    $output .= '</p></div>';
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Occurrences Saved');
    
    return $output;
}

sub generateCollectionLabel {
    
    my ($dbt, $collection_no) = @_; #jpjenk (q s dbt hbo) here?
    
    $collection_no = int($collection_no); 
    return unless $collection_no;

    # require GD;
    my $sql = "SELECT collection_name FROM collections WHERE collection_no=".int($collection_no);
    my $collection_name = ${$dbt->getData($sql)}[0]->{'collection_name'};
    # PBDB::PBDBUtil::autoCreateDir("$HTML_DIR/public/collection_labels");
    # my $file = $HTML_DIR."/public/collection_labels/$collection_no.png";
    # my $txt = "#$collection_no: $collection_name";

    # my $font= "$DATA_DIR/fonts/sapirsan.ttf";
    # my $font_size = 10;
    # my $x = $font_size+2;
    # my $height = 240;
    # my $y = $height-3;
    # my $num_lines = 3;
    # my $angle = 1.57079633;# Specified in radians = .5*pi

    # my $width = ($font_size+1)*$num_lines+3;
    # my $im = new GD::Image($width,$height,1);
    # my $white = $im->colorAllocate(255,255,255); # Allocate background color first
    # my $black = $im->colorAllocate(0,0,0);
    # $im->transparent($white);
    # $im->filledRectangle(0,0,$width-1,$height-1,$white);

#     my @words = split(/[\s-]+/,$txt);
#     my $line_count = 1;
#     foreach my $word (@words) {
#         # This first call to stringFT is to GD::Image - this doesn't draw anything
#         # but instead gets the @bounds back quickly so we know whether or now to 
#         # wrap to the next line
#         my @bounds = GD::Image->stringFT($black,$font,$font_size,$angle,$x,$y,$word);
# #        print "Bounds are: ".join(",",@bounds)." for $word<BR>";
#         if ($bounds[3] < 0) {
#             #bounds[3] is the top left y coordinate or some such. if its < 0, then this
#             # strin gis running off the image so break to next line
#             $x += $font_size + 1;
#             last if ($line_count > $num_lines);
#             $y = $height - 3;
#             my @bounds = $im->stringFT($black,$font,$font_size,$angle,$x,$y,$word);
#             $y = $bounds[3] - int($font_size/3);
#         } else {
#             my @bounds = $im->stringFT($black,$font,$font_size,$angle,$x,$y,$word);
#             $y = $bounds[3] - int($font_size);
#         }
#     }

#     open IMG,">$file";
#     print IMG $im->png; 
#     close IMG;
    return $collection_name;
}


# This function now handles inserting/updating occurrences, as well as inserting/updating reids
# Rewritten PS to be a bit clearer, handle deletions of occurrences, and use DBTransationManager
# for consistency/simplicity.
sub processEditOccurrences {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $dbh = $dbt->dbh;
    my $output = '';
    
	if (!$s->isDBMember()) {
	    return login( "Please log in first." );
	}
    
    unless ( $q->param('check_status') eq 'done' )
    {
	my $output = $hbo->$hbo->stdIncludes($PAGE_TOP);
	$output .= "<center><p>Something went wrong, and the database could not be updated.  Please notify the database administrator.</p></center>\n<br>\n";
	$output .= $hbo->$hbo->stdIncludes($PAGE_BOTTOM);
	return $output;
    }
	
	# list of the number of rows to possibly update.
	my @rowTokens;

	# parse freeform all-in-one-textarea lists passed in by
	#  displayOccurrenceListForm JA 19-20.5.09
	my $collection_no = $q->numeric_param('collection_no');
    my $reference_no = $q->numeric_param('reference_no');
    
    if ( ref $collection_no eq 'ARRAY' )
    {
	$collection_no = $collection_no->[0];
    }
    
    if ( ref $reference_no eq 'ARRAY' )
    {
	$reference_no = $reference_no->[0];
    }
    
	if ( $q->param('row_token') )	{
		@rowTokens = $q->param('row_token');
	} elsif ( $q->param('taxon_list') )	{
		my $taxon_list = $q->param('taxon_list');
		# collapse down multiple delimiters, if any
		$taxon_list =~ s/[^A-Za-z0-9 <>\.\"\?\*#\/][^A-Za-z0-9 <>\.\"\?\(\)\*#\/]/=/g;
		my @lines = split /[^A-Za-z0-9 <>\.\"\?\(\)\*#\/]/,$taxon_list;
		my (@names,@comments,@colls,@refs,@occs,@reids);
		for my $l ( 0..$#lines )	{
			if ( $lines[$l] !~ /[A-Za-z0-9]/ )	{
				next;
			}
			if ( $lines[$l] =~ /^[\*#\/]/ && $#names == $#comments + 1 )	{
				$lines[$l] =~ s/^[\*#\/]//g;
				push @comments , $lines[$l];
			} elsif ( $lines[$l] =~ /^[\*#\/]/ )	{
				$lines[$l] =~ s/^[\*#\/]//;
				$comments[$#comments] .= "\n".$lines[$l];
			} else	{
				push @names , $lines[$l];
				while ( $#names > $#comments + 1 )	{
					push @comments , "";
				}
			}
		}
		push @colls , $collection_no foreach @names;
		push @refs , $reference_no foreach @names;
		push @rowTokens , "row_token" foreach @names;
		push @occs , -1 foreach @names;
		push @reids , -1 foreach @names;
		$q->param('taxon_name' => @names);
		$q->param('comments' => @comments);
		$q->param($COLLECTION_NO => @colls);
		$q->param('reference_no' => @refs);
		$q->param($OCCURRENCE_NO => @occs);
		$q->param('reid_no' => @reids);
	} else	{
	    $collection_no = $q->param($COLLECTION_NO);
        }

	# Get the names of all the fields coming in from the form.
	my @param_names = $q->param();

	# list of required fields
	my @required_fields = ($COLLECTION_NO, "taxon_name", "reference_no");
	my @warnings = ();
	my @occurrences = ();
	my @occurrences_to_delete = ();

        my @genera = ();
        my @subgenera = ();
        my @species = ();
        my @latin_names = ();
        my @resos = ("\?","aff\.","cf\.","ex gr\.","n\. gen\.","n\. subgen\.","n\. sp\.","sensu lato");

	my @matrix;

	# loop over all rows submitted from the form

	for (my $i = 0;$i < @rowTokens; $i++)	{

        # Flatten the table into a single row, for easy manipulation
        my %fields = ();
        foreach my $param (@param_names) {
            my @vars = $q->param($param);
            if (scalar(@vars) == 1) {
                $fields{$param} = $vars[0];
            } else {
                $fields{$param} = $vars[$i];
            }
        }

        my $rowno = $i + 1;

        # extract the genus, subgenus, and species names and resos
        #  JA 5.7.07
        if ( $fields{'taxon_name'} )	{
            my $name = $fields{'taxon_name'};

        # first some free passes for breaking the rules by putting stuff
        #  at the end
        # n. gen. n. sp. at the end
            if ( $name =~ /n\. gen\. n\. sp\.$/ )	{
                $name =~ s/n\. gen\. n\. sp\.$//;
                $fields{'genus_reso'} = "n. gen.";
                $fields{'species_reso'} = "n. sp.";
            }
        # n. sp. or sensu lato after a species name at the end
            elsif ( $name =~ / [a-z]+ (n\. sp\.|sensu lato)$/ )	{
                if ( $name =~ /sensu lato$/ )	{
                    $fields{'species_reso'} = "sensu lato";
                } else	{
                    $fields{'species_reso'} = "n. sp.";
                }
                $name =~ s/ (n\. sp\.|sensu lato)$//;
            }
        # a bad idea, but some users may put n. sp. before the species name
            elsif ( $name =~ / n\. sp\./ )	{
                $fields{'species_reso'} = "n. sp.";
                $name =~ s/ n\. sp\.//;
            }
        # users may want to enter n. sp. as a qualifier for a sp., in which
        #  case they will probably write out n. sp. followed by nothing
        # this tests for a genus or subgenus name immediately beforehand
            $name =~ s/([A-Z][a-z]+("|\)|"\)|))( n\. sp\.)$/$1 n. sp. sp./;

        # hack: stash the informals and replace them with dummy values
            my %informal;
            my $foo;
            if ( $name =~ /^</ )	{
                ($informal{'genus'},$foo) = split />/,$name;
                $informal{'genus'} =~ s/<//;
                $name =~ s/^<[^>]*> /Genus /;
            }
            if ( $name =~ / <.*> / )	{
                ($informal{'subgenus'},$foo) = split />/,$name;
                ($foo,$informal{'subgenus'}) = split /</,$informal{'subgenus'};
                $name =~ s/ <.*> / \(Subgenus\) /;
            }
            if ( $name =~ />$/ )	{
                ($foo,$informal{'species'}) = split /</,$name;
                $informal{'species'} =~ s/>//;
                $name =~ s/ <.*>/ species/;
            }
            $name =~ s/^ //;
            $name =~ s/ $//;
            my @words = split / /,$name;
            for my $reso ( @resos )	{
                if ( $words[0]." ".$words[1] eq $reso )	{
                    $fields{'genus_reso'} = $reso;
                    splice @words , 0 , 2;
                } elsif ( $words[0] eq $reso )	{
                    $fields{'genus_reso'} = shift @words;
                    last;
                }
            }
            $fields{'genus_name'} = shift @words;
            $fields{'species_name'} = pop @words;
            for my $reso ( @resos )	{
                if ( $words[$#words-1]." ".$words[$#words] eq $reso )	{
                    $fields{'species_reso'} = $reso;
                    splice @words , 0 , 2;
                }  elsif ( $words[$#words] eq $reso )	{
                    $fields{'species_reso'} = pop @words;
                    last;
                }
            }
            # there is either nothing left, or a subgenus
            if ( $#words > -1 )	{
                $fields{'subgenus_name'} = pop @words;
            }
            if ( $#words > -1 )	{
                for my $reso ( @resos )	{
                    if ( $words[0]." ".$words[1] eq $reso )	{
                        $fields{'subgenus_reso'} = $reso;
                        # shift @words , 2;
			shift @words;
                    } elsif ( $words[0] eq $reso )	{
                        $fields{'subgenus_reso'} = shift @words;
                        last;
                    }
                }
            }
            $fields{'subgenus_name'} =~ s/\(//;
            $fields{'subgenus_name'} =~ s/\)//;
            for my $f ( "genus","subgenus","species" )	{
                if ( $fields{$f.'_name'} =~ /"/ )	{
                    $fields{$f.'_reso'} = '"';
                    $fields{$f.'_name'} =~ s/"//g;
                }
                if ( $informal{$f} )	{
                    $fields{$f.'_name'} = $informal{$f};
                    $fields{$f.'_reso'} = 'informal';
                }
                $fields{$f.'_reso'} =~ s/\\//;
            }
            push @genera , $fields{'genus_name'};
            push @subgenera , $fields{'subgenus_name'};
            push @species , $fields{'species_name'};
            if ( $fields{'species_name'} =~ /^[a-z]*$/ )	{
                if ( $fields{'subgenus_name'} =~ /^[A-Z][a-z]*$/ )	{
                    push @latin_names , $fields{'genus_name'} ." (". $fields{'subgenus_name'} .") ". $fields{'species_name'};
                } else	{
                    push @latin_names , $fields{'genus_name'} ." ". $fields{'species_name'};
                }
            } else	{
                if ( $fields{'subgenus_name'} =~ /^[A-Z][a-z]*$/ )	{
                    push @latin_names , $fields{'genus_name'} ." (". $fields{'subgenus_name'} . ")";
                } else	{
                    push @latin_names , $fields{'genus_name'};
                }
            }
            $fields{'latin_name'} = $latin_names[$#latin_names];
        }

	
        if ( $fields{$COLLECTION_NO} > 0 )	{
            $collection_no = $fields{$COLLECTION_NO}
        }

	%{$matrix[$i]} = %fields;

	# end of first pass
	}

	# check for duplicates JA 2.4.08
	# this section replaces the old occurrence-by-occurrence check that
	#  used checkDuplicates; it's much faster and uses more lenient
	#  criteria because isolated duplicates are handled by the JavaScript
	my $sql ="SELECT genus_reso,genus_name,subgenus_reso,subgenus_name,species_reso,species_name,taxon_no FROM $OCCURRENCES WHERE $COLLECTION_NO=" . $collection_no;
	my @occrefs = @{$dbt->getData($sql)};
	my %taxon_no;
	if ( $#occrefs > 0 )	{
		my $newrows;
		my %newrow;
		for (my $i = 0;$i < @rowTokens; $i++)	{
			if ( $matrix[$i]{'genus_name'} =~ /^[A-Z][a-z]*$/ && $matrix[$i]{$OCCURRENCE_NO} == -1 )	{
				$newrow{ $matrix[$i]{'genus_reso'} ." ". $matrix[$i]{'genus_name'} ." ". $matrix[$i]{'subgenus_reso'} ." ". $matrix[$i]{'subgenus_name'} ." ". $matrix[$i]{'species_reso'} ." ". $matrix[$i]{'species_name'} }++;
				$newrows++;
			}
		}
		if ( $newrows > 0 )	{
			my $dupes;
			for my $or ( @occrefs )	{
				if ( $newrow{ $or->{'genus_reso'} ." ". $or->{'genus_name'} ." ". $or->{'subgenus_reso'} ." ". $or->{'subgenus_name'} ." ". $or->{'species_reso'} ." ". $or->{'species_name'} } > 0 )	{
					$dupes++;
				}
			}
			if ( $newrows == $dupes && $newrows == 1 )	{
				push @warnings , "Nothing was entered or updated because the new occurrence was a duplicate";
				@rowTokens = ();
			} elsif ( $newrows == $dupes )	{
				push @warnings , "Nothing was entered or updated because all the new records were duplicates";
				@rowTokens = ();
			} elsif ( $dupes >= 3 )	{
				push @warnings , "Nothing was entered or updated because there were too many duplicate entries";
				@rowTokens = ();
			}
		}
		# while we're at it, store the taxon_no JA 20.7.08
		# do this here and not earlier because taxon_no is not
		#  stored in the entry form
		for my $or ( @occrefs )	{
			if ( $or->{'taxon_no'} > 0 && $or->{'genus_reso'} !~ /informal/ )	{
				my $latin_name;
				if ( $or->{'species_name'} =~ /^[a-z]*$/ && $or->{'species_reso'} !~ /informal/ )	{
					if ( $or->{'subgenus_name'} =~ /^[A-Z][a-z]*$/ && $or->{'subgenus_reso'} !~ /informal/ )	{
						$latin_name = $or->{'genus_name'} ." (". $or->{'subgenus_name'} .") ". $or->{'species_name'};
					} else	{
						$latin_name = $or->{'genus_name'} ." ". $or->{'species_name'};
					}
				} else	{
					if ( $or->{'subgenus_name'} =~ /^[A-Z][a-z]*$/ && $or->{'subgenus_reso'} !~ /informal/ )	{
						$latin_name = $or->{'genus_name'} ." (". $or->{'subgenus_name'} . ")";
					} else	{
						$latin_name = $or->{'genus_name'};
					}
				}
				$taxon_no{$latin_name} = $or->{'taxon_no'};
			}
		}
	}

	# get as many taxon numbers as possible at once JA 2.4.08
	# this greatly speeds things up because we now only need to use
	#  getBestClassification as a last resort
	$sql = "SELECT taxon_name,taxon_no,count(*) c FROM authorities WHERE taxon_name IN ('" . join('\',\'',@latin_names) . "') GROUP BY taxon_name";
	my @taxonrefs = @{$dbt->getData($sql)};
	for my $tr ( @taxonrefs )	{
		if ( $tr->{'c'} == 1 )	{
			$taxon_no{$tr->{'taxon_name'}} = $tr->{'taxon_no'};
		} elsif ( $tr->{'c'} > 1 )	{
			$taxon_no{$tr->{'taxon_name'}} = -1;
		}
	}

	# finally, check for n. sp. resos that appear to be duplicates and
	#  insert a type_locality number if there's no problem JA 14-15.12.08
	# this is not 100% because it will miss cases where a species was
	#  entered with "n. sp." using two different combinations
	# a couple of (fast harmless) checks in the section section are
	#  repeated here for simplicity
	my (@to_check,%dupe_colls);
	for (my $i = 0;$i < @rowTokens; $i++)	{
		my %fields = %{$matrix[$i]};
		if ( $fields{'genus_name'} eq "" && $fields{$OCCURRENCE_NO} < 1 )	{
			next;
		}
        	if ( $fields{'reference_no'} !~ /^\d+$/ && $fields{'genus'} =~ /[A-Za-z]/ )	{
            		next; 
        	}
        	if ( $fields{$COLLECTION_NO} !~ /^\d+$/ )	{
            		next; 
        	}
	# guess the taxon no by trying to find a single match for the name
	#  in the authorities table JA 1.4.04
	# see Reclassify.pm for a similar operation
	# only do this for non-informal taxa
	# done here and not in the last pass because we need the taxon_nos
		if ( $taxon_no{$fields{'latin_name'}} > 0 )	{
			$fields{'taxon_no'} = $taxon_no{$fields{'latin_name'}};
		} elsif ( $taxon_no{$fields{'latin_name'}} eq "" )	{
			$fields{'taxon_no'} = PBDB::Taxon::getBestClassification($dbt,\%fields);
		} else	{
			$fields{'taxon_no'} = 0;
		}
		if ( $fields{'taxon_no'} > 0 && $fields{'species_reso'} eq "n. sp." )	{
			push @to_check , $fields{'taxon_no'};
		}
		%{$matrix[$i]} = %fields;
	}
	if ( @to_check )	{
		# pre-processing is faster than a join
		$sql = "SELECT taxon_no,taxon_name,type_locality FROM authorities WHERE taxon_no IN (".join(',',@to_check).") AND taxon_rank='species'";
		my @species = @{$dbt->getData($sql)};
		if ( @species )	{
			@to_check = ();
			push @to_check , $_->{'taxon_no'} foreach @species;
			$sql = "(SELECT taxon_no,collection_no FROM occurrences WHERE collection_no!=$collection_no AND taxon_no in (".join(',',@to_check).") AND species_reso='n. sp.') UNION (SELECT taxon_no,collection_no FROM reidentifications WHERE collection_no!=$collection_no AND taxon_no in (".join(',',@to_check).") AND species_reso='n. sp.')";
			my @dupe_refs = @{$dbt->getData($sql)};
			if ( @dupe_refs )	{
				$dupe_colls{$_->{'taxon_no'}} .= ", ".$_->{$COLLECTION_NO} foreach @dupe_refs;
				for (my $i = 0;$i < @rowTokens; $i++)	{
					my %fields = %{$matrix[$i]};
					if ( ! $dupe_colls{$fields{'taxon_no'}} || ! $fields{'taxon_no'} )	{
						next;
					}
					$dupe_colls{$fields{'taxon_no'}} =~ s/^, //;
					if ( $dupe_colls{$fields{'taxon_no'}} =~ /^[0-9]+$/ )	{
                        # jpjenk-question
						push @warnings, "<a href=\"$WRITE_URL?a=displayAuthorityForm&amp;taxon_no=$fields{'taxon_no'}\"><i>$fields{'genus_name'} $fields{'species_name'}</i></a> has already been marked as new in collection $dupe_colls{$fields{'taxon_no'}}, so it won't be recorded as such in this one";
					} elsif ( $dupe_colls{$fields{'taxon_no'}} =~ /, [0-9]/ )	{
						$dupe_colls{$fields{'taxon_no'}} =~ s/(, )([0-9]*)$/ and $2/;
						push @warnings, "<i>$fields{'genus_name'} $fields{'species_name'}</i> has already been marked as new in collections $dupe_colls{$fields{'taxon_no'}}, so it won't be recorded as such in this one";
					}
				}
			}
			my @to_update;
			for my $s ( @species )	{
				if ( ! $dupe_colls{$s->{'taxon_no'}} && $s->{'type_locality'} < 1 )	{
					push @to_update , $s->{'taxon_no'};
				} elsif ( ! $dupe_colls{$s->{'taxon_no'}} && $s->{'type_locality'} > 0 && $s->{'type_locality'} != $collection_no )	{
                    # jpjenk-question
					push @warnings, "The type locality of <a href=\"$WRITE_URL?a=displayAuthorityForm&amp;taxon_no=$s->{'taxon_no'}\"><i>$s->{'taxon_name'}</i></a> has already been marked as new in collection $s->{'type_locality'}, which seems incorrect";
				}
			}
			if ( @to_update )	{
				$sql = "UPDATE authorities SET type_locality=$collection_no,modified=modified WHERE taxon_no IN (".join(',',@to_update).")";
				$dbh->do($sql);
				PBDB::Taxon::propagateAuthorityInfo($dbt,$_) foreach @to_update;
			}
		}

	}

	# last pass, update/insert loop
	for (my $i = 0;$i < @rowTokens; $i++)	{

	my %fields = %{$matrix[$i]};
	my $rowno = $i + 1;

	if ( $fields{'genus_name'} eq "" && $fields{$OCCURRENCE_NO} < 1 )	{
		next;
	}

		# check that all required fields have a non empty value
        if ( $fields{'reference_no'} !~ /^\d+$/ && $fields{'genus'} =~ /[A-Za-z]/ )	{
            push @warnings, "There is no reference number for row $rowno, so it was skipped";
            next; 
        }
        if ( $fields{$COLLECTION_NO} !~ /^\d+$/ )	{
            push @warnings, "There is no collection number for row $rowno, so it was skipped";
            next; 
        }
	my $taxon_name = PBDB::CollectionEntry::formatOccurrenceTaxonName(\%fields);

        if ($fields{'genus_name'} =~ /^\s*$/) {
            if ($fields{$OCCURRENCE_NO} =~ /^\d+$/ && $fields{'reid_no'} != -1) {
                # THIS IS AN UPDATE: CASE 1 or CASE 3. We will be deleting this record, 
                # Do nothing for now since this is handled below;
            } else {
                # THIS IS AN INSERT: CASE 2 or CASE 4. Just do nothing, this is a empty row
                next;  
            }
        } else {
            if (!PBDB::Validation::validOccurrenceGenus($fields{'genus_reso'},$fields{'genus_name'})) {
                push @warnings, "The genus ($fields{'genus_name'}) in row $rowno is blank or improperly formatted, so it was skipped";
                next; 
            }
            if ($fields{'subgenus_name'} !~ /^\s*$/ && !PBDB::Validation::validOccurrenceGenus($fields{'subgenus_reso'},$fields{'subgenus_name'})) {
                push @warnings, "The subgenus ($fields{'subgenus_name'}) in row $rowno is improperly formatted, so it was skipped";
                next; 
            }
            if ($fields{'species_name'} =~ /^\s*$/ || !PBDB::Validation::validOccurrenceSpecies($fields{'species_reso'},$fields{'species_name'})) {
                push @warnings, "The species ($fields{'species_name'}) in row $rowno is blank or improperly formatted, so it was skipped";
                next; 
            }
        }

        if ($fields{$OCCURRENCE_NO} =~ /^\d+$/ && $fields{$OCCURRENCE_NO} > 0 &&
            (($fields{'reid_no'} =~ /^\d+$/ && $fields{'reid_no'} > 0) || ($fields{'reid_no'} == -1))) {
            # We're either updating or inserting a reidentification
            my $sql = "SELECT reference_no FROM $OCCURRENCES WHERE $OCCURRENCE_NO=$fields{$OCCURRENCE_NO}";
            my $occurrence_reference_no = ${$dbt->getData($sql)}[0]->{'reference_no'};
            if ($fields{'reference_no'} == $occurrence_reference_no) {
                push @warnings, "The occurrence of taxon $taxon_name in row $rowno and its reidentification have the same reference number";
                next;
            }
            # don't insert a new reID using a ref already used to reID
            #   this occurrence
            if ( $fields{'reid_no'} == -1 )	{
                my $sql = "SELECT reference_no FROM reidentifications WHERE occurrence_no=$fields{'occurrence_no'}";
                my @reidrows = @{$dbt->getData($sql)};
                my $isduplicate;
                for my $reidrow ( @reidrows )	{
                    if ($fields{'reference_no'} == $reidrow->{reference_no}) {
                        push @warnings, "This reference already has been used to reidentify the occurrence of taxon $taxon_name in row $rowno";
                       $isduplicate++;
                       next;
                    }
                }
                if ( $isduplicate > 0 )	{
                   next;
                }
            }
        }
        
		# CASE 1: UPDATE REID
        if ($fields{'reid_no'} =~ /^\d+$/ && $fields{'reid_no'} > 0 &&
            $fields{$OCCURRENCE_NO} =~ /^\d+$/ && $fields{$OCCURRENCE_NO} > 0) {

            # CASE 1a: Delete record
            if ($fields{'genus_name'} =~ /^\s*$/) {
                $dbt->deleteRecord($s,'reidentifications','reid_no',$fields{'reid_no'});
            } 
            # CASE 1b: Update record
            else {
                # ugly hack: make sure taxon_no doesn't change unless
                #  genus_name or species_name did JA 1.4.04
                my $old_row = ${$dbt->getData("SELECT * FROM reidentifications WHERE reid_no=$fields{'reid_no'}")}[0];
                die ("no reid for $fields{reid_no}") if (!$old_row);
                if ($old_row->{'genus_name'} eq $fields{'genus_name'} &&
                    $old_row->{'subgenus_name'} eq $fields{'subgenus_name'} &&
                    $old_row->{'species_name'} eq $fields{'species_name'}) {
                    delete $fields{'taxon_no'};
                }

                $dbt->updateRecord($s,'reidentifications','reid_no',$fields{'reid_no'},\%fields);

                if($old_row->{'reference_no'} != $fields{'reference_no'}) {
                    dbg("calling setSecondaryRef (updating ReID)<br>");
                    unless(PBDB::CollectionEntry::isRefPrimaryOrSecondary($dbt, $fields{$COLLECTION_NO}, $fields{'reference_no'})){
                           PBDB::CollectionEntry::setSecondaryRef($dbt,$fields{$COLLECTION_NO},$fields{'reference_no'});
                    }
                }
            }
            setMostRecentReID($q, $s, $dbt, $hbo, $fields{$OCCURRENCE_NO});
            push @occurrences, $fields{$OCCURRENCE_NO};
        }
		# CASE 2: NEW REID
		elsif ($fields{$OCCURRENCE_NO} =~ /^\d+$/ && $fields{$OCCURRENCE_NO} > 0 && 
               $fields{'reid_no'} == -1) {
            # Check for duplicates
            my @keys = ("genus_reso","genus_name","subgenus_reso","subgenus_name","species_reso","species_name",$OCCURRENCE_NO);
            my %vars = map{$_,$dbh->quote($_)} @fields{@keys};

            my $dupe_id = $dbt->checkDuplicates("reidentifications", \%vars);

            if ( $dupe_id ) {
                push @warnings, "Row ". ($i + 1) ." may be a duplicate";
            }
#            } elsif ( $return ) {
            $dbt->insertRecord($s,'reidentifications',\%fields);

            unless(PBDB::CollectionEntry::isRefPrimaryOrSecondary($dbt, $fields{$COLLECTION_NO}, $fields{'reference_no'}))	{
               PBDB::CollectionEntry::setSecondaryRef($dbt,$fields{$COLLECTION_NO}, $fields{'reference_no'});
            }
#            }
            setMostRecentReID($q, $s, $dbt, $hbo, $fields{$OCCURRENCE_NO});
            push @occurrences, $fields{$OCCURRENCE_NO};
        }
		
		# CASE 3: UPDATE OCCURRENCE
		elsif($fields{$OCCURRENCE_NO} =~ /^\d+$/ && $fields{$OCCURRENCE_NO} > 0) {
            # CASE 3a: Delete record
            if ($fields{'genus_name'} =~ /^\s*$/) {
                # We push this onto an array for later processing because we can't delete an occurrence
                # With reids attached to it, so we want to let any reids be deleted first
                my $old_row = ${$dbt->getData("SELECT * FROM $OCCURRENCES WHERE $OCCURRENCE_NO=$fields{$OCCURRENCE_NO}")}[0];
                push @occurrences_to_delete, [$fields{$OCCURRENCE_NO},PBDB::CollectionEntry::formatOccurrenceTaxonName($old_row),$i];
            } 
            # CASE 3b: Update record
            else {
                # ugly hack: make sure taxon_no doesn't change unless
                #  genus_name or species_name did JA 1.4.04
                my $old_row = ${$dbt->getData("SELECT * FROM $OCCURRENCES WHERE $OCCURRENCE_NO=$fields{$OCCURRENCE_NO}")}[0];
                die ("no reid for $fields{reid_no}") if (!$old_row);
                if ($old_row->{'genus_name'} eq $fields{'genus_name'} &&
                    $old_row->{'subgenus_name'} eq $fields{'subgenus_name'} &&
                    $old_row->{'species_name'} eq $fields{'species_name'}) {
                    delete $fields{'taxon_no'};
                }

                $dbt->updateRecord($s,$OCCURRENCES,$OCCURRENCE_NO,$fields{$OCCURRENCE_NO},\%fields);

                if($old_row->{'reference_no'} != $fields{'reference_no'}) {
                    dbg("calling setSecondaryRef (updating occurrence)<br>");
                    unless(PBDB::CollectionEntry::isRefPrimaryOrSecondary($dbt, $fields{$COLLECTION_NO}, $fields{'reference_no'}))	{
                           PBDB::CollectionEntry::setSecondaryRef($dbt,$fields{$COLLECTION_NO}, $fields{'reference_no'});
                    }
                }
            }
            push @occurrences, $fields{$OCCURRENCE_NO};
		} 
        # CASE 4: NEW OCCURRENCE
        elsif ($fields{$OCCURRENCE_NO} == -1) {
            # previously, a check here for duplicates generated error
            #  messages but (1) was incredibly slow and (2) apparently
            #  didn't work, so there is now a batch check above instead
	    delete $fields{$OCCURRENCE_NO}; delete $fields{reid_no};
            my ($result, $occurrence_no) = $dbt->insertRecord($s,$OCCURRENCES,\%fields);
            if ($result && $occurrence_no =~ /^\d+$/) {
                push @occurrences, $occurrence_no;
            }

            unless(PBDB::CollectionEntry::isRefPrimaryOrSecondary($dbt, $fields{$COLLECTION_NO}, $fields{'reference_no'}))	{
                   PBDB::CollectionEntry::setSecondaryRef($dbt,$fields{$COLLECTION_NO}, $fields{'reference_no'});
            }
        }
    }

    # Now handle the actual deletion
    foreach my $o (@occurrences_to_delete) {
        my ($occurrence_no,$taxon_name,$line_no) = @{$o};
        my $sql = "SELECT COUNT(*) c FROM reidentifications WHERE occurrence_no=$occurrence_no";
        my $reid_cnt = ${$dbt->getData($sql)}[0]->{'c'};
        $sql = "SELECT COUNT(*) c FROM specimens WHERE occurrence_no=$occurrence_no";
        my $measure_cnt = ${$dbt->getData($sql)}[0]->{'c'};
        if ($reid_cnt) {
            push @warnings, "'$taxon_name' on line $line_no can't be deleted because there are reidentifications based on it";
        }
        if ($measure_cnt) {
            push @warnings, "'$taxon_name' on line $line_no can't be deleted because there are measurements based on it";
        }
        if ($reid_cnt == 0 && $measure_cnt == 0) {
            $dbt->deleteRecord($s,$OCCURRENCES,$OCCURRENCE_NO,$occurrence_no);
        }
    }

	$output .= $hbo->stdIncludes( $PAGE_TOP );

	$output .= qq|<div align="center"><p class="large" style="margin-bottom: 1.5em;">|;
	$sql = "SELECT collection_name AS coll FROM collections WHERE collection_no=$collection_no";
	$output .= ${$dbt->getData($sql)}[0]->{'coll'};
	$output .= "</p></div>\n\n";

	# Links to re-edit, etc
	my $links = "<div align=\"center\" style=\"padding-top: 1em;\">";
	if ($q->param('form_source') eq 'new_reids_form') {
        # suppress link if there is clearly nothing more to reidentify
        #  JA 3.8.07
        # this won't work if exactly ten occurrences have been displayed
        if ( $#rowTokens < 9 )	{
            my $localtaxon_name = uri_escape_utf8($q->param('search_taxon_name') // '');
            my $localcoll_no = uri_escape_utf8($q->numeric_param("list_collection_no") // '');
            my $localpage_no = uri_escape_utf8($q->param('page_no') // '');
            $links .= makeAnchor("displayCollResults", "type=reid&taxon_name=$localtaxon_name&collection_no=$localcoll_no&page_no=$localpage_no") . "<nobr>Reidentify next 10 occurrences</nobr> - ";
        }
        $links .= makeAnchor("displayReIDCollsAndOccsSearchForm", "", "<nobr>Reidentify different occurrences</nobr>");
    } else {
        if ($q->param('list_collection_no')) {
            my $collection_no = $q->numeric_param("list_collection_no");
            $links .= makeAnchor("displayOccurrenceAddEdit", "$COLLECTION_NO=$collection_no", "<nobr>Edit this taxonomic list</nobr>") . " - ";
            $links .= makeAnchor("displayOccurrenceListForm", "$COLLECTION_NO=$collection_no", "Paste in more names") . " - ";
            $links .= makeAnchor("startStartReclassifyOccurrences", "$COLLECTION_NO=$collection_no", "<nobr>Reclassify these IDs</nobr>") . " - ";
            $links .= makeAnchor("displayCollectionForm", "$COLLECTION_NO=$collection_no", "<nobr>Edit the collection record</nobr>") . "<br>";
        }
        $links .= makeAnchor("displaySearchCollsForAdd", "type=add", "Add") . " or ";
        $links .= makeAnchor("displaySearchColls", "type=edit", "edit another collection") . " - </nobr>";
        $links .= makeAnchor("displaySearchColls", "type=edit_occurrence", "Add/edit");
        $links .= makeAnchor("displaySearchColls", "type=occurrence_list", "paste in") . ", or ";
        $links .= makeAnchor("displayReIDCollsAndOccsSearchForm", "", "reidentify IDs for a different collection") . "</nobr>";
    }
    $links .= "</div><br>";

	# for identifying unrecognized (new to the db) genus/species names.
	# these are the new taxon names that the user is trying to enter, do this before insert
	my @new_genera = PBDB::TypoChecker::newTaxonNames($dbt,\@genera,'genus_name');
	my @new_subgenera =  PBDB::TypoChecker::newTaxonNames($dbt,\@subgenera,'subgenus_name');
	my @new_species =  PBDB::TypoChecker::newTaxonNames($dbt,\@species,'species_name');

	$output .= qq|<div style="padding-left: 1em; padding-right: 1em;>"|;

    my $return;
    if ($q->param('list_collection_no')) {
        my $collection_no = $q->numeric_param("list_collection_no");
        my $coll = ${$dbt->getData("SELECT $COLLECTION_NO,reference_no FROM $COLLECTIONS WHERE $COLLECTION_NO=$collection_no")}[0];
    	$return = PBDB::CollectionEntry::buildTaxonomicList($dbt,$hbo,$s,{$COLLECTION_NO=>$collection_no, 'hide_reference_no'=>$coll->{'reference_no'},'new_genera'=>\@new_genera, 'new_subgenera'=>\@new_subgenera, 'new_species'=>\@new_species, 'do_reclassify'=>1, 'warnings'=>\@warnings, 'save_links'=>$links });
    } else {
    	$return = PBDB::CollectionEntry::buildTaxonomicList($dbt,$hbo,$s,{'occurrence_list'=>\@occurrences, 'new_genera'=>\@new_genera, 'new_subgenera'=>\@new_subgenera, 'new_species'=>\@new_species, 'do_reclassify'=>1, 'warnings'=>\@warnings, 'save_links'=>$links });
    }
    if ( ! $return )	{
        $output .= $links;
    } else	{
        $output .= $return;
    }

    $output .= "\n</div>\n<br>\n";

    $output .= $hbo->stdIncludes( $PAGE_BOTTOM );
    
    $hbo->pageTitle('PBDB Occurrences Saved');
    
    return $output;
}



 #  3.* System processes new reference if user entered one.  System
#       displays search occurrences and search collections forms
#     * User searches for a collection in order to work with
#       occurrences from that collection
#     OR
#     * User searches for genus names of occurrences to work with
sub displayReIDCollsAndOccsSearchForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    # Have to be logged in
    if (!$s->isDBMember()) {
	redirect '/login?reason=login', 303;
	# login( "Please log in first.",'displayReIDCollsAndOccsSearchForm');
	# return;
    }
    
        # Have to have a reference #
	my $reference_no = $s->get("reference_no");
	if ( ! $reference_no ) {
	    $s->enqueue_action('displayReIDCollsAndOccsSearchForm');
	    $q->param('type' => 'select');
	    return displaySearchRefs($q, $s, $dbt, $hbo, "<center>Please choose a reference first</center>" );
	}	


    my %vars = $q->Vars();
    $vars{'enterer_me'} = $s->get('enterer_reversed');
    $vars{'submit'} = "Search for reidentifications";
    $vars{'page_title'} = "Reidentifications search form";
    $vars{'action'} = "displayCollResults";
    $vars{'type'} = "reid";

    # Spit out the HTML
    
    my $output = $hbo->stdIncludes( $PAGE_TOP );
    $output .= PBDB::PBDBUtil::printIntervalsJava($dbt,1);
    $output .= PBDB::Person::makeAuthEntJavascript($dbt);
    $output .= $hbo->populateHTML('search_occurrences_form',\%vars);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Reidentifications Search');
    
    return $output;
}

sub displayOccsForReID {
    
    my ($q, $s, $dbt, $hbo, $collNos) = @_;
    
    my $output = '';
    my $dbh = $dbt->dbh;
    my $collection_no = $q->numeric_param('collection_no');
    my $taxon_name = $q->param('taxon_name');
    my $where = "";
    
	#dbg("genus_name: $genus_name, subgenus_name: $subgenus_name, species_name: $species_name");

	my $current_session_ref = $s->get("reference_no");
	# make sure they've selected a reference
	# (the only way to get here without a reference is by doing 
	# a coll search right after logging in).
	unless($current_session_ref){
	    $s->enqueue_action('displayOccsForReID', $q);
	    $q->param('type' => 'select');
	    return displaySearchRefs($q, $s, $dbt, $hbo);	
	}

    # my $collNos = shift;
	my @colls;
	if($collNos){
		@colls = @{$collNos};
	}

	my $printCollDetails = 0;

	$output .= $hbo->stdIncludes( $PAGE_TOP );
	$output .= $hbo->populateHTML('js_occurrence_checkform');
    
	my $pageNo = $q->param('page_no');
	if ( ! $pageNo ) { 
		$pageNo = 1;
	}


	my $reference_no = $current_session_ref;
	my $ref = PBDB::Reference::getReference($dbt,$reference_no);
	my $formatted_primary = PBDB::Reference::formatLongRef($ref);
	my $refString = "<b>" . makeAnchor("displayReference", "reference_no=$reference_no", "$reference_no") . "</b> $formatted_primary<br>";

	# Build the SQL
	my @where = ();
	my $printCollectionDetails = 0;
	# Don't build it directly from the genus_name or species_name, let dispalyCollResults
	# DO that for us and pass in a set of collection_nos, for consistency, then filter at the end

	if (! @colls && $q->numeric_param('collection_no')) {
		push @colls , $q->numeric_param('collection_no');
	}

	if (@colls) {
		$printCollectionDetails = 1;
		push @where, "collection_no IN (".join(',',@colls).")";
		my ($genus,$subgenus,$species) = PBDB::Taxon::splitTaxon($q->param('taxon_name'));
		if ( $genus )	{
			my $names = $dbh->quote($genus);
			if ($subgenus) {
				$names .= ", ".$dbh->quote($subgenus);
			}
			push @where, "(genus_name IN ($names) OR subgenus_name IN ($names))";
		}
		push @where, "species_name LIKE ".$dbh->quote($species) if ($species);
	} elsif ($collection_no) {
		push @where, "collection_no=$collection_no";
	} else {
		push @where, "0=1";
	}

	# some occs are out of primary key order, so order them JA 26.6.04
	my $sql = "SELECT * FROM occurrences WHERE ".join(" AND ",@where);
        my $sortby = $q->param('sort_occs_by');
	if ( $sortby && $sortby =~ /^\w+$/ )	{
		$sql .= " ORDER BY $sortby";
		if ( $q->param('sort_occs_order') eq "desc" )	{
			$sql .= " DESC";
		}
	}
	my $limit = 1 + 10 * $pageNo;
	$sql .= " LIMIT $limit";

	dbg("$sql<br>");
	my @results = @{$dbt->getData($sql)};

	my $rowCount = 0;
	my %pref = $s->getPreferences();
	my @optional = ('subgenera','genus_and_species_only','abundances','plant_organs','species_name');
    if (@results) {
        my $header_vars = {
            'ref_string'=>$refString,
            'search_taxon_name'=>$taxon_name,
            'list_collection_no'=>$collection_no
        };
        $header_vars->{$_} = $pref{$_} for (@optional);
		$output .= $hbo->populateHTML('reid_header_row', $header_vars);

	splice @results , 0 , ( $pageNo - 1 ) * 10;
        foreach my $row (@results) {
            my $html = "";
            # If we have 11 rows, skip the last one; and we need a next button
            $rowCount++;
            last if $rowCount > 10;

            # Print occurrence row and reid input row
            $html .= "<tr>\n";
            $html .= "    <td align=\"left\" style=\"padding-top: 0.5em;\">".$row->{"genus_reso"};
            $html .= " ".$row->{"genus_name"};
            if ($pref{'subgenera'} eq "yes")	{
                $html .= " ".$row->{"subgenus_reso"};
                $html .= " ".$row->{"subgenus_name"};
            }
            $html .= " " . $row->{"species_reso"};
            $html .= " " . $row->{"species_name"} . "</td>\n";
            $html .= " <td>". $row->{"comments"} . "</td>\n";
            if ($pref{'plant_organs'} eq "yes")	{
                $html .= "    <td>" . $row->{"plant_organ"} . "</td>\n";
                $html .= "    <td>" . $row->{"plant_organ2"} . "</td>\n";
            }
            $html .= "</tr>";
            if ($current_session_ref == $row->{'reference_no'}) {
                $html .= "<tr><td colspan=20><i>The current reference is the same as the original reference, so this taxon may not be reidentified.</i></td></tr>";
            } else {
                my $vars = {
                    'collection_no'=>$row->{'collection_no'},
                    'occurrence_no'=>$row->{'occurrence_no'},
                    'reference_no'=>$current_session_ref
                };
                $vars->{$_} = $pref{$_} for (@optional);
                $html .= $hbo->populateHTML('reid_entry_row',$vars);
            }

            # print other reids for the same occurrence

            $html .= "<tr><td colspan=100>";
            my ($table,$classification) = PBDB::CollectionEntry::getReidHTMLTableByOccNum($dbt,$hbo,$s,$row->{'occurrence_no'}, 0);
            $html .= "<table>".$table."</table>";
            $html .= "</td></tr>\n";
            #$sth2->finish();
            
            my $ref = PBDB::Reference::getReference($dbt,$row->{'reference_no'});
            my $formatted_primary = PBDB::Reference::formatShortRef($ref);
            my $refString = '<b>' . makeAnchor("displayReference", "reference_no=$row->{reference_no}", "$row->{reference_no}") . "</b>&nbsp;$formatted_primary";

            $html .= "<tr><td colspan=20 class=\"verysmall\" style=\"padding-bottom: 0.75em;\">Original reference: $refString<br>\n";
            # Print the collections details
            if ( $printCollectionDetails) {
                my $sql = "SELECT collection_name,state,country,formation,period_max FROM collections WHERE collection_no=" . $row->{'collection_no'};
                my $sth = $dbh->prepare( $sql ) || die ( "$sql<hr>$!" );
                $sth->execute();
                my %collRow = %{$sth->fetchrow_hashref()};
                $html .= "Collection:";
                my $details = makeAnchor("basicCollectionSearch", "collection_no=$row->{'collection_no'}", "$row->{'collection_no'}") . " " . $collRow{'collection_name'};
                if ($collRow{'state'} && $collRow{'country'} eq "United States")	{
                     $details .= " - " . $collRow{'state'};
                }
                if ($collRow{'country'})	{
                    $details .= " - " . $collRow{'country'};
                }
                if ($collRow{'formation'})	{
                    $details .= " - " . $collRow{'formation'} . " Formation";
                }
                if ($collRow{'period_max'})	{
                    $details .= " - " . $collRow{'period_max'};
                }
                $html .= "$details </td>";
                $html .= "</tr>";
                $sth->finish();
            }
        
            #$html .= "<tr><td colspan=100><hr width=100%></td></tr>";
            if ($rowCount % 2 == 1) {
                $html =~ s/<tr/<tr class=\"darkList\"/g;
            } else	{
                $html =~ s/<tr/<tr class=\"lightList\"/g;
            }
            $output .= $html;

        }
    }

	$output .= "</table>\n";
	$pageNo++;
	if ($rowCount > 0)	{
		$output .= qq|<center><p><input type=submit value="Save reidentifications"></center></p>\n|;
		$output .= qq|<input type="hidden" name="page_no" value="$pageNo">\n|;
		$output .= qq|<input type="hidden" name="sort_occs_by" value="|;
		$output .= $q->param('sort_occs_by') . "\">\n";
		$output .= qq|<input type="hidden" name="sort_occs_order" value="|;
		$output .= $q->param('sort_occs_order') . "\">\n";
	} else	{
		$output .= "<center><p class=\"pageTitle\">Sorry! No matches were found</p></center>\n";
		$output .= "<p align=center>Please " . makeAnchor("displayReIDCollsAndOccsSearchForm", "", "try again") . " with different search terms</p>\n";
	}
	$output .= "</form>\n";
	$output .= "\n<table border=0 width=100%>\n<tr>\n";

	# Print prev and next  links as appropriate

	# Next link
	if ( $rowCount > 10 ) {
        my $localsort_occs_by=$q->param('sort_occs_by');
        my $localsort_occs_order=$q->param('sort_occs_order');
		$output .= "<td align=center>";
		$output .= "<b>" . makeAnchor("displayCollResults", "type=reid&taxon_name=$taxon_name&collection_no=$collection_no&sort_occs_by=$localsort_occs_by&sort_occs_order=$localsort_occs_order&page_no=$pageNo", "Skip to the next 10 occurrences") . "</b>";
		$output .= "</td></tr>\n";
		$output .= "<tr><td class=small align=center><i>Warning: if you go to the next page without saving, your changes will be lost</i></td>\n";
	}

	$output .= "</tr>\n</table><p>\n";

    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    $hbo->pageTitle('PBDB Occurrences For Reidentification');
    
    return $output;
}


# Marks the most_recent field in the reidentifications table to YES for the most recent reid for
# an occurrence, and marks all not-most-recent to NO.  Needed for collections search for Map and such
# PS 8/15/2005
sub setMostRecentReID {
    
    my ($q, $s, $dbt, $hbo, $occurrence_no) = @_;
    
    # my $dbt = shift;
    my $dbh = $dbt->dbh;
    # my $occurrence_no = shift;

    if ($occurrence_no =~ /^\d+$/) {
        my $sql = "SELECT re.* FROM reidentifications re, refs r WHERE r.reference_no=re.reference_no AND re.occurrence_no=".$occurrence_no." ORDER BY r.pubyr DESC, re.reid_no DESC";
        my @results = @{$dbt->getData($sql)};
        if ($results[0]->{'reid_no'}>0) {
            $sql = "UPDATE reidentifications SET modified=modified, most_recent='YES' WHERE reid_no=".$results[0]->{'reid_no'};
            my $result = $dbh->do($sql);
            dbg("set most recent: $sql");
            if (!$result) {
                carp "Error setting most recent reid to YES for reid_no=$results[0]->{reid_no}";
            } else	{
                $sql = "UPDATE occurrences SET modified=modified, reid_no=".$results[0]->{'reid_no'}." WHERE occurrence_no=".$occurrence_no;
                my $result = $dbh->do($sql);
            }
                
            my @older_reids;
            for(my $i=1;$i<scalar(@results);$i++) {
                push @older_reids, $results[$i]->{'reid_no'};
            }
            if (@older_reids) {
                $sql = "UPDATE reidentifications SET modified=modified, most_recent='NO' WHERE reid_no IN (".join(",",@older_reids).")";
                $result = $dbh->do($sql);
                dbg("set not most recent: $sql");
                if (!$result) {
                    carp "Error setting most recent reid to NO for reid_no IN (".join(",",@older_reids).")"; 
                }
            }
        }
    }
}

# ------------------------ #
# Person pages
# ------------------------ #

# sub personForm	{
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
# 	return if PBDB::PBDBUtil::checkForBot();
# 	logRequest($s,$q);
# 	PBDB::Person::personForm($dbt,$hbo,$s,$q);
# }

# sub addPerson	{
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
# 	return if PBDB::PBDBUtil::checkForBot();
# 	logRequest($s,$q);
# 	PBDB::Person::addPerson($dbt,$hbo,$s,$q);
# }

# sub editPerson	{
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
# 	return if PBDB::PBDBUtil::checkForBot();
# 	logRequest($s,$q);
# 	PBDB::Person::editPerson($dbt,$hbo,$s,$q);
# }

# sub showEnterers {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
#     logRequest($s,$q);
#     print $hbo->stdIncludes($PAGE_TOP);
#     print PBDB::Person::showEnterers($dbt,$IS_FOSSIL_RECORD);
#     print $hbo->stdIncludes($PAGE_BOTTOM);
# }

# sub showAuthorizers {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
#     logRequest($s,$q);
#     print $hbo->stdIncludes($PAGE_TOP);
#     print PBDB::Person::showAuthorizers($dbt,$IS_FOSSIL_RECORD);
#     print $hbo->stdIncludes($PAGE_BOTTOM);
# }

# sub showFeaturedAuthorizers {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
#     logRequest($s,$q);
#     print $hbo->stdIncludes($PAGE_TOP);
#     print PBDB::Person::showFeaturedAuthorizers($dbt,$IS_FOSSIL_RECORD);
#     print $hbo->stdIncludes($PAGE_BOTTOM);
# }

# sub showInstitutions {
    
#     my ($q, $s, $dbt, $hbo) = @_;
    
#     logRequest($s,$q);
#     print $hbo->stdIncludes($PAGE_TOP);
#     print PBDB::Person::showInstitutions($dbt,$IS_FOSSIL_RECORD);
#     print $hbo->stdIncludes($PAGE_BOTTOM);
# }

sub publications	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    logRequest($s,$q);
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Person::publications($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    return $output;
}

sub publicationForm	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    logRequest($s,$q);
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Person::publicationForm($q,$dbt,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    return $output;
}

sub editPublication	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    logRequest($s,$q);
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Person::editPublication($q,$dbt);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    return $output;
}


# ------------------------ #
# Confidence Intervals JSM #
# ------------------------ #

# sub displaySearchSectionResults{
#     return if PBDB::PBDBUtil::checkForBot();
#     require Confidence;
#     logRequest($s,$q);
#     print $hbo->stdIncludes($PAGE_TOP);
#     Confidence::displaySearchSectionResults($q, $s, $dbt,$hbo);
#     print $hbo->stdIncludes($PAGE_BOTTOM);
# }

# sub displaySearchSectionForm{
#     require Confidence;
#     print $hbo->stdIncludes($PAGE_TOP);
#     Confidence::displaySearchSectionForm($q, $s, $dbt,$hbo);
#     print $hbo->stdIncludes($PAGE_BOTTOM);
# }

# sub displayTaxaIntervalsForm{
#     require Confidence;
#     print $hbo->stdIncludes($PAGE_TOP);
#     Confidence::displayTaxaIntervalsForm($q, $s, $dbt,$hbo);
#     print $hbo->stdIncludes($PAGE_BOTTOM);
# }

# sub displayTaxaIntervalsResults{
#     return if PBDB::PBDBUtil::checkForBot();
#     require Confidence;
#     logRequest($s,$q);
#     print $hbo->stdIncludes($PAGE_TOP);
#     Confidence::displayTaxaIntervalsResults($q, $s, $dbt,$hbo);
#     print $hbo->stdIncludes($PAGE_BOTTOM);
# }

# sub buildListForm {
#     return if PBDB::PBDBUtil::checkForBot();
#     require Confidence;
#     print $hbo->stdIncludes($PAGE_TOP);
#     Confidence::buildList($q, $s, $dbt,$hbo,{});
#     print $hbo->stdIncludes($PAGE_BOTTOM);
# }

sub displayStratTaxaForm{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    return if PBDB::PBDBUtil::checkForBot();
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Confidence::displayStratTaxa($q, $s, $dbt);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

sub showOptionsForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    return if PBDB::PBDBUtil::checkForBot();
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Confidence::optionsForm($q, $s, $dbt);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

sub calculateTaxaInterval {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    return if PBDB::PBDBUtil::checkForBot();

    logRequest($s,$q);

    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Confidence::calculateTaxaInterval($q, $s, $dbt);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

sub calculateStratInterval {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    return if PBDB::PBDBUtil::checkForBot();
    
    logRequest($s,$q);

    my $output= $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Confidence::calculateStratInterval($q, $s, $dbt);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

## Cladogram stuff

sub displayCladeSearchForm	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= $hbo->populateHTML('search_clade_form');
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;

	#print $hbo->stdIncludes($PAGE_TOP);
    #PBDB::Cladogram::displayCladeSearchForm($dbt,$q,$s,$hbo);
	#print $hbo->stdIncludes($PAGE_BOTTOM);
}
#sub processCladeSearch	{
#	print $hbo->stdIncludes($PAGE_TOP);
#    PBDB::Cladogram::processCladeSearch($dbt,$q,$s,$hbo);
#	print $hbo->stdIncludes($PAGE_BOTTOM);
#}
sub displayCladogramChoiceForm	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Cladogram::displayCladogramChoiceForm($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

sub displayCladogramForm	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Cladogram::displayCladogramForm($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    return $output;
}

sub submitCladogramForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Cladogram::submitCladogramForm($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

sub drawCladogram	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    my $cladogram_no = $q->numeric_param('cladogram_no');
    my $force_redraw = $q->param('force_redraw');
    my ($pngname, $caption, $taxon_name) = PBDB::Cladogram::drawCladogram($dbt,$cladogram_no,$force_redraw);
    if ($pngname) {
        $output .= qq|<div align="center"><h3>$taxon_name</h3>|;
        $output .= qq|<img src="/public/cladograms/$pngname"><br>$caption|;
        $output .= qq|</div>|;
    }
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

# JA 17.1.10
sub displayReviewForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Review::displayReviewForm($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

sub processReviewForm {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Review::processReviewForm($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

sub listReviews	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Review::listReviews($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

sub showReview	{
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Review::showReview($dbt,$q,$s,$hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);

    return $output;
}

# Displays taxonomic opinions and names associated with a reference_no
# PS 10/25/2004
sub displayTaxonomicNamesAndOpinions {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes( $PAGE_TOP );
    my $ref = PBDB::Reference->new($dbt,$q->numeric_param('reference_no'));
    if ($ref) {
        $q->param('goal'=>'authority');
        if ( $q->param('display') ne "opinions" )	{
            $output .= processTaxonSearch($q, $s, $dbt, $hbo);
        }
        elsif ( $q->param('display') ne "authorities" )	{
            $output .= PBDB::Opinion::displayOpinionChoiceForm($q, $s, $dbt, $hbo);
        }
    } else {
        $output .=  "<div align=\"center\">".PBDB::Debug::printErrors(["No valid reference supplied"])."</div>";
    }
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    return $output;
}



sub logRequest {
    
    my ($q, $s, $dbt, $hbo) = @_;

    return;
}

#     # my ($s,$q) = @_;
    
#     if ( $HOST_URL !~ /paleobackup\.nceas\.ucsb\.edu/ && $HOST_URL !~ /paleodb\.org/ )  {
#         return;
#     }
#     my $status = open LOG, ">>/var/log/apache2/request_log";
#     if (!$status) {
#         $status = open LOG, ">>/var/log/httpd/request_log";
#     }
#     if (!$status) {
#         carp "Could not open request_log";
#     } else {
#         my $date = now();

#         my $ip = $ENV{'REMOTE_ADDR'};
#         $ip ||= 'localhost';

#         my $user = $s->get('enterer');
#         if (!$user) { $user = 'Guest'; }

#         my $postdata = "";
#         my @fields = $q->param();
#         foreach my $field (@fields) {
#             my @values = $q->param($field);
#             foreach my $value (@values) {
#                 if ($value !~ /^$/) {
#                     # Escape these to make it easier to parse later
#                     $value =~ s/&/\\A/g;
#                     $value =~ s/\\/\\\\/g;
#                     $postdata .= "$field=$value&";
#                 }
#             }
#         } 
#         $postdata =~ s/&$//;
#         $postdata =~ s/[\n\r\t]/ /g;

#         # make the file "hot" to ensure that the buffer is flushed properly.
#         # see http://perl.plover.com/FAQs/Buffering.html for more info on this.
#         my $ofh = select LOG;
#         $| = 1;
#         select $ofh;

#         my $line = "$ip\t$date\t$user\t$postdata\n";
#         print LOG $line;
#     }
# }

# These next functin simply provide simple links to all of our taxon/collection pages
# so they can be indexed by search engines
sub listCollections {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes ($PAGE_TOP);
    my $sql = "SELECT MAX(collection_no) max_id FROM collections";
    my $page = int($q->param("page"));

    my $max_id = ${$dbt->getData($sql)}[0]->{'max_id'};
   
    for(my $i=0;$i*200 < $max_id;$i++) {
        if ($page == $i) {
            $output .= "$i ";
        } else {
            $output .= makeAnchor("listCollections", "page=$i", "$i");
        }
    }
    $output .= "<BR><BR>";
    my $start = $page*200;
    for (my $i=$start; $i<$start+200 && $i <= $max_id;$i++) {
        $output .= makeAnchor("basicCollectionSearch", "collection_no=$i", "$i");
    }

    $output .= $hbo->stdIncludes ($PAGE_BOTTOM);
    return $output;
}

sub listTaxa {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes ($PAGE_TOP);
    
    my $sql = "SELECT MAX(taxon_no) max_id FROM authorities";
    my $page = int($q->param("page"));

    my $max_id = ${$dbt->getData($sql)}[0]->{'max_id'};
   
    for(my $i=0;$i*200 < $max_id;$i++) {
        if ($page == $i) {
            $output .= "$i ";
        } else {
            $output .= makeAnchor("listCollections", "page=$i", "$i");
        }
    }
    $output .= "<BR><BR>";
    my $start = $page*200;
    for (my $i=$start; $i<$start+200 && $i <= $max_id;$i++) {
        $output .= makeAnchor("basicTaxonInfo", "taxon_no=$i", "$i");
    }

    $output .= $hbo->stdIncludes ($PAGE_BOTTOM);
    return $output;
}


sub showArchive {

    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = $hbo->stdIncludes($PAGE_TOP);
    $output .= PBDB::Archive::showArchive($q, $s, $dbt, $hbo);
    $output .= $hbo->stdIncludes($PAGE_BOTTOM);
    
    return $output;
}


sub requestDOI {

    my ($q, $s, $dbt, $hbo) = @_;
    
    my $output = PBDB::Archive::requestDOI($q, $s, $dbt, $hbo);
    
    return $output;
}


sub emailList {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    unless ( $s->isSuperUser )
    {
	ouch("401", "You are not authorized to retrieve that information");
    }
    
    my $list_title = '';
    my $prefix = '';
    my $filter = '1=1';
    
    my $status_filter = $q->param('status') || 'active';
    
    if ( $status_filter eq 'active' )
    {
	$filter = "u.contributor_status='active'";
    }
    
    elsif ( $status_filter eq 'inactive' )
    {
	$filter = "u.contributor_status!='active'";
	$prefix = "Inactive ";
    }
    
    elsif ( $status_filter eq 'all' )
    {
	$prefix = "Active and inactive ";
    }
    
    else
    {
	ouch("400", "Invalid value '$status_filter' for parameter 'status'");
    }
    
    my $role_filter = $q->param('role') || 'all';
    
    if ( $role_filter eq 'contributor' )
    {
	$list_title = $prefix ? "$prefix database contributors" : "Database contributors";
	$filter .= " and u.role not in ('guest')";
    }
    
    elsif ( $role_filter eq 'guest' )
    {
	$list_title = $prefix ? "$prefix database guests" : "Database guests";
	$filter .= " and u.role in ('guest')";
    }
    
    elsif ( $role_filter eq 'all' )
    {
	$list_title = $prefix ? "$prefix database contributors and guests" :
	    "Database contributors and guests";
    }
    
    else
    {
	ouch("400", "Invalid value '$role_filter' for parameter 'role'");
    }
    
    
    if ( my $last_login = $q->param('last_login') )
    {
	if ( $last_login =~ /^\d+$/ )
	{
	    my $days = $last_login * 31;
	    $list_title .= " who have logged in within the past $last_login months";
	    $filter .= " and datediff(curdate(), u.last_login) <= '$days'";
	}
	
	else
	{
	    ouch("400", "Invalid value '$last_login' for parameter 'last_login'");
	}
    }
    
    my $format = $q->param('format') || 'text';
    
    my $dbh = $dbt->dbh;
    
    if ( $format eq 'text' )
    {
	my $sql = "SELECT real_name, email
		   FROM pbdb_wing.users as u WHERE $filter";
	
	my $result = $dbh->selectall_arrayref($sql, { Slice => { } });
	
	my $output = $hbo->stdIncludes($PAGE_TOP);
	
	$output .= "<div style=\"margin-left: 30px\">\n";
	
	$output .= "<p class=\"heading1\">$list_title</p>\n\n<p>";
	
	if ( ref $result eq 'ARRAY' && @$result )
	{
	    foreach my $row ( @$result )
	    {
		my $name = $row->{real_name};
		my $email = $row->{email};
		
		$output .= encode_entities("$name <$email>, ");
	    }
	}
	
	else
	{
	    $output .= "No matching users were found";
	}
	
	$output .= "</p>\n\n</div>\n\n";
	
	$output .= $hbo->stdIncludes($PAGE_BOTTOM);
	
	$hbo->pageTitle('PBDB Email List');
	
	return $output;
    }
    
    elsif ( $format eq 'csv' )
    {
	my $sql = "SELECT u.real_name, u.email, u.role, u.person_no, u.admin,
			  u.institution, u.country, u.authorizer_no, p.real_name as authorizer, 
			  u.contributor_status as status, date(u.last_login) as last_login
		   FROM pbdb_wing.users as u 
			left join pbdb_wing.users as p on p.person_no = u.authorizer_no
		   WHERE $filter";
	
	my $result = $dbh->selectall_arrayref($sql, { Slice => { } });
	
	unless ( ref $result eq 'ARRAY' && @$result )
	{
	    ouch(400, "No results were found");
	}
	
	$q->param('output_format', 'csv');
	
	my $output = qq{"Name","Email","Role","PBDB number","PBDB authorizer",} .
	    qq{"Country","Institution","Last login","$list_title"\n};
	
	foreach my $row ( @$result )
	{
	    my $name = $row->{real_name} || '';
	    my $email = $row->{email} || '';
	    my $role = $row->{role} || '';
	    my $status = $row->{status} || '';
	    my $person_no = $row->{person_no} || '';
	    my $authorizer = $row->{authorizer} || '';
	    my $institution = $row->{institution} || '';
	    my $country = $row->{country} || '';
	    my $last_login = $row->{last_login} || '';
	    
	    $name =~ s{(['"])}{\\$1}g;
	    $email =~ s{(['"])}{\\$1}g;
	    
	    if ( $row->{admin} )
	    {
		$role .= "/administrator";
	    }
	    
	    if ( $status_filter ne 'active' )
	    {
		$role .= " ($status)";
	    }
	    
	    $authorizer = '' if $row->{authorizer_no} eq $row->{person_no};
	    
	    $output .= qq{"$name","$email","$role","$person_no","$authorizer",} .
		qq{"$country","$institution","$last_login"\n};
	}
	
	return $output;
    }
    
    else
    {
	ouch(400, "Invalid format '$format'");
    }
}


package PBDB::Request;

use URI::Escape;
use ExternalIdent qw(%IDRE);

our %IDTYPE = ( collection_no => $IDRE{COL},
		occurrence_no => $IDRE{OCC},
		reidentification_no => $IDRE{REI},
		specimen_no => $IDRE{SPM},
		measurement_no => $IDRE{MEA},
		taxon_no => $IDRE{TID},
		opinion_no => $IDRE{OPN},
		reference_no => $IDRE{REF},
		interval_no => $IDRE{INT},
		scale_no => $IDRE{TSC},
		person_no => $IDRE{PRS},
		authorizer_no => $IDRE{PRS},
		enterer_no => $IDRE{PRS},
		modifier_no => $IDRE{PRS} );


sub new {

    my ($class, $request_method, $params_ref, $uri, $cookies) = @_;
    
    my ($path, $query_string) = split qr{\?}, $uri;
    
    my $request = { params => $params_ref,
		    path => $path,
		    cookies => $cookies,
		    request_method => $request_method,
		    query_string => $query_string };
    
    if ( ref $params_ref eq 'HASH' )
    {
	foreach my $k ( keys $params_ref->%* )
	{
	    if ( $IDTYPE{$k} && $params_ref->{$k} =~ $IDTYPE{$k} )
	    {
		$params_ref->{$k} = $2;
	    }
	}
    }
    
    return bless $request;
}


sub reset_params {
    
    my ($request, $params_ref) = @_;
    
    return unless ref $params_ref eq 'HASH';
    
    $request->{params} = $params_ref;
    
    my $action = $params_ref->{a} || $params_ref->{action};
    
    $request->{path} = "/classic/$action";
    
    my $query_string = '';
    
    foreach my $key ( keys %$params_ref )
    {
	my $value = $params_ref->{$key} || '';
	
	$query_string .= '&' if $query_string;
	$query_string .= "$key=";
	$query_string .= uri_escape_utf8($value // '');
    }
    
    $request->{query_string} = $query_string;
    
    return $params_ref->{a} || $params_ref->{action} || 'menu';
}


sub param {
    
    my ($request, $name, @values) = @_;
    
    if ( @values )
    {
	if ( @values > 1 )
	{
	    $request->{params}{$name} = \@values;
	    return @values;
	}
	else
	{
	    $request->{params}{$name} = $values[0];
	    return $values[0];
	}
    }
    
    elsif ( defined $name )
    {
	if ( ref $request->{params}{$name} eq 'ARRAY' )
	{
	    if ( wantarray )
	    {
		return @{$request->{params}{$name}};
	    }

	    else
	    {
		return $request->{params}{$name}[0];
	    }
	}
	
	else
	{
	    return $request->{params}{$name};
	}
    }
    
    else
    {
	return keys %{$request->{params}};
    }
}


sub numeric_param {

    my ($request, $name) = @_;
    
    my $value;
    
    if ( defined $name )
    {
	if ( ref $request->{params}{$name} eq 'ARRAY' )
	{
	    $value = $request->{params}{$name}[0];
	}
	
	else
	{
	    $value = $request->{params}{$name};
	}
    }
    
    if ( defined $value && $value =~ /^(-?\d+)/ )
    {
	return $1;
    }
    
    else
    {
	return '';
    }
}


sub Vars {
    
    my ($request) = @_;
    
    return wantarray ? %{$request->{params}} : $request->{params};
}


sub query_string {
    
    my ($request) = @_;
    
    return $request->{query_string};
}


sub path_info {

    my ($request) = @_;
    
    return $request->{path};
}


sub charset {

    my ($request) = @_;
    
    return Dancer::request->content_type;
}


sub cookie {
    
    my ($request, $key) = @_;
    
    my $cookie = $request->{cookies}{$key};
    
    if ( $cookie )
    {
	return $cookie->value;
    }
    
    else
    {
	return;
    }
}


sub request_method {

    my ($request) = @_;

    return $request->{request_method};
}


sub list_params {

    my ($request) = @_;
    
    return unless ref $request->{params} eq 'HASH';
    
    my $output = '';
    
    foreach my $k ( sort keys %{$request->{params}} )
    {
	my $v = $request->{params}{$k} || '';
	
	my @values = ref $v eq 'ARRAY' ? @$v : $v;
	
	foreach my $value ( @values )
	{
	    $output .= "$k=$value\n";
	}
	
	# $output .= "$k=$request->{params}{$k}\n";
    }
    
    return $output;
}


sub save {
    
    my ($request, $save_fh) = @_;
    
    foreach my $k ( sort keys %{$request->{params}} )
    {
	my $v = $request->{params}{$k} || '';
	
	my @values = ref $v eq 'ARRAY' ? @$v : $v;
	
	foreach my $value ( @values )
	{
	    my $encoded = uri_escape_utf8($value // '');
	    print $save_fh "$k=$encoded\n";
	}
    }
    
    print $save_fh "=\n";
}

1;
