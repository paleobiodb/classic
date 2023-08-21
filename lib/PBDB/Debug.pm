# For debugging and error logging to log files
# originally written by rjp, 12/2004
#

use strict;

package PBDB::Debug;

use Exporter qw(import);

our @EXPORT_OK = qw(dbg save_request load_request log_request log_step
		    profile_request profile_end_request
		    printErrors printWarnings);


use PBDB::Constants qw(%CONFIG $LOG_REQUESTS $APP_DIR $CGI_DEBUG);

my $rlfh;

if ( $LOG_REQUESTS )
{
    if ( open $rlfh, ">>", "$APP_DIR/logs/request_log" )
    {
	$rlfh->autoflush(1);
	print STDERR "Logging requests to $APP_DIR/logs/request_log\n";
    }
    
    else
    {
	print STDERR "WARNING: Could not open $APP_DIR/logs/request_log for appending: $!\n";
    }
}


# Utility routines

sub printWarnings {
    my @msgs;
    if (ref $_[0]) {
        @msgs = @{$_[0]};
    } else {
        @msgs = @_;
    }
    my $return = "";
    if (scalar(@msgs)) {
        my $plural = (scalar(@msgs) > 1) ? "s" : "";
        $return .= "<br><div class=\"warningBox\">" .
              "<div class=\"warningTitle\">Warning$plural</div>";
        $return .= "<ul>";
        $return .= "<li class='boxBullet'>$_</li>" for (@msgs);
        $return .= "</ul>";
        $return .= "</div>";
    }
    return $return;
}

sub printErrors{
    my @msgs;
    if (ref $_[0]) {
        @msgs = @{$_[0]};
    } else {
        @msgs = @_;
    }
    my $return = "";
    if (scalar(@msgs)) {
        my $plural = (scalar(@msgs) > 1) ? "s" : "";
        $return .= "<br><div class=\"errorBox\">" .
              "<div class=\"errorTitle\">Error$plural</div>";
        $return .= "<ul>";
        $return .= "<li class='boxBullet'>$_</li>" for (@msgs);
        $return .= "</ul>";
        $return .= "</div>";
    }
    return $return;
}  

sub dbg {
    
    my ($message, $level);
    
    if ( $CONFIG{DEBUG} && $CONFIG{DEBUG} >= $level && $message )
    {
        print STDERR "DEBUG: $message\n";
	return $CONFIG{DEBUG};
    }
    
    return 0;
}


# The following routines log details about how long each request takes to process.

sub log_request {
    
    my ($action, $timestamp) = @_;
    
    if ( $rlfh )
    {
	my $datetime = localtime($timestamp);
	my $procid = sprintf("%5s", $$);
	print $rlfh "$procid : $datetime : START $action\n";
    }
}


sub log_step {
    
    my ($action, $step, $timestamp, $starttime) = @_;
    
    if ( $rlfh )
    {
	my $datetime = localtime($timestamp);
	my $procid = sprintf("%5s", $$);
	
	if ( $starttime )
	{
	    my $duration = $timestamp - $starttime;
	    print $rlfh "$procid : $datetime : $step $action ($duration secs)\n";
	}
	
	else
	{
	    print $rlfh "$procid : $datetime : $step $action\n";
	}
    }
}


sub profile_request {
    
    my ($action, $timestamp) = @_;
    
    if ( $ENV{NYTPROF} && $ENV{NYTPROF} =~ /start=no/ && DB->can('enable_profile') )
    {
	my $filename = "nytprof.$$.$action.out";
	if ( -d "drq" )
	{
	    $filename = "drq/$filename";
	}
	
	DB::enable_profile($filename);
	return $filename;
    }
    
    elsif ( $CONFIG{PROFILE_REQUESTS} )
    {
	my $filename = "request.$$.$action.out";
	if ( -d "drq" )
	{
	    $filename = "drq/$filename";
	}
	
	return $filename;
    }
    
    return;
}


sub profile_end_request {
    
    my ($filename, $starttime, $q) = @_;
    
    return unless $filename;
    
    my $duration = time - $starttime;
    my $threshold = $CONFIG{PROFILE_THRESHOLD} || 10;
    
    if ( DB->can('enable_profile') && $filename =~ /nytprof/ )
    {
	DB::finish_profile();
	unlink $filename if ! $starttime || $duration < $threshold;
    }
    
    if ( $q && $starttime && $duration >= $threshold )
    {
	my $savename = $filename;
	
	$savename =~ s/nytprof/request/;
	$savename =~ s/[.]out$/.$duration/;
	
	if ( open my $save_fh, '>', $savename )
	{
	    $q->save($save_fh);
	    
	    print $save_fh "session: " . $q->cookie('session_id') . "\n";
	    print $save_fh "method: " . $q->request_method . "\n";
	    print $save_fh "path_info: " . $q->path_info . "\n";
	    print $save_fh "duration: $duration\n";
	    
	    close $save_fh || print STDERR "Cannot close $savename: $!\n";
	}
	
	else
	{
	    print STDERR "Cannot open $savename: $!\n";
	}
    }
}


