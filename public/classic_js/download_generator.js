
var params = { base_name: '',
	       interval: '' };
var param_errors = { base_name: 0,
		     interval: 0 };
var visible = { f1: 0, f2: 0 };
var pbdb_data = { init: 1 };
var data_type = "occs";
var data_op = "occs/list";
var url_op = "occs/list";
var data_format = ".csv";
var ref_format = "";
var non_ref_format = ".csv";
var output_section = 'none';
var output_order = 'none';
var confirm_download = 0;
var taxon_status_save = '';
var taxon_box_save = false;

var patt_dec_num = /^[+-]?(\d+[.]\d*|\d*[.]\d+|\d+)$/;
var patt_dec_pos = /^(\d+[.]\d*|\d*[.]\d+|\d+)$/;
var patt_name = /^(.+),\s+(.+)/;
var patt_name2 = /^(.+)\s+(.+)/;
var patt_has_digit = /\d/;
var user_names;
var user_match = [ ];
var user_matchinit = [ ];
var valid_name = { };

document.addEventListener("DOMContentLoaded", initConfig, false);


function initConfig ( )
{
    initDisplayClasses();
    
    $.getJSON(base_data_url + 'config.json?show=all&limit=all').done(callBackConfig1);
    $.getJSON(base_data_url + 'intervals/list.json?all_records&limit=all').done(callBackConfig2);
}


function initDisplayClasses ( )
{
    showByClass('type_occs');
    showByClass('taxon_reso');
    
    hideByClass('advanced');
    hideByClass('mult_cc3');
    hideByClass('mult_cc2');
    
    hideByClass('type_colls');
    hideByClass('type_taxa');
    hideByClass('type_ops');
    hideByClass('type_strata');
    hideByClass('type_refs');
    
    hideByClass('help_h1');
    hideByClass('help_h2a');
    hideByClass('help_h2b');
    hideByClass('help_f1');
    hideByClass('help_f2');
    hideByClass('help_f3');
    hideByClass('help_f4');
    hideByClass('help_f5');
    hideByClass('help_f6');
    hideByClass('help_o1');
    
    if ( is_contributor )
    {
	showElement('pd_private');
	params.private = 1;
    }
    
    // $('.dl_help_f1').css('display', 'none');
    // $('.dl_advanced').css('display', 'none');
    // $('.dl_type_taxa_ops').css('display', 'none');
}


function callBackConfig1 ( response )
{
    if ( response.records )
    {
	pbdb_data.rank_string = {};
	pbdb_data.continent_name = {};
	pbdb_data.continents = [];
	pbdb_data.country_code = {};
	pbdb_data.country_name = {};
	pbdb_data.countries = [];
	var country_names = [];
	var aux_continents = [];
	
	for ( var i=0; i < response.records.length; i++ )
	{
	    var record = response.records[i];
	    
	    if ( record.cfg == "trn" ) {
		pbdb_data.rank_string[record.cod] = record.rnk;
	    }
	    else if ( record.cfg == "con" ) {
		pbdb_data.continent_name[record.code] = record.nam;
		if ( record.cod == 'ATA' || record.cod == 'OCE' || record.cod == 'IOC' )
		    aux_continents.push(record.cod, record.nam);
		else
		    pbdb_data.continents.push(record.cod, record.nam);
	    }
	    else if ( record.cfg == "cou" ) {
		var key = record.nam.toLowerCase();
		pbdb_data.country_code[key] = record.cod;
		pbdb_data.country_name[record.cod] = record.nam;
		country_names.push(record.nam);
		// pbdb_data.countries.push(record.cod, record.nam);
	    }
	}
	
	pbdb_data.continents = pbdb_data.continents.concat(aux_continents);
	country_names = country_names.sort();
	
	for ( i=0; i < country_names.length; i++ )
	{
	    var key = country_names[i].toLowerCase();
	    var code = pbdb_data.country_code[key];
	    pbdb_data.countries.push( code, country_names[i] + " (" + code + ")" );
	}
	
	if ( pbdb_data.interval ) initThisForm();
    }
    
    else
	badInit();
}


function callBackConfig2 ( response )
{
    if ( response.records )
    {
	pbdb_data.interval = {};
	
	for ( var i = 0; i < response.records.length; i++ )
	{
	    var record = response.records[i];
	    var key = record.nam.toLowerCase();
	    
	    pbdb_data.interval[key] = record.oid;
	}
    }
    
    if ( pbdb_data.rank_string ) initThisForm();
}


function initThisForm ( )
{
    document.getElementById("db_initmsg").style.display = 'none';
    initFormContents();
    showHideSection('f1', 'show');
    setRecordType('occs', 1);
    params.output_metadata = 1;
    updateFormState();
}


function resetForm ( )
{
    document.getElementById("download_form").reset();
    params = { base_name: '', interval: '', output_metadata: 1 };
    updateFormState();
}


function badInit ( )
{
    document.getElementByid("initmsg").innerHTML = "Initialization failed!  Please contact admin@paleobiodb.org";
}


function hideElement ( id )
{
    var element = myGetElement(id);
    
    if ( element )
    {
	element.style.display = 'none';
	visible[id] = 0;
    }
}


function showElement ( id )
{
    var element = myGetElement(id);
    
    if ( element )
    {
	element.style.display = '';
	visible[id] = 1;
    }
}


function hideByClass ( classname )
{
    visible[classname] = 0;
    var list = document.getElementsByClassName('vis_' + classname);
    
    for ( var i = 0; i < list.length; i++ )
    {
	list[i].style.display = 'none';
    }
    
    list = document.getElementsByClassName('inv_' + classname);
    
    element:
    for ( var i = 0; i < list.length; i++ )
    {
	var classes = list[i].classList;
	
	for ( var j = 0; j < classes.length; j++ )
	{
	    var classprefix = classes[j].slice(0,4);
	    var rest = classes[j].substr(4);
	    
	    if ( classprefix == "vis_" && ! visible[rest] )
	    {
		continue element;
	    }
	    
	    else if ( classprefix == "inv_" && visible[rest] )
	    {
		continue element;
	    }
	}
	
	list[i].style.display = '';
    }
}


function showByClass ( classname )
{
    visible[classname] = 1;
    var list = document.getElementsByClassName('vis_' + classname);
    
    element:
    for ( var i = 0; i < list.length; i++ )
    {
	var classes = list[i].classList;
	
	for ( var j = 0; j < classes.length; j++ )
	{
	    var classprefix = classes[j].slice(0,4);
	    var rest = classes[j].substr(4);
	    
	    if ( classprefix == "vis_" && ! visible[rest] )
	    {
		continue element;
	    }
	    
	    else if ( classprefix == "inv_" && visible[rest] )
	    {
		continue element;
	    }
	}
	
	list[i].style.display = '';
    }
    
    list = document.getElementsByClassName('inv_' + classname);
    
    for ( var i = 0; i < list.length; i++ )
    {
	list[i].style.display = 'none';
    }
}


function showHideSection( section_id, action )
{
    var my_sect = document.getElementById(section_id);
    var my_mark = document.getElementById('m'+section_id);
    
    if ( ! my_sect ) return;
    
    if ( my_sect.style.display == 'none' || (action && action == 'show') )
    {
        my_sect.style.display = '';
	visible[section_id] = 1;
	my_mark.src = "/JavaScripts/img/open_section.png";
    }

    else
    {
        my_sect.style.display = 'none';
	visible[section_id] = 0;
	my_mark.src = "/JavaScripts/img/closed_section.png";
    }
    
    updateFormState();
}


function helpClick ( section_id, e )
{
    if ( !visible[section_id] && !visible['q'+section_id] )
	showHideSection(section_id, 'show');
    
    showHideHelp(section_id);
    
    if ( !e )
	e = window.event;
    e.stopPropagation();
}


function showHideHelp ( help_id, action )
{
    var my_sect = document.getElementById(help_id);
    var my_mark = document.getElementById('q'+help_id);
    
    if ( visible['q'+help_id] && ( action == undefined || action == "hide" ) )
    {
	my_mark.src = "/JavaScripts/img/hidden_help.png";
	visible['q'+help_id] = 0;
	hideByClass( 'help_' + help_id );
    }
    
    else if ( action == undefined || action == "show" )
    {
	my_mark.src = "/JavaScripts/img/visible_help.png";
	visible['q'+help_id] = 1;
	showByClass( 'help_' + help_id );
    }
}


function showHideAdvanced ( action )
{
    if ( visible.advanced && ( action == undefined || action == "hide" ) )
    {
	visible.advanced = 0;
	$('.dlSectionAdvanced').css('display', 'none');
	$('.dlSpanAdvanced').css('display', 'none');
    }
    
    else if ( action == undefined || action == "show" )
    {
	visible.advanced = 1;
	$('.dlSectionAdvanced').css('display', 'block');
	$('.dlSpanAdvanced').css('display', 'inline');
    }
    
    checkInterval(1);
    
    updateFormState();
}


function showOneElement ( selected, prefix, values )
{
    for ( var i = 0; i < values.length; i++ )
    {
	var name = values[i].value;
	
	if ( name == selected )
	    showElement(prefix + name);
	
	else
	    hideElement(prefix + name);
    }
}


// function showHideElement ( id, action )
// {
//     var elt = myGetElement(id);
//     if ( elt == undefined ) return;
    
//     if ( action == 'hide' )
// 	elt.style.display = 'none';
    
//     else if ( action == 'show' )
// 	elt.style.display = '';
    
//     else if ( action != undefined )
// 	elt.style.display = action;
    
//     if ( action == 'hide' )
// 	visible[id] = 0;
    
//     else
// 	visible[id] = 1;
// }


// function showOutputHelp ( do_show )
// {
//     if ( do_show )
//     {
// 	$('.dlBlockDoc').css('display', 'inline');
//     }
    
