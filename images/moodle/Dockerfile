FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    locales locales-all \
    nfs-common \
    tzdata \
    unzip cron \
    gettext wget curl ca-certificates \
    nginx-full \
    php8.1 php8.1-fpm php8.1-common php8.1-cli \
    php8.1-mbstring php8.1-xmlrpc php8.1-soap php8.1-gd php8.1-xml \
    php8.1-intl php8.1-pgsql php8.1-ldap php8.1-zip php8.1-curl \
    php8.1-redis php8.1-opcache php8.1-igbinary php8.1-pspell \
    php8.1-imagick php8.1-imap php8.1-apcu php8.1-bz2 php8.1-yaml php8.1-bcmath \
    poppler-utils ffmpeg gpac graphviz aspell aspell-pt-br ghostscript \
    texlive texlive-latex-recommended && \
    echo "pt_BR.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen && \
    rm -rf /var/lib/apt/lists/*

ENV LC_ALL=pt_BR.UTF-8
ENV LANG=pt_BR.UTF-8
ENV LANGUAGE=pt_BR.UTF-8

RUN cp /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# Moodle core 4.5
RUN wget -q https://github.com/moodle/moodle/archive/refs/heads/MOODLE_405_STABLE.zip && \
    unzip -q MOODLE_405_STABLE.zip && \
    mv moodle-MOODLE_405_STABLE/* /var/www/html/ && \
    rm -rf MOODLE_405_STABLE.zip moodle-MOODLE_405_STABLE /var/www/html/.github /var/www/html/.grunt

# Ensure required ext for Moodle 4.5 is present.
RUN php -m | grep -qi '^sodium$'

COPY --chown=www-data:www-data files/config.php /var/www/html/config.php.template

# tool_objectfs (supports 4.4/4.5)
RUN wget -q https://codeload.github.com/catalyst/moodle-tool_objectfs/zip/refs/heads/MOODLE_404_STABLE -O objectfs.zip && \
    unzip -q objectfs.zip && \
    mkdir -p /var/www/html/admin/tool/objectfs && \
    mv moodle-tool_objectfs-MOODLE_404_STABLE/* /var/www/html/admin/tool/objectfs/ && \
    rm -rf objectfs.zip moodle-tool_objectfs-MOODLE_404_STABLE

# local_bulkenrol (Moodle 4.5 compatible branch)
RUN wget -q https://codeload.github.com/moodle-an-hochschulen/moodle-local_bulkenrol/zip/refs/heads/MOODLE_405_STABLE -O bulkenrol.zip && \
    unzip -q bulkenrol.zip && \
    mkdir -p /var/www/html/local/bulkenrol && \
    mv moodle-local_bulkenrol-MOODLE_405_STABLE/* /var/www/html/local/bulkenrol/ && \
    rm -rf bulkenrol.zip moodle-local_bulkenrol-MOODLE_405_STABLE

# cachestore_rediscluster (4.5)
RUN wget -q https://codeload.github.com/open-lms-open-source/moodle-cachestore_rediscluster/zip/refs/heads/MOODLE_405_STABLE -O rediscluster.zip && \
    unzip -q rediscluster.zip && \
    mkdir -p /var/www/html/cache/stores/rediscluster && \
    mv moodle-cachestore_rediscluster-MOODLE_405_STABLE/* /var/www/html/cache/stores/rediscluster/ && \
    rm -rf rediscluster.zip moodle-cachestore_rediscluster-MOODLE_405_STABLE

# tool_forcedcache (4.5)
RUN wget -q https://codeload.github.com/catalyst/moodle-tool_forcedcache/zip/refs/heads/MOODLE_405_STABLE -O forcedcache.zip && \
    unzip -q forcedcache.zip && \
    mkdir -p /var/www/html/admin/tool/forcedcache && \
    mv moodle-tool_forcedcache-MOODLE_405_STABLE/* /var/www/html/admin/tool/forcedcache/ && \
    rm -rf forcedcache.zip moodle-tool_forcedcache-MOODLE_405_STABLE

# tool_heartbeat (supports 3.9-4.5)
RUN wget -q https://codeload.github.com/catalyst/moodle-tool_heartbeat/zip/refs/heads/MOODLE_39_STABLE -O heartbeat.zip && \
    unzip -q heartbeat.zip && \
    mkdir -p /var/www/html/admin/tool/heartbeat && \
    mv moodle-tool_heartbeat-MOODLE_39_STABLE/* /var/www/html/admin/tool/heartbeat/ && \
    rm -rf heartbeat.zip moodle-tool_heartbeat-MOODLE_39_STABLE

RUN mkdir -p /var/www/localdata/cache /var/www/moodledata && \
    chown -R www-data:www-data /var/www/localdata /var/www/moodledata /var/www/html

RUN rm -rf /etc/nginx/sites-enabled/default && \
    mkdir -p /var/run/php && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log && \
    ln -sf /dev/stderr /var/log/php8.1-fpm.log

COPY files/nginx-moodle.conf /etc/nginx/sites-available/moodle.conf
COPY files/nginx.conf /etc/nginx/nginx.conf
RUN ln -sf /etc/nginx/sites-available/moodle.conf /etc/nginx/sites-enabled/moodle.conf

COPY files/php.ini /etc/php/8.1/fpm/php.ini
COPY files/php.ini /etc/php/8.1/cli/php.ini
COPY files/www.conf /etc/php/8.1/fpm/pool.d/www.conf
COPY files/opcache.ini /etc/php/8.1/mods-available/opcache.ini
COPY files/apcu.ini /etc/php/8.1/mods-available/apcu.ini

COPY --chown=www-data:www-data files/configure_muc.php /var/www/html/configure_muc.php
COPY files/init.sh /init.sh
COPY files/init_cron.sh /init_cron.sh
COPY files/run-moodle-cron.sh /usr/local/bin/run-moodle-cron.sh

RUN chmod +x /init.sh /init_cron.sh /usr/local/bin/run-moodle-cron.sh

CMD ["/init.sh"]
