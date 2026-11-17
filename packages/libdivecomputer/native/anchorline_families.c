/*
 * Anchorline: which libdivecomputer families this build contains.
 *
 * Licensed LGPL-2.1-or-later, like the libdivecomputer it extends.
 */

#include <libdivecomputer/common.h>

#include "anchorline_families.h"

int
al_family_present (unsigned int family)
{
	switch (family) {
#ifdef AL_LEFT_OUT_SUUNTO_EONSTEEL
	case DC_FAMILY_SUUNTO_EONSTEEL:
		return 0;
#endif
#ifdef AL_LEFT_OUT_DEEPBLU_COSMIQ
	case DC_FAMILY_DEEPBLU_COSMIQ:
		return 0;
#endif
#ifdef AL_LEFT_OUT_OCEANS_S1
	case DC_FAMILY_OCEANS_S1:
		return 0;
#endif
#ifdef AL_LEFT_OUT_DIVESOFT_FREEDOM
	case DC_FAMILY_DIVESOFT_FREEDOM:
		return 0;
#endif
#ifdef AL_LEFT_OUT_HW_OSTC3
	case DC_FAMILY_HW_OSTC3:
		return 0;
#endif
#ifdef AL_LEFT_OUT_PELAGIC_I330R
	case DC_FAMILY_PELAGIC_I330R:
		return 0;
#endif
#ifdef AL_LEFT_OUT_DEEPSIX_EXCURSION
	case DC_FAMILY_DEEPSIX_EXCURSION:
		return 0;
#endif
#ifdef AL_LEFT_OUT_COCHRAN_COMMANDER
	case DC_FAMILY_COCHRAN_COMMANDER:
		return 0;
#endif
#ifdef AL_LEFT_OUT_MCLEAN_EXTREME
	case DC_FAMILY_MCLEAN_EXTREME:
		return 0;
#endif
	default:
		return 1;
	}
}
