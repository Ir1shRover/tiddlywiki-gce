# MIT License
# Copyright (c) 2018 Nicola Worthington <nicolaw@tfb.net>

FROM certbot/certbot:latest

COPY init-and-run /usr/local/bin/init-and-run
RUN chmod a+x /usr/local/bin/*

COPY root.crontab /var/spool/cron/crontabs/root

ENTRYPOINT []
CMD ["/bin/sh","/usr/local/bin/init-and-run"]