//     else
//     {
// 	$('.dlBlockDoc').css('display', 'none');
//     }
// }


function updateFormState ( )
{
    updateMainURL();
}


function getRadioValue ( elt_name )
{
    var elt_list = document.getElementsByName(elt_name);
    var i;
    
    if ( ! elt_list.length ) return "";
    
    for ( i=0; i < elt_list.length; i++ )
	if ( elt_list[i].checked ) return elt_list[i].value;
    
    return "";
}


function initFormContents ( )
{
    var content = "";
    
    // First generate the controls for selecting output blocks
    
    content = "<tr><td>\n";
    
    content += makeBlockControl( "od_occs",
				 ["*full", "full", "Includes all boldface blocks (no need to check them separately)",
				  "*attribution", "attr", "Attribution (author and year) of the accepted name",
				  "*classification", "class", "Taxonomic classification of the occurrence",
				  "classification ext.", "classext", "Taxonomic classification including taxon ids",
				  "genus", "genus", "Use instead of the above if you just want the genus",
				  "subgenus", "subgenus", "Use with any of the above to include subgenus as well",
				  "accepted only", "acconly", "Suppress the exact identification of the occurrence, show only accepted name",
				  "ident components", "ident", "Individual components of the identification, rarely needed",
				  "phylopic id", "img", "Identifier of a <a href=\"http://phylopic.org/\" target=\"_blank\">phylopic</a> representing this taxon or the closest containing taxon",
				  "*plant organs", "plant", "Plant organ(s) identified as part of this occurrence, if any",
				  "*abundance", "abund", "Abundance of this occurrence in the collection",
				  "*ecospace", "ecospace", "The ecological space occupied by this organism",
				  "*taphonomy", "taphonomy", "Taphonomy of this organism",
				  "eco/taph basis", "etbasis", "Annotation for ecospace and taphonomy as to taxonomic level",
				  "*preservation", "pres", "Is this occurrence identified as a form taxon, ichnotaxon or regular taxon",
				  "*collection", "coll", "The name and description of the collection in which this occurrence was found",
				  "*coordinates", "coords", "Latitude and longitude of this occurrence",
				  "*location", "loc", "Additional info about the geographic locality",
				  "*paleolocation", "paleoloc", "Paleogeographic locality of this occurrence",
				  "*protection", "prot", "Indicates whether this occurrence is on protected land, i.e. a national park",
				  "stratigraphy", "strat", "Basic stratigraphy of the occurrence",
				  "*stratigraphy ext.", "stratext", "Extended (detailed) stratigraphy of the occurrence",
				  "lithology", "lith", "Basic lithology of the occurrence",
				  "*lithology ext.", "lithext", "Extended (detailed) lithology of the occurrence",
				  "paleoenvironment", "env", "The paleoenvironment associated with this collection",
				  "*geological context", "geo", "Additional info about the geological context (includes env)",
				  "*methods", "methods", "Info about the collection methods used",
				  "research group", "resgroup", "The research group(s) if any associated with the collection",
				  "reference", "ref", "The reference from which this occurrence was entered, as formatted text",
				  "*ref attribution", "refattr", "Author(s) and publication year of the reference",
				  "enterer ids", "ent", "Identifiers of the people who authorized/entered/modified each record",
				  "enterer names", "entname", "Names of the people who authorized/entered/modified each record",
				  "created/modified", "crmod", "Creation and modification timestamps for each record" ]);
    
    content += "</td></tr>\n";
    
    content += makeOutputHelpRow("occs/list");
    
    setInnerHTML("od_occs", content);
    
    content = "<tr><td>\n";
    
    content += makeBlockControl( "od_colls",
				 ["*full", "full", "Includes all boldface blocks (no need to check them separately)",
				  "*location", "loc", "Additional info about the geographic locality",
				  "*paleolocation", "paleoloc", "Paleogeographic locality of this collection",
				  "*protection", "prot", "Indicates whether collection is on protected land",
				  "stratigraphy", "strat", "Basic stratigraphy of the occurrence",
				  "*stratigraphy ext.", "stratext", "Detailed stratigraphy of the occurrence",
				  "lithology", "lith", "Basic lithology of the occurrence",
				  "*lithology ext.", "lithext", "Detailed lithology of the occurrence",
				  "*geological context", "geo", "Additional info about the geological context",
				  "*methods", "methods", "Info about the collection methods used",
				  "research group", "resgroup", "The research group(s) if any associated with this collection",
				  "reference", "ref", "The primary reference associated with this collection, as formatted text",
				  "*ref attribution", "refattr", "Author(s) and publication year of the reference",
				  "all references", "secref", "Identifiers of all references associated with this collection",
				  "enterer ids", "ent", "Identifiers of the people who authorized/entered/modified this record",
				  "enterer names", "entname", "Names of the people who authorized/entered/modified this record",
				  "created/modified", "crmod", "Creation and modification timestamps" ]);
    
    content += "</td></tr>\n";
    
    content += makeOutputHelpRow("colls/list");
    
    setInnerHTML("od_colls", content);
    
    content = "<tr><td>\n";
    
    content += makeBlockControl( "od_specs",
				 ["*full", "full", "Includes all boldface blocks (no need to check them separately)",
				  "*attribution", "attr", "Attribution (author and year) of the accepted taxonomic name",
				  "*classification", "class", "Taxonomic classification of the specimen",
				  "classification ext.", "classext", "Taxonomic classification including taxon ids",
				  "genus", "genus", "Use instead of the above if you just want the genus",
				  "subgenus", "subgenus", "Use with any of the above to include subgenus as well",
				  "*plant organs", "plant", "Plant organ(s) if any",
				  "*abundance", "abund", "Abundance of the occurrence (if any) in its collection",
				  "*collection", "coll", "The name and description of the collection in which the occurrence (if any) was found",
				  "*coordinates", "coords", "Latitude and longitude of the occurrence (if any)",
				  "*location", "loc", "Additional info about the geographic locality of the occurrence (if any)",
				  "*paleolocation", "paleoloc", "Paleogeographic locality of the occurrence (if any)",
				  "*protection", "prot", "Indicates whether source of specimen was on protected land (if known)",
				  "stratigraphy", "strat", "Basic stratigraphy of the occurrence (if any)",
				  "*stratigraphy ext.", "stratext", "Detailed stratigraphy of the occurrence (if any)",
				  "lithology", "lith", "Basic lithology of the occurrence (if any)",
				  "*lithology ext.", "lithext", "Detailed lithology of the occurrence (if any)",
				  "*geological context", "geo", "Additional info about the geological context (if known)",
				  "*methods", "methods", "Info about the collection methods used (if known)",
				  "remarks", "rem", "Additional remarks about the associated collection (if any)",
				  "resgroup", "resgroup", "The research group(s) if any associated with this collection",
				  "reference", "ref", "The reference from which this specimen was entered, as formatted text",
				  "*ref attribution", "refattr", "Author(s) and publication year of the reference",
				  "enterer ids", "ent", "Identifiers of the people who authorized/entered/modified this record",
				  "enterer names", "entname", "Names of the people who authorized/entered/modified this record",
				  "created/modified", "crmod", "Creation and modification timestamps" ]);
    
    content += "</td></tr>\n";
    
    content += makeOutputHelpRow("specs/list");
    
    setInnerHTML("od_specs", content);
    
    content = "<tr><td>\n";
    
    content += makeBlockControl( "od_taxa",
				 ["*full", "full", "Includes all boldface blocks (no need to check them separately)",
				  "*attribution", "attr", "Attribution (author and year) of this taxonomic name",
				  "*common", "common", "Common name (if any)",
    				  "*age range overall", "app", "Ages of first and last appearance among all occurrences in this database",
				  "age range selected", "occapp", "Ages of first and last appearance among selected occurrences",
				  "*parent", "parent", "Name and identifier of parent taxon",
				  "immediate parent", "immparent", "Name and identifier of immediate parent taxon (may be a junior synonym)",
    				  "*size", "size", "Number of subtaxa",
				  "*classification", "class", "Taxonomic classification: phylum, class, order, family, genus",
				  "classification ext.", "classext", "Taxonomic classification including taxon ids",
				  "*subtaxon counts", "subcounts", "Number of genera, families, and orders contained in this taxon",
				  "*ecospace", "ecospace", "The ecological space occupied by this organism",
				  "*taphonomy", "taphonomy", "Taphonomy of this organism",
				  "eco/taph basis", "etbasis", "Annotation for ecospace and taphonomy as to taxonomic level",
				  "*preservation", "pres", "Is this a form taxon, ichnotaxon or regular taxon",
				  "sequence numbers", "seq", "The sequence numbers of this taxon in the computed tree",
				  "phylopic id", "img", "Phylopic identifier",
				  "reference", "ref", "The reference from which this taxonomic name was entered, as formatted text",
				  "*ref attribution", "refattr", "Author(s) and publication year of the reference",
				  "enterer ids", "ent", "Identifiers of the people who authorized/entered/modified this record",
				  "enterer names", "entname", "Names of the people who authorized/entered/modified this record",
				  "created/modified", "crmod", "Creation and modification timestamps" ]);
    
    content += "</td></tr>\n";
    
    content += makeOutputHelpRow("taxa/list");
    
    setInnerHTML("od_taxa", content);
    
    content = "<tr><td>\n";
    
    content += makeBlockControl( "od_ops",
    				 ["*full", "full", "Includes all boldface blocks (no need to check them separately)",
				  "*basis", "basis", "Basis of this opinion, i.e. 'stated with evidence'",
				  "reference", "ref", "The reference from which this opinion was entered, as formatted text",
				  "*ref attribution", "refattr", "Author(s) and publication year of the reference",
				  "enterer ids", "ent", "Identifiers of the people who authorized/entered/modified this record",
				  "enterer names", "entname", "Names of the people who authorized/entered/modified this record",
				  "created/modified", "crmod", "Creation and modification timestamps" ]);
   
    content += "</td></tr>\n";
    
    content += makeOutputHelpRow("opinions/list");
    
    setInnerHTML("od_ops", content);
    
    content = "<tr><td>\n";
    
    content += makeBlockControl( "od_strata",
    				 ["coordinates", "coords", "Latitude and longitude range of occurrences",
				  "gplates", "gplates", "Tectonic plate identifiers (GPlates model) associated with occurrences from this stratum",
				  "splates", "splates", "Tectonic plate identifiers (Scotese model) associated with occurrences from this stratum" ]);
    
    content += "</td></tr>\n";
    
    content += makeOutputHelpRow("strata/list");
    
    setInnerHTML("od_strata", content);
    
    content = "<tr><td>\n";
    
    content += makeBlockControl( "od_refs",
    				 ["associated counts", "counts", "Counts of authorities, opinions, occurrences, collections associated with this reference",
				  "formatted", "formatted", "Return a single formatted string instead of individual fields",
				  "both", "both", "Return a single formatted string AND the individual fields",
				  "comments", "comments", "Comments entered about this reference, if any",
				  "enterer ids", "ent", "Identifiers of the people who authorized/entered/modified this record",
				  "enterer names", "entname", "Names of the people who authorized/entered/modified this record",
				  "created/modified", "crmod", "Creation and modification timestamps" ]);
   
    content += "</td></tr>\n";
    
    content += makeOutputHelpRow("refs/list");
    
    setInnerHTML("od_refs", content);
    
    // Then the controls for selecting output order
    
    content = makeOptionList( [ '--', 'default', 'earlyage', 'max_ma', 'lateage', 'min_ma',
				'taxon', 'taxonomic hierarchy',
				'formation', 'geological formation', 'plate', 'tectonic plate',
				'created', 'creation date of record',
				'modified', 'modification date of record' ] );
    
    setInnerHTML("pm_occs_order", content);
    
    setInnerHTML("pm_colls_order", content);
    
    content = makeOptionList( [ '--', 'default', 'hierarchy', 'taxonomic hierarchy',
				'name', 'taxonomic name (alphabetical)', 
				'ref', 'bibliographic reference',
				'firstapp', 'first appearance', 'lastapp', 'last appearance',
				'n_occs', 'number of occurrences',
				'authpub', 'author of name, year of publication',
				'pubauth', 'year of publication, author of name',
				'created', 'creation date of record',
				'modified', 'modification date of record' ] );
    
    setInnerHTML("pm_taxa_order", content);
    
    content = makeOptionList( [ '--', 'default', 'hierarchy', 'taxonomic hierarchy',
				'name', 'taxonomic name (alphabetical)', 
				'ref', 'bibliographic reference',
				'authpub', 'author of opinion, year of publication',
				'pubauth', 'year of publication, author of opinion',
				'basis', 'basis of opinion',
				'created', 'creation date of record',
				'modified', 'modification date of record' ] );
    
    setInnerHTML("pm_ops_order", content);
    
    content = makeOptionList( [ '--', 'default', 'authpub', 'author of reference, year of publication',
				'pubauth', 'year of publication, author of reference',
				'reftitle', 'title of reference',
				'pubtitle', 'title of publication',
				'created', 'creation date of record',
				'modified', 'modification date of record' ] );
    
    setInnerHTML("pm_refs_order", content);
    
    // Then generate various option lists.
    
    var continents = pbdb_data.continents || ['ERROR', 'An error occurred'];
    
    content = makeOptionList( [ '--', '--', '**', 'Multiple' ].concat(continents) );
    
    setInnerHTML("pm_continent", content);
    
    content = makeCheckList( "pm_continents", continents, 'checkCC()' );
    
    setInnerHTML("pd_continents", content);
    
    var countries = pbdb_data.countries || ['ERROR', 'An error occurred'];
    
    content = makeOptionList( ['--', '--', '**', 'Multiple'].concat(countries) );
    
    setInnerHTML("pm_country", content);
    
    var crmod_options = [ 'created_after', 'created after',
			  'created_before', 'created before',
			  'modified_after', 'modified after',
			  'modified_before', 'modified before' ];
    
    content = makeOptionList( crmod_options );
    
    setInnerHTML("pm_occs_crmod", content);
    setInnerHTML("pm_colls_crmod", content);
    setInnerHTML("pm_taxa_crmod", content);
    setInnerHTML("pm_ops_crmod", content);
    setInnerHTML("pm_refs_crmod", content);
    
    var authent_options = [ 'authent_by', 'authorized/entered by',
			    'authorized_by', 'authorized by',
			    'entered_by', 'entered by',
			    'modified_by', 'modified by',
			    'touched_by', 'touched by' ];
    
    content = makeOptionList( authent_options );
    
    setInnerHTML("pm_occs_authent", content);
    setInnerHTML("pm_colls_authent", content);
    setInnerHTML("pm_taxa_authent", content);
    setInnerHTML("pm_ops_authent", content);
    setInnerHTML("pm_refs_authent", content);

    var envtype_options = [ 'terr', 'terrestrial',
			    'marine', 'any marine',
			    'carbonate', 'carbonate',
			    'silicic', 'siliciclastic',
			    'unknown', 'unknown' ];
    
    content = makeCheckList( "pm_envtype", envtype_options, 'checkEnv()' );
    
    setInnerHTML("pd_envtype", content);
    
    var envzone_options = [ 'lacust', 'lacustrine', 'fluvial', 'fluvial',
			    'karst', 'karst', 'terrother', 'terrestrial other',
			    'marginal', 'marginal marine', 'reef', 'reef',
			    'stshallow', 'shallow subtidal', 'stdeep', 'deep subtidal',
			    'offshore', 'offshore', 'slope', 'slope/basin',
			    'marindet', 'marine indet.' ];
    
    content = makeCheckList( "pm_envzone", envzone_options, 'checkEnv()' );
    
    setInnerHTML("pd_envzone", content);
    
    var reftypes = [ '+auth', 'authority references', '+class', 'classification references',
		     'ops', 'all opinion references', 'occs', 'occurrence references',
		     'specs', 'specimen references', 'colls', 'collection references' ];
    
    content = makeCheckList( "pm_reftypes", reftypes, 'checkRefopts()' );
    
    setInnerHTML("pd_reftypes", content);
    
    params.reftypes = 'taxonomy';
    
    // We need to execute the following operation here, because the
    // spans to which it applies are created by the code above.
    
    hideByClass('help_o1');
    
    // Then collect the database user names, which are part of the form from the earlier version.
    
    setDBUserNames();
}


