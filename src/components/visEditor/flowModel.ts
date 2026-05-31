import type { Connection, Edge, EdgeChange, Node, NodeChange } from '@xyflow/react';
import { applyEdgeChanges, applyNodeChanges } from '@xyflow/react';
import type {
    VisualizerBgKind,
    VisualizerComplexEdge,
    VisualizerComplexNode,
    VisualizerComplexV1,
    VisualizerInputKind,
    VisualizerOverlayKind,
    VisualizerNodeRole,
} from '../visualizer/complex';
import type { VisualizerMode } from '../../types';

// Converts the persisted complex schema to and from React Flow's transient graph model.
export interface FlowNodeData extends Record<string, unknown> {
    label: string;
    kind: string;
    role: VisualizerNodeRole;
    enabled: boolean;
    opacity?: number;
    mode?: string;
}

export type VisFlowNodeType = 'inputNode' | 'backgroundNode' | 'mainRendererNode' | 'overlayNode' | 'outputNode';
export type VisFlowNode = Node<FlowNodeData, VisFlowNodeType>;
export type VisFlowEdge = Edge;

export type AddComplexNodeRequest =
    | { role: 'input'; kind: VisualizerInputKind; label: string; }
    | { role: 'visualizerBg'; kind: VisualizerBgKind; label: string; }
    | { role: 'visualizerMain'; mode: VisualizerMode; label: string; }
    | { role: 'visualizerOverlay'; kind: VisualizerOverlayKind; label: string; };

export interface AddComplexNodeResult {
    complex: VisualizerComplexV1;
    nodeId: string;
}

const NODE_TYPES_BY_ROLE: Record<VisualizerNodeRole, VisFlowNodeType> = {
    input: 'inputNode',
    visualizerBg: 'backgroundNode',
    visualizerMain: 'mainRendererNode',
    visualizerOverlay: 'overlayNode',
    output: 'outputNode',
};

export const toFlowNodes = (complex: VisualizerComplexV1): VisFlowNode[] =>
    complex.nodes.map(node => ({
        id: node.id,
        type: NODE_TYPES_BY_ROLE[node.role],
        position: node.position,
        data: {
            label: node.label,
            kind: node.kind,
            role: node.role,
            enabled: node.enabled,
            opacity: 'config' in node ? node.config.opacity : undefined,
            mode: node.role === 'visualizerMain' ? node.config.mode : undefined,
        },
    }));

export const toFlowEdges = (complex: VisualizerComplexV1): VisFlowEdge[] =>
    complex.edges.map(edge => ({
        id: edge.id,
        source: edge.source,
        target: edge.target,
        animated: true,
        selectable: true,
    }));

const outputListForRole = (nodes: VisualizerComplexNode[], role: VisualizerNodeRole) =>
    nodes.filter(node => node.role === role && node.enabled).map(node => node.id);

export const rebuildOutput = (nodes: VisualizerComplexNode[]) => ({
    bgNodeIds: outputListForRole(nodes, 'visualizerBg'),
    mainNodeIds: outputListForRole(nodes, 'visualizerMain'),
    overlayNodeIds: outputListForRole(nodes, 'visualizerOverlay'),
});

const ensureUniqueEdgeId = (edges: VisualizerComplexEdge[], source: string, target: string) => {
    const baseId = `${source}-${target}`;
    const usedIds = new Set(edges.map(edge => edge.id));
    if (!usedIds.has(baseId)) {
        return baseId;
    }

    let suffix = 2;
    while (usedIds.has(`${baseId}-${suffix}`)) {
        suffix += 1;
    }
    return `${baseId}-${suffix}`;
};

export const applyFlowNodeChanges = (
    complex: VisualizerComplexV1,
    changes: NodeChange<VisFlowNode>[],
) => {
    const flowNodes = applyNodeChanges(changes, toFlowNodes(complex));
    const nodeIds = new Set(flowNodes.map(node => node.id));
    const positionsById = new Map(flowNodes.map(node => [node.id, node.position]));
    const nodes = complex.nodes
        .filter(node => nodeIds.has(node.id))
        .map(node => ({
            ...node,
            position: positionsById.get(node.id) ?? node.position,
        })) as VisualizerComplexNode[];

    return {
        ...complex,
        nodes,
        edges: complex.edges.filter(edge => nodeIds.has(edge.source) && nodeIds.has(edge.target)),
        output: rebuildOutput(nodes),
    };
};

export const applyFlowEdgeChanges = (
    complex: VisualizerComplexV1,
    changes: EdgeChange<VisFlowEdge>[],
) => {
    const flowEdges = applyEdgeChanges(changes, toFlowEdges(complex));
    const nodeIds = new Set(complex.nodes.map(node => node.id));
    const edges = flowEdges
        .filter(edge => nodeIds.has(edge.source) && nodeIds.has(edge.target))
        .map(edge => ({ id: edge.id, source: edge.source, target: edge.target }));

    return {
        ...complex,
        edges,
    };
};

