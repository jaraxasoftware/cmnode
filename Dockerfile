FROM erlang:21.3.8.11-slim
LABEL org.opencontainers.image.source https://github.com/jaraxasoftware/cmnode
RUN apt-get update; apt-get install -y libgd-dev libwebp-dev inotify-tools vim tree
RUN mkdir -p /opt/cmnode/apps; mkdir ~/.ssh; ssh-keyscan github.com >> ~/.ssh/known_hosts
ENV CMHOME /opt/cmnode
RUN rm -rf rebar3; wget https://github.com/erlang/rebar3/releases/download/3.9.1/rebar3; chmod +x rebar3; mv rebar3 /usr/local/bin
ENV CODE_LOADING_MODE interactive
ENV RELX_REPLACE_OS_VARS true
ENV CMNODE cmnode
WORKDIR /opt/cmnode
ADD rebar.config .
ADD config config
ADD apps apps
RUN mkdir etc
RUN rebar3 release
CMD ["/opt/cmnode/_build/default/rel/cmnode/bin/cmnode", "console"]
