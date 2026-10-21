FROM repo.cylo.net/rutorrent@sha256:92d9947204371b07c67335a17fc091cc6d32a6d6e259b22ec79a52f941c26e6a

ADD scripts /scripts

RUN chmod -R +x /scripts/*

EXPOSE 80

CMD [ "/scripts/start.sh" ]