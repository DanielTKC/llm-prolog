% CLI driver: swipl driver.pl [--json] examples/routes.json
% Prints the generated Express code, lint warnings, and security
% suggestions. The exit code is the verdict: 0 means the spec is clean,
% 1 means the linter has warnings, 2 means the spec never loaded.
% Hooks and CI can gate on it.
:- use_module(express_patterns).
:- use_module(library(json)).

main :-
    current_prolog_flag(argv, Argv),
    parse_args(Argv, Mode, File),
    !,
    load_routes_json(File),
    report_dict(Report),
    print_report(Mode, Report),
    verdict(Report).
main :-
    format(user_error, "Usage: swipl driver.pl [--json] <routes.json>~n", []),
    halt(2).

parse_args(['--json', File], json, File).
parse_args([File], human, File) :-
    File \== '--json'.

print_report(json, Report) :-
    json_write_dict(current_output, Report),
    nl.
print_report(human, Report) :-
    forall(member(Code, Report.code),
           format("~w~n", [Code])),
    nl,
    forall(member(W, Report.warnings),
           format("[!] ~w (~w): ~w~n", [W.route, W.type, W.message])),
    nl,
    forall(member(S, Report.suggestions),
           format("[+] ~w (~w): ~w~n", [S.route, S.type, S.message])).

% Warnings block. Suggestions advise. That line matters: a gate that
% nags about optional hardening trains everyone to bypass the gate.
verdict(Report) :-
    Report.warnings == [],
    !,
    halt(0).
verdict(_) :-
    halt(1).

:- initialization(main, main).
