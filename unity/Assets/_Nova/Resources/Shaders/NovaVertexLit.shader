Shader "Nova/VertexLit"
{
    // Cheap mobile lit shader for the world: albedo texture x vertex color x tint,
    // half-lambert from the main directional light + a global ambient term.
    // Pairs with ProcTexture slots (same material slots / tiling) so real art can
    // replace the procedural textures 1:1 later. UVs are authored in world units
    // (see WorldBatch) — material texture scale stays 1.
    Properties
    {
        _Color ("Tint", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 150

        Pass
        {
            Tags { "LightMode" = "ForwardBase" }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
                float3 worldNormal : TEXCOORD1;
                UNITY_FOG_COORDS(2)
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4 _Color;
            // Set by DayLight.cs from RenderSettings.ambientLight (avoids macro risk).
            float3 _NovaAmbient;

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.color = v.color;
                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                UNITY_TRANSFER_FOG(o, o.pos);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float3 n = normalize(i.worldNormal);
                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
                float nd = dot(n, lightDir) * 0.5 + 0.5; // half-lambert: soft Lagos daylight
                float3 albedo = tex2D(_MainTex, i.uv).rgb * i.color.rgb * _Color.rgb;
                float3 col = albedo * (_LightColor0.rgb * nd + _NovaAmbient);
                UNITY_APPLY_FOG(i.fogCoord, col);
                return fixed4(col, 1.0);
            }
            ENDCG
        }
    }
}
