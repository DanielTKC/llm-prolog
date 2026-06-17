:- module(express_patterns, [
    route/4,
    assert_route/1,
    clear_routes/0
]).

:- dynamic route/4.
assert_route(route(Name, Method, Path, Features)) :-
    assertz(route(Name, Method, Path, Features)).

clear_routes :-
    retractall(route(_,_,_,_)).
