

function checkIntervalNames (require_field) {
    var frm = document.forms[1];
    var eml1 = frm.eml_max_interval.options[frm.eml_max_interval.selectedIndex].value;
    var name1 = frm.max_interval.value;
    var eml2 = frm.eml_min_interval.options[frm.eml_min_interval.selectedIndex].value;
    var name2 = frm.min_interval.value;
    
    if ( eml1 == 'Late/Upper' ) eml1 = 'Late';
    else if ( eml1 == 'Early/Lower' ) eml1 = 'Early';
    
    if ( eml2 == 'Late/Upper' ) eml2 = 'Late';
    else if ( eml2 == 'Early/Lower' ) eml2 = 'Early';
    
    if ( eml1 == 'Early' && eml2 == 'Late' )
    {
	eml1 = '';
	eml2 = '';
	if ( name1 == name2 ) name2 = '';
    }
    
    var emlname1 = eml1 ? eml1 + ' ' + name1 : name1;
    var emlname2 = eml2 ? eml2 + ' ' + name2 : name2;
    
    if ( name1 == "" || is_integer.test(name1))   {
        if (require_field) {
            var noname ="WARNING!\\n" +
                    "The maximum interval field is required.\\n" +
                    "Please fill it in and submit the form again.\\n" +
                    "Hint: epoch names are better than nothing.\\n";
            alert(noname);
            return false;
        }
    }
    
    if ( ! pbdb_interval_list.includes(name1) )
    {
	alert(`${name1} is not an official time interval.\nPlease use a different interval name.`);
	return false;
    }
    
    else if ( ! pbdb_interval_list.includes(emlname1) )
    {
	alert(`${emlname1} is not an official time interval.\nUse ${name1} with no prefix.`);
	return false;
    }
    
    if ( name2 )
    {
	if ( ! pbdb_interval_list.includes(name2) )
	{
	    alert(`${name2} is not an official time interval.\nPlease use a different interval name.`);
	    return false;
	}
	
	else if ( ! pbdb_interval_list.includes(emlname2) )
	{
	    alert(`${emlname2} is not an official time interval.\nUse ${name2} with no prefix.`);
	    return false;
	}
    }
    
    return true;
}

