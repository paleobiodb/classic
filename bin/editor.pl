#!/usr/bin/env perl
# 
# The purpose of this program is to provide easy single-record editing for the
# Paleobiology Database, allowing for updating, deleting and insertion of
# records with consistency checks and writing the proper datalog entries.
# 
# This is intended to replace (for the most part) editing the database via the
# mysql command line, which in particular does not write datalog entries.


use strict;

use lib 'lib';
use lib 'pbdb-new/lib';

# use CoreFunction qw(connectDB);
use TaxonDefs qw(%RANK_STRING %TAXON_TABLE);
use TableDefs qw($OCC_MATRIX $OCCURRENCES $REIDS);
use TaxonTables qw(fixOpinionCache);
use OccurrenceTables qw(updateOccurrenceMatrix);

use PBDB::DBTransactionManager;
use PBDB::Session;

use Term::ReadLine;
# use Term::ReadPassword;
use Try::Tiny;
use Carp qw(carp croak);
use Storable;
use Getopt::Long;

my $PROMPT = "PBDB %> ";
my $CMD_COUNT = 1;
my $DONE;

my %HELPSTRING;
my %DEFAULT_SETTINGS = ( limit => 100, page => 10, display => 'short' );

my %DEBUG;
my %SETTINGS;
my %SELECTION;
my @SELECT_HIST;
my %LIST;
my %UNDO_SEL;

my $SESSION;
my $LOGIN_NO;

my $STATE_FILE = "$ENV{HOME}/.pbdb-state";
my $STORED = { };

my %COLUMN_INFO;
my %COLUMN_TYPE;

my %TABLE = (
    authorities => [ 'authorities', 'taxon_no' ],
    auth => [ 'authorities', 'taxon_no' ],
    authname => [ 'authorities', 'taxon_name' ],
    authorig => [ 'authorities', 'orig_no' ],
    opinions => [ 'opinions', 'opinion_no' ],
    op => [ 'opinions', 'opinion_no' ],
    oporig => [ 'opinions', 'orig_no' ],
    opname => [ 'opinions', 'taxon_name' ],
    taxon_trees => [ 'taxon_trees', 'orig_no' ],
    tt => [ 'taxon_trees', 'orig_no' ],
    t => [ 'taxon_trees', 'orig_no' ],
    taxa => [ 'taxon_trees', 'orig_no' ],
    ttname => [ 'taxon_trees', 'taxon_name' ],
    occurrences => [ 'occurrences', 'occurrence_no' ],
    occ => [ 'occurrences', 'occurrence_no' ],
    occtaxon => [ 'occurrences', 'taxon_no' ],
    occorig => [ 'occurrences', 'orig_no' ],
    occname => [ 'occurrences', 'taxon_name' ],
    reidentifications => [ 'reidentifications', 'reid_no' ],
    reid => [ 'reidentifications', 'reid_no' ],
    reocc => [ 'reidentifications', 'occurrence_no' ],
    collections => [ 'collections', 'collection_no' ],
    colls => [ 'collections', 'collection_no' ],
    collname => [ 'collections', 'collection_name' ],
    specimens => [ 'specimens', 'specimen_no' ],
    spec => [ 'specimens', 'specimen_no' ],
    specoccs => [ 'specimens', 'occurrence_no' ],
    specorig => [ 'specimens', 'orig_no' ],
    specname => [ 'specimens', 'taxon_name' ],
    references => [ 'refs', 'reference_no' ],
    ref => [ 'refs', 'reference_no' ],
    secondary_refs => [ 'secondary_refs', 'collection_no' ],
    secrefs => [ 'secondary_refs', 'collection_no' ],
    secref => [ 'secondary_refs', 'collectino_no' ],
    person => [ 'person', 'person_no' ],
    people => [ 'person', 'person_no' ],
    personname => [ 'person', 'name' ],
);

my %PRIMARY_KEY = (
    authorities => 'taxon_no',
    taxa_tree_cache => 'taxon_no',
    taxon_trees => 'orig_no',
    opinions => 'opinion_no',
    order_opinions => 'opinion_no',
    occurrences => 'occurrence_no',
    reidentifications => 'reid_no',
    collections => 'collection_no',
    specimens => 'specimen_no',
    refs => 'reference_no',
    person => 'person_no');

my %ACTION = (
    authorities => { query => \&query_auth, list => \&list_auth,
		     update => \&update_auth, delete => \&delete_auth,
		     aux_del => \&aux_del_auth, aux_add => \&aux_add_auth },
    taxon_trees => { query => \&query_tt, list => \&list_tt, update => \&update_tt,
		     unlink => \&unlink_tt },
    opinions => { query => \&query_ops, list => \&list_ops,
		  update => \&update_opinion, delete => \&delete_opinion,
		  aux_update => \&aux_update_opinion, aux_add => \&aux_update_opinion,
		  aux_del => \&aux_del_opinion },
    occurrences => { query => \&query_occs, list => \&list_occs,
		     update => \&update_occ, delete => \&delete_occ,
		     aux_update => \&aux_update_occ, aux_add => \&aux_add_occ,
		     aux_del => \&aux_del_occ },
    reidentifications => { query => \&query_reids, list => \&list_reids,
			   update => \&update_reid, delete => \&delete_reid,
			   aux_update => \&aux_update_occ, aux_add => \&aux_update_occ,
			   aux_del => \&aux_update_occ }
);

my %SELECTION_LABEL = ( AUTH => 'authorities',
			TT   => 'taxon_trees',
			SYN  => 'synonyms',
			CHLD => 'children',
			OPIN => 'opinions',
			COLL => 'collections',
			OCCS => 'occurrences',
			REID => 'reids',
			SPEC => 'specimens',
			MEAS => 'measurements',
			REFS => 'references',
			PERS => 'people',
		        NONE => 'records' );

my %PERSON;

# Create a new Term::ReadLine object, for our command loop.

my $TERM = Term::ReadLine->new('PBDB Editor');
my $OUT = $TERM->OUT || \*STDOUT;

sub print_msg ($);
sub print_line ($);

# Make a database connection and a DBTransactionManager object.

# my $DBH = connectDB();
my $DBT = PBDB::DBTransactionManager->new();
my $DBH = $DBT->{dbh};

# Make sure that we can write to the datalog file.

unless ( PBDB::DBTransactionManager::checkLogAccess )
{
    die "Could not write to the datalog file: $!\n";
}

# Try to load the saved state.

load_state();

# Parse the options list, if any

my ($opt_login);

GetOptions("login=s" => \$opt_login);

# Log in to the database. If we a login id was given on the command line, use that as the
# first try. Otherwise, if there is one saved in the state, try using that. But if it
# doesn't work, the user will be asked to enter a different one.

$SESSION = pbdb_login($opt_login || $LOGIN_NO);
$LOGIN_NO = $SESSION->{authorizer_no};

print_msg "\nYou are logged in as $SESSION->{authorizer}, person_no = $SESSION->{authorizer_no}:";

preload_people($DBH);

# If we have a command history list loaded from the saved state, add it to the
# Term::ReadLine object.

if ( ref $STORED->{HISTORY} eq 'ARRAY' )
{
    foreach my $h ( @{$STORED->{HISTORY}} )
    {
	$TERM->add_history($h);
    }
}

# Start the command loop, inside a try block so that we can save application state if
# a problem occurs.

try {
    while ( !$DONE )
    {
	my $prompt = $PROMPT;
	$prompt =~ s/%/$CMD_COUNT++/e;
	
	my $input = $TERM->readline($prompt);
	last unless defined $input;
	
	warn $@ if $@;
	
	try {
	    handle_command($input) if $input =~ /\S/;
	}
	    
	catch {
	    print_msg($_);
	};
    }
}

catch {
    save_state($TERM);
    die $_;
};


# If the command loop is ended explicitly by the user, save state and quit.

save_state($TERM);
print_msg "Done.";
exit;


# Main help

BEGIN {
    $HELPSTRING{main} = <<ENDHelp;

Available commands are:

  select        Select one or more records to operate on. This clears any previous selection.
  list          Displays matching records, but does not select them.
  add           Add to the current selection.
  clear         Clear the current selection.
  next          Display the next page of records from the selection or list.
  prev          Display the previous page of records from the selection or list.
  show          Show a specific record or records from the selection or list.
  set           Change an application setting, or display the current value one or more settings.
  debug         Set or clear various debugging flags.
  help          Display this message, or display specific help about any command.
  quit          Exit this program, saving the current state including the selection.

ENDHelp
}

# Handle a single command.

sub handle_command {

    my ($input) = @_;
    
    my ($command, $rest);
    
    if ( $input =~ qr{ ^ \s* (\S*) \s+ (.*) }xs )
    {
	$command = $1;
	$rest = $2;
	$rest =~ s/\s+$//;
    }
    
    else
    {
	$command = $input;
	$rest = '';
	
	$command =~ s/^\s+//;
    }
    
    return unless $command ne '';
    
    try {
	if ( $command =~ qr{ ^ h (elp)? $ }xsi )
	{
	    return do_help($rest);
	}
	
	elsif ( $command =~ qr{ ^ sel (ect)? $ }xsi )
	{
	    return do_select('select', $rest);
	}
	
	elsif ( $command =~ qr{ ^ add $ }xsi )
	{
	    return do_select('add', $rest);
	}
	
	elsif ( $command =~ qr{ ^ list $ }xsi )
	{
	    return do_select('list', $rest);
	}
	
	elsif ( $command =~ qr{ ^ n (ext)? $ }xsi )
	{
	    return do_page('next', $rest);
	}
	
	elsif ( $command =~ qr{ ^ p (rev (ious)?)? $ }xsi )
	{
	    return do_page('prev', $rest);
	}
	
	elsif ( $command =~ qr{ ^ show $ }xsi )
	{
	    return do_page('show', $rest);
	}
	
	elsif ( $command =~ qr{ ^ clear $ }xsi )
	{
	    return do_clear($rest);
	}
	
	# elsif ( $command =~ qr{ ^ d (el (ete)? )? $ }xsi )
	# {
	#     return do_delete($dbt, $session, $rest);
	# }
	
	# elsif ( $command =~ qr{ ^ unl (ink)? $ }xsi )
	# {
	#     return do_unlink($dbt, $session, $rest);
	# }
	
	# elsif ( $command =~ qr{ ^ i (ns (ert)? )? $ }xsi )
	# {
	#     return print_msg("INSERT: not yet implemented");
	#     # return do_insert($dbt, $session, $rest);	# still unimplemented
	# }
	
	# elsif ( $command =~ qr{ ^ u (pd (ate)? )? $ }xsi )
	# {
	#     return do_update($dbt, $session, 0, $rest);
	# }
	
	# elsif ( $command =~ qr{ ^ f (ix)? $ }xsi )
	# {
	#     return do_update($dbt, $session, 1, $rest);
	# }
	
	# elsif ( $command =~ qr{ ^ undo $ }xsi )
	# {
	#     return do_undo($dbt, $session, 1, $rest);
	# }
	
	# elsif ( $command =~ qr{ ^ redo $ }xsi )
	# {
	#     return do_undo($dbt, $session, 2, $rest);
	# }
	
	elsif ( $command =~ qr{ ^ set $ }xsi )
	{
	    return do_set($rest);
	}

	elsif ( $command =~ qr{ ^ show $ }xsi )
	{
	    return do_show($rest);
	}
	
	elsif ( $command =~ qr{ ^ deb (ug)? $ }xsi )
	{
	    return do_debug($rest);
	}
	
	# elsif ( $command =~ qr{ ^ clear $ }xsi )
	# {
	#     return do_clear($dbh, $rest);
	# }
	
	elsif ( $command =~ qr{ ^ q (uit)? $ }xsi )
	{
	    if ( $rest )
	    {
		print_line("UNKNOWN ARGUMENT '$rest' to command 'quit'");
		return;
	    }
	    
	    else
	    {
		$DONE = 1;
		return;
	    }
	}
	
	else
	{
	    return print_line "UNKNOWN COMMAND: $command";
	}
    }
    
    catch {
	print_msg $_;
    };
}


sub print_msg ($) {
    
    my ($msg) = @_;
    
    print $OUT "$msg\n\n";
}


sub print_line ($) {
    
    my ($line) = @_;
    
    print $OUT "$line\n";
}


sub print_string ($) {

    my ($string) = @_;

    print $OUT $string;
}


sub ask_yorn ($) {
    
    my ($prompt) = @_;
    
    while (1)
    {
	print $OUT "$prompt ";
	my $answer = <STDIN>;
	
	if ( $answer =~ /^y/i )
	{
	    return 1;
	}
	
	elsif ( $answer =~ /^n/i )
	{
	    return 0;
	}
	
	else
	{
	    $prompt = "Please answer Y or N:";
	}
    }
}


BEGIN {
    $HELPSTRING{debug} = <<ENDHelp;

Summary:

  debug OPTION

Options:

  sql           Turn on the display of SQL statements as they are executed.
  nosql         Turn off the display of SQL statements as they are executed.

ENDHelp
}

sub do_debug {
    
    my ($rest) = @_;
    
    if ( lc $rest eq 'sql' )
    {
	$DEBUG{sql} = 1;
    }
    
    elsif ( lc $rest eq 'nosql' )
    {
	$DEBUG{sql} = undef;
    }
    
    elsif ( lc $rest eq 'single' )
    {
	$DB::single = 1;
	my $a = 1;
    }
    
    elsif ( $rest )
    {
	print_msg "UNKNOWN ARGUMENT '$rest' to 'debug'";
    }
    
    else
    {
	foreach my $flag ( qw(sql) )
	{
	    my $value = $DEBUG{$flag} ? 'yes' : 'no';
	    print_line("  $flag: $value");
	}
    }
}


BEGIN {
    $HELPSTRING{set} = <<ENDHelp;

Summary:

  set SETTING [=] VALUE
  set [SETTING]

Change or display application settings. If a value is provided, the setting is changed.
The = sign is optional. If no value is given, the current value of the setting is
displayed.  If no arguments are given, the full liset of application settings is
displayed. Available settings are:

  page          The number of records that will be displayed at one time.
                Defaults to 10.
  
  display       The format in which records are displayed. This may be one of:
                short          The default
                space          An extra blank line is added between records
                long           Additional information is provided

ENDHelp
}

sub do_set {
    
    my ($rest) = @_;
    
    my @display_list;
    
    if ( $rest =~ qr{ ^ (\w+) (?: \s* [=] \s* | \s+ ) (.+) }xsi )
    {
	my $setting = $1;
	my $value = $2;
	
	if ( $setting eq 'page' )
	{
	    unless ( $value =~ qr{ ^ \d+ $ }xs && $value > 0 )
	    {
		print_msg "BAD VALUE '$value'";
		return;
	    }
	    
	    $SETTINGS{page} = $value;
	}
	
	elsif ( $setting eq 'display' )
	{
	    unless ( $value =~ qr{ ^ (?:short|long|space) $ }xsi )
	    {
		print_msg "BAD VALUE '$value'";
		return;
	    }
	    
	    $SETTINGS{display} = lc $value;
	}
	
	elsif ( exists $SETTINGS{$setting} )
	{
	    print_msg "ERROR: cannot set '$setting'";
	}
	
	else
	{
	    print_msg "ERROR: unknown setting '$setting'";
	}
	
	return;
    }
    
    elsif ( $rest =~ qr{ ^ (\w+) $ }xs )
    {
	my $setting = $1;
	
	if ( exists $SETTINGS{$setting} )
	{
	    @display_list = $setting;
	}
	
	else
	{
	    print_msg "UNKNOWN SETTING '$setting'";
	    return;
	}
    }
    
    elsif ( $rest =~ /\S/ )
    {
	print_msg "SYNTAX ERROR: '$rest'";
    }
    
    else
    {
	@display_list = sort keys %SETTINGS;
    }
    
    print_line "";
    
    foreach my $key ( @display_list )
    {
    	print_line "  $key = $SETTINGS{$key}";
    }
    
    print_line "";
}


BEGIN {
    $HELPSTRING{help} = <<ENDHelp;

Summary:

  help [TOPIC]

Display documentation about the specified command or topic.

ENDHelp
}

sub do_help {

    return display_help(@_);
}


BEGIN {
    $HELPSTRING{select} = <<ENDHelp;

Summary:

  select [TYPE] ARGS

When this command is given, the current selection is first cleared. If no type
is specified, the only allowed arguments are external identifiers.

Multiple arguments are accepted, separated by commas. Allowable arguments include strings,
which may be quoted if they contain commas or quotation marks; numbers, which are
interpreted as record identifiers if a record type is specified, and external identifiers.

Types:

  taxon|taxa|tx ARGS [rank=RANK]

    String arguments are matched against the 'taxon_name' field of the 'authorities'
    table. Identifiers are matched against the 'taxon_no' field. All matching taxa are selected,
    with all homonyms as the secondary selection. If a rank= option is specified, only taxa with
    the specified rank are selected. You can use the wildcards % and _ in string arguments.

  tt ARGS

    Match the specified argument against the 'name' field in the taxon_trees
    table instead of against 'taxon_name' in the authorities table. All matching
    taxa are selected, with all homonyms as the secondary selection.

  opinion|opin|op [parent] ARGS

    String arguments are matched against the 'taxon_name' field of the authorities
    table, and all opinions with a corresponding child_no or child_spelling_no are
    selected. If the first word of the argument is 'parent', then opinions with a
    corresponding parent_no or parent_spelling_no are selected. Identifiers are
    matched against the 'opinion_no' field.

  collection|coll|co [aka] ARGS

    String arguments are matched against the 'collection_name' field of the collections
    table. If the first word of the arguments is 'aka', then string arguments are also
    matched against the 'collection_aka' field. Identifiers are matched against the
    'collection_no' field.

ENDHelp
}

sub do_select {
    
    my ($command, $args) = @_;
    
    # If the command is 'select', start by clearing the selection.
    
    if ( $command eq 'select' )
    {
	clear_selection('all');
    }
    
    # If the command is 'list' ,start by clearing the list.
    
    elsif ( $command eq 'list' )
    {
	clear_list();
    }
    
    # If the first argument is an external identifier, then we weren't given a type.
    # Select the records corresponding to valid identifiers, and print error messages
    # for the rest.
    
    if ( $args =~ qr{ ^ [a-z][a-z][a-z][:]\d+ } )
    {
	return select_extids($command, $args);
    }
    
    elsif ( $args =~ qr{ ^ \d } )
    {
	return print_line "INVALID ARGUMENT: you must specify a record type";
    }
    
    # Otherwise, look for a type.
    
    my ($type, $rest) = parse_selection_type($args);
    
    if ( $type eq 'AUTH' || $type eq 'TT' )
    {
	return select_auth($command, $type, $rest);
    }
    
    elsif ( $type eq 'OPIN' )
    {
	return select_opin($command, $type, $rest);
    }
    
    elsif ( $type eq 'COLL' )
    {
	return select_coll($command, $type, $rest);
    }

    elsif ( $type eq 'OCCS' || $type eq 'REID' )
    {
	return select_occs($command, $type, $rest);
    }
    
    elsif ( $type eq 'SPEC' || $type eq 'MEAS' )
    {
	return select_spec($command, $type, $rest);
    }

    elsif ( $type eq 'PERS' )
    {
	return select_pers($command, $type, $rest);
    }

    elsif ( $type eq 'REFS' )
    {
	return select_refs($command, $type, $rest);
    }
    
    elsif ( $args =~ qr{ ^ (\w+) } )
    {
	return print_line "INVALID ARGUMENT: unknown record type '$1'";
    }
    
    else
    {
	my $argerr = substr($args, 0, 20);
	$argerr .= '...' if length($args) > 20;
	return print_line "INVALID ARGUMENT: cannot understand '$argerr'";
    }
}


