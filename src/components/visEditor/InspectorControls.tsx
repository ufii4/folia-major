import type { ChangeEvent, ReactNode } from 'react';
import {
    DEFAULT_CADENZA_TUNING,
    DEFAULT_CAPPELLA_TUNING,
    DEFAULT_FUME_TUNING,
    DEFAULT_PARTITA_TUNING,
    DEFAULT_TILT_TUNING,
    type CadenzaTuning,
    type CappellaTuning,
    type FumeTuning,
    type PartitaTuning,
    type TiltTuning,
    type VisualizerMode,
} from '../../types';
import { VISUALIZER_REGISTRY } from '../visualizer/registry';
import type { VisualizerComplexNode, VisualizerMainNode } from '../visualizer/complex';

// src/components/visEditor/InspectorControls.tsx
// Shared inspector controls for concrete visualizer parameters.
export type SetVisualizerNode = (updater: (node: VisualizerComplexNode) => VisualizerComplexNode) => void;

const readNumber = (event: ChangeEvent<HTMLInputElement | HTMLSelectElement>) => Number(event.target.value);

export interface RangeFieldProps {
    label: string;
    value: number;
    min: number;
    max: number;
    step: number;
    onChange: (value: number) => void;
}

export const RangeField = ({ label, value, min, max, step, onChange }: RangeFieldProps) => (
    <label className="vis-editor-field">
        <span>{label} {value.toFixed(step < 1 ? 2 : 0)}</span>
        <input
            type="range"
            min={min}
            max={max}
            step={step}
            value={value}
            onChange={event => onChange(readNumber(event))}
        />
    </label>
);

export const CheckboxField = ({ label, checked, onChange }: { label: string; checked: boolean; onChange: (checked: boolean) => void; }) => (
    <label className="vis-editor-check">
        <input type="checkbox" checked={checked} onChange={event => onChange(event.target.checked)} />
        <span>{label}</span>
    </label>
);

export const FieldGroup = ({ title, children }: { title: string; children: ReactNode; }) => (
    <section className="vis-editor-field-group">
        <div className="vis-editor-field-group__title">{title}</div>
        {children}
    </section>
);

const updateMainConfig = (
    node: VisualizerComplexNode,
    patch: Partial<VisualizerMainNode['config']>,
): VisualizerComplexNode => (
    node.role === 'visualizerMain' ? { ...node, config: { ...node.config, ...patch } } : node
);

const updateMainTuning = <K extends keyof VisualizerMainNode['config']>(
    node: VisualizerComplexNode,
    key: K,
    fallback: NonNullable<VisualizerMainNode['config'][K]>,
    patch: Partial<NonNullable<VisualizerMainNode['config'][K]>>,
): VisualizerComplexNode => {
    if (node.role !== 'visualizerMain') {
        return node;
    }

    const current = (node.config[key] ?? fallback) as NonNullable<VisualizerMainNode['config'][K]>;
    return {
        ...node,
        config: {
            ...node.config,
            [key]: { ...current, ...patch },
        },
    };
};

const renderCadenzaControls = (node: VisualizerMainNode, setNode: SetVisualizerNode) => {
    const tuning: CadenzaTuning = node.config.cadenzaTuning ?? DEFAULT_CADENZA_TUNING;
    return (
        <FieldGroup title="Cadenza">
            <RangeField label="Font scale" value={tuning.fontScale} min={0.6} max={1.8} step={0.01} onChange={value => setNode(n => updateMainTuning(n, 'cadenzaTuning', DEFAULT_CADENZA_TUNING, { fontScale: value }))} />
            <RangeField label="Width ratio" value={tuning.widthRatio} min={0.4} max={1} step={0.01} onChange={value => setNode(n => updateMainTuning(n, 'cadenzaTuning', DEFAULT_CADENZA_TUNING, { widthRatio: value }))} />
            <RangeField label="Motion" value={tuning.motionAmount} min={0} max={2} step={0.01} onChange={value => setNode(n => updateMainTuning(n, 'cadenzaTuning', DEFAULT_CADENZA_TUNING, { motionAmount: value }))} />
            <RangeField label="Glow" value={tuning.glowIntensity} min={0} max={2} step={0.01} onChange={value => setNode(n => updateMainTuning(n, 'cadenzaTuning', DEFAULT_CADENZA_TUNING, { glowIntensity: value }))} />
            <RangeField label="Beam" value={tuning.beamIntensity} min={0} max={2} step={0.01} onChange={value => setNode(n => updateMainTuning(n, 'cadenzaTuning', DEFAULT_CADENZA_TUNING, { beamIntensity: value }))} />
        </FieldGroup>
    );
};

