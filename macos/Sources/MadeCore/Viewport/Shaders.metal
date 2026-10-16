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
    float3 viewNormal;
    float3 viewPos;
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
    float4 viewPos = uniforms.viewMatrix * worldPos;
    out.position = uniforms.projectionMatrix * viewPos;
    out.worldPos = worldPos.xyz;
    out.worldNormal = uniforms.normalMatrix * norm;

    bool isOrtho = abs(uniforms.projectionMatrix[3][3] - 1.0) < 1e-3;
    out.viewPos = isOrtho ? float3(0.0, 0.0, -1.0) : viewPos.xyz;
    out.viewNormal = (uniforms.viewMatrix * float4(out.worldNormal, 0.0)).xyz;
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

    // Silhouette contouring on curved surfaces:
    float3 vN = normalize(in.viewNormal);
    float3 vV = normalize(-in.viewPos); // View vector towards eye in view space
    float ndotv = abs(dot(vN, vV));
    float dN = length(fwidth(vN));

    // Flat surfaces (like boxes) have dN ≈ 0; curved surfaces (cylinders, spheres) have dN > 0.005.
    if (dN > 0.005) {
        float delta = fwidth(ndotv);
        float distPx = ndotv / max(delta, 1e-4);
        float silhouetteWidth = 1.2;
        if (distPx < silhouetteWidth) {
            float edgeAlpha = 1.0 - saturate(distPx / silhouetteWidth);
            float3 edgeColor = float3(0.12, 0.12, 0.14);
            finalRgb = mix(finalRgb, edgeColor, edgeAlpha);
        }
    }
    
    return float4(finalRgb, in.color.a);
}

fragment float4 unshadedFragmentShader(VertexOut in [[stage_in]]) {
    return in.color;
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

struct OutlineUniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float3x3 normalMatrix;
    float4 color;
    float outlineWidth;
    float3 _padding;
};

struct OutlineVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex OutlineVertexOut outlineVertexShader(
    uint vertexID [[vertex_id]],
    constant packed_float3 *positions [[buffer(0)]],
    constant packed_float3 *normals [[buffer(1)]],
    constant OutlineUniforms &uniforms [[buffer(2)]]
) {
    OutlineVertexOut out;
    float3 pos = float3(positions[vertexID]);
    float3 norm = float3(normals[vertexID]);

    float4 worldPos = uniforms.modelMatrix * float4(pos, 1.0);
    float3 worldNormal = float3(0.0);
    if (length_squared(norm) > 1e-6) {
        worldNormal = normalize(uniforms.normalMatrix * norm);
    }

    float4 viewPos = uniforms.viewMatrix * worldPos;
    float3 viewNormal = float3(0.0);
    if (length_squared(worldNormal) > 1e-6) {
        viewNormal = normalize((uniforms.viewMatrix * float4(worldNormal, 0.0)).xyz);
    }

    float4 clipPos = uniforms.projectionMatrix * viewPos;
    float4 clipNormal = uniforms.projectionMatrix * float4(viewNormal, 0.0);

    float2 normalDir = clipNormal.xy;
    if (length_squared(normalDir) > 1e-6) {
        clipPos.xy += normalize(normalDir) * uniforms.outlineWidth * clipPos.w;
    }

    out.position = clipPos;
    out.color = uniforms.color;
    return out;
}

fragment float4 outlineFragmentShader(OutlineVertexOut in [[stage_in]]) {
    return in.color;
}

// MARK: - Sub-element GPU Pick Shaders (BL-SEL-02)

struct PickUniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    uint solidIndex;
    uint subelementType; // 1 = face, 2 = edge, 3 = vertex
    uint elementId;
    float viewportWidth;
    float viewportHeight;
    float tolerancePx;   // 6.0 to 8.0
    float depthBias;     // negative offset for edge / vertex
    float _padding;
};

struct EdgeSegmentData {
    packed_float3 start;
    packed_float3 end;
    uint edgeId;
    uint _padding;
};

struct VertexData {
    packed_float3 position;
    uint vertexId;
};

