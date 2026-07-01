:- module(express_patterns, [
    route/4,
    assert_route/1,
    clear_routes/0,
    middleware/2,
    middleware_chain/2,
    generate_route/2,
    lint/1,
    suggest/1,
    load_routes_json/1,
    why/2
]).

:- dynamic route/4.
assert_route(route(Name, Method, Path, Features)) :-
    assertz(route(Name, Method, Path, Features)).

clear_routes :-
    retractall(route(_,_,_,_)).

middleware(auth,'authenticate').
middleware(paginated, 'paginate').
middleware(file_upload, 'upload.single("file")').
middleware(validated(Schema), Mw) :-
    format(atom(Mw), 'validate(~w)', [Schema]).
middleware(admin_only, 'requireAdmin').
middleware(csrf, 'csrfProtection').



middleware_chain(Name, Chain) :-
    route(Name, _Method, _Path, Features),
    findall(Mw, (member(F, Features), middleware(F, Mw)), Chain).

generate_route(Name, Code) :-
    route(Name, Method, Path, _Features),
    middleware_chain(Name, Chain),
    format(atom(HandlerAtom), '~wHandler', [Name]),
    append(Chain, [HandlerAtom], CallArgs),
    atomic_list_concat(CallArgs, ', ', ArgsAtom),
    format(string(Code),
           "router.~w('~w', ~w);",
           [Method, Path, ArgsAtom]).

% lint/1 gathers every warning that fires across the route. Each
% warning is warning(Type, RouteName, Message): the Type names the rule,
% so a complaint can be traced back to the clause that raised it
lint(Warnings) :-
    findall(warning(Type, Name, Msg), warn(Type, Name, Msg), Warnings).


mutating_method(post).
mutating_method(put).
mutating_method(patch).

has_validation(Features) :- member(validated(_), Features).


warn(missing_validation, Name, Msg) :-
    route(Name, Method, Path, Features),
    mutating_method(Method),
    \+ has_validation(Features),
    format(string(Msg),
           "~w ~w has no validation; ~w bodies should be schema-checked",
           [Method, Path, Method]).


warn(unknown_feature, Name, Msg) :-
    route(Name, _, _, Features),
    member(F, Features),
    \+ middleware(F, _),
    format(string(Msg),
           "feature ~w has no middleware mapping and would be silently dropped",
           [F]).


warn(route_conflict, Name, Msg) :-
    route(Name, Method, Path, _),
    route(Other, Method, Path, _),
    Name @< Other,
    format(string(Msg),
           "~w ~w also defined by ~w",
           [Method, Path, Other]).

% Getting into suggestions.
suggest(Suggestions) :-
    findall(suggestion(Type, Name, Msg),
            suggest_one(Type, Name, Msg),
            Suggestions).

% Paths that look like authentication endpoints.
auth_path(Path) :- sub_atom(Path, _, _, _, login).
auth_path(Path) :- sub_atom(Path, _, _, _, auth).
auth_path(Path) :- sub_atom(Path, _, _, _, password).

% rate limiting is cheap.
suggest_one(add_rate_limit, Name, Msg) :-
    route(Name, _, Path, Features),
    auth_path(Path),
    \+ member(rate_limited, Features),
    format(string(Msg),
           "~w looks like an auth endpoint; add rate_limited to slow attacks",
           [Path]).

% Changing routes reachable from a browser should carry CSRF protection
suggest_one(add_csrf, Name, Msg) :-
    route(Name, Method, Path, Features),
    mutating_method(Method),
    \+ member(csrf, Features),
    format(string(Msg),
           "~w ~w changes state from a browser; add csrf protection",
           [Method, Path]).

%JSON loading routes arrive like {"routes":[...]}
feature_from_json(Feature0, Feature) :-
    is_dict(Feature0), !,
    dict_pairs(Feature0, _, [Key-Value]),
    Feature =.. [Key, Value].
feature_from_json(Feature, Feature).

route_from_json(Dict, route(Name, Method, Path, Features)) :-
    get_dict(name, Dict, Name),
    get_dict(method, Dict, Method),
    get_dict(path, Dict, Path),
    get_dict(features, Dict, Features0),
    maplist(feature_from_json, Features0, Features).

load_routes_json(File) :-
    setup_call_cleanup(
        open(File, read, Stream),
        json_read_dict(Stream, Doc, [value_string_as(atom)]),
        close(Stream)),
    get_dict(routes, Doc, RouteDicts),
    forall(member(D, RouteDicts),
           ( route_from_json(D, Route),
             assert_route(Route) )).

%  Tell me why, ain't nothing but a fact trace
% Could not resist the BSB reference
why(Name, Steps) :-
    route(Name, Method, Path, Features),
    format(string(RouteFact),
           "route(~w, ~w, ~w, ~w) is a declared fact",
           [Name, Method, Path, Features]),
    findall(Step,
            ( member(F, Features),
              middleware(F, Mw),
              format(string(Step),
                     "feature ~w maps to middleware ~w", [F, Mw]) ),
            FeatureSteps),
    format(string(HandlerConvention),
           "handler ~wHandler follows the <name>Handler convention",
           [Name]),
    generate_route(Name, Code),
    format(string(Conclusion), "therefore: ~w", [Code]),
    append([[RouteFact], FeatureSteps, [HandlerConvention], [Conclusion]],
           Steps).
