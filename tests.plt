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

% Runnin routes
:- begin_tests(generate_route,
   [setup(setup_routes([
       route(users_list,    get,    '/users',            [auth, paginated]),
       route(user_create,   post,   '/users',            [auth, validated(user_schema)]),
       route(user_delete,   delete, '/users/:id',        [auth, admin_only]),
       route(public_ping,   get,    '/ping',             []),
       route(upload_avatar, post,   '/users/:id/avatar', [auth, file_upload])
   ]))]).

test(no_middleware_still_renders_handler) :-
    generate_route(public_ping, Code),
    Code == "router.get('/ping', public_pingHandler);".

test(renders_method_path_chain_and_handler) :-
    generate_route(users_list, Code),
    Code == "router.get('/users', authenticate, paginate, users_listHandler);".

test(param_validation_renders) :-
    generate_route(user_create, Code),
    Code == "router.post('/users', authenticate, validate(user_schema), user_createHandler);".

test(delete_with_admin_check) :-
    generate_route(user_delete, Code),
    Code == "router.delete('/users/:id', authenticate, requireAdmin, user_deleteHandler);".

:- end_tests(generate_route).

% lint/1  is for missing validations
:- begin_tests(lint_missing_validation,
   [setup(setup_routes([
       route(users_list,    get,    '/users',            [auth, paginated]),
       route(user_create,   post,   '/users',            [auth, validated(user_schema)]),
       route(upload_avatar, post,   '/users/:id/avatar', [auth, file_upload]),
       route(public_ping,   get,    '/ping',             [])
   ]))]).

test(post_without_validation_warns) :-
    express_patterns:lint(Warnings),
    memberchk(warning(missing_validation, upload_avatar, _), Warnings).

test(post_with_validation_is_clean) :-
    express_patterns:lint(Warnings),
    \+ memberchk(warning(missing_validation, user_create, _), Warnings).

test(get_never_needs_validation) :-
    express_patterns:lint(Warnings),
    \+ memberchk(warning(missing_validation, public_ping, _), Warnings).

:- end_tests(lint_missing_validation).

:- begin_tests(lint_unknown_feature,
   [setup(setup_routes([
       route(users_list, get,  '/users', [auth, paginated]),
       route(bad_route,  post, '/bad',   [auth, validted(user_schema)])
   ]))]).

test(unmapped_feature_warns) :-
    express_patterns:lint(Warnings),
    memberchk(warning(unknown_feature, bad_route, _), Warnings).

test(mapped_features_are_clean) :-
    express_patterns:lint(Warnings),
    \+ memberchk(warning(unknown_feature, users_list, _), Warnings).

:- end_tests(lint_unknown_feature).

:- initialization(run_tests, main).