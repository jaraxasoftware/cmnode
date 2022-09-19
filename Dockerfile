FROM erlang:21.3.8.11
LABEL org.opencontainers.image.source https://github.com/jaraxasoftware/cmnode
RUN apt-get update; apt-get install -y libgd-dev libwebp-dev inotify-tools vim tree
RUN mkdir -p /opt/cmnode/
ENV CMHOME /opt/cmnode
ENV CODE_LOADING_MODE interactive
ENV RELX_REPLACE_OS_VARS true
ENV CMNODE cmnode
WORKDIR /opt/cmnode/
ADD ./ .
CMD ["/opt/cmnode/_build/default/rel/cmnode/bin/cmnode", "console"]
