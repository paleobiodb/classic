#
# PBDB::Publish.pm
#
# Publish web pages from source material in Google docs and templates stored locally.

package PBDB::Publish;

use strict;

use URL::Encode qw(url_decode);


sub displayPageEditor {
    
    my ($q, $s, $dbt, $hbo) = @_;

    my $dbh = $dbt->{dbh};
    my $page_name = $q->param('page_name');
    my $sql;
    
    my $name_quoted = $dbh->quote($page_name);
    
    $sql = "SELECT source, templates, name FROM pages
	    WHERE name = $name_quoted";
    
    my ($page_source, $page_templates) = $dbh->selectrow_array($sql);
    
    my $vars = { page_name => $page_name,
		 page_source => $page_source,
		 page_templates => $page_templates };
    
    my $output = $hbo->populateHTML('page_editor', $vars);
    
    return $output;
}


sub publishPage {
    
    my ($q, $s, $dbt) = @_;
    
    my $dbh = $dbt->{dbh};
    
    my $page_name = $q->param('page_name');
    my $page_source = $q->param('page_source');
    my $page_templates = $q->param('page_templates');
    my $test_output = $q->param('test');
    
    my $quoted_name = $dbh->quote($page_name);
    
    my $sql = "SELECT source, templates FROM pages
		WHERE name = $quoted_name";
    
    my ($stored_source, $stored_templates) = $dbh->selectrow_array($sql);
    
    if ( $stored_source ne $page_source )
    {
	my $quoted_source = $dbh->quote($page_source);

	$sql = "UPDATE pages SET source = $quoted_source
		WHERE name = $quoted_name LIMIT 1";

	$dbh->do($sql);
    }
    
    if ( $stored_templates ne $page_templates )
    {
	my $quoted_templates = $dbh->quote($page_templates);
	
	$sql = "UPDATE pages SET templates = $quoted_templates
		WHERE name = $quoted_name LIMIT 1";

	$dbh->do($sql);
    }
    
    my ($content_ref, $template_ref, $generated_content);
    
    eval {
	$content_ref = parseSource($page_source);
	$template_ref = parseTemplates($page_templates);
	$generated_content = generateOutput($page_name, $content_ref, $template_ref);
    };
    
    if ( $@ )
    {
	Dancer::status(500); return "Error: $@\n";
    }
    
    my $file_name = $test_output ? 'test.html' : "$page_name.html";
    
    if ( open( my $outfh, '>', "/data/MyApp/pbdb-main/build/pages/$file_name" ) )
    {
	binmode $outfh, ':utf8';
	print $outfh $generated_content;
	
	if ( close $outfh )
	{
	    return "The page '$page_name' was published to '$file_name'";
	}
    }
	
    Dancer::status(500);
    return "Error publishing '$page_name' to '$file_name': $!";
}


sub parseSource {
    
    my ($source) = @_;
    
    my $content_ref = { sections => [ ] };
    my $state = 'INIT';
    my $line_no = 0;
    my @errors;
    
    my %ws_state = ( INTRO_WS => 'INTRO',
		     SECTION_WS => 'SECTION' );
    
    my @lines = split /\n|\r\n/, $source;
    
  LINE:
    while ( @lines )
    {
	my $line = shift @lines;
	$line_no++;
	
	if ( $ws_state{$state} )
	{
	    if ( $line =~ qr{ ^ \s* $ }xs )
	    {
		next LINE;
	    }

	    else
	    {
		$state = $ws_state{$state};
	    }
	}
	
	if ( $state eq 'INIT' && $line =~ qr{ ^ \s* =head\d (?: \s+ (.*) )? }xsi )
	{
	    my $heading = $1 || 'Frequently Asked Questions';
	    addIntro($content_ref, $heading);
	    $state = 'INTRO_WS';
	    next LINE;
	}
	
	elsif ( $line =~ qr{ ^ \s* =head\d? \s+ (.*) }xsi )
	{
	    my $heading = $1;
	    my $anchor;

	    if ( $heading =~ qr{ ^ (.*?) \s+ \[ (.*) \] $ }xs )
	    {
		$heading = $1;
		$anchor = $2;
	    }
	    
	    addSection($content_ref, $heading, $anchor);
	    $state = 'SECTION_WS';
	    next LINE;
	}
	
	elsif ( $line =~ qr{ ^ \s* (=\w+) }xs )
	{
	    addError($content_ref, $line_no, "unknown command &quot;$1&quot;");
	    next LINE;
	}
	
	elsif ( $state eq 'INIT' || $state eq 'INTRO' )
	{
	    addIntroBody($content_ref, $line);
	    next LINE;
	}
	
	elsif ( $state eq 'SECTION' )
	{
	    addSectionBody($content_ref, $line);
	    next LINE;
	}
	
	else
	{
	    addError($content_ref, $line_no, "bad state &quot;$state&quot;");
	    last LINE;
	}
    }
    
    processContent($content_ref);
    
    return $content_ref;
}


