#include <metal_stdlib>
using namespace metal;

// Vertex buffers are packed at 12 bytes per vertex; float3 would read at a 16-byte stride.
struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float3x3 normalMatrix;
    float4 color;
};

struct VertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float3 worldPos;
    float4 color;
};

vertex VertexOut cadVertexShader(
    uint vertexID [[vertex_id]],
    constant packed_float3 *positions [[buffer(0)]],
    constant packed_float3 *normals [[buffer(1)]],
    constant Uniforms &uniforms [[buffer(2)]]
) {
    VertexOut out;
    float3 pos = float3(positions[vertexID]);
    float3 norm = float3(normals[vertexID]);
    
    float4 worldPos = uniforms.modelMatrix * float4(pos, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldPos = worldPos.xyz;
    out.worldNormal = uniforms.normalMatrix * norm;
    out.color = uniforms.color;
    return out;
}

fragment float4 cadFragmentShader(VertexOut in [[stage_in]]) {
    float3 N = normalize(in.worldNormal);
    // Key light from upper-front right
    float3 L1 = normalize(float3(1.0, -1.0, 1.5));
    // Fill light from back-left
    float3 L2 = normalize(float3(-1.0, 1.0, 0.5));
    
    float diff1 = max(dot(N, L1), 0.0) * 0.7;
    float diff2 = max(dot(N, L2), 0.0) * 0.3;
    float ambient = 0.25;
    
    float lighting = ambient + diff1 + diff2;
    float3 finalRgb = in.color.rgb * lighting;
    
    return float4(finalRgb, in.color.a);
}

struct GridUniforms {
    float4x4 viewProjectionMatrix;
};

struct GridVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex GridVertexOut gridVertexShader(
    uint vertexID [[vertex_id]],
    constant packed_float3 *positions [[buffer(0)]],
    constant float4 *colors [[buffer(1)]],
    constant GridUniforms &uniforms [[buffer(2)]]
) {
    GridVertexOut out;
    out.position = uniforms.viewProjectionMatrix * float4(float3(positions[vertexID]), 1.0);
    out.color = colors[vertexID];
    return out;
}

fragment float4 gridFragmentShader(GridVertexOut in [[stage_in]]) {
    return in.color;
}

struct BillboardUniforms {
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float labelSize;
    float3 _padding;
};

struct BillboardVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

vertex BillboardVertexOut billboardVertexShader(
    uint vertexID [[vertex_id]],
    constant packed_float3 *centers [[buffer(0)]],
    constant float2 *offsets [[buffer(1)]],
    constant float2 *texCoords [[buffer(2)]],
    constant float4 *colors [[buffer(3)]],
    constant BillboardUniforms &uniforms [[buffer(4)]]
) {
    BillboardVertexOut out;
    float4 viewCenter = uniforms.viewMatrix * float4(float3(centers[vertexID]), 1.0);
    
    // Scale label with distance so it stays readable when camera zooms
    float distance = -viewCenter.z;
    float scale = max(1.0, distance / 150.0);
    
    float4 viewPos = viewCenter;
    viewPos.xy += offsets[vertexID] * uniforms.labelSize * scale;
    
    out.position = uniforms.projectionMatrix * viewPos;
    out.texCoord = texCoords[vertexID];
    out.color = colors[vertexID];
    return out;
}

fragment float4 billboardFragmentShader(
    BillboardVertexOut in [[stage_in]],
    texture2d<float> labelTexture [[texture(0)]],
    sampler labelSampler [[sampler(0)]]
) {
    float4 texColor = labelTexture.sample(labelSampler, in.texCoord);
    return float4(in.color.rgb, in.color.a * texColor.a);
}
