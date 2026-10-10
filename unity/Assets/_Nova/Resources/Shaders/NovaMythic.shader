Shader "Nova/MythicSkin"
{
    // NOVA mythic skin surface — ported from Godot shaders/mythic_skin.gdshader.
    // Procedural ANIMATED theme detail, unlit + emissive only (no lighting cost).
    // _Pattern: 0 molten cracks, 1 creeping frost, 2 swirling void nebula,
    //           3 circuitry traces, 4 energy flow bands.
    // _Evolve: 0..1 kill evolution — intensifies glow and pattern coverage.
    // Pattern coordinates come from OBJECT-SPACE position (gun meshes have no
    // usable UVs), so the same material works on any factory-built gun part.
    Properties
    {
        _Primary ("Primary Color", Color) = (1,0.4,0.1,1)
        _Secondary ("Secondary Color", Color) = (1,0.8,0.3,1)
        _Pattern ("Pattern", Int) = 0
        _Evolve ("Evolve", Range(0,1)) = 0
        _GlowStrength ("Glow Strength", Range(0,4)) = 1.4
        _AnimSpeed ("Anim Speed", Range(0,4)) = 1.0
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 objPos : TEXCOORD0;
                UNITY_FOG_COORDS(1)
            };

            fixed4 _Primary;
            fixed4 _Secondary;
            int _Pattern;
            float _Evolve;
            float _GlowStrength;
            float _AnimSpeed;

            float hash21(float2 p)
            {
                p = frac(p * float2(234.34, 435.345));
                p += dot(p, p + 34.23);
                return frac(p.x * p.y);
            }

            float vnoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);
                float a = hash21(i);
                float b = hash21(i + float2(1.0, 0.0));
                float c = hash21(i + float2(0.0, 1.0));
                float d = hash21(i + float2(1.0, 1.0));
                return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
            }

            float fbm(float2 p)
            {
                float v = 0.0;
                float a = 0.5;
                for (int i = 0; i < 3; i++)
                {
                    v += a * vnoise(p);
                    p *= 2.03;
                    a *= 0.5;
                }
                return v;
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.objPos = v.vertex.xyz;
                UNITY_TRANSFER_FOG(o, o.pos);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // Object-space pattern coords: guns are ~1 m, parts near origin.
                float2 uv = i.objPos.xy * 2.3 + i.objPos.zx * 1.9;
                float t = _Time.y * _AnimSpeed;
                float pat = 0.0;
                if (_Pattern == 0)
                {
                    // Molten cracks: ridged fbm, slowly creeping.
                    float n = fbm(uv * 5.0 + float2(t * 0.08, -t * 0.05));
                    float r = 1.0 - abs(2.0 * n - 1.0);
                    pat = pow(clamp(r * 1.4 - 0.55, 0.0, 1.0), 1.5);
                }
                else if (_Pattern == 1)
                {
                    // Creeping frost: streaky high-frequency noise; coverage grows with evolve.
                    float n = fbm(float2(uv.x * 7.0, uv.y * 22.0) + float2(0.0, t * 0.03));
                    float cover = 0.45 + 0.35 * _Evolve + 0.08 * sin(t * 0.3);
                    pat = smoothstep(cover, cover + 0.25, n);
                }
                else if (_Pattern == 2)
                {
                    // Swirling void nebula: domain-warped swirl.
                    float2 c = (i.objPos.xy + i.objPos.zx) * 1.5;
                    float ang = atan2(c.y, c.x) + t * 0.25 + fbm(uv * 3.0) * 4.0;
                    float rad = length(c) * 3.0;
                    pat = 0.5 + 0.5 * sin(ang * 2.0 + rad * 4.0 - t * 0.6);
                    pat = smoothstep(0.35, 0.9, pat);
                }
                else if (_Pattern == 3)
                {
                    // Circuitry traces: grid lines with traveling pulses.
                    float2 g = abs(frac(uv * 10.0) - 0.5);
                    float line = smoothstep(0.44, 0.5, max(g.x, g.y));
                    float pulse = 0.5 + 0.5 * sin((uv.x + uv.y) * 12.0 - t * 3.0);
                    pat = line * (0.35 + 0.65 * pulse);
                }
                else
                {
                    // Energy flow: diagonal bands over fbm warp.
                    float b = sin((uv.x * 0.7 + uv.y) * 9.0 - t * 2.2 + fbm(uv * 4.0) * 3.0);
                    pat = smoothstep(0.1, 0.9, 0.5 + 0.5 * b);
                }
                float glow = _GlowStrength * (0.55 + 0.85 * _Evolve + 0.22 * sin(t * 1.7));
                fixed3 base = fixed3(0.05, 0.05, 0.07);
                fixed3 alb = lerp(base, _Primary.rgb * 0.35, pat * 0.6);
                fixed3 emis = lerp(_Primary.rgb * 0.35, _Secondary.rgb, pat) * glow;
                fixed3 c = alb + emis;
                UNITY_APPLY_FOG(i.fogCoord, c);
                return fixed4(c, 1.0);
            }
            ENDCG
        }
    }
}
