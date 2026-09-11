% MCP stdio server: the oracle answers its own phone.
%
% The hook rejects finished homework at the door; this server answers
% questions mid-task. It speaks JSON-RPC 2.0 over stdin/stdout, one
% message per line, and only knows the four methods MCP actually needs:
% initialize, notifications/initialized, tools/list, tools/call.
%
% Handlers are pure predicates over dicts (mcp_handle/2) so the whole
% protocol is testable without ever touching a pipe. main/0 is just a
% read-dispatch-write loop around them.
%
% Run it: swipl mcp_server.pl
:- module(mcp_server, [
    mcp_handle/2
]).

:- use_module(express_patterns).
:- use_module(library(json)).

% ---- dispatch -------------------------------------------------------

% mcp_handle(+Message, -Response) takes one decoded JSON-RPC message
% and produces either a response dict or the atom none (notifications
% get no reply).
mcp_handle(Msg, Response) :-
    (   get_dict(id, Msg, Id) -> true ; Id = none ),
    get_dict(method, Msg, Method),
    (   get_dict(params, Msg, Params) -> true ; Params = _{} ),
    once(handle_method(Method, Params, Id, Response)).

handle_method(initialize, Params, Id, Reply) :-
    (   get_dict(protocolVersion, Params, Version) -> true
    ;   Version = '2025-06-18' ),
    Reply = _{jsonrpc: "2.0", id: Id,
              result: _{protocolVersion: Version,
                        capabilities: _{tools: _{}},
                        serverInfo: _{name: "prolog-oracle",
                                      version: "0.1.0"}}}.

handle_method('notifications/initialized', _, _, none).
handle_method('notifications/cancelled', _, _, none).

handle_method(ping, _, Id, _{jsonrpc: "2.0", id: Id, result: _{}}).

handle_method('tools/list', _, Id,
              _{jsonrpc: "2.0", id: Id, result: _{tools: Tools}}) :-
    findall(Spec, tool_spec(_, Spec), Tools).

handle_method('tools/call', Params, Id, Reply) :-
    get_dict(name, Params, Tool),
    (   get_dict(arguments, Params, Args) -> true ; Args = _{} ),
    safe_call_tool(Tool, Args, Outcome),
    tool_reply(Outcome, Id, Reply).

% Anything else: unknown notifications are ignored, unknown requests
% get the JSON-RPC "method not found" error.
handle_method(_, _, none, none).
handle_method(Method, _, Id, _{jsonrpc: "2.0", id: Id, error: Error}) :-
    format(string(Message),
           "method ~w is not part of this oracle's vocabulary", [Method]),
    Error = _{code: -32601, message: Message}.

tool_reply(ok(Payload), Id,
           _{jsonrpc: "2.0", id: Id,
             result: _{content: [_{type: "text", text: Text}],
                       isError: false}}) :-
    dict_json_text(Payload, Text).
tool_reply(error(Text), Id,
           _{jsonrpc: "2.0", id: Id,
             result: _{content: [_{type: "text", text: Text}],
                       isError: true}}).

% A tool that fails or throws becomes an isError result with a reason,
% never a dead line on the wire.
safe_call_tool(Tool, Args, Outcome) :-
    catch(
        (   call_tool(Tool, Args, Payload)
        ->  Outcome = ok(Payload)
        ;   format(string(Text),
                   "tool ~w could not derive a result from those arguments",
                   [Tool]),
            Outcome = error(Text)
        ),
        Caught,
        (   Caught = oracle_error(Text)
        ->  Outcome = error(Text)
        ;   format(string(Text), "tool ~w raised ~w", [Tool, Caught]),
            Outcome = error(Text)
        )).

% ---- the four tools -------------------------------------------------

% Every tool takes the routes inline, loads them into the store, and
% asks the same predicates the driver uses. Nothing is duplicated: the
% oracle on the phone and the gate at the door share one rulebook.
load_spec(Args) :-
    get_dict(routes, Args, RouteDicts),
    clear_routes,
    forall(member(Dict, RouteDicts),
           (   route_from_json(Dict, Route),
               assert_route(Route) )).

call_tool(generate, Args, _{code: Codes}) :-
    load_spec(Args),
    findall(Code,
            (   route(Name, _, _, _),
                generate_route(Name, Code) ),
            Codes).