const renderPartitaControls = (node: VisualizerMainNode, setNode: SetVisualizerNode) => {
    const tuning: PartitaTuning = node.config.partitaTuning ?? DEFAULT_PARTITA_TUNING;
    return (
        <FieldGroup title="Partita">
            <CheckboxField label="Show guide lines" checked={tuning.showGuideLines} onChange={checked => setNode(n => updateMainTuning(n, 'partitaTuning', DEFAULT_PARTITA_TUNING, { showGuideLines: checked }))} />
            <CheckboxField label="Use semantic layout" checked={tuning.useSemanticLayout} onChange={checked => setNode(n => updateMainTuning(n, 'partitaTuning', DEFAULT_PARTITA_TUNING, { useSemanticLayout: checked }))} />
            <RangeField label="Stagger min" value={tuning.staggerMin} min={0} max={240} step={1} onChange={value => setNode(n => updateMainTuning(n, 'partitaTuning', DEFAULT_PARTITA_TUNING, { staggerMin: Math.min(value, tuning.staggerMax) }))} />
            <RangeField label="Stagger max" value={tuning.staggerMax} min={0} max={320} step={1} onChange={value => setNode(n => updateMainTuning(n, 'partitaTuning', DEFAULT_PARTITA_TUNING, { staggerMax: Math.max(value, tuning.staggerMin) }))} />
        </FieldGroup>
    );
};

const renderFumeControls = (node: VisualizerMainNode, setNode: SetVisualizerNode) => {
    const tuning: FumeTuning = node.config.fumeTuning ?? DEFAULT_FUME_TUNING;
    return (
        <FieldGroup title="Fume">
            <CheckboxField label="Hide print symbols" checked={tuning.hidePrintSymbols} onChange={checked => setNode(n => updateMainTuning(n, 'fumeTuning', DEFAULT_FUME_TUNING, { hidePrintSymbols: checked }))} />
            <CheckboxField label="Disable inner geometry" checked={tuning.disableGeometricBackground} onChange={checked => setNode(n => updateMainTuning(n, 'fumeTuning', DEFAULT_FUME_TUNING, { disableGeometricBackground: checked }))} />
            <RangeField label="Object opacity" value={tuning.backgroundObjectOpacity} min={0} max={1} step={0.01} onChange={value => setNode(n => updateMainTuning(n, 'fumeTuning', DEFAULT_FUME_TUNING, { backgroundObjectOpacity: value }))} />
            <RangeField label="Text hold" value={tuning.textHoldRatio} min={0} max={1} step={0.01} onChange={value => setNode(n => updateMainTuning(n, 'fumeTuning', DEFAULT_FUME_TUNING, { textHoldRatio: value }))} />
            <label className="vis-editor-field">
                <span>Camera tracking</span>
                <select value={tuning.cameraTrackingMode} onChange={event => setNode(n => updateMainTuning(n, 'fumeTuning', DEFAULT_FUME_TUNING, { cameraTrackingMode: event.target.value as FumeTuning['cameraTrackingMode'] }))}>
                    <option value="smooth">Smooth</option>
                    <option value="stepped">Stepped</option>
                </select>
            </label>
            <RangeField label="Camera speed" value={tuning.cameraSpeed} min={0.55} max={1.85} step={0.01} onChange={value => setNode(n => updateMainTuning(n, 'fumeTuning', DEFAULT_FUME_TUNING, { cameraSpeed: value }))} />
            <RangeField label="Glow" value={tuning.glowIntensity} min={0} max={1.8} step={0.01} onChange={value => setNode(n => updateMainTuning(n, 'fumeTuning', DEFAULT_FUME_TUNING, { glowIntensity: value }))} />
            <RangeField label="Hero scale" value={tuning.heroScale} min={0.82} max={1.32} step={0.01} onChange={value => setNode(n => updateMainTuning(n, 'fumeTuning', DEFAULT_FUME_TUNING, { heroScale: value }))} />
        </FieldGroup>
    );
};

