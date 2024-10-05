package PBDB::TimeLookup;

# use Data::Dumper;
use Carp qw(carp croak);
use strict;

# Ten million year bins, in order from oldest to youngest
@TimeLookup::bins = ("Cenozoic 6", "Cenozoic 5", "Cenozoic 4", "Cenozoic 3", "Cenozoic 2", "Cenozoic 1", "Cretaceous 8", "Cretaceous 7", "Cretaceous 6", "Cretaceous 5", "Cretaceous 4", "Cretaceous 3", "Cretaceous 2", "Cretaceous 1", "Jurassic 6", "Jurassic 5", "Jurassic 4", "Jurassic 3", "Jurassic 2", "Jurassic 1", "Triassic 4", "Triassic 3", "Triassic 2", "Triassic 1", "Permian 4", "Permian 3", "Permian 2", "Permian 1", "Carboniferous 5", "Carboniferous 4", "Carboniferous 3", "Carboniferous 2", "Carboniferous 1", "Devonian 5", "Devonian 4", "Devonian 3", "Devonian 2", "Devonian 1", "Silurian 2", "Silurian 1", "Ordovician 5", "Ordovician 4", "Ordovician 3", "Ordovician 2", "Ordovician 1", "Cambrian 4", "Cambrian 3", "Cambrian 2", "Cambrian 1");

my %isBin;
$isBin{$_}++ foreach @TimeLookup::bins;

