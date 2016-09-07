#!/usr/bin/perl

use strict;
use warnings;

open(IN, '< moduleList.txt');

my $err;

while(my $module = <IN>) {
    chop($module);
    $err = system("echo ------------ $module >> tofix.out");
    $err = system("grep -n $module *.pm >> tofix.out");
}
