import { beforeEach, describe, expect, it, vi } from 'vitest';
import { autoMatchBestLyric } from '@/utils/lyrics/autoMatchBestLyric';
import { neteaseApi } from '@/services/netease';
import { processNeteaseLyrics } from '@/utils/lyrics/neteaseProcessing';
import { searchQQLyrics, fetchQQLyrics } from '@/utils/lyrics/providers/qqLyricProvider';
import { searchKugouLyrics, fetchKugouLyrics } from '@/utils/lyrics/providers/kugouLyricProvider';

// test/unit/lyrics/autoMatchBestLyric.test.ts
// Unit tests for the best lyric auto-matcher.

vi.mock('@/services/netease', () => ({
    neteaseApi: {
        cloudSearch: vi.fn(),
        getLyric: vi.fn(),
        getSongDetail: vi.fn()
    }
}));

vi.mock('@/utils/lyrics/neteaseProcessing', () => ({
    processNeteaseLyrics: vi.fn()
}));

vi.mock('@/utils/lyrics/providers/qqLyricProvider', () => ({
    searchQQLyrics: vi.fn(),
    fetchQQLyrics: vi.fn()
}));

vi.mock('@/utils/lyrics/providers/kugouLyricProvider', () => ({
    searchKugouLyrics: vi.fn(),
    fetchKugouLyrics: vi.fn()
}));

