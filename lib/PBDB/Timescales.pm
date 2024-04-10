
use strict;

package PBDB::Timescales;

use PBDB::Reference;

use TableDefs qw(%TABLE);
use CoreTableDefs;
use IntervalBase qw(ts_defined ts_record ts_name ts_bounds ts_intervals ts_by_age
		    int_defined int_bounds int_name int_type int_scale int_container
		    int_record int_correlation ints_by_age INTL_SCALE BIN_SCALE);
use List::Util qw(min max all);

use PBDB::Constants qw($INTERVAL_URL $RANGE_URL);
use JSON;


# displayTimescale ( )
# 
# Display the specified timescale or portion of a timescale as an HTML diagram with
# interval names, ages, and colors. 

sub displayTimescale {
    
    my ($dbt, $hbo, $s, $q) = @_;
    
    my $dbh = $dbt->dbh;
    
    # Parse the parameters of this call.
    
    my $scale_no = $q->param('scale_no') || $q->param('scale');
    my $interval_name = lc $q->param('interval');
    my $interval_range = lc $q->param('range');
    my $display = $q->param('show');
    my $action = $q->param('type') || $q->param('action');
    
    # If the action is 'list', redirect to listTimescales.
    
    if ( $action eq 'list' )
    {
	return listTimescales($dbt, $hbo, $s, $q);
    }
    
    # Declare the variables we will need.
    
    my $options = { mark_obsolete => 1 };
    
    my $heading = 'Display Timescale';
    my $details = '';
    
    my ($has_interp, $has_obsolete, $n_colls, $t_limit, $b_limit, $t_range, $b_range);
    
    my ($sql, $result);
    
    my (@scale_list, $main_scale, %use_scale, %sdata, %ssequence,
	@interval_list, $main_interval, $main_idata);
    
    my (@reference_list, %reference_uniq, 
	@long_refs, %long_ref, %short_ref);
    
    # We need to assign these constants to local variables, because we will be
    # using them as hash keys and interpolating them into strings.
    
    my $INTL_SCALE = INTL_SCALE;
    my $BIN_SCALE = BIN_SCALE;
    
    # Basic sanity checks on the arguments.
    
    if ( defined $scale_no && $scale_no !~ /^\d[\d\s,]*$/ )
    {
	return "<h2>Invalid timescale identifier '$scale_no'</h2>";
    }
    
    unless ( $scale_no || $interval_name || $interval_range )
    {
	return "<h2>You must specify either a timescale, an interval, or a range</h2>";
    }
    
    # Add the specified scales (if any) to the display list.
    
    if ( $scale_no && $scale_no =~ /\d/ )
    {
	my @args = split /\s*,\s*/, $scale_no;
	
	foreach my $s ( @args )
	{
	    if ( ts_defined($s) && ! $use_scale{$s} )
	    {
		push @scale_list, $s;
		$use_scale{$s} = 1;
	    }
	}
	
	unless ( @scale_list )
	{
	    return "<h2>You did not specify any valid timescale identifiers</h2>";
	}
    }
    
    # If the 'intervals' parameter was specified, add the specified intervals to
    # the display list.
    
    if ( $interval_name )
    {
	my @args = split /\s*,\s*/, $interval_name;
	
	foreach my $n ( @args )
	{
	    if ( my $i = int_defined($n) )
	    {
		push @interval_list, $i;
	    }
	}
	
	unless ( @interval_list )
	{
	    return "<h2>You did not specify any valid intervals</h2>";
	}
	
	$hbo->pageTitle('PBDB Interval');
    }
    
    # If the 'range' parameter was specified, set $b_range and $t_range to
    # indicate which intervals should be highlighted. Also, limit the display to
    # the containing period, or eon for precambrian.
    
    if ( $interval_range =~ /^(.*?)[-,](.*)/ )
    {
	my $int1 = int_defined($1);
	my $int2 = int_defined($2);
	
	if ( $int1 && $int2 )
	{
	    # First, get the age range that spans the specified intervals.
	    
	    push @interval_list, $int1, $int2;
	    
	    my ($b1, $t1) = int_bounds($int1);
	    my ($b2, $t2) = int_bounds($int2);
	    
	    $b_range = max($b1, $b2);
	    $t_range = min($t1, $t2);
	    
	    # Next, get age range that spans the periods (or eons if
	    # precambrian) that contain those intervals.
	    
	    ($b1, $t1) = int_bounds(int_container($int1));
	    ($b2, $t2) = int_bounds(int_container($int2));
	    
	    $options->{t_limit} = min($t1, $t2);
	    $options->{b_limit} = max($b1, $b2);
	}
	
	else
	{
	    return "<h2>Invalid range '$interval_range'</h2>";
	}
	
	$hbo->pageTitle('PBDB Interval Range');
    }
    
    elsif ( $interval_range )
    {
	if ( my $int = int_defined($interval_range) )
	{
	    push @interval_list, $int;
	    
	    ($b_range, $t_range) = int_bounds($int);
	    
	    ($options->{b_limit}, $options->{t_limit}) = int_bounds(int_container($int));
	}
	
	else
	{
	    return "<h2>Invalid range '$interval_range'</h2>";
	}
    }
    
    # Add the timescales corresponding to the selected intervals, if they are
    # not already selected.
    
    if ( @interval_list )
    {
	$main_interval = $interval_list[0] unless $interval_range;
	
	foreach my $i ( @interval_list )
	{
	    my $s = int_scale($i);
	    
	    unless ( $use_scale{$s} )
	    {
		if ( $s eq $INTL_SCALE ) {
		    unshift @scale_list, $s;
		} else { 
		    push @scale_list, $s;
		}
		$use_scale{$s} = 1;
	    }
	    
	    $options->{highlight}{$i} = 1;
	}
    }
    
    # Scan through the selected timescales. Always display the international scale first.
    
    if ( @scale_list )
    {
	$main_scale = $scale_list[0];
	
	unshift @scale_list, $INTL_SCALE unless $use_scale{$INTL_SCALE};
	
	foreach my $s ( @scale_list )
	{
	    $sdata{$s} = ts_record($s);
	    
	    foreach my $int ( ts_intervals($s) )
	    {
		push $ssequence{$s}->@*, $int;
		
		# For every timescale other than the international one, collect
		# the interval reference_no values and determine the max and min
		# age range.
		
		if ( $s eq $main_scale || $s ne $INTL_SCALE )
		{
		    my $reference_no = $int->{reference_no};
		    
		    if ( $reference_no && ! $reference_uniq{$reference_no} )
		    {
			push @reference_list, $reference_no;
			$reference_uniq{$reference_no} = 1;
		    }
		    
		    $t_limit = $int->{t_age} if ! defined $t_limit || $int->{t_age} < $t_limit;
		    $b_limit = $int->{b_age} if ! defined $b_limit || $int->{b_age} > $b_limit;
		}
		
		# Determine if there are any interpreted bounds or obsolete
		# intervals to be displayed.
		
		$has_interp = 1 if $int->{t_type} eq 'interpolated' ||
		    $int->{b_type} eq 'interpolated';
		
		$has_obsolete = 1 if $int->{obsolete};
		
		# If there is a selected range, highlight all of the intervals
		# that fall within that range.
		
		if ( defined $t_range && defined $b_range &&
		     $int->{t_age} >= $t_range && $int->{b_age} <= $b_range )
		{
		    $options->{highlight}{$int->{interval_no}} = 1;
		}
		
		# If a specific interval was selected, its data will be used to
		# generate the details section of the display.
		
		if ( $s eq $main_scale && $main_interval && 
		     $int->{interval_no} eq $main_interval )
		{
		    $main_idata = $int;
		}
	    }
	}
    }
    
    else
    {
	return "<h2>No valid timescales were specified</h2>";
    }
    
    # If the displayed diagram should be trimmed by age, do so now.
    
    if ( lc $display eq 'precambrian' )
    {
	$display = 'neoproterozoic-hadean';
    }
    
    if ( $display =~ /(\w+?)[-,](\w+)/ )
    {
	my ($b1, $t1) = int_bounds($1);
	my ($b2, $t2) = int_bounds($2);
	
	unless ( defined $b1 && defined $b2 )
	{
	    return "<h2>Invalid value '$display' for parameter 'show'</h2>";
	}
	
	$options->{t_limit} = min($t1, $t2);
	$options->{b_limit} = max($b1, $b2);
    }
    
    elsif ( lc $display eq 'all' )
    {
	$options->{t_limit} = 0;
	$options->{b_limit} = 5000;
    }
    
    elsif ( lc $display eq 'later' )
    {
	$options->{t_limit} = 0;
    }
    
    elsif ( $display =~ /\w/ )
    {
	my ($b, $t) = int_bounds($display);
	
	unless ( defined $b )
	{
	    return "<h2>Invalid value '$display' for parameter 'show'</h2>";
	}
	
	$options->{t_limit} = $t;
	$options->{b_limit} = $b;
    }
    
    elsif ( $main_interval )
    {
	($options->{b_limit}, $options->{t_limit}) = int_bounds(int_container($main_interval));
    }
    
    # Make $b_limit and $t_limit match the limit options.
    
    if ( defined $options->{t_limit} )
    {
	$t_limit = $options->{t_limit};
    }
    
    if ( defined $options->{b_limit} )
    {
	$b_limit = $options->{b_limit};
    }
    
    # Look up collection counts, using the newly defined tables.
    
    my $scale_string = join ',', @scale_list;
    
    my %n_colls;
    
    # $sql = "SELECT i.interval_no, count(*) as n_colls
    # 		FROM $TABLE{INTERVAL_DATA} as i 
    # 		    join $TABLE{SCALE_MAP} as sm using (interval_no)
    # 		    join $TABLE{COLLECTION_DATA} as c on
    # 			i.interval_no = c.max_interval_no or
    # 			i.interval_no = c.min_interval_no or
    # 			i.interval_no = c.ma_interval_no
    # 		WHERE sm.scale_no in ($scale_string) and 
    # 		      i.early_age > '$t_limit' and i.late_age < '$b_limit'
    # 		GROUP BY i.interval_no";
    
    $sql = "SELECT interval_no, colls_defined, colls_major, occs_major
		FROM $TABLE{OCC_INT_SUMMARY}
		WHERE scale_no in ($scale_string)";
    
    foreach my $r ( $dbh->selectall_array($sql, { Slice => { } }) )
    {
	$n_colls{$r->{interval_no}} = $r;
    }
    
    # if ( $main_scale ne $INTL_SCALE )
    # {
	# $sql = "SELECT count(*)
	# 	FROM $TABLE{COLLECTION_DATA} as c join $TABLE{SCALE_MAP} as sm
	# 		on sm.interval_no = c.max_interval_no or
	# 		   sm.interval_no = c.min_interval_no or
	# 		   sm.interval_no = c.ma_interval_no
	# 	     join $TABLE{INTERVAL_DATA} as i using (interval_no)
	# 	WHERE sm.scale_no = $main_scale and i.scale_no = sm.scale_no";
	
    # 	($n_colls) = $dbh->selectrow_array($sql);
    # }
    
    $sql = "SELECT colls_defined FROM $TABLE{OCC_TS_SUMMARY}
		WHERE scale_no = $main_scale";
    
    ($n_colls) = $dbh->selectrow_array($sql);
    
    # Fetch all of the bibliographic references associated with the displayed
    # timescale(s).
    
    foreach my $reference_no ( @reference_list )
    {
	my $ref = PBDB::Reference->new($dbt, $reference_no);
	
	if ( $ref )
	{
	    $long_ref{$reference_no} = $ref->formatLongRef();
	    $short_ref{$reference_no} = $ref->formatShortRef();
	}
    }
    
    # Generate the diagram. The code for this is contained in IntervalBase, in
    # the PBDB API codebase.
    
    my $d = IntervalBase->generate_ts_diagram($options, \%sdata, \%ssequence, @scale_list);
    
    my $html_output = IntervalBase->generate_ts_html($d, \%sdata);
    
    my @bounds_list = map { $_->[0] } $d->{bound2d}->@*;
    
    # Generate the details content for the displayed timescale, interval, or range.
    
    my $details = '';
    
    # If $main_idata is defined, that means we are displaying an interval.
    
    if ( $main_idata )
    {
	my $name = $main_idata->{interval_name} || '?';
	my $type = $main_idata->{type} || '';
	my $n_colls = $n_colls{$main_interval};
	my $reference_no = $main_idata->{reference_no};
	my $long_ref = $long_ref{$reference_no};
	
	$heading = "$name <span class=\"ts_type\">$type</span>";
	
	$details = generateIntervalDetails($main_idata, $main_interval, $n_colls, $long_ref);
	
	$details .= expandOrShrink($q->query_string, $b_limit);
    }
    
    # If the 'range' parameter was given, that means we are displaying a range.
    
    elsif ( $interval_range )
    {
	my $int1 = int_record($interval_list[0]);
	my $int2 = int_record($interval_list[1]);
	
	my $name1 = $int1->{interval_name} || '?';
	my $type1 = $int1->{type} || '';
	my $name2 = $int2->{interval_name} || '?';
	my $type2 = $int2->{type} || '';
	
	$heading = "$name1 <span class=\"ts_type\">$type1</span>";
	
	if ( $interval_list[1] )
	{
	    $heading .= " - $name2 <span class=\"ts_type\">$type2</span>";
	}
	
	$heading .= "</h3>\n";
	
	$details = generateRangeDetails($int1, $int2, $name1, $name2, $b_range, $t_range);
	
	$details .= expandOrShrink($q->query_string, $b_limit);
    }
    
    # Otherwise, we are displaying a timescale.
    
    else
    {
	$heading = ts_name($main_scale) || '?';
	
	$details = generateTimescaleDetails($q, $main_scale, \@reference_list, \%long_ref, 
					    $has_interp, $has_obsolete, $n_colls);	
	
	$details .= expandOrShrink($q->query_string, $b_limit);
    }
    
    # Generate the data needed by the accompanying Javascript code, which is
    # located in /classic_js/timescales.js.
    
    my %idata;
    
    foreach my $scale_no ( @scale_list )
    {
	foreach my $int ( ts_intervals($scale_no) )
	{
	    if ( $int->{b_age} > $t_limit && $int->{t_age} < $b_limit )
	    {
		my $interval_no = $int->{interval_no};
		my $ikey = "s$scale_no-$interval_no";
		
		delete $int->{color} unless $int->{color};
		delete $int->{early_age};
		delete $int->{late_age};
		
		$idata{$ikey} = $int;
		$idata{$ikey}{n_colls} = $n_colls{$interval_no}{colls_defined}
		    if $n_colls{$interval_no}{colls_defined};
		
		$idata{$ikey}{nmc} = $n_colls{$interval_no}{colls_major};
		$idata{$ikey}{nmo} = $n_colls{$interval_no}{occs_major};
	    }
	}
    }
    
    # Encode this data into JSON format.
    
    my $idata_encoded = encode_json(\%idata);
    $idata_encoded =~ s/}/}\n/g;
    
    my $refs_encoded = encode_json(\%short_ref);
    $refs_encoded =~ s/}/}\n/g;
    
    my $bounds_encoded = encode_json(\@bounds_list);
    
    my $idata = <<END_DATA;
