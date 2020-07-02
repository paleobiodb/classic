#!/opt/local/bin/perl

=head1 SYNOPSIS

  code_update_d.pl [options] directory ...
  
  Options:
  
    --check-interval=n
        Wait at least n seconds between checks (defaults to 3)
    
    --update-interval=n
        Wait at least n seconds between updates (defaults to 30)
    
    --subdir=name
        Look for the trigger and log files in the named subdirectory of each
        specified directory (defaults to 'update')
    
    --trigger=name
        The name to use for the trigger file (defaults to 'code_update_trigger')
    
    --log=name
        The name to use for the log file (defaults to 'code_update_log')
    
    --cmd=name
        The full pathname of the Git command to use (defaults to 'git')
    
    --make-trigger=filename
        Write a trigger script to the specified file.  The filename is
        interpreted relative to the specified directory.  All other options
        should be specified identically to when this program is run as a
        daemon.

=head1 DESCRIPTION

code_update_d.pl is designed to be run as a daemon, providing a secure way for
updates to be carried out on web application code from a remote location,
without anyone having to log in to the web server.

For the purpose of security, the webserver code and associated files should be
owned by a userid other than the one under which the web server process runs
(typically _www).  The only files and directories that should be owned by _www
are those which need to be modified by the server or the application code
during the normal course of operations (i.e. a directory for file uploads).
This way, even if the server or one of the cgi programs is somehow compromised
it will not be able to alter the web application code, the HTML template
files, the images, etc.

This script should be run under the userid which owns the application files.
Its arguments should be pathnames of directories that are git repositories.
Every few seconds it looks for a particular trigger file in each repository.
Note that the directory in which this file is to be placed must be writeable
by _www (easiest to make it world-writeable) in order for the trigger
mechanism to work.  By default, that directory is named 'update'.  Whenever a
trigger file is found, this program deletes it, executes 'git pull origin
master', and appends the output to a log file in the same directory.

The companion to this script is 'remote_update.pl', which should be installed
in /cgi-bin/ or some other location where it can be triggered by an HTTP
request.  That program (running under the same userid as the web server,
typically _www) does nothing but create the trigger file and then report any
output that is appended to the log file.  This mechanism allows anyone to
trigger a code pull, in a way that prevents them from misusing the trigger
program to do anything else.  Since the trigger program runs under _www, it
has no more privileges than any other CGI program, and is carefully written to
do nothing harmful no matter what arguments are passed to it.  Note that for
this reason you should not customize it in any way except to hard-code the
proper path names.

In order to limit the opportunity for denial-of-service attacks (or
programming errors which might have the same effect) 'git pull' will not be
executed until a minimum interval has elapsed since the previous execution.
This interval can be set by the --update-interval option.

If the 'make-trigger' option is specified, then the program will write a
trigger script to the specified filename (relative to the specified directory)
and exit.  All options should be specified just as they will be when the
program is run as a daemon.

=head1 AUTHOR

Michael McClennen <mmcclenn@geology.wisc.edu>

=cut

use strict;
use IO::Handle;
use Getopt::Long;
use Pod::Usage;

our ($VERSION) = 0.1;


# Start by checking for options, if any.

# Options include:

# Directory (relative to the repository root) where the files are located

my ($UPDATE_DIRNAME) = 'update';

# Name of the update trigger file

my ($TRIGGER_FILENAME) = 'code_update_trigger';

# Name of the update log file

my ($LOG_FILENAME) = 'code_update_log';

# Interval between checks for the trigger file (in seconds):

my ($CHECK_INTERVAL) = 3;

# Minimum interval between code updates (in seconds):

my ($UPDATE_INTERVAL) = 30;

# Refresh interval for trigger script (in seconds):

my ($REFRESH_INTERVAL) = 2;

# Command to use

my ($GIT_COMMAND) = 'git';

# Other options

my ($help, $man, $version, $trigger_filename, $DEBUG);


GetOptions('help' => \$help,
	   'man' => \$man,
	   'version' => \$version,
	   'debug' => \$DEBUG,
	   'make-trigger=s' => \$trigger_filename,
	   'check-interval=i' => \$CHECK_INTERVAL,
	   'update-interval=i' => \$UPDATE_INTERVAL,
	   'subdir=s' => \$UPDATE_DIRNAME,
	   'trigger=s' => \$TRIGGER_FILENAME,
	   'log=s' => \$LOG_FILENAME,
	   'cmd=s' => \$GIT_COMMAND)
    or pod2usage(2);

