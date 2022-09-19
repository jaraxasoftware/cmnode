-module(cmcluster_sup).
-behaviour(supervisor).
-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    W = cmkit:child_spec(cmcluster_watcher,
                         cmcluster_watcher,
                         [],
                         permanent,
                         worker),

    {ok, { {one_for_one, 0, 1}, [W]} }.
