
// These functions are used to check the input values for occurrence lists.

"use strict";

function checkForm()
{
    try {
	var frm = document.forms["occurrenceList"];
	var rows = 0;
	var taxon_names = [ ];
	var abund_values = [ ];
	var abund_units = [ ];
	var occurrence_nos = [ ];
	var reid_nos = [ ];
	var ref_nos = [ ];
	var errors = "";
	
	// If this script is validating the 'occurrence_add_edit' form:
	
	if ( typeof( frm.row_token) != "undefined" )
	{
	    rows = frm.row_token.length;
	    
	    for ( var i=0; i < frm.taxon_name.length; i++ )
	    {
		taxon_names[i] = frm.taxon_name[i].value;
		occurrence_nos[i] = frm.occurrence_no[i] && frm.occurrence_no[i].value;
		reid_nos[i] = frm.reid_no && frm.reid_no[i] && frm.reid_no[i].value;
		ref_nos[i] = frm.reference_no && frm.reference_no[i] && frm.reference_no[i].value;
	    }
	}
	
	// If this script is validating the 'occurrence_list' form:
	
	else
	{
	    if ( /[\n\r]/.test( frm.taxon_list.value ) )
	    {
		var lines = [ ];
		lines = frm.taxon_list.value.split(/[\n\r]+/);
		for ( var i=0; i < lines.length; i++ )
		{
		    if ( /^\s*[^\*#\/]/.test( lines[i] ) )
		    {
			taxon_names[rows] = lines[i];
			occurrence_nos[rows] = -1;
			reid_nos[rows] = -1;
			ref_nos[rows] = frm.reference_no.value;
			rows = rows + 1;
		    }
		    
		    else if ( rows == 0 )
		    {
			errors += "* Don't start the list with a comment\n";
		    }
		}
	    }
	    
	    else
	    {
		taxon_names[0] = frm.taxon_list.value;
		occurrence_nos[0] = -1;
		reid_nos[0] = -1;
		ref_nos[0] = frm.reference_no.value;
		rows = 1;
	    }
	}
	
	var lasterrors = "";
	var lastocc = 0;
	var reid_count = { };
	
	// need to know which occurrences are reidentified
	// some strong assumptions: the reid is of the last occurrence
	
	for ( var i=0; i < rows; i++ )
	{
	    if ( taxon_names[i] != "" && reid_nos[i] > 0 && lastocc > 0 && lastocc == occurrence_nos[i] )
	    {
		reid_count[lastocc] = reid_count[lastocc] + 1;
	    }
	    
	    else if ( taxon_names[i] != "" && reid_nos[i] == 0 )
	    {
		lastocc = occurrence_nos[i];
		reid_count[lastocc] = 0;
	    }
	}
	
	// main pass
	
	for ( var i=0; i < rows; i++ )
	{
	    if ( taxon_names[i] != "" )
	    {
		// checks for duplicates will need to ignore subgenera,
		//  n. gen., and n. sp.
		
		var simpleName = simplify_name( taxon_names[i] );
		
		var reid_index = occurrence_nos[i] > 0 ? reid_count[occurrence_nos[i]] : 0;
		
		// check for dupes
		// revised 20.2.08 so only current IDs are matched,
		//  as opposed to occurrences since reIDed
		
		for ( var j=0; j < i; j++ )
		{
		    var simpleName2 = simplify_name( taxon_names[j] );
		    
		    if ( taxon_names[j] != "" && simpleName == simpleName2 )
		    {
			var reid_index_2 = occurrence_nos[j] > 0 ? reid_count[occurrence_nos[j]] : 0;
			
			// case 1: identical occurrence and its own reID
			// if ( occurrence_nos[i] == occurrence_nos[j] && reid_index > 0 )
			// {
			//     errors += "* " + simpleName + " and its reID have the same name\n";
			// }
			
			// case 2: identical occurrences with no reIDs
			
			if ( reid_index < 1 && reid_index_2 < 1 )
			{
			    errors += "* " + simpleName + " is listed twice\n";
			}
			
			// case 3: identical reIDs
			
			if ( reid_nos[i] > 0 && reid_nos[j] > 0 && 
			     occurrence_nos[i] == occurrence_nos[j] )
			{
			    errors += "* " + simpleName + " is listed twice\n";
			}
			
			// case 4: first is a reID and second has no reID
			// only complain if the refs are identical
			// Update: MM commented this out at Mark Uhen's request
			//if ( reid_nos[i] > 0 && reid_index_2 < 1 && ref_nos[i] == ref_nos[j] )	{
			//	errors += "* " + simpleName + " is listed twice\n";
			//}
			
			// case 5: first has no reID and second is a reID
			if ( reid_index < 1 && reid_nos[j] > 0 && 
			     ref_nos[i] == ref_nos[j] )
			{
			    errors += "* " + simpleName + " is listed twice\n";
			}
		    }
		}
		
		// Now check each name to make sure it follows all of the rules.
		
		var taxonName = taxon_names[i];
		
		// Replace informals with dummies before checking.
		
		taxonName = taxonName.replace(/^<.*?> /,'Genus ');
		taxonName = taxonName.replace(/ [(]<.*?>[)]/,' (Subgenus)');
		taxonName = taxonName.replace(/ <.*>/g,' species');
		
		// Remove trailing spaces and collapse whitespace into single spaces.
		
		taxonName = taxonName.replace(/ +$/, '');
		taxonName = taxonName.replace(/ +/g, ' ');
		
		// Check for obvious errors
		
		// if ( ! / /.test(taxonName) )
		// {
		// 	  errors += errstr("Taxon names must include at least two words", taxon_names[i]);
		// 	  continue;
		// }
		
		if ( /^ /.test(taxonName) )
		{
		    errors += errstr("Names must not start with a space", taxon_names[i]);
		    continue;
		}
		
		if ( /[0-9]/.test(taxonName) )
		{
		    errors += errstr("Numeric digits are not allowed", taxon_names[i]);
		    continue;
		}
		
		if ( /[A-Za-z][A-Z]/.test(taxonName) )
		{
		    errors += errstr("Bad capitalization", taxon_names[i]);
		    continue;
		}
		
		if ( /([?]|[.]|sensu lato)[A-Za-z]/.test(taxonName) )
		{
		    errors += errstr("Enter a space after a qualifier like cf.", taxon_names[i]);
		    continue;
		}
		
		if ( /[A-Za-z]+[^a-z: -][a-z]/.test(taxonName) )
		{
		    errors += errstr("Only small letters can go inside a word", taxon_names[i]);
		    continue;
		}
		
		if ( /[^A-Za-z ".?():-]/.test(taxonName) )
		{
		    errors += errstr("Name contains an invalid character", taxon_names[i]);
		    continue;
		}
		
		if ( /[A-Z][.]/.test(taxonName) )
		{
		    errors += errstr("Genus and subgenus names must be written out", taxon_names[i]);
		    continue;
		}
		
		if ( /gen[.] nov[.]|nov[.] gen[.]|n[.] g[.]|n[.]g[.]/.test(taxonName) )
		{
		    errors += errstr("Use n. gen. for a new genus", taxon_names[i]);
		    continue;
		}
		
		if ( /sp[.] nov[.]|nov[.] sp[.]|n[.]sp[.]/.test(taxonName) )
		{
		    errors += errstr("Use n. sp. for a new species", taxon_names[i]);
		    continue;
		}
		
		if ( /[.][^ ]/.test(taxonName) )
		{
		    errors += errstr("A period must be followed by a space", taxon_names[i]);
		    continue;
		}
		
		if ( / [a-z][.]/.test(taxonName) && ( taxonName.search(/ [a-z][.]/) != 
						      taxonName.search(/ n[.] (sub)?(gen|sp)[.]/) ) )
		{
		    errors += errstr("Species names must be written out", taxon_names[i]);
		    continue;
		}
		
		if ( /\( /.test(taxonName) )
		{
		    errors += errstr("Open parentheses have to come right before subgenus names",
				     taxon_names[i]);
		    continue;
		}
		
		if ( / \)/.test(taxonName) )
		{
		    errors += errstr("Close parentheses have to come right after subgenus names",
				     taxon_names[i]);
		    continue;
		}
		
		if ( /[^ ]\(/.test(taxonName) || /\)[^ ]/.test(taxonName) )
		{
		    errors += errstr("There must be a space before and after parentheses",
				     taxon_names[i]);
		    continue;
		}
		
		if ( /sp[.] indet[.]/.test(taxonName) )
		{
		    errors += errstr("Enter sp. instead of sp. indet.", taxon_names[i]);
		    continue;
		}
		
		if ( /var[.]/.test(taxonName) )
		{
		    errors += errstr("Enter variety names in the comments field only", taxon_names[i]);
		    continue;
		}
		
		if ( /\?$/.test(taxonName) )
		{
		    errors += errstr("Put ? at the beginning of the name", taxon_names[i]);
		    continue;
		}
		
		if ( /(indet|sp|spp)$/.test(taxonName) )
		{
		    errors += errstr("Put a period after indet, sp, or spp", taxon_names[i]);
		    continue;
		}
		
		if ( /<|>/.test(taxonName) )
		{
		    errors += errstr("Improper or unbalanced &lt; &gt;", taxon_names[i]);
		    continue;
		}
		
		// Deconstruct the name and make sure it follows the allowed pattern
		
		var match;
		var rest = taxonName;
		
		var genusName, genusReso, subgenusName, subgenusReso;
		var speciesName, speciesReso, subspeciesName, subspeciesReso;
		
		// Remove n. gen. and its associates if any are found. This may leave
		// extra spaces in the name.
		
		if ( match = rest.match(/(.*)n[.] gen[.](.*)/) )
		{
		    genusReso = "n. gen.";
		    rest = match[1] + ' ' + match[2];
		}
		
		if ( match = rest.match(/(.*)n[.] sp[.](.*)/) )
		{
		    speciesReso = "n. sp.";
		    rest = match[1] + ' ' + match[2];
		}
		
		if ( match = rest.match(/(.*)n[.] subgen[.](.*)/) )
		{
		    subgenusReso = "n. subgen.";
		    rest = match[1] + ' ' + match[2];
		}
		
		if ( match = rest.match(/(.*)n[.] subsp[.](.*)/) )
		{
		    subspeciesReso = "n. subsp.";
		    rest = match[1] + ' ' + match[2];
		}
		
		// Remove extra spaces
		
		rest = rest.replace(/^ +/, '');
		rest = rest.replace(/ +$/, '');
		rest = rest.replace(/  +/g, ' ');
		
		// Now look for the genus name, starting with any qualifiers.
		
		if ( match = rest.match(/^([?]|aff[.]|cf[.]|ex gr[.]|sensu lato)\s+(.*)/) )
		{
		    genusReso = match[1];
		    rest = match[2];
		}
		
		if ( match = rest.match(/^(["]?)([A-Za-z]+)(["]?)\s*(.*)/) )
		{		    
		    genusName = match[2];
		    rest = match[4];
		    
		    if ( match[1] != match[3] )
		    {
			errors += errstr('Unmatched &quot; on genus name', taxon_names[i]);
			continue;
		    }
		    
		    if ( ! /^[A-Z][a-z]+$/.test(genusName) )
		    {
			errors += errstr('Genus names must be capitalized', taxon_names[i]);
			continue;
		    }
		}
		
		else if ( /[A-Z]/.test(rest) )
		{
		    errors += errstr("Invalid modifier on genus", taxon_names[i]);
		    continue;
		}
		
		else
		{
		    errors += errstr("Missing genus", taxon_names[i]);
		    continue;
		}
		
		if ( match = rest.match(/^([?]|aff[.]|cf[.]|ex gr[.]|sensu lato)\s+([(].*)/) )
		{
		    subgenusReso = match[1];
		    rest = match[2];
		}
		
		if ( match = rest.match(/^[(](["]?)([A-Za-z]+)(["]?)[)]\s*(.*)/) )
		{
		    subgenusName = match[2];
		    rest = match[4];
		    
		    if ( match[1] != match[3] )
		    {
			errors += errstr("Unmatched &quot; on subgenus name", taxon_names[i]);
			continue;
		    }
		    
		    if ( ! /^[A-Z][a-z]+$/.test(subgenusName) )
		    {
			errors += errstr("Subgenus names must be capitalized", taxon_names[i]);
			continue;
		    }
		}
		
		else if ( match = rest.match(/^[(](.*?)[)]\s*(.*)/) )
		{
		    errors += errstr("Invalid subgenus", taxon_names[i]);
		    continue;
		}
		
		else if ( /[(]/.test(rest) )
		{
		    errors += errstr("Invalid modifier on subgenus", taxon_names[i]);
		    continue;
		}
		
		if ( subgenusName && /[(]/.test(rest) )
		{
		    errors += errstr("There can only be one subgenus name", taxon_names[i]);
		    continue;
		}
		
		if ( match = rest.match(/^([?]|aff[.]|cf[.]|ex gr[.]|sensu lato)\s+(.*)/) )
		{
		    speciesReso = match[1];
		    rest = match[2];
		}
		
		if ( match = rest.match(/^(["]?)([A-Za-z-]+[.]?)(["]?)(.*)/) )
		{
		    speciesName = match[2];
		    rest = match[4];
		    
		    if ( match[1] != match[3] )
		    {
			errors += errstr('Unmatched &quot; on species name', taxon_names[i]);
			continue;
		    }
		    
		    if ( /^[A-Z]/.test(speciesName) )
		    {
			errors += errstr('Species names must not be capitalized', taxon_names[i]);
			continue;
		    }
		    
		    if ( /[.]$/.test(speciesName) && ! /^(sp[.]|spp[.]|indet[.])$/.test(speciesName) )
		    {
			if ( rest != "" )
			{
			    errors += errstr('Invalid modifier on species', taxon_names[i]);
			    continue;
			}
			
			else
			{
			    errors += errstr('Invalid or badly formed species name', taxon_names[i]);
			    continue;
			}
		    }
		}
		
		else if ( /[a-z]/.test(rest) )
		{
		    errors += errstr("Invalid modifier on species", taxon_names[i]);
		    continue;
		}
		
		else
		{
		    errors += errstr("Enter sp. or indet. for indeterminate species or higher taxa",
				     taxon_names[i]);
		    continue;
		}
		
		if ( match = rest.match(/^\s+([?]|aff[.]|cf[.]|ex gr[.]|sensu lato)(.*)/) )
		{
		    subspeciesReso = match[1];
		    rest = match[2];
		}
		
		if ( match = rest.match(/^\s+(["]?)([A-Za-z]+)(["]?)\s*(.*)/) )
		{
		    subspeciesName = match[2];
		    rest = match[4];
		    
		    if ( match[1] != match[3] )
		    {
			errors += errstr('Unmatched &quot; on subspecies name', taxon_names[i]);
			continue;
		    }
		    
		    if ( /^[A-Z]/.test(subspeciesName) )
		    {
			errors += errstr('Author names must be entered in the comment field', taxon_names[i]);
			continue;
		    }
		}
		
		else if ( /[a-z]/.test(rest) )
		{
		    errors += errstr("Invalid modifier on subspecies", taxon_names[i]);
		    continue;
		}
		
		if ( rest != "" )
		{
		    errors += errstr("Extra stuff at end of name", taxon_names[i]);
		    continue;
		}
		
		// else if ( ( ! /\(("|)[A-Z][a-z][a-z]*("|)\)/.test( taxonName ) ) && ( /\(/.test( taxonName ) || /\)/.test( taxonName ) ) )	{
		// 	    errors += "* Only a subgenus name can be in parentheses";
		// } else if ( /[A-Z][a-z]+ .+ \(/.test( taxonName ) && ! /[A-Z][a-z]+ (\?|aff\.|cf\.|ex gr\.|n\. gen\.|sensu lato) \(/.test( taxonName ) )	{
		//     errors += "* Only a qualifier can come between genus and subgenus names";
		// } else if ( /[^A-Za-z]et[^a-z]/.test( taxonName ) )	{
		//     errors += "* Et tu, Brute?";
		// } else if ( /(\?|aff\.|cf\.|ex gr\.|n\. gen\.|n\. sp\.|sensu lato)( )(\?|aff\.|cf\.|ex gr\.|n\. gen\.|n\. sp\.|sensu lato)/.test( taxonName ) && ! /n\. gen\. n\. sp\./.test( taxonName ) )	{
		//     errors += "* A genus or species name can only have one qualifier";
		// else if ( /\. /.test( taxonName ) && ! /(\baff\.|\bcf\.|\bex gr\.|\bn\. gen\.)( )/.test( taxonName ) && ! /\bn\. sp\./.test( taxonName ) )	{
		//     errors += "* Only qualifiers can end with periods";
		// } else if ( /\. (\baff\.|\bcf\.|\bex gr\.|\bn\. gen\.|\bn\. sp\.)( )/.test( taxonName ) && ! /n\. gen\. n\. sp\./.test( taxonName ) )	{
		//     errors += "* Only qualifiers can end with periods";
		// } else if ( /(\baff\.|\bcf\.|\bex gr\.|\bn\. gen\.|\bn\. sp\.)( [A-Za-z]+\.)/.test( taxonName ) && ! /(\baff\.|\bcf\.|\bex gr\.|\bn\. gen\.|\bn\. sp\.)( )(n\. sp\.|indet\.|sp\.|spp\.)/.test( taxonName ) )	{
		//     errors += "* Only qualifiers can end with periods";
                // } else if ( /n\. gen\. n\. sp\. /.test( taxonName ) )	{
                //     errors += "* Put n. gen. n. sp. at the end";
                // } else if ( /n\. gen\. n\. sp\./.test( taxonName ) && ! / [a-z]+ n\. gen\. n\. sp\./.test( taxonName ) )	{
                //     errors += "* There appears to be no species name";
		// } else if ( /^[a-z]/.test( taxonName ) && ! /^(\?|aff\.|cf\.|ex gr\.|n\. gen\.|sensu lato)/.test( taxonName ) )	{
		//     errors += "* You must capitalize genus names";
		// } else if ( /^(\?|aff\.|cf\.|ex gr\.|n\. gen\.|sensu lato)( [a-z])/.test( taxonName ) )	{
		//     errors += "* You must capitalize genus names";
		// } else if ( /(^" )|( " )/.test( taxonName ) )	{
		//     errors += "* Quotation marks should not be separated from taxon names";
		// } else if ( / (\(|)[A-Za-z]+"(\)|)|"[A-Za-z]+(\)|) |^[A-Za-z]+"|"[A-Za-z]+$/.test( taxonName ) )	{
		//     errors += "* Quotation marks must be matched";
		// } else if ( /(n\. sp\. [^a-z])/.test( taxonName ) )	{
		//     errors += "* Put n. sp. between the genus and species names";
		// } else if ( /[A-Z][a-z]* [A-Z][a-z]*/.test( taxonName ) )	{
		//     errors += "* Subgenus names should be in parentheses";
		// } else if ( / ("|)[a-z]+("|) ("|)[a-z][a-z]+/.test( taxonName ) && ! / (sensu lato|ex gr\.) (\(("|)[A-Z]|)[a-z]+/.test( taxonName ) && ! / [a-z]+ sensu lato$/.test( taxonName )  )	{
		//     errors += "* Enter subspecies names in the comments field only";
		// else if ( /"$/.test( taxonName ) )	{
		//     errors += "* You can't end a name with a quote";
		// } else if ( /(indet\. |([a-mo-z]\.|[a-z]) sp\. |spp\. )/.test( taxonName ) )	{
		//     errors += "* Nothing can come after indet., sp., or spp.";
		// } else if ( ! /^(([A-Z][a-z][a-z]*)|("[A-Z][a-z][a-z]*")|((\?|aff\.|cf\.|ex gr\.|n\. gen\.|sensu lato) [A-Z][a-z][a-z]*))( |" )/.test( taxonName ) )	{
		//     errors += "* The genus name is missing or ill-formed";
		// } else if ( ! /( |")([a-z][a-z]*)("|)$/.test( taxonName ) && ! /( )(indet\.|sp\.|spp\.)$/.test( taxonName ) )	{
		//     errors += "* The species name is missing or ill-formed";
		// }
		
		if ( frm.abund_value && frm.abund_unit )
		{
		    if ( /[A-Za-z0-9]/.test( abund_values[i] ) && ! /[a-z]/.test( abund_units[i] ) )
		    {
			errors += errstr("Don't forget the abundance unit", taxon_names[i]);
		    }
		    
		    else if ( ! /[A-Za-z0-9]/.test( abund_values[i] ) && /[a-z]/.test( abund_units[i] ) )
		    {
			errors += errstr("Don't forget the abundance value", taxon_names[i]);
		    }
		}
		
		if ( ref_nos[i] == "" )
		{
		    errors += errstr("Don't leave out the reference number", taxon_names[i]);
		}
		
		else if ( ! /^[1-9][0-9]*$/.test( ref_nos[i] ) )
		{
		    errors += errstr("The reference number must be a positive integer", taxon_names[i]);
		}
		
		// // For non-informal names, reconstruct the latin name and check for duplicates.
		
		// if ( genusName && genusName != 'Genus' )
		// {
		//     var latinName = genusName;
		    
		//     if ( subgenusName && subgenusName != 'Subgenus' )
		//     {
		// 	latinName = latinName + ' (' + subgenusName + ')';
		//     }
		    
		//     if ( speciesName && speciesName != 'species' )
		//     {
		// 	latinName = latinName + ' ' + speciesName;
			
		// 	if ( subspeciesName && subspeciesName != 'species' )
		// 	{
		// 	    latinName = latinName + ' ' + subspeciesName;
		// 	}
		//     }		    
		// }
	    }
	}
	
	if ( errors != "" )
	{
	    alert ( errors );
	    return false;
	}
	
	frm.check_status.value = "done";
	return true;
    }
    
    catch (err) {
	alert("An error occurred during validation, so the form cannot be submitted: " + err);
	return false;
    }
}

function simplify_name( name )
{
    // treat subgenera as genera
    // assumes authors use or don't use subgenus names consistently
    if ( /\(/.test( name ) )
    {
	name = name.replace(/^\s*[A-Z][a-z]* /,'');
	name = name.replace(/\(/,'');
	name = name.replace(/\)/,'');
    }
    
    name = name.replace(/\s*n\. gen\.\s*/,' ');
    name = name.replace(/\s*n\. sp\.\s*/,' ');
    name = name.replace(/^\s+/,'');
    name = name.replace(/\s+$/,'');
    name = name.replace(/</g, '&lt;');
    name = name.replace(/>/g, '&gt;');
    return name;
}

function errstr( message, name )
{
    if ( name )
    {
	name = name.replace('<', '&lt;');
	name = name.replace('>', '&gt;');
    }
    
    return "* " + message + "\n   (" + name + ")\n";
}

