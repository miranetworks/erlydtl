-module(erlydtl_runtime).

-compile(export_all).

-define(IFCHANGED_CONTEXT_VARIABLE, erlydtl_ifchanged_context).

find_value(_, undefined) ->
    undefined;
find_value(Key, Fun) when is_function(Fun, 1) ->
    Fun(Key);
find_value(Key, L) when is_atom(Key), is_list(L) ->
    case lists:keyfind(Key, 1, L) of
        false           -> find_value(atom_to_list(Key), L);
        {Key, Value}    -> Value
    end;
find_value(Key, L) when is_list(Key), is_list(L) ->
    case lists:keyfind(Key, 1, L) of
        false           -> find_value(list_to_binary(Key), L);
        {Key, Value}    -> Value
    end;
find_value(Key, L) when is_binary(Key), is_list(L) ->
    case lists:keyfind(Key, 1, L) of
        false           -> undefined;
        {Key, Value}    -> Value
    end;
find_value(Key, {GBSize, GBData}) when is_integer(GBSize) ->
    case gb_trees:lookup(Key, {GBSize, GBData}) of
        {value, Val} ->
            Val;
        _ ->
            undefined
    end;
find_value(Key, Tuple) when is_tuple(Tuple) ->
    Module = element(1, Tuple),
    case Module of
        dict -> 
            case dict:find(Key, Tuple) of
                {ok, Val} ->
                    Val;
                _ ->
                    undefined
            end;
        Module ->
            case lists:member({Key, 1}, Module:module_info(exports)) of
                true ->
                    Tuple:Key();
                _ ->
                    undefined
            end
    end.

find_deep_value([Key|Rest],Item) ->
    case find_value(Key,Item) of
	undefined -> undefined;
	NewItem -> find_deep_value(Rest,NewItem)
    end;
find_deep_value([],Item) -> Item.

fetch_value(Key, Data) ->
    case find_value(Key, Data) of
        undefined ->
            throw({undefined_variable, Key});
        Val ->
            Val
    end.

regroup(List, Attribute) ->
    regroup(List, Attribute, []).

regroup([], _, []) ->
    [];
regroup([], _, [[{grouper, LastGrouper}, {list, LastList}]|Acc]) ->
    lists:reverse([[{grouper, LastGrouper}, {list, lists:reverse(LastList)}]|Acc]);
regroup([Item|Rest], Attribute, []) ->
    regroup(Rest, Attribute, [[{grouper, find_deep_value(Attribute, Item)}, {list, [Item]}]]);
regroup([Item|Rest], Attribute, [[{grouper, PrevGrouper}, {list, PrevList}]|Acc]) ->
    case find_deep_value(Attribute, Item) of
        Value when Value =:= PrevGrouper ->
            regroup(Rest, Attribute, [[{grouper, PrevGrouper}, {list, [Item|PrevList]}]|Acc]);
        Value ->
            regroup(Rest, Attribute, [[{grouper, Value}, {list, [Item]}], [{grouper, PrevGrouper}, {list, lists:reverse(PrevList)}]|Acc])
    end.

translate(_, none, Default) ->
    Default;
translate(String, TranslationFun, Default) when is_function(TranslationFun) ->
    case TranslationFun(String) of
        undefined -> Default;
        <<"">> -> Default;
        "" -> Default;
        Str -> Str
    end.

are_equal(Arg1, Arg2) when Arg1 =:= Arg2 ->
    true;
are_equal(Arg1, Arg2) when is_binary(Arg1) ->
    are_equal(binary_to_list(Arg1), Arg2);
are_equal(Arg1, Arg2) when is_binary(Arg2) ->
    are_equal(Arg1, binary_to_list(Arg2));
are_equal(Arg1, Arg2) when is_integer(Arg1) ->
    are_equal(integer_to_list(Arg1), Arg2);
are_equal(Arg1, Arg2) when is_integer(Arg2) ->
    are_equal(Arg1, integer_to_list(Arg2));
are_equal(Arg1, Arg2) when is_atom(Arg1), is_list(Arg2) ->
    are_equal(atom_to_list(Arg1), Arg2);
are_equal(Arg1, Arg2) when is_list(Arg1), is_atom(Arg2) ->
    are_equal(Arg1, atom_to_list(Arg2));
are_equal(_, _) ->
    false.

is_false("") ->
    true;
is_false(false) ->
    true;
is_false(undefined) ->
    true;
is_false("0") ->
    true;
is_false(<<"0">>) ->
    true;
is_false(<<>>) ->
    true;
is_false(_) ->
    false.

is_true(V) ->
    not is_false(V).

'in'(Sublist, [Sublist|_]) ->
    true;
'in'(Sublist, List) when is_atom(List) ->
    'in'(Sublist, atom_to_list(List));
'in'(Sublist, List) when is_binary(Sublist) ->
    'in'(binary_to_list(Sublist), List);
'in'(Sublist, List) when is_binary(List) ->
    'in'(Sublist, binary_to_list(List));
'in'(Sublist, [C|Rest]) when is_list(Sublist) andalso is_binary(C) ->
    'in'(Sublist, [binary_to_list(C)|Rest]);
'in'(Sublist, [C|Rest]) when is_list(Sublist) andalso is_list(C) ->
    'in'(Sublist, Rest);
'in'(Sublist, List) when is_list(Sublist) andalso is_list(List) ->
    string:str(List, Sublist) > 0;
'in'(Element, List) when is_list(List) ->
    lists:member(Element, List);
'in'(_, _) ->
    false.

'not'(Value) ->
    not is_true(Value).

'or'(Value1, Value2) ->
    is_true(Value1) or is_true(Value2).

'and'(Value1, Value2) ->
    is_true(Value1) and is_true(Value2).