function makeBlockControl ( section_name, block_list )
{
    var content = "";
    
    for ( var i = 0; i < block_list.length; i += 3 )
    {
	var block_name = block_list[i];
	var block_code = block_list[i+1];
	var block_doc = block_list[i+2];
	var attrs = '';
	var asterisked = 0;
	
	if ( block_name.indexOf('*') == 0 )
	{
	    asterisked = 1;
	    block_name = block_name.slice(1);
	}
	
	// if ( block_name == "full" )
	// {
	//     attrs = 'checked="1"';
	// }
	
	content = content + '<span class="dlBlockLabel"><input type="checkbox" name="' + 
	    section_name + '" value="' + block_code + '" ';
	content = content + attrs + ' onClick="updateFormState()">';
	content += asterisked ? '<b>' + block_name + '</b>' : block_name;
	content += '</span><span class="vis_help_o1">' + block_doc + "<br/></span>\n";
    }
    
    return content;
}


function makeCheckList ( list_name, options, ui_action )
{
    var content = '';
    
    for ( i=0; i < options.length / 2; i++ )
    {
	var code = options[2*i];
	var label = options[2*i+1];
	var attrs = '';
	var checked = false;
	
	if ( code.substr(0,1) == '+' )
	{
	    code = code.substr(1);
	    checked = true;
	}
	
	content += '<span class="dlCheckBox"><input type="checkbox" name="' + list_name + '" value="' + code + '" ';
	if ( checked ) content += 'checked="1" ';
	content += attrs + 'onClick="' + ui_action + '">' + label + "</span>\n";
    }
    
    return content;
}


function makeOptionList ( options )
{
    var content = '';
    var i;
    
    for ( i=0; i < options.length / 2; i++ )
    {
	var code = options[2*i];
	var label = options[2*i+1];
	
	content += '<option value="' + code + '">' + label + "</option>\n";
    }
    
    return content;
}


function makeOutputHelpRow ( path )
{
    var content = '<tr class="dlHelp vis_help_o1"><td>' + "\n";
    content += "<p>You can get more information about these output blocks and fields ";
    content += '<a target="_blank" href="' + base_data_url + path + '#response" ';
    content += 'style="text-decoration: underline">here</a>.</p>';
    content += "\n</td></tr>";
    
    return content;
}


function setInnerHTML ( id, content )
{
    var elt = document.getElementById(id);
    
    if ( elt == undefined )
    {
	console.log("ERROR: unknown element '" + id + "'");
	return;
    }
    
    if ( typeof(content) != "string" )
	elt.innerHTML = "";
    else
	elt.innerHTML = content;
}


function setDBUserNames ( )
{
    if ( ! user_names )	user_names = entererNames();
    
    for ( var i = 0; i < user_names.length; i++ )
    {
	var match;
	
	if ( match = user_names[i].match(patt_name) )
	{
	    valid_name[match[1]] = 1;
	    var rebuilt = match[2].substr(0,1) + '. ' + match[1];
	    valid_name[rebuilt] = 1;
	    user_names[i] = rebuilt;
	    user_match[i] = match[1].toLowerCase();
	    user_matchinit[i] = match[2].substr(0,1).toLowerCase();
	}
	
	else if ( match = user_names[i].match(patt_name2) )
	{
	    valid_name[match[2]] = 1;
	    var rebuilt = match[1].substr(0,1) + '. ' + match[2];
	    valid_name[rebuilt] = 1;
	    user_names[i] = rebuilt;
	    user_match[i] = match[2].toLowerCase();
	    user_matchinit[i] = match[1].substr(0,1).toLowerCase();
	}
    }
}


