/*
 * Anchorline: which libdivecomputer families this build contains.
 *
 * Licensed LGPL-2.1-or-later, like the libdivecomputer it extends.
 */

#ifndef ANCHORLINE_FAMILIES_H
#define ANCHORLINE_FAMILIES_H

#ifdef __cplusplus
extern "C" {
#endif /* __cplusplus */

/*
 * Returns 0 if the family (a dc_family_t value) was left out of this build by
 * the hook's leave_out_families user-define, and 1 otherwise. A left-out
 * family still appears in the descriptor list; its entry functions return
 * DC_STATUS_UNSUPPORTED.
 */
int
al_family_present (unsigned int family);

#ifdef __cplusplus
}
#endif /* __cplusplus */

#endif /* ANCHORLINE_FAMILIES_H */