sub addIntro {

    my ($content_ref, $intro_heading) = @_;

    $content_ref->{intro_heading} = $intro_heading;
}


sub addIntroBody {

    my ($content_ref, $intro_html);

    $content_ref->{intro_body} //= '';
    $content_ref->{intro_body} .= "$intro_html\n";
}


sub addSection {

    my ($content_ref, $section_heading, $section_anchor) = @_;
    
    unless ( $section_anchor )
    {
	$section_anchor = lc $section_heading;
	$section_anchor =~ s{\s+}{-}g;
	$section_anchor =~ s{[^\w]+}{-}g;
    }
    
    push @{$content_ref->{sections}}, { section_heading => $section_heading,
					section_anchor => $section_anchor,
					section_body => '' };
}


sub addSectionBody {
    
    my ($content_ref, $section_html) = @_;
    
    $content_ref->{sections}[-1]{section_body} //= '';
    $content_ref->{sections}[-1]{section_body} .= "$section_html\n";
}


sub addError {
    
    my ($structure, $line_no, $message) = @_;

    push @{$structure->{_errors}}, { line_no => $line_no,
				     message => $message };
}


sub processContent {
    
    my ($content_ref) = @_;

    $content_ref->{intro_body} = processBody($content_ref->{intro_body});

    foreach my $section ( @{$content_ref->{sections}} )
    {
	$section->{section_body} = processBody($section->{section_body});
    }
}


sub processBody {
    
    my ($body_html) = @_;
    
    $body_html =~ s/\n+$/\n/xs;
    $body_html =~ s/\n\n/<\/p><p>/gx;
    $body_html = "<p>$body_html</p>\n";
    
    $body_html =~ s{ MAILTO[(] (.*) (?<! \\) [;] \s* (.*) (?<! \\) [)] }{<a href="mailto:$2 ($1)">$2</a>}xg;
    $body_html =~ s{ MAILTO[(] (.*) (?<! \\) [)] }{<a href="mailto:$1">$1</a>}xg;
    
    $body_html =~ s{ LINK[(] (.*) (?<! \\) [;] \s* (.*) (?<! \\) [)] }{<a href="$2">$1</a>}xg;
    $body_html =~ s{ LINK[(] (.*) (?<! \\) [)] }{<a href="$1">$1</a>}xg;
    
    # $body_html =~ s/ MAILTO: ( \w+ [@] [\w.]+[.][\w]+ ) /<a href="mailto:$1">$1<\/a>/xg;
    # $body_html =~ s/ LINK: ( https?:\/\/ \S* (?: \w | \/ ) ) /<a href="$1">$1<\/a>/xg;
    
    return $body_html;
}


