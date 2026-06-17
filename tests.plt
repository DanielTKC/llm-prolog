:- use_module(express_patterns).
setup_routes(Routes) :-
    express_patterns:clear_routes,
    forall(member(R, Routes), express_patterns:assert_route(R)).
:- begin_tests(middleware_chain,
   [setup(setup_routes([route(public_ping, get, '/ping', [])
   ]))]).

test(empty_features_empty_chain) :-
    middleware_chain(public_ping, Chain),
    Chain == [].
:- end_tests(middleware_chain).

:- initialization(run_tests, main).