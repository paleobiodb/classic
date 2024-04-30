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
//     document.addEventListener("DOMContentLoaded", acapp.initialize.bind(acapp), false);
// 
// Note that you will need to create and initialize a separate AutoCompleteObject for each search
// box on the page, if there is more than one.
// 
// Each search box and its associated dropdown menu should be declared using something like the following:
// 
//   <form onsubmit="return acapp.do_submit(this)">
//     <input type="text" class="form-control" placeholder="Search the database" id="searchbox"
//			  onkeyup="acapp.do_keyup()">
//     <div class="searchResult dropdown-menu" style="display: none;"></div>
//   </form>
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
// If the third parameter is the string "classic", then menu items will be displayed in HTML <a> tags which link
// to the corresponding Classic pages. If it is a function, then it is set as a "click" handler on the dropdown menu items.

function AutoCompleteObject ( search_box_id, req_type, link_handler )
{
    var self = this;
    var search_box_selector = '#' + search_box_id;
    
    var data_url = window.location.origin;
    var data_service = "/data1.2";
    
    var request_type = '&type=' + req_type;
    
    var link_classic;
    var link_function;
    
    var stratRankMap = {
	"member": "Mbr",
	"formation": "Fm",
	"group": "Gp"
    };
    
    var data_cache = { };
    
    var quick_link;
    
    // Check parameters
    
    if ( ! search_box_id )
    {
	throw "You must specify the 'id' attribute value of the search box as the first parameter.";
    }
    
    if ( ! req_type )
    {
	throw "You must specify the 'type' argument to pass to the data service autocomplete operation as the first parameter.";
    }
    
    if ( link_handler )
    {
	if ( typeof(link_handler) == "function" )
	{
	    link_function = link_handler;
	}
	
	else if ( link_handler == "classic" )
	{
	    link_classic = 1;
	}
	
	else
	{
	    throw "Invalid link handler '" + link_handler + "'";
	}
    }
    
    // The following function must be called once for each object instance, after DOM content is
    // loaded. This is typically done using an event listener on "DOMContentLoaded".
    // 
    // The purpose of this function is to grab object references to the search box and dropdown
    // menu box, and to properly initialize the data service URL.
    
    this.initialize = function initialize ( )
    {
	self.search_box = document.getElementById(search_box_id);
	self.dropdown_box = $(search_box_selector).next('.searchResult');
	
	if ( ! self.search_box )
	{
	    throw "Cannot find HTML element with id '" + search_box_id + "'";
	}
	
	if ( ! self.dropdown_box )
	{
	    throw "Cannot find HTML element with class 'searchResult'";
	}
    }
    
    // The following function must be called in response to every keyup event in the search
    // box. It checks the text value, and if that exceeds 3 characters (disregarding initial
    // punctuation) then it makes a call to the data service autocompletion operator. Results are
    // cached to avoid duplicate calls, especially if the user backspaces and then retypes the
    // same thing. 
    
    this.do_keyup = function do_keyup ()
    {
	var search_value = self.search_box.value;
	var dropdown_box = self.dropdown_box;
	var check_punctuation;
	
	// Check for punctuation
	
	if ( check_punctuation = search_value.match( /[;,]+(.*)/ ) )
	{
	    search_value = check_punctuation[1];
	}
	
	// If there are fewer than 3 characters in the search box, hide the menu and otherwise do nothing.
	
	if (search_value.length < 3)
	{
	    $(dropdown_box).css("display","none");
	    $(dropdown_box).html("");
	    quick_link = undefined;
	    return;
	}
	
	// If there is already a cached autocomplete result corresponding to the search box
	// contents, just display that.
	
	else if ( data_cache[search_value] )
	{
	    display_results(dropdown_box, search_value, data_cache[search_value]);
	    return;
	}
	
	// Otherwise, we need to make a data service call.
	
	var htmlRequest = data_url + data_service + '/combined/auto.json?show=countries&name=' + search_value + request_type;
	$.getJSON(encodeURI(htmlRequest)).then(
	    function(json) { // on success
		display_results(dropdown_box, search_value, json);
		data_cache[search_value] = json;
	    }, 
	    function() { // on failure
		var htmlResult = "<div class='autocompleteError'>Error: server did not respond</div>"
		$(dropdown_box).html(htmlResult);
		$(dropdown_box).css("display","block");
		quick_link = undefined;
	    }
	)
    }
    
    // The following function fills in the dropdown menu box according to the results received
    // from the data service.
    
    function display_results ( dropdown_box, search_value, json )
    {
	var htmlResult = "";
	
	if (json.records.length == 0)
	{
	    htmlResult += "<div class='autocompleteError'>No matching results for \"" + search_value + "\"</div>"
	    $(dropdown_box).html(htmlResult);
	    $(dropdown_box).css("display","inline-block");
	    quick_link = undefined;
	    return;
	}
	
	var search_compare = search_value.toLowerCase();
	var currentType = "";
	var itemLink;
	var oneLink;
	var linkCount = 0;
	
	json.records.map( function(d) {
	    var oidsplit = d.oid.split(":");
	    var rtype = oidsplit[0];
	    var oidnum = oidsplit[1];
	    switch (rtype) {
	    case "int":
		if ( currentType != "int" ) { htmlResult += "<h4 class='autocompleteTitle'>Time Intervals</h4>"; currentType = "int"; }
		htmlResult += "<div class='suggestion' data-nam='" + d.nam + "' data-oid='" + d.oid + "' data-rtype='int'>";
		if ( link_classic ) {
		    linkCount++;
		    itemLink = '/classic/displayTimescale?interval=' + encodeURI(d.nam);
		    htmlResult += '<a href="' + itemLink + '">';
		}
		htmlResult += "<p class='tt-suggestion'>" + d.nam + " <small class=taxaRank>" + Math.round(d.eag) + "-" + Math.round(d.lag) + " ma</small></p>";
		if ( link_classic ) htmlResult += "</a>";
		htmlResult += "</div>\n";
		break;
	    case "str":
		if ( currentType != "str" ) { htmlResult += "<h4 class='autocompleteTitle'>Stratigraphic Units</h4>"; currentType = "str"; }
		htmlResult += "<div class='suggestion' data-nam='" + d.nam + "' data-rtype='str'>";
		if ( link_classic ) { 
		    linkCount++;
		    itemLink = '/classic/displaySearchStrataResults?group_formation_member=' + encodeURI(d.nam);
		    htmlResult += '<a href="' + itemLink + '">';
		}
		htmlResult += "<p class='tt-suggestion'>" + d.nam + " " + stratRankMap[d.rnk] + " <small class=taxaRank>in " + 
		    d.cc2 + "</small></p>"
		if ( link_classic ) htmlResult += "</a>";
		htmlResult += "</div>\n";
		break;
	    case "txn":
		if ( currentType != "txn" ) { htmlResult += "<h4 class='autocompleteTitle'>Taxa</h4>"; currentType = "txn"; }
		htmlResult += "<div class='suggestion' data-nam='" + d.nam + "' data-oid='" + 
		    d.oid + "' data-searchstr='" + d.oid + "' data-rtype='txn'>"
		if ( link_classic) {
		    linkCount++;
		    itemLink = '/classic/basicTaxonInfo?taxon_no=' + d.oid;
		    htmlResult += '<a href="' + itemLink + '">';
		}
		if (d.tdf) { htmlResult += "<p class='tt-suggestion'>" + d.nam + " <small class=taxaRank>" + d.rnk + 
			     " in " + d.htn + "</small><br><small class=misspelling>" + d.tdf + " " + d.acn + "</small></p>"; }
		else { htmlResult += "<p class='tt-suggestion'>" + d.nam + " <small class=taxaRank>" + d.rnk + " in "
		       + d.htn + "</small></p>"; }
		if ( link_classic ) htmlResult += "</a>";
		htmlResult += "</div>\n";
		break;
	    case "col":
		var interval = d.oei ? d.oei : "" ;
		if (d.oli) { interval += "-" + d.oli };
		if ( currentType != "col" ) { htmlResult += "<h4 class='autocompleteTitle'>Collections</h4>"; currentType = "col"; }
		htmlResult += "<div class='suggestion' data-nam='" + d.nam + "' data-oid='" + d.oid + "' data-searchval='" + d.oid + "' data-rtype='col'>"
		if ( link_classic) {
		    linkCount++;
		    itemLink = '/classic/displayCollResults?collection_no=' + d.oid;
		    htmlResult += '<a href="' + itemLink + '">';
		}
		htmlResult += "<p class='tt-suggestion'>" + d.nam + " <br><small class=taxaRank>" + " (" + interval + 
		    " of " + d.cc2 + ")</small></p>";
		if ( link_classic ) htmlResult += "</a>";
		htmlResult += "</div>\n";
		break;
	    case "ref":
		if ( currentType != "ref" ) { htmlResult += "<h4 class='autocompleteTitle'>References</h4>"; currentType = "ref"; }
		htmlResult += "<div class='suggestion' data-nam='" + d.nam + "' data-rtype='" + rtype + "' data-oid='" + 
		    d.oid + "' data-searchval='" + d.oid + "'>"
		if ( link_classic) {
		    linkCount++;
		    itemLink = '/classic/displayRefResults?reference_no=' + d.oid;
		    htmlResult += '<a href="' + itemLink + '">';
		}
		htmlResult += "<p class='tt-suggestion'>" + " <small> " + d.nam + "</small></p>";
		if ( link_classic ) htmlResult += "</a>";
		htmlResult += "</div>\n";
		break;
	    default: //do nothing
	    };
	    
	    if ( d.nam && d.nam.toLowerCase() == search_compare )
	    {
		oneLink = itemLink;
	    }
	});
	
	// If we are displaying exactly one link, save that in 'quick_link' so that we can select it when the return key is hit.
	
	if ( linkCount == 1 )
	{
	    quick_link = itemLink;
	}
	
	else if ( oneLink )
	{
	    quick_link = oneLink;
	}
	
	else
	{
	    quick_link = undefined;
	}
	
	// Set the contents of the dropdown box to be the HTML we have just computed, and display it.
	
	$(dropdown_box).html(htmlResult);
	$(dropdown_box).css("display","inline-block");
	
	// If we were given a function to handle clicking on a menu item, assign it as the event handler now.
	
	if ( link_function )
	{
	    $(".suggestion").on("click", link_function);
	}
	
	return;
    }
    
    // The following function must be called in response to a "submit" event on the form that the
    // search box is contained in. The argument must be the form object itself. If there is a
    // single link displayed on the menu, or if one of the menu links exactly matches what is
    // typed in the search box, then that link is followed.
    
    this.do_submit = function do_submit ( this_form )
    {
	if ( quick_link && this_form )
	{
	    window.location.href = quick_link;
	    return false;
	}
	
	else
	{
	    return false;
	}
    }
    
    
    // The following function must be called from a "click" event listener on the document
    // body. If the click was made on the search box, and the contents of the dropdown box are not
    // empty, then the dropdown is displayed. Otherwise, the dropdown is hidden.
    
    this.showhide_menu = function showhide_menu (e)
    {
	if ( typeof(e) == 'object' && e.target == self.search_box && typeof(self.dropdown_box) == 'object' )
	{
	   if ( $(self.dropdown_box).html().length > 0 )
	    {
		$(self.dropdown_box).css("display","inline-block");
	    }
	}
	
	else
	{
	    $(self.dropdown_box).css("display","none");
	}
    }
}