function setErrorMessage ( id, messages )
{
    if ( messages == undefined || messages == "" || messages.length == 0 )
    {
	setInnerHTML(id, "");
	hideElement(id);
    }
    
    else
    {
	var err_msg = messages.join("</li><li>") || "Error";
	setInnerHTML(id, "<li>" + err_msg + "</li>");
	showElement(id);
    }
}


function setDisabled ( id, disabled )
{
    var elt = document.getElementById(id);
    
    if ( elt == undefined )
    {
	console.log("ERROR: unknown element '" + id + "'");
	return;
    }
    
    elt.disabled = disabled;
}


function myGetElement ( id )
{
    var elt = document.getElementById(id);
    
    if ( elt == undefined )
    {
	console.log("ERROR: unknown element '" + id + "'");
	return undefined;
    }
    
    else return elt;
}


function getElementValue ( id )
{
    var elt = document.getElementById(id);
    
    if ( elt == undefined )
    {
	console.log("ERROR: unknown element '" + id + "'");
	return "";
    }
    
    else if ( elt.type && elt.type == "checkbox" )
	return elt.checked;
    
    else
	return elt.value;
}


function clearElementValue ( id )
{
    var elt = document.getElementById(id);

    if ( elt == undefined )
	console.log("ERROR: unknown element '" + id + "'");

    else if ( elt.type && elt.type == "checkbox" )
	elt.checked = 0;

    else
	elt.value = "";
}


function hideElement ( id )
{
    var elt = myGetElement(id);
    if ( elt == undefined ) return;
    elt.style.display = 'none';
    visible[id] = 0;
}


function showElement ( id, display )
{
    var elt = myGetElement(id);
    if ( elt == undefined ) return;
    elt.style.display = ( display || '' );
    visible[id] = 1;
}


function checkTaxon ( )
{
    var base_name = getElementValue("pm_base_name");
    params.ident = getElementValue("pm_ident");
    params.pres = getElementValue("pm_pres");
    
    base_name = base_name.replace(/[\s,]*,[\s,]*/g, ", ");
    base_name = base_name.replace(/\^\s*/g, " ^");
    base_name = base_name.replace(/\^[\s^]*/g, "^");
    base_name = base_name.replace(/[\s^]*\^,[\s,]*/g, ", ");
    base_name = base_name.replace(/[^a-zA-Z:]+$/, "");
    
    if ( base_name == params.base_name )
    {
	updateFormState(); // value of base_name has not changed
    }
    
    else if ( base_name == "" )
    {
	params.base_name = "";
	param_errors.base_name = 0;
	setErrorMessage("pe_base_name", "");
	updateFormState();
    }
    
    else
    {
	params.base_name = base_name;
	$.getJSON(base_data_url + 'taxa/list.json?name=' + base_name).done(callBackBaseName);
    }
}


function checkTaxonStatus ( changed )
{
    var status_box = myGetElement("pm_acc_only");
    var status_selector = myGetElement("pm_taxon_status");
    var variant_selector = myGetElement("pm_taxon_variants");
    
    if ( ! status_box || ! status_selector || ! variant_selector ) return;
    
    if ( changed == 'box' )
    {
        if ( status_box.checked )
        {
            taxon_status_save = status_selector.value;
            status_selector.value = "accepted";
            taxon_box_save = true;
            variant_selector.checked = false;
        }
        
        else
        {
            status_selector.value = taxon_status_save;
            taxon_box_save = false;
        }
    }
    
    else if ( changed == 'selector' )
    {
        taxon_status_save = status_selector.value;
        if ( status_selector.value != "accepted" )
            status_box.checked = false;
    }
    
    else
    {
        if ( variant_selector.checked )
            status_box.checked = false;
    }
    
    updateFormState();
}


function callBackBaseName ( response )
{
    var err_elt = document.getElementById("pe_base_name");
    
    if ( response.warnings )
    {
	var err_msg = response.warnings.join("</li><li>") || "Warnings occurred";
	err_elt.innerHTML = "<li>" + err_msg + "</li>";
	param_errors.base_name = 1;
    }
    
    else if ( response.errors )
    {
	var err_msg = response.errors.join("</li><li>") || "Errors occurred";
	err_elt.innerHTML = "<li>" + err_msg + "</li>";
	param_errors.base_name = 1;
    }
    
    else
    {
	err_elt.innerHTML = "";
	param_errors.base_name = 0;
    }
    
    updateFormState();
}


function checkInterval ( select )
{
    // $$$ fix this to deal with combined interval/ma fields
    
    var int_age_1 = getElementValue("pm_interval");
    var int_age_2 = getElementValue("pm_interval_2");
    
    var errors = [ ];
    
    params.timerule = getElementValue("pm_timerule");
    params.timebuffer = getElementValue("pm_timebuffer");
    
    // First check the values in the two interval fields.  Check for both numeric values and
    // interval names.  If the two are incompatible, clear the one not specified by the parameter
    // 'select'.
    
    if ( int_age_1 == "" )
    {
	params.interval = "";
	params.ma_max = "";
    }
    
    else
    {
	if ( patt_dec_pos.test(int_age_1) )
	{
	    params.ma_max = int_age_1;
	    params.interval = "";
	    
	    if ( select && select == 1 && !patt_has_digit.test(int_age_2) )
	    {
		clearElementValue("pm_interval_2");
		int_age_2 = "";
	    }
	}
	
	else if ( patt_has_digit.test(int_age_1) )
	    errors.push("The string '" + int_age_1 + "' is not a valid age or interval");
	
	else if ( validInterval(int_age_1) )
	{
	    params.ma_max = "";
	    params.interval = int_age_1;
	    
	    if ( select && select == 1 && patt_has_digit.test(int_age_2) )
	    {
		clearElementValue("pm_interval_2");
		int_age_2 = "";
	    }
	}
	
	else
	    errors.push("The interval '" + int_age_1 + "' was not found in the database");
    }
    
    if ( int_age_2 == "" )
    {
	params.interval2 = "";
	params.ma_min = "";
    }
    
    else
    {
	if ( patt_dec_pos.test(int_age_2) )
	{
	    params.ma_min = int_age_2;
	    params.interval2 = "";
	    
	    if ( select && select == 2 && !patt_has_digit.test(int_age_1) )
	    {
		clearElementValue("pm_interval");
		params.ma_max = "";
		params.interval = "";
	    }
	}
	
	else if ( patt_has_digit.test(int_age_2) )
	    errors.push("The string '" + int_age_2 + "' is not a valid age or interval");
	
	else if ( validInterval(int_age_2) )
	{
	    params.ma_min = "";
	    params.interval2 = int_age_2;
	    
	    if ( select && select == 2 && patt_has_digit.test(int_age_1) )
	    {
		clearElementValue("pm_interval");
		params.ma_max = "";
		params.interval = "";
	    }
	}
	
	else
	    errors.push("The interval '" + int_age_2 + "' was not found in the database");
    }
    
    if ( params.ma_max && params.ma_min && Number(params.ma_max) < Number(params.ma_min) )
    {
	errors.push("You must specify the maximum age on the left and the minimum on the right");
    }
    
    if ( visible.advanced )
    {
	if ( params.timerule == 'buffer' && params.timebuffer != "" && ! patt_dec_pos.test(params.timebuffer) )
	    errors.push("invalid value '" + params.timebuffer + "' for timebuffer");
    }
    
    // Adjust the error message field and flag.
    
    if ( errors.length )
    {
	param_errors.interval = 1;
	setErrorMessage("pe_interval", errors);
    }
    
    else
    {
	param_errors.interval = 0;
	setErrorMessage("pe_interval", "");
    }
    
    // Adjust visibility of controls
    
    if ( params.timerule == 'buffer' )
	showElement('pd_timebuffer');
    
    else
	hideElement('pd_timebuffer');
    
    // Update the form state
    
    updateFormState();
}


function validInterval ( interval_name )
{
    if ( typeof interval_name != "string" )
	return false;
    
    if ( pbdb_data.interval[interval_name.toLowerCase()] )
	return true;
    
    else
	return false;
}


function callBackInterval ( response )
{
    var err_elt = document.getElementById("interval_error");
    
    if ( response.warnings && response.warnings.length )
    {
	setErrorMessage("pe_interval", response.warnings);
	// var err_msg = response.warnings.join("</li><li>") || "Warnings occurred";
	// err_elt.innerHTML = "<li>" + err_msg + "</li>";
	param_errors.interval = 1;
    }
    
    else if ( response.errors && response.errors.length )
    {
	setErrorMessage("pe_interval", response.errors);
	// var err_msg = response.errors.join("</li><li>") || "Errors occurred";
	// err_elt.innerHTML = "<li>" + err_msg + "</li>";
	param_errors.interval = 1;
    }
    
    else
    {
	setErrorMessage("pe_interval", "");
	param_errors.interval = 0;
    }
    
    updateFormState();
}


