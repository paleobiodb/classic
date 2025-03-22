
// The following three functions can be used with hyperlinks to make
// them difficult for crawler bots to traverse. Either of the first
// two should be used in an "onclick" handler, and the third in
// "onmouseover".

function openLink ( action, params ) {
    
    if ( params )
    {
	window.location.assign("/classic/" + action + "?" + params);
    }
    
    else
    {
	window.location.assign("/classic/" + action);
    }
}

function openWindow ( action, params ) {
    
    if ( params )
    {
	window.open("/classic/" + action + "?" + params);
    }
    
    else
    {
	window.open("/classic/" + action);
    }
}

function setHref ( link, action, params ) {
    
    if ( params )
    {
	link.href = "/classic/" + action + "?" + params;
    }
    
    else
    {
	link.href = "/classic/" + action;
    }    
}
