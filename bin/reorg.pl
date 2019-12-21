#!/usr/bin/perl
# move image files into subdirectories
# Copyright 2013-2017 Matthew Wall
# Distributed under terms of the GPLv3

use File::Find;
use File::Basename;
use File::Spec::Functions qw(rel2abs);
use strict;

my $path = dirname(rel2abs($0));
require "$path/eyesee.pl";
our $verbose;
our $doit;

my $srcdir = '/tmp';
my $dstdir = '/tmp';

while($ARGV[0]) {
    my $arg = shift;
    if ($arg eq '--srcdir') {
        $srcdir = shift;
    } elsif ($arg eq '--dstdir') {
        $dstdir = shift;
    } elsif ($arg eq '--debug') {
        $doit = 0;
    } elsif ($arg eq '--verbose') {
        $verbose = 1;
    }
}

logmsg("scanning $srcdir");
my @files;
find ( sub {
    return unless -f;
    my $fn = $File::Find::name;
    return unless $fn =~ /\d.avi$/ || $fn =~ /\d.mp4$/;
    push @files, $File::Find::name;
       }, $srcdir);

my $cnt = scalar @files;
logmsg("found $cnt files");
foreach my $f (@files) {
    my($fn) = $f =~ /([^\/]+)$/;
    my($subdir) = $fn =~ /^(\d\d\d\d\d\d\d\d)/;
    if($subdir ne "") {
        if(! -d $dstdir/$subdir) {
            docmd("mkdir $dstdir/$subdir");
        }
        docmd("mv $f $dstdir/$subdir/$fn");
    }
}

exit 0;
