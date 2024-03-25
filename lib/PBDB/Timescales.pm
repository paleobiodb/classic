
use strict;

package PBDB::Timescales;

use PBDB::Reference;

use TableDefs qw(%TABLE);
use CoreTableDefs;
use PB2::IntervalData qw($INTL_SCALE $BIN_SCALE %SDATA %SSEQUENCE %IDATA);
use List::Util qw(min);
use JSON;


# displayTimescale ( )
# 
# Display the specified timescale or portion of a timescale as an HTML diagram with
# interval names, ages, and colors. 

sub displayTimescale {
    
    my ($dbt, $hbo, $s, $q) = @_;
    
    my $dbh = $dbt->dbh;
    
    # Make sure that we have cached all of the interval and timescale data.
    
    unless ( %IDATA )
    {
	PB2::IntervalData->cache_interval_data($dbh);
    }
    
    # Parse the parameters of this call.
    
    my $scale_no = $q->param('scale_no');
    my $interval_no = $q->param('interval_no');
    my $interval_name = $q->param('interval');
    my $display = $q->param('display');
    my $time = $q->param('time');
    my $action = $q->param('type') || $q->param('action');
    
    if ( $action eq 'list' )
    {
	return listTimescales($dbt, $hbo, $s, $q);
    }
    
    my $options = { mark_obsolete => 1 };
    
    my $heading = 'Display Timescale';
    my $details = '';
    
    my ($has_interp, $has_obsolete, $n_colls, $t_range, $b_range);
    
    my ($sql, $result);
    
    my (@scale_list, $main_scale, %use_scale, 
	@interval_list, $main_interval, $main_idata, @other_ts);
    
    my (@reference_list, %reference_uniq, 
	@long_refs, %long_ref, %short_ref);
    
    my (%n_colls);
    
    if ( defined $scale_no && $scale_no !~ /^\d[\d\s,]*$/ )
    {
	return "<h2>Invalid timescale identifier '$scale_no'</h2>";
    }
    
    if ( defined $interval_no && $interval_no !~ /^\d[\d\s,]*$/ )
    {
	return "<h2>Invalid interval identifier '$interval_no'</h2>";
    }
    
    unless ( $scale_no || $interval_no || $interval_name )
    {
	return "<h2>You must specify either a timescale identifier or an interval identifier</h2>";
    }
    
    my (@names, @nums);
    
    if ( $interval_name )
    {
	my @args = split /\s*,\s*/, $interval_name;
	
	foreach my $n ( @args )
	{
	    if ( $n =~ /^\d+$/ )
	    {
		push @nums, $n;
	    }
	    
	    elsif ( $n =~ /\w/ )
	    {
		push @names, $n;
	    }
	}
    }
    
    if ( $interval_no )
    {
	push @nums, grep { $_ =~ /\d/ } split /\s*,\s*/, $interval_no;
    }
	
    if ( @names )
    {
	my $name_string = join ',', map { $dbh->quote(lc $_) } @names;
	
	$sql = "SELECT interval_no FROM $TABLE{INTERVAL_DATA}
		WHERE interval_name in ($name_string)";
	
	$result = $dbh->selectcol_arrayref($sql);
	
	push @interval_list, $result->@*;
    }
    
    if ( @nums )
    {
	my $num_string = join ',', @nums;
	
	$sql = "SELECT interval_no FROM $TABLE{INTERVAL_DATA}
		WHERE interval_no in ($num_string)";
	
	$result = $dbh->selectcol_arrayref($sql);
	
	push @interval_list, $result->@*;
    }
    
    if ( @names || @nums )
    {
	unless ( @interval_list )
	{
	    return "<h2>You did not specify any valid intervals</h2>";
	}
    }
    
    if ( $scale_no && $scale_no =~ /\d/ )
    {
	my @nos = split /\s+,\s+/, $scale_no;
	
	my $num_string = join ',', grep { $_ =~ /\d+$/ } @nos;
	
	$sql = "SELECT distinct scale_no FROM $TABLE{SCALE_DATA}
		WHERE scale_no in ($num_string)";
	
	$result = $dbh->selectcol_arrayref($sql);
	
	unless ( $result->@* )
	{
	    return "<h2>You did not specify any valid timescale identifiers</h2>";
	}
	
	foreach my $n ( $result->@* )
	{
	    unless ( $use_scale{$n} )
	    {
		push @scale_list, $n;
		$use_scale{$n} = 1;
	    }
	}
    }
    
    if ( @interval_list )
    {
	$main_interval = $interval_list[0];
	
	my $num_string = join ',', @interval_list;
	
	$sql = "SELECT distinct scale_no FROM $TABLE{INTERVAL_DATA}
		WHERE interval_no in ($num_string)";
	
	$result = $dbh->selectcol_arrayref($sql);
	
	foreach my $n ( $result->@* )
	{
	    unless ( $use_scale{$n} )
	    {
		if ( $n eq $INTL_SCALE ) {
		    unshift @scale_list, $n;
		} else { 
		    push @scale_list, $n
		}
		$use_scale{$n} = 1;
	    }
	}
	
	foreach my $i ( @interval_list )
	{
	    $options->{highlight}{$i} = 1;
	}
    }
    
    # Fetch scale information
    
    if ( @scale_list )
    {
	$main_scale = $scale_list[0];
	
	unshift @scale_list, $INTL_SCALE unless $use_scale{$INTL_SCALE};
	
	# $sql = "SELECT * FROM $TABLE{SCALE_DATA}
	# 	WHERE scale_no in ($scale_string)";
	
	# foreach my $s ( $dbh->selectall_array($sql, { Slice => { } }) )
	# {
	#     my $scale_no = $s->{scale_no};
	    
	#     $SDATA{$scale_no} = $s;
	# }
	
	# $sql = "SELECT sm.scale_no, sm.interval_no, sm.color, sm.type, sm.reference_no,
	# 	    i.interval_name, i.abbrev, sm.obsolete,
	# 	    i.early_age as b_age, i.b_ref, i.b_type, 
	# 	    i.late_age as t_age, i.t_ref, i.t_type
	# 	FROM $TABLE{SCALE_MAP} as sm join $TABLE{INTERVAL_DATA} as i using (interval_no)
	# 	WHERE sm.scale_no in ($scale_string)
	# 	ORDER BY scale_no, sequence";
	
	# foreach my $int ( $dbh->selectall_array($sql, { Slice => { } }) )
	# {
	#     my $scale_no = $int->{scale_no};
	#     my $interval_no = $int->{interval_no};
	#     my $ikey = "s$scale_no-$interval_no";
	    
	#     $int->{b_age} =~ s/[.]?0+$//;
	#     $int->{b_ref} =~ s/[.]?0+$//;
	#     $int->{t_age} =~ s/[.]?0+$//;
	#     $int->{t_ref} =~ s/[.]?0+$//;
	
	foreach my $scale_no ( @scale_list )
	{
	    foreach my $int ( $SSEQUENCE{$scale_no}->@* )
	    {
		if ( $scale_no eq $main_scale || $scale_no ne $INTL_SCALE )
		{
		    my $reference_no = $int->{reference_no};
		    
		    if ( $reference_no && ! $reference_uniq{$reference_no} )
		    {
			push @reference_list, $reference_no;
			$reference_uniq{$reference_no} = 1;
		    }
		    
		    $t_range = $int->{t_age} if ! defined $t_range || $int->{t_age} < $t_range;
		    $b_range = $int->{b_age} if ! defined $b_range || $int->{b_age} > $b_range;
		}
		
		$has_interp = 1 if $int->{t_type} eq 'interpolated' ||
		    $int->{b_type} eq 'interpolated';
		
		if ( $int->{obsolete} )
		{
		    $has_obsolete = 1;
		}
		
		# push $SSEQUENCE{$scale_no}->@*, $int;
		# $IDATA{$ikey} = $int;
		
		if ( $scale_no eq $main_scale && $main_interval && 
		     $int->{interval_no} eq $main_interval )
		{
		    $main_idata = $int;
		}
	    }
	}
    }
    
    # If the displayed diagram should be trimmed by age, do so now.
    
    if ( $display =~ /(\w+?)-(\w+)/ )
    {
	my ($b1, $t1) = fetchBoundsByName($dbh, $1);
	my ($b2, $t2) = fetchBoundsByName($dbh, $2);
	
	unless ( defined $b1 && defined $b2 )
	{
	    return "<h2>Invalid interval '$display'</h2>";
	}
	
	$options->{t_limit} = min($t1, $t2);
	$options->{b_limit} = max($b1, $b2);
    }
    
    elsif ( $display =~ /\w/ )
    {
	my ($b, $t) = fetchBoundsByName($dbh, $display);
	
	unless ( defined $b )
	{
	    return "<h2>Invalid interval '$display'</h2>";
	}
	
	$options->{t_limit} = $t;
	$options->{b_limit} = $b;
    }
    
    elsif ( $main_interval )
    {
	my ($period_no) = $dbh->selectrow_array("SELECT period_no FROM interval_lookup
		WHERE interval_no = $main_interval");
	
	my ($b, $t) = fetchBoundsByName($dbh, $period_no);
	
	$options->{t_limit} = $t;
	$options->{b_limit} = $b;
    }
    
    if ( defined $options->{t_limit} && $options->{t_limit} > $t_range )
    {
	$t_range = $options->{t_limit};
    }
    
    if ( defined $options->{b_limit} && $options->{b_limit} < $b_range )
    {
	$b_range = $options->{b_limit};
    }
    
    # If we have at least one scale, look up collection counts.
    
    if ( @scale_list )
    {
	my $scale_string = join ',', @scale_list;
	
	$sql = "SELECT i.interval_no, count(*) as n_colls
		FROM $TABLE{INTERVAL_DATA} as i 
		    join $TABLE{SCALE_MAP} as sm using (interval_no)
		    join collections as c on
			i.interval_no = c.max_interval_no or
			i.interval_no = c.min_interval_no or
			i.interval_no = c.ma_interval_no
		WHERE sm.scale_no in ($scale_string) and 
		      i.early_age > '$t_range' and i.late_age < '$b_range'
		GROUP BY i.interval_no";
	
	foreach my $int ( $dbh->selectall_array($sql, { Slice => { } }) )
	{
	    my $interval_no = $int->{interval_no};
	    $n_colls{$interval_no} = $int->{n_colls};
	}
	
	if ( $main_scale ne $INTL_SCALE )
	{
	    $sql = "SELECT count(*)
		FROM collections as c join $TABLE{SCALE_MAP} as sm
			on sm.interval_no = c.max_interval_no or
			   sm.interval_no = c.min_interval_no or
			   sm.interval_no = c.ma_interval_no
		     join $TABLE{INTERVAL_DATA} as i using (interval_no)
		WHERE sm.scale_no = $main_scale and i.scale_no = sm.scale_no";
	    
	    ($n_colls) = $dbh->selectrow_array($sql);
	}
    }
    
    else
    {
	return "<h2>No valid timescales were specified</h2>";
    }
    
    foreach my $reference_no ( @reference_list )
    {
	my $ref = PBDB::Reference->new($dbt, $reference_no);
	
	if ( $ref )
	{
	    $long_ref{$reference_no} = $ref->formatLongRef();
	    $short_ref{$reference_no} = $ref->formatShortRef();
	    
	    my $anchor = "<a href=\"/classic/displayRefResults?reference_no=$reference_no\" target=\"classic2\">view</a>";
	    
	    push @long_refs, "<li>$long_ref{$reference_no} $anchor</li>\n";
	}
    }
    
    # If we are displaying information about an interval, fetch the names and
    # identifiers of other timescales in which it is used.
    
    # if ( $main_interval )
    # {
    # 	$sql = "SELECT distinct sm.scale_no, sd.scale_name
    # 		FROM $TABLE{SCALE_MAP} as sm join $TABLE{SCALE_DATA} as sd using (scale_no)
    # 			join $TABLE{INTERVAL_DATA} as i using (interval_no)
    # 		WHERE sm.interval_no = $main_interval and sm.scale_no <> i.scale_no";
    
    # if ( $time && $time eq 'linear' )
    # {
    # 	$options->{lintime} = 1;
    # }
    
    # Generate the diagram
    
    my $d = PB2::IntervalData->generate_ts_diagram($options, \%SDATA, \%SSEQUENCE, @scale_list);
    
    my $html_output = PB2::IntervalData->generate_ts_html($d, \%SDATA);
    
    my @bounds_list = map { $_->[0] } $d->{bound2d}->@*;
    
    # Generate the details list
    
    my $details = '';
    
    if ( $main_idata )
    {
	my $name = $main_idata->{interval_name} || '?';
	my $type = $main_idata->{type} || '';
	
	$heading = "<h3 class=\"ts_heading\">$name <span class=\"ts_type\">$type</span></h3>\n";
	
	my $scale_no = $main_idata->{scale_no};
	my $scale_name = $SDATA{$scale_no}{scale_name};
	my $reference_no = $main_idata->{reference_no};
	my $t_age = $main_idata->{t_age};
	my $t_type = $main_idata->{t_type};
	my $b_age = $main_idata->{b_age};
	my $b_type = $main_idata->{b_type};
	
	$details .= "<p>$b_age - $t_age Ma</p>\n";
	
	my $ts_anchor = "<a href=\"/classic/displayTimescale?scale_no=$scale_no\">$scale_name</a>";
	
	if ( $long_ref{$reference_no} )
	{
	    $details .= "<p>The definition of this interval in the timescale $ts_anchor " .
		"is taken from the following source:</p>\n";
	    
	    my $anchor = "<a href=\"/classic/displayRefResults?reference_no=$reference_no\" " .
		"target=\"classic2\">view</a>";
	    
	    $details .= "<ul>";
	    $details .= "<li>$long_ref{$reference_no} $anchor</li>";
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
	
	if ( $main_idata->{obsolete} )
	{
	    $details .= "<p>This interval is no longer in current use</p>\n";
	}
	
	if ( my $n_colls = $n_colls{$main_interval} )
	{
	    my $anchor = "<a href=\"/classic/displayCollResults?type=view&person_type=authorizer&sortby=collection_no&basic=yes&limit=30&uses_interval=$main_interval\" target=\"classic2\">$n_colls collections</a>";
	    
	    $details .= "<p>This interval is used in the definition of $anchor</p>\n";
	}
    }
    
    else
    {
	my $name = $SDATA{$main_scale}{scale_name} || '?';
	
	$heading = "<h3 class=\"ts_heading\">$name</h3>\n";
	
	if ( @reference_list )
	{
	    my $s = @reference_list > 1 ? 's' : '';
	    
	    $details .= "<h4>The interval definitions in this timescale are derived " .
		"from the following source$s:</h4>\n";
	    $details .= "<ul>\n";
	    
	    $details .= $_ foreach @long_refs;
	    
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
	    my $anchor = "<a href=\"/classic/displayCollResults?type=view&person_type=authorizer&sortby=collection_no&basic=yes&limit=30&uses_timescale=$main_scale\" target=\"classic2\">$n_colls collections</a>";
	    
	    $details .= "<p>This timescale is used in the definition of $anchor</p>\n";
	}
    }
    
    # Generate the data needed by the accompanying Javascript code in JSON
    # format.
    
    my %idata;
    
    foreach my $scale_no ( @scale_list )
    {
	foreach my $int ( $SSEQUENCE{$scale_no}->@* )
	{
	    if ( $int->{b_age} > $t_range && $int->{t_age} < $b_range )
	    {
		my $interval_no = $int->{interval_no};
		my $ikey = "s$scale_no-$interval_no";
		
		$idata{$ikey} = { $int->%* };
		$idata{$ikey}{n_colls} = $n_colls{$interval_no} if defined $n_colls{$interval_no};
	    }
	}
    }
    
    my $idata_encoded = encode_json(\%idata);
    $idata_encoded =~ s/}/}\n/g;
    
    my $refs_encoded = encode_json(\%short_ref);
    $refs_encoded =~ s/}/}\n/g;
    
    my $bounds_encoded = encode_json(\@bounds_list);
    
    my $idata = "intl_scale = $INTL_SCALE;
