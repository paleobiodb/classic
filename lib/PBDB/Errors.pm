#!/usr/bin/env perl

# created by rjp, 3/2004.
# Used to keep track of error messages to display to the user.


package PBDB::Errors;

use strict;

use fields qw(	
				count
				errorString
				displayEndingMessage
			
				);  # list of allowable data fields.

						

sub new {
	my $class = shift;
	my PBDB::Errors $self = fields::new($class);
	
	$self->{count} = 0;
	$self->{displayEndingMessage} = 1;

	return $self;
}


# adds an error with a bullet point to the list of error messages.
sub add {
	my PBDB::Errors $self = shift;
	my $newError = shift;

	if ($newError) {
		$self->{errorString} .= "<LI>$newError</LI>\n";
		$self->{count} += 1;
	}
}

# returns a count of how many errors the user has added.
sub count {
	my PBDB::Errors $self = shift;
	
	return $self->{count};
}

# pass this a boolean,
# should we display the ending message ("make corrections as necessary, etc.") or not?
sub setDisplayEndingMessage {
	my PBDB::Errors $self = shift;	
	$self->{displayEndingMessage} = shift;
}

# returns the error message.
sub errorMessage {
	my PBDB::Errors $self = shift;
	
	my $count = numberToName($self->{count});
	
	if ($self->{count} == 1) {
		$count = "error";
	} else {
		$count .= " errors";	
	}
	
	my $errString = qq|<div class="errorMessage">
<div class="errorTitle">Please fix the following $count and resubmit</div>
<ul class="small" style="text-align: left;">
$self->{errorString}
</ul>
</div>
|;

    if ($self->{count} > 0) {
	    return $errString;
    } else {
        return '';
    }
}

# pass this method another Error object, and it will append the
# new object onto the end of itself.
sub appendErrors {
	my PBDB::Errors $self = shift;
	
	my $errorsToAppend = shift;
	
	if ($errorsToAppend) {
		$self->{errorString} .= $errorsToAppend->{errorString};
		$self->{count} += $errorsToAppend->{count};
	}
}


# pass this a number like "5" and it will return the name ("five").
# only works for numbers up through 19.  Above that and it will just return
# the original number.
#
sub numberToName {
    my $num = shift;

    my %numtoname = (  "0" => "zero", "1" => "one", "2" => "two",
                         "3" => "three", "4" => "four", "5" => "five",
                         "6" => "six", "7" => "seven", "8" => "eight",
                         "9" => "nine", "10" => "ten",
                         "11" => "eleven", "12" => "twelve", "13" => "thirteen",
                         "14" => "fourteen", "15" => "fifteen", "16" => "sixteen",
                         "17" => "seventeen", "18" => "eighteen", "19" => "nineteen");

    my $name;

    if ($num < 20) {
        $name = $numtoname{$num};
    } else {
        $name = $num;
    }

    return $name;
}




# end of Errors.pm


1;

