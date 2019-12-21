#!/usr/bin/perl
# Copyright 2013-2017 Matthew Wall
# Distributed under terms of the GPLv3

use Cwd 'abs_path';
use File::Basename;
use File::Spec::Functions qw(rel2abs);
use strict;

my $path = dirname(rel2abs($0));
require "$path/eyesee.pl";
our $verbose;
our $doit;

my %cfg = get_cfg('/etc/eyesee/eyesee.cfg',
                  ('REAPER_DIR', '/var/eyesee',
                   'REAPER_MAXAGE', 1
                  ));

while($ARGV[0]) {
    my $arg = shift;
    if ($arg eq '--debug') {
        $doit = 0;
    } elsif ($arg eq '--verbose') {
        $verbose = 1;
    } elsif ($arg eq '--dir') {
        $cfg{REAPER_DIR} = shift;
    } elsif ($arg eq '--maxage') {
        $cfg{REAPER_MAXAGE} = shift;
    }
}

my $dir = $cfg{REAPER_DIR};
my $maxage = $cfg{REAPER_MAXAGE}; # days

# figure out the latest file so we do not delete that one
my $latest = get_latest_file($dir);

# delete all of the old files
logmsg("finding files in $dir older than $maxage days");
my @files = `find $dir -type f -mtime +$maxage`;
foreach my $f (@files) {
    chomp($f);
    if ($f ne $latest) {
        docmd("rm $f");
    } else {
        logmsg("skipping latest file $f");
    }
}

# delete any remaining empty directories
logmsg("finding empty directories in $dir");
my @dirs = `find $dir -type d`;
foreach my $d (@dirs) {
    chomp($d);
    my $cnt = numfiles($d);
    if ($cnt == 0) {
        docmd("rmdir $d");
    }
}

exit 0;




sub numfiles {
    my $dirname = shift;
    my $cnt = -1;
    if (opendir(DIR, "$dirname")) {
        $cnt = scalar(grep { $_ ne "." && $_ ne ".." } readdir(DIR));
        closedir(DIR);
    } else {
        logmsg("cannot open directory $dirname: $!");
    }
    return $cnt;
}

# find the real path to the latest symlink
sub get_latest_file {
    my ($dir) = @_;
    my $fn = q();
    foreach my $lfn ("$dir/latest.jpg", "$dir/latest.avi") {
        if ( -f $lfn && -l $lfn) {
            $fn = abs_path($lfn);
        }
    }
    return $fn;
}
