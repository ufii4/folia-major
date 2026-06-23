import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useMotionValueEvent } from 'framer-motion';
import VisualizerShell from '../VisualizerShell';
import VisualizerSubtitleOverlay from '../VisualizerSubtitleOverlay';
import { type VisualizerSharedProps } from '../definition';
import { DEFAULT_CIELO_TUNING } from '../../../types';
import CieloBackground from './CieloBackground';
import { colorWithAlpha } from '../colorMix';

// A simple predictable random number generator based on a seed
const sfc32 = (a: number, b: number, c: number, d: number) => {
    return function() {
        a |= 0; b |= 0; c |= 0; d |= 0; 
        const t = (a + b | 0) + d | 0;
        d = d + 1 | 0;
        a = b ^ b >>> 9;
        b = c + (c << 3) | 0;
        c = c << 21 | c >>> 11;
        c = c + t | 0;
        return (t >>> 0) / 4294967296;
    }
};

const generateHashString = (str: string) => {
    let hash = 1779033703 ^ str.length;
    for(let i = 0; i < str.length; i++) {
        hash = Math.imul(hash ^ str.charCodeAt(i), 3432918353);
        hash = hash << 13 | hash >>> 19;
    }
    return () => {
        hash = Math.imul(hash ^ hash >>> 16, 2246822507);
        hash = Math.imul(hash ^ hash >>> 13, 3266489909);
        return (hash ^= hash >>> 16) >>> 0;
    };
};

interface LyricNodeState {
    id: string;
    worldY: number;
    worldX: number;
    scale: number;
    opacity: number;
    active: boolean;
    isOutline: boolean;
}