export const connectFlowNodes = (
    complex: VisualizerComplexV1,
    connection: Connection,
) => {
    if (!connection.source || !connection.target || connection.source === connection.target) {
        return complex;
    }

    const sourceNode = complex.nodes.find(node => node.id === connection.source);
    const targetNode = complex.nodes.find(node => node.id === connection.target);
    const canConnect = sourceNode?.role === 'input'
        ? targetNode?.role === 'visualizerBg' || targetNode?.role === 'visualizerMain' || targetNode?.role === 'visualizerOverlay'
        : (
            sourceNode?.role === 'visualizerBg'
            || sourceNode?.role === 'visualizerMain'
            || sourceNode?.role === 'visualizerOverlay'
        ) && targetNode?.role === 'output';
    if (!canConnect) {
        return complex;
    }

    const hasEdge = complex.edges.some(edge => edge.source === connection.source && edge.target === connection.target);
    if (hasEdge) {
        return complex;
    }

    return {
        ...complex,
        edges: [
            ...complex.edges,
            {
                id: ensureUniqueEdgeId(complex.edges, connection.source, connection.target),
                source: connection.source,
                target: connection.target,
            },
        ],
    };
};

const slugify = (value: string) => value
    .replace(/([a-z0-9])([A-Z])/g, '$1-$2')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'node';

const uniqueNodeId = (nodes: VisualizerComplexNode[], base: string) => {
    const usedIds = new Set(nodes.map(node => node.id));
    if (!usedIds.has(base)) {
        return base;
    }

    let suffix = 2;
    while (usedIds.has(`${base}-${suffix}`)) {
        suffix += 1;
    }
    return `${base}-${suffix}`;
};

const nextNodePosition = (nodes: VisualizerComplexNode[], role: VisualizerNodeRole) => {
    const sameRoleNodes = nodes.filter(node => node.role === role);
    const index = sameRoleNodes.length;
    const xByRole: Record<VisualizerNodeRole, number> = {
        input: 40,
        visualizerBg: 330,
        visualizerMain: 620,
        visualizerOverlay: 620,
        output: 930,
    };

    return {
        x: xByRole[role],
        y: 40 + (index % 6) * 118,
    };
};

const createNodeFromRequest = (
    complex: VisualizerComplexV1,
    request: AddComplexNodeRequest,
): VisualizerComplexNode => {
    if (request.role === 'input') {
        return {
            id: uniqueNodeId(complex.nodes, `input-${slugify(request.kind)}`),
            role: 'input',
            kind: request.kind,
            label: request.label,
            enabled: true,
            position: nextNodePosition(complex.nodes, 'input'),
        };
    }

    if (request.role === 'visualizerBg') {
        return {
            id: uniqueNodeId(complex.nodes, `bg-${slugify(request.kind)}`),
            role: 'visualizerBg',
            kind: request.kind,
            label: request.label,
            enabled: true,
            position: nextNodePosition(complex.nodes, 'visualizerBg'),
            config: {
                opacity: request.kind === 'vignette' ? 0.65 : 1,
                hideShapes: request.kind === 'geometric' ? false : undefined,
                useCoverColor: request.kind === 'coverFluid' ? true : undefined,
            },
        };
    }

    if (request.role === 'visualizerMain') {
        return {
            id: uniqueNodeId(complex.nodes, `main-${slugify(request.mode)}`),
            role: 'visualizerMain',
            kind: 'mainRenderer',
            label: request.label,
            enabled: true,
            position: nextNodePosition(complex.nodes, 'visualizerMain'),
            config: { mode: request.mode, opacity: 1, lyricsFontScale: 1 },
        };
    }

    return {
        id: uniqueNodeId(complex.nodes, `overlay-${slugify(request.kind)}`),
        role: 'visualizerOverlay',
        kind: request.kind,
        label: request.label,
        enabled: true,
        position: nextNodePosition(complex.nodes, 'visualizerOverlay'),
        config: { opacity: 0.6, hideTranslation: false, translationFontSizeRem: 1.1, upcomingFontSizeRem: 0.95 },
    };
};

const autoEdgesForNode = (complex: VisualizerComplexV1, node: VisualizerComplexNode): VisualizerComplexEdge[] => {
    const outputNode = complex.nodes.find(existing => existing.role === 'output');
    if (!outputNode || node.role === 'input' || node.role === 'output') {
        return [];
    }

    return [{
        id: ensureUniqueEdgeId(complex.edges, node.id, outputNode.id),
        source: node.id,
        target: outputNode.id,
    }];
};

export const addComplexNode = (
    complex: VisualizerComplexV1,
    request: AddComplexNodeRequest,
): AddComplexNodeResult => {
    const node = createNodeFromRequest(complex, request);
    const nodes = [...complex.nodes, node];
    const edges = [...complex.edges, ...autoEdgesForNode(complex, node)];

    return {
        nodeId: node.id,
        complex: {
            ...complex,
            nodes,
            edges,
            output: rebuildOutput(nodes),
        },
    };
};

export const removeComplexEdge = (
    complex: VisualizerComplexV1,
    edgeId: string,
) => ({
    ...complex,
    edges: complex.edges.filter(edge => edge.id !== edgeId),
});