function checkCC ( )
{
    var continent_select = getElementValue("pm_continent");
    // var multiple_div = document.getElementById("pd_continents");
    if ( continent_select == '**' || continent_select == '^^' ) showByClass('mult_cc3');
    else hideByClass('mult_cc3');
    
    var country_select = getElementValue("pm_country");
    // multiple_div = document.getElementById("pd_countries");
    if ( country_select == '**' ) showByClass('mult_cc2');
    else hideByClass('mult_cc2');
    
    var continent_list = '';
    var country_list = '';
    var errors = [];
    var cc_ex = getElementValue("pm_ccex");
    var cc_mod = getElementValue("pm_ccmod");
    
    // var cc_exclude = '';
    // if ( cc_ex == "exclude" ) cc_exclude = '^';
    
    // Check continents
    
    if ( continent_select && continent_select != '--' && continent_select != '**' &&
	 continent_select != '^^' )
	continent_list = continent_select;
    
    else if ( continent_select && ( continent_select == '**' || continent_select == '^^' ) )
    {
	continent_list = getCheckList("pm_continents");
	
	// if ( continent_list )
	//     cc_list1.push(continent_list);
    }
    
    // Check countries
    
    // if ( cc_mod == 'sub' && ( cc_list.length || ! cc_exclude ) )
    // 	cc_exclude = '^';
    
    if ( country_select && country_select != '--' && country_select != '**' )
    {
	country_list = country_select;
	
	if ( cc_mod == "sub" ) country_list = '^' + country_list;
    }
    
    else if ( country_select && country_select == '**' )
    {
	country_list = getElementValue("pm_countries");
	
	// var match = ( /^\^(.*)/.exec(country_list) )
	// var cc_exclude = ''
	
	// if ( match != null )
	// {
	//     country_list = match[1];
	//     cc_exclude = '^';
	// }
	
	if ( country_list != '' )
	{
	    var cc_list = [ ];
	    var values = country_list.split(/[\s,]+/);
	    
	    for ( var i=0; i < values.length; i++ )
	    {
		var canonical = values[i].toUpperCase();
		var key = canonical.replace(/^\^/,'');
		
		if ( key == '' ) next;
		
		if ( cc_mod == "sub" ) canonical = "^" + key;
		
		if ( pbdb_data.country_name[key] || pbdb_data.continent_name[key] )
		    cc_list.push(canonical);
		
		else
		    errors.push("Unknown country code '" + key + "'");
		
		// cc_exclude = '';
	    }
	    
	    country_list = cc_list.join(',');
	}
    }
    
    params.cc = '';
    
    if ( country_list != '' || continent_list != '' )
    {
	var prefix = '';
	if ( cc_ex == "exclude" ) prefix = '!';
	
	if ( continent_list != '' && country_list != '' )
	    params.cc = prefix + continent_list + ',' + country_list;
	
	else
	    params.cc = prefix + continent_list + country_list;
    }
    
    // if ( cc_list.length )
    // 	params.cc = cc_list.join(',');
    // else
    // 	params.cc = '';
    
    // Check plates
    
    var plate_list = getElementValue("pm_plate");
    var plate_model = getElementValue("pm_pgmodel");
    
    if ( plate_list != '' )
    {
	var match = ( /^\^(.*)/.exec(plate_list) )
	var plate_exclude = '';
	
	if ( match != null )
	{
	    plate_list = match[1];
	    plate_exclude = '^';
	}
	
	var values = plate_list.split(/[\s,]+/);
	var value_list = [ ];
	
	for ( var i=0; i < values.length; i++ )
	{
	    var value = values[i];
	    if ( value == '' ) next;
	    
	    if ( /^[0-9]+$/.test(value) )
		value_list.push(value);
	    else
		errors.push("Invalid plate number '" + value + "'");
	}
	
	if ( value_list.length )
	    params.plate = plate_exclude + plate_model + value_list.join(',');
	else
	    params.plate = '';
    }
    
    else
	params.plate = '';
    
    // If there are any errors, show them.  Otherwise, clear the error indicator
    
    if ( errors.length )
    {
	setErrorMessage("pe_cc", errors);
	param_errors.cc = 1;
    }
    
    else
    {
	setErrorMessage("pe_cc", "");
	param_errors.cc = 0;
    }
    
    updateFormState();
}


function checkCoords ( )
{
    var latmin = getElementValue('pm_latmin');
    var latmax = getElementValue('pm_latmax');
    var lngmin = getElementValue('pm_lngmin');
    var lngmax = getElementValue('pm_lngmax');
    var errors = [];
    
    // Check for valid values in the coordinate fields
    
    if ( latmin == '' || validCoord(latmin, 'ns') ) params.latmin = cleanCoord(latmin);
    else {
	params.latmin = '';
	errors.push("invalid value '" + latmin + "' for minimum latitude");
    }
    
    if ( latmax == '' || validCoord(latmax, 'ns') ) params.latmax = cleanCoord(latmax);
    else {
	params.latmax = '';
	errors.push("invalid value '" + latmax + "' for maximum latitude");
    }
    
    if ( lngmin == '' || validCoord(lngmin, 'ew') ) params.lngmin = cleanCoord(lngmin);
    else {
	params.lngmin = '';
	errors.push("invalid value '" + lngmin + "' for minimum longitude");
    }
    
    if ( lngmax == '' || validCoord(lngmax, 'ew') ) params.lngmax = cleanCoord(lngmax);
    else {
	params.lngmax = '';
	errors.push("invalid value '" + lngmax + "' for maximum longitude");
    }
    
    // If only one longitude coordinate is filled in, ignore the other one.
    
    if ( lngmin && ! lngmax || lngmax && ! lngmin )
    {
	errors.push("you must specify both longitude values if you specify one of them");
    }
    
    // If any of the parameters are in error, display the message and flag the error condition.
    
    if ( errors.length )
    {
	setErrorMessage('pe_coords', errors);
	param_errors.coords = 1;
    }
    else
    {
	// If the longitude coordinates are reversed, note that fact.
	
	if ( params.lngmin != '' && params.lngmax != '' &&
	     coordsAreReversed(params.lngmin, params.lngmax) )
	{
	    message = [ "Note: the longitude coordinates are reversed.  " +
			"This will select a strip stretching the long way around the earth." ]
	    setErrorMessage('pe_coords', message );
	}
	else setErrorMessage('pe_coords', null);
	
	// Clear the error flag in any case.
	
	param_errors.coords = 0;
    }
    
    // Update the main URL to reflect the changed coordinates.
    
    updateFormState();
}


function validCoord ( coord, dir )
{
    if ( coord == undefined )
	return false;
    
    if ( patt_dec_num.test(coord) )
	return true;
    
    if ( dir == 'ns' && /^(\d+[.]\d*|\d*[.]\d+|\d+)[ns]$/i.test(coord) )
	return true;
    
    if ( dir === 'ew' && /^(\d+[.]\d*|\d*[.]\d+|\d+)[ew]$/i.test(coord) )
	return true;
    
    return false;
}


function cleanCoord ( coord )
{
    if ( coord == undefined || coord == '' )
	return '';
    
    if ( /^[+-]?(\d+[.]\d*|\d*[.]\d+|\d+)$/.test(coord) )
	return coord;
    
    if ( /^(\d+[.]\d*|\d*[.]\d+|\d+)[sw]$/i.test(coord) )
	return '-' + coord.replace(/[nsew]/i, '');
    
    else
	return coord.replace(/[nsew]/i, '');
}


function coordsAreReversed ( min, max )
{
    // First convert the coordinates into signed integers.
    
    var imin = Number(min);
    var imax = Number(max);
    
    return ( imax - imin > 180 || ( imax - imin < 0 && imax - imin > -180 ));
}


function checkStrat ( )
{
    var strat = document.getElementById("pm_strat").value;
    
    if ( strat && /[a-z]/i.test(strat) )
    {
	params.strat = strat;
	$.getJSON(base_data_url + 'strata/list.json?limit=0&rowcount&name=' + strat).done(callBackStrat);
    }
    
    else
    {
	params.strat = "";
	param_errors.strat = 0;
	setErrorMessage("pe_strat", "");
	updateFormState();
    }
}


function callBackStrat  ( response )
{
    if ( response.records_found )
    {
	setErrorMessage("pe_strat", null);
	param_errors.strat = 0;
    }
    
    else
    {
	setErrorMessage("pe_strat", [ "no matching strata were found in the database" ]);
	param_errors.strat = 1;
    }
    
    updateFormState();
}


function checkEnv ( )
{
    var env_ex = getElementValue("pm_envex");
    var env_mod = getElementValue("pm_envmod");
    var env_type = getCheckList("pm_envtype");
    var env_zone = getCheckList("pm_envzone");
    
    if ( env_ex && env_ex == "exclude" )
	env_type = "!" + env_type;
    
    if ( env_mod && env_mod == "sub" )
	env_zone = "^" + env_zone.replace(/,/g, ',^');
    
    if ( env_zone )
	env_type += ',' + env_zone;
    
    params.envtype = env_type;
    
    updateFormState();
}