%TimeLookup::binning = (
    "33" => "Cenozoic 6", # Pleistocene
    "34" => "Cenozoic 6", # Pliocene
    "83" => "Cenozoic 6", # Late Miocene
    "84" => "Cenozoic 5", # Middle Miocene
    "85" => "Cenozoic 5", # Early Miocene
    "36" => "Cenozoic 4", # Oligocene
    "88" => "Cenozoic 3", # Late Eocene
    "107" => "Cenozoic 3", # Bartonian
    "108" => "Cenozoic 2", # Lutetian
    "90" => "Cenozoic 2", # Early Eocene
    "38" => "Cenozoic 1", # Paleocene
    "112" => "Cretaceous 8", # Maastrichtian
    "113" => "Cretaceous 7", # Campanian
    "114" => "Cretaceous 6", # Santonian
    "115" => "Cretaceous 6", # Coniacian
    "116" => "Cretaceous 6", # Turonian
    "117" => "Cretaceous 5", # Cenomanian
    "118" => "Cretaceous 4", # Albian
    "119" => "Cretaceous 3", # Aptian
    "120" => "Cretaceous 2", # Barremian
    "121" => "Cretaceous 2", # Hauterivian
    "122" => "Cretaceous 1", # Valanginian
    "123" => "Cretaceous 1", # Berriasian
    "124" => "Jurassic 6", # Tithonian
    "125" => "Jurassic 5", # Kimmeridgian
    "126" => "Jurassic 5", # Oxfordian
    "127" => "Jurassic 5", # Callovian
    "128" => "Jurassic 4", # Bathonian
    "129" => "Jurassic 4", # Bajocian
    "130" => "Jurassic 3", # Aalenian
    "131" => "Jurassic 3", # Toarcian
    "132" => "Jurassic 2", # Pliensbachian
    "133" => "Jurassic 1", # Sinemurian
    "134" => "Jurassic 1", # Hettangian
# used from 19.3.05
    "135" => "Triassic 4", # Rhaetian
    "136" => "Triassic 4", # Norian
    "137" => "Triassic 3", # Carnian
    "45" => "Triassic 2", # Middle Triassic
# used up to 19.3.05
#	"135" => "Triassic 5", # Rhaetian
#	"136" => "Triassic 5", # Norian
#	"137" => "Triassic 4", # Carnian
#	"138" => "Triassic 3", # Ladinian
#	"139" => "Triassic 2", # Anisian
# used up to 17.8.04
#	"136" => "Triassic 4", # Norian
#	"137" => "Triassic 3", # Carnian
#	"138" => "Triassic 2", # Ladinian
#	"139" => "Triassic 1", # Anisian
    "46" => "Triassic 1", # Early Triassic
    "143" => "Permian 4", # Changxingian
    "715" => "Permian 4", # Changhsingian
# used up to 16.8.04
#	"715" => "Permian 5", # Changhsingian
    "716" => "Permian 4", # Wuchiapingian
    "145" => "Permian 3", # Capitanian
# used up to 16.8.04
#	"145" => "Permian 4", # Capitanian
    "146" => "Permian 3", # Wordian
    "717" => "Permian 3", # Roadian
    "148" => "Permian 2", # Kungurian
    "149" => "Permian 2", # Artinskian
    "150" => "Permian 1", # Sakmarian
    "151" => "Permian 1", # Asselian
# used up to 9.8.04, reverted back to 17.8.04
    "49" => "Carboniferous 5", # Gzelian
    "50" => "Carboniferous 5", # Kasimovian
    "51" => "Carboniferous 4", # Moscovian
# used up to 17.8.04
#	"51" => "Carboniferous 5", # Moscovian
    "52" => "Carboniferous 4", # Bashkirian
# used up to 6.11.06
#    "166" => "Carboniferous 3", # Alportian
#    "167" => "Carboniferous 3", # Chokierian
# used up to 9.8.04
#	"166" => "Carboniferous 4", # Alportian
#	"167" => "Carboniferous 4", # Chokierian
# Serpukhovian added 29.6.06
    "53" => "Carboniferous 3", # Serpukhovian
    "168" => "Carboniferous 3", # Arnsbergian
    "169" => "Carboniferous 3", # Pendleian
    "170" => "Carboniferous 3", # Brigantian
    "171" => "Carboniferous 2", # Asbian
    "172" => "Carboniferous 2", # Holkerian
    "173" => "Carboniferous 2", # Arundian
    "174" => "Carboniferous 2", # Chadian
    "55" => "Carboniferous 1", # Tournaisian
    "177" => "Devonian 5", # Famennian
    "178" => "Devonian 4", # Frasnian
    "57" => "Devonian 3", # Middle Devonian
    "181" => "Devonian 2", # Emsian
    "182" => "Devonian 1", # Pragian
    "183" => "Devonian 1", # Lochkovian
    "59" => "Silurian 2", # Pridoli
    "60" => "Silurian 2", # Ludlow
    "61" => "Silurian 2", # Wenlock
    "62" => "Silurian 1", # Llandovery
    "638" => "Ordovician 5", # Ashgillian
# added 8.6.06
    "63" => "Ordovician 5", # Ashgill
# added 29.6.06
    "192" => "Ordovician 5", # Hirnantian
    "639" => "Ordovician 4", # Caradocian
# added 8.6.06
    "64" => "Ordovician 4", # Caradoc
# added 29.6.06
    "787" => "Ordovician 4", # early Late Ordovician
# now spans bins 3 and 4
#    "65" => "Ordovician 3", # Llandeilo
    "66" => "Ordovician 3", # Llanvirn
# used up to 15.8.04
#	"30" => "Ordovician 3", # Middle Ordovician
    "596" => "Ordovician 2", # Arenigian
# added 8.6.06
    "67" => "Ordovician 2", # Arenig
# added 29.6.06
    "789" => "Ordovician 2", # late Early Ordovician
# used up to 15.8.04
#	"641" => "Ordovician 2", # Latorpian
    "559" => "Ordovician 1", # Tremadocian
# added 8.6.06
    "68" => "Ordovician 1", # Tremadoc
    "69" => "Cambrian 4", # Merioneth
# added 29.6.06
    "780" => "Cambrian 4", #  Furongian
    "70" => "Cambrian 3", # St David's
# added 29.6.06
    "781" => "Cambrian 3", # Middle Cambrian
    "71" => "Cambrian 2", # Caerfai
# next four added 29.6.06
    "749" => "Cambrian 2", # Toyonian
    "750" => "Cambrian 2", # Botomian
    "213" => "Cambrian 2", # Atdabanian
    "214" => "Cambrian 2", # Tommotian
    "748" => "Cambrian 1", # Manykaian
# added 29.6.06
    "799" => "Cambrian 1" # Nemakit-Daldynian
);