intl_scale = $INTL_SCALE;
bin_scale = $BIN_SCALE;

interval_data = $idata_encoded;
interval_bounds = $bounds_encoded;

reference_data = $refs_encoded;

display_interval_url = '$INTERVAL_URL';
display_ref_url =      '/classic/displayRefResults?reference_no=';
display_colls_def =    '/classic/displayCollResults?view=standard&timerule=defined&max_interval=';
display_colls_cont =   '/classic/displayCollResults?view=standard&timerule=major&max_interval=';

END_DATA
    
    # Generate the page itself, using /guest_templates/display_timescales.html.
    
    my $fields = { heading => $heading,
		   details => $details,
		   idata => $idata,
		   diagram => $html_output };
    
    my $output = $hbo->populateHTML("display_timescales", $fields);
    
    return $output;
}


# generateIntervalDetails ( idata, interval_no, n_colls, long_ref )
# 
# Generate the details pane content for displaying an interval.

sub generateIntervalDetails {
    
    my ($idata, $interval_no, $n_colls, $long_ref) = @_;
    
    my $scale_no = $idata->{scale_no};
    my $scale_name = ts_name($scale_no);
    my $reference_no = $idata->{reference_no};
    my $t_age = $idata->{t_age};
    my $t_type = $idata->{t_type};
    my $b_age = $idata->{b_age};
    my $b_type = $idata->{b_type};
    
    my $details = "<p>$b_age - $t_age Ma</p>\n";
    
    my $ts_anchor = "<a href=\"/classic/displayTimescale?scale=$scale_no\">$scale_name</a>";
    
    if ( $long_ref )
    {
	$details .= "<p>The definition of this interval in the timescale $ts_anchor " .
	    "is taken from the following source:</p>\n";
	
	my $anchor = "<a href=\"/classic/displayRefResults?reference_no=$reference_no\" " .
	    "target=\"_blank\">view</a>";
	
	$details .= "<ul>";
	$details .= "<li>$long_ref $anchor</li>";
	$details .= "</ul>\n";
    }
    
    else
    {
	$details .= "<p>This interval is defined in the timescale $ts_anchor</p>\n";
    }
    
    if ( $t_type eq 'interpolated' || $b_type eq 'interpolated' )
    {
	my $words;
	
	if ( $t_type eq 'interpolated' ) {
	    $words = $b_type eq 'interpolated' ? 'top and bottom ages have been'
		: 'top age has been';
	} else {
	    $words = 'bottom age has been';
	}
	
	$details .= "<p>The $words interpolated based on the differences between " .
	    "the ages for international timescale boundaries quoted in the " .
	    "source and the currently accepted ages for those boundaries.</p>\n";
    }
    
    if ( my @overlaps = getOverlapIntervals($b_age, $t_age, $interval_no) )
    {
	my $count = scalar(@overlaps);
	
	my $trigger = "onclick=\"showOverlapList()\"";
	
	$details .= "<p>There are intervals in $count timescales which overlap this one. ";
	$details .= "<a $trigger>show</a></p>\n";
	$details .= "<ul class=\"ts_ovlist\" id=\"ts_ovlist\" style=\"display: none\">\n";
	$details .= "<li>$_</li>\n" foreach @overlaps;
	$details .= "</ul>\n";
    }
    
    if ( $idata->{obsolete} )
    {
	$details .= "<p>This interval is no longer in current use</p>\n";
    }
    
    if ( $n_colls && defined $n_colls->{colls_defined} )
    {
	my $name = $idata->{interval_name} || '?';
	my $anchor = "<a href=\"/classic/displayCollResults?view=standard&timerule=defined&max_interval=$name\" target=\"_blank\">$n_colls->{colls_defined} collections</a>";
	
	$details .= "<p>This interval is used in the definition of $anchor</p>\n";
    }
    
    if ( $n_colls && defined $n_colls->{colls_major} )
    {
	my $name = $idata->{interval_name} || '?';
	my $anchor = "<a href=\"/classic/displayCollResults?view=standard&timerule=major&max_interval=$name\" target=\"_blank\">$n_colls->{colls_major} collections</a>";
	
	$details .= "<p>A total of $anchor with $n_colls->{occs_major} occurrences lie within this time span</p>\n";
    }

    
    return $details;
}


