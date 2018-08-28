
// taxoninfo.js
//
// This file contains functions to enhance the functionality of the checkTaxonInfo page.



function GDDTaxonInfoApp( gdd_url, taxon_name, panel_id, var_name )
{
    "use strict";
    
    // Initialize some private variables.
    
    var useful_dict = { pbdb: 1, ITIS: 1, intervals: 1, stratigraphic_names: 1, lithologies: 1 };
    var panel_status = '';
    var panel_element;
    
    var term_data, terms_loaded;
    var snippet_data, snippets_loaded;

    var button_more_entries = panel_id + "button1";
    
    function initApp ( )
    {
	if ( panel_status ) return;
	
	if ( panel_id )
	{
	    panel_element = document.getElementById(panel_id);

	    if ( ! panel_element )
	    {
		console.log("ERROR: unknown element '" + panel_id + "'");
		return;
	    }
	}

	else
	{
	    console.log("ERROR: no panel id was given");
	    return;
	}
	
	if ( ! gdd_url )
	{
	    console.log("ERROR: no URL was provided");
	    badLoad();
	    return;
	}
	
	panel_status = 'opened';
	panel_element.innerHTML = "<p>Loading...</p>";

	if ( taxon_name )
	{
	    $.getJSON(gdd_url + 'terms?term=' + taxon_name).done(cbTerms);
	    $.getJSON(gdd_url + 'snippets?article_limit=5&term=' + taxon_name).done(cbSnippets);
	}
	
	else
	{
	    badLoad();
	}
    }
    
    this.initApp = initApp;

    
    function cbTerms ( response )
    {
	if ( response.success )
	{
	    var data = response.success.data;
	    
	    if ( data && data.length )
	    {
		for ( i = 0; i < data.length; i++ )
		{
		    if ( data[i].n_docs && data[i].dict_name && data[i].dict_name == "pbdb" )
		    {
			term_data = data[i];
			break;
		    }
		}
	    }
	    
	    terms_loaded = 1;
	    if ( snippets_loaded )
		goodLoad();
	}
	
	else
	{
	    badLoad();
	}
    }
    
    
    function cbSnippets ( response )
    {
	if ( response.success )
	{
	    var data = response.success.data;
	    
	    if ( data )
	    {
		snippet_data = data;
	    }
	    
	    snippets_loaded = 1;
	    if ( terms_loaded )
		goodLoad();
	}
	
	else
	{
	    badLoad();
	}
    }
    
    
    function badLoad ( )
    {
	panel_element.innerHTML = "<p>ERROR loading information from GeoDeepDive</p>";
	panel_status = 'error';
    }
    
    
    function goodLoad ( )
    {
	var content = "<div align=\"center\">\n";
	
	try {
	    
	    if ( term_data )
	    {
		content = generateTermContent();
		
		if ( snippet_data && snippet_data.length )
		    content += generateSnippetContent();
		
		var label = "all";
		
		if ( term_data.n_docs > 500 )
		    label = "first 500";
		
		content += "<p><a id=\"" + button_more_entries + "\" class=\"actionLink\" onclick=\"" + var_name +
		    ".getMoreEntries()\">Show " + label + " entries</a></p>\n";
	    }
	    
	    else
	    {
		content += "</p>No results found for " + taxon_name + "</p>\n";
	    }
	}
	
	catch (e) {
	    
	    content = "<div align=\"center\"><p>ERROR formatting response from GeoDeepDive</p>\n";
	}
	
	content += "</div>\n";
	
	panel_element.innerHTML = content;
    }
    
    
    function generateTermContent ( )
    {
	var content = "<p><a href=\"https://geodeepdive.org/\" target=\"_blank\">" +
	    "GeoDeepDive</a> matched this taxon in " + term_data.n_docs + " documents";
	
	if ( term_data.n_pubs )
	    content += " from " + term_data.n_pubs + " journals/publications";
	
	content += ":</p>\n";
	
	return content;
    }
    
    
    function generateSnippetContent ( )
    {
	var content = "<ul>\n";
	
	for ( var i=0; i < snippet_data.length; i++ )
	{
	    var citation = "";
	    
	    if ( snippet_data[i].authors )
	    {
		citation += snippet_data[i].authors + ". ";
	    }
	    
	    if ( snippet_data[i].title )
	    {
		citation += "<i>" + snippet_data[i].title + "</i>. ";
	    }
	    
	    if ( snippet_data[i].pubname )
	    {
		citation += "<b>" + snippet_data[i].pubname + " ";
		
		if ( snippet_data[i].coverDate )
		    citation += snippet_data[i].coverDate;
		
		citation += "</b>. ";
	    }
	    
	    if ( snippet_data[i].URL )
		content += "<li><a href=\"" + snippet_data[i].URL + "\" target=\"_blank\">" + citation + "</a></li>\n";
	    
	    else
		content += "<li>" + citation + "</li>\n";
	    
	    if ( snippet_data[i].highlight )
	    {
		for ( var j=0; j < snippet_data[i].highlight.length; j++ )
		{
		    content += "<p>..." + snippet_data[i].highlight[j] + "...</p>";
		}
	    }

	    var a_id = panel_id + "termvis" + i;
	    var div_id = panel_id + "terms" + i;
	    
	    content += "<div class=\"actionLink\"><a id=\"" + a_id + "\" onclick=\"" +
		var_name + ".showHideDocTerms(" + i +
		")\">Show recognized terms from this document</a></div><div class=\"extraInfoTable\" id=\"" + div_id +
		"\"></div>\n";
	}
	
	content += "</ul>\n\n";
	
	return content;
    }
    
    
    function getMoreEntries ( )
    {
	var button = document.getElementById(button_more_entries);
	
	button.textContent = "Loading...";
	button.onclick = null;
	
	$.getJSON(gdd_url + 'snippets?article_limit=500&term=' + taxon_name).done(cbMoreEntries);
    }

    this.getMoreEntries = getMoreEntries;
    
    
    function cbMoreEntries ( response )
    {
	if ( response.success )
	{
	    var data = response.success.data;
	    
	    if ( data )
	    {
		snippet_data = data;
	    }
	}
	
	displayMoreEntries();
    }
    
    
    function displayMoreEntries ( )
    {
	var content = "<div align=\"center\">\n";
	
	try {
	    
	    if ( term_data )
	    {
		content = generateTermContent( term_data );
		
		if ( snippet_data && snippet_data.length )
		    content += generateSnippetContent( snippet_data );
		
		else
		    content += "<p>Error loading data from GeoDeepDive</p>\n";
	    }
	    
	    else
	    {
		content += "<p>Error loading data from GeoDeepDive</p>\n";
	    }
	}
	
	catch (e) {
	    
	    content = "<div align=\"center\"><p>ERROR formatting response from GeoDeepDive</p>\n";
	}
	
	content += "</div>\n";
	
	panel_element.innerHTML = content;
    }
    
    
    function showHideDocTerms ( i )
    {
	var div = document.getElementById(panel_id + "terms" + i);
	var button = document.getElementById(panel_id + "termvis" + i);
	
	if ( div )
	{
	    if ( ! div.innerHTML )
	    {
		button.textContent = "Loading...";
		getDocTerms(i);
	    }
	    
	    else if ( div.style.display == "none" )
	    {
		div.style.display = "block";
		button.textContent = "Hide recognized terms from this document";
	    }
	    
	    else
	    {
		div.style.display = "none";
		button.textContent = "Show recognized terms from this document";
	    }
	}
    }

    this.showHideDocTerms = showHideDocTerms;
    
    
    function getDocTerms ( i )
    {
	var docid = snippet_data[i]._gddid
	
	$.getJSON(gdd_url + 'terms?docid=' + docid).done(function (response) {
	    cbDocTerms(response, i);
	});
    }
    
    
    function cbDocTerms ( response, i )
    {
	var div = document.getElementById(panel_id + "terms" + i);
	var button = document.getElementById(panel_id + "termvis" + i);
	var data;
	
	if ( response.success )
	{
	    data = response.success.data;
	}
	
	if ( data && div )
	{
	    displayDocTerms(data, div);
	}
	
	else if ( div )
	{
	    div.innerHTML = "<a>Error loading data from GeoDeepDive</a>";
	}
	
	if ( button )
	    button.textContent = "Hide recognized terms from this document";
    }
    
    
    function displayDocTerms ( data, div )
    {
	var content = "<p><table cellpadding=\"4\" border=\"0\">\n";
	var taxa = [ ];
	var found_taxa = { };
	var strata = [ ];
	var lithologies = [ ];
	var intervals = [ ];
	
	for ( i=0; i < data.length; i++ )
	{
	    if ( data[i].dict_name && useful_dict[data[i].dict_name] )
	    {
		if ( data[i].dict_name == "pbdb" && ! found_taxa[data[i].term] )
		{
		    taxa.push(data[i].term);
		    found_taxa[data[i].term] = 1;
		}
		
		else if ( data[i].dict_name == "lithologies" )
		{
		    lithologies.push(data[i].term);
		}
		
		else if ( data[i].dict_name == "stratigraphic_names" )
		{
		    strata.push(data[i].term);
		}
		
		else if ( data[i].dict_name == "intervals" )
		{
		    intervals.push(data[i].term);
		}
	    }
	}

	if ( taxa.length )
	{
	    content += generateTermRow("Taxonomic names", taxa);
	}
	
	if ( strata.length )
	{
	    content += generateTermRow("Stratigraphic names", strata);
	}
	
	if ( lithologies.length )
	{
	    content += generateTermRow("Lithologies", lithologies);
	}
	
	if ( intervals.length )
	{
	    content += generateTermRow("Intervals", intervals);
	}
	
	content += "</table></p>\n";
	
	div.innerHTML = content;
    }


    function generateTermRow ( label, termlist )
    {
	var content = "<tr valign=\"top\"><td>" + label + "</td><td>\n";
	
	for ( i=0; i < termlist.length; i++ )
	    content += termlist[i] + "<br>\n";
	
	content += "</td></tr>\n";
	
	return content;
    }
}


