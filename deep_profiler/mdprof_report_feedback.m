%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2011 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: mdprof_report_feedback.m.
% Author: pbone.
%
% This module contains code for showing the contents of feedback files
% in a human-readable form.
%
%-----------------------------------------------------------------------------%

:- module mdprof_report_feedback.
:- interface.

:- import_module io.

%-----------------------------------------------------------------------------%

:- pred main(io::di, io::uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module mdbcomp.
:- import_module mdbcomp.feedback.
:- import_module mdbcomp.feedback.automatic_parallelism.
:- import_module mdprof_fb.
:- import_module mdprof_fb.automatic_parallelism.
:- import_module mdprof_fb.automatic_parallelism.autopar_reports.

:- import_module bool.
:- import_module char.
:- import_module getopt.
:- import_module int.
:- import_module library.
:- import_module list.
:- import_module map.
:- import_module string.

%-----------------------------------------------------------------------------%

main(!IO) :-
    io.progname_base("mdprof_report_feedback", ProgName, !IO),
    io.command_line_arguments(Args0, !IO),
    getopt.process_options(option_ops_multi(short, long, defaults),
        Args0, Args, MaybeOptions),
    io.stderr_stream(Stderr, !IO),
    (
        MaybeOptions = ok(Options0),
        post_process_options(ProgName, Options0, Options, !IO),
        lookup_bool_option(Options, help, Help),
        lookup_bool_option(Options, version, Version),
        ( Version = yes ->
            write_version_message(ProgName, !IO)
        ; Help = yes ->
            write_help_message(ProgName, !IO)
        ;
            (
                Args = [FeedbackFileName],
                feedback.read_feedback_file(FeedbackFileName,
                    FeedbackReadResult, !IO),
                (
                    FeedbackReadResult = ok(Feedback),
                    ProfileProgName = get_feedback_program_name(Feedback),
                    print_feedback_report(ProfileProgName, Feedback, !IO)
                ;
                    FeedbackReadResult = error(FeedbackReadError),
                    feedback.read_error_message_string(FeedbackFileName,
                        FeedbackReadError, Message),
                    io.format(Stderr, "%s: %s\n",
                        [s(ProgName), s(Message)], !IO),
                    io.set_exit_status(1, !IO)
                )
            ;
                ( Args = []
                ; Args = [_, _ | _]
                ),
                write_help_message(ProgName, !IO),
                io.set_exit_status(1, !IO)
            )
        )
    ;
        MaybeOptions = error(Msg),
        io.format(Stderr, "%s: error parsing options: %s\n",
            [s(ProgName), s(Msg)], !IO),
        write_help_message(ProgName, !IO),
        io.set_exit_status(1, !IO)
    ).

:- func help_message(string) = string.

help_message(ProgName) = HelpMessage :-
    FormatStr = 
"Usage: %s [options] <feedbackfile>
    This command outputs a report that shows the contents of the named
    feedback file in a human-readable form.

    You may specify the following general options:

    -h --help       Generate this help message.
    -V --version    Report the program's version number.
    -v --verbosity  <0-4>
                    Generate messages. The higher the argument, the more
                    verbose the program becomes. 2 is recommended, and
                    is the default.
",
    HelpMessage = string.format(FormatStr, [s(ProgName)]).

:- pred write_help_message(string::in, io::di, io::uo) is det.

write_help_message(ProgName, !IO) :-
    io.write_string(help_message(ProgName), !IO).

:- pred write_version_message(string::in, io::di, io::uo) is det.

write_version_message(ProgName, !IO) :-
    library.version(Version, Fullarch),
    io.format("%s: Mercury deep profiler\n", [s(ProgName)], !IO),
    io.format("version: %s, on %s.\n",
        [s(Version), s(Fullarch)], !IO).

%----------------------------------------------------------------------------%
%
% This section describes and processes command line options. Individual
% feedback information can be requested by the user, as well as options named
% after optimizations that may imply one or more feedback inforemation types,
% which that optimization uses.
%

    % Command line options.
    %
:- type option
    --->    help
    ;       version
    ;       verbosity.

% TODO: Introduce an option to disable parallelisation of dependent
% conjunctions, or switch to the simple calculations for independent
% conjunctions.

:- pred short(char::in, option::out) is semidet.

short('h',  help).
short('v',  verbosity).
short('V',  version).

:- pred long(string::in, option::out) is semidet.

long("help",        help).
long("verbosity",   verbosity).
long("version",     version).

:- pred defaults(option::out, option_data::out) is multi.

defaults(help,      bool(no)).
defaults(verbosity, int(2)).
defaults(version,   bool(no)).

:- pred post_process_options(string::in,
    option_table(option)::in, option_table(option)::out,
    io::di, io::uo) is det.

post_process_options(ProgName, !Options, !IO) :-
    lookup_int_option(!.Options, verbosity, VerbosityLevel),
    io.stderr_stream(Stderr, !IO),
    ( VerbosityLevel < 0 ->
        io.format(Stderr,
            "%s: warning: verbosity level should not be negative.\n",
            [s(ProgName)], !IO),
        set_option(verbosity, int(0), !Options)
    ; VerbosityLevel > 4 ->
        io.format(Stderr,
            "%s: warning: verbosity level should not exceed 4.\n",
            [s(ProgName)], !IO),
        set_option(verbosity, int(4), !Options)
    ;
        true
    ).

    % Set the value of an option in the option table.
    %
:- pred set_option(option::in, option_data::in,
    option_table(option)::in, option_table(option)::out) is det.

set_option(Option, Value, !Options) :-
    map.set(Option, Value, !Options).

%-----------------------------------------------------------------------------%
:- end_module mdprof_report_feedback.
%-----------------------------------------------------------------------------%
