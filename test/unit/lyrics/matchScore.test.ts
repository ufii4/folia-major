import { describe, expect, it } from 'vitest';
import { calculateMatchScore } from '@/utils/lyrics/matchScore';

// test/unit/lyrics/matchScore.test.ts

describe('calculateMatchScore', () => {
    it('normalizes accidental ms * 1000 durations before scoring', () => {
        const score = calculateMatchScore(
            {
                title: 'Night of Bloom (feat. nayuta)',
                artist: 'Kirara Magic/Xomu/nayuta',
                durationMs: 286000000
            },
            {
                id: 201,
                name: 'Night of Bloom',
                artists: [
                    { id: 1, name: 'Kirara Magic' },
                    { id: 2, name: 'Xomu' },
                    { id: 3, name: 'nayuta' }
                ],
                album: { id: 1, name: 'Night of Bloom' },
                duration: 286000
            }
        );

        expect(score).toBeGreaterThanOrEqual(85);
    });
});
