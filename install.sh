#!/bin/bash

# this expects the /var partition to have sufficient space for images and video

# set default values
[ -z "$PREFIX" ] && PREFIX=/opt/eyesee
[ -z "$DATADIR" ] && DATADIR=/var/eyesee
[ -z "$CFGDIR" ] && CFGDIR=/etc/eyesee
[ -z "$LOGDIR" ] && LOGDIR=/var/log/eyesee
[ -z "$EYESEE_LOGADM" ] && EYESEE_LOGADM=adm

# if there is a UID specified, then use it
[ ! -z "$EYESEE_UID" -a -z "$EYESEE_GID" ] && EYESEE_GID=$EYESEE_UID

# set to 1 if mqtt notifications are desired
[ -z "$INSTALL_MQTT" ] && INSTALL_MQTT=0


ts=`date +"%Y%m%d%H%M%S"`

mk_archive() {
    d=$1
    if [ -e "$d" ]; then
        mv $d $d.$ts
    fi
}

mk_symlink() {
    tgt=$1
    lnk=$2
    [[ -e "$lnk" || -L "$lnk" ]] && rm $lnk
    ln -s $tgt $lnk
}


install_prereq() {
    # for capturing images and pushing to server
    apt-get -q -y install curl

    # for creating thumbnails
    apt-get -q -y install imagemagick

    # for captures only during daylight
    apt-get -q -y install libdatetime-event-sunrise-perl
    apt-get -q -y install libdatetime-format-dateparse-perl

    # for the info cgi install json
    apt-get -q -y install libjson-perl

    # for encoding to video
    apt-get -q -y install mencoder ffmpeg

    # debian older than 9 (8?) needed libav-tools
#    apt-get -q -y install mencoder libav-tools ffmpeg
    
    # alternative ffmpeg for encoding to video
#    echo "deb http://www.deb-multimedia.org wheezy main non-free" > /etc/apt/sources.list.d/www.deb-multimedia.org.list
#    apt-get update
#    apt-get -q -y install deb-multimedia-keyring
#    apt-get -q -y install ffmpeg

    # include mqtt compatibility
    if [ "$INSTALL_MQTT" = "1" ]; then
        cd /var/tmp
        wget http://search.cpan.org/CPAN/authors/id/J/JU/JUERD/Net-MQTT-Simple-1.21.tar.gz
        tar xvfz Net-MQTT-Simple-1.21.tar.gz
        cd Net-MQTT-Simple-1.21
        perl Makefile.PL
        make
        make test
        make install
    fi
}