# The following routines are for saving and loading the CGI state.  This allows us to make
# a request using a web brower and then replay it under the Perl debugger.  To activate
# this system, set CGI_DEBUG = 1 in pbdb.conf.  This will cause the last 5 requests to be
# saved.  Then run bridge.pl with the number of the desired saved request: 1 = most
# recent, 2 = next-most, etc.  Note: this only works if the directory 'saves' exists
# inside the main pbdb directory.

# save_cgi ( q )
# 
# Save the CGI state for later use in debugging.

sub save_request {
    
    my ($q) = @_;
    
    # Do nothing unless the value of $CGI_DEBUG is greater than zero and the directory
    # $APP_DIR/saves exists. Return silently if either of these is not true.

    my $SAVE_DIR = "$APP_DIR/saves";
    
    return unless $CGI_DEBUG && -d $SAVE_DIR;
    
    my ($save_fh, $save_path);
    
    # If the 'debug_name' field has a value, use that name.
    
    if ( my $name = $q->param('debug_name') )
    {
	$save_path = ">$SAVE_DIR/$name.txt";
    }
    
    # Otherwise, rename each of the save files q<n>.txt for n=1,2...$CGI_DEBUG-1 to
    # q<n+1>.txt.
    
    else
    {
	for ( my $index = $CGI_DEBUG-1; $index > 0; $index-- )
	{
	    my $next = $index + 1;
	    rename("$SAVE_DIR/q$index.txt", "$SAVE_DIR/q$next.txt");
	}
	
	# Now save the CGI state, including the session cookie and path info, to
	# /saves/q1.txt
	
	$save_path = ">$SAVE_DIR/q1.txt";
    }
    
    # Prepare to write the save file.
    
    open($save_fh, $save_path) || die "can't open $save_path: $!";
    
    $q->save($save_fh);
    
    print $save_fh "session: " . $q->cookie('session_id') . "\n";
    print $save_fh "method: " . $q->request_method . "\n";
    print $save_fh "path_info: " . $q->path_info . "\n";
    
    close $save_fh || die "can't close $save_path: $!";
}


# load_request ( save_name, print )
# 
# Load the request state from a saved file. If $save_name is numeric, look for a file
# named "qn.txt" where n is the numeric argument. Otherwise, look for a file named
# "$save_name.txt". If the second argument is true, print out the lines in the state file.
# Return the saved request method, class, and query parameters. 

sub load_request {
    
    my ($search_arg, $print_request) = @_;
    
    my $save_path = find_request($search_arg);
    
    die "No save file matches $search_arg\n" unless $save_path && -e $save_path;
    
    my ($save_fh, $line);
    
    open ($save_fh, '<', $save_path) || die "can't read $save_path: $!\n";
    
    my $state = 'ARGS';
    my $method = '';
    my $path = '';
    my $query = '';
    
 LINE:
    while ( defined($line = <$save_fh>) )
    {
	chomp $line;
	
	if ( $print_request )
	{
	    print "$line\n";
	}
	
	if ( $state eq 'ARGS' )
	{
	    if ( $line eq '=' )
	    {
		$state = 'VARS';
	    }
	    
	    elsif ( $line )
	    {
		$query .= '&' if $query ne '';
		$query .= $line;
	    }
	    
	    next LINE;
	}
	
	if ( $line =~ /^session: (.*)/ )
	{
	    $query .= '&' if $query ne '';
	    $query .= "session_id=$1";
	}
	
	elsif ( $line =~ /^path_info: (.*)/ )
	{
	    $path = $1;
	}
	
	elsif ( $line =~ /method: (.*)/ )
	{
	    $method = $1;
	}
    }
    
    return ($method, $path, $query);
}


