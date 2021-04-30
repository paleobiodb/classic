//
// Paleobiodb page editor
//



function showHideTemplates ( ) {

    var control = document.getElementById('show_templates');
    var textarea = document.getElementById('edit_templates');
    
    if ( textarea && control && control.checked )
    {
	textarea.style.display = 'block';
    }

    else if ( textarea && control )
    {
	textarea.style.display = 'none';
    }
}

function selectPage ( ) {

    var control = document.forms['page_edit']['page_name'];
    var new_name = control.value;
    
    window.open('/classic/displayPageEditor?page_name=' + new_name, '_self');
}

