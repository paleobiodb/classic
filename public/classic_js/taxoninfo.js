
// taxoninfo.js
//
// This file contains functions to enhance the functionality of the checkTaxonInfo page.


var dd_base = "https://geodeepdive.org/api/v1/";
var useful_dict = { pbdb: 1, ITIS: 1, intervals: 1, stratigraphic_names: 1, lithologies: 1 };
var TINFO = { panel7status: '', panel7element: undefined };


function getPanelElement ( i )
{
    var id = "panel" + i;
    
    var elt = document.getElementById(id);
    
    if ( elt == undefined )
    {
	console.log("ERROR: unknown element '" + id + "'");
	return undefined;
    }
    
    else return elt;
}


function openLiterature ( )
{
    var panel7 = getPanelElement(7);
    
    if ( panel7 == undefined ) return;
    
    if ( TINFO.panel7status ) return;
    
    TINFO.panel7element = panel7;
    TINFO.panel7status = 'opened';
    
    panel7.innerHTML = "<p>Loading...</p>";

    if ( taxonName !== undefined )
    {
	TINFO.taxonName = taxonName;
	
	$.getJSON(dd_base + 'terms?term=' + taxonName).done(cbTerms);
	$.getJSON(dd_base + 'snippets?article_limit=5&term=' + taxonName).done(cbSnippets);
    }
    
    else
    {
	badLitLoad();
    }
}


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
		    TINFO.termData = data[i];
		    break;
		}
	    }
	}
	
	TINFO.cbTerms = 1;
	if ( TINFO.cbSnippets )
	    goodLitLoad();
    }
    
    else
    {
	badLitLoad();
    }
}


function cbSnippets ( response )
{
    if ( response.success )
    {
	var data = response.success.data;

	if ( data )
	{
	    TINFO.snippetData = data;
	}
	
	TINFO.cbSnippets = 1;
	if ( TINFO.cbTerms )
	    goodLitLoad();
    }
    
    else
    {
	badLitLoad();
    }
}


function badLitLoad ( )
{
    TINFO.panel7element.innerHTML = "<p>ERROR loading information from GeoDeepDive</p>";
    TINFO.panel7status = 'error';
}


function goodLitLoad ( )
{
    var content = "<div align=\"center\">\n";

    try {
	
	if ( TINFO.termData )
	{
	    content = generateTermContent( TINFO.termData );

	    if ( TINFO.snippetData && TINFO.snippetData.length )
		content += generateSnippetContent( TINFO.snippetData );

	    var label = "all";
	    
	    if ( TINFO.termData.n_docs > 500 )
		label = "first 500";
	    
	    content += "<p><a id=\"panel7button1\" onclick=\"getMoreEntries()\">Show " + label + " entries</a></p>\n";
	}
	
	else
	{
	    content += "</p>No results found for " + TINFO.taxonName + "</p>\n";
	}
    }
    
    catch (e) {
	
	content = "<div align=\"center\"><p>ERROR formatting response from GeoDeepDive</p>\n";
    }
    
    content += "</div>\n";
    
    TINFO.panel7element.innerHTML = content;
}


function generateTermContent ( termData )
{
    var content = "<p><a href=\"https://geodeepdive.org/\" target=\"_blank\">" +
	"GeoDeepDive</a> matched this taxon in " + termData.n_docs + " documents";
    
    if ( termData.n_pubs )
	content += " from " + termData.n_pubs + " journals/publications";

    content += ":</p>\n";
    
    return content;
}


function generateSnippetContent ( snippetData )
{
    var content = "<ul>\n";
    
    for ( i=0; i < snippetData.length; i++ )
    {
	var citation = "";

	if ( snippetData[i].authors )
	{
	    citation += snippetData[i].authors + ". ";
	}
	
	if ( snippetData[i].title )
	{
	    citation += "<i>" + snippetData[i].title + "</i>. ";
	}

	if ( snippetData[i].pubname )
	{
	    citation += "<b>" + snippetData[i].pubname + " ";

	    if ( snippetData[i].coverDate )
		citation += snippetData[i].coverDate;

	    citation += "</b>. ";
	}

	if ( snippetData[i].URL )
	    content += "<li><a href=\"" + snippetData[i].URL + "\" target=\"_blank\">" + citation + "</a></li>\n";

	else
	    content += "<li>" + citation + "</li>\n";
	
	if ( snippetData[i].highlight )
	{
	    for ( j=0; j < snippetData[i].highlight.length; j++ )
	    {
		content += "<p>..." + snippetData[i].highlight[j] + "...</p>";
	    }
	}

	content += "<div class=\"TIdocterms\" id=\"panel7terms" + i +
	    "\"><a onclick=\"getDocTerms(" + i + ")\">Show recognized terms</div>\n";
    }
    
    content += "</ul>\n\n";

    return content;
}


function getMoreEntries ( taxonName )
{
    var button = document.getElementById("panel7button1");

    button.textContent = "Loading...";
    button.onclick = null;
    
    $.getJSON(dd_base + 'snippets?article_limit=500&term=' + TINFO.taxonName).done(cbMoreEntries);
}


function cbMoreEntries ( response )
{
    if ( response.success )
    {
	var data = response.success.data;

	if ( data )
	{
	    TINFO.snippetData = data;
	}
    }
    
    displayMoreEntries();
}


function displayMoreEntries ( )
{
    var content = "<div align=\"center\">\n";
    
    try {
	
	if ( TINFO.termData )
	{
	    content = generateTermContent( TINFO.termData );

	    if ( TINFO.snippetData && TINFO.snippetData.length )
		content += generateSnippetContent( TINFO.snippetData );

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
    
    TINFO.panel7element.innerHTML = content;
}


function getDocTerms ( i )
{
    var div = document.getElementById("panel7terms" + i);
    
    div.innerHTML = "<a>Loading...</a>";
    // button.onclick = null;
    
    var docid = TINFO.snippetData[i]._gddid
    
    $.getJSON(dd_base + 'terms?docid=' + docid).done(function (response) {
	cbDocTerms(response, i);
    });
}


function cbDocTerms ( response, i )
{
    var div = document.getElementById("panel7terms" + i);
    var data;
    
    if ( response.success )
    {
	data = response.success.data;
    }
    
    if ( data )
    {
	displayDocTerms(data, div);
    }
    
    else
    {
	div.innerHTML = "<a>Error loading data from GeoDeepDive</a>";
    }
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
