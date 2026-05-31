import { useCallback, useMemo, useState, type CSSProperties, type MouseEvent } from 'react';
import {
    Background,
    Controls,
    MiniMap,
    ReactFlow,
    ReactFlowProvider,
    type Connection,
    type Edge,
    type EdgeChange,
    type NodeChange,
    type NodeTypes,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import './VisEditor.css';
import { Inspector } from './Inspector';
import { BackgroundNode, InputNode, MainRendererNode, OutputNode, OverlayNode } from './VisNode';
import {
    addComplexNode,
    applyFlowEdgeChanges,
    applyFlowNodeChanges,
    connectFlowNodes,
    removeComplexEdge,
    toFlowEdges,
    toFlowNodes,
    type AddComplexNodeRequest,
    type VisFlowEdge,
    type VisFlowNode,
} from './flowModel';
import type { VisEditorProps } from './types';
import { VISUALIZER_REGISTRY } from '../visualizer/registry';

// Full-screen visualizer complex editor composed from a graph canvas, preview, and inspector.
const nodeTypes: NodeTypes = {
    inputNode: InputNode,
    backgroundNode: BackgroundNode,
    mainRendererNode: MainRendererNode,
    overlayNode: OverlayNode,
    outputNode: OutputNode,
};

const hasPersistedNodeChange = (changes: NodeChange<VisFlowNode>[]) =>
    changes.some(change => change.type === 'position' || change.type === 'remove');

const hasPersistedEdgeChange = (changes: EdgeChange<VisFlowEdge>[]) =>
    changes.some(change => change.type === 'remove');

const inputPalette: AddComplexNodeRequest[] = [
    { role: 'input', kind: 'theme', label: 'Theme Input' },
    { role: 'input', kind: 'audio', label: 'Audio Input' },
    { role: 'input', kind: 'lyrics', label: 'Lyrics Input' },
    { role: 'input', kind: 'song', label: 'Song Input' },
    { role: 'input', kind: 'playback', label: 'Playback Input' },
];

const backgroundPalette: AddComplexNodeRequest[] = [
    { role: 'visualizerBg', kind: 'solidTheme', label: 'Theme Background' },
    { role: 'visualizerBg', kind: 'coverFluid', label: 'Cover Fluid' },
    { role: 'visualizerBg', kind: 'geometric', label: 'Geometry' },
    { role: 'visualizerBg', kind: 'vignette', label: 'Vignette' },
];

const overlayPalette: AddComplexNodeRequest[] = [
    { role: 'visualizerOverlay', kind: 'subtitle', label: 'Subtitle Overlay' },
];

export const VisEditor = ({
    complex,
    theme,
    isDaylight,
    onChange,
    onSave,
    onReset,
    onBack,
    preview,
}: VisEditorProps) => {
    const [selectedNodeId, setSelectedNodeId] = useState<string | null>(complex.nodes[0]?.id ?? null);
    const [selectedEdgeId, setSelectedEdgeId] = useState<string | null>(null);
    const nodes = useMemo(() => toFlowNodes(complex), [complex]);
    const edges = useMemo(() => toFlowEdges(complex), [complex]);
    const mainPalette = useMemo<AddComplexNodeRequest[]>(() => VISUALIZER_REGISTRY.map(entry => ({
        role: 'visualizerMain',
        mode: entry.mode,
        label: entry.labelFallback,
    })), []);

    const onNodesChange = useCallback((changes: NodeChange<VisFlowNode>[]) => {
        if (!hasPersistedNodeChange(changes)) {
            return;
        }

        const nextComplex = applyFlowNodeChanges(complex, changes);
        const stillSelected = selectedNodeId ? nextComplex.nodes.some(node => node.id === selectedNodeId) : false;
        if (!stillSelected) {
            setSelectedNodeId(nextComplex.nodes[0]?.id ?? null);
        }
        setSelectedEdgeId(null);
        onChange(nextComplex);
    }, [complex, onChange, selectedNodeId]);

    const onEdgesChange = useCallback((changes: EdgeChange<VisFlowEdge>[]) => {
        if (!hasPersistedEdgeChange(changes)) {
            return;
        }

        const nextComplex = applyFlowEdgeChanges(complex, changes);
        const stillSelected = selectedEdgeId ? nextComplex.edges.some(edge => edge.id === selectedEdgeId) : false;
        if (!stillSelected) {
            setSelectedEdgeId(null);
        }
        onChange(nextComplex);
    }, [complex, onChange, selectedEdgeId]);

    const onConnect = useCallback((connection: Connection) => {
        onChange(connectFlowNodes(complex, connection));
    }, [complex, onChange]);

    const addNode = useCallback((request: AddComplexNodeRequest) => {
        const result = addComplexNode(complex, request);
        setSelectedNodeId(result.nodeId);
        setSelectedEdgeId(null);
        onChange(result.complex);
    }, [complex, onChange]);

    const deleteSelectedEdge = useCallback(() => {
        if (!selectedEdgeId) {
            return;
        }

        onChange(removeComplexEdge(complex, selectedEdgeId));
        setSelectedEdgeId(null);
    }, [complex, onChange, selectedEdgeId]);

    const onEdgeClick = useCallback((_: MouseEvent, edge: Edge) => {
        setSelectedEdgeId(edge.id);
        setSelectedNodeId(null);
    }, []);

    const clearSelection = useCallback(() => {
        setSelectedNodeId(null);
        setSelectedEdgeId(null);
    }, []);

    const renderPaletteGroup = (title: string, items: AddComplexNodeRequest[]) => (
        <section className="vis-editor-palette__group">
            <div className="vis-editor-palette__title">{title}</div>
            <div className="vis-editor-palette__buttons">
                {items.map(item => (
                    <button
                        key={`${item.role}-${'kind' in item ? item.kind : item.mode}`}
                        type="button"
                        onClick={() => addNode(item)}
                    >
                        {item.label}
                    </button>
                ))}
            </div>
        </section>
    );

    return (
        <ReactFlowProvider>
            <div
                className={`vis-editor ${isDaylight ? 'vis-editor--daylight' : 'vis-editor--night'}`}
                style={{
                    '--vis-editor-bg': theme.backgroundColor,
                    '--vis-editor-primary': theme.primaryColor,
                    '--vis-editor-accent': theme.accentColor,
                    '--vis-editor-secondary': theme.secondaryColor,
                } as CSSProperties}
            >
                <header className="vis-editor__header">
                    <div>
                        <div className="vis-editor__eyebrow">Visualizer Complex</div>
                        <h1>Flow Editor</h1>
                    </div>
                    <div className="vis-editor__actions">
                        {selectedEdgeId ? <button type="button" onClick={deleteSelectedEdge}>Delete edge</button> : null}
                        {onBack ? <button type="button" onClick={onBack}>Back</button> : null}
                        {onReset ? <button type="button" onClick={onReset}>Reset</button> : null}
                        {onSave ? <button type="button" className="vis-editor__primary-action" onClick={onSave}>Save</button> : null}
                    </div>
                </header>

                <main className="vis-editor__body">
                    <aside className="vis-editor-palette" aria-label="Node library">
                        <div className="vis-editor-panel-title">Node Library</div>
                        {renderPaletteGroup('Inputs', inputPalette)}
                        {renderPaletteGroup('Backgrounds', backgroundPalette)}
                        {renderPaletteGroup('Main Renderers', mainPalette)}
                        {renderPaletteGroup('Overlays', overlayPalette)}
                    </aside>

                    <section className="vis-editor__canvas" aria-label="Visualizer complex graph">
                        <ReactFlow
                            nodes={nodes}
                            edges={edges}
                            nodeTypes={nodeTypes}
                            onNodesChange={onNodesChange}
                            onEdgesChange={onEdgesChange}
                            onConnect={onConnect}
                            onNodeClick={(_, node) => {
                                setSelectedNodeId(node.id);
                                setSelectedEdgeId(null);
                            }}
                            onEdgeClick={onEdgeClick}
                            onPaneClick={clearSelection}
                            fitView
                            fitViewOptions={{ padding: 0.18 }}
                        >
                            <Background />
                            <Controls />
                            <MiniMap pannable zoomable />
                        </ReactFlow>
                    </section>

                    <aside className="vis-editor__side">
                        <section className="vis-editor-preview" aria-label="Preview">
                            <div className="vis-editor-panel-title">Preview</div>
                            <div className="vis-editor-preview__frame">
                                {preview ?? <div className="vis-editor-empty">No preview mounted.</div>}
                            </div>
                        </section>
                        <Inspector
                            complex={complex}
                            selectedNodeId={selectedNodeId}
                            theme={theme}
                            isDaylight={isDaylight}
                            onChange={onChange}
                        />
                    </aside>
                </main>
            </div>
        </ReactFlowProvider>
    );
};

export default VisEditor;