@TimeLookup::FR2_bins = ("Pleistocene","Pliocene","Upper Miocene","Middle Miocene","Lower Miocene","Chattian","Rupelian","Priabonian","Bartonian","Lutetian","Ypresian","Thanetian","Danian","Maastrichtian","Campanian","Santonian","Coniacian","Turonian","Cenomanian","Albian","Aptian","Barremian","Hauterivian","Valanginian","Berriasian","Portlandian","Kimmeridgian","Oxfordian","Callovian","Bathonian","Bajocian","Aalenian","Toarcian","Pliensbachian","Sinemurian","Hettangian","Rhaetian","Norian","Carnian","Ladinian","Anisian","Scythian","Tatarian","Kazanian","Kungurian","Artinskian","Sakmarian","Asselian","Gzelian","Kasimovian","Moscovian","Bashkirian","Serpukhovian","Visean","Tournaisian","Famennian","Frasnian","Givetian","Eifelian","Emsian","Pragian","Lochkovian","Pridoli","Ludlow","Wenlock","Llandovery","Ashgill","Caradoc","Llanvirn","Arenig","Tremadoc","Merioneth","St Davids","Caerfai","Vendian");

my %isFR2Bin;
$isFR2Bin{$_}++ foreach @TimeLookup::FR2_bins;

%TimeLookup::FR2_binning = (
	"23" => "Vendian",
	"782" => "Caerfai", # equated with the entire Early Cambrian
	"70" => "St Davids",
	"69" => "Merioneth",
	"68" => "Tremadoc",
	"67" => "Arenig",
	"66" => "Llanvirn",
	"65" => "Llanvirn", # former Llandeilo, no longer valid
	"64" => "Caradoc",
	"63" => "Ashgill",
	"62" => "Llandovery",
	"61" => "Wenlock",
	"60" => "Ludlow",
	"59" => "Pridoli",
	"183" => "Lochkovian",
	"182" => "Pragian",
	"181" => "Emsian",
	"180" => "Eifelian",
	"179" => "Givetian",
	"178" => "Frasnian",
	"177" => "Famennian",
	"55" => "Tournaisian",
	"54" => "Visean",
	"53" => "Serpukhovian",
	"52" => "Bashkirian",
	"51" => "Moscovian",
	"50" => "Kasimovian",
	"49" => "Gzelian",
	"151" => "Asselian",
	"150" => "Sakmarian",
	"149" => "Artinskian",

# in the Permian, the FR2 time scale uses Russian time terms with very complex
#  relationships to the standard global time scale that are inferred from the
#  following:

# Sennikov and Golubev 2006:
# Ufimian (post-Kungurian) = latest Cisuralian (LM)
# Kazanian = Biarmian
# Urzhumian = Biarmian
# Severodvinian = Tatarian
# Vjatkian = Tatarian

# Leonova 2007:
# Kungurian = pre-Roadian = latest LM
# Ufimian = synonym or part of Kungurian (or possibly straddles boundary)
# Kazanian = Roadian
# Tatarian = Wordian and remaining Permian

# Taylor et al. 2009:
# Urzhumian = Tatarian = mid-Capitanian (and earlier?)
# Severodovinian = Tatarian = late Capitanian + most of the Wuchiapingian
# Vyatkian = Tatarian = latest Wuchiapingian + Changhsingian

# composite:
# Kungurian (includes Ufimian)
# Kazanian = Roadian
# Urzhumian = Tatarian = Wordian + early Capitanian [inferred]
# Severodovinian = Tatarian = late Capitanian + most of the Wuchiapingian
# Vjatkian = Tatarian = latest Wuchiapingian + Changhsingian

# Fossil Record 2:
# Kungurian
# Ufimian (invalid)
# Kazanian
# (Urzhumian omitted)
# Tatarian

	"148" => "Kungurian", # Kungurian proper
	"147" => "Kungurian", # Ufimian
	"905" => "Kazanian", # Kazanian proper
	"717" => "Kazanian", # Roadian
	"904" => "Tatarian", # Tatarian proper
	"146" => "Tatarian", # Wordian, assuming Urzhumian falls in FR2's "Tatarian"
	"145" => "Tatarian", # Capitanian, with same assumption
	"771" => "Tatarian", # Lopingian

	# Scythian equals Early Triassic
	"46" => "Scythian",
	"139" => "Anisian",
	"138" => "Ladinian",
	"137" => "Carnian",
	"136" => "Norian",
	"135" => "Rhaetian",
	"134" => "Hettangian",
	"133" => "Sinemurian",
	"132" => "Pliensbachian",
	"131" => "Toarcian",
	"130" => "Aalenian",
	"129" => "Bajocian",
	"128" => "Bathonian",
	"127" => "Callovian",
	"126" => "Oxfordian",
	"125" => "Kimmeridgian",
	# equals Tithonian
	"124" => "Portlandian",
	"123" => "Berriasian",
	"122" => "Valanginian",
	"121" => "Hauterivian",
	"120" => "Barremian",
	"119" => "Aptian",
	"118" => "Albian",
	"117" => "Cenomanian",
	"116" => "Turonian",
	"115" => "Coniacian",
	"114" => "Santonian",
	"113" => "Campanian",
	"112" => "Maastrichtian",
	"111" => "Danian",
	# Selandian included in Benton's Thanetian based on Harland et al. 1989
	"743" => "Thanetian",
	"110" => "Thanetian",
	"109" => "Ypresian",
	"108" => "Lutetian",
	"107" => "Bartonian",
	"106" => "Priabonian",
	"105" => "Rupelian",
	"104" => "Chattian",
	"85" => "Lower Miocene",
	"84" => "Middle Miocene",
	"83" => "Upper Miocene",
	"34" => "Pliocene",
	"33" => "Pleistocene"
);