describe('autoMatchBestLyric', () => {
    const cloudSearchMock = vi.mocked(neteaseApi.cloudSearch);
    const getLyricMock = vi.mocked(neteaseApi.getLyric);
    const processNeteaseLyricsMock = vi.mocked(processNeteaseLyrics);
    const searchQQLyricsMock = vi.mocked(searchQQLyrics);
    const fetchQQLyricsMock = vi.mocked(fetchQQLyrics);
    const searchKugouLyricsMock = vi.mocked(searchKugouLyrics);
    const fetchKugouLyricsMock = vi.mocked(fetchKugouLyrics);

    beforeEach(() => {
        vi.resetAllMocks();
    });

    it('prioritizes NetEase when perfect word-by-word match exists', async () => {
        cloudSearchMock.mockResolvedValue({
            result: {
                songs: [
                    { id: 101, name: 'Song Title', dt: 200000, ar: [{ name: 'Artist Name' }] }
                ]
            }
        });
        getLyricMock.mockResolvedValue({ lyric: '[00:00.00]test' });
        processNeteaseLyricsMock.mockResolvedValue({
            lyrics: { lines: [], isWordByWord: true },
            mainLrc: 'test',
            yrcLrc: 'test',
            transLrc: '',
            isPureMusic: false
        });

        const result = await autoMatchBestLyric('Song Title', 'Artist Name', 200000);
        expect(result).not.toBeNull();
        expect(result?.source).toBe('netease');
        expect(result?.id).toBe(101);
        expect(cloudSearchMock).toHaveBeenCalled();
        expect(searchQQLyricsMock).not.toHaveBeenCalled();
    });

    it('falls back to QQ Music if NetEase match does not have word-by-word lyrics', async () => {
        cloudSearchMock.mockResolvedValue({
            result: {
                songs: [
                    { id: 101, name: 'Song Title', dt: 200000, ar: [{ name: 'Artist Name' }] }
                ]
            }
        });
        getLyricMock.mockResolvedValue({ lyric: '[00:00.00]test' });
        processNeteaseLyricsMock.mockResolvedValue({
            lyrics: { lines: [], isWordByWord: false },
            mainLrc: 'test',
            yrcLrc: null,
            transLrc: '',
            isPureMusic: false
        });

        searchQQLyricsMock.mockResolvedValue([
            { id: 201, name: 'Song Title', duration: 201000, artists: [{ id: 1, name: 'Artist Name' }], qqMid: 'mid123' }
        ]);
        fetchQQLyricsMock.mockResolvedValue({ lines: [], isWordByWord: true });

        const result = await autoMatchBestLyric('Song Title', 'Artist Name', 200000);
        expect(result).not.toBeNull();
        expect(result?.source).toBe('qq');
        expect(result?.id).toBe(201);
        expect(result?.qqMid).toBe('mid123');
        expect(searchKugouLyricsMock).not.toHaveBeenCalled();
    });

    it('applies NetEase API chorus ranges to a QQ best lyric match', async () => {
        cloudSearchMock.mockResolvedValue({
            result: {
                songs: [
                    { id: 101, name: 'Song Title', dt: 200000, ar: [{ name: 'Artist Name' }] }
                ]
            }
        });
        getLyricMock.mockResolvedValue({ lyric: '[00:00.00]test' });
        processNeteaseLyricsMock.mockResolvedValue({
            lyrics: { lines: [], isWordByWord: false },
            mainLrc: 'test',
            yrcLrc: null,
            transLrc: '',
            isPureMusic: false,
            chorusRanges: [{ startTime: 34, endTime: 89 }]
        });

        searchQQLyricsMock.mockResolvedValue([
            { id: 201, name: 'Song Title', duration: 201000, artists: [{ id: 1, name: 'Artist Name' }], qqMid: 'mid123' }
        ]);
        fetchQQLyricsMock.mockResolvedValue({
            lines: [
                { fullText: 'Verse', startTime: 10, endTime: 20, words: [] },
                { fullText: 'API Chorus', startTime: 40, endTime: 45, words: [], isChorus: true, chorusEffect: 'bars' }
            ],
            isWordByWord: true
        });

        const result = await autoMatchBestLyric('Song Title', 'Artist Name', 200000);

        expect(result?.source).toBe('qq');
        expect(fetchQQLyricsMock).toHaveBeenCalledWith(
            expect.objectContaining({ id: 201 }),
            { chorusRanges: [{ startTime: 34, endTime: 89 }] }
        );
        expect(result?.lyrics.lines[0].isChorus).toBeUndefined();
        expect(result?.lyrics.lines[0].chorusEffect).toBeUndefined();
        expect(result?.lyrics.lines[1].isChorus).toBe(true);
        expect(result?.lyrics.lines[1].chorusEffect).toBe('bars');
    });

    it('reuses a preprocessed NetEase candidate for the same song id', async () => {
        cloudSearchMock.mockResolvedValue({
            result: {
                songs: [
                    { id: 101, name: 'Song Title', dt: 200000, ar: [{ name: 'Artist Name' }] }
                ]
            }
        });
        searchQQLyricsMock.mockResolvedValue([
            { id: 201, name: 'Song Title', duration: 201000, artists: [{ id: 1, name: 'Artist Name' }], qqMid: 'mid123' }
        ]);
        fetchQQLyricsMock.mockResolvedValue({ lines: [], isWordByWord: true });

        const result = await autoMatchBestLyric('Song Title', 'Artist Name', 200000, {
            neteaseCandidate: {
                id: 101,
                lyrics: { lines: [], isWordByWord: false },
                chorusRanges: [{ startTime: 71.288, endTime: 100.79 }]
            }
        });

        expect(result?.source).toBe('qq');
        expect(cloudSearchMock).not.toHaveBeenCalled();
        expect(getLyricMock).not.toHaveBeenCalled();
        expect(processNeteaseLyricsMock).not.toHaveBeenCalled();
        expect(fetchQQLyricsMock).toHaveBeenCalledWith(
            expect.objectContaining({ id: 201 }),
            { chorusRanges: [{ startTime: 71.288, endTime: 100.79 }] }
        );
    });

    it('returns the preprocessed NetEase candidate directly when it is word-by-word', async () => {
        const result = await autoMatchBestLyric('Song Title', 'Artist Name', 200000, {
            neteaseCandidate: {
                id: 101,
                lyrics: { lines: [], isWordByWord: true },
                chorusRanges: [{ startTime: 10, endTime: 30 }]
            }
        });

        expect(result?.source).toBe('netease');
        expect(result?.id).toBe(101);
        expect(cloudSearchMock).not.toHaveBeenCalled();
        expect(getLyricMock).not.toHaveBeenCalled();
        expect(searchQQLyricsMock).not.toHaveBeenCalled();
        expect(searchKugouLyricsMock).not.toHaveBeenCalled();
    });

    it('falls back to Kugou Music if both NetEase and QQ Music matches fail', async () => {
        cloudSearchMock.mockResolvedValue({ result: { songs: [] } });
        searchQQLyricsMock.mockResolvedValue([]);
        searchKugouLyricsMock.mockResolvedValue([
            { id: 301, name: 'Song Title', duration: 199000, artists: [{ id: 1, name: 'Artist Name' }], kgHash: 'hash123' }
        ]);
        fetchKugouLyricsMock.mockResolvedValue({ lines: [], isWordByWord: true });

        const result = await autoMatchBestLyric('Song Title', 'Artist Name', 200000);
        expect(result).not.toBeNull();
        expect(result?.source).toBe('kugou');
        expect(result?.id).toBe(301);
        expect(result?.kgHash).toBe('hash123');
    });

    it('returns null if no sources match the duration filter', async () => {
        cloudSearchMock.mockResolvedValue({
            result: {
                songs: [
                    { id: 101, name: 'Song Title', dt: 205000, ar: [{ name: 'Artist Name' }] }
                ]
            }
        });
        searchQQLyricsMock.mockResolvedValue([]);
        searchKugouLyricsMock.mockResolvedValue([]);

        const result = await autoMatchBestLyric('Song Title', 'Artist Name', 200000);
        expect(result).toBeNull();
    });
});