# generateRangeDetails ( idata1, idata2, name1, name2, b_range, t_range )
# 
# Generate the details pane content for displaying a range of intervals.

sub generateRangeDetails {
    
    my ($idata1, $idata2, $name1, $name2, $b_range, $t_range) = @_;
    
    my $details = "<p>$b_range - $t_range Ma</p>";
    
    my $anchor1 = "<a href=\"$INTERVAL_URL$name1\">Show $name1</a>";
    my $anchor2 = "<a href=\"$INTERVAL_URL$name2\">Show $name2</a>";
    
    $details .= "<p>$anchor1</p>\n";
    $details .= "<p>$anchor2</p>\n" if $name2 ne '?';
    
    return $details;
}


# generateTimescaleDetails ( q, scale_no, reference_list, long_ref, has_interp,
#                            has_obsolete, n_colls )
# 
# Generate the details pane content for displaying a timescale without any
# selected intervals.

sub generateTimescaleDetails {
    
    my ($q, $main_scale, $reference_list, $long_ref, $has_interp, $has_obsolete, $n_colls) = @_;
    
    my $details = '';
    
    if ( $reference_list->@* )
    {
	my $s = $reference_list->@* > 1 ? 's' : '';
	
	$details .= "<h4>The interval definitions in this timescale are derived " .
	    "from the following source$s:</h4>\n";
	$details .= "<ul>\n";
	
	foreach my $r ( $reference_list->@* )
	{
	    my $anchor = "<a href=\"/classic/displayRefResults?reference_no=$r\" target=\"_blank\">view</a>";
	    
	    $details .= "<li>$long_ref->{$r} $anchor</li>\n";
	}
	
	$details .= "</ul>\n";
    }
    
    my ($b_age, $t_age) = ts_bounds($main_scale);
    
    if ( my @overlaps = getOverlapTimescales($b_age, $t_age, $main_scale, $q->query_string) )
    {
	my $count = scalar(@overlaps);
	
	my $trigger = "onclick=\"showOverlapList()\"";
	
	$details .= "<p>There are $count timescales which overlap this one. <a $trigger>show</a></p>\n";
	$details .= "<ul class=\"ts_ovlist\" id=\"ts_ovlist\" style=\"display: none\">\n";
	$details .= "<li>$_</li>\n" foreach @overlaps;
	$details .= "</ul>\n";
    }
    
    if ( $has_interp )
    {
	$details .= "<p>Interval boundaries marked with * have been interpolated based on the ";
	$details .= "differences between the ages for international timescale boundaries ";
	$details .= "quoted in the source and the currently accepted ages for those boundaries.</p>\n";
    }
    
    if ( $has_obsolete )
    {
	$details .= "<p>Interval names marked with &dagger; are no longer in current use.</p>\n";
    }
    
    if ( defined $n_colls && $main_scale )
    {
	my $anchor = "<a href=\"/classic/displayCollResults?view=standard&uses_timescale=$main_scale\" target=\"_blank\">$n_colls collections</a>";
	
	$details .= "<p>This timescale is used in the definition of $anchor</p>\n";
    }
    
    return $details;
}