function checkMeta ( section )
{
    var datepattern = /^(\d+[mshdMY]|\d\d\d\d(-\d\d(-\d\d)?)?)$/;
    var errors = [];
    
    var crmod_elt = myGetElement("pm_" + section + "_crmod");
    var cmdate_elt = myGetElement("pm_" + section + "_cmdate");
    if ( crmod_elt == undefined || cmdate_elt == undefined ) return;
    
    var datetype = section + "_crmod";
    var datefield = section + "_cmdate";
    var datevalue = cmdate_elt.value;
    
    if ( datevalue && datevalue != '' )
    {
	params[datetype] = crmod_elt.value;
	params[datefield] = datevalue;
	
	if ( ! datepattern.test(datevalue) )
	{
	    param_errors[datefield] = 1;
	    errors.push("Bad value '" + datevalue + "'");
	}
    }
    
    else
    {
	params[datetype] = crmod_elt.value;
	params[datefield] = "";
	param_errors[datefield] = 0;
    }
    
    var authent_elt = myGetElement("pm_" + section + "_authent");
    var aename_elt = myGetElement("pm_" + section + "_aename");
    if ( authent_elt == undefined || aename_elt == undefined ) return;
    
    var nametype = section + "_authent";
    var namefield = section + "_aename";
    var namevalue = aename_elt.value.trim();
    var rebuild = [ ];
    var exclude = '';
    
    if ( namevalue && namevalue != '' )
    {
	param_errors[namefield] = 0;
	
	// If the value starts with !, we have an exclusion.  Pull it
	// out and save for the end when we are rebuilding the value
	// string.
	
	var expr = namevalue.match(/^!\s*(.*)/);
	if ( expr )
	{
	    namevalue = expr[1];
	    exclude = '!';
	}
	
	var names = namevalue.split(/,\s*/);
	for ( var i = 0; i < names.length; i++ )
	{
	    // Skip empty names, i.e. repeated commas.
	    
	    if ( ! names[i] ) continue;
	    
	    // If we cannot find the name, then search through all of
	    // the known names to try for a match.
	    
	    if ( ! valid_name[names[i]] )
	    {
		var check = names[i].toLowerCase();
		var init = '';
		var subs;
		
		if ( subs = names[i].match(/^(\w)\w*[.]\s*(.*)/) )
		{
		    init = subs[1].toLowerCase();
		    check = subs[2].toLowerCase();
		}
		
		var matches = [];
		
		for ( var j = 0; j < user_match.length; j++ )
		{
		    if ( check == user_match[j].substr(0,check.length) )
		    {
			if ( init == '' || init == user_matchinit[j] )
			    matches.push(j);
		    }
		}
		
		if ( matches.length == 0 )
		{
		    param_errors[namefield] = 1;
		    errors.push("Unknown name '" + names[i] + "'");
		    rebuild.push(names[i]);
		}
		
		else if ( matches.length > 1 )
		{
		    param_errors[namefield] = 1;
		    
		    var result = user_names[matches[0]];
		    
		    for ( var k = 1; k < matches.length; k++ )
		    {
			result = result + ", " + user_names[matches[k]];
		    }
		    
		    errors.push("Ambiguous name '" + names[i] + "' matches: " + result);
		    rebuild.push(names[i]);
		}
		
		else
		{
		    rebuild.push(user_names[matches[0]]);
		}
	    }
	    
	    else
	    {
		rebuild.push(names[i]);
	    }
	}
	
	params[nametype] = authent_elt.value;
	params[namefield] = exclude + rebuild.join(',');
	aename_elt.value = exclude + rebuild.join(', ');
    }
    
    else
    {
	params[nametype] = authent_elt.value;
	params[namefield] = "";
	param_errors[namefield] = 0;
    }
    
    if ( errors.length ) setErrorMessage("pe_meta_" + section, errors);
    else setErrorMessage("pe_meta_" + section, null);
    
    // Now check for reference selection fields
    
    // That will have to wait until later...

    updateFormState();
}


function checkMetaText ( elt_name )
{
    var elt_value = getElementValue( 'pm_' + elt_name );
    
    if ( elt_value && elt_value != '' )
	params[elt_name] = elt_value;
    
    else
    {
	params[elt_name] = '';
	param_errors[elt_name] = 0;
    }
    
    updateFormState();
}


function checkRef ( )
{
    var ref_select = myGetElement("pm_ref_select");
    
    if ( ref_select )
    {
	var selected = ref_select.value;
	if ( selected == "ref_primary" ) select = "ref_author";
	
	showOneElement(selected, 'pm_', ref_select.options);
    }
}


function checkOutputOpts ( )
{
    var metadata_elt = myGetElement("pm_output_metadata");
    params.output_metadata = metadata_elt.checked;
    
    updateFormState();
}


function checkOrder ( selection )
{
    if ( selection && selection != 'dir' )
    {
	var order_elt = myGetElement("pm_order_dir");
	if ( order_elt ) order_elt.value = '--';
    }
    
    updateFormState();
}


function checkRefopts ( )
{
    params.reftypes = getCheckList("pm_reftypes");
    if ( params.reftypes == "auth,class" ) params.reftypes = 'taxonomy';
    else if ( params.reftypes == "auth,class,ops" ) params.reftypes = 'auth,ops';
    else if ( params.reftypes == "auth,class,ops,occs,colls" ) params.reftypes = 'all'
    else if ( params.reftypes == "auth,ops,occs,colls" ) params.reftypes = 'all'
    updateFormState();
}


function checkLimit ( )
{
    var limit = getElementValue("pm_limit");
    
    if ( limit == "" )
    {
	param_errors.limit = 0;
	params.offset = '';
	params.limit = '';
	setErrorMessage("pe_limit", "");
	updateFormState();
	return;
    }
    
    var matches = limit.match(/^\s*(\d+)(\s*,\s*(\d+))?\s*$/);
    
    if ( matches )
    {
	param_errors.limit = 0;
	setErrorMessage("pe_limit", "");
	
	if ( matches[3] )
	{
	    params.offset = matches[1];
	    params.limit = matches[3];
	}
	
	else
	{
	    params.offset = '';
	    params.limit = matches[1];
	}
    }
    
    else
    {
	param_errors.limit = 1;
	params.offset = 'x';
	params.limit = 'x';
	setErrorMessage("pe_limit", ["Invalid limit '" + limit + "'"]);
    }

    updateFormState();
}


function getCheckList ( list_name )
{
    var elts = document.getElementsByName(list_name);
    var i;
    var selected = [];
    
    for ( i=0; i < elts.length; i++ )
    {
	if ( elts[i].checked ) selected.push(elts[i].value);
    }
    
    return selected.join(',');
}


