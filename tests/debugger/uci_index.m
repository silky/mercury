:- module uci_index.

:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is det.

:- implementation.

:- import_module string, list.

main(!IO) :-
	compare(R, mai, mbi),
	write(R, !IO).

:- type i	--->	ai(int) ; bi(int) ; ci(int).

:- func mai = i.
:- func mbi = i.

mai = ai(1).
mbi = bi(11).
