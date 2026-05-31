import type { Theme } from '../../types';
import type { VisualizerComplexNode, VisualizerComplexV1 } from '../visualizer/complex';
import { CheckboxField, FieldGroup, RangeField, renderMainModeControls } from './InspectorControls';

// src/components/visEditor/Inspector.tsx
// Right-side inspector for selecting and editing persisted complex nodes.
interface InspectorProps {
    complex: VisualizerComplexV1;
    selectedNodeId: string | null;
    theme: Theme;
    isDaylight: boolean;
    onChange: (complex: VisualizerComplexV1) => void;
}

const updateOutput = (nodes: VisualizerComplexNode[]) => ({
    bgNodeIds: nodes.filter(node => node.role === 'visualizerBg' && node.enabled).map(node => node.id),
    mainNodeIds: nodes.filter(node => node.role === 'visualizerMain' && node.enabled).map(node => node.id),
    overlayNodeIds: nodes.filter(node => node.role === 'visualizerOverlay' && node.enabled).map(node => node.id),
});

const updateNode = (
    complex: VisualizerComplexV1,
    nodeId: string,
    updater: (node: VisualizerComplexNode) => VisualizerComplexNode,
) => {
    const nodes = complex.nodes.map(node => (node.id === nodeId ? updater(node) : node));
    return { ...complex, nodes, output: updateOutput(nodes) };
};

const hasOpacityConfig = (node: VisualizerComplexNode): node is Extract<VisualizerComplexNode, { config: { opacity?: number } }> =>
    'config' in node && 'opacity' in node.config;

export const Inspector = ({ complex, selectedNodeId, theme, isDaylight, onChange }: InspectorProps) => {
    const selectedNode = complex.nodes.find(node => node.id === selectedNodeId) ?? null;

    if (!selectedNode) {
        return (
            <aside className="vis-editor-inspector" style={{ borderColor: `${theme.accentColor}33` }}>
                <div className="vis-editor-panel-title">Inspector</div>
                <div className="vis-editor-empty">Select a node to edit its graph settings.</div>
            </aside>
        );
    }

    const setNode = (updater: (node: VisualizerComplexNode) => VisualizerComplexNode) => {
        onChange(updateNode(complex, selectedNode.id, updater));
    };

    return (
        <aside className="vis-editor-inspector" style={{ borderColor: `${theme.accentColor}33` }}>
            <div className="vis-editor-panel-title">Inspector</div>
            <div className="vis-editor-inspector__id">{selectedNode.id}</div>

            <label className="vis-editor-field">
                <span>Label</span>
                <input value={selectedNode.label} onChange={event => setNode(node => ({ ...node, label: event.target.value }))} />
            </label>

            <CheckboxField label="Enabled" checked={selectedNode.enabled} onChange={checked => setNode(node => ({ ...node, enabled: checked }))} />

            <div className="vis-editor-readonly-grid">
                <span>Role</span>
                <strong>{selectedNode.role}</strong>
                <span>Kind</span>
                <strong>{selectedNode.kind}</strong>
            </div>

            {hasOpacityConfig(selectedNode) ? (
                <RangeField
                    label="Opacity"
                    value={selectedNode.config.opacity ?? 1}
                    min={0}
                    max={1}
                    step={0.01}
                    onChange={value => setNode(node => {
                        if (node.role === 'visualizerBg' || node.role === 'visualizerMain' || node.role === 'visualizerOverlay') {
                            return { ...node, config: { ...node.config, opacity: value } };
                        }
                        return node;
                    })}
                />
            ) : null}

            {selectedNode.role === 'visualizerBg' && selectedNode.kind === 'coverFluid' ? (
                <CheckboxField
                    label="Use cover color"
                    checked={selectedNode.config.useCoverColor ?? true}
                    onChange={checked => setNode(node => node.role === 'visualizerBg' ? { ...node, config: { ...node.config, useCoverColor: checked } } : node)}
                />
            ) : null}

            {selectedNode.role === 'visualizerBg' && selectedNode.kind === 'geometric' ? (
                <CheckboxField
                    label="Hide geometry shapes"
                    checked={selectedNode.config.hideShapes ?? false}
                    onChange={checked => setNode(node => node.role === 'visualizerBg' ? { ...node, config: { ...node.config, hideShapes: checked } } : node)}
                />
            ) : null}

            {selectedNode.role === 'visualizerMain' ? renderMainModeControls(selectedNode, setNode) : null}

            {selectedNode.role === 'visualizerOverlay' ? (
                <FieldGroup title="Subtitle overlay">
                    <CheckboxField label="Hide translation" checked={selectedNode.config.hideTranslation ?? false} onChange={checked => setNode(node => node.role === 'visualizerOverlay' ? { ...node, config: { ...node.config, hideTranslation: checked } } : node)} />
                    <RangeField label="Translation font" value={selectedNode.config.translationFontSizeRem ?? 1.1} min={0.7} max={1.8} step={0.01} onChange={value => setNode(node => node.role === 'visualizerOverlay' ? { ...node, config: { ...node.config, translationFontSizeRem: value } } : node)} />
                    <RangeField label="Upcoming font" value={selectedNode.config.upcomingFontSizeRem ?? 0.95} min={0.6} max={1.4} step={0.01} onChange={value => setNode(node => node.role === 'visualizerOverlay' ? { ...node, config: { ...node.config, upcomingFontSizeRem: value } } : node)} />
                </FieldGroup>
            ) : null}

            {selectedNode.role === 'visualizerMain' && complex.output.mainNodeIds.length > 1 ? (
                <div className="vis-editor-inspector__hint">Multiple main renderers are active; opacity and GPU cost stack in output order.</div>
            ) : (
                <div className="vis-editor-inspector__hint">
                    {isDaylight ? 'Daylight preview colors are active.' : 'Dark preview colors are active.'}
                </div>
            )}
        </aside>
    );
};
