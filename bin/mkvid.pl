#!/usr/bin/perl
# Copyright 2013-2017 Matthew Wall
# Distributed under terms of the GPLv3
#
# create movie from images

# typical movie size is around 2M for 640x480 at 10fps
#      1 movie per day
#    365 movies per year
#  730MB storage for one year

use File::Find;
use File::Basename;
use File::Spec::Functions qw(rel2abs);
use strict;

my $path = dirname(rel2abs($0));
require "$path/eyesee.pl";
our $verbose;
our $doit;

my %cfg = get_cfg('/etc/eyesee/eyesee.cfg',
                  ('MKVID_HOST', 'x.x.x.x',
                   'MKVID_ID', q(),
                   'MKVID_BASEDIR', '/var/eyesee',
                   'MKVID_TMPDIR', q(),
                   'MKVID_SRCDIR', q(),
                   'MKVID_BATCHDIR', q(),
                   'MKVID_ODIR', q(),
                   'MKVID_MAXAGE', 2*3600, # two hours
                   'MKVID_ENDTIME', -1,
                   'MKVID_ENCODER', 'ffmpeg',
                   'MKVID_FPS', 1,
                   'MKVID_MAKE_THUMBNAIL', 1,
                   'MKVID_THUMBNAIL_HEIGHT', 50,
                  ));

while($ARGV[0]) {
    my $arg = shift;
    if ($arg eq '--debug') {
        $doit = 0;
    } elsif ($arg eq '--verbose') {
        $verbose = 1;
    } elsif ($arg eq '--id') {
        $cfg{MKVID_ID} = shift;
    } elsif ($arg eq '--maxage') {
        $cfg{MKVID_MAXAGE} = shift;
    } elsif ($arg eq '--endtime') {
        $cfg{MKVID_ENDTIME} = shift;
    } elsif ($arg eq '--host') {
        $cfg{MKVID_HOST} = shift;
    } elsif ($arg eq '--srcdir') {
        $cfg{MKVID_SRCDIR} = shift;
    } elsif ($arg eq '--batchdir') {
        $cfg{MKVID_BATCHDIR} = shift;
    } elsif ($arg eq '--odir') {
        $cfg{MKVID_ODIR} = shift;
    } elsif ($arg eq '--tmpdir') {
        $cfg{MKVID_TMPDIR} = shift;
    }
}

%cfg = reduce_cfg($cfg{MKVID_HOST}, %cfg);

# provide feedback about the configuration
foreach my $k (sort keys %cfg) {
    logmsg("$k=$cfg{$k}");
}

my $host = $cfg{MKVID_HOST};
my $id = $cfg{MKVID_ID};             # identifier for the image source
my $basedir = $cfg{MKVID_BASEDIR};
my $tmpdir = $cfg{MKVID_TMPDIR};
my $srcdir = $cfg{MKVID_SRCDIR};     # single source for images
my $batchdir = $cfg{MKVID_BATCHDIR}; # scan every subdir for images
my $odir = $cfg{MKDIR_ODIR};
my $maxage = $cfg{MKVID_MAXAGE};     # seconds
my $endtime = $cfg{MKVID_ENDTIME};   # epoch, or -1 for now
my $encoder = $cfg{MKVID_ENCODER};
my $fps = $cfg{MKVID_FPS};
my $mkthumb = $cfg{MKVID_MAKE_THUMBNAIL};
my $tnheight = $cfg{MKVID_THUMBNAIL_HEIGHT};

$endtime = get_endtime($endtime);
my $tstmp = format_datetime($endtime);
logmsg("endtime: $tstmp");

if ($batchdir eq q()) {
    $id = $host if $id eq q();
    process_dir($endtime, $basedir, $id, $srcdir, $odir, $tmpdir);
} else {
    logmsg("reading $batchdir/img");
    if (opendir(DIR, "$batchdir/img")) {
        my @dirs = grep { $_ ne '.' && $_ ne '..' && -d "$batchdir/img/$_" && ! -l "$batchdir/img/$_" } readdir(DIR);
        closedir(DIR);
        foreach my $d (@dirs) {
            process_dir($endtime, "$batchdir", "$d", q(), q(), $tmpdir);
        }
    } else {
        logmsg("cannot read batch dir $batchdir: $!\n");
    }
}

exit 0;



