cbuffer c_per_object : register(b1)
{
    uint __bindless_sampler_raster;
    uint __bindless_sampler_distortion;
    uint __bindless_sampler_variation;
    uint _bindless_padding;

    uint2 __bindless_texture_raster;
    uint2 __bindless_minlod_raster;
    uint2 __bindless_texture_distortion;
    uint2 __bindless_minlod_distortion;
    uint2 __bindless_texture_unused;
    uint2 __bindless_minlod_unused;
    uint2 __bindless_texture_variation_a;
    uint2 __bindless_minlod_variation_a;
    uint2 __bindless_texture_variation_b;
    uint2 __bindless_minlod_variation_b;

    float4x4 _reserved_matrices[3];
    float4 _reserved_wireframe_color;
    float material_variable_01c83489;
    float global_distortion;
    float material_variable_a0cca63e;
    float distortion_brightness;
    float material_variable_fa5882af;
    float raster_intensity;
    float strength;
    float angular_strength;
};

Texture2D<float4> __tex_source : register(t0);
SamplerState __samp_source : register(s0);
Texture2D<float4> global_texture2D[] : register(t0, space2);
SamplerState global_samplers[] : register(s0, space2);
SamplerState static_minlod_sampler : register(s0, space31);

struct PixelInput
{
    float4 position : SV_Position;

    float2 custom0 : CUSTOM0;
    float2 custom2 : CUSTOM2;
    float4 custom1 : CUSTOM1;
    float2 custom3 : CUSTOM3;
    float2 custom4 : CUSTOM4;
    float2 custom5 : CUSTOM5;
    float2 custom6 : CUSTOM6;
    float2 custom7 : CUSTOM7;
};

float4 main(PixelInput input) : SV_Target0
{
    float2 uv = input.custom0.xy;
    float centered_x = uv.x * 2.0 - 1.0;
    float centered_y = uv.y * 2.0 - 1.0;
    float curve_weight = 1.0 - pow(abs(centered_x), angular_strength);
    uv.y += curve_weight * centered_y * strength;

    float4 color = __tex_source.Sample(__samp_source, uv);

    float2 raster_uv = input.custom0 * input.custom2;
    float raster_min_lod = global_texture2D[NonUniformResourceIndex(__bindless_minlod_raster.x)]
        .Sample(static_minlod_sampler, raster_uv).r * 32.0;
    float raster = global_texture2D[NonUniformResourceIndex(__bindless_texture_raster.x)]
        .Sample(global_samplers[__bindless_sampler_raster], raster_uv, int2(0, 0), raster_min_lod).r;
    float raster_factor = saturate(raster + raster_intensity);

    float variation_a_min_lod = global_texture2D[NonUniformResourceIndex(__bindless_minlod_variation_a.x)]
        .Sample(static_minlod_sampler, input.custom6).r * 32.0;
    float variation_a = global_texture2D[NonUniformResourceIndex(__bindless_texture_variation_a.x)]
        .Sample(global_samplers[__bindless_sampler_variation], input.custom6, int2(0, 0), variation_a_min_lod).r;
    float variation_b_min_lod = global_texture2D[NonUniformResourceIndex(__bindless_minlod_variation_b.x)]
        .Sample(static_minlod_sampler, input.custom7).r * 32.0;
    float variation_b = global_texture2D[NonUniformResourceIndex(__bindless_texture_variation_b.x)]
        .Sample(global_samplers[__bindless_sampler_variation], input.custom7, int2(0, 0), variation_b_min_lod).r;
    float variation_factor = 1.0 - abs(variation_b - variation_a) * material_variable_a0cca63e;

    color.rgb *= input.custom1.rgb * raster_factor * variation_factor;

    return color;
}