install_eyesee_files() {
    # if the distribution is at the installation location, then do not do the
    # file copy.
    cwd=`pwd`
    if [ "$cwd" = "${PREFIX}" ]; then
        echo "no files to copy"
        return
    fi

    # install the necessary files
    echo "copy files to ${PREFIX}"
    for d in \
bin \
cgi-bin \
html \
html/css \
html/css/images \
html/fonts \
html/highslide \
html/highslide/graphics \
html/highslide/graphics/outlines \
html/js \
; do
        mkdir -p ${PREFIX}/$d
    done

    for f in \
bin/backfill.pl \
bin/eyesee.pl \
bin/getimg.pl \
bin/mkvid.pl \
bin/reaper.pl \
bin/reorg.pl \
bin/xfrimg.pl \
cgi-bin/info \
cgi-bin/rcvimg \
html/blank.gif \
html/index.html \
html/loading.gif \
html/css/bootstrap.min.css \
html/css/jquery-ui.css \
html/css/images/ui-bg_diagonals-thick_18_b81900_40x40.png \
html/css/images/ui-bg_diagonals-thick_20_666666_40x40.png \
html/css/images/ui-bg_flat_10_000000_40x100.png \
html/css/images/ui-bg_glass_100_f6f6f6_1x400.png \
html/css/images/ui-bg_glass_100_fdf5ce_1x400.png \
html/css/images/ui-bg_glass_65_ffffff_1x400.png \
html/css/images/ui-bg_gloss-wave_35_f6a828_500x100.png \
html/css/images/ui-bg_highlight-soft_100_eeeeee_1x100.png \
html/css/images/ui-bg_highlight-soft_75_ffe45c_1x100.png \
html/css/images/ui-icons_222222_256x240.png \
html/css/images/ui-icons_228ef1_256x240.png \
html/css/images/ui-icons_ef8c08_256x240.png \
html/css/images/ui-icons_ffd27a_256x240.png \
html/css/images/ui-icons_ffffff_256x240.png \
html/fonts/glyphicons-halflings-regular.eot \
html/fonts/glyphicons-halflings-regular.woff \
html/fonts/glyphicons-halflings-regular.svg \
html/fonts/glyphicons-halflings-regular.woff2 \
html/fonts/glyphicons-halflings-regular.ttf \
html/highslide/highslide.min.js \
html/highslide/highslide-with-gallery.packed.js \
html/highslide/highslide.css \
html/highslide/highslide-with-gallery.js \
html/highslide/highslide.js \
html/highslide/highslide-with-gallery.min.js \
html/highslide/graphics/close.png \
html/highslide/graphics/controlbar-text-buttons.png \
html/highslide/graphics/loader.white.gif \
html/highslide/graphics/closeX.png \
html/highslide/graphics/controlbar-white.gif \
html/highslide/graphics/controlbar2.gif \
html/highslide/graphics/controlbar-white-small.gif \
html/highslide/graphics/resize.gif \
html/highslide/graphics/controlbar3.gif \
html/highslide/graphics/fullexpand.gif \
html/highslide/graphics/scrollarrows.png \
html/highslide/graphics/controlbar4.gif \
html/highslide/graphics/geckodimmer.png \
html/highslide/graphics/zoomin.cur \
html/highslide/graphics/controlbar4-hover.gif \
html/highslide/graphics/icon.gif \
html/highslide/graphics/zoomout.cur \
html/highslide/graphics/controlbar-black-border.gif \
html/highslide/graphics/loader.gif \
html/highslide/graphics/outlines/beveled.png \
html/highslide/graphics/outlines/glossy-dark.png \
html/highslide/graphics/outlines/Outlines.psd \
html/highslide/graphics/outlines/rounded-white.png \
html/highslide/graphics/outlines/drop-shadow.png \
html/highslide/graphics/outlines/outer-glow.png \
html/highslide/graphics/outlines/rounded-black.png \
html/js/bootstrap.min.js \
html/js/echo.min.js \
html/js/jquery.min.js \
html/js/jquery-ui.min.js \
; do
        cp -p $f ${PREFIX}/$f
    done
}

install_eyesee_user() {
    # create the user with password disabled
    flag=`grep eyesee /etc/passwd`
    if [ "$flag" = "" ]; then
        if [ "$EYESEE_GID" != "" -a "$EYESEE_UID" != "" ]; then
            echo "create user eyesee ($EYESEE_UID, $EYESEE_GID)"
            groupadd --gid $EYESEE_GID eyesee
            useradd --uid $EYESEE_UID --gid $EYESEE_GID eyesee
        else
            echo "create user eyesee"
            useradd eyesee
        fi
    else
        echo "user eyesee already exists"
    fi
}

