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
    why/2,
    report_dict/1
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
middleware(rate_limited, 'rateLimit').




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

% Every lint rule is a traced rule: warn_why/4 derives the reasoning
% steps and the message from the same clause, so the report and the
% proof cannot drift apart. warn/3 is just warn_why/4 with the steps
% thrown away.
warn(Type, Name, Msg) :-
    warn_why(Type, Name, _Steps, Msg).

route_fact_step(Name, Method, Path, Features, Step) :-
    format(string(Step),
           "route(~w, ~w, ~w, ~w) is a declared fact",
           [Name, Method, Path, Features]).

mutating_step(Method, Step) :-
    format(string(Step),
           "~w is a mutating method, so requests carry a body",
           [Method]).

warn_why(missing_validation, Name, [RouteFact, MutStep, Absence], Msg) :-
    route(Name, Method, Path, Features),
    mutating_method(Method),
    \+ has_validation(Features),
    route_fact_step(Name, Method, Path, Features, RouteFact),
    mutating_step(Method, MutStep),
    format(string(Absence),
           "no validated(_) feature appears in ~w", [Features]),
    format(string(Msg),
           "~w ~w has no validation; ~w bodies should be schema-checked",
           [Method, Path, Method]).

warn_why(unknown_feature, Name, [RouteFact, Orphan], Msg) :-
    route(Name, Method, Path, Features),
    member(F, Features),
    \+ middleware(F, _),
    route_fact_step(Name, Method, Path, Features, RouteFact),
    format(string(Orphan),
           "feature ~w matches no middleware/2 clause", [F]),
    format(string(Msg),
           "feature ~w has no middleware mapping and would be silently dropped",
           [F]).

warn_why(route_conflict, Name, [RouteFact, OtherFact, Clash], Msg) :-
    route(Name, Method, Path, Features),
    route(Other, Method, Path, OtherFeatures),
    Name @< Other,
    route_fact_step(Name, Method, Path, Features, RouteFact),
    format(string(OtherFact),
           "route(~w, ~w, ~w, ~w) is also a declared fact",
           [Other, Method, Path, OtherFeatures]),
    format(string(Clash),
           "both claim ~w ~w, so one handler will never be reached",
           [Method, Path]),
    format(string(Msg),
           "~w ~w also defined by ~w",
           [Method, Path, Other]).

% Getting into suggestions.
suggest(Suggestions) :-
    findall(suggestion(Type, Name, Msg),
            suggest_one(Type, Name, Msg),
            Suggestions).

% Paths that look like authentication endpoints. auth_word/1 names the
% clue so a trace can cite which word gave the path away.
auth_word(login).
auth_word(auth).
auth_word(password).

auth_path(Path) :- auth_word(Word), sub_atom(Path, _, _, _, Word).

% Suggestions are traced rules too, same deal as warn/3.
suggest_one(Type, Name, Msg) :-
    suggest_why(Type, Name, _Steps, Msg).

% rate limiting is cheap.
suggest_why(add_rate_limit, Name, [RouteFact, Clue, Absence], Msg) :-
    route(Name, Method, Path, Features),
    auth_word(Word),
    sub_atom(Path, _, _, _, Word),
    \+ member(rate_limited, Features),
    route_fact_step(Name, Method, Path, Features, RouteFact),
    format(string(Clue),
           "path ~w contains \"~w\", so auth_path(~w) holds",
           [Path, Word, Path]),
    format(string(Absence),
           "rate_limited is not among ~w", [Features]),
    format(string(Msg),
           "~w looks like an auth endpoint; add rate_limited to slow attacks",
           [Path]).

% Changing routes reachable from a browser should carry CSRF protection
suggest_why(add_csrf, Name, [RouteFact, MutStep, Absence], Msg) :-
    route(Name, Method, Path, Features),
    mutating_method(Method),
    \+ member(csrf, Features),
    route_fact_step(Name, Method, Path, Features, RouteFact),
    mutating_step(Method, MutStep),
    format(string(Absence),
           "csrf is not among ~w", [Features]),
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

% report_dict/1 packages everything the program can say about the
% current routes into one dict
report_dict(_{code: Codes, warnings: Warnings, suggestions: Suggestions}) :-
    findall(Code,
            ( route(Name, _, _, _),
              generate_route(Name, Code) ),
            Codes),
    lint(Lint),
    maplist(warning_dict, Lint, Warnings),
    suggest(Suggest),
    maplist(suggestion_dict, Suggest, Suggestions).

warning_dict(warning(Type, Name, Msg),
             _{type: Type, route: Name, message: Msg}).

suggestion_dict(suggestion(Type, Name, Msg),
                _{type: Type, route: Name, message: Msg}).

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

% why also answers for the linter and the suggester. The reasoning
% steps come from the same traced rule that raised the finding, and the
% conclusion is the exact line the driver prints, so an explanation can
% only exist where the finding actually holds.
why(warning(Type, Name), Steps) :-
    warn_why(Type, Name, Reasoning, Msg),
    format(string(Conclusion), "therefore: [!] ~w (~w): ~w",
           [Name, Type, Msg]),
    append(Reasoning, [Conclusion], Steps).

why(suggestion(Type, Name), Steps) :-
    suggest_why(Type, Name, Reasoning, Msg),
    format(string(Conclusion), "therefore: [+] ~w (~w): ~w",
           [Name, Type, Msg]),
    append(Reasoning, [Conclusion], Steps).
