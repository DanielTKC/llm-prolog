:- use_module(express_patterns).
:- begin_tests(nothingburger).

test(trivial) :-
    1=:=1.

:- end_tests(nothingburger).
:- initialization(run_tests, main).