struct PickFaceVertexOut {
    float4 position [[position]];
};

vertex PickFaceVertexOut pickFaceVertexShader(
    uint vertexID [[vertex_id]],
    constant packed_float3 *positions [[buffer(0)]],
    constant PickUniforms &uniforms [[buffer(1)]]
) {
    PickFaceVertexOut out;
    float3 pos = float3(positions[vertexID]);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * float4(pos, 1.0);
    return out;
}

fragment uint4 pickFaceFragmentShader(
    PickFaceVertexOut in [[stage_in]],
    uint primitiveID [[primitive_id]],
    constant PickUniforms &uniforms [[buffer(1)]],
    constant uint *triangleFaceIds [[buffer(2)]]
) {
    uint faceId = triangleFaceIds != nullptr ? triangleFaceIds[primitiveID] : 0;
    return uint4(uniforms.solidIndex, 1, faceId, 0);
}

struct PickEdgeVertexOut {
    float4 position [[position]];
    uint edgeId;
};

vertex PickEdgeVertexOut pickEdgeVertexShader(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant PickUniforms &uniforms [[buffer(1)]],
    constant EdgeSegmentData *segments [[buffer(3)]]
) {
    PickEdgeVertexOut out;
    EdgeSegmentData seg = segments[instanceID];
    out.edgeId = seg.edgeId;

    float4 aWorld = uniforms.modelMatrix * float4(float3(seg.start), 1.0);
    float4 bWorld = uniforms.modelMatrix * float4(float3(seg.end), 1.0);

    float4 aClip = uniforms.projectionMatrix * uniforms.viewMatrix * aWorld;
    float4 bClip = uniforms.projectionMatrix * uniforms.viewMatrix * bWorld;

    float wA = max(aClip.w, 1e-4);
    float wB = max(bClip.w, 1e-4);

    float2 aNdc = aClip.xy / wA;
    float2 bNdc = bClip.xy / wB;

    float2 aScreen = float2((aNdc.x + 1.0) * 0.5 * uniforms.viewportWidth, (aNdc.y + 1.0) * 0.5 * uniforms.viewportHeight);
    float2 bScreen = float2((bNdc.x + 1.0) * 0.5 * uniforms.viewportWidth, (bNdc.y + 1.0) * 0.5 * uniforms.viewportHeight);

    float2 dir = bScreen - aScreen;
    float len = length(dir);
    float2 nScreen = len > 1e-4 ? float2(-dir.y, dir.x) / len : float2(0.0, 1.0);

    float halfTol = max(uniforms.tolerancePx * 0.5, 1.0);

    // Quad vertex indices (2 triangles = 6 vertices):
    // 0: A - N, 1: B - N, 2: A + N
    // 3: A + N, 4: B - N, 5: B + N
    bool isB = (vertexID == 1 || vertexID == 4 || vertexID == 5);
    float signN = (vertexID == 2 || vertexID == 3 || vertexID == 5) ? 1.0 : -1.0;

    float4 baseClip = isB ? bClip : aClip;
    float baseW = isB ? wB : wA;

    float2 offsetScreen = nScreen * (signN * halfTol);
    float2 offsetNdc = float2(2.0 * offsetScreen.x / max(uniforms.viewportWidth, 1.0),
                              2.0 * offsetScreen.y / max(uniforms.viewportHeight, 1.0));

    float4 pClip = baseClip;
    pClip.xy += offsetNdc * baseW;
    pClip.z -= uniforms.depthBias * baseW;

    out.position = pClip;
    return out;
}

fragment uint4 pickEdgeFragmentShader(
    PickEdgeVertexOut in [[stage_in]],
    constant PickUniforms &uniforms [[buffer(1)]]
) {
    return uint4(uniforms.solidIndex, 2, in.edgeId, 0);
}

struct PickVertexVertexOut {
    float4 position [[position]];
    uint vertexId;
};

