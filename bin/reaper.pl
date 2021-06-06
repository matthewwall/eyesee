#!/usr/bin/perl
# Copyright 2013-2021 Matthew Wall
# Distributed under terms of the GPLv3
#
# selectively delete videos and images

use Cwd 'abs_path';
use File::Basename;
use File::Spec::Functions qw(rel2abs);
use strict;

my $path = dirname(rel2abs($0));
require "$path/eyesee.pl";
our $verbose;
our $doit;

my $version = '0.23';
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
    } elsif ($arg eq '--version') {
        print "$version\n";
        exit 0;
    } elsif ($arg eq '--help') {
        print "options include:\n";
        print "  --verbose         # provide feedback\n";
        print "  --debug           # test run but no action\n";
        print "  --config FILE     # configuration file\n";
        print "  --dir DIRECTORY   # where to find the images and videos\n";
        print "  --maxage N        # delete files older than N days\n";
        exit 0;
    }
}

my $dir = $cfg{REAPER_DIR};
my $maxage = $cfg{REAPER_MAXAGE}; # days

# provide feedback about the configuration
foreach my $k (sort keys %cfg) {
    logmsg("$k=$cfg{$k}");
}

# figure out the latest file so we do not delete that one
my $latest = get_latest_file($dir);

# delete all of the old files
logmsg("finding files in $dir older than $maxage days");
my @files = `find $dir -type f -mtime +$maxage`;
my $deleted = 0;
foreach my $f (@files) {
    chomp($f);
    if ($f ne $latest) {
        docmd("rm $f");
        $deleted += 1;
    } else {
        logmsg("skipping latest file $f");
    }
}
logmsg("deleted $deleted files\n");

# delete any remaining empty directories
logmsg("finding empty directories in $dir");
my @dirs = `find $dir -type d`;
$deleted = 0;
foreach my $d (@dirs) {
    chomp($d);
    my $cnt = numfiles($d);
    if ($cnt == 0) {
        docmd("rmdir $d");
        $deleted += 1;
    }
}
logmsg("deleted $deleted directories\n");

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
