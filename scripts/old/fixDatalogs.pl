#!/usr/bin/env perl
# 
# Fix improperly written datalog files.  This should be run with '-i'.

# When we find a header line, grab the 



my ($state, $replace, $op, $key, $record);
my ($oldargv, $line, $count, $replacements);

$record = '';
$state = 0;

while ( <> )
{
    # Keep track of line numbers, for error messages
    
    if ( $ARGV ne $oldargv )
    {
	if ( $count > 0 )
	{
	    print STDERR "    wrote $count records.\n";
	    print STDERR "    made $replacements replacements.\n";
	}
	
	$line = 1;
	$count = 0;
	$replacements = 0;
	print STDERR "Processing $ARGV...\n";
	$oldargv = $ARGV;
    }
    
    else
    {
	$line++;
    }
    
    # Now execute the proper state
    
    if ( / ^ \# \s+ ( \d\d\d\d .* ) /xs )
    {
	if ( $state eq '0' )
	{
	    $record = $_;
	    $state = 1;
	    ($date, $op, $table, $key) = split(qr{ [|] }, $1);
	}
	
	else
	{
	    print STDERR "ERROR: header found unexpectedly at $ARGV, line $line\n";
	}
    }
    
    elsif ( / ^ [a-zA-Z] /xsi )
    {
	if ( $state eq '1' )
	{
	    if ( $op eq 'INSERT' && $_ =~ qr{ ^ INSERT }xsi )
	    {
		s{ ^ INSERT (?: \s+ IGNORE )? }{ "REPLACE" }xei;
		s{ ( VALUES \s+ \( ) }{ "$1$key," }xei unless $table eq 'secondary_refs';
		$replacements++;
	    }
	    
	    $record .= $_;
	    $state = 2;
	}
	
	else
	{
	    print STDERR "ERROR: $op found without header at $ARGV, line $line\n";
	}
    }
    
    elsif ( / ^ \# \s+ = /xsi )
    {
	if ( $state eq '2' )
	{
	    $record .= $_;
	    print $record;
	    $record = '';
	    $count++;
	    $state = 0;
	}
	
	else
	{
	    print STDERR "ERROR: end found without header at $ARGV, line $line\n";
	}
    }
    
    elsif ( / ^ \# \s+ /xsi )
    {
	if ( $state eq '2' )
	{
	    $record .= $_;
	}
	
	else
	{
	    print STDERR "ERROR: extra line found unexpectedly at $ARGV, line $line\n";
	}
    }
    
    else
    {
	print STDERR "ERROR: unknown line found at $ARGV, line $line\n";
    }
}


print STDERR "    wrote $count records.\n";
print STDERR "    made $replacements replacements.\n";
