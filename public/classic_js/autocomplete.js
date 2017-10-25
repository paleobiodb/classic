//
// autocomplete.js - provides access to the autocompletion facility provided by the PBDB data service.
// 
// Original code by: Valerie Syverson
// Updated by: Michael McClennen
// 
// This javascript file defines the object class AutoCompleteObject by providing a constructor
// function of that name. This is designed to work with a text input element, which we refer to as
// a "search box". The following code should be included inside a <script> tag near the top of
// each page on which such an element appears (with appropriate values for the constructor parameters):
// 
//     var acapp = new AutoCompleteObject("searchbox", "cls", 1);
//     document.addEventListener("DOMContentLoaded", acapp.initialize, false);
// 
// Note that you will need to create and initialize a separate AutoCompleteObject for each search
// box on the page, if there is more than one.
// 
// Each search box and its associated dropdown menu should be declared using something like the following:
// 
//     <input type="text" class="form-control" placeholder="Search the database" id="searchbox"
//			  onkeyup="acapp.do_keyup()">
//     <div class="searchResult dropdown-menu" style="display: none;"></div>
// 
// The input element can have any value for "id", as long as the same value is passed to the
// constructor. The "onkeyup" attribute must refer to an AutoCompleteObject instance that was
// created with that same value as the first parameter to the constructor call. The dropdown menu
// MUST have class "searchResult", as that is how it is identified and referred to in the code below.
// 
// The final thing you will need to do is to add an "onclick" handler to the body tag, either in
// HTML as follows:
// 
//     <body onclick="acapp.showhide_menu(event)">
// 
// or else using a call to addEventListener:
// 
//     document.body.addEventListener("click", function (e) {
//             acapp.showhide_menu(e);
//         });
// 
// Again, you must add a separate call to showhide_menu for each separate instance of
// AutoCompleteObject that you create. These calls can all appear in the same handler function or
// script.
// 

// AutoCompleteObject ( sb_id, req_type, show_links )
// 
// This constructor function returns a new object of this class, which will handle autocompletion
// using an HTML text input element. The first parameter should be the "id" value of this
// element. The second specifies what kind of PBDB entities should be matched against whatever is
// typed into the text input. It may consist of one or more of the following, separated by commas
// without spaces:
// 
//   int	geological time intervals
//   str	names of geological strata
//   prs	names of database contributors
//   txn	taxonomic names
//   col	fossil collections
//   ref	bibliographic references
//   nav	the set of types appropriate for auto-completion in the Navigator web application
//   cls	the set of types appropriate for auto-completion in the Classic web application
// 
// If the third parameter is true, then menu items will be displayed in HTML <a> tags which link
// to the corresponding Classic pages.

