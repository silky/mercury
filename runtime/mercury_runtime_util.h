/*
** Copyright (C) 2001,2006 The University of Melbourne.
** Copyright (C) 2014 The Mercury team.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

#ifndef	MERCURY_RUNTIME_UTIL_H
#define	MERCURY_RUNTIME_UTIL_H

#include	<stdio.h>

/*
** A reasonable buffer size for MR_strerror().
*/
#define MR_STRERROR_BUF_SIZE	256

/*
** Thread-safe strerror function. Returns a pointer to a null terminated string
** describing the error number. The returned pointer may be to the provided
** buffer, or it may be a pointer into static or thread-local memory.
** errno may be modified by this call.
*/
extern const char *MR_strerror(int errnum, char *buf, size_t buflen);

extern	FILE	*MR_checked_fopen(const char *filename, const char *message,
			const char *mode);
extern	void	MR_checked_fclose(FILE *file, const char *filename);
extern	void	MR_checked_atexit(void (*func)(void));
extern  int	MR_setenv(const char *name, const char *value, int overwrite);

#endif	/* MERCURY_RUNTIME_UTIL_H */
