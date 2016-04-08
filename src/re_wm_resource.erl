%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(re_wm_resource).

-export([resources/0,
         routes/0,
         dispatch/0]).

-export([init/1,
         service_available/2,
         allowed_methods/2,
         content_types_provided/2,
         content_types_accepted/2,
         resource_exists/2,
         provide_content/2,
         delete_resource/2,
         process_post/2,
         provide_text_content/2,
         provide_static_content/2,
         accept_content/2,
         post_is_create/2,
         create_path/2,
         last_modified/2]).

-include_lib("webmachine/include/webmachine.hrl").
-include("re_wm.hrl").

-record(ctx, {route :: route()}).

%%%===================================================================
%%% API
%%%===================================================================

resources() ->
    [
     re_wm_explore,
     re_wm_control,
     re_wm_proxy,
     re_wm_static
    ].

routes() ->
    routes(resources(), []).

routes([], Routes) ->
    Routes;
routes([Resource|Rest], Routes) ->
    routes(Rest, Routes ++ Resource:routes()).

dispatch() ->
    build_wm_routes(routes(), []).

%%%===================================================================
%%% Webmachine Callbacks
%%%===================================================================

init(_) ->
    {ok, #ctx{}}.

service_available(ReqData, Ctx) ->
    Route = case get_route(routes(), ReqData) of
                #route{}=R ->
                    R;
                _ ->
                    [R] = re_wm_static:routes(),
                    R
            end,
    lager:info("-----------------------: ~p", [wrq:path(ReqData)]),
    lager:info("-----------------------: ~p", [Route]),
    {Available, ReqData1} = 
        case Route#route.available of
            {M, F} -> M:F(ReqData);
            Bool -> {Bool, ReqData}
        end,
    {Available, ReqData1, Ctx#ctx{route = Route}}.

allowed_methods(ReqData, Ctx = #ctx{route = Route}) ->
    {Route#route.methods, ReqData, Ctx}.

content_types_provided(ReqData, Ctx = #ctx{route = Route}) ->
    case Route#route.provides of
        {M, F} ->
            {CTs, ReqData1} = M:F(ReqData),
            {CTs, ReqData1, Ctx};
        Provides ->
            {Provides, ReqData, Ctx}
     end.

content_types_accepted(ReqData, Ctx = #ctx{route = Route}) ->
    {Route#route.accepts, ReqData, Ctx}.

resource_exists(ReqData, Ctx = #ctx{route = #route{exists = {M, F}}}) ->
    {Success, ReqData1} = M:F(ReqData),
    {Success, ReqData1, Ctx};
resource_exists(ReqData, Ctx = #ctx{route = #route{exists = Exists}})
  when is_boolean(Exists) ->
    {Exists, ReqData, Ctx}.

delete_resource(ReqData, Ctx = #ctx{route = #route{delete = {M, F}}}) ->
    {Success, ReqData1} = M:F(ReqData),
    {Success, ReqData1, Ctx}.

provide_content(ReqData, Ctx = #ctx{route = #route{content = {M, F}}}) ->
    {Body, ReqData1} = M:F(ReqData),
    {mochijson2:encode(Body), ReqData1, Ctx}.

provide_text_content(ReqData, Ctx = #ctx{route = #route{content = {M, F}}}) ->
    {Body, ReqData1} = M:F(ReqData),
    case is_binary(Body) of
        true ->
            {binary_to_list(Body), ReqData1, Ctx};
        false ->
            {Body, ReqData1, Ctx}
    end.

provide_static_content(ReqData, Ctx = #ctx{route = #route{content = {M, F}}}) ->
    {Body, ReqData1} = M:F(ReqData),
    {Body, ReqData1, Ctx}.

accept_content(ReqData, Ctx = #ctx{route = #route{accept = {M, F}}}) ->
    {Success, ReqData1} = M:F(ReqData),
    {Success, ReqData1, Ctx};
accept_content(ReqData, Ctx = #ctx{route = #route{accept = undefined}}) ->
    {false, ReqData, Ctx}.

process_post(ReqData, Ctx = #ctx{route = #route{accept = {M, F}}}) ->
    {Success, ReqData1} = M:F(ReqData),
    {Success, ReqData1, Ctx}.

post_is_create(ReqData, Ctx = #ctx{route = #route{post_create = PostCreate}}) ->
    {PostCreate, ReqData, Ctx}.

create_path(ReqData, Ctx = #ctx{route = #route{post_path = {M, F}}}) ->
    {Path, ReqData1} = M:F(ReqData),
    {Path, ReqData1, Ctx}.

last_modified(ReqData, Ctx = #ctx{route = #route{last_modified = undefined}}) ->
    {undefined, ReqData, Ctx};
last_modified(ReqData, Ctx = #ctx{route = #route{last_modified = {M, F}}}) ->
    {LM, ReqData1} = M:F(ReqData),
    {LM, ReqData1, Ctx}.

%% ====================================================================
%% Private
%% ====================================================================

get_route([], _ReqData) ->
    undefined;
get_route([Route=#route{base=[],path=Paths} | Rest], ReqData) ->
    case get_route_path([], Paths, Route, ReqData) of
        undefined ->
            get_route(Rest, ReqData);
        R -> R
    end;
get_route([Route=#route{base=Bases,path=[]} | Rest], ReqData) ->
    case get_route_path([], Bases, Route, ReqData) of
        undefined ->
            get_route(Rest, ReqData);
        R -> R
    end;
get_route([Route=#route{base=Bases,path=Paths} | Rest], ReqData) ->
    case get_route_base(Bases, Paths, Route, ReqData) of
        undefined ->
            get_route(Rest, ReqData);
        R -> R
    end.


get_route_base([], _, _, _) ->
    undefined;
get_route_base([Base|Rest], Paths, Route, ReqData) ->
    case get_route_path(Base, Paths, Route, ReqData) of
        undefined ->
            get_route_base(Rest, Paths, Route, ReqData);
        R -> R
    end.

get_route_path(_, [], _, _) ->
    undefined;
get_route_path(Base, [Path|Rest], Route, ReqData) ->
    ReqPath = string:tokens(wrq:path(ReqData), "/"),
    case expand_path(Base ++ Path, ReqData, []) of
        ReqPath ->
            Route;
        _ ->
            get_route_path(Base, Rest, Route, ReqData)
    end.

expand_path([], _ReqData, Acc) ->
    lists:reverse(Acc);
expand_path([Part|Rest], ReqData, Acc) when is_list(Part) ->
    expand_path(Rest, ReqData, [Part | Acc]);
expand_path(['*'|Rest], ReqData, Acc) ->
    Tokens = string:tokens(wrq:path(ReqData), "/"),
    case length(Acc) > length(Tokens) of
        true ->
            undefined;
        false ->
            expand_path(Rest, ReqData, lists:reverse(lists:nthtail(length(Acc), Tokens)) ++ Acc)
    end;
expand_path([Part|Rest], ReqData, Acc) when is_atom(Part) ->
    expand_path(Rest, ReqData, [wrq:path_info(Part, ReqData) | Acc]).

build_wm_routes([], Acc) ->
    lists:reverse(lists:flatten(Acc));
build_wm_routes([#route{base = [], path = Paths} | Rest], Acc) ->
    build_wm_routes(Rest, [build_wm_route([], Paths, []) | Acc]);
build_wm_routes([#route{base = Bases, path = []} | Rest], Acc) ->
    build_wm_routes(Rest, [build_wm_route([], Bases, []) | Acc]);
build_wm_routes([#route{base = Bases, path = Paths} | Rest], Acc) ->
    build_wm_routes(Rest, [build_wm_routes(Bases, Paths, []) | Acc]).

build_wm_routes([], _, Acc) ->
    Acc;
build_wm_routes([Base|Rest], Paths, Acc) ->
    build_wm_routes(Rest, Paths, [build_wm_route(Base, Paths, [])|Acc]).

build_wm_route(_, [], Acc) ->
    Acc;
build_wm_route(Base, [Path|Rest], Acc) ->
    build_wm_route(Base, Rest, [{Base ++ Path, ?MODULE, []}|Acc]).
