-module(cmtask_worker).
-behaviour(gen_server).
-export([start_link/2, run/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

run(Pid) -> 
    gen_server:cast(Pid, run).

start_link(Name, Params) ->
    gen_server:start_link(?MODULE, [Name, Params], []).

init([Name, #{ settings := Settings }=Params]) ->
    case cmconfig:task(Name) of 
        {ok, Spec} ->
            case cmconfig:settings(Settings) of 
                {ok, SettingsSpec} ->
                    {ok, #{ name => Name,
                            spec => Spec,
                            settings => SettingsSpec,
                            params => Params }};
                Other -> 
                    cmkit:danger({cmtask, Name, Settings, settings_error, Other}),
                    {stop, normal}
            end;
        Other ->
            cmkit:danger({cmtask, Name, task_error, Other}),
            {stop, normal}
    end.

handle_call(_, _, _) -> 
    {reply, ok}.

handle_cast(run, #{ name := Name,
                    spec := Spec,
                    settings := Settings,
                    params := Params }) ->
    cmtask_util:run(Spec, Settings, Params),
    {stop, normal, Name};

handle_cast(_, Data) ->
    {noreply, Data}.

handle_info(_, Data) ->
    {noreply, Data}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(Reason, Name) ->
    cmkit:log({cmtask, Name, self(), terminated, Reason}),
    ok.
