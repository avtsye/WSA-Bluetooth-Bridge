#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MAKE_TAG_CONSTANT(A,B,C,D) (((A)<<24)|((B)<<16)|((C)<<8)|(D))
#define HARDWARE_MODULE_TAG MAKE_TAG_CONSTANT('H','W','M','T')
#define HARDWARE_DEVICE_TAG MAKE_TAG_CONSTANT('H','W','D','T')
#define HARDWARE_MAKE_API_VERSION(maj,min) ((((maj)&0xff)<<8)|((min)&0xff))
#define HARDWARE_HAL_API_VERSION HARDWARE_MAKE_API_VERSION(1,0)
#define AUDIO_MODULE_API_VERSION_0_1 HARDWARE_MAKE_API_VERSION(0,1)
#define AUDIO_DEVICE_API_VERSION_3_0 HARDWARE_MAKE_API_VERSION(3,0)
#define AUDIO_HARDWARE_MODULE_ID "audio"
#define AUDIO_HARDWARE_INTERFACE "audio_hw_if"

typedef uint32_t audio_channel_mask_t;
typedef uint32_t audio_format_t;
typedef uint32_t audio_devices_t;
typedef int32_t audio_io_handle_t;
typedef uint32_t audio_output_flags_t;
typedef uint32_t audio_input_flags_t;
typedef int32_t audio_source_t;
typedef int32_t audio_mode_t;
typedef int32_t audio_patch_handle_t;
typedef int32_t audio_port_handle_t;
typedef void* effect_handle_t;

#define AUDIO_FORMAT_PCM_16_BIT 0x1u
#define AUDIO_CHANNEL_OUT_STEREO 0x3u
#define AUDIO_CHANNEL_IN_MONO 0x10u

struct audio_config {
    uint32_t sample_rate;
    audio_channel_mask_t channel_mask;
    audio_format_t format;
    uint8_t opaque[192];
};

struct audio_port_config;
struct audio_port;
struct audio_port_v7;
struct audio_microphone_characteristic_t;
struct audio_mmap_buffer_info;
struct audio_mmap_position;
struct source_metadata;
struct source_metadata_v7;
struct sink_metadata;
struct sink_metadata_v7;

struct hw_module_t;
struct hw_device_t;

struct hw_module_methods_t {
    int (*open)(const struct hw_module_t*, const char*, struct hw_device_t**);
};

typedef struct hw_module_t {
    uint32_t tag;
    uint16_t module_api_version;
    uint16_t hal_api_version;
    const char* id;
    const char* name;
    const char* author;
    struct hw_module_methods_t* methods;
    void* dso;
#ifdef __LP64__
    uint64_t reserved[25];
#else
    uint32_t reserved[25];
#endif
} hw_module_t;

typedef struct hw_device_t {
    uint32_t tag;
    uint32_t version;
    struct hw_module_t* module;
#ifdef __LP64__
    uint64_t reserved[12];
#else
    uint32_t reserved[12];
#endif
    int (*close)(struct hw_device_t*);
} hw_device_t;

typedef int (*stream_callback_t)(int, void*, void*);
typedef int (*stream_event_callback_t)(int, void*, void*);

struct audio_stream {
    uint32_t (*get_sample_rate)(const struct audio_stream*);
    int (*set_sample_rate)(struct audio_stream*, uint32_t);
    size_t (*get_buffer_size)(const struct audio_stream*);
    audio_channel_mask_t (*get_channels)(const struct audio_stream*);
    audio_format_t (*get_format)(const struct audio_stream*);
    int (*set_format)(struct audio_stream*, audio_format_t);
    int (*standby)(struct audio_stream*);
    int (*dump)(const struct audio_stream*, int);
    audio_devices_t (*get_device)(const struct audio_stream*);
    int (*set_device)(struct audio_stream*, audio_devices_t);
    int (*set_parameters)(struct audio_stream*, const char*);
    char* (*get_parameters)(const struct audio_stream*, const char*);
    int (*add_audio_effect)(const struct audio_stream*, effect_handle_t);
    int (*remove_audio_effect)(const struct audio_stream*, effect_handle_t);
};

struct audio_stream_out {
    struct audio_stream common;
    uint32_t (*get_latency)(const struct audio_stream_out*);
    int (*set_volume)(struct audio_stream_out*, float, float);
    ssize_t (*write)(struct audio_stream_out*, const void*, size_t);
    int (*get_render_position)(const struct audio_stream_out*, uint32_t*);
    int (*get_next_write_timestamp)(const struct audio_stream_out*, int64_t*);
    int (*set_callback)(struct audio_stream_out*, stream_callback_t, void*);
    int (*pause)(struct audio_stream_out*);
    int (*resume)(struct audio_stream_out*);
    int (*drain)(struct audio_stream_out*, int);
    int (*flush)(struct audio_stream_out*);
    int (*get_presentation_position)(const struct audio_stream_out*, uint64_t*, struct timespec*);
    void* reserved[16];
};

struct audio_stream_in {
    struct audio_stream common;
    int (*set_gain)(struct audio_stream_in*, float);
    ssize_t (*read)(struct audio_stream_in*, void*, size_t);
    uint32_t (*get_input_frames_lost)(struct audio_stream_in*);
    int (*get_capture_position)(const struct audio_stream_in*, int64_t*, int64_t*);
    void* reserved[12];
};

struct audio_hw_device {
    struct hw_device_t common;
    uint32_t (*get_supported_devices)(const struct audio_hw_device*);
    int (*init_check)(const struct audio_hw_device*);
    int (*set_voice_volume)(struct audio_hw_device*, float);
    int (*set_master_volume)(struct audio_hw_device*, float);
    int (*get_master_volume)(struct audio_hw_device*, float*);
    int (*set_mode)(struct audio_hw_device*, audio_mode_t);
    int (*set_mic_mute)(struct audio_hw_device*, bool);
    int (*get_mic_mute)(const struct audio_hw_device*, bool*);
    int (*set_parameters)(struct audio_hw_device*, const char*);
    char* (*get_parameters)(const struct audio_hw_device*, const char*);
    size_t (*get_input_buffer_size)(const struct audio_hw_device*, const struct audio_config*);
    int (*open_output_stream)(struct audio_hw_device*, audio_io_handle_t, audio_devices_t,
                              audio_output_flags_t, struct audio_config*,
                              struct audio_stream_out**, const char*);
    void (*close_output_stream)(struct audio_hw_device*, struct audio_stream_out*);
    int (*open_input_stream)(struct audio_hw_device*, audio_io_handle_t, audio_devices_t,
                             struct audio_config*, struct audio_stream_in**,
                             audio_input_flags_t, const char*, audio_source_t);
    void (*close_input_stream)(struct audio_hw_device*, struct audio_stream_in*);
    int (*get_microphones)(const struct audio_hw_device*, struct audio_microphone_characteristic_t*, size_t*);
    int (*dump)(const struct audio_hw_device*, int);
    int (*set_master_mute)(struct audio_hw_device*, bool);
    int (*get_master_mute)(struct audio_hw_device*, bool*);
    int (*create_audio_patch)(struct audio_hw_device*, unsigned, const struct audio_port_config*,
                              unsigned, const struct audio_port_config*, audio_patch_handle_t*);
    int (*release_audio_patch)(struct audio_hw_device*, audio_patch_handle_t);
    int (*get_audio_port)(struct audio_hw_device*, struct audio_port*);
    int (*set_audio_port_config)(struct audio_hw_device*, const struct audio_port_config*);
    void* reserved[8];
};

#ifdef __cplusplus
}
#endif