sub parseTemplates {

    my ($template_source) = @_;
    
    my $template_ref = { };
    my $state = 'INIT';
    my $line_no = 0;
    
    my @lines = split /\n|\r\n/, $template_source;
    
  LINE:
    while ( @lines )
    {
	my $line = shift @lines;
	$line_no++;
	
	if ( $line =~ qr{ ^ \s* % \s* (template|define) \s+ (\w+) \s* %? }xs )
	{
	    my $tname = $2;
	    
	    $template_ref->{$tname} = { body => [ ], line_no => $line_no };
	    $template_ref->{_current} = $template_ref->{$tname};
	    $state = 'BODY';
	    next LINE;
	}
	
	elsif ( $line =~ qr{ ^ \s* % \s* end \s* %? }xs )
	{
	    $state = 'INIT';
	    next LINE;
	}
	
	elsif ( $line =~ qr{ ^ \s* % \s* (\w+|.) }xs )
	{
	    addError($template_ref, $line_no, "syntax error at &quot;$1&quot;");
	    $state = 'ERROR';
	    next LINE;
	}
	
	elsif ( $state eq 'BODY' )
	{
	    push @{$template_ref->{_current}{body}}, "$line\n";
	    next LINE;
	}
	
	elsif ( $state eq 'INIT' )
	{
	    if ( $line !~ qr{ ^ \s* $ }xs )
	    {
		addError($template_ref, $line_no, "content found outside of template");
	    }

	    $state = 'ERROR';
	    next LINE;
	}
	
	elsif ( $state eq 'ERROR' )
	{
	    # ignore lines in this state until we reach another command or the end of
	    # the data.
	    next LINE;
	}

	else
	{
	    addError($template_ref, $line_no, "bad state &quot;$state&quot;");
	    last LINE;
	}
    }
    
    delete $template_ref->{_current};
    
    return $template_ref;
}


my @CONTEXT;

sub generateOutput {
    
    my ($page_name, $content_ref, $template_ref) = @_;
    
    unshift @CONTEXT, $content_ref;
    
    unless ( ref $template_ref eq 'HASH' )
    {
	$template_ref = { };
    }
    
    $template_ref->{ERRORS} //= { line_no => 0,
				  body => [ "<div id=\"errors\">\n",
					    "[[CONTENT_ERRORS, require=_content_errors]]\n",
					    "[[TEMPLATE_ERRORS, require=_errors]]\n",
					    "</div>\n" ] };
    $template_ref->{CONTENT_ERRORS} //= { line_no => 0,
					  body => [ "<h3>Content errors:</h3><ul>\n",
						    "[[ERROR._content_errors]]\n",
						    "</ul>\n" ] };

    $template_ref->{TEMPLATE_ERRORS} //= { line_no => 0,
					   body => [ "<h3>Template errors:</h3><ul>\n",
						     "[[ERROR._errors]]\n",
						     "</ul>\n" ] };
    
    $template_ref->{ERROR} //= { line_no => 0,
				 body => [ "<li>Line {{line_no}}: {{message}}</li>\n" ] };
    
    my $output = '';
    
    if ( defined $template_ref->{PAGE} )
    {
	$output .= evaluateTemplate($content_ref, $template_ref, 0, 'PAGE');
	$output .= evaluateTemplate($content_ref, $template_ref, 0, 'ERRORS' );
    }
    
    else
    {
	addError($template_ref, 0, "template 'PAGE' not found");
	$output .= evaluateTemplate($content_ref, { }, 0, 'ERRORS');
    }

    return $output;
}