pod2usage(-exitval => 0, -verbose => 0) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;
if ( $version )
{
    print STDOUT "Version: $VERSION\n";
    exit;
}
if ( $trigger_filename )
{
    make_trigger($trigger_filename);
    exit;
}

print STDOUT "PaleoDB update daemon STARTING\n";

# Then parse the remaining argument list to determine the list of repositories
# to monitor.  Check each one to make sure that we can write to the update
# directory and append to the log file, and actually open each log file for
# appending.

my $DONE;
my @CHECK_LIST;

foreach my $dir (@ARGV)
{
    # Check to make sure that we have the necessary access to the specified
    # directory and its subdirectories.  Check, also, for the existence of
    # .git since this command won't work unless the directory is a Git
    # repository.
    
    unless ( -e $dir )
    {
	print STDOUT "ERROR: not found: $dir\n";
	next;
    }
    
    unless ( -r $dir )
    {
	print STDOUT "ERROR: cannot read from: $dir\n";
	next;
    }
    
    unless ( -r "$dir/.git" )
    {
	print STDOUT "ERROR: not a git repository: $dir\n";
	next;
    }
    
    my ($update_dir) = "$dir/$UPDATE_DIRNAME";
    
    unless ( -e $update_dir )
    {
	print STDOUT "ERROR: not found: $update_dir\n";
	next;
    }
    
    unless ( -w $update_dir )
    {
	print STDOUT "ERROR: cannot write to: $update_dir\n";
	next;
    }
    
    # Open the log file, and set autoflush to true.  This makes sure that log
    # messages are always promptly flushed to disk, which is necessary in
    # order that our companion CGI script can read them.
    
    my ($log_file) = "$update_dir/$LOG_FILENAME";
    my $log_fh;
    
    unless ( open($log_fh, ">>", $log_file) )
    {
	print STDOUT "ERROR: cannot append to: $log_file: $!\n";
	next;
    }
    
    $log_fh->autoflush(1);
    
    # Write to the main log file for this daemon (which should be hooked up to
    # standard out) and add this directory to our check-list.
    
    print STDOUT "Monitoring directory $dir\n";
    print STDOUT "    Trigger file: $update_dir/$TRIGGER_FILENAME\n";
    print STDOUT "    Log file: $log_file\n";
    
    push @CHECK_LIST, {
	       dir => $dir,
	       log_fh => $log_fh,
	       last => 0,
	};
}


# If none of the specified directories passed all of the above tests, there's no
# point in continuing.

unless (@CHECK_LIST)
{
    print STDOUT "FATAL ERROR: no valid directories to monitor\n";
    $DONE = 1;
}


# Catch any TERM signal, so we'll know if we are requested to stop.

$SIG{TERM} = \&catch_term;


# Now start looping, checking for the trigger file in each of the specified
# directories.  Sleep for the indicated amount of time between checks.

while ( ! $DONE )
{
    foreach my $record (@CHECK_LIST)
    {
	doUpdate($record);
    }
    
    sleep($CHECK_INTERVAL);
}

# If we get here, then we've been told to be done.

print STDOUT "PaleoDB update daemon ENDING.\n";
exit;


# doUpdate ( record )
# 
# Do a 'git pull origin master' on the specified directory and write the
# results to the specified log file.

sub doUpdate {
    
    my ($record) = @_;
    	
    my ($dir) = $record->{dir};
    my ($log_fh) = $record->{log_fh};
    my ($last_update) = $record->{last};
    
    my ($trigger_filename) = "$dir/$UPDATE_DIRNAME/$TRIGGER_FILENAME";
    
    print STDOUT "CHECKING FOR $trigger_filename...\n" if $DEBUG;
    
    unless ( -e $trigger_filename && time - $last_update > $UPDATE_INTERVAL && ! $record->{suppress} )
    {
	return;
    }
    
    unless ( chdir $record->{dir} )
    {
	print STDOUT "ERROR: could not change directory to $record->{dir}: $!\n";
	print STDOUT "    Removing $record->{dir} from the monitoring list\n";
	$record->{suppress} = 1;
	return;
    }
    
    unless ( unlink($trigger_filename) )
    {
	print STDOUT "ERROR: could not unlink $trigger_filename: $!\n";
	print STDOUT "    Removing $record->{dir} from the monitoring list.\n";
	$record->{suppress} = 1;
	return;
    }
    
    $record->{last} = time;
    
    print STDOUT "PaleoDB update daemon: updating $record->{dir}\n";
    print STDOUT "    at " . localtime . "\n";
    
    print $log_fh "\nUPDATE AT " . localtime . "\n\n";
    
    my ($git_fh);
    
    unless ( open($git_fh, "-|", "$GIT_COMMAND pull origin master 2>&1") )
    {
	print STDOUT "ERROR: could not run $GIT_COMMAND: $!\n";
	print $log_fh "ERROR: could not run $GIT_COMMAND: $!\n";
	print $log_fh "\n[UPDATE INCOMPLETE]\n";
	return;
    }
    
    while ( defined(my $line = <$git_fh>) )
    {
	print $log_fh $line;
    }
    
    close $git_fh;
    
    print "DONE\n\n" if $DEBUG;
    print $log_fh "\n[UPDATE COMPLETE AT " . localtime . "]\n";
}