sub do_page {
    
    my ($cmd, $argstring) = @_;
    
    if ( $cmd eq 'next' || $cmd eq 'prev' )
    {
	if ( $argstring && $argstring !~ qr{ ^ \d+ $ }xs )
	{
	    print_msg "INVALID ARGUMENT '$argstring'\n";
	    return;
	}
    }
    
    if ( $cmd eq 'next' )
    {
	if ( $argstring ne '' )
	{
	    $SELECTION{OFFSET} += $argstring;
	}
	
	else
	{
	    $SELECTION{OFFSET} += $SETTINGS{page};
	}

	$SELECTION{SHOW_LIST} ? display_list() : display_selection();
    }
    
    elsif ( $cmd eq 'prev' )
    {
	if ( $argstring ne '' )
	{
	    $SELECTION{OFFSET} -= $argstring;
	}

	else
	{
	    $SELECTION{OFFSET} -= $SETTINGS{page};
	}
	
	$SELECTION{OFFSET} = 0 if $SELECTION{OFFSET} < 0;
	
	$SELECTION{SHOW_LIST} ? display_list() : display_selection();
    }
    
    elsif ( $cmd eq 'show' )
    {
	if ( $argstring eq '' )
	{
	    return $SELECTION{SHOW_LIST} ? display_list() : display_selection();
	}
	
	if ( $argstring =~ qr{ ^ (?:selection|sel|all) $ }xsi )
	{
	    delete $SELECTION{SHOW_LIST};
	    return display_selection();
	}
	
	if ( $argstring =~ qr{ ^ list (?: \s* (.*) )? $ }xsi )
	{
	    $SELECTION{SHOW_LIST} = 1;
	    my $display = $1;
	    if ( $display =~ qr{ ^ (short|space|long) }xsi )
	    {
		$LIST{DISPLAY} = $1;
	    }
	    return display_list();
	}
	
	elsif ( $argstring =~ qr{ ^ pri (m (ary)? )? $ }xsi )
	{
	    $SELECTION{SHOW} = $SELECTION{PRIMARY_TYPE};
	    return display_selection();
	}
	
	# Otherwise, look for a type.
	
	my ($type, $rest) = parse_selection_type($argstring);
	
	if ( $type && $type ne 'INVALID' )
	{
	    $type = 'AUTH' if $type eq 'tt';
	    
	    $SELECTION{SHOW} = $type;
	    
	    if ( $rest =~ qr{ ^ (short|space|long) }xsi )
	    {
		$SELECTION{"${type}_DISPLAY"} = $1;
	    }
	    
	    return display_selection();
	}

	else
	{
	    print_msg "INVALID ARGUMENT '$argstring'";
	    return;
	}
    }
}


sub clear_selection ($) {

    my ($table) = @_;
    
    croak "You must specify a record type" unless $table;
    
    %SELECTION = ();
    # @SELECT_LIST = ();
    # $SELECT_TABLE = $table;
}


sub clear_list {

    %LIST = ();
}


BEGIN {
    $HELPSTRING{clear} = <<ENDHelp;

Summary:

  clear OPTION

Clears the specified information. This does not alter the database in any way.
The letter 's' is allowed at the end of the argument for 'opinion', 'collection',
etc.

Options:

  sel|selection         Clears the current selection completely
  list                  Clears the current list
  history               Clears the command history
  selhist               Clears the selection history
  undo                  Clears the undo list
  taxon|taxa|tx         Clears all taxa from the current selection
  opinion|opin|op       Clears all opinions from the current selection
  occurrence|occ|oc     Clears all occurrences from the current selection
  collection|coll|co    Clears all collections from the current selection
  settings              Resets application settings to defaults
  all                   Clears everything

ENDHelp
}

sub do_clear {
    
    my ($rest) = @_;
    
    if ( $rest =~ qr{ ^ (history|all) $ }xsi )
    {
	if ( ref $STORED->{HISTORY} eq 'ARRAY' )
	{
	    @{$STORED->{HISTORY}} = ();
	    eval {
		$TERM->clear_history;
	    };
	}
    }
    
    if ( $rest =~ qr{ ^ (undo|all) $ }xsi )
    {
	if ( ref $STORED->{UNDO_LIST} eq 'ARRAY' )
	{
	    @{$STORED->{UNDO_LIST}} = ();
	}
    }

    elsif ( $rest =~ qr{ ^ (settings|all) $ }xsi )
    {
	%SETTINGS = %DEFAULT_SETTINGS;
    }
    
    elsif ( $rest =~ qr{ ^ (selection|all) $ }xsi )
    {
	clear_selection('all');
    }
    
    elsif ( $rest =~ qr{ ^ (taxon|taxa|authority|authoritie|auth) s? $ }xsi )
    {
	clear_selection('authorities');
    }
    
    elsif ( $rest =~ qr{ ^ (opinion|opin) s? $ }xsi )
    {
	clear_selection('opinions');
    }

    elsif ( $rest =~ qr{ ^ (collection|coll) s? $ }xsi )
    {
	clear_selection('collections');
    }
    
    elsif ( $rest =~ qr{ ^ (occurrence|occ) s? $ }xsi )
    {
	clear_selection('occurrences');
    }
    
    else
    {
	print_line "INVALID ARGUMENT: unknown option '$rest'";
    }
}


# parse_selection_type ( argstring )
#
# Parse the specified string into a type specifier and remainder.

sub parse_selection_type {

    my ($args) = @_;
    
    if ( $args =~ qr{ ^ [^a-z] }xsi )
    {
	return 'INVALID', '';
    }
    
    elsif ( $args =~ qr{ ^ (?:taxon|taxa|authority|authorities|auths?|au|tx) (?: $ | \s+ (.*) ) }xsi )
    {
	return 'AUTH', $1;
    }
    
    elsif ( $args =~ qr{ ^ (?:vars?|variants|spells?|spellings) (?: $ | \s+ (.*) ) }xsi )
    {
	my $rest = "/var $1";
	return 'AUTH', $1;
    }
    
    elsif ( $args =~ qr{ ^ (?:syns?|synonyms?) (?: $ | \s+ (.*) ) }xsi )
    {
	my $rest = "/syn $1";
	return 'AUTH', $rest;
    }
    
    elsif ( $args =~ qr{ ^ (?:child|children) (?: $ | \s+ (.*) ) }xsi )
    {
	my $rest = "/child $1";
	return 'AUTH', $rest;
    }
    
    elsif ( $args =~ qr{ ^ tt (?: $ | \s+ (.*) ) }xsi )
    {
	return 'TT', $1;
    }
    
    elsif ( $args =~ qr{ ^ (?:opinions?|opins?|ops?) (?: $ | \s+ (.*) ) }xsi )
    {
	return 'OPIN', $1;
    }
    
    elsif ( $args =~ qr{ ^ (class|spell|group) [_/-]? op (?: $ | \s+ (.*) ) }xsi )
    {
	my $rest = "/$1 $2";
	return 'OPIN', $1;
    }
    
    elsif ( $args =~ qr{ ^ (?:collections?|colls?|co) (?: $ | \s+ (.*) ) }xsi )
    {
	return 'COLL', $1;
    }
    
    elsif ( $args =~ qr{ ^ (?:occurrences?|occs?|oc) (?: $ | \s+ (.*) ) }xsi )
    {
	return 'OCCS', $1;
    }
    
    elsif ( $args =~ qr{ ^ (?: reidentifications?|reids?|ri) (?: $ | \s+ (.*) ) }xsi )
    {
	return 'REID', $1;
    }

    elsif ( $args =~ qr{ ^ (?: specimens?|specs?|sp) (?: $ | \s+ (.*) ) }xsi )
    {
	return 'SPEC', $1;
    }

    elsif ( $args =~ qr{ ^ (?: measurements?|meas|me) (?: $ | \s+ (.*) ) }xsi )
    {
	return 'MEAS', $1;
    }

    elsif ( $args =~ qr{ ^ (?: people|persons?|pers|pe) (?: $ | \s+ (.*) ) }xsi )
    {
	return 'PERS', $1;
    }
    
    elsif ( $args =~ qr{ ^ (?: references?|refs?|re) (?: $ | \s+ (.*) ) }xsi )
    {
	return 'REFS', $1;
    }

    else
    {
	return 'INVALID', '';
    }
}


# parse_selection_args ( argstring )
#
# Parse the specified string into an argument list for a selection command.

