import { describe, expect, it } from 'vitest';
import { createDefaultVisualizerComplex } from '@/components/visualizer/complex';
import { addComplexNode, connectFlowNodes, removeComplexEdge } from '@/components/visEditor/flowModel';

// test/unit/visualizer/flowModel.test.ts
// Covers persisted graph edits projected from the React Flow editor.
describe('visEditor flow model', () => {
    it('adds visual nodes with a unique id and output edge', () => {
        const complex = createDefaultVisualizerComplex();
        const result = addComplexNode(complex, {
            role: 'visualizerMain',
            mode: 'fume',
            label: 'Fume',
        });

        expect(result.nodeId).toBe('main-fume');
        expect(result.complex.output.mainNodeIds).toContain('main-fume');
        expect(result.complex.edges).toContainEqual({
            id: 'main-fume-output-player',
            source: 'main-fume',
            target: 'output-player',
        });
    });

    it('removes a selected persisted edge', () => {
        const complex = createDefaultVisualizerComplex();
        const next = removeComplexEdge(complex, 'main-output');

        expect(next.edges.some(edge => edge.id === 'main-output')).toBe(false);
        expect(next.output.mainNodeIds).toEqual(['main-classic']);
    });

    it('allows only v1 graph connection directions', () => {
        const complex = createDefaultVisualizerComplex();
        const allowed = connectFlowNodes(complex, { source: 'input-song', target: 'bg-solid' });
        const rejected = connectFlowNodes(complex, { source: 'main-classic', target: 'bg-solid' });

        expect(allowed.edges).toHaveLength(complex.edges.length + 1);
        expect(rejected.edges).toHaveLength(complex.edges.length);
    });
});
