/*
** Copyright (C) 1995-1997, 1999-2002, 2007, 2011 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/* mercury_float.h - floating point handling */

#ifndef MERCURY_FLOAT_H
#define MERCURY_FLOAT_H

#include "mercury_conf.h"       /* for MR_BOXED_FLOAT, MR_CONSERVATIVE_GC */
#include "mercury_types.h"      /* for `MR_Word' */
#include "mercury_std.h"        /* for `MR_bool' */

#ifdef MR_USE_SINGLE_PREC_FLOAT
  typedef float MR_Float;
  #define MR_FLT_MIN_PRECISION  7
  #define MR_FLT_FMT            "%f"
  /* We assume that sizeof(float) <= sizeof(MR_Word). */
  #undef MR_BOXED_FLOAT
#else
  typedef double MR_Float;
  #define MR_FLT_MIN_PRECISION  15
  #define MR_FLT_FMT            "%lf"
#endif
#define MR_FLT_MAX_PRECISION    (MR_FLT_MIN_PRECISION + 2)

#define MR_FLOAT_WORDS          ((sizeof(MR_Float) + sizeof(MR_Word) - 1) \
                                        / sizeof(MR_Word))

  /*
  ** MR_Float_Aligned and #pragma pack are used convince the C compiler to lay
  ** out structures containing MR_Float members as expected by the Mercury
  ** compiler, without additional padding or packing.
  **
  ** For MSVC, __declspec(align) only increases alignment, e.g. for single
  ** precision floats on 64-bit platforms. #pragma pack is required to
  ** reduce packing size, e.g. double precision floats on 32-bit platform.
  */
#if defined(MR_GNUC) || defined(MR_CLANG)
  typedef MR_Float MR_Float_Aligned __attribute__((aligned(sizeof(MR_Word))));
#elif defined(MR_MSVC)
  typedef __declspec(align(MR_BYTES_PER_WORD)) MR_Float MR_Float_Aligned;
#else
  typedef MR_Float MR_Float_Aligned;
#endif

#ifdef MR_BOXED_FLOAT

  #define MR_word_to_float(w)   (* (MR_Float *) (w))

  #ifdef MR_CONSERVATIVE_GC
    #define MR_float_to_word(f)                                             \
      (                                                                     \
        MR_hp_alloc_atomic_msg(MR_FLOAT_WORDS,                              \
            (MR_AllocSiteInfoPtr) MR_ALLOC_SITE_FLOAT, NULL),               \
        * (MR_Float *) (void *) (MR_hp - MR_FLOAT_WORDS) = (f),             \
        /* return */ (MR_Word) (MR_hp - MR_FLOAT_WORDS)                     \
      )
    #define MR_make_hp_float_aligned() ((void)0)
  #else
    /*
    ** We need to ensure that what we allocated on the heap is properly
    ** aligned for a floating-point value, by rounding MR_hp up to the
    ** nearest float-aligned boundary.
    ** XXX This code assumes that sizeof(MR_Float) is a power of two,
    ** and not greater than 2 * sizeof(MR_Word).
    */
    #define MR_make_hp_float_aligned()                                      \
      ( (MR_Word) MR_hp & (sizeof(MR_Float) - 1) ?                          \
            MR_hp_alloc_atomic_msg(1, MR_ALLOC_SITE_FLOAT, NULL)            \
      :                                                                     \
            (void)0                                                         \
      )
    #define MR_float_to_word(f)                                             \
      (                                                                     \
        MR_make_hp_float_aligned(),                                         \
        MR_hp_alloc_atomic_msg(MR_FLOAT_WORDS, MR_ALLOC_SITE_FLOAT, NULL),  \
        * (MR_Float *) (void *)(MR_hp - MR_FLOAT_WORDS) = (f),              \
        /* return */ (MR_Word) (MR_hp - MR_FLOAT_WORDS)                     \
      )
  #endif

  #ifdef MR_GNUC
    #define MR_float_const(f) ({ static const MR_Float d = f; (MR_Word) &d; })
  #else
    #define MR_float_const(f) MR_float_to_word(f)   /* inefficient */
  #endif

  /*
  ** MR_BOXED_FLOAT is never defined if using single-precision floats,
  ** so MR_Float must be double.
  */
  union MR_Float_Dword {
        MR_Float f;
        MR_Word w[2];
  };

  #if defined(MR_GNUC) || defined(MR_CLANG)
    #define MR_float_word_bits(F, I)                                        \
        (((union MR_Float_Dword) (MR_Float) (F)).w[(I)])
  #else
    MR_EXTERN_INLINE MR_Word
    MR_float_word_bits(MR_Float f, MR_Integer n);

    MR_EXTERN_INLINE MR_Word
    MR_float_word_bits(MR_Float f, MR_Integer n)
    {
        union MR_Float_Dword __ffdw;
        __ffdw.f = f;
        return __ffdw.w[n];
    }
  #endif

  #if defined(MR_DEBUG_DWORD_ALIGNMENT) && \
	(defined(MR_GNUC) || defined(MR_CLANG))
    #define MR_dword_ptr(ptr)                                               \
      ({                                                                    \
          MR_Word __addr = (MR_Word) (ptr);                                 \
          assert((__addr % 8) == 0);                                        \
          /* return */ (void *) __addr;                                     \
      })
  #else
    #define MR_dword_ptr(ptr)   ((void *) (ptr))
  #endif

  #define MR_float_from_dword_ptr(ptr)                                      \
        (((union MR_Float_Dword *) (ptr))->f)

  #if defined(MR_GNUC) || defined(MR_CLANG)
    #define MR_float_from_dword(w0, w1)                                     \
      ({                                                                    \
        union MR_Float_Dword __ffdw;                                        \
        __ffdw.w[0] = (MR_Word) (w0);                                       \
        __ffdw.w[1] = (MR_Word) (w1);                                       \
        __ffdw.f;                                                           \
      })
  #else

    #define MR_float_from_dword(w0, w1)				 	    \
	MR_float_from_dword_func((MR_Word)(w0), (MR_Word)(w1))

    MR_EXTERN_INLINE MR_Float
    MR_float_from_dword_func(MR_Word w0, MR_Word w1);

    MR_EXTERN_INLINE MR_Float
    MR_float_from_dword_func(MR_Word w0, MR_Word w1)
    {
        union MR_Float_Dword __ffdw;
        __ffdw.w[0] = (MR_Word) (w0);
        __ffdw.w[1] = (MR_Word) (w1);
        return __ffdw.f;
    }
  #endif

