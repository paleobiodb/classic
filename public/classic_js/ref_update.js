//
// This script enables Classic pages to update the current reference
// display when a new reference is selected in the refs app.
// 
// Written by: Michael McClennen
// Created: 2025-10-16


window.addEventListener("storage", check_for_ref_update);


async function check_for_ref_update (e) {

    if ( e.key == "pbdb_selected_ref_data" ) {

	if ( !e.newValue ) {
	    update_navbar_ref(null);
	}

	else if ( e.newValue == "LOAD" ) {
	    fetch_selected_ref();
	}

	else {

	    try {
		let selected_ref_data = JSON.parse(e.newValue);
		update_navbar_ref(selected_ref_data);
	    }

	    catch (e) {
		window.alert(`Error while parsing selected reference: ${e.message}`);
	    }
	}
    }
}


async function fetch_selected_ref () {

    let endpoint = `refs/selected.json?show=formatted,attr&markrefs`;

    let response = await APIRequest(data_url + endpoint);

    if ( response.records && response.records[0] ) {
	selected_ref_data = response.records[0];
	localStorage.setItem("pbdb_selected_ref_data", JSON.stringify(selected_ref_data));
    }
						
    else {
	selected_ref_data = null;
	localStorage.setItem("pbdb_selected_ref_data", "");
    }

    update_navbar_ref(selected_ref_data);
}


function update_navbar_ref (ref_data) {

    try {
	let ref_elt = document.getElementById("pbdb_selected_ref");

	if ( ref_data && ref_data.oid ) {
	    let ref_attr = ref_data.atr || "???";
	    if ( ! /\d\d\d\d/.test(ref_attr) )
		ref_attr = `${ref_data.atr} ${ref_data.pby}`;

	    let link_elt = ref_elt.firstElementChild;
	    if ( ! link_elt ) {
		link_elt = document.createElement("a");
		ref_elt.appendChild(link_elt);
	    }

	    link_elt.href = `/app/refs#display=${ref_data.oid}`;
	    link_elt.target = '_blank';
	    link_elt.textContent = ref_attr;
	}

	else
	    ref_elt.textContent = '';
    }

    catch (e) {
	window.alert(`Error while updating the navigation bar reference: ${e.message}`);
    }
}	


