% CLI driver: swipl driver.pl examples/routes.json
% Loads routes from a JSON file, then prints the generated Express
% code,
:- use_module(express_patterns).

print_code :-
    forall(route(Name, _, _, _),
           ( generate_route(Name, Code),
             format("~w~n", [Code]) )).

print_warnings :-
    lint(Warnings),
    forall(member(warning(Type, Name, Msg), Warnings),
           format("[!] ~w (~w): ~w~n", [Name, Type, Msg])).

print_suggestions :-
    suggest(Suggestions),
    forall(member(suggestion(Type, Name, Msg), Suggestions),
           format("[+] ~w (~w): ~w~n", [Name, Type, Msg])).

main :-
    current_prolog_flag(argv, [File|_]),
    load_routes_json(File),
    print_code,
    nl,
    print_warnings,
    nl,
    print_suggestions.
main :-
    format("Usage: swipl driver.pl <routes.json>~n", []),
    halt(1).

:- initialization(main, main).