bin_scale = $BIN_SCALE;
t_range = $t_range;
b_range = $b_range;
interval_data = $idata_encoded;
interval_bounds = $bounds_encoded;
ref_data = $refs_encoded\n";
    
    # Generate the page itself.
    
    my $fields = { heading => $heading,
		   details => $details,
		   idata => $idata,
		   diagram => $html_output };
    
    my $output = $hbo->populateHTML("display_timescales", $fields);
    
    return $output;
}


sub listTimescales {
    
    my ($dbt, $hbo, $s, $q) = @_;
    
    my $dbh = $dbt->dbh;
    
    my $html .= "<div class=\"ts_list\"><h4>Main timescales</h4>\n<ul>\n";
    
    my ($sql, $result);
    
    my ($main_heading, $global_heading, $regional_heading, $nz_heading);
    
    $sql = "SELECT * FROM $TABLE{SCALE_DATA}
	    ORDER BY scale_no";
    
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
	
	my $link = "/classic/displayTimescale?scale_no=$snum";
	my $anchor = "<a href=\"$link\">$name</a>";
	
	$html .= "<li>$anchor</li>\n";
    }
    
    $html .= "</ul></div>\n";
    
    my $fields = { heading => "<h3 class=\"ts_heading\">The following timescales are defined in The Paleobiology Database:</h3>",
		   diagram => $html };
    
    my $output = $hbo->populateHTML("display_timescales", $fields);
    
    return $output;
}


sub fetchBoundsByName {
    
    my ($dbh, $name) = @_;
    
    my $qname = $dbh->quote($name);
    my $sql;
    
    if ( $name =~ /^\d+$/ )
    {
	$sql = "SELECT early_age, late_age FROM $TABLE{INTERVAL_DATA}
		WHERE interval_no = $qname";
    }
    
    else
    {
	$sql = "SELECT early_age, late_age FROM $TABLE{INTERVAL_DATA}
		WHERE interval_name = $qname";
    }
    
    return $dbh->selectrow_array($sql);
}
    
    
1;
