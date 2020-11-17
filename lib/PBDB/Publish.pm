#
# PBDB::Publish.pm
#
# Publish web pages from source material in Google docs and templates stored locally.

package PBDB::Publish;

use strict;

use URL::Encode qw(url_decode);


sub publishPage {
    
    my ($q, $s, $dbt) = @_;
    
    my $dbh = $dbt->{dbh};

    my $page_name = $q->param('page_name');
    my $source_text = $q->param('source_text');
    
    my $source_parsed = parseSource($source_text);
    
    my $new_content = generateOutput($page_name, $source_parsed);
    
    if ( open( my $outfh, '>', "/data/MyApp/pbdb-main/build/pages/${page_name}.html" ) )
    {
	print $outfh $new_content;

	my $sitename = Wing->config->get("sitename");
	my $output = "<h2>Update page '$page_name'</h2>\n";
	$output .= "<h3><a href='http://$sitename/#/$page_name' target='_blank'>view the new page</a></h3>\n";
	return $output;
    }
    
    else
    {
	$output = "<h2>An error occurred</h2>\n";
	return $output;
    }
}


sub parseSource {
    
    my ($source) = @_;
    
    my $page_content = { };
    my $state = 'INIT';
    
    while ( $source =~ m{ <p [^>]* class=" ([^"]+) " [^>]* > (.*?) </p> }xsg )
    {
	my $pclass = $1;
	my $sclass;
	my $html = $2;
	
	if ( $html =~ qr{ ^ <span [^>]* class=" ([^"]+) " [^>]* > (.*?) </span> $ }xs )
	{
	    $sclass = $1;
	    $html = $2;
	}
	
	if ( $sclass eq 'c9' )
	{
	    $page_content->{introduction_html} = $html;
	    next;
	}
	
	elsif ( $sclass eq 'c2' )
	{
	    my $section_header = $html;
	    my $section_anchor;
	    
	    $section_header =~ s/<[^>]+>//g;
	    $section_header =~ s/^\s+//;
	    $section_header =~ s/\s+$//;
	    
	    if ( $section_header =~ qr{ (.*) \s+ \[ (.*) \] $ }xs )
	    {
		$section_header = $1;
		$section_anchor = $2;
	    }

	    if ( $section_header =~ /\w/ )
	    {
		addSection($page_content, $section_header, $section_anchor);
		$state = 'SECTION';
		next;
	    }
	}
	
	elsif ( $state eq 'SECTION' )
	{
	    my $section_content = $html;
	    next unless $section_content =~ /\w/;
	    $section_content =~ s{ </span> .*? <span [^>]* > }{}xsg;
	    $section_content =~ s{ <a [^>]* href=" ([^"]+) " [^>]* > }{ deGooglify($1) }xge;
	    addSectionContent($page_content, $section_content);
	}
    }
    
    return $page_content;
}



sub addSection {

    my ($page_content, $section_header, $section_anchor) = @_;
    
    unless ( $section_anchor )
    {
	$section_anchor = lc $section_header;
	$section_anchor =~ s{\s+}{-}g;
	$section_anchor =~ s{[^\w]+}{-}g;
    }
    
    push @{$page_content->{sections}}, { header_text => $section_header,
					 anchor_name => $section_anchor,
					 content_html => '' };
}


sub addSectionContent {
    
    my ($page_content, $section_content) = @_;

    $page_content->{sections}[-1]{content_html} .= $section_content;
}