vertex PickVertexVertexOut pickVertexVertexShader(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant PickUniforms &uniforms [[buffer(1)]],
    constant VertexData *vertices [[buffer(4)]]
) {
    PickVertexVertexOut out;
    VertexData v = vertices[instanceID];
    out.vertexId = v.vertexId;

    float4 vWorld = uniforms.modelMatrix * float4(float3(v.position), 1.0);
    float4 vClip = uniforms.projectionMatrix * uniforms.viewMatrix * vWorld;
    float wV = max(vClip.w, 1e-4);

    float halfTol = max(uniforms.tolerancePx * 0.5, 1.0);

    // 6 vertices per vertex instance forming camera-facing quad
    float signX = (vertexID == 1 || vertexID == 4 || vertexID == 5) ? 1.0 : -1.0;
    float signY = (vertexID == 2 || vertexID == 3 || vertexID == 5) ? 1.0 : -1.0;

    float2 offsetScreen = float2(signX * halfTol, signY * halfTol);
    float2 offsetNdc = float2(2.0 * offsetScreen.x / max(uniforms.viewportWidth, 1.0),
                              2.0 * offsetScreen.y / max(uniforms.viewportHeight, 1.0));

    float4 pClip = vClip;
    pClip.xy += offsetNdc * wV;
    pClip.z -= (uniforms.depthBias * 1.5) * wV;

    out.position = pClip;
    return out;
}

fragment uint4 pickVertexFragmentShader(
    PickVertexVertexOut in [[stage_in]],
    constant PickUniforms &uniforms [[buffer(1)]]
) {
    return uint4(uniforms.solidIndex, 3, in.vertexId, 0);
}

// MARK: - Sub-element Edge Highlight Shaders (BL-SEL-04)

struct EdgeHighlightUniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float4 color;
    float viewportWidth;
    float viewportHeight;
    float lineWidth;
    uint targetEdgeId;
    float depthBias;
    float3 _padding;
};

struct EdgeHighlightVertexOut {
    float4 position [[position]];
};

vertex EdgeHighlightVertexOut edgeHighlightVertexShader(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant EdgeHighlightUniforms &uniforms [[buffer(2)]],
    constant EdgeSegmentData *segments [[buffer(3)]]
) {
    EdgeHighlightVertexOut out;
    EdgeSegmentData seg = segments[instanceID];
    if (seg.edgeId != uniforms.targetEdgeId) {
        out.position = float4(0.0, 0.0, 0.0, 1.0);
        return out;
    }

    float4 aWorld = uniforms.modelMatrix * float4(float3(seg.start), 1.0);
    float4 bWorld = uniforms.modelMatrix * float4(float3(seg.end), 1.0);

    float4 aClip = uniforms.projectionMatrix * uniforms.viewMatrix * aWorld;
    float4 bClip = uniforms.projectionMatrix * uniforms.viewMatrix * bWorld;

    float wA = max(aClip.w, 1e-4);
    float wB = max(bClip.w, 1e-4);

    float2 aNdc = aClip.xy / wA;
    float2 bNdc = bClip.xy / wB;

    float2 aScreen = float2((aNdc.x + 1.0) * 0.5 * uniforms.viewportWidth, (aNdc.y + 1.0) * 0.5 * uniforms.viewportHeight);
    float2 bScreen = float2((bNdc.x + 1.0) * 0.5 * uniforms.viewportWidth, (bNdc.y + 1.0) * 0.5 * uniforms.viewportHeight);

    float2 dir = bScreen - aScreen;
    float len = length(dir);
    float2 nScreen = len > 1e-4 ? float2(-dir.y, dir.x) / len : float2(0.0, 1.0);

    float halfWidth = max(uniforms.lineWidth * 0.5, 0.5);

    // Quad vertex indices (2 triangles = 6 vertices):
    // 0: A - N, 1: B - N, 2: A + N
    // 3: A + N, 4: B - N, 5: B + N
    bool isB = (vertexID == 1 || vertexID == 4 || vertexID == 5);
    float signN = (vertexID == 2 || vertexID == 3 || vertexID == 5) ? 1.0 : -1.0;

    float4 baseClip = isB ? bClip : aClip;
    float baseW = isB ? wB : wA;

    float2 offsetScreen = nScreen * (signN * halfWidth);
    float2 offsetNdc = float2(2.0 * offsetScreen.x / max(uniforms.viewportWidth, 1.0),
                              2.0 * offsetScreen.y / max(uniforms.viewportHeight, 1.0));

    float4 pClip = baseClip;
    pClip.xy += offsetNdc * baseW;
    pClip.z -= uniforms.depthBias * baseW;

    out.position = pClip;
    return out;
}