# expandOrshrink( query_string, b_range )
# 
# Generate a line containing two links. The first expands or contracts the range
# of time displayed, and the second calls the toggleTime() function which
# toggles between displaying linear time and regular time.

sub expandOrShrink {
    
    my ($query_string, $b_range) = @_;
    
    my ($range, $word);
    
    if ( $b_range < 70 )
    {
	$range = 'Cenozoic';
    }
    
    elsif ( $b_range < 150 )
    {
	$range = 'Cretaceous-Cenozoic';
    }
    
    elsif ( $b_range < 253 )
    {
	$range = 'Mesozoic-Cenozoic';
    }
    
    elsif ( $b_range < 300 )
    {
	$range = 'Permian-Cenozoic';
    }
    
    elsif ( $b_range < 420 )
    {
	$range = 'Devonian-Cenozoic';
    }
    
    elsif ( $b_range < 550 )
    {
	$range = 'Phanerozoic';
    }
    
    else
    {
	$range = 'all';
    }
    
    if ( $query_string =~ /&show=[\w-]+/ )
    {
	$query_string =~ s/&show=[\w-]+//;
	$word = 'less';
    }
    
    else
    {
	$query_string .= "&show=$range";
	$word = 'more';
    }
    
    my $ex_link = "<p><a class=\"ts_expand\" href=\"/classic/displayTimescale?$query_string\">Show $word time</a></p>\n";
    my $st_link = "<p><a class=\"ts_expand\" id=\"ts_showtime\" onclick=\"toggleTime()\">Show linear time</a></p>\n";
    
    return "<table><tr><td>$ex_link</td><td>$st_link</td></tr></table>\n";
}