function updateMainURL ( )
{
    var param_list = [];
    var has_main_param = 0;
    var errors_found = 0;
    var occs_required = 0;
    var taxon_required = 0;
    var all_required = 0;
    var my_op = data_op;
    
    if ( visible.f1 )		// select by taxon
    {
	if ( params.base_name && params.base_name != "" ) {
	    param_list.push("base_name=" + params.base_name);
	    has_main_param = 1;
	    taxon_required = 1;
	}
	
	if ( param_errors.base_name ) errors_found = 1;
	
	if ( data_type == "occs" || data_type == "colls" || data_type == "strata" )
	{
	    var taxonres = getElementValue("pm_taxon_reso");
	    if ( taxonres && taxonres != "" )
		param_list.push("taxon_reso=" + taxonres);
	    
	    if ( visible.advanced && params.ident && params.ident != 'latest' )
		param_list.push("ident=" + params.ident);
	}
	
	else if ( data_type == 'diversity' )
	{
	    var taxonres = getElementValue("pm_div_count");
	    if ( taxonres && taxonres != "" )
		param_list.push("count=" + taxonres);
	}
	
	else if ( data_type == "taxa" || data_type == "ops" || data_type == "refs" )
	{
	    var taxon_rank = getElementValue("pm_taxon_rank");
	    
	    if ( taxon_rank && taxon_rank != '--' )
		param_list.push("rank=" + taxon_rank);
	    
	    var taxon_status = getElementValue("pm_taxon_status");
	    
	    if ( taxon_status )
		param_list.push("taxon_status=" + taxon_status);
	    
	    var taxon_variants = getElementValue("pm_taxon_variants");
	    
	    if ( visible.advanced && taxon_variants )
		param_list.push("variant=all");
	}
	
	if ( visible.advanced && params.pres && params.pres != 'all' )
	    param_list.push("pres=" + params.pres);
    }
    
    if ( visible.f2 )		// select by time
    {
	var intervals = [ ];
	var has_time_param;
	
	if ( params.interval && params.interval != "" )
	    intervals.push(params.interval);
	if ( params.interval2 && params.interval2 != "" )
	    intervals.push(params.interval2);
	
	if ( intervals.length )
	{
	    param_list.push("interval=" + intervals.join(','));
	    has_main_param = 1;
	    has_time_param = 1;
	    occs_required = 1;
	}
	
	else
	{
	    if ( params.ma_max )
	    {
		param_list.push("max_ma=" + params.ma_max);
		has_main_param = 1;
		has_time_param = 1;
		occs_required = 1;
	    }
	    
	    if ( params.ma_min )
	    {
		param_list.push("min_ma=" + params.ma_min);
		has_main_param = 1;
		has_time_param = 1;
		occs_required = 1;
	    }
	}
	
	if ( param_errors.interval ) errors_found = 1;
	
	if ( data_type == 'diversity' )
	{
	    has_time_param = 1;
	    
	    var timeres = getElementValue("pm_div_time");
	    
	    if ( timeres && timeres != "stage" )
		param_list.push("time_reso=" + timeres);
	    
	    var recent = getElementValue("pm_div_recent");
	    if ( recent )
		param_list.push("recent");
	}
	
	if ( visible.advanced ) {
	    if ( params.timerule && params.timerule != 'major' && has_time_param ) {
		param_list.push("time_rule=" + params.timerule);
		if ( params.timebuffer && params.timerule == 'buffer' )
		    param_list.push("time_buffer=" + params.timebuffer);
	    }
	}
    }
    
    if ( visible.f3 )		// select by location
    {
	if ( params.cc && params.cc != "" )
	{
	    param_list.push("cc=" + params.cc);
	    occs_required = 1;
	    has_main_param = 1;
	}
	
	if ( params.plate && params.plate != "" )
	{
	    param_list.push("plate=" + params.plate);
	    occs_required = 1;
	    has_main_param = 1;
	}
	
	if ( param_errors.cc || param_errors.plate ) errors_found = 1;
	
	// if ( params.continent && params.continent != '--' )
	// {
	//     if ( params.continent == '**' ) {
	// 	var continent_list = getCheckList("pm_continents");
	// 	if ( continent_list )
	// 	    param_list.push("continent=" + continent_list);
	//     }
	//     else {
	// 	param_list.push("continent=" + params.continent);
	//     }
	    
	//     occs_required = 1;
	// }
	
	// if ( params.country && params.country != '--' )
	// {
	//     if ( params.country == '**' ) {
	// 	var country_list = getElementValue("pm_countries");
	// 	if ( country_list )
	// 	    param_list.push("cc=" + country_list);
	//     }
	//     else {
	// 	param_list.push("cc=" + params.country);
	//     }
	    
	//     occs_required = 1;
	// }
	
	if ( params.latmin || params.latmax || params.lngmin || params.lngmax )
	{
	    if ( params.lngmin ) param_list.push("lngmin=" + params.lngmin);
	    if ( params.lngmax ) param_list.push("lngmax=" + params.lngmax);
	    if ( params.latmin ) param_list.push("latmin=" + params.latmin);
	    if ( params.latmax ) param_list.push("latmax=" + params.latmax);
	    
	    occs_required = 1;
	    has_main_param = 1;
	}
	
	if ( param_errors.coords ) errors_found = 1;
    }
    
    if ( visible.f4 )		// select by stratigraphy
    {
	if ( params.strat && params.strat != "" ) {
	    param_list.push("strat=" + params.strat);
	    occs_required = 1;
	    has_main_param = 1
	}
	
	if ( param_errors.strat ) errors_found = 1;
	
	if ( params.envtype && params.envtype != "" ) {
	    param_list.push("envtype=" + params.envtype);
	    occs_required = 1;
	}
    }
    
    if ( visible.f5 )		// select by metadata
    {
	if ( visible.pd_meta_coll_re || 1 )
	{
	    if ( params.coll_re ) {
		param_list.push("coll_re=" + params.coll_re);
		occs_required = 1;
		has_main_param = 1;
	    }
	    
	    if ( param_errors.coll_re ) errors_found = 1;
	}
	
	if ( visible.pd_meta_occs )
	{
	    if ( params.occs_cmdate ) {
		param_list.push("occs_" + params.occs_crmod + "=" + params.occs_cmdate);
		occs_required = 1;
		all_required = 1;
	    }
	    
	    if ( params.occs_aename ) {
		param_list.push("occs_" + params.occs_authent + "=" + params.occs_aename);
		occs_required = 1
		all_required = 1;
	    }
	    
	    if ( param_errors.occs_cmdate || param_errors.occs_aename ) errors_found = 1;
	}
	
	if ( visible.pd_meta_colls )
	{
	    if ( params.colls_cmdate ) {
		param_list.push("colls_" + params.colls_crmod + "=" + params.colls_cmdate);
		all_required = 1;
	    }
	    
	    if ( params.colls_aename ) {
		param_list.push("colls_" + params.colls_authent + "=" + params.colls_aename);
		all_required = 1;
	    }
	    
	    if ( param_errors.colls_cmdate || param_errors.colls_aename ) errors_found = 1;
	}
	
	if ( visible.pd_meta_taxa )
	{
	    if ( params.taxa_cmdate ) {
		param_list.push("taxa_" + params.taxa_crmod + "=" + params.taxa_cmdate);
		all_required = 1;
	    }
	    
	    if ( params.taxa_aename ) {
		param_list.push("taxa_" + params.taxa_authent + "=" + params.taxa_aename);
		all_required = 1;
	    }
	    
	    if ( param_errors.taxa_cmdate || param_errors.taxa_aename ) errors_found = 1;
	}
	
	if ( visible.pd_meta_ops )
	{
	    if ( params.ops_cmdate ) {
		param_list.push("ops_" + params.ops_crmod + "=" + params.ops_cmdate);
		all_required = 1;
	    }
	    
	    if ( params.ops_aename ) {
		param_list.push("ops_" + params.ops_authent + "=" + params.ops_aename);
		all_required = 1;
	    }
	    
	    if ( param_errors.ops_cmdate || param_errors.ops_aename ) errors_found = 1;
	}
	
	if ( visible.pd_meta_refs )
	{
	    if ( params.refs_cmdate ) {
		param_list.push("refs_" + params.refs_crmod + "=" + params.refs_cmdate);
		all_required = 1;
	    }
	    
	    if ( params.refs_aename ) {
		param_list.push("refs_" + params.refs_authent + "=" + params.refs_aename);
		all_required = 1;
	    }
	    
	    if ( param_errors.refs_cmdate || param_errors.refs_aename ) errors_found = 1;
	}
    }
    
    if ( data_type == 'refs' || data_type == 'byref' )
    {
	if ( params.reftypes && params.reftypes != "" ) {
	    param_list.push("select=" + params.reftypes);
	}
    }
    
    else if ( data_type == "ops" )
    {
	var op_select = getElementValue("pm_op_select");
	if ( op_select )
	    param_list.push("op_type=" + op_select);
    }
    
    if ( params.private )
    {
	param_list.push("private");
    }
    
    // Update the operation, if necessary, based on the chosen parameters
    
    if ( occs_required )
    {
	if ( my_op == 'taxa/list' ) my_op = 'occs/taxa';
	else if ( my_op == 'taxa/refs' ) my_op = 'occs/refs';
	else if ( my_op == 'taxa/byref' ) my_op = 'occs/taxabyref';
	else if ( my_op == 'opinions/list' ) my_op = 'occs/opinions';
    }
    
    else if ( taxon_required )
    {
	if ( my_op == 'opinions/list' ) my_op = 'taxa/opinions';
    }
    
    confirm_download = 0;
    
    if ( ! has_main_param && all_required )
    {
	param_list.push('all_records');
	has_main_param = 1;
    }
    
    else if ( ! has_main_param )
    {
	var all_records_elt = myGetElement("pm_all_records");
	
	if ( all_records_elt && all_records_elt.checked )
	{
	    param_list.push('all_records');
	    has_main_param = 1;
	    confirm_download = 1;
	}
    }
    
    if ( visible.o1 && param_errors.limit ) errors_found = 1;
    
    // Now update the main URL
    
    var url_elt = document.getElementById('mainURL');
    
    if ( errors_found )
    {
	url_elt.textContent = "Fix the parameter errors below to generate a download URL";
	url_elt.href = "";
    }
    
    else if ( ! has_main_param )
    {
	url_elt.textContent = "Enter one or more parameters below to generate a download URL";
	url_elt.href = "";
    }
    
    else
    {
	if ( visible.o1 )
	{
	    var output_list = getOutputList();

	    if ( ! occs_required )
		output_list = output_list.replace(/occapp,?/, 'app,');
	    if ( output_list ) param_list.push("show=" + output_list);
	    
	    var order_expr = getElementValue(output_order);
	    var order_dir = getElementValue("pm_order_dir");
	    
	    if ( order_expr && order_expr != '--' )
	    {
		if ( order_expr == 'authpub' )
		{
		    if ( order_dir && order_dir == 'asc' )
			param_list.push("order=author,pubyr.asc");
		    else
			param_list.push("order=author,pubyr.desc");
		}
		
		else if ( order_expr == 'pubauth' )
		{
		    if ( order_dir && order_dir == 'asc' )
			param_list.push("order=pubyr.asc,author");
		    else
			param_list.push("order=pubyr.desc,author");
		}
		
		else
		{
		    if ( order_dir && order_dir != '--' )
			order_expr = order_expr + '.' + order_dir;
		    param_list.push("order=" + order_expr);
		}
	    }
	    
	    if ( params.offset ) param_list.push("offset=" + params.offset);
	    if ( params.limit ) param_list.push("limit=" + params.limit);
	    
	    if ( params.limit ) confirm_download = 0;
	}
	
	else if ( (data_type == 'occs' || data_type == 'specs') && visible.f1)
	{
	    var acc_only = myGetElement("pm_acc_only");
	    if ( acc_only && acc_only.checked )
		param_list.push('show=acconly');
	}
	
	var param_string = param_list.join('&');
	
	// Construct the new URL
	
	var new_url = base_data_url + my_op + data_format + '?';
	
	if ( params.output_metadata )
	    new_url += 'datainfo&rowcount&';
	
	new_url += param_string;
	
	url_elt.textContent = new_url;
	url_elt.href = new_url;
    }
    
    // Adjust metadata subsections
    
    url_op = my_op;
    
    switch ( my_op )
    {
        case 'occs/list':
        case 'occs/diversity':
        case 'occs/taxa':
	case 'occs/strata':
    	    selectMetaSub('pd_meta_occs');
    	    break;
        case 'colls/list':
    	    selectMetaSub('pd_meta_colls');
	    showElement('pd_meta_occs');
    	    break;
    	case 'taxa/list':
    	    selectMetaSub('pd_meta_taxa');
    	    break;
    	case 'opinions/list':
    	    selectMetaSub('pd_meta_ops');
    	    break;
        case 'taxa/opinions':
    	    selectMetaSub('pd_meta_ops');
	    showElement('pd_meta_taxa');
    	    break;
    	case 'refs/list':
	    selectMetaSub('pd_meta_refs');
	    break;
    	case 'occs/refs':
	case 'occs/taxabyref':
	    selectMetaSub('pd_meta_occs');
	    showElement('pd_meta_refs');
	    break;
        case 'taxa/refs':
	case 'taxa/byref':
    	    selectMetaSub('pd_meta_taxa' );
	    showElement('pd_meta_refs');
    	    break;
    }
}


function selectMetaSub ( subsection )
{
    var subs = { pd_meta_occs: 1, pd_meta_colls: 1, pd_meta_taxa: 1,
		 pd_meta_ops: 1, pd_meta_refs: 1 };
    var s;
    
    for ( s in subs )
    {
	if ( s == subsection )
	{
	    showElement(s);
	    visible[s] = 1;
	}
	else
	{
	    hideElement(s);
	    visible[s] = 0;
	}
    }
}


function getOutputList ( )
{
    var elts = document.getElementsByName(output_section);
    var i;
    var selected = [];
    
    for ( i=0; i<elts.length; i++ )
    {
	if ( elts[i].checked ) selected.push(elts[i].value);
    }
    
    if ( visible.f1 && (data_type == 'occs' || data_type == 'specs'))
    {
	var acc_only = myGetElement("pm_acc_only");
	if ( acc_only && acc_only.checked )
	    selected.push('acconly');
    }
    
    return selected.join(',');
}


function setAdvanced ( show )
{
    if ( show )
	showByClass('advanced');
    else
	hideByClass('advanced');
    
    updateFormState();
}