%TimeLookup::rank_order = (
    'eon/eonothem' => 1,
    'era/erathem' => 2,
    'period/system' => 3,
    'subperiod/system' =>4,
    'epoch/series' =>5,
    'subepoch/series' =>6,
    'age/stage' =>7,
    'subage/stage' =>8,
    'chron/zone' =>9
);

sub getBins {
    return @TimeLookup::bins;
}

sub getFR2Bins {
    return @TimeLookup::FR2_bins;
}

sub getBinning {
    return \%TimeLookup::binning;
}

sub new {
    my $c = shift;
    my $dbt = shift;

    my $self  = {'ig'=>undef,'dbt'=>$dbt,'set_boundaries'=>0, 'sl'=>{},'il'=>{}};
    bless $self,$c;
}

# JA 9.3.12
# super-simple function that replaces Schroeter's epic getIntervalGraph
sub allIntervals	{
	my $dbt = shift;
	my %intervals;
	my $sql = "SELECT IF((eml_interval IS NOT NULL AND eml_interval!=''),CONCAT(i.eml_interval,' ',i.interval_name),i.interval_name) AS name,il.* FROM intervals i,interval_lookup il WHERE i.interval_no=il.interval_no";
	$intervals{$_->{'interval_no'}} = $_ foreach @{$dbt->getData($sql)};
	return %intervals;
}

# Convenience
# JA: this one and the subtended functions getRangeByBoundary and
#  getRangeByInterval are actually pretty important
sub getRange {
    my $self = shift;
    my ($eml_max,$max,$eml_min,$min,%options) = @_;
    if ($max =~ /^[0-9.]+$/ || $min =~ /^[0-9.]+$/) {
        return $self->getRangeByBoundary($max,$min,%options),[],[];
    } else {
        return $self->getRangeByInterval(@_);
        
    }
}


# JA: this one is only ever used by FossilRecord::submitSearchTaxaForm,
#  so it's more or less obsolete and certainly way too complicated because
#  the hashes should be computable straight off of interval_lookup