function AutoCompleteObject ( sb_id, req_type, show_links )
{
    var search_box_id = sb_id;
    var search_box_selector = '#' + sb_id;
    var include_links = show_links;
    
    var search_box;
    var dropdown_box;
    
    var data_url = window.location.origin;
    var data_service = "/data1.2";
    
    var request_type = '&type=' + req_type;
    
    var stratRankMap = {
	"member": "Mbr",
	"formation": "Fm",
	"group": "Gp"
    };
    
    var data_cache = { };
    
    // The following function must be called once for each object instance, after DOM content is
    // loaded. This is typically done using an event listener on "DOMContentLoaded".
    // 
    // The purpose of this function is to grab object references to the search box and dropdown
    // menu box, and to properly initialize the data service URL.
    
    function initialize ( )
    {
	search_box = document.getElementById(search_box_id);
	dropdown_box = $(search_box_selector).next('.searchResult');
	
	if ( window.location.origin && window.location.origin.match(/localhost/) )
	{
	    data_url = window.location.origin + ":3000";
	}
    }
    
    this.initialize = initialize;
    
    // The following function must be called in response to every keyup event in the search
    // box. It checks the text value, and if that exceeds 3 characters (disregarding initial
    // punctuation) then it makes a call to the data service autocompletion operator. Results are
    // cached to avoid duplicate calls, especially if the user backspaces and then retypes the
    // same thing. 
    
    function do_keyup ()
    {
	var search_value = search_box.value;
	var check_punctuation;
	
	if ( check_punctuation = search_value.match( /[;,](.*)/ ) )
	{
	    search_value = check_punctuation[1];
	}
	
	if (search_value.length < 3)
	{
	    $(dropdown_box).css("display","none");
	    $(dropdown_box).html("");
	    return;
	}
	
	else if ( data_cache[search_value] )
	{
	    display_results(search_value, data_cache[search_value]);
	    return;
	}
	
	var htmlRequest = data_url + data_service + '/combined/auto.json?show=countries&name=' + search_value + request_type;
	$.getJSON(encodeURI(htmlRequest)).then(
	    function(json) { // on success
		display_results(search_value, json);
		data_cache[search_value] = json;
	    }, 
	    function() { // on failure
		var htmlResult = "<div class='autocompleteError'>Error: server did not respond</div>"
		$(dropdown_box).html(htmlResult);
		$(dropdown_box).css("display","block");
	    }
	)
    }
    
    this.do_keyup = do_keyup;
    
    // The following function fills in the dropdown menu box according to the results received
    // from the data service.
    
    function display_results ( search_value, json )
    {
	var htmlResult = "";
	
	if (json.records.length == 0)
	{
	    htmlResult += "<div class='autocompleteError'>No matching results for \"" + search_value + "\"</div>"
	    $(dropdown_box).html(htmlResult);
	    $(dropdown_box).css("display","inline-block");
	    return;
	}
	
	var currentType = "";
	json.records.map( function(d) {
	    var oidsplit = d.oid.split(":");
	    var rtype = oidsplit[0];
	    var oidnum = oidsplit[1];
	    switch (rtype) {
	    case "int":
		if ( currentType != "int" ) { htmlResult += "<h4 class='autocompleteTitle'>Time Intervals</h4>"; currentType = "int"; }
		htmlResult += "<div class='suggestion' data-nam='" + d.nam + "' data-oid='" + oidnum + "'>"
		htmlResult += "<p class='tt-suggestion'>" + d.nam + " <small class=taxaRank>" + Math.round(d.eag) + "-" + Math.round(d.lag) + " ma</small></p></div>\n";
		break;
	    case "str":
		if ( currentType != "str" ) { htmlResult += "<h4 class='autocompleteTitle'>Stratigraphic Units</h4>"; currentType = "str"; }
		htmlResult += "<div class='suggestion' data-nam='" + d.nam + "'>"
		if ( include_links ) { 
		    htmlResult += "<a href=\"/classic/displaySearchStrataResults?group_formation_member=" + encodeURI(d.nam) + "\">"
		}
		htmlResult += "<p class='tt-suggestion'>" + d.nam + " " + stratRankMap[d.rnk] + " <small class=taxaRank>in " + 
		    d.cc2 + "</small></p>"
		if ( include_links ) { htmlResult += "</a>"}
		htmlResult += "</div>\n";
		break;
	    case "txn":
		if ( currentType != "txn" ) { htmlResult += "<h4 class='autocompleteTitle'>Taxa</h4>"; currentType = "txn"; }
		htmlResult += "<div class='suggestion' data-nam='" + d.nam + "' data-typ='" + rtype + "' data-oid='" + 
		    oidnum + "' data-searchstr='" + oidnum + "'>"
		if ( include_links) { htmlResult += "<a href=\"/classic/basicTaxonInfo?taxon_no=" + oidnum + "\">"}
		if (d.tdf) { htmlResult += "<p class='tt-suggestion'>" + d.nam + " <small class=taxaRank>" + d.rnk + 
			     " in " + d.htn + "</small><br><small class=misspelling>" + d.tdf + " " + d.acn + "</small></p>"; }
		else { htmlResult += "<p class='tt-suggestion'>" + d.nam + " <small class=taxaRank>" + d.rnk + " in "
		       + d.htn + "</small></p>"; }
		if ( include_links ) { htmlResult += "</a>"}
		htmlResult += "</div>\n";
		break;
	    case "col":
		var interval = d.oei ? d.oei : "" ;
		if (d.oli) { interval += "-" + d.oli };
		if ( currentType != "col" ) { htmlResult += "<h4 class='autocompleteTitle'>Collections</h4>"; currentType = "col"; }
		htmlResult += "<div class='suggestion' data-nam='" + d.nam + "' data-typ='" + rtype + "' data-oid='" + oidnum + "' data-searchval='" + oidnum + "'>"
		if ( include_links) { htmlResult += "<a href=\"/classic/displayCollResults?collection_no=" + oidnum + "\">"}
		htmlResult += "<p class='tt-suggestion'>" + d.nam + " <br><small class=taxaRank>" + " (" + interval + 
		    " of " + d.cc2 + ")</small></p>";
		if ( include_links ) { htmlResult += "</a>"}
		htmlResult += "</div>\n";
		break;
	    case "ref":
		if ( currentType != "ref" ) { htmlResult += "<h4 class='autocompleteTitle'>References</h4>"; currentType = "ref"; }
		htmlResult += "<div class='suggestion' data-nam='" + d.nam + "' data-typ='" + rtype + "' data-oid='" + 
		    oidnum + "' data-searchval='" + oidnum + "'>"
		if ( include_links) { htmlResult += "<a href=\"/classic/displayRefResults?reference_no=" + oidnum + "\">"}
		htmlResult += "<p class='tt-suggestion'>" + " <small> " + d.nam + "</small></p>";
		if ( include_links ) { htmlResult += "</a>"}
		htmlResult += "</div>\n";
		break;
	    default: //do nothing
	    };
	});
	
	// The following code was written by Valerie, and I'm not sure what it does. We need to
	// talk and figure out how to adapt it to the rewritten code base.
	
	$(dropdown_box).html(htmlResult);
	$(dropdown_box).css("display","inline-block");
	$(".suggestion").on("click", function(event) {
	    // event.preventDefault();
	    switch (thisName) {
	    case "taxonAutocompleteInput": //allow multiple values
		if ($(thisInput).val().indexOf(';') > -1) {
		    var previousTaxa = $(thisInput).val().match(/(.*[;,] )(.*)/)[1];
		    var newval = previousTaxa + $(this).attr('data-nam')
		    $(thisInput).val(newval);
		    $(thisInput).attr('data-oid',$(thisInput).attr('data-oid') + ",txn:" + $(this).attr('data-oid'));
		} else {
		    $(thisInput).val($(this).attr('data-nam'));
		    $(thisInput).attr('data-oid',"txn:" + $(this).attr('data-oid'));
		};
		break;
	    case "timeStartAutocompleteInput":
	    case "timeEndAutocompleteInput":
		$(thisInput).val($(this).attr('data-nam'));
		$(thisInput).attr('data-oid',$(this).attr('data-oid'));
		break;
	    case "universalAutocompleteInput": //this is handled by the previous switch function
	    default: //do nothing
		break;
	    }
	    $(thisInput).next('.searchResult').css("display","none");
	});
	return;
    }
    
    // The following function must be called from a "click" event listener on the document
    // body. If the click was made on the search box, and the contents of the dropdown box are not
    // empty, then the dropdown is displayed. Otherwise, the dropdown is hidden.
    
    function showhide_menu (e)
    {
	if ( typeof(e) == 'object' && e.target == search_box && typeof(dropdown_box) == 'object' )
	{
	   if ( $(dropdown_box).html().length > 0 )
	    {
		$(dropdown_box).css("display","inline-block");
	    }
	}
	
	else
	{
	    $(dropdown_box).css("display","none");
	}
    }
    
    this.showhide_menu = showhide_menu;
}



