

int_selector = { };

function selectInterval ( e )
{
    e.cancelBubble = true;
    
    var ikey = e.originalTarget.id;
    
    if ( ikey && interval_data[ikey] )
    {
	displayIntervalDetails(e, interval_data[ikey]);
    }
    
    else if ( /\+/.test(ikey) )
    {
	var which = int_selector[ikey];
	var keys = ikey.split('+');
	
	if ( which && which >= keys.length - 1 )
	{
	    int_selector[ikey] = 0;
	}
	
	else if ( which )
	{
	    int_selector[ikey] = which + 1;
	}
	
	else
	{
	    int_selector[ikey] = 1;
	    which = 0;
	}
	
	ikey = keys[which];
	
	if ( ikey && interval_data[ikey] )
	{
	    displayIntervalDetails(e, interval_data[ikey]);
	}
    }
    
    else
    {
	closeIntervalDetails(e);
    }
}


refurl = '/classic/displayRefResults?reference_no=';
collurl = '/classic/displayCollResults?type=view&person_type=authorizer&sortby=collection_no&basic=yes&limit=30&uses_interval=';
our_target = 'target="classic2"';

function displayIntervalDetails ( e, data )
{
    var name = data.interval_name || '?';
    var type = data.type || '';
    var scaleno = data.scale_no || 0;
    var intno = data.interval_no || 0;
    var refno = data.reference_no || 0;
    var t_age = data.t_age || '?';
    var b_age = data.b_age || '?';
    
    var details = `<span class="int_heading">${name}</span> ${type}\n`;
    
    details += `<p>${b_age} - ${t_age} Ma</p>\n`;
    
    if ( scaleno == intl_scale )
    {
	details += `<p>This interval is part of the international time scale</p>\n`;
    }
    
    else if ( scaleno == bin_scale )
    {
	details += `<p>This interval is as close as possible to 10 million years.</p>\n`;
    }
    
    else
    {
	var ref_label;
	
	if ( ref_data && ref_data[refno] )
	    ref_label = ref_data[refno];
	
	else
	    ref_label = 'reference ' + refno;
	    
	var ref_anchor = `<a href="${refurl}${refno}" ${our_target}>${ref_label}</a>`;
	
	details += `<p>The definition of this interval is taken from ${ref_anchor}</p>\n`;
    }
    
    if ( data.t_type == 'interpolated' || data.b_type == 'interpolated' )
    {
	var words;
	
	if ( data.t_type == 'interpolated' )
	    words = data.b_type == 'interpolated' ? 'top and bottom boundaries have been' 
		: 'top boundary has been';
	
	else
	    words = 'bottom boundary has been';
	
	details += `<p>The ${words} interpolated</p>`;
    }
    
    if ( data.n_colls )
    {
	var coll_anchor = `<a href="${collurl}${intno}" ${our_target}>${data.n_colls} collections</a>`;
	details += `<p>This interval is used in the definition of ${coll_anchor}</p>\n`;
    }
    
    var intbox = e.originalTarget;
    var detbox = $('#int_details')[0];
    
    detbox.innerHTML = details;
    detbox.style.display = 'block';
    
    var cellrect = intbox.getBoundingClientRect();
    var boxrect = detbox.getBoundingClientRect();
    
    var boxvpos = detbox.offsetTop;
    var newpos = boxvpos + e.y - boxrect.y - 50;
    
    detbox.style.top = '' + newpos + 'px';
    
    if ( e.originalTarget.offsetLeft > boxrect.width )
    {
	var boxhpos = detbox.offsetLeft;
	var newpos = boxhpos + cellrect.x - (boxrect.x + boxrect.width + 25);
	
	detbox.style.left = '' + newpos + 'px';
    }
    
    else
    {
	var boxhpos = detbox.offsetLeft;
	var newpos = boxhpos + (cellrect.x + cellrect.width) - boxrect.x + 25;
	
	detbox.style.left = '' + newpos + 'px';
    }
    
}


function closeIntervalDetails ( e )
{
    $('#int_details').css('display', 'none');
}
