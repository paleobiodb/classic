package PBDB::Download;

use PBDB::PBDBUtil;
use PBDB::TimeLookup;
use PBDB::TaxonInfo;
use PBDB::Validation;
use PBDB::Ecology;
use PBDB::Taxon;
use PBDB::DBTransactionManager;
use PBDB::TaxaCache;
use PBDB::Reference;
use PBDB::ReferenceEntry;
use PBDB::Permissions;
use URI::Escape;
use Mail::Mailer;
use Class::Date qw(now);
use PBDB::Constants qw($HTML_DIR $DATA_DIR $TAXA_TREE_CACHE makeFormPostTag);

use strict;

# Flags and constants
my $DEBUG=0;
$|=1;

# These arrays contain names of possible fields to be checked by a user in the
# download form.  When writing the data out to files, these arrays are compared
# to the query params to determine the file header line and then the data to
# be written out. 
my @collectionsFieldNames = qw(authorizer license enterer modifier collection_subset reference_no pubyr collection_name collection_aka country state county plate latdeg latmin latsec latdir latdec lngdeg lngmin lngsec lngdir lngdec latlng_basis paleolatdeg paleolatmin paleolatsec paleolatdir paleolatdec paleolngdeg paleolngmin paleolngsec paleolngdir paleolngdec gp_early_lat gp_early_lng gp_mid_lat gp_mid_lng gp_late_lat gp_late_lng altitude_value altitude_unit geogscale spatial_resolution geogcomments period epoch subepoch stage 10_my_bin FR2_bin max_interval min_interval direct_ma direct_ma_error direct_ma_method max_ma max_ma_error max_ma_method min_ma min_ma_error min_ma_method interval_base interval_top interval_midpoint interpolated_base interpolated_top interpolated_mid ma_max ma_min ma_mid emlperiod_max period_max emlperiod_min period_min emlepoch_max epoch_max emlepoch_min epoch_min emlintage_max intage_max emlintage_min intage_min emllocage_max locage_max emllocage_min locage_min zone research_group geological_group formation member localsection localbed localbedunit localorder regionalsection regionalbed regionalbedunit regionalorder stratscale stratcomments lithdescript lithadj lithification minor_lithology lithology1 fossilsfrom1 lithification2 minor_lithology2 lithadj2 lithology2 fossilsfrom2 environment tectonic_setting pres_mode geology_comments spatial_resolution temporal_resolution feed_pred_traces encrustation bioerosion fragmentation sorting dissassoc_minor_elems dissassoc_maj_elems art_whole_bodies disart_assoc_maj_elems seq_strat lagerstatten concentration orientation preservation_quality abund_in_sediment sieve_size_min sieve_size_max assembl_comps taphonomy_comments collection_type collection_coverage coll_meth collection_size collection_size_unit museum collectors collection_dates rock_censused_unit rock_censused collection_comments taxonomy_comments release_date access_level created modified);
my @occFieldNames = qw(authorizer enterer modifier occurrence_no abund_value abund_unit reference_no comments created modified plant_organ plant_organ2);
my @occTaxonFieldNames = qw(genus_reso genus_name subgenus_reso subgenus_name species_reso species_name taxon_no);
my @reidFieldNames = qw(authorizer enterer modifier reid_no reference_no comments created modified modified_temp plant_organ);
my @reidTaxonFieldNames = qw(genus_reso genus_name subgenus_reso subgenus_name species_reso species_name taxon_no);
my @plantOrganFieldNames = ('unassigned','leaf','seed/fruit','axis','plant debris','marine palyn','microspore','megaspore','flower','seed repro','non-seed repro','wood','sterile axis','fertile axis','root','cuticle','multi organs');
my @refsFieldNames = qw(authorizer enterer modifier reference_no author1init author1last author2init author2last otherauthors pubyr reftitle pubtitle editors pubvol pubno firstpage lastpage publication_type basis language doi comments project_name project_ref_no created modified);
my @paleozoic = qw(cambrian ordovician silurian devonian carboniferous permian);
my @mesoCenozoic = qw(triassic jurassic cretaceous tertiary);
my @ecoFields = (); # Note: generated at runtime in setupQueryFields
my @pubyr = ();
my @continents = ('North America','South America','Europe','Africa','Antarctica','Asia','Australia','Indian Ocean','Oceania');
my @paleocontinents = ('paleo Africa','paleo Antarctica','Arabia','paleo Australia','Baltica','Barentsia','Caribbean','Cimmeria','Costa Rica-Panama','Eastern Avalonia','Eastern USA','India','Japan','Kazakhstania','Laurentia','New Zealand','North Britain','North China','Precordillera','Shan-Thai','Siberia','paleo South America','South China','Southern Europe','Stikinia','Western Avalonia','Wrangellia','Yucatan');
my (@checkedcontinents,@uncheckedcontinents,@checkedpaleocontinents);
my @reso_types_group = ('aff.','cf.','ex gr.','new','sensu lato','?','"','informal','other');
my (%parents,%subgenus,%extant,%name,%rank,%spelling,%synonym,%nomen);

my $OUT_HTTP_DIR = "/public/downloads";
my $OUT_FILE_DIR = $HTML_DIR.$OUT_HTTP_DIR;

my (@form_errors,@form_warnings);
my $matrix_limit = 5000;
my $cites = "<div style=\"font-size: 0.75em; text-indent: -1em; margin-left: 1em; padding-left: 2em; padding-right: 2em;\">";

sub new {
    my ($class,$dbt,$q,$s,$hbo) = @_;
    my $dbh = $dbt->dbh;

    my $name = ($s->get("enterer")) ? $s->get("enterer") : $q->param("yourname");
    my $filename = PBDB::PBDBUtil::getFilename($name);

    my $p = PBDB::Permissions->new($s,$dbt);
    my $t = new PBDB::TimeLookup($dbt);

    my $self = {'dbh'=>$dbh,
                'dbt'=>$dbt,
                'q'=>$q,
                't'=>$t,
                'p'=>$p,
                's'=>$s,
                'hbo'=>$hbo, 
                'setup_query_fields_called'=>0,
                'filename'=>$filename};
    bless $self, $class;
    return $self;
}