install_eyesee_conf() {
    # create config
    mkdir -p ${CFGDIR}

    echo "copy default configs"
    cp etc/eyesee-defaults.cfg ${CFGDIR}
    cp etc/eyesee-defaults.js ${CFGDIR}

    echo "create the configuration files"
    mk_archive ${CFGDIR}/eyesee.cfg
    cp etc/eyesee.cfg.tmpl ${CFGDIR}/eyesee.cfg
    mk_archive ${CFGDIR}/eyesee.js
    cp etc/eyesee.js.tmpl ${CFGDIR}/eyesee.js

    echo "ensure symlink for the web config"
    mk_symlink ${CFGDIR}/eyesee.js ${PREFIX}/html/eyesee.js

    echo "copy template for list of cameras"
    mk_archive /etc/default/eyesee
    cp etc/default/eyesee /etc/default

    if [ ! -d ${LOGDIR} ]; then
        echo "configure log directory"
        mkdir -p ${LOGDIR}
        chown eyesee ${LOGDIR}
        chgrp ${EYESEE_LOGADM} ${LOGDIR}
    fi

    if [ ! -f /etc/logrotate.d/eyesee ]; then
        echo "configure logrotate"
        cat etc/logrotate.d/eyesee | \
            sed -e "s%/var/log/eyesee%${LOGDIR}%" > \
                /etc/logrotate.d/eyesee
    fi

    if [ ! -f /etc/cron.d/eyesee ]; then
        echo "configure cron"
        cat etc/cron.d/eyesee | \
            sed -e "s%/opt/eyesee%${PREFIX}%" \
                -e "s%/var/eyesee%${DATADIR}%" \
                -e "s%/var/log/eyesee%${LOGDIR}%" > \
                /etc/cron.d/eyesee
    fi

    if [ -d /etc/init.d -a ! -f /etc/init.d/eyesee ]; then
        echo "configure init"
        cat etc/init.d/eyesee | \
            sed -e "s%/opt/eyesee%${PREFIX}%" \
                -e "s%/var/eyesee%${DATADIR}%" \
                -e "s%/var/log/eyesee%${LOGDIR}%" > \
                /etc/init.d/eyesee
        chmod 755 /etc/init.d/eyesee
    fi

    if [ -d /etc/nginx/conf.d -a ! -f /etc/nginx/conf.d/eyesee.conf ]; then
        echo "configure nginx"
        cat etc/nginx/conf.d/eyesee.conf | \
            sed -e "s%/opt/eyesee%${PREFIX}%" \
                -e "s%/var/eyesee%${DATADIR}%" > \
                /etc/nginx/conf.d/eyesee.conf
    fi
    
    if [ -d /etc/apache2/conf.d -a ! -f /etc/apache2/conf.d/eyesee.conf ]; then
        echo "configure apache"
        cat etc/apache/conf.d/eyesee.conf | \
            sed -e "s%/var/eyesee%${DATADIR}%" \
                -e "s%/opt/eyesee%${PREFIX}%" > \
                /etc/apache2/conf.d/eyesee.conf
    fi

    # create the destination for images and videos
    #   images are saved to /var/eyesee/img/<id>/
    #   videos are saved to /var/eyesee/vid/<id>/
    #   temporary caching in /var/eyesee/cache/
    for d in img vid cache; do
        if [ ! -d ${DATADIR}/$d ]; then
            echo "create directory ${DATADIR}/$d"
            mkdir -p ${DATADIR}/$d
            chown -R eyesee ${DATADIR}/$d
            chgrp -R eyesee ${DATADIR}/$d
        fi
    done
}


# images are received to /var/eyesee/img/<id>/
config_eyesee_server() {
    # install the cgi script
    ln -s /opt/eyesee/cgi-bin/rcvimg ${cgidir}

    # ensure that we have a place to put images and video
    mkdir -p ${DATADIR}
    mkdir -p ${DATADIR}/img
    mkdir -p ${DATADIR}/vid

    # let web server write to image and video directories
    chmod 775 ${DATADIR}/img
    chmod 775 ${DATADIR}/vid
    chgrp www-data ${DATADIR}/img
    chgrp www-data ${DATADIR}/vid

    # let web server owner write to log directory
    chown www-data ${LOGDIR}
}

if [ "$USER" != "root" ]; then
    echo "root privileges are required to install this software"
    exit
fi

install_prereq
install_eyesee_files
install_eyesee_user
install_eyesee_conf
#config_eyesee_server