# getOverlapIntervals ( b_age, t_age, interval_no )
# 
# Return a list of links, one for each interval that ovelaps the currently
# displayed one. Each link will add that interval to the display.

my (%OV_SELECT) = ( epoch => 5, subepoch => 4, age => 3, subage => 2, zone => 1, chron => 1 );

sub getOverlapIntervals {
    
    my ($b_age, $t_age, $interval_no) = @_;
    
    my (%list, @result);
    
    my $main_name = int_name($interval_no) // '';
    
    foreach my $int ( ints_by_age($b_age, $t_age, 'overlap') )
    {
	if ( $int->{scale_no} && $OV_SELECT{$int->{type}} && $int->{interval_no} ne $interval_no )
	{
	    push $list{$int->{scale_no}}->@*, $int;
	}
    }
    
    foreach my $s ( sort { $a <=> $b } keys %list )
    {
	my $scale_name = ts_name($s) // 'Timescale';
	my $line = "<em>$scale_name:</em> ";
	
	my @sublist;
	
	foreach my $int ( $list{$s}->@* )
	{
	    my $name = $int->{interval_name};
	    my $type = $int->{type};
	    
	    my $anchor = "<a href=\"$INTERVAL_URL$main_name,$name\">";
	    push @sublist, "$anchor$name</a> $type";
	}
	
	$line .= join(', ', @sublist);
	
	push @result, $line;
    }
    
    return @result;
}


