Shader "Nova/Sky"
{
    // Cheap mobile gradient skybox: 3-stop vertical gradient + sun disc/glow.
    // Lives in Resources/Shaders so it is always included in builds.
    Properties
    {
        _TopColor ("Top Color", Color) = (0.22, 0.42, 0.72, 1)
        _HorizonColor ("Horizon Color", Color) = (0.78, 0.83, 0.90, 1)
        _BottomColor ("Bottom Color", Color) = (0.32, 0.30, 0.27, 1)
        _SunDir ("Sun Direction", Vector) = (0.35, 0.45, -0.82, 0)
        _SunColor ("Sun Glow Color", Color) = (1.0, 0.88, 0.66, 1)
        _SunSize ("Sun Disc Size", Range(0.0, 0.5)) = 0.08
    }
    SubShader
    {
        Tags { "Queue" = "Background" "RenderType" = "Background" "PreviewType" = "Skybox" }
        Cull Off
        ZWrite Off
        Fog { Mode Off }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            fixed3 _TopColor;
            fixed3 _HorizonColor;
            fixed3 _BottomColor;
            float4 _SunDir;
            fixed3 _SunColor;
            float _SunSize;

            struct v2f
            {
                float4 pos : SV_POSITION;
                float3 dir : TEXCOORD0;
            };

            v2f vert(appdata_base v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.dir = v.vertex.xyz;
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float3 d = normalize(i.dir);
                float h = d.y;
                fixed3 col;
                if (h >= 0.0)
                    col = lerp(_HorizonColor, _TopColor, pow(h, 0.55));
                else
                    col = lerp(_HorizonColor, _BottomColor, pow(-h, 0.45));

                float s = max(dot(d, normalize(_SunDir.xyz)), 0.0);
                // Tight disc + wide glow.
                float disc = smoothstep(1.0 - _SunSize, 1.0 - _SunSize * 0.55, s);
                float glow = pow(s, 10.0) * 0.28;
                col += _SunColor * (disc * 1.6 + glow);
                return fixed4(col, 1.0);
            }
            ENDCG
        }
    }
    Fallback Off
}