function setPrivate ( flag )
{
    if ( flag )
	params.private = 1;
    else
	params.private = 0;
    
    updateFormState();    
}


function setRecordType ( type )
{
    data_type = type;
    
    var record_label;
    var type_sections = [ 'type_occs', 'type_colls', 'type_specs', 'type_meas', 'type_strata',
			  'type_diversity', 'type_taxa', 'taxon_reso', 'taxon_range', 'div_reso',
			  'type_ops', 'type_refs', 'acc_only' ];
    var show_sections = { };
    
    if ( type == 'occs' )
    {
	data_op = 'occs/list';
	output_section = 'od_occs';
	output_order = 'pm_occs_order';
	record_label = 'occurrence records';
	show_sections = { type_occs: 1, taxon_reso: 1, acc_only: 1 };
	// showByClass('type_occs');
	// showByClass('taxon_reso');
	// showByClass('acc_only');
	// hideByClass('type_colls');
	// hideByClass('type_specs');
	// hideByClass('type_meas');
	// hideByClass('type_taxa');
	// hideByClass('type_ops');
	// hideByClass('taxon_range');
	// hideByClass('type_strata');
	// hideByClass('type_refs');
    }
    
    else if ( type == 'colls' )
    {
	data_op = 'colls/list';
	output_section = 'od_colls';
	output_order = 'pm_colls_order';
	record_label = 'collection records';
	show_sections = { type_colls: 1, taxon_reso: 1 };
	// showByClass('type_colls');
	// showByClass('taxon_reso');
	// hideByClass('acc_only');
	// hideByClass('type_occs');
	// hideByClass('type_specs');
	// hideByClass('type_meas');
	// hideByClass('type_taxa');
	// hideByClass('type_ops');
	// hideByClass('taxon_range');
	// hideByClass('type_strata');
	// hideByClass('type_refs');
    }
    
    else if ( type == 'specs' )
    {
	data_op = 'specs/list';
	output_section = 'od_specs';
	output_order = 'pm_occs_order';
	record_label = 'specimen records';
	show_sections = { type_specs: 1, taxon_reso: 1, acc_only: 1 };
	// showByClass('type_specs');
	// showByClass('taxon_reso');
	// showByClass('acc_only');
	// hideByClass('type_occs');
	// hideByClass('type_colls');
	// hideByClass('type_meas');
	// hideByClass('type_taxa');
	// hideByClass('type_ops');
	// hideByClass('taxon_range');
	// hideByClass('type_strata');
	// hideByClass('type_refs');
    }
    
    else if ( type == 'meas' )
    {
	data_op = 'specs/measurements';
	output_section = 'od_meas';
	output_order = 'pm_occs_order';
	record_label = 'measurement records';
	show_sections = { type_meas: 1, taxon_reso: 1 };
	// showByClass('type_meas');
	// showByClass('taxon_reso');
	// hideByClass('acc_only');
	// hideByClass('type_occs');
	// hideByClass('type_colls');
	// hideByClass('type_specs');
	// hideByClass('type_taxa');
	// hideByClass('type_ops');
	// hideByClass('taxon_range');
	// hideByClass('type_strata');
	// hideByClass('type_refs');
    }
    
    else if ( type == 'strata' )
    {
	data_op = 'occs/strata';
	output_section = 'od_strata';
	output_order = 'pm_strata_order';
	record_label = 'stratum records';
	show_sections = { type_strata: 1, taxon_reso: 1 };
	// showByClass('type_strata');
	// showByClass('taxon_reso');
	// hideByClass('acc_only');
	// hideByClass('type_occs');
	// hideByClass('type_colls');
	// hideByClass('type_specs');
	// hideByClass('type_meas');
	// hideByClass('type_taxa');
	// hideByClass('type_ops');
	// hideByClass('taxon_range');
	// hideByClass('type_refs');
    }
    
    else if ( type == 'diversity' )
    {
	showHideSection('f2', 'show');
	data_op = 'occs/diversity';
	output_section = 'od_diversity';
	output_order = 'none';
	record_label = 'occurrence records';
	show_sections = { type_diversity: 1, div_reso: 1 };
	// showByClass('type_diversity');
	// hideByClass('type_taxa');
	// hideByClass('taxon_range');
	// hideByClass('acc_only');
	// hideByClass('type_occs');
	// hideByClass('type_colls');
	// hideByClass('type_specs');
	// hideByClass('type_meas');
	// hideByClass('taxon_reso');
	// hideByClass('type_ops');
	// hideByClass('type_strata');
	// hideByClass('type_refs');
    }
    
    else if ( type == 'taxa' )
    {
	data_op = 'taxa/list';
	output_section = 'od_taxa';
	output_order = 'pm_taxa_order';
	record_label = 'taxonomic name records';
	show_sections = { type_taxa: 1, taxon_range : 1, acc_only: 1 };
	// showByClass('type_taxa');
	// showByClass('taxon_range');
	// hideByClass('acc_only');
	// hideByClass('type_occs');
	// hideByClass('type_colls');
	// hideByClass('type_specs');
	// hideByClass('type_meas');
	// hideByClass('taxon_reso');
	// hideByClass('type_ops');
	// hideByClass('type_strata');
	// hideByClass('type_refs');
    }
    
    else if ( type == 'ops' )
    {
	data_op = 'opinions/list';
	output_section = 'od_ops';
	output_order = 'pm_ops_order';
	record_label = 'taxonomic opinion records';
	show_sections = { type_ops: 1, taxon_range: 1, acc_only: 1 };
    // 	showByClass('type_ops');
    // 	showByClass('taxon_range');
    // 	hideByClass('acc_only');
    // 	hideByClass('type_occs');
    // 	hideByClass('type_colls');
    // 	hideByClass('type_specs');
    // 	hideByClass('type_meas');
    // 	hideByClass('taxon_reso');
    // 	hideByClass('type_taxa');
    // 	hideByClass('type_strata');
    // 	hideByClass('type_refs');
    }
    
    else if ( type == 'refs' )
    {
	data_op = 'taxa/refs';
	output_section = 'od_refs';
	output_order = 'pm_refs_order';
	record_label = 'bibliographic reference records';
	show_sections = { type_refs: 1, taxon_range: 1, acc_only: 1 };
	// showByClass('type_refs');
	// showByClass('taxon_range');
	// hideByClass('acc_only');
	// hideByClass('type_occs');
	// hideByClass('type_colls');
	// hideByClass('type_specs');
	// hideByClass('type_meas');
	// hideByClass('taxon_reso');
	// hideByClass('type_taxa');
	// hideByClass('type_ops');
	// hideByClass('type_strata');
    }
    
    else if ( type == 'byref' )
    {
	data_op = 'taxa/byref';
	output_section = 'od_taxa';
	output_order = 'pm_refs_order';
	record_label = 'taxonomic name records';
	show_sections = { type_refs: 1, taxon_range: 1, acc_only: 1 };
	// showByClass('type_refs');
	// showByClass('taxon_range');
	// hideByClass('acc_only');
	// hideByClass('type_occs');
	// hideByClass('type_colls');
	// hideByClass('type_specs');
	// hideByClass('type_meas');
	// hideByClass('taxon_reso');
	// hideByClass('type_taxa');
	// hideByClass('type_ops');
	// hideByClass('type_strata');
    }
    
    else
    {
	alert("Error! (" + type + ")");
	output_section = 'none';
	output_order = 'none';
    }
    
    // Show the proper form division(s) for this type, and hide the others.
    
    var i;
    
    for ( i=0; i < type_sections.length; i++ )
    {
	var name = type_sections[i];
	
	if ( show_sections[name] )
	    showByClass(name);
	else
	    hideByClass(name);
    }
    
    // Show the proper output control for this type, and hide the others.
    
    var sections = document.getElementsByClassName("dlOutputSection");
	  
    for ( i=0; i < sections.length; i++ )
    {
	if ( sections[i].id == output_section )
	    sections[i].style.display = '';	
	else
	    sections[i].style.display = 'none';
    }
    
    sections = document.getElementsByClassName("dlOutputOrder");
    
    for ( i=0; i < sections.length; i++ )
    {
	if ( sections[i].id == output_order )
	    sections[i].style.display = '';	
	else
	    sections[i].style.display = 'none';
    }
    
    // Set the label on "select all records"
    
    try
    {
	setInnerHTML("label_all_records", record_label);
    }
    
    finally {};
    
    // Show and hide various other controls based on type
    
    try
    {
	if ( type == 'refs' )
	{
	    setDisabled("rb.ris", 0);
	    if ( ref_format ) document.getElementById("rb"+ref_format).click();
	}
	
	else
	{
	    setDisabled("rb.ris", 1);
	    if ( data_format == '.ris' ) document.getElementById("rb"+non_ref_format).click();
	}
	
    } finally {};
    
    showElement('pd_meta_coll_re');
    
    // Then store the new type, and update the main URL
    
    updateFormState();
}


function setFormat ( type )
{
    data_format = '.' + type;
    if ( data_type != 'refs' && type != 'ris' ) non_ref_format = data_format;
    else if ( data_type == 'refs' ) ref_format = data_format;
    
    updateFormState();
}


function testMainURL ( )
{
    var url = document.getElementById("mainURL").textContent;
    
    if ( ! url.match(/http/i) ) return;
   
    if ( data_format == '.csv' ) url = url.replace('.csv','.txt');
    else url += '&textresult';
    
    if ( ! params.limit && url_op != 'occs/diversity' ) url += '&limit=100';
    
    window.open(url);
}


function downloadMainURL ( )
{
    var url = document.getElementById("mainURL").textContent;
    
    if ( ! url.match(/http/i) ) return;
    
    if ( confirm_download )
    {
	if ( ! confirm("You are about to initiate a download that might exceed 100 MB.  Continue?") )
	    return;
    }
    
    window.open(url);
}


