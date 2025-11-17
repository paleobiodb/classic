//
// This script provides a common set of routines for making frontend API requests.
// It is made available to all PBDB web pages and applications.
//
// Written by: Michael McClennen
// Created: 2025-10-16


debug_api_requests = false;


async function APIRequest (query_url, body, method, our_options) {

    if ( debug_api_requests ) {
	console.log(query_url);
	if ( body ) console.log(body);
    }

    let options;

    if ( body ) options = { method: method || "POST",
			    headers: { "Content-Type": "application/json" },
			    body: JSON.stringify(body) };
    else options = { };

    try {

	const response = await fetch(query_url, options);

	if ( response.ok ) {
	    if ( /^application[/]json/.test(response.headers.get('content-type')) ) {
		let content_data = await response.json();
		if ( debug_api_requests ) console.log(content_data);
		return content_data;
	    }
	    else {
		let content_text = await response.text();
		return { text: content_text };
	    }
	}

	else {
	    if ( /^application[/]json/.test(response.headers.get('content-type')) ) {
		let content_data = await response.json();
		if ( debug_api_requests ) console.log(content_data);
		if ( our_options && our_options.no_400 && response.status == "400" ) {
		    return content_data;
		}
		else {
		    handleAPIError(content_data, response.status, response.textStatus);
		    return content_data;
		}
	    }
	    else {
		let content_text = await response.text();
		handleAPIError({ text: content_text}, response.status, response.textStatus);
		return { text: content_text };
	    }
	}
    }

    catch (error) {
	handleAPIError({}, '999', error.message);
	return {};
    }
}


async function APIRequestAsync (query_url, success_func, fail_func) {
	    
    if ( debug_api_requests ) {
	console.log(query_url);
    }

    fetch(query_url)
	.then(async function(response) {
	    try {

		let content_data;

		if ( /^application[/]json/.test(response.headers.get('content-type')) ) {
		    content_data = await response.json();
		    if ( debug_api_requests ) console.log(content_data);
		}

		else {
		    let content_text = await response.text();
		    content_data = { text: content_text };
		    if ( debug_api_requests ) console.log(content_text);
		}

		if ( response.ok )
		    return success_func(content_data);

		else if ( fail_func )
		    fail_func(content_data, response.status, response.textStatus);

		else
		    handleAPIError(content_data, response.status, response.textStatus);
	    }

	    catch (error) {
		if ( fail_func )
		    fail_func({}, '999', error.message);
		else
		    handleAPIError({}, '999', error.message);
		return;
	    }
	});
}


function handleAPIError (content_data, status, textStatus) {

    let message = "API Error: ";

    switch (status) {
	case 999:
	    message += textStatus;
	    break;
	case 400:
	    if ( content_data.errors )
		message += "Bad Request (400) - " + content_data.errors[0];
	    else
		message += "Bad Request (400). Please report this error.";
	    break;
	case 401:
	    message += "Unauthorized (401). Please log in and try again.";
	    break;
	case 403:
	    message += "Forbidden (403). Access to this resource is denied.";
	    break;
	case 404:
	    message += "Not Found (404).";
	    break;
	case 405:
	    message += "Method Not Allowed (405). Please report this error.";
	    break;
	case 408:
	    message += "Request Timeout (408). The request took too long to process.";
	    break;
	case 415:
	    message += "Unsupported Media Type (415). Please report this error.";
	    break;
	case 500:
	    message += "Internal Server Error (500). Please report this error.";
	    break;
	case 502:
	    message += "The API is temporarily down (502). Please try again later.";
	    break;
	case 503:
	    message += "The API is temporarily down (503). Please try again later.";
	    break;
	case 504:
	    message += "The API is temporarily down (504). Please try again later.";
	    break;
	default:
	    message += status + " - " + textStatus;
    }

    window.alert(message);
}

