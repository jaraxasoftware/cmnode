% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

-module(cbt_btree_copy).

-export([copy/3]).

-include("cbt.hrl").

-define(CHUNK_THRESHOLD, 16#4ff).

-record(acc, {
    btree,
    ref,
    mod,
    before_kv_write = {fun(Item, Acc) -> {Item, Acc} end, []},
    filter = fun(_) -> true end,
    compression = ?DEFAULT_COMPRESSION,
    kv_chunk_threshold,
    kp_chunk_threshold,
    nodes = dict:from_list([{1, []}]),
    cur_level = 1,
    max_level = 1
}).

-type cbt_copy_options() :: [{backend, cbt_file | atom()}
                            | {before_kv_write, {fun(), any()}}
                            | {filter, fun()}
                            | override
                            | {compression, cbt_compress:compression_method()}].
-export_type([cbt_copy_options/0]).

%% @doc copy a btree to a cbt file process.
%% Options are:
%% <ul>
%% <li> {backend, Module} : backend to use to read/append btree items. Default
%% is cbt_file.</li>
%% <li>`{before_kv_write, fun(Item, Acc) -> {Newttem, NewAcc} end, InitAcc}':
%% to edit a Key/Vlaue before it's written to the new btree.</li>
%% <li>`{filter, fun(Item) -> true | false end}', function to filter the
%% items copied to the new btree.</li>
%% <li>`override': if the new file should be truncated</li>
%% <li>`{compression, Module}': to change the compression on the new
%% btree.</li>
%% </ul>
-spec copy(Bt :: cbt_btree:cbtree(), Ref :: cbt_backend:ref(), cbt_copy_options()) ->
    {ok, cbt_btree:cbtree_root(), any()}.
copy(Btree, Ref, Options) ->
    %% use custom backend if needed
    Mod = proplists:get_value(backend, Options, cbt_file),
    %% override the file
    case lists:member(override, Options) of
        true ->
            ok = Mod:empty(Ref);
        false ->
            ok
    end,
    Acc0 = #acc{btree = Btree,
                ref = Ref,
                mod = Mod,
                kv_chunk_threshold = Btree#btree.kv_chunk_threshold,
                kp_chunk_threshold = Btree#btree.kp_chunk_threshold},
    Acc = apply_options(Options, Acc0),
    {ok, _, #acc{cur_level = 1} = FinalAcc0} = cbt_btree:fold(
        Btree, fun fold_copy/3, Acc, []),
    {ok, CopyRootState, FinalAcc} = finish_copy(FinalAcc0),
    ok = Mod:sync(Ref),
    {_, LastUserAcc} = FinalAcc#acc.before_kv_write,
    {ok, CopyRootState, LastUserAcc}.

apply_options([], Acc) ->
    Acc;
apply_options([{backend, Mod} | Rest], Acc) ->
    apply_options(Rest, Acc#acc{mod = Mod});
apply_options([{before_kv_write, {Fun, UserAcc}} | Rest], Acc) ->
    apply_options(Rest, Acc#acc{before_kv_write = {Fun, UserAcc}});
apply_options([{filter, Fun} | Rest], Acc) ->
    apply_options(Rest, Acc#acc{filter = Fun});
apply_options([override | Rest], Acc) ->
    apply_options(Rest, Acc);
apply_options([{compression, Comp} | Rest], Acc) ->
    apply_options(Rest, Acc#acc{compression = Comp});
apply_options([{kv_chunk_threshold, Threshold} | Rest], Acc) ->
    apply_options(Rest, Acc#acc{kv_chunk_threshold = Threshold});
apply_options([{kp_chunk_threshold, Threshold} | Rest], Acc) ->
    apply_options(Rest, Acc#acc{kp_chunk_threshold = Threshold}).

extract(#acc{btree = #btree{extract_kv = identity}}, Value) ->
    Value;
extract(#acc{btree = #btree{extract_kv = Extract}}, Value) ->
    Extract(Value).

assemble(#acc{btree = #btree{assemble_kv = identity}}, KeyValue) ->
    KeyValue;
assemble(#acc{btree = #btree{assemble_kv = Assemble}}, KeyValue) ->
    Assemble(KeyValue).


before_leaf_write(#acc{before_kv_write = {Fun, UserAcc0}} = Acc, KVs) ->
    {NewKVs, NewUserAcc} = lists:mapfoldl(
        fun({K, _V}=KV, UAcc) ->
            Item = assemble(Acc, KV),
            {NewItem, UAcc2} = Fun(Item, UAcc),
            {K, _NewValue} = NewKV = extract(Acc, NewItem),
            {NewKV, UAcc2}
        end,
        UserAcc0, KVs),
    {NewKVs, Acc#acc{before_kv_write = {Fun, NewUserAcc}}}.


write_leaf(#acc{ref = Ref, mod=Mod, compression = Comp}, Node, Red) ->
    {ok, Pos, Size} = Mod:append_term(Ref, Node, [{compression, Comp}]),
    {ok, {Pos, Red, Size}}.


write_kp_node(#acc{ref = Ref, mod=Mod, btree = Bt, compression = Comp}, NodeList) ->
    {ChildrenReds, ChildrenSize} = lists:foldr(
        fun({_Key, {_P, Red, Sz}}, {AccR, AccSz}) ->
            {[Red | AccR], Sz + AccSz}
        end,
        {[], 0}, NodeList),
    Red = case Bt#btree.reduce of
    nil -> [];
    _ ->
        cbt_btree:final_reduce(Bt, {[], ChildrenReds})
    end,
    {ok, Pos, Size} = Mod:append_term(
        Ref, {kp_node, NodeList}, [{compression, Comp}]),
    {ok, {Pos, Red, ChildrenSize + Size}}.


fold_copy(Item, _Reds, #acc{nodes = Nodes, cur_level = 1, filter = Filter} = Acc) ->
    case Filter(Item) of
    false ->
        {ok, Acc};
    true ->
        {K, V} = extract(Acc, Item),
        LevelNode = dict:fetch(1, Nodes),
        LevelNodes2 = [{K, V} | LevelNode],
        NextAcc = case ?term_size(LevelNodes2) >= Acc#acc.kv_chunk_threshold of
        true ->
            {LeafState, Acc2} = flush_leaf(LevelNodes2, Acc),
            bubble_up({K, LeafState}, Acc2);
        false ->
            Acc#acc{nodes = dict:store(1, LevelNodes2, Nodes)}
        end,
        {ok, NextAcc}
    end.


bubble_up({Key, NodeState}, #acc{cur_level = Level} = Acc) ->
    bubble_up({Key, NodeState}, Level, Acc).

bubble_up({Key, NodeState}, Level, #acc{max_level = MaxLevel,
                                        nodes = Nodes} = Acc) ->
    Acc2 = Acc#acc{nodes = dict:store(Level, [], Nodes)},
    case Level of
    MaxLevel ->
        Acc2#acc{
            nodes = dict:store(Level + 1, [{Key, NodeState}], Acc2#acc.nodes),
            max_level = Level + 1
        };
    _ when Level < MaxLevel ->
        NextLevelNodes = dict:fetch(Level + 1, Acc2#acc.nodes),
        NextLevelNodes2 = [{Key, NodeState} | NextLevelNodes],
        case ?term_size(NextLevelNodes2) >= Acc#acc.kp_chunk_threshold of
        true ->
            {ok, NewNodeState} = write_kp_node(
                Acc2, lists:reverse(NextLevelNodes2)),
            bubble_up({Key, NewNodeState}, Level + 1, Acc2);
        false ->
            Acc2#acc{
                nodes = dict:store(Level + 1, NextLevelNodes2, Acc2#acc.nodes)
            }
        end
    end.


finish_copy(#acc{cur_level = 1, max_level = 1, nodes = Nodes} = Acc) ->
    case dict:fetch(1, Nodes) of
    [] ->
        {ok, nil, Acc};
    [{_Key, _Value} | _] = KvList ->
        {RootState, Acc2} = flush_leaf(KvList, Acc),
        {ok, RootState, Acc2}
    end;

finish_copy(#acc{cur_level = Level, max_level = Level, nodes = Nodes} = Acc) ->
    case dict:fetch(Level, Nodes) of
    [{_Key, {Pos, Red, Size}}] ->
        {ok, {Pos, Red, Size}, Acc};
    NodeList ->
        {ok, RootState} = write_kp_node(Acc, lists:reverse(NodeList)),
        {ok, RootState, Acc}
    end;

finish_copy(#acc{cur_level = Level, nodes = Nodes} = Acc) ->
    case dict:fetch(Level, Nodes) of
    [] ->
        Acc2 = Acc#acc{cur_level = Level + 1},
        finish_copy(Acc2);
    [{LastKey, _} | _] = NodeList ->
        {UpperNodeState, Acc2} = case Level of
        1 ->
            flush_leaf(NodeList, Acc);
        _ when Level > 1 ->
            {ok, KpNodeState} = write_kp_node(Acc, lists:reverse(NodeList)),
            {KpNodeState, Acc}
        end,
        ParentNode = dict:fetch(Level + 1, Nodes),
        Acc3 = Acc2#acc{
            nodes = dict:store(Level + 1, [{LastKey, UpperNodeState} | ParentNode], Nodes),
            cur_level = Level + 1
        },
        finish_copy(Acc3)
    end.


flush_leaf(KVs, #acc{btree = Btree} = Acc) ->
    {NewKVs, Acc2} = before_leaf_write(Acc, lists:reverse(KVs)),
    Red = case Btree#btree.reduce of
        nil -> [];
        _ ->
            Items = case Btree#btree.assemble_kv of
                identity ->
                    NewKVs;
                _ ->
                    [assemble(Acc2, Kv) || Kv <- NewKVs]
            end,
            cbt_btree:final_reduce(Btree, {Items, []})
    end,
    {ok, LeafState} = write_leaf(Acc2, {kv_node, NewKVs}, Red),
    {LeafState, Acc2}.
