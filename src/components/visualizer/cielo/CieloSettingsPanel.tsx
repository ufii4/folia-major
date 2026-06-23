import React, { useCallback } from 'react';
import { type VisualizerSettingsPanelProps } from '../definition';
import { DEFAULT_CIELO_TUNING, type CieloTuning } from '../../../types';

export const CieloSettingsPanel: React.FC<VisualizerSettingsPanelProps> = ({
    t,
    cieloTuning,
    onCieloTuningChange,
    onSliderPointerDown,
    onSliderCommit,
    rangeInputClass,
    controlCardBg,
}) => {
    const tuning = cieloTuning ?? DEFAULT_CIELO_TUNING;

    const handleChange = useCallback((key: keyof CieloTuning) => (event: React.ChangeEvent<HTMLInputElement>) => {
        onCieloTuningChange?.({ [key]: parseFloat(event.target.value) });
    }, [onCieloTuningChange]);

    return (
        <div
            className="rounded-[24px] border border-white/10 p-4 space-y-4"
            style={{ backgroundColor: controlCardBg }}
        >
            <div className="space-y-1">
                <div className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>
                    {t('options.cieloSettings') || '天际参数'}
                </div>
                <div className="text-xs opacity-50" style={{ color: 'var(--text-secondary)' }}>
                    {t('options.cieloSettingsDesc') || '控制着色器推镜速度、几何与粒子密度。'}
                </div>
            </div>

            <div className="space-y-2">
                <div className="flex items-center justify-between text-sm" style={{ color: 'var(--text-primary)' }}>
                    <span>{t('options.cieloCameraSpeed') || '摄影机移动速度'}</span>
                    <span className="font-mono opacity-70" style={{ color: 'var(--text-secondary)' }}>
                        {tuning.cameraSpeed.toFixed(2)}x
                    </span>
                </div>
                <input
                    type="range"
                    min="0.2"
                    max="3.0"
                    step="0.1"
                    value={tuning.cameraSpeed}
                    onChange={handleChange('cameraSpeed')}
                    onPointerDown={onSliderPointerDown}
                    onPointerUp={onSliderCommit}
                    className={rangeInputClass}
                />
            </div>

            <div className="space-y-2">
                <div className="flex items-center justify-between text-sm" style={{ color: 'var(--text-primary)' }}>
                    <span>{t('options.cieloGeometricDensity') || '几何图形密度'}</span>
                    <span className="font-mono opacity-70" style={{ color: 'var(--text-secondary)' }}>
                        {tuning.geometricDensity.toFixed(2)}x
                    </span>
                </div>
                <input
                    type="range"
                    min="0.1"
                    max="2.0"
                    step="0.1"
                    value={tuning.geometricDensity}
                    onChange={handleChange('geometricDensity')}
                    onPointerDown={onSliderPointerDown}
                    onPointerUp={onSliderCommit}
                    className={rangeInputClass}
                />
            </div>

            <div className="space-y-2">
                <div className="flex items-center justify-between text-sm" style={{ color: 'var(--text-primary)' }}>
                    <span>{t('options.cieloParticleDensity') || '碎片粒子密度'}</span>
                    <span className="font-mono opacity-70" style={{ color: 'var(--text-secondary)' }}>
                        {tuning.particleDensity.toFixed(2)}x
                    </span>
                </div>
                <input
                    type="range"
                    min="0.0"
                    max="2.0"
                    step="0.1"
                    value={tuning.particleDensity}
                    onChange={handleChange('particleDensity')}
                    onPointerDown={onSliderPointerDown}
                    onPointerUp={onSliderCommit}
                    className={rangeInputClass}
                />
            </div>

            <div className="space-y-2">
                <div className="flex items-center justify-between text-sm" style={{ color: 'var(--text-primary)' }}>
                    <span>{t('options.cieloBaseColorMix') || '基础色调混合比'}</span>
                    <span className="font-mono opacity-70" style={{ color: 'var(--text-secondary)' }}>
                        {Math.round(tuning.baseColorMix * 100)}%
                    </span>
                </div>
                <input
                    type="range"
                    min="0.0"
                    max="1.0"
                    step="0.05"
                    value={tuning.baseColorMix}
                    onChange={handleChange('baseColorMix')}
                    onPointerDown={onSliderPointerDown}
                    onPointerUp={onSliderCommit}
                    className={rangeInputClass}
                />
            </div>
        </div>
    );
};

export default CieloSettingsPanel;
