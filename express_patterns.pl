:- module(express_patterns, [
    route/4,
    assert_route/1,
    clear_routes/0,
    middleware/2,
    middleware_chain/2
]).

:- dynamic route/4.
assert_route(route(Name, Method, Path, Features)) :-
    assertz(route(Name, Method, Path, Features)).

clear_routes :-
    retractall(route(_,_,_,_)).

middleware(auth,'authenticate').
middleware(paginated, 'paginate').


middleware_chain(Name, Chain) :-
    route(Name, _Method, _Path, Features),
    findall(Mw, (member(F, Features), middleware(F, Mw)), Chain).
