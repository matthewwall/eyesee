#!/usr/bin/perl
# move image files into subdirectories
# Copyright 2013-2017 Matthew Wall
# Distributed under terms of the GPLv3
#
# create thumbnail then transfer it

use Cwd 'abs_path';
use File::Basename;
use File::Spec::Functions qw(rel2abs);
use Time::Local;
use strict;

my $path = dirname(rel2abs($0));
require "$path/eyesee.pl";
our $verbose;
our $doit;

my $dir = q();

my %cfg = get_cfg('/etc/eyesee/eyesee.cfg',
                  ('XFRIMG_TMPDIR', '/var/tmp',
                   'XFRIMG_BASEDIR', '/var/eyesee/img',
                   'XFRIMG_ID', q(),
                   'XFRIMG_LABEL', q(),
                   'XFRIMG_HOST', 'x.x.x.x',
                   'XFRIMG_DESTINATION', 'http://localhost/cgi-bin/rcvimg',
                   'XFRIMG_LAST_XFR', 'last-xfr',
                   'XFRIMG_MQTT_TELEMETRY_BROKER', 'localhost',
                   'XFRIMG_MQTT_PORT', '1883',
                   'XFRIMG_MQTT_TOPIC', 'cam/tn-upload',
                   'XFRIMG_MQTT_SEND', 0,
                  ));

while($ARGV[0]) {
    my $arg = shift;
    if ($arg eq '--debug') {
        $doit = 0;
    } elsif ($arg eq '--verbose') {
        $verbose = 1;
    } elsif ($arg eq '--dir') {
        $dir = shift;
    } elsif ($arg eq '--basedir') {
        $cfg{XFRIMG_BASEDIR} = shift;
    } elsif ($arg eq '--host') {
        $cfg{XFRIMG_HOST} = shift;
    } elsif ($arg eq '--label') {
        $cfg{XFRIMG_LABEL} = shift;
    } elsif($arg eq '--id') {
        $cfg{XFRIMG_ID} = shift;
    } elsif ($arg eq '--dest') {
        $cfg{XFRIMG_DESTINATION} = shift;
    }
}

%cfg = reduce_cfg($cfg{XFRIMG_HOST}, %cfg);

# provide feedback about the configuration
foreach my $k (sort keys %cfg) {
    logmsg("$k=$cfg{$k}");
}

my $TMPDIR = $cfg{XFRIMG_TMPDIR};
my $basedir = $cfg{XFRIMG_BASEDIR};
my $host = $cfg{XFRIMG_HOST};
my $label = $cfg{XFRIMG_ID} ? $cfg{XFRIMG_ID} : $cfg{XFRIMG_LABEL};
my $dest = $cfg{XFRIMG_DESTINATION};
my $lastxfrfn = $cfg{XFRIMG_LAST_XFR};

if ($label ne q()) {
    $dir = "$basedir/$label";
} else {
    $dir = "$basedir/$host";
}

# the filename in which to place timestamp of last upload
my $tsfn = "$dir/$lastxfrfn";

# get the image's timestamp to use as reference
my $fn = get_latest_file($dir);
if ($fn ne q()) {
    my $ts = get_ts($fn);
    my $last_ts = read_ts($tsfn);

    if ($last_ts < $ts) {
        my $src = "$TMPDIR/xfrimg_src_$$.jpg";

        # make a copy of the image for us to work on
        docmd("cp $fn $src");

        # create a shrunken version of the image
        my $tn = "$TMPDIR/xfrimg_tn_$$.jpg";
        docmd("convert $src -resize x150 $tn");

        # do the transfer
        my $labelstr = $label eq q() ? q() : "-F 'label=$label'";
        my ($fail, $rc, $sig) = docmd("curl -s -w %{http_code} $labelstr -F 'filename=$ts.jpg' -F 'thumbnail=\@$tn' -o /dev/null $dest > $src.code");
        my $code = `cat $src.code`;

        # save the timestamp after successful upload
        if ($rc == 0 && $code == 200) {
            write_ts($ts);
        }

        if ($cfg{XFRIMG_MQTT_SEND}) {
            my @t = $ts =~ m!(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})!;
            $t[1]--;
            my $epoch = timelocal @t[5,4,3,2,1,0];
            my $topic = $cfg{XFRIMG_MQTT_TOPIC};
            my $labelstr = $label eq q() ? q() :  "\"label\":\"$label\", ";
            my $msg = "{\"ts\":$epoch, \"filename\":\"$ts.jpg\", ${labelstr}\"fail\":$fail, \"rc\":$rc, \"signal\":$sig, \"code\":$code}";
            send_mqtt($cfg{XFRIMG_MQTT_TELEMETRY_BROKER},
                      $cfg{XFRIMG_MQTT_PORT},
                      $topic, $msg);
        }

        # clean up
        docmd("rm -f $src");
        docmd("rm -f $src.code");
        docmd("rm -f $tn");
    } else {
        logmsg("skipping image $fn (last:$last_ts latest:$ts)");
    }
} else {
    logmsg("cannot find latest.jpg in $dir");
}

exit 0;




# find the real path to the latest symlink
sub get_latest_file {
    my ($dir) = @_;
    my $fn = q();
    my $lfn = "$dir/latest.jpg";
    if ( -f $lfn && -l $lfn) {
        $fn = abs_path($lfn);
    }
    return $fn;
}

# get the timestamp of the latest image
sub get_ts {
    my ($fn) = @_;
    my $ts = 0;
    my ($digits) = $fn =~ /(\d+)\.jpg$/;
    if (length($digits) == 14) {
        $ts = $digits;
    }
    return $ts;
}

# save timestamp to disk.  format is single line.
sub read_ts {
    my $ts = 0;
    if (open(FILE, "<$tsfn")) {
        while(<FILE>) {
            if ($_ =~ /(\d+)/) {
                $ts = $1;
            }
        }
        close(FILE);
    } else {
        errmsg("cannot read timestamp from $tsfn: $!");
    }
    return $ts;
}

# read timestamp from disk.  format is single line.
sub write_ts {
    my ($ts) = @_;
    if (open(FILE, ">$tsfn")) {
        print FILE "$ts\n";
        close(FILE);
    } else {
        errmsg("cannot write timestamp to $tsfn: $!");
    }
}
