#!/usr/bin/perl
# Copyright 2013-2021 Matthew Wall
# Distributed under terms of the GPLv3
#
# capture an image from a web camera
#
# one picture every 5 minutes at 30K per picture
#    288 images per day
# 105120 images per year
# 3.1GB storage for one year
#
# one picture every 2 seconds at 55kB per image
#   2.5GB per day
#    70GB per month
#
# one picture every 5 minutes at 10K to 15K per image
#      3K per day
#    100K per month
#
# take pictures only when sun is up - 45 minutes before sunrise and 45 minutes
# after sunset.
#
# in daemon mode, run continuously.
#
# images will be saved to the following directory structure:
#   /var/eyesee/img/
#   /var/eyesee/img/YYYYmmdd/YYYYmmddHHMMSS.jpg
#   /var/eyesee/img/YYYYmmdd/YYYYmmddHHMMSS.tn.jpg

use File::Basename;
use File::Spec::Functions qw(rel2abs);
use strict;

my $path = dirname(rel2abs($0));
require "$path/eyesee.pl";
our $verbose;
our $doit;

my $version = '0.32';
my $daemon = 0;                     # if non-zero, run as a daemon
my %cfg = get_cfg('/etc/eyesee/eyesee.cfg',
                  ('GETIMG_DAYONLY', 0,
                   'GETIMG_WAIT', 5,
                   'GETIMG_ID', q(),
                   'GETIMG_HOST', 'x.x.x.x',
                   'GETIMG_BASEDIR', '/var/eyesee/img',
                   'GETIMG_ODIR', q(),
                   'GETIMG_USER', 'guest',
                   'GETIMG_PASS', q(),
                   'GETIMG_USE_DIGEST', 0,
		   'GETIMG_CRED_PROTO', q(),
                   'GETIMG_DAYLIGHT_BUFFER', 45,
                   'GETIMG_LOC', q(),
                   'GETIMG_CTYPE', 'TV-IP110',
                   'GETIMG_TMPNAME', 'tmp',
                   'GETIMG_MAKE_THUMBNAIL', 1,
                   'GETIMG_THUMBNAIL_HEIGHT', 50,
                   'GETIMG_MQTT_TELEMETRY_BROKER', 'localhost',
                   'GETIMG_MQTT_PORT', '1883',
                   'GETIMG_MQTT_TOPIC', 'cam/img-capture',
                   'GETIMG_MQTT_SEND', 0,
                  ));

while($ARGV[0]) {
    my $arg = shift;
    if ($arg eq '--debug') {
        $doit = 0;
    } elsif ($arg eq '--verbose') {
        $verbose = 1;
    } elsif ($arg eq '--daemon') {
        $daemon = 1;
    } elsif ($arg eq '--daemon-wait') {
        $cfg{GETIMG_WAIT} = shift;
    } elsif ($arg eq '--id') {
        $cfg{GETIMG_ID} = shift;
    } elsif ($arg eq '--host') {
        $cfg{GETIMG_HOST} = shift;
    } elsif ($arg eq '--loc') {
        $cfg{GETIMG_LOC} = shift;
    } elsif ($arg eq '--odir') {
        $cfg{GETIMG_ODIR} = shift;
    } elsif ($arg eq '--user') {
        $cfg{GETIMG_USER} = shift;
    } elsif ($arg eq '--pass') {
        $cfg{GETIMG_PASS} = shift;
    } elsif ($arg eq '--cam') {
        $cfg{GETIMG_CTYPE} = shift;
    } elsif ($arg eq '--ignore-daylight' || $arg eq '--force') {
        $cfg{GETIMG_DAYONLY} = 0;
    } elsif ($arg eq '--daylight-only') {
        $cfg{GETIMG_DAYONLY} = 1;
    } elsif ($arg eq '--use-digest') {
        $cfg{GETIMG_USE_DIGEST} = 1;
    } elsif ($arg eq '--cred-proto') {
        my $p = shift;
	if ($p ne 'digest' && $p ne 'cgi') {
	    print "unrecognized credentials protocol '$p'\n";
	    exit 1;
	}
	$cfg{GETIMG_CRED_PROTO} = $p;
    } elsif ($arg eq '--version') {
	print "$version\n";
	exit 0;
    } elsif ($arg eq '--help') {
        print "options include:\n";
        print "  --verbose        # provide feedback\n";
        print "  --debug          # test run but no action\n";
        print "  --config FILE     # configuration file\n";
        print "  --daemon         # run as a daemon\n";
        print "  --daemon-wait N  # how long to wait between snaps, seconds\n";
        print "  --host HOST      # host name/address\n";
        print "  --loc LAT,LON    # lat,lon for calculating sunset\n";
        print "  --odir DIR       # where to save the files\n";
        print "  --user USERNAME  # username for getting images\n";
        print "  --pass PASSWORD  # password for user\n";
        print "  --cam CAM_TYPE   # camera type\n";
        print "  --cred-proto PROTO # protocol for auth: basic, digest, cgi\n";
        print "  --id ID          # identifier for the image source\n";
        exit 0;
    }
}

