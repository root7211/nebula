/*
 * headless_test.c
 * 无头离屏渲染验证程序
 * 直接用 wgpu-native C API 渲染圆角矩形到离屏纹理，
 * 读回像素并保存为 PPM 图像，验证 Uniform 布局和 WGSL 着色器是否正确。
 *
 * Phase 2.2: 结构体和着色器源码从 fixture_shader.h 导入，
 *            该头文件由 tools/export_shader_fixture.nelua 在编译期自动生成。
 *
 * Phase 2.3.4: 改用 ButtonUniforms 紧凑 std140 布局（80 字节）。
 *              添加 static_assert 验证所有关键字段偏移量。
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>   /* offsetof */
#include <assert.h>   /* static_assert */
#include "webgpu/webgpu.h"
#include "webgpu/wgpu.h"
#include "fixture_shader.h"

#define WIDTH  800
#define HEIGHT 600

/* ── Phase 2.3.4: 编译期布局断言 ── */
static_assert(sizeof(ButtonUniforms) == NEBULA_BUTTON_UNIFORMS_SIZE,
    "ButtonUniforms size mismatch: expected 80 bytes (compact std140)");
static_assert(offsetof(ButtonUniforms, pos)          == NEBULA_OFFSET_POS,
    "ButtonUniforms.pos offset mismatch");
static_assert(offsetof(ButtonUniforms, size)         == NEBULA_OFFSET_SIZE,
    "ButtonUniforms.size offset mismatch");
static_assert(offsetof(ButtonUniforms, radius)       == NEBULA_OFFSET_RADIUS,
    "ButtonUniforms.radius offset mismatch");
static_assert(offsetof(ButtonUniforms, bg_color)     == NEBULA_OFFSET_BG_COLOR,
    "ButtonUniforms.bg_color offset mismatch");
static_assert(offsetof(ButtonUniforms, border_color) == NEBULA_OFFSET_BORDER_COLOR,
    "ButtonUniforms.border_color offset mismatch");
static_assert(offsetof(ButtonUniforms, border_width) == NEBULA_OFFSET_BORDER_WIDTH,
    "ButtonUniforms.border_width offset mismatch");
static_assert(offsetof(ButtonUniforms, viewport)     == NEBULA_OFFSET_VIEWPORT,
    "ButtonUniforms.viewport offset mismatch");

/* ── 全局回调结果 ── */
static WGPUAdapter  g_adapter = NULL;
static WGPUDevice   g_device  = NULL;
static int          g_mapped  = 0;
static int          g_work_done = 0;

static void on_work_done(WGPUQueueWorkDoneStatus status, void* ud1, void* ud2) {
    if (status == WGPUQueueWorkDoneStatus_Success) g_work_done = 1;
    else fprintf(stderr, "work done failed: %d\n", status);
}

static void on_adapter(WGPURequestAdapterStatus status, WGPUAdapter adapter,
                        WGPUStringView msg, void* ud1, void* ud2) {
    if (status == WGPURequestAdapterStatus_Success) g_adapter = adapter;
    else fprintf(stderr, "adapter failed\n");
}

static void on_device(WGPURequestDeviceStatus status, WGPUDevice device,
                       WGPUStringView msg, void* ud1, void* ud2) {
    if (status == WGPURequestDeviceStatus_Success) g_device = device;
    else fprintf(stderr, "device failed\n");
}

static void on_map(WGPUMapAsyncStatus status, WGPUStringView msg,
                   void* ud1, void* ud2) {
    if (status == WGPUMapAsyncStatus_Success) g_mapped = 1;
    else fprintf(stderr, "map failed: %d\n", status);
}

/* ── WGSL 着色器（Phase 2.3.4: 从 fixture_shader.h 导入，80B 紧凑布局） ── */
#define WGSL FIXTURE_WGSL

