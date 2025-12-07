FROM alpine:3.23 as builder
#FROM alpine as builder
MAINTAINER Rich A Marino

#meta container, we want fresh builds
RUN apk update; \
    apk add alpine-sdk sudo; \
    addgroup sdk; \
    adduser  -G sdk -s /bin/sh -D sdk; \
    echo "sdk:sdk"| /usr/sbin/chpasswd; \
    echo "sdk    ALL=(ALL) ALL" >> /etc/sudoers; \
    chmod g+w /var/cache/distfiles/; \
    sudo addgroup sdk abuild;
USER sdk
WORKDIR /tmp
RUN git clone --depth 1 https://gitlab.alpinelinux.org/alpine/aports
WORKDIR /home/sdk

RUN abuild-keygen -a -n
#RUN sed -i 's/pkgver=0\.9\.13/pkgver=0\.9\.10/' APKBUILD
#RUN abuild checksum
WORKDIR /tmp/aports
RUN git pull

WORKDIR /tmp/aports/community/xrdp
RUN abuild fetch; \
    abuild unpack; \
    abuild deps; \
    abuild prepare; \
    abuild build; \
    abuild rootpkg;

ARG PULSE_VER="17.0"
ENV PULSE_VER=${PULSE_VER}
WORKDIR /tmp/aports/community/pulseaudio
RUN abuild fetch; \
    abuild unpack; \
    abuild deps; \
    abuild prepare; \
    abuild build; \
    abuild rootpkg;
WORKDIR /tmp/aports/community/pulseaudio/src/pulseaudio-"${PULSE_VER}"
RUN cp ./output/config.h .

WORKDIR /tmp/aports/community/xorgxrdp
RUN abuild fetch; \
    abuild unpack; \
    abuild deps; \
    abuild prepare; \
    abuild build; \
    abuild rootpkg;

ARG XRDPPULSE_VER="0.6"
ENV XRDPPULSE_VER=${XRDPPULSE_VER}

RUN echo sdk | sudo -S ls && echo "echo 'http://dl-cdn.alpinelinux.org/alpine/edge/testing'>>/etc/apk/repositories" | sudo sh
RUN echo sdk | sudo -S apk update
RUN echo sdk | sudo -S apk add pulseaudio-dev xrdp-dev xorgxrdp-dev
WORKDIR /tmp
RUN wget https://github.com/neutrinolabs/pulseaudio-module-xrdp/archive/refs/tags/v"${XRDPPULSE_VER}".tar.gz -O pulseaudio-module-xrdp-"${XRDPPULSE_VER}".tar.gz
RUN tar -zxf pulseaudio-module-xrdp-"${XRDPPULSE_VER}".tar.gz
WORKDIR /tmp/pulseaudio-module-xrdp-"${XRDPPULSE_VER}"
RUN ./bootstrap
RUN ./configure PULSE_DIR=/tmp/aports/community/pulseaudio/src/pulseaudio-"${PULSE_VER}"
RUN make
RUN echo sdk | sudo -S make install

RUN ls -al /tmp/pulseaudio-module-xrdp-"${XRDPPULSE_VER}"/src/.libs/module-xrdp-sink.so
RUN ls -al  /tmp/pulseaudio-module-xrdp-"${XRDPPULSE_VER}"/src/.libs/module-xrdp-source.so

# RUN STOP

FROM alpine:edge
MAINTAINER Daniel Guerra
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing">>/etc/apk/repositories

RUN apk --update --no-cache add \
    alpine-conf \
    bash \
    dbus \
    faenza-icon-theme \
    libpulse \
    openssh \
    paper-gtk-theme \
    paper-icon-theme \
    pavucontrol \
    pkgconf \
    openssl \
    pulseaudio \
    pulseaudio-utils \
    pulseaudio-dev \
    pulsemixer \
    setxkbmap \
    slim \
    sudo \
    supervisor \
    thunar-volman \
    ttf-freefont \
    util-linux \
    xauth \
    xf86-input-synaptics \
    xfce4 \
    xfce4-pulseaudio-plugin \
    xfce4-terminal \
    xinit \
    xorg-server \
    xorgxrdp \
    xterm \
    xrdp \
    dcron \
    git \
    gvim \
    librewolf \
    netsurf \
    vim \
    chicago95 \
    chicago95-fonts \
    chicago95-icons \
