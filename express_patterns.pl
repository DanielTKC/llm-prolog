:- module(express_patterns, [
    route/4,
    assert_route/1,
    clear_routes/0,
    middleware/2,
    middleware_chain/2,
    generate_route/2
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