export const VisualizerCielo: React.FC<VisualizerSharedProps> = (props) => {
    const {
        currentTime,
        lines,
        theme,
        audioPower,
        audioBands,
        seed = 'cielo',
        cieloTuning = DEFAULT_CIELO_TUNING,
    } = props;

    const containerRef = useRef<HTMLDivElement>(null);
    const cameraY = useRef(0);
    const lastTime = useRef(performance.now());
    const wordNodesRef = useRef<Map<string, HTMLDivElement>>(new Map());
    const wordStatesRef = useRef<Map<string, LyricNodeState>>(new Map());
    
    // We only use React state for mounting/unmounting lines (discrete updates)
    const [activeLines, setActiveLines] = useState<number[]>([]);

    // We initialize a PRNG based on the song seed for consistent lyric placement
    const prng = useMemo(() => {
        const hashStr = typeof seed === 'string' ? seed : seed.toString();
        const getHash = generateHashString(hashStr);
        return sfc32(getHash(), getHash(), getHash(), getHash());
    }, [seed]);

    // Update active lines based on currentTime (discrete updates, roughly every few seconds)
    useMotionValueEvent(currentTime, 'change', (time) => {
        const PRE_TIME = 4.0; // Render 4 seconds before
        // The camera scrolls very slowly (60px/s). Staggered text might take up to 3000px height.
        // We need a massive POST_TIME to ensure words are not unmounted before they scroll off the top edge.
        const POST_TIME = 45.0; 
        
        const newActiveLines: number[] = [];
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const startTime = line.startTime;
            const endTime = line.endTime ?? (startTime + 3);
            
            if (time >= startTime - PRE_TIME && time <= endTime + POST_TIME) {
                newActiveLines.push(i);
            }
        }

        // Only update React state if the visible set of lines changed
        setActiveLines(prev => {
            if (prev.length !== newActiveLines.length) return newActiveLines;
            for (let i = 0; i < prev.length; i++) {
                if (prev[i] !== newActiveLines[i]) return newActiveLines;
            }
            return prev;
        });
    });

    // The core RAF loop for the Single Source of Truth
    useEffect(() => {
        let rafId: number;

        const loop = (now: number) => {
            const dt = Math.min(now - lastTime.current, 50) / 1000;
            lastTime.current = now;

            const power = audioPower.get();
            const speedMultiplier = cieloTuning.cameraSpeed;
            // Base speed: calm, smooth MG pan. Remove audio from deltaY to prevent jittery scrolling.
            const deltaY = dt * 60 * speedMultiplier;
            cameraY.current += deltaY;

            // Update DOM Lyrics
            const height = containerRef.current?.clientHeight ?? 800;
            const width = containerRef.current?.clientWidth ?? 1200;

            activeLines.forEach(lineIndex => {
                const line = lines[lineIndex];
                line.words.forEach((word, wordIndex) => {
                    const wordId = `${lineIndex}_${wordIndex}`;
                    let state = wordStatesRef.current.get(wordId);
                    if (!state) {
                        // Cascading Typography Layout
                        // Generate a consistent base X for the whole line
                        const lineHash = generateHashString(seed + lineIndex.toString())();
                        const startX = width * 0.2 + (lineHash % 1000 / 1000) * width * 0.5;
                        const startY = cameraY.current + height * 0.8 + 100;
                        
                        // Strict vertical spacing to prevent overlaps
                        const offsetY = wordIndex * 160; 
                        // Random X jitter around the line's base X
                        const offsetX = (prng() - 0.5) * 300; 
                        
                        const isHuge = prng() > 0.85;
                        const isOutline = prng() > 0.7;
                        
                        state = {
                            id: wordId,
                            worldY: startY + offsetY,
                            worldX: startX + offsetX,
                            scale: isHuge ? 4.0 + prng() * 1.5 : 1.5 + prng() * 1.5,
                            opacity: isOutline ? 0.8 : 0.4 + prng() * 0.4,
                            active: true,
                            isOutline
                        };
                        wordStatesRef.current.set(wordId, state);
                    }

                    const domNode = wordNodesRef.current.get(wordId);
                    if (domNode) {
                        // screenY = worldY - cameraY
                        const screenY = state.worldY - cameraY.current;
                        domNode.style.transform = `translate3d(${state.worldX}px, ${screenY}px, 0) scale(${state.scale})`;
                        domNode.style.opacity = `${state.opacity}`;
                        // We apply styles here since state might not be available during initial render map
                        if (state.isOutline) {
                            domNode.style.color = 'transparent';
                            domNode.style.WebkitTextStroke = `2px ${theme.primaryColor}`;
                        } else {
                            domNode.style.color = theme.primaryColor;
                            domNode.style.WebkitTextStroke = 'none';
                        }
                    }
                });
            });

            rafId = requestAnimationFrame(loop);
        };

        rafId = requestAnimationFrame(loop);
        return () => cancelAnimationFrame(rafId);
    }, [activeLines, audioPower, cieloTuning.cameraSpeed, prng]);

    return (
        <VisualizerShell {...props}>
            <div ref={containerRef} className="absolute inset-0 overflow-hidden pointer-events-none">
                {/* Background WebGL Shader layer */}
                <CieloBackground 
                    cameraYRef={cameraY}
                    audioPower={audioPower}
                    audioBands={audioBands}
                    theme={theme}
                    tuning={cieloTuning}
                />

                {/* Scattered Lyrics DOM layer (Word Level) */}
                <div className="absolute inset-0">
                    {activeLines.map(lineIndex => {
                        const line = lines[lineIndex];
                        return line.words.map((word, wordIndex) => {
                            const wordId = `${lineIndex}_${wordIndex}`;
                            return (
                                <div
                                    key={wordId}
                                    ref={(el) => {
                                        if (el) wordNodesRef.current.set(wordId, el);
                                        else wordNodesRef.current.delete(wordId);
                                    }}
                                    className="absolute top-0 left-0 text-5xl font-black tracking-widest origin-center whitespace-nowrap"
                                    style={{
                                        // Color is handled in the RAF loop to match state
                                        willChange: 'transform',
                                    }}
                                >
                                    {word.text}
                                </div>
                            );
                        });
                    })}
                </div>
            </div>

            {/* Standard Subtitle Overlay at the bottom */}
            <VisualizerSubtitleOverlay {...props} />
        </VisualizerShell>
    );
};

export default VisualizerCielo;