&& rm -rf /tmp/* /var/cache/apk/*

COPY --from=builder /tmp/pulseaudio-module-xrdp-0.6/src/.libs/module-xrdp-sink.so   /tmp/module-xrdp-sink.so
COPY --from=builder /tmp/pulseaudio-module-xrdp-0.6/src/.libs/module-xrdp-source.so /tmp/module-xrdp-source.so

# Install them into whatever dir this pulseaudio expects
RUN PULSE_MODDIR="$(pkg-config --variable=modlibexecdir libpulse)" \
 && mkdir -p "$PULSE_MODDIR" \
 && install -m 755 /tmp/module-xrdp-sink.so   "$PULSE_MODDIR/module-xrdp-sink.so" \
 && install -m 755 /tmp/module-xrdp-source.so "$PULSE_MODDIR/module-xrdp-source.so" \
 && rm /tmp/module-xrdp-sink.so /tmp/module-xrdp-source.so

RUN mkdir -p /var/log/supervisor

# add scripts/config
ADD etc /etc
ADD bin /bin

# Disable XFCE compositing (improved RDP performance)
RUN mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml \
 && cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="theme" type="string" value="Chicago95"/>
  </property>
</channel>
EOF

# Disable wallpaper
RUN mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml \
 && cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << 'EOF'
<?xml version="1.1" encoding="UTF-8"?>                                          
<channel name="xfce4-desktop" version="1.0">                                    
  <property name="backdrop" type="empty">                                       
    <property name="screen0" type="empty">                                      
      <property name="monitor0" type="empty">                                   
        <property name="workspace0" type="empty">                               
          <property name="image-path" type="empty"/>                            
          <property name="image-show" type="empty"/>                            
          <property name="color-style" type="empty"/>                           
          <property name="color1" type="empty"/>                                
        </property>                                                             
      </property>                                                               
      <property name="monitorrdp0" type="empty">                                
        <property name="workspace0" type="empty">                               
          <property name="image-style" type="int" value="0"/>                   
        </property>                                                             
      </property>                                                               
    </property>                                                                 
  </property>                                                                   
  <property name="last-settings-migration-version" type="uint" value="1"/>      
</channel>
EOF


RUN mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml \
 && cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml << 'EOF'
<?xml version="1.1" encoding="UTF-8"?>

<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Chicago95"/>
    <property name="IconThemeName" type="string" value="Chicago95"/>
  </property>
</channel>
EOF

#remove .xsession
RUN rm -f /etc/skel/.xsession

RUN cat > /etc/xrdp/startwm.sh << 'EOF' \
 && chmod 755 /etc/xrdp/startwm.sh
#!/bin/sh

# Load system and user profiles (for PATH, locale, etc.)
[ -r /etc/profile ] && . /etc/profile
[ -r "$HOME/.profile" ] && . "$HOME/.profile"

# Make sure we have an XDG runtime dir (needed by pulseaudio and friends)
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR=/tmp/xdg-runtime-$UID
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
fi

# Start a per-user dbus session (if not already running)
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval "$(dbus-launch --sh-syntax --exit-with-session)" || echo "dbus-launch failed" >&2
fi

# Start PulseAudio for this RDP session
pulseaudio --start --exit-idle-time=-1 || echo "pulseaudio failed to start" >&2

# If the user has their own X session script, hand off to it.
# Using "exec" means we *never* come back here if it succeeds.
if [ -x "$HOME/.xsession" ]; then
    "$HOME/.xsession"
fi

if [ -x "$HOME/.xinitrc" ]; then
    exec "$HOME/.xinitrc"
fi

# Fallback: no user script, so start the default DE
exec startxfce4
xterm
EOF

# prepare user alpine
RUN addgroup alpine \
&& adduser  -G alpine -s /bin/sh -D alpine \
&& echo "alpine:alpine" | /usr/sbin/chpasswd \
&& echo "alpine    ALL=(ALL) ALL" >> /etc/sudoers

# prepare xrdp key
RUN xrdp-keygen xrdp auto

# XRDP config tweaks
RUN sed -i 's/bitmap_compression=true/bitmap_compression=false/' /etc/xrdp/xrdp.ini \
 && sed -i 's/security_layer=negotiate/security_layer=tls/' /etc/xrdp/xrdp.ini

# Make startwm.sh executable by alpine user.
RUN chmod 755 /etc/xrdp

EXPOSE 3389 22
VOLUME ["/etc/ssh"]
ENTRYPOINT ["/bin/docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord","-c","/etc/supervisor/supervisord.conf"]