# catch_term ( )
# 
# This function responds to a TERM signal by setting the $DONE flag, which
# will cause the main loop to terminate the next time through.

sub catch_term {

    $DONE = 1;
}


# make_trigger ( filename )
# 
# This function generates a trigger script, based on the given options.

sub make_trigger {

    my ($filename) = @_;
    
    my $base_text = '';
    my $incomplete_count = int(1.5 * $UPDATE_INTERVAL / $REFRESH_INTERVAL);
    
    die "Error: update interval is too small\n" unless $incomplete_count > 1;
    $incomplete_count = 10 unless $incomplete_count > 10;
    
    # First generate the base text.
    
    while ( <DATA> )
    {
	$base_text .= $_;
    }
    
    close DATA;
    
    $base_text =~ s/<<PERL>>/$^X/g;
    $base_text =~ s/<<THIS_PROG>>/$0/g;
    $base_text =~ s/<<UPDATE_DIRNAME>>/$UPDATE_DIRNAME/g;
    $base_text =~ s/<<TRIGGER_FILENAME>>/$TRIGGER_FILENAME/g;
    $base_text =~ s/<<LOG_FILENAME>>/$LOG_FILENAME/g;
    $base_text =~ s/<<REFRESH_INTERVAL>>/$REFRESH_INTERVAL/g;
    $base_text =~ s/<<INCOMPLETE_COUNT>>/$incomplete_count/g;
    
    # Now go through each specified directory and create the file.
    
    foreach my $dir (@ARGV)
    {
	my $script_fh;
	my $script_file = $filename =~ qr{^/} ? $filename : "$dir/$filename";
	my $script_text = $base_text;
	
	$script_text =~ s/<<BASE_DIR>>/$dir/g;
	
	unless ( open( $script_fh, ">", $script_file ) )
	{
	    print STDOUT "ERROR: could not write to $script_file: $!\n";
	    next;
	}
	
	print $script_fh $script_text;
	
	unless ( close $script_fh )
	{
	    print STDOUT "ERROR: closing $script_file: $!\n";
	    next;
	}
	
	else
	{
	    system("chmod +x $script_file");
	    print STDOUT "Created trigger script: $script_file\n";
	}
    }
    
    exit;
}


# The rest of this file contains the base text from which the remote
# invocation script will be generated by make_trigger().

__DATA__
#!<<PERL>>

# The purpose of this script is to trigger a code update when invoked in
# response to an HTTP request.
# 
# This script was generated by <<THIS_PROG>>.
# See that program for more details.

use strict;
use IO::Handle;

# CONSTANTS:

# Directory (relative to the root of the current repository) where the files are located

my ($UPDATE_DIRNAME) = '<<UPDATE_DIRNAME>>';

# Name of the update trigger file

my ($TRIGGER_FILENAME) = '<<TRIGGER_FILENAME>>';

# Name of the update log file

my ($LOG_FILENAME) = '<<LOG_FILENAME>>';

# Number of seconds to wait between log checks

my ($REFRESH_INTERVAL) = '<<REFRESH_INTERVAL>>';

# Number of query cycles to wait before we report an incomplete outcome.
# (This should amount to approximately 1 minute).

my ($INCOMPLETE_COUNT) = '<<INCOMPLETE_COUNT>>';

# Base directory of this repository.

my ($BASE_DIR) = '<<BASE_DIR>>';

# Now determine the necessary path names.

my ($trigger_filename) = "$BASE_DIR/$UPDATE_DIRNAME/$TRIGGER_FILENAME";
my ($log_filename) = "$BASE_DIR/$UPDATE_DIRNAME/$LOG_FILENAME";

# Check for the script name and query arguments.  If we find "mark=" then we
# check to see if anything has been added to the log file after the indicated
# byte.  Otherwise, we trigger an update.

