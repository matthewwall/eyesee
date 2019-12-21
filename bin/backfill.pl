#!/usr/bin/perl
# Copyright 2013-2017 Matthew Wall
# Distributed under terms of the GPLv3
#
# create a thumbnail for each image we find

use File::Find;
use File::Basename;
use File::Spec::Functions qw(rel2abs);
use strict;

my $path = dirname(rel2abs($0));
require "$path/eyesee.pl";
our $verbose;
our $doit;

my $dir = '/var/eyesee';
my $tnheight = 50; # pixels
my $force = 0; # generate thumbnail even if one already exists
my $type = 'img'; # img or vid

while($ARGV[0]) {
    my $arg = shift;
    if ($arg eq '--dir') {
        $dir = shift;
    } elsif ($arg eq '--tn-height') {
        $tnheight = shift;
    } elsif ($arg eq '--type') {
        $type = shift;
    } elsif ($arg eq '--force') {
        $force = 1;
    } elsif ($arg eq '--debug') {
        $doit = 0;
    } elsif ($arg eq '--verbose') {
        $verbose = 1;
    }
}

my $ext = ($type eq 'vid') ? 'avi' : 'jpg';

my @files;
find ( sub {
    return unless -f;
    my $fn = $File::Find::name;
    return unless $fn =~ /\d.${ext}$/;
    push @files, $File::Find::name;
       }, $dir);

my $total = scalar @files;
my $success_cnt = 0;
my $fail_cnt = 0;
foreach my $f (@files) {
    my $tn = $f;
    $tn =~ s/.${ext}$/-tn.jpg/;
    if ($force && -f "$tn") {
        unlink "$tn";
    }
    if (! -f "$tn") {
        # generate thumbnail only if none already, or forced to regenerate
        my $cmd;
        if ($type eq 'vid') {
            # grab one frame and size to height we want
            # '-vframes 1' instead of '-t 1' ?
            $cmd = "ffmpeg -ss 0 -i $f -t 1 -s x${tnheight} -f image2 $tn";
        } else {
            # shrink to the required height
            $cmd = "convert $f -resize x${tnheight} $tn";
        }
        my($fail, $rc, $s) = docmd($cmd);
        if ($fail || $rc != 0) {
            $fail_cnt += 1;
        } else {
            $success_cnt += 1;
            # set the timestamp to match that of the original video
            my $mtime = (stat $f)[9];
            utime $mtime, $mtime, "$tn";
        }
    }
}
logmsg("generated $success_cnt thumbnails ($total total, $fail_cnt failures)");

exit 0;



sub create_img_thumbnails {
    my($dir) = @_;

    my @files;
    find ( sub {
        return unless -f;
        my $fn = $File::Find::name;
        return unless $fn =~ /\d.jpg$/;
        push @files, $File::Find::name;
           }, $dir);

    my $total = scalar @files;
    my $success_cnt = 0;
    my $fail_cnt = 0;
    foreach my $f (@files) {
        my $tn = $f;
        $tn =~ s/.jpg$/-tn.jpg/;
        if ($force && -f "$tn") {
            unlink "$tn";
        }
        if (! -f "$tn") {
            # generate thumbnail only if none already, or forced to regenerate
            my($fail, $rc, $s) = docmd("convert $f -resize x${tnheight} $tn");
            if ($fail || $rc != 0) {
                $fail_cnt += 1;
            } else {
                $success_cnt += 1;
                # set the timestamp to match that of the original image
                my $mtime = (stat $f)[9];
                utime $mtime, $mtime, "$tn";
            }
        }
    }
    logmsg("generated $success_cnt thumbnails for $total images ($fail_cnt failures)");
}