'eq'(Value1, Value2) ->
    are_equal(Value1, Value2).

'ne'(Value1, Value2) ->
    not are_equal(Value1, Value2).

'le'(Value1, Value2) ->
    not 'gt'(Value1, Value2).

'ge'(Value1, Value2) ->
    not 'lt'(Value1, Value2).

'gt'(Value1, Value2) when is_list(Value1) ->
    'gt'(list_to_integer(Value1), Value2);
'gt'(Value1, Value2) when is_list(Value2) ->
    'gt'(Value1, list_to_integer(Value2));
'gt'(Value1, Value2) when Value1 > Value2 ->
    true;
'gt'(_, _) ->
    false.

'lt'(Value1, Value2) when is_list(Value1) ->
    'lt'(list_to_integer(Value1), Value2);
'lt'(Value1, Value2) when is_list(Value2) ->
    'lt'(Value1, list_to_integer(Value2));
'lt'(Value1, Value2) when Value1 < Value2 ->
    true;
'lt'(_, _) ->
    false.

stringify_final(In, BinaryStrings) ->
    stringify_final(In, [], BinaryStrings).

stringify_final([], Out, _) ->
    lists:reverse(Out);
stringify_final([El | Rest], Out, false = BinaryStrings) when is_atom(El) ->
    stringify_final(Rest, [atom_to_list(El) | Out], BinaryStrings);
stringify_final([El | Rest], Out, true = BinaryStrings) when is_atom(El) ->
    stringify_final(Rest, [atom_to_binary(El, latin1) | Out], BinaryStrings);
stringify_final([El | Rest], Out, BinaryStrings) when is_list(El) ->
    stringify_final(Rest, [stringify_final(El, BinaryStrings) | Out], BinaryStrings);
stringify_final([El | Rest], Out, false = BinaryStrings) when is_tuple(El) ->
    stringify_final(Rest, [io_lib:print(El) | Out], BinaryStrings);
stringify_final([El | Rest], Out, true = BinaryStrings) when is_tuple(El) ->
    stringify_final(Rest, [list_to_binary(io_lib:print(El)) | Out], BinaryStrings);
stringify_final([El | Rest], Out, BinaryStrings) ->
    stringify_final(Rest, [El | Out], BinaryStrings).

init_counter_stats(List) ->
    init_counter_stats(List, undefined).

init_counter_stats(List, Parent) when is_list(List) ->
    [{counter, 1}, 
        {counter0, 0}, 
        {revcounter, length(List)}, 
        {revcounter0, length(List) - 1}, 
        {first, true}, 
        {last, length(List) =:= 1},
        {parentloop, Parent}].

increment_counter_stats([{counter, Counter}, {counter0, Counter0}, {revcounter, RevCounter},
        {revcounter0, RevCounter0}, {first, _}, {last, _}, {parentloop, Parent}]) ->
    [{counter, Counter + 1},
        {counter0, Counter0 + 1},
        {revcounter, RevCounter - 1},
        {revcounter0, RevCounter0 - 1},
        {first, false}, {last, RevCounter0 =:= 1},
        {parentloop, Parent}].

forloop(Fun, Acc0, Values) ->
    push_ifchanged_context(),
    Result = lists:mapfoldl(Fun, Acc0, Values),
    pop_ifchanged_context(),
    Result.

push_ifchanged_context() ->
    IfChangedContextStack = case get(?IFCHANGED_CONTEXT_VARIABLE) of
        undefined -> [];
        Stack -> Stack
    end,
    put(?IFCHANGED_CONTEXT_VARIABLE, [[]|IfChangedContextStack]).

pop_ifchanged_context() ->
    [_|Rest] = get(?IFCHANGED_CONTEXT_VARIABLE),
    put(?IFCHANGED_CONTEXT_VARIABLE, Rest).

ifchanged(Expressions) ->
    [IfChangedContext|Rest] = get(?IFCHANGED_CONTEXT_VARIABLE),
    {Result, NewContext} = lists:foldl(fun (Expr, {ProvResult, Context}) when ProvResult == true ->
                                               {_, NContext} = ifchanged2(Expr, Context),
                                               {true, NContext};
                                           (Expr, {_ProvResult, Context}) ->
                                               ifchanged2(Expr, Context)
                                       end, {false, IfChangedContext}, Expressions),
    put(?IFCHANGED_CONTEXT_VARIABLE, [NewContext|Rest]),
    Result.

ifchanged2({Key, Value}, IfChangedContext) ->
    PreviousValue = proplists:get_value(Key, IfChangedContext),
    if
        PreviousValue =:= Value ->
            {false, IfChangedContext};
        true ->
            NewContext = [{Key, Value}|proplists:delete(Key, IfChangedContext)],
            {true, NewContext}
    end.

cycle(NamesTuple, Counters) when is_tuple(NamesTuple) ->
    element(fetch_value(counter0, Counters) rem size(NamesTuple) + 1, NamesTuple).

widthratio(Numerator, Denominator, Scale) ->
    round(Numerator / Denominator * Scale).

spaceless(Contents) ->
    Contents1 = lists:flatten(Contents),
    Contents2 = re:replace(Contents1, "^\\s+<", "<", [{return,list}]),
    Contents3 = re:replace(Contents2, ">\\s+$", ">", [{return,list}]),
    Contents4 = re:replace(Contents3, ">\\s+<", "><", [global, {return,list}]),
    Contents4.

read_file(Module, Function, DocRoot, FileName) ->
    AbsName = case filename:absname(FileName) of
        FileName -> FileName;
        _ -> filename:join([DocRoot, FileName])
    end,
    {ok, Binary} = Module:Function(AbsName),
    binary_to_list(Binary).
