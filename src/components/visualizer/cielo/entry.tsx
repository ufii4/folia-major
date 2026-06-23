import React, { lazy } from 'react';
import { defineVisualizer } from '../definition';
import { DEFAULT_CIELO_TUNING } from '../../../types';

const VisualizerCielo = lazy(() => import('./VisualizerCielo'));
const CieloSettingsPanel = lazy(() => import('./CieloSettingsPanel'));

export default defineVisualizer({
    mode: 'cielo',
    order: 45, // Arbitrary order after fume(40)
    labelKey: 'ui.visualizerCielo',
    labelFallback: '天际',
    previewSeed: 'cielo',
    previewStartOffset: 0,
    tuningKind: 'cielo',
    render: props => <VisualizerCielo {...props} />,
    renderSettingsPanel: props => <CieloSettingsPanel {...props} />,
    resetSettings: ({ resetCieloTuning, setDraftCieloTuning }) => {
        setDraftCieloTuning?.(DEFAULT_CIELO_TUNING);
        resetCieloTuning?.();
    },
});