# getOverlapTimescales ( b_age, t_age, main_scale, query_string )
# 
# Return a list of links, one for each timescale that overlaps the currently
# displayed one. Each link will add that timescale to the display.

sub getOverlapTimescales {
    
    my ($b_age, $t_age, $main_scale, $query_string) = @_;
    
    my (@result);
    
    foreach my $ts ( sort { $a->{scale_no} <=> $b->{scale_no} } ts_by_age($b_age, $t_age, 'overlap') )
    {
	if ( $ts->{scale_no} ne $main_scale )
	{
	    my $num = $ts->{scale_no};
	    my $name = $ts->{scale_name};
	    
	    my $new_url = "/classic/displayTimescale?$query_string";
	    
	    if ( $new_url =~ /scale=\d/ )
	    {
		$new_url =~ s/scale=([\d,]+)/scale=$main_scale,$num/;
	    }
	    
	    else
	    {
		$new_url .= "&scale=$main_scale,$num";
	    }
	    
	    push @result, "<a href=\"$new_url\">$name</a>";
	}
    }
    
    return @result;
}


# listTimescales ( dbt, hbo, s, q )
# 
# List the timescales known to the database.

sub listTimescales {
    
    my ($dbt, $hbo, $s, $q) = @_;
    
    my $dbh = $dbt->dbh;
    
    my $html .= "<div class=\"ts_list\"><h4>Main timescales</h4>\n<ul>\n";
    
    my ($sql, $result);
    
    my ($main_heading, $global_heading, $regional_heading, $nz_heading);
    
    $sql = "SELECT * FROM $TABLE{SCALE_DATA}
	    ORDER BY scale_no";
    
    # Add headings, to indicate the various groupings of timescales according to
    # their identifying numbers.
    
    foreach my $s ( $dbh->selectall_array($sql, { Slice => { } }) )
    {
	my $snum = $s->{scale_no};
	my $name = $s->{scale_name};
		
	if ( $snum > 10 && ! $global_heading )
	{
	    $html .= "</ul>\n<h4>Additional global timescales</h4>\n<ul>\n";
	    $global_heading = 1;
	}
	
	if ( $snum >= 50 && ! $regional_heading )
	{
	    $html .= "</ul>\n<h4>Regional timescales</h4>\n<ul>\n";
	    $regional_heading = 1;
	}
	
	if ( $snum >= 250 && ! $nz_heading )
	{
	    $html .= "</ul>\n<h4>New Zealand timescales</h4>\n<ul>\n";
	    $nz_heading = 1;
	}
	
	my $link = "/classic/displayTimescale?scale=$snum";
	my $anchor = "<a href=\"$link\">$name</a>";
	
	$html .= "<li>$anchor</li>\n";
    }
    
    $html .= "</ul></div>\n";
    
    my $fields = { heading => "<h3 class=\"ts_heading\">The following timescales are defined in The Paleobiology Database:</h3>",
		   diagram => $html };
    
    my $output = $hbo->populateHTML("display_timescales", $fields);
    
    $hbo->pageTitle('PBDB Timescale List');
    
    return $output;
}