fragment float4 edgeHighlightFragmentShader(
    EdgeHighlightVertexOut in [[stage_in]],
    constant EdgeHighlightUniforms &uniforms [[buffer(2)]]
) {
    return uniforms.color;
}

// MARK: - Antialiased B-Rep Edge Shaders (BL-VPT-04)

struct CadEdgeUniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float4 color;
    float viewportWidth;
    float viewportHeight;
    float lineWidth;
    float depthBias;
    float2 _padding;
};

struct CadEdgeVertexOut {
    float4 position [[position]];
    float edgeDist; // Normalized distance from line center: -1.0 to 1.0
};

vertex CadEdgeVertexOut cadEdgeVertexShader(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant CadEdgeUniforms &uniforms [[buffer(2)]],
    constant EdgeSegmentData *segments [[buffer(3)]]
) {
    CadEdgeVertexOut out;
    EdgeSegmentData seg = segments[instanceID];

    float4 aWorld = uniforms.modelMatrix * float4(float3(seg.start), 1.0);
    float4 bWorld = uniforms.modelMatrix * float4(float3(seg.end), 1.0);

    float4 aClip = uniforms.projectionMatrix * uniforms.viewMatrix * aWorld;
    float4 bClip = uniforms.projectionMatrix * uniforms.viewMatrix * bWorld;

    float wA = max(aClip.w, 1e-4);
    float wB = max(bClip.w, 1e-4);

    float2 aNdc = aClip.xy / wA;
    float2 bNdc = bClip.xy / wB;

    float2 aScreen = float2((aNdc.x + 1.0) * 0.5 * uniforms.viewportWidth, (aNdc.y + 1.0) * 0.5 * uniforms.viewportHeight);
    float2 bScreen = float2((bNdc.x + 1.0) * 0.5 * uniforms.viewportWidth, (bNdc.y + 1.0) * 0.5 * uniforms.viewportHeight);

    float2 dir = bScreen - aScreen;
    float len = length(dir);
    float2 nScreen = len > 1e-4 ? float2(-dir.y, dir.x) / len : float2(0.0, 1.0);

    // Expand ribbon by 0.5px on each side for smooth 1-pixel feathering
    float halfWidth = max(uniforms.lineWidth * 0.5, 0.5) + 0.5;

    bool isB = (vertexID == 1 || vertexID == 4 || vertexID == 5);
    float signN = (vertexID == 2 || vertexID == 3 || vertexID == 5) ? 1.0 : -1.0;

    float4 baseClip = isB ? bClip : aClip;
    float baseW = isB ? wB : wA;

    float2 offsetScreen = nScreen * (signN * halfWidth);
    float2 offsetNdc = float2(2.0 * offsetScreen.x / max(uniforms.viewportWidth, 1.0),
                              2.0 * offsetScreen.y / max(uniforms.viewportHeight, 1.0));

    float4 pClip = baseClip;
    pClip.xy += offsetNdc * baseW;
    pClip.z -= uniforms.depthBias * baseW; // Offset towards camera to eliminate z-fighting with adjacent coplanar faces

    out.position = pClip;
    out.edgeDist = signN;
    return out;
}

fragment float4 cadEdgeFragmentShader(
    CadEdgeVertexOut in [[stage_in]],
    constant CadEdgeUniforms &uniforms [[buffer(2)]]
) {
    float halfWidth = max(uniforms.lineWidth * 0.5, 0.5) + 0.5;
    float dPx = abs(in.edgeDist) * halfWidth;
    // 1-pixel feather at the outer boundary of the line ribbon
    float alpha = saturate(halfWidth - dPx);
    return float4(uniforms.color.rgb, uniforms.color.a * alpha);
}