# Pass in a range of intervals and this populates and passes back four hashes
# %pre hash has intervals that come before the range (including overlapping with part of the range)
# %post has intervals that come after the range (including overlapping with part of the range)
# %range has intervals in the range passed in
# %unknown has intervals  we dont' know what to do with, which are mostly larger intervals
#   that span both before and after the range of intervals
sub getCompleteRange {
    my ($self,$intervals) = @_;
    my (%pre,%range,%post,%unknown);

# disabled this for now pending rewrite of this function (if ever needed)
# JA 9.3.12
    my $ig; # = $self->getIntervalGraph();
    foreach my $i (@$intervals) {
        $range{$i} = $ig->{$i};
    }

    my $i = $intervals->[0];
    if ($i) {
        my $first_itv = $ig->{$i};
        while (my ($i,$itv) = each %$ig) {
            $itv->{'visited'} = 0;
        }
        $self->{precedes_lb} = {}; 
        #$self->markPrecedesLB($ig,$first_itv,0);
        
        while (my ($i,$itv) = each %$ig) {
            $itv->{'visited'} = 0;
        }
        $self->{follows_ub} = {};
        #$self->markFollowsUB($ig,$first_itv,0);

        foreach my $post_no (keys %{$self->{precedes_lb}{$i}}) {
            if (!$range{$post_no}) {
                $post{$post_no} = $ig->{$post_no};
            }
        }
        foreach my $pre_no (keys %{$self->{follows_ub}{$i}}) {
            if (!$range{$pre_no} && !$post{$pre_no}) {
                $pre{$pre_no} = $ig->{$pre_no};
            }
        }
    }
    while (my ($i,$itv) = each %$ig) {
        if (!$range{$i} && !$pre{$i} && !$post{$i}) {
            $unknown{$i} = $itv;
        }
    }
    return (\%pre,\%range,\%post,\%unknown);
}

# old Schroeter function that finds all intervals falling within a range
#  of Ma values
# heavily rewritten to take advantage of allIntervals by JA 9.3.12
sub getRangeByBoundary {
    my $self = shift;
    my ($max,$min,%options) = @_;
    my %intervals = allIntervals($self->{dbt});

    if ($max !~ /^[0-9]*\.?[0-9]+$/) {
        $max = 9999;
    }
    if ($min !~ /^[0-9]*\.?[0-9]+$/) {
        $min = 0;
    }
    if ($min > $max) {
        ($max,$min) = ($min,$max);
    }

    my @interval_nos;
    for my $no ( keys %intervals )	{
        if ( $options{'use_mid'} )	{
            my $mid = ( $intervals{$no}->{'base_age'} + $intervals{$no}->{'top_age'} ) / 2;
            if ($min <= $mid && $mid <= $max)	{
                push @interval_nos , $no;
            }
        } elsif ( $min <= $intervals{$no}->{'top_age'} && $max >= $intervals{$no}->{'base_age'} )	{
            push @interval_nos , $no;
        }
    }

    return \@interval_nos;
}

