# created by rjp, 1/2004.

# the following functions were moved into ReferenceEntry.pm by JA 4.6.13:
# formatRISRef, risLine, risAuthor, risYear, risOtherAuthors (McClennen
#  functions), getSecondaryRefs (used in CollectionEntry.pm),
#  displayReferenceForm, processReferenceForm, checkFraud

package PBDB::Reference;

use strict;
use PBDB::AuthorNames;
use Class::Date qw(now date);
use PBDB::Debug qw(dbg);
use PBDB::Constants qw($TAXA_TREE_CACHE $COLLECTION_NO makeAnchor
		       makeAnchorWithAttrs makeATag makeFormPostTag);
use PBDB::Download;
use PBDB::Person;
# calls to these two modules need to be removed eventually
use PBDB::Nexusfile;
use PBDB::PBDBUtil;
use PBDB::Opinion;
use PBDB::ReferenceEntry;
use PBDB::Permissions;
use Text::CSV_XS;

use Carp qw(carp);

# Paths from the Apache environment variables (in the httpd.conf file).

use fields qw(reference_no
				reftitle
				pubtitle
				editors
				pubyr
				pubvol
				pubno
				firstpage
				lastpage
				project_name
				author1init
				author1last
				author2init
				author2last
				otherauthors
				authorizer
                dbt);  # list of allowable data fields.

						

sub new {
	my $class = shift;
    my $dbt = shift;
    my $reference_no = shift;
	my PBDB::Reference $self = fields::new($class);

    my $error_msg = "";

    if (!$reference_no) { 
        $error_msg = "Could not create Reference object with reference_no=undef."
    } else {
        my @fields = qw(reference_no reftitle pubtitle editors pubyr pubvol pubno firstpage lastpage author1init author1last author2init author2last otherauthors project_name);
        my $sql = "SELECT ".join(",",@fields)." FROM refs WHERE reference_no=".$dbt->dbh->quote($reference_no);
        my @results = @{$dbt->getData($sql)};
        if (@results) {
            foreach $_ (@fields) {
                $self->{$_}=$results[0]->{$_};
            }
        } else {
            $error_msg = "Could not create Reference object with reference_no=$reference_no."
        }
    }

    if ($error_msg) {
        my $cs = "";
        for(my $i=0;$i<10;$i++) {
            my ($package, $filename, $line, $subroutine) = caller($i);
            last if (!$package);
            $cs .= "$package:$line:$subroutine ";
        }
        $cs =~ s/\s*$//;
        $error_msg .= " Call stack is $cs.";
        carp $error_msg;
        return undef;
    } else {
        return $self;
    }
}

# return the referenceNumber
sub get {
	my PBDB::Reference $self = shift;
	my $field = shift;

	return ($self->{$field});	
}

sub pages {
	my PBDB::Reference $self = shift;
	
	my $p = $self->{'firstpage'};
	if ($self->{'lastpage'}) {
		$p .= "-" . $self->{'lastpage'};	
	}
	
	return $p;	
}

# get all authors and year for reference
sub authors {
	my PBDB::Reference $self = shift;
    return formatShortRef($self);
}

# returns a nicely formatted HTML reference line.
sub formatAsHTML {
	my PBDB::Reference $self = shift;
	
	if ($self->{reference_no} == 0) {
		# this is an error, we should never have a zero reference.
		return "no reference";	
	}
	
	my $html = $self->authors() . ". ";
	if ($self->{reftitle})	{ $html .= $self->{reftitle}; }
	if ($self->{pubtitle})	{ $self->{pubtitle} = " <i>" . $self->{pubtitle} . "</i>"; }
	if ($self->{editors} =~ /(,)|( and )/)	{ $self->{pubtitle} = ". In " . $self->{editors} . " (eds.), " . $self->{pubtitle} . ""; }
	elsif ($self->{editors})	{ $self->{pubtitle} = ". In " . $self->{editors} . " (ed.), " . $self->{pubtitle} . ""; }
	if ($self->{pubtitle})	{ $html .= $self->{pubtitle}; }
	if ($self->{pubvol}) 	{ $html .= " <b>" . $self->{pubvol} . "</b>"; }
	if ($self->{pubno})		{ $html .= "<b>(" . $self->{pubno} . ")</b>"; }

	if ($self->pages())		{ $html .= ":" . $self->pages(); }
	
	return $html;
}

sub getReference {
    my $dbt = shift;
    my $reference_no = int(shift);

    if ($reference_no) {
        my $sql = "SELECT authorizer_no,enterer_no,modifier_no,r.reference_no,r.author1init,r.author1last,r.author2init,r.author2last,r.otherauthors,r.pubyr,r.reftitle,r.pubtitle,r.editors,r.publisher,r.pubcity,r.pubvol,r.pubno,r.firstpage,r.lastpage,r.created,r.modified,r.publication_type,r.basis,r.language,r.doi,r.comments,r.project_name,r.project_ref_no FROM refs r WHERE r.reference_no=$reference_no";
        my $ref = ${$dbt->getData($sql)}[0];
        my %lookup = %{PBDB::PBDBUtil::getPersonLookup($dbt)};
        $ref->{'authorizer'} = $lookup{$ref->{'authorizer_no'}};
        $ref->{'enterer'} = $lookup{$ref->{'enterer_no'}};
        $ref->{'modifier'} = $lookup{$ref->{'modifier_no'}};
        return $ref;
    } else {
        return undef;
    }
    
}
# JA 16-17.8.02
# Moved and extended by PS 05/2005 to accept a number (reference_no) or hashref (if all the pertinent data has been grabbed already);
sub formatShortRef  {
    my $refData;
    my %options;
    if (UNIVERSAL::isa($_[0],'PBDB::DBTransactionManager')) {
        my $dbt = shift;
        my $reference_no = int(shift);
        if ($reference_no) {
            my $sql = "SELECT reference_no,author1init,author1last,author2init,author2last,otherauthors,pubyr FROM refs WHERE reference_no=$reference_no";
            $refData = ${$dbt->getData($sql)}[0];
        }
        %options = @_;
    } else {
        $refData = shift;
        %options = @_;
    }
    return if (!$refData);

    # stuff like Jr. or III often is in the last name fields, and for a short
    #  ref we don't care about it JA 18.4.07

    $refData->{'author1last'} =~ s/( Jr)|( III)|( II)//;
    $refData->{'author1last'} =~ s/\.$//;
    $refData->{'author1last'} =~ s/,$//;
    $refData->{'author2last'} =~ s/( Jr)|( III)|( II)//;
    $refData->{'author2last'} =~ s/\.$//;
    $refData->{'author2last'} =~ s/,$//;
    
    my $shortRef = "";
    $shortRef .= $refData->{'author1init'}." " if $refData->{'author1init'} && ! $options{'no_inits'};
    $shortRef .= $refData->{'author1last'};
    if ( $refData->{'otherauthors'} ) {
        $shortRef .= " et al.";
    } elsif ( $refData->{'author2last'} ) {
        # We have at least 120 refs where the author2last is 'et al.'
        if($refData->{'author2last'} !~ /^et al/i){
            $shortRef .= " and ";
        	$shortRef .= $refData->{'author2init'}." " if $refData->{'author2init'} && ! $options{'no_inits'};
        	$shortRef .= $refData->{'author2last'};
        } else {
            $shortRef .= " et al.";
        }
    }
    if ($refData->{'pubyr'}) {
        if ($options{'alt_pubyr'}) {
            $shortRef .= " (" . $refData->{'pubyr'} . ")"; 
        } else {
            $shortRef .= " " . $refData->{'pubyr'};
        }
    }

    if ($options{'link_id'}) {
        if ($refData->{'reference_no'}) {
            $shortRef = makeAnchor("app/refs", "#display=$refData->{reference_no}", $shortRef);
        }
    }
    if ($options{'show_comments'}) {
        if ($refData->{'comments'}) {
            $shortRef .= " [" . $refData->{'comments'}."]";
        }
    }
    if ($options{'is_recombination'}) {
        $shortRef = "(".$shortRef.")";
    }

    return $shortRef;
}