# Main handling routine
sub buildDownload {
    my $self = shift;
    my ($q,$s,$hbo) = ($self->{'q'},$self->{'s'},$self->{'hbo'});
    my $dbt = $self->{'dbt'};
    my $dbh = $self->{'dbh'};
    my $output = '';

    if ( $q->param('restore_defaults') )	{
        my $sql = "UPDATE person SET last_action=last_action,last_download=NULL";
        $dbh->do($sql);
        $q->param('error_message' => 'Your defaults have been restored');
        if ( $q->param('form_type') eq "full" )	{
            $output .= PBDB::displayDownloadForm();
        } else	{
            $output .= PBDB::displayBasicDownloadForm();
        }
    }

    my @errors = $self->checkInput($q);

    if ( @errors )
    {
	my $errorString = "<li>" . join('</li><li>',@errors) . "</li>";
	my %vars = { error_message => $errorString };

	return $hbo->populateHTML('download_form',\%vars);
    }
    
    geographyOptions($q);
    
    my ($lumpedResults,$allResults) = $self->queryDatabase();

    my (%onhour,%onref,%byauth,%first,%last,%initials,%first_plus);
    # tally hours of keystroking if possible; otherwise tally references used
    #  for entry of collections and guesstimate hours using the known 1.7:1
    #  ratio in keystroked data
    for my $row (@$allResults)	{
        if ( ! $row->{'upload'} )	{
            $onhour{$row->{'personhour'}}++;
            if ( $onhour{$row->{'personhour'}} == 1 )	{
                $byauth{$row->{'authorizer_no'}}++;
            }
        } else	{
            $onref{$row->{'authorizer_no'}." ".$row->{'reference_no'}}++;
            if ( $onref{$row->{'authorizer_no'}." ".$row->{'reference_no'}} == 1 )	{
                $byauth{$row->{'authorizer_no'}} += 1.7;
            }
        }
    }
    my @h = keys %onhour;
    my $hours = $#h + 1;
    my @r = keys %onref;
    $hours += 1.7 * ( $#r + 1 );
    my @authnos = keys %byauth;
    @authnos = sort { $byauth{$b} <=> $byauth{$a} } @authnos;
    my $sql = "SELECT first_name,middle,last_name,name,person_no FROM person WHERE person_no IN ('".join("','",@authnos)."') ORDER BY last_name,first_name";
    for my $p ( @{$dbt->getData($sql)} )	{
        $first{$p->{'person_no'}} = $p->{'first_name'};
        $last{$p->{'person_no'}} = $p->{'last_name'};
        $initials{$p->{'person_no'}} = $p->{'first_name'}." ".$p->{'middle'};
        $initials{$p->{'person_no'}} =~ s/([A-Za-z])[a-z]* /$1. /;
        $initials{$p->{'person_no'}} =~ s/ //g;
        $first_plus{$p->{'person_no'}} = $p->{'first_name'}." ".$p->{'middle'};
    }
    # don't prominently list authorizers contributing less than 10 person days =
    #  80 person hours (arbitrary, but seems good to me)
    my @others;
    while ( $byauth{$authnos[$#authnos]} < 80 && @authnos )	{
        push @others , pop @authnos;
    }
    $byauth{$_} /= $hours / 100 foreach keys %byauth;
    my $monthyears = sprintf("%.1f work years",$hours / 2000);
    if ( $monthyears < 1 )	{
        $monthyears = sprintf("%.1f work months",$hours / 2000 * 12);
    }
    $hours = sprintf("%d",$hours);

    my ($refsCount,$nameCount,$taxaCount,$scaleCount,$mainCount) = (0,0,0,0,ref $lumpedResults ? scalar(@$lumpedResults) : $lumpedResults);
    my ($refsFile,$taxaFile,$scaleFile,$mainFile,$collFile,$colls) = ('','','','','',0);

    PBDB::PBDBUtil::autoCreateDir($HTML_DIR."/downloads");
    
    if ( $q->param('time_scale') ) {
        ($scaleCount,$scaleFile) = $self->printScaleFile($allResults);
    }

    if ( $q->param("output_data") =~ /occurrence/ ) {
        ($taxaCount,$taxaFile) = $self->printAbundFile($allResults);
    }
    
    my ($dummy, $ris_count, $bad_list);
    
    ($refsCount, $refsFile, $dummy, $ris_count, $bad_list) = $self->printRefsFile($allResults);
    my $risFile = $refsFile;
    $risFile =~ s/-refs\..*/-ris.txt/;
    
    if ($q->param('output_data') =~ /matrix/i) {
        ($nameCount,$mainCount,$mainFile) = $self->printMatrix($lumpedResults);
        if ($nameCount =~ /^ERROR/) {
            push @form_errors, "The matrix is currently limited to $matrix_limit collections and $mainCount were returned. Please email the database administrator if this is a problem";
        }
    } elsif ($q->param('output_data') =~ /conjunct/i) {
        ($mainCount,$mainFile,$collFile,$colls) = $self->printCONJUNCT($lumpedResults);
    } else {
        ($mainCount,$mainFile) = $self->printCSV($lumpedResults);
    }

    if (@form_errors) {
        my $errorString = "<li>" . join('<li>',@form_errors);
        $q->param('error_message' => $errorString );
        if ( $q->param('form_type') eq "full" )	{
            return PBDB::displayDownloadForm();
        } else	{
            return PBDB::displayBasicDownloadForm();
        }
    }

    # current limit for data set size that triggers the click through: 50 work
    #  days = 50 x 4 = 200 hours, assuming that actual entry makes up half
    # figure is based on a poll of 12 major contributors taken at NAPC 23.6.09
    my $hourlimit = 0;

    $output .= "<div align=\"center\"><p class=\"pageTitle\">Download results</p></div>\n\n";
    if ( $hours >= $hourlimit )	{
        my (%vars,@pb_authors,@au);
        push @pb_authors , "$initials{$_} $last{$_}" foreach @authnos;
        $pb_authors[0] = "$last{$authnos[0]}, $initials{$authnos[0]}";
        s/([A-Z])(\.)([A-Z])/$1$2 $3/g foreach @pb_authors;
        # needed if there are two middle initials
        s/([A-Z])(\.)([A-Z])/$1$2 $3/g foreach @pb_authors;
        if ( $#pb_authors > 0 )	{
            $pb_authors[$#pb_authors] = "and ".$pb_authors[$#pb_authors];
        }
	$vars{filename} = $self->{filename};
        $vars{'paleobiology_authors'} = join(', ',@pb_authors).".";
        $vars{'paleobiology_authors'} =~ s/\.\././;
        if ( $#pb_authors == 1 )	{
            $vars{'paleobiology_authors'} =~ s/, and / and /;
        }
        push @au , "$last{$_}, $first_plus{$_}" foreach @authnos;
        $vars{'major_contributors'} = join('<br>AU ',@au);
        if ( $q->param('max_interval_name') || $q->param('taxon_name') )	{
            $vars{'keywords'} = "KW ";
            $vars{'keywords'} .= ( $q->param($_) ) ? $q->param($_)."<br>" : "" foreach ('max_interval_name','min_interval_name','taxon_name');
        }
        $vars{'major_contributor_list'} .= sprintf "<li>$first{$_} $last{$_} (%d hours = %.1f%%)</li>\n",$byauth{$_} * $hours / 100,$byauth{$_} foreach @authnos;
	# only print "authorized" for the first contributor
	$vars{'major_contributor_list'} =~ s/ hours / hours authorized /;
        my $interval = ( $q->param('max_interval_name') ) ? " ".$q->param('max_interval_name') : "";
        $interval .= ( $q->param('min_interval_name') ) ? " to ".$q->param('min_interval_name') : "";
        $vars{'title'} = ( $q->param('taxon_name') ) ? "Taxonomic occurrences of$interval ".$q->param('taxon_name') : "Taxonomic occurrences";
        my @places =  ( @checkedcontinents && $#checkedcontinents < $#continents ) ?  @checkedcontinents : ( @checkedpaleocontinents ) ? @checkedpaleocontinents : ( $q->param('country') ) ? $q->param('country') : "";
        if ( $#places > 0 )	{
            $places[$#places] = "and ".$places[$#places];
        }
        $vars{'title'} .= ( $places[0] ne "" ) ? " from ".join(', ',@places) : "";
        if ( $#places == 1 )	{
            $vars{'title'} =~ s/, and / and /;
        }
        $vars{'occurrence_count'} = scalar @$allResults;
        ($vars{'year'},$vars{'month'},$vars{'day'}) = split /-/,now();
        $vars{'day'} =~ s/^0//;
        $vars{'day'} =~ s/ .*//;
        my @toMonth = ("January","February","March","April","May","June","July","August","September","October","November","December");
        $vars{'month'} = $toMonth[$vars{'month'}];
        $vars{'ref_count'} = $refsCount;
        $vars{'contributor_count'} = $#authnos + $#others + 2;
        @others = sort { $last{$a} cmp $last{$b} || $first{$a} cmp $first{$b} } @others;
        $others[$_] = $first{$others[$_]}." ".$last{$others[$_]} foreach 0..$#others;
        $vars{'hours'} = $hours;
        $vars{'monthyears'} = $monthyears;
        $others[$#others] = "and ".$others[$#others] if $#others >= 0;
        $vars{'other_contributors'} = join(', ',@others);
        $vars{'file_path'} = "$OUT_HTTP_DIR/$refsFile";
        $vars{'file_name'} = $refsFile;
        $vars{'cites'} = $cites . '</div>';
        $output .= $hbo->populateHTML('download_terms', \%vars);
    }

    $output .= qq|<div class="displayPanel" style="padding-top: 1em; padding-left: 1em; margin-left: 3em; margin-right: 3em; overflow: hidden;">|;

    $output .= $self->retellOptions();
    if (@form_warnings) {
        $output .= '<div align="center">';
        $output .= Debug::printWarnings(\@form_warnings);
        $output .= '</div>';
    }

    # Tell what happened
    $output .= "<div align=\"center\">\n";
    $output .= '<p class="large darkList" style="width: 36em; text-align: left; padding: 2px; lmargin-bottom: 0.5em;">Output</p>';
    $output .= "<div style=\"text-align: left; width: 40em;\">\n";
    if ( $mainCount > 0 )	{
        if ( $q->param("output_data") =~ /matrix/ ) {
            $output .= "$mainCount collections and $nameCount taxa were printed to <a href=\"$OUT_HTTP_DIR/$mainFile\">$mainFile</a><br>\n";
        }  else {
            my $things = ($q->param("output_data") =~ /occurrence/) 
                ? "occurrences" : $q->param("output_data");
            if ( $mainCount == 1 )	{
                if ( $things !~ /species/ )	{
                    $things =~ s/s$//;
                }
                $output .= "$mainCount $things was printed to <a href=\"$OUT_HTTP_DIR/$mainFile\">$mainFile</a><br>\n";
            } else	{
                $output .= "$mainCount $things were printed to <a href=\"$OUT_HTTP_DIR/$mainFile\">$mainFile</a><br>\n";
            }
            if ( $q->param("output_data") =~ /conjunct/i ) {
                $output .= "$colls collections were printed to <a href=\"$OUT_HTTP_DIR/$collFile\">$collFile</a><br>\n";
            }
        }
        if ( $q->param("output_data") =~ /occurrence/ ) {
            if ( $taxaCount == 1 )	{
                $output .= "1 taxonomic range was printed to <a href=\"$OUT_HTTP_DIR/$taxaFile\">$taxaFile</a><br>\n";
            } else	{
                $output .= "$taxaCount taxonomic ranges were printed to <a href=\"$OUT_HTTP_DIR/$taxaFile\">$taxaFile</a><br>\n";
            }
        } 
	
        if ( $refsCount == 1 )	{
            $output .= "$refsCount reference was printed to <a href=\"$OUT_HTTP_DIR/$refsFile\">$refsFile</a><br>\n";
        } else	{
            $output .= "$refsCount references were printed to <a href=\"$OUT_HTTP_DIR/$refsFile\">$refsFile</a><br>\n";
        }
	
	if ( $ris_count > 0 ) {
	    $output .= "$ris_count references were printed to <a href=\"$OUT_HTTP_DIR/$risFile\">$risFile</a><br>\n";
	    if ( @$bad_list ) {
		$output .= "<p>The following references could not be printed due to erroneous data:<ul>\n";
		$output .= "<li>$_</li>\n" foreach @$bad_list;
		$output .= "</ul></p>\n";
	    }
	}
        my $fileNames = $mainFile."/".$taxaFile."/".$refsFile."/".$risFile;
        if ( $q->param('time_scale') )    {
            $output .= "$scaleCount time intervals were printed to <a href=\"$OUT_HTTP_DIR/$scaleFile\">$scaleFile</a><br>\n";
            $fileNames .= "/".$scaleFile;
        }
        $output .= "</div>\n\n";
        $output .= "<p>You can also e-mail the files.<br>\n<nobr>";
	$output .= makeFormPostTag();
	$output .= "Address: <input type=\"hidden\" name=\"action\" value=\"emailDownloadFiles\"><input type=\"hidden\" name=\"filenames\" value=\"$fileNames\"><input name=\"email\" size=\"20\"> <input type=\"submit\" value=\"e-mail\"></form></nobr></p>\n\n";
    } else	{
        $output .= "</div>\n\n";
        $output .= "<p><i>No occurrences met the search criteria</i></p>";
    }
    $output .= qq|<p align="center" style="white-space: nowrap;"><a href="?action=displayDownloadForm">Do another download</a> |;
    if ( $hours >= $hourlimit )	{
        $output .= qq| - <a href="#" onClick=\"document.getElementById('mainPanel').style.display='none'; document.getElementById('terms').style.display='inline';\">Show terms again</a>|;
    }
    #print qq|<a href="?action=PASTQueryForm">Analyze with PAST functions</a></p></div>|;

    $output .= "</div>\n\n</div>\n\n";
    if ( $hours >= $hourlimit )	{
        $output .= "</div>\n\n";
    }

    # stash submitted form params so they can be recycled the next time the
    #  user opens a download form JA 28.11.11
    if ( $s->get("enterer_no") > 0 )	{
        # fields with unusual defaults
        my %defaults = ('form_type' => 'full', 'output_data' => 'occurrence list', 'output_format' => 'csv', 'research_group_restricted_to' => '0', 'created_before_after' => 'before', 'published_before_after' => 'after', 'occurrence_count_qualifier' => 'less', 'abundance_count_qualifier' => 'less', 'extant_extinct' => 'both', 'abundance_required' => 'all', 'collections_reference_no' => 'YES', 'collections_10_my_bin' => 'YES', 'collections_max_interval_no' => 'YES', 'collections_min_interval_no' => 'YES', 'occurrences_genus_name' => 'YES', 'occurrences_genus_reso' => 'YES' );
        my @pairs;
        # common defaults are handled here
        for my $p ( $q->param() )	{
            if ( $p ne "action" && $q->param($p) ne "" && $defaults{$p} ne $q->param($p) && ( $p !~ /lat/ || $q->param($p) !~ /90$/ ) && ( $p !~ /lng/ || $q->param($p) !~ /180$/ ) && ( $p !~ /^(lithology_|environment_|zone_|modern|replace_with_|compendium_|include_exclude|abundance_taxon|late_pleist)/ || $q->param($p) !~ /(yes|include)/i ) && ( $p !~ /(exclude_superset|lump_genera|split_subgenera|indet|incomplete_abund)/ || $q->param($p) !~ /^no$/i ) && ( $p !~ /_format$/ || $q->param($p) !~ /decimal/i ) )	{
                push @pairs , "$p=".$q->param($p);
            } elsif ( $defaults{$p} eq "YES" && $q->param($p) ne "YES" )	{
                push @pairs , "$p=NO";
            }
        }
	# these are the only isolated boxes that are checked by default
	for my $p ( 'collections_reference_no', 'collections_10_my_bin' )	{
		if ( $q->param($p) ne "YES" )	{
                	push @pairs , "$p=NO";
		}
	}
        s/'/\\'/g foreach @pairs;
        $sql = "UPDATE person SET last_action=last_action,last_download='".join('/',@pairs)."' WHERE person_no=".$s->get("enterer_no");
        $dbh->do($sql);
    }

    return $output;
}

sub checkInput {
    my ($self,$q) = @_;
    my @clean_vars = ('taxon_name','exclude_taxon_name','yourname','max_interval_name','min_interval_name','authorizer_reversed','pubyr','latmin1','latmax1','latmin2','latmax2','lngmin1','lngmax1','lngmin2','lngmax2','paleolatmin1','paleolatmax1','paleolatmin2','paleolatmax2','paleolngmin1','paleolngmax1','paleolngmin2','paleolngmax2','collection_no','occurrence_count','abundance_count','min_mean_abundance');
    my @errors;
    foreach my $p (@clean_vars) {
        if ($p =~ /taxon_name/) {
            if ($q->param($p) =~ /[<>]/) {
                push @errors, "Bad data entered in form field $p";
            }
        } else {
            if ($q->param($p) =~ /[^a-zA-Z0-9\s'\.\-,]/) {
                push @errors, "Bad data entered in form field $p";
            }
        }
    }

    my $required = 0;
    for my $r ( 'taxon_name','max_interval_name','authorizer_reversed','research_group' )	{
        if ( $q->param($r) ne "" )	{
            $required++;
        }
    }
    if ( $required == 0 )	{
        push @errors , "You must specify a taxonomic group, time interval, authorizer, or research group";
    } elsif ( $required == 1 && $q->param('max_interval_name') eq "Phanerozoic" )	{
        push @errors , "If you want data for the entire Phanerozoic, you must also specify a taxonomic group, authorizer, or research group";
    } elsif ( $required == 1 && $q->param('taxon_name') =~ /(Metazoa|Animalia)/ )	{
        push @errors , "If you want data for all animals, you must also specify a time interval, authorizer, or research group";
    }

    if ( ! $q->param("restrict_to_field") && $q->param("restrict_to_list" ) )	{
        push @errors , "You must select a 'Download only the following' value if you want to use this option";
    }
    
    # if ( @errors )	{
    #     errors($q,\@errors);
    #     return 0;
    # }
    # return 1;

    return @errors;
}

# pulled out for reuse by queryDatabase JA 31.5.12
sub errors	{
    my ($q,$errors) = @_;
    my $errorString = "<li>" . join('</li><li>',@$errors) . "</li>";
    $q->param( 'error_message' => $errorString );
    if ( $q->param('form_type') eq "full" )	{
        return PBDB::displayDownloadForm();
    } else	{
        return PBDB::displayBasicDownloadForm();
    }
}

# Prints out the options which the user selected in summary form.
sub retellOptions {
    my $self = shift;
    my $q = $self->{'q'};
    # Call as needed
    $self->setupQueryFields() if (! $self->{'setup_query_fields_called'});

    my $html = "<div align=\"center\">\n<table style=\"width: 40em;\">\n";
    $html .= '<tr><td colspan=2><p class="large darkList" style="padding: 2px; margin-bottom: 0.5em;">Download criteria</p></td></tr>';

    # authorizer added 30.6.04 JA (left out by mistake?) 
    if ( $q->param("output_data") =~ /conjunct/i )	{
        $html .= $self->retellOptionsRow ( "Output data type", "CONJUNCT" );
    } else	{
        $html .= $self->retellOptionsRow ( "Output data type", $q->param("output_data") );
    }
    $html .= $self->retellOptionsRow ( "Output data format", $q->param("output_format") );
    $html .= $self->retellOptionsRow ( "Authorizer", $q->param("authorizer_reversed") );
    if ($q->param('research_group')) {
        if ($q->param("research_group_restricted_to")) {
            $html .= $self->retellOptionsRow ( "Research group or project", "restricted to ".$q->param("research_group"));
        } else {
            $html .= $self->retellOptionsRow ( "Research group or project", "includes ".$q->param("research_group"));
        }
    }
    
    # added by rjp on 12/30/2003
    if ($q->param('year')) {
        my $dataCreatedBeforeAfter = $q->param("created_before_after") . " " . $q->param("month") . " " . $q->param("day_of_month") . " " . $q->param("year");
        $html .= $self->retellOptionsRow ( "Data records created", $dataCreatedBeforeAfter);
    }
    
    # JA 31.8.04
    if ($q->param('pubyr')) {
        my $dataPublishedBeforeAfter = $q->param("published_before_after") . " " . $q->param("pubyr");
        $html .= $self->retellOptionsRow ( "Data records published", $dataPublishedBeforeAfter);
    }
    if ( $q->param("taxon_name") !~ /[ ,]/ )    {
        $html .= $self->retellOptionsRow ( "Taxon to include", $q->param("taxon_name") );
    } else    {
        $html .= $self->retellOptionsRow ( "Taxa to include", $q->param("taxon_name") );
    }
    if ( $q->param("exclude_taxon_name") !~ /[ ,]/ )    {
        $html .= $self->retellOptionsRow ( "Taxon to exclude", $q->param("exclude_taxon_name") );
    } else    {
        $html .= $self->retellOptionsRow ( "Taxa to exclude", $q->param("exclude_taxon_name") );
    }

    $html .= $self->retellOptionsRow ( "Class", $q->param("class") );

    if ($q->param("max_interval_name")) {
        $html .= $self->retellOptionsRow ( "Oldest interval", $q->param("max_eml_interval") . " " . $q->param("max_interval_name") );
    }
    if ($q->param("min_interval_name")) { 
        $html .= $self->retellOptionsRow ( "Youngest interval", $q->param("min_eml_interval") . " " .$q->param("min_interval_name") );
    }

    if ( $q->param('late_pleistocene') =~ /no/i ) {
        $html .= $self->retellOptionsRow ( "Late Neogene bin excludes", "Late Pleistocene/undifferentiated Pleistocene" );
    }

    $html .= $self->retellOptionsRow ( "Restrict to ".$q->param("restrict_to_field")."(s): ",$q->param("restrict_to_list"));

    my @lithification_group = ('lithified','poorly_lithified','unlithified','unknown');
    $html .= $self->retellOptionsGroup('Lithification','lithification_',\@lithification_group);
   
    # Lithologies or lithology
    if ( $q->param("lithology1") ) {
        $html .= $self->retellOptionsRow("Lithology: ", $q->param("include_exclude_lithology1") . " " .$q->param("lithology1"));
    } else {
        my @lithology_group = ('carbonate','mixed','siliciclastic','unknown');
        $html .= $self->retellOptionsGroup('Lithologies','lithology_',\@lithology_group);
    }

    # Environment or environments
    if ( $q->param('environment') ) {
        $html .= $self->retellOptionsRow ( "Environment", $q->param("include_exclude_environment") . " " .$q->param("environment") );
    } else {
        my @environment_group = ('carbonate','unknown','siliciclastic','terrestrial');
        $html .= $self->retellOptionsGroup('Environments','environment_',\@environment_group);
    }

    # Environmental (previously just onshore-offshore) zones
    my @zone_group = ('lacustrine','fluvial','karst','other_terrestrial','marginal_marine','reef','shallow_subtidal','deep_subtidal','offshore','slope_basin');
    $html .= $self->retellOptionsGroup('Environmental zones:','zone_',\@zone_group);

    # Preservation mode
    my @pres_mode_group= ('cast','adpression','soft_parts','original_aragonite','mold/impression','replaced_with_silica','trace','charcoalification','coalified','other');
    $html .= $self->retellOptionsGroup('Preservation modes:','pres_mode_',\@pres_mode_group);

    # Collection methods
    if ( $q->param('sieve') )	{
        $html .= $self->retellOptionsRow('Collection methods:',$q->param('sieve'));
    }

    # Collection types
    my @collection_types_group = ('archaeological','biostratigraphic','paleoecologic','taphonomic','taxonomic','general_faunal/floral','unknown');
    $html .= $self->retellOptionsGroup('Reasons for describing included collections:','collection_type_',\@collection_types_group);

    # Continents or country
    # If a country was selected, ignore the continents JA 6.7.02
    if ( $q->param("country") )    {
        $html .= $self->retellOptionsRow ( "Country", $q->param("include_exclude_country") . " " . $q->param("country") );
    }
    else    {
        if ( $#checkedcontinents > -1 && $#continents > $#checkedcontinents )	{
            $html .= $self->retellOptionsRow ( "Continents", join (  ", ", @checkedcontinents ) );
            $q->param($_ => '') foreach @checkedcontinents;
            $q->param($_ => 'NO') foreach @uncheckedcontinents;
        }

        if ( $#checkedpaleocontinents > -1 ) {
            $html .= $self->retellOptionsRow ( "Paleocontinents", join (  ", ", @checkedpaleocontinents ) );
        }
    }

    # all the boundaries must be given
    my @ranges = ([$q->param('latmin1'),$q->param('latmax1'),-90,90],
               [$q->param('lngmin1'),$q->param('lngmax1'),-180,180],
               [$q->param('latmin2'),$q->param('latmax2'),-90,90],
               [$q->param('lngmin2'),$q->param('lngmax2'),-180,180],
               [$q->param('paleolatmin1'),$q->param('paleolatmax1'),-90,90],
               [$q->param('paleolngmin1'),$q->param('paleolngmax1'),-180,180],
               [$q->param('paleolatmin2'),$q->param('paleolatmax2'),-90,90],
               [$q->param('paleolngmin2'),$q->param('paleolngmax2'),-180,180]);
    my @range_descriptions;

    # Create text descriptions of what the user has entered for the diff. ranges above
    for(my $i=0;$i<@ranges;$i++) {
        my ($min,$max,$lower,$upper) = @{$ranges[$i]};
        my $description = "";

	# user may have confused min and max, so swap them JA 5.7.06
	if ( $min > $max )	{
		my $temp = $min;
		$min = $max;
		$max = $temp;
	}

        # If either the min or max value has been changed from an upper bound
        # (i.e. its been modified by the user) than we want to print a description
        # message
        if (($min > $lower && $min < $upper) ||
            ($max > $lower && $max < $upper)) {

            # Case 1: they've both been changed, print a range
            # Case 2: one has been change, its the minimum value.  max is unchanged
            # Case 3: (else): one has been changed, its the maximum value. min is unchanged
            if ($min > $lower && $max < $upper) {
                $description .= "$min&deg; to $max&deg;";
            } elsif ($min > $lower) {
                $description .= "greater than $min&deg; "
            } else {
                $description .= "less than $max&deg; "
            }
        }

        # Now store this text description, which will be a empty string if the user
        # didn't edit this range, else will be a text string describing the changes
        $range_descriptions[$i]=$description;
    }
  
    # Print out the text generated above
    $html .= $self->retellOptionsRow("Latitudinal range", $range_descriptions[0]); 
    $html .= $self->retellOptionsRow("Longitudinal range", $range_descriptions[1]); 
    $html .= $self->retellOptionsRow("Additional latitudinal range", $range_descriptions[2]); 
    $html .= $self->retellOptionsRow("Additional longitudinal range", $range_descriptions[3]); 
    $html .= $self->retellOptionsRow("Paleolatitudinal range", $range_descriptions[4]); 
    $html .= $self->retellOptionsRow("Paleolongitudinal range", $range_descriptions[5]); 
    $html .= $self->retellOptionsRow("Additional paleolatitudinal range", $range_descriptions[6]); 
    $html .= $self->retellOptionsRow("Additional paleolongitudinal range", $range_descriptions[7]); 
    
    
    $html .= $self->retellOptionsRow ( "Lump lists by county and formation?", $q->param("lumplist") );

    my @geogscale_group = ('small_collection','hand_sample','outcrop','local_area','basin','unknown');
    $html .= $self->retellOptionsGroup( "Geographic scale of collections", 'geogscale_', \@geogscale_group);

    my @stratscale_group = ('bed','group_of_beds','member','formation','group','unknown');
    $html .= $self->retellOptionsGroup("Stratigraphic scale of collections", 'stratscale_',\@stratscale_group);

    $html .= $self->retellOptionsRow ( "Lump by location??", $q->param("lump_by_location") );
    $html .= $self->retellOptionsRow ( "Lump by stratigraphic unit?", $q->param("lump_by_strat_unit") );
    $html .= $self->retellOptionsRow ( "Lump by published reference?", $q->param("lump_by_ref") );
    $html .= $self->retellOptionsRow ( "Lump by time interval?", $q->param("lump_by_interval") );
    $html .= $self->retellOptionsRow ( "Exclude collections with subset collections? ","yes" ) if ($q->param("exclude_superset") eq 'YES');
    $html .= $self->retellOptionsRow ( "Exclude collections with ".$q->param("occurrence_count_qualifier")." than",$q->param("occurrence_count")." occurrences") if (int($q->param("occurrence_count")));
    $html .= $self->retellOptionsRow ( "Exclude collections with ".$q->param("abundance_count_qualifier")." than",$q->param("abundance_count")." specimens/individuals") if (int($q->param("abundance_count")));

    if ($q->param('output_data') =~ /occurrence|taxonomic.list/) {
        $html .= $self->retellOptionsRow ( "Lump occurrences of same genus of same collection?","yes") if ($q->param('lump_genera') eq 'YES');
        $html .= $self->retellOptionsRow ( "Replace genus names with subgenus names?","yes") if ($q->param("split_subgenera") eq 'YES');
        $html .= $self->retellOptionsRow ( "Replace names with reidentifications?","no") if ($q->param('repace_with_reid') eq 'NO');
        $html .= $self->retellOptionsRow ( "Replace names with senior synonyms?","no") if ($q->param("replace_with_ss") eq 'NO');
        $html .= $self->retellOptionsRow ( "Include occurrences that are generically indeterminate?", "yes") if ($q->param('indet') eq 'YES');
        $html .= $self->retellOptionsRow ( "Include occurrences that are specifically indeterminate?", "yes") if ($q->param('sp') eq 'NO');
        my $quals .= $self->retellOptionsGroup('Include genus occurrences qualified by','genus_reso_',\@reso_types_group);
        if ( $quals && $q->param('genus_reso_informal') eq "YES" )	{
            $quals =~ s/<\/i>/, informal<\/i>/;
        }
        $html .= $quals;
        $quals = $self->retellOptionsGroup('Include species occurrences qualified by','species_reso_',\@reso_types_group);
        if ( $quals && $q->param('species_reso_informal') eq "YES" )	{
            $quals =~ s/<\/i>/, informal<\/i>/;
        }
        $html .= $quals;
        my @preservation = $q->param('preservation');
        $html .= $self->retellOptionsRow ( "Include preservation categories", join(", ",@preservation)) if scalar(@preservation) < 3;
        $html .= $self->retellOptionsRow ( "Include occurrences of extant or extinct taxa?", "extant only") if ($q->param("extant_extinct") =~ /extant/i);
        $html .= $self->retellOptionsRow ( "Include occurrences of extant or extinct taxa?", "extinct only") if ($q->param("extant_extinct") =~ /extinct/i);
        $html .= $self->retellOptionsRow ( "Include occurrences falling outside Compendium age ranges?", "no") if ($q->param("compendium_ranges") eq 'NO');
        $html .= $self->retellOptionsRow ( "Only include occurrences with abundance data?", "yes, require some kind of abundance data" ) if ($q->param("abundance_required") eq 'abundances');
        $html .= $self->retellOptionsRow ( "Only include occurrences with abundance data?", "yes, require specimen or individual counts" ) if ($q->param("abundance_required") eq 'specimens');
        if ( $q->param("abundance_taxon_name") )	{
            my $inexclude;
            if ( $q->param('abundance_taxon_include') eq "include" )	{
                $inexclude = "included";
            } else	{
                $inexclude = "excluded";
            }
            $html .= $self->retellOptionsRow ( "Taxa whose abundances are $inexclude", $q->param("abundance_taxon_name") );
        }
        $html .= $self->retellOptionsRow ( "Include abundances if the taxonomic list omits some genera?", "yes" ) if ($q->param("incomplete_abundances") eq 'YES');
        $html .= $self->retellOptionsRow ( "Exclude classified occurrences?", $q->param("classified") ) if ($q->param("classified" !~ /classified|unclassified/i));
        $html .= $self->retellOptionsRow ( "Minimum # of specimens to compute mean abundance", $q->param("min_mean_abundance") ) if ($q->param("min_mean_abundance"));

        my $plantOrganFieldCount = 0;
        foreach my $plantOrganField (@plantOrganFieldNames) {
            if ($q->param("plant_organ_".$plantOrganField)) {
                $plantOrganFieldCount++;
            }
        }
        if ($plantOrganFieldCount != 0 && $plantOrganFieldCount != scalar(@plantOrganFieldNames)) {
            $html .= $self->retellOptionsGroup('Include plant organs','plant_organ_',\@plantOrganFieldNames);
        }

        my @occFields = ();
        if ($q->param('output_data') =~ /occurrence/) {
            foreach my $field ( @occTaxonFieldNames) {
                if( $q->param ( "occurrences_".$field ) ){ 
                    if ($field =~ /(class|order|family|parent)_name/) {
                        push ( @occFields, $field );
                    } else {
                        push ( @occFields, "occurrences_".$field ); 
                    }
                }
            }
            foreach my $field ( @reidTaxonFieldNames ) {
                if( $q->param ( "occurrences_".$field) ){ 
                    push ( @occFields, "original_".$field ); 
                }
            }
            foreach my $field ( @occFieldNames ) {
                if( $q->param ( "occurrences_".$field) ){ 
                    push ( @occFields, "occurrences_".$field ); 
                }
            }
            foreach my $field ( @reidFieldNames ) {
                if( $q->param ( "occurrences_".$field) ){ 
                    push ( @occFields, "original_".$field ); 
                }
            }
        } elsif ($q->param('output_data') =~ /taxonomic_list/ && $q->param('taxonomic_level') =~ /genus/) {
            push @occFields, 'genus_name';
        } elsif ($q->param('output_data') =~ /taxonomic_list/) {
            push @occFields, 'genus_name';
            push @occFields, 'subgenus_name' if ($q->param('occurrences_subgenus_name'));
            push @occFields, 'species_name';
        }
        push @occFields, 'extant' if ($q->param('occurrences_extant'));

        push @occFields, ('author1init','author1last') if ($q->param('occurrences_first_author'));
        push @occFields, ('author2init','author2last') if ($q->param('occurrences_second_author'));
        push @occFields, 'other_authors' if ($q->param('occurrences_other_authors'));
        push @occFields, 'pubyr' if ($q->param('occurrences_year_named'));
        push @occFields, 'preservation' if ($q->param('occurrences_preservation'));
        push @occFields, 'type_specimen' if ($q->param('occurrences_type_specimen'));
        push @occFields, 'type_body_part' if ($q->param('occurrences_type_body_part'));
        push @occFields, 'type_locality' if ($q->param('occurrences_type_locality'));
        push @occFields, 'form_taxon' if ($q->param('occurrences_form_taxon'));
        push @occFields, 'common_name' if ($q->param('occurrences_common_name'));

        if (@occFields) {
            my $fieldnames = join "<br>", @occFields;
            $fieldnames =~ s/occurrences_//g;
            $html .= $self->retellOptionsRow ( "Occurrence output fields", $fieldnames );
        }
        
        # Ecology fields
        if (@ecoFields) {
            $html .= $self->retellOptionsRow ( "Ecology output fields", join ( "<br>", @ecoFields) );
        }
        
    } 

    if ($q->param('output_data') =~ /occurrence|collections/) {
        # collection table fields
        # these are required
        my @collFields = ( 'collection_no','authorizer','license' );
        foreach my $field ( @collectionsFieldNames ) {
            if ( $q->param ( 'collections_'.$field ) ) { push ( @collFields, 'collections_'.$field ); }
        }
	if ( $q->param('collections_altitude') ) {
	    push @collFields, 'collections_altitude_value', 'collections_altitude_unit';
	}
        my $fieldnames = join "<br>", @collFields;
        $fieldnames =~ s/collections_//g;
        $html .= $self->retellOptionsRow ( "Collection output fields", $fieldnames );
    }

    $html .= "</table>\n</div>\n";

    $html =~ s/_/ /g;
    return $html;
}


# Formats a bunch of checkboses of a query parameter (name=value) as a table row in html.
sub retellOptionsGroup {
    my ($self,$message,$form_prepend,$group_ref) = @_;
    my $q = $self->{'q'};
    my $missing = 0;

    foreach my $item (@$group_ref) {
        $missing++ if (!$q->param($form_prepend.$item));
    }

    if ($missing && $missing < scalar(@$group_ref)) {
        my $options = "";
        foreach my $item (@$group_ref) {
            if ($q->param($form_prepend.$item)) {
                $options .= ", ".$item;
                $q->param($form_prepend.$item => '');
            } else	{
                $q->param($form_prepend.$item => 'NO');
            }
        }
        $options =~ s/_/ /g;
        $options =~ s/^, //;
        return $self->retellOptionsRow($message,$options);
    } else {
        return "";
    }
}


# Formats a query parameter (name=value) as a table row in html.
sub retellOptionsRow {
    my ($self,$name,$value) = @_;

    if ( $value && $value !~ /[<>]/) {
        return "<tr><td valign='top'>$name</td><td valign='top'><i>$value</i></td></tr>\n";
    }
}


# 4.2.13 JA
# figures out selected geography options for use in several places
sub geographyOptions	{
	my $q = shift;
	for my $c ( @continents )	{
		if ( $q->param($c) eq 'YES' )	{
			push @checkedcontinents , $c;
		} else	{
                	push @uncheckedcontinents, $c;
		}
	}
	for my $p ( @paleocontinents )	{
		if ( $q->param($p) eq 'YES' )	{
			push @checkedpaleocontinents, $p;
			$checkedpaleocontinents[$#checkedpaleocontinents] =~ s/paleo //;
		}
	}
}

# 6.7.02 JA
sub getCountryString {
    my $self = shift;
    my $q = $self->{'q'};
    my $dbh = $self->{'dbh'};
    my $output = '';


    if ( $#continents == $#checkedcontinents )	{
        $q->param($_ => '') foreach @continents;
        if ( ! $q->param('country') )	{
            return;
        }
    }

    my $country_sql = "";
    my $in_str = "";

    #Country or Countries
    if ($q->param('country')) {
        my $country_term = $dbh->quote($q->param('country'));
        if ($q->param('include_exclude_country') eq "exclude") {
            $country_sql = qq| c.country NOT LIKE $country_term |;
        } else {
            $country_sql = qq| c.country LIKE $country_term |;
        }
    } else {     
        # Get the regions
        if ( ! open ( REGIONS, "$DATA_DIR/PBDB.regions" ) ) {
            return "<font color='red'>Skipping regions.</font> Error message is $!<br><BR>\n";
        }

        my %REGIONS;
        while (<REGIONS>) {
            chomp();
            my ($region, $countries) = split(/:/, $_, 2);
            $countries =~ s/'/\\'/g;
            $REGIONS{$region} = $countries;
        }
        close REGIONS;
        # Add the countries within selected regions

        for my $c (@checkedcontinents) {
            $in_str = $in_str .','. "'".join("','", split(/\t/,$REGIONS{$c}))."'";
            $in_str =~ s/^,//; 
        }
        if ($in_str) {
            $country_sql = qq| c.country IN ($in_str) |;
        } else {
            $country_sql = "";
        }    
    }
    return $country_sql;
}

# 15.8.05 JA
sub getPlateString    {
    my $self = shift;
    my $q = $self->{'q'};
    my $dbt = $self->{'dbt'};

    if ( ! @checkedpaleocontinents || $#paleocontinents == $#checkedpaleocontinents )	{
        return "";
    }

    my (@plates,%platein);
    my $sql = "SELECT plate FROM plates WHERE paleocontinent IN ('" . join("','",@checkedpaleocontinents) . "')";
    my @platerefs = @{$dbt->getData($sql)};
    if ( ! @platerefs )	{
        return "";
    }
    foreach my $p ( @platerefs )	{
        push @plates , $p->{'plate'};
        $platein{$p->{'plate'}} = "Y";
    }

    return " plate IN (".join(',',@plates).")";
}

# 12/13/2004 PS 
sub getPaleoLatLongString    {
    my $self = shift;
    my $q = $self->{'q'};
    
    my $coord_sql = "";

    # all the boundaries must be given
    foreach my $i (1..2) {
        my $latmin = $q->param('paleolatmin'.$i);
        my $latmax = $q->param('paleolatmax'.$i);
        my $lngmin = $q->param('paleolngmin'.$i);
        my $lngmax = $q->param('paleolngmax'.$i);

	# user may have confused min and max, so swap them JA 5.7.06
	if ( $latmin > $latmax )	{
		my $temp = $latmin;
		$latmin = $latmax;
		$latmax = $temp;
	}
	if ( $lngmin > $lngmax )	{
		my $temp = $lngmin;
		$lngmin = $lngmax;
		$lngmax = $temp;
	}

        # if all are blank, just return (no parameters may have been passed in if this wasn't called form a script
        if ($latmin =~ /^\s*$/ && $latmax =~ /^\s*$/ && $lngmin =~ /^\s*$/ && $lngmax =~ /^\s*$/) {
            next;
        }

        # all the boundaries must be given correctly
        if ( $latmin !~ /^-?\d+(|\.\d+)$/ || $latmax !~ /^-?\d+(|\.\d+)$/ )    {
            push @form_errors,"The paleolatitude is formatted incorrectly";
            next;
        }
        if ( $lngmin !~ /^-?\d+(|\.\d+)$/ || $lngmax !~ /^-?\d+(|\.\d+)$/ )    {
            push @form_errors,"The paleolongitude is formatted incorrectly";
            next;
        }
        # at least one of the boundaries must be non-trivial
        if ( $latmin <= -90 && $latmax >= 90 && $lngmin <= -180 && $lngmax >= 180 )    {
            next;
        }

        my @clauses = ();
        if ($latmin > -90) {
            push @clauses,"paleolat >= $latmin";
        }
        if ($latmax < 90 ) {
            push @clauses, "paleolat <= $latmax";
        }
        if ($lngmin > -180 ) {
            push @clauses, "paleolng >= $lngmin";
        }
        if ($lngmax < 180 ) {
            push @clauses, "paleolng <= $lngmax";
        }
        $coord_sql .= " OR (".join(" AND ",@clauses).")";
    }
    $coord_sql =~ s/^ OR//;
    if ($coord_sql) {
        $coord_sql = '('.$coord_sql.')';
    }
    return $coord_sql;
}

# 29.4.04 JA
sub getLatLongString    {
    my $self = shift;
    my $q = $self->{'q'};

    my $latlongclause = "";
    foreach my $i (1..2) {
        my $latmin = $q->param('latmin'.$i);
        my $latmax = $q->param('latmax'.$i);
        my $lngmin = $q->param('lngmin'.$i);
        my $lngmax = $q->param('lngmax'.$i);

	# user may have confused min and max, so swap them JA 5.7.06
	if ( $latmin > $latmax )	{
		my $temp = $latmin;
		$latmin = $latmax;
		$latmax = $temp;
	}
	if ( $lngmin > $lngmax )	{
		my $temp = $lngmin;
		$lngmin = $lngmax;
		$lngmax = $temp;
	}

        my $abslatmin = abs($latmin);
        my $abslatmax = abs($latmax);
        my $abslngmin = abs($lngmin);
        my $abslngmax = abs($lngmax);

        if ($latmin =~ /^\s*$/ && $latmax =~ /^\s*$/ && $lngmin =~ /^\s*$/ && $lngmax =~ /^\s*$/) {
            next;
        }   

        # all the boundaries must be given correctly
        if ( $latmin !~ /^-?\d+(|\.\d+)$/ || $latmax !~ /^-?\d+(|\.\d+)$/ )    {
            push @form_errors,"The latitude is formatted incorrectly";
            next;
        }
        if ( $lngmin !~ /^-?\d+(|\.\d+)$/ || $lngmax !~ /^-?\d+(|\.\d+)$/ )    {
            push @form_errors,"The longitude is formatted incorrectly";
            next;
        }
        # at least one of the boundaries must be non-trivial
        if ( $latmin <= -90 && $latmax >= 90 && $lngmin <= -180 && $lngmax >= 180 )    {
            next;
        }

        $latlongclause .= " OR (";
        my $sum;

        sub extractMinutes	{
            my $latlng = shift;
            my ($degrees,$minutes) = split /\./, shift;
            if ( ! $minutes ) { return $latlng."deg"; }
            else { return "IF(".$latlng."min IS NOT NULL,".$latlng."deg+(".$latlng."min/60),".$latlng."deg)"; }
        }

        $sum = extractMinutes('lat',$abslatmin);
        if ( $latmin >= 0 )    {
            $latlongclause .= "$sum>=$abslatmin AND latdir='North'";
        } else    {
            $latlongclause .= "(($sum<$abslatmin AND latdir='South') OR latdir='North')";
        }

        $latlongclause .= " AND ";
        $sum = extractMinutes('lat',$abslatmax);
        if ( $latmax >= 0 )    {
            $latlongclause .= "(($sum<$abslatmax AND latdir='North') OR latdir='South')";
        } else    {
            $latlongclause .= "$sum>=$abslatmax AND latdir='South'";
        }

        $latlongclause .= " AND ";
        $sum = extractMinutes('lng',$abslngmin);
        if ( $lngmin >= 0 )    {
            $latlongclause .= "$sum>=$abslngmin AND lngdir='East'";
        } else    {
            $latlongclause .= "(($sum<$abslngmin AND lngdir='West') OR lngdir='East')";
        }

        $latlongclause .= " AND ";
        $sum = extractMinutes('lng',$abslngmax);
        if ( $lngmax >= 0 )    {
            $latlongclause .= "(($sum<$abslngmax AND lngdir='East') OR lngdir='West')";
        } else    {
            $latlongclause .= "$sum>=$abslngmax AND lngdir='West'";
        }
        $latlongclause .= ")";
    }
    $latlongclause =~ s/^ OR//;
    if ($latlongclause) {
        $latlongclause = '('.$latlongclause.')';
    }

    return $latlongclause;
}

sub getIntervalString    {
    my $self = shift;
    my $q = $self->{'q'};
    my $dbh = $self->{'dbh'};
    my $dbt = $self->{'dbt'};

    my $max = ($q->param('max_interval_name') || "");
    my $min = ($q->param('min_interval_name') || "");
    my $eml_max  = ($q->param("max_eml_interval") || "");  
    my $eml_min  = ($q->param("min_eml_interval") || "");  

    # return immediately if the user already selected a full time scale
    #  to bin the data
    if ( $q->param('time_scale') )    {
        return "";
    }

    if ( $max )    {
        my $use_mid=0;
        if ($q->param("use_midpoints")) {
            $use_mid = 1;
        }

        my ($intervals,$errors,$warnings) = $self->{t}->getRange($eml_max, $max, $eml_min, $min,'',$use_mid);

        # need to know the boundaries of the interval to make use of the
        #  direct estimates JA 5.4.07
        my ($ub,$lb) = $self->{t}->getBoundaries();
        my $upper = 999999;
        my $lower;
        my %lowerbounds = %{$lb};
        my %upperbounds = %{$ub};
        for my $intvno ( @$intervals )  {
            if ( $upperbounds{$intvno} < $upper )       {
                $upper = $upperbounds{$intvno};
            }
            if ( $lowerbounds{$intvno} > $lower )       {
                $lower = $lowerbounds{$intvno};
            }
        }


        push @form_errors , @$errors;
        @form_warnings = @$warnings;
        my $intervals_sql = join(", ",@$intervals);
        # -1 to prevent crashing on blank string
        # only use the interval names if there is no direct estimate
	# backed off this because there are too many cases of AEO values causing
	#  collections to land in the wrong epoch, might change my mind later
	return "(c.max_interval_no IN (-1,$intervals_sql) AND c.min_interval_no IN (0,$intervals_sql))";
        #return "((c.max_interval_no IN (-1,$intervals_sql) AND c.min_interval_no IN (0,$intervals_sql) AND c.max_ma IS NULL AND c.min_ma IS NULL) OR (c.max_ma<=$lower AND c.min_ma>=$upper AND c.max_ma IS NOT NULL AND c.min_ma IS NOT NULL))";
    }

    

    return "";
}

# JA 11.4.05
# almost complete rewrite 21.8.09 to handle cases where lithification varies
#  between lithologies
# we now assume that if the user does not want a category, they don't want
#  any collection that includes any fossils from that category
sub getLithificationString    {
    my $self = shift;
    my $q = $self->{'q'};

    my $lithified = $q->param('lithification_lithified');
    my $poorly_lithified = $q->param('lithification_poorly_lithified');
    my $unlithified = $q->param('lithification_unlithified');
    my $unknown = $q->param('lithification_unknown');
    my $lithif_sql = "";
    my $lithvals = "";
        # if all the boxes were unchecked, just return (idiot proofing)
        if ( ! $lithified && ! $poorly_lithified && ! $unlithified && ! $unknown )    {
            return "";
        }
    # likewise, if all the boxes are checked do nothing
    elsif ( $lithified && $poorly_lithified && $unlithified && $unknown )    {
            return "";
        }
    # all other combinations
    my @include;
    if (  $lithified )    {
        push @include , 'lithified';
    }
    if (  $poorly_lithified )    {
        push @include , 'poorly lithified';
    }
    if (  $unlithified )    {
        push @include , 'unlithified';
    }
    my ($liths1,$liths2);
    if ( @include )	{
        $liths1 = "lithification IN ('".join ("','",@include)."')";
        $liths2 = "lithification2 IN ('".join ("','",@include)."')";
        if ( $unknown )	{
            $liths1 .= " OR lithification IS NULL OR lithification=''";
            $liths2 .= " OR lithification2 IS NULL OR lithification2=''";
        }
    # must want unknown only
    } else	{
        $liths1 = "lithification IS NULL OR lithification=''";
        $liths2 = "lithification2 IS NULL OR lithification2=''";
    }
    $liths1 = " ( ".$liths1." )";
    $liths2 = " ( ".$liths2." )";

    # case 1: lithification and lithification2 are both good
    # this will immediately grab all completely unknown (but wanted) cases
    my @cases = (" ($liths1 AND $liths2) ");

    # case 2: lithification is good and there is no lithification2 and
    #  fossilsfrom2 is not yes
    push @cases , " ($liths1 AND (lithification2='' OR lithification2 IS NULL) AND (fossilsfrom2='' OR fossilsfrom2 IS NULL)) ";

    # case 3: lithification2 is good and there is no lithification and
    #  fossilsfrom is not yes
    push @cases , " ($liths2 AND (lithification='' OR lithification IS NULL) AND (fossilsfrom1='' OR fossilsfrom1 IS NULL)) ";

    # case 4: lithification is good and lithification2 is bad but
    #  fossilsfrom1 is Y and fossilsfrom2 is not
    push @cases , " ($liths1 AND NOT $liths2 AND fossilsfrom1='Y' AND (fossilsfrom2 IS NULL OR fossilsfrom2='')) ";

    # case 5: lithification2 is good and lithification is bad but
    #  fossilsfrom2 is Y and fossilsfrom1 is not
    push @cases , " ($liths2 AND NOT $liths1 AND fossilsfrom2='Y' AND (fossilsfrom1 IS NULL OR fossilsfrom1='')) ";

    $lithif_sql = " (".join(' OR ',@cases).") ";

    return $lithif_sql;
}


# JA 1.7.04
# WARNING: relies on fixed lists of lithologies; if these ever change in
#  the database, this section will need to be modified
# major rewrite JA 14.8.04 to handle checkboxes instead of pulldown
sub getLithologyString    {
    my $self = shift;
    my $hbo = $self->{'hbo'};
    my $q = $self->{'q'};
    my $dbh = $self->{'dbh'};

    my $carbonate = $q->param('lithology_carbonate');
    my $mixed = $q->param('lithology_mixed');
    my $silic = $q->param('lithology_siliciclastic');
    my $unknown = $q->param('lithology_unknown');
    my $lith_sql = "";

    my $ff1 = "AND (c.fossilsfrom1='Y' OR c.fossilsfrom2 IS NULL OR c.fossilsfrom2='')";
    my $ff2 = "AND (c.fossilsfrom2='Y' OR c.fossilsfrom1 IS NULL OR c.fossilsfrom1='')";
    my $notff1 = "OR (c.fossilsfrom2='Y' AND (c.fossilsfrom1 IS NULL OR c.fossilsfrom1=''))";
    my $notff2 = "OR (c.fossilsfrom1='Y' AND (c.fossilsfrom2 IS NULL OR c.fossilsfrom2=''))";

    # Lithology or Lithologies
    if ( $q->param('lithology1') ) {
        my $lith_term = $dbh->quote($q->param('lithology1'));
        if ($q->param('include_exclude_lithology1') eq "exclude") {
            return qq| (c.lithology1!=$lith_term OR c.lithology1 IS NULL $notff1) AND|.
                   qq| (c.lithology2!=$lith_term OR c.lithology2 IS NULL $notff2)|;
        } else {
            return qq| ((c.lithology1=$lith_term $ff1) OR (c.lithology2=$lith_term $ff2)) |;
        }
    } else {
        # if all the boxes were unchecked, just return (idiot proofing)
        if ( ! $carbonate && ! $mixed && ! $silic && ! $unknown)    {
            return "";
        }
        # only do something if some of the boxes aren't checked
        if  ( ! $carbonate || ! $mixed || ! $silic || ! $unknown)    {

            my $silic_str = join(",", map {"'".$_."'"} $hbo->getList('lithology_siliciclastic'));
            my $mixed_str = join(",", map {"'".$_."'"} $hbo->getList('lithology_mixed'));
            my $carbonate_str = join(",", map {"'".$_."'"} $hbo->getList('lithology_carbonate'));
            
            # the logic is basically different for every combination,
            #  so go through all of them
            # carbonate only
            if  ( $carbonate && ! $mixed && ! $silic )    {
                $lith_sql =  qq| ( c.lithology1 IN ($carbonate_str) $ff1 AND ( c.lithology2 IS NULL OR c.lithology2='' OR c.lithology2 IN ($carbonate_str) $notff2 ) ) |;
            }
            # mixed only
            elsif  ( ! $carbonate && $mixed && ! $silic )    {
                $lith_sql = qq| ( ( c.lithology1 IN ($mixed_str) $ff1 ) OR ( c.lithology2 IN ($mixed_str) $ff2 ) OR ( c.lithology1 IN ($carbonate_str) $ff1 AND c.lithology2 IN ($silic_str) $ff2 ) OR ( c.lithology1 IN ($silic_str) $ff1 AND c.lithology2 IN ($carbonate_str) $ff2 ) ) |;
            }
            # siliciclastic only
            elsif  ( ! $carbonate && ! $mixed && $silic )    {
                $lith_sql = qq| ( c.lithology1 IN ($silic_str) $ff1 AND ( c.lithology2 IS NULL OR c.lithology2='' OR c.lithology2 IN ($silic_str) $notff2 ) ) |;
            }
            # carbonate and siliciclastic but NOT mixed
            elsif  ( $carbonate && ! $mixed && $silic )    {
                $lith_sql = qq| ( ( c.lithology1 IN ($carbonate_str) $ff1 AND ( c.lithology2 IS NULL OR c.lithology2='' OR c.lithology2 IN ($carbonate_str) $notff2 ) ) OR ( c.lithology1 IN ($silic_str) $ff1 AND ( c.lithology2 IS NULL OR c.lithology2='' OR c.lithology2 IN ($silic_str) $notff2 ) ) ) |;
            }
            # carbonate and mixed
            elsif  ( $carbonate && $mixed && ! $silic )    {
                $lith_sql = qq| ( ( ( c.lithology1 IN ($mixed_str) $ff1 ) OR ( c.lithology2 IN ($mixed_str) $ff2 ) OR ( ( c.lithology1 IN ($carbonate_str) $ff1 ) AND ( c.lithology2 IN ($silic_str) $ff2 ) ) OR ( c.lithology1 IN ($silic_str) $ff1 AND c.lithology2 IN ($carbonate_str) $ff2 ) ) OR ( c.lithology1 IN ($carbonate_str) $ff1 AND ( c.lithology2 IS NULL OR c.lithology2='' OR c.lithology2 IN ($carbonate_str) $notff2 ) ) ) |;
            }
            # mixed and siliciclastic
            elsif  ( ! $carbonate && $mixed && $silic )    {
                $lith_sql = qq| ( ( ( c.lithology1 IN ($mixed_str) $ff1 ) OR ( c.lithology2 IN ($mixed_str) $ff2 ) OR ( c.lithology1 IN ($carbonate_str) $ff1 AND c.lithology2 IN ($silic_str) $ff2 ) OR ( c.lithology1 IN ($silic_str) $ff1 AND c.lithology2 IN ($carbonate_str) $ff2 ) ) OR ( c.lithology1 IN ($silic_str) $ff1 AND ( c.lithology2 IS NULL OR c.lithology2='' OR c.lithology2 IN ($silic_str) $notff2 ) ) ) |;
            }
            
            # lithologies where both fields are null
            if ($unknown) {
                my $unknown_sql = qq|((c.lithology1 IS NULL OR c.lithology1='') AND (c.lithology2 IS NULL OR c.lithology2=''))|;
                if ($lith_sql) {
                    $lith_sql = "($lith_sql OR $unknown_sql)";
                } else {
                    $lith_sql = "$unknown_sql";
                }    

            }
        }
    }

    return $lith_sql;
}

sub getEnvironmentString{
    my $self = shift;
    my $q = $self->{'q'};
    my $hbo = $self->{'hbo'};
    my $dbh = $self->{'dbh'};

    # ignore zone fields if only terrestrial plus all four terrestrial zones
    #  are unchecked, regardless of unknown JA 15.12.08
    if ( $q->param("environment_carbonate") && $q->param("environment_siliciclastic") && ! $q->param("environment_terrestrial") && ! $q->param("zone_lacustrine") && ! $q->param("zone_fluvial") && ! $q->param("zone_karst") && ! $q->param("zone_other_terrestrial") && $q->param("zone_marginal_marine") && $q->param("zone_reef") && $q->param("zone_shallow_subtidal") && $q->param("zone_deep_subtidal") && $q->param("zone_offshore") && $q->param("zone_slope_basin") && $q->param("zone_unknown") ) {
        $q->param("zone_lacustrine" => "YES");
        $q->param("zone_fluvial" => "YES");
        $q->param("zone_karst" => "YES");
        $q->param("zone_other_terrestrial" => "YES");
    }

    # likewise with marine environments, regardless of unknown
    if ( ! $q->param("environment_carbonate") && ! $q->param("environment_siliciclastic") && $q->param("environment_terrestrial") && $q->param("zone_lacustrine") && $q->param("zone_fluvial") && $q->param("zone_karst") && $q->param("zone_other_terrestrial") && ! $q->param("zone_marginal_marine") && ! $q->param("zone_reef") && ! $q->param("zone_shallow_subtidal") && ! $q->param("zone_deep_subtidal") && ! $q->param("zone_offshore") && ! $q->param("zone_slope_basin") && ! $q->param("zone_unknown") ) {
        $q->param("zone_marginal_marine" => "YES");
        $q->param("zone_reef" => "YES");
        $q->param("zone_shallow_subtidal" => "YES");
        $q->param("zone_deep_subtidal" => "YES");
        $q->param("zone_offshore" => "YES");
        $q->param("zone_slope_basin" => "YES");
        $q->param("zone_unknown" => "YES");
    }

    my $env_sql = '';

    # Environment or environments
    if ( $q->param('environment') ) {
        # Maybe this is redundant, but for consistency sake
        my $environment;
        if ($q->param('environment') =~ /General/) {
            $environment = join(",", map {"'".$_."'"} $hbo->getList('environment_general'));
        } elsif ($q->param('environment') =~ /Terrestrial/) {
            $environment = join(",", map {"'".$_."'"} $hbo->getList('environment_terrestrial'));
        } elsif ($q->param('environment') =~ /Siliciclastic/) {
            $environment = join(",", map {"'".$_."'"} $hbo->getList('environment_siliciclastic'));
        } elsif ($q->param('environment') =~ /Carbonate/) {
            $environment = join(",", map {"'".$_."'"} $hbo->getList('environment_carbonate'));
        } else {
            $environment = $dbh->quote($q->param('environment'));
        }

        if ($q->param('include_exclude_environment') eq "exclude") {
            return qq| (c.environment NOT IN ($environment) OR c.environment IS NULL) |;
        } else {
            return qq| c.environment IN ($environment)|;
        }
    } else {
        if (! $q->param("environment_carbonate") || ! $q->param("environment_siliciclastic") || ! $q->param("environment_terrestrial"))	{
            my $carbonate_str = join(",", map {"'".$_."'"} $hbo->getList('environment_carbonate'));
            my $siliciclastic_str = join(",", map {"'".$_."'"} $hbo->getList('environment_siliciclastic'));
            my $terrestrial_str = join(",", map {"'".$_."'"} $hbo->getList('environment_terrestrial'));
            if ( $q->param("environment_carbonate") ) {
                $env_sql .= " OR c.environment IN ($carbonate_str)";
            }
            if ( $q->param("environment_siliciclastic") ) {
                $env_sql .= " OR c.environment IN ($siliciclastic_str)";
            }
            if ( $q->param("environment_carbonate") && $q->param("environment_siliciclastic") )    {
                $env_sql .= " OR c.environment IN ('marine indet.','coastal indet.','deltaic indet.')";
            }
            if ( $q->param("environment_terrestrial") ) {
                $env_sql .= " OR c.environment IN ($terrestrial_str)";
            }
            $env_sql =~ s/^ OR//;
            if ($env_sql) {
                $env_sql = '('.$env_sql.')';
            }
        }
        if ( ! $q->param("zone_lacustrine") || ! $q->param("zone_fluvial") || ! $q->param("zone_karst") || ! $q->param("zone_other_terrestrial") || ! $q->param("zone_marginal_marine") || ! $q->param("zone_reef") || ! $q->param("zone_shallow_subtidal") || ! $q->param("zone_deep_subtidal") || ! $q->param("zone_offshore") || ! $q->param("zone_slope_basin") || ! $q->param("zone_unknown") ) {
            my @lists;
            my $zone_sql = " c.environment IN (";
            for my $z ( 'lacustrine','fluvial','karst','other_terrestrial','marginal_marine','reef','shallow_subtidal','deep_subtidal','offshore','slope_basin','unknown' )	{
                if ( $q->param("zone_".$z) )	{
                    push @lists , join(",", map {"'".$_."'"} $hbo->getList('zone_'.$z));
                }
            }
            if ( $q->param("zone_marginal_marine") && $q->param("zone_reef") && $q->param("zone_shallow_subtidal") && $q->param("zone_deep_subtidal") && $q->param("zone_offshore") && $q->param("zone_slope_basin") && ! $q->param("zone_unknown") )	{
                push @lists , "'coastal indet.','deltaic indet.'";
            }
            if ( @lists )	{
                $zone_sql .= join(',',@lists) . ")";
                if ($zone_sql) {
                    $zone_sql = '('.$zone_sql.')';
                    if ($env_sql) {
                        $env_sql = '('.$env_sql.' AND '.$zone_sql.')';
                    } else	{
                        $env_sql = $zone_sql;
                    }
                }
            }
        }
   }

    # whoops, clause needs to be at the end JA 15.4.13
    if ( $q->param("environment_unknown") && $env_sql ) {
        $env_sql = "($env_sql OR c.environment = '' OR c.environment IS NULL)"; 
    } elsif ( ! $q->param("environment_carbonate") && ! $q->param("environment_siliciclastic") && ! $q->param("environment_terrestrial") && $q->param("environment_unknown") ) {
        $env_sql = "(c.environment = '' OR c.environment IS NULL)"; 
    }
    return $env_sql;
}

sub getGeogscaleString{
    my $self = shift;
    my $q = $self->{'q'};

    my $geogscales = "";
    if (! $q->param('geogscale_small_collection') || !$q->param('geogscale_hand_sample') || ! $q->param('geogscale_outcrop') || ! $q->param('geogscale_local_area') ||
        ! $q->param('geogscale_basin') || ! $q->param('geogscale_unknown')) { 
        if ( $q->param('geogscale_hand_sample') )    {
            $geogscales = "'hand sample'";
        }
        if ( $q->param('geogscale_small_collection') )    {
            $geogscales .= ",'small collection'";
        }
        if ( $q->param('geogscale_outcrop') )    {
            $geogscales .= ",'outcrop'";
        }
        if ( $q->param('geogscale_local_area') )    {
            $geogscales .= ",'local area'";
        }
        if ( $q->param('geogscale_basin') )    {
            $geogscales .= ",'basin'";
        }
        if ( $q->param('geogscale_unknown') ) {
            $geogscales .= ",''";
        }    
        $geogscales =~ s/^,//;
        if ( $geogscales )    {
            $geogscales = qq| c.geogscale IN ($geogscales) |;
            if ( $q->param('geogscale_unknown')) {
                $geogscales = " (".$geogscales."OR c.geogscale IS NULL)";
            }
        }
    }
    return $geogscales;
}

sub getStratscaleString{
    my $self = shift;
    my $q = $self->{'q'};

    my $stratscales = "";

    if (! $q->param('stratscale_bed') || ! $q->param('stratscale_group_of_beds') || ! $q->param('stratscale_member') ||
        ! $q->param('stratscale_formation') || ! $q->param('stratscale_group') || ! $q->param('stratscale_unknown')) {
        if ( $q->param('stratscale_bed') )    {
            $stratscales = "'bed'";
        }
        if ( $q->param('stratscale_group_of_beds') )    {
            $stratscales .= ",'group of beds'";
        }
        if ( $q->param('stratscale_member') )    {
            $stratscales .= ",'member'";
        }
        if ( $q->param('stratscale_formation') )    {
            $stratscales .= ",'formation'";
        }
        if ( $q->param('stratscale_group') )    {
            $stratscales .= ",'group'";
        }
        if ( $q->param('stratscale_unknown') ) {
            $stratscales .= ",''";
        }
       
        $stratscales =~ s/^,//;
        if ( $stratscales )    {
            $stratscales = qq| c.stratscale IN ($stratscales) |;
            if ($q->param('stratscale_unknown')) {
                $stratscales = " (".$stratscales."OR c.stratscale IS NULL)";
            }
        }
    }
    return $stratscales;
}

sub getPreservationModeString {
    my $self = shift;
    my $q = $self->{'q'};
    my $dbh = $self->{'dbh'};

    # the form should use underscores, the database doesn't JA 28.9.12
    my @pres_modes_all = ('cast','adpression','soft_parts','original_aragonite','mold/impression','replaced_with_silica','trace','charcoalification','coalified');
    my $has_other = ($q->param('pres_mode_other') eq 'YES') ? 1 : 0; 

    # If its in the form, stick in in the array
    my @pres_modes = grep {$q->param('pres_mode_'.$_) eq 'YES'} @pres_modes_all;

    my $seen_checkbox = ($has_other + @pres_modes);
    my $total_checkbox = (1 + @pres_modes_all);

    my $sql = "";
    if ($seen_checkbox > 0 && $seen_checkbox < $total_checkbox) {
        if ($has_other) {
            my %seen_modes = ();
            foreach (@pres_modes_all) {
                $seen_modes{$_} = 1;
            }
            foreach (@pres_modes) {
                delete $seen_modes{$_};
            }
            my @pres_modes_missing = keys %seen_modes;
            $pres_modes_missing[$_] =~ s/_/ /g foreach 0..$#pres_modes_missing;
            $pres_modes[$_] =~ s/_/ /g foreach 0..$#pres_modes;
            $sql = "(pres_mode IS NULL OR (".join(" AND ", map{'NOT FIND_IN_SET('.$dbh->quote($_).',pres_mode)'} @pres_modes_missing)."))";
        } else {
            $pres_modes[$_] =~ s/_/ /g foreach 0..$#pres_modes;
            $sql = "(".join(" OR ",  map{'FIND_IN_SET('.$dbh->quote($_).',pres_mode)'} @pres_modes).")";
        }
    }
    return $sql;

}

# JA 23.5.08
sub getCollMethString {
    my $self = shift;
    my $q = $self->{'q'};
    my $dbh = $self->{'dbh'};

    my $sql = "";
    my $sql2 = "";
    if ( $q->param('sieve') =~ /not sieved/ )	{
        $sql = "(coll_meth IS NULL OR coll_meth NOT LIKE '%sieve%')";
    } elsif ( $q->param('sieve') =~ /not easily sieved/ )	{
        $sql = "(coll_meth IS NULL OR coll_meth NOT LIKE '%sieve%' OR coll_meth LIKE '%chemical%' OR coll_meth LIKE '%mechanical%' OR (lithification='lithified' AND lithification2 IS NULL) OR (lithification IS NULL AND lithification2='lithified') OR (lithification='lithified' AND lithification2='lithified'))";
    } elsif ( $q->param('sieve') =~ /easily sieved/ )	{
        $sql = "(coll_meth LIKE '%sieve%' AND coll_meth NOT LIKE '%chemical%' AND coll_meth NOT LIKE '%mechanical%' AND (lithification IS NULL OR lithification!='lithified') AND (lithification2 IS NULL OR lithification2!='lithified'))";
    } elsif ( $q->param('sieve') =~ /sieved/ )	{
        $sql = "(coll_meth LIKE '%sieve%')";
    }
    return $sql;

}

sub getCollectionTypeString{
    my $self = shift;
    my $q = $self->{'q'};

    my $colltypes = "";
    # Collection types
    if (! $q->param('collection_type_archaeological') || ! $q->param('collection_type_biostratigraphic') ||
        ! $q->param('collection_type_paleoecologic') || ! $q->param('collection_type_taphonomic') ||
        ! $q->param('collection_type_taxonomic') || ! $q->param('collection_type_general_faunal/floral') ||
        ! $q->param('collection_type_unknown')) {
        if ($q->param('collection_type_archaeological')) {
            $colltypes .= ",'archaeological'";
        }
        if ($q->param('collection_type_biostratigraphic')) {
            $colltypes .= ",'biostratigraphic'";
        }
        if ($q->param('collection_type_paleoecologic')) {
            $colltypes .= ",'paleoecologic'";
        }
        if ($q->param('collection_type_taphonomic')) {
            $colltypes .= ",'taphonomic'";
        }
        if ($q->param('collection_type_taxonomic')) {
            $colltypes .= ",'taxonomic'";
        }
        if ($q->param('collection_type_general_faunal/floral')) {
            $colltypes .= ",'general faunal/floral'";
        }
        if ($q->param('collection_type_unknown')) {
            $colltypes .= ",''";
        }
        $colltypes =~ s/^,//;
        if ( $colltypes)    {
            $colltypes = qq| c.collection_type IN ($colltypes) |;
            if ($q->param('collection_type_unknown')) {
                $colltypes = "(".$colltypes." OR c.collection_type IS NULL)";
            }
        }
    }
    return $colltypes;
}

# WARNING: this code is slightly buggy because it assumes that senior synonym
#  masking has no logical impact on the original resos, which might or might
#  not make sense, especially for n. gen. and n. sp.
# we make this problem somewhat transparent to the user by not carrying
#  over the reso in such cases
sub getResoString{
    my $self = shift;
    my $level = shift;
    my $q = $self->{'q'};

    my $resos = "";
    my $unchecked;
    for my $r ( @reso_types_group )	{
        if ( ! $q->param($level.'_reso_'.$r) )	{
            $unchecked++;
        }
    }
    if ( $unchecked > 0 && $unchecked < $#reso_types_group + 1 )	{
        if ( $q->param($level.'_reso_aff.') )    {
            $resos .= ",'aff.'";
        }
        if ( $q->param($level.'_reso_cf.') )    {
            $resos .= ",'cf.'"; }
        if ( $q->param($level.'_reso_ex gr.') )    {
            $resos .= ",'ex gr.'";
        }
        if ( $q->param($level.'_reso_new') ) {
            if ( $level eq "genus" )	{
                $resos .= ",'n. gen.'";
            } else	{
                $resos .= ",'n. sp.'";
            }
        }
        if ( $q->param($level.'_reso_sensu lato') )    {
            $resos .= ",'sensu lato'";
        }
        if ( $q->param($level.'_reso_?') )    {
            $resos .= ",'?'";
        }
        if ( $q->param($level.'_reso_"') )    {
            $resos .= ",'\"'";
        }
        if ( $q->param($level.'_reso_informal') )    {
            $resos .= ",'informal'";
        }
        if ( $q->param($level.'_reso_other') )    {
            $resos .= ",''";
        }
        $resos =~ s/^,//;
    # only return something if at least one box was checked
        if ( $resos )    {
            $resos = " o.".$level."_reso IN ($resos) ";
    # $reso is good enough on its own unless 'other' is checked JA 18.12.08
            if ( $q->param($level.'_reso_other') )    {
                $resos = " (" . $resos ."OR o.".$level."_reso IS NULL)";
            }
        
        }
    }
    # informal needs special handling because the default is to exclude it
    # so, if no boxes were checked at all, exclude it anyway
    if ( ! $resos && $unchecked == $#reso_types_group + 1 && $level =~ /genus/i )	{
        $resos = " (o.".$level."_reso NOT IN ('informal') OR o.".$level."_reso IS NULL OR o.".$level."_reso='')";
    }
    return $resos;
}


# Returns three where arrays: The first is applicable to the both the occs
# and reids table, the second is occs only, and the third is reids only
sub getOccurrencesWhereClause {
    my $self = shift;
    my $q = $self->{'q'};
    my $dbh = $self->{'dbh'};
    my $dbt = $self->{'dbt'};

    my (@all_where,@occ_where,@reid_where);

    if ( $q->param('pubyr') > 0 && $q->param('output_data') !~ /collections/i )    {
        my $pubyrrelation = ">=";
        if ( $q->param('published_before_after') eq "before" )    {
            $pubyrrelation = "<";
        } 
        push @all_where,"r.pubyr".$pubyrrelation.$q->param('pubyr');
    }

    my $plantOrganFieldCount = 0;
    my @includedPlantOrgans = ();
    foreach my $plantOrganField (@plantOrganFieldNames) {
        if ($q->param("plant_organ_".$plantOrganField)) {
            $plantOrganFieldCount++;
            push @includedPlantOrgans, $dbh->quote($plantOrganField);
        }
    }
    if ($plantOrganFieldCount != 0 && $plantOrganFieldCount != scalar(@plantOrganFieldNames)) {
        my $plant_organs = join(",", @includedPlantOrgans);
        if ( $q->param('plant_organ_unassigned') eq 'YES' )	{
            push @occ_where, "(o.plant_organ IN ($plant_organs) OR o.plant_organ2 IN ($plant_organs) OR (o.plant_organ IS NULL AND o.plant_organ2 IS NULL))";
            push @reid_where, "(o.plant_organ IN ($plant_organs) OR o.plant_organ2 IN ($plant_organs) OR (o.plant_organ IS NULL AND o.plant_organ2 IS NULL))";
        } else	{
            push @occ_where, "(o.plant_organ IN ($plant_organs) OR o.plant_organ2 IN ($plant_organs))";
            push @reid_where, "(o.plant_organ IN ($plant_organs) OR o.plant_organ2 IN ($plant_organs))";
        }
    }  

# I'm not sure this is going to work if reidentifications are not used
    if ($q->param("classified") =~ /unclassified/i) {
        push @occ_where, "o.taxon_no=0";
        push @reid_where, "re.taxon_no=0";
    } elsif ($q->param("classified") =~ /classified/i) {
        push @occ_where, "o.taxon_no != 0";
        push @reid_where, "re.taxon_no != 0";
    }

   
    if ($q->param('authorizer_reversed')) {
        my $name = $q->param('authorizer_reversed');
        $name =~ s/^\s*(.*)\s*,\s*(.*)\s*$/$2 $1/;
        my $quoted_name = $dbh->quote($name);
        my $sql = "SELECT person_no FROM person WHERE name=$quoted_name";
        my $authorizer_no = ${$dbt->getData($sql)}[0]->{'person_no'};
        push @all_where, "o.authorizer_no=".$authorizer_no if ($authorizer_no);
    }

    push @all_where, "o.abund_unit NOT LIKE \"\" AND o.abund_value IS NOT NULL" if $q->param("abundance_required") eq 'abundances';
    push @all_where, "o.abund_unit IN ('individuals','specimens') AND o.abund_value IS NOT NULL" if $q->param("abundance_required") eq 'specimens';

    push @occ_where, "o.species_name NOT LIKE '%indet%'" if $q->param('indet') ne 'YES';
    push @occ_where, "o.species_name!='sp.'" if $q->param('sp') eq 'NO';
    my $genusResoString = $self->getResoString('genus');
    push @occ_where, $genusResoString if $genusResoString;
    my $speciesResoString = $self->getResoString('species');
    push @occ_where, $speciesResoString if $speciesResoString;

    push @reid_where, "re.species_name NOT LIKE '%indet.%'" if $q->param('indet') ne 'YES';
    push @reid_where, "re.species_name!='sp.'" if $q->param('sp') eq 'NO';

    # this is kind of a hack, I admit it JA 31.7.05
    $genusResoString =~ s/o\.genus_reso/re.genus_reso/g;
    push @reid_where, $genusResoString if $genusResoString;
    $speciesResoString =~ s/o\.species_reso/re.species_reso/g;
    push @reid_where, $speciesResoString if $speciesResoString;

    return (\@all_where,\@occ_where,\@reid_where);
}

sub getCollectionsWhereClause {
    my $self = shift;
    my $q = $self->{'q'};
    my $dbt = $self->{'dbt'};
    my $dbh = $self->{'dbh'};

    my @where = ();

    if ( my $state = $q->param('state') )
    {
	my $quoted = $dbh->quote($state);
        push @where," c.state=$quoted";
    }
    
    if ( $q->param('pubyr') > 0 && $q->param('output_data') =~ /collections/i )    {
        my $pubyrrelation = ">=";
        if ( $q->param('published_before_after') eq "before" )    {
            $pubyrrelation = "<";
        } 
        push @where," r.pubyr".$pubyrrelation.$q->param('pubyr')." ";
    }

    # This is handled by getOccurrencesWhereClause if we're getting occs data.
    if($q->param('output_data') eq 'collections' && $q->param('authorizer_reversed')) {
        my $name = $q->param('authorizer_reversed');
        $name =~ s/^\s*(.*)\s*,\s*(.*)\s*$/$2 $1/;
        my $quoted_name = $dbh->quote($name);
        my $sql = "SELECT person_no FROM person WHERE name=$quoted_name";
        my $authorizer_no = ${$dbt->getData($sql)}[0]->{'person_no'};
        push @where, "c.authorizer_no=".$authorizer_no if ($authorizer_no);
    }
    my $resGrpRestrictedTo = ($q->param('research_group_restricted_to')) ? '1' : '0';
    my $resGrpString = PBDB::PBDBUtil::getResearchGroupSQL($dbt,$q->param('research_group'),$resGrpRestrictedTo);
    push @where, $resGrpString if ($resGrpString);
    
    # should we filter the data based on collection creation date?
    # added by rjp on 12/30/2003, some code copied from Curve.pm.
    # (filter it if they enter a year at the minimum.
    if ($q->param('year')) {

        my $created_string;
        my $created_date = $self->formCreatedDate(); 
        # if so, did they want to look before or after?
        if ($q->param('created_before_after') eq "before") {
            if ( $q->param('output_data') eq 'collections' )    {
                $created_string = " c.created < $created_date ";
            } else    {
                $created_string = " o.created < $created_date ";
            }
        } elsif ($q->param('created_before_after') eq "after") {
            if ( $q->param('output_data') eq 'collections' )    {
                $created_string = " c.created >= $created_date ";
            } else    {
                $created_string = " o.created >= $created_date ";
            }
        }
    
    # from 6.2.07 through 27.9.07 I had some code at about this point
    #  that also sifted the reIDs by creation date if created_before_after
    #  was used; this was a really bad idea because:
    #  (1) it is impossible to sort out which reID is the "most recent"
    #    if the most recent was entered after a created-before date but
    #    the occurrence itself was created before it
    #  (2) in such cases the occurrence got knocked out completely anyway
    #  (3) similar manipulations cannot be done on the synonymy mask

        push @where,$created_string;

    }
    
    my $restrict_to_field = $q->param("restrict_to_field") // '';
    my $restrict_to_list = $q->param("restrict_to_list") // '';
    
    if ( $restrict_to_field =~ /[a-z]*/ && $restrict_to_list =~ /[A-Za-z0-9]/)
    {
        # treat it as a name with a wildcard if there are letters
        # won't work if the user actually wants reference or collection nos
        #  JA 17.8.08
        if ($restrict_to_list =~ /[A-Za-z]/)
	{
	    my $quoted = $dbh->quote($restrict_to_list . '%');
	    
            if ( $restrict_to_field eq "strat_unit" )
	    {
                push @where, "(c.geological_group LIKE $quoted OR c.formation LIKE $quoted OR c.member LIKE $quoted)"
            }
	    
	    elsif ( $restrict_to_field =~ /^\w+$/ )
	    {
                push @where, "c.$restrict_to_field LIKE $quoted";
            }
        }
	
	elsif ($restrict_to_field =~ /(_no|plate)$/)
	{
	    # Clean it up
            my @nos = split(/[^0-9]/,$q->param('restrict_to_list'));
            my $list = join(',', map {int($_)} @nos);
	    
            if ( $restrict_to_field =~ /reference_no/ )
	    {
                push @where, "(c.reference_no IN ($list) OR sr.reference_no IN ($list))";
            }
	    
	    elsif ( $restrict_to_field =~ /^\w+$/ )
	    {
                push @where, "c.$restrict_to_field IN ($list)";
            }
        }
    }

	# this one is super-simple, no need to make it a separate function
	# note that a member name by itself is not adequate info (as mentioned
	#  where strat lumping is carried out)
	# JA 4.4.11
	if ( $q->param('require_strat_unit') =~ /y/i )	{
		push @where , "(c.geological_group IS NOT NULL OR c.formation IS NOT NULL)";
	}

    foreach my $whereItem (
        $self->getCountryString(),
        $self->getPlateString(),
        $self->getLatLongString(),
        $self->getPaleoLatLongString(),
        $self->getIntervalString(),
        $self->getLithificationString(),
        $self->getLithologyString(),
        $self->getEnvironmentString(),
        $self->getGeogscaleString(),
        $self->getStratscaleString(),
        $self->getCollectionTypeString(),
        $self->getPreservationModeString(),
        $self->getCollMethString(),
        $self->getSubsetString()) {
        push @where,$whereItem if ($whereItem);
    }

    return @where;
}

sub formCreatedDate	{
    my $self = shift;
    my $q = $self->{'q'};
    my $dbh = $self->{'dbh'};

    my $month = ($q->param('month') || "01");
    my $day = ($q->param('day_of_month') || "01");

    if ( length $month == 1 )    {
       $month = "0" . $month;
    }
    if ( length $day == 1 )    {
       $day = "0" . $day;
    }

    return $dbh->quote($q->param('year')."-".$month."-".$day." 00:00:00");
}

sub getSubsetString {
    my $self = shift;
    my $q = $self->{'q'};
    my $dbt = $self->{'dbt'};

    my $str = "";
    # Maybe this isn't super scalable (just gets all collections that have at least one subset) but its
    # fast enough as this is only 260 collections or so right now (PS 2/13/2005);
    # maybe update this to a subselect if mysql ever gets upgraded
    if ($q->param('exclude_superset') =~ /YES/i) {
        my $sql = "select distinct collection_subset from collections where collection_subset is not null";
        my @results = @{$dbt->getData($sql)};
        my $collections = join(", ",map{$_->{'collection_subset'}} @results);
        $str = "c.collection_no NOT IN ($collections)";
    } 
    return $str;
}

# JA 29-31.5.13
# replaces a long section of code that used to be towards the end of
#  queryDatabase
# returns name, rank, senior synonym, current spelling, parents, and extant for
#  all taxa appearing in the occurrences
# this function is quite fast, and most of the hangtime in downloads is actually
#  related to the main occurrence table query
sub fastClassificationLookups	{
	my ($dbt,$include_taxa,$subtaxa) = @_;
	my @taxa = split(/\s*[, \t\n-:;]{1}\s*/,$include_taxa);

	my %used;
	$used{$_}++ foreach @$subtaxa;

	# get the spellings and senior synonyms first
	my @tree_info = @{$dbt->getData("SELECT taxon_no,spelling_no,synonym_no FROM $TAXA_TREE_CACHE WHERE taxon_no IN (".join(',',keys %used).")")};
	for my $t ( @tree_info )	{
		$synonym{$t->{$_}} = $t->{synonym_no} foreach ('taxon_no','spelling_no','synonym_no');
		$spelling{$t->{$_}} = $t->{spelling_no} foreach ('taxon_no','spelling_no');
		$spelling{$t->{synonym_no}} = $t->{synonym_no};
		$used{$t->{spelling_no}}++;
		$used{$t->{synonym_no}}++;
	}

	# get basic info for all used taxa including their current spellings and
	#  senior synonyms
	my @all_subtaxa = @{$dbt->getData("SELECT taxon_no,taxon_name,taxon_rank,extant FROM authorities WHERE taxon_no IN (".join(',',keys %used).")")};
	for my $s ( @all_subtaxa )	{
		$name{$s->{taxon_no}} = $s->{taxon_name};
		$rank{$s->{taxon_no}} = $s->{taxon_rank};
		$extant{$s->{taxon_no}} = $s->{extant};
		if ( $rank{$s->{taxon_no}} =~ /^(class|order|family|genus|subgenus)$/ )	{
			$parents{$s->{taxon_no}}{$s->{taxon_rank}} = $s->{taxon_no};
		}
	}

	# get all the parents at ranks of interest
	# this will override bogus parent-of-self values for invalid names
	#  that were just computed above
	# the lowest-ranking family (or whatever) will be kept if there are
	#  nested parents of the same rank because the parents are checked
	#  from highest to lowest
	delete $used{''};

	my $child_list = join(',', keys %used);
	my $sql = "WITH RECURSIVE ancestors as (
		SELECT taxon_no, taxon_no as base_no, spelling_no, opinion_no, lft
		FROM $TAXA_TREE_CACHE
		WHERE taxon_no in ($child_list)
	  UNION SELECT t.taxon_no, ancestors.base_no, t.spelling_no, t.opinion_no, t.lft
		FROM ancestors
			join opinions as o using (opinion_no)
			join $TAXA_TREE_CACHE as t on t.taxon_no = o.parent_spelling_no
		WHERE t.spelling_no <> ancestors.spelling_no )
		SELECT ancestors.base_no, a.taxon_name, a.taxon_rank, a.taxon_no as child_no,
			o.parent_spelling_no as parent_no, o.status
		FROM ancestors join opinions as o using (opinion_no)
			join authorities as a on a.taxon_no = ancestors.spelling_no
		WHERE a.taxon_rank in ('class', 'order', 'family', 'genus', 'subgenus')
		ORDER by lft";
	
	my @parent_child = @{$dbt->getData($sql)};
	
	# my @parent_child = @{$dbt->getData("SELECT taxon_name,taxon_rank,parent_no,child_no FROM
	# authorities a,$TAXA_LIST_CACHE l WHERE taxon_no=parent_no AND child_no IN
	# (".join(',',keys %used).") AND taxon_rank IN
	# ('class','order','family','genus','subgenus') AND child_no!=parent_no")};
	
	my %used_anywhere = %used;
	
	foreach my $record ( @parent_child )
	{
	    $parents{$record->{base_no}}{$record->{taxon_rank}} = $record->{child_no}
		if $record->{child_no} ne $record->{base_no};
	    $parents{$record->{child_no}}{immediate} = $record->{parent_no};
	    $name{$record->{parent_no}} = $record->{taxon_name};
	    $rank{$record->{parent_no}} = $record->{taxon_rank};
	    $used_anywhere{$record->{parent_no}}++;
	    if ( $record->{status} =~ /nomen/ )	{
		$nomen{$record->{child_no}}++;
	    }
	}
	
	# for my $p ( @parent_child )	{
	# 	my $no = $p->{parent_no};
	# 	$name{$no} = $p->{taxon_name};
	# 	$rank{$no} = $p->{taxon_rank};
	# 	$used_anywhere{$no}++;
	# }
	
	# # an entirely different method is needed to get immediate parents
	# my @immediates = @{$dbt->getData("SELECT taxon_name,taxon_rank,a.taxon_no parent_no,t.taxon_no child_no,status FROM authorities a,$TAXA_TREE_CACHE t,opinions o WHERE a.taxon_no=parent_spelling_no AND t.opinion_no=o.opinion_no AND t.taxon_no IN (".join(',',keys %used).")")};
	# for my $p ( @immediates )	{
	# 	my $no = $p->{parent_no};
	# 	$name{$no} = $p->{taxon_name};
	# 	$rank{$no} = $p->{taxon_rank};
	# 	$used_anywhere{$no}++;
	# 	$parents{$p->{child_no}}{'immediate'} = $no;
	# 	# nomina dubia etc. have to be tracked because their species
	# 	#  names shouldn't be salvaged later on JA 10.6.13
	# 	if ( $p->{status} =~ /nomen/ )	{
	# 		$nomen{$p->{child_no}}++;
	# 	}
	# }
	
	# record stripped subgenus names if relevant
	for my $no ( keys %used )	{
		if ( $parents{$no}{'subgenus'} )	{
			$subgenus{$no} = $name{$parents{$no}{'subgenus'}};
			$subgenus{$no} =~ s/[A-Z][a-z]* \(//;
			$subgenus{$no} =~ s/\)//;
			# the subgenus of a subgenus is itself (just in case)
			$subgenus{$parents{$no}{'subgenus'}} = $subgenus{$no};
		}
	}

	# if the full name of a "valid" species is inconsistent with the valid
	#  genus or subgenus then something is wrong and this module should
	#  treat it as invalid and equivalent to the genus
	# most of these cases involve molluscan species that have most
	#  recently been assigned to a "genus" that itself is now treated as
	#  subgenus; if so, then the species' status hasn't been looked into and
	#  its correct Latin gender can't be determined
	for my $no ( keys %used )	{
		my $sen = $synonym{$no};
		if ( $rank{$sen} =~ /species/ )	{
			my ($g,$sg,$s,$ss) = PBDB::Taxon::splitTaxon($name{$sen});
			if ( $g ne $name{$parents{$sen}{'genus'}} || ( $g." (".$sg.")" ne $name{$parents{$sen}{'subgenus'}} && $name{$parents{$sen}{'subgenus'}} ) )	{
				$synonym{$no} = $parents{$no}{'genus'};
				$spelling{$no} = $parents{$no}{'genus'};
				delete $subgenus{$no};
			}
		}
	}

	# determine extant values for parents at ranks of interest

	$child_list = join(',', keys %used_anywhere);
	
	$sql = "WITH RECURSIVE ancestors as (
		SELECT t.taxon_no, t.spelling_no, t.opinion_no
		FROM $TAXA_TREE_CACHE as t join authorities as a using (taxon_no)
		WHERE taxon_no in ($child_list) and a.extant = 'yes'
	  UNION SELECT t.taxon_no, t.spelling_no, t.opinion_no
		FROM ancestors
			join opinions as o using (opinion_no)
			join $TAXA_TREE_CACHE as t on t.taxon_no = o.parent_spelling_no
		WHERE t.spelling_no <> ancestors.spelling_no )
		SELECT distinct ancestors.taxon_no
		FROM ancestors join authorities as a on a.taxon_no = ancestors.spelling_no
		WHERE a.taxon_rank in ('class', 'order', 'family', 'genus', 'subgenus', 'species', 'subspecies')";
	
	my @extants = @{$dbt->getData($sql)};

	$extant{$_->{taxon_no}} = 'yes' foreach @extants;
	
	# my @extants = @{$dbt->getData("SELECT parent_no FROM authorities a,authorities a2,$TAXA_LIST_CACHE l WHERE a.taxon_no=parent_no AND a2.taxon_no=child_no AND child_no IN (".join(',',keys %used_anywhere).") AND a2.extant='yes' AND a.taxon_rank IN ('class','order','family','genus','subgenus','species','subspecies') AND child_no!=parent_no GROUP BY parent_no")};
	# $extant{$_->{parent_no}} = 'yes' foreach @extants;
	# delete $extant{''};

	# likewise for focal taxa based on their children

	my $focal_list = join(',', keys %used);
	
	$sql = "SELECT distinct p.taxon_no
		FROM taxa_tree_cache as p join taxa_tree_cache as c on c.lft between p.lft and p.rgt
			join authorities as a on a.taxon_no = c.taxon_no
		WHERE p.taxon_no in ($focal_list) and a.extant='yes'";
	
	@extants = @{$dbt->getData($sql)};
	$extant{$_->{taxon_no}} = 'yes' foreach @extants;
	
	# my @extants = @{$dbt->getData("SELECT parent_no FROM authorities a,authorities a2,$TAXA_LIST_CACHE l WHERE a.taxon_no=parent_no AND a2.taxon_no=child_no AND parent_no IN (".join(',',keys %used).") AND a2.extant='yes' AND child_no!=parent_no GROUP BY parent_no")};
	# $extant{$_->{parent_no}} = 'yes' foreach @extants;
	
	delete $extant{''};
	
	return;
}


# Assembles and executes the query.  Does a join between the occurrences and
# collections tables, filters the results against the appropriate 
# cgi-bin/data/classdata/ file if necessary, does another select for all fields
# from the refs table for any as-yet-unqueried ref, and writes out the data.
sub queryDatabase {
    my $self = shift;
    my $q = $self->{'q'};
    my $p = $self->{'p'}; #Permissions object
    my $dbt = $self->{'dbt'};
    my $dbh = $self->{'dbh'};

    if ( $q->param('occurrences_abund') )	{
        $q->param('occurrences_abund_value' => 'YES');
        $q->param('occurrences_abund_unit' => 'YES');
    }

    # Call as needed
    $self->setupQueryFields() if (! $self->{'setup_query_fields_called'});


    ###########################################################################
    #  Generate the query
    ###########################################################################

    my (@fields,@where,@occ_where,@reid_where,$taxon_where,@tables,@from,@groupby,@left_joins);

    @fields = ('c.authorizer_no','c.authorizer AS `c.authorizer`','c.license','c.reference_no','c.collection_no','c.research_group','c.access_level',"DATE_FORMAT(c.release_date, '%Y%m%d') rd_short",'CONCAT(c.enterer_no," ",TO_DAYS(c.created),HOUR(c.created)) AS personhour','c.upload');
    @tables = ('collections as c');
    @where = $self->getCollectionsWhereClause();
    
    if ($q->param('output_data') =~ /occurrence|collections/) {
        my @collection_columns = $dbt->getTableColumns('collections');
        if ( $q->param('incomplete_abundances') eq "NO" && ! $q->param('collections_collection_coverage') )	{
            push @fields,"c.collection_coverage AS `c.collection_coverage`";
        }
        if ( $q->param('collections_pubyr') eq "YES" )	{
            $q->param('collections_reference_no' => "YES");
        }
        foreach my $c (@collection_columns) {
            next if ($c =~ /^(lat|lng)(deg|dec|min|sec|dir)$/); # handled below - handle these through special "coords" fields
            if ($q->param("collections_".$c)) {
                push @fields,"c.$c AS `c.$c`";
            }
        }
	# altitude fields if requested
	if ( $q->param('collections_altitude') eq 'YES' )
	{
	    push @fields, "c.altitude_value as `c.altitude_value`", "c.altitude_unit as `c.altitude_unit`";
	}
        # these data are always needed for range computations
        push @fields , "c.".$_." AS `c.".$_."`" foreach ( 'direct_ma','direct_ma_error','direct_ma_unit','direct_ma_method','max_ma','max_ma_error','max_ma_unit','max_ma_method','min_ma','min_ma_error','min_ma_unit','min_ma_method','ma_interval_no' );
        if ($q->param('collections_direct_ma') eq 'YES')	{
            $q->param('collections_direct_ma_error' => "YES");
            $q->param('collections_direct_ma_method' => "YES");
        }
        if ($q->param('collections_max_ma') eq 'YES')	{
            $q->param('collections_max_ma_error' => "YES");
            $q->param('collections_max_ma_method' => "YES");
        }
        if ($q->param('collections_min_ma') eq 'YES')	{
            $q->param('collections_min_ma_error' => "YES");
            $q->param('collections_min_ma_method' => "YES");
        }
        if ($q->param('collections_paleocoords') eq 'YES')	{
            push @fields,"c.paleolat AS `c.paleolat`";
            push @fields,"c.paleolng AS `c.paleolng`";
        }
	if ($q->param('collections_gplates') eq 'YES')
	{
	    push @tables, "paleocoords as pc";
	    push @where, "pc.collection_no = c.collection_no";
	    push @fields, "pc.early_lat AS `c.gp_early_lat`";
	    push @fields, "pc.early_lng AS `c.gp_early_lng`";
	    push @fields, "pc.mid_lat AS `c.gp_mid_lat`";
	    push @fields, "pc.mid_lng AS `c.gp_mid_lng`";
	    push @fields, "pc.late_lat AS `c.gp_late_lat`";
	    push @fields, "pc.late_lng AS `c.gp_late_lng`";
	}
        if ($q->param('collections_coords') eq 'YES')	{
            push @fields , "c.".$_." AS `c.".$_."`" foreach ( 'lngdeg','lngmin','lngsec','lngdec','lngdir','latdeg','latmin','latsec','latdec','latdir' );
        }
        if ($q->param('collections_enterer') eq 'YES')	{
            push @fields, 'c.enterer';
        }
        if ($q->param('collections_modifier') eq 'YES')	{
            push @fields, 'c.modifier';
        }
    }

    # We'll want to join with the reid ids if we're hitting the occurrences table,
    # or if we're getting collections and filtering using the taxon_no in the occurrences table
    # or excluding collections based on occurrence or abundance counts
    my $join_reids = ($q->param('output_data') =~ /occurrence|taxonomic.list/ || $q->param('taxon_name') || $q->param('exclude_taxon_name') || $q->param('occurrence_count') || $q->param('abundance_count')) ? 1 : 0;
    if ($join_reids) {
        push @tables, 'occurrences as o', 'authorities as a';
        unshift @where, 'c.collection_no = o.collection_no and a.taxon_no = o.taxon_no';
	
        if ($q->param('output_data') =~ /occurrence|taxonomic.list/) {
            push @fields, 'o.occurrence_no AS `o.occurrence_no`', 
                       'o.reference_no AS `o.reference_no`', 
                       'o.genus_reso AS `o.genus_reso`', 
                       'o.genus_name AS `o.genus_name`',
                       'o.species_name AS `o.species_name`',
                       'o.taxon_no AS `o.taxon_no`',
		       'a.form_taxon, a.preservation';
       if ( $q->param('abundance_taxon_name') =~ /[A-Za-z]/ )	{
            my $taxa = $self->getTaxonString($q->param('abundance_taxon_name'),'');
            $taxa =~ s/table\.taxon/o.taxon/;
            if ( $q->param('abundance_taxon_include') eq "include" )	{
                push @fields, "IF ($taxa,o.abund_value,NULL) `o.abund_value`";
                push @fields, "IF ($taxa,o.abund_unit,NULL) `o.abund_unit`";
            } else	{
                push @fields, "IF ($taxa,NULL,o.abund_value) `o.abund_value`";
                push @fields, "IF ($taxa,NULL,o.abund_unit) `o.abund_unit`";
            }
       } else	{
           push @fields, 'o.abund_value AS `o.abund_value`',
                       'o.abund_unit AS `o.abund_unit`';
       }
                       
            if ( $q->param('replace_with_reid') ne 'NO' )   {
                push @fields, 're.reid_no AS `re.reid_no`',
                           're.reference_no AS `re.reference_no`',
                           're.genus_reso AS `re.genus_reso`',
                           're.genus_name AS `re.genus_name`',
                           're.species_name AS `re.species_name`',
                           're.taxon_no AS `re.taxon_no`';
            }
            my ($whereref,$occswhereref,$reidswhereref) = $self->getOccurrencesWhereClause();
            push @where, @$whereref;
            push @occ_where, @$occswhereref;
            push @reid_where, @$reidswhereref;
            my @occurrences_columns = $dbt->getTableColumns('occurrences');
            my @reid_columns = $dbt->getTableColumns('reidentifications');
            foreach my $c (@occurrences_columns) {
                if ($q->param("occurrences_".$c) && $c !~ /^abund/) {
                    push @fields,"o.$c AS `o.$c`";
                }
            }
            if ( $q->param('replace_with_reid') ne 'NO' )   {
                foreach my $c (@reid_columns) {
                    # Note we use occurrences_ fields
                    if ($q->param("occurrences_".$c) && $c !~ /^abund/) {
                        push @fields,"re.$c AS `re.$c`";
                    }
                }
            }
            if ($q->param('occurrences_authorizer') eq 'YES') {
                push @fields, 'o.authorizer';
                if ( $q->param('replace_with_reid') ne 'NO' )   {
                    push @fields, 're.authorizer';
                }
            }
            if ($q->param('occurrences_enterer') eq 'YES') {
                push @fields, 'o.enterer';
                if ( $q->param('replace_with_reid') ne 'NO' )   {
                    push @fields, 're.enterer';
                }
            }
            if ($q->param('occurrences_modifier') eq 'YES') {
                push @fields, 'o.modifier';
                if ( $q->param('replace_with_reid') ne 'NO' )   {
                    push @fields, 're.modifier';
                }
            }
        } 

        if ( $q->param('taxon_name') || $q->param('exclude_taxon_name') ) {
            # Don't include $taxon_where in my () above, it needs to stay in scope
            # so it can be used much later in function
            $taxon_where = $self->getTaxonString($q->param('taxon_name'),$q->param('exclude_taxon_name'));
            if ( $taxon_where )	{
                my $occ_sql = $taxon_where;
                my $reid_sql = $taxon_where;
                $occ_sql =~ s/table\./o\./g;
                $reid_sql =~ s/table\./re\./g;
                push @occ_where, $occ_sql;
                push @reid_where, $reid_sql;
            }
        }

        if ( $q->param('pubyr') > 0 ) {
            push @tables, 'refs r';
            if ( $q->param('output_data') =~ /collections/i )	{
                unshift @where, 'r.reference_no=c.reference_no';
            } else	{
                unshift @where, 'r.reference_no=o.reference_no';
            }
        }
    }

    # Handle matching against secondary refs
    if($q->param('research_group') =~ /^(?:divergence|decapod|ETE|5%|1%|PACED|PGAP)$/ || ( $q->param('restrict_to_field') =~ /reference_no/ && $q->param('restrict_to_list') =~ /[0-9]/ ) )	{
        push @left_joins, "LEFT JOIN secondary_refs sr ON sr.collection_no=c.collection_no";
    }

    if ( $q->param('occurrence_count') && $q->param('output_data') =~ /collections/i )	{
        push @fields, 'count(*) num';
    }

    # Handle GROUP BY
    # This is important: don't group by genus_name for the obvious cases, 
    # Do the grouping in PERL, since otherwise we can't get a list of references
    # nor can we filter out old reids and rows that don't pass permissions.
    if ( $q->param('output_data') =~ /occurrence|taxonomic.list/ )    {
        if ( $q->param('replace_with_reid') ne 'NO' )   {
            push @groupby, 'o.occurrence_no,re.reid_no';
        } else {
            push @groupby, 'o.occurrence_no';
        }
    } elsif ($q->param('output_data') eq 'collections' && ($q->param('research_group') || $join_reids )) { # = collections
       push @groupby, 'c.collection_no';
    }


    # filters out things like o.collection_no=c.collection_no
    my @conditions = grep {!/^\s*\w{1,2}\.\w+\s*=\s*\w{1,2}\.\w+\s*$/} @where,@occ_where;
    @conditions = grep {!/o.species_name!='indet.'/} @conditions;
    if (!@conditions) {
        push @form_errors, "No valid search terms were entered.";
    }


    # Assemble the final SQL
    my $sql;
    if ($join_reids) {
        # Reworked PS  07/15/2005
        # Instead of doing a left join on the reids table, we achieve the close to the same effect
        # with a union of the (collections,occurrences left join reids where reid_no IS NULL) UNION (collections,occurrences,reids).
        # but for the first SQL in the union, we use o.taxon_no, while in the second we use re.taxon_no
        # This has the advantage in that it can use indexes in each case, thus is super fast (rather than taking ~5-8s for a full table scan)
        # Just doing a simple left join does the full table scan because an OR is needed (o.taxon_no IN () OR re.taxon_no IN ())
        # and because you can't use indexes for tables that have been LEFT JOINED as well
        # By hitting the occ/reids tables separately, it also has the advantage in that it excludes occurrences that
        # have been reid'd into something that no longer is the taxon name and thus shouldn't show up.
        #
        # In the future: when we update to mysql 4.1, filter for "most recent" REID in a subquery, rather
        # than after the fact in the "exclude++" section of the code
        if ( $q->param('replace_with_reid') ne 'NO' )   {
            my @left_joins1 = ('LEFT JOIN reidentifications re ON re.occurrence_no=o.occurrence_no',@left_joins);

            # This term very important.  sql1 deal with occs with NO reid, sql2 deals with only reids
            # This way WHERE terms can focus on only pruning the occurrences table for sql1 and only
            # pruning on the reids table for sql2 PS 07/15/2005
            my @where1 = (@where,@occ_where,"re.reid_no IS NULL");
            my $sql1 = "SELECT ".join(",",@fields).
                   " FROM (" .join(",",@tables).") ".join (" ",@left_joins1).
                   " WHERE ".join(" AND ",@where1);
            $sql1 .= " GROUP BY ".join(",",@groupby) if (@groupby);
            if ( $q->param('occurrence_count') && $q->param('output_data') =~ /collections/i )	{
               $sql1 .= ' HAVING num>'.$q->param('occurrence_count');
            }

            my @where2 = ("re.occurrence_no=o.occurrence_no AND re.most_recent='YES'",@where,@reid_where);
            my @tables2 = (@tables,'reidentifications re'); 
            my $sql2 = "SELECT ".join(",",@fields).
                   " FROM (" .join(",",@tables2).") ".join (" ",@left_joins).
                   " WHERE ".join(" AND ",@where2);
            $sql2 .= " GROUP BY ".join(",",@groupby) if (@groupby);
            if ( $q->param('occurrence_count') && $q->param('output_data') =~ /collections/i )	{
               $sql2 .= ' HAVING num>'.$q->param('occurrence_count');
            }
            $sql = "($sql1) UNION ($sql2)";
        } else {
            my @where1 = (@where,@occ_where);
            my $sql1 = "SELECT ".join(",",@fields).
                   " FROM (" .join(",",@tables).") ".join (" ",@left_joins).
                   " WHERE ".join(" AND ",@where1);
            $sql1 .= " GROUP BY ".join(",",@groupby) if (@groupby);
            if ( $q->param('occurrence_count') && $q->param('output_data') =~ /collections/i )	{
               $sql1 .= ' HAVING num>'.$q->param('occurrence_count');
            }
            $sql = $sql1;
        }
    } else {
        $sql = "SELECT ".join(",",@fields).
               " FROM (" .join(",",@tables).") ".join (" ",@left_joins).
               " WHERE ".join(" AND ",@where);
        $sql .= " GROUP BY ".join(",",@groupby) if (@groupby);
        if ( $q->param('occurrence_count') && $q->param('output_data') =~ /collections/i )	{
           $sql .= ' HAVING num>'.$q->param('occurrence_count');
        }
    }
    # added this because the occurrences must be ordered by collection no or the CONJUNCT output will split up the collections JA 14.7.05
    if ( $q->param('output_data') =~ /occurrence/)    {
        $sql .= " ORDER BY collection_no";
    }

    if (@form_errors) {
        return ([],[]);
    } 

    ###########################################################################
    #  Set up various lookup tables before we loop through results
    ###########################################################################
    # Changed to use prebuild lookup table PS
    my $time_lookup;
    my @time_fields = ();
    if ($q->param("output_data") !~ /taxonomic_list/) {
        push @time_fields, 'period_name' if ($q->param('collections_period'));
        push @time_fields, 'subepoch_name'  if ($q->param('collections_subepoch'));
        push @time_fields, 'epoch_name'  if ($q->param('collections_epoch'));
        push @time_fields, 'stage_name'  if ($q->param('collections_stage'));
        push @time_fields, 'FR2_bin'  if ($q->param('collections_FR2_bin'));
        # these data are always needed for range computations
        push @time_fields, 'base_age','top_age';
        if ( $q->param("collections_interpolated_base") eq "YES" || $q->param("collections_interpolated_top") eq "YES" ||$q->param("collections_interpolated_mid") eq "YES" )	{
            push @time_fields, 'interpolated_base','interpolated_top';
        }
        if (($q->param("collections_max_interval") eq "YES" || 
             $q->param("collections_min_interval") eq "YES")) {
            push @time_fields, 'interval_name';
        }
    }

	# get the PBDB 10 m.y. bin names for the collections JA 3.3.04
	if ( ($q->param('collections_10_my_bin') && $q->param("output_data") !~ /taxonomic_list/) || $q->param('compendium_ranges') eq 'NO' ) {
		push @time_fields, 'ten_my_bin';
	}
	if (@time_fields) {
		$time_lookup = $self->{t}->lookupIntervals([],\@time_fields);
	}


    # Get a list of acceptable Sepkoski compendium taxa/10 m.y. bin pairs
    my %incompendium = ();
    if ( $q->param('compendium_ranges') eq 'NO' )    {
        if (!open IN,"<./data/compendium.ranges") {
            die "Could not open Sepkoski compendium ranges file<br>";
        }
        while (<IN>) {
            chomp;
            my ($genus,$bin) = split /\t/,$_;
            $incompendium{$genus.$bin}++;
        }
        close IN;
    }


    ###########################################################################
    #  Execute
    ###########################################################################

    my $sth = $dbh->prepare($sql); #|| die $self->dbg("Prepare query failed ($!)<br>");
    $sth->execute();
 
    # See if rows okay by permissions module
    my @dataRows = ( );
    my $limit = 10000000;
#    if ($q->param('limit')) {
#        $limit = $q->param('limit');
#    }
#    if (int($q->param('row_offset'))) {
#        $limit += $q->param('row_offset');
#    }
    my $ofRows = 0;
    $p->getReadRows ( $sth, \@dataRows, $limit, \$ofRows );

    $sth->finish();

    if ( scalar @dataRows == 0 )	{
        errors($q,["No matching data records were found"]);
        return 0;
    }

    ###########################################################################
    #  Tally some data we will need later
    ###########################################################################

    # get as many numbers as possible in case the higher taxon needs
    #  to be guessed 
    my %all_taxa = ();
    foreach my $row (@dataRows) {
        for my $no ( $row->{'o.taxon_no'},$row->{'re.taxon_no'} )	{
            if ( $no > 0 )	{
                $all_taxa{$no} = 1;
            }
        }
    }
    my @taxon_nos = keys %all_taxa;

    # absolutely essential call JA 29.5.13
    if ( @taxon_nos )	{
        fastClassificationLookups($dbt,$q->param('taxon_name'),\@taxon_nos);
    }

    # section moved below the above from above the above because senior
    #  synonyms need to be classified as well JA 13.8.06
    foreach my $row (@dataRows) {
        for my $no ( $row->{'o.taxon_no'},$row->{'re.taxon_no'} )	{
            if ( $no > 0 )	{
                if ( $synonym{$no} > 0 )	{
                    $all_taxa{$synonym{$no}} = 1;
                }
                if ( $parents{$no}{'genus'} > 0 )	{
                    $all_taxa{$parents{$no}{'genus'}} = 1;
                }
                if ( $parents{$no}{'subgenus'} > 0 )	{
                    $all_taxa{$parents{$no}{'subgenus'}} = 1;
                }
            }
        }
    }

    my @taxon_nos = keys %all_taxa;

    # Ecotaph/preservation/parent data
    my %ecotaph;
    my %all_genera;
    my @preservation = $q->param('preservation');
    my $get_preservation = 0;
    if ((@preservation > 0 && @preservation < 3) ||
	$q->param('occurrences_preservation')) {
	$get_preservation = 1;
    }
    
    if (@dataRows && $q->param("output_data") =~ /occurrence|taxonomic.list/ && @ecoFields) { 
        # set the ecotaph values by running up the hierarchy
        # greatly compacted JA 29.5.13
	my %master_class=%{PBDB::TaxaCache::getParents($dbt,\@taxon_nos,'array_full')};
	%ecotaph = %{PBDB::Ecology::getEcology($dbt,\%master_class,\@ecoFields,0,0)};
    }

    # Type specimen numbers, body part, and common name data
    my %authority;
    if (( $q->param("occurrences_first_author") ||
        $q->param("occurrences_second_author") ||
        $q->param("occurrences_other_authors") ||
        $q->param("occurrences_year_named") ||
        $q->param("occurrences_type_specimen") ||
        $q->param("occurrences_type_body_part") ||
        $q->param("occurrences_type_locality") ||
        $q->param("occurrences_form_taxon") ||
        $q->param("occurrences_common_name")) &&
        $q->param('output_data') =~ /occurrence|taxonomic.list/ ) {
        if (%all_taxa) {

        # you need the data for all taxa with the same current spelling as any
        #  taxon in the current data set, i.e., all variant combinations etc.
        # previously done by joining taxa_tree_cache to itself in the call
        #  below, but this is incredibly inefficient and two hits is faster
        #  JA 22.5.08
            my @spelling_nos = ();
            my $sql = "SELECT DISTINCT spelling_no FROM $TAXA_TREE_CACHE WHERE taxon_no IN (".join(',',@taxon_nos).")";
            foreach my $row (@{$dbt->getData($sql)}) {
                push @spelling_nos, $row->{'spelling_no'};
            }

            my $sql = "SELECT t.taxon_no,if(a.ref_is_authority='YES',r.author1init,a.author1init) a1i,if(a.ref_is_authority='YES',r.author1last,a.author1last) a1l,if(a.ref_is_authority='YES',r.author2init,a.author2init) a2i,if(a.ref_is_authority='YES',r.author2last,a.author2last) a2l,if(a.ref_is_authority='YES',r.otherauthors,a.otherauthors) other_authors,if(a.ref_is_authority='YES',r.pubyr,a.pubyr) year_named,a.type_specimen,a.type_body_part,a.type_locality,a.form_taxon type_form_taxon,a.common_name FROM $TAXA_TREE_CACHE t, authorities a, refs r WHERE t.spelling_no IN (".join(',',@spelling_nos).") AND t.taxon_no=a.taxon_no AND a.reference_no=r.reference_no";

            foreach my $row (@{$dbt->getData($sql)}) {
                my $no = $row->{'taxon_no'};
                $authority{$no}{$_} = $row->{$_} foreach ('taxon_no','other_authors','year_named','type_specimen','type_body_part','type_locality','type_form_taxon','common_name');
                if ( $row->{'a1i'} )	{
                    $authority{$no}{'first_author'} = $row->{'a1i'} . " " .$row->{'a1l'};
                } else	{
                    $authority{$no}{'first_author'} = $row->{'a1l'};
                }
                if ( $row->{'a2i'} )	{
                    $authority{$no}{'second_author'} = $row->{'a2i'} . " " .$row->{'a2l'};
                } else	{
                    $authority{$no}{'second_author'} = $row->{'a2l'};
                }
            }
            # if the user does not want species names, the occurrence species
            #  name is irrelevant and the occurrence should inherit values for
            #  the genus name
            # rewritten JA 29.5.13
            if ( $q->param('taxonomic_level') !~ /species/ )	{
                my @nos = keys %authority;
                for my $no ( @nos )	{
                    if ( $rank{$no} =~ /species/ )	{
                        $authority{$no} = $authority{$parents{$no}{'genus'}};
                    }
                }
            }
        }
    }

    # Populate calculated time fields, which are needed below
    if (@time_fields) {
        my %COLL = ();
        foreach my $row ( @dataRows ){
            if ($COLL{$row->{'collection_no'}}) {
                # This is merely a timesaving measure, reuse old collections values if we've already come across this collection
                my $orow = $COLL{$row->{'collection_no'}};
                for my $field ( '10_my_bin','FR2_bin','stage','subepoch','epoch','period','max_interval','min_interval','direct_ma','direct_ma_error','direct_ma_method','max_ma','max_ma_error','max_ma_error','min_ma','min_ma_error','min_ma_method' ,'interval_base','interval_top','interval_midpoint','interpolated_base','interpolated_top','interpolated_mid','ma_max','ma_min','ma_mid' )	{
                	$row->{'c.'.$field}  = $orow->{'c.'.$field};
                }
                next;
            }
            # Populate the generated time fields;
            my $base_lookup = $time_lookup->{$row->{'c.max_interval_no'}};
            my $top_lookup = ($row->{'c.min_interval_no'}) ? $time_lookup->{$row->{'c.min_interval_no'}} : $base_lookup;
            my $max_lookup = $base_lookup;
            my $min_lookup = $top_lookup;
            my $ma_lookup = $time_lookup->{$row->{'c.ma_interval_no'}};
            # use the absolute date-based interval assignment only if it is completely
	    #  consistent with the qualitative assignment JA 25.3.11
            if ( $ma_lookup->{'base_age'} <= $max_lookup->{'base_age'} && $ma_lookup->{'top_age'} >= $min_lookup->{'top_age'} )	{
                $max_lookup = ($row->{'c.ma_interval_no'}) ? $time_lookup->{$row->{'c.ma_interval_no'}} : $max_lookup;
                $min_lookup = ($row->{'c.ma_interval_no'}) ? $time_lookup->{$row->{'c.ma_interval_no'}} : $min_lookup;
            }

            if ($max_lookup->{'ten_my_bin'} && $max_lookup->{'ten_my_bin'} eq $min_lookup->{'ten_my_bin'} && ($q->param('late_pleistocene') !~ /no/i || ($row->{'c.max_interval_no'} != 33 && $row->{'c.max_interval_no'} != 922))) {
                $row->{'c.10_my_bin'} = $max_lookup->{'ten_my_bin'};
            }
            if ($max_lookup->{'FR2_bin'} && $max_lookup->{'FR2_bin'} eq $min_lookup->{'FR2_bin'} && ($q->param('late_pleistocene') !~ /no/i || ($row->{'c.max_interval_no'} != 33 && $row->{'c.max_interval_no'} != 922))) {
                $row->{'c.FR2_bin'} = $max_lookup->{'FR2_bin'};
            }
            
            if ($max_lookup->{'period_name'} && $max_lookup->{'period_name'} eq $min_lookup->{'period_name'}) {
                $row->{'c.period'} = $max_lookup->{'period_name'};
            }
            if ($max_lookup->{'epoch_name'} && $max_lookup->{'epoch_name'} eq $min_lookup->{'epoch_name'}) {
                $row->{'c.epoch'} = $max_lookup->{'epoch_name'};
            }
            if ($max_lookup->{'subepoch_name'} && $max_lookup->{'subepoch_name'} eq $min_lookup->{'subepoch_name'}) {
                $row->{'c.subepoch'} = $max_lookup->{'subepoch_name'};
            }
            if ($max_lookup->{'stage_name'} && $max_lookup->{'stage_name'} eq $min_lookup->{'stage_name'}) {
                $row->{'c.stage'} = $max_lookup->{'stage_name'};
            }
            $row->{'c.max_interval'} = $time_lookup->{$row->{'c.max_interval_no'}}{'interval_name'};
            $row->{'c.min_interval'} = $time_lookup->{$row->{'c.min_interval_no'}}{'interval_name'};
            if ( $row->{'c.direct_ma'} > 0 && $row->{'c.direct_ma_unit'} =~ /ybp/i )	{
                    $row->{'c.direct_ma'} /= 1000000;
                    $row->{'c.direct_ma_error'} /= 1000000;
            } elsif ( $row->{'c.direct_ma'} > 0 && $row->{'c.direct_ma_unit'} =~ /ka/i )	{
                    $row->{'c.direct_ma'} /= 1000;
                    $row->{'c.direct_ma_error'} /= 1000;
            }
            $row->{'c.interval_base'} = $base_lookup->{'base_age'};
            $row->{'c.interval_top'} = $top_lookup->{'top_age'};
            $row->{'c.interval_midpoint'} = ($base_lookup->{'base_age'} + $top_lookup->{'top_age'})/2;
            $row->{'c.interpolated_base'} = $max_lookup->{'interpolated_base'};
            $row->{'c.interpolated_top'} = $min_lookup->{'interpolated_top'};
            if ( $row->{'c.interpolated_base'} == 0 )	{
                $row->{'c.interpolated_base'} = $row->{'c.ma_max'};
                $row->{'c.interpolated_top'} = $row->{'c.ma_min'};
            }
            $row->{'c.interpolated_mid'} = ($row->{'c.interpolated_base'} + $row->{'c.interpolated_top'})/2;
            if ( $row->{'c.max_ma'} > 0 && $row->{'c.max_ma_unit'} =~ /ybp/i )	{
                    $row->{'c.max_ma'} /= 1000000;
                    $row->{'c.max_ma_error'} /= 1000000;
            } elsif ( $row->{'c.max_ma'} > 0 && $row->{'c.max_ma_unit'} =~ /ka/i )	{
                    $row->{'c.max_ma'} /= 1000;
                    $row->{'c.max_ma_error'} /= 1000;
            }
            if ( $row->{'c.min_ma'} > 0 && $row->{'c.min_ma_unit'} =~ /ybp/i )	{
                    $row->{'c.min_ma'} /= 1000000;
                    $row->{'c.min_ma_error'} /= 1000000;
            } elsif ( $row->{'c.min_ma'} > 0 && $row->{'c.min_ma_unit'} =~ /ka/i )	{
                    $row->{'c.min_ma'} /= 1000;
                    $row->{'c.min_ma_error'} /= 1000;
            }
            # use geochronology if available for composite max/min age
            # whoops, only use dates consistent with the time scale
            #  JA 5.1.12
            if ( $row->{'c.direct_ma'} && $row->{'c.direct_ma'} <= $base_lookup->{'base_age'} && $row->{'c.direct_ma'} >= $top_lookup->{'top_age'} )	{
                $row->{'c.ma_max'} = $row->{'c.direct_ma'};
                $row->{'c.ma_min'} = $row->{'c.direct_ma'};
                $row->{'c.ma_mid'} = ($row->{'c.ma_max'} + $row->{'c.ma_min'})/2;
            } elsif ( $row->{'c.max_ma'} > 0 && $row->{'c.min_ma'} > 0 && $row->{'c.max_ma'} <= $base_lookup->{'base_age'} && $row->{'c.min_ma'} >= $top_lookup->{'top_age'} )	{
                $row->{'c.ma_max'} = $row->{'c.max_ma'};
                $row->{'c.ma_min'} = $row->{'c.min_ma'};
                $row->{'c.ma_mid'} = ($row->{'c.ma_max'} + $row->{'c.ma_min'})/2;
            } elsif ( $row->{'c.max_ma'} > 0 && $row->{'c.min_ma'} <= 0 && $row->{'c.max_ma'} <= $base_lookup->{'base_age'} && $row->{'c.min_ma'} >= $top_lookup->{'top_age'} )	{
                $row->{'c.ma_max'} = $row->{'c.max_ma'};
                $row->{'c.ma_min'} = 0;
                $row->{'c.ma_mid'} = ($row->{'c.ma_max'} + $row->{'c.ma_min'})/2;
            # otherwise strictly base ages on interval names
            } else	{
                $row->{'c.ma_max'} = $base_lookup->{'base_age'};
                $row->{'c.ma_min'} = $top_lookup->{'top_age'};
                $row->{'c.ma_mid'} = ($base_lookup->{'base_age'} + $top_lookup->{'top_age'})/2;
            }
            $COLL{$row->{'collection_no'}} = $row; 
        }
    }

    ###########################################################################
    #  First handle occurrence level filters
    ###########################################################################

    my %occs_by_taxa;
    if ($q->param('output_data') =~ /occurrence|taxonomic.list/) {
        # Do integer compares is quite a bit faster than q-> calls, so set that up here
        my $replace_with_ss = ($q->param("replace_with_ss") ne 'NO') ? 1 : 0;
        my $replace_with_reid = ($q->param("replace_with_reid") ne 'NO') ? 1 : 0;
        my $split_subgenera = ($q->param('split_subgenera') eq 'YES') ? 1 : 0;
        my $compendium_only = ($q->param('compendium_ranges') eq 'NO') ? 1 : 0;
        my ($get_regular,$get_ichno,$get_form) = (0,0,0);
        if ($get_preservation) {
            my @preservations = $q->param('preservation');
            foreach my $p (@preservations) {
                $get_regular = 1 if ($p eq 'regular taxon'); 
                $get_ichno   = 1 if ($p eq 'ichnofossil'); 
                $get_form    = 1 if ($p eq 'form taxon');
            }
            if (! @preservations)	{
                $get_regular = 1;
                $get_ichno   = 1;
                $get_form    = 1;
            }
        }


        my @temp = ();
        foreach my $row ( @dataRows ) {
            
            # swap the reIDs into the occurrences (pretty important!)
            # don't do this unless the user requested it (the default)
            #  JA 16.4.06
            if ($row->{'re.reid_no'} > 0 && $replace_with_reid) {
                foreach my $field (@reidFieldNames,@reidTaxonFieldNames) {
                    $row->{'or.'.$field}=$row->{'o.'.$field};
                    $row->{'o.'.$field}=$row->{'re.'.$field};
                }
            }

            # Replace with senior_synonym_no PS 11/1/2005
            # the "original name" is actually a reID whenever a reID exists
            # even possibly okay names are now checked because of the chaotic
            #  mismatches between occurrence and authority data created by
            #  fuzzy matching of subgenus names JA 20.12.08
            if ($replace_with_ss && $synonym{$row->{'o.taxon_no'}})	{
                my $no = $synonym{$row->{'o.taxon_no'}};
                my ($genus,$subgenus,$species,$subspecies) = PBDB::Taxon::splitTaxon($name{$synonym{$row->{'o.taxon_no'}}});
                # genus or subgenus could be wrong if the species' current
                #  spelling disagrees with the rank of its parent, e.g., it's
                #  correctly spelled Yus yus but Yus is a subgenus of Xus
                # case 1: the current genus should be a subgenus
                if ( $genus eq $subgenus{$no} )	{
                    $subgenus = $genus;
                    $genus = $name{$parents{$no}{'genus'}};
                }
                # case 2: the current subgenus should be a genus
                elsif ( $subgenus && $subgenus eq $name{$parents{$no}{'genus'}} )	{
                    $genus = $subgenus;
                    $subgenus = "";
                }
                # free pass for unclassified species within classified genera
                if ( ! $species && $row->{'o.species_name'} =~ /^[a-z]*$/ && $rank{$synonym{$row->{'o.taxon_no'}}} =~ /genus/ && $nomen{$row->{'o.taxon_no'}} == 0 )	{
                    $species = $row->{'o.species_name'};
                # same for subgenera (certainly don't do this for classified
                #  species, whose correct subgenera are known)
                    if ( ! $subgenus && $row->{'o.subgenus_name'} =~ /^[A-Z][a-z]*$/ )	{
                        $subgenus = $row->{'o.subgenus_name'};
                    }
                }

                my $rowspecies = $row->{'o.species_name'};
                if ( $rowspecies !~ /^[a-z]*$/ )	{
                    $rowspecies = "";
                }
                if ( $q->param('indet') ne 'YES' && ( $row->{'o.genus_reso'} eq "informal" || ( ! $species && $rank{$synonym{$row->{'o.taxon_no'}}} eq "" ) || ( $rank{$synonym{$row->{'o.taxon_no'}}} ne "" && $rank{$synonym{$row->{'o.taxon_no'}}} !~ /genus|species/ ) ) )	{
                    next;
		}
                if ( $q->param('sp') eq 'NO' && ( ! $species || $row->{'o.species_reso'} eq "informal" ) )	{
                    next;
                }
                if ( $genus ne $row->{'o.genus_name'} || $subgenus ne $row->{'o.subgenus_name'} || $species ne $rowspecies || ( $species !~ /indet\./ && $rank{$synonym{$row->{'o.taxon_no'}}} ne "" && $rank{$synonym{$row->{'o.taxon_no'}}} !~ /genus|species/ ) )	{
                    foreach my $field ('genus_name','subgenus_name','species_name','subspecies_name','genus_reso','subgenus_reso','species_reso','taxon_no')	{
                        if ( ! $row->{'or.'.$field} )	{
                            $row->{'or.'.$field} = $row->{'o.'.$field};
                        }
                    }
                    $row->{'o.genus_name'} = $genus;
                    if ( $species )	{
                        $row->{'o.subgenus_name'} = $subgenus;
                        $row->{'o.species_name'} = $species;
                        $row->{'o.subspecies_name'} = $subspecies;
                    } elsif ( $rank{$synonym{$row->{'o.taxon_no'}}} =~ /genus|species/ )	{
                        $row->{'o.subgenus_name'} = $subgenus;
                        $row->{'o.species_name'} = "sp.";
                    } else	{
                        $row->{'o.subgenus_name'} = "";
                        $row->{'o.species_name'} = "indet.";
                    }
                    if ( $spelling{$row->{'o.taxon_no'}} > 0 && $spelling{$row->{'o.taxon_no'}} != $spelling{$row->{'or.taxon_no'}} )	{
                        $row->{'o.genus_reso'} = "";
                        $row->{'o.subgenus_reso'} = "";
                        $row->{'o.species_reso'} = "";
                    }
                    $row->{'o.taxon_no'} = $no;
                }
            }

            # get rid of occurrences of genera either (1) not in the
            #  Compendium or (2) falling outside the official Compendium
            #  age range JA 27.8.04
            if ( $compendium_only) {
                if ( ! $incompendium{$row->{'o.genus_name'}.$row->{'c.10_my_bin'}} )    {
                    next; # Skip, no need to process any more
                }
            }

            if ($get_preservation) {
                my $preservation = $row->{preservation};
                if ($preservation eq 'trace') {
                    next unless ($get_ichno);
                } else {
                    next unless ($get_regular);
                }
                if ($row->{form_taxon} eq 'yes') {
                    next unless ($get_form);
                }
            }
            # delete abundances (not occurrences) if the collection excludes
            #  some genera or some groups JA 27.9.06
            # some groups was too strict, dropped it JA 12.2.07
            if ( $q->param('incomplete_abundances') eq "NO" && $row->{'c.collection_coverage'} =~ /some genera/ )	{
                # toss it out completely if abundances are strictly required
                #  JA 8.2.07
                if ( $q->param('abundance_required') =~ /abundances|specimens/ )	{
                    next;
                }
                $row->{'o.abund_value'} = "";
                $row->{'o.abund_unit'} = "";
            }

            # If we haven't skipped this row yet because of a "next", we use it 
            push @temp, $row;

            # "extant" calculations must be done here to allow correct
            #   lumping below
            # entirely rewritten JA 29.5.13

            # in most cases the fastClassificationLookups value is fine
            $row->{'genus_extant'} = $extant{$parents{$row->{'o.taxon_no'}}{'genus'}};
            if ( $rank{$synonym{$row->{'o.taxon_no'}}} =~ /species/ )	{
                $row->{'species_extant'} = $extant{$synonym{$row->{'o.taxon_no'}}};
            }

            # raise subgenera to genus level JA 18.8.04
            # genus_extant is based on the subgenus if possible 30.5.13 JA
            # note that the literal content of the subgenus field isn't used
            #  because the name might be bogus
            if ( $split_subgenera && $parents{$row->{'o.taxon_no'}}{'subgenus'} ) {
                $row->{'o.genus_name'} = $subgenus{$parents{$row->{'o.taxon_no'}}{'subgenus'}};
                if ( $extant{$parents{$row->{'o.taxon_no'}}{'subgenus'}} ne $extant{$parents{$row->{'o.taxon_no'}}{'genus'}} )	{
                    $row->{'genus_extant'} = $extant{$parents{$row->{'o.taxon_no'}}{'subgenus'}};
                }
            }

            # get parent extant values if extant values are wanted at all
            #   31.3.11
            # greatly compacted JA 29.5.13
            if ( $q->param('occurrences_extant') && $row->{'o.taxon_no'} > 0 )	{
                $row->{'o.class_extant'} = $extant{$parents{$row->{'o.taxon_no'}}{'class'}};
                $row->{'o.order_extant'} = $extant{$parents{$row->{'o.taxon_no'}}{'order'}};
                $row->{'o.family_extant'} = $extant{$parents{$row->{'o.taxon_no'}}{'family'}};
                $row->{'o.parent_extant'} = $extant{$parents{$row->{'o.taxon_no'}}{'immediate'}};
            }

        }
        @dataRows = @temp;
        
        ###########################################################################
        #  Some more occurrence level filters where you need to first aggregate data 
        #  at the collection level
        ###########################################################################
        my $occurrence_count = int($q->param('occurrence_count'));
        my $abundance_count  = int($q->param('abundance_count'));
        if ($occurrence_count || $abundance_count) {
            my %COLL = ();
            my %ABUND = ();
            foreach my $row (@dataRows) {
                $COLL{$row->{'collection_no'}}++;
                if ( $row->{'o.abund_unit'} =~ /^(?:specimens|individuals)$/ && $row->{'o.abund_value'} > 0 ) {
                    $ABUND{$row->{'collection_no'}} += $row->{'o.abund_value'};
                }
            }
            my @temp = ();
            my $occ_more_than = ($q->param('occurrence_count_qualifier') =~ /more/i) ? 1 : 0;
            my $abund_more_than = ($q->param('abundance_count_qualifier') =~ /more/i) ? 1 : 0;
            foreach my $row (@dataRows) {
                if ($occurrence_count) {
                    if ($occ_more_than) {
                        next if ($COLL{$row->{'collection_no'}} > $occurrence_count);
                    } else {
                        next if ($COLL{$row->{'collection_no'}} != $occurrence_count);
                    }
                }
                # also assume that if the user is worrying about specimen or
                #  individual counts, they only want occurrences that do have
                #  specimen/individual count data JA 31.8.06
                if ($abundance_count) {
                    if ($abund_more_than) {
                        next if ($ABUND{$row->{'collection_no'}} > $abundance_count || $row->{'o.abund_value'} < 1 || $row->{'o.abund_unit'} !~ /^(?:specimens|individuals)$/);
                    } else {
                        next if ($ABUND{$row->{'collection_no'}} < $abundance_count || $row->{'o.abund_value'} < 1 || $row->{'o.abund_unit'} !~ /^(?:specimens|individuals)$/);
                    }
                }
                push @temp,$row;
            }
            @dataRows = @temp;
        }

    }

    # quick pruning of extinct taxa JA 24.7.09
    # or extant taxa JA 24.3.10
    if ( $q->param('extant_extinct') =~ /extant|extinct/i )	{
        my @temp;
        if ( $q->param('extant_extinct') =~ /extant/i )	{
          foreach my $row ( @dataRows ) {
            if ( $row->{'genus_extant'} =~ /y/i || $row->{'species_extant'} =~ /y/i )	{
              push @temp , $row;
            }
          }
        }
        # WARNING: assumes extinct until proven extant
        else	{
          foreach my $row ( @dataRows ) {
            if ( $row->{'genus_extant'} !~ /y/i && $row->{'species_extant'} !~ /y/i )	{
              push @temp , $row;
            }
          }
        }
        @dataRows = @temp;
        @temp = ();
    }

    ###########################################################################
    #  Now handle lumping of collections
    ###########################################################################

    my %lumpcollno;
    my %lumpgenusref;
    my %lumpoccref;
    my @lumpedDataRows = ();
    my @allDataRows = @dataRows;
    foreach my $row ( @dataRows ) {
        my $lump = 0;
        if (($q->param('output_data') =~ /taxonomic_list/ || $q->param('lump_genera') eq 'YES')) {
            my $genus_string;
            if ($q->param('lump_genera') eq 'YES') {
                $genus_string = $row->{'collection_no'};
            }
          
            if ($q->param('taxonomic_level') =~ /species/i) {
                $genus_string .= $row->{'o.genus_name'}.$row->{'o.species_name'};
            } else {
                $genus_string .= $row->{'o.genus_name'};
            }
            if ($lumpgenusref{$genus_string}) {
                $lump++;
                if ( $row->{'genus_extant'} =~ /y/i )	{
                    $lumpgenusref{$genus_string}->{'genus_extant'} = "yes";
                }
                if ($q->param('taxonomic_level') =~ /species/i && $row->{'species_extant'} =~ /y/i )	{
                    $lumpgenusref{$genus_string}->{'species_extant'} = "yes";
                }
                if ( $row->{'o.abund_unit'} =~ /(^specimens$)|(^individuals$)/ && $row->{'o.abund_value'} > 0 )	{
            # don't need to do this if you're lumping by other things, because
            #  that lumps the genus occurrences anyway
                  unless ( $q->param('lump_by_location') eq 'YES' || $q->param('lump_by_interval') eq 'YES' || $q->param('lump_by_strat_unit') =~ /(group)|(formation)|(member)/i || $q->param('lump_by_ref') eq 'YES' )    {
                    $lumpgenusref{$genus_string}->{'o.abund_value'} += $row->{'o.abund_value'};
                    $lumpgenusref{$genus_string}->{'o.abund_unit'} = $row->{'o.abund_unit'};
                    $row->{'o.abund_value'} = "";
                    $row->{'o.abund_unit'} = "";
                  }
                }
            } else {
            	$lumpgenusref{$genus_string} = $row;
            }
        }
        # lump bed/group of beds scale collections with the exact same
        #  formation/member and geographic coordinate JA 21.8.04
        if ( $q->param('lump_by_location') || $q->param('lump_by_interval') eq 'YES' || $q->param('lump_by_strat_unit') =~ /(group)|(formation)|(member)/i || $q->param('lump_by_ref') eq 'YES' )    {

            my $lump_string;

            if ( $q->param('lump_by_location') =~ /coordinate/ )    {
                $lump_string .= $row->{'c.latdeg'}."|".$row->{'c.latmin'}."|".$row->{'c.latsec'}."|".$row->{'c.latdec'}."|".$row->{'c.latdir'}."|".$row->{'c.lngdeg'}."|".$row->{'c.lngmin'}."|".$row->{'c.lngsec'}."|".$row->{'c.lngdec'}."|".$row->{'c.lngdir'};
            } elsif ( $q->param('lump_by_location') =~ /county/ )    {
            # don't lump by county if there's no state, that would be nonsense
                if ( $row->{'c.state'} && $row->{'c.county'} )	{
                    $lump_string .= $row->{'c.state'}."|".$row->{'c.county'};
            # whoops, splitting by collection_no would defeat lumping by
            #  reference JA 26.8.11
                } elsif ( $q->param('lump_by_ref') ne 'YES' )    {
                    $lump_string .= $row->{'collection_no'};
                }
            } elsif ( $q->param('lump_by_location') =~ /state/ )    {
                if ( $row->{'c.state'} )	{
                    $lump_string .= $row->{'c.state'};
            # same bug fix here, see above
                } elsif ( $q->param('lump_by_ref') ne 'YES' )    {
                    $lump_string .= $row->{'collection_no'};
                }
            }
            if ( $q->param('lump_by_interval') eq 'YES' )    {
            # the user has to ask for this field specifically or the lumping
            #  will always be by interval no
                if ( ! $q->param('collections_max_ma') )	{
                    $lump_string .= $row->{'c.max_interval_no'}."|".$row->{'c.min_interval_no'};
                } else	{
                    $lump_string .= $row->{'c.max_ma'}."|".$row->{'c.min_ma'};
                }
            }
            if ( $q->param('lump_by_strat_unit') eq 'group' )    {
                if ( $row->{'c.geological_group'} )	{
                    $lump_string .= $row->{'c.geological_group'};
            # if there's no group, at least you can lump by formation
                } elsif ( $row->{'c.formation'} )	{
                    $lump_string .= $row->{'c.formation'};
            # you don't want to lump by member if there's no formation,
            #  because that's probably a data entry error
            # same bug fix here, see above
                } elsif ( $q->param('lump_by_ref') ne 'YES' )    {
                    $lump_string .= $row->{'collection_no'};
                }
            }
            elsif ( $q->param('lump_by_strat_unit') eq 'formation' )    {
            # we could also add in the group name, but often the formation
            #  appears both with and without the group, so that would split
            #  collections actually from the same formation
                if ( $row->{'c.formation'} )	{
                    $lump_string .= $row->{'c.formation'};
            # grouping by group is better than nothing JA 3.4.11
                } elsif ( $row->{'c.geological_group'} )	{
            # you don't want to lump by member if there's no formation or group,
            #  because that's probably a data entry error
            # same bug fix here, see above
                } elsif ( $q->param('lump_by_ref') ne 'YES' )    {
                    $lump_string .= $row->{'collection_no'};
                }
            }
            elsif ( $q->param('lump_by_strat_unit') eq 'member' )    {
                if ( $row->{'c.formation'} && $row->{'c.member'} )	{
                    $lump_string .= $row->{'c.formation'}.$row->{'c.member'};
            # whoops, formation is better than nothing if the member is missing
            # even if the formation has named members, you still don't want to
            #  keep the "member unknown" collections separate from each other
            # should have fixed this years ago JA 3.4.11
                } elsif ( $row->{'c.formation'} )	{
                    $lump_string .= $row->{'c.formation'};
            # ditto group-only collections
                } elsif ( $row->{'c.geological_group'} )	{
                    $lump_string .= $row->{'c.geological_group'};
            # same bug fix here, see above
                } elsif ( $q->param('lump_by_ref') ne 'YES' )    {
                    $lump_string .= $row->{'collection_no'};
                }
            }
            if ( $q->param('lump_by_ref') eq 'YES' )    {
                $lump_string .= $row->{'c.reference_no'};
            }

            my $genus_string;

            if ($q->param('taxonomic_level') =~ /species/i) {
                $genus_string = $row->{'o.genus_name'}.$row->{'o.species_name'};
            } else {
                $genus_string = $row->{'o.genus_name'};
            }

            if ( $lumpcollno{$lump_string} )    {
                # Change  the collection_no to be the same collection_no as the first
                # collection_no encountered that has the same $lump_string, so that 
                # Curve.pm will lump them together when doing a calculation
                $row->{'collection_no'} = $lumpcollno{$lump_string};
                if ( $lumpoccref{$row->{'collection_no'}.$genus_string} )    {
                    $lump++;
                # if you lump occurrences with abundances, the abundances have
                #  to be added together JA 1.9.06
                    if ( $row->{'o.abund_unit'} =~ /(^specimens$)|(^individuals$)/ && $row->{'o.abund_value'} > 0 )	{
                        $lumpoccref{$row->{'collection_no'}.$genus_string}->{'o.abund_value'} += $row->{'o.abund_value'};
                        $lumpoccref{$row->{'collection_no'}.$genus_string}->{'o.abund_unit'} = $row->{'o.abund_unit'};
                    }
                }
            } else    {
                $lumpcollno{$lump_string} = $row->{'collection_no'};
            }
            if ( ! $lumpoccref{$row->{'collection_no'}.$genus_string} )	{
            	$lumpoccref{$row->{'collection_no'}.$genus_string} = $row;
            }
        }
        if ( $lump == 0) {
            push @lumpedDataRows, $row;
        }
    }
    
    @dataRows = @lumpedDataRows;
    my $dataRowsSize = scalar(@dataRows);

    # This is a bit nasty doing it here, but since we do lumping in PERL code, we have to do this after the
    # fact and can't do it after the fact. Will have to amend table structure or radically alter queries
    # so we can do more in SQL to get around this I think PS
    if (int($q->param('row_offset'))) {
        splice(@dataRows,0,int($q->param('row_offset')));
    }
    if (int($q->param('limit'))) {
        splice(@dataRows,int($q->param('limit')));
    }


    # Sort by
    if ($q->param('output_data') =~ /^(?:taxonomic_list)$/) {
        @dataRows = sort { $a->{'o.genus_name'} cmp $b->{'o.genus_name'} ||
                           $a->{'o.species_name'} cmp $b->{'o.species_name'}} @dataRows;
    }

    # main pass through the results set
    my $acceptedCount = 0;
    foreach my $row ( @dataRows )	{

        if ($q->param('output_data') =~ /occurrence|taxonomic.list/) {
            # Setup up family/name/class fields
            # greatly simplified JA 29.5.13
            if (($q->param("occurrences_class_name") eq "YES" || 
                $q->param("occurrences_order_name") eq "YES" ||
                $q->param("occurrences_family_name") eq "YES" ||
                $q->param("occurrences_parent_name") eq "YES") &&
                $row->{'o.taxon_no'} > 0 && $parents{$row->{'o.taxon_no'}}) {
                    $row->{'o.parent_name'} = $name{$parents{$row->{'o.taxon_no'}}{'immediate'}};
                    $row->{'o.parent_rank'} = $rank{$parents{$row->{'o.taxon_no'}}{'immediate'}};
                    $row->{'o.class_name'} = $name{$parents{$row->{'o.taxon_no'}}{'class'}};
                    $row->{'o.order_name'} = $name{$parents{$row->{'o.taxon_no'}}{'order'}};
                    $row->{'o.family_name'} = $name{$parents{$row->{'o.taxon_no'}}{'family'}};
            }

            if ($q->param('occurrences_first_author') || $q->param('occurrences_second_author') || $q->param('occurrences_other_authors') || $q->param('occurrences_year_named') || $q->param('occurrences_type_specimen') || $q->param('occurrences_type_body_part') || $q->param('occurrences_type_locality') || $q->param('occurrences_form_taxon') || $q->param('occurrences_common_name')) {
            # type info must apply to the original name if there is one,
            #  or else the data can't be recovered for invalid names JA 11.12.08
            # if o.taxon_no and re.taxon_no are identical there's a reID of some kind, so
            #  or.taxon_no is simply wrong and it should be ignored
                my $taxon_no = $row->{'o.taxon_no'};
                if ($row->{'or.taxon_no'} > 0 && $row->{'o.taxon_no'} != $row->{'re.taxon_no'}) {
                    $taxon_no = $row->{'or.taxon_no'};
                }
            # get these data only if (1) the record is of a species and the
            #  user wants species names, or (2) the user does not want species
            #  names JA 27.1.08 (screwed this up on a first pass 6.11.07)
            # this check is a little loose because it will prevent inheritance
            #  for some informal names, but that's no tragedy
                if ( ( $rank{$taxon_no} eq "species" || $row->{'o.species_name'} =~ /indet\.|sp\.|spp\.|[^a-z]/ ) || $q->param('taxonomic_level') !~ /species/ )	{
                    $row->{$_} = $authority{$taxon_no}{$_} foreach ('first_author','second_author','other_authors','year_named','type_specimen','type_body_part','type_locality','type_form_taxon');
                }
            # common names are never a problem
                $row->{'common_name'} = $authority{$taxon_no}{'common_name'};
            }

            # Set up the ecology fields
            foreach (@ecoFields) {
                if ($ecotaph{$row->{'or.taxon_no'}}{$_} !~ /^\s*$/) {
                    $row->{$_} = $ecotaph{$row->{'or.taxon_no'}}{$_};
                } elsif ($ecotaph{$row->{'o.taxon_no'}}{$_} !~ /^\s*$/) {
                    $row->{$_} = $ecotaph{$row->{'o.taxon_no'}}{$_};
                } else {
                    $row->{$_} = '';
                }
            }

        }

        # Set up collections fields
        if ($q->param("output_data") =~ /collections|occurrence/) {
            # Get coordinates into the correct format (decimal or deg/min/sec/dir), performing
            # conversions as necessary
            if ($q->param('collections_coords') eq "YES") {
                if ($q->param('collections_coords_format') eq 'DMS') {
                    if (!($row->{'c.lngmin'} =~ /\d+/)) {
                        if ($row->{'c.lngdec'} =~ /\d+/) {
                            my $min = 60*(".".$row->{'c.lngdec'});
                            $row->{'c.lngmin'} = int($min);
                            $row->{'c.lngsec'} = int(($min-int($min))*60);
                        }    
                    }
                    
                    if (!($row->{'c.latmin'} =~ /\d+/)) {
                        if ($row->{'c.latdec'} =~ /\d+/) {
                            my $min = 60*(".".$row->{'c.latdec'});
                            $row->{'c.latmin'} = int($min);
                            $row->{'c.latsec'} = int(($min-int($min))*60);
                        }    
                    }
                } else {
                    if ($row->{'c.latmin'} =~ /\d+/) {
                        $row->{'c.latdec'} = sprintf("%.6f",$row->{'c.latdeg'} + $row->{'c.latmin'}/60 + $row->{'c.latsec'}/3600);
                    } else {
                        if ($row->{'c.latdec'} =~ /\d+/) {
                            $row->{'c.latdec'} = sprintf("%s",$row->{'c.latdeg'}.".".int($row->{'c.latdec'}));
                        } else {
                            $row->{'c.latdec'} = $row->{'c.latdeg'};
                        }
                    }    
                    $row->{'c.latdec'} *= -1 if ($row->{'c.latdir'} eq "South");
                    
                    if ($row->{'c.lngmin'} =~ /\d+/) {
                        $row->{'c.lngdec'} = sprintf("%.6f",$row->{'c.lngdeg'} + $row->{'c.lngmin'}/60 + $row->{'c.lngsec'}/3600);
                    } else {
                        if ($row->{'c.lngdec'} =~ /\d+/) {
                            $row->{'c.lngdec'} = sprintf("%s",$row->{'c.lngdeg'}.".".int($row->{'c.lngdec'}));
                        } else {
                            $row->{'c.lngdec'} = $row->{'c.lngdeg'};
                        }
                    }    
                    $row->{'c.lngdec'} *= -1 if ($row->{'c.lngdir'} eq "West");
                }
            }
            if ($q->param('collections_paleocoords') eq "YES") {
                if ($q->param('collections_paleocoords_format') eq 'DMS') {
                    if ($row->{'c.paleolat'} =~ /\d+/) {
                        $row->{'c.paleolatdir'}  = ($row->{'c.paleolat'} >= 0) ? "North" : "South";
                        my $abs_lat = ($row->{'c.paleolat'} < 0) ? -1*$row->{'c.paleolat'} : $row->{'c.paleolat'};
                        my $deg = int($abs_lat);
                        my $min = 60*($abs_lat-$deg);
                        $row->{'c.paleolatdeg'} = $deg;
                        $row->{'c.paleolatmin'} = int($min);
                        $row->{'c.paleolatsec'} = int(($min-int($min))*60);
                    }    
                    if ($row->{'c.paleolng'} =~ /\d+/) {
                        $row->{'c.paleolngdir'}  = ($row->{'c.paleolng'} >= 0) ? "East" : "West";
                        my $abs_lat = ($row->{'c.paleolng'} < 0) ? -1*$row->{'c.paleolng'} : $row->{'c.paleolng'};
                        my $deg = int($abs_lat);
                        my $min = 60*($abs_lat-$deg);
                        $row->{'c.paleolngdeg'} = $deg;
                        $row->{'c.paleolngmin'} = int($min);
                        $row->{'c.paleolngsec'} = int(($min-int($min))*60);
                    }    
                } else {
                    $row->{'c.paleolatdec'} = $row->{'c.paleolat'};
                    $row->{'c.paleolngdec'} = $row->{'c.paleolng'};
                }
            }
	    
	    if ($q->param('collections_altitude') eq 'YES' && defined $row->{'c.altitude_value'} )
	    {
		my $output = $q->param('collections_altitude_output');
		my $row_unit = $row->{'c.altitude_unit'};
		
		# Ignore all values with no assigned unit
		
		next unless defined $row_unit and $row_unit ne '';
		
		# Otherwise, convert to the desired output unit
		
		if ( $output eq 'feet' and $row_unit eq 'meters' )
		{
		    $row->{'c.altitude_value'} *= 3.28;
		}
		
		elsif ( $output eq 'meters' and $row_unit eq 'feet' )
		{
		    $row->{'c.altitude_value'} *= 0.305;
		}
	    }
        }
    }

    return (\@dataRows,\@allDataRows,$dataRowsSize);
}

sub printCSV {
    my $self = shift;
    my $results = shift;
    my $q = $self->{'q'};

    my $ext = 'csv';
    if ($q->param('output_format') =~ /tab/i) {
        $ext = 'tab';
    }

    my $mainFile = "";
    my $filename = $self->{'filename'};
    if ( $q->param("output_data") eq 'collections') {
        $mainFile = "$filename-collections.$ext";
    } elsif ( $q->param('output_data') eq 'taxonomic list' && $q->param('taxonomic_level') eq 'genera') {
        $mainFile = "$filename-genera.$ext";
    } elsif ( $q->param('output_data') eq 'taxonomic list' && $q->param('taxonomic_level') eq 'species') {
        $mainFile = "$filename-species.$ext";
    } else {
        $mainFile = "$filename-occs.$ext";
    }

    if (! open(OUTFILE, ">$OUT_FILE_DIR/$mainFile") ) {
        die ( "Could not open output file: $mainFile ($!)<br>\n" );
    }

    #
    # Header Generation
    #

    # print column names to occurrence output file JA 19.8.01
    my @header = ();

    if ($q->param('output_data') =~ /occurrence|collections/) {
        push @header,'collection_no';
    }
    # these are required, users must understand where the data come from
    #  and what the terms of use are JA 20.11.12
    push @header,('c.authorizer','license');
    if ($q->param('output_data') =~ /occurrence|taxonomic.list/) {
        push @header, 'o.class_name' if ($q->param("occurrences_class_name") eq 'YES');
        push @header, 'o.class_extant' if ( $q->param("occurrences_class_name") eq 'YES' && $q->param('occurrences_extant') eq 'YES');
        push @header, 'o.order_name' if ($q->param("occurrences_order_name") eq 'YES');
        push @header, 'o.order_extant' if ( $q->param("occurrences_order_name") eq 'YES' && $q->param('occurrences_extant') eq 'YES');
        push @header, 'o.family_name' if ($q->param("occurrences_family_name") eq 'YES');
        push @header, 'o.family_extant' if ( $q->param("occurrences_family_name") eq 'YES' && $q->param('occurrences_extant') eq 'YES');
        push @header, 'o.parent_rank' if ($q->param("occurrences_parent_name") eq 'YES');
        push @header, 'o.parent_name' if ($q->param("occurrences_parent_name") eq 'YES');
        push @header, 'o.parent_extant' if ( $q->param("occurrences_parent_name") eq 'YES' && $q->param('occurrences_extant') eq 'YES');
        push @header, 'genus_extant' if ( $q->param('occurrences_extant') eq 'YES');
        push @header, 'species_extant' if ( $q->param('taxonomic_level') =~ /species/i && $q->param('occurrences_extant') eq 'YES');
    }      
    if ($q->param('output_data') =~ /taxonomic.list/ && $q->param('taxonomic_level') =~ /genera/) {
        push @header, 'o.genus_name';
    } elsif ($q->param('output_data') =~ /taxonomic.list/ && $q->param('taxonomic_level') =~ /species/) {
        push @header, 'o.genus_name';
        push @header, 'o.subgenus_name' if ($q->param("occurrences_subgenus_name") eq "YES");
        push @header, 'o.species_name';
    } elsif ($q->param('output_data') =~ /occurrence/) {
        foreach (@occTaxonFieldNames) {
            if ($q->param("occurrences_".$_) eq 'YES') {
                push(@header, "o.$_") 
            }
        }
        foreach (@reidTaxonFieldNames) {
            if ($q->param("occurrences_".$_) eq 'YES') {
                push @header, "or.$_"
            }
        }
        foreach (@occFieldNames) {
            if ($q->param("occurrences_".$_) eq 'YES') {
                push @header, "o.$_";
            }
        }
        foreach (@reidFieldNames) {
            if ($q->param("occurrences_".$_) eq 'YES') {
                push @header,"or.$_"
            }
        }
    }

    if ($q->param('output_data') =~ /first_author|second_author|other_authors|year_named|occurrence|taxonomic.list/) {
        push @header,@ecoFields;
        push @header,'first_author' if ($q->param("occurrences_first_author"));
        push @header,'second_author' if ($q->param("occurrences_second_author"));
        push @header,'other_authors' if ($q->param("occurrences_other_authors"));
        push @header,'year_named' if ($q->param("occurrences_year_named"));
        push @header,'preservation' if ($q->param("occurrences_preservation"));
        push @header,'type_specimen' if ($q->param("occurrences_type_specimen"));
        push @header,'type_body_part' if ($q->param("occurrences_type_body_part"));
        push @header,'type_locality' if ($q->param("occurrences_type_locality"));
        push @header,'form_taxon' if ($q->param("occurrences_form_taxon"));
        push @header,'common_name' if ($q->param("occurrences_common_name"));
    }
       
    if ($q->param('output_data') =~ /collections|occurrence/) {
        foreach (@collectionsFieldNames) {
            if ($q->param("collections_paleocoords_format") eq "DMS") {
                next if ($_ =~ /^paleo(?:latdec|lngdec)/);
            } else {
                next if ($_ =~ /^paleo(?:latdeg|latdir|latmin|latsec|lngdeg|lngdir|lngmin|lngsec)/);
            }
            if ($q->param("collections_coords_format") eq "DMS") {
                next if ($_ =~ /^(?:latdec|lngdec)/);
            } else {
                next if ($_ =~ /^(?:latdeg|latdir|latmin|latsec|lngdeg|lngdir|lngmin|lngsec)/);
            }
            if ($q->param("collections_".$_) eq 'YES') {
                push @header, "c.$_";
            }
        }
	
	if ( $q->param('collections_altitude') eq "YES" )
	{
	    push @header, "c.altitude_value";
	}
    }

    my @printedHeader = (); 
    foreach (@header) {
        my $v = $_;
        # printing table names for all fields was really, really annoying,
        #  should have fixed this years ago JA 14.6.12
        if ( $v =~ /authorizer|enterer|modifier|reference_no|created|modified|genus_|species_/ )	{
            $v =~ s/^o\./occurrence\./;
            $v =~ s/^or\./original\./;
            $v =~ s/^re\./reidentification\./;
            $v =~ s/^c\./collection\./;
        } else	{
            $v =~ s/^(o|or|re|c)\.//;
        }
        $v =~ s/^e\.//;
        if ($q->param("output_data") =~ /taxonomic_list/) {
            $v =~ s/^[a-z]+\.//g;
        }
        push @printedHeader,$v;
    }
    my $headerline = $self->formatRow(@printedHeader);
    print OUTFILE $headerline."\n";
  
    foreach my $row (@$results) {
        my @line = ();

        if ( $q->param('collections_pubyr') eq "YES" )	{
            $row->{'c.pubyr'} = $pubyr[$row->{'c.reference_no'}];
    	}
        for my $v (@header) {
            push @line, $row->{$v};
        }

        my $curLine = $self->formatRow(@line);
        $curLine =~ s/\r|\n/ /g;
        print OUTFILE "$curLine\n";
    }

    return (scalar (@$results),$mainFile);
}

sub printMatrix {
    my $self = shift;
    my $results = shift;
    my $dbt = $self->{'dbt'};
    my $q = $self->{'q'};

    my $ext = 'csv';
    if ($q->param('output_format') =~ /tab/i) {
        $ext = 'tab';
    } 

    my $mainFile = "$self->{filename}-matrix.$ext";

    if (! open(OUTFILE, ">$OUT_FILE_DIR/$mainFile") ) {
        die ( "Could not open output file: $mainFile ($!)<br>\n" );
    }

    #
    # Header Generation
    #

    my @nameHeader = ();
    my @printedNameHeader = ();
    my @occHeader = ();
    my @printedOccHeader = ();
    my @collHeader = ();
    my @printedCollHeader = ();

    foreach (@occTaxonFieldNames,'plant_organ','plant_organ2') {
        if ($q->param("occurrences_".$_) eq 'YES') {
            push @nameHeader, "o.".$_;
            push @printedNameHeader, $_;
        }
    }
       
    foreach (@collectionsFieldNames) {
        if ($q->param("collections_paleocoords_format") eq "DMS") {
            next if ($_ =~ /^paleo(?:latdec|lngdec)/);
        } else {
            next if ($_ =~ /^paleo(?:latdeg|latdir|latmin|latsec|lngdeg|lngdir|lngmin|lngsec)/);
        }
        if ($q->param("collections_coords_format") eq "DMS") {
            next if ($_ =~ /^(?:latdec|lngdec)/);
        } else {
            next if ($_ =~ /^(?:latdeg|latdir|latmin|latsec|lngdeg|lngdir|lngmin|lngsec)/);
        }
        if ($q->param("collections_".$_) eq 'YES') {
            push @collHeader, "c.".$_;
            push @printedCollHeader, "collections.".$_;
        }
    }

    if ($q->param("occurrences_class_name") eq 'YES') {
        push @occHeader, 'o.class_name';
        push @printedOccHeader, 'class_name';
    }
    if ($q->param("occurrences_order_name") eq 'YES') {
        push @occHeader, 'o.order_name';
        push @printedOccHeader, 'order_name';
    }
    if ($q->param("occurrences_family_name") eq 'YES') {
        push @occHeader, 'o.family_name';
        push @printedOccHeader, 'family_name';
    }
    if ($q->param("occurrences_parent_name") eq 'YES') {
        push @occHeader, 'o.parent_rank,o.parent_name';
        push @printedOccHeader, 'parent_rank,parent_name';
    }

    push @occHeader,@ecoFields;
    push @occHeader,'first_author' if ($q->param("occurrences_first_author"));
    push @occHeader,'second_author' if ($q->param("occurrences_second_author"));
    push @occHeader,'other_authors' if ($q->param("occurrences_other_authors"));
    push @occHeader,'year_named' if ($q->param("occurrences_year_named"));
    push @occHeader,'preservation' if ($q->param("occurrences_preservation"));
    push @occHeader,'type_specimen' if ($q->param("occurrences_type_specimen"));
    push @occHeader,'type_body_part' if ($q->param("occurrences_type_body_part"));
    push @occHeader,'type_locality' if ($q->param("occurrences_type_locality"));
    push @occHeader,'form_taxon' if ($q->param("occurrences_form_taxon"));
    push @occHeader,'common_name' if ($q->param("occurrences_common_name"));
    push @printedOccHeader,@ecoFields;
    push @printedOccHeader,'first_author' if ($q->param("occurrences_first_author"));
    push @printedOccHeader,'second_author' if ($q->param("occurrences_second_author"));
    push @printedOccHeader,'other_authors' if ($q->param("occurrences_other_authors"));
    push @printedOccHeader,'year_named' if ($q->param("occurrences_year_named"));
    push @printedOccHeader,'preservation' if ($q->param("occurrences_preservation"));
    push @printedOccHeader,'type_specimen' if ($q->param("occurrences_type_specimen"));
    push @printedOccHeader,'type_body_part' if ($q->param("occurrences_type_body_part"));
    push @printedOccHeader,'type_locality' if ($q->param("occurrences_type_locality"));
    push @printedOccHeader,'form_taxon' if ($q->param("occurrences_form_taxon"));
    push @printedOccHeader,'common_name' if ($q->param("occurrences_common_name"));

    my %matrix;
    my %collections;
    my %occ_data;

    foreach my $ref (@$results) {
        my %row = %$ref;
        my $taxon_key = join "|", @row{@nameHeader};
        $taxon_key =~ s/n\. gen\.|n\. subgen\.|n\. sp\.//g;
        push @{$matrix{$taxon_key}{$row{'collection_no'}}}, $ref;
        $collections{$row{'collection_no'}} = $ref;
        push @{$occ_data{$taxon_key}}, $ref;
    }

    if (scalar(keys(%collections)) > $matrix_limit) {
        return ("ERROR: too many collections",scalar(keys(%collections)));
    }

    # Standard Schwartzian transform - we don't want to sort by _reso, so cut
    # out the resos to create a sorting key, sort on that, then tranform back
    my $numNameBits = scalar(@nameHeader);
    my $makeSortKey = sub {
        my $taxon_key = shift;
        my @nameBits = split(/\|/, $taxon_key, $numNameBits);
        my @reorder = ();
        # Reorder so resos come last
        for(my $i=0;$i<@nameHeader;$i++) {
            if ($nameHeader[$i] !~ /reso/) {
                push @reorder, $i; 
            } 
        }
        for(my $i=0;$i<@nameHeader;$i++) {
            if ($nameHeader[$i] =~ /reso/) {
                push @reorder, $i; 
            }
        }
        my $sort_key = "";
        foreach my $idx (@reorder) {
            $sort_key .= " ".$nameBits[$idx];
        }
        return $sort_key;
    };
    my @taxa = 
        map {$_->[1]}
        sort {$a->[0] cmp $b->[0]}
        map {[$makeSortKey->($_),$_]}
        keys %matrix;
    my @collections = sort {$a <=> $b} keys %collections;

    my $headerline = $self->formatRow((@printedNameHeader,@collections,@printedOccHeader));
    print OUTFILE $headerline."\n";
   
    foreach my $taxon_key (@taxa) {
        my @line = ();
        push @line, split(/\|/, $taxon_key, $numNameBits);
        foreach my $collection_no (@collections) {
            my $occs= $matrix{$taxon_key}{$collection_no};
            if ($occs) {
                my $abundance = 0;
                foreach my $row (@$occs) {
                    if ($row->{'o.abund_value'} =~ /^\d*\.?\d+$/ && $row->{'o.abund_unit'} !~ /%|rank|category/) {
                        $abundance += $row->{'o.abund_value'};
                    }
                }
                if ($abundance) {
                    push @line, $abundance;
                } else {
                    push @line, "X";
                }
            } else {
                push @line, "";
            }
        }
        my @occ_rows = @{$occ_data{$taxon_key}};
        my $ref = $occ_rows[0];
        foreach my $v (@occHeader) {
            push @line, $ref->{$v};
        }

        my $curLine = $self->formatRow(@line);
        $curLine =~ s/\r|\n/ /g;
        print OUTFILE "$curLine\n";
    }
    my @blanks = ();
    for(my $i = 0;$i < (scalar(@nameHeader)-1); $i++) {
        push @blanks, "";
    }
    for(my $i = 0;$i < @printedCollHeader;$i++) {
        my @line = ();
        push @line, $printedCollHeader[$i];
        push @line, @blanks;
        # Print blanks to get this to line up
        foreach my $collection_no (@collections) {
            my $ref = $collections{$collection_no};    
            push @line, $ref->{$collHeader[$i]};
        }
        my $curLine = $self->formatRow(@line);
        $curLine =~ s/\r|\n/ /g;
        print OUTFILE "$curLine\n";
    }

    return (scalar(@taxa),scalar(@collections),$mainFile);
}

# this section is by Schroeter; I'm just doing a cleanup 15.4.06 JA
sub printCONJUNCT {
    my $self = shift;
    my $results = shift;
    my $q = $self->{'q'};

    my $filename = $self->{'filename'};
    # Conjunct is expecting an "occurrences" type or it might screw up, so keep this short
    my $mainFile = "$filename-conjunct";

    if (! open(OUTFILE, ">$OUT_FILE_DIR/$mainFile") ) {
        die ( "Could not open output file: $mainFile ($!)<br>\n" );
    }

    my $ext = 'csv';
    if ($q->param('output_format') =~ /tab/i) {
        $ext = 'tab';
    }
    my $collFile = "$filename-collections.$ext";
    if (! open(COLLS, ">$OUT_FILE_DIR/$collFile") ) {
        die ( "Could not open output file: $collFile($!)<br>\n" );
    }
    my @outfields = ("collection");
    foreach (@collectionsFieldNames) {
        if ($q->param("collections_".$_) eq 'YES') {
            push @outfields , $_;
        }
    }
    print COLLS $self->formatRow(@outfields)."\n";

    my $colls = 0;
    my $lastcoll;
    my %indetseen;
    foreach my $row (@$results) {
        if ($lastcoll != $row->{'collection_no'}) {
            $colls++;
            if ( $lastcoll )    {
                print OUTFILE ".\n\n";
            }
            %indetseen = ();
            my @data = ();
            if ( $row->{'c.collection_name'} )    {
                $row->{'c.collection_name'} =~ s/ /_/g;
                push @data , $row->{'c.collection_name'};
                printf OUTFILE "%s\n",$row->{'c.collection_name'};
            } else    {
                push @data , $row->{'collection_no'};
                print OUTFILE "Collection_$row->{'collection_no'}\n";
            }

            my @comments = ("collection_no: $row->{'collection_no'}");

            foreach (@collectionsFieldNames) {
                if ($q->param("collections_".$_) eq 'YES') {
                    push @data , $row->{'c.'.$_};
                    if ($row->{'c.'.$_}) {
                        # these three will be printed anyway
                        if ( $_ !~ /collection_name|localsection|localbed/ )	{
                        	push @comments,"$_: $row->{'c.'.$_}"; 
                    	}
                    }
                }
            } 
            print COLLS $self->formatRow(@data)."\n";

            if (@comments) {
                print OUTFILE "[".join("\n",@comments)."]\n";
            }

            my $level;
            my $level_value;
            if ($row->{'c.regionalsection'} && $row->{'c.regionalbed'} =~ /^[0-9]+(\.[0-9]+)*$/) {
                $level = $row->{'c.regionalsection'};
                $level_value = $row->{'c.regionalbed'};
                if ($row->{'c.regionalorder'} eq 'top to bottom') {
                    $level_value *= -1;
                }
            # CONJUNCT can't cope with decimal values, so toss them
                if ( $level_value =~ /\./ )	{
                    my $foo;
                    ($level_value,$foo) = split /\./,$level_value;
                }
            }
            if ($row->{'c.localsection'} && $row->{'c.localbed'} =~ /^[0-9]+(\.[0-9]+)*$/) {
                $level = $row->{'c.localsection'};
                $level_value = $row->{'c.localbed'};
                if ($row->{'c.localorder'} eq 'top to bottom') {
                    $level_value *= -1;
                }
                if ( $level_value =~ /\./ )	{
                    my $foo;
                    ($level_value,$foo) = split /\./,$level_value;
                }
            }
            if ($level) {
                $level =~ s/ /_/g;
                print OUTFILE "level: $level $level_value\n";
            }
        }

# print higher order names as if they were separate taxa, but don't keep
#  doing it over and over JA 21.3.07
# note that parent_name is never printed to a CONJUNCT file
        if ( $q->param('occurrences_class_name') eq "YES" && $row->{'o.class_name'} && ! $indetseen{$row->{'o.class_name'}} )	{
            print OUTFILE $row->{'o.class_name'}," indet.\n";
            $indetseen{$row->{'o.class_name'}} = 1;
        }
        if ( $q->param('occurrences_order_name') eq "YES" && $row->{'o.order_name'} && ! $indetseen{$row->{'o.order_name'}} )	{
            print OUTFILE $row->{'o.order_name'}," indet.\n";
            $indetseen{$row->{'o.order_name'}} = 1;
        }
        if ( $q->param('occurrences_family_name') eq "YES" && $row->{'o.family_name'} && ! $indetseen{$row->{'o.family_name'}} )	{
            print OUTFILE $row->{'o.family_name'}," indet.\n";
            $indetseen{$row->{'o.family_name'}} = 1;
        }
        
# informals and new taxa don't work; we're punting on adding quotes
        if ( $row->{'o.genus_reso'} && $row->{'o.genus_reso'} !~ /(informal)|(")|(n\. gen\.)/) {
            printf OUTFILE "%s ",$row->{'o.genus_reso'};
        }
        print OUTFILE "$row->{'o.genus_name'} ";
        if ( $row->{'o.species_reso'} && $row->{'o.species_reso'} !~ /(informal)|(")|(n\. sp\.)/) {
            printf OUTFILE "%s ",$row->{'o.species_reso'};
        }
        if ( ! $row->{'o.species_name'} || $row->{'o.species_reso'} =~ /(informal)|(n\. gen\.)/ )    {
            print OUTFILE "sp.\n";
        } else {
            my $species_name = $row->{'o.species_name'};
# if there are spaces in the species name, it's some stupid thing like "sp. A",
#   so put the garbage in brackets JA 16.4.06 and print a sp. JA 14.10.06
            if ( $species_name =~ / / )	{
                $species_name = "sp. [" . $species_name . "]";
            }
            printf OUTFILE "%s\n",$species_name;
        }
        $lastcoll = $row->{'collection_no'};
    }

    print OUTFILE ".\n\n";
    close OUTFILE;
    close COLLS;

    return (scalar(@$results),$mainFile,$collFile,$colls);
}


sub printRefsFile {
    my $self = shift;
    my $results = shift;
    my $q = $self->{'q'};
    my $dbt = $self->{'dbt'};

    # Open the file handlea we're going to use or die
    my $filename = $self->{'filename'};
    my $ext = ($q->param('output_format') =~ /tab/) ? "tab" : "csv";
    my $refsFile = "$filename-refs.$ext";
    my $risFile = "$filename-ris.txt";
    if (!open(REFSFILE, ">$OUT_FILE_DIR/$refsFile")) {
        die ("Could not open output file: $refsFile($!) <br>");
    } 
    if (!open(RISFILE, ">$OUT_FILE_DIR/$risFile")) {
	die "Could not open output file: $risFile ($!) <br>";
    }
    
    # now hit the secondary refs table, mark all of those references as
    #  having been used, and print all the refs JA 16.7.04
    my (%all_refs,%all_colls,%colls_by_ref,%occs_by_ref);
    foreach my $row (@$results) {
        $all_colls{$row->{'collection_no'}}++;
        $all_refs{$row->{'reference_no'}}++;
        $colls_by_ref{$row->{'reference_no'}}{$row->{'collection_no'}}++;
        if ($row->{'o.reference_no'}) {
            $all_refs{$row->{'o.reference_no'}}++;
            $occs_by_ref{$row->{'o.reference_no'}}++;
        }
        if ($row->{'re.reference_no'}) {
            $all_refs{$row->{'re.reference_no'}}++;
            $occs_by_ref{$row->{'re.reference_no'}}++;
        }
    }
    delete $all_colls{''};
    if (%all_colls) {
        my $sql = "SELECT sr.reference_no FROM secondary_refs as sr JOIN collections as c using (collection_no)
		   WHERE c.reference_no <> sr.reference_no and
			 collection_no IN (".join (', ',keys %all_colls).")";
        $self->dbg("secondary refs sql: $sql"); 
        my @results = @{$dbt->getData($sql)};
        foreach my $row (@results){
            $all_refs{$row->{'reference_no'}}++;
        }
    }
    delete $all_refs{''};

    # print the header
    print REFSFILE join (',',@refsFieldNames), "\n";

    # print the refs
    my $ref_count = 0;
    my $ris_ref_count = 0;
    my (@ris_bad_list);
    if (%all_refs) {
        my $fields = join(",",map{"r.".$_} grep{!/^(?:authorizer|enterer|modifier)$/} @refsFieldNames);
        my $sql = "SELECT p1.name authorizer, p2.name enterer, p3.name modifier, $fields FROM refs r ".
                   " LEFT JOIN person p1 ON p1.person_no=r.authorizer_no" .
                   " LEFT JOIN person p2 ON p2.person_no=r.enterer_no" .
                   " LEFT JOIN person p3 ON p3.person_no=r.modifier_no" .
                   " WHERE reference_no IN (" . join (', ',keys %all_refs) . ")";
        $self->dbg("Get ref data sql: $sql"); 
        my @results = @{$dbt->getData($sql)};
        @results = sort { $a->{'author1last'} cmp $b->{'author1last'} || $a->{'author2last'} cmp $b->{'author2last'} || $a->{'pubyr'} cmp $b->{'pubyr'} } @results;
        my %points;
        foreach my $row (@results) {
            my @refvals = ();
            foreach my $r (@refsFieldNames) {
                if ($row->{$r}) {
                    push @refvals,$row->{$r};
                } else {
                    push @refvals,'';
                }
            }
            my $refLine = $self->formatRow(@refvals);
            $refLine =~ s/\r|\n/ /g;
            printf REFSFILE "%s\n",$refLine;
            $ref_count++;
	    
	    my $refout = PBDB::ReferenceEntry::formatRISRef($dbt, $row);
	    if ( $refout =~ /PARSE ERROR/ )
	    {
		push @ris_bad_list, $row->{reference_no};
	    }
	    else
	    {
		$ris_ref_count++;
		print RISFILE $refout;
	    }
	    
            # need this to print the publication year for collections JA 4.12.06
            $pubyr[$row->{reference_no}] = $row->{pubyr};
            my @temp = keys %{$colls_by_ref{$row->{'reference_no'}}};
            my $colls_by_ref = $#temp;
            if ( $colls_by_ref == 0 )	{
                $points{$row->{'reference_no'}} = $occs_by_ref{$row->{'reference_no'}};
            } else	{
                $points{$row->{'reference_no'}} = $colls_by_ref * $occs_by_ref{$row->{'reference_no'}};
            }
        }
        # list major data sources 23-24.7.11 JA
        @results = sort { $points{$b->{'reference_no'}} <=> $points{$a->{'reference_no'}} } @results;
        my $printed;
        for my $row ( @results )	{
            if ( $printed == 20 || $points{$row->{'reference_no'}} < 100 )	{
                last;
            }
            $printed++;
            my ($colls,$occs) = ("collections","occurrences");
            my @temp = keys %{$colls_by_ref{$row->{'reference_no'}}};
            my $colls_by_ref = $#temp;
            #my $colls_by_ref = $#{ keys %{$colls_by_ref{$row->{'reference_no'}}} };
            $colls_by_ref == 1 ? $colls = "collection" : $colls;
            $occs_by_ref{$row->{'reference_no'}} == 1 ? $occs = "occurrence" : $occs;
            $cites .= "<div style=\"margin-bottom: -1.25em;\">";
            my $ref = $row;
            # suppress printing of authorizer/enterer info
            $ref->{'authorizer'} = "";
            $cites .= PBDB::Reference::formatLongRef($row);
            $cites .= " [";
            $colls_by_ref > 0 ? $cites .= "$colls_by_ref $colls" : "";
            $colls_by_ref > 0 && $occs_by_ref{$row->{'reference_no'}} > 0 ? $cites .= ", " : "";
            $occs_by_ref{$row->{'reference_no'}} > 0 ? $cites .= $occs_by_ref{$row->{'reference_no'}}." $occs" : "";
            $cites .= "]</div><br>\n";
        }
        if ( $points{$results[0]->{'reference_no'}} < 100 )	{
            $cites = "";
        } else	{
            $cites .= "</div>\n\n";
        }
    }
    close REFSFILE;
    return ($ref_count,$refsFile,$cites,$ris_ref_count,\@ris_bad_list);
}


sub printAbundFile {
    my $self = shift;
    my $results = shift;
    my $q = $self->{'q'};

    # Open the file handle we're going to use or die
    my $filename = $self->{'filename'};
    my $ext = ($q->param('output_format') =~ /tab/) ? "tab" : "csv";
    my $rangeFile = "$filename-ranges.$ext";

    if (!open(RANGEFILE, ">$OUT_FILE_DIR/$rangeFile")) {
        die ("Could not open output file: $rangeFile($!) <br>");
    }

    # cumulate number of specimens per collection
    my %abundance = ();
    for my $row (@$results) {
        if ( $row->{'o.abund_unit'} =~ /^(?:specimens|individuals)$/ && $row->{'o.abund_value'} > 0 ) {
            $abundance{$row->{'collection_no'}} += $row->{'o.abund_value'};
        }
    }

    # compute relative abundance proportion and add to running total
    # WARNING: sum is of logged abundances because geometric means are desired
    my (%occs_by_taxa,%range_max,%range_min,%summed_proportions,%number_of_counts);
    my $min_abund = int($q->param('min_mean_abundance'));
    foreach my $row (@$results) {
        my $taxa_key = $row->{'o.genus_name'};
        # cumulate number of collections including each genus
        if ($q->param('taxonomic_level') =~ /species/i) {
            $taxa_key .= "|".$row->{'o.species_name'};
        } 
        $occs_by_taxa{$taxa_key}++;
        # range computation JA 8.4.09
        # bear with me here, first we need the oldest min and youngest max
        # note that the max and min can be reversed at this stage and it's okay
        # WARNING: range computations always use both interval-based info
        #  and direct dating regardless of what the user wants
        if ( $row->{'c.ma_min'} > $range_max{$taxa_key} )	{
            $range_max{$taxa_key} = $row->{'c.ma_min'};
        }
        if ( ( $row->{'c.ma_max'} < $range_min{$taxa_key} || ! $range_min{$taxa_key} ) && $row->{'c.ma_max'} )	{
            $range_min{$taxa_key} = $row->{'c.ma_max'};
        }
        # need these two for ecology lookup below

        if ( ($row->{'o.abund_unit'} eq "specimens" || $row->{'o.abund_unit'} eq "individuals") && 
             ($row->{'o.abund_value'} =~ /^\d+$/ && $row->{'o.abund_value'} > 0) ) {
            if ($min_abund) {
                if ($abundance{$row->{collection_no}} >= $min_abund) {
                    $number_of_counts{$taxa_key}++;
                    $summed_proportions{$taxa_key} += log($row->{'o.abund_value'} / $abundance{$row->{'collection_no'}});
                } else {
                    $self->dbg("Skipping collection_no $row->{collection_no}, count $abundance{$row->{collection_no}} is below count $min_abund");
                }
            } else {
                $number_of_counts{$taxa_key}++;
                $summed_proportions{$taxa_key} += log($row->{'o.abund_value'} / $abundance{$row->{'collection_no'}});
            }
        }
    }
    # end of range computation JA 8.4.09
    # now that we have the absolute minimum range we need to pad it out by
    #  looking at youngest max and oldest min ranges of possible oldest and
    #  youngest occurrences (got that?)
    my %new_range_max;
    my %new_range_min;
    foreach my $row (@$results) {
        my $taxa_key = $row->{'o.genus_name'};
        if ($q->param('taxonomic_level') =~ /species/i) {
            $taxa_key .= "|".$row->{'o.species_name'};
        }
        if ( $row->{'c.ma_max'} == $row->{'c.ma_min'} && $row->{'c.ma_max'} )	{
            if ( $row->{'c.ma_max'} >= $range_max{$taxa_key} && ( $row->{'c.ma_max'} < $new_range_max{$taxa_key} || ! $new_range_max{$taxa_key} ) )	{
                $new_range_max{$taxa_key} = $row->{'c.ma_max'};
            }
            if ( $row->{'c.ma_min'} <= $range_min{$taxa_key} && ( $row->{'c.ma_min'} >= $new_range_min{$taxa_key} || ! $new_range_min{$taxa_key} ) && $row->{'c.ma_min'} )	{
                $new_range_min{$taxa_key} = $row->{'c.ma_min'};
            }
        } else	{
            if ( $row->{'c.ma_max'} > $range_max{$taxa_key} && ( $row->{'c.ma_max'} < $new_range_max{$taxa_key} || ! $new_range_max{$taxa_key} ) )	{
                $new_range_max{$taxa_key} = $row->{'c.ma_max'};
            }
            if ( $row->{'c.ma_min'} < $range_min{$taxa_key} && ( $row->{'c.ma_min'} >= $new_range_min{$taxa_key} || ! $new_range_min{$taxa_key} ) && $row->{'c.ma_min'} )	{
                $new_range_min{$taxa_key} = $row->{'c.ma_min'};
            }
        }
    }
    # print out a list of genera with total number of occurrences and average relative abundance
    # This list of genera is needed abundance file far below
    my @rangeline = ();
    push @rangeline, 'genus';
    if ($q->param('taxonomic_level') =~ /species/i) {
        push @rangeline, 'species';
    }
    push @rangeline, 'base of range (Ma)','top of range (Ma)','collections','with abundances','geometric mean abundance';
    print RANGEFILE $self->formatRow(@rangeline)."\n";

    my @taxa = sort keys %occs_by_taxa;
    foreach my $taxon ( @taxa ) {
        @rangeline = ();
        if ($q->param('taxonomic_level') =~ /species/i) {
            my ($genus,$species)=split(/\|/,$taxon);
            push @rangeline, $genus, $species, $new_range_max{$taxon}, $new_range_min{$taxon}, $occs_by_taxa{$taxon}, sprintf("%d",$number_of_counts{$taxon});
        } else {
            push @rangeline, $taxon, $new_range_max{$taxon}, $new_range_min{$taxon}, $occs_by_taxa{$taxon}, sprintf("%d",$number_of_counts{$taxon});
        }
        
        if ( $number_of_counts{$taxon} > 0 )    {
            push @rangeline, sprintf("%.4f",exp($summed_proportions{$taxon} / $number_of_counts{$taxon}));
        } else    {
            push @rangeline, "NaN";
        }
        print RANGEFILE $self->formatRow(@rangeline)."\n";
    }
    close RANGEFILE;
    return (scalar(@taxa),$rangeFile);
}


sub printScaleFile {
    my $self = shift;
    my $results = shift;
    my $q = $self->{'q'};
    my $dbt = $self->{'dbt'};
    my $dbh = $self->{'dbh'};

    my $time_scale = int($q->param('time_scale'));
    return ('','') unless $time_scale;
   
    # Open the file handlea we're going to use or die
    my $filename = $self->{'filename'};
    my $ext = ($q->param('output_format') =~ /tab/) ? "tab" : "csv";
    my $scaleFile = "$filename-scale.$ext";
    if (!open(SCALEFILE, ">$OUT_FILE_DIR/$scaleFile")) {
        die ("Could not open output file: $scaleFile($!) <br>");
    }

    my ($interval_lookup,$upper_bin_bound,$lower_bin_bound);
    if ( $q->param('time_scale') eq "PBDB 10 m.y. bins" ) {
        ($upper_bin_bound,$lower_bin_bound) = $self->{t}->computeBinBounds('bins');
        ($interval_lookup) = $self->{t}->getScaleMapping('bins');
    } else {
        ($upper_bin_bound,$lower_bin_bound) = $self->{t}->getBoundaries();
        ($interval_lookup) = $self->{t}->getScaleMapping($time_scale,'names');
    }

    my (%occs_by_bin,%taxa_by_bin);
    my (%occs_by_bin_taxon,%occs_by_category,%occs_by_bin_cat_taxon);
    my (%occs_by_bin_and_category,%taxa_by_bin_and_category);
    foreach my $row (@$results) {
        # count up occurrences per time interval bin
        my $max_no = $row->{'max_interval_no'};
        my $min_no = $row->{'min_interval_no'} || $row->{'max_interval_no'};
        my $max_lookup = $interval_lookup->{$max_no};
        my $min_lookup = $interval_lookup->{$min_no};
        my $interval;
        if ($max_lookup && $max_lookup eq $min_lookup) {
            $interval = $max_lookup;
        }
        my $bin_key = $row->{'o.genus_name'};
        if ($q->param("taxonomic_level") =~ /species/) {
            $bin_key .="_".$row->{'o.species_name'};
        } 
        # only use occurrences from collections that map into exactly one bin
        if ($interval) {
            $occs_by_bin{$interval}++;
            $occs_by_bin_taxon{$interval}{$bin_key}++;
            if ( $occs_by_bin_taxon{$interval}{$bin_key} == 1 )    {
                $taxa_by_bin{$interval}++;
            }
        }
        # now things get nasty: if a field was selected to
        #  break up into categories, add to the count involving
        #  the appropriate enum value
        # WARNING: algorithm assumes that only enum fields are
        #  ever selected for processing
        if ( $q->param('binned_field') )    {
            my $row_value;
            if ( $q->param('binned_field') eq "ecology" )    {
                # special processing for ecology data
                $row_value= $row->{$q->param('ecology1')}; 
            } else {
                # default processing
                if ($q->param('binned_field') =~ /plant_organ/) {
                    $row_value = $row->{"o.".$q->param('binned_field')};
                } else {
                    $row_value = $row->{"c.".$q->param('binned_field')};
                }
            }
            $occs_by_bin_and_category{$interval}{$row_value}++;
            $occs_by_bin_cat_taxon{$interval}{$row_value.$bin_key}++;
            if ( $occs_by_bin_cat_taxon{$interval}{$row_value.$bin_key} == 1 )    {
                $taxa_by_bin_and_category{$interval}{$row_value}++;
            }
            $occs_by_category{$row_value}++;
        }
    }

    # print out a list of time intervals with counts of occurrences

    my @intervalnames;
    #  list of 10 m.y. bin names
    if ( $q->param('time_scale') =~ /bin/ )    {
        @intervalnames = PBDB::TimeLookup::getBins();
    } else {
        @intervalnames = $self->{t}->getScaleOrder(int($q->param('time_scale')));
    }

    # need a list of enum values that actually have counts
    # NOTE: we're only using occs_by_category to generate this list,
    #  but it is kind of cute
    my @enumvals = sort keys %occs_by_category;

    # now print the results
    my @scaleline;
    push @scaleline, 'interval','lower boundary','upper boundary','midpoint','total occurrences';
    if ($q->param("taxonomic_level") =~ /species/) {
        push @scaleline, 'total species';
    } else {
        push @scaleline, 'total genera';
    }
    foreach my $val ( @enumvals )    {
        if ( $val eq "" )    {
            push @scaleline, 'no data occurrences', 'no data taxa';
        } else    {
            push @scaleline, "$val occurrences", "$val taxa";
        }
    }
    foreach my $val ( @enumvals )    {
        if ( $val eq "" )    {
            push @scaleline, 'proportion no data occurrences', 'proportion no data taxa';
        } else    {
            push @scaleline, "proportion $val occurrences", "proportion $val taxa";
        }
    }
    print SCALEFILE $self->formatRow(@scaleline)."\n";

    foreach my $intervalName ( @intervalnames ) {
        my @scaleline = ();
        push @scaleline, $intervalName;
        push @scaleline, sprintf("%.2f",$lower_bin_bound->{$intervalName});
        push @scaleline, sprintf("%.2f",$upper_bin_bound->{$intervalName});
        push @scaleline, sprintf("%.2f",($lower_bin_bound->{$intervalName} + $upper_bin_bound->{$intervalName}) / 2);
        push @scaleline, sprintf("%d",$occs_by_bin{$intervalName});
        push @scaleline, sprintf("%d",$taxa_by_bin{$intervalName});
        foreach my $val ( @enumvals )    {
            push @scaleline, sprintf("%d",$occs_by_bin_and_category{$intervalName}{$val});
            push @scaleline, sprintf("%d",$taxa_by_bin_and_category{$intervalName}{$val});
        }
        foreach my $val ( @enumvals )    {
            if ( $occs_by_bin_and_category{$intervalName}{$val} eq "" )    {
                push @scaleline, "0.0000","0.0000";
            } else    {
                push @scaleline, sprintf("%.4f",$occs_by_bin_and_category{$intervalName}{$val} / $occs_by_bin{$intervalName});
                push @scaleline, sprintf("%.4f",$taxa_by_bin_and_category{$intervalName}{$val} / $taxa_by_bin{$intervalName});
            }
        }
        print SCALEFILE $self->formatRow(@scaleline)."\n";
    }
    close SCALEFILE;
    return (scalar(@intervalnames),$scaleFile);
}

sub emailDownloadFiles	{
	my $self = shift;
	my $q = $self->{'q'};
        my $output = '';

	my %headers = ('Subject'=> 'Paleobiology Database download files','From'=>'PaleoDB administrator');
	$headers{'To'} = $q->param('email');
	$headers{'Content-Transfer-Encoding'} = "7bit";
	$headers{'Content-Type'} = 'multipart/mixed; boundary=Apple-Mail-81-601985459';
	$headers{'MIME-Version'} = "1.0";
	my $mailer = new Mail::Mailer;
	$mailer->open(\%headers);
	my @files = split /\//,$q->param('filenames');
	# this is a total hack that avoids having to install an extra package
	my $body = qq|This is a multi-part message in MIME format.

--Apple-Mail-81-601985459
Content-Transfer-Encoding: 7bit
Content-Type: text/plain; charset=US-ASCII; format=flowed

Here are the data files you downloaded from the Paleobiology Database web site.

|;
	for my $file ( @files )	{
		$body .= qq|
--Apple-Mail-81-601985459
Content-Transfer-Encoding: quoted-printable
Content-Type: application/octet-stream; x-unix-mode=0644; name=$file
Content-Disposition: attachment; filename=$file

|;
		$body .= `cat $OUT_FILE_DIR/$file`;
	}
	print $mailer $body; # we are printing to a process, not to a web page
	$mailer->close;

	$output .= "<center>\n<p class=\"pageTitle\">Download sent</p>\n\nYour download files have been mailed to:</p>\n\n<p><b>".$q->param('email')."</b></p></center>";

        return $output;
}


# The purpose of this function is set up various implied fields in the Q object
# so other functions (retellOptions and queryDatabsae) can behave correctly.  Should
# never have to be manually called, it will be called as needed by the various functions
# that use it.
sub setupQueryFields {
    my $self = shift;
    my $q = $self->{'q'};
    my $dbt = $self->{'dbt'};
    $self->{'setup_query_fields_called'} = 1;

    foreach my $c (@continents) {
        if ($q->param('country') eq $c) {
            $q->param($c=>"YES");
            $q->param('country'=>"");
        }
    }

    # Setup default parameters
    $q->param('output_format'=>'csv') if ($q->param('output_format') !~ /csv|tab/i);
    $q->param('output_data'=>'occurrence list') if ($q->param('output_data') !~ /collections|occurrence|taxonomic.list/);

    if ($q->param('output_data') =~ /conjunct/i) {
        $q->param("collections_regionalbed"=>"YES");
        $q->param("collections_regionalsection"=>"YES");
        $q->param("collections_regionalbedunit"=>"YES");
        $q->param("collections_localbed"=>"YES");
        $q->param("collections_localsection"=>"YES");
        $q->param("collections_localbedunit"=>"YES");
    }

    # Setup additional fields that should appear as columns in the CSV file

    # Just always download these two fields, since so many other fields are dependent on them 
    $q->param('collections_max_interval_no' => "YES");
    $q->param('collections_min_interval_no' => "YES");

    # and hey, if you want counts of some enum field split up within
    #  time interval bins, you have to download that field
    if ( $q->param('binned_field') )    {
        if ( $q->param('binned_field') =~ /plant_organ/ )    {
            $q->param('occurrences_' . $q->param('binned_field') => "YES");
        } else    {
            $q->param('collections_' . $q->param('binned_field') => "YES");
        }
    }
    # this sets a bunch of checkbox values to true if a corresponding checkbox is also true
    # so that the download script may be a bit simpler. 
    # must be called before retellOptions
    # i.e  if intage_max == YES, then set emlintage_max == YES as well 
    # PS 11/22/2004
    $q->param('collections_emlperiod_max' => "YES") if ($q->param('collections_period_max'));
    $q->param('collections_emlperiod_min' => "YES") if ($q->param('collections_period_min'));
    $q->param('collections_emlintage_max' => "YES") if ($q->param('collections_intage_max'));
    $q->param('collections_emlintage_min' => "YES") if ($q->param('collections_intage_min'));
    $q->param('collections_emlepoch_max' => "YES")  if ($q->param('collections_epoch_max'));
    $q->param('collections_emlepoch_min' => "YES")  if ($q->param('collections_epoch_min'));
    $q->param('collections_emllocage_max' => "YES") if ($q->param('collections_locage_max'));
    $q->param('collections_emllocage_min' => "YES") if ($q->param('collections_locage_min'));

    if ($q->param('lump_by_location')) {
        if (!$q->param("collections_coords") && $q->param('lump_by_location') =~ /coordinate/) {
            $q->param("collections_coords"=>"YES");
        } elsif (!$q->param("collections_county") && $q->param('lump_by_location') =~ /county/) {
            $q->param("collections_county"=>"YES");
            $q->param("collections_state"=>"YES");
        } elsif (!$q->param("collections_state") && $q->param('lump_by_location') =~ /state/) {
            $q->param("collections_state"=>"YES");
        }
    }
    if ($q->param('lump_by_strat_unit')) {
        if ( $q->param('lump_by_strat_unit') eq "group" )	{
            $q->param('collections_geological_group'=>'YES');
            $q->param('collections_formation'=>'YES');
        } elsif ( $q->param('lump_by_strat_unit') eq "formation" )	{
            $q->param('collections_formation'=>'YES');
        } elsif ( $q->param('lump_by_strat_unit') eq "member" )	{
            $q->param('collections_formation'=>'YES');
            $q->param('collections_member'=>'YES');
        }
    }
    if ($q->param('lump_by_ref')) {
        $q->param('collections_reference_no'=>'YES');
    }
    if ($q->param('collections_paleocoords')) {
        if ($q->param('collections_paleocoords_format') eq 'DMS') {
            $q->param('collections_paleolngdeg'=>'YES');
            $q->param('collections_paleolngmin'=>'YES');
            $q->param('collections_paleolngsec'=>'YES');
            $q->param('collections_paleolngdir'=>'YES');
            $q->param('collections_paleolatdeg'=>'YES');
            $q->param('collections_paleolatmin'=>'YES');
            $q->param('collections_paleolatsec'=>'YES');
            $q->param('collections_paleolatdir'=>'YES');
        } else { 
            $q->param('collections_paleolngdec'=>'YES');
            $q->param('collections_paleolatdec'=>'YES');
        }
    }
    if ($q->param('collections_gplates'))
    {
	if ( $q->param('collections_gplates_select') =~ /early|all/ )
	{
	    $q->param('collections_gp_early_lat' => 'YES');
	    $q->param('collections_gp_early_lng' => 'YES');
	}
	if ( $q->param('collections_gplates_select') =~ /mid|all/ )
	{
	    $q->param('collections_gp_mid_lat' => 'YES');
	    $q->param('collections_gp_mid_lng' => 'YES');
	}
	if ( $q->param('collections_gplates_select') =~ /late|all/ )
	{
	    $q->param('collections_gp_late_lat' => 'YES');
	    $q->param('collections_gp_late_lng' => 'YES');
	}
    }
    if ($q->param('collections_coords')) {
        if ($q->param('collections_coords_format') eq 'DMS') {
            $q->param('collections_lngdeg'=>'YES');
            $q->param('collections_lngmin'=>'YES');
            $q->param('collections_lngsec'=>'YES');
            $q->param('collections_lngdir'=>'YES');
            $q->param('collections_latdeg'=>'YES');
            $q->param('collections_latmin'=>'YES');
            $q->param('collections_latsec'=>'YES');
            $q->param('collections_latdir'=>'YES');
        } else {
            $q->param('collections_latdec'=>'YES');
            $q->param('collections_lngdec'=>'YES');
        }
    }

    if ( $q->param('split_subgenera') eq 'YES') {
        $q->param('occurrences_subgenus_name'=>'YES');
    } 

    # Get the right lat/lng/paleolat/paleolng fields
    if ($q->param("collections_regionalbed")) {
        $q->param("collections_regionalbedunit"=>"YES");
    }
    if ($q->param("collections_localbed")) {
        $q->param("collections_localbedunit"=>"YES");
    }
    
    # Need to get the species_name field as well
    # this step is crucial given that there's now a level field but no separate
    #  species_name field 10.6.13 JA
    if ($q->param('taxonomic_level') =~ /species/) {
        $q->param('occurrences_species_reso'=>'YES');
        $q->param('occurrences_species_name'=>'YES');
    }

    # Get these related fields as well
    if ($q->param('occurrences_subgenus_name')) {
        $q->param('occurrences_subgenus_reso'=>'YES');
    }

    # Required fields
    $q->param("occurrences_genus_name"=>'YES'); 
    $q->param("occurrences_genus_reso"=>'YES');

    # Get EML values, check interval names
    if ($q->param('max_interval_name')) {
        if ($q->param('max_interval_name') =~ /[a-zA-Z]/) {
            my ($eml, $name) = $self->{t}->splitInterval($q->param('max_interval_name'));
            my $ret = PBDB::Validation::checkInterval($dbt,$eml,$name);
            if (!$ret) {
                push @form_errors, "The database does not include a time interval called ".$q->param('max_interval_name');
                $q->param('max_interval_name'=>'');
                $q->param('max_eml_interval'=>'');
            } else {
                $q->param('max_interval_name'=>$name);
                $q->param('max_eml_interval'=>$eml);
            }
        }
    }
    if ($q->param('min_interval_name')) {
        if ($q->param('min_interval_name') =~ /[a-zA-Z]/) {
            my ($eml, $name) = $self->{t}->splitInterval($q->param('min_interval_name'));
            my $ret = PBDB::Validation::checkInterval($dbt,$eml,$name);
            if (! $ret) {
                push @form_errors, "The database does not include a time interval called ".$q->param('min_interval_name');
                $q->param('min_interval_name'=>'');
                $q->param('min_eml_interval'=>'');
            } else {
                $q->param('min_interval_name'=>$name);
                $q->param('min_eml_interval'=>$eml);
            }
        }
    }

    # Generate these fields on the fly
    @ecoFields = ();
    if ($q->param('output_data') =~ /occurrence|taxonomic.list/) {
        for(1..6) {
            if ($q->param("ecology$_")) {
                push @ecoFields, $q->param("ecology$_");
            }
        }
    }
}

# CSV_XS sometimes (always?) fails to add quotations when there are single
#  quotes and I honestly don't care why, so I'm trashing it in favor of
#  regexps that do the same thing just as well (thank you)
#  JA 12.4.13
sub formatRow {
    
    my $self = shift;
    my $q = $self->{'q'};

    if ( $q->param('output_format') =~ /tab/i )
    {
	return join "\t",@_;
    }
    
    else
    {
	foreach my $field (@_)
	{
	    $field =~ s/"/""/g;
	    $field = '"' . $field . '"' if $field =~ /[,"' \n]/;
	}
	 
	return join ',', @_;
    }
}

# renamed from getGenusNames to getTaxonString to reflect changes in how this works PS 01/06/2004
# Have to do a regex on the string it returns - $str =~ s/table\./\occurrences\./ or reids or whaetever
# Is a bit tricky cause of the exclusion.  If we're ONLY excluding taxa when we just do a NOT IN (xxx).
# If we're including taxa, we have to a set subtraction from the included taxa.  There can be multiple
# levels of nesting of Include(Exclude(Include))) so its a bit tricky.  The set subtraction happens
# in the getChildren function by passing in stuff to exclude.   
sub getTaxonString {
    my $self = shift;
    my $taxon_name = shift;
    my $exclude_taxon_name = shift;
    my $q = $self->{'q'};
    my $dbt = $self->{'dbt'};
    my $dbh = $self->{'dbh'};

    my @taxon_nos_unique;
    my $taxon_nos_string;
    my $genus_names_string;

    my @taxa = split(/\s*[, \t\n-:;]{1}\s*/,$taxon_name);
    my @exclude_taxa = split(/\s*[, \t\n-:;]{1}\s*/,$exclude_taxon_name);

    my (@sql_or_bits,@sql_and_bits);
    my %taxon_nos_unique = ();
    if (@taxa) {
        my @exclude_taxon_nos = ();
        foreach my $taxon (@exclude_taxa) {
            my @taxon_nos = PBDB::TaxonInfo::getTaxonNos($dbt,$taxon,'','lump');
            if (scalar(@taxon_nos) == 0) {
                push @sql_and_bits, "table.genus_name NOT LIKE ".$dbh->quote($taxon);
            } else	{
                push @exclude_taxon_nos, $taxon_nos[0];
            }
        }
        foreach my $taxon (@taxa) {
            my @taxon_nos = PBDB::TaxonInfo::getTaxonNos($dbt,$taxon,'','lump');
            if (scalar(@taxon_nos) == 0) {
                push @sql_or_bits, "table.genus_name LIKE ".$dbh->quote($taxon);
            } else	{
                my @all_taxon_nos = PBDB::TaxaCache::getChildren($dbt,$taxon_nos[0],'','',\@exclude_taxon_nos);
                # Uses hash slices to set the keys to be equal to unique taxon_nos.  Like a mathematical UNION.
                @taxon_nos_unique{@all_taxon_nos} = ();
            }
        }
        if (%taxon_nos_unique) {
            push @sql_or_bits, "table.taxon_no IN (".join(", ",keys(%taxon_nos_unique)).")";
        }
    } elsif (@exclude_taxa) {
        my @exclude_taxon_nos = ();
        foreach my $taxon (@exclude_taxa) {
            my @taxon_nos = PBDB::TaxonInfo::getTaxonNos($dbt,$taxon,'','lump');
            if (scalar(@taxon_nos) == 0) {
                push @sql_or_bits, "table.genus_name NOT LIKE ".$dbh->quote($taxon);
            } else	{
                push @exclude_taxon_nos, $taxon_nos[0];
                my @all_taxon_nos = PBDB::TaxaCache::getChildren($dbt,$taxon_nos[0],'','',\@exclude_taxon_nos);
                # Uses hash slices to set the keys to be equal to unique taxon_nos.  Like a mathematical UNION.
                @taxon_nos_unique{@all_taxon_nos} = ();
            }
        }
        if (%taxon_nos_unique) {
            push @sql_or_bits, "table.taxon_no NOT IN (".join(", ",keys(%taxon_nos_unique)).")";
        }
    }
    my $sql = "";
    if (@sql_or_bits > 1) {
        $sql = "(".join(" OR ",@sql_or_bits).")"; 
    } elsif (@sql_or_bits == 1) {
        $sql = $sql_or_bits[0];
    }
    $sql = join " AND ", $sql , @sql_and_bits;

    return $sql;
}

sub dbg {
    my $self = shift;
    my $message = shift;
    
    # if ( $DEBUG && $message ) { print "<font color='green'>$message</font><br>\n"; }

    if ( $DEBUG && $message ) { print STDERR "DEBUG: $message\n"; }
    
    return $DEBUG;                    # Either way, return the current DEBUG value
}

1;
