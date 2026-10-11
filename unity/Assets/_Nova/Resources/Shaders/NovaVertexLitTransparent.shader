Shader "Nova/VertexLitTransparent"
{
    // Transparent twin of Nova/VertexLit: albedo texture x vertex color x tint,
    // half-lambert lighting, alpha blended. Lives in Resources/Shaders so it is
    // always included in builds (built-in shaders get stripped when nothing
    // references them, which turns materials magenta on device).
    Properties
    {
        _Color ("Tint", Color) = (1,1,1,0.5)
        _MainTex ("Albedo (RGB) Alpha (A)", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" }
        LOD 150
        ZWrite Off
        Blend SrcAlpha OneMinusSrcAlpha

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
                float nd = dot(n, lightDir) * 0.5 + 0.5;
                fixed4 tex = tex2D(_MainTex, i.uv);
                float3 albedo = tex.rgb * i.color.rgb * _Color.rgb;
                float alpha = tex.a * i.color.a * _Color.a;
                float3 col = albedo * (_LightColor0.rgb * nd + _NovaAmbient);
                UNITY_APPLY_FOG(i.fogCoord, col);
                return fixed4(col, alpha);
            }
            ENDCG
        }
    }
    Fallback Off
}