sub formatLongRef {
    my $ref;
    if (UNIVERSAL::isa($_[0],'DBTransactionManager')) {
        $ref = getReference(@_);
    } else {
        $ref = shift;
    }
    return if (!$ref);

    return "" if (!$ref);

    my $longRef = "";
    my $an = PBDB::AuthorNames->new($ref);
	$longRef .= $an->toString();

	$longRef .= "." if $longRef && $longRef !~ /\.\Z/;
	$longRef .= " ";

	$longRef .= $ref->{'pubyr'}.". " if $ref->{'pubyr'};

	$longRef .= $ref->{'reftitle'} if $ref->{'reftitle'};
	$longRef .= "." if $ref->{'reftitle'} && $ref->{'reftitle'} !~ /\.\Z/;
	$longRef .= " " if $ref->{'reftitle'};

	$ref->{'pubtitle'} = "<i>" . $ref->{'pubtitle'} . "</i>" if $ref->{'pubtitle'};
	if ($ref->{'pubtitle'} && $ref->{'editors'} =~ /(,)|( and )/)	{ $ref->{'pubtitle'} = " In " . $ref->{'editors'} . " (eds.), " . $ref->{'pubtitle'}; }
	elsif ($ref->{'pubtitle'} && $ref->{'editors'})	{ $ref->{'pubtitle'} = " In " . $ref->{'editors'} . " (ed.), " . $ref->{'pubtitle'}; }
	$longRef .= $ref->{'pubtitle'}." " if $ref->{'pubtitle'};

	$longRef .= "<b>" . $ref->{'pubvol'} . "</b>" if $ref->{'pubvol'};

	$longRef .= "<b>(" . $ref->{'pubno'} . ")</b>" if $ref->{'pubno'};

	$longRef .= ":" if $ref->{'pubvol'} && ( $ref->{'firstpage'} || $ref->{'lastpage'} );

	$longRef .= $ref->{'firstpage'} if $ref->{'firstpage'};
	$longRef .= "-" if $ref->{'firstpage'} && $ref->{'lastpage'};
	$longRef .= $ref->{'lastpage'};
	# also displays authorizer and enterer JA 23.2.02
	if ( $ref->{'authorizer'} )	{
		$longRef .= "<span class=\"small\"> [".$ref->{'authorizer'}."/".
			   $ref->{'enterer'};
		if($ref->{'modifier'}){
			$longRef .= "/".$ref->{'modifier'};
		}
		$longRef .= "]</span>";
	}
    return $longRef;
}


# Given a hash whose pages are page numbers or page ranges, generate a single
# non-duplicative list.

sub coalescePages {

    my ($pages) = @_;
    
    return unless ref $pages eq 'HASH';
    
    my (%range, %other);
    
    foreach my $spec (keys %$pages)
    {
	if ( $spec =~ /^\s*(\d+)\s*-\s*(\d+)\s*$/ )
	{
	    my $first = $1;
	    my $last = $2;
	    
	    if ( !defined $range{$first} or $range{$first} < $last )
	    {
		$range{$first} = $last;
	    }
	}
	
	elsif ( $spec =~ /^\s*(\d+)\s*$/ )
	{
	    my $page = $1;
	    
	    if ( !defined $range{$page} )
	    {
		$range{$page} = $page;
	    }
	}
	
	elsif ( $spec =~ /^\s*(\w.*)/ )
	{
	    my $page = $1;
	    $other{$page} = $page unless exists $other{$page};
	}
    }
    
    my ($first, $last, @pages) = @_;
    
    foreach my $key ( sort { $a <=> $b } keys %range )
    {
	if ( defined $last and $key <= $last + 1 )
	{
	    $last = $key;
	}
	
	elsif ( defined $last )
	{
	    push @pages, $first == $last ? $last : "$first-$last";
	    $first = $key;
	    $last = $range{$key};
	}
	
	else
	{
	    $first = $key;
	    $last = $range{$key};
	}
    }
    
    if ( defined $last )
    {
	push @pages, $first == $last ? $last : "$first-$last";
    }
    
    push @pages, $_ foreach keys %other;
    
    return join(', ', @pages);
}

# This shows the actual references.
sub displayRefResults {
    my ($dbt,$q,$s,$hbo) = @_;
    
    my $type = $q->param('type');
    my $output = '';
    
    # use_primary is true if the user has clicked on the "Current reference" link at
    # the top or bottom of the page.  Basically, don't bother doing a complicated 
    # query if we don't have to.
    my ($data,$query_description,$alternatives) = ([],'','');
    unless ( $q->param('use_primary') )	{
	($data,$query_description,$alternatives) = getReferences($dbt,$q,$s,$hbo);
    } 
    my @data;
    if ( $data )	{
	@data  = @$data;
    }
    
    if ( (scalar(@data) == 1 && $type ne 'add') || $q->param('use_primary') || $q->param('use_last') )	{
	# # Do the action, don't show results...
	
	# # Set the reference_no
	# unless ( $q->param('use_primary') || $q->param('type') =~ /view|edit/ )	{
	# 	$s->setReferenceNo( $data[0]->{'reference_no'});
	# 	Dancer::redirect "/classic/dequeue";
	# 	return;
	# }
	
	# # QUEUE
	# my %queue = $s->dequeue();
	# my $action = $queue{'action'};
	
	# # Get all query params that may have been stuck on the queue
	# # back into the query object:
	# foreach my $key (keys %queue) {
	# 	$q->param($key => $queue{$key});
	# }
	
	# # if there's an action, go straight back to it without showing the ref
	# if ($action)	{
	#     PBDB::execAction($action);
	# } elsif 
	if ($q->param('type') eq 'edit')
	{  
	    $q->param("reference_no"=>$data[0]->{'reference_no'});
	    return PBDB::ReferenceEntry::displayReferenceForm($dbt,$q,$s,$hbo);
	} elsif ($q->param('type') eq 'select') {  
	    return PBDB::menu($q, $s, $dbt, $hbo);
	} else {
	    # otherwise, display a page showing the ref JA 10.6.02
	    return displayReference($dbt,$q,$s,$hbo,$data[0],$alternatives);
	}
    } 
    
    elsif ( scalar(@data) > 0 )
    {
	# Needs to be > 0 for add -- case where its 1 is handled above explicitly
	# Print the sub header
	my $offset = (int($q->param('refsSeen')) || 0);
	my $limit = 30;
	$output .= "<div align=\"center\"><p class=\"pageTitle\" style=\"margin-bottom: 1em;\">$query_description matched ";
	if (scalar(@data) > 1 && scalar(@data) > $limit) {
	    $output .= scalar(@data)." references</p>\n\n";
	    $output .= "<p class=\"medium\">Here are ";
	    if ($offset == 0)	{
		$output .= "the first $limit";
	    } elsif ($offset + $limit > scalar(@data)) {
		$output .= "the remaining ".(scalar(@data)-$offset)." references";
	    } else	{
		$output .= "references ",($offset + 1), " through ".($offset + $limit);
	    }
	    $output .= "</p>\n\n";
	} elsif ( scalar(@data) == 1) {
	    $output .= "exactly one reference</p>";
	} else	{
	    $output .= scalar(@data)." references</p>\n";
	}
	$output .= "</div>\n";
	#        if ($type eq 'add') {
#            $output .= "If the reference is not already in the system press \"Add reference.\"<br><br>";
#        } elsif ($type eq 'edit') {
#            $output .= "Click the reference number to edit the reference<br><br>";
#        } elsif ($type eq 'select') {
#            $output .= "Click the reference number to select the reference<br><br>";
#        } else {
#        }

		# Print the references found
	$output .= "<div style=\"margin: 1.5em; margin-bottom: 1em; padding: 1em; border: 1px solid #E0E0E0;\">\n";
	$output .= "<table border=0 cellpadding=5 cellspacing=0>\n";
	    
	# Only print the last 30 rows that were found JA 26.7.02
	my $dark;
	for (my $i=$offset;$i < $offset + 30 && $i < scalar(@data); $i++)
	{
	    my $row = $data[$i];
	    if ( ($offset - $i) % 2 == 0 )
	    {
		$output .= "<tr class=\"darkList\">";
		$dark++;
	    }
	    else
	    {
		$output .= "<tr>";
		$dark = "";
	    }
	    $output .= "<td valign=\"top\">";
	    if ($s->isDBMember())
	    {
		if ($type eq 'add')
		{
		    $output .= makeAnchor("app/refs", "#display=$row->{reference_no}", $row->{reference_no});
		}
		elsif ($type eq 'edit')
		{
		    $output .= makeAnchor("app/refs", "#display=$row->{reference_no}&type=edit", $row->{reference_no});
		}
		elsif ($type eq 'view')
		{
		    $output .= makeAnchor("app/refs", "#display=$row->{reference_no}", $row->{reference_no}) . "</br>";
		}
		else
		{
		    $output .= makeAnchor("selectReference", "reference_no=$row->{reference_no}", $row->{reference_no}) . "<br>";
		}
	    }
	    else
	    {
		$output .= makeAnchor("app/refs", "#display=$row->{reference_no}", $row->{reference_no});
	    }
	    $output .= "</td>";
	    my $formatted_reference = formatLongRef($row);
	    $output .= "<td>".$formatted_reference;
	    if ( $type eq 'view' && $s->isDBMember() )
	    {
		$output .= " <small>";
		$output .= makeAnchor("selectReference", "reference_no=$row->{reference_no}", "select")
		    . "</small>";
	    }
	    my $reference_summary = getReferenceLinkSummary($dbt,$s,$row->{'reference_no'});
	    $output .= "<br><small>$reference_summary</small></td>";
	    $output .= "</tr>";
	}
	$output .= "</table>\n";
	if ( $alternatives )
	{
	    if ( ! $dark )
	    {
		$output .= "<div style=\"border-top: 1px solid #E0E0E0; margin-top: 0.5em; \"></div>\n";
	    }
	    $output .= "<div class=\"small\" style=\"margin-left: 6em; margin-right: 4em; margin-top: 0.5em; margin-bottom: -0.5em; text-align: left; text-indent: -1em;\">Other possible matches include $alternatives.</div>\n\n";
	}
	$output .= "</div>";
	    
	    
	# Now print links at bottom
	$output .=  "<center><p>";
	if ($offset + 30 < scalar(@data))
	{
	    my %vars = $q->Vars();
	    $vars{'refsSeen'} += 30;
	    my $ref_params = "";
	    foreach my $k (sort keys %vars)
	    {
		$ref_params .= "&$k=$vars{$k}";
	    }
	    $ref_params=~ s/^&//;
	    $output .= makeAnchor("displayRefResults", "$ref_params", "Display the next 30 references");
	} 
	    
	my $authname = $s->get('authorizer');
	$authname =~ s/\. //;
	# printRefsCSV(\@data,$authname);
	# $output .= qq|<a href="/public/references/${authname}_refs.csv">Download all the references</a> -\n|;
	# $output .= makeAnchor("displaySearchRefs", "type=$type", "Change search parameters");
	$output .= "</p></center><br>\n";
	    
	if ($type eq 'add')
	{
	    $output .= "<div align=\"center\">\n";
	    $output .= makeFormPostTag();
	    $output .= "<input type=\"hidden\" name=\"action\" value=\"displayReferenceForm\">\n";
	    foreach my $f ("name","year","reftitle","project_name")
	    {
		$output .= "<input type=\"hidden\" name=\"$f\" value=\"".$q->param($f)."\">\n";
	    }
	    $output .= "<input type=submit value=\"Add reference\"></center>\n";
	    $output .= "</form>\n";
	    $output .= "</div>\n";
	}
	
	return $output;
    }
    else
    {				# 0 Refs found
	if ($q->param('type') eq 'add')
	{
	    $q->param('reference_no'=>'');
	    return PBDB::ReferenceEntry::displayReferenceForm($dbt,$q,$s,$hbo);
	}
	
	my $error = "<p class=\"small\" style=\"margin-left: 8em; margin-right: 8em;\">";
	if ( $query_description )
	{
	    $query_description =~ s/ $//;
	    $error .= "<center>Nothing matches $query_description: ";
	    if ( $alternatives )
	    {
		$alternatives =~ s/ and / or /;
		$error .= " if you didn't mean $alternatives, ";
	    }
	    $error .= "please try again</center></p>\n\n";
	}
	else
	{
	    $error .= "<center>Please enter at least one search term</center></p>\n";
	}
	
	return displaySearchRefs($dbt,$q,$s,$hbo,$error);
    }
}

