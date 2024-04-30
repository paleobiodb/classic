//
// TimescaleDisplayApp - a web application for displaying timescales from The Paleobiology Database.
// 
// Written by M. McClennen, March 2024
//


// This app depends on the following variables, which should be set by the
// script which embeds it:
// 
// interval_data	  Maps interval cell identifiers to interval data records
// 
// interval_bounds	  Lists the ages of interval bounds
// 
// intl_scale		  The identifier of the international timescale
//
// bin_scale		  The identifier of the ten million year bin timescale
// 
// reference_data	  Maps reference_no values to short-form formatted bib refs
// 
// display_interval_url	  URL for displaying a specified interval
// 
// display_ref_url	  URL for displaying a specified bibliographic reference
// 
// display_colls_def      URL for listing collections whose definition includes a
//                        specified interval.
// 
// display_colls_cont     URL for listing collections contained within a specified
//                        interval.

function TimescaleDisplayApp ( )
{
    let int_selector = { };
    
    function selectInterval ( e )
    {
	// This function is called when the user clicks on an interval cell. The
	// result is to show the interval details in a pop-up pane. This function
	// depends on the variable 'interval_data', which should be set by the
	// script which embeds this app. The value of interval_data must be an
	// object whose keys are the identifiers of the table cells. The values
	// should be objects which contain the parameters of the corresponding
	// intervals. If the identifier of the cell which is clicked on is
	// composed of multiple keys joined by '+', then cycle among the keys
	// with each new click, showing the corresponding interval details for
	// each key in turn.
	
	e.cancelBubble = true;
	
	var ikey = e.target.id;
	
	// If the identifier of the cell clicked on is a single key, show the
	// pop-up box with the corresponding details.
	
	if ( ikey && interval_data[ikey] )
	{
	    displayIntervalDetails(e, interval_data[ikey]);
	}
	
	// If the identifier is composed of multiple keys joined by '+', cycle
	// among them. The variable 'int_selector' specifies which of the keys
	// should be selected on the next click, with empty meaning 0.
	
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
	
	// If the user clicks on an element that is not an interval cell, close
	// the interval details pane.
	
	else
	{
	    // closeIntervalDetails(e);
	}
    }
    
    this.selectInterval = selectInterval;
    
    
    function closeIntervalDetails ( )
    {
	// Close the interval details pane.
	
	$('#int_details').css('display', 'none');
    }
    
    this.closeIntervalDetails = closeIntervalDetails;
    
    
    // The following URLs allow users to display other PBDB information by
    // following links in the interval details pane.
    
    const our_target = 'target="_blank"';

    function displayIntervalDetails ( e, data )
    {
	// Show the interval details pane, with content derived from the
	// specified interval data record.
	
	let name = data.interval_name || '?';
	let type = data.type || '';
	let scaleno = data.scale_no || 0;
	let intno = data.interval_no || 0;
	let refno = data.reference_no || 0;
	let t_age = data.t_age || '?';
	let b_age = data.b_age || '?';
	
	let details = `<span class="int_heading">${name}</span> ${type}\n`;
	
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
	    let ref_label;
	    
	    if ( reference_data && reference_data[refno] )
		ref_label = reference_data[refno];
	    
	    else
		ref_label = 'reference ' + refno;
	    
	    var ref_anchor = `<a href="${display_ref_url}${refno}" ${our_target}>${ref_label}</a>`;
	    
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
	    let coll_anchor = `<a href="${display_colls_def}${name}" ${our_target}>` +
		`${data.n_colls} collections</a>`;
	    details += `<p>This interval is used in the definition of ${coll_anchor}</p>\n`;
	}
	
	if ( data.nmc )
	{
	    let coll_anchor = `<a href="${display_colls_cont}${name}" ${our_target}>` +
		`${data.nmc} collections</a>`;
	    details += `<p>A total of ${coll_anchor} with ${data.nmo} occurrences lie within this time span</p>\n`;
	}
	
	details += `<p><a href="${display_interval_url}${name}">Select this interval</a></p>\n`;
	
	// Make the details box visible, and place it next to the table cell the user clicked on.
	
	var intbox = e.target;
	var detbox = $('#int_details')[0];
	
	detbox.innerHTML = details;
	detbox.style.display = 'block';
	
	// Compare the bounding box of the interval cell and the details pane.
	
	var cellrect = intbox.getBoundingClientRect();
	var boxrect = detbox.getBoundingClientRect();
	
	// Place the details pane 50 pixels up from where the user clicked.
	
	var boxvpos = detbox.offsetTop;
	var newpos = boxvpos + e.y - boxrect.y - 50;
	
	detbox.style.top = '' + newpos + 'px';
	
	// If there is enough room to place the details pane to the left of the interval
	// cell, do so.
	
	if ( intbox.offsetLeft > boxrect.width )
	{
	    var boxhpos = detbox.offsetLeft;
	    var newpos = boxhpos + cellrect.x - (boxrect.x + boxrect.width + 25);
	    
	    detbox.style.left = '' + newpos + 'px';
	}
	
	// Otherwise, place it to the right of the interval cell.
	
	else
	{
	    var boxhpos = detbox.offsetLeft;
	    var newpos = boxhpos + (cellrect.x + cellrect.width) - boxrect.x + 25;
	    
	    detbox.style.left = '' + newpos + 'px';
	}
    }
    
    
    let save_label = { };
    
    function showTime ( type )
    {
	// Change the attributes of the interval cells and bounds cells to show either
	// linear time (the height of each interval approximates its relative age span) or
	// regular time (the height of each interval provides just enough room to display
	// the labels legibly).
	
	// The value of 'ppma' will be the number of pixels per million years. The entire
	// display is scaled to 1500 pixels high if the displayed age range is more than a
	// billion years, 1000 pixels high otherwise.
	
	let age_range = interval_bounds[interval_bounds.length-1] - interval_bounds[0];
	let pix_range = age_range > 1000 ? 1500 : 1000;
	let ppma = pix_range / age_range;
	
	// However, the ppma value should always be at least 100, because otherwise the small
	// intervals will be too small. For large time spans, this will increase the
	// display beyond 1000/1500 pixels.
	
	if ( ppma > 100 )
	    ppma = 100;
	
	// I experimented with displaying logarithmic time, but could not get a reasonable
	// result. I am leaving the code commented out, for potential future use.
	
	// let log_offset = 1;
	
	// if ( type == 'log' )
	// {
	//     let log_range = Math.log(interval_bounds[interval_bounds.length-1] + log_offset) -
	// 	Math.log(interval_bounds[0] + log_offset);
	//     pix_range = 1000;
	//     ppma = pix_range / log_range;
	// }
	
	if ( type == 'linear' || type == 'log' )
	{
	    let current_height = 0;
	    let new_height;
	    
	    // Adjust the height of each bound-display row to be proportional to its
	    // time span. After we collapse the contents of small interval cells below,
	    // the height of each row will be controlled by the height of the bound row at
	    // the end.
	    
	    for ( var i=0; i<interval_bounds.length-1; i++ )
	    {
		let selector = 'b' + i;
		let elt = document.getElementById(selector);
		
		if ( elt )
		{
		    new_height = Math.round((interval_bounds[i+1]-interval_bounds[i]) * ppma);
		
		    // if ( type == 'log' )
		    // {
		    //     new_height = Math.round((Math.log(interval_bounds[i+1]+log_offset) -
		    // 			     Math.log(interval_bounds[i]+log_offset)) * ppma);
		    // }
		    
		    // Each row should be at least one pixel high, although this will
		    // distort some parts of the diagram at certain resolutions,
		    // e.g. the Holocene.
		    
		    if ( new_height < 1 )
			new_height = 1;
		    
		    elt.style.height = new_height + 'px';
		    
		    // Remove any bound label that is less than 10 pixels below the
		    // previous visible one. Save the value in the variable 'save_label'
		    // so that it can be restored when the display is returned to regular
		    // time.
		    
		    if ( current_height == 0 || current_height >= 10 )
		    {
			current_height = 0;
		    }
		    
		    else
		    {
			save_label[selector] = elt.innerHTML;
			elt.innerHTML = '';
		    }
		    
		    current_height += new_height;
		}
	    }
	    
	    // Get a list of all interval cells, and scan through them looking for cells
	    // with a small age span.
	    
	    let interval_cells = document.getElementsByClassName("ts_interval");
	    
	    for ( let i = 0; i < interval_cells.length; i++ )
	    {
		let elt = interval_cells[i];
		let key = elt.id;
		
		// If the cell id represents multiple intervals, use the first one.
		
		if ( /\+/.test(key) )
		{
		    let keys = key.split('+');
		    key = keys[0];
		}
		
		let idata = interval_data[key];
		
		if ( idata )
		{
		    let new_height = Math.round((idata.b_age - idata.t_age) * ppma);
		    
		    // if ( type == 'log' )
		    // {
		    // 	new_height = Math.round((Math.log(idata.b_age + log_offset) -
		    // 				 Math.log(idata.t_age + log_offset)) * ppma);
		    // }
		    
		    // If the cell is going to be less than 10 pixels high, remove its
		    // label. Save the label so that it can be restored when the display
		    // is returned to regular time.
		    
		    if ( new_height < 10 )
		    {
			save_label[elt.id] = elt.innerHTML;
			elt.innerHTML = '';
		    }
		    
		    // If the cell is going to be less than 25 pixels high, add the CSS
		    // class 'ts_lintime'. This removes its padding, and reduces its font
		    // size to 50% if the label is still there.
		    
		    if ( new_height < 25 )
			elt.classList.add('ts_lintime');
		}
	    }
	    
	    // Reduce all of the bound labels to 80% size.
	    
	    $('.ts_lastlabel').css('font-size', '80%');
	    $('.ts_boundlabel').css('font-size', '80%');
	}
	
	// Restore the display to regular time.
	
	else if ( type = 'regular' )
	{
	    // Set the height of each bound row back to 20 pixels, and restore any bound
	    // labels that were removed.
	    
	    for ( var i=0; i<interval_bounds.length-1; i++ )
	    {
		let selector = 'b' + i;
		let elt = document.getElementById(selector);
		
		if ( elt )
		{
		    elt.style.height = '20px';
		    if ( save_label[selector] ) elt.innerHTML = save_label[selector];
		}
	    }
	    
	    // Remove the CSS class 'ts_lintime' from any interval cells that have it, and
	    // restore any labels that were removed. For some reason I don't understand,
	    // the labels need to be restored via .textContent rather than through .innerHTML.
	    
	    let interval_cells = document.getElementsByClassName("ts_interval");
	    
	    for ( let i = 0; i < interval_cells.length; i++ )
	    {
		let elt = interval_cells[i];
		
		if ( save_label[elt.id] ) elt.textContent = save_label[elt.id];
		elt.classList.remove('ts_lintime');
	    }
	    
	    // Return the font size of the bound labels to normal.
	    
	    $('.ts_boundlabel').css('font-size', 'inherit');
	    $('.ts_lastlabel').css('font-size', 'inherit');
	}
	
	// For debugging purposes, return the calculated pixels-per-million-years scaling
	// factor.
	
	return ppma;
    }
    
    this.showTime = showTime;
}
