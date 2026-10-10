Shader "Nova/Water"
{
    // Animated water: samples the ProcTexture.Water() noise texture whose offset is
    // scrolled on the CPU by WaterAnimator (scrolling material offset), plus small
    // GPU vertex waves. Transparent, unlit, fogged.
    Properties
    {
        _Color ("Tint", Color) = (1,1,1,1)
        _MainTex ("Water (RGB)", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" }
        LOD 100
        ZWrite Off
        Cull Off
        Blend SrcAlpha OneMinusSrcAlpha

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
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
                float wave : TEXCOORD1;
                UNITY_FOG_COORDS(2)
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4 _Color;

            v2f vert (appdata v)
            {
                v2f o;
                float4 wp = mul(unity_ObjectToWorld, v.vertex);
                float w = sin(wp.x * 0.45 + _Time.y * 1.2) * 0.09
                        + cos(wp.z * 0.38 + _Time.y * 0.9) * 0.09;
                wp.y += w;
                o.pos = mul(UNITY_MATRIX_VP, wp);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.color = v.color;
                o.wave = w * 2.0;
                UNITY_TRANSFER_FOG(o, o.pos);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed3 t = tex2D(_MainTex, i.uv).rgb;
                fixed3 c = t * i.color.rgb * _Color.rgb + i.wave * 0.12;
                UNITY_APPLY_FOG(i.fogCoord, c);
                return fixed4(c, 0.9);
            }
            ENDCG
        }
    }
}
