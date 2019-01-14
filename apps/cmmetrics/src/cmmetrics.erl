-module(cmmetrics).
-export([
         define_gauge/2,
         define_counter/2,
         define_http_duration/1, 
         define_http_duration/2,
         define_http_count/1, 
         define_ws_duration/1, 
         define_ws_count/1, 
         http_duration_groups/1,
         ws_duration_groups/1,
         set/2,
         increment/2,
         increment_http_count/1,
         decrement_http_count/1,
         increment_ws_count/1,
         decrement_ws_count/1,
         record_http_duration/4,
         record_ws_duration/3
        ]).

define_gauge(Name, Help) ->
    MetricName = to_bin(Name),
    prometheus_gauge:declare([{name, MetricName}, 
                               {help, Help}]),
    {ok, MetricName}.

define_counter(Name, Help) ->
    MetricName = to_bin(Name),
    prometheus_counter:declare([{name, MetricName}, 
                            {help, Help}]),
    {ok, MetricName}.

define_histogram(Name, Labels, Buckets, Help) ->
    MetricName = to_bin(Name), 
    prometheus_histogram:declare([{name, MetricName},
                                   {labels, Labels},
                                   {buckets, Buckets},
                                   {help, Help}]),
    {ok, MetricName}.

define_http_duration(Name, Buckets) ->
    define_histogram(Name, [method, status], Buckets, "Http Request execution time in milliseconds").

define_http_duration(Name) ->
    define_http_duration(Name, http_duration_groups(internal)).

define_ws_duration(Name, Buckets) ->
    define_histogram(Name, [termination], Buckets, "Websocket lifetime in seconds").
    
define_ws_duration(Name) ->
    define_ws_duration(Name, ws_duration_groups(internal)).

define_http_count(Name) ->
    define_gauge(Name, "Active Http requests").

define_ws_count(Name) ->
    define_gauge(Name, "Active Websocket connections").

record_http_duration(Name, Method, Status, Value) ->
    prometheus_histogram:observe(Name, [cmhttp:method(Method), Status], Value).

record_ws_duration(Name, Reason, Value) ->
    prometheus_histogram:observe(Name, [Reason], Value).

set(Name, Value) ->
    prometheus_gauge:set(Name, Value).

increment(Name, Value) ->
    prometheus_counter:inc(Name, Value).

increment_ws_count(Name) ->
    prometheus_gauge:inc(Name).

decrement_ws_count(Name) ->
    prometheus_gauge:dec(Name).

increment_http_count(Name) ->
    prometheus_gauge:inc(Name).

decrement_http_count(Name) ->
    prometheus_gauge:dec(Name).

to_bin(V) -> cmkit:to_bin(V).

ws_duration_groups(internal) -> [30, 60, 300, 600, 1800, 3600].
http_duration_groups(external) -> [50, 100, 150, 300, 500, 750, 1000];
http_duration_groups(internal) -> [0.5, 1, 10, 25, 50, 100, 150, 300, 500, 1000].
