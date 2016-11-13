#!/usr/bin/perl
##############################################################################
# By BumbleBeeWare.com 2006
# Simple CAPTCHA using static premade images
# captcha.cgi
##############################################################################

# configuration
$tempdir = "/pathtoyourwww/captcha/temp";
$imagedir = "/pathtoyourwww/captcha/images";

##########################


# open image dir choose a random image
opendir IMGDIR, "$imagedir"; 
@allimgfiles = readdir IMGDIR;
	
#$totalimages = @allimgfiles;

# define each image
foreach $imgfile(@allimgfiles) {
	
	# count and use only the gif images
	if ($imgfile =~ /\.gif/i){
	$countimages++;
	$IMAGE{$countimages} = $imgfile;}
	}

# choose a random image	
$randomnumber = int rand ($countimages);
if ($randomnumber < 1){$randomnumber = 1;}

$randomimage = $IMAGE{$randomnumber};

# images are named the same as the random text
# remove the filetype extension so we have the text only
$imagetext = $randomimage;
$imagetext =~ s/\.gif//g; # remove .gif extension

# set to lower case for case insensitivity
$imagetext = lc($imagetext);

# get ip and create an id file with the text on the image
open (TMPDATA, ">$tempdir/$ENV{'REMOTE_ADDR'}");
print TMPDATA "$imagetext";
close TMPDATA;
chmod 0777, "$tempdir/$ENV{'REMOTE_ADDR'}";

# set date for cookie
$date = (time + 86400);
$expirecookie = gmtime($date);

# set a cookie with ip for any proxy servers used for image caching
print "set-cookie: checkme=$ENV{'REMOTE_ADDR'}; expires=$expirecookie\n";

# print the image to the page
print "Content-type: image/jpg\n";
print "\n";

open(IMAGE, "<$imagedir/$randomimage");
while (<IMAGE>)
{
        print $_;
}
close(IMAGE);