# sub fetchBoundsByName {
    
#     my ($dbh, $name) = @_;
    
#     my $qname = $dbh->quote($name);
#     my $sql;
    
#     if ( $name =~ /^\d+$/ )
#     {
# 	$sql = "SELECT early_age, late_age FROM $TABLE{INTERVAL_DATA}
# 		WHERE interval_no = $qname";
#     }
    
#     else
#     {
# 	$sql = "SELECT early_age, late_age FROM $TABLE{INTERVAL_DATA}
# 		WHERE interval_name = $qname";
#     }
    
#     return $dbh->selectrow_array($sql);
# }
    

# collectionIntervalLabel( interval_no, [interval_no] )
# 
# Given one or two interval numbers, return a label suitable for the collection
# search results.

sub collectionIntervalLabel {
    
    my ($i1, $i2) = @_;
    
    if ( int_defined($i1) && int_defined($i2) && $i1 ne $i2 )
    {
	my $iname1 = int_name($i1) // '?';
	my $iname2 = int_name($i2) // '?';
	
	my $label = "<a href=\"$RANGE_URL$i1-$i2\" target=\"_blank\">$iname1/$iname2</a>";
	
	my $bin1 = int_correlation($i1, 'ten_my_bin');
	my $bin2 = int_correlation($i2, 'ten_my_bin');
	
	if ( $bin1 && $bin2 && $bin1 eq $bin2 )
	{
	    $label .= " - $bin1";
	    return $label;
	}
	
	elsif ( $bin1 && $bin2 )
	{
	    my ($period1, $num1) = split /\s/, $bin1;
	    my ($period2, $num2) = split /\s/, $bin2;
	    
	    if ( $period1 eq $period2 )
	    {
		$label .= " - $period1 $num1-$num2";
		return $label;
	    }
	    
	    else
	    {
		$label .= " - $bin1/$bin2";
		return $label;
	    }
	}
	
	elsif ( $bin1 )
	{
	    $label .= " - $bin1";
	    return $label;
	}
	
	else
	{
	    return '?';
	}
    }
    
    elsif ( int_defined($i1) )
    {
	my $interval_name = int_name($i1) // '?';
	my $label = "<a href=\"$INTERVAL_URL$i1\" target=\"_blank\">$interval_name</a>";
	
	if ( my $ten_my_bin = int_correlation($i1, 'ten_my_bin') )
	{
	    $label .= " - $ten_my_bin";
	}
	
	return $label;
    }
    
    else
    {
	return '?';
    }
}

1;