sub deGooglify {
    
    my ($href_value) = @_;

    if ( $href_value =~ qr{ ^ https://\w+.google.com .* q= (.*?) &amp; }xs )
    {
	$href_value = url_decode($1);
    }
    
    return "<a href=\"$href_value\">";
}


sub generateOutput {
    
    my ($page_name, $page_content) = @_;
    
    my (%template, %subfield);
    
    $template{PAGE} = <<PAGE_TEMPLATE;
{{INIT}}
{{SECTION}}
{{FOOTER}}
PAGE_TEMPLATE

    $template{INIT} = <<INIT_TEMPLATE;
<div class="row pageHeader"><div class="col-sm-12 pageTitle"><h2>Frequently Asked Questions</h2>
<small>{{introduction_html}}</small><br><br></div>
<div class="row" id="faq-questions">
<div class="col-md-6 col-sm-12">
<ul>{{INIT_TOC_A}}</ul></div>
<div class="col-md-6 col-sm-12">
<ul>{{INIT_TOC_B}}</ul></div></div></div>
<div class="row" id="faqContent"><div class="col-sm-12"><dl>
INIT_TEMPLATE

    $template{INIT_TOC} = <<INIT_TOC_TEMPLATE;
<li><a href="#/faq/{{anchor_name}}" onclick="scrollTo('{{anchor_name}}')">{{header_text}}</a></li>
INIT_TOC_TEMPLATE
    
    $subfield{INIT_TOC} = 'sections';
    
    $template{SECTION} = <<SECTION_TEMPLATE;
<dt id="what-is-the-paleobiology-database">{{header_text}} <a href="#/faq/{{anchor_name}}">
<i class="icon icon-link"></i></a></dt>
<dd>{{content_html}}</dd><br><br>
SECTION_TEMPLATE
    
    $subfield{SECTION} = 'sections';
    
    my $footer_template = <<FOOTER_TEMPLATE;
<div class="faq-logo-holder-holder"><div class="faq-logo-holder"><img src="build/logos/pbdb_color.jpg" class="faq-logo"><div class="type-holder"><a href="build/logos/pbdb_color.ai">AI</a> <a href="build/logos/pbdb_color.svg">SVG</a> <a href="build/logos/pbdb_color.png">PNG</a> <a href="build/logos/pbdb_color.jpg">JPG</a></div></div><div class="faq-logo-holder"><img src="build/logos/pbdb_black.jpg" class="faq-logo"><div class="type-holder"><a href="build/logos/pbdb_black.ai">AI</a> <a href="build/logos/pbdb_black.svg">SVG</a> <a href="build/logos/pbdb_black.png">PNG</a> <a href="build/logos/pbdb_black.jpg">JPG</a></div></div></div></dd><br></dl></div></div>
FOOTER_TEMPLATE
    
    my $page_generator = { template => \%template,
			   subfield => \%subfield };
    
    my $output = evaluateTemplate($page_content, $page_generator, 'PAGE');
}


sub evaluateTemplate {
    
    my ($root_content, $page_generator, $template_name, $subfield_content) = @_;

    my $column;
    
    if ( $template_name =~ /(.*)_([AB])$/ )
    {
	$template_name = $1;
	$column = $2;
    }
    
    my $template_content = $page_generator->{template}{$template_name};
    my $subfield_name = $page_generator->{subfield}{$template_name};
    my $context = $subfield_content || $root_content;
    
    return "Template '$template_name' was not found" unless $template_content;
    
    my $output = '';
    
    if ( $subfield_name )
    {
	if ( ref $context->{$subfield_name} eq 'ARRAY' )
	{
	    my @entry_list = @{$context->{$subfield_name}};
	    my $list_half = int((scalar(@entry_list)+1)/2);

	    if ( $column )
	    {
		if ( $column eq 'A' )
		{
		    splice(@entry_list, $list_half);
		}
		
		else
		{
		    splice(@entry_list, 0, $list_half);
		}
	    }
	    
	    foreach my $entry ( @entry_list )
	    {
		$output .= substituteTemplate($root_content, $page_generator, $template_name, $entry);
	    }
	}

	elsif ( ! $column || $column eq 'A' )
	{
	    $output .= substituteTemplate($root_content, $page_generator, $template_name, $context->{$subfield_name});
	}
    }
    
    else
    {
	$output .= substituteTemplate($root_content, $page_generator, $template_content, $subfield_content);
    }

    return $output;
}


sub substituteTemplate {
    
    my ($root_content, $page_generator, $template_content, $subfield_content) = @_;

    my $output = $template_content;
    
    while ( $output =~ / {{(\w+)}} /xs )
    {
	my $beginning = $-[0];
	my $end = $+[0];
	my $var = $1;
	
	if ( $var =~ /^[A-Z_-]+$/ )
	{
	    substr($output, $beginning, $end-$beginning) =
		evaluateTemplate($root_content, $page_generator, $var, $subfield_content);
	}
	
	elsif ( $subfield_content->{$var} )
	{
	    substr($output, $beginning, $end-$beginning) = $subfield_content->{$var};
	}

	elsif ( $root_content->{$var} )
	{
	    substr($output, $beginning, $end-$beginning) = $root_content->{$var};
	}

	else
	{
	    substr($output, $beginning, $end-$beginning) = "Field '$var' not found.";
	}
    }
    
    return $output;
}


1;
