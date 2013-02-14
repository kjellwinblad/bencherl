-module(ets_fixed_elements).

-export([bench_args/2, run/3]).


%% Description: Inserts small number of fixed keys many times into ets
%% table in parallel. It test ets with set table type and write and
%% read concurrency enabled; and etsmp.  See etsmp.erl for a
%% description of etsmp.
%%
%% Authors: David Klaftenegger (david.klaftenegger@it.uu.se) and
%%          Kjell Winblad (kjell.winblad@it.uu.se)


bench_args(Version, _) ->
    NrOfOperations = 
	case Version of
	    short        -> 500000;
	    intermediate -> 5000000;
	    long         -> 50000000
	end,
    TableImpels = [ets, etsmp],
    [[NrOfOperations, TableImpel] || TableImpel <- TableImpels].


run([NrOfOperations, TableImpel| _], _, _) ->
    NrOfWorkers = erlang:system_info(schedulers),
    par_insert(NrOfOperations, 1024, NrOfWorkers, TableImpel).


%% Count = how many inserts
%% Max = maximum number of DIFFERENT inserts
%% WorkerCount = number of parallel inserts
par_insert(Count, Max, WorkerCount, TableImpel) ->
	{Table, Workers} = setup(Count, Max, WorkerCount, TableImpel),
	par_insert(Workers),
	TableImpel:delete(Table),
	ok.

%% start workers and wait for workers to finish
par_insert(Workers) ->
	par_insert(Workers, []).
par_insert([], Running) ->
	wait_for(Running);
par_insert([Next | Waiting], Running) ->
	Next ! worker_start,
	par_insert(Waiting, [Next | Running]).

%% wait for start signal, insert into table & notify parent when done
insert_and_msg(Start, End, Max, Table, Parent, TableImpel) ->
	random:seed(now()),
	Src = array:from_list([X||{_,X} <- lists:sort([ {random:uniform(), N} || N <- lists:seq(0,Max+1)])]),
	receive worker_start -> ok end,
	insert(Start, End, Max, Table, Src, TableImpel),
	Parent ! {self(), worker_done},
	ok.

wait_for([]) -> ok;
wait_for([Worker | Workers]) ->
	receive {Worker, worker_done} -> ok end,
	wait_for(Workers),
	ok.

insert(Count, Count, _Max, _Table, _Src,_) -> ok;
insert(Num, Count, Max, Table, Src, TableImpel) ->
	TableImpel:insert(Table, {array:get((Num rem Max)+1, Src), ignored}),
	insert(Num+1, Count, Max, Table, Src, TableImpel).

setup(Count, Max, WorkerCount, TableImpel) ->
	Table = TableImpel:new(?MODULE, [set, public, {read_concurrency, true}, {write_concurrency, true}]),
	setup(Count, Max, WorkerCount, Table, 0, [], TableImpel).

setup(_Count, _Max, _WorkerCount, Table, _WorkerCount, Workers, _TableImpel) ->
	{Table, Workers};
setup(Count, Max, WorkerCount, Table, Started, Workers, TableImpel) ->
	MainProcess = self(),
	Range = Count div WorkerCount,
	Start = Started*Range,
	End = Start+Range,
	Workers2 = [spawn(fun() -> insert_and_msg(Start, End, Max, Table, MainProcess, TableImpel) end) | Workers],
	setup(Count, Max, WorkerCount, Table, Started+1, Workers2, TableImpel).
