# Copyright 2013-2017 Matthew Wall
# Distributed under terms of the GPLv3
#
# common code for the eyesee image capture system

use Time::Local;
use POSIX;

# format for date/time in the log messages
my $DATE_FORMAT = "%Y.%m.%d %H:%M:%S";

# control the verbosity of log output
our $verbose = 0;

# set to 0 for debug
our $doit = 1;


sub docmd {
    my($cmd) = @_;
    logmsg($cmd);
    my $rc = -1;
    my $s = -1;
    my $fail = 0;
    if ($doit) {
        system($cmd);
        if ($? == -1) {
            $fail = 1;
            logmsg("failed to execute: $!");
        } elsif ($? & 127) {
            $s = ($? & 127);
            my $dump = ($? & 128) ? " (with coredump)" : q();
            logmsg("child died with signal $s$dump");
        } else {
            $rc = $? >> 8;
            if ($rc != 0) {
                logmsg("child exited with value $rc");
            }
        }
    }
    return ($fail, $rc, $s);
}


sub errmsg {
    my ($msg) = @_;
    my $tstr = strftime $DATE_FORMAT, localtime time;
    print "$tstr $msg\n";
}


sub logmsg {
    my ($msg) = @_;
    my $tstr = strftime $DATE_FORMAT, localtime time;
    print "$tstr $msg\n" if $verbose;
}


# read a configuration file.  format is as follows:
#
#   name1=value1
#   name2=value2
#   [hostidentifier1]
#   name3=value3
#   [hostidentifier2]
#   name4=value4
#
# name-value pairs after a host identifier are applied only to that host.
# lines that begin with # are ignored
sub get_cfg {
    my($cfgfn, %cfg) = @_;

    for(my $i=0; $i<scalar @ARGV; $i++) {
        if ($ARGV[$i] eq '--config') {
            $i += 1;
            $cfgfn = $ARGV[$i];
        }
    }

    if (open(CFG, "<$cfgfn")) {
        my $hostkey = q();
        while(<CFG>) {
            my $line = $_;
            chomp($line);
            # skip comments
            next if $line =~ /^\s*\#/;
            # put items for specific hosts into separate dict
            if($line =~ /\[(\S+)\]/) {
                $hostkey = $1;
            }
            # get any name=value pairs
            if($line =~ /=/) {
                my ($n,$v) = split('=', $line);
                $n =~ s/^\s+//g;
                $n =~ s/\s+$//g;
                $v =~ s/^\s+//g;
                $v =~ s/\s+$//g;
                if($n =~ /\S+/ && $v =~ /\S+/) {
                    if($hostkey) {
                        $cfg{$hostkey}{$n} = $v;
                    } else {
                        $cfg{$n} = $v;
                    }
                }
            }
        }
        close(CFG);
    }

    return %cfg;
}

# specialize any configuration variables with per-host overrides
sub reduce_cfg {
    my($hostkey, %cfg) = @_;
    my %newcfg;
    # get every non-specialized value
    foreach my $k (keys %cfg) {
        if(ref $cfg{$k} ne 'HASH') {
            $newcfg{$k} = $cfg{$k};
        }
    }
    # specialize with any values for the indicated host
    if($cfg{$hostkey}) {
        foreach my $k (keys %{$cfg{$hostkey}}) {
            $newcfg{$k} = $cfg{$hostkey}{$k};
        }
    }
    return %newcfg;
}


sub format_datetime {
    my($ts, $fmt) = @_;
    $fmt = $DATE_FORMAT if ! $fmt;
    return strftime $fmt, localtime $ts;
}


# send an mqtt message
sub send_mqtt {
    my ($broker, $port, $topic, $msg) = @_;

    my $rval = eval "{ require Net::MQTT::Simple; }"; ## no critic (ProhibitStringyEval)
    if (! $rval) {
        my $msg = 'Net::MQTT::Simple is not installed';
        errmsg($msg);
        return;
    }

    my $s = $broker . q(:) . $port;
    logmsg("mqtt msg '$msg' as topic $topic at broker $s");
    my $c = Net::MQTT::Simple->new($s);
    $c->retain("$topic", $msg);
}

1;