%cfg = reduce_cfg($cfg{GETIMG_HOST}, %cfg);

# backward copatibility for digest
if ($cfg{GETIMG_USE_DIGEST} && $cfg{GETIMG_CRED_PROTO} eq q()) {
    $cfg{GETIMG_CRED_PROTO} = 'digest';
}

# provide feedback about the configuration
foreach my $k (sort keys %cfg) {
    logmsg("$k=$cfg{$k}");
}

my $dayonly = $cfg{GETIMG_DAYONLY}; # take picture regardless of sunrise/sunset
my $wait = $cfg{GETIMG_WAIT};       # how often to take picture, seconds
my $host = $cfg{GETIMG_HOST};       # ip address of camera
my $id = $cfg{GETIMG_ID};           # identifier for the image source
my $basedir = $cfg{GETIMG_BASEDIR};
my $odir = $cfg{GETIMG_ODIR};
my $user = $cfg{GETIMG_USER};       # username for camera access
my $pass = $cfg{GETIMG_PASS};       # password for camera access
my $auth = $cfg{GETIMG_CRED_PROTO}; # how to format auth credentials
my $buffer = $cfg{GETIMG_DAYLIGHT_BUFFER}; # time before/after sunset, minutes
my $loc = $cfg{GETIMG_LOC};         # latitude,longitude
my $ctype = $cfg{GETIMG_CTYPE};     # camera type
my $tmpname = $cfg{GETIMG_TMPNAME};
my $mkthumb = $cfg{GETIMG_MAKE_THUMBNAIL};
my $tnheight = $cfg{GETIMG_THUMBNAIL_HEIGHT};

# figure out the URL based on the camera type
my %cameras = (
    'foscam-FI8905W',    "http://$host/snapshot.cgi",
    'trendnet-TVIP110',  "http://$host/cgi/jpg/image.cgi",
    'dlink-DCS900',      "http://$host/image.jpg",
    'dlink-DCS932',      "http://$host/image/jpeg.cgi",
    'dahua-HFW4300',     "http://$host:9989/",
    'dahua-HFW1320',     "http://$host/cgi-bin/snapshot.cgi",
    'mobotix',           "http://$host/record/current.jpg",
#    'mobotix',           "http://$host/cgi-bin/image.jpg",
    'hikvision',         "http://$host/Streaming/channels/1/picture",
    'hikvision2',        "http://$host/ISAPI/Streaming/channels/101/picture",
    'reolink',           "http://$host/cgi-bin/api.cgi?cmd=Snap&channel=0",
    );
my $img_url = q();
foreach my $c (keys %cameras) {
    if($c =~ /$ctype/) {
        $img_url = $cameras{$c};
    }
}
if($img_url eq q()) {
    errmsg("no camera found for type $ctype");
    exit 1;
}

# if no output directory specified, default to the basedir/id, or if no id
# specified default to basedir/host
if($odir eq q()) {
    if ($id ne q()) {
        $odir = "$basedir/$id";
    } else {
        $odir = "$basedir/$host";
    }
}
if(! -d $odir) {
    logmsg("creating directory $odir");
    docmd("mkdir -p $odir");
}
if(! -d $odir) {
    exit 1;
}