sub evaluateTemplate {
    
    my ($content_ref, $template_ref, $calling_line_no, $calling_expr) = @_;
    
    my ($tname, $trec, $subkey, $argstring, %arg, %vars);
    
    if ( $calling_expr =~ qr{ ^ \s* (\w+) (?: [.] (\w+) )? (?: \s* , \s* (.*) )? \s* $ }xs )
    {
	$tname = $1;
	$subkey = $2;
	$argstring = $3;

      ARGUMENT:
	while ( $argstring )
	{
	    if ( $argstring =~ qr{ ^ (?: \s* , \s* | \s+ $ ) (.*) }xs )
	    {
		$argstring = $1;
		next ARGUMENT;
	    }
	    
	    elsif ( $argstring =~ qr{ ^ slice \s* = \s* (\d+) / (\d+) (.*) }xs )
	    {
		$arg{slice} = $1;
		$arg{slice_count} = $2;
		$argstring = $3;
		next ARGUMENT;
	    }

	    elsif ( $argstring =~ qr{ ^ if (?: \s* = \s* | \s+ ) (\w+) (.*) }xs )
	    {
		$arg{require}{$1} = 1;
		$argstring = $2;
		next ARGUMENT;
	    }
	    
	    elsif ( $argstring =~ qr{ ^ empty_ok (.*) }xs )
	    {
		$arg{empty_ok} = 1;
		$argstring = $1;
		next ARGUMENT;
	    }
	    
	    elsif ( $argstring =~ qr{ ^ [$] (\w+) \s* = \s* 
				      (?| ' ([^']*) ' | " [^"]* " | (\S+) ) (.*) }xs )
	    {
		$vars{$1} = $2;
		$argstring = $3;
		next ARGUMENT;
	    }
	    
	    else
	    {
		my $firstchars = substr($argstring, 0, 10);
		addError($content_ref, $calling_line_no, "syntax error at &quot$firstchars&quot;");
		last ARGUMENT;
	    }
	}
    }

    else
    {
	addError($content_ref, $calling_line_no, "bad template call &quot;$calling_expr&quot;");
	return "bad template call &quot;$calling_expr&quot;";
    }
    
    unless ( $trec = $template_ref->{$tname} )
    {
	addError($content_ref, $calling_line_no, "template &quot;$tname&quot; not found");
	return "template &quot;$tname&quot; not found";
    }
    
    if ( $tname eq 'ERRORS' )
    {
	return '' unless (ref $content_ref->{_errors} eq 'ARRAY' && @{$content_ref->{_errors}} ||
			  ref $template_ref->{_errors} eq 'ARRAY' && @{$template_ref->{_errors}});
	return '' if $template_ref->{_errors_displayed} = 1;
	$template_ref->{_errors_displayed} = 1;
    }
    
    my $output = '';
    my $local_context;
    
    if ( %vars )
    {
	unshift @CONTEXT, \%vars;
	$local_context = 1;
    }

    if ( $arg{require} )
    {
	foreach my $req ( keys %{$arg{require}} )
	{
	    if ( $req eq '_content_errors' )
	    {
		return '' unless ref $content_ref->{_errors} eq 'ARRAY' && @{$content_ref->{_errors}};
	    }

	    else
	    {
		my $req_context = lookupSubkey($req);

		if ( ref $req_context eq 'ARRAY' )
		{
		    return '' unless @$req_context;
		}

		else
		{
		    return '' unless $req_context;
		}
	    }
	}
    }
    
    if ( $subkey )
    {
	my $subcontext = lookupSubkey($subkey);
	my @content_list;
	
	if ( ref $subcontext eq 'ARRAY' )
	{
	    push @content_list, @$subcontext;
	}
	
	elsif ( ref $subcontext eq 'HASH' )
	{
	    push @content_list, $subcontext;
	}
	
	unless ( @content_list || $arg{empty_ok} )
	{
	    addError($content_ref, $calling_line_no, "subcontent &quot;$subkey&quot; not found");
	    return "subcontent &quot;$subkey&quot; not found";
	}
	
	if ( $arg{slice} )
	{
	    my $slice_len = int((scalar(@content_list)+1)/$arg{slice_count});
	    my $slice_start = $slice_len * ($arg{slice} - 1);
	    my $slice_end = $slice_len * $arg{slice};
	    
	    @content_list = @content_list[$slice_start..$slice_end];
	}
	
	foreach my $entry ( @content_list )
	{
	    unshift @CONTEXT, $entry;
	    $output .= substituteTemplate($content_ref, $template_ref, $calling_line_no, $tname);
	    shift @CONTEXT;
	}
	
	if ( $local_context )
	{
	    shift @CONTEXT;
	}
    }
    
    else
    {
	$output .= substituteTemplate($content_ref, $template_ref, $calling_line_no, $tname);
    }
    
    return $output;
}


sub substituteTemplate {
    
    my ($content_ref, $template_ref, $calling_line_no, $tname) = @_;
    
    my @template_lines = @{$template_ref->{$tname}{body}};
    my $line_no = $template_ref->{$tname}{line_no};
    
    my $output = '';
    
    foreach my $line ( @template_lines )
    {
	$line_no++;
	
	while ( $line =~ qr{ \[\[ (.*?) \]\] }xs )
	{
	    my $beginning = $-[0];
	    my $end = $+[0];
	    my $expr = $1;
	    
	    print STDERR "Template: $expr\n";
	    
	    substr($line, $beginning, $end-$beginning) =
		evaluateTemplate($content_ref, $template_ref, $line_no, $expr);
	}
	
	while ( $line =~ qr{ \{\{ (.*?) \}\} }xs )
	{
	    my $beginning = $-[0];
	    my $end = $+[0];
	    my $expr = $1;
	    
	    print STDERR "Variable: $expr\n";
	    
	    my $default = '';
	    
	    if ( $expr =~ qr{ ^ (.*?) [|] (.*) }xs )
	    {
		$expr = $1;
		$default = $2;
	    }

	    my $value = lookupSubkey($expr) // $default;
	    
	    substr($line, $beginning, $end-$beginning) = $value;
	}

	$output .= $line;
    }
    
    return $output;
}


sub lookupSubkey {

    my ($key) = @_;
    
    foreach my $c ( @CONTEXT )
    {
	return $c->{$key} if exists $c->{$key};
    }

    return;
}


# sub oldGenerateOutput {
    
#     my (%template, %subfield);
    
#     $template{PAGE} = <<PAGE_TEMPLATE;
# {{HEADER}}
# {{SECTION}}
# {{FOOTER}}
# PAGE_TEMPLATE

#     $template{HEADER} = <<INIT_TEMPLATE;
# <div class="row pageHeader"><div class="col-sm-12 pageTitle"><h2>Frequently Asked Questions</h2>
# <small>{{introduction_html}}</small><br><br></div>
# <div class="row" id="faq-questions">
# <div class="col-md-6 col-sm-12">
# <ul>{{INIT_TOC_A}}</ul></div>
# <div class="col-md-6 col-sm-12">
# <ul>{{INIT_TOC_B}}</ul></div></div></div>
# <div class="row" id="faqContent"><div class="col-sm-12"><dl>
# INIT_TEMPLATE

#     $template{INIT_TOC} = <<INIT_TOC_TEMPLATE;
# <li><a href="#/faq/{{anchor_name}}" onclick="scrollTo('{{anchor_name}}')">{{header_text}}</a></li>
# INIT_TOC_TEMPLATE
    
#     $subfield{INIT_TOC} = 'sections';
    
#     $template{SECTION} = <<SECTION_TEMPLATE;
# <dt id="what-is-the-paleobiology-database">{{header_text}} <a href="#/faq/{{anchor_name}}">
# <i class="icon icon-link"></i></a></dt>
# <dd>{{content_html}}</dd><br><br>
# SECTION_TEMPLATE
    
#     $subfield{SECTION} = 'sections';
    
#     my $footer_template = <<FOOTER_TEMPLATE;
# <div class="faq-logo-holder-holder"><div class="faq-logo-holder"><img src="build/logos/pbdb_color.jpg" class="faq-logo"><div class="type-holder"><a href="build/logos/pbdb_color.ai">AI</a> <a href="build/logos/pbdb_color.svg">SVG</a> <a href="build/logos/pbdb_color.png">PNG</a> <a href="build/logos/pbdb_color.jpg">JPG</a></div></div><div class="faq-logo-holder"><img src="build/logos/pbdb_black.jpg" class="faq-logo"><div class="type-holder"><a href="build/logos/pbdb_black.ai">AI</a> <a href="build/logos/pbdb_black.svg">SVG</a> <a href="build/logos/pbdb_black.png">PNG</a> <a href="build/logos/pbdb_black.jpg">JPG</a></div></div></div></dd><br></dl></div></div>
# FOOTER_TEMPLATE
    
#     my $page_generator = { template => \%template,
# 			   subfield => \%subfield };
    
#     my $output = evaluateTemplate($page_content, $page_generator, 'PAGE');
# }


# sub deGooglify {
    
#     my ($href_value) = @_;

#     if ( $href_value =~ qr{ ^ https://\w+.google.com .* q= (.*?) &amp; }xs )
#     {
# 	$href_value = url_decode($1);
#     }
    
#     return "<a href=\"$href_value\">";
# }


1;