# You can pass in a 10 million year bin or an eml/interval pair
sub getRangeByInterval {
    my $self = shift;
    my $dbt = $self->{'dbt'};

    my ($eml_max,$max,$eml_min,$min,%options) = @_;
    
    $eml_max = 'Late/Upper' if $eml_max eq 'Late';
    $eml_max = 'Early/Lower' if $eml_max eq 'Early';
    $eml_min = 'Late/Upper' if $eml_min eq 'Late';
    $eml_min = 'Early/Lower' if $eml_min eq 'Early';
    
    my @errors = ();
    my @warnings = ();

    if (! $min) {
        $eml_min = $eml_max;
        $min = $max;
    }
    if (! $max) {
        $eml_max = $eml_min;
        $max = $min;
    }
    my @intervals;
    if ($max =~ /^[A-Z][a-z]+ \d$/ || $min =~ /^[A-Z][a-z]+ \d$/)	{
        # 10 M.Y. binning - i.e. Triassic 2
        my ($index1,$index2) = (-1,-1);
        for(my $i=0;$i<scalar(@TimeLookup::bins);$i++) {
            if ($max eq $TimeLookup::bins[$i]) {
                $index1 = $i;
            }
            if ($min eq $TimeLookup::bins[$i]) {
                $index2 = $i;
            }
        }

        if ($index1 < 0) {
            return ([],["Term $max not valid or not in the database"]);
        } elsif ($index2 < 0) {
            return ([],["Term $min not valid or not in the database"]);
        } else {
            if ($index1 > $index2) {
                ($index1,$index2) = ($index2,$index1);
            }
            @intervals = $self->mapIntervals(@TimeLookup::bins[$index1 .. $index2]);
        }
    } else {
        my ($max_interval_no,$min_interval_no);
        if ($max =~ /^\d+$/) {
            $max_interval_no = $max;
        } else {
            $max_interval_no = $self->getIntervalNo($eml_max,$max);
            my $max_name = $eml_max ? "$eml_max $max" : $max;
            if (!$max_interval_no) {
                push @errors, qq/The term "$max_name" not valid or not in the database/;
            }
        }
        if ($min =~ /^\d+$/) {
            $min_interval_no = $min;
        } else {
            $min_interval_no = $self->getIntervalNo($eml_min,$min);
            my $min_name = $eml_min ? "$eml_min $min" : $min;
            if (!$min_interval_no) {
                push @errors, qq/The term "$min_name" not valid or not in the database/;
            }
        }
   
        # if numbers weren't found for either interval, bomb out!
        if (@errors) {
            return ([],\@errors,\@warnings);
        }
       
        @intervals = $self->mapIntervals($max_interval_no,$min_interval_no);

    }
    return (\@intervals,\@errors,\@warnings);
}


# JA: only ever used by generateLookupTable in this module but used
#  repeatedly elsewhere, so it really needs to be looked over

# You can pass in both an integer corresponding to the scale_no of the scale or
# the keyword "bins" correspdoning to 10 my bins. Passes back a hashref where
# the key => value pair is the mapping. If $return_type is "name" the "value"
# will be the interval name, else it will be the interval_no.  For bins, it'll be the bin name always
# I.E.:  $hashref = $t->getScaleMapping('bins'), $hashref = $t->getScaleMapping(69,'name');
sub getScaleMapping {
    my $self = shift;
    my $dbt = $self->{'dbt'};

    my $scale = shift;
    my $return_type = shift || "number";

    # first retrieve a list of (parent) interval_nos included in the scale

    # This bins thing is slightly tricky - if the keyword "bins" is passed
    # in, then map to bins
    my @intervals;
    if ($scale =~ /bin/ && $scale !~ /fossil/i) {
        @intervals = @TimeLookup::bins;
    } elsif ($scale =~ /fossil/i) {
        @intervals = @TimeLookup::FR2_bins;
    } else {
        my $scale = int($scale);
        return unless $scale;
        my $sql = "SELECT interval_no FROM correlations WHERE scale_no=$scale";
        @intervals = map {$_->{'interval_no'}} @{$dbt->getData($sql)};
    }

    my %mapping = ();

    foreach my $i (@intervals) {
        # Map intervals accepts both 10 my bins and integers
        my @mapped = $self->mapIntervals($i);
        foreach my $j (@mapped) {
            $mapping{$j} = $i;
        }
    } 
   
    # If $scale is "bins" then the return type is always going
    # to be the name of the bin, so don't change anything
    if ($return_type =~ /name/ && $scale !~ /bin/) {
        # Return interval_no => interval_name mapping
        my %intervals = allIntervals($dbt);
        $mapping{$_} = $intervals{$mapping{$_}}->{'name'} foreach keys %intervals;
    } # Else default is to return interval_no => interval_no
    return \%mapping;
}


