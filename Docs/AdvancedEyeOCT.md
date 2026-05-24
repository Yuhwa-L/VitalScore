# Advanced Eye + OCT Research Demo

The Advanced Eye + OCT panel is a research extension surface. It demonstrates how VitalScore could combine phone-based eye-tracking behavior with OCT/OCTA retinal metrics exported from external imaging systems.

The panel is not a medical device, diagnosis, screening test, or treatment recommendation. Any disease-specific language must remain framed as research potential and should require clinician review, regulatory validation, and prospective human data before product use.

## Demo Inputs

The import connector accepts JSON or CSV metric exports with any of these optional fields:

| Domain | Example fields |
|---|---|
| Eye tracking | `eyeFocusScore`, `gazeTrackingLossPct`, `averageReactionMs`, `gazeStabilityPx` |
| OCT structure | `rnflThicknessMicrons`, `ganglionCellComplexMicrons`, `macularThicknessMicrons` |
| OCTA/fOCTA function | `vesselDensityPercent`, `capillaryRNVCResponsePercent`, `rnvcTimeToPeakSeconds` |
| Quality | `signalStrength`, `quality` |

## Intended Signal Stack

1. Eye-tracking behavior captures reaction timing, gaze stability, fixation behavior, blink rate, and tracking quality.
2. OCT structure captures retinal layer and macular morphology.
3. OCTA/fOCTA function captures vessel-density and retinal neurovascular coupling response fields.
4. Research review combines the structured signals into hypotheses for longitudinal analysis, not automated clinical claims.

## Paper Basis

Liu et al. propose functional OCT angiography with flicker light stimulation to measure retinal neurovascular coupling at the capillary level. In their premotor Parkinson's mouse model, they report attenuated and delayed retinal neurovascular coupling before motor deficits, with levodopa-related recovery used as a discriminative signal. This is a preprint and preclinical animal-model result, so VitalScore must not present it as validated human screening.

## Reference

1. Liu K, Wang R, Huang L, Zhang H, Gao M, Sun B, et al. Transocular detection of premotor Parkinson's disease via retinal neurovascular coupling through functional OCT angiography. bioRxiv. 2024. doi:10.1101/2024.08.04.606502. Preprint.
