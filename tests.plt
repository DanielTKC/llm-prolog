:- use_module(express_patterns).
:- begin_tests(route_store, [cleanup(clear_routes)]).

test(assert_and_lookup) :-
    assert_route(route(home, get, "/", [auth])),
    route(home, get, "/", [auth]).

test(clear_removes_routes) :-
    assert_route(route(home, get, "/", [])),
    clear_routes,
    \+ route(home, _, _, _).

:- end_tests(route_store).
:- initialization(run_tests, main).