#else /* not MR_BOXED_FLOAT */

  /* unboxed float means we can assume sizeof(MR_Float) <= sizeof(MR_Word) */

  #define MR_make_hp_float_aligned() ((void)0)

  union MR_Float_Word {
        MR_Float f;
        MR_Word w;
  };

  #define MR_float_const(f) MR_float_to_word(f)

  #if defined(MR_GNUC) || defined(MR_CLANG)

    /*
    ** GNU C allows you to cast to a union type.
    ** clang also provides this extension.
    */
    #define MR_float_to_word(f) (__extension__ \
                                ((union MR_Float_Word)(MR_Float)(f)).w)
    #define MR_word_to_float(w) (__extension__ \
                                ((union MR_Float_Word)(MR_Word)(w)).f)

  #else /* not MR_GNUC or MR_CLANG */

    static MR_Word MR_float_to_word(MR_Float f)
        { union MR_Float_Word tmp; tmp.f = f; return tmp.w; }
    static MR_Float MR_word_to_float(MR_Word w)
        { union MR_Float_Word tmp; tmp.w = w; return tmp.f; }

  #endif /* not MR_GNUC or MR_CLANG */

#endif /* not MR_BOXED_FLOAT */

/*
** The size of the buffer to pass to MR_sprintf_float.
**
** Longest possible string for %#.*g format is `-n.nnnnnnE-mmmm', which
** has size  PRECISION + MAX_EXPONENT_DIGITS + 5 (for the `-', `.', `E',
** '-', and '\\0').  PRECISION is at most 20, and MAX_EXPONENT_DIGITS is
** at most 5, so we need at most 30 chars.  80 is way more than enough.
*/
#define MR_SPRINTF_FLOAT_BUF_SIZE   80

#define MR_float_to_string(Float, String, alloc_id)                         \
    do {                                                                    \
        char buf[MR_SPRINTF_FLOAT_BUF_SIZE];                                \
        MR_sprintf_float(buf, Float);                                       \
        MR_make_aligned_string_copy_msg(Str, buf, (alloc_id));              \
    } while (0)

void MR_sprintf_float(char *buf, MR_Float f);

MR_Integer MR_hash_float(MR_Float);

/*
** We define MR_is_{nan,infinite,finite} as macros if we support C99 
** since the resulting code is faster.
*/
#if __STDC_VERSION__ >= 199901
    #if defined(MR_USE_SINGLE_PREC_FLOAT)
        #define MR_is_nan(f) isnanf((f))
    #else
        #define MR_is_nan(f) isnan((f))
    #endif
#else
    #define MR_is_nan(f) MR_is_nan_func((f))
#endif

/*
** See comments for function MR_is_infinite_func in mercury_float.c for the
** handling of Solaris here.
*/
#if __STDC_VERSION__ >= 199901 && !defined(MR_SOLARIS)
    #if defined(MR_USE_SINGLE_PREC_FLOAT)
        #define MR_is_infinite(f) isinff((f))
    #else
        #define MR_is_infinite(f) isinf((f))
    #endif
#else
    #define MR_is_infinite(f) MR_is_infinite_func((f))
#endif

/*
** XXX I don't know whether isfinite works on Solaris or not.
*/
#if __STDC_VERSION__ >= 199901 && !defined(MR_SOLARIS)
    #define MR_is_finite(f) isfinite((f))
#else   
    #define MR_is_finite(f) (!MR_is_infinite((f)) && !MR_is_nan((f)))
#endif

MR_bool MR_is_nan_func(MR_Float);
MR_bool MR_is_infinite_func(MR_Float);

#endif /* not MERCURY_FLOAT_H */