sub getBoundaries {
    my $self = shift;
    my $dbt = $self->{dbt};

    my %ub = ();
    my %lb = ();

    my $sql = "SELECT interval_no,top_age,base_age FROM interval_lookup";
    my @results = @{$dbt->getData($sql)};
    foreach my $row (@results) {
        $ub{$row->{interval_no}} = $row->{top_age};
        $lb{$row->{interval_no}} = $row->{base_age};
    }

    return (\%ub,\%lb);
}


sub getIntervalNo {
    my $self = shift;
    my $dbt;
    if ($self->isa('DBTransactionManager')) {
        $dbt = $self;
    } else {
        $dbt = $self->{'dbt'};
    }
    my $dbh = $dbt->dbh;

    my $eml = shift;
    my $name = shift;

    my $sql = "SELECT interval_no FROM intervals ".
              " WHERE interval_name=".$dbh->quote($name);
    if ($eml) {
        $sql .= " AND eml_interval=".$dbh->quote($eml);
    } else {
        $sql .= " AND (eml_interval IS NULL or eml_interval='')";
    }
              
    my $row = ${$dbt->getData($sql)}[0];
    if ($row) {
        return $row->{'interval_no'};
    } else {
        return undef;
    }
}


# Utility function, parse input from form into valid eml+interval name pair, if possible
# Can be called directly or in obj oriented fashion, which is what the shift is for
sub splitInterval {
    shift if ref $_[0];
    my $interval_name = shift;

    my @terms = split(/ /,$interval_name);
    my @eml_terms;
    my @interval_terms;
    foreach my $term (@terms) {
        if ($term =~ /e\.|l\.|m\.|early|lower|middle|late|upper/i) {
            push @eml_terms, $term;
        } else {
            push @interval_terms, $term;
        }
    }
    my $interval = join(" ",@interval_terms);
    $interval =~ s/^\s*//;
    $interval =~ s/\s*$//;

    my $eml;
    if (scalar(@eml_terms) == 1) {
        $eml = 'Early/Lower' if ($eml_terms[0] =~ /e\.|lower|early/i);
        $eml = 'Late/Upper' if ($eml_terms[0] =~ /l\.|late|upper/i);
        $eml = 'Middle' if ($eml_terms[0] =~ /m\.|middle/i);
    } elsif(scalar(@eml_terms) > 1) {
        my ($eml0, $eml1);
        $eml0 = 'early'  if ($eml_terms[0] =~ /e\.|early|lower/i);
        $eml0 = 'middle' if ($eml_terms[0] =~ /m\.|middle/i);
        $eml0 = 'late'   if ($eml_terms[0] =~ /l\.|late|upper/i);
        $eml1 = 'Early'  if ($eml_terms[1] =~ /e\.|early|lower/i);
        $eml1 = 'Middle' if ($eml_terms[1] =~ /m\.|middle/i);
        $eml1 = 'Late'   if ($eml_terms[1] =~ /l\.|late|upper/i);
        if ($eml0 && $eml1) {
            $eml = $eml0.' '.$eml1;
        }
    }

    return ($eml,$interval);
}

