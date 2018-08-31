//
// The functions defined in this file are used to manipulate the reference entry/editing form
// and change the fields to match the publication type.
//
// Moved from templates/js_reference_checkform.html to public/classic_js/reference_entry.js
// by Michael McClennen, 2018-08-30



function ReferenceEntryWidget ( form_name )
{
    var warning_count = 0;
    
    var no_collection_name;
    var no_city;
    var no_country;
    
    function checkForm() {
	
	var frm = document.forms[form_name];
	
	if ( ! frm )
	{
	    alert("ERROR: Form '" + form_name + "'not found.");
	    return 0;
	}
	
	if ( frm.publication_type.value == "museum collection" )
	{
	    return checkMuseumCollection();
	}
	
	var year = /^[1-2][0-9]{3}$/;
	// var capital = /[A-Z]/;
	var capital = XRegExp('\\p{Lu}');
	
	// var period = /[A-Za-z]\.$/;
	var period = XRegExp('\\p{L}\\.$');
	
	// var space = /([A-Za-z])(\.| | \.)([A-Za-z])|([A-Z][A-Z])/;
	
	// var all_caps = /^[A-Z][A-Z]/;
	var all_caps = XRegExp('\\p{Lu}{3}');
	var all_lower = XRegExp('\\p{Ll}{3}');
	
	var other_authors = XRegExp('^\\p{L}{2}|\\p{L}\\.$');
	
	var errors = "";
	var warnings = "";

	// First Author Initials
	// pattern for multiple spaces match
	var last_name_institution = /^\S+\s+\S+\s+\S+/;
	var last_name_anon = /^anon/i;
	if ( frm.author1init.value == "" ) {
	    if(frm.author1last.value.match(last_name_institution) ||
               frm.author1last.value.match(last_name_anon)){
		// OK to have a blank first name if the last name is
		// an institution, or is "anonymous"
	    }
	    else{
		errors += "* First author initials may not be blank\n"; 
	    }
	} else {
	    // Check for a capital letter
	    if ( capital.test ( frm.author1init.value ) == false ) {
		errors += "* First author initials should have a capital letter\n"; 
	    }
	    if ( period.test ( frm.author1init.value ) == false ) {
		errors += "* The first author's initials must end with a period\n"; 
	    }
	    // if ( space.test ( frm.author1init.value ) == true ) {
	    //     errors += "* There must be a period and a space between the first author's two initials\n"; 
	    // }
	}

	// First Author Last
	if ( frm.author1last.value == "" ) {
	    errors += "* First author last name may not be blank\n"; 
	} else {
	    // Check for a capital letter
	    if ( capital.test ( frm.author1last.value ) == false ) {
		if (! frm.author1last.value.match(last_name_anon)) {
		    errors += "* First author last name should have a capital letter\n"; 
		}
	    } else if ( all_caps.test ( frm.author1last.value ) == true && frm.author1last.value.length > 3) {
		errors += "* First author name can't all consist of capital letters\n"; 
            }
	}

	// Second Author Initials
	if ( frm.author2init.value != "" ) {
	    // Check for a capital letter
	    if ( capital.test ( frm.author2init.value ) == false ) {
		errors += "* Second author initials should have a capital letter\n"; 
	    } 
	    if ( period.test ( frm.author2init.value ) == false ) {
		errors += "* The second author's initials must end with a period\n"; 
	    }
	    // if ( space.test ( frm.author2init.value ) == true ) {
	    //     errors += "* There must be a period and a space between the second author's two initials\n"; 
	    // }
	}

	// Second Author Last
	if ( frm.author2last.value != "" ) {
	    // Check for a capital letter
	    if ( capital.test ( frm.author2last.value ) == false ) {
		errors += "* Second author last name should have a capital letter\n"; 
	    } else if ( all_caps.test ( frm.author2last.value ) == true && frm.author2last.value.length > 3) {
		errors += "* Second author name can not consist of all capital letters\n"; 
            }
	}

	// OtherAuthors
	// var contents = frm.otherauthors.value;
	// var pattern = /(^[A-Z][a-z\']+)|([A-Z]\.$)/;
	// var result = contents.match(pattern);
	if ( frm.otherauthors.value.match(other_authors) )	{
	    errors += "* Names of additional authors must be formatted with " +
		" initials before last names\n"+
		"Example: P. McCartney, J. P. Jones, J. Hendrix\n";
	}


	// Publication Year
	if ( frm.pubyr.value == "" ) {
	    errors += "* The publication year may not be blank\n"; 
	} else {
	    if ( year.test( frm.pubyr.value ) == false ) {
		errors += "* The publication year is invalid\n"; 
	    }
	}


	// Language
	if (frm.language && frm.language.selectedIndex != null) {
            var index = frm.language.selectedIndex;
            if ( index == 0 ) {
		errors += "* The publication language must be selected\n"; 
            } 
	}

	// Publication Type
	if (frm.publication_type && frm.publication_type.selectedIndex != null) {
            var index = frm.publication_type.selectedIndex;
            if ( index == 0 ) {
		errors += "* The publication type must be selected\n"; 
            } else {
		if ( frm.publication_type.options[frm.publication_type.selectedIndex].text == "book/book chapter" ) {
                    if ( frm.pubtitle.value == "" ) {
			errors += "* If you select \"book/book chapter\", you are required to fill in its name\n"; 
                    }
		}
            }
	}
	// var contents = frm.editors.value;
	// var pattern = /(^[A-Z][a-z\']+)|([A-Z]\.$)/;
	// var result = contents.match(pattern);
	if ( frm.editors.value.match(other_authors) )	{
	    errors += "* Names of editors must be formatted with " +
		" initials before last names\n"+
		"Example: P. McCartney, J. P. Jones, J. Hendrix\n";
	}
	
	if ( ! ( frm.reftitle.value || frm.pubtitle.value ) )
	{
	    errors += "* You must include either a title or a publication name\n";
	}
	
	// if ( /[^A-Za-z0-9\)\]\?\!"\.]$/.test(frm.reftitle.value) )	{
	// if ( /\.$/.test(frm.reftitle.value) ) {
	//	errors += "* The reference's title must end with a letter\n";
	// }
	if ( /\.$/.test(frm.reftitle.value) )	{
	    if ( ! / nov\.$/.test(frm.reftitle.value) && ! /U\.S\.A\.$/.test(frm.reftitle.value) && ! /U\.S\.S\.R\.$/.test(frm.reftitle.value) && ! / sp\.$/.test(frm.reftitle.value) && ! / spec\.$/.test(frm.reftitle.value) && ! / nov\.$/.test(frm.reftitle.value) )	{
		warnings += "* A reference title shouldn't end with a period\n";
		// warning_count++;
	    }
	}
	else if ( /\.[^0-9 ]/.test(frm.reftitle.value) )	{
	    if ( ! / sp\.(; | ,|\)|)/.test(frm.reftitle.value) && ! / nov\.(; |, |\)|)/.test(frm.reftitle.value) && ! /U\.S\.A\.(; |, |\)|)/.test(frm.reftitle.value) && ! /U\.S\.S\.R\.(; |, |\)|)/.test(frm.reftitle.value) )	{
		warnings += "* The reference title may include a stray period\n";
		// warning_count++;
	    }
	}
	//if ( /[~@\#\$%\^\*_\+\{\}\|\\<>\t\n]/.test(frm.reftitle.value) || /[^A-Za-z0-9]\//.test(frm.reftitle.value) || /[\/][^A-Za-z0-9]/.test(frm.reftitle.value) || /[:;\?\!][A-Za-z0-9]/.test(frm.reftitle.value) )	{
	//	errors += "* The reference's title includes weird characters\n";
	//}
	if ( /[^ ]\&/.test(frm.reftitle.value) || /[^ ]\&/.test(frm.pubtitle.value) )	{
	    errors += "* There must be a space before &\n";
	}
	if ( /\&[^ ]/.test(frm.reftitle.value) || /\&[^ ]/.test(frm.pubtitle.value) )	{
	    errors += "* There must be a space after &\n";
	}
	if ( /  /.test(frm.reftitle.value) )	{
	    errors += "* The reference's title includes extra spaces\n";
	}
	if ( all_caps.test(frm.reftitle.value) && ! all_lower.test(frm.reftitle.value) )	{
	    errors += "* Don't capitalize the entire reference title\n";
	}

	// if ( /[^A-Za-z0-9\)\]\?\!"]$/.test(frm.pubtitle.value) )	{
	if ( /\.$/.test(frm.pubtitle.value) ) {
	    errors += "* The book/serial name must end with a letter\n";
	}
	if ( /[~@\#\$%\^\*_\+\{\}\|\\<>\t\n]/.test(frm.pubtitle.value) || /[^A-Za-z0-9]\//.test(frm.pubtitle.value) || /[\/][^A-Za-z0-9]/.test(frm.pubtitle.value) || /[:;\?\!][A-Za-z0-9]/.test(frm.pubtitle.value) )	{
	    warnings += "* The book/serial name includes weird characters\n";
	    // warning_count++;
	}
	if ( /\.[^0-9 ]/.test(frm.pubtitle.value) )	{
	    warnings += "* The book/serial name may include a stray period\n";
	    // warning_count++;
	}
	if ( /  /.test(frm.pubtitle.value) )	{
	    errors += "* The book/serial name includes extra spaces\n";
	}
	if ( all_caps.test(frm.pubtitle.value) && ! all_lower.test(frm.pubtitle.value) && ! /PLoS ONE/.test(frm.pubtitle.value) )	{
	    errors += "* Don't capitalize the entire book/serial name\n";
	}
	// Report errors
	
	if ( errors != "" )
	{
	    errors = errors + "\nPlease fix the problem and resubmit";
	    alert ( errors );
	    warning_count = 0;
	    return false;
	}

	else if ( warnings != "" && warning_count == 0 )
	{
	    warning_count = 1;
	    warnings = warnings + "\nPlease make sure there isn't a mistake and resubmit\n";
	    alert ( warnings );
	    return false;
	}
	
	frm.check_status.value = "done";
	return true;
    }

    this.checkForm = checkForm;


    function checkMuseumCollection ( )
    {
	var frm = document.forms[form_name];
	
	var errors = "";
	var warnings = "";
	
	if ( ! frm.museum_name.value )
	{
	    errors = errors + "* You must specify the museum name\n";
	}

	if ( ! frm.museum_collection.value && ! no_collection_name )
	{
	    warnings = warnings + "* Please enter a collection name if you know it\n";
	}

	if ( ! frm.museum_acronym.value )
	{
	    warnings = warnings + "* Please enter the museum acronym if at all possible\n";
	}
	
	if ( frm.museum_city.value && ! frm.museum_country.value && ! no_country )
	{
	    errors = errors + "* If you specify a city, you must fill in the country and the state/province if there is one\n";
	}
	
	else if ( ! frm.museum_city.value && ! no_city )
	{
	    warnings = warnings + "* Please fill in the museum city, state/province, and country if at all possible\n";
	}
	
	if ( errors != "" )
	{
	    errors = errors + "\nPlease fix the problem and resubmit";
	    alert ( errors );
	    warning_count = 0;
	    return false;
	}
	
	else if ( warnings != "" && warning_count == 0 )
	{
	    warning_count = 1;
	    warnings = warnings + "\nPlease make sure there isn't a mistake and resubmit\n";
	    alert ( warnings );
	    return false;
	}
	
	frm.check_status.value = "done";
	return true;
    }
    
    
    function adjustRefType()
    {
	var frm = document.forms[form_name];
	var pubtype = frm.publication_type.value;
	
	if ( pubtype == '' || pubtype == 'unpublished' )
	{
	    document.getElementById('authorinfo').style.display = 'block';
	    document.getElementById('museuminfo').style.display = 'none';
	    document.getElementById('miscinfo').style.display = 'block';
	    document.getElementById('addressinfo').style.display = 'none';
	    document.getElementById('pubinfo').style.display = 'none';
	    document.getElementById('editors').style.display = 'none';	    
	    document.getElementById('titleinfo').style.display = 'block';
	    document.getElementById('serialinfo').style.display = 'none';
	    document.getElementById('volinfo').style.display = 'none';
	    document.getElementById('pageinfo').style.display = 'none';
	}
	
	else if ( pubtype == 'museum collection' )
	{
	    document.getElementById('authorinfo').style.display = 'none';
	    document.getElementById('museuminfo').style.display = 'block';
	    document.getElementById('miscinfo').style.display = 'none';	    
	    document.getElementById('addressinfo').style.display = 'block';
	    document.getElementById('pubinfo').style.display = 'none';	    
	    document.getElementById('editors').style.display = 'none';	    
	    document.getElementById('titleinfo').style.display = 'none';
	    document.getElementById('serialinfo').style.display = 'none';
	    document.getElementById('volinfo').style.display = 'none';
	    document.getElementById('pageinfo').style.display = 'none';
	}
	
	else
	{
	    document.getElementById('authorinfo').style.display = 'block';
	    document.getElementById('museuminfo').style.display = 'none';
	    document.getElementById('miscinfo').style.display = 'block';
	    document.getElementById('addressinfo').style.display = 'none';
	    document.getElementById('pubinfo').style.display = 'block';
	    document.getElementById('editors').style.display = 'block';	    
	    document.getElementById('titleinfo').style.display = 'block';
	    document.getElementById('serialinfo').style.display = 'block';
	    document.getElementById('volinfo').style.display = 'block';
	    document.getElementById('pageinfo').style.display = 'block';
	}
	
	// If this is the initial call to this function, and if this is an edit of an existing
	// record, then record whether some of the optional fields are in fact missing. This will
	// prevent warnings from being given for them later.

	if ( frm.reference_no.value )
	{
	    if ( ! frm.museum_collection.value )
		no_collection_name = 1;

	    if ( ! frm.museum_city.value )
		no_city = 1;

	    if ( ! frm.museum_country.value )
		no_country = 1;
	}
	
	//if ( pubtype == 'book' || pubtype == 'book chapter' || pubtype == 'book/book chapter' ||
	//     pubtype == 'serial monograph' || pubtype == 'compendium' || pubtype == 'guidebook' )
	//{
	//	document.getElementById('editors').style.display = 'inline';
	//} else {
	//	document.getElementById('editors').style.display = 'none';
	//}
	
	//if ( pubtype == 'journal article' || pubtype == 'serial monograph' ||
	//	pubtype == 'news article' || pubtype == 'abstract' )
	//{
	//	document.getElementById('volinfo').style.display = 'inline';
	//} else {
	//	document.getElementById('volinfo').style.display = 'none';
	//}
	
	//if ( pubtype == 'journal article' || pubtype == 'book chapter' ||
	//	pubtype == 'book/book chapter' || pubtype == 'news article' || pubtype == 'abstract' )
	//{
	//	document.getElementById('pageinfo').style.display = 'inline';
	//} else {
	//	document.getElementById('pageinfo').style.display = 'none';
	//}
    }

    this.adjustRefType = adjustRefType;
}