sub parse_selection_args {

    my ($type, $argstring) = @_;
    
    # Loop until the entire argument string is processed. If it starts with a single or a double
    # quote mark, split out the quoted string as a single argument. If it contains a single or
    # double quote mark preceded by a space or comma, then process everything that proceeds that
    # and add the quoted string to the list. Otherwise, just process the entire argument
    # list. Processing involves splitting on commas, and then splitting any arguments that are
    # composed of just numbers or external identifiers on whitespace.
    
    my @arglist;
    my @optlist;
    
    while ( defined $argstring && $argstring ne '' )
    {
	# If the remainder of the argstring is whitespace, we are done.
	
	if ( $argstring =~ qr{ ^ \s+ $ }xs )
	{
	    last;
	}

	# If the argstring begins with a string of the type /arg or arg=val, treat that as
	# an option specifier. These should be specified at the beginning of any argument string.
	
	elsif ( $argstring =~ qr{ ^ ([/] \w+) (?: $ | \s+ (.*) ) }xs )
	{
	    $argstring = $2;
	    push @optlist, "$1=";
	}
	
	elsif ( $argstring =~ qr{ ^ [/]? (\w+ [=] \S*) (?: $ | \s+ (.*) ) }xs )
	{
	    $argstring = $2;
	    push @optlist, "/$1";
	}
	
	# If the argstring begins with a quoted string, split that out whole. Ignore quote marks
	# preceded by \. Eat up any commas or whitespace afterward.
	
	elsif ( $argstring =~ qr{ ^ ['] (.*?) (?<!\\) ['] [\s,]* (.*) }xs )
	{
	    $argstring = $2;
	    push @arglist, $1;
	}

	elsif ( $argstring =~ qr{ ^ ["] (.*?) (?<!\\) ["] [\s,]* (.*) }xs )
	{
	    $argstring = $2;
	    push @arglist, $1;
	}

	# If the argstring contains a quote mark partway in preceded by either a space or a
	# comma, process everything up to that.
	
	elsif ( $argstring =~ qr{ (.*?) (?<=[\s,]) ( ['"] .*) }xs )
	{
	    $argstring = $2;
	    my @simple = parse_simple_args($1);
	    push @arglist, @simple;
	}
	
	# Otherwise, process the entire string for simple arguments.
	
	else
	{
	    my @simple = parse_simple_args($argstring);
	    push @arglist, @simple;
	    $argstring = '';
	}
    }
    
    return @optlist, @arglist;
}


sub parse_simple_args {
    
    my ($argstring) = @_;

    # Start by splitting on commas and surrounding whitespace.
    
    my @commalist = split /\s*,\s*/, $argstring;

    # Now go through these comma-separated arguments. Ignore any that don't have at least one
    # non-whitespace character in them.
    
    my @arglist;
    
    foreach my $arg ( @commalist )
    {
	next unless defined $arg && $arg =~ /\S/;
	
	# An argument without any digits or punctuation is assumed to be a taxon or collection name
	# and is added to the argument list in its entirety, with initial and final
	# whitespace removed.
	
	if ( $arg =~ qr{^[a-zA-Z()\s]+$} )
	{
	    $arg =~ s/^\s+//;
	    $arg =~ s/\s+$//;
	    $arg =~ s/\s+/ /g;
	    push @arglist, $arg;
	    next;
	}
	
	# Otherwise, it is split on whitespace. Everything that looks like an identifier is added
	# to the argument list, and other strings are collected up and pasted together again with
	# spaces between them.
	
	my @tokenlist = split /\s+/, $arg;
	my @buffer;
	
	foreach my $token ( @tokenlist )
	{
	    if ( $token =~ qr{ ^ (\w\w\w[:])? \d+ $ }xs )
	    {
		if ( @buffer )
		{
		    push @arglist, join(' ', @buffer);
		    @buffer = ();
		}
		
		push @arglist, $token;
	    }
	    
	    else
	    {
		push @buffer, $token;
	    }
	}
	
	if ( @buffer )
	{
	    push @arglist, join(' ', @buffer);
	    @buffer = ();
	}
    }
    
    # We have processed it all, so now return it.
    
    return @arglist;
}


sub select_extids {

    my ($argstring) = @_;
    
    my $a = 1;

    print_msg "NOT YET IMPLEMENTED: selection by external identifiers\n";
}


sub select_auth {
    
    my ($command, $table, $argstring) = @_;
    
    my @arglist = parse_selection_args('AUTH', $argstring);
    
    my %auth;
    my %orig;
    my %aux;
    my @id_list;
    my @error_list;
    my @notfound_list;
    
    # Look for option specifiers at the beginning of the argument list.
    
    my $variants;
    
    while ( $arglist[0] =~ qr{ ^ [/] }xs )
    {
	my $opt = shift @arglist;
	
	if ( $opt =~ qr{ ^ [/] (?:var|all) }xs )
	{
	    $variants = 1;
	}
	
	elsif ( $opt =~ qr{ ^ [/] syn }xs )
	{
	    $table = 'SYN';
	}
	
	elsif ( $opt =~ qr{ ^ [/] (?:chil|chld) }xs )
	{
	    $table = 'CHLD';
	}
	
	else
	{
	    print_line "INVALID OPTION: '$opt'.";
	    return;
	}
    }
    
    # Then process the rest of the arguments.
    
    foreach my $arg ( @arglist )
    {
	my ($sql, $type, $id);
	
	if ( $arg =~ qr{ ^ (\w\w\w[:])? (\d+) $ }xs )
	{
	    $type = $1;
	    $id = $2;
	    
	    if ( $type && ($type ne 'txn' && $type ne 'var') )
	    {
		push @error_list, $arg;
		next;
	    }
	    
	    if ( $table eq 'TT' )
	    {
		$sql = "SELECT orig_no, spelling_no as taxon_no, name as taxon_name, rank as taxon_rank
			FROM taxon_trees as t WHERE orig_no = '$id'
			UNION SELECT orig_no, spelling_no as taxon_no, name as taxon_name, rank as taxon_rank
			FROM taxon_trees as t WHERE spelling_no = '$id'";
	    }
	    
	    elsif ( $table eq 'SYN' )
	    {
		$sql = "SELECT distinct t.orig_no, t.spelling_no as taxon_no, t.name as taxon_name, t.rank as taxon_rank
			FROM taxon_trees as t join taxon_trees as base
			using (synonym_no) join authorities as a on base.orig_no = a.orig_no
			WHERE a.taxon_no = '$id'";
	    }
	    
	    elsif ( $table eq 'CHLD' )
	    {
		$sql = "SELECT t.orig_no, t.spelling_no as taxon_no, t.name as taxon_name, t.rank as taxon_rank
			FROM taxon_trees as t join taxon_trees as base on t.immpar_no = base.orig_no
			  join authorities as a on base.orig_no = a.orig_no
			WHERE a.taxon_no = '$id'
			UNION SELECTt.orig_no, t.spelling_no as taxon_no, t.name as taxon_name, t.rank as taxon_rank
			FROM taxon_trees as t join taxon_trees as base on t.senpar_no = base.orig_no
			  join authorities as a on base.orig_no = a.orig_no
			WHERE a.taxon_no = '$id'";
	    }
	    
	    elsif ( $table eq 'AUTH' )
	    {
		$sql = "SELECT orig_no, taxon_no, taxon_name, taxon_rank FROM authorities WHERE taxon_no = '$id'";
	    }
	    
	    else
	    {
		croak "Invalid table '$table'\n";
	    }
	}
	
	elsif ( $arg !~ qr{ ^ [a-zA-Z()_%\s]+ $ }xs )
	{
	    push @error_list, $arg;
	}
	
	else
	{
	    my $quoted = $DBH->quote($arg);
	    
	    if ( $table eq 'TT' )
	    {
		$sql = "SELECT orig_no, spelling_no as taxon_no, name as taxon_name, rank as taxon_rank
			FROM taxon_trees WHERE name like $quoted";
	    }
	    
	    elsif ( $table eq 'SYN' )
	    {
		$sql = "SELECT distinct t.orig_no, t.spelling_no as taxon_no, t.name as taxon_name, t.rank as taxon_rank
			FROM taxon_trees as t join taxon_trees as base using (synonym_no)
			    join authorities as a on base.orig_no = a.orig_no
			WHERE a.taxon_name like $quoted";
	    }
	    
	    elsif ( $table eq 'CHLD' )
	    {
		$sql = "SELECT t.orig_no, t.spelling_no as taxon_no, t.name as taxon_name, t.rank as taxon_rank
			FROM taxon_trees as t join taxon_trees as base on t.immpar_no = base.orig_no
			    join authorities as a on base.orig_no = a.orig_no
			WHERE a.taxon_name like $quoted
			UNION SELECT t.orig_no, t.spelling_no as taxon_no, t.name as taxon_name, t.rank as taxon_rank
			FROM taxon_trees as t join taxon_trees as base on t.senpar_no = base.orig_no
			    join authorities as a on base.orig_no = a.orig_no
			WHERE a.taxon_name like $quoted";
	    }
	    
	    elsif ( $table eq 'AUTH' )
	    {
		$sql = "SELECT orig_no, taxon_no, taxon_name, taxon_rank FROM authorities
			WHERE taxon_name like $quoted";
	    }
	    
	    else
	    {
		croak "Invalid table '$table'\n";
	    }
	}
	
	print_msg $sql if $DEBUG{sql};
	
	my ($found) = $DBH->selectall_arrayref($sql, { Slice => { } });
	
	if ( $found && @$found )
	{
	    foreach my $r ( @$found )
	    {
		my $orig_no = $r->{orig_no};
		my $taxon_no = $r->{taxon_no} || $r->{spelling_no};
		unless ( $auth{$taxon_no} )
		{
		    $auth{$taxon_no} = $r;
		    push @id_list, $taxon_no;
		}
		$orig{$orig_no} = 1;
	    }
	}
	
	else
	{
	    my $display_arg = $id || $arg;
	    push @notfound_list, $display_arg;
	}
    }
    
    if ( @error_list )
    {
	my $errstring = join("', '", @error_list);
	print_line("SKIPPED: invalid taxon name or id '$errstring'");
    }
    
    if ( @notfound_list )
    {
	my $nfstring = join("', '", @notfound_list);
	my $label = $table eq 'TT' ? 'entries in taxon_trees' : 'authorities';
	print_line "NOT FOUND: no $label matched '$nfstring'"
    }
    
    if ( $table eq 'SYN' || $table eq 'CHLD' )
    {
	$table = 'AUTH';
    }
    
    # If none of the arguments actually matched, return now.
    
    unless ( %auth )
    {
	if ( $command eq 'select' )
	{
	    print_msg "No records found. Selection is empty.";
	}
	
	else
	{
	    print_msg "No records found.";
	}
	
	# If we were adding to an existing selection, add a selector record indicating no
	# records were added.
	
	if ( $command eq 'add' )
	{
	    push @{$SELECTION{SELECTORS}}, { ARGSTRING => $argstring,
					     TABLE => $table,
					     TYPE => 'AUTH',
					     FOUND => 0 };
	}
	
	return;
    }
    
    # If the 'variants' option was given, find all variants of these names.
    
    my $primary_count = scalar(@id_list);
    my $variant_count = 0;
    
    if ( $variants )
    {
	my $idstring = join(',', keys %orig);
	
	my $sql = "SELECT a.taxon_no, a.orig_no, a.taxon_name, a.taxon_rank
		FROM authorities as a WHERE a.orig_no in ($idstring)";
	
	print_msg $sql if $DEBUG{sql};
	
	my $result = $DBH->selectall_arrayref($sql, { Slice => {} });
	
	if ( $result && ref $result eq 'ARRAY' )
	{
	    foreach my $r ( @$result )
	    {
		my $taxon_no = $r->{taxon_no};
		
		unless ( $auth{$taxon_no} )
		{
		    push @id_list, $taxon_no;
		    $variant_count++;
		    $auth{$taxon_no} = $r;
		    $aux{$taxon_no} = 1;
		}
	    }
	}
    }
    
    # If the command was 'list', stuff these results into the list.
    
    if ( $command eq 'list' )
    {
	$LIST{TYPE} = 'AUTH';
	$LIST{TABLE} = $table;
	$LIST{ARGSTRING} = $argstring;
	$LIST{OFFSET} = 0;
	$SELECTION{SHOW_LIST} = 1;
	
	$LIST{ID} = \%auth;
	$LIST{AUX} = \%aux;
	$LIST{RESULTS} = \@id_list;
	$LIST{COUNT} = scalar(@id_list);
	
	return display_list('noheader');
    }
    
    # Otherwise, we either establish a new selection or modify the existing one. Establish
    # a new selection if none exists, and create a selector record to record the selection
    # parameters.

    else
    {
	my $selector = { ARGSTRING => $argstring,
			 TYPE => 'AUTH',
			 TABLE => $table,
			 COUNT => scalar(@id_list),
			 DUP => 0 };
	
	push @{$SELECTION{SELECTORS}}, $selector;
	$SELECTION{COUNT} ||= 0;
	$SELECTION{OFFSET} = 0;
	delete $SELECTION{SHOW_LIST};
	
	# Set the primary selection type to 'authorities', unless it is already set.
	
	$SELECTION{PRIMARY_TYPE} ||= 'AUTH';
	
	# Now add the selected records, unless they duplicate a record that is already
	# part of the selection. In that case, increment the duplicate count.
	
	foreach my $id ( @id_list )
	{
	    if ( $SELECTION{AUTH}{$id} )
	    {
		$selector->{DUP}++;
		delete $SELECTION{AUTH_AUX}{$id} unless $aux{$id};
	    }
	    
	    else
	    {
		push @{$SELECTION{AUTH_LIST}}, $id;
		$SELECTION{AUTH}{$id} = $auth{$id};
		$SELECTION{AUTH_AUX}{$id} = 1 if $aux{$id};
	    }
	}
	
	$SELECTION{AUTH_COUNT} = $SELECTION{AUTH_LIST} ? @{$SELECTION{AUTH_LIST}} : 0;
	
	adjust_selection();
	display_selection('noheader');
    }
}


sub select_opin {
    
    my ($command, $table, $argstring) = @_;
    
    my @arglist = parse_selection_args('OPIN', $argstring);
    
    my %opin;
    my @id_list;
    my @error_list;
    my @notfound_list;
    
    # Look for option specifiers at the beginning of the argument list.
    
    my $op_type = 'all';
    my $default_type = 'opn';
    my $select_field = 'child_spelling_no';
    
    if ( $table eq 'CLASS' )
    {
	$op_type = 'class';
    }
    
    elsif ( $table eq 'GROUP' )
    {
	$op_type = 'group';
    }
    
    elsif ( $table eq 'SPELL' )
    {
	$op_type = 'spell';
    }

    while ( $arglist[0] =~ qr{ ^ [/] }xs )
    {
	my $opt = shift @arglist;
	
	if ( $opt =~ qr{ ^ [/] txn $ }xs )
	{
	    $default_type = 'var';
	}
	
	elsif ( $opt =~ qr{ ^ [/] par }xs )
	{
	    $select_field = 'parent_spelling_no';
	}
	
	elsif ( $opt =~ qr{ ^ [/] cha }xs )
	{
	    $select_field = 'child_no';
	}
	
	elsif ( $opt =~ qr{ ^ [/] cla }xs )
	{
	    $op_type = 'class';
	}

	elsif ( $opt =~ qr{ ^ [/] gr }xs )
	{
	    $op_type = 'group';
	}
	
	elsif ( $opt =~ qr{ ^ [/] sp }xs )
	{
	    $op_type = 'spell';
	}

	elsif ( $opt =~ qr{ ^ [/] all $ }xs )
	{
	    $op_type = 'all';
	}
	
	if ( $opt =~ qr{ ^ [/] var }xs )
	{
	    $op_type = 'variants';
	}
	
	else
	{
	    print_line "INVALID OPTION: '$opt'.";
	    return;
	}
    }
    
    # Then process the rest of the arguments.
    
    foreach my $arg ( @arglist )
    {
	my $type;
	my $selector;
	
	# From the argument, generate a selector expression.
	
	if ( $arg =~ qr{ ^ (\w\w\w[:])? (\d+) $ }xs )
	{
	    $type = $1 || $default_type;
	    my $id = $2;
	    
	    if ( $1 && $1 ne 'txn' && $1 ne 'var' && $1 ne 'opn')
	    {
		push @error_list, $arg;
		next;
	    }
	    
	    if ( $type eq 'opn' )
	    {
		$selector = "opinion_no = '$id'";
	    }
	    
	    else
	    {
		$selector = "taxon_no = '$id'";
	    }
	}
	
	elsif ( $arg !~ qr{ ^ [a-zA-Z()_%\s]+ $ }xs )
	{
	    push @error_list, $arg;
	}
	
	else
	{
	    my $quoted = $DBH->quote($arg);

	    $selector = "taxon_name like $quoted";
	}
	
	# From $type, $op_type, and $selector, generate an SQL statement.
	
	my $sql;
	
	if ( $type && $type eq 'opn' )
	{
	    $sql = "SELECT o.opinion_no FROM opinions WHERE o.$selector";
	}
	
	elsif ( $op_type eq 'class' )
	{
	    $sql = "SELECT t.opinion_no, a.taxon_no, a.orig_no, a.taxon_name
		    FROM taxon_trees as t join authorities as a using (orig_no)
		    WHERE a.$selector";
	}
	
	elsif ( $op_type eq 'group' )
	{
	    $sql = "SELECT n.opinion_no, n.taxon_no, n.orig_no, a.taxon_name
		    FROM taxon_names as n join authorities as a using (taxon_no)
		    WHERE a.$selector";

	    if ( $type eq 'txn' )
	    {
		$sql = "SELECT n.opinion_no, n.taxon_no, n.orig_no
		    FROM taxon_trees as t join authorities as a using (orig_no)
		        join taxon_names as n on n.taxon_no = t.spelling_no
		    WHERE a.$selector";
	    }
	}
	
	elsif ( $op_type eq 'spell' )
	{
	    $sql = "SELECT n.opinion_no, a.taxon_no, a.orig_no, a.taxon_name
		    FROM taxon_trees as t join authorities as a using (orig_no)
		        join taxon_names as n on n.taxon_no = t.spelling_no
		    WHERE a.$selector";
	}
	
	elsif ( $op_type eq 'all' )
	{
	    $sql = "SELECT o.opinion_no, a.taxon_no, a.orig_no, a.taxon_name
		    FROM opinions as o join authorities as a on a.taxon_no = o.$select_field
		    WHERE a.$selector UNION
		    SELECT t.opinion_no, a.taxon_no, a.orig_no, a.taxon_name
		    FROM taxon_trees as t join authorities as a using (orig_no)
		    WHERE a.$selector";
	}
	
	elsif ( $op_type eq 'variants' )
	{
	    $sql = "SELECT o.opinion_no, a.taxon_no, a.orig_no, a.taxon_name
		    FROM opinions as o join authorities as a on a.taxon_no = o.$select_field
			join authorities as base on a.orig_no = base.orig_no
		    WHERE base.$selector UNION
		    SELECT t.opinion_no, a.taxon_no, a.orig_no, a.taxon_name
		    FROM taxon_trees as t join authorities as a using (orig_no)
		    WHERE a.$selector";
	}
	
	print_msg $sql if $DEBUG{sql};
	
	my ($found) = $DBH->selectall_arrayref($sql, { Slice => { } });
	
	if ( $found && ref $found eq 'ARRAY' )
	{
	    foreach my $r ( @$found )
	    {
		my $opinion_no = $r->{opinion_no};
		unless ( $opin{$opinion_no} )
		{
		    $opin{$opinion_no} = $r;
		    push @id_list, $opinion_no;
		}
	    }
	}
	
	else
	{
	    push @notfound_list, $arg;
	}
    }
    
    if ( @error_list )
    {
	my $errstring = join("', '", @error_list);
	print_line("SKIPPED: invalid taxon name or id '$errstring'");
    }
    
    if ( @notfound_list )
    {
	my $nfstring = join("', '", @notfound_list);
	print_line "NOT FOUND: no opinions matched '$nfstring'"
    }
    
    # If none of the arguments actually matched, return now.
    
    unless ( %opin )
    {
	if ( $command eq 'select' )
	{
	    print_msg "No records found. Selection is empty.";
	}
	
	else
	{
	    print_msg "No records found.";
	}
	
	# If we were adding to an existing selection, add a selector record indicating no
	# records were added.
	
	if ( $command eq 'add' )
	{
	    push @{$SELECTION{SELECTORS}}, { ARGSTRING => $argstring,
					     TABLE => 'OPIN',
					     TYPE => 'OPIN',
					     FOUND => 0 };
	}
	
	return;
    }
    
    # If the command was 'list', stuff these results into the list.
    
    if ( $command eq 'list' )
    {
	$LIST{TYPE} = 'OPIN';
	$LIST{TABLE} = 'OPIN';
	$LIST{ARGSTRING} = $argstring;
	$LIST{OFFSET} = 0;
	$SELECTION{SHOW_LIST} = 1;
	
	$LIST{ID} = \%opin;
	$LIST{RESULTS} = \@id_list;
	$LIST{COUNT} = scalar(@id_list);
	
	return display_list('noheader');
    }
    
    # Otherwise, we either establish a new selection or modify the existing one. Establish
    # a new selection if none exists, and create a selector record to record the selection
    # parameters.

    else
    {
	my $selector = { ARGSTRING => $argstring,
			 TYPE => 'OPIN',
			 TABLE => 'OPIN',
			 COUNT => scalar(@id_list),
			 DUP => 0 };
	
	push @{$SELECTION{SELECTORS}}, $selector;
	$SELECTION{COUNT} ||= 0;
	$SELECTION{OFFSET} = 0;
	$SELECTION{PRIMARY_TYPE} ||= 'OPIN';
	delete $SELECTION{SHOW_LIST};
	
	# Now add the selected records, unless they duplicate a record that is already
	# part of the selection. In that case, increment the duplicate count.
	
	foreach my $id ( @id_list )
	{
	    if ( $SELECTION{OPIN}{$id} )
	    {
		$selector->{DUP}++;
	    }
	    
	    else
	    {
		push @{$SELECTION{OPIN_LIST}}, $id;
		$SELECTION{OPIN}{$id} = $opin{$id};
	    }
	}
	
	$SELECTION{OPIN_COUNT} = $SELECTION{OPIN_LIST} ? @{$SELECTION{OPIN_LIST}} : 0;
	
	adjust_selection();
	display_selection('noheader');
    }
}


sub adjust_selection {
    
    $SELECTION{TOTAL_COUNT} = $SELECTION{AUTH_COUNT} +	$SELECTION{OPIN_COUNT} +
	$SELECTION{OCCS_COUNT} + $SELECTION{COLL_COUNT};
}


# display_list
# 
# Print out results of a the most recent list operation.
# 
# If the number of records is more than the value of the
# application setting 'page', then display that number of records. The user can use the
# commands 'next', 'previous', and 'show' to move forward and backward in the list.

sub display_list {
    
    my ($arg);
    
    unless ( $LIST{COUNT} )
    {
	print_msg "Nothing found.";
    }
    
    unless ( $arg && $arg eq 'noheader' )
    {
	my $type = $LIST{TABLE} || 'NONE';
	print_line "List $SELECTION_LABEL{$type}: $LIST{ARGSTRING}";
    }
    
    my $count = $LIST{COUNT};
    my $offset = $LIST{OFFSET};
    my $page = $SETTINGS{page};
    my $last = $offset + $page;
    
    $last = $count - 1 if $last > $count - 1;
    
    if ( $count == 0 )
    {
	print_msg "Nothing found.";
	return;
    }
    
    elsif ( $offset > 0 || $last < $count - 1 )
    {
	print_msg "Showing $offset - $last of $count";
    }
    
    else
    {
	print_line "Found $count records";
    }
    
    unless ( ref $LIST{RESULTS} eq 'ARRAY' && @{$LIST{RESULTS}} )
    {
	print_msg "INTERNAL ERROR: result list not found";
	return;
    }
    
    my @display_list = @{$LIST{RESULTS}}[$offset..$last];
    
    display_records(\@display_list, { type => $LIST{TYPE}, offset => $offset, attrs => $LIST{ID} });
}


sub display_selection {

    my ($arg);
    
    # First print out a header. But suppress this if $arg is 'noheader'.
    
    unless ( $SELECTION{TOTAL_COUNT} )
    {
	print_msg "Nothing selected.";
	return;
    }
    
    unless ( $arg && $arg eq 'noheader' )
    {
	if ( ref $SELECTION{SELECTORS} eq 'ARRAY' )
	{
	    my $word = "Select";
	    print_line "";
	    
	    foreach my $selector ( @{$SELECTION{SELECTORS}} )
	    {
		my $label = $SELECTION_LABEL{$selector->{TABLE}};
		print_line sprintf("%-21s %s", "$word $label:", $selector->{ARGSTRING});
		$word = "Add   ";
	    }

	    print_line "";
	}
	
	else
	{
	    print_msg "\nINTERNAL ERROR: list of selectors not found.";
	}
    }
    
    # Figure out what types of records to display and how many there are. If
    # $SELECTION{SHOW} is set, it indicates what type to display.
    
    my @show_sections;
    
    my $count_line = '';
    my $separator = '';
    my $display_label = 'records';
    my $display_count = 0;
    
    if ( my $display_type = $SELECTION{SHOW} )
    {
	@show_sections = $display_type;
	$display_count = $SELECTION{"${display_type}_COUNT"};
	$display_label = $SELECTION_LABEL{$display_type};
	$count_line = "[ $display_count $display_label ]";
	$separator = ' + ';
	
	foreach my $section ( qw(AUTH OPIN COLL OCCS REID SPEC MEAS PERS REFS) )
	{
	    if ( $section ne $display_type )
	    {
		if ( my $count = $SELECTION{"${section}_COUNT"} )
		{
		    my $label = $SELECTION_LABEL{$section};
		    $count_line .= "$separator$count $label";
		    $separator = ', ';
		}
	    }
	}
    }
    
    else
    {
	@show_sections = qw(AUTH OPIN COLL OCCS REID SPEC MEAS PERS REFS);
	$count_line = "[ ";
	
	foreach my $section ( @show_sections )
	{
	    if ( my $count = $SELECTION{"${section}_COUNT"} )
	    {
		my $label = $SELECTION_LABEL{$section};
		$count_line .= "$separator$count $label";
		$separator = ', ';
		$display_count += $count;
	    }
	}

	$count_line .= " ]";
    }
    
    # Then print out the result count and offset if any, along with total record counts. The
    # offset is adjusted if necessary to put it in the range from zero to the result count
    # minus the page size.
    
    if ( $display_count == 0 )
    {
	print_msg "No $display_label selected.";
	return;
    }
    
    my $offset = $SELECTION{OFFSET};
    my $page = $SETTINGS{page};
    my $last = $offset + $page;
    my $stop = $display_count - $page;
    
    $offset = 0 if $offset < 0;
    $offset = $stop if $stop > 0 && $offset > $stop;
    $offset = 0 if $stop <= 0;
    
    if ( $offset == 0 && $last >= $display_count - 1 )
    {
	print_msg sprintf("%-21s %s", "Showing all of", $count_line);
    }
    
    else
    {
	print_msg sprintf("%-21s %s", "Showing $offset-$last of", $count_line);
    }
    
    # Now print out the results themselves, section by section.
    
    my $remaining = $page;
    my $remoffset = $offset;
    
    foreach my $type ( @show_sections )
    {
	last unless $remaining;
	
	if ( my $count = $SELECTION{"${type}_COUNT"} )
	{
	    if ( $count < $remoffset )
	    {
		$remoffset = $remoffset - $count;
		next;
	    }
	    
	    my $list = $SELECTION{"${type}_LIST"};
	    
	    unless ( $list && ref $list eq 'ARRAY' )
	    {
		print_msg "INTERNAL ERROR: ${type}_LIST not found\n";
		next;
	    }
	    
	    my $last = $remoffset + $remaining;
	    $last = $count - 1 if $last > $count - 1;
	    
	    my $label = $SELECTION_LABEL{$type};
	    
	    my @display_list = @$list[$remoffset..$last];
	    
	    $remaining = $remaining - scalar(@display_list);
	    $remoffset = 0;

	    my $display = $SELECTION{"${type}_DISPLAY"} || $SETTINGS{display} || 'short';
	    
	    display_records(\@display_list, { type => $type, offset => $remoffset,
					      display => $display, attrs => $SELECTION{$type} });
	}
    }
    
    if ( $offset > 0 && $remaining == 0 )
    {
	print_msg "End of selection.";
    }
}


sub display_records {
    
    my ($list, $options) = @_;
    
    my $type = $options->{type};
    my $index = $options->{offset};
    my $display = $options->{display};
    my $attrs = $options->{attrs};
    
    my $id_string = join(',', grep { $_ } @$list);
    
    my %output_record;
    
    if ( $type eq 'AUTH' )
    {
	%output_record = output_auth($id_string, $attrs, $display);
    }
    
    elsif ( $type eq 'OPIN' )
    {
	%output_record = output_opin($id_string, $attrs, $display);
    }
    
    elsif ( $type eq 'COLL' )
    {
	%output_record = output_coll($id_string, $attrs, $display);
    }

    elsif ( $type eq 'OCCS' )
    {
	%output_record = output_occs($id_string, $attrs, $display);
    }
    
    foreach my $id ( @$list )
    {
	my $indstr = sprintf("%-6d", $index++);
	
	if ( defined $id && $output_record{$id} )
	{
	    substr($output_record{$id}, 0, 6) = $indstr;
	    print_string $output_record{$id};
	}
	
	else
	{
	    print_string "${indstr}MISSING RECORD\n";
	}
    }
}


sub output_auth {
    
    my ($id_string, $attrs, $display) = @_;
    
    return () unless $id_string =~ /\d/;
    
    $display ||= 'short';
    $attrs ||= { };
    
    my $long_fields = '';
    my $long_tables = '';

    if ( $display eq 'long' )
    {
	$long_fields = '
		    n.opinion_no as spell_opinion_no, t.opinion_no as class_opinion_no,
		    class.author as class_author, class.pubyr as class_pubyr,
		    spell.author as spell_author, spell.pubyr as spell_pubyr,';
	$long_tables = '
		    left join order_opinions as class on class.opinion_no = t.opinion_no
		    left join order_opinions as spell on spell.opinion_no = n.opinion_no';
    }
    
    my $sql = "SELECT a.taxon_no, a.orig_no, a.taxon_name, a.taxon_rank, t.name as tree_name, t.rank as tree_rank,
		    n.spelling_reason, t.spelling_no, t.accepted_no, t.status, $long_fields
		    acc.name as accepted_name, ao.taxon_name as orig_name,
		    par.name as parent_name, syn.name as synonym_name
		FROM authorities as a left join authorities as ao on ao.taxon_no = a.orig_no
		    left join taxon_names as n on n.taxon_no = a.taxon_no
		    left join taxon_trees as t on t.orig_no = a.orig_no
		    left join taxon_trees as acc on acc.orig_no = t.accepted_no
		    left join taxon_trees as par on par.orig_no = t.senpar_no
		    left join taxon_trees as syn on syn.orig_no = t.synonym_no $long_tables
		WHERE a.taxon_no in ($id_string)";
    
    print_msg $sql if $DEBUG{sql};
    
    my $result = $DBH->selectall_arrayref($sql, { Slice => {} });
    
    my @output_list;
    
    foreach my $r ( @$result )
    {
	my $taxon_no = $r->{taxon_no};
	my $tree_entry = $taxon_no eq $r->{spelling_no} ? 1 : 0;
	
	push @output_list, $taxon_no;
	
	my $label = $tree_entry ? 'Taxon' : 'Auth ';
	
	my $num = $r->{taxon_no} || '###';
	$num .= " ($r->{orig_no})" if $r->{orig_no} && $r->{orig_no} ne $r->{taxon_no};
	
	my $name;
	
	if ( $tree_entry )
	{
	    $name = $r->{tree_name} || 'xxx';
	    $name .= " [$r->{taxon_name}]" if $r->{taxon_name} && $r->{taxon_name} ne $name;
	    $name .= " ($r->{orig_name})" if $r->{orig_name} && $r->{orig_name} ne $name;
	}
	
	else
	{
	    $name = $r->{taxon_name} || 'xxx';
	    $name .= " ($r->{orig_name})" if $r->{orig_name} && $r->{orig_name} ne $r->{taxon_name};
	    $name .= " => $r->{tree_name}" if $r->{tree_name} && $r->{tree_name} ne $name;
	}
	
	my $desc = "$r->{taxon_rank} - ";
	$desc .= "$r->{spelling_reason} - " if $r->{spelling_reason} && $r->{spelling_reason} !~ /^orig/;
	$desc .= $r->{status} || 'unclassified';
	
	if ( $r->{status} && $r->{status} =~ /belongs/ && $r->{parent_name} )
	{
	    $desc .= " $r->{parent_name}";
	}
	
	elsif ( $r->{status} && $r->{status} =~ /synonym/ && $r->{synonym_name} )
	{
	    $desc .= " $r->{synonym_name}";
	}
	
	my $opinions = '';
	
	if ( $display eq 'long' )
	{
	    my $class_author = $r->{class_author} || 'xxx';
	    my $class_pubyr = $r->{class_pubyr} || '?';
	    my $op_no = $r->{class_opinion_no};
	    
	    $opinions .= $op_no ? "$class_author $class_pubyr #$op_no" : "no classification";
	    
	    my $spell_author = $r->{spell_author} || 'xxx';
	    my $spell_pubyr = $r->{spell_pubyr} || '?';
	    my $sp_no = $r->{spell_opinion_no};
	    
	    $opinions .= " - $spell_author $spell_pubyr #$sp_no"
		if $sp_no && $r->{spelling_reason} && $r->{spelling_reason} !~ /^orig/;
	}
	
	my $outstring = '';
	$outstring =  sprintf("      %-5s %-19s%s\n", $label, $num, $name);
	$outstring .= sprintf("      %-5s %-19s  %s\n", "", "", $desc);
	$outstring .= sprintf("      %-5s %-19s    %s\n", "", "", $opinions) if $display eq 'long';
	$outstring .= "\n" if $display ne 'short';
	
	push @output_list, $outstring;
    }
    
    return @output_list;
}


sub output_opin {
    
    my ($id_string, $attrs, $display) = @_;
    
    return () unless $id_string =~ /\d/;
    
    $display ||= 'short';
    $attrs ||= { };
    
    my $long_fields = '';
    my $long_tables = '';
    
    my $sql = "SELECT o.opinion_no, o.reference_no, o.child_no, o.child_spelling_no as spelling_no,
		    asp.orig_no as child_orig_no, o.parent_spelling_no, ap.orig_no as parent_orig_no,
		    o.status, o.basis, o.spelling_reason, o.ref_has_opinion, oo.author, oo.pubyr, oo.ri,
		    ac.taxon_name as child_name, asp.taxon_name as spelling_name, ap.taxon_name as parent_name,
		    t.name as class_tree_name, tn.name as spell_tree_name
		FROM opinions as o join order_opinions as `oo` using (opinion_no)
		    left join authorities as `ac` on ac.taxon_no = o.child_no
		    left join authorities as `asp` on asp.taxon_no = o.child_spelling_no
		    left join authorities as `ap` on ap.taxon_no = o.parent_spelling_no
		    left join taxon_trees as t on t.opinion_no = o.opinion_no
		    left join taxon_names as n on n.opinion_no = o.opinion_no
		    left join taxon_trees as tn on tn.spelling_no = n.taxon_no
		WHERE o.opinion_no in ($id_string)";
    
    print_msg $sql if $DEBUG{sql};
    
    my $result = $DBH->selectall_arrayref($sql, { Slice => {} });
    
    my @output_list;
    
    foreach my $r ( @$result )
    {
	my $opinion_no = $r->{opinion_no};
	
	push @output_list, $opinion_no;
	
	my $label = 'Opinion ';
	$label .= 'C' if $r->{class_tree_name};
	$label .= 'S' if $r->{spell_tree_name};
	
	my $num = $r->{opinion_no} || '###';

	my $spell_reason = $r->{spelling_reason} || 'something';
	my $child_name = $r->{child_name} || 'xxx';
	my $spell_name = $r->{spelling_name} || 'xxx';
	my $spell_line = "$child_name $spell_reason $spell_name";
	
	my $status = $r->{status} || '???';
	my $parent_name = $r->{parent_name} || 'xxx';
	
	my $class_line = "$spell_name $status $parent_name";
	
	if ( $display eq 'long' )
	{
	}
	
	my $outstring = '';
	$outstring =  sprintf("      %-10s %-10s%s\n", $label, $num, $class_line);
	$outstring .= sprintf("      %-10s %-10s%s\n", "", "", $spell_line);
	$outstring .= "\n" if $display ne 'short';
	
	push @output_list, $outstring;
    }

    return @output_list;
}


# =============================

# sub add_to_selection {

#     my ($label, $record) = @_;
    
#     croak "Invalid selection label" unless $label =~ qr{ ^ [a-z][a-z]? $ }xs;
#     croak "Invalid selection record" unless ref $record eq 'HASH';
#     croak "Selection label already exists" if $SELECTION{$label};
    
#     $SELECTION{$label} = $record;
#     push @SELECT_LIST, $label;
# }


# sub do_list {
    
#     my ($dbt, $session, $args) = @_;
    
#     my $dbh = $dbt->dbh;
    
#     # Check to see if we're listing undo records
    
#     if ( $args =~ qr{ ^ undo (?: \s+ | $ ) (.* ) }xsi )
#     {
# 	my $rest = $1;
# 	return list_undo($dbh, $rest);
#     }
    
#     # Otherwise check for a valid arg pattern
    
#     unless ( $args =~ qr{ ^ (\w+) \s+ (\S[^/]*) (.*) }xsi )
#     {
# 	return print_msg "INVALID ARGUMENTS: '$args'";
#     }
    
#     my $table_key = $1;
#     my $keyval = $2;
#     my $rest = $3;
    
#     $keyval =~ s/\s+$//;
    
#     unless ( $TABLE{$table_key} && ref $TABLE{$table_key} eq 'ARRAY' )
#     {
# 	return print_msg "UNKNOWN TABLE: $table_key";
#     }
    
#     unless ( $keyval )
#     {
# 	return print_msg "YOU MUST SPECIFY A KEY VALUE";
#     }
    
#     my ($table, $key) = @{$TABLE{$table_key}};
#     my ($sql, $result, $by_name);
    
#     my $options = { };
#     $options = options_for_list($rest) if $rest;
    
#     if ( $keyval =~ qr{ ^ [0-9,\s]+ $ }xs )
#     {
# 	$options->{by_name} = undef;
#     }
    
#     elsif ( $keyval =~ qr{ ^ ( [a-z][a-z]? ) [>] $ }xs )
#     {
# 	$options->{by_selection} = 1;
# 	$options->{by_name} = undef;
# 	$keyval = $SELECTION{$1};
	
# 	unless ( ref $keyval eq 'HASH' )
# 	{
# 	    return print_msg("No such record.");
# 	}
#     }
    
#     else
#     {
# 	$options->{by_name} = 1;
	
# 	# if ( $args[0] =~ qr{ ^ [a-zA-Z] }xs )
# 	# {
# 	#     $keyval .= " " . shift @args;
# 	# }
	
# 	$keyval =~ s/\./%/;
# 	$keyval = $dbh->quote($keyval);
#     }
    
#     if ( my $query_sub = $ACTION{$table}{query} )
#     {
# 	$sql = &$query_sub($dbh, $key, $keyval, $options);
#     }
    
#     else
#     {
# 	return print_msg("UNIMPLEMENTED: '$table'");
#     }
    
#     # Now that we have determined what SQL query to make, execute it and
#     # display the results.
    
#     if ( $DEBUG{sql} )
#     {
# 	print_line "";
# 	print_line $sql;
#     }
    
#     if ( $options->{limit} )
#     {
# 	$sql .= " LIMIT " . $options->{limit} if $options->{limit} > 0;
#     }
    
#     elsif ( $SETTINGS{limit} )
#     {
# 	$sql .= " LIMIT " . $SETTINGS{limit};
#     }
    
#     $result = $dbh->selectall_arrayref($sql, { Slice => {} });
    
#     unless ( ref $result eq 'ARRAY' && @$result )
#     {
# 	return print_msg "NOTHING FOUND.";
#     }
    
#     # Now process the results and print them.
    
#     if ( my $list_sub = $ACTION{$table}{list} )
#     {
# 	&$list_sub($dbh, $result);
# 	print_line "";
#     }
    
#     else
#     {
# 	print_msg "ERROR: UNIMPLEMENTED '$table'";
#     }
    
#     return;
# }


# sub options_for_list {
    
#     my ($rest) = @_;
    
#     my @opts = split /\s+/, $rest;
#     my $options = { };
    
#     while ( @opts )
#     {
# 	my $opt = shift @opts;
	
# 	if ( $opt =~ qr{ ^ /all $ }xsi )
# 	{
# 	    $options->{all} = 1;
# 	}
	
# 	elsif ( $opt =~ qr{ ^ /limit $ }xsi )
# 	{
# 	    my $limit = shift @opts;
# 	    die "ERROR: you must include a positive value for /limit"
# 		unless defined $limit && ($limit > 0 || lc $limit eq 'all');
# 	    $options->{limit} = $limit;
# 	}
	
# 	else
# 	{
# 	    die "ERROR: unknown option '$opt'";
# 	}
#     }
    
#     return $options;
# }


# sub set_field {
    
#     my ($r, $s, $field, $value) = @_;
    
#     my $field_key = "field_$field";
#     my $field_len = length($value);
#     my $width_key = "width_$field";
    
#     $r->{$field_key} = $value;
#     $s->{$width_key} = $field_len
# 	if !defined $s->{$width_key} || $field_len > $s->{$width_key};
# }


# sub get_date {
    
#     my ($datetime) = @_;
    
#     if ( $datetime =~ qr{ ^ ( \d\d\d\d-\d\d-\d\d ) }xsi )
#     {
# 	return $1;
#     }
    
#     else
#     {
# 	return 'unknown';
#     }
# }


# sub do_update {

#     my ($dbt, $session, $is_fix, $args) = @_;
    
#     unless ( $SELECT_TABLE && @SELECT_LIST )
#     {
# 	print_msg("NOTHING TO UPDATE.");
# 	return;
#     }
    
#     unless ( $args =~ qr{ ^ ( [,a-z]+ ) \s* (.*) }xs )
#     {
# 	print_msg("INVALID ARGUMENTS: '$args'");
# 	return;
#     }
    
#     my $selector = $1;
#     my $rest = $2;
#     my $dbh = $dbt->dbh;
    
#     unless ( $COLUMN_INFO{$SELECT_TABLE} )
#     {
# 	fetch_column_info($dbh, $SELECT_TABLE);
#     }
    
#     my @update_keys;
    
#     foreach my $a ( split( qr{\s*,\s*}, $selector ) )
#     {
# 	next unless $a;
	
# 	unless ( ref $SELECTION{$a} eq 'HASH' )
# 	{
# 	    return print_msg("INVALID SELECTOR: '$a'");
# 	}
	
# 	push @update_keys, $a;
#     }
    
#     my %update_values;
    
#     $update_values{IS_FIX} = 1 if $is_fix;
    
#     $rest =~ s{ set \s* }{}xsi;
    
#     while ( $rest =~ /\S/ )
#     {
# 	if ( $rest =~ qr{ ^ ( \w+ ) \s* = \s* ' ( [^']* ) ' [,\s]* (.*) }xsi )
# 	{
# 	    my $arg = $1;
# 	    my $value = $dbh->quote($2);
# 	    $rest = $3;
# 	    $update_values{$arg} = $value;
# 	}
	
# 	elsif ( $rest =~ qr{ ^ ( \w+ ) \s* = \s* " ( [^"]* ) " [,\s]* (.*) }xsi )
# 	{
# 	    my $arg = $1;
# 	    my $value = $dbh->quote($2);
# 	    $rest = $3;
# 	    $update_values{$arg} = $value;
# 	}
	
# 	elsif ( $rest =~ qr{ ^ ( \w+ ) \s* = \s* ( [\S]* ) (.*) }xsi )
# 	{
# 	    my $arg = $1;
# 	    my $value = $2;
# 	    $rest = $3;
# 	    $value =~ s/,+$//;
	    
# 	    unless ( $value =~ qr{ ^ -? [0-9]+ (?: [.][0-9]+ )? $ }xsi || 
# 		     $COLUMN_TYPE{$SELECT_TABLE}{$value} )
# 	    {
# 		return print_msg("ARGUMENT '$arg' must be quoted unless the value is numeric");
# 	    }
	    
# 	    $update_values{$arg} = $value;
# 	}
	
# 	else
# 	{
# 	    return print_msg("INVALID UPDATE ARGS: '$rest'");
# 	}
	
# 	$rest =~ s/^[,\s]+//;
#     }
    
#     foreach my $k ( keys %update_values )
#     {
# 	if ( $COLUMN_TYPE{$SELECT_TABLE}{$k} =~ qr{int}xsi )
# 	{
# 	    my $value = $update_values{$k};
	    
# 	    unless ( $value =~ qr{ ^ -? [0-9]+ $ }xsi || $COLUMN_TYPE{$SELECT_TABLE}{$value} =~ qr{int}xsi )
# 	    {
# 		print_msg("ARGUMENT '$k' must have an integer value.");
# 		return;
# 	    }
# 	}
#     }
    
#     foreach my $a (@update_keys)
#     {
# 	my $r = $SELECTION{$a};
# 	my $update_sub = $ACTION{$SELECT_TABLE}{update};
	
# 	if ( $update_sub )
# 	{
# 	    &$update_sub($dbt, $session, $r, \%update_values);
# 	}
	
# 	else
# 	{
# 	    return print_msg("UNIMPLEMENTED: $SELECT_TABLE");
# 	}
#     }
# }


# sub do_delete {
    
#     my ($dbt, $session, $rest) = @_;
    
#     unless ( $SELECT_TABLE && @SELECT_LIST )
#     {
# 	print_msg("NOTHING TO DELETE.");
# 	return;
#     }
    
#     unless ( $rest =~ qr{ ^ ( [,a-z]+ ) \s* (.*) }xs )
#     {
# 	print_msg("INVALID ARGUMENTS: '$rest'");
# 	return;
#     }
    
#     my $selector = $1;
#     my $rest = $2;
    
#     unless ( $COLUMN_INFO{$SELECT_TABLE} )
#     {
# 	my $dbh = $dbt->dbh;
# 	fetch_column_info($dbh, $SELECT_TABLE);
#     }
    
#     my @delete_keys;
    
#     foreach my $a ( split( qr{\s*,\s*}, $selector ) )
#     {
# 	next unless $a;
	
# 	unless ( ref $SELECTION{$a} eq 'HASH' )
# 	{
# 	    return print_msg("INVALID SELECTOR: '$a'");
# 	}
	
# 	push @delete_keys, $a;
#     }
    
#     foreach my $a (@delete_keys)
#     {
# 	my $r = $SELECTION{$a};
# 	my $delete_sub = $ACTION{$SELECT_TABLE}{delete};
	
# 	if ( $delete_sub )
# 	{
# 	    &$delete_sub($dbt, $session, $r);
# 	}
	
# 	else
# 	{
# 	    return print_msg("CANNOT DELETE FROM $SELECT_TABLE");
# 	}
#     }
# }


# sub do_unlink {

#     my ($dbt, $session, $rest) = @_;
    
#     unless ( $SELECT_TABLE && @SELECT_LIST )
#     {
# 	print_msg("NOTHING TO UNLINK.");
# 	return;
#     }
    
#     unless ( $rest =~ qr{ ^ ( \w+ ) \s+ ( [,a-z]+ ) \s* (.*) }xsi )
#     {
# 	print_msg("INVALID ARGUMENTS: '$rest'");
# 	return;
#     }
    
#     my $table_key = $1;
#     my $selector = $2;
#     my $rest = $3;
    
#     unless ( $TABLE{$table_key} && ref $TABLE{$table_key} eq 'ARRAY' )
#     {
# 	return print_msg "UNKNOWN TABLE: $table_key";
#     }
    
#     my ($target, $key) = @{$TABLE{$table_key}};
    
#     unless ( $COLUMN_INFO{$target} )
#     {
# 	my $dbh = $dbt->dbh;
# 	fetch_column_info($dbh, $target);
#     }
    
#     my @unlink_keys;
    
#     foreach my $a ( split( qr{\s*,\s*}, $selector ) )
#     {
# 	next unless $a;
	
# 	unless ( ref $SELECTION{$a} eq 'HASH' )
# 	{
# 	    return print_msg("INVALID SELECTOR: '$a'");
# 	}
	
# 	push @unlink_keys, $a;
#     }
    
#     foreach my $a (@unlink_keys)
#     {
# 	my $r = $SELECTION{$a};
# 	my $unlink_sub = $ACTION{$target}{unlink};
	
# 	if ( $unlink_sub )
# 	{
# 	    &$unlink_sub($dbt, $session, $r);
# 	}
	
# 	else
# 	{
# 	    return print_msg("CANNOT DELETE FROM $target");
# 	}
#     }


# }


# sub do_undo {
    
#     my ($dbt, $session, $option, $rest) = @_;
    
#     unless ( $rest =~ qr{ ^ ( [a-z][a-z]? ) $ }xsi )
#     {
# 	return print_msg("ERROR: invalid selector '$rest'");
#     }
    
#     my $selector = $1;
#     my $r = $UNDO_SEL{$selector};
    
#     unless ( ref $r eq 'HASH' )
#     {
# 	return print_msg("ERROR: no undo record found for '$selector'");
#     }
    
#     if ( $option eq '1' )
#     {
# 	return execute_undo($dbt, $session, $r);
#     }
    
#     elsif ( $option eq '2' )
#     {
# 	return execute_redo($dbt, $session, $r);
#     }
    
#     else
#     {
# 	return print_msg("ERROR: unknown option '$option'");
#     }
# }


# sub query_auth {
    
#     my ($dbh, $key, $keyval, $options) = @_;
    
#     my $fields = "a.*, t.status, t.spelling_no, t.opinion_no, t.synonym_no, t.$SETTINGS{accepted} as accepted_no, 
# 		t.$SETTINGS{immpar} as immpar_no, t.$SETTINGS{senpar} as senpar_no, t.lft, t.rgt,
# 		pt.name as parent_name, at.name as accepted_name, v.taxon_size,
# 		r.author1last as r_author1last, r.author2last as r_author2last,
# 		r.otherauthors as r_otherauthors, r.pubyr as r_pubyr";
#     my $sql;
    
#     my $where_clause;
    
#     if ( $options->{by_name} )
#     {
# 	$where_clause = "base.taxon_name like $keyval";
#     }
    
#     elsif ( $options->{by_selection} )
#     {
# 	my $taxon_no = $keyval->{child_spelling_no} || $keyval->{spelling_no} || $keyval->{taxon_no} || $keyval->{orig_no};
# 	$where_clause = "base.taxon_no = $taxon_no";
#     }
    
#     else
#     {
# 	$where_clause = "base.$key in ($keyval)";
#     }
    
#     $sql = "	SELECT $fields
# 		FROM authorities as a JOIN authorities as base using (orig_no)
# 			LEFT JOIN taxon_trees as t using (orig_no)
# 			LEFT JOIN taxon_attrs as v using (orig_no)
# 			LEFT JOIN taxon_ints as ph using (ints_no)
# 			LEFT JOIN refs as r on r.reference_no = a.reference_no
# 			LEFT JOIN taxon_trees as pt on pt.orig_no = t.$SETTINGS{immpar}
# 			LEFT JOIN taxon_trees as at on at.orig_no = t.$SETTINGS{accepted}
# 		WHERE $where_clause
# 		GROUP BY a.taxon_no";
        
#     return $sql;
# }


# sub list_auth {

#     my ($dbh, $result) = @_;
    
#     # First assemble print fields and determine maximum widths.
    
#     my $s = { };
    
#     clear_selection('authorities');
#     my $l = 'a';
    
#     foreach my $r ( @$result )
#     {
# 	my $taxon_name = $r->{taxon_name};
# 	my $taxon_rank = $r->{taxon_rank};
# 	my $taxon_no = $r->{taxon_no};
# 	my $orig_no = $r->{orig_no};
# 	my $opinion_no = $r->{opinion_no};
	
# 	my $status = $r->{status};
	
# 	my $attribution = auth_attribution($r);
	
# 	my $other_name = $status eq 'belongs to' ? $r->{parent_name} : $r->{accepted_name};
# 	my $other_no = $status eq 'belongs to' ? $r->{immpar_no} : $r->{accepted_no};

# 	$other_name .= " ($other_no)";
# 	$other_name .= " [in $r->{parent_name} ($r->{immpar_no})]"
# 	    if defined $r->{parent_name} && defined $r->{accepted_name} && $status ne 'belongs to' &&
# 		$r->{parent_name} ne $r->{accepted_name};
	
# 	my $opinion = "<$r->{opinion_no}>";
	
# 	$r->{current} = 1 if $r->{taxon_no} eq $r->{spelling_no};
# 	my $cflag = $r->{current} ? '*' : ' ';
	
# 	my $id_string = $taxon_no;
# 	$id_string .= " ($orig_no)" if $taxon_no ne $orig_no;
	
# 	my $auth_name = $PERSON{$r->{authorizer_no}};
# 	my $ent_name = $PERSON{$r->{enterer_no}};
# 	my $mod_name = $PERSON{$r->{modifier_no}};
	
# 	my $authent_string = $auth_name;
# 	$authent_string .= " ($ent_name)" if $ent_name ne $auth_name;
# 	$authent_string .= " / $mod_name" if $mod_name && $mod_name ne $ent_name;
	
# 	my $date_string = get_date($r->{created}) . ' : ' . get_date($r->{modified});
	
# 	set_field($r, $s, "basic", "$taxon_name [$attribution] : $id_string $cflag ");
# 	set_field($r, $s, "rank", $taxon_rank);
# 	set_field($r, $s, "status", "$status $other_name");
# 	set_field($r, $s, "opinion", $opinion);
# 	set_field($r, $s, "authent", $authent_string);
# 	set_field($r, $s, "crmod", $date_string);
#     }
    
#     foreach my $r ( @$result )
#     {
# 	print_record($l, make_fields($r, $s, "basic", "   ", "rank", "  ", "status", "  ", "opinion"),
# 		         make_fields($r, $s, "authent"),
# 			 make_fields($r, $s, "crmod"));
# 	add_to_selection($l, $r);
# 	$l++;
#     }
# }


# sub update_auth {

#     my ($dbt, $session, $r, $updates) = @_;
    
#     my $taxon_no = $r->{taxon_no};
#     my $dbh = $dbt->dbh;
    
#     unless ( $taxon_no && $taxon_no =~ qr{ ^ [0-9]+ $ }xs )
#     {
# 	return print_msg("ERROR: BAD TAXON_NO '$taxon_no'");
#     }
    
#     set_modifier($dbt, $session, $updates);
    
#     my $auth_entry = get_record($dbh, 'authorities', $taxon_no);
#     my $action_sql = make_update_sql($dbh, 'authorities', $taxon_no, $updates);
#     my $undo_sql = make_update_undo_sql($dbh, 'authorities', $taxon_no, $updates, $auth_entry);
    
#     # $dbt->updateRecord($session, 'authorities', 'taxon_no', $taxon_no,
#     # $updates);
    
#     # my $errmsg = $dbt->last_errmsg;
    
#     # if ( $errmsg )
#     # {
#     # 	print_msg("ERROR: $errmsg");
#     # 	return;
#     # }
    
#     # my ($action_sql, $undo_sql) = $dbt->last_sql;
    
#     my $event_type = $updates->{IS_FIX} ? 'FIX' : 'UPDATE';
    
#     my $updated = execute_sql($dbh, $action_sql);
    
#     unless ( $updated )
#     {
# 	print_msg("Update failed for '$taxon_no'.");
# 	return;
#     }
    
#     log_event($session, $event_type, 'authorities', $taxon_no, $action_sql, $undo_sql);
#     add_undo($r, $event_type, 'authorities', $action_sql, $undo_sql);
    
#     my $report_which = "$taxon_no \"$r->{taxon_name}\"";
    
#     print_msg("UPDATED authorities: $report_which");
    
#     return 1;
# }


# sub delete_auth {
    
#     my ($dbt, $session, $r) = @_;
    
#     my $taxon_no = $r->{taxon_no};
#     my $orig_no = $r->{orig_no};
#     my $spelling_no = $r->{spelling_no};
#     my $taxon_name = $r->{taxon_name};
#     my $taxon_size = $r->{taxon_size};
    
#     my $dbh = $dbt->{dbh};
    
#     # First make sure we actually have a valid taxon.
    
#     unless ( $taxon_no =~ qr{ ^ [0-9]+ $ }xsi )
#     {
# 	print_msg("ERROR: BAD TAXON_NO '$taxon_no'");
# 	return;
#     }
    
#     # Then see if this is the child_no or orig_no for any opinions.  If so,
#     # they must be deleted or updated first.
    
#     my $op_res = $dbh->selectall_arrayref("
# 		SELECT opinion_no, orig_no, child_spelling_no FROM order_opinions
# 		WHERE orig_no = $taxon_no or child_spelling_no = $taxon_no", { Slice => {} });
    
#     my ($op_string);
    
#     if ( ref $op_res eq 'ARRAY' && @$op_res )
#     {
# 	my @ops;
	
# 	foreach my $r ( @$op_res )
# 	{
# 	    push @ops, $r->{opinion_no};
# 	}
	
# 	$op_string = join(', ', @ops);
	
# 	if ( $op_string )
# 	{
# 	    print_msg("CANNOT DELETE: OPINIONS: $op_string");
# 	    return;
# 	}
#     }
    
#     # Then see if this is the orig_no for any other taxa.
    
#     my $linked_res = $dbh->selectall_arrayref("
# 		SELECT taxon_no, taxon_name FROM authorities
# 		WHERE orig_no = $taxon_no and taxon_no <> $taxon_no", { Slice => {} });
    
#     my ($linked_string, $linked_taxa);
    
#     if ( ref $linked_res eq 'ARRAY' && @$linked_res )
#     {
# 	my (@names, @taxa);
	
# 	foreach my $r ( @$linked_res )
# 	{
# 	    next if $r->{taxon_no} eq $taxon_no;	# ignore the taxon to
#                                                         # be deleted, of course
# 	    push @names, "$r->{taxon_name} ($r->{taxon_no})";
# 	    #push @taxa, $a->{taxon_no};
# 	}
	
# 	$linked_string = join(', ', @names);
# 	#$linked_taxa = join(', ', @taxa);
	
# 	if ( $linked_string )
# 	{
# 	    print_msg("CANNOT DELETE: ORIG_NO: $linked_string");
# 	    return;
# 	}
#     }
    
#     # Then see if this is the taxon_no for any occurrences.
    
#     my $occs_list = $dbh->selectcol_arrayref("
# 		SELECT occurrence_no FROM occ_matrix
# 		WHERE taxon_no = $taxon_no", { Slice => {} });
    
#     if ( ref $occs_list eq 'ARRAY' && @$occs_list )
#     {
# 	my $occs_string = join(', ', @$occs_list);
	
# 	print_msg("CANNOT DELETE: OCCURRENCES: $occs_string");
# 	return;
#     }
    
#     # If this is the orig_no we are deleting, and if it has children and/or
#     # junior synonyms, then confirm.  These will all have to be detached from
#     # the hierarchy if this taxon is deleted.
    
#     if ( $taxon_no eq $orig_no )
#     {
# 	my $dependent_nos = $dbh->selectcol_arrayref("
# 		SELECT orig_no FROM taxon_trees
# 		WHERE ($SETTINGS{immpar} = $orig_no or $SETTINGS{senpar} = $orig_no or $SETTINGS{accepted} = $orig_no)
# 			and orig_no <> $orig_no");
	
# 	my @dependents = ref $dependent_nos eq 'ARRAY' ? @$dependent_nos : ();
	
# 	if ( @dependents )
# 	{
# 	    my $dep_string = join(', ', @dependents);
# 	    print_msg("CANNOT DELETE: DEPENDENTS: $dep_string");
# 	    return;
# 	}
#     }
    
#     # Otherwise, we may need to set the spelling_no field to something else.  We
#     # set it to orig_no for now.
    
#     else
#     {
# 	my $result = $dbh->do("
# 		UPDATE taxon_trees SET spelling_no = orig_no
# 		WHERE orig_no = $orig_no and spelling_no = $taxon_no");
	
# 	print_msg("RESET spelling_no for taxon_trees entry: $orig_no") if $result;
#     }
    
#     # If we get here, then all of the preconditions for deleting the authority
#     # record are met.  We also need to delete the taxa_tree_cache entry
#     # corresponding to this authority record, and also the taxon_trees entry
#     # if $taxon_no == $orig_no.
    
#     # $dbt->deleteRecord($session, 'authorities', 'taxon_no', $taxon_no);
    
#     # my $errmsg = $dbt->last_errmsg;
    
#     # if ( $errmsg )
#     # {
#     # 	print_msg("ERROR: $errmsg");
#     # 	return;
#     # }
    
#     # my ($action_sql, $undo_sql) = $dbt->last_sql;
    
#     my $auth_entry = get_record($dbh, 'authorities', $taxon_no);
#     my $ttc_entry = get_record($dbh, 'taxa_tree_cache', $taxon_no);
#     my $tt_entry = get_record($dbh, 'taxon_trees', $taxon_no);
    
#     # First delete the authority record and log it.
    
#     my $action_sql = make_delete_sql($dbh, 'authorities', $taxon_no);
#     my $undo_sql = make_replace_sql($dbh, 'authorities', $auth_entry);
    
#     my $deleted_auth = execute_sql($dbh, $action_sql);
    
#     unless ( $deleted_auth )
#     {
# 	print_msg("Delete failed: '$taxon_no'");
# 	return;
#     }
    
#     log_event($session, 'DELETE', 'authorities', $taxon_no, $action_sql, $undo_sql);
    
#     my $string = "$taxon_name : $orig_no";
#     $string .= " ($taxon_no)" if $taxon_no ne $orig_no;
    
#     print_msg("DELETED authority: $string");
    
#     # Then delete one or possibly both auxiliary records.  These sub-actions
#     # are not logged, since they are derived algorithmically from the
#     # authority and opinion tables.  But we need to add them to the undo
#     # record so that we can undo this action if requested later.  The
#     # taxon_trees entry is only deleted if one actually exists (i.e. if
#     # $taxon_no == $orig_no).
    
#     $r->{TTC_ENTRY} = get_record($dbh, 'taxa_tree_cache', $taxon_no);
#     $r->{TT_ENTRY} = get_record($dbh, 'taxon_trees', $taxon_no);
    
#     my $undo = add_undo($r, 'DELETE', 'authorities', $action_sql, $undo_sql);
    
#     do_aux_delete($dbh, $undo);
    
#     return 1;
# }


# sub aux_del_auth {
    
#     my ($dbh, $r) = @_;
    
#     my $taxon_no = $r->{taxon_no};
    
#     my $ttc_delete_sql = make_delete_sql($dbh, 'taxa_tree_cache', $taxon_no);
#     my $tt_delete_sql = make_delete_sql($dbh, 'taxon_trees', $taxon_no);
    
#     if ( execute_sql($dbh, $ttc_delete_sql) )
#     {
# 	print_msg("DELETED taxa_tree_cache: $taxon_no");
#     }
    
#     if ( $r->{TT_ENTRY} && execute_sql($dbh, $tt_delete_sql) )
#     {
# 	print_msg("DELETED taxon_trees: $taxon_no");
#     }
# }


# sub aux_add_auth {
    
#     my ($dbh, $r) = @_;
    
#     my $taxon_no = $r->{taxon_no};
    
#     if ( $r->{TTC_ENTRY} )
#     {
# 	my $ttc_sql = make_replace_sql($dbh, 'taxa_tree_cache', $r->{TTC_ENTRY});
	
# 	if ( execute_sql($dbh, $ttc_sql) )
# 	{
# 	    print_msg("RECREATED taxa_tree_cache: $taxon_no");
# 	}
#     }
    
#     if ( $r->{TT_ENTRY} )
#     {
# 	my $tt_sql = make_replace_sql($dbh, 'taxon_trees', $r->{TT_ENTRY});
	
# 	if ( execute_sql($dbh, $tt_sql) )
# 	{
# 	    print_msg("RECREATED taxon_trees: $taxon_no");
# 	}
#     }
# }


# sub auth_attribution {
    
#     my ($r) = @_;
    
#     return 'unknown' unless defined $r->{ref_is_authority} || defined $r->{ac_ref_is_authority};
    
#     my $prefix = '';
    
#     if ( $r->{ac_ref_is_authority} )
#     {
# 	$prefix = 'rc_';
#     }
    
#     elsif ( $r->{ref_is_authority} )
#     {
# 	$prefix = 'r_';
#     }
    
#     elsif ( $r->{ac_author1last} )
#     {
# 	$prefix = 'ac_';
#     }
    
#     my $attr = $r->{"${prefix}author1last"};
#     my $pubyr = $r->{"${prefix}pubyr"};
    
#     if ( $r->{"${prefix}otherauthors"} )
#     {
# 	$attr .= " et. al.";
#     }
    
#     elsif ( $r->{"${prefix}author2last"} )
#     {
# 	$attr .= " and $r->{rc_author2last}";
#     }
    
#     # elsif ( $r->{ref_is_authority} )
#     # {
#     # 	$attr = $r->{r_author1last};
#     # 	$pubyr = $r->{r_pubyr};
	
#     # 	if ( $r->{r_otherauthors} )
#     # 	{
#     # 	    $attr .= " et. al.";
#     # 	}
	
#     # 	elsif ( $r->{r_author2last} )
#     # 	{
#     # 	    $attr .= " and $r->{r_author2last}";
#     # 	}
#     # }
    
#     # elsif ( $r->{ac_author1last} )
#     # {
#     # 	$attr = $r->{ac_author1last};
#     # 	$pubyr = $r->{ac_pubyr};
	
#     # 	if ( $r->{ac_otherauthors} )
#     # 	{
#     # 	    $attr .= "et. al.";
#     # 	}
	
#     # 	elsif ( $r->{ac_author2last} )
#     # 	{
#     # 	    $attr .= " and $r->{ac_author2last}";
#     # 	}
#     # }
    
#     # else
#     # {
#     # 	$attr = $r->{author1last};
#     # 	$pubyr = $r->{pubyr};
	
#     # 	if ( $r->{otherauthors} )
#     # 	{
#     # 	    $attr .= "et. al.";
#     # 	}
	
#     # 	elsif ( $r->{author2last} )
#     # 	{
#     # 	    $attr .= " and $r->{author2last}";
#     # 	}
#     # }
    
#     if ( $attr && $pubyr )
#     {
# 	return "$attr $pubyr";
#     }
    
#     elsif ( $pubyr )
#     {
# 	return $pubyr;
#     }
    
#     elsif ( $attr )
#     {
# 	return $attr;
#     }
    
#     else
#     {
# 	return 'unknown';
#     }
# }


# sub query_tt {
    
#     my ($dbh, $key, $keyval, $options) = @_;    
    
#     my $fields = "t.orig_no, t.spelling_no, t.name as taxon_name, t.rank as taxon_rank, t.opinion_no as class_no,
# 		t.status, t.spelling_no, t.synonym_no, t.$SETTINGS{accepted} as accepted_no, t.lft, t.rgt, 
# 		pt.name as parent_name, t.$SETTINGS{immpar} as immpar_no, t.$SETTINGS{senpar} as senpar_no, at.name as accepted_name";
#     my $sql;
    
#     my $where_clause;
    
#     if ( $options->{by_name} || $key eq 'taxon_name' )
#     {
# 	$where_clause = "t.name like $keyval";
#     }
    
#     elsif ( $options->{by_selection} )
#     {
# 	my $orig_no = $keyval->{child_no} || $keyval->{orig_no} || $keyval->{taxon_no};
# 	$where_clause = "t.orig_no = $orig_no";
#     }
    
#     else
#     {
# 	$where_clause = "t.orig_no = $keyval";
#     }
    
#     $sql = "	SELECT $fields
# 		FROM taxon_trees as t
# 			LEFT JOIN taxon_attrs as v using (orig_no)
# 			LEFT JOIN taxon_ints as ph using (ints_no)
# 			LEFT JOIN taxon_trees as pt on pt.orig_no = t.$SETTINGS{immpar}
# 			LEFT JOIN taxon_trees as at on at.orig_no = t.$SETTINGS{accepted}
# 		WHERE $where_clause
# 		GROUP BY t.orig_no";
    
#     return $sql;
# }


# sub list_tt {

#     my ($dbh, $result) = @_;
    
#     # First assemble print fields and determine maximum widths.
    
#     my $s = { };
    
#     clear_selection('taxon_trees');
#     my $l = 'a';
    
#     foreach my $r ( @$result )
#     {
# 	my $taxon_name = $r->{taxon_name};
# 	my $taxon_rank = $RANK_STRING{$r->{taxon_rank}};
# 	my $orig_no = $r->{orig_no};
# 	my $spelling_no = $r->{spelling_no};
	
# 	my $status = $r->{status};
	
# 	my $other_name = $status eq 'belongs to' ? $r->{parent_name} : $r->{accepted_name};
# 	my $other_no = $status eq 'belongs to' ? $r->{immpar_no} : $r->{accepted_no};
	
# 	$other_name .= " ($other_no)";
# 	$other_name .= " [in $r->{parent_name} ($r->{immpar_no})]"
# 	    if defined $r->{parent_name} && defined $r->{accepted_name} && $status =~ qr{synonym|replaced} &&
# 		$r->{parent_name} ne $r->{accepted_name};
	
# 	my $id_string = "$taxon_name : $orig_no";
# 	$id_string .= " ($spelling_no)" if $spelling_no ne $orig_no;
	
# 	my $opinion = "<$r->{class_no}>";
	
# 	set_field($r, $s, "basic", $id_string);
# 	set_field($r, $s, "rank", $taxon_rank);
# 	set_field($r, $s, "status", "$status $other_name");
# 	set_field($r, $s, "opinion", $opinion);
#     }
    
#     foreach my $r ( @$result )
#     {
# 	print_record($l, make_fields($r, $s, "basic", "   ", "rank", "  ", "status", "  ", "opinion"));
# 	add_to_selection($l, $r);
# 	$l++;
#     }
# }


# sub update_tt {

#     my ($dbt, $session, $r, $updates) = @_;
    
#     my $orig_no = $r->{orig_no};
#     my $dbh = $dbt->dbh;
    
#     unless ( $orig_no && $orig_no =~ qr{ ^ [0-9]+ $ }xsi )
#     {
# 	print_msg("ERROR: BAD ORIG_NO '$orig_no'");
# 	return;
#     }
    
#     my $tt_entry = get_record($dbh, 'taxon_trees', $r->{orig_no});
#     my $action_sql = make_update_sql($dbh, 'taxon_trees', $r->{orig_no}, $updates);
#     my $undo_sql = make_update_undo_sql($dbh, 'taxon_trees', $r->{orig_no}, $updates, $tt_entry);
    
#     my $updated = execute_sql($dbh, $action_sql);
    
#     unless ( $updated )
#     {
# 	print_msg("Update failed.");
# 	return;
#     }
    
#     add_undo($r, 'FIX', 'taxon_trees', $action_sql, $undo_sql);
    
#     print_msg("UPDATED taxon_trees: $orig_no");
    
#     return 1;
# }


# sub unlink_tt {
    
#     my ($dbt, $session, $r, $substitute) = @_;
    
#     my $orig_no = $r->{orig_no};
#     my $dbh = $dbt->dbh;
    
#     unless ( $orig_no && $orig_no =~ qr{ ^ [0-9]+ $ }xsi )
#     {
# 	print_msg("ERROR: BAD ORIG_NO '$orig_no'");
# 	return;
#     }
    
#     unlink_tt_aspect($dbt, $session, $r, $SETTINGS{accepted}, $substitute);
#     unlink_tt_aspect($dbt, $session, $r, 'synonym_no', $substitute);
#     unlink_tt_aspect($dbt, $session, $r, $SETTINGS{immpar}, $substitute);
#     unlink_tt_aspect($dbt, $session, $r, $SETTINGS{senpar}, $substitute);    
    
#     # my ($synonym) = $dbh->selectcol_arrayref("
#     # 		SELECT orig_no FROM taxon_trees WHERE synonym_no = $orig_no");
    
#     # if ( ref $synonym eq 'ARRAY' && @$synonym )
#     # {
#     # 	my $key_list = join(',', @$synonym);
#     # 	my %updates = ( synonym_no => 0 );
#     # 	my %undos = ( synonym_no => $orig_no );
	
#     # 	my $action_sql = make_multifix_sql($dbh, 'taxon_trees', $key_list, \%updates);
#     # 	my $undo_sql = make_multifix_sql($dbh, 'taxon_trees', $key_list, \%undos);
	
#     # 	my $unlinked = execute_sql($dbh, $action_sql);
	
#     # 	unless ( $unlinked )
#     # 	{
#     # 	    print_msg("Unlink failed for 'synonym_no'.");
#     # 	}
	
#     # 	else
#     # 	{
#     # 	    log_event($session, 'FIX', 'taxon_trees', $key_list, $action_sql, $undo_sql);
#     # 	    add_undo($r, 'FIX', 'taxon_trees', $action_sql, $undo_sql);
#     # 	    print_msg("UNLINKED taxon_trees for 'synonym_no': $key_list");
#     # 	}
#     # }    
    
#     # my ($parent) = $dbh->selectcol_arrayref("
#     # 		SELECT orig_no FROM taxon_trees WHERE $SETTINGS{immpar} = $orig_no");
    
#     # if ( ref $parent eq 'ARRAY' && @$parent )
#     # {
#     # 	my $key_list = join(',', @$parent);
#     # 	my %updates = ( $SETTINGS{immpar} => 0 );
#     # 	my %undos = ( $SETTINGS{immpar} => $orig_no );
	
#     # 	my $action_sql = make_multifix_sql($dbh, 'taxon_trees', $key_list, \%updates);
#     # 	my $undo_sql = make_multifix_sql($dbh, 'taxon_trees', $key_list, \%undos);
	
#     # 	my $unlinked = execute_sql($dbh, $action_sql);
	
#     # 	unless ( $unlinked )
#     # 	{
#     # 	    print_msg("Unlink failed for '$SETTINGS{immpar}'.");
#     # 	}
	
#     # 	else
#     # 	{
#     # 	    log_event($session, 'FIX', 'taxon_trees', $key_list, $action_sql, $undo_sql);
#     # 	    add_undo($r, 'FIX', 'taxon_trees', $action_sql, $undo_sql);
#     # 	    print_msg("UNLINKED taxon_trees for '$SETTINGS{immpar}': $orig_no");
#     # 	}
#     # }    
    
#     # my ($senpar) = $dbh->selectcol_arrayref("
#     # 		SELECT orig_no FROM taxon_trees WHERE $SETTINGS{senpar} = $orig_no");
    
#     # if ( ref $parent eq 'ARRAY' && @$parent )
#     # {
#     # 	my $key_list = join(',', @$parent);
#     # 	my %updates = ( $SETTINGS{senpar} => 0 );
#     # 	my %undos = ( $SETTINGS{senpar} => $orig_no );
	
#     # 	my $action_sql = make_multifix_sql($dbh, 'taxon_trees', $key_list, \%updates);
#     # 	my $undo_sql = make_multifix_sql($dbh, 'taxon_trees', $key_list, \%undos);
	
#     # 	my $unlinked = execute_sql($dbh, $action_sql);
	
#     # 	unless ( $unlinked )
#     # 	{
#     # 	    print_msg("Unlink failed for '$SETTINGS{senpar}'.");
#     # 	}
	
#     # 	else
#     # 	{
#     # 	    log_event($session, 'FIX', 'taxon_trees', $key_list, $action_sql, $undo_sql);
#     # 	    add_undo($r, 'FIX', 'taxon_trees', $action_sql, $undo_sql);
#     # 	    print_msg("UNLINKED taxon_trees for '$SETTINGS{senpar}': $key_list");
#     # 	}
#     # }    
    
#     return 1;
# }


# sub unlink_tt_aspect {

#     my ($dbt, $session, $r, $linkfield, $substitute) = @_;
    
#     my $orig_no = $r->{orig_no};
#     my $dbh = $dbt->dbh;
    
#     $substitute //= 0;
    
#     my ($list) = $dbh->selectcol_arrayref("
# 		SELECT orig_no FROM taxon_trees WHERE $linkfield = $orig_no");
    
#     return unless ref $list eq 'ARRAY' && @$list;
    
#     my %updates = ( $linkfield => $substitute );
#     my %undos = ( $linkfield => $orig_no );
#     my $key_string = join(',', @$list);
    
#     my $action_sql = make_multifix_sql($dbh, 'taxon_trees', $key_string, \%updates);
#     my $undo_sql = make_multifix_sql($dbh, 'taxon_trees', $key_string, \%undos);
    
#     my $unlinked = execute_sql($dbh, $action_sql);
    
#     unless ( $unlinked )
#     {
# 	return print_msg("Unlink failed for '$linkfield'.");
#     }
    
#     else
#     {
# 	log_event($session, 'FIX', 'taxon_trees', $orig_no, $action_sql, $undo_sql);
# 	add_undo($r, 'FIX', 'taxon_trees', $action_sql, $undo_sql);
# 	print_msg("UNLINKED taxon_trees for '$linkfield': $key_string");
#     }
    
#     return 1;
# }


# sub query_ops {
    
#     my ($dbh, $key, $keyval, $options) = @_;    
    
#     my $fields = "o.*, oo.orig_no as oo_orig_no, oo.ri, oo.pubyr as oo_pubyr, oo.parent_no as oo_parent_no,
# 		ac.orig_no, t.name as current_name, t.opinion_no as class_no,
# 		ac.taxon_name as child_name, ac.taxon_rank as child_rank, ac.ref_is_authority as ac_ref_is_authority,
# 		ac.author1last as ac_author1last, ac.author2last as ac_author2last, ac.otherauthors as ac_otherauthors,
# 		ac.pubyr as ac_pubyr, rc.author1last as rc_author1last, rc.author2last as rc_author2last,
# 		rc.otherauthors as rc_otherauthors, rc.pubyr as rc_pubyr,
# 		ap.taxon_name as parent_name";
#     my $sql;
    
#     if ( $key eq 'opinion_no' && ! $options->{by_name} )
#     {
# 	my $opinion_no = $options->{by_selection} ? ($keyval->{opinion_no} || $keyval->{class_no}): $keyval;
	
# 	$sql = "SELECT $fields
# 		FROM opinions as o join order_opinions as oo using (opinion_no)
# 			LEFT JOIN authorities as ac on ac.taxon_no = o.child_spelling_no
# 			LEFT JOIN refs as rc on rc.reference_no = ac.reference_no
# 			LEFT JOIN authorities as ap on ap.taxon_no = o.parent_spelling_no
# 			LEFT JOIN taxon_trees as t on t.orig_no = ac.orig_no
# 		WHERE o.opinion_no in ($opinion_no)
# 		GROUP BY o.opinion_no";
#     }
    
#     else
#     {
# 	my $where_clause = ($options->{by_name} || $key eq 'taxon_name') ? "base.taxon_name like $keyval" : 
# 	    "base.taxon_no in ($keyval)";
	
# 	$where_clause .= " and o.opinion_no = t.opinion_no" unless $options->{all};
	
# 	my $order_clause = $options->{all} ? "ORDER BY if(o.opinion_no = t.opinion_no, 0, 1)" : "";
	
# 	$sql = "SELECT $fields
# 		FROM authorities as base JOIN opinions as o on (o.child_no = base.taxon_no or o.child_spelling_no = base.taxon_no)
# 			JOIN order_opinions as oo using (opinion_no)
# 			LEFT JOIN authorities as ac on ac.taxon_no = o.child_spelling_no
# 			LEFT JOIN taxon_trees as t on t.orig_no = ac.orig_no
# 			LEFT JOIN refs as rc on rc.reference_no = ac.reference_no
# 			LEFT JOIN authorities as ap on ap.taxon_no = o.parent_spelling_no
# 		WHERE $where_clause
# 		GROUP BY o.opinion_no $order_clause";
#     }
    
#     return $sql;
# }


# sub list_ops {

#     my ($dbh, $result) = @_;
    
#     # First assemble print fields and determine maximum widths.
    
#     my $s = { };
    
#     clear_selection('opinions');
#     my $l = 'a';
    
#     foreach my $r ( @$result )
#     {
# 	my $child_name = $r->{child_name};
# 	my $child_rank = $r->{child_rank};
# 	my $parent_name = $r->{parent_name};
# 	my $status = $r->{status};
# 	$status .= " ($r->{spelling_reason})" if $r->{spelling_reason} && $r->{spelling_reason} ne 'original spelling';
# 	my $spelling_no = $r->{spelling_no};
	
# 	my $child_attr = auth_attribution($r);
	
# 	my $child = "$r->{child_name} [$child_attr] : $r->{child_spelling_no}";
# 	$child .= " ($r->{child_no})" if $r->{child_spelling_no} ne $r->{child_no};
# 	$child .= " (* $r->{oo_orig_no} *)" if $r->{oo_orig_no} ne $r->{orig_no};
	
# 	my $parent_name = "$r->{parent_name} : $r->{parent_no}";
# 	$parent_name .= " (* $r->{oo_parent_no} *)" if $r->{oo_parent_no} ne $r->{parent_no};
	
# 	my $author_string = "$r->{author} $r->{pubyr}";
	
# 	my $flag = $r->{opinion_no} eq $r->{class_no} ? "  [*]  " : "       ";
	
# 	my $auth_name = $PERSON{$r->{authorizer_no}};
# 	my $ent_name = $PERSON{$r->{enterer_no}};
# 	my $mod_name = $PERSON{$r->{modifier_no}};
	
# 	my $authent_string = $auth_name;
# 	$authent_string .= " ($ent_name)" if $ent_name ne $auth_name;
# 	$authent_string .= " / $mod_name" if $mod_name && $mod_name ne $ent_name;
	
# 	my $date_string = get_date($r->{created}) . ' : ' . get_date($r->{modified});
	
# 	set_field($r, $s, "id", $r->{opinion_no});
# 	set_field($r, $s, "child", $child);
# 	set_field($r, $s, "flag", $flag);
# 	set_field($r, $s, "status", $status);
# 	set_field($r, $s, "parent", $parent_name);
# 	set_field($r, $s, "rank", $child_rank);
# 	set_field($r, $s, "author", $author_string);
# 	set_field($r, $s, "authent", $authent_string);
# 	set_field($r, $s, "crmod", $date_string);
#     }
    
#     foreach my $r ( @$result )
#     {
# 	print_record($l, make_fields($r, $s, "id", "  ", "child", "flag", "status", "   ", "parent"),
# 		         make_fields($r, $s, ">child", "rank", "   ", "author"),
# 			 make_fields($r, $s, "authent"),
# 			 make_fields($r, $s, "crmod"));
# 	add_to_selection($l, $r);
# 	$l++;
#     }
# }


# sub update_opinion {
    
#     my ($dbt, $session, $r, $updates) = @_;
    
#     my $opinion_no = $r->{opinion_no};
#     my $dbh = $dbt->dbh;
    
#     unless ( $opinion_no && $opinion_no =~ qr{ ^ [0-9]+ $ }xs )
#     {
# 	return print_msg("ERROR: BAD OPINION_NO '$opinion_no'");
#     }
    
#     set_modifier($dbt, $session, $updates);
    
#     my $op_entry = get_record($dbh, 'opinions', $opinion_no);
#     my $action_sql = make_update_sql($dbh, 'opinions', $opinion_no, $updates);
#     my $undo_sql = make_update_undo_sql($dbh, 'opinions', $opinion_no, $updates, $op_entry);
    
#     my $event_type = $updates->{IS_FIX} ? 'FIX' : 'UPDATE';
    
#     my $updated = execute_sql($dbh, $action_sql);
    
#     unless ( $updated )
#     {
# 	print_msg("Update failed for '$opinion_no'.");
# 	return;
#     }
    
#     log_event($session, $event_type, 'opinions', $opinion_no, $action_sql, $undo_sql);
    
#     print_msg("Updated opinion: $opinion_no");
    
#     my $undo = add_undo($r, $event_type, 'opinions', $action_sql, $undo_sql);
    
#     do_aux_update($dbh, $undo);
    
#     return 1;
# }


# sub aux_update_opinion {

#     my ($dbh, $r) = @_;
    
#     my $opinion_no = $r->{opinion_no};
    
#     fixOpinionCache($dbh, 'order_opinions', 'taxon_trees', $opinion_no);
# }


# sub delete_opinion {
    
#     my ($dbt, $session, $r) = @_;
    
#     my $opinion_no = $r->{opinion_no};
#     my $child_name = $r->{child_name};
#     my $dbh = $dbt->{dbh};
    
#     # First make sure we actually have a valid opinion.
    
#     unless ( $opinion_no && $opinion_no =~ qr{ ^ [0-9]+ $ }xsi )
#     {
# 	print_msg("ERROR: BAD OPINION_NO '$opinion_no'");
# 	return;
#     }
    
#     # Then see if this is the classification opinion for any taxa.
#     # If so, they must be deleted or updated first.
    
#     my $op_res = $dbh->selectall_arrayref("
# 		SELECT orig_no, name FROM taxon_trees
# 		WHERE opinion_no = $opinion_no", { Slice => {} });
    
#     my ($op_string);
    
#     if ( ref $op_res eq 'ARRAY' && @$op_res )
#     {
# 	my @taxa;
	
# 	foreach my $r ( @$op_res )
# 	{
# 	    push @taxa, $r->{taxon_no} . " (" . $r->{orig_no} . ")";
# 	}
	
# 	$op_string = join(', ', @taxa);
	
# 	if ( $op_string )
# 	{
# 	    print_msg("CANNOT DELETE: CLASSIFICATIONS: $op_string");
# 	    return;
# 	}
#     }
    
#     # If we get here then we have passed all of the preconditions for deleting
#     # an opinion record.
    
#     my $op_entry = get_record($dbh, 'opinions', $opinion_no);
#     my $action_sql = make_delete_sql($dbh, 'opinions', $opinion_no);
#     my $undo_sql = make_replace_sql($dbh, 'opinions', $op_entry);
    
#     my $deleted_main = execute_sql($dbh, $action_sql);
    
#     unless ( $deleted_main )
#     {
# 	print_msg("Delete failed: '$opinion_no'");
# 	return;
#     }
    
#     my $string = "$opinion_no : $r->{child_name} ($r->{child_spelling_no}) ";
#     $string .= "$r->{status} ";
#     $string .= "$r->{parent_name} ($r->{parent_spelling_no})";
    
#     print_msg("DELETED opinion: $string");
    
#     log_event($session, 'DELETE', 'opinions', $opinion_no, $action_sql, $undo_sql);
    
#     my $undo = add_undo($r, 'DELETE', 'opinions', [$action_sql], [$undo_sql]);
    
#     do_aux_delete($dbh, $undo);
    
#     return 1;
# }


# sub aux_del_opinion {	# add aux_add_opinion

#     my ($dbh, $r) = @_;
    
#     my $opinion_no = $r->{opinion_no};
    
#     my $delete_sql = make_delete_sql($dbh, 'order_opinions', $opinion_no);
    
#     if ( execute_sql($dbh, $delete_sql) )
#     {
# 	print_msg("DELETED order_opinions: $opinion_no");
#     }
    
#     my $a = 1;	# we can stop here when debugging
# }


# sub occ_or_reid_ident {
    
#     my ($r) = @_;
    
#     my $ident = $r->{genus_name};
#     my $check = $r->{genus_name};
    
#     $ident .= " $r->{genus_reso}" if $r->{genus_reso};
    
#     if ( $r->{subgenus_name} )
#     {
# 	$ident .= " ($r->{subgenus_name}";
# 	$ident .= " $r->{subgenus_reso}" if $r->{subgenus_reso};
# 	$ident .= ")";
# 	$check .= " ($r->{subgenus_name})";
#     }
    
#     if ( $r->{species_name} )
#     {
# 	$ident .= " $r->{species_name}";
# 	$ident .= " $r->{species_reso}" if $r->{species_reso};
# 	$check .= " $r->{species_name}";
#     }
    
#     return ($ident, $check);
# }


# sub query_occs {
    
#     my ($dbh, $key, $keyval, $options) = @_;    
    
#     my $fields = "o.*, t.name as current_name, t.$SETTINGS{accepted} as accepted_no, at.name as accepted_name";
    
#     my $sql;
    
#     if ( $key eq 'taxon_name' || $options->{by_name} )
#     {
# 	$sql = "SELECT $fields
# 		FROM authorities as base JOIN $OCC_MATRIX as o using (orig_no)
# 			JOIN $OCCURRENCES as oo using (occurrence_no)
# 			LEFT JOIN authorities as a on a.taxon_no = o.taxon_no
# 			LEFT JOIN taxon_trees as t on t.orig_no = o.orig_no
# 			LEFT JOIN taxon_trees as at on at.orig_no = t.accepted_no
# 		WHERE base.taxon_name like $keyval
# 		GROUP BY o.occurrence_no";
#     }
    
#     elsif ( $key eq 'occurrence_no' || $key eq 'orig_no' || $key eq 'taxon_no' )
#     {
# 	my $value = $keyval;
	
# 	if ( $options->{by_selection} )
# 	{
# 	    $value = $keyval->{$key};
# 	    return print_msg("No value found for '$key'") unless $value;
# 	}
	
# 	$sql = "SELECT $fields
# 		FROM $OCC_MATRIX as o join $OCCURRENCES as oo using (occurrence_no)
# 			LEFT JOIN authorities as a on a.taxon_no = o.taxon_no
# 			LEFT JOIN taxon_trees as t on t.orig_no = o.orig_no
# 			LEFT JOIN taxon_trees as at on at.orig_no = t.$SETTINGS{accepted}
# 		WHERE o.$key in ($value)
# 		GROUP BY o.occurrence_no";
#     }
    
#     else
#     {
# 	croak "Invalid key '$key'";
#     }
    
#     return $sql;
# }


# sub list_occs {

#     my ($dbh, $result) = @_;
    
#     # First assemble print fields and determine maximum widths.
    
#     my $s = { };
    
#     clear_selection('occurrences');
#     my $l = 'a';
    
#     foreach my $r ( @$result )
#     {
# 	my ($ident, $check) = occ_or_reid_ident($r);
# 	my $orig_no = $r->{orig_no};
# 	my $taxon_no = $r->{taxon_no};
	
# 	$ident .= " : $orig_no";
# 	$ident .= " ($taxon_no)" if $taxon_no ne $orig_no;
	
# 	my $accepted = $r->{accepted_name};
# 	$accepted .= " ($r->{accepted_no})" if $r->{accepted_no} ne $orig_no;
	
# 	my $auth_name = $PERSON{$r->{authorizer_no}};
# 	my $ent_name = $PERSON{$r->{enterer_no}};
# 	my $mod_name = $PERSON{$r->{modifier_no}};
	
# 	my $authent_string = $auth_name;
# 	$authent_string .= " ($ent_name)" if $ent_name ne $auth_name;
# 	$authent_string .= " / $mod_name" if $mod_name && $mod_name ne $ent_name;
	
# 	my $date_string = get_date($r->{created}) . ' : ' . get_date($r->{modified});
	
# 	set_field($r, $s, "id", $r->{occurrence_no});
# 	set_field($r, $s, "ident", $ident);
# 	set_field($r, $s, "accepted", $accepted);
# 	set_field($r, $s, "authent", $authent_string);
# 	set_field($r, $s, "crmod", $date_string);

#     }
    
#     foreach my $r ( @$result )
#     {
# 	print_record($l, make_fields($r, $s, "id", "  ", "ident", "   ", "accepted"),
# 			 make_fields($r, $s, "authent"),
# 		         make_fields($r, $s, "crmod"));
# 	add_to_selection($l, $r);
# 	$l++;
#     }
# }


# sub update_occ {
    
#     my ($dbt, $session, $r, $updates) = @_;
    
#     my $occurrence_no = $r->{occurrence_no};
#     my $dbh = $dbt->dbh;
    
#     unless ( $occurrence_no && $occurrence_no =~ qr{ ^ [0-9]+ $ }xs )
#     {
# 	return print_msg("CANNOT UPDATE RECORD: occurrence_no = '$occurrence_no'");
#     }
    
#     set_modifier($dbt, $session, $updates);
    
#     my $occ_entry = get_record($dbh, 'occurrences', $occurrence_no);
#     my $action_sql = make_update_sql($dbh, 'occurrences', $occurrence_no, $updates);
#     my $undo_sql = make_update_undo_sql($dbh, 'occurrences', $occurrence_no, $updates, $occ_entry);
    
#     my $event_type = $updates->{IS_FIX} ? 'FIX' : 'UPDATE';
    
#     my $updated = execute_sql($dbh, $action_sql);
    
#     unless ( $updated )
#     {
# 	print_msg("Update failed for '$occurrence_no'.");
# 	return;
#     }
    
#     print_msg("UPDATED occurrence: $occurrence_no");
    
#     log_event($session, $event_type, 'occurrences', $occurrence_no, $action_sql, $undo_sql);
    
#     my $undo = add_undo($r, $event_type, 'occurrences', [$action_sql], [$undo_sql]);
    
#     do_aux_update($dbh, $undo);
    
#     return 1;
# }


# sub aux_update_occ {
    
#     my ($dbh, $r) = @_;
    
#     my $occurrence_no = $r->{occurrence_no};
#     updateOccurrenceMatrix($dbh, $occurrence_no);
    
#     print_msg("UPDATED $OCC_MATRIX: $occurrence_no");
# }


# sub delete_occ {
    
#     my ($dbt, $session, $r) = @_;

#     my $occurrence_no = $r->{occurrence_no};
#     my $dbh = $dbt->{dbh};
    
#     # First make sure we actually have a valid occurrence id.
    
#     unless ( $occurrence_no && $occurrence_no =~ qr{ ^ [0-9]+ $ }xsi )
#     {
# 	print_msg("ERROR: BAD OCCURRENCE_NO '$occurrence_no'");
# 	return;
#     }
    
#     # First check to make sure there are no reidentifications for this
#     # occurrence.
    
#     my $occ_res = $dbh->selectall_arrayref("
# 		SELECT * FROM reidentifications WHERE occurrence_no = $occurrence_no");
    
#     if ( ref $occ_res eq 'ARRAY' && @$occ_res )
#     {
# 	my @reids;
	
# 	foreach my $r ( @$occ_res )
# 	{
# 	    my $name = join(' ', grep { $_ } ($r->{genus_name}, $r->{genus_reso},
# 					      $r->{subgenus_name}, $r->{subgenus_reso},
# 					      $r->{species_name}, $r->{species_reso}));
# 	    push @reids, "$name ($r->{reid_no})";
# 	}
	
# 	my $reid_string = join(', ', @reids);
	
# 	if ( $reid_string )
# 	{
# 	    print_msg("CANNOT DELETE: REIDS: $reid_string");
# 	    return;
# 	}
#     }
    
#     # If we get here then we have passed all of the preconditions for deleting
#     # an occurrence record.
    
#     my $occ_entry = get_record($dbh, 'occurrences', $occurrence_no);
#     my $action_sql = make_delete_sql($dbh, 'occurrences', $occurrence_no);
#     my $undo_sql = make_replace_sql($dbh, 'occurrences', $occ_entry);
    
#     my $deleted_main = execute_sql($dbh, $action_sql);
    
#     unless ( $deleted_main )
#     {
# 	print_msg("Delete failed: '$occurrence_no'");
# 	return;
#     }
    
#     print_msg("DELETED occurrence: $occurrence_no");
    
#     log_event($session, 'DELETE', 'occurrences', $occurrence_no, $action_sql, $undo_sql);
    
#     my $undo = add_undo($r, 'DELETE', 'occurrences', [$action_sql], [$undo_sql]);
    
#     do_aux_delete($dbh, $undo);
    
#     return 1;
# }


# sub aux_del_occ {

#     my ($dbh, $r) = @_;
        
#     my $occurrence_no = $r->{occurrence_no};
    
#     my $delete_sql = make_delete_sql($dbh, $OCC_MATRIX, $occurrence_no);
    
#     if ( execute_sql($dbh, $delete_sql) )
#     {
# 	print_msg("DELETED $OCC_MATRIX: $occurrence_no");
#     }
    
#     my $a = 1;	# we can stop here when debugging
# }


# sub query_reids {
    
#     my ($dbh, $key, $keyval, $options) = @_;    
    
#     my $fields = "re.*, t.orig_no, t.name as current_name, t.$SETTINGS{accepted} as accepted_no, at.name as accepted_name";
    
#     my $sql;
#     my $value = $keyval;
    
#     if ( $options->{by_selection} )
#     {
# 	$value = $keyval->{$key};
# 	return print_msg("No value found for '$key'") unless $value;
#     }
    
#     if ( $key eq 'taxon_name' || $options->{by_name} )
#     {
# 	$sql = "SELECT $fields
# 		FROM authorities as base JOIN authorities as a using (orig_no)
# 			JOIN $REIDS as re on reid.taxon_no = a.taxon_no
# 			LEFT JOIN taxon_trees as t on t.orig_no = a.orig_no
# 			LEFT JOIN taxon_trees as at on at.orig_no = t.$SETTINGS{accepted}
# 		WHERE base.taxon_name like $value
# 		GROUP BY re.reid_no";
#     }
    
#     elsif ( $key eq 'orig_no' )
#     {
# 	$sql = "SELECT $fields
# 		FROM $REIDS as re JOIN authorities as a using (taxon_no)
# 			LEFT JOIN taxon_trees as t on t.orig_no = a.orig_no
# 			LEFT JOIN taxon_trees as at on at.orig_no = t.$SETTINGS{accepted}
# 		WHERE a.orig_no in ($value)
# 		GROUP BY re.reid_no";

#     }
    
#     elsif ( $key eq 'occurrence_no' || $key eq 'reid_no' || $key eq 'taxon_no' )
#     {
# 	$sql = "SELECT $fields
# 		FROM $REIDS as re
# 			LEFT JOIN authorities as a on a.taxon_no = re.taxon_no
# 			LEFT JOIN taxon_trees as t on t.orig_no = a.orig_no
# 			LEFT JOIN taxon_trees as at on at.orig_no = t.$SETTINGS{accepted}
# 		WHERE re.$key in ($value)
# 		GROUP BY re.reid_no";
#     }
    
#     else
#     {
# 	croak "Invalid key '$key'";
#     }
    
#     return $sql;
# }


# sub list_reids {

#     my ($dbh, $result) = @_;
    
#     # First assemble print fields and determine maximum widths.
    
#     my $s = { };
    
#     clear_selection('reidentifications');
#     my $l = 'a';
    
#     foreach my $r ( @$result )
#     {
# 	my $id_string = $r->{reid_no};
# 	$id_string .= " [$r->{occurrence_no}]";
	
# 	my ($ident, $check) = occ_or_reid_ident($r);
# 	my $orig_no = $r->{orig_no};
# 	my $taxon_no = $r->{taxon_no};
	
# 	$ident .= " : $orig_no";
# 	$ident .= " ($taxon_no)" if $taxon_no ne $orig_no;
	
# 	my $accepted = $r->{accepted_name};
# 	$accepted .= " ($r->{accepted_no})" if $r->{accepted_no} ne $orig_no;
	
# 	my $auth_name = $PERSON{$r->{authorizer_no}};
# 	my $ent_name = $PERSON{$r->{enterer_no}};
# 	my $mod_name = $PERSON{$r->{modifier_no}};
	
# 	my $authent_string = $auth_name;
# 	$authent_string .= " ($ent_name)" if $ent_name ne $auth_name;
# 	$authent_string .= " / $mod_name" if $mod_name && $mod_name ne $ent_name;
	
# 	my $date_string = get_date($r->{created}) . ' : ' . get_date($r->{modified});
	
# 	set_field($r, $s, "id", $id_string);
# 	set_field($r, $s, "ident", $ident);
# 	set_field($r, $s, "accepted", $accepted);
# 	set_field($r, $s, "authent", $authent_string);
# 	set_field($r, $s, "crmod", $date_string);
#     }
    
#     foreach my $r ( @$result )
#     {
# 	print_record($l, make_fields($r, $s, "id", "  ", "ident", "   ", "accepted"),
# 			 make_fields($r, $s, "authent"),
# 		         make_fields($r, $s, "crmod"));
# 	add_to_selection($l, $r);
# 	$l++;
#     }
# }


# sub update_reid {
    
#     my ($dbt, $session, $r, $updates) = @_;
    
#     my $reid_no = $r->{reid_no};
#     my $occurrence_no = $r->{occurrence_no};
#     my $dbh = $dbt->dbh;
    
#     unless ( $reid_no && $reid_no =~ qr{ ^ [0-9]+ $ }xs )
#     {
# 	return print_msg("CANNOT UPDATE RECORD: reid_no = '$reid_no'");
#     }
    
#     set_modifier($dbt, $session, $updates);
    
#     my $reid_entry = get_record($dbh, 'reidentifications', $reid_no);
#     my $action_sql = make_update_sql($dbh, 'reidentifications', $reid_no, $updates);
#     my $undo_sql = make_update_undo_sql($dbh, 'reidentifications', $reid_no, $updates, $reid_entry);
    
#     my $event_type = $updates->{IS_FIX} ? 'FIX' : 'UPDATE';
    
#     my $updated = execute_sql($dbh, $action_sql);
    
#     unless ( $updated )
#     {
# 	print_msg("Update failed for '$reid_no'.");
# 	return;
#     }
    
#     log_event($session, $event_type, 'reidentifications', $reid_no, $action_sql, $undo_sql);
    
#     my $undo = add_undo($r, $event_type, 'reidentifications', $action_sql, $undo_sql);
    
#     do_aux_update($dbh, $undo);
    
#     print_msg("UPDATED reidentification: $reid_no [$occurrence_no]");
    
#     return 1;
# }


# sub delete_reid {
    
#     my ($dbt, $session, $r) = @_;

#     my $reid_no = $r->{reid_no};
#     my $dbh = $dbt->{dbh};
    
#     # First make sure we actually have a valid reid id.
    
#     unless ( $reid_no && $reid_no =~ qr{ ^ [0-9]+ $ }xsi )
#     {
# 	print_msg("ERROR: BAD REID_NO '$reid_no'");
# 	return;
#     }
    
#     # There are no preconditions for deleting a reidentification record.
    
#     my $reid_entry = get_record($dbh, 'reidentifications', $reid_no);
#     my $action_sql = make_delete_sql($dbh, 'reidentifications', $reid_no);
#     my $undo_sql = make_replace_sql($dbh, 'reidentifications', $reid_entry);
    
#     my $deleted_main = execute_sql($dbh, $action_sql);
    
#     unless ( $deleted_main )
#     {
# 	print_msg("Delete failed: '$reid_no'");
# 	return;
#     }
    
#     log_event($session, 'DELETE', 'reidentifications', $reid_no, $action_sql, $undo_sql);
    
#     my $undo = add_undo($r, 'DELETE', 'reidentifications', [$action_sql], [$undo_sql]);
    
#     do_aux_update($dbh, $undo);

#     print_msg("DELETED reidentification: $reid_no");
    
#     return 1;
# }


# sub do_aux_update {
    
#     my ($dbh, $r) = @_;
    
#     my $table = $r->{TABLE};
    
#     if ( my $aux_update_sub = $ACTION{$table}{aux_update} )
#     {
# 	return &$aux_update_sub($dbh, $r);
#     }
# }


# sub do_aux_add {

#     my ($dbh, $r) = @_;
    
#     my $table = $r->{TABLE};
    
#     if ( my $aux_add_sub = ($ACTION{$table}{aux_add} || $ACTION{$table}{aux_update}) )
#     {
# 	return &$aux_add_sub($dbh, $r);
#     }
# }


# sub do_aux_delete {

#     my ($dbh, $r) = @_;
    
#     my $table = $r->{TABLE};
    
#     if ( my $aux_del_sub = $ACTION{$table}{aux_del} )
#     {
# 	return &$aux_del_sub($dbh, $r);
#     }
# }


# sub make_fields {

#     my ($r, $s, @fields) = @_;
    
#     my $line = '';
    
#     foreach my $f (@fields)
#     {
# 	if ( $f =~ qr{ ^ > (\w+) }xsi )
# 	{
# 	    my $tab = $s->{"left_$1"};
	    
# 	    if ( $tab && length($line) < $tab )
# 	    {
# 		my $pad = $tab - length($line);
# 		$line .= ' ' x $pad;
# 	    }
# 	}
	
# 	elsif ( $f =~ qr{ ^ \w+ $ }xsi )
# 	{
# 	    $s->{"left_$f"} = length($line);
	    
# 	    my $field_val = $r->{"field_$f"};
# 	    my $width_val = $s->{"width_$f"};
# 	    my $pad = $width_val - length($field_val);
# 	    my $padding = $pad > 0 ? ' ' x $pad : '';
	    
# 	    $line .= $field_val . $padding;
# 	}
	
# 	else
# 	{
# 	    $line .= $f;
# 	}
#     }
    
#     return $line;
# }


sub print_record {

    my ($flag, @lines) = @_;
    
    print_line "";
    foreach my $line (@lines)
    {
	print_line "$flag> $line";
    }
}


sub preload_people {
    
    my ($dbh) = @_;
    
    my $result = $dbh->selectall_arrayref(" SELECT person_no, name FROM person", { Slice => {} });
    
    foreach my $r ( @$result )
    {
	my $person_no = $r->{person_no};
	my $name = $r->{name};
	
	$PERSON{$person_no} = $name;
    }
}


# sub check_fields {
    
#     my ($dbh) = @_;
    
#     my ($table, $tree_table_fields) = $dbh->selectrow_array("SHOW CREATE TABLE `taxon_trees`");
    
#     if ( $tree_table_fields =~ qr{ `accepted_no` }xs )
#     {
# 	$SETTINGS{accepted} = 'accepted_no';
#     }
    
#     else
#     {
# 	$SETTINGS{accepted} = 'synonym_no';
#     }
    
#     if ( $tree_table_fields =~ qr{ `senpar_no` }xs )
#     {
# 	$SETTINGS{senpar} = 'senpar_no';
#     }
    
#     else
#     {
# 	$SETTINGS{senpar} = 'parsen_no';
#     }
    
#     if ( $tree_table_fields =~ qr{ `immpar_no` }xs )
#     {
# 	$SETTINGS{immpar} = 'immpar_no';
#     }
    
#     else
#     {
# 	$SETTINGS{immpar} = 'parent_no';
#     }
# }


sub pbdb_login {
    
    my ($login_id) = @_;
    
    my $session_record;
    
    while ( ! $session_record )
    {
	unless ( $login_id && $login_id ne 'new' )
	{
	    print "Enter a PBDB login name, person_no, or session_id: ";
	    $login_id = <STDIN>;
	    chomp $login_id;
	}
	
	next unless $login_id;
	
	my $sql;
	
	if ( $login_id =~ /^[0-9A-Z-]+$/ && length($login_id) > 30 )
	{
	    my $quoted_id = $DBH->quote($login_id);
	    
	    $sql = "SELECT s.session_id, s.role, s.authorizer_no, p.name as authorizer
		FROM session_data as s join person as p on s.authorizer_no = p.person_no
		WHERE s.session_id = $quoted_id";
	}
	
	elsif ( $login_id =~ /^\d+$/ )
	{
	    $sql = "SELECT s.session_id, s.role, s.authorizer_no, p.name as authorizer
		FROM session_data as s join person as p on s.authorizer_no = p.person_no
		WHERE s.authorizer_no = $login_id ORDER BY record_date desc LIMIT 1";
	}
	
	elsif ( $login_id =~ /^\w[.]\s+\w+/ )
	{
	    my $quoted_name = $DBH->quote($login_id);
	    
	    $sql = "SELECT s.session_id, s.role, s.authorizer, s.authorizer_no, p.name as authorizer
		FROM session_data as s join person as p on s.authorizer_no = p.person_no
		WHERE p.name = $quoted_name ORDER BY record_date desc LIMIT 1";
	}
	
	else
	{
	    my $quoted_name = $DBH->quote($login_id);
	    
	    $sql = "SELECT s.session_id, s.role, s.authorizer, s.authorizer_no, p.name as authorizer
		FROM session_data as s join person as p on s.authorizer_no = p.person_no
			join pbdb_wing.users as u on s.authorizer_no = u.person_no
		WHERE u.username = $quoted_name ORDER BY record_date desc LIMIT 1";
	}
	
	$session_record = $DBH->selectrow_hashref( $sql, { Slice => { } } );
	
	unless ( $session_record )
	{
	    print "No login session was found for '$login_id'.\n";
	    next;
	}
	
	unless ( $session_record->{role} && $session_record->{role} eq 'authorizer' )
	{
	    my $role = $session_record->{role} || '';
	    print "The database role for that session is '$role'. You must be logged in as an authorizer to use this tool.\n";
	    next;
	}
    }
    
    bless $session_record, 'PBDB::Session';
    
    return $session_record;
}


sub get_record {
    
    my ($dbh, $table, $key_value) = @_;
    
    my $primary_key = $PRIMARY_KEY{$table};
    
    croak("Invalid table '$table'") unless $primary_key;
    croak("invalid primary key value '$key_value'") unless 
	$key_value && $key_value =~ qr{ ^ \d+ $ }xsi;
    
    my $sql = "SELECT * FROM $table WHERE $primary_key = $key_value";
    
    my $record = $dbh->selectrow_hashref($sql);
    
    return $record;
}


# sub make_replace_sql {

#     my ($dbh, $table, $r) = @_;
    
#     my $primary_key = $PRIMARY_KEY{$table};
#     my $key_value = $r->{$primary_key};
    
#     croak("Invalid table '$table'") unless $primary_key;
#     croak("Invalid primary key value '$key_value'") unless 
# 	$r->{$primary_key} && $r->{$primary_key} =~ qr{ ^ \d+ $ }xsi;
    
#     unless ( $COLUMN_INFO{$table} )
#     {
# 	fetch_column_info($dbh, $table);
#     }
    
#     my (@insertFields, @insertValues);
    
#     foreach my $col ( @{$COLUMN_INFO{$table}} )
#     {
# 	my $field = $col->{COLUMN_NAME};
# 	my $type = $col->{TYPE_NAME};
# 	my $is_nullable = $col->{IS_NULLABLE};
# 	my $default = $col->{COLUMN_DEF};
	
# 	my $value = $r->{$field};
	
# 	unless ( defined $value )
# 	{
# 	    $value = $is_nullable ? 'NULL' : $default;
# 	}
	
# 	else
# 	{
# 	    $value = $dbh->quote($value);
# 	}
	
# 	push @insertFields, $field;
# 	push @insertValues, $value;
#     }
    
#     my $field_string = join(',', @insertFields);
#     my $value_string = join(',', @insertValues);
    
#     my $insertSQL = "REPLACE INTO $table ($field_string)
# 		VALUES ($value_string)";
    
#     return $insertSQL;
# }


# sub make_update_sql {

#     my ($dbh, $table, $key_value, $updates) = @_;
    
#     my $primary_key = $PRIMARY_KEY{$table};
    
#     die "Invalid table '$table'" unless $primary_key;
#     die "Invalid primary key value '$key_value'" unless 
# 	$key_value && $key_value =~ qr{ ^ \d+ $ }xsi;
    
#     unless ( $COLUMN_INFO{$table} )
#     {
# 	fetch_column_info($dbh, $table);
#     }
    
#     if ( $updates->{authorizer_no} )
#     {
# 	$updates->{authorizer} = $PERSON{$updates->{authorizer_no}};
#     }
    
#     if ( $updates->{enterer_no} )
#     {
# 	$updates->{enterer} = $PERSON{$updates->{enterer_no}};
#     }
    
#     my (@updateTerms);
    
#  COL:
#     foreach my $col ( @{$COLUMN_INFO{$table}} )
#     {
# 	my $field = $col->{COLUMN_NAME};
# 	my $type = $col->{TYPE_NAME};
# 	my $is_nullable = $col->{IS_NULLABLE};
# 	my $default = $col->{COLUMN_DEF};
	
# 	my $value;
	
# 	if ( $field eq 'modifier_no' )
# 	{
# 	    next COL if $updates->{IS_FIX};
# 	    $value = $session->get('enterer_no');
# 	    $value = $dbh->quote($value);
# 	}
	
# 	elsif ( $field eq 'modifier' )
# 	{
# 	    next COL if $updates->{IS_FIX};
# 	    $value = $session->get('enterer');
# 	    $value = $dbh->quote($value);
# 	}
	
# 	elsif ( $field eq 'modified' )
# 	{
# 	    $value = $updates->{IS_FIX} ? 'modified' : 'NOW()';
# 	}
	
# 	else
# 	{
# 	    next COL unless exists $updates->{$field};
# 	    $value = $updates->{$field};
	    
# 	    unless ( defined $value )
# 	    {
# 		$value = $is_nullable ? 'NULL' : $default;
# 	    }
# 	}
	
# 	push @updateTerms, "$field=$value";
#     }
    
#     unless ( @updateTerms )
#     {
# 	die "ERROR: no updates specified\n";
#     }
    
#     my $update_string = join(',', @updateTerms);
    
#     unless ( $key_value =~ qr{ ^ [0-9]+ $ }xsi )
#     {
# 	$key_value = $dbh->quote($key_value);
#     }
    
#     my $sql = "UPDATE $table
# 		SET $update_string
# 		WHERE $primary_key=$key_value";
    
#     return $sql;
# }


# sub make_update_undo_sql {

#     my ($dbh, $table, $key_value, $updates, $r) = @_;
    
#     my $primary_key = $PRIMARY_KEY{$table};
    
#     die "Invalid table '$table'" unless $primary_key;
#     die "Invalid primary key value '$key_value'" unless 
# 	$key_value && $key_value =~ qr{ ^ \d+ $ }xsi;
    
#     unless ( $COLUMN_INFO{$table} )
#     {
# 	fetch_column_info($dbh, $table);
#     }
    
#     my ($additional_updates) = { modifier => 1, modifier_no => 1, modified => 1};
    
#     if ( $updates->{authorizer_no} )
#     {
# 	$additional_updates->{authorizer} = 1;
#     }
    
#     if ( $updates->{enterer_no} )
#     {
# 	$additional_updates->{enterer} = 1;
#     }
    
#     my (@updateTerms);
    
#  COL:
#     foreach my $col ( @{$COLUMN_INFO{$table}} )
#     {
# 	my $field = $col->{COLUMN_NAME};
# 	my $type = $col->{TYPE_NAME};
# 	my $is_nullable = $col->{IS_NULLABLE};
# 	my $default = $col->{COLUMN_DEF};
	
# 	if ( exists $updates->{$field} || exists $additional_updates->{$field} )
# 	{
# 	    my $value = $dbh->quote($r->{$field});
# 	    push @updateTerms, "$field=$value";
# 	}
#     }
    
#     my $update_string = join(',', @updateTerms);
    
#     unless ( $key_value =~ qr{ ^ [0-9]+ $ }xsi )
#     {
# 	$key_value = $dbh->quote($key_value);
#     }
    
#     my $sql = "UPDATE $table
# 		SET $update_string
# 		WHERE $primary_key=$key_value";
    
#     return $sql;
# }


# sub make_multifix_sql {

#     my ($dbh, $table, $key_value, $updates) = @_;
    
#     my $primary_key = $PRIMARY_KEY{$table};
    
#     die "Invalid table '$table'" unless $primary_key;
#     die "Invalid primary key value '$key_value'" unless 
# 	$key_value && $key_value =~ qr{ ^ [\d,]+ $ }xsi;
    
#     unless ( $COLUMN_INFO{$table} )
#     {
# 	fetch_column_info($dbh, $table);
#     }
    
#     if ( $updates->{authorizer_no} )
#     {
# 	$updates->{authorizer} = $PERSON{$updates->{authorizer_no}};
#     }
    
#     if ( $updates->{enterer_no} )
#     {
# 	$updates->{enterer} = $PERSON{$updates->{enterer_no}};
#     }
    
#     my (@updateTerms);
    
#  COL:
#     foreach my $col ( @{$COLUMN_INFO{$table}} )
#     {
# 	my $field = $col->{COLUMN_NAME};
# 	my $type = $col->{TYPE_NAME};
# 	my $is_nullable = $col->{IS_NULLABLE};
# 	my $default = $col->{COLUMN_DEF};
	
# 	my $value;
	
# 	if ( $field eq 'modifier_no' )
# 	{
# 	    next COL if $updates->{IS_FIX};
# 	    $value = $session->get('enterer_no');
# 	    $value = $dbh->quote($value);
# 	}
	
# 	elsif ( $field eq 'modifier' )
# 	{
# 	    next COL if $updates->{IS_FIX};
# 	    $value = $session->get('enterer');
# 	    $value = $dbh->quote($value);
# 	}
	
# 	elsif ( $field eq 'modified' )
# 	{
# 	    $value = $updates->{IS_FIX} ? 'modified' : 'NOW()';
# 	}
	
# 	else
# 	{
# 	    next COL unless exists $updates->{$field};
# 	    $value = $updates->{$field};
	    
# 	    unless ( defined $value )
# 	    {
# 		$value = $is_nullable ? 'NULL' : $default;
# 	    }
# 	}
	
# 	push @updateTerms, "$field=$value";
#     }
    
#     unless ( @updateTerms )
#     {
# 	die "ERROR: no updates specified\n";
#     }
    
#     my $update_string = join(',', @updateTerms);
    
#     my $sql = "UPDATE $table
# 		SET $update_string
# 		WHERE $primary_key in ($key_value)";
    
#     return $sql;
# }


# sub make_delete_sql {
    
#     my ($dbh, $table, $key_value) = @_;
    
#     my $primary_key = $PRIMARY_KEY{$table};
    
#     die "Invalid table '$table'" unless $primary_key;
#     die "Invalid primary key value '$key_value'" unless 
# 	$key_value && $key_value =~ qr{ ^ \d+ $ }xsi;
    
#     my $sql = "DELETE FROM $table
# 		WHERE $primary_key = $key_value";
    
#     return $sql;
# }


# sub set_modifier {
    
#     my ($dbt, $session, $updates) = @_;
    
#     $updates->{MODIFIER_NO} = $session->get('enterer_no');
#     $updates->{MODIFIER} = $session->get('enterer');
    
#     my $a = 1;	# we can stop here when debugging
# }


# sub execute_sql {
    
#     my ($dbh, $sql) = @_;
    
#     my $result;
    
#     if ( $DEBUG{sql} )
#     {
# 	print_line("");
# 	print_line($sql);
#     }
    
#     try {
# 	$result = $dbh->do($sql);
#     }
    
#     catch {
# 	print_msg($sql);
# 	die $_;
#     };
    
#     return $result;
# }


sub log_event {
    
    my ($session, $type, $table, $key_value, $action_sql, $undo_sql) = @_;
    
    croak "Invalid table '$table'" unless $PRIMARY_KEY{$table};
    croak "Invalid type '$type'"
	unless $type =~ qr{ ^ (?: UNDO_ | REDO_ )?
			      (?: UPDATE | FIX | DELETE | INSERT ) $ }xs;
    
    PBDB::DBTransactionManager::logEvent(
	{ stmt => $type, 
	  table => $table, 
	  key => $PRIMARY_KEY{$table}, 
	  keyval => $key_value, 
	  auth_no => $session->get('authorizer_no'),
	  ent_no => $session->get('enterer_no'),
	  sql => $action_sql,
	  undo_sql => $undo_sql});
    
    my $a = 1;	# we can stop here when debugging.
}


sub fetch_column_info {
    
    my ($dbh, $table) = @_;
    
    my $sth = $dbh->column_info(undef, $Constants::DB, $table, '%');
    
    my @defs;
    my %type;
    
    while ( my $row = $sth->fetchrow_hashref() )
    {
	my $name = $row->{COLUMN_NAME};
	my $type = $row->{TYPE_NAME};
	
	push @defs, $row;
	$type{$name} = $type;
    }
    
    $COLUMN_INFO{$table} = \@defs;
    $COLUMN_TYPE{$table} = \%type;
}


sub add_undo {
    
    my ($r, $action, $table, $action_arg, $undo_arg) = @_;
    
    my $undo_record = { %$r };
    
    my $action_list = ref $action_arg eq 'ARRAY' ? $action_arg : defined $action_arg ? [ $action_arg ] : [];
    my $undo_list = ref $undo_arg eq 'ARRAY' ? $undo_arg : defined $undo_arg ? [ $undo_arg ] : [];
    
    $undo_record->{TABLE} = $table;
    $undo_record->{ACTION} = $action;
    $undo_record->{ACTION_LIST} = $action_list;
    $undo_record->{UNDO_LIST} = $undo_list;
    
    foreach my $s ( @$action_list )
    {
	$s = reformat_sql($s);
    }
    
    foreach my $s ( @$undo_list )
    {
	$s = reformat_sql($s);
    }
    
    push @{$STORED->{UNDO_LIST}}, $undo_record;
    return $undo_record;
}


sub list_undo {
    
    my ($dbh, $rest) = @_;
    
    unless ( ref $STORED->{UNDO_LIST} eq 'ARRAY' )
    {
	return print_msg("NOTHING TO UNDO.");
    }
    
    %UNDO_SEL = ();
    
    my $start = -5;
    my $end = -1;
    
    my $options = { };
    
    if ( $rest =~ qr{ ^ ( [0-9]+ ) \s* (.*) }xsi )
    {
	$start = -1 * $1;
	$end = $start + 4;
	$rest = '';
    }
    
    while ( $rest =~ qr{ ^ / (\w+) \s* (.*) }xsi )
    {
	my $arg = lc $1;
	$rest = $2;
	
	if ( $arg eq 'full' )
	{
	    $options->{full} = 1;
	}
	
	else
	{
	    return print_msg("INVALID OPTION '$arg'");
	}
    }
    
    if ( $rest )
    {
	return print_msg("ERROR: invalid argument '$rest'");
    }
    
    my @list = @{$STORED->{UNDO_LIST}}[$start..$end];
    
    my $l = 'a';
    
    foreach my $r (@list)
    {
	next unless ref $r eq 'HASH';
	list_undo_record($dbh, $l, $r, $options);
	$UNDO_SEL{$l} = $r;
	$l++;
    }
    
    print_msg("");
}


sub list_undo_record {

    my ($dbh, $l, $r, $options) = @_;
    
    my $table = $r->{TABLE} || '[unknown]';
    my $action = $r->{ACTION} || '[unknown]';
    my $primary_key = $PRIMARY_KEY{$table};
    
    unless ( $primary_key && $r->{$primary_key} )
    {
	return print_record($l, "Invalid entry");
    }
    
    my @lines;
    
    my $value = $r->{$primary_key};
    my $header = "$action $table : $value";
    $header .= "   [[UNDONE]]" if $r->{UNDONE};
    
    push @lines, $header;
    
    if ( $options->{full} )
    {
	if ( ref $r->{ACTION_LIST} eq 'ARRAY' )
	{
	    foreach my $line (@{$r->{ACTION_LIST}})
	    {
		push @lines, "ACTION:" . reformat_sql($line);
	    }
	}
	
	if ( ref $r->{UNDO_LIST} eq 'ARRAY' )
	{
	    foreach my $line (@{$r->{UNDO_LIST}} )
	    {
		push @lines, "UNDO:" . reformat_sql($line);
	    }
	}
	
	if ( ref $r->{TTC_ENTRY} eq 'HASH' )
	{
	    my $sql = make_replace_sql($dbh, 'taxa_tree_cache', $r->{TTC_ENTRY});
	    push @lines, "TTC: " . reformat_sql($sql);
	}
	
	if ( ref $r->{TT_ENTRY} eq 'HASH' )
	{
	    my $sql = make_replace_sql($dbh, 'taxon_trees', $r->{TT_ENTRY});
	    push @lines, "TT: " . reformat_sql($sql);
	}
    }
    
    print_record($l, @lines);
}


sub execute_undo {
    
    my ($dbt, $session, $r) = @_;
    
    my $dbh = $dbt->dbh;
    my $action_list = $r->{ACTION_LIST};
    my $undo_list = $r->{UNDO_LIST};
    my $table = $r->{TABLE};
    my $action = $r->{ACTION};
    
    unless ( ref $undo_list eq 'ARRAY' && @$undo_list )
    {
	return print_msg("No actions to undo.");
    }
    
    foreach my $i ( 0..$#$undo_list )
    {
	my $undo_sql = $undo_list->[$i];
	my $action_sql = $action_list->[$i];
	
	my $result;
	$undo_sql =~ s{ ^ INSERT }{REPLACE}xs;
	
	print_msg(">> $undo_sql");
	
	try {
	    $result = $dbh->do($undo_sql);
	}
	
	catch {
	    print_msg("ERROR: $_");
	};
	
	unless ( $result )
	{
	    print_msg("No changes were made to the database.");
	}
	
	# Now we log the undo action.  Note that $undo_sql and $action_sql are
	# swapped in the call below, since the action we are taking is the
	# undo and the "undo" of that would be the original action.
	
	my $type = "UNDO_$action";
	my $primary_key = $PRIMARY_KEY{$table};
	my $key_value = $r->{$primary_key};
	
	log_event($session, $type, $table, $key_value, $undo_sql, $action_sql);
    }
    
    # If any auxiliary actions need to be taken, do them now.  Note that the
    # "undo" of an add is a delete and vice versa.
    
    if ( $action eq 'UPDATE' )
    {
	do_aux_update($dbh, $r);
    }
    
    elsif ( $action eq 'DELETE' )
    {
	do_aux_add($dbh, $r);
    }
    
    elsif ( $action eq 'INSERT' )
    {
	do_aux_delete($dbh, $r);
    }
    
    $r->{UNDONE} = 1;
    
    my $a = 1;	# we can stop here when debugging
}


sub execute_redo {
    
    my ($dbt, $session, $r) = @_;
    
    my $dbh = $dbt->dbh;
    my $redo_list = $r->{ACTION_LIST};
    my $undo_list = $r->{UNDO_LIST};
    my $table = $r->{TABLE};
    my $action = $r->{ACTION};
    
    unless ( ref $redo_list eq 'ARRAY' && @$redo_list )
    {
	return print_msg("No actions to undo.");
    }
    
    foreach my $i ( 0..$#$undo_list )
    {
	my $action_sql = $redo_list->[$i];
	my $undo_sql = $undo_list->[$i];
	my $result;
	
	$action_sql =~ s{ ^ INSERT }{REPLACE}xs;
	
	print_msg(">> $action_sql");
	
	try {
	    $result = $dbh->do($action_sql);
	}
	
	catch {
	    print_msg("ERROR: $_");
	};
	
	unless ( $result )
	{
	    print_msg("No changes were made to the database.");
	}
	
	# Now we log the redo action.
	
	my $type = "REDO_$action";
	my $primary_key = $PRIMARY_KEY{$table};
	my $key_value = $r->{$primary_key};
	
	log_event($session, $type, $table, $key_value, $action_sql, $undo_sql);
    }
    
    # If any auxiliary actions need to be taken, do them now.
    
    if ( $action eq 'UPDATE' )
    {
	do_aux_update($dbh, $r);
    }
    
    elsif ( $action eq 'DELETE' )
    {
	do_aux_delete($dbh, $r);
    }
    
    elsif ( $action eq 'INSERT' )
    {
	do_aux_add($dbh, $r);
    }
    
    # if ( $table eq 'opinions' )
    # {
    # 	my $opinion_no = $r->{opinion_no};
    # 	my ($sql, $result);
	
    # 	if ( $action eq 'DELETE' )
    # 	{
    # 	    $sql = "DELETE FROM $TAXON_TABLE{taxon_trees}{opcache} WHERE opinion_no = $opinion_no";
    # 	    $result = $dbh->do($sql);
    # 	}
	
    # 	else
    # 	{
    # 	    fixOpinionCache($dbh, $TAXON_TABLE{taxon_trees}{opcache}, 'taxon_trees', $opinion_no);
    # 	}
    # }
    
    # elsif ( $table eq 'occurrences' )
    # {
    # 	my $occurrence_no = $r->{occurrence_no};
    # 	my ($sql, $result);
	
    # 	if ( $action eq 'DELETE' )
    # 	{
    # 	    $sql = "DELETE FROM $OCC_MATRIX WHERE occurrence_no = $occurrence_no";
    # 	    $result = $dbh->do($sql);
    # 	}
	
    # 	else
    # 	{
    # 	    updateOccurrenceMatrix($dbh, $occurrence_no);
    # 	}
    # }
    
    $r->{UNDONE} = 0;
    
    my $a = 1;	# we can stop here when debugging
}


sub reformat_sql {
    
    my ($line) = @_;
    
    $line =~ s{ ^ \s* }{}xs;
    $line =~ s{ ^ \s* }{\t}xmg;
    return "\n" . $line;
}


sub save_state {
    
    my ($term) = @_;
    
    my @history = $term->GetHistory;
    
    $STORED->{HISTORY} = \@history;
    $STORED->{SETTINGS} = \%SETTINGS;
    $STORED->{DEBUG} = \%DEBUG;
    $STORED->{SELECTION} = \%SELECTION;
    $STORED->{SELECT_HIST} = \@SELECT_HIST;
    $STORED->{LIST} = \%LIST;
    $STORED->{LOGIN_NO} = $LOGIN_NO;
    
    store($STORED, $STATE_FILE) if ref $STORED;
}


sub load_state {
    
    unless ( $ENV{HOME} )
    {
	die "Cannot determine home directory.\n";
    }
    
    if ( -e $STATE_FILE )
    {
	die "Cannot read '$STATE_FILE': $!" unless -r $STATE_FILE;
	
	$STORED = retrieve($STATE_FILE);
	
	%SETTINGS = %{$STORED->{SETTINGS}} if ref $STORED->{SETTINGS} eq 'HASH';
	%DEBUG = %{$STORED->{DEBUG}} if ref $STORED->{DEBUG} eq 'HASH';
	
	foreach my $key ( keys %DEFAULT_SETTINGS )
	{
	    $SETTINGS{$key} //= $DEFAULT_SETTINGS{$key};
	}
	
	%SELECTION = %{$STORED->{SELECT}} if ref $STORED->{SELECT} eq 'HASH';
	%SELECTION = %{$STORED->{SELECTION}} if ref $STORED->{SELECTION} eq 'HASH';
	@SELECT_HIST = @{$STORED->{SELECT_HIST}} if ref $STORED->{SELECT_HIST} eq 'ARRAY';
	
	%LIST = %{$STORED->{LIST}} if ref $STORED->{LIST} eq 'HASH';

	$LOGIN_NO = $STORED->{LOGIN_NO};
    }
}


sub display_help {

    my ($arg) = @_;
    
    if ( $HELPSTRING{$arg} )
    {
	print_msg $HELPSTRING{$arg};
    }

    elsif ( $arg )
    {
	print_msg "UNKNOWN SUBCOMMAND '$arg'";
    }
    
    else
    {
	print_msg $HELPSTRING{main};
    }
}