sub process_dir {
    my($endtime, $basedir, $host, $srcdir, $odir, $tmpdir) = @_;

    if($srcdir eq q()) {
        $srcdir = "${basedir}/img/$host";
    }
    if($odir eq q()) {
        $odir = "${basedir}/vid/$host";
    }
    if($tmpdir eq q()) {
        $tmpdir = "/tmp/vid$$";
    }

    logmsg("basedir: $basedir");
    logmsg("srcdir: $srcdir");
    logmsg("dstdir: $odir");

    if(! -d $tmpdir) {
        logmsg("creating directory $tmpdir");
        docmd("mkdir -p $tmpdir");
    }

    logmsg("identifying files in $srcdir");
    #my $timearg = "-mmin -15"; # 15 minutes
    #    $timearg = "-daystart -mtime $daysago";
    #    $timearg = "-mmin -$minago";
    # copying files does not work properly when running as non-root user
    #docmd("find $srcdir $timearg -type f -exec cp -p {} $tmpdir \\;");
    # saving names to file works great for mencoder but not ffmpeg
    #my $images_fn = "$tmpdir/images.txt";
    #docmd("find $srcdir $timearg -type f > $images_fn");
    # using symlinks works for mencoder and ffmpeg, but File::Find might have
    # problems when root (cron) does a su to non-root user.
    my @files;
    my @subdirs;
    my $sod = get_startofday($endtime - $maxage);
    if (opendir DH, $srcdir) {
        my @children = grep { /^[^\.]/ && -d "$srcdir/$_" } readdir DH;
        closedir DH;
        foreach my $c (@children) {
            my($y,$m,$d) = $c =~ /(\d\d\d\d)(\d\d)(\d\d)/;
            if($y && $m && $d) {
                my $ts = timelocal(0,0,0,$d,$m-1,$y);
                if($ts >= $sod) {
                    push @subdirs, "$srcdir/$c";
#                    logmsg("using directory $c");
                } else {
#                    logmsg("skipped directory $c: outside time range");
                }
            } else {
#                logmsg("skipped directory $c");
            }
        }
    } else {
        logmsg("cannot read srcdir $srcdir: $!");
    }
    foreach my $subdir (@subdirs) {
        find ( sub {
            return unless -f;
            my $fn = $File::Find::name;
            return unless $fn =~ /\d.jpg$/;
            my $mtime = (stat $fn)[9];
            my $age = $endtime - $mtime;
            return unless $age < $maxage;
            push @files, $File::Find::name;
               }, $subdir);
    }
    my $tmpvb = $verbose;
    $verbose = 0;
    foreach my $f (@files) {
        docmd("ln -s $f $tmpdir");
    }
    $verbose = $tmpvb;
    my $cnt = scalar @files;
    logmsg("found $cnt files");

    if ($cnt > 0) {
        my $ts = strftime("%Y%m%d%H%M%S", localtime);
        my $ext = 'none';
        my $fn = 'untitled.$ext';
        my $fail = 0;
        chdir($tmpdir);

        my($subdir) = $ts =~ /(\d\d\d\d\d\d\d\d)/;
        if(! -d "$odir/$subdir") {
            logmsg("creating directory $odir/$subdir");
            docmd("mkdir -p $odir/$subdir");
        }

        if ($encoder eq "ffmpeg") {
            logmsg("encoding using ffmpeg");
            $ext = 'mp4';
            $fn = "$ts.$ext";

            # mp4 encoding
            # these options do not work:
            #  -movflags faststart
            #  -vcodec libx264
            #  -acodec aac -ac 2 -ab 160k
            # these have no effect:
            #   -pix_fmt yuv420p
            #   -preset slow
            #   -profile:v baseline
            #   -f mp4
            # this shrinks size by factor of 2, but useless in chrome and ffox
            #   -c:v mpeg4
            # increasing frame rate reduces the size, but makes scrubbing bad
            docmd("ffmpeg -framerate $fps -pattern_type glob -i '*.jpg' $odir/$subdir/$fn");
        } elsif ($encoder eq "mencoder") {
            logmsg("encoding using mencoder");
            $ext = 'avi';
            $fn = "$ts.$ext";

            # avi encoding.  does not display on ios.
            docmd("mencoder mf://\\*.jpg -mf w=640:h=480:fps=$fps:type=jpg -ovc lavc -lavcopts vcodec=mpeg4 -oac copy -o $odir/$subdir/$fn -of avi");
#            docmd("mencoder mf://\@${images_fn} -mf w=640:h=480:fps=$fps:type=jpg -ovc lavc -lavcopts vcodec=mpeg4 -oac copy -o $odir/$subdir/$fn -of avi");
#           docmd("mencoder mf://\@${images_fn} -mf w=640:h=480:fps=$fps:type=jpg -nosound -ovc lavc -lavcopts vcodec=mpeg4 -o $odir/$subdir/$fn -of avi");
        } else {
            logmsg("unknown encoder '$encoder'");
            $fail = 1;
        }

        if (! $fail) {
            logmsg("linking");
            chdir($odir);
            docmd("rm -f latest.$ext");
            if (-f "$odir/$subdir/$fn") {
                docmd("ln -s $subdir/$fn latest.$ext");
            }

            # create a thumbnail of the first image
            logmsg("src: $files[0]");
            if ($mkthumb && -f $files[0]) {
                my $src = $files[0];
                my $tn = "$odir/$subdir/${ts}-tn.jpg";
                docmd("convert $src -resize x${tnheight} $tn");
            }
        }
    } else {
        logmsg("nothing to encode");
    }

    logmsg("cleaning up");
    docmd("rm -rf $tmpdir");
}

sub get_endtime() {
    my($ts) = @_;
    if($ts < 0) {
        $ts = time();
    } elsif($ts =~ /\d\d:\d\d/) {
        my($h,$m) = $endtime =~ /(\d\d):(\d\d)/;
        my @t = localtime time;
        $ts = timelocal(0,$m,$h,$t[3],$t[4],$t[5]);
    }
    return $ts;
}

sub get_startofday() {
    my($ts) = @_;
    my @t = localtime($ts);
    my $sod = timelocal(0,0,0,$t[3],$t[4],$t[5]);
    return $sod;
}