sub list_request {
    
    my ($search_arg) = @_;
    
    my @save_paths = find_request($search_arg);
    
    die "No save file matches $search_arg\n" unless @save_paths;
    
    my ($save_fh, $line);
    
    foreach my $save_path ( @save_paths )
    {
	my $filename = $save_path;
	
	if ( $filename =~ qr{ / ( [^/]+ ) [.] txt $ }xs )
	{
	    $filename = $1;
	}
	
	unless ( open ($save_fh, '<', $save_path) )
	{
	    print "Cannot read $save_path: $!\n";
	    next;
	}
	
	my ($action, $arg, $session, %name, %no);
	
	while ( defined($line = <$save_fh>) )
	{
	    chomp $line;
	    
	    if ( $line =~ qr{ action = (\w+) }xs )
	    {
		$action = $1;
	    }
	    
	    elsif ( $line =~ qr{ ^session: \s (\S\S\S\S\S\S\S\S) }xs )
	    {
		$session = $1;
	    }
	    
	    elsif ( $line =~ qr{ (\w+ _no) = ([0-9-]+) }xs )
	    {
		$no{$1} = $2;
	    }
	    
	    elsif ( $line =~ qr{ (\w+ _name) = (\S+) }xs )
	    {
		$name{$1} = $2;
	    }
	}
	
	$action ||= 'unknown action';
	
	if ( keys %no == 1 )
	{
	    my ($key) = keys %no;
	    
	    $arg = "$key = $no{$key}";
	}
	
	elsif ( keys %name == 1 )
	{
	    my ($key) = keys %name;
	    
	    $arg = "$key = $name{$key}";
	}
	
	elsif ( keys %no )
	{
	    if ( $action =~ /tax/i && $no{taxon_no} )
	    {
		$arg = "taxon_no = $no{taxon_no}";
	    }
	    
	    elsif ( $action =~ /coll/i && $no{collection_no} )
	    {
		$arg = "collection_no = $no{collection_no}";
	    }
	    
	    elsif ( $action =~ /occ/i && $no{occurrence_no} )
	    {
		$arg = "occurrence_no = $no{occurrence_no}";
	    }
	    
	    elsif ( $action =~ /ref/i && $no{reference_no} )
	    {
		$arg = "reference_no = $no{reference_no}";
	    }
	    
	    elsif ( $action =~ /opin/i )
	    {
		if ( $no{opinion_no} && $no{opinion_no} > 0 )
		{
		    $arg = "opinion_no = $no{opinion_no}";
		}
		
		elsif ( $no{child_spelling_no} )
		{
		    $arg = "child_spelling_no = $no{child_spelling_no}";
		}
		
		elsif ( $no{child_no} )
		{
		    $arg = "child_no = $no{child_no}";
		}
	    }
	}
	
	my $line = "$filename - $action";
	
	if ( $arg )
	{
	    $line .= " $arg";
	}
	
	if ( $session )
	{
	    $line .= " ($session)";
	}
	
	print "$line\n";
    }
}


sub find_request {
    
    my ($search_arg) = @_;
    
    my $SAVE_DIR = "$APP_DIR/saves";
    
    # First check to see if the search argument matches any of the saved request files.
    # Check the argument alone and also with .txt as a suffix.
    
    if ( $search_arg )
    {
	if ( -e "$SAVE_DIR/$search_arg" )
	{
	    return "$SAVE_DIR/$search_arg";
	}
	
	if ( $search_arg !~ /[.]txt$/ && -e "$SAVE_DIR/$search_arg.txt" )
	{
	    return "$SAVE_DIR/$search_arg.txt";
	}
	
	if ( -e "$APP_DIR/$search_arg" )
	{
	    return "$APP_DIR/$search_arg";
	}
    }
    
    else
    {
	$search_arg = '.';
    }
    
    # Next, grep for the search term among all of the save files.
    
    my @result = `grep -il '$search_arg' $SAVE_DIR/*.txt`;
    
    @result = sort { my ($a1, $b1); 
		     if ( $a =~ /q(\d+)[.]txt/ ) { $a1 = $1; }
		     if ( $b =~ /q(\d+)[.]txt/ ) { $b1 = $1; }
		     if ( defined $a1 && defined $b1 ) { return $a1 <=> $b1 }
		     else { return $a1 cmp $b1 } } @result;
    
    # If we are asked for a list, 
    
    if ( wantarray )
    {
	my @list;
	
	foreach my $line ( @result )
	{
	    if ( $line =~ qr{ ( .+? [.] txt ) }xs )
	    {
		push @list, $1;
	    }
	}
	
	return @list;
    }
    
    elsif ( $result[0] && $result[0] =~ qr{ ( .+? [.] txt ) }xs )
    {
	return $1;
    }
    
    else
    {
	return;
    }
}
    

1;