call_tool(lint, Args, _{warnings: Warnings}) :-
    load_spec(Args),
    lint(Raw),
    findall(_{type: Type, route: Name, message: Msg},
            member(warning(Type, Name, Msg), Raw),
            Warnings).

call_tool(suggest, Args, _{suggestions: Suggestions}) :-
    load_spec(Args),
    suggest(Raw),
    findall(_{type: Type, route: Name, message: Msg},
            member(suggestion(Type, Name, Msg), Raw),
            Suggestions).

call_tool(why, Args, _{derivations: Derivations}) :-
    load_spec(Args),
    why_subject(Args, Subject),
    findall(Steps, why(Subject, Steps), Derivations),
    (   Derivations == []
    ->  format(string(Text),
               "nothing to prove: ~w does not hold for these routes",
               [Subject]),
        throw(oracle_error(Text))
    ;   true
    ).

why_subject(Args, Subject) :-
    get_dict(kind, Args, Kind),
    get_dict(name, Args, Name),
    (   Kind == route
    ->  Subject = Name
    ;   get_dict(type, Args, Type),
        Subject =.. [Kind, Type, Name]
    ).

% ---- tool catalogue -------------------------------------------------

routes_schema(_{
    type: array,
    description: "Route spec, same shape as the routes array in a spec file",
    items: _{type: object,
             properties: _{
                 name: _{type: string},
                 method: _{type: string,
                           enum: [get, post, put, patch, delete]},
                 path: _{type: string},
                 features: _{type: array,
                             description: "Feature atoms like \"auth\", or single-key objects like {\"validated\": \"user_schema\"}"}
             },
             required: [name, method, path, features]}
}).

tool_spec(generate, _{name: generate,
                      description: "Generate Express router code from a route spec. Returns {code: [lines]}.",
                      inputSchema: Schema}) :-
    routes_schema(Routes),
    Schema = _{type: object,
               properties: _{routes: Routes},
               required: [routes]}.

tool_spec(lint, _{name: lint,
                  description: "Lint a route spec for defects (missing validation, unknown features, route conflicts). Returns {warnings: [{type, route, message}]}. Warnings block the gate.",
                  inputSchema: Schema}) :-
    routes_schema(Routes),
    Schema = _{type: object,
               properties: _{routes: Routes},
               required: [routes]}.

tool_spec(suggest, _{name: suggest,
                     description: "Suggest security hardening for a route spec (rate limiting on auth paths, csrf on mutating routes). Returns {suggestions: [{type, route, message}]}. Suggestions advise; they do not block.",
                     inputSchema: Schema}) :-
    routes_schema(Routes),
    Schema = _{type: object,
               properties: _{routes: Routes},
               required: [routes]}.

tool_spec(why, _{name: why,
                 description: "Ask for the derivation behind a route, warning, or suggestion. Every step cites a declared fact or a rule; the conclusion is the exact generated code or report line. Returns {derivations: [[step, ...]]}. Refuses to explain anything the rules cannot prove.",
                 inputSchema: Schema}) :-
    routes_schema(Routes),
    Schema = _{type: object,
               properties: _{
                   routes: Routes,
                   kind: _{type: string,
                           enum: [route, warning, suggestion]},
                   name: _{type: string,
                           description: "The route name"},
                   type: _{type: string,
                           description: "The warning or suggestion type; required unless kind is route"}
               },
               required: [routes, kind, name]}.

% ---- the wire -------------------------------------------------------

dict_json_text(Dict, Text) :-
    with_output_to(string(Text),
                   json_write_dict(current_output, Dict, [width(0)])).

main :-
    serve.

serve :-
    read_line_to_string(user_input, Line),
    (   Line == end_of_file
    ->  true
    ;   handle_line(Line),
        serve
    ).

handle_line("") :- !.
handle_line(Line) :-
    catch(
        (   setup_call_cleanup(
                open_string(Line, In),
                json_read_dict(In, Msg, [value_string_as(atom)]),
                close(In)),
            mcp_handle(Msg, Response),
            emit(Response)
        ),
        Caught,
        format(user_error, "prolog-oracle: ~w~n", [Caught])).

emit(none) :- !.
emit(Response) :-
    json_write_dict(user_output, Response, [width(0)]),
    nl(user_output),
    flush_output(user_output).

:- initialization(main, main).
