#!/bin/bash
#
# Install the 'eyesee' image capture system.  This expects the /var partition
# to have sufficient space for images and video.  It uses the following
# configuration:
#
# PREFIX    /opt/eyesee
# DATADIR   /var/eyesee
# CFGDIR    /etc/eyesee
# CGIDIR    /var/www/cgi-bin
# LOGDIR    /var/log/eyesee
#
# The system runs as the unpriviledged user 'eyesee'.  If this user does not
# exist, this installer will create the user.  If you specify a UID/GID, then
# this installer will use the specified UID/GID for the account.  Otherwise it
# will use the next available system UID/GID, with no aging information.

# set default values
[ -z "$PREFIX" ] && PREFIX=/opt/eyesee
[ -z "$DATADIR" ] && DATADIR=/var/eyesee
[ -z "$CFGDIR" ] && CFGDIR=/etc/eyesee
[ -z "$LOGDIR" ] && LOGDIR=/var/log/eyesee
[ -z "$EYESEE_LOGADM" ] && EYESEE_LOGADM=adm
[ -z "$WWW_USER" ] && WWW_USER=www-data

# if there is a UID specified, then use it
[ ! -z "$EYESEE_UID" -a -z "$EYESEE_GID" ] && EYESEE_GID=$EYESEE_UID

# set to 1 if mqtt notifications are desired
[ -z "$INSTALL_MQTT" ] && INSTALL_MQTT=0


ts=`date +"%Y%m%d%H%M%S"`

install_log=/var/tmp/eyesee-install-${ts}.log
defaults_file=/etc/default/eyesee

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
    echo "install pre-requisites"

    # for capturing images and pushing to server
    echo "  curl"
    apt-get -q -y install curl >> $install_log 2>&1

    # for creating thumbnails
    echo "  imagemagick"
    apt-get -q -y install imagemagick >> $install_log 2>&1

    # for captures only during daylight
    echo "  libdatetime"
    apt-get -q -y install libdatetime-event-sunrise-perl >> $install_log 2>&1
    apt-get -q -y install libdatetime-format-dateparse-perl >> $install_log 2>&1

    # for the info cgi install json
    echo "  libjson-perl"
    apt-get -q -y install libjson-perl >> $install_log 2>&1

    # for encoding to video
    echo "  mencoder ffmpeg"
    apt-get -q -y install mencoder ffmpeg >> $install_log 2>&1

    # debian older than 9 (8?) needed libav-tools
#    apt-get -q -y install mencoder libav-tools ffmpeg 2>&1

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
    # if the distribution is at the installation location, then we are running
    # from the source tree, so do not copy the code to the install location.
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
            useradd --system eyesee
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

    if [ -d ${PREFIX}/html ]; then
        echo "ensure symlink for the web config"
        mk_symlink ${CFGDIR}/eyesee.js ${PREFIX}/html/eyesee.js
    fi

    echo "configure the defaults file"
    mk_archive $defaults_file
    echo "insert paths into defaults file"
    echo "# parameters for eyesee" >> $defaults_file
    echo "GETIMG=${PREFIX}/bin/getimg.pl" >> $defaults_file
    echo "CFG=${CFGDIR}/eyesee.cfg" >> $defaults_file
    echo "LOGDIR=${LOGDIR}" >> $defaults_file
    echo "copy template for list of cameras"
    echo "" >> $defaults_file
    cat etc/default/eyesee >> $defaults_file

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
        cp etc/init.d/eyesee /etc/init.d/eyesee
        chmod 755 /etc/init.d/eyesee
    fi

    mkdir -p /etc/eyesee/nginx
    cat etc/nginx/conf.d/eyesee.conf | \
        sed -e "s%/opt/eyesee%${PREFIX}%" \
            -e "s%/var/eyesee%${DATADIR}%" > \
            /etc/eyesee/nginx/eyesee.conf
    cat etc/nginx/conf.d/eyesee-sub.conf | \
        sed -e "s%/opt/eyesee%${PREFIX}%" \
            -e "s%/var/eyesee%${DATADIR}%" > \
            /etc/eyesee/nginx/eyesee-sub.conf
    if [ -d /etc/nginx/conf.d -a ! -f /etc/nginx/conf.d/eyesee.conf ]; then
        echo "configure nginx"
        mk_symlink /etc/eyesee/nginx/eyesee.conf /etc/nginx/conf.d/eyesee.conf
    fi

    mkdir -p /etc/eyesee/apache2
    cat etc/apache/conf.d/eyesee.conf | \
        sed -e "s%/var/eyesee%${DATADIR}%" \
            -e "s%/opt/eyesee%${PREFIX}%" > \
            /etc/eyesee/apache2/eyesee.conf
    if [ -d /etc/apache2/conf.d -a ! -f /etc/apache2/conf.d/eyesee.conf ]; then
        echo "configure apache"
        mk_symlink /etc/eyesee/apache2/eyesee.conf /etc/apache2/conf.d/eyesee.conf
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


# ensure that the local storage is configured properly for images and video.
#   images are received to /var/eyesee/img/<id>/
#   videos are placed in /var/eyesee/vid/<id>/
config_eyesee_server() {
    # install the cgi script
    if [ -d ${CGIDIR} ]; then
        if [ ! -f ${CGIDIR}/info ]; then
            mk_symlink /opt/eyesee/cgi-bin/info ${CGIDIR}/info
        fi
        if [ ! -f ${CGIDIR}/rcvimg ]; then
            mk_symlink /opt/eyesee/cgi-bin/rcvimg ${CGIDIR}/rcvimg
        fi
    fi

    # ensure that we have a place to put images and video
    mkdir -p ${DATADIR}
    mkdir -p ${DATADIR}/img
    mkdir -p ${DATADIR}/vid

    # data directories are owned by the eyesee user
    chown -R eyesee ${DATADIR}

    # let web server write to image and video directories
    chmod 775 ${DATADIR}/img
    chmod 775 ${DATADIR}/vid
    chgrp ${WWW_USER} ${DATADIR}/img
    chgrp ${WWW_USER} ${DATADIR}/vid

    # let web server owner write to log directory
    chmod 775 ${LOGDIR}
    chgrp ${WWW_USER} ${LOGDIR}
}

if [ "$USER" != "root" ]; then
    echo "root privileges are required to install this software"
    exit
fi

install_prereq
install_eyesee_files
install_eyesee_user
install_eyesee_conf
config_eyesee_server

echo ""
echo "To complete the installation, add your camera IP addresses and other"
echo "camera paramters to the appropriate configuration files:"
echo ""
echo "  /etc/eyesee/eyesee.cfg   - tell the image capture about the cameras"
echo "  /etc/eyesee/eyesee.js    - tell the web interface about the cameras"
echo "  /etc/default/eyesee      - if you want to run getimg as a daemon"
echo "  /etc/cron.d/eyesee       - if you want to run getimg using cron"
echo ""