do {
    my $now = time;
    my $skip = 0;

    if ($dayonly) {
        my $fail = 0;
        eval { require DateTime; };
        if ($@) {
            errmsg("DateTime is not installed");
            $skip = 1;
            $fail = 1;
        }
        eval { require DateTime::Event::Sunrise; };
        if ($@) {
            errmsg("DateTime::Event::Sunrise is not installed");
            $skip = 1;
            $fail = 1;
        }
        if($loc eq q()) {
            errmsg("dayonly requested, but no lat/lon specified");
            $skip = 1;
            $fail = 1;
        }
        if (! $fail) {
            my($lat,$lon) = split(',', $loc);
            my $dt = DateTime->now();
            $dt->set_time_zone('local');
            my $s = DateTime::Event::Sunrise->new(longitude => $lon,
                                                  latitude => $lat);
            my $span = $s->sunrise_sunset_span($dt);
            my($y,$m,$d,$H,$M,$S) =
                $span->start->datetime =~ /(\d\d\d\d)-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)/;
            my $sr = DateTime->new(
                year => $y, month => $m, day => $d,
                hour => $H, minute => $M, second => $S,
                time_zone => 'local'
                );
            $sr->add(minutes => -$buffer);
            ($y,$m,$d,$H,$M,$S) =
                $span->end->datetime =~ /(\d\d\d\d)-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)/;
            my $ss = DateTime->new(
                year => $y, month => $m, day => $d,
                hour => $H, minute => $M, second => $S,
                time_zone => 'local'
                );
            $ss->add(minutes => $buffer);
            $span = DateTime::Span->from_datetimes(start => $sr, end => $ss);
            if (! $span->contains($dt)) {
                logmsg("skipping due to darkness (now=$dt sr=$sr ss=$ss)");
                $skip = 1;
            }
        }
    }

    if (! $skip) {
	my $authstr = q();
	my $authcgi = q();
        if ($user ne q()) {
            if ($auth eq 'digest') {
                $authstr = "-u $user:$pass --digest";
            } elsif ($auth eq 'cgi') {
                $authcgi = "&user=$user&password=$pass";
            } else {
                $authstr = "-u $user:$pass";
            }
        }
	# -s - silent mode
	# -S - show error even with -s
	# -w - use output format after completion
        my ($fail, $rc, $sig) = docmd("curl -s -S $authstr -w %{http_code} -o $odir/$tmpname '${img_url}${authcgi}' > $odir/$tmpname.code");
        my $code = `cat $odir/$tmpname.code`;
        # final filename is the timestamp
        my $ts = strftime("%Y%m%d%H%M%S", localtime($now));
        # be sure that curl executed properly and we got the right http return
        if ($fail == 0 && $rc == 0 && "$code" eq "200") {

            # keep images in one directory per day YYYYmmdd
            my($subdir) = $ts =~ /(\d\d\d\d\d\d\d\d)/;
            my $ofile = "$ts.jpg";

            # create the directory if it does not already exist
            if(! -d "$odir/$subdir") {
                logmsg("creating directory $odir/$subdir");
                docmd("mkdir -p $odir/$subdir");
            }

            docmd("mv $odir/$tmpname $odir/$subdir/$ofile");
            docmd("rm $odir/$tmpname.code");
            docmd("rm -f $odir/latest.jpg");
            docmd("ln -s $subdir/$ofile $odir/latest.jpg");

            # create a shrunken version of the image
            if ($mkthumb && -f "$odir/$subdir/$ofile") {
                my $tn = "$odir/$subdir/${ts}-tn.jpg";
                docmd("convert $odir/$subdir/$ofile -resize x${tnheight} $tn");
            }
        } else {
            errmsg("download failed: fail=$fail rc=$rc code=$code");
        }

        if ($cfg{GETIMG_MQTT_SEND}) {
            # ts is the name of the image (the time it was captured)
            # fail, rc, sig is the status of the upload attempt
            my $msg = "{\"ts\":$now, \"filename\":\"$ts.jpg\", \"fail\":$fail, \"rc\":$rc, \"signal\":$sig, \"code\":\"$code\"}";
            send_mqtt($cfg{GETIMG_MQTT_TELEMETRY_BROKER},
                      $cfg{GETIMG_MQTT_PORT},
                      $cfg{GETIMG_MQTT_TOPIC},
                      $msg);
        }
    }

    if ($daemon) {
        sleep($wait);
    }
} while($daemon);

exit 0;
