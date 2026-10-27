# Qi v03 localized roundhouse skirt correction

The v02 0.20 s large thigh-through-outer-skirt defect is mitigated in the reviewed v03 renders. Only DEF-skirt_* channels of RoundhouseKick_R/L are corrected; no common body, arm, leg, head, hair, locomotion, or rifle tracks are edited.

Method: each sample follows the actual kicking thigh's horizontal direction. A smooth direction-localized skirt lift adds at most 0.34 radians to nearby sectors, fading on from 0.09 to 0.17 s and off from 0.55 to 0.65 s. This avoids the previous fixed-sector broad lifting that missed the outgoing leg and collided with arms. Waist anchoring and garment meshes are unchanged.

Visual review: R at 0.10, .15, .18, .20, .23, .27, .30, .35, .40, .43, .467, .50, .53, .57, .60, .70 s; L at .20, .35, .467, .50 s. The prior large exposed thigh through an intact outer skirt band is no longer visible in these views. Hem overlaps/occludes the retracting leg at .467–.50 s; this is not proof of zero triangle contacts. Local skirt folds bunch around .27–.30 s. The skirt naturally lifts during the high kick and opaque safety shorts remain. These are finite sampled-view checks, not all-angle collision-free certification.

Source: Qi-Rifle-Actions-Candidate.blend, reproducible correction fix.py. The rejected 0.78-radian trial was not retained in the source.

Runtime: use preserve_common_with_skirt.py on a fresh export. It restores original common glTF buffer tracks, replacing only RoundhouseKick_R/L skirt-node channels from the revised export. Validate non-skirt skin matrices against the original independently; expected <=1e-6 numerical deviation. Full actual-export skin/BVH QA is owned by the parent pipeline.

## Final bounded hand-clearance revision

Actual-export BVH identified new skirt/hand-arm contact around 0.30–0.367 s in the first 0.34-radian correction. The final source adds a smooth temporal notch: correction decreases from full at .25 s to zero at .29 s, stays zero through .38 s, and recovers smoothly by .42 s. The .20 s visible-defect correction is unchanged. Additional renders at .27/.30/.333/.367/.40 s verify the reduced folds clear the arm visually. The updated full-motion MP4 is rendered from this final notched source. Numerical final QA is still required from the parent pipeline; prior collision counts must not be attributed to this revised source.
