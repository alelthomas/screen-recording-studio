#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct MotionBlurUniforms {
    float2 velocityUV;
    float intensity;
    float zoomFactor;
    float vignetteIntensity;
    float brightnessOffset;
};

vertex VertexOut fullscreenQuadVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    constexpr float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

fragment float4 directionalMotionBlurFragment(
    VertexOut in [[stage_in]],
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    constant MotionBlurUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = in.uv;
    float2 vel = uniforms.velocityUV * uniforms.intensity;
    float speed = length(vel);

    float4 accum = float4(0.0);
    if (speed < 0.0004) {
        accum = sourceTexture.sample(texSampler, uv);
    } else {
        constexpr int SAMPLES = 12;
        float weightSum = 0.0;
        for (int i = 0; i < SAMPLES; ++i) {
            float t = (float(i) / float(SAMPLES - 1)) - 0.5;
            float2 sampleUV = clamp(uv + vel * t, float2(0.001), float2(0.999));
            float w = 1.0 - abs(t) * 0.65;
            accum += sourceTexture.sample(texSampler, sampleUV) * w;
            weightSum += w;
        }
        accum /= max(weightSum, 0.001);
    }

    // Apply subtle vignette & brightness offset
    float2 centered = uv - float2(0.5, 0.5);
    float distSq = dot(centered, centered);
    float vignette = 1.0 - clamp(distSq * uniforms.vignetteIntensity * 1.4, 0.0, 0.65);
    accum.rgb = clamp((accum.rgb + uniforms.brightnessOffset) * vignette, 0.0, 1.0);
    return accum;
}
