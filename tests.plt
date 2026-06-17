:- use_module(express_patterns).
setup_routes(Routes) :-
    express_patterns:clear_routes,
    forall(member(R, Routes), express_patterns:assert_route(R)).

:- begin_tests(middleware_chain,
   [setup(setup_routes([
        route(users_list,  get, '/users', [auth, paginated]),
        route(user_create,  post, '/users', [auth, validated(user_schema)]),
        route(upload_avatar, post, '/users/:id/avatar', [auth, file_upload]),
        route(public_ping, get, '/ping', [])
   ]))]).
test(simple_features_expand_in_order) :-
    middleware_chain(users_list, Chain),
    Chain == ['authenticate', 'paginate'].

test(empty_features_empty_chain) :-
    middleware_chain(public_ping, Chain),
    Chain == [].
:- end_tests(middleware_chain).

:- initialization(run_tests, main).