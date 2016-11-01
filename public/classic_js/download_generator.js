//
// PBDB Download generator
//
// Author: Michael McClennen
// 
// This code is designed to work with the file download_generator.html to implement a Web
// application for downloading data from the Paleobiology Database using the database's API.
// Users can fill in the various form elements to specify the kind of data they wish to download,
// filter parameters, output options, etc.  The application then generates an API URL using those
// values, and provides a button for carrying out the download.



// The following function is the constructor for the application controller object.  This should
// be called once, at load time, and provided with the following parameters:
// 
// data_url		base URL for the API
// is_contributor	true if the user is logged in to the database, false otherwise
// 
// After this object is instantiated, its initApp method should be called to initialize it.  It is
// a good idea to call this after the entire web page is loaded, so that all necessary DOM
// elements will be in place.

function DownloadGeneratorApp( data_url, is_contributor )
{
    "use strict";
    
    // Initialize some private variables.
    
    var done_config1, done_config2;
    
    var params = { base_name: '', interval: '', output_metadata: 1, reftypes: 'taxonomy' };
    var param_errors = { };

    var visible = { };
    
    var data_type = "occs";
    var data_op = "occs/list";
    var url_op = "occs/list";

    var data_format = ".csv";
    var ref_format = "";
    var non_ref_format = ".csv";

    var form_mode = "simple";
    
    var output_section = 'none';
    var output_order = 'none';
    
    var output_full = { };
    var full_checked = { };
    
    var confirm_download = 0;
    var taxon_status_save = '';

    var no_update = 0;

    // Object for holding data cached from the API
    
    var api_data = { };
    
    // Variables for handling object identifiers in the "metadata" section.
    
    var id_param_map = { col: "coll_id", clu: "clust_id",
			  occ: "occ_id", spm: "spec_id" };
    var id_param_index = { col: 0, clu: 1, occ: 2, spm: 3 };
    
    // The following regular expressions are used to validate user input.
    
    var patt_dec_num = /^[+-]?(\d+[.]\d*|\d*[.]\d+|\d+)$/;
    var patt_dec_pos = /^(\d+[.]\d*|\d*[.]\d+|\d+)$/;
    var patt_int_pos = /^\d+$/;
    var patt_name = /^(.+),\s+(.+)/;
    var patt_name2 = /^(.+)\s+(.+)/;
    var patt_has_digit = /\d/;
    var patt_date = /^(\d+[mshdMY]|\d\d\d\d(-\d\d(-\d\d)?)?)$/;
    var patt_extid = /^(col|occ|clu|spm)[:]\d+$/;
    
    // The following function initializes this application controller object.  It is exported as
    // a method, so that it can be called once the web page is fully loaded.  It must make two
    // API calls to get a list of country and continent codes, and geological time intervals.
    // When both of these calls complete, the "initializing form..." HTML floating element is hidden,
    // signaling to the user that the application is ready for use.
    
    function initApp ()
    {
	// Do various initialization steps
	
	no_update = 1;
	
	initDisplayClasses();
	getDBUserNames();
	
	if ( getElementValue("vf1") != "-1" )
	    showHideSection('f1', 'show');
	
	var sections = { vf2: 'f2', vf3: 'f3', vf4: 'f4', vf5: 'f5', vf6: 'f6', vo1: 'o1' };
	var s;
	
	for ( s in sections )
	{
	    if ( getElementValue(s) == "1" )
		showHideSection(sections[s], 'show');
	}
	
	// If the form is being reloaded and already has values entered into it, take some steps
	// to make sure it is properly set up.
	
	try
	{
	    var record_type = $('input[name="record_type"]:checked').val();
	    setRecordType(record_type);
	    
	    var form_mode = $('input[name="form_mode"]:checked').val();
	    setFormMode(form_mode);
	    
	    var output_format = $('input[name="output_format"]:checked').val();
	    setFormat(output_format);

	    var private_url = $('input[name="private_url"]:checked').val();
	    console.log("private_url = " + private_url);
	    setPrivate(private_url);
	}
	
	catch (err) { };
	
	no_update = 0;
	
	// Initiate two API calls to fetch necessary data.  Each has a callback to handle the data
	// that comes back, and a failure callback too.
	
	$.getJSON(data_url + 'config.json?show=all&limit=all')
	    .done(callbackConfig1)
	    .fail(badInit);
	$.getJSON(data_url + 'intervals/list.json?all_records&limit=all')
	    .done(callbackConfig2)
	    .fail(badInit);
    }
    
    this.initApp = initApp;
    
    
    // The following function is called when the first configuration API call returns.  Country
    // and continent codes and taxonomic ranks are saved as properties of the api_data object.
    // These will be used for validating user input.
    
    function callbackConfig1 (response)
    {
	if ( response.records )
	{
	    api_data.rank_string = { };
	    api_data.continent_name = { };
	    api_data.continents = [ ];
	    api_data.country_code = { };
	    api_data.country_name = { };
	    api_data.countries = [ ];
	    api_data.country_names = [ ];
	    api_data.aux_continents = [ ];
	    api_data.lithologies = [ ];
	    api_data.lith_types = [ ];
	    
	    var lith_uniq = { };
	    
	    for ( var i=0; i < response.records.length; i++ )
	    {
		var record = response.records[i];
		
		if ( record.cfg == "trn" ) {
		    api_data.rank_string[record.cod] = record.rnk;
		}
		else if ( record.cfg == "con" ) {
		    api_data.continent_name[record.cod] = record.nam;
		    api_data.continents.push(record.cod, record.nam);
		}
		else if ( record.cfg == "cou" ) {
		    var key = record.nam.toLowerCase();
		    api_data.country_code[key] = record.cod;
		    api_data.country_name[record.cod] = record.nam;
		    api_data.country_names.push(record.nam);
		}
		else if ( record.cfg == "lth" ) {
		    api_data.lithologies.push( record.lth, record.lth );
		    if ( ! lith_uniq[record.ltp] )
		    {
			api_data.lith_types.push( record.ltp, record.ltp );
			lith_uniq[record.ltp] = 1;
		    }
		}
	    }
	    
	    api_data.lith_types.push( 'unknown', 'unknown' );
	    
	    // api_data.continents = api_data.continents.concat(api_data.aux_continents);
	    api_data.country_names = api_data.country_names.sort();
	    
	    for ( i=0; i < api_data.country_names.length; i++ )
	    {
		var key = api_data.country_names[i].toLowerCase();
		var code = api_data.country_code[key];
		api_data.countries.push( code, api_data.country_names[i] + " (" + code + ")" );
	    }

	    // If both API calls are complete, finish the initialization process. 
	    
	    done_config1 = 1;
	    if ( done_config2 ) finishInitApp();
	}

	// If no results were received, we're in trouble.  The application can't be used if the
	// API is not working, so there's no point in proceeding further.
	
	else
	    badInit();
    }
    
    
    // The following function is called when the second configuration API call returns.  The names
    // of known geological intervals are saved as a property of the api_data object.  These will
    // be used for validating user input.
    
    function callbackConfig2 (response)
    {
	if ( response.records )
	{
	    api_data.interval = { };
	    
	    for ( var i = 0; i < response.records.length; i++ )
	    {
		var record = response.records[i];
		var key = record.nam.toLowerCase();
		
		api_data.interval[key] = record.oid;
	    }
	    
	    // If both API calls are complete, finish the initialization process. 
	    
	    done_config2 = 1;
	    if ( done_config1 ) finishInitApp();
	}
	
	// If no results were received, we're in trouble.  The application can't be used if the
	// API is not working, so there's no point in proceeding further.
	
	else
	    badInit();
	
    }
    

    // This function is called when both configuration API calls are complete.  It hides the
    // "initializing form, please wait" HTML floating object, and then calls updateFormState to
    // initialize the main URL and other form elements.
    
    function finishInitApp ()
    {
	initFormContents();
	
	var init_box = myGetElement("db_initmsg");
	if ( init_box ) init_box.style.display = 'none';
	
	no_update = 1;
	
	try {
	    checkTaxon();
	    checkTaxonStatus();
	    checkInterval();
	    checkCC();
	    checkCoords();
	    checkStrat();
	    checkEnv();
	    checkMeta('specs');
	    checkMeta('occs');
	    checkMeta('colls');
	    checkMeta('taxa');
	    checkMeta('occs');
	    checkMeta('refs');
	}

	catch (err) { };
	
	no_update = 0;
	
	updateFormState();
    }
    

    // The following method can be called to reset the form back to its initial state.  It is tied
    // to the "clear form" button in the HTML layout.  The options selected in the top section of
    // the form (i.e. record type, output format) will be preserved.  All others will be reset.
    
    function resetForm ()
    {
	var keep_type = data_type;
	var keep_format = data_format.substring(1);
	var keep_private = params.private;
	var keep_advanced = form_mode;
	
	var form_elt = myGetElement("download_form");
	if ( form_elt ) form_elt.reset();
	
	params = { base_name: '', interval: '', output_metadata: 1, reftypes: 'taxonomy' };
	
	initDisplayClasses();

	try
	{
	    no_update = 1;
	    
	    setRecordType(keep_type);
	    $('input[name="record_type"][value="' + keep_type + '"]')[0].checked = 1;
	    setFormat(keep_format);
	    $('input[name="output_format"][value="' + keep_format + '"]')[0].checked = 1;
	    setPrivate(keep_private);
	    $('input[name="private"][value="' + keep_private + '"]')[0].checked = 1;
	    setFormMode(keep_advanced);
	    $('input[name="form_mode"][value="' + keep_advanced + '"]')[0].checked = 1;	    
	}
	
	finally
	{
	    no_update = 0;
	}
	
	updateFormState();
    }

    this.resetForm = resetForm;
    
    
    // This function notifies the user that this application is not able to be used.  It is called
    // if either of the configuration API calls fail.  If the API is not working, there's no point
    // in proceeding with this application.
    
    function badInit ( )
    {
	var init_box = myGetElement("db_initmsg");
	if ( init_box ) init_box.innerHTML = "Initialization failed!  Please contact admin@paleobiodb.org";
    }
    
    
    // Included in this application is a system to easily hide and show all HTML objects that are
    // tagged with particular CSS classes.  This subroutine sets up the initial form state.
    
    function initDisplayClasses ()
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
	
	hideByClass('buffer_rule');
	
	// If the user is currently logged in to the database, show the form element that chooses
	// between generating a URL that fetches private data and one that does not.  The former
	// will only work when the user is logged in, the latter may be distributed publicly.
	
	if ( is_contributor )
	{
	    showByClass('private');
	    // params.private = 1;
	}
	
	else
	    hideByClass('private');
    }
    
    
    // -----------------------------------------------------------------------------------------
    
    // The following functions generate some of the repetitious HTML necessary for checklists and
    // other complex controls.  Doing it this way makes the lists easier to change as the API is
    // updated, and allows download_generator.html to be much smaller and simpler.  These
    // functions call convenience routines such as setInnerHTML, which are defined below.
    
    function initFormContents ( )
    {
	var content = "";
	
	// First generate the controls for selecting output blocks
	
	content = "<tr><td>\n";
	
	// "*full", "full", "Includes all boldface blocks (no need to check them separately)",
	
	content += makeBlockControl( "od_occs",
				     ["*attribution", "attr", "Attribution (author and year) of the accepted name",
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
				     ["*location", "loc", "Additional info about the geographic locality",
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
				     ["*attribution", "attr", "Attribution (author and year) of the accepted taxonomic name",
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
				     ["*attribution", "attr", "Attribution (author and year) of this taxonomic name",
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
    				     ["*basis", "basis", "Basis of this opinion, i.e. 'stated with evidence'",
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
	
	// Then generate various option lists.  The names and codes for the continents and
	// countries were fetched during initialization via an API call.
	
	var continents = api_data.continents || ['ERROR', 'An error occurred'];
	
	content = makeOptionList( [ '--', '--', '**', 'Multiple' ].concat(continents) );
	
	setInnerHTML("pm_continent", content);
	
	content = makeCheckList( "pm_continents", api_data.continents, 'dgapp.checkCC()' );
	
	setInnerHTML("pd_continents", content);
	
	var countries = api_data.countries || ['ERROR', 'An error occurred'];
	
	content = makeOptionList( ['--', '--', '**', 'Multiple'].concat(countries) );
	
	setInnerHTML("pm_country", content);
	
	var crmod_options = [ 'created_after', 'entered after',
			      'created_before', 'entered before',
			      'modified_after', 'modified after',
			      'modified_before', 'modified before' ];
	
	content = makeOptionList( crmod_options );
	
	setInnerHTML("pm_specs_crmod", content);
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
	
	setInnerHTML("pm_specs_authent", content);
	setInnerHTML("pm_occs_authent", content);
	setInnerHTML("pm_colls_authent", content);
	setInnerHTML("pm_taxa_authent", content);
	setInnerHTML("pm_ops_authent", content);
	setInnerHTML("pm_refs_authent", content);
	
	content = makeCheckList( "pm_lithtype", api_data.lith_types, 'dgapp.checkLith()' );
	
	setInnerHTML("pd_lithtype", content);
	
	var envtype_options = [ 'terr', 'terrestrial',
				'marine', 'any marine',
				'carbonate', 'carbonate',
				'silicic', 'siliciclastic',
				'unknown', 'unknown' ];
	
	content = makeCheckList( "pm_envtype", envtype_options, 'dgapp.checkEnv()' );
	
	setInnerHTML("pd_envtype", content);
	
	var envzone_options = [ 'lacust', 'lacustrine', 'fluvial', 'fluvial',
				'karst', 'karst', 'terrother', 'terrestrial other',
				'marginal', 'marginal marine', 'reef', 'reef',
				'stshallow', 'shallow subtidal', 'stdeep', 'deep subtidal',
				'offshore', 'offshore', 'slope', 'slope/basin',
				'marindet', 'marine indet.' ];
	
	content = makeCheckList( "pm_envzone", envzone_options, 'dgapp.checkEnv()' );
	
	setInnerHTML("pd_envzone", content);
	
	var reftypes = [ '+auth', 'authority references', '+class', 'classification references',
			 'ops', 'all opinion references', 'occs', 'occurrence references',
			 'specs', 'specimen references', 'colls', 'collection references' ];
	
	content = makeCheckList( "pm_reftypes", reftypes, 'dgapp.checkRefopts()' );
	
	setInnerHTML("pd_reftypes", content);
	
	var taxon_mods = [ 'nm', 'no modifiers', 'ns', 'n. sp.', 'ng', 'n. (sub)gen', 'af', 'aff.', 'cf', 'cf.',
			   'sl', 'sensu lato', 'if', 'informal', 'eg', 'ex gr.',
			   'qm', '?', 'qu', '&quot;&quot;' ];
	
	content = makeCheckList( "pm_idgenmod", taxon_mods, 'dgapp.checkTaxonMods()' );
	
	setInnerHTML("pd_idgenmod", content);
	
	content = makeCheckList( "pm_idspcmod", taxon_mods, 'dgapp.checkTaxonMods()' );
	
	setInnerHTML("pd_idspcmod", content);
	
	// We need to execute the following operation here, because the
	// spans to which it applies are created by the code above.
	
	hideByClass('help_o1');
    }
    
    
    // The following function generates HTML code for displaying a checklist of output blocks.
    // One of these is created for every different data type.  As a SIDE EFFECT, produces a 
    // hash listing every boldfaced block and stores it in a property of the variable 'output_full'.
    
    function makeBlockControl ( section_name, block_list )
    {
	var content = "";
	
	output_full[section_name] = output_full[section_name] || { };
	
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
		output_full[section_name][block_code] = 1;
	    }
	    
	    content = content + '<span class="dlBlockLabel"><input type="checkbox" name="' + 
		section_name + '" value="' + block_code + '" ';
	    content = content + attrs + ' onClick="dgapp.updateFormState()">';
	    content += asterisked ? '<b>' + block_name + '</b>' : block_name;
	    content += '</span><span class="vis_help_o1">' + block_doc + "<br/></span>\n";
	}
	
	return content;
    }
    
    
    // The following function generates HTML code for the "help" row at the bottom of a checklist
    // of output blocks.
    
    function makeOutputHelpRow ( path )
    {
	var content = '<tr class="dlHelp vis_help_o1"><td>' + "\n";
	content += "<p>You can get more information about these output blocks and fields ";
	content += '<a target="_blank" href="' + data_url + path + '#RESPONSE" ';
	content += 'style="text-decoration: underline">here</a>.</p>';
	content += "\n</td></tr>";
	
	return content;
    }


    // The following function generates HTML code for displaying a checklist of possible parameter
    // values.
    
    function makeCheckList ( list_name, options, ui_action )
    {
	var content = '';
	
	if ( options == undefined || ! options.length )
	{
	    console.log("ERROR: no options specified for checklist '" + list_name + "'");
	    return content;
	}
	
	for ( var i=0; i < options.length / 2; i++ )
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
    
    
    // The following function generates HTML code for displaying a dropdown menu of possible
    // parameter values.
    
    function makeOptionList ( options )
    {
	var content = '';
	var i;
	
	if ( options == undefined || ! options.length )
	{
	    return '<option value="error">ERROR</option>';
	}
	
	for ( i=0; i < options.length / 2; i++ )
	{
	    var code = options[2*i];
	    var label = options[2*i+1];
	    
	    content += '<option value="' + code + '">' + label + "</option>\n";
	}
	
	return content;
    }
    
    
    // We don't have to query the API to get the list of database contributor names, because the
    // Classic code that generates the application's web page automatically includes the function
    // 'entererNames' which returns this list.  We go through this list and stash all of the names
    // in the api_data object anyway.
    
    function getDBUserNames ( )
    {
	if ( api_data.user_names ) return;
	
	api_data.user_names = entererNames();
	api_data.valid_name = { };
	api_data.user_match = [ ];
	api_data.user_matchinit = [ ];
	
	// The names might be either in the form "last, first" or "first last".  We have to check
	// both patterns.  We add the object 'valid_name', whose properties include all of the
	// valid names in the form "first last" plus all last names.
	
	for ( var i = 0; i < api_data.user_names.length; i++ )
	{
	    var match;
	    
	    if ( match = api_data.user_names[i].match(patt_name) )
	    {
		api_data.valid_name[match[1]] = 1;
		var rebuilt = match[2].substr(0,1) + '. ' + match[1];
		api_data.valid_name[rebuilt] = 1;
		api_data.user_names[i] = rebuilt;
		api_data.user_match[i] = match[1].toLowerCase();
		api_data.user_matchinit[i] = match[2].substr(0,1).toLowerCase();
	    }
	    
	    else if ( match = api_data.user_names[i].match(patt_name2) )
	    {
		api_data.valid_name[match[2]] = 1;
		var rebuilt = match[1].substr(0,1) + '. ' + match[2];
		api_data.valid_name[rebuilt] = 1;
		api_data.user_names[i] = rebuilt;
		api_data.user_match[i] = match[2].toLowerCase();
		api_data.user_matchinit[i] = match[1].substr(0,1).toLowerCase();
	    }
	}
    }
    

    // -----------------------------------------------------------------------------
    
    // The following convenience methods manipulate DOM objects.  We use the javascript object
    // 'visible' to keep track of which groups of objects are supposed to be visible and which are
    // not.  The properties of this object are matched up with CSS classes whose names start with
    // 'vis_' or 'inv_'.  If an object has CSS classes 'vis_x' and 'vis_y', then it is visible if
    // both visible[x] and visible[y] are true, hidden otherwise.  Additionally, if an object has
    // CSS class 'inv_z', then it is hidden whenever visible[z] is true.
    
    // The following routine sets visible[classname] to false, then adjusts the visibility of all
    // DOM objects.
    
    function hideByClass ( classname )
    {
	// We start by setting the specified property of visible to false.
	
	visible[classname] = 0;
	
	// All objects with class 'vis_' + classname must now be hidden, regardless of any other
	// classes they may also have.
	
	var list = document.getElementsByClassName('vis_' + classname);
	
	for ( var i = 0; i < list.length; i++ )
	{
	    list[i].style.display = 'none';
	}
	
	// Some objects with class 'inv_' + classname may now be visible, if visible[x] is true for
	// each class 'vis_x' that the object has and visible[y] is false for each class 'inv_y'
	// that the object has.
	
	list = document.getElementsByClassName('inv_' + classname);
	
	element:
	for ( var i = 0; i < list.length; i++ )
	{
	    // For each such object, check all of its classes.
	    
	    var classes = list[i].classList;
	    
	    for ( var j = 0; j < classes.length; j++ )
	    {
		var classprefix = classes[j].slice(0,4);
		var rest = classes[j].substr(4);
		
		// If it has class 'vis_x' and visible[x] is not true, then setting
		// visible[classname] to false does not change its status.
		
		if ( classprefix == "vis_" && ! visible[rest] )
		{
		    continue element;
		}
		
		// If it has class 'inv_y' and visible[y] is true, then y != classname because we
		// set visible[classname] to false at the top of this function.  So this object's
		// status doesn't change either.
		
		else if ( classprefix == "inv_" && visible[rest] )
		{
		    continue element;
		}
	    }
	    
	    // If we get here then the object should be made visible.
	    
	    list[i].style.display = '';
	}
    }
    
    
    // The following routine sets visible[classname] to true, then adjusts the visibility of all
    // DOM objects.
    
    function showByClass ( classname )
    {
	visible[classname] = 1;
	
	// Some objects with class 'vis_' + classname may now be visible, if visible[x] is true for
	// each class 'vis_x' that the object has and visible[y] is false for each class 'inv_y'
	// that the object has.
	
	var list = document.getElementsByClassName('vis_' + classname);
	
	element:
	for ( var i = 0; i < list.length; i++ )
	{
	    // For each such object, check all of its classes.
	    
	    var classes = list[i].classList;
	    
	    for ( var j = 0; j < classes.length; j++ )
	    {
		var classprefix = classes[j].slice(0,4);
		var rest = classes[j].substr(4);
		
		// If it has class 'vis_x' and visible[x] is not true, then x != classname because
		// we set visible[classname] to true at the top of this function.  So this
		// object's status does not change.
		
		if ( classprefix == "vis_" && ! visible[rest] )
		{
		    continue element;
		}
		
		// If it has class 'inv_y' and visible[y] is true, then its status does not change
		// because 'inv_' overrides 'vis_'.
		
		else if ( classprefix == "inv_" && visible[rest] )
		{
		    continue element;
		}
	    }
	    
	    // If we get here then the object should be made visible.
	    
	    list[i].style.display = '';
	}
	
	// All objects with class 'inv_' + classname must now be hidden, regardless of any other
	// classes they may also have.
	
	list = document.getElementsByClassName('inv_' + classname);
	
	for ( var i = 0; i < list.length; i++ )
	{
	    list[i].style.display = 'none';
	}
    }
    
    
    // The following method expands or collapses the specified section of the application.  If
    // the value of 'action' is 'show', then it is expanded.  Otherwise, its state is
    // toggled.
    
    function showHideSection ( section_id, action )
    {
	// If we are forcing or toggling the section to expanded then execute the necessary steps.
	// The triangle marker corresponding to the section has the same name but prefixed with
	// 'm'.
	
	if ( ! visible[section_id] || (action && action == 'show') )
	{
            showElement(section_id);
	    setElementSrc('m'+section_id, "/JavaScripts/img/open_section.png");
	    setElementValue('v'+section_id, "1");
	    var val = getElementValue('v'+section_id);
	}
	
	// Otherwise, we must be toggling it to collapsed.
	
	else
	{
            hideElement(section_id);
	    setElementSrc('m'+section_id, "/JavaScripts/img/closed_section.png");
	    setElementValue('v'+section_id, "-1");
	    var val = getElementValue('v'+section_id);
	}
	
	// Update the form state to reflect the new configuration.
	
	updateFormState();
    }
    
    this.showHideSection = showHideSection;
    
    
    // The following method should be called if the user clicks the 'help' button for one of the
    // sections.  If the section is currently collapsed, it will be expanded.  The help text and
    // related elements for the section will then be toggled.  The event object responsible for
    // this action can be passed as the second parameter, or else it will be assumed to be the
    // currently executing event.
    
    function helpClick ( section_id, e )
    {
	if ( ! visible[section_id] && ! visible['help_' + section_id] )
	    showHideSection(section_id, 'show');
	
	showHideHelp(section_id);
	
	// Stop the event from propagating, because it has now been carried out.
	
	if ( !e ) e = window.event;
	e.stopPropagation();
    }
    
    this.helpClick = helpClick;
    
    
    // Adjust the visiblity of the help text for the specified section of the application.  If the
    // action is 'show', make it visible.  If 'hide', make it invisible.  Otherwise, toggle it.
    // The help button has the same name as the section, but prefixed with 'q'.  The help elements
    // all have the class 'vis_help_' + the section id.
    
    function showHideHelp ( section_id, action )
    {
	// If the help text is visible and we're either hiding or toggling, then do so.
	
	if ( visible['help_' + section_id] && ( action == undefined || action == "hide" ) )
	{
	    setElementSrc('q' + section_id, "/JavaScripts/img/hidden_help.png");
	    hideByClass('help_' + section_id);
	}
	
	// If the help text is invisible and we're showing or toggling, then do so.
	
	else if ( action == undefined || action == "show" )
	{
	    setElementSrc('q' + section_id, "/JavaScripts/img/visible_help.png");
	    showByClass('help_' + section_id);
	}
    }
    
    
    // ------------------------------------------------------------------------------------
    
    // The following convenience routines operate on elements one at a time, rather than in
    // groups.  This is an alternate mechanism for showing and hiding elements, used for elements
    // which are singular such as the "initializing application" floater or the elements that
    // display error messages.  These routines also set the property of the 'visible' object
    // corresponding to the identifier of the element being set.
    
    // This function retrieves the DOM object with the specified id, and leaves a reasonable
    // message on the console if the program contains a typo and the requested element does not
    // exist.
    
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
    
    // Hide the DOM element with the specified id.
    
    function hideElement ( id )
    {
	var elt = myGetElement(id);
	
	if ( elt )
	{
	    elt.style.display = 'none';
	    visible[id] = 0;
	}
    }
    
    
    // Show the DOM elment with the specified id.

    function showElement ( id )
    {
	var elt = myGetElement(id);
	
	if ( elt )
	{
	    elt.style.display = '';
	    visible[id] = 1;
	}
    }
    
    
    // Show one element from a list, and hide the rest.  The list is given by the argument
    // 'values', prefixed by 'prefix'.  The value corresponding to 'selected' specifies which
    // element to show; the rest are hidden.
    
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
    
    
    // Set the 'innerHTML' property of the specified element.  If the specified content is not a
    // string, then the property is set to the empty string.
    
    function setInnerHTML ( id, content )
    {
	var elt = myGetElement(id);
	
	if ( elt )
	{
	    if ( typeof(content) != "string" )
		elt.innerHTML = "";
	    else
		elt.innerHTML = content;
	}
    }
    
    
    // Set the 'src' property of the specified element.
    
    function setElementSrc ( id, value )
    {
	var elt = myGetElement(id);
	
	if ( elt && typeof(value) == "string" ) elt.src = value;
    }
    
    
    // Set the 'value' property of the specified element.
    
    function setElementValue ( id, value )
    {
	var elt = myGetElement(id);
	
	if ( elt && typeof(value) == "string" ) elt.value = value;
    }
    
    
    // Set the 'innerHTML' property of the specified element to a sequence of list items derived
    // from the elements of 'messages'.  The first argument should be the identifier of a DOM <ul>
    // object, and the second should be an array of strings.  If the second argument is undefined
    // or empty, then the list contents are set to the empty string.  This function is used to
    // display or clear lists of error messages, in order to inform the application user about
    // improper values they have entered or other error conditions.
    
    function setErrorMessage ( id, messages )
    {
	if ( messages == undefined || messages == "" || messages.length == 0 )
	{
	    setInnerHTML(id, "");
	    hideElement(id);
	}

	else if ( typeof(messages) == "string" )
	{
	    setInnerHTML(id, "<li>" + messages + "</li>");
	    showElement(id);
	}
	
	else
	{
	    var err_msg = messages.join("</li><li>") || "Error";
	    setInnerHTML(id, "<li>" + err_msg + "</li>");
	    showElement(id);
	}
    }
    
    
    // Set the 'disabled' property of the specified DOM object to true or false, according to the
    // second argument.
    
    function setDisabled ( id, disabled )
    {
	var elt = myGetElement(id);
	
	if ( elt ) elt.disabled = disabled;
    }
    
    
    // If the specified DOM object is of type "checkbox", then return the value of its 'checked'
    // attribute.  Otherwise, return the value of its 'value' attribute.
    
    function getElementValue ( id )
    {
	var elt = myGetElement(id);
	
	if ( elt && elt.type && elt.type == "checkbox" )
	    return elt.checked;
	
	else if ( elt )
	    return elt.value;
	
	else
	    return "";
    }
    

    // If the specified DOM object is of type "checkbox" then set its 'checked' attribute to
    // false.  Otherwise, set its 'value' attribute to the empty string.
    
    function clearElementValue ( id )
    {
	var elt = myGetElement(id);

	if ( elt && elt.type && elt.type == "checkbox" )
	    elt.checked = 0;

	else if ( elt )
	    elt.value = "";
    }
    
    
    // The following function returns a list of the values of all checked elements from among
    // those with the specified name.
    
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
    
    
    // ---------------------------------------------------------------------------------
    
    // The following routines check various parts of the user input.  They are called from the
    // HTML side of this application when various form fields are modified.  These routines set
    // properties of the javascript object 'params' to indicate good parameter values that should
    // be used to generate the main URL, and properties of the javascript object 'param_errors' to
    // indicate that the main URL should not be generated because of input errors.  Each of these
    // routines ends by calling updateFormState to update the main URL.
    
    // The following function is called whenever any of the form elements "pm_base_name",
    // "pm_ident", or "pm_pres" in the section "Select by Taxonomy" are changed.
    
    function checkTaxon ( )
    {
	// Get the current value of each element.  The values for 'ident' and 'pres' come from
	// dropdown menus and can be stored as-is.
	
	var base_name = getElementValue("pm_base_name");
	params.ident = getElementValue("pm_ident");
	params.pres = getElementValue("pm_pres");
	
	// Filter out spurious characters from the value of 'base_name'.  Turn multiple
	// commas/whitespace into a single comma followed by a space, multiple ^ into a single ^
	// preceded by a space, and take out any sequence of non-alphabetic characters at the end
	// of the string.
	
	base_name = base_name.replace(/[\s,]*,[\s,]*/g, ", ");
	base_name = base_name.replace(/\^\s*/g, " ^");
	base_name = base_name.replace(/\^[\s^]*/g, "^");
	base_name = base_name.replace(/[\s^]*\^,[\s,]*/g, ", ");
	base_name = base_name.replace(/[^a-zA-Z:]+$/, "");

	// If the result is the same as the stored value of this field, then just call
	// 'updateFormState' without changing anything.
	
	if ( base_name == params.base_name )
	{
	    updateFormState();
	}

	// Otherwise, if the value is empty, then clear the stored value and any error messages
	// associated with this field.
	
	else if ( base_name == "" )
	{
	    params.base_name = "";
	    param_errors.base_name = 0;
	    setErrorMessage("pe_base_name", "");
	    updateFormState();
	}

	// Otherwise, we need to call the API to determine if the value(s) entered in this field
	// are actual taxonomic names known to the database.
	
	else
	{
	    params.base_name = base_name;
	    $.getJSON(data_url + 'taxa/list.json?name=' + base_name).done(callbackBaseName);
	}
    }
    
    this.checkTaxon = checkTaxon;
    
    
    // This is called when the API call for a new taxonomic name completes.  If the result
    // includes any error or warning messages, display them to the user and set the 'base_name'
    // property of 'param_errors' to true.  Otherwise, we know that the names were good so we
    // clear any messages that were previously displayed and set the property to false.
    
    function callbackBaseName ( response )
    {
	if ( response.warnings )
	{
	    var err_msg = response.warnings.join("</li><li>") || "There is a problem with the API";
	    setErrorMessage("pe_base_name", err_msg);
	    param_errors.base_name = 1;
	}
	
	else if ( response.errors )
	{
	    var err_msg = response.errors.join("</li><li>") || "There is a problem with the API";
	    setErrorMessage("pe_base_name", err_msg);
	    param_errors.base_name = 1;
	}
	
	else
	{
	    setErrorMessage("pe_base_name", "");
	    param_errors.base_name = 0;
	}
	
	updateFormState();
    }
    

    // This function is called when various fields in the "Select by taxonomy" section are
    // modified.  The parameter 'changed' indicates which one has changed.
    
    function checkTaxonStatus ( changed )
    {
	var accepted_box = myGetElement("pm_acc_only");
	var status_selector = myGetElement("pm_taxon_status");
	var variant_box = myGetElement("pm_taxon_variants");
	
	if ( ! accepted_box || ! status_selector || ! variant_box ) return;

	// If the checkbox "show accepted names only" is now checked, then save the previous value
	// for the 'status_selector' dropdown and set it to "accepted names".  If it is now
	// unchecked, then restore the previous dropdown value.
	
	if ( changed == 'accepted' )
	{
            if ( accepted_box.checked )
            {
		taxon_status_save = status_selector.value;
		status_selector.value = "accepted";
		variant_box.checked = false;
            }
            
            else
            {
		status_selector.value = taxon_status_save;
            }
	}

	// If the 'status_selector' dropdown is set to anything but "accepted", or if
	// 'variant_box' is checked, then uncheck 'accepted_box'.
	
	else if ( changed == 'selector' )
	{
            taxon_status_save = status_selector.value;
            if ( status_selector.value != "accepted" )
		accepted_box.checked = false;
	}
	
	else
	{
            if ( variant_box.checked )
		accepted_box.checked = false;
	}
	
	updateFormState();
    }
    
    this.checkTaxonStatus = checkTaxonStatus;
    
    
    // This function is called when any of the taxon modifier options are changed.
    
    function checkTaxonMods ( )
    {
	var idqual = getElementValue("pm_idqual");
	
	if ( idqual == 'any' )
	{
	    params.idqual = '';
	    params.idgenmod = '';
	    params.idspcmod = '';
	    hideByClass('taxon_mods');
	    return;
	}
	
	else if ( idqual == 'custom' )
	{
	    params.idqual = '';
	    showByClass('taxon_mods');
	    checkTaxonCustom();
	}
	
	else
	{
	    params.idqual = idqual;
	    params.idgenmod = '';
	    params.idspcmod = '';
	    hideByClass('taxon_mods');
	}
	
	updateFormState();
    }
    
    this.checkTaxonMods = checkTaxonMods;
    
    function checkTaxonCustom ( )
    {
	var idgenmod = getCheckList("pm_idgenmod");
	var idspcmod = getCheckList("pm_idspcmod");
	var gen_ex = getElementValue("pm_genmod_ex");
	var spc_ex = getElementValue("pm_spcmod_ex");
	
	if ( gen_ex && gen_ex == "exclude" && idgenmod )
	    idgenmod = "!" + idgenmod;
	
	if ( spc_ex && spc_ex == "exclude" && idspcmod )
	    idspcmod = "!" + idspcmod;
	
	params.idgenmod = idgenmod;
	params.idspcmod = idspcmod;
    }
    
    // This function is called when any of the abundance options is changed.

    function checkAbund ( )
    {
	var abund_type = getElementValue("pm_abund_type");
	var abund_min = getElementValue("pm_abund_min");
	
	var abund_value = '';
	
	if ( abund_type && abund_type != 'none' )
	{
	    abund_value = abund_type;
	    
	    if ( abund_min && abund_min != '' )
	    {
		if ( patt_int_pos.test(abund_min) )
		{
		    abund_value += ':' + abund_min;
		    setErrorMessage("pe_abund_min", "");
		    param_errors.abundance = 0;
		}
		
		else
		{
		    setErrorMessage("pe_abund_min", "Minimum abundance must be a positive integer");
		    param_errors.abundance = 1;
		}
	    }
	    params.abundance = abund_value;
	}
	
	else
	{
	    params.abundance = "";
	}
	
	if ( abund_min == "" )
	{
	    setErrorMessage("pe_abund_min", "");
	    param_errors.abundance = 0;
	}
	
	updateFormState();
    }
    
    this.checkAbund = checkAbund;
    
    // This function is called when either of the main text fields in the "Select by time" section
    // are modified.  The values might either be interval names or millions of years.  It is also
    // called when the value of "pm_timerule" or "pm_timebuffer" changes.  The parameter 'select'
    // will be 1 if the first text field was changed, 2 if the second.
    
    function checkInterval ( select )
    {
	var int_age_1 = getElementValue("pm_interval");
	var int_age_2 = getElementValue("pm_interval_2");
	
	var errors = [ ];
	
	params.timerule = getElementValue("pm_timerule");
	params.timebuffer = getElementValue("pm_timebuffer");
	
	// First check the value of the first text field.  If it is empty, then clear both of the
	// corresponding parameter properties.
	
	if ( int_age_1 == "" )
	{
	    params.interval = "";
	    params.ma_max = "";
	}

	else
	{
	    // If it is a number, then set the property 'ma_max' and clear 'interval'.  If the
	    // other text field contains an interval name, clear it.
	    
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
	    
	    // If it contains a digit but is not a number, then the value is invalid.
	    
	    else if ( patt_has_digit.test(int_age_1) )
		errors.push("The string '" + int_age_1 + "' is not a valid age or interval");
	    
	    // If it is the name of a known geologic time interval, then set the property
	    // 'interval' and clear 'ma_max'.  If the other text field contains a number, then
	    // clear it.
	    
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
	    
	    // Otherwise, the value is not valid.
	    
	    else
		errors.push("The interval '" + int_age_1 + "' was not found in the database");
	}
	
	// Repeat this process for the second text field.
	
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
	
	// If the text field values are numbers, check to make sure they were not entered in the
	// wrong order.
	
	if ( params.ma_max && params.ma_min && Number(params.ma_max) < Number(params.ma_min) )
	{
	    errors.push("You must specify the maximum age on the left and the minimum on the right");
	}
	
	// If the 'timebuffer' field is visible and has a value, check to make sure that it is a number.
	
	if ( visible.advanced )
	{
	    if ( params.timerule == 'buffer' && params.timebuffer != "" && ! patt_dec_pos.test(params.timebuffer) )
		errors.push("invalid value '" + params.timebuffer + "' for timebuffer");
	}
	
	// If we have discovered any errors so far, display them and set the appropriate property
	// of the 'param_errors' javascript object.
	
	if ( errors.length )
	{
	    param_errors.interval = 1;
	    setErrorMessage("pe_interval", errors);
	}

	// Otherwise, clear them both.
	
	else
	{
	    param_errors.interval = 0;
	    setErrorMessage("pe_interval", "");
	}
	
	// Adjust visibility of controls
	
	if ( params.timerule == 'buffer' )
	    showByClass('buffer_rule');
	
	else
	    hideByClass('buffer_rule');
	
	// Update the form state
	
	updateFormState();
    }
    
    this.checkInterval = checkInterval;
    
    
    // Check whether the specified interval name is registered as a property of the javascript
    // object 'api_data.interval', disregarding case.
    
    function validInterval ( interval_name )
    {
	if ( typeof interval_name != "string" )
	    return false;
	
	if ( api_data.interval[interval_name.toLowerCase()] )
	    return true;
	
	else
	    return false;
    }
    
    
    // This function is called when any of the fields in the "Select by location" section other
    // than the longitude/latitude coordinate fields are modified.
    
    function checkCC ( )
    {
	// Get the value of the dropdown menus for selecting continents and countries.  If the
	// value of either is '**', then show the full set of checkboxes for continents and the
	// "multiple countries" text field for countries.
	
	var continent_select = getElementValue("pm_continent");
	if ( continent_select == '**' ) showByClass('mult_cc3');
	else hideByClass('mult_cc3');
	
	var country_select = getElementValue("pm_country");
	// multiple_div = document.getElementById("pd_countries");
	if ( country_select == '**' ) showByClass('mult_cc2');
	else hideByClass('mult_cc2');
	
	var continent_list = '';
	var country_list = '';
	var errors = [ ];
	var cc_ex = getElementValue("pm_ccex");
	var cc_mod = getElementValue("pm_ccmod");
	
	// Get the selected continent or continents, if any
	
	if ( continent_select && continent_select != '--' && continent_select != '**' )
	    continent_list = continent_select;
	
	else if ( continent_select && continent_select == '**' )
	{
	    continent_list = getCheckList("pm_continents");
	}
	
	// Get the selected country or countries, if any.  If the user selected "minus" for the
	// value of pm_ccmod, then put a ^ before each country code.
	
	if ( country_select && country_select != '--' && country_select != '**' )
	{
	    country_list = country_select;
	    
	    if ( cc_mod == "sub" ) country_list = '^' + country_list;
	}

	// If the user selected "Multiple", then look at the value of the "multiple countries"
	// text field.  Split this into words, ignoring commas, spaces, and ^, and check to make
	// sure that each word is a valid country code.
	
	else if ( country_select && country_select == '**' )
	{
	    country_list = getElementValue("pm_countries");
	    
	    if ( country_list != '' )
	    {
		var cc_list = [ ];
		var values = country_list.split(/[\s,^]+/);
		
		for ( var i=0; i < values.length; i++ )
		{
		    var canonical = values[i].toUpperCase();
		    // var key = canonical.replace(/^\^/,'');
		    
		    // if ( key == '' ) next;
		    
		    // if ( cc_mod == "sub" ) canonical = "^" + canonical;
		    
		    if ( api_data.country_name[canonical] )
		    {
			if ( cc_mod == "sub" ) cc_list.push("^" + canonical);
			else cc_list.push(canonical);
		    }
		    
		    else
			errors.push("Unknown country code '" + canonical + "'");
		}
		
		country_list = cc_list.join(',');
	    }
	}
	
	params.cc = '';

	// If we have found a valid list of continents and/or a valid list of countries, set
	// the "cc" property of the javascript object 'params' to the entire list.  Add a prefix
	// of "!" if the user selected "exclude" instead of "include".
	
	if ( country_list != '' || continent_list != '' )
	{
	    var prefix = '';
	    if ( cc_ex == "exclude" ) prefix = '!';
	    
	    if ( continent_list != '' && country_list != '' )
		params.cc = prefix + continent_list + ',' + country_list;
	    
	    else
		params.cc = prefix + continent_list + country_list;
	}
	
	// We have detected any errors, display them and set the 'cc' property of the 'param_errors'
	// object.  Otherwise, clear the error indicator and property.
	
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
	
	// Now check to see if the user specified any tectonic plates.  If so, validate the list
	// and adjust the objects 'params' and 'param_errors' accordingly.
	
	var plate_list = getElementValue("pm_plate");
	var plate_model = getElementValue("pm_pgmodel");
	var plate_ex = getElementValue("pm_plate_ex");
	errors = [ ];
	
	if ( plate_list != '' )
	{
	    // var match = ( /^\^(.*)/.exec(plate_list) )
	    var plate_exclude = '';

	    if ( plate_ex == "exclude" ) plate_exclude = '^';
	    // if ( match != null )
	    // {
	    // 	plate_list = match[1];
	    // 	plate_exclude = '^';
	    // }
	    
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

	// If we discovered any errors, display them.  Otherwise, clear any messages that were
	// there before.
	
	if ( errors.length )
	{
	    setErrorMessage("pe_plate", errors);
	    param_errors.plate = 1;
	}
	
	else
	{
	    setErrorMessage("pe_plate", "");
	    param_errors.plate = 0;
	}
	
	updateFormState();
    }
    
    this.checkCC = checkCC;
    

    // This function is called when any of the latitude/longitude fields are modified.
    
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
    
    this.checkCoords = checkCoords;

    
    // Check whether the given value is a valid coordinate.  The parameter 'dir' must be one of
    // 'ns' or 'ew', specifying which direction suffixes will be accepted.
    
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


    // Remove directional suffix, if any, and change to a signed number.
    
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
    

    // Return true if the given longitude values specify a region stretching more than 180 degrees
    // around the earth.
    
    function coordsAreReversed ( min, max )
    {
	// First convert the coordinates into signed integers.
	
	var imin = Number(min);
	var imax = Number(max);
	
	return ( imax - imin > 180 || ( imax - imin < 0 && imax - imin > -180 ));
    }
    

    // This function is called when the geological strata input field from "Select by geological
    // context" is modified.
    
    function checkStrat ( )
    {
	var strat = getElementValue("pm_strat");
	
	// If the value contains at least one letter, try to look it up using the API.
	
	if ( strat && /[a-z]/i.test(strat) )
	{
	    params.strat = strat;
	    $.getJSON(data_url + 'strata/list.json?limit=0&rowcount&name=' + strat).done(callbackStrat);
	}
	
	// Otherwise, clear any error messages that may have been displayed previously and clear
	// the parameter value. 
	
	else
	{
	    params.strat = "";
	    param_errors.strat = 0;
	    setErrorMessage("pe_strat", "");
	    updateFormState();
	}
    }
    
    this.checkStrat = checkStrat;
    
    
    // This function is called when the API request to look up strata names returns.  If any
    // records are returned, assume that at least some of the names are okay.  We currently have
    // no way to determine which names match known strata and which do not, which is an
    // unfortunate limitation.
    
    function callbackStrat  ( response )
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
    
    
    // This function is called when any of the Lithology form elements in the "select by
    // geological context" section are modified.
    
    function checkLith ( )
    {
	var lith_ex = getElementValue("pm_lithex");
	var lith_type = getCheckList("pm_lithtype");
	
	if ( lith_ex && lith_ex == "exclude" && lith_type && lith_type != "" )
	    lith_type = "!" + lith_type;
	
	params.lithtype = lith_type;
	
	updateFormState();
    }
    
    this.checkLith = checkLith;
    
    // This function is called when any of the Environment form elements in the "Select by
    // geological context" section are modified.
    
    function checkEnv ( )
    {
	var env_ex = getElementValue("pm_envex");
	var env_mod = getElementValue("pm_envmod");
	var env_type = getCheckList("pm_envtype");
	var env_zone = getCheckList("pm_envzone");
	
	if ( env_ex && env_ex == "exclude" && env_type && env_type != "" )
	    env_type = "!" + env_type;
	
	if ( env_mod && env_mod == "sub" )
	    env_zone = "^" + env_zone.replace(/,/g, ',^');
	
	if ( env_zone )
	    env_type += ',' + env_zone;
	
	params.envtype = env_type;
	
	updateFormState();
    }
    
    this.checkEnv = checkEnv;
    
    
    // This function is called whenever the "created after" or "authorized/entered by" form
    // elements in the "Select by metadata" section are modified, or when the corresponding text
    // fields are modified.  The parameter 'section' indicates which row was modified, because
    // there may be more than one depending upon the data type currently selected.
    
    function checkMeta ( section )
    {
	var errors = [];
	
	// The value of the "..._cmdate" field must match the pattern 'patt_date'.
	
	var crmod_value = getElementValue("pm_" + section + "_crmod");
	var cmdate_value = getElementValue("pm_" + section + "_cmdate");
	
	var datetype = section + "_crmod";
	var datefield = section + "_cmdate";
	
	if ( cmdate_value && cmdate_value != '' )
	{
	    params[datetype] = crmod_value;
	    params[datefield] = cmdate_value;
	    
	    if ( ! patt_date.test(cmdate_value) )
	    {
		param_errors[datefield] = 1;
		errors.push("Bad value '" + cmdate_value + "'");
	    }
	    
	    else
	    {
		param_errors[datefield] = 0;
	    }
	}
	
	else
	{
	    params[datetype] = crmod_value;
	    params[datefield] = "";
	    param_errors[datefield] = 0;
	}
	
	// Now we check the value of the "..._aename" field.
	
	var authent_value = getElementValue("pm_" + section + "_authent");
	var aename_value = getElementValue("pm_" + section + "_aename").trim();
	
	var nametype = section + "_authent";
	var namefield = section + "_aename";
	var rebuild = [ ];
	var exclude = '';
	
	if ( aename_value && aename_value != '' )
	{
	    param_errors[namefield] = 0;
	    
	    // If the value starts with !, we have an exclusion.  Pull it
	    // out and save for the end when we are rebuilding the value
	    // string.
	    
	    var expr = aename_value.match(/^!\s*(.*)/);
	    if ( expr )
	    {
		aename_value = expr[1];
		exclude = '!';
	    }
	    
	    // Split the field value on commas, and check each individual name.
	    
	    var names = aename_value.split(/,\s*/);
	    
	    for ( var i = 0; i < names.length; i++ )
	    {
		// Skip empty names, i.e. repeated commas.
		
		if ( ! names[i] ) continue;
		
		// If we cannot find the name, then search through all of
		// the known names to try for a match.
		
		if ( ! api_data.valid_name[names[i]] )
		{
		    var check = names[i].toLowerCase().trim();
		    var init = '';
		    var subs;
		    
		    if ( subs = names[i].match(/^(\w)\w*[.]\s*(.*)/) )
		    {
			init = subs[1].toLowerCase();
			check = subs[2].toLowerCase();
		    }
		    
		    var matches = [];
		    
		    for ( var j = 0; j < api_data.user_match.length; j++ )
		    {
			if ( check == api_data.user_match[j].substr(0,check.length) )
			{
			    if ( init == '' || init == api_data.user_matchinit[j] )
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
			
			var result = api_data.user_names[matches[0]];
			
			for ( var k = 1; k < matches.length; k++ )
			{
			    result = result + ", " + api_data.user_names[matches[k]];
			}
			
			errors.push("Ambiguous name '" + names[i] + "' matches: " + result);
			rebuild.push(names[i]);
		    }
		    
		    else
		    {
			rebuild.push(api_data.user_names[matches[0]]);
		    }
		}
		
		else
		{
		    rebuild.push(names[i]);
		}
	    }
	    
	    params[nametype] = authent_value;
	    params[namefield] = exclude + rebuild.join(',');
	    aename_value = exclude + rebuild.join(', ');
	}
	
	else
	{
	    params[nametype] = authent_value;
	    params[namefield] = "";
	    param_errors[namefield] = 0;
	}
	
	// If we detected any errors, display them.  Otherwise, clear any errors that were
	// displayed previously.
	
	if ( errors.length ) setErrorMessage("pe_meta_" + section, errors);
	else setErrorMessage("pe_meta_" + section, "");
	
	updateFormState();
    }
    
    this.checkMeta = checkMeta;
    
    
    // This function is called when one of the free-text fields (currently only 'pm_coll_re') in
    // the "Select by metadata" section is modified.  It simply stores the value in the
    // corresponding property of the 'params' object if it is not empty.
    
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
    
    this.checkMetaText = checkMetaText;
    
    
    // This function is called when one of the fields 'pm_meta_id_list' or 'pm_meta_id_select' is
    // modified.  The parameter 'selector' indicates which one.  The former of the two fields is
    // expected to hold one or more PBDB object identifiers, either numeric or extended.
    
    function checkMetaId ( selector )
    {
	var id_list = getElementValue( 'pm_meta_id_list' );
	var id_type = getElementValue( 'pm_meta_id_select' );
	var id_param = id_param_map[id_type];
	
	if ( id_type == '' )
	{
	    params["meta_id_list"] = '';
	    param_errors["meta_id"] = 0;
	    setErrorMessage("pe_meta_id", "");
	}
	
	else
	{
	    // Split the list on commas/whitespace.
	    
	    var id_strings = id_list.split(/[\s,]+/);
	    var id_key = { };
	    var key_list = [ ];
	    var param_list = [ ];
	    var errors = [ ];
	    
	    // Check each identifier individually.
	    
	    for ( var i=0; i < id_strings.length; i++ )
	    {
		// If it is an extended identifier, keep track of all the different
		// three-character prefixes we encounter while traversing the list using the
		// object 'id_key' and array 'key_list'.
		
		if ( patt_extid.test( id_strings[i] ) )
		{
		    param_list.push(id_strings[i]);
		    var key = id_strings[i].substr(0,3);
		    
		    if ( ! id_key[key] )
		    {
			key_list.push(key);
			id_key[key] = 1;
		    }
		}
		
		// If it is a numeric identifier, just add it to the parameter list.
		
		else if ( patt_int_pos.test( id_strings[i] ) )
		{
		    param_list.push(id_strings[i]);
		}
		
		// Anything else is an error.
		
		else if ( id_strings[i] != '' )
		{
		    errors.push("invalid identifier '" + id_strings[i] + '"');
		}
	    }
	    
	    // If we found more than one different identifier prefix, that is an error.
	    
	    if ( key_list.length > 1 )
	    {
		errors.push("You may not specify identifiers of different types");
	    }
	    
	    // If we found any errors, display them.
	    
	    if ( errors.length )
	    {
		params["meta_id_list"] = '';
		param_errors["meta_id"] = 1;
		setErrorMessage("pe_meta_id", errors);
	    }
	    
	    // Otherwise, construct the proper parameter value by joining all of the identifiers
	    // we found.
	    
	    else
	    {
		params["meta_id_list"] = param_list.join(',');
		
		// If we found an extended-identifier prefix, then set the "select" element to the
		// corresponding item.
		
		if ( key_list.length == 1 )
		{
		    id_param = id_param_map[key_list[0]];
		    var select_index = id_param_index[key_list[0]];
		    var select_elt = myGetElement("pm_meta_id_select");
		    if ( select_elt )
		    {
			select_elt.selectedIndex = select_index;
		    }
		}
		
		// The variable 'id_param' was set from the selection dropdown, at the top of this
		// function.  It indicates which parameter name to use, as a function of the
		// selected identifier type.  For example, if the user selected "Occurrence" or at
		// least one of the identifiers started with "occ:", then the parameter name would
		// be "occ_id".
		
		if ( id_param )
		{
		    params["meta_id_param"] = id_param;
		    param_errors["meta_id"] = 0;
		    setErrorMessage("pe_meta_id", "");
		}
		
		// If for some reason we haven't found a proper parameter name, then display an
		// error message.
		
		else
		{
		    params["meta_id_param"] = '';
		    param_errors["meta_id"] = 1;
		    setErrorMessage("pe_meta_id", ["Unknown identifier type '" + id_param + "'"]);
		}
	    }
	}
	
	updateFormState();
    }
    
    this.checkMetaId = checkMetaId;
    
    
    // This function is incomplete, and the HTML that would call it is commented out until it can
    // be reworked later.
    
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
    
    this.checkRef = checkRef;
    
    
    // This function is called when the "include metadata" checkbox in the "Choose output options"
    // section is modified.
    
    function checkOutputOpts ( )
    {
	var metadata_elt = myGetElement("pm_output_metadata");
	params.output_metadata = metadata_elt.checked;
	
	updateFormState();
    }
    
    this.checkOutputOpts = checkOutputOpts;
    
    
    // This function is called when one of the "Output order" dropdowns in the "Choose output
    // options" section is modified.  The 'selection' parameter indicates which one.  I'm not
    // actually sure this does anything useful at this point.
    
    function checkOrder ( selection )
    {
	if ( selection && selection != 'dir' )
	{
	    var order_elt = myGetElement("pm_order_dir");
	    if ( order_elt ) order_elt.value = '--';
	}
	
	updateFormState();
    }
    
    this.checkOrder = checkOrder;
    
    
    // This function is called if the "include all boldfaced output blocks" element in the "Output
    // options" section is modified.
    
    function checkFullOutput ( )
    {
	var full_value = getElementValue("pm_fulloutput");
	var elts = document.getElementsByName(output_section);
	var i;
	
	full_checked[output_section] = full_value;
	
	for ( i=0; i<elts.length; i++ )
	{
	    var block_code = elts[i].value;
	    
	    if ( output_full[output_section][block_code] )
	    {
		if ( full_value ) elts[i].checked = 1;
		else elts[i].checked = 0;
	    }
	}

	updateFormState();
    }
    
    this.checkFullOutput = checkFullOutput;
    
    
    // This function is called if the "reference types" checkboxes are modified.  These are only
    // visible for certain record types.
    
    function checkRefopts ( )
    {
    	params.reftypes = getCheckList("pm_reftypes");
    	if ( params.reftypes == "auth,class" ) params.reftypes = 'taxonomy';
    	else if ( params.reftypes == "auth,class,ops" ) params.reftypes = 'auth,ops';
    	else if ( params.reftypes == "auth,class,ops,occs,colls" ) params.reftypes = 'all'
    	else if ( params.reftypes == "auth,ops,occs,colls" ) params.reftypes = 'all'
    	updateFormState();
    }
    
    this.checkRefopts = checkRefopts;
    
    
    // This function is called when the "Limit number of records" field in the "Choose output
    // options" section is modified.
    
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
	
	// The value can either be one number, or two separated by commas.  In the second case,
	// the first will be taken as an offset and the second as a limit.
	
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
    
    this.checkLimit = checkLimit;
    
    
    // This function is called whenever some element changes that could change the overall state
    // of the application.  The only thing it currently does is to update the main URL, but other
    // things could be added later.
    
    function updateFormState ( )
    {
	if ( ! no_update ) updateMainURL();
    }
    
    this.updateFormState = updateFormState;
    
    
    // The following function provides the core functionality for this application.  It is called
    // whenever any form element changes, and updates the "main URL" element to reflect the
    // changes.  This main URL can then be used to download data.
    
    // Many of the form elements are not queried directly.  Rather, the properties of the
    // javascript object 'parameters' are updated whenever any of these elements change value, and
    // these properties are used in the function below to generate the URL.  The properties of the
    // object 'param_errors' are used to indicate whether any errors were found when the values
    // were checked.  Only elements requiring no interpretation or checking are queried directly.
    
    // Only the form elements in visible sections are used.  Any section that is collapsed (not
    // visible) is ignored.  However, if it is opened again then this function will be immediately
    // called and the values entered there will be applied to the main URL.  The properties of the
    // javascript object 'visible' keep track of what is visible and what is hidden.
    
    function updateMainURL ( )
    {
	// The following variable keeps track of the parameters and values that make up the URL.
	
	var param_list = [ ];
	
	// The following variable will be set to true if a "significant parameter" is specified.
	// Otherwise, the main URL will not be generated.  Such parameters include the taxonomic
	// name, time interval, stratum, etc.  In other words, some parameter that will
	// substantially restrict the result set.  The "select all records" checkbox also counts,
	// just in case somebody really wants to download all records of a particular type.
	
	var has_main_param = 0;

	// The following variable will be set to true if any errors are encountered in association
	// with a visible form element.  This will prevent the main URL from being generated.
	
	var errors_found = 0;

	// The following variables indicate that an occurrence operation or a taxon operation must
	// be generated instead of the default operation for the selected record type.
	
	var occs_required = 0;
	var taxon_required = 0;

	// The following variable is set to true if certain form elements are filled in, to
	// indicate that the "all_records" parameter must be added in order to satisfy the
	// requirements of the API.
	
	var all_required = 0;

	// The following variable indicates the API operation (i.e. "occs/list", "taxa/list",
	// etc.)  to be used.  It is set from the default operation for the selected record type,
	// but may be modified under certain circumstances.
	
	var my_op = data_op;

	// If the "Select by taxonomy" section is visible, then go through the parameters it
	// contains.  If the "advanced" parameters are visible, then check them too.
	
	if ( visible.f1 )
	{
	    if ( params.base_name && params.base_name != "" ) {
		param_list.push("base_name=" + params.base_name);
		has_main_param = 1;
		taxon_required = 1;
	    }
	    
	    if ( param_errors.base_name ) errors_found = 1;
	    
	    if ( data_type == "occs" || data_type == "specs" || data_type == "meas" ||
		 data_type == "colls" || data_type == "strata" )
	    {
		var taxonres = getElementValue("pm_taxon_reso");
		if ( taxonres && taxonres != "" )
		    param_list.push("taxon_reso=" + taxonres);
		
		if ( visible.advanced )
		{
		    if ( params.ident && params.ident != 'latest' )
			param_list.push("ident=" + params.ident);
		    
		    if ( params.idqual )
			param_list.push("idqual=" + params.idqual);
		    
		    if ( params.idgenmod || params.idspcmod )
		    {
			if ( params.idgenmod == params.idspcmod )
			    param_list.push("idmod=" + params.idgenmod);
			
			else
			{
			    if ( params.idgenmod )
				param_list.push("idgenmod=" + params.idgenmod);
			    
			    if ( params.idspcmod )
				param_list.push("idspcmod=" + params.idspcmod);
			}			
		    }
		}
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
	
	// If the "Select by time" section is visible, then go through the parameters it
	// contains.  If the "advanced" parameters are visible, then check them too.
	
	if ( visible.f2 )
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

	// If the section "Select by location" is visible, then go through the parameters it
	// contains.  If the "advanced" parameters are visible, then check them too.
	
	if ( visible.f3 )
	{
	    if ( params.cc && params.cc != "" )
	    {
		param_list.push("cc=" + params.cc);
		occs_required = 1;
		has_main_param = 1;
	    }
	    
	    if ( visible.advanced && params.plate && params.plate != "" )
	    {
		param_list.push("plate=" + params.plate);
		occs_required = 1;
		has_main_param = 1;
	    }
	    
	    if ( visible.advancd && (param_errors.cc || param_errors.plate) ) errors_found = 1;
	    
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
	
	// If the section "Select by geological context" is visible, then go through the
	// parameters it contains.  If the "advanced" parameters are visible, then check them too.
	
	if ( visible.f4 )
	{
	    if ( params.strat && params.strat != "" ) {
		param_list.push("strat=" + params.strat);
		occs_required = 1;
		has_main_param = 1
	    }
	    
	    if ( param_errors.strat ) errors_found = 1;
	    
	    if ( visible.advanced && params.lithtype && params.lithtype != "" ) {
		param_list.push("lithology=" + params.lithtype);
		occs_required = 1;
	    }
	    
	    if ( visible.advanced && params.envtype && params.envtype != "" ) {
		param_list.push("envtype=" + params.envtype);
		occs_required = 1;
	    }
	}
	
	// If the section "Select by specimen is visible, then go through the parameters it contains.
	
	if ( visible.f6 )
	{
	    if ( params.abundance )
	    {
		if ( param_errors.abundance ) errors_found = 1;
		param_list.push("abundance=" + params.abundance );
		occs_required = 1;
	    }
	}
	
	// If the section "Select by metadata" is visible, then go through the parameters it
	// contains.  Only some of the rows will be visible, depending on the selected record type.
	
	if ( visible.f5 )
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
	    
	    if ( visible.pd_meta_id || 1 )
	    {
		if ( params.meta_id_list ) {
		    param_list.push(params.meta_id_param + "=" + params.meta_id_list);
		    occs_required = 1;
		    has_main_param = 1;
		}
		
		if ( param_errors.meta_id ) errors_found = 1;
	    }
	    
	    if ( visible.meta_specs )
	    {
		if ( params.specs_cmdate ) {
		    param_list.push("specs_" + params.specs_crmod + "=" + params.specs_cmdate);
		    occs_required = 1;
		    all_required = 1;
		}
		
		if ( params.specs_aename ) {
		    param_list.push("specs_" + params.specs_authent + "=" + params.specs_aename);
		    occs_required = 1
		    all_required = 1;
		}
		
		if ( param_errors.specs_cmdate || param_errors.specs_aename ) errors_found = 1;
	    }
	    
	    if ( visible.meta_occs )
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
	    
	    if ( visible.meta_colls )
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
	    
	    if ( visible.meta_taxa )
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
	    
	    if ( visible.meta_ops )
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
	    
	    if ( visible.meta_refs )
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
	
	// If the selected record type is either references or taxa selected by reference or
	// opinions, then add the appropriate parameter using the form element that appears just
	// above the"Select by taxonomy" section.
	
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

	// If "include non-public data" is selected, add the parameter 'private'.
	
	if ( params.private && is_contributor )
	{
	    param_list.push("private");
	}
	
	// If the section "output options" is visible, then go through the parameters it contains.
	// This includes specifying which output blocks to return using the "show" parameter.
	
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

	    if ( param_errors.limit ) errors_found = 1;
	}
	
	// Otherwise, add "show=acconly" if indicated by the "accepted names only" checkbox
	// in the "Select by taxonomy" section.
	
	else if ( (data_type == 'occs' || data_type == 'specs' ) && visible.f1)
	{
	    var acc_only = myGetElement("pm_acc_only");
	    if ( acc_only && acc_only.checked )
		param_list.push('show=acconly');
	}
	
	// Now alter the operation, if necessary, based on the chosen parameters
	
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
	
	// If no "significant" parameter has been entered, then see if we need to add the
	// parameter 'all_records' in order to satisfy the requirements of the API.
	
	if ( ! has_main_param )
	{
	    var all_records_elt = myGetElement("pm_all_records");

	    // If 'all_required' is true, then add the parameter.  This flag will be true if
	    // certain of the fields in the "Metadata" section are filled in.
	    
	    if ( all_required )
	    {
		param_list.push('all_records');
		has_main_param = 1;
	    }
	    
	    // Do the same if the "select all records" box is checked.  In this case,
	    // Set the 'confirm_download' flag so that a confirmation dialog box will
	    // be generated before a download is initiated.
	    
	    else if ( all_records_elt && all_records_elt.checked )
	    {
		param_list.push('all_records');
		has_main_param = 1;
		confirm_download = 1;
	    }
	}
	
	// Now, if any errors were found, or if no "significant" parameter was entered,
	// then display a message for the user.
	
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

	// Otherwise, generate the URL and display it.
	
	else
	{
	    
	    var param_string = param_list.join('&');
	    
	    // Construct the new URL
	    
	    var new_url = data_url + my_op + data_format + '?';
	    
	    if ( params.output_metadata )
		new_url += 'datainfo&rowcount&';
	    
	    new_url += param_string;
	    
	    url_elt.textContent = new_url;
	    url_elt.href = new_url;
	}
	
	// Adjust metadata subsections according to the selected operation.
	
	url_op = my_op;
	
	// switch ( my_op )
	// {
	//     case 'specs/list':
	//     selectMetaSub('pd_meta_specs');
	//     // showElement('pd_meta_occs');
	//     // showElement('pd_meta_colls');
        //     case 'occs/list':
        //     case 'occs/diversity':
        //     case 'occs/taxa':
	//     case 'occs/strata':
    	//     selectMetaSub('pd_meta_occs');
	//     showElement('pd_meta_colls');
    	//     break;
        //     case 'colls/list':
    	//     selectMetaSub('pd_meta_colls');
	//     showElement('pd_meta_occs');
    	//     break;
    	//     case 'taxa/list':
    	//     selectMetaSub('pd_meta_taxa');
    	//     break;
    	//     case 'opinions/list':
    	//     selectMetaSub('pd_meta_ops');
    	//     break;
        //     case 'taxa/opinions':
    	//     selectMetaSub('pd_meta_ops');
	//     showElement('pd_meta_taxa');
    	//     break;
    	//     case 'refs/list':
	//     selectMetaSub('pd_meta_refs');
	//     break;
    	//     case 'occs/refs':
	//     case 'occs/taxabyref':
	//     selectMetaSub('pd_meta_occs');
	//     showElement('pd_meta_refs');
	//     break;
        //     case 'taxa/refs':
	//     case 'taxa/byref':
    	//     selectMetaSub('pd_meta_taxa' );
	//     showElement('pd_meta_refs');
    	//     break;
	// }
    }

    
    // Make the named section visible, and hide the others.
    
    function selectMetaSub ( subsection )
    {
	var subs = { pd_meta_occs: 1, pd_meta_colls: 1, pd_meta_taxa: 1,
		     pd_meta_ops: 1, pd_meta_refs: 1, pd_meta_specs: 1 };
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

    // Return a list of the values that should be passed to the parameter 'show' in order to get
    // the output blocks selected on this form.  If the checkbox 'pm_acc_only' in the Taxonomy
    // section is checked, add 'acconly' to the list.
    
    function getOutputList ( )
    {
	var elts = document.getElementsByName(output_section);
	var full_value = getElementValue("pm_fulloutput");
	var i;
	var selected = [];

	if ( full_value )
	    selected.push('full');
	
	for ( i=0; i<elts.length; i++ )
	{
	    var value = elts[i].value;
	    
	    if ( elts[i].checked )
	    {
		if ( ! ( full_value && output_full[output_section][value] ) )
		    selected.push(value);
	    }
	}
	
	if ( visible.f1 && (data_type == 'occs' || data_type == 'specs'))
	{
	    var acc_only = myGetElement("pm_acc_only");
	    if ( acc_only && acc_only.checked )
		selected.push('acconly');
	}
	
	return selected.join(',');
    }
    

    // Show or hide the "advanced" form elements.
    
    function setFormMode ( mode )
    {
	if ( mode == "advanced" )
	{
	    form_mode = "advanced";
	    showByClass('advanced');
	}
	
	else
	{
	    form_mode = "simple";
	    hideByClass('advanced');
	}
	
	updateFormState();
    }
    
    this.setFormMode = setFormMode;
    

    // Set or clear the "include non-public data" parameter.
    
    function setPrivate ( flag )
    {
	if ( flag && flag != "0" )
	    params.private = 1;
	else
	    params.private = 0;
	
	updateFormState();    
    }
    
    // Set it to false by default when the App is loaded.
    
    this.setPrivate = setPrivate;
    

    // Select the indicated record type.  This specifies the type of record that will be returned
    // when a download is initiated.  Depending upon the record type, various sections of the form
    // will be shown or hidden.
    
    function setRecordType ( type )
    {
	data_type = type;
	
	var record_label;
	var type_sections = [ 'type_occs', 'type_colls', 'type_specs', 'type_strata',
			      'type_diversity', 'type_taxa', 'taxon_reso', 'taxon_range', 'div_reso',
			      'type_ops', 'type_refs', 'acc_only', 'meta_specs', 'meta_occs',
			      'meta_colls', 'meta_taxa', 'meta_ops', 'meta_refs' ];
	var show_sections = { };
	
	if ( type == 'occs' )
	{
	    data_op = 'occs/list';
	    output_section = 'od_occs';
	    output_order = 'pm_occs_order';
	    record_label = 'occurrence records';
	    show_sections = { type_occs: 1, taxon_reso: 1, acc_only: 1, meta_occs: 1,
			      meta_colls: 1 };
	}
	
	else if ( type == 'colls' )
	{
	    data_op = 'colls/list';
	    output_section = 'od_colls';
	    output_order = 'pm_colls_order';
	    record_label = 'collection records';
	    show_sections = { type_colls: 1, taxon_reso: 1, meta_occs: 1, meta_colls: 1 };
	}
	
	else if ( type == 'specs' )
	{
	    data_op = 'specs/list';
	    output_section = 'od_specs';
	    output_order = 'pm_occs_order';
	    record_label = 'specimen records';
	    show_sections = { type_specs: 1, taxon_reso: 1, acc_only: 1, meta_occs: 1,
			      meta_specs: 1 };
	}
	
	else if ( type == 'meas' )
	{
	    data_op = 'specs/measurements';
	    output_section = 'od_meas';
	    output_order = 'pm_occs_order';
	    record_label = 'measurement records';
	    show_sections = { type_meas: 1, taxon_reso: 1, meta_occs: 1,
			      meta_specs: 1 };
	}
	
	else if ( type == 'strata' )
	{
	    data_op = 'occs/strata';
	    output_section = 'od_strata';
	    output_order = 'pm_strata_order';
	    record_label = 'stratum records';
	    show_sections = { type_strata: 1, taxon_reso: 1, meta_occs: 1, meta_colls: 1 };
	}
	
	else if ( type == 'diversity' )
	{
	    showHideSection('f2', 'show');
	    data_op = 'occs/diversity';
	    output_section = 'od_diversity';
	    output_order = 'none';
	    record_label = 'occurrence records';
	    show_sections = { type_diversity: 1, div_reso: 1, meta_occs: 1 };
	}
	
	else if ( type == 'taxa' )
	{
	    data_op = 'taxa/list';
	    output_section = 'od_taxa';
	    output_order = 'pm_taxa_order';
	    record_label = 'taxonomic name records';
	    show_sections = { type_taxa: 1, taxon_range : 1, acc_only: 1, meta_taxa: 1,
			      meta_occs: 1 };
	}
	
	else if ( type == 'ops' )
	{
	    data_op = 'opinions/list';
	    output_section = 'od_ops';
	    output_order = 'pm_ops_order';
	    record_label = 'taxonomic opinion records';
	    show_sections = { type_ops: 1, taxon_range: 1, acc_only: 1, meta_taxa: 1,
			      meta_ops: 1, meta_occs: 1 };
	}
	
	else if ( type == 'refs' )
	{
	    data_op = 'taxa/refs';
	    output_section = 'od_refs';
	    output_order = 'pm_refs_order';
	    record_label = 'bibliographic reference records';
	    show_sections = { type_refs: 1, taxon_range: 1, acc_only: 1, meta_taxa: 1,
			      meta_occs: 1, meta_refs: 1 };
	}
	
	else if ( type == 'byref' )
	{
	    data_op = 'taxa/byref';
	    output_section = 'od_taxa';
	    output_order = 'pm_refs_order';
	    record_label = 'taxonomic name records';
	    show_sections = { type_refs: 1, taxon_range: 1, acc_only: 1, meta_taxa: 1, meta_refs: 1 };
	}
	
	else
	{
	    alert("Error! (" + type + ")");
	    output_section = 'none';
	    output_order = 'none';
	}
	
	// Set the "include all output blocks" form element according to the saved value.
	
	var full_elt = myGetElement("pm_fulloutput");
	
	if ( full_checked[output_section] ) full_elt.checked = 1;
	else full_elt.checked = 0;
	
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
	
	// showElement('pd_meta_coll_re');
	
	// Then store the new type, and update the main URL
	
	updateFormState();
    }
    
    this.setRecordType = setRecordType;
    
    
    // Select the indicated output format.  This is the format in which the downloaded
    // data will be expressed.
    
    function setFormat ( type )
    {
	data_format = '.' + type;
	if ( data_type != 'refs' && type != 'ris' ) non_ref_format = data_format;
	else if ( data_type == 'refs' ) ref_format = data_format;
	
	updateFormState();
    }
    
    this.setFormat = setFormat;
    

    // This function is called when the "Test" button is activated.  Unless a record limit is
    // specified, a limit of 100 will be added.  Also, the output format ".csv" will be changed to
    // ".txt", which will (in most browsers) cause the result to be displayed in the browser
    // window rather than saved to disk.
    
    function testMainURL ( )
    {
	var url = document.getElementById("mainURL").textContent;
	
	if ( ! url.match(/http/i) ) return;
	
	if ( data_format == '.csv' ) url = url.replace('.csv','.txt');
	else url += '&textresult';
	
	if ( ! params.limit && url_op != 'occs/diversity' ) url += '&limit=100';
	
	window.open(url);
    }
    
    this.testMainURL = testMainURL;


    // This function is called when the "Download" button is activated.  If the 'confirm_download'
    // flag is true, generate a dialog box before initiating the download.
    
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
    
    this.downloadMainURL = downloadMainURL;
}

