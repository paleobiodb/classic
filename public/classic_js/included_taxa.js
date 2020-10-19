//
// included_taxa.js
//
// The code in this file is used in the taxonomic hierarchy display produced by the
// 'Print a Taxonomic Hierarchy' operation. It enables various parts of the display
// to be expanded and collapsed.


var is_collapsed = { };


function showAll(caller_id)
{
    var alldivs = new Array();
    alldivs = document.getElementsByTagName('div');
    var html;
    var showingBlock = 0;
    
    for ( i = 0; i < alldivs.length; i++ )
    {
	// start showing block
	if ( alldivs[i].id == caller_id )
	{
	    showingBlock = 1;
	}
	
	else if ( /show all/.test( alldivs[i].innerHTML ) )
	{
	    showingBlock = 0;
	}
	
	else if ( showingBlock == 1 )
	{
	    if ( /^hot\d/.test( alldivs[i].id ) && ! /show all/.test( alldivs[i].id.innerHTML ) )
	    {
		alldivs[i].style.display = 'block';
		alldivs[i].innerHTML = 'hide';
	    }
	    
	    else if ( /^t\d/.test( alldivs[i].id ) )
	    {
		alldivs[i].style.display = 'block';
	    }
	}
    }
} 


function showHide(parent_id, op)
{
    var hot_id = parent_id.replace('t', 'hot');
    var hot_elt = document.getElementById(hot_id);
    var new_label;
    var new_display;
    
    if ( op == 'show' || is_collapsed[parent_id] )
    {
	new_label = 'hide';
	new_display = 'block';
    }
    
    else if ( op == 'hide' )
    {
	new_label = '+';
	new_display = 'none';
    }
    
    else if ( hot_elt && hot_elt.innerHTML == '+' )
    {
	new_label = 'hide';
	new_display = 'block';
    }
    
    else
    {
	new_label = '+';
	new_display = 'none';
    }
    
    if ( hot_elt ) hot_elt.innerHTML = new_label;
    else if ( new_label == '+' ) is_collapsed[parent_id] = 1;
    else delete is_collapsed[parent_id];
    
    if ( Array.isArray(box_hierarchy[parent_id]) )
    {
	for ( var i = 0; i < box_hierarchy[parent_id].length; i++ )
	{
	    var child_id = box_hierarchy[parent_id][i];
	    var child_elt = document.getElementById(child_id);
	    if ( child_elt ) child_elt.style.display = new_display;
	}
    }
    
    return true;
}


function collapseChildren(parent_id)
{
    if ( Array.isArray(box_hierarchy[parent_id]) )
    {
	for ( var i = 0; i < box_hierarchy[parent_id].length; i++ )
	{
	    var child_id = box_hierarchy[parent_id][i];
	    var child_elt = document.getElementById(child_id);
	    if ( child_elt ) showHide(child_id, 'hide');
	}
    }
}


