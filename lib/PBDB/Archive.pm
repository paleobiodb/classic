#
# PBDB::Archive.pm
#
# Operations relating to data archives.

package PBDB::Archive;

use Wing;
use Ouch;

use strict;

# use URL::Encode qw(url_decode);


sub showArchive {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $dbh = $dbt->{dbh};
    my $sql;
    
    my $archive_id = $q->param('id') || $q->param('archive_id');
    my $archive_no;
    my $error_msg;
    my $archive_record;
    
    if ( $archive_id =~ /dar:(\d+)$/ )
    {
	$archive_no = $1;
    }
    
    elsif ( $archive_id =~ /^\d+$/ )
    {
	$archive_no = $archive_id;
	$archive_id = "dar:$archive_id";
    }
    
    if ( $archive_no && $archive_no > 0 )
    {
	$sql = "SELECT da.*, pe.name as enterer_name, pa.name as authorizer_name,
			date_format(da.created, '%d %b %Y %T') as date_created,
			date_format(da.fetched, '%d %b %Y %T') as date_fetched,
			date_format(da.modified, '%d %b %Y %T') as date_modified
		FROM data_archives as da
		    left join person as pe on pe.person_no = da.enterer_no
		    left join person as pa on pa.person_no = da.authorizer_no
		WHERE archive_no = $archive_no";
	
	$archive_record = $dbh->selectrow_hashref($sql);
	
	if ( $archive_record )
	{
	    $archive_record->{uri} = "$archive_record->{uri_path}?$archive_record->{uri_args}";
	    $archive_record->{archive_id} = $archive_id;
	    $archive_record->{header_label} = $archive_no;
	    $archive_record->{viewable} = $archive_record->{is_public} ? 'public' : 'private';
	    $archive_record->{authent} = $archive_record->{enterer_name} || "prs:$archive_record->{enterer_no}";
	    
	    if ( $archive_record->{authorizer_no} ne $archive_record->{enterer_no} )
	    {
		my $authorizer = $archive_record->{authorizer_name} || "prs:$archive_record->{authorizer_no}";
		$archive_record->{authent} .= " ($authorizer)";
	    }
	    
	    if ( $s && $s->{enterer_no} )
	    {
		$sql = "SELECT permission FROM table_permissions
			WHERE table_name = 'ARCHIVES' and person_no = $s->{enterer_no}
				and permission = 'admin'";
		
		my ($admin_permission) = $dbh->selectrow_array($sql);
		
		if ( $s->{superuser} || $admin_permission ||
		     $archive_record->{enterer_no} eq $s->{enterer_no} ||
		     $archive_record->{authorizer_no} eq $s->{enterer_no} )
		{
		    $archive_record->{editable} = 'yes';
		}
	    }
	}
    }
    
    else
    {
	ouch(400, "bad value '$archive_id' for parameter 'id'");
    }
    
    unless ( $archive_record )
    {
	$error_msg ||= "$archive_id: not found";
	$archive_record = { header_label => $error_msg }
    }
    
    $archive_record->{referer} = Dancer::request->referer;
    
    return $hbo->populateSimple('show_archive', $archive_record);
}


sub requestDOI {
    
    my ($q, $s, $dbt, $hbo) = @_;
    
    my $dbh = $dbt->{dbh};
    my $sql;
    
    # Check to make sure that this is either the active installation or a development
    # installation. In the latter case, a prominent label will be added to the e-mail.
    
    my $pbdb_site = Wing->config->get("pbdb_site");
    
    unless ( $pbdb_site eq 'main' || $pbdb_site eq 'dev' )
    {
	ouch(400, "This request is only valid for the main site or the development site");
    }
    
    # Fetch the metadata for the archive being requested. Return a 400 error if the 'id' parameter
    # is not properly formatted.
    
    my $archive_id = $q->param('id') || $q->param('archive_id');
    my $archive_no;
    my $vars;
    
    if ( $archive_id =~ /dar:(\d+)$/ )
    {
	$archive_no = $1;
    }
    
    elsif ( $archive_id =~ /^\d+$/ )
    {
	$archive_no = $archive_id;
	$archive_id = "dar:$archive_id";
    }
    
    if ( $archive_no && $archive_no > 0 )
    {
	$sql = "SELECT da.*, year(da.fetched) as pubyr
		FROM data_archives as da
		WHERE archive_no = $archive_no";
	
	$vars = $dbh->selectrow_hashref($sql);
    }
    
    else
    {
	ouch(400, "bad value '$archive_id' for parameter 'id'");
    }
    
    # If a record was found, check to make sure that this user has either edit or admin permission
    # on this archive record. If so, send e-mail using the template from the directory
    # var/mkits/request_doi.mkit. If this succeeds, change the status of the record.
    
    if ( $vars )
    {
	# First make sure that this user has edit permission on this archive record. If the
	# current user is either a superuser or else is the enterer or authorizer of this record,
	# then they can request a DOI for it.
	
	my $authorized;
	
	if ( $s && $s->{enterer_no} )
	{
	    if ( $s->{superuser} ||
		 $s->{enterer_no} eq $vars->{enterer_no} ||
		 $s->{enterer_no} eq $vars->{authorizer_no} )
	    {
		$authorized = 1;
	    }
	    
	    # Otherwise, check to see if the current user has admin privilege on the ARCHIVES
	    # (data_archives) table.
	    
	    else
	    {
		$sql = "SELECT permission FROM table_permissions
		        WHERE table_name = 'ARCHIVES' and person_no = $s->{enterer_no}
			    and permission = 'admin'";
		
		my ($admin_permission) = $dbh->selectrow_array($sql);
		
		$authorized = 1 if $admin_permission eq 'admin';
	    }
	}
	
	# If the user is not authorized to manage the DOI for this record, return a 401 error.
	
	unless ( $authorized )
	{
	    ouch(401, "You are not authorized to manage the DOI for this record.");
	}
	
	# Then fill in the extra information necessary to make this request.
	
	$vars->{archive_id} = "dar:$vars->{archive_no}";
	$vars->{send_to} = "mmcclenn\@geology.wisc.edu";
	
	if ( $pbdb_site eq 'dev' )
	{
	    $vars->{dev_msg} = "!!!!! THIS IS A TEST E-MAIL, NOT A REAL REQUEST !!!!!"; 
	}
	
	else
	{
	    $vars->{dev_msg} = '';
	}
	
	# If the parameter 'operation=cancel' was given, send out a cancel_doi e-mail. If the send
	# succeeds, update the record status to 'canceled'.
	
	my $op = $q->param('operation');
	
	if ( $op && $op eq 'cancel' )
	{
	    Wing->send_templated_email('cancel_doi', $vars);

	    $sql = "UPDATE data_archives SET status = 'canceled'
		WHERE archive_no = $archive_no LIMIT 1";

	    $dbh->do($sql);
	}

	# Otherwise, send out a request_doi e-mail. If the send succeeds, update the record status
	# to 'pending'.
	
	else
	{
	    Wing->send_templated_email('request_doi', $vars);
	    
	    $sql = "UPDATE data_archives SET status = 'pending'
		WHERE archive_no = $archive_no LIMIT 1";
	    
	    $dbh->do($sql);
	}

	# Return a simple indication of success.

	return "<h2>Request succeeded.</h2>\n";
    }
    
    # If no data archive record was found, return a 404 error.
    
    else
    {
	ouch(404, "archive record '$archive_id' was not found");
    }
}

1;