/* ── 保存 PPM ── */
static void save_ppm(const char* path, const uint8_t* data,
                     uint32_t w, uint32_t h, uint32_t bytes_per_row) {
    FILE* f = fopen(path, "wb");
    if (!f) { perror("fopen"); return; }
    fprintf(f, "P6\n%u %u\n255\n", w, h);
    for (uint32_t y = 0; y < h; y++) {
        const uint8_t* row = data + y * bytes_per_row;
        for (uint32_t x = 0; x < w; x++) {
            /* BGRA8 → RGB */
            uint8_t b = row[x*4+0];
            uint8_t g = row[x*4+1];
            uint8_t r = row[x*4+2];
            fputc(r, f); fputc(g, f); fputc(b, f);
        }
    }
    fclose(f);
    printf("saved: %s (%ux%u)\n", path, w, h);
}

int main(void) {
    /* Phase 2.3.4: 验证 80B 紧凑布局 */
    printf("sizeof(ButtonUniforms) = %zu (expected %d)\n",
           sizeof(ButtonUniforms), NEBULA_BUTTON_UNIFORMS_SIZE);
    printf("offset pos          = %zu (expected %d)\n",
           offsetof(ButtonUniforms, pos),          NEBULA_OFFSET_POS);
    printf("offset size         = %zu (expected %d)\n",
           offsetof(ButtonUniforms, size),         NEBULA_OFFSET_SIZE);
    printf("offset radius       = %zu (expected %d)\n",
           offsetof(ButtonUniforms, radius),       NEBULA_OFFSET_RADIUS);
    printf("offset bg_color     = %zu (expected %d)\n",
           offsetof(ButtonUniforms, bg_color),     NEBULA_OFFSET_BG_COLOR);
    printf("offset border_color = %zu (expected %d)\n",
           offsetof(ButtonUniforms, border_color), NEBULA_OFFSET_BORDER_COLOR);
    printf("offset border_width = %zu (expected %d)\n",
           offsetof(ButtonUniforms, border_width), NEBULA_OFFSET_BORDER_WIDTH);
    printf("offset viewport     = %zu (expected %d)\n",
           offsetof(ButtonUniforms, viewport),     NEBULA_OFFSET_VIEWPORT);

    /* ── 1. Instance ── */
    WGPUInstanceDescriptor inst_desc = {0};
    WGPUInstance instance = wgpuCreateInstance(&inst_desc);
    if (!instance) { fprintf(stderr, "no instance\n"); return 1; }

    /* ── 2. Adapter（无 Surface，headless） ── */
    WGPURequestAdapterOptions adapter_opts = {
        .nextInChain        = NULL,
        .compatibleSurface  = NULL,
        .powerPreference    = WGPUPowerPreference_Undefined,
        .backendType        = WGPUBackendType_Undefined,
        .forceFallbackAdapter = 0,
    };
    WGPURequestAdapterCallbackInfo adapter_cb = {
        .nextInChain = NULL,
        .mode        = WGPUCallbackMode_AllowSpontaneous,
        .callback    = on_adapter,
        .userdata1   = NULL,
        .userdata2   = NULL,
    };
    wgpuInstanceRequestAdapter(instance, &adapter_opts, adapter_cb);
    if (!g_adapter) { fprintf(stderr, "no adapter\n"); return 1; }
    printf("adapter OK\n");

    /* ── 3. Device ── */
    WGPUDeviceDescriptor dev_desc = {
        .nextInChain = NULL,
        .label       = {.data = "nebula-headless", .length = 15},
        .deviceLostCallbackInfo = {
            .mode = WGPUCallbackMode_AllowSpontaneous,
        },
        .uncapturedErrorCallbackInfo = {0},
    };
    WGPURequestDeviceCallbackInfo device_cb = {
        .nextInChain = NULL,
        .mode        = WGPUCallbackMode_AllowSpontaneous,
        .callback    = on_device,
        .userdata1   = NULL,
        .userdata2   = NULL,
    };
    wgpuAdapterRequestDevice(g_adapter, &dev_desc, device_cb);
    if (!g_device) { fprintf(stderr, "no device\n"); return 1; }
    WGPUQueue queue = wgpuDeviceGetQueue(g_device);
    printf("device OK\n");

    /* ── 4. 离屏渲染纹理（RenderAttachment + CopySrc） ── */
    WGPUTextureDescriptor tex_desc = {
        .nextInChain = NULL,
        .label       = {.data = "offscreen", .length = 9},
        .usage       = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_CopySrc,
        .dimension   = WGPUTextureDimension_2D,
        .size        = {WIDTH, HEIGHT, 1},
        .format      = WGPUTextureFormat_BGRA8Unorm,
        .mipLevelCount = 1,
        .sampleCount   = 1,
        .viewFormatCount = 0,
        .viewFormats     = NULL,
    };
    WGPUTexture offscreen_tex = wgpuDeviceCreateTexture(g_device, &tex_desc);
    WGPUTextureViewDescriptor view_desc = {
        .nextInChain     = NULL,
        .format          = WGPUTextureFormat_BGRA8Unorm,
        .dimension       = WGPUTextureViewDimension_2D,
        .baseMipLevel    = 0,
        .mipLevelCount   = 1,
        .baseArrayLayer  = 0,
        .arrayLayerCount = 1,
        .aspect          = WGPUTextureAspect_All,
        .usage           = 0,
    };
    WGPUTextureView offscreen_view = wgpuTextureCreateView(offscreen_tex, &view_desc);
    printf("offscreen texture OK\n");

    /* ── 5. Uniform Buffer（Phase 2.3.4: 使用 ButtonUniforms，80 字节） ── */
    WGPUBufferDescriptor ubuf_desc = {
        .nextInChain      = NULL,
        .label            = {.data = "uniforms", .length = 8},
        .usage            = WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst,
        .size             = sizeof(ButtonUniforms),
        .mappedAtCreation = 0,
    };
    WGPUBuffer uniform_buf = wgpuDeviceCreateBuffer(g_device, &ubuf_desc);

    /* 填充 Uniform 数据（default 状态：深灰按钮，蓝色边框） */
    ButtonUniforms u = {0};
    u.pos          = (Vec2){300.0f, 250.0f};
    u.size         = (Vec2){200.0f, 60.0f};
    u.radius       = 12.0f;
    u.bg_color     = (Color){0.22f, 0.22f, 0.24f, 1.0f};
    u.border_color = (Color){0.4f,  0.6f,  1.0f,  1.0f};
    u.border_width = 2.0f;
    u.viewport     = (Vec2){(float)WIDTH, (float)HEIGHT};
    wgpuQueueWriteBuffer(queue, uniform_buf, 0, &u, sizeof(u));

    /* ── 6. BindGroupLayout ── */
    WGPUBindGroupLayoutEntry bgl_entry = {
        .nextInChain = NULL,
        .binding     = 0,
        .visibility  = WGPUShaderStage_Vertex | WGPUShaderStage_Fragment,
        .buffer      = {
            .type            = WGPUBufferBindingType_Uniform,
            .hasDynamicOffset = 0,
            .minBindingSize  = sizeof(ButtonUniforms),
        },
    };
    WGPUBindGroupLayoutDescriptor bgl_desc = {
        .nextInChain = NULL,
        .label       = {.data = "bgl", .length = 3},
        .entryCount  = 1,
        .entries     = &bgl_entry,
    };
    WGPUBindGroupLayout bgl = wgpuDeviceCreateBindGroupLayout(g_device, &bgl_desc);

    WGPUBindGroupEntry bg_entry = {
        .binding     = 0,
        .buffer      = uniform_buf,
        .offset      = 0,
        .size        = sizeof(ButtonUniforms),
    };
    WGPUBindGroupDescriptor bg_desc = {
        .nextInChain = NULL,
        .label       = {.data = "bg", .length = 2},
        .layout      = bgl,
        .entryCount  = 1,
        .entries     = &bg_entry,
    };
    WGPUBindGroup bind_group = wgpuDeviceCreateBindGroup(g_device, &bg_desc);

    /* ── 7. Shader ── */
    WGPUShaderSourceWGSL wgsl_src = {
        .chain = {.sType = WGPUSType_ShaderSourceWGSL},
        .code  = {.data = WGSL, .length = strlen(WGSL)},
    };
    WGPUShaderModuleDescriptor shader_desc = {
        .nextInChain = (WGPUChainedStruct*)&wgsl_src,
        .label       = {.data = "shader", .length = 6},
    };
    WGPUShaderModule shader = wgpuDeviceCreateShaderModule(g_device, &shader_desc);
    printf("shader compiled OK\n");

    /* ── 8. Pipeline ── */
    WGPUPipelineLayoutDescriptor pl_desc = {
        .nextInChain          = NULL,
        .label                = {.data = "pl", .length = 2},
        .bindGroupLayoutCount = 1,
        .bindGroupLayouts     = &bgl,
    };
    WGPUPipelineLayout pipeline_layout = wgpuDeviceCreatePipelineLayout(g_device, &pl_desc);

    WGPUBlendState blend = {
        .color = {WGPUBlendOperation_Add, WGPUBlendFactor_SrcAlpha, WGPUBlendFactor_OneMinusSrcAlpha},
        .alpha = {WGPUBlendOperation_Add, WGPUBlendFactor_One,      WGPUBlendFactor_OneMinusSrcAlpha},
    };
    WGPUColorTargetState color_target = {
        .format    = WGPUTextureFormat_BGRA8Unorm,
        .blend     = &blend,
        .writeMask = WGPUColorWriteMask_All,
    };
    WGPUFragmentState frag = {
        .module      = shader,
        .entryPoint  = {.data = "fs_main", .length = 7},
        .targetCount = 1,
        .targets     = &color_target,
    };
    WGPURenderPipelineDescriptor rp_desc = {
        .nextInChain = NULL,
        .label       = {.data = "pipeline", .length = 8},
        .layout      = pipeline_layout,
        .vertex      = {
            .module     = shader,
            .entryPoint = {.data = "vs_main", .length = 7},
        },
        .primitive   = {.topology = WGPUPrimitiveTopology_TriangleList},
        .multisample = {.count = 1, .mask = 0xFFFFFFFF},
        .fragment    = &frag,
    };
    WGPURenderPipeline pipeline = wgpuDeviceCreateRenderPipeline(g_device, &rp_desc);
    printf("pipeline OK\n");

    /* ── 9. 渲染一帧 ── */
    WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(g_device, NULL);

    WGPURenderPassColorAttachment color_att = {
        .view         = offscreen_view,
        .depthSlice   = WGPU_DEPTH_SLICE_UNDEFINED,
        .loadOp       = WGPULoadOp_Clear,
        .storeOp      = WGPUStoreOp_Store,
        .clearValue   = {0.12, 0.12, 0.13, 1.0},
    };
    WGPURenderPassDescriptor pass_desc = {
        .colorAttachmentCount = 1,
        .colorAttachments     = &color_att,
    };
    WGPURenderPassEncoder pass = wgpuCommandEncoderBeginRenderPass(encoder, &pass_desc);
    wgpuRenderPassEncoderSetPipeline(pass, pipeline);
    wgpuRenderPassEncoderSetBindGroup(pass, 0, bind_group, 0, NULL);
    wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0);
    wgpuRenderPassEncoderEnd(pass);
    wgpuRenderPassEncoderRelease(pass);

    /* ── 10. 纹理 → 读回 Buffer ── */
    uint32_t bytes_per_row = WIDTH * 4;
    /* bytes_per_row 必须是 256 的倍数 */
    bytes_per_row = (bytes_per_row + 255) & ~255u;
    uint64_t readback_size = (uint64_t)bytes_per_row * HEIGHT;

    WGPUBufferDescriptor rb_desc = {
        .label            = {.data = "readback", .length = 8},
        .usage            = WGPUBufferUsage_CopyDst | WGPUBufferUsage_MapRead,
        .size             = readback_size,
        .mappedAtCreation = 0,
    };
    WGPUBuffer readback_buf = wgpuDeviceCreateBuffer(g_device, &rb_desc);

    WGPUTexelCopyTextureInfo src = {
        .texture  = offscreen_tex,
        .mipLevel = 0,
        .origin   = {0, 0, 0},
        .aspect   = WGPUTextureAspect_All,
    };
    WGPUTexelCopyBufferInfo dst = {
        .layout = {.offset = 0, .bytesPerRow = bytes_per_row, .rowsPerImage = HEIGHT},
        .buffer = readback_buf,
    };
    WGPUExtent3D copy_size = {WIDTH, HEIGHT, 1};
    wgpuCommandEncoderCopyTextureToBuffer(encoder, &src, &dst, &copy_size);

    WGPUCommandBuffer cmd = wgpuCommandEncoderFinish(encoder, NULL);
    wgpuCommandEncoderRelease(encoder);
    wgpuQueueSubmit(queue, 1, &cmd);
    wgpuCommandBufferRelease(cmd);
    printf("render submitted\n");

    /* ── 11. 用 wgpuDevicePoll 刷新并等待 GPU 完成 ── */
    wgpuDevicePoll(g_device, 1, NULL);
    printf("GPU work done\n");

    /* ── 12. Map 读回 Buffer ── */
    WGPUBufferMapCallbackInfo map_cb = {
        .mode      = WGPUCallbackMode_AllowSpontaneous,
        .callback  = on_map,
        .userdata1 = NULL,
        .userdata2 = NULL,
    };
    wgpuBufferMapAsync(readback_buf, WGPUMapMode_Read, 0, readback_size, map_cb);
    wgpuDevicePoll(g_device, 0, NULL);
    if (!g_mapped) {
        int timeout = 200;
        while (!g_mapped && timeout-- > 0) {
            wgpuDevicePoll(g_device, 0, NULL);
        }
    }
    if (!g_mapped) { fprintf(stderr, "map timeout\n"); return 1; }

    const uint8_t* pixels = wgpuBufferGetMappedRange(readback_buf, 0, readback_size);

    /* 验证：中心像素应该是按钮背景色（深灰 ~0.22）
     * Phase 2.3.4: 使用 ButtonUniforms 80B 布局，渲染结果应与 Phase 2.2 完全一致 */
    uint32_t cx = WIDTH/2, cy = HEIGHT/2;
    const uint8_t* center = pixels + cy * bytes_per_row + cx * 4;
    printf("center pixel BGRA: %d %d %d %d\n", center[0], center[1], center[2], center[3]);
    printf("expected ~(56, 56, 61, 255) for bg_color(0.22, 0.22, 0.24, 1.0)\n");

    /* 验证：背景区域（左上角）应该是清除色（深灰 ~0.12） */
    const uint8_t* bg = pixels + 10 * bytes_per_row + 10 * 4;
    printf("background pixel BGRA: %d %d %d %d\n", bg[0], bg[1], bg[2], bg[3]);
    printf("expected ~(33, 33, 31, 255) for clearColor(0.12, 0.12, 0.13, 1.0)\n");

    /* 保存 PPM */
    save_ppm("/tmp/nebula_render_2_3_4.ppm", pixels, WIDTH, HEIGHT, bytes_per_row);

    wgpuBufferUnmap(readback_buf);

    /* ── 清理 ── */
    wgpuBufferRelease(readback_buf);
    wgpuRenderPipelineRelease(pipeline);
    wgpuShaderModuleRelease(shader);
    wgpuBindGroupRelease(bind_group);
    wgpuBindGroupLayoutRelease(bgl);
    wgpuBufferRelease(uniform_buf);
    wgpuTextureViewRelease(offscreen_view);
    wgpuTextureRelease(offscreen_tex);
    wgpuDeviceRelease(g_device);
    wgpuAdapterRelease(g_adapter);
    wgpuInstanceRelease(instance);

    printf("headless test PASSED (Phase 2.3.4: ButtonUniforms 80B compact layout)\n");
    return 0;
}