my ($URL_PATH) = $ENV{SCRIPT_NAME};

if ( $ENV{QUERY_STRING} =~ /mark=(\d+)/ )
{
    my $log_mark = $1;
    my $query_count;
    
    if ( $ENV{QUERY_STRING} =~ /count=(\d+)/ )
    {
	$query_count = $1;
    }
    
    query_update_progress($log_mark, $query_count + 1);
    exit;
}

else
{
    trigger_update();
    exit;
}


# trigger_update ( )
# 
# Create the trigger file that will tell code_update_d to execute a 'git pull'
# operation.

sub trigger_update {

    # Look for the log file.  If we find one, note its current size.
    
    my ($current_log_size) = -s $log_filename || 0;
    
    # Create the trigger file.
    
    my $trigger_fh;
    
    unless ( open($trigger_fh, ">", $trigger_filename) )
    {
	print_error_response("Cannot create create trigger file: $!");
	return;
    }
    
    close $trigger_fh;
    
    # Now send a response page indicating that the trigger has been created.
    # This page will refresh to display the state of the update until it is
    # complete.
    
    print_update_response('', $current_log_size, 0);
    return;
}


# query_update_progress ( log_mark )
# 
# Look in the log file, starting at the position indicated by $log_mark, to
# see whether the update has progressed.  Print out a response indicating the
# progress, if any.  If the update has not yet completed, the resulting page
# will include a Refresh header.

sub query_update_progress {

    my ($log_mark, $query_count) = @_;
    
    my $log_fh;
    my $log_contents = '';
    
    unless ( open($log_fh, "<", $log_filename) )
    {
	print_error_response("Cannot open log file: $!");
	return;
    }
    
    seek($log_fh, $log_mark, 0);
    
    while (<$log_fh>)
    {
	$log_contents .= $_;
    }
    
    close $log_fh;
    
    if ( $log_contents =~ /^\[UPDATE /m )
    {
	print_done_response($log_contents);
	return;
    }
    
    elsif ( $query_count >= $INCOMPLETE_COUNT )
    {
	print_incomplete_response($log_contents);
	return;
    }
    
    else
    {
	print_update_response($log_contents, $log_mark, $query_count);
	return;
    }
}


# print_trigger_response ( log_mark, progress_string )
# 
# Return a response to the user that will indicate that a code update has been
# triggered.  This page will refresh to the specified query until the update
# is complete.

sub print_update_response {

    my ($log_contents, $log_mark, $query_count) = @_;

    print <<END_UPDATE_RESPONSE;
Content-type: text/html
Refresh: $REFRESH_INTERVAL; url=$URL_PATH?mark=$log_mark&count=$query_count

<html>
<head><title>Code update waiting</title></head>
<body>
<h1>Code update has been triggered</h1>
<hr>
<pre id="logmessage">
$log_contents
</pre>
<p id="waiting">waiting...</p>
</body>
</html>
END_UPDATE_RESPONSE

}


# print_done_response ( progress_string )
# 
# Return a response to the user that will indicate that a code update has been
# completed.

sub print_done_response {

    my ($log_contents) = @_;

    print <<END_UPDATE_RESPONSE;
Content-type: text/html

<html>
<head><title>Code update done</title></head>
<body>
<h1>Code update complete</h1>
<hr>
<pre id="logmessage">
$log_contents
</pre>
<hr>
<h2><a href="$URL_PATH">Update again</a></h2>
</body>
</html>
END_UPDATE_RESPONSE

}


# print_incomplete_response ( progress_string )
# 
# Return a response to the user that will indicate that the code update has
# not completed after several seconds.

sub print_incomplete_response {

    my ($log_contents) = @_;

    print <<END_UPDATE_RESPONSE;
Content-type: text/html

<html>
<head><title>Code update incomplete</title></head>
<body>
<h1>Code update <u>incomplete</u></h1>
<hr>
<pre id="logmessage">
$log_contents
</pre>
<hr>
<h2><a href="$URL_PATH">Try again</a></h2>
</body>
</html>
END_UPDATE_RESPONSE

}



# print_error_response ( message )
# 
# Return an error response to the user who called this program.

sub print_error_response {

    my ($message) = @_;
    
    print <<END_ERROR_RESPONSE;
Content-type: text/html
Status: 500 Server error

<html>
<head><title>Code update: error</title>
</head>
<body>
<h1>An error occurred:</h1>
<h2>$message</h2>
<hr>
<h2><a href="$URL_PATH">Try again</a></h2>
</body>
</html>
END_ERROR_RESPONSE

}



