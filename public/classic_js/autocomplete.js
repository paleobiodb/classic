//
// Autocomplete functionality for Classic menu bar. This should be kept in synchrony with the corresponding function on the splash page.
// 


//Autocomplete for search bar and taxon/time pick lists

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
	
	var htmlRequest = data_url + data_service + '/combined/auto.json?show=countries&name=' + search_value + request_type;
	$.getJSON(encodeURI(htmlRequest)).then(
	    function(json) { // on success
		display_results(json)
	    }, 
	    function() { // on failure
		var htmlResult = "<div class='autocompleteError'>Error: server did not respond</div>"
		$(dropdown_box).html(htmlResult);
		$(dropdown_box).css("display","block");
	    }
	)
    }
    
    this.do_keyup = do_keyup;
    
    function display_results ( json )
    {
	var htmlResult = "";
	
	if (json.records.length == 0)
	{
	    htmlResult += "<div class='autocompleteError'>No matching results for \"" + autocompleteInput + "\"</div>"
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
    
    function do_blur ()
    {
	if ($(dropdown_box).html().length > 0) {
	    switch (event.type) {
	    case "focus":
		$(search_box).next('.searchResult').css("display","inline-block");
		break;
	    case "blur":
		$(search_box).next('.searchResult').css("display","none");
		break;
	    };
	}
    }

    this.do_blur = do_blur;
}