# Returns an array of interval names in the correct order for a given scale
# With the newest interval first -- not finished yet, don't use
# PS 02/28/3004
# JA: actually, this function seems to work OK and is used heavily elsewhere
sub getScaleOrder {
    my $self = shift;
    my $dbt = $self->{'dbt'};
    my $dbh = $dbt->dbh;
    
    my $scale_no = shift;
    my $return_type = shift || "name"; #name or number

    my @scale_list = ();

    my $count;
    my @results;
    my %next_i;
    if ($return_type  =~ /number/) {
        my $sql = "SELECT c.correlation_no, c.base_age, c.interval_no, c.next_interval_no FROM correlations c".
                  " WHERE c.scale_no=".$dbt->dbh->quote($scale_no);
        @results = @{$dbt->getData($sql)};
    } else {
        my $sql = "SELECT c.correlation_no, c.base_age, c.interval_no, c.next_interval_no, i.eml_interval, i.interval_name FROM correlations c, intervals i".
                  " WHERE c.interval_no=i.interval_no".
                  " AND c.scale_no=".$dbt->dbh->quote($scale_no);
        @results = @{$dbt->getData($sql)};
    }
    my %ints;
    my %nexts;
    foreach my $row (@results) {
        $ints{$row->{'interval_no'}} = $row;
        $nexts{$row->{'next_interval_no'}} = 1;
    }
    my @base_intervals;
    foreach my $row (@results) {
        if (!$nexts{$row->{'interval_no'}}) {
            push @base_intervals,$row->{'interval_no'};
        }
    }
    @base_intervals = sort {
        $ints{$b}->{'base_age'} <=> $ints{$a}->{'base_age'} ||
        $ints{$b}->{'correlation_no'} <=> $ints{$a}->{'correlation_no'}
    } @base_intervals;
    my @intervals;
    foreach my $base (@base_intervals) {
        my $i = $base;
        while (my $interval = $ints{$i}) {
            push @intervals, $interval;
            $i = $interval->{'next_interval_no'};
        }
    }

    foreach my $row (reverse @intervals) {
        if ($return_type =~ /number/) {
            push @scale_list, $row->{'interval_no'};
        } else {
            if ($row->{'eml_interval'}) {
                push @scale_list, $row->{'eml_interval'} . ' ' .$row->{'interval_name'};
            } else {
                push @scale_list, $row->{'interval_name'};
            }
        }
    }
        
    return @scale_list;
}

# JA: this is an old Schroeter function that is similar to allIntervals but
#  sorts out period, epoch, etc. interval names and is used by Collection
#  and Download, so it shouldn't be deprecated
sub lookupIntervals {
    my ($self,$intervals,$fields) = @_;
    my $dbt = $self->{'dbt'};
    
    my @fields = ('interval_name','period_name','epoch_name','stage_name','ten_my_bin','base_age','top_age');
    if ($fields) {
        @fields = @$fields;
    } 
    my @intervals = @$intervals;

    my @sql_fields;
    my @left_joins;
    foreach my $f (@fields) {
        if ($f eq 'interval_name') {
            push @sql_fields, "TRIM(CONCAT(i1.eml_interval,' ',i1.interval_name)) AS interval_name";
            push @left_joins, "LEFT JOIN intervals i1 ON il.interval_no=i1.interval_no";
        } elsif ($f eq 'period_name') {
            push @sql_fields, "TRIM(CONCAT(i2.eml_interval,' ',i2.interval_name)) AS period_name";
            push @left_joins, "LEFT JOIN intervals i2 ON il.period_no=i2.interval_no";
        } elsif ($f eq 'epoch_name') {
            push @sql_fields, "TRIM(CONCAT(i3.eml_interval,' ',i3.interval_name)) AS epoch_name";
            push @left_joins, "LEFT JOIN intervals i3 ON il.epoch_no=i3.interval_no";
        } elsif ($f eq 'subepoch_name') {
            push @sql_fields, "TRIM(CONCAT(i4.eml_interval,' ',i4.interval_name)) AS subepoch_name";
            push @left_joins, "LEFT JOIN intervals i4 ON il.subepoch_no=i4.interval_no";
        } elsif ($f eq 'stage_name') {
            push @sql_fields, "TRIM(CONCAT(i5.eml_interval,' ',i5.interval_name)) AS stage_name";
            push @left_joins, "LEFT JOIN intervals i5 ON il.stage_no=i5.interval_no";
        } else {
            push @sql_fields, 'il.'.$f;
        }
    }
   
    my $sql = "SELECT il.interval_no,".join(",",@sql_fields)." FROM interval_lookup il ".join(" ",@left_joins);
    if (@intervals) {
        $sql .= " WHERE il.interval_no IN (".join(", ",@intervals).")";
    }
    my @results = @{$dbt->getData($sql)};
    my %interval_table = ();
    foreach my $row (@results) {
        $interval_table{$row->{'interval_no'}} = $row;
    }

    return \%interval_table;
}

return 1;

