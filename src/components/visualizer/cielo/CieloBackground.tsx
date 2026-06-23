import React, { useEffect, useRef } from 'react';
import * as twgl from 'twgl.js';
import { type MotionValue } from 'framer-motion';
import { type Theme, type AudioBands, type CieloTuning } from '../../../types';

interface CieloBackgroundProps {
    cameraYRef: React.MutableRefObject<number>;
    audioPower: MotionValue<number>;
    audioBands: AudioBands;
    theme: Theme;
    tuning: CieloTuning;
}

const vertexShader = `
    attribute vec2 position;
    varying vec2 vUv;
    void main() {
        vUv = position * 0.5 + 0.5;
        gl_Position = vec4(position, 0.0, 1.0);
    }
`;

const fragmentShader = `
    precision highp float;
    
    uniform vec2 u_resolution;
    uniform float u_dpr;
    uniform float u_cameraY;
    uniform vec3 u_colorBg;
    uniform vec3 u_colorPrimary;
    uniform vec3 u_colorAccent;
    uniform float u_densityGeo;
    uniform float u_densityParticle;
    uniform float u_colorMix;
    
    varying vec2 vUv;

    // Hash functions
    float hash21(vec2 p) {
        p = fract(p * vec2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    vec2 hash22(vec2 p) {
        float n = hash21(p);
        return vec2(n, hash21(p + n));
    }

    // 2D Rotation matrix
    mat2 rot(float a) {
        float s = sin(a), c = cos(a);
        return mat2(c, -s, s, c);
    }

    // SDF for Rhombus (Diamond/Kite)
    float ndot(vec2 a, vec2 b) { return a.x*b.x - a.y*b.y; }
    float sdRhombus( in vec2 p, in vec2 b ) {
        p = abs(p);
        float h = clamp( ndot(b-2.0*p,b)/dot(b,b), -1.0, 1.0 );
        float d = length( p-0.5*b*vec2(1.0-h,1.0+h) );
        return d * sign( p.x*b.y + p.y*b.x - b.x*b.y );
    }

    // SDF for Line segment
    float sdSegment(vec2 p, vec2 a, vec2 b) {
        vec2 pa = p - a, ba = b - a;
        float h = clamp(dot(pa, ba)/dot(ba, ba), 0.0, 1.0);
        return length(pa - ba*h);
    }

    void main() {
        // World coordinates in CSS pixels (1:1 with DOM)
        vec2 cssResolution = u_resolution / u_dpr;
        vec2 cssFragCoord = gl_FragCoord.xy / u_dpr;
        
        // Origin top-left to match DOM
        float screenY = cssResolution.y - cssFragCoord.y;
        vec2 worldPos = vec2(cssFragCoord.x, screenY + u_cameraY);
        
        // Base background color
        vec3 col = mix(u_colorBg, u_colorPrimary, u_colorMix * 0.1);

        // --- LAYER 1: Arcs (Thick and Thin) ---
        float gridC = 800.0;
        float aaC = 1.5 / gridC;
        vec2 cellC = worldPos / gridC;
        vec2 cellCId = floor(cellC);
        vec2 cellCUv = fract(cellC) - 0.5;
        
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec2 nOffset = vec2(float(x), float(y));
                vec2 nId = cellCId + nOffset;
                float hc = hash21(nId + 8.0);
                
                if (hc < 0.8 * u_densityGeo) {
                    vec2 localUv = cellCUv - nOffset;
                    localUv -= hash22(nId) - 0.5;
                    
                    float entrance = clamp((u_cameraY + cssResolution.y - nId.y * gridC) / (cssResolution.y * 0.5), 0.0, 1.0);
                    
                    float radius = 0.3 + hc * 1.5;
                    float dist = abs(length(localUv) - radius);
                    
                    // Mix of thick and thin arcs
                    float thickness = hc < 0.3 ? 0.02 : 0.003; 
                    
                    // Sweep
                    float angle = atan(localUv.y, localUv.x);
                    float sweep = smoothstep(-3.14, 3.14, angle);
                    
                    if (dist < thickness + aaC && sweep < entrance) {
                        float mask = smoothstep(thickness + aaC, thickness - aaC, dist);
                        // Colors: Black, Accent(Pink), or White
                        vec3 cCol = hc < 0.4 ? vec3(0.0) : (hc < 0.7 ? u_colorAccent : vec3(1.0));
                        col = mix(col, cCol, mask * 0.9);
                    }
                }
            }
        }

        // --- LAYER 2: Solid Circles ---
        float gridS = 500.0;
        float aaS = 1.5 / gridS;
        vec2 cellS = worldPos / gridS;
        vec2 cellSId = floor(cellS);
        vec2 cellSUv = fract(cellS) - 0.5;
        
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec2 nOffset = vec2(float(x), float(y));
                vec2 nId = cellSId + nOffset;
                float hs = hash21(nId + 19.0);
                
                if (hs < 0.3 * u_densityGeo) {
                    vec2 localUv = cellSUv - nOffset;
                    localUv -= hash22(nId) - 0.5;
                    
                    float entrance = clamp((u_cameraY + cssResolution.y - nId.y * gridS) / (cssResolution.y * 0.4), 0.0, 1.0);
                    localUv.y += (1.0 - entrance) * 1.0; 
                    
                    float radius = 0.1 + hs * 0.1;
                    float dist = length(localUv) - radius;
                    
                    if (dist < aaS) {
                        float mask = smoothstep(aaS, -aaS, dist);
                        vec3 sCol = hs > 0.5 ? u_colorPrimary : u_colorAccent;
                        col = mix(col, sCol, mask * 0.95);
                    }
                }
            }
        }

        // --- LAYER 3: Rhombus (Diamonds with center line) ---
        float gridT = 300.0;
        float aaT = 1.5 / gridT;
        vec2 cellT = worldPos / gridT;
        vec2 cellTId = floor(cellT);
        vec2 cellTUv = fract(cellT) - 0.5;
        
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec2 nOffset = vec2(float(x), float(y));
                vec2 nId = cellTId + nOffset;
                float ht = hash21(nId + 13.1);
                
                if (ht < 0.8 * u_densityParticle) {
                    vec2 localUv = cellTUv - nOffset;
                    localUv -= hash22(nId) - 0.5;
                    
                    float entrance = clamp((u_cameraY + cssResolution.y - nId.y * gridT) / (cssResolution.y * 1.0), 0.0, 1.0);
                    
                    // Fixed rotation (no continuous spinning)
                    float rotAngle = hash21(nId) * 6.28;
                    
                    // Pre-rotate UVs to local space of the rhombus
                    vec2 rotatedUv = localUv * rot(rotAngle);
                    
                    // Bezier translation animation (Cubic Ease-Out)
                    // The shape moves fast initially, then slows down smoothly
                    float ease = 1.0 - pow(1.0 - entrance, 3.0);
                    
                    // Translate along the local Y axis (towards its sharp corner)
                    // UV offset goes from positive to negative, so the shape moves from -Y to +Y in local space
                    rotatedUv.y += mix(2.0, -1.0, ease);
                    
                    // Rhombus size (width, height) - make them elongated diamonds
                    vec2 rbSize = vec2(0.1 + ht * 0.05, 0.2 + ht * 0.15);
                    
                    float d3 = sdRhombus(rotatedUv, rbSize);
                    
                    if (d3 < aaT) {
                        float triMask = smoothstep(aaT, -aaT, d3);
                        
                        // Pick color (Blue, Pink, or White)
                        vec3 triCol = ht < 0.2 ? vec3(1.0) : (ht < 0.5 ? u_colorAccent : u_colorPrimary);
                        
                        // Center line slicing the diamond longitudinally (along Y axis of the rhombus)
                        float lineDist = abs(rotatedUv.x);
                        float lineThickness = 0.003;
                        float centerLineMask = smoothstep(lineThickness + aaT, lineThickness - aaT, lineDist);
                        
                        // Mix the center line color (Black) over the rhombus color
                        triCol = mix(triCol, vec3(0.0), centerLineMask);
                        
                        col = mix(col, triCol, triMask * 0.95);
                    }
                }
            }
        }

        // Output
        gl_FragColor = vec4(col, 1.0);
    }
`;