sub displayReference {
    my ($dbt,$q,$s,$hbo,$ref,$alternatives) = @_;
    my $dbh = $dbt->dbh;

    if (!$ref) {
        $ref = getReference($dbt,$q->numeric_param('reference_no'));
    } 

    if (!$ref) {
        return "<h2>Valid reference not supplied</h2>\n";
    }
    my $reference_no = $ref->{'reference_no'};

    
    # Create the thin line boxes
    my $box = sub { 
        my $html = '<div class="displayPanel" align="left" style="margin: 1em;">'
                 . qq'<span class="displayPanelHeader">$_[0]</span>'
                 . qq'<div class="displayPanelContent">'
                 . qq'<div class="displayPanelText">$_[1]'
                 . '</div></div></div>';
        return $html;
    };
    
    my $shortRef = formatShortRef($ref);
    
    my $output = "<div align=\"center\"><p class=\"pageTitle\">$shortRef</p></div>";
    
    my $citation = formatLongRef($ref);
    if ($s->isDBMember())	{
        $citation .= " <small>";
	$citation .= makeAnchor("displayRefResults", "type=select&reference_no=$ref->{reference_no}", "select") . " - ";
	$citation .= makeAnchor("displayRefResults", "type=edit&reference_no=$ref->{reference_no}", "edit") . "</small>";
    }
    $citation = "<div style=\"text-indent: -0.75em; margin-left: 1em;\">" . $citation . "</div>";
    if ( $alternatives )	{
        $citation .= "<div style=\"margin-top: 0.5em;\">Other possible matches include $alternatives.</div>\n\n";
    }
    $output .= $box->("Full reference",$citation);
    
    # Start Metadata box
    my $html = "<table border=0 cellspacing=0 cellpadding=0\">";
    $html .= "<tr><td class=\"fieldName\">ID number: </td><td>&nbsp;$reference_no</td></tr>";
    if ($ref->{'created'}) {
        $html .= "<tr><td class=\"fieldName\">Created: </td><td>&nbsp;$ref->{'created'}</td></tr>";
    }
    if ($ref->{'modified'}) {
        my $modified = date($ref->{'modified'});
        $html .= "<tr><td class=\"fieldName\">Modified: </td><td>&nbsp;$modified</td></tr>" unless ($modified eq $ref->{'created'});
    }
    if($ref->{'project_name'}) {
        $html .= "<tr><td class=\"fieldName\">Project name: </td><td>&nbsp;$ref->{'project_name'}";
        if ($ref->{'project_ref_no'}) {
            $html .= " $ref->{'project_ref_no'}";
        }
        $html .= "</td></tr>";
    }
    if($ref->{'publication_type'}) {
        $html .= "<tr><td class=\"fieldName\">Publication type: </td><td>&nbsp;$ref->{'publication_type'}</td></tr>";
    }
    if($ref->{'basis'}) {
        $html .= "<tr><td class=\"fieldName\">Taxonomy: </td><td>&nbsp;$ref->{'basis'}</td></tr>";
    }
    if($ref->{'language'}) {
        $html .= "<tr><td class=\"fieldName\">Language: </td><td>&nbsp;$ref->{'language'} </td></tr>";
    }
    if($ref->{'doi'}) {
        $html .= "<tr><td class=\"fieldName\">DOI: </td><td>&nbsp;$ref->{'doi'}</td></tr>";
    }
    if($ref->{'comments'}) {
        $html .= "<tr><td colspan=2><span class=\"fieldName\">Comments: </span> $ref->{'comments'}</td></tr>";
    }
    $html .= "</table>";
    if ($html) {
        $output .= $box->("Metadata",$html);
    }

  
    # Get counts
    my $sql = "SELECT count(*) c FROM authorities WHERE reference_no=$reference_no";
    my $authority_count = ${$dbt->getData($sql)}[0]->{'c'};
    
    # TBD: scales, ecotaph, images, specimens/measurements, occs+reids

    # Handle taxon names box
    if ($authority_count) {
        my $html = "";
        if ($authority_count < 100) {
            my $sql = "SELECT taxon_no,taxon_name FROM authorities WHERE reference_no=$reference_no ORDER BY taxon_name";
            my @results = 
                map { makeAnchor("basicTaxonInfo", "taxon_no=$_->{taxon_no}", $_->{taxon_name}) }
                @{$dbt->getData($sql)};
            $html = join(", ",@results);
        } else {
            $html .= makeATag("displayTaxonomicNamesAndOpinions", "reference_no=$reference_no&display=authorities");
            my $plural = ($authority_count == 1) ? "" : "s";
            $html .= "view taxonomic name$plural";
            $html .= qq|</a> |;
        }
        $output .= $box->(qq'Taxonomic names ($authority_count)',$html);
    }
    
    # Handle opinions box
    $sql = "SELECT count(*) c FROM opinions WHERE reference_no=$reference_no";
    my $opinion_count = ${$dbt->getData($sql)}[0]->{'c'};

    if ($opinion_count) {
        my $html = "";
        if ($opinion_count < 30) {
            my $sql = "SELECT opinion_no FROM opinions WHERE reference_no=$reference_no";
            my @results = 
                map {$_->[1] }
                sort { $a->[0] cmp $b->[0] }
                map { 
                    my $o = PBDB::Opinion->new($dbt,$_->{'opinion_no'}); 
                    my $html = $o->formatAsHTML; 
                    my $name = $html;
                    $name =~ s/^'(<i>)?//; 
                    $name =~ s/(belongs |replaced |invalid subgroup |recombined |synonym | homonym | misspelled).*?$//; 
                    [$name,$html] }
                @{$dbt->getData($sql)};
            $html = join("<br>",@results);
        } else {
            $html .= makeATag("displayTaxonomicNamesAndOpinions", "reference_no=$reference_no&display=opinions");
            if ($opinion_count) {
                my $plural = ($opinion_count == 1) ? "" : "s";
                $html .= "view taxonomic opinion$plural";
            }
            $html .= qq|</a> |;
        }

	my $class_link; 
	$class_link = " - <small>" . makeAnchor("classify", "reference_no=$reference_no", "view classification") . "</small>";
	$output .= $box->(qq'Taxonomic opinions ($opinion_count) $class_link',$html);
    }

	# list taxa with measurements based on this reference JA 4.12.10
	my @taxon_refs = getMeasuredTaxa($dbt,$reference_no);
	if ( @taxon_refs )	{
		my @taxa;
		push @taxa , makeAnchor("basicTaxonInfo", "taxon_no=$_->{'taxon_no'}", $_->{'taxon_name'}) foreach @taxon_refs;
		$output .= $box->("Measurements",join('<br>',@taxa));
	}
    
    # Handle phlogenetic character matrices box
    my @nexus_files = PBDB::Nexusfile::getFileInfo($dbt, undef, { reference_no => $reference_no });
    my @nexus_lines;
    
    if ( @nexus_files )
    {
	my $current_auth = $s->get('authorizer_no');
	
	foreach my $nf (@nexus_files)
	{
	    my $nexusfile_no = $nf->{nexusfile_no};
	    my $filename = $nf->{filename};
	    my $taxon_name = $nf->{taxon_name};
	    my $taxon_no = $nf->{taxon_no};
	    my $verb = $nf->{authorizer_no} == $current_auth ? 'edit' : 'view';
	    
	    next unless $nexusfile_no and $filename;
	    
	    my $line = makeAnchor("${verb}NexusFile", "nexusfile_no=$nexusfile_no", $filename);
	    $line .= " (" . makeAnchor("basicTaxonInfo", "taxon_no=$taxon_no", $taxon_name) . ")"if $taxon_name;
	    push @nexus_lines, $line;
	}
    }
    
    if ( @nexus_lines )
    {
	my $count = scalar(@nexus_files);
	$output .= $box->("Phylogenetic character matrices ($count)", join("<br>\n", @nexus_lines));
    }
    
    # Handle collections box
    my $collection_count;
    $sql = "SELECT count(*) as c FROM collections WHERE reference_no=$reference_no";
    $collection_count = ${$dbt->getData($sql)}[0]->{'c'};
    $sql = "SELECT count(*) as c
	    FROM secondary_refs as sr JOIN collections as c using (collection_no)
	    WHERE sr.reference_no=$reference_no and c.reference_no <> $reference_no";
    $collection_count += ${$dbt->getData($sql)}[0]->{'c'}; 
    if ($collection_count) {
        my $html = "";
        if ($collection_count < 100) {
            # primary ref in first SELECT, secondary refs in second SELECT
            # the '1 is primary' and '0 is_primary' is a cool trick - alias the value 1 or 0 to column is_primary
            # any primary referneces will have a  virtual column called "is_primary" set to 1, and secondaries will not have it.  PS 04/29/2005
            my $sql = "(SELECT collection_no,authorizer_no,collection_name,access_level,research_group,release_date,year(release_date) release_year,DATE_FORMAT(release_date, '%Y%m%d') rd_short, 1 is_primary FROM collections c WHERE reference_no=$reference_no)";
            $sql .= " UNION ";
            $sql .= "(SELECT c.collection_no, c.authorizer_no, c.collection_name, c.access_level, c.research_group, release_date, year(release_date) release_year, DATE_FORMAT(c.release_date,'%Y%m%d') rd_short, 0 is_primary FROM collections c, secondary_refs s WHERE c.collection_no = s.collection_no AND s.reference_no=$reference_no AND c.reference_no <> $reference_no) ORDER BY collection_no";

            my $sth = $dbh->prepare($sql);
            $sth->execute();

            my $p = PBDB::Permissions->new($s,$dbt);
            my $results = [];
            if($sth->rows) {
                my $limit = 100;
                my $ofRows = 0;
                $p->getReadRows($sth,$results,$limit,\$ofRows);
            }
		my $readable = join(',',map { $_->{collection_no} } @$results);
		if ( $readable )	{
			$sql =~ s/WHERE /WHERE c.collection_no NOT IN ($readable) AND /g;
		}
		my @protected = @{$dbt->getData($sql)};
		my (%in_year,$protected_count);
		$in_year{$_->{'release_year'}}++ foreach @protected;
		$protected_count = scalar(@protected);
		my @years = keys %in_year;
		@years = sort { $a <=> $b } @years;
		my $year_list = pop @years;
		if ( $#years > 1 ) 	{
			$year_list = join(', ',@years).", and ".$year_list;
		} elsif ( $#years == 1 )	{
			$year_list = $years[0]." and ".$year_list;
		}

            foreach my $row (@$results) {
                my $style;
                if (! $row->{'is_primary'}) {
                    $style = " class=\"boring\"";
                }
                my $coll_link = makeAnchorWithAttrs("basicCollectionSearch", "collection_no=$row->{collection_no}", $style, $row->{collection_no});
                $html .= $coll_link . ", ";
            }
            $html =~ s/, $//;
		if ( $year_list )	{
			my $number = ( $#protected > 0 ) ? sprintf("%d ",$#protected+1)."collections" : "one collection";
			( $collection_count > $protected_count ) ? $html .= ", and " : "";
			$html .= "$number to be released in $year_list";
		}
        } else {
            my $plural = ($collection_count == 1) ? "" : "s";
            $html .= makeAnchor("displayCollResults", "type=view&wild=N&reference_no=$reference_no", "view collection$plural");
        }
        if ($html) {
            $output .= $box->("Collections (" . makeAnchor("displayCollResults", "type=view&wild=N&reference_no=$reference_no", "$collection_count") . ")", $html);
        }
    }

    return $output;
}

# JA 4.12.10
sub getMeasuredTaxa	{
	my $dbt = shift;
	my $reference_no = shift;

	my $sql = "(SELECT taxon_name,a.taxon_no FROM authorities a,specimens s WHERE s.reference_no=$reference_no AND a.taxon_no=s.taxon_no) UNION (SELECT taxon_name,a.taxon_no FROM authorities a,specimens s, occurrences o LEFT JOIN reidentifications r ON r.occurrence_no=o.occurrence_no WHERE s.reference_no=$reference_no AND a.taxon_no=o.taxon_no AND s.occurrence_no=o.occurrence_no AND r.reid_no IS NULL) UNION (SELECT taxon_name,a.taxon_no FROM authorities a,specimens s,reidentifications r WHERE s.reference_no=$reference_no AND a.taxon_no=r.taxon_no AND s.occurrence_no=r.occurrence_no AND s.occurrence_no>0 AND r.most_recent='YES' GROUP BY a.taxon_no) ORDER BY taxon_name ASC";

	return @{$dbt->getData($sql)};
}

# Shows the search form
# modified by rjp, 3/2004
# JA: Poling completely fucked this up and I restored it from backup 13.4.04
# $Message tells them why they are here
sub displaySearchRefs {
    my ($dbt,$q,$s,$hbo,$message) = @_;
	
	my $type = $q->param("type");
	
	# Prepend the message and the type

	my $vars = {'message'=>$message,'type'=>$type};
	# If we have a default reference_no set, show another button.
	# Don't bother to show if we are in select mode.
	my $reference_no = $s->get("reference_no");
	if ( $reference_no && $type ne "add" ) {
		$vars->{'use_current'} = qq|<input type="submit" name="use_current" value="Use $reference_no">\n|;
	}
	if ( $s->isDBMember() && $type ne "add" )	{
		my $sql = "SELECT reference_no FROM refs WHERE enterer_no=".$s->get('enterer_no')." ORDER BY reference_no DESC LIMIT 1";
		my $last = ${$dbt->getData($sql)}[0]->{reference_no};
		if ( $last != $reference_no )	{
			$vars->{'use_current'} .= qq|<input type="submit" name="use_last" value="Use last entered">\n<input type="hidden" name="last_ref" value="$last">\n|;
		}
	}
	if ( $message && $s->isDBMember() )	{
		for my $f ("name","year","reftitle","project_name")	{
			if ( $q->param($f) )	{
				$vars->{'add'} .= "<input type='hidden' name='$f' value='".$q->param($f)."'>\n";
			}
		} 
		# $vars->{'add'} .= "<input type='submit' name='add' value='Add'>\n";
	}

    return PBDB::Person::makeAuthEntJavascript($dbt) . $hbo->populateHTML("search_refs_form", $vars);
}

# JA 23.2.02
sub getReferenceLinkSummary	{
	my ($dbt,$s,$reference_no) = @_;
	my $dbh = $dbt->dbh;
	my ($sql,@chunks);

	# $DB tests are repeated in case we want to make the lines more
	#  complex or remove certainones

	# Handle Authorities
	my $authority_count;
	$sql = "SELECT count(*) c FROM authorities WHERE reference_no=$reference_no";
	$authority_count = ${$dbt->getData($sql)}[0]->{'c'};

	if ($authority_count) {
		my $plural = ($authority_count == 1) ? "" : "s";
		push @chunks , makeAnchor("displayTaxonomicNamesAndOpinions", "reference_no=$reference_no", "$authority_count taxonomic name$plural");
	}
	
	# Handle Opinions
	my (@opinion_counts,$opinion_total,$has_opinion);
	$sql = "SELECT ref_has_opinion,count(*) c FROM opinions WHERE reference_no=$reference_no GROUP BY ref_has_opinion ORDER BY ref_has_opinion";
	@opinion_counts = @{$dbt->getData($sql)};
	if ( $opinion_counts[0]->{'ref_has_opinion'} eq "YES" )	{
		$has_opinion = $opinion_counts[0]->{'c'};
	} elsif ( $opinion_counts[1]->{'ref_has_opinion'} eq "YES" )	{
		$has_opinion = $opinion_counts[1]->{'c'};
	}
	$opinion_total = $opinion_counts[0]->{'c'} + $opinion_counts[1]->{'c'};

	if ( $opinion_total ) {
		my $plural = ($opinion_total == 1) ? "" : "s";
		push @chunks , makeAnchor("displayTaxonomicNamesAndOpinions", "reference_no=$reference_no&display=opinions", "$opinion_total taxonomic opinion$plural");
		if ( $has_opinion > 0 )	{
 			$chunks[$#chunks] .= " (" . makeAnchor("classify", "reference_no=$reference_no", "show classification") . ")";
		}
	}      

	# list taxa with measurements based on this reference JA 4.12.10
	my @taxon_refs = getMeasuredTaxa($dbt,$reference_no);
	if ( @taxon_refs )	{
		my @taxa;
		push @taxa , makeAnchor("basicTaxonInfo", "taxon_no=$_->{taxon_no}", $_->{'taxon_name'}) foreach @taxon_refs;
		push @chunks , "measurements of ".join(', ',@taxa);
	}

	# Handle Collections
	# make sure displayed collections are readable by this person JA 24.6.02

	# primary ref in first SELECT, secondary refs in second SELECT
	# the '1 is primary' and '0 is_primary' is a cool trick - alias the value 1 or 0 to column is_primary
	# any primary referneces will have a  virtual column called "is_primary" set to 1, and secondaries will not have it.  PS 04/29/2005
	my @colls = ();
	my ($collection_count,$protected_count,%in_year);
	$sql = "(SELECT collection_no,authorizer_no,collection_name,access_level,research_group,release_date,year(release_date) release_year,DATE_FORMAT(release_date, '%Y%m%d') rd_short, 1 is_primary FROM collections c WHERE reference_no=$reference_no)";
	$sql .= " UNION ";
	$sql .= "(SELECT c.collection_no, c.authorizer_no, c.collection_name, c.access_level, c.research_group, release_date, year(release_date) release_year, DATE_FORMAT(c.release_date,'%Y%m%d') rd_short, 0 is_primary FROM collections c, secondary_refs s WHERE c.collection_no = s.collection_no AND s.reference_no=$reference_no AND c.reference_no <> $reference_no) ORDER BY collection_no";

	my $sth = $dbh->prepare($sql);
	$sth->execute();

	my $p = PBDB::Permissions->new($s,$dbt);
	if($sth->rows) {
		my $limit = 999;
		my $ofRows = 0;
		$p->getReadRows($sth,\@colls,$limit,\$ofRows);
	# second hit (which is reasonably fast) gets a count to warn
	#  users that protected collections do exist
		my $readable = join(',',map { $_->{collection_no} } @colls);
		if ( $readable )	{
			$sql =~ s/WHERE /WHERE c.collection_no NOT IN ($readable) AND /g;
		}
		my @protected = @{$dbt->getData($sql)};
		$in_year{$_->{'release_year'}}++ foreach @protected;
		$protected_count = scalar(@protected);
	}
	$collection_count = scalar(@colls);

	if ($collection_count == 0 && $protected_count == 0) {
		push @chunks , "no collections";
	}
	my ($thing1,$thing2,$action);
	if ($collection_count > 0)	{
		$thing1 = ($collection_count == 1) ? "collection" : "collections";
		$action = "basicCollectionSearch";
		my @coll_links;
		foreach my $row (@colls) {
			my $style;
			if (! $row->{'is_primary'}) {
				$style = " class=\"boring\"";
			}
			push @coll_links , makeAnchorWithAttrs($action, "$COLLECTION_NO=$row->{$COLLECTION_NO}", $style, $row->{$COLLECTION_NO});
		}
		$thing1 = ( $protected_count > 0 ) ? "released ".$thing1 : $thing1;
		push @chunks , makeAnchor("displayCollResults", "type=view&wild=N&reference_no=$reference_no", "$collection_count $thing1") . '  ('.join(' ',@coll_links).")";
	}
	if ($protected_count > 0)	{
		$thing2 = ($protected_count == 1) ? "collection" : "collections";
		my @years = keys %in_year;
		@years = sort { $a <=> $b } @years;
		my $year_list = pop @years;
		if ( $#years > 1 ) 	{
			$year_list = join(', ',@years).", and ".$year_list;
		} elsif ( $#years == 1 )	{
			$year_list = $years[0]." and ".$year_list;
		}
		push @chunks , "$protected_count $thing2 to be released in $year_list";
	}

	return join(', ',@chunks);
}



# Greg Ederer function that is our standard method for querying the refs table
# completely messed up by Poling 3.04 and restored by JA 10.4.04
sub getReferences {
    my ($dbt,$q,$s,$hbo) = @_;
    my $dbh = $dbt->dbh;
    my %options = $q->Vars();

    if ($options{'use_current'})	{
        $options{'reference_no'} = $s->get('reference_no');
    }
    if ($options{'use_last'})	{
        $options{'reference_no'} = $options{'last_ref'};
    }
    if ($options{'author'} && ! $options{'name'})	{
        $options{'name'} = $options{'author'};
    }

	# build a string that will tell the user what they asked for
	my $query_description = '';
	# also return alternative searches that will work
	my $alternatives = '';

    my @where = ();
    my $year_relation;
    if ($options{'reference_no'}) {
        push @where, "r.reference_no=".int($options{'reference_no'}) if ($options{'reference_no'});
        $query_description .= " reference ".$options{'reference_no'} 
    } else {
        if ($options{'name'}) {
            $query_description .= " ".$options{'name'};
            if ($options{'name_pattern'} =~ /equals/i)	{
                push @where,"(r.author1last=".$dbh->quote($options{'name'}) . " OR r.author2last=".$dbh->quote($options{'name'}) . " OR r.otherauthors=".$dbh->quote($options{'name'}).')';
            } elsif ($options{'name_pattern'} =~ /begins/i)	{
                push @where,"(r.author1last LIKE ".$dbh->quote($options{'name'}.'%') . " OR r.author2last LIKE ".$dbh->quote($options{'name'}.'%') . " OR r.otherauthors LIKE ".$dbh->quote($options{'name'}.'%').')';
            } elsif ($options{'name_pattern'} =~ /ends/i)	{
                push @where,"(r.author1last LIKE ".$dbh->quote('%'.$options{'name'}) . " OR r.author2last LIKE ".$dbh->quote('%'.$options{'name'}) . " OR r.otherauthors LIKE ".$dbh->quote('%'.$options{'name'}).')';
            } else	{ # includes
                push @where,"(r.author1last LIKE ".$dbh->quote('%'.$options{'name'}.'%') . " OR r.author2last LIKE ".$dbh->quote('%'.$options{'name'}.'%') . " OR r.otherauthors LIKE ".$dbh->quote('%'.$options{'name'}.'%').')';
            }
        }
        if ($options{'year'}) {
            $query_description .= " ".$options{'year'};
            if ($options{'year_relation'} eq "in")	{
                $year_relation = "r.pubyr=".$options{'year'};
            } elsif ($options{'year_relation'} =~ /after/i)	{
                $year_relation = "r.pubyr>".$options{'year'};
            } elsif ($options{'year_relation'} =~ /before/i)	{
                $year_relation = "r.pubyr<".$options{'year'};
            } else	{
                $year_relation = "r.pubyr=".$options{'year'};
            }
        }
	if ( $year_relation )	{
		push @where , $year_relation;
	}
        if ($options{'reftitle'}) {
            $query_description .= " ".$options{'reftitle'};
            push @where, "r.reftitle LIKE ".$dbh->quote('%'.$options{'reftitle'}.'%');
        }
        if ($options{'pubtitle'}) {
            push @where, "r.pubtitle LIKE ".$dbh->quote('%'.$options{'pubtitle'}.'%');
            if ($options{'pubtitle_pattern'} =~ /equals/i)	{
                push @where, "r.pubtitle LIKE ".$dbh->quote($options{'pubtitle'});
            } elsif ($options{'pubtitle_pattern'} =~ /begins/i)	{
                push @where, "r.pubtitle LIKE ".$dbh->quote($options{'pubtitle'}.'%');
            } elsif ($options{'pubtitle_pattern'} =~ /ends/i)	{
                push @where, "r.pubtitle LIKE ".$dbh->quote('%'.$options{'pubtitle'});
            } else	{ # includes
                push @where, "r.pubtitle LIKE ".$dbh->quote('%'.$options{'pubtitle'}.'%');
            }
        }
        if ($options{'project_name'}) {
            push @where, "FIND_IN_SET(".$dbh->quote($options{'project_name'}).",r.project_name)";
            $query_description .= " ".$options{'project_name'};
        }
        if ( $options{'authorizer_reversed'}) {
            push @where, "p1.name LIKE ".$dbh->quote(PBDB::Person::reverseName($options{'authorizer_reversed'}));
            $query_description .= " authorizer ".$options{'authorizer_reversed'};
        }
        if ( $options{'enterer_reversed'}) {
            push @where, "p2.name LIKE ".$dbh->quote(PBDB::Person::reverseName($options{'enterer_reversed'}));
            $query_description .= " enterer ".$options{'enterer_reversed'};
        }
    }

    if (@where) {
        my $tables = "(refs r, person p1, person p2)".
                     " LEFT JOIN person p3 ON p3.person_no=r.modifier_no";
        # This exact order is very important due to work around with inflexible earlier code
        my $from = "p1.name authorizer, p2.name enterer, p3.name modifier, r.reference_no, r.author1init,r.author1last,r.author2init,r.author2last,r.otherauthors,r.editors,r.pubyr,r.reftitle,r.pubtitle,r.publisher,r.pubcity,r.pubvol,r.pubno,r.firstpage,r.lastpage,r.publication_type,r.basis,r.doi,r.comments,r.language,r.created,r.modified";
        my @join_conditions = ("r.authorizer_no=p1.person_no","r.enterer_no=p2.person_no");
        my $sql = "SELECT $from FROM $tables WHERE ".join(" AND ",@join_conditions,@where);
        my $orderBy = " ORDER BY ";
        my $refsortby = $options{'refsortby'};
        my $refsortorder = ($options{'refsortorder'} =~ /desc/i) ? "DESC" : "ASC"; 

        # order by clause is mandatory
        if ($refsortby eq 'year') {
            $orderBy .= "r.pubyr $refsortorder, ";
        } elsif ($refsortby eq 'publication') {
            $orderBy .= "r.pubtitle $refsortorder, ";
        } elsif ($refsortby eq 'authorizer') {
            $orderBy .= "p1.last_name $refsortorder, p1.first_name $refsortorder, ";
        } elsif ($refsortby eq 'enterer') {
            $orderBy .= "p2.last_name $refsortorder, p2.first_name $refsortorder, ";
        } elsif ($refsortby eq 'entry date') {
            $orderBy .= "r.reference_no $refsortorder, ";
        }
        
        if ($refsortby)	{
            $orderBy .= "r.author1last $refsortorder, r.author1init $refsortorder, r.pubyr $refsortorder";
        }

        # only append the ORDER clause if something is in it,
        #  which we know because it doesn't end with "BY "
        if ( $orderBy !~ /BY $/ )	{
            $orderBy =~ s/, $//;
            $sql .= $orderBy;
        }

        dbg("RefQuery SQL".$sql);
        
	if ( $query_description ) { 
		$query_description =~ s/^\s*//;
		$query_description = "'$query_description' "; 
	}
	my @data = @{$dbt->getData($sql)};

	# check for variant spellings using not very bright but effective
	#  off-by-one-or-two check JA 23.9.11
	# only do this for a standard last name (required) plus initials and/or
	#  year search
	if ( $options{'variants'} !~ /no/i && $options{'name'} && ( ! $options{'name_pattern'} || $options{'name_pattern'} =~ /equals/i ) && ! $options{'reference_no'} && ! $options{'reftitle'}&& ! $options{'pubtitle'} && ! $options{'project_name'} && ! $options{'authorizer_reversed'} && ! $options{'enterer_reversed'} )	{
		my ($sql,@variants,$groupby);
		my @letts = split //,$options{'name'};
		for my $i ( 1..length($options{'name'})-2 )	{
			my @wild = @letts;
			$wild[$i] = "%";
			splice @wild , $i+1 , 1;
			push @variants , $dbh->quote(join('',@wild));
		    }
		push @variants, $dbh->quote('NO_VARIANTS') unless @variants;
		$sql = "SELECT reference_no,author1last AS name,pubyr AS year FROM refs r WHERE author1last != ".$dbh->quote($options{'name'})." AND (author1last LIKE ".join(" OR author1last LIKE ",@variants).")";
		$sql .= ( $options{'year'} > 1500 ) ? " AND $year_relation" : "";
		$sql .= " AND length(author1last)-1<=".length($options{'name'})." AND length(author1last)+1>=".length($options{'name'});
		my $sql2 = $sql;
		$sql2 =~ s/author1/author2/g;
		$sql = "SELECT reference_no,name,year,count(*) c FROM (($sql) UNION ($sql2)) AS matches";
		$sql .= " GROUP BY name";
		$sql .= ( $options{'year'} > 1500 ) ? ",year" : "";
		my @likes = @{$dbt->getData($sql)};
		my @links;
		for my $l ( @likes )	{
			if ( $l->{'c'} == 1 )	{
				push @links , makeAnchor("app/refs", "#display=$l->{'reference_no'}", $l->{'name'});
			} else	{
			    my $params = "name=$l->{'name'}";
			    $params .= "&year=$options{'year'}&year_relation=$options{'year_relation'}" if $options{year};
			    $params .= "&variants=no";
			    push @links, makeAnchor("displayRefResults", $params, $l->{'name'});
			}
		}
		if ( @likes )	{
			$links[$#links] = ( $#links > 0 ) ? "and ".$links[$#links] : $links[$#links];
			$alternatives .= ( @links && $#links > 1 ) ? join(', ',@links) : "";
			$alternatives .= ( @links && $#links == 1 ) ? join(' ',@links) : "";
			$alternatives .= ( @links && $#links == 0 ) ? $links[0] : "";
		}
	}
	return (\@data,$query_description,$alternatives);

	} else {
		return ('','');
	}
}

sub getReferencesXML {
    my ($dbt,$q,$s,$hbo) = @_;
    require XML::Generator;

    my ($data,$query_description) = getReferences($dbt,$q,$s,$hbo);
    my @data = @$data;
    my $dataRowsSize = scalar(@data);

    my $g = XML::Generator->new(escape=>'always',conformance=>'strict',empty=>'args',pretty=>2);
    my $output = '';
    
    $output .= "<?xml version=\"1.0\" encoding=\"ISO-8859-1\" standalone=\"yes\"?>\n";
    $output .= "<references total=\"$dataRowsSize\">\n";
    foreach my $row (@data) {
        my $an = PBDB::AuthorNames->new($row);
        my $authors = $an->toString();

        my $pages = $row->{'firstpage'};
        if ($row->{'lastpage'} ne "") {
            $pages .= " - $row->{lastpage}";
        }

        # left out: authorizer/enterer, basis, language, doi, comments, project_name
        $output .= $g->reference(
            $g->reference_no($row->{reference_no}),
            $g->authors($authors),
            $g->year($row->{pubyr}),
            $g->title($row->{reftitle}),
            $g->publication($row->{pubtitle}),
            $g->publication_volume($row->{pubvol}),
            $g->publication_no($row->{pubno}),
            $g->pages($pages),
            $g->publication_type($row->{publication_type})
        );
        $output .= "\n";
    }
    $output .= "</references>";
    
    return $output;
}
   
# JA 17-18.3.09
sub getTitleWordOdds	{
    my ($dbt,$q,$s,$hbo) = @_;
	
    my $dbh = $dbt->dbh;
	my $output = '';
	my @tables= ("refs r");
	my @where = ("(language IN ('English') OR language IS NULL) AND reftitle!='' AND reftitle IS NOT NULL");

	my %isbad;
	$isbad{$_}++ foreach ('about','and','been','for','from','have','its','near','not','off','some','the','their','them','this','those','two','which','with');

	my (%cap,%iscap,%isplural,%notplural,%freq,%allfreq,%infreq,@words,@allwords,$n,$allrefs,$nrefs,@allrefs,%refwords);

	# avoids another table scan
	my $sql = "SELECT reftitle,pubtitle,reference_no FROM ".join(',',@tables)." WHERE ".join(' AND ',@where);
	getWords($sql);
	# okay, so it's a hack
	%allfreq = %freq;
	@allwords = @words;
	my $nallrefs = $n;

	# we're actually using the checkbox names instead of values
	my @params = $q->param;
	my @titles;
	for my $p ( @params )	{
		if ( $p =~ /^title / )	{
			my $t = $p;
			$t =~ s/title //;
			push @titles , $t;
		}
	}

	$output .= "<p class=\"pageTitle\" style=\"margin-left: 16em; margin-bottom: 1.5em;\">Paper title analytical results</p>\n\n";

	# oy vey
	if ( $q->param('title Palaeontologische Zeitschrift') )	{
		$sql = "SELECT distinct(pubtitle) FROM refs WHERE pubtitle LIKE 'pal% zeitschrift'";
		my @pzs = @{$dbt->getData($sql)};
		push @titles , $_->{'pubtitle'} foreach @pzs;
	}

	if ( @titles )	{
		push @where , "pubtitle IN ('".join("','",@titles)."')";
	}
	if ( $q->param('authors') =~ /[A-Za-z]/ )	{
		my $auth = $q->param('authors');
		$auth =~ s/[^A-Za-z ]//g;
		push @where , " (r.author1last IN ('".join("','",split(/ /,$auth))."') OR r.author2last IN ('".join("','",split(/ /,$auth))."'))";
	}
	if ( $q->param('first_year') >= 1700 && ( $q->param('first_year') < $q->param('last_year') || ! $q->param('last_year') ) )		{
		push @where , "r.pubyr>=".$q->numeric_param('first_year');
	}
	if ( $q->param('last_year') >= 1700 && ( $q->param('first_year') < $q->param('last_year') || ! $q->param('first_year') ) )		{
		push @where , "r.pubyr<=".$q->numeric_param('last_year');
	}
	if ( $q->param('keywords') =~ /[A-Za-z]/ )	{
		my @words = split / /,$q->param('keywords');
		$isbad{$_}++ foreach @words;
		my @likes;
		push @likes , "(reftitle REGEXP '[^A-Za-z]".$_."[^A-Za-z]' OR reftitle REGEXP '".$_."[^A-Za-z]' OR reftitle REGEXP '[^A-Za-z]".$_."' OR reftitle REGEXP '[^A-Za-z]".$_."s[^A-Za-z]' OR reftitle REGEXP '".$_."s[^A-Za-z]' OR reftitle REGEXP '[^A-Za-z]".$_."s')" foreach @words;
		push @where , "(".join(' OR ',@likes).")";
	}
	my @periods;
	for my $p ( @params )	{
		if ( $p =~ /^period / )	{
			push @periods , $q->param($p);
			my ($p,$period) = split / /,$p;
			$isbad{$period}++;
		}
	}
	my $group_by;
	if ( @periods )	{
		push @tables , "collections c,interval_lookup i";
		push @where , "r.reference_no=c.reference_no AND c.max_interval_no=i.interval_no AND period_no IN (".join(',',@periods).")";
		$group_by = " GROUP BY r.reference_no";
	}
	my $country_sql;
	for my $continent ( 'Africa','Antarctica','Asia','Australia','Europe','North America','South America' )	{
		if ( $q->param($continent) =~ /y/i )	{
			my $d = PBDB::Download->new($dbt,$q,$s,$hbo);
			$country_sql = $d->getCountryString();
			last;
		}
	}
	if ( $country_sql )	{
		if ( ! @periods )	{
			push @tables , "collections c";
			push @where , "r.reference_no=c.reference_no";
			$group_by = " GROUP BY r.reference_no";
		}
		push @where , $country_sql;
	}
	if ( $q->param('exclude_places') )	{
		$isbad{$_}++ foreach ( 'Africa','Antarctica','Asia','Australia','Europe','North America','South America' );
		$sql = "(SELECT distinct(country) AS place FROM collections WHERE country IS NOT NULL AND country!='') UNION (SELECT distinct(state) AS place FROM collections WHERE state IS NOT NULL AND state!='')";
		my @places = @{$dbt->getData($sql)};
		$isbad{$_->{'place'}}++ foreach @places;
	}
	if ( $q->param('taxon') =~ /^[A-Z][a-z]*$/ )	{
	    my $quoted_taxon = $dbh->quote($q->param('taxon'));
	    $sql = "SELECT lft,rgt FROM authorities a,$TAXA_TREE_CACHE t WHERE a.taxon_no=t.taxon_no AND taxon_name=$quoted_taxon AND t.taxon_no=spelling_no ORDER BY rgt-lft DESC";
		my $span = ${$dbt->getData($sql)}[0];
		push @tables , "opinions o,".$TAXA_TREE_CACHE." t";
		push @where , "r.reference_no=o.reference_no AND child_no=t.taxon_no AND lft>=".$span->{'lft'}." AND rgt<=".$span->{'rgt'};
		$group_by = " GROUP BY r.reference_no";
	}

	$sql = "SELECT reftitle FROM ".join(',',@tables)." WHERE ".join(' AND ',@where);
	getWords($sql);
	# okay, so it's a hack
	%infreq = %freq;
	my $inrefs = $n;

	sub getWords	{
		$sql .= $group_by;
		my @refs = @{$dbt->getData($sql)};
		if ( ! @allwords )	{
			@allrefs = @refs;
		}
		$n = $#refs;
		%freq = ();
		foreach my $r ( @refs )	{
			$r->{'reftitle'} =~ s/\'s//g;
			$r->{'reftitle'} =~ s/[^A-Za-z ]//g;
			my @words = split / /,$r->{'reftitle'};
			foreach my $w ( @words )	{
				if ( length( $w ) > 2 )	{
					if ( $isbad{$w} )	{
						next;
					}
					my $small = $w;
					$small =~ tr/A-Z/a-z/;
					if ( $isbad{$small} )	{
						next;
					}
					$freq{$small}++;
				# only do this the first time
					if ( $w =~ /^[A-Z]/ && ! @allwords && $w ne $words[0] )	{
						$cap{$small} = $w;
						$iscap{$small}++;
					}
					if ( $w =~ /s$/&& ! @allwords )	{
						$isplural{$small}++;
					} else	{
						$notplural{$small}++;
					}
					if ( ! @allwords )	{
						push @{$refwords{$r->{'reference_no'}}} , $small;
					}
				}
			}
		}
		@words = keys %freq;
	}

	# only use words appearing in both sets
	my @temp;
	for my $w ( @allwords )	{
		my $short = $w;
		$short =~ s/s$//;
		unless ( $notplural{$short} )	{
			$isplural{$w} = "";
		}
	}
	for my $w ( @allwords )	{
		if ( $isplural{$w.'s'} )	{
			$allfreq{$w.'s'} += $allfreq{$w};
			$infreq{$w.'s'} += $infreq{$w};
			$iscap{$w.'s'} += $iscap{$w};
			if ( ! $cap{$w.'s'} && $cap{$w} )	{
				$cap{$w.'s'} = $cap{$w} . "s";
			}
			delete $allfreq{$w};
			delete $infreq{$w};
			delete $iscap{$w};
			delete $isplural{$w};
		}
	}
	# get rid of the singular forms
	@allwords = keys %allfreq;
	for my $w ( @allwords )	{
		if ( $infreq{$w} > 0 && $infreq{$w} < $allfreq{$w} )	{
			push @temp , $w;
			if ( $iscap{$w} < $allfreq{$w} / 2 )	{
				delete $iscap{$w};
			}
		}
	}
	@allwords = @temp;

	for my $w ( @allwords )	{
		$allfreq{$w} -= $infreq{$w};
	# Williams' continuity correction, sort of
		if ( $allfreq{$w} > $infreq{$w} )	{
			$allfreq{$w} -= 0.5;
			$infreq{$w} += 0.5;
		} elsif ( $allfreq{$w} < $infreq{$w} )	{
			$allfreq{$w} += 0.5;
			$infreq{$w} -= 0.5;
		}
	}
	$nallrefs -= $inrefs;
	my %buzz;
	for my $w ( @allwords )	{
		$allfreq{$w} /= $nallrefs;
		$infreq{$w} /= $inrefs;
		$buzz{$w} = $infreq{$w} / $allfreq{$w}
	}
	my (%refbuzz,%absrefbuzz,%jbuzz,%injournal);
	for my $r ( @allrefs )	{
		if ( ! $refwords{$r->{'reference_no'}} || $#{$refwords{$r->{'reference_no'}}} == 0 )	{
			next;
		}
		my $nrefwords = 0;
		$r->{'pubtitle'} =~ s/American Museum of Natural History/AMNH/;
		$r->{'pubtitle'} =~ s/Geological Society of London/GSL/;
		$r->{'pubtitle'} =~ s/Palaeogeography, Palaeoclimatology, Palaeoecology/Palaeo3/;
		$r->{'pubtitle'} =~ s/Proceedings of the National Academy of Sciences/PNAS/;
		$r->{'pubtitle'} =~ s/United States Geological Survey/USGS/;
		for my $w ( @{$refwords{$r->{'reference_no'}}} )	{
			if ( $buzz{$w} != 0 && $infreq{$w} * $inrefs >= $q->param('minimum') && $allfreq{$w} * $nallrefs >= $q->param('minimum') )	{
				$refbuzz{$r->{'reference_no'}} += log( $buzz{$w} );
				$absrefbuzz{$r->{'reference_no'}} += abs( log( $buzz{$w} ) );
			}
			$nrefwords++;
		}
		$refbuzz{$r->{'reference_no'}} /= $nrefwords;
		$absrefbuzz{$r->{'reference_no'}} /= $nrefwords;
		$jbuzz{$r->{'pubtitle'}} += $refbuzz{$r->{'reference_no'}};
		$injournal{$r->{'pubtitle'}}++;
	}
	for my $j ( keys %jbuzz )	{
		if ( $injournal{$j} < 100 || ! $j )	{
			delete $jbuzz{$j};
			delete $injournal{$j};
		} else	{
			$jbuzz{$j} /= $injournal{$j};
		}
	}
	my @refnos = keys %refbuzz;
	my @journals = keys %jbuzz;

	if ( ! @refnos )	{
		return "<p style=\"margin-bottom: 3em;\">Not enough papers fall in the categories you selected to compute the odds. Please <a href=\"?page=word_odds_form\">try again</a>.</p>\n";
	}

	$output .= "<div style=\"margin-left: 0em;\">\n\n";
	my $title = "Words giving the best odds";
	my $title2 = "Journals averaging the highest odds";
	my $title3 = "Paper titles averaging the highest odds";
	@allwords = sort { $infreq{$b} / $allfreq{$b} <=> $infreq{$a} / $allfreq{$a} } @allwords;
	@refnos = sort { $refbuzz{$b} <=> $refbuzz{$a} || $#{$refwords{$b}} <=> $#{$refwords{$a}} } @refnos;
	@journals = sort { $jbuzz{$b} <=> $jbuzz{$a} } @journals;
	printWords('best');

	$title = "Words giving the worst odds";
	$title2 = "Journals averaging the lowest odds";
	$title3 = "Papers with titles averaging the lowest odds";
	@allwords = sort { $infreq{$a} / $allfreq{$a} <=> $infreq{$b} / $allfreq{$b} || $allfreq{$b} <=> $allfreq{$a} } @allwords;
	@refnos = sort { $refbuzz{$a} <=> $refbuzz{$b} || $#{$refwords{$b}} <=> $#{$refwords{$a}} } @refnos;
	@journals = sort { $jbuzz{$a} <=> $jbuzz{$b} } @journals;
	printWords('worst');

	$title = "Words mattering the least";
	$title2 = "Hardest-to-tell journals";
	$title3 = "Hardest-to-tell paper titles";
	@allwords = sort { abs(log($infreq{$a} / $allfreq{$a})) <=> abs(log($infreq{$b} / $allfreq{$b})) || $allfreq{$b} <=> $allfreq{$a} } @allwords;
	@refnos = sort { $absrefbuzz{$a} <=> $absrefbuzz{$b} || $#{$refwords{$b}} <=> $#{$refwords{$a}} } @refnos;
	@journals = sort { abs( $jbuzz{$a} ) <=> abs( $jbuzz{$b} ) } @journals;
	printWords('equal');

	sub printWords		{
		my $sort = shift;
		$output .= "<div class=\"displayPanel\" style=\"float: left; clear: left; width: 26em; margin-bottom: 3em; padding-left: 1em; padding-bottom: 1em;\">\n";
		$output .= "<span class=\"displayPanelHeader\">$title</span>\n";
		$output .= "<div class=\"displayPanelContent\">\n";
		my $out = 0;
		my $lastodds = "";
		for my $i ( 0..$#allwords )	{
			# the threshold makes a big difference!
			if ( $infreq{$allwords[$i]} * $inrefs >= $q->param('minimum') && $allfreq{$allwords[$i]} * $nallrefs >= $q->param('minimum') )	{
				my $odds = $buzz{$allwords[$i]};
				if ( $odds >= 1 && $lastodds < 1 && $lastodds && $sort ne "equal" )	{
					last;
				} elsif ( $odds <= 1 && $lastodds > 1 && $lastodds && $sort ne "equal" )	{
					last;
				} elsif ( ( $odds < 0.5 || $odds > 2 ) && $sort eq "equal" )	{
					if ( $out == 0 )	{
						$output .= "<p class=\"small\"><i>No common words have a small effect on publication odds.</i></p>\n\n";
					}
					last;
				} elsif ( $odds > 1 && $out == 0 && $sort eq "worst" )	{
					$output .= "<p class=\"small\"><i>No common words decrease the publication odds.</i></p>\n\n";
					last;
				} elsif ( $out == 0 )	{
					$output .= "<table>\n";
					$output .= "<tr><td>Rank</td>\n";
					$output .= "<td style=\"padding-left: 2em;\">Word</td>\n";
					$output .= "<td><nobr>Odds ratio</nobr></td>\n";
					$output .= "<td>Uses</td></tr>\n";
				}
				$out++;
				$output .= "<tr><td align=\"center\">$out</td>\n";
				my $w = $allwords[$i];
				if ( $iscap{$allwords[$i]} )	{
					$w = $cap{$w};
				}
				if ( $isplural{$w} )	{
					$w =~ s/s$/\(s\)/;
				}
				$output .= "<td style=\"padding-left: 2em;\">$w</td>\n";
				$output .= sprintf "<td align=\"center\">%.2f</td>\n",$odds;
				$output .= sprintf "<td align=\"center\">%.0f</td>\n",$infreq{$allwords[$i]} * $inrefs + $allfreq{$allwords[$i]} * $nallrefs;
				$output .= "</tr>\n";
				if ( $out == 30 )	{
					last;
				}
				$lastodds = $odds;
			}
		}
		$output .= "</table>\n</div>\n</div>\n\n";
		if ( $out > 0 )	{
			$output .= "<div class=\"displayPanel\" style=\"float: left; clear: right; width: 23em; margin-bottom: 3em; padding-left: 1em; padding-bottom: 1em;\">\n";
			$output .= "<span class=\"displayPanelHeader\">$title2</span>\n";
			$output .= "<div class=\"displayPanelContent\">\n";
			$output .= "<table>\n";
			$output .= "<tr><td>Rank</td>\n";
			$output .= "<td>Journal</td>\n";
			$output .= "<td><nobr>Mean odds</nobr></td>\n";
			for my $i ( 0..$out-1 )	{
				if ( ! $journals[$i] )	{
					last;
				}
				$output .= "<tr>\n";
				$output .= sprintf "<td align=\"center\" valign=\"top\">%d</td>\n",$i + 1;
				$output .= "<td class=\"verysmall\" style=\"padding-left: 0.5em; text-indent: -0.5em;\">$journals[$i]</td>\n";
				$output .= sprintf "<td align=\"center\" valign=\"top\">%.2f</td>\n",exp( $jbuzz{$journals[$i]} );
				$output .= "</tr>\n";
			}
			$output .= "</table></div>\n</div>\n\n";

			$output .= "<div class=\"displayPanel\" style=\"float: left; clear: right; width: 50em; margin-bottom: 3em; padding-left: 1em; padding-bottom: 1em;\">\n";
			$output .= "<span class=\"displayPanelHeader\">$title3</span>\n";
			$output .= "<div class=\"displayPanelContent\">\n";
			my @reflist;
			for my $i ( 0..9 )	{
				push @reflist , $refnos[$i];
			}
			$sql = "SELECT reference_no,author1init,author1last,author2init,author2last,otherauthors,reftitle,pubyr,pubtitle,pubvol,firstpage,lastpage FROM refs WHERE reference_no IN (".join(',',@reflist).")";
			my %refdata;
			$refdata{$_->{'reference_no'}} = $_ foreach @{$dbt->getData($sql)};
			for my $i ( 0..9 )	{
				$output .= sprintf "<p class=\"verysmall\" style=\"margin-left: 1em; text-indent: -0.5em; padding-bottom: -1em;\">\n%d&nbsp;&nbsp;",$i + 1;
				$output .= formatLongRef($refdata{$reflist[$i]});
				$output .= sprintf " [average odds based on %d keywords: %.2f]\n",$#{$refwords{$reflist[$i]}} + 1,exp( $refbuzz{$reflist[$i]} );
				$output .= "</p>\n";
			}
			$output .= "</div>\n</div>\n\n";
		}
	}
	$output .= "</div>\n\n";

	$output .= qq|
<div class="verysmall" style="clear: left; margin-left: 3em; margin-right: 5em; padding-bottom: 3em; text-indent: -0.5em;">
The odds ratio compares the percentage of paper titles within the journals or other categories you selected that include a given word to the same percentage for all other papers. If the "best odds" papers did not appear in a journal you selected, then maybe they should have. If only a few words are shown, then only those words are frequent and have the appropriate odds (respectively greater than 1, less than 1, or between 0.5 and 2). <a href=\"?page=word_odds_form\">Try again</a> if you want to procrastinate even more.
</div>
|;
	
	return $output;
}

1;
