import Foundation

public enum MetalShaders {
    public static let source: String = """
    #include <metal_stdlib>
    using namespace metal;

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
        constant float3 *positions [[buffer(0)]],
        constant float3 *normals [[buffer(1)]],
        constant Uniforms &uniforms [[buffer(2)]]
    ) {
        VertexOut out;
        float3 pos = positions[vertexID];
        float3 norm = normals[vertexID];
        
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
    """
}