// Simple hex to RGB parser since we are omitting full colorMix for brevity
const parseHex = (hex: string) => {
    let raw = hex.trim();
    if (raw.startsWith('#')) raw = raw.slice(1);
    if (raw.length === 3) raw = raw.split('').map(c => c + c).join('');
    if (raw.length !== 6 && raw.length !== 8) return [0, 0, 0];
    const r = parseInt(raw.slice(0, 2), 16) / 255;
    const g = parseInt(raw.slice(2, 4), 16) / 255;
    const b = parseInt(raw.slice(4, 6), 16) / 255;
    return [r, g, b];
};

export const CieloBackground: React.FC<CieloBackgroundProps> = ({
    cameraYRef,
    audioPower,
    theme,
    tuning,
}) => {
    const canvasRef = useRef<HTMLCanvasElement>(null);

    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas) return;

        const gl = canvas.getContext('webgl');
        if (!gl) {
            console.warn('WebGL not supported');
            return;
        }

        // Setup twgl
        const programInfo = twgl.createProgramInfo(gl, [vertexShader, fragmentShader]);
        
        // A full-screen quad: 2 triangles
        const arrays = {
            position: {
                numComponents: 2,
                data: [
                    -1, -1,
                     1, -1,
                    -1,  1,
                    -1,  1,
                     1, -1,
                     1,  1,
                ],
            },
        };
        const bufferInfo = twgl.createBufferInfoFromArrays(gl, arrays);

        let rafId: number;

        const render = () => {
            twgl.resizeCanvasToDisplaySize(canvas);
            gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);

            gl.useProgram(programInfo.program);
            twgl.setBuffersAndAttributes(gl, programInfo, bufferInfo);

            const uniforms = {
                u_resolution: [gl.canvas.width, gl.canvas.height],
                u_dpr: window.devicePixelRatio || 1.0,
                u_cameraY: cameraYRef.current,
                u_audioPower: audioPower.get(),
                u_colorBg: parseHex(theme.backgroundColor),
                u_colorPrimary: parseHex(theme.primaryColor),
                u_colorAccent: parseHex(theme.accentColor),
                u_densityGeo: tuning.geometricDensity,
                u_densityParticle: tuning.particleDensity,
                u_colorMix: tuning.baseColorMix,
            };

            twgl.setUniforms(programInfo, uniforms);
            twgl.drawBufferInfo(gl, bufferInfo);

            rafId = requestAnimationFrame(render);
        };

        rafId = requestAnimationFrame(render);

        return () => {
            cancelAnimationFrame(rafId);
            gl.deleteProgram(programInfo.program);
        };
    }, [audioPower, cameraYRef, theme.accentColor, theme.backgroundColor, theme.primaryColor, tuning.baseColorMix, tuning.geometricDensity, tuning.particleDensity]);

    return (
        <canvas
            ref={canvasRef}
            className="absolute inset-0 w-full h-full"
            style={{ display: 'block' }}
        />
    );
};

export default CieloBackground;