const renderCappellaControls = (node: VisualizerMainNode, setNode: SetVisualizerNode) => {
    const tuning: CappellaTuning = node.config.cappellaTuning ?? DEFAULT_CAPPELLA_TUNING;
    return (
        <FieldGroup title="Cappella">
            <CheckboxField label="Show emo messages" checked={tuning.showEmoMessages} onChange={checked => setNode(n => updateMainTuning(n, 'cappellaTuning', DEFAULT_CAPPELLA_TUNING, { showEmoMessages: checked }))} />
            <label className="vis-editor-field">
                <span>Emoji pack</span>
                <select value={tuning.emojiPackSource} onChange={event => setNode(n => updateMainTuning(n, 'cappellaTuning', DEFAULT_CAPPELLA_TUNING, { emojiPackSource: event.target.value as CappellaTuning['emojiPackSource'] }))}>
                    <option value="builtin">Builtin</option>
                    <option value="custom">Custom</option>
                </select>
            </label>
            <label className="vis-editor-field">
                <span>Avatar source</span>
                <select value={tuning.avatarSource} onChange={event => setNode(n => updateMainTuning(n, 'cappellaTuning', DEFAULT_CAPPELLA_TUNING, { avatarSource: event.target.value as CappellaTuning['avatarSource'] }))}>
                    <option value="cover">Cover</option>
                    <option value="builtin">Builtin</option>
                    <option value="color">Theme color</option>
                </select>
            </label>
        </FieldGroup>
    );
};

const renderTiltControls = (node: VisualizerMainNode, setNode: SetVisualizerNode) => {
    const tuning: TiltTuning = node.config.tiltTuning ?? DEFAULT_TILT_TUNING;
    return (
        <FieldGroup title="Tilt">
            <RangeField label="Split probability" value={tuning.splitProbability} min={0} max={1} step={0.01} onChange={value => setNode(n => updateMainTuning(n, 'tiltTuning', DEFAULT_TILT_TUNING, { splitProbability: value }))} />
            <RangeField label="Tilt style chance" value={tuning.tiltStyleProbability} min={0} max={1} step={0.01} onChange={value => setNode(n => updateMainTuning(n, 'tiltTuning', DEFAULT_TILT_TUNING, { tiltStyleProbability: value }))} />
            <label className="vis-editor-field">
                <span>Color scheme</span>
                <select value={tuning.colorScheme ?? 'default'} onChange={event => setNode(n => updateMainTuning(n, 'tiltTuning', DEFAULT_TILT_TUNING, { colorScheme: event.target.value as TiltTuning['colorScheme'] }))}>
                    <option value="default">Default</option>
                    <option value="swap">Swap</option>
                    <option value="accentAll">Accent all</option>
                    <option value="primaryAll">Primary all</option>
                </select>
            </label>
        </FieldGroup>
    );
};

export const renderMainModeControls = (node: VisualizerMainNode, setNode: SetVisualizerNode) => (
    <>
        <label className="vis-editor-field">
            <span>Main renderer mode</span>
            <select
                value={node.config.mode}
                onChange={event => setNode(n => updateMainConfig(n, { mode: event.target.value as VisualizerMode }))}
            >
                {VISUALIZER_REGISTRY.map(entry => (
                    <option key={entry.mode} value={entry.mode}>{entry.labelFallback}</option>
                ))}
            </select>
        </label>
        <RangeField
            label="Lyrics font scale"
            value={node.config.lyricsFontScale ?? 1}
            min={0.6}
            max={1.8}
            step={0.01}
            onChange={value => setNode(n => updateMainConfig(n, { lyricsFontScale: value }))}
        />
        {node.config.mode === 'cadenza' ? renderCadenzaControls(node, setNode) : null}
        {node.config.mode === 'partita' ? renderPartitaControls(node, setNode) : null}
        {node.config.mode === 'fume' ? renderFumeControls(node, setNode) : null}
        {node.config.mode === 'cappella' ? renderCappellaControls(node, setNode) : null}
        {node.config.mode === 'tilt' ? renderTiltControls(node, setNode) : null}
    